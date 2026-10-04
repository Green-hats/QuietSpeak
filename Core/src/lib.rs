mod audio;
mod chat;

use anyhow::{anyhow, Context, Result};
use chat::{ChatDelivery, PendingChat};
use futures::StreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{CStr, CString},
    os::raw::c_char,
    sync::{atomic::Ordering, Mutex, OnceLock},
    time::{Duration, Instant},
};
use tokio::sync::mpsc;
use tsclientlib::{
    prelude::*, ChannelId, ClientId, Codec, Connection, DisconnectOptions, Identity, MessageTarget,
    StreamItem,
};
use tsproto_packets::packets::AudioData;

static EVENTS: OnceLock<Mutex<VecDeque<Value>>> = OnceLock::new();
static COMMANDS: OnceLock<mpsc::UnboundedSender<Command>> = OnceLock::new();

pub(crate) fn emit(event: Value) {
    let queue = EVENTS.get_or_init(|| Mutex::new(VecDeque::new()));
    if let Ok(mut q) = queue.lock() {
        // A blocked UI must not cause unbounded growth. Coalesce superseded snapshots.
        if event["type"] == "snapshot" {
            q.retain(|e| e["type"] != "snapshot");
        }
        if q.len() >= 512 {
            q.pop_front();
        }
        q.push_back(event);
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum Command {
    Connect {
        address: String,
        nickname: String,
        #[serde(default)]
        password: String,
        identity: Option<String>,
    },
    Disconnect,
    Join {
        channel: u64,
        #[serde(default)]
        password: String,
    },
    Chat {
        text: String,
    },
    Audio {
        microphone: bool,
        deafened: bool,
        #[serde(default = "one")]
        volume: f32,
    },
    TestOutput {
        #[serde(default = "one")]
        volume: f32,
    },
}
fn one() -> f32 {
    1.0
}

#[no_mangle]
pub extern "C" fn qs_initialize() {
    COMMANDS.get_or_init(|| {
        let (tx, mut rx) = mpsc::unbounded_channel();
        std::thread::Builder::new()
            .name("QuietSpeak protocol".into())
            .spawn(move || {
                let runtime = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(r) => r,
                    Err(e) => {
                        emit(json!({"type":"fatal","message":e.to_string()}));
                        return;
                    }
                };
                runtime.block_on(async {
                    while let Some(command) = rx.recv().await {
                        if let Command::Connect {
                            address,
                            nickname,
                            password,
                            identity,
                        } = command
                        {
                            if let Err(e) =
                                session(address, nickname, password, identity, &mut rx).await
                            {
                                emit(json!({"type":"error", "message":format!("{e:#}")}));
                            }
                            emit(json!({"type":"disconnected"}));
                        } else if let Command::TestOutput { volume } = command {
                            audio::test_output_offline(volume);
                        }
                    }
                });
            })
            .expect("Cannot create protocol thread");
        tx
    });
}

/// The caller owns the UTF-8 C string and keeps it alive for this call only.
///
/// # Safety
/// A non-null pointer must refer to a readable, NUL-terminated string for the
/// duration of this call. The input is borrowed and is never freed by Rust.
#[no_mangle]
pub unsafe extern "C" fn qs_command(command: *const c_char) {
    if command.is_null() {
        return;
    }
    qs_initialize();
    let command = match CStr::from_ptr(command)
        .to_str()
        .ok()
        .and_then(|s| serde_json::from_str::<Command>(s).ok())
    {
        Some(c) => c,
        None => {
            emit(json!({"type":"error","message":"无效的客户端命令"}));
            return;
        }
    };
    if let Some(tx) = COMMANDS.get() {
        let _ = tx.send(command);
    }
}

/// Returns an owned JSON array. Always release it using qs_free_string.
#[no_mangle]
pub extern "C" fn qs_poll() -> *mut c_char {
    let queue = EVENTS.get_or_init(|| Mutex::new(VecDeque::new()));
    let items: Vec<_> = queue
        .lock()
        .map(|mut q| q.drain(..).collect())
        .unwrap_or_default();
    CString::new(serde_json::to_string(&items).unwrap_or_else(|_| "[]".into()))
        .unwrap()
        .into_raw()
}
#[no_mangle]
/// Release an owned string returned by `qs_poll`.
///
/// # Safety
/// A non-null pointer must have been returned by `qs_poll` and must not have
/// been freed previously. The caller must stop using the string after this call.
pub unsafe extern "C" fn qs_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

async fn session(
    address: String,
    nickname: String,
    password: String,
    saved: Option<String>,
    rx: &mut mpsc::UnboundedReceiver<Command>,
) -> Result<()> {
    let identity = match saved {
        Some(s) if !s.is_empty() => {
            serde_json::from_str::<Identity>(&s).context("保存的身份无法读取，请检查钥匙串")?
        }
        _ => Identity::create(),
    };
    emit(json!({"type":"identity", "value":serde_json::to_string(&identity)?}));
    let mut con = Connection::build(address)
        .name(nickname.clone())
        .password(password)
        .identity(identity)
        .input_muted(true)
        .output_muted(false)
        .connect()?;
    let (audio_tx, mut audio_rx) = mpsc::channel(5);
    let mut audio = audio::Audio::new(audio_tx);
    let mut connected = false;
    let mut subscribing = false;
    let mut connecting_since = Instant::now();
    let mut requested_mic = false;
    let mut deafened = false;
    let mut chat_delivery = ChatDelivery::default();
    let mut speakers: HashMap<ClientId, Instant> = HashMap::new();
    let mut heartbeat = tokio::time::interval(Duration::from_millis(250));
    loop {
        tokio::select! {
            cmd = rx.recv() => {
                let Some(cmd) = cmd else { break; };
                match cmd {
                    Command::Disconnect => break,
                    Command::Connect{..} => emit(json!({"type":"error","message":"请先断开当前连接"})),
                    Command::TestOutput{volume} => {
                        if let Err(e) = audio.test_output(volume) {
                            emit(json!({"type":"audioError","message":format!("无法测试扬声器：{e:#}")}));
                        }
                    },
                    Command::Join{channel,password} => {
                        let result: Result<()> = (|| {
                            let s = con.get_state()?;
                            let own = s.clients.get(&s.own_client).context("尚未连接")?;
                            own.client_move(ChannelId(channel)).set_password(&password).send_with_result(&mut con)?;
                            Ok(())
                        })();
                        if let Err(e) = result { emit(json!({"type":"error","message":e.to_string()})); }
                    },
                    Command::Chat{text} => {
                        let result: Result<()> = (|| {
                            if text.trim().is_empty() || text.len()>1024 { return Err(anyhow!("消息需要在 1–1024 字节以内")); }
                            let s = con.get_state()?;
                            let own = s.clients.get(&s.own_client).context("尚未连接")?;
                            let chat = PendingChat{text:text.clone(),channel:own.channel.0,nickname:own.name.clone(),own:own.id.0};
                            let handle = s.send_message(MessageTarget::Channel,&text).send_with_result(&mut con)?;
                            chat_delivery.track(handle,chat);
                            Ok(())
                        })();
                        if let Err(e) = result { emit(json!({"type":"error","message":e.to_string()})); }
                    },
                    Command::Audio{microphone, deafened:new_deaf, volume} => {
                        audio.volume.store(volume.clamp(0.0,1.5).to_bits(),Ordering::Relaxed);
                        deafened = new_deaf;
                        if deafened {audio.reset();}
                        let opus = con.get_state().ok().and_then(|s| s.clients.get(&s.own_client)
                            .and_then(|c| s.channels.get(&c.channel))).map(|c|matches!(c.codec,Codec::OpusVoice|Codec::OpusMusic)).unwrap_or(false);
                        requested_mic = microphone && !deafened;
                        if requested_mic && !opus {
                            requested_mic = false;
                            emit(json!({"type":"audioError","capture":true,"message":"当前频道使用旧版编码，第一版仅支持 Opus 语音频道"}));
                        }
                        // Close capture and empty queued frames before publishing muted state.
                        if let Err(e) = audio.set_capture(requested_mic) {
                            requested_mic = false;
                            let _ = audio.set_capture(false);
                            emit(json!({"type":"audioError","capture":true,"message":format!("无法开启麦克风：{e:#}")}));
                        }
                        while audio_rx.try_recv().is_ok() {}
                        if connected {
                            if let Ok(state) = con.get_state() {
                                if let Err(e) = state.client_update().set_input_muted(!requested_mic)
                                    .set_output_muted(deafened).send_with_result(&mut con) {
                                    emit(json!({"type":"error","message":e.to_string()}));
                                }
                            }
                        }
                        emit(json!({"type":"audioState","microphone":requested_mic,"deafened":deafened}));
                    },
                }
            },
            packet = audio_rx.recv() => {
                if let Some(packet) = packet {
                    if requested_mic && !deafened && connected && con.can_send_audio() {
                        if let Err(e) = con.send_audio(packet) {emit(json!({"type":"audioError","message":e.to_string()}));}
                    }
                }
            },
            event = async { con.events().next().await } => {
                let Some(event) = event else {break;};
                match event? {
                    StreamItem::BookEvents(events) => {
                        if !connected && con.get_state().is_ok() {
                            connected = true;
                            emit(json!({"type":"connected"}));
                            if let Err(e) = audio.start_playback() {emit(json!({"type":"audioError","message":format!("无法播放语音：{e:#}")}));}
                        }
                        if connected && !subscribing {
                            subscribing = true;
                            con.get_state()?.server.set_subscribed(true).send_with_result(&mut con)?;
                        }
                        for event in events {
                            let channel = con.get_state().ok().and_then(|s|s.clients.get(&s.own_client)).map(|c|c.channel.0).unwrap_or(0);
                            let own = con.get_state().ok().map(|s|s.own_client);
                            if let Some(message) = chat::notification(event,own,channel) {emit(message);}
                        }
                        publish_snapshot(&con,&audio);
                    },
                    StreamItem::Audio(packet) => {
                        let from = match packet.data().data() {AudioData::S2C{from,..}|AudioData::S2CWhisper{from,..}=>ClientId(*from),_=>continue};
                        if !deafened && con.can_receive_audio() {
                            if speakers.get(&from).map(|t| t.elapsed()>Duration::from_millis(150)).unwrap_or(true) {
                                emit(json!({"type":"speaking","client":from.0}));
                                speakers.insert(from,Instant::now());
                            }
                            if let Err(e) = audio.receive(from,packet) {emit(json!({"type":"audioError","message":format!("音频解码失败：{e}")}));}
                        }
                    },
                    StreamItem::IdentityLevelIncreasing(level) => emit(json!({"type":"status","message":format!("正在提升身份安全等级至 {level}…")})),
                    StreamItem::IdentityLevelIncreased => {
                        if let Some(id)=con.get_options().get_identity() {emit(json!({"type":"identity","value":serde_json::to_string(id)?}));}
                    },
                    StreamItem::DisconnectedTemporarily(_) => {
                        connected = false;
                        subscribing = false;
                        connecting_since = Instant::now();
                        requested_mic = false;
                        audio.set_capture(false)?;
                        audio.reset();
                        chat_delivery.clear();
                        emit(json!({"type":"reconnecting"}));
                    },
                    StreamItem::MessageResult(handle,result) => {
                        if let Some(message) = chat_delivery.complete(handle,result.is_ok()) {emit(message);}
                        if let Err(e) = result {emit(json!({"type":"error","message":format!("服务器拒绝操作：{e}")}));}
                    },
                    StreamItem::AudioChange(_) => {
                        if !con.can_receive_audio() {audio.reset();}
                        emit(json!({"type":"talkPermission","allowed":con.can_send_audio()}));
                    },
                    _ => {},
                }
            },
            _ = heartbeat.tick() => {
                if !connected && connecting_since.elapsed()>Duration::from_secs(30) {return Err(anyhow!("连接超时，请检查地址、UDP 端口和服务器状态"));}
            },
        }
    }
    audio.set_capture(false)?;
    audio.reset();
    if con.disconnect(DisconnectOptions::new()).is_ok() {
        let _ = tokio::time::timeout(Duration::from_secs(2), async {
            while con.events().next().await.is_some() {}
        })
        .await;
    }
    Ok(())
}

fn publish_snapshot(con: &Connection, audio: &audio::Audio) {
    emit(json!({"type":"talkPermission","allowed":con.can_send_audio()}));
    if let Ok(s) = con.get_state() {
        let current = s
            .clients
            .get(&s.own_client)
            .map(|c| c.channel.0)
            .unwrap_or(0);
        if let Some(channel) = s.channels.get(&ChannelId(current)) {
            audio.codec.store(
                if channel.codec == Codec::OpusMusic {
                    1
                } else {
                    0
                },
                Ordering::Relaxed,
            );
        }
        let channels:Vec<_> = s.channels.values().map(|c|json!({"id":c.id.0,"parent":c.parent.0,"order":c.order.0,"name":c.name,"topic":c.topic,"locked":c.has_password.unwrap_or(false),"codec":format!("{:?}",c.codec)})).collect();
        let clients:Vec<_> = s.clients.values().map(|c|json!({"id":c.id.0,"channel":c.channel.0,"name":c.name,"muted":c.input_muted,"deafened":c.output_muted})).collect();
        emit(
            json!({"type":"snapshot","server":s.server.name,"welcome":s.server.welcome_message,"own":s.own_client.0,"currentChannel":current,"channels":channels,"clients":clients}),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identity_roundtrip_keeps_security_level_and_key() {
        let id = Identity::create();
        let restored: Identity =
            serde_json::from_str(&serde_json::to_string(&id).unwrap()).unwrap();
        assert_eq!(restored.key().to_pub(), id.key().to_pub());
        assert_eq!(restored.level(), id.level());
    }
    #[test]
    fn command_utf8_validation_and_event_ownership() {
        assert!(serde_json::from_str::<Command>(
            r#"{"op":"audio","microphone":false,"deafened":true}"#
        )
        .is_ok());
        emit(json!({"type":"test","text":"你好"}));
        let p = qs_poll();
        let text = unsafe { CStr::from_ptr(p).to_str().unwrap().to_owned() };
        assert!(text.contains("你好"));
        unsafe { qs_free_string(p) };
    }
}
