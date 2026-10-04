use serde_json::{json, Value};
use std::collections::HashMap;
use tsclientlib::{events::Event, ClientId, MessageHandle, MessageTarget};

pub(crate) struct PendingChat {
    pub text: String,
    pub channel: u64,
    pub nickname: String,
    pub own: u16,
}

#[derive(Default)]
pub(crate) struct ChatDelivery {
    pending: HashMap<MessageHandle, PendingChat>,
}

impl ChatDelivery {
    pub fn track(&mut self, handle: MessageHandle, chat: PendingChat) {
        self.pending.insert(handle, chat);
    }

    pub fn clear(&mut self) {
        self.pending.clear();
    }

    pub fn complete(&mut self, handle: MessageHandle, succeeded: bool) -> Option<Value> {
        let chat = self.pending.remove(&handle)?;
        succeeded.then(|| {
            json!({"type":"chat","sender":chat.nickname,"client":chat.own,"text":chat.text,
                "channel":chat.channel,"scope":"channel","outgoing":true})
        })
    }
}

pub(crate) fn notification(event: Event, own: Option<ClientId>, channel: u64) -> Option<Value> {
    let Event::Message {
        target,
        invoker,
        message,
    } = event
    else {
        return None;
    };
    let outgoing = own == Some(invoker.id);
    // Our channel sends are displayed by their successful command result. TS3
    // can also echo them, before or after that result. Ignore only this echo;
    // distinct sends retain their individual handles, even with identical text.
    if outgoing && target == MessageTarget::Channel {
        return None;
    }
    let scope = match target {
        MessageTarget::Channel => "channel",
        MessageTarget::Server => "server",
        _ => "private",
    };
    Some(
        json!({"type":"chat","sender":invoker.name,"client":invoker.id.0,"text":message,
        "channel":channel,"scope":scope,"outgoing":outgoing}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use tsclientlib::Invoker;

    const OWN: ClientId = ClientId(7);
    const CHANNEL: u64 = 42;

    fn pending() -> PendingChat {
        PendingChat {
            text: "同一句话".into(),
            channel: CHANNEL,
            nickname: "测试用户".into(),
            own: OWN.0,
        }
    }

    fn incoming(sender: ClientId, target: MessageTarget) -> Event {
        Event::Message {
            target,
            invoker: Invoker {
                name: "测试用户".into(),
                id: sender,
                uid: None,
            },
            message: "同一句话".into(),
        }
    }

    #[test]
    fn own_channel_message_appears_once_in_either_echo_ack_order() {
        for echo_first in [true, false] {
            let mut delivery = ChatDelivery::default();
            delivery.track(MessageHandle(1), pending());
            let mut displayed = Vec::new();
            if echo_first {
                displayed.extend(notification(
                    incoming(OWN, MessageTarget::Channel),
                    Some(OWN),
                    CHANNEL,
                ));
            }
            displayed.extend(delivery.complete(MessageHandle(1), true));
            if !echo_first {
                displayed.extend(notification(
                    incoming(OWN, MessageTarget::Channel),
                    Some(OWN),
                    CHANNEL,
                ));
            }
            assert_eq!(displayed.len(), 1, "echo_first={echo_first}");
            assert_eq!(displayed[0]["text"], "同一句话");
            assert_eq!(displayed[0]["channel"], CHANNEL);
            assert_eq!(displayed[0]["outgoing"], true);
        }
    }

    #[test]
    fn two_identical_sends_remain_two_messages_with_interleaved_echoes() {
        let mut delivery = ChatDelivery::default();
        delivery.track(MessageHandle(1), pending());
        delivery.track(MessageHandle(2), pending());
        let mut displayed = Vec::new();
        displayed.extend(notification(
            incoming(OWN, MessageTarget::Channel),
            Some(OWN),
            CHANNEL,
        ));
        displayed.extend(delivery.complete(MessageHandle(2), true));
        displayed.extend(notification(
            incoming(OWN, MessageTarget::Channel),
            Some(OWN),
            CHANNEL,
        ));
        displayed.extend(delivery.complete(MessageHandle(1), true));
        assert_eq!(displayed.len(), 2);
        assert!(displayed
            .iter()
            .all(|message| message["text"] == "同一句话"));
    }

    #[test]
    fn successful_send_without_echo_keeps_original_channel() {
        let mut delivery = ChatDelivery::default();
        delivery.track(MessageHandle(1), pending());
        let message = delivery.complete(MessageHandle(1), true).unwrap();
        assert_eq!(message["channel"], CHANNEL);
        assert!(delivery.complete(MessageHandle(1), true).is_none());
    }

    #[test]
    fn rejected_and_abandoned_sends_do_not_display() {
        let mut delivery = ChatDelivery::default();
        delivery.track(MessageHandle(1), pending());
        assert!(delivery.complete(MessageHandle(1), false).is_none());
        assert!(delivery.complete(MessageHandle(1), true).is_none());
        delivery.track(MessageHandle(2), pending());
        delivery.clear();
        assert!(delivery.complete(MessageHandle(2), true).is_none());
    }

    #[test]
    fn other_participant_with_same_name_and_text_is_not_suppressed() {
        let message = notification(
            incoming(ClientId(8), MessageTarget::Channel),
            Some(OWN),
            CHANNEL,
        )
        .unwrap();
        assert_eq!(message["text"], "同一句话");
        assert_eq!(message["outgoing"], false);
        assert_eq!(message["client"], 8);
    }

    #[test]
    fn server_and_private_messages_keep_their_scope() {
        for (target, scope) in [
            (MessageTarget::Server, "server"),
            (MessageTarget::Client(ClientId(8)), "private"),
        ] {
            let message = notification(incoming(OWN, target), Some(OWN), CHANNEL).unwrap();
            assert_eq!(message["scope"], scope);
            assert_eq!(message["outgoing"], true);
        }
    }
}
