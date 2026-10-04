<div align="center">

<img src="Docs/logo.svg" width="120" height="120" alt="QuietSpeak logo" />

# QuietSpeak

**Native macOS · TeamSpeak 3 · Lightweight voice chat**

Connect to your TeamSpeak 3 server, browse channels, talk and send messages.

[![macOS](https://img.shields.io/badge/macOS-14%2B-303030?logo=apple&logoColor=white)](#quick-start) [![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift&logoColor=white)](Native/) [![Rust](https://img.shields.io/badge/Core-Rust-6E4C38?logo=rust&logoColor=white)](Core/) [![MIT](https://img.shields.io/badge/License-MIT-2E745C)](LICENSE) [![Release](https://img.shields.io/badge/Release-0.1.8-2E745C)](https://github.com/Green-hats/QuietSpeak/releases/latest) [![CI](https://github.com/Green-hats/QuietSpeak/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Green-hats/QuietSpeak/actions/workflows/ci.yml)

[简体中文](README.md) · [**English**](README.en.md)

[Quick start](#quick-start) · [Features](#features) · [Architecture](Docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) · [Issues](https://github.com/Green-hats/QuietSpeak/issues)

</div>

---

## Screenshots

![QuietSpeak light appearance](Docs/screenshots/quietspeak-light.jpg)

Captured from a native window with fictional servers, members and messages.

## Features

| Capability | Details |
| --- | --- |
| Native interface | SwiftUI / AppKit, collapsible sidebars and dark appearance; Liquid Glass on newer systems, Material on older systems |
| Servers and channels | TS3 connection, SRV / TSDNS discovery, reconnection, bookmarks, channel tree and protected channels |
| Voice | Opus, speaker mixing, push-to-talk / continuous mode, microphone mute, deafen and playback volume |
| Messages | Send and receive channel messages; receive server and private messages |
| macOS integration | Menu bar controls, speaker test, UserDefaults bookmarks and Keychain identity / remembered passwords |

Current version: **0.1.8**, with a Simplified Chinese UI. [Release notes and checksums](https://github.com/Green-hats/QuietSpeak/releases/tag/v0.1.8).

## Quick start

Download: [Apple Silicon](https://github.com/Green-hats/QuietSpeak/releases/download/v0.1.8/QuietSpeak-0.1.8-macOS-arm64.dmg) · [Intel](https://github.com/Green-hats/QuietSpeak/releases/download/v0.1.8/QuietSpeak-0.1.8-macOS-x86_64.dmg). Open the DMG, drag `QuietSpeak.app` into Applications and open it. Requires macOS 14+.

Building from source also requires Xcode Command Line Tools (including `swift-format`), Rust, CMake and Python 3.9+. Xcode 26+ is recommended for Liquid Glass. Rust 1.95.0 is pinned in `rust-toolchain.toml`.

```bash
git clone https://github.com/Green-hats/QuietSpeak.git
cd QuietSpeak
./build.sh
open dist/QuietSpeak.app
```

The first build downloads Rust and Cargo dependencies. Vendored sources are included; no submodules are needed. The script builds for your Mac's architecture and applies ad-hoc signing. Running the App requires no Rust or Homebrew. Developer ID signing and notarization are not yet available.

1. Add a server address, nickname and optional password, then connect and join a channel.
2. Enable the microphone, which starts disabled, and grant macOS microphone permission.
3. Hold the bottom button or `⌥ Option` to talk. Keyboard push-to-talk works only while the App is foreground; continuous mode is also available.

The system sidebar button toggles servers; `⌘⇧2` toggles channels. Drag the dividers to resize panes. Changing channels disables the microphone; deafen stops voice transmission. Closing the window keeps menu bar controls available.

## Development

```bash
./check.sh
./test.sh
./build.sh
```

Caches default to `work/build/` and the App to `dist/QuietSpeak.app`. See [Contributing](CONTRIBUTING.md) for development, validation and packaging, and [Changelog](CHANGELOG.md) for version history.

Swift manages the native UI; Rust / Tokio handles the protocol and audio. C ABI commands and events connect them, with Opus statically linked. See [Architecture](Docs/ARCHITECTURE.md) for the complete system and audio flow (Chinese).

## Limitations and troubleshooting

- Voice supports OpusVoice / OpusMusic only. Global push-to-talk, voice activation, echo cancellation, private-message sending, file transfer, permission management and identity import are not implemented.
- Audio uses the system default devices. Reconnect if audio stops after changing devices.
- Apple Silicon has been validated locally; Intel hardware, additional macOS versions and two-endpoint voice calls need further validation.

For no sound, check deafen and volume, run the speaker test in audio settings and check the system output device. For `No route to host`, check your network and proxy. Do not append the default port to an SRV hostname.

## Contributing and license

Report [issues](https://github.com/Green-hats/QuietSpeak/issues) or submit PRs. Report security vulnerabilities privately according to the [security policy](SECURITY.md).

Project code is [MIT licensed](LICENSE). The TS3 protocol uses [ReSpeak/tsclientlib](https://github.com/ReSpeak/tsclientlib), with CPAL and Opus / audiopus for audio. QuietSpeak implements the native UI, application behavior, bridge and device audio pipeline.

See [Vendor documentation](Vendor/README.md) for upstream sources and patches, and [Third-party notices](THIRD_PARTY_NOTICES.txt) for licenses. QuietSpeak is not an official TeamSpeak product.
