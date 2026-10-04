// Read-only live integration check. Never opens audio capture or sends chat.
use serde_json::json;
use std::{
    ffi::CStr,
    time::{Duration, Instant},
};
fn main() {
    let address = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "127.0.0.1:9987".into());
    quietspeak_core::qs_initialize();
    let command=std::ffi::CString::new(json!({"op":"connect","address":address,"nickname":"QuietSpeak-Test","password":"","identity":null}).to_string()).unwrap();
    unsafe { quietspeak_core::qs_command(command.as_ptr()) };
    let start = Instant::now();
    let mut success = false;
    loop {
        let pointer = quietspeak_core::qs_poll();
        let text = unsafe { CStr::from_ptr(pointer).to_string_lossy().into_owned() };
        unsafe { quietspeak_core::qs_free_string(pointer) };
        let events: Vec<serde_json::Value> = serde_json::from_str(&text).unwrap();
        for event in events {
            match event["type"].as_str().unwrap_or("") {
                "identity" => {} // Private keys must never enter test logs.
                "snapshot" => {
                    println!("LIVE SNAPSHOT: channels={}, visible_clients={}, own={}, current_channel={}",event["channels"].as_array().unwrap().len(),event["clients"].as_array().unwrap().len(),event["own"],event["currentChannel"]);
                    if !event["channels"].as_array().unwrap().is_empty() {
                        let own = event["clients"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .find(|c| c["id"] == event["own"])
                            .unwrap();
                        assert_eq!(own["muted"], true, "test client must remain muted");
                        success = true;
                    }
                }
                "error" => {
                    eprintln!("CONNECTION ERROR: {}", event["message"]);
                }
                "connected" => println!("LIVE CONNECTED"),
                "disconnected" => {
                    println!("LIVE DISCONNECTED");
                    std::process::exit(if success { 0 } else { 1 })
                }
                _ => {}
            }
        }
        if success && start.elapsed() > Duration::from_secs(4)
            || start.elapsed() > Duration::from_secs(35)
        {
            let command = std::ffi::CString::new("{\"op\":\"disconnect\"}").unwrap();
            unsafe { quietspeak_core::qs_command(command.as_ptr()) };
            std::thread::sleep(Duration::from_secs(3));
            std::process::exit(if success { 0 } else { 1 });
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
