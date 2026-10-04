use anyhow::{anyhow, Context, Result};
use audiopus::coder::Encoder;
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    SampleFormat, Stream,
};
use std::sync::{
    atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering},
    Arc, Mutex,
};
use tokio::sync::mpsc;
use tsclientlib::{
    audio::{AudioHandler, Error as QueueError},
    ClientId,
};
use tsproto_packets::packets::{AudioData, CodecType, Direction, InAudioBuf, OutAudio, OutPacket};

pub const FRAME: usize = 960;
const TEST_TONE_SAMPLES: u32 = 48000 * 4 / 5;

pub struct Audio {
    playback: Option<Stream>,
    capture: Option<Stream>,
    pub gate: Arc<AtomicBool>,
    pub volume: Arc<AtomicU32>,
    pub codec: Arc<AtomicU8>,
    tone: Arc<AtomicU32>,
    handler: Arc<Mutex<AudioHandler<ClientId>>>,
    sender: mpsc::Sender<OutPacket>,
}

impl Audio {
    pub fn new(sender: mpsc::Sender<OutPacket>) -> Self {
        Self {
            playback: None,
            capture: None,
            gate: Arc::new(AtomicBool::new(false)),
            volume: Arc::new(AtomicU32::new(1f32.to_bits())),
            codec: Arc::new(AtomicU8::new(0)),
            tone: Arc::new(AtomicU32::new(0)),
            handler: Arc::new(Mutex::new(AudioHandler::new())),
            sender,
        }
    }
    pub fn start_playback(&mut self) -> Result<()> {
        if self.playback.is_some() {
            return Ok(());
        }
        let device = cpal::default_host()
            .default_output_device()
            .context("没有可用的输出设备")?;
        let config = device.default_output_config()?;
        let channels = config.channels() as usize;
        let rate = config.sample_rate();
        let handler = self.handler.clone();
        let volume = self.volume.clone();
        let mut render = Renderer::new(handler, volume, self.tone.clone(), channels, rate);
        let err = |e| {
            crate::emit(
                serde_json::json!({"type":"audioError", "message": format!("输出设备错误：{e}")}),
            )
        };
        let stream = match config.sample_format() {
            SampleFormat::F32 => device.build_output_stream(
                config.config(),
                move |data: &mut [f32], _| render.fill(data),
                err,
                None,
            )?,
            SampleFormat::I16 => device.build_output_stream(
                config.config(),
                move |data: &mut [i16], _| render.fill(data),
                err,
                None,
            )?,
            SampleFormat::U16 => device.build_output_stream(
                config.config(),
                move |data: &mut [u16], _| render.fill(data),
                err,
                None,
            )?,
            other => return Err(anyhow!("输出设备的音频格式暂不支持：{other:?}")),
        };
        stream.play()?;
        self.playback = Some(stream);
        let name = device
            .description()
            .map(|d| d.name().to_owned())
            .unwrap_or_else(|_| "系统默认输出设备".into());
        crate::emit(serde_json::json!({"type":"audioDevice", "name":name}));
        Ok(())
    }
    pub fn test_output(&mut self, volume: f32) -> Result<()> {
        self.volume
            .store(volume.clamp(0.0, 1.5).to_bits(), Ordering::Relaxed);
        self.start_playback()?;
        self.tone.store(TEST_TONE_SAMPLES, Ordering::Relaxed);
        Ok(())
    }
    pub fn set_capture(&mut self, enabled: bool) -> Result<()> {
        self.gate.store(false, Ordering::SeqCst);
        if !enabled {
            self.capture = None;
            return Ok(());
        }
        if self.capture.is_none() {
            let device = cpal::default_host()
                .default_input_device()
                .context("没有可用的麦克风")?;
            let config = device.default_input_config()?;
            let mut encoder = Capture::new(
                self.sender.clone(),
                self.gate.clone(),
                self.codec.clone(),
                config.channels() as usize,
                config.sample_rate(),
            )?;
            let err = |e| {
                crate::emit(
                    serde_json::json!({"type":"audioError", "capture":true, "message":format!("麦克风错误：{e}")}),
                )
            };
            let stream = match config.sample_format() {
                SampleFormat::F32 => device.build_input_stream(
                    config.config(),
                    move |data: &[f32], _| encoder.read(data),
                    err,
                    None,
                )?,
                SampleFormat::I16 => device.build_input_stream(
                    config.config(),
                    move |data: &[i16], _| encoder.read(data),
                    err,
                    None,
                )?,
                SampleFormat::U16 => device.build_input_stream(
                    config.config(),
                    move |data: &[u16], _| encoder.read(data),
                    err,
                    None,
                )?,
                other => return Err(anyhow!("麦克风的音频格式暂不支持：{other:?}")),
            };
            stream.play()?;
            self.capture = Some(stream);
        }
        self.gate.store(true, Ordering::SeqCst);
        Ok(())
    }
    pub fn reset(&self) {
        if let Ok(mut h) = self.handler.lock() {
            h.reset();
        }
    }
    pub fn receive(&self, client: ClientId, packet: InAudioBuf) -> Result<()> {
        let mut handler = self.handler.lock().map_err(|_| anyhow!("音频队列不可用"))?;
        receive_packet(&mut handler, client, packet)
    }
}

fn receive_packet(
    handler: &mut AudioHandler<ClientId>,
    client: ClientId,
    packet: InAudioBuf,
) -> Result<()> {
    // Keep a copy only for queue resynchronization. Late/duplicate datagrams are
    // normal UDP behavior, not decoder failures. Never reset other speakers.
    let backup = packet.raw_data().to_vec();
    match handler.handle_packet(client, packet) {
        Ok(_) | Err(QueueError::Duplicate(_)) => Ok(()),
        Err(QueueError::TooLate { wanted, got }) => {
            if got.wrapping_sub(wanted) < 0x8000 {
                handler.get_mut_queues().remove(&client);
                handler.handle_packet(client, InAudioBuf::try_new(Direction::S2C, backup)?)?;
            }
            Ok(())
        }
        Err(QueueError::QueueFull) => {
            handler.get_mut_queues().remove(&client);
            handler.handle_packet(client, InAudioBuf::try_new(Direction::S2C, backup)?)?;
            Ok(())
        }
        Err(error) => Err(error.into()),
    }
}

pub fn test_output_offline(volume: f32) {
    std::thread::spawn(move || {
        let (sender, _receiver) = mpsc::channel(1);
        let mut audio = Audio::new(sender);
        if let Err(error) = audio.test_output(volume) {
            crate::emit(
                serde_json::json!({"type":"audioError", "message":format!("无法测试扬声器：{error:#}")}),
            );
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(1100));
    });
}

// Convert the device's native sample rate to Opus's 48 kHz, carrying phase across callbacks.
struct Capture {
    encoder: Encoder,
    sender: mpsc::Sender<OutPacket>,
    gate: Arc<AtomicBool>,
    codec: Arc<AtomicU8>,
    channels: usize,
    step: f64,
    phase: f64,
    previous: f32,
    frame: Vec<f32>,
    output: [u8; 1275],
}
impl Capture {
    fn new(
        sender: mpsc::Sender<OutPacket>,
        gate: Arc<AtomicBool>,
        codec: Arc<AtomicU8>,
        channels: usize,
        rate: u32,
    ) -> Result<Self> {
        Ok(Self {
            encoder: Encoder::new(
                audiopus::SampleRate::Hz48000,
                audiopus::Channels::Mono,
                audiopus::Application::Voip,
            )?,
            sender,
            gate,
            codec,
            channels,
            step: 48000.0 / rate as f64,
            phase: 0.0,
            previous: 0.0,
            frame: Vec::with_capacity(FRAME),
            output: [0; 1275],
        })
    }
    fn read<T: cpal::Sample>(&mut self, data: &[T])
    where
        f32: cpal::FromSample<T>,
    {
        if !self.gate.load(Ordering::SeqCst) {
            self.frame.clear();
            self.phase = 0.0;
            return;
        }
        for chunk in data.chunks_exact(self.channels) {
            let mono =
                chunk.iter().map(|v| v.to_sample::<f32>()).sum::<f32>() / self.channels as f32;
            self.phase += self.step;
            while self.phase >= 1.0 {
                self.phase -= 1.0;
                let weight = (1.0 - self.phase / self.step) as f32;
                self.frame
                    .push(self.previous + (mono - self.previous) * weight.clamp(0.0, 1.0));
                if self.frame.len() == FRAME {
                    if let Ok(len) = self.encoder.encode_float(&self.frame, &mut self.output) {
                        let codec = if self.codec.load(Ordering::Relaxed) == 1 {
                            CodecType::OpusMusic
                        } else {
                            CodecType::OpusVoice
                        };
                        let _ = self.sender.try_send(OutAudio::new(&AudioData::C2S {
                            id: 0,
                            codec,
                            data: &self.output[..len],
                        }));
                    }
                    self.frame.clear();
                }
            }
            self.previous = mono;
        }
    }
}

struct Renderer {
    handler: Arc<Mutex<AudioHandler<ClientId>>>,
    volume: Arc<AtomicU32>,
    tone: Arc<AtomicU32>,
    channels: usize,
    step: f64,
    position: f64,
    index: usize,
    buffer: [f32; FRAME * 2],
    current: [f32; 2],
    next: [f32; 2],
}
impl Renderer {
    fn new(
        handler: Arc<Mutex<AudioHandler<ClientId>>>,
        volume: Arc<AtomicU32>,
        tone: Arc<AtomicU32>,
        channels: usize,
        rate: u32,
    ) -> Self {
        Self {
            handler,
            volume,
            tone,
            channels,
            step: 48000.0 / rate as f64,
            position: 0.0,
            index: FRAME,
            buffer: [0.0; FRAME * 2],
            current: [0.0; 2],
            next: [0.0; 2],
        }
    }
    fn frame(&mut self) -> [f32; 2] {
        if self.index >= FRAME {
            self.buffer.fill(0.0);
            if let Ok(mut h) = self.handler.lock() {
                h.fill_buffer(&mut self.buffer);
            }
            self.index = 0;
        }
        let mut result = [self.buffer[self.index * 2], self.buffer[self.index * 2 + 1]];
        self.index += 1;
        let remaining = self.tone.load(Ordering::Relaxed);
        if remaining > 0 {
            // A gentle local tone through the same renderer as received voice.
            let elapsed = TEST_TONE_SAMPLES - remaining;
            let envelope = (elapsed.min(remaining) as f32 / 1440.0).min(1.0);
            let tone =
                (elapsed as f32 * 660.0 * std::f32::consts::TAU / 48000.0).sin() * 0.12 * envelope;
            result[0] += tone;
            result[1] += tone;
            let _ = self.tone.compare_exchange(
                remaining,
                remaining - 1,
                Ordering::Relaxed,
                Ordering::Relaxed,
            );
        }
        result
    }
    fn fill<T: cpal::Sample + cpal::FromSample<f32>>(&mut self, data: &mut [T]) {
        let volume = f32::from_bits(self.volume.load(Ordering::Relaxed));
        for chunk in data.chunks_exact_mut(self.channels) {
            let p = self.position as f32;
            let stereo = [
                self.current[0] * (1.0 - p) + self.next[0] * p,
                self.current[1] * (1.0 - p) + self.next[1] * p,
            ];
            for (i, sample) in chunk.iter_mut().enumerate() {
                let value = if self.channels == 1 {
                    (stereo[0] + stereo[1]) * 0.5
                } else {
                    stereo[i.min(1)]
                };
                *sample = T::from_sample((value * volume).clamp(-1.0, 1.0));
            }
            self.position += self.step;
            while self.position >= 1.0 {
                self.position -= 1.0;
                self.current = self.next;
                self.next = self.frame();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn voice_packet(id: u16, encoder: &mut Encoder) -> InAudioBuf {
        use tsproto_packets::packets::Direction;
        let frame: Vec<f32> = (0..FRAME)
            .map(|i| (i as f32 * 440.0 * std::f32::consts::TAU / 48000.0).sin() * 0.1)
            .collect();
        let mut bytes = [0u8; 1275];
        let len = encoder.encode_float(&frame, &mut bytes).unwrap();
        let packet = OutAudio::new(&AudioData::S2C {
            id,
            from: 7,
            codec: CodecType::OpusVoice,
            data: &bytes[..len],
        });
        InAudioBuf::try_new(Direction::S2C, packet.into_vec()).unwrap()
    }
    #[test]
    fn startup_reorders_packets_before_playback() {
        let mut encoder = Encoder::new(
            audiopus::SampleRate::Hz48000,
            audiopus::Channels::Mono,
            audiopus::Application::Voip,
        )
        .unwrap();
        let mut handler = AudioHandler::<ClientId>::new();
        let first = voice_packet(20238, &mut encoder);
        let second = voice_packet(20239, &mut encoder);
        handler.handle_packet(ClientId(7), second).unwrap();
        let mut buffer = [0f32; FRAME * 2];
        handler.fill_buffer(&mut buffer);
        assert!(
            buffer.iter().all(|s| *s == 0.0),
            "Wait for jitter before consuming the first packet"
        );
        handler.handle_packet(ClientId(7), first).unwrap();
        handler
            .handle_packet(ClientId(7), voice_packet(20240, &mut encoder))
            .unwrap();
        handler.fill_buffer(&mut buffer);
        assert!(buffer.iter().map(|s| s * s).sum::<f32>() > 0.01);
    }
    #[test]
    fn realtime_renderer_handles_jitter_wraparound_and_output_rates() {
        for (rate, channels) in [(48000, 2), (44100, 1), (16000, 2)] {
            let mut encoder = Encoder::new(
                audiopus::SampleRate::Hz48000,
                audiopus::Channels::Mono,
                audiopus::Application::Voip,
            )
            .unwrap();
            let mut arrivals = Vec::new();
            for index in 0u16..200 {
                let delay = [5, 0, 1, 0, 3, 0][index as usize % 6];
                arrivals.push((
                    index as usize * 4 + delay,
                    voice_packet(65520u16.wrapping_add(index), &mut encoder),
                ));
            }
            arrivals.sort_by_key(|(tick, _)| *tick);
            let handler = Arc::new(Mutex::new(AudioHandler::<ClientId>::new()));
            let mut renderer = Renderer::new(
                handler.clone(),
                Arc::new(AtomicU32::new(1f32.to_bits())),
                Arc::new(AtomicU32::new(0)),
                channels,
                rate,
            );
            let mut arrivals = arrivals.into_iter().peekable();
            let mut voiced_callbacks = 0;
            for tick in 0..840 {
                while arrivals
                    .peek()
                    .map(|(arrival, _)| *arrival <= tick)
                    .unwrap_or(false)
                {
                    let (_, packet) = arrivals.next().unwrap();
                    receive_packet(&mut handler.lock().unwrap(), ClientId(7), packet).unwrap();
                }
                let frames = (tick + 1) * rate as usize / 200 - tick * rate as usize / 200;
                let mut output = vec![0f32; frames * channels];
                renderer.fill(&mut output);
                assert!(output.iter().all(|s| s.is_finite() && s.abs() <= 1.0));
                if (20..800).contains(&tick) && output.iter().map(|s| s * s).sum::<f32>() > 0.01 {
                    voiced_callbacks += 1;
                }
            }
            assert!(
                voiced_callbacks > 740,
                "Continuous speech at {rate} Hz: {voiced_callbacks}/780 audible callbacks"
            );
        }
    }
    #[test]
    fn late_duplicates_are_harmless_and_large_forward_gap_recovers() {
        let mut encoder = Encoder::new(
            audiopus::SampleRate::Hz48000,
            audiopus::Channels::Mono,
            audiopus::Application::Voip,
        )
        .unwrap();
        let mut handler = AudioHandler::<ClientId>::new();
        for id in 100..103 {
            receive_packet(&mut handler, ClientId(7), voice_packet(id, &mut encoder)).unwrap();
        }
        receive_packet(&mut handler, ClientId(8), voice_packet(500, &mut encoder)).unwrap();
        let mut output = [0f32; FRAME * 2];
        handler.fill_buffer(&mut output);
        receive_packet(&mut handler, ClientId(7), voice_packet(100, &mut encoder)).unwrap();
        receive_packet(&mut handler, ClientId(7), voice_packet(102, &mut encoder)).unwrap();
        for id in 300..303 {
            receive_packet(&mut handler, ClientId(7), voice_packet(id, &mut encoder)).unwrap();
        }
        receive_packet(&mut handler, ClientId(7), voice_packet(50, &mut encoder)).unwrap();
        assert!(
            handler.get_queues().contains_key(&ClientId(8)),
            "Recovery must preserve other speakers"
        );
        output.fill(0.0);
        handler.fill_buffer(&mut output);
        assert!(
            output.iter().map(|s| s * s).sum::<f32>() > 0.01,
            "Speech must resume after an ID jump"
        );
        assert!(handler
            .handle_packet(ClientId(7), voice_packet(303, &mut encoder))
            .is_ok());
    }
    #[test]
    fn local_test_tone_uses_playback_volume_and_stops() {
        let tone = Arc::new(AtomicU32::new(TEST_TONE_SAMPLES));
        let volume = Arc::new(AtomicU32::new(1f32.to_bits()));
        let handler = Arc::new(Mutex::new(AudioHandler::<ClientId>::new()));
        let mut renderer = Renderer::new(handler, volume.clone(), tone.clone(), 2, 48000);
        let mut output = [0f32; FRAME * 2];
        renderer.fill(&mut output);
        assert!(output.iter().map(|s| s * s).sum::<f32>() > 0.01);
        volume.store(0f32.to_bits(), Ordering::Relaxed);
        renderer.fill(&mut output);
        assert!(output.iter().all(|s| *s == 0.0));
        volume.store(1f32.to_bits(), Ordering::Relaxed);
        for _ in 0..41 {
            renderer.fill(&mut output);
        }
        assert_eq!(tone.load(Ordering::Relaxed), 0);
        assert!(output.iter().all(|s| *s == 0.0));
    }
    #[test]
    fn capture_packets_decode_and_mix_for_both_opus_codecs() {
        use tsproto_packets::packets::Direction;
        for music in [false, true] {
            let (tx, mut rx) = mpsc::channel(8);
            let gate = Arc::new(AtomicBool::new(true));
            let codec = Arc::new(AtomicU8::new(if music { 1 } else { 0 }));
            let mut capture = Capture::new(tx, gate, codec, 1, 48000).unwrap();
            let mut handler = AudioHandler::<ClientId>::new();
            for id in 0..6 {
                let frame: Vec<f32> = (0..FRAME)
                    .map(|i| ((i as f32 / 48000.0) * 440.0 * std::f32::consts::TAU).sin() * 0.1)
                    .collect();
                capture.read(&frame);
                let packet = rx.try_recv().unwrap();
                let incoming = InAudioBuf::try_new(Direction::C2S, packet.into_vec()).unwrap();
                if let AudioData::C2S { codec, data, .. } = incoming.data().data() {
                    assert_eq!(
                        *codec,
                        if music {
                            CodecType::OpusMusic
                        } else {
                            CodecType::OpusVoice
                        }
                    );
                    let server = OutAudio::new(&AudioData::S2C {
                        id,
                        from: 7,
                        codec: *codec,
                        data,
                    });
                    handler
                        .handle_packet(
                            ClientId(7),
                            InAudioBuf::try_new(Direction::S2C, server.into_vec()).unwrap(),
                        )
                        .unwrap();
                } else {
                    panic!("Expected client voice packet");
                }
            }
            let mut energy = 0f32;
            for _ in 0..8 {
                let mut buffer = [0f32; FRAME * 2];
                handler.fill_buffer(&mut buffer);
                assert!(buffer.iter().all(|s| s.is_finite()));
                energy += buffer.iter().map(|s| s * s).sum::<f32>();
            }
            assert!(
                energy > 0.01,
                "Encoded voice must decode to audible, finite PCM"
            );
        }
    }
    #[test]
    fn muted_capture_emits_nothing_then_encodes_exact_frames() {
        let (tx, mut rx) = mpsc::channel(8);
        let gate = Arc::new(AtomicBool::new(false));
        let mut c = Capture::new(tx, gate.clone(), Arc::new(AtomicU8::new(0)), 2, 48000).unwrap();
        c.read(&vec![0.1f32; FRAME * 2]);
        assert!(rx.try_recv().is_err());
        gate.store(true, Ordering::SeqCst);
        c.read(&vec![0.1f32; 500 * 2]);
        assert!(rx.try_recv().is_err());
        c.read(&vec![0.1f32; 460 * 2]);
        assert!(rx.try_recv().is_ok());
        assert!(rx.try_recv().is_err());
    }
    #[test]
    fn resamples_44100_and_discards_partial_frame_on_mute() {
        let (tx, mut rx) = mpsc::channel(8);
        let gate = Arc::new(AtomicBool::new(true));
        let mut c = Capture::new(tx, gate.clone(), Arc::new(AtomicU8::new(0)), 1, 44100).unwrap();
        c.read(&vec![0.1f32; 883]);
        assert!(rx.try_recv().is_ok());
        c.read(&vec![0.1f32; 400]);
        gate.store(false, Ordering::SeqCst);
        c.read(&[0.0]);
        gate.store(true, Ordering::SeqCst);
        c.read(&vec![0.1f32; 400]);
        assert!(rx.try_recv().is_err());
    }
}
