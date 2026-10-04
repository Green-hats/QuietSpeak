# 项目架构

[返回项目介绍](../README.md) · [开发路线](ROADMAP.md)


以下图示对应当前 0.1.7 源码。整个客户端运行在一个 macOS App 进程内，Rust 核心和 Opus 静态链接到 App。

```mermaid
flowchart TB
    subgraph SWIFT["原生界面 · Swift 主线程"]
        UI["SwiftUI / AppKit<br/>窗口 · 频道 · 聊天 · 菜单栏"]
        MODEL["ClientModel<br/>界面状态 · 用户操作 · 事件处理"]
        UI -->|用户操作| MODEL
        MODEL -->|状态更新| UI
    end

    subgraph RUST["Rust 核心 · 静态链接"]
        FFI["C ABI / FFI<br/>qs_command · qs_poll"]
        SESSION["Tokio 会话<br/>连接 · 频道 · 消息 · 语音权限"]
        PROTO["tsclientlib<br/>TS3 协议 · 域名发现 · 重连"]
        AUDIO["音频模块<br/>Opus · 抖动缓冲 · 混音 · 重采样"]
        FFI -->|命令队列| SESSION
        SESSION -->|事件队列| FFI
        SESSION <-->|协议命令与事件| PROTO
        SESSION <-->|语音包与音频控制| AUDIO
    end

    MODEL -->|JSON 命令| FFI
    FFI -->|JSON 事件 · 每 50ms 轮询| MODEL
    MODEL <-->|收藏读写| PREFS["UserDefaults<br/>服务器收藏"]
    MODEL <-->|身份与密码读写| KEYS["macOS Keychain<br/>身份密钥 · 服务器密码"]
    PROTO <-->|UDP| SERVER["TeamSpeak 3 服务器"]
    AUDIO <-->|音频回调| DEVICE["CPAL → CoreAudio<br/>麦克风 · 耳机 / 扬声器"]

    classDef swift fill:#eaf1ff,stroke:#6689c7,color:#182e50;
    classDef rust fill:#e8f5ef,stroke:#4c9977,color:#183e2d;
    classDef storage fill:#fff5e4,stroke:#be9756,color:#593e1b;
    classDef external fill:#f1f3f5,stroke:#87939e,color:#273746;
    class UI,MODEL swift;
    class FFI,SESSION,PROTO,AUDIO rust;
    class PREFS,KEYS storage;
    class SERVER,DEVICE external;
```

Swift 的 `ClientModel` 管理界面状态，把连接、加入频道、聊天和音频控制序列化为 JSON 命令。Rust 通过命令队列接收操作，把频道快照、消息、连接状态和音频错误放入事件队列；Swift 每 50ms 轮询并更新界面。

语音 PCM 在 Rust 音频模块内处理。网络语音包经 Opus 编解码、播放队列和重采样，通过 CPAL 调用 CoreAudio 与实际音频设备交换数据。

### 音频数据流

```mermaid
flowchart TB
    subgraph SEND["发送语音"]
        MIC["麦克风 · CPAL / CoreAudio 输入回调"]
        CAPTURE["Capture<br/>合并为单声道 · 转换为 48kHz"]
        ENCODE["Opus 编码<br/>20ms 帧 · 每帧 960 个采样点"]
        OUTQUEUE["语音包队列<br/>Tokio mpsc · 容量 5"]
        GATE["会话检查<br/>已连接 · 请求发送 · 耳机未静音 · 允许说话"]
        TX["tsclientlib.send_audio<br/>TS3 UDP 发包"]
        MIC --> CAPTURE --> ENCODE --> OUTQUEUE --> GATE --> TX
    end

    SERVER["TeamSpeak 3 服务器"]
    TX --> SERVER

    subgraph RECEIVE["接收语音"]
        RX["tsclientlib · StreamItem.Audio"]
        CHECK["会话检查<br/>允许接收 · 耳机未静音"]
        QUEUE["按说话者维护队列<br/>乱序接收 · 起播缓冲 · 序号跳变恢复"]
        DECODE["AudioHandler<br/>Opus 解码 · 丢包处理 · 多人混音"]
        RENDER["Renderer<br/>播放音量 · 输出采样率和声道转换"]
        SPEAKER["耳机 / 扬声器 · CPAL / CoreAudio 输出回调"]
        RX --> CHECK --> QUEUE --> DECODE --> RENDER --> SPEAKER
    end

    SERVER --> RX
    LOCAL["测试扬声器<br/>本地提示音"] --> RENDER

    classDef input fill:#eaf1ff,stroke:#6689c7,color:#182e50;
    classDef audio fill:#e8f5ef,stroke:#4c9977,color:#183e2d;
    classDef network fill:#fff5e4,stroke:#be9756,color:#593e1b;
    class MIC,SPEAKER input;
    class CAPTURE,ENCODE,QUEUE,DECODE,RENDER,LOCAL audio;
    class OUTQUEUE,GATE,TX,SERVER,RX,CHECK network;
```

起播以 60ms 为初始缓冲目标，允许 UDP 包在播放前重新排序；已播放的迟到包和重复包会被丢弃，较大的正向序号跳变会重建对应说话者的队列。本地扬声器测试经过同一个 Renderer 输出。

### 代码职责和线程

| 模块 | 源码 | 职责与执行位置 |
| --- | --- | --- |
| 界面 | `Native/QuietSpeakApp.swift`、`MainView.swift`、`Sheets.swift` | SwiftUI 窗口、表单、菜单栏和 App 生命周期 |
| 状态管理 | `Native/ClientModel.swift` | MainActor；界面状态、操作校验、事件轮询和麦克风权限 |
| 本地存储 | `Native/Storage.swift`、`ClientModel.swift` | Keychain 身份/密码；UserDefaults 收藏；地址校验和频道排序 |
| FFI 桥接 | `Core/src/lib.rs` | `qs_initialize`、`qs_command`、`qs_poll`、`qs_free_string`；命令与事件的跨语言所有权 |
| 网络会话 | `Core/src/lib.rs` 的 `session` | 独立协议线程内的 Tokio 单线程运行时；处理命令、网络事件、语音发送和连接超时 |
| 音频 | `Core/src/audio.rs` | 会话线程接收语音包；CoreAudio 输入/输出回调运行 Capture 和 Renderer |
| TS3 协议与接收解码 | `Vendor/tsclientlib/` | 服务器发现、UDP、协议状态、每位说话者的 AudioHandler 队列、解码与混音 |

会话线程和输出回调用 `Arc<Mutex<AudioHandler>>` 共享接收队列；麦克风门控、音量和本地提示音等控制使用原子变量。输入回调通过容量为 5 的 `mpsc` 队列提交已编码语音包。离线扬声器测试会短暂创建单独的本地测试线程。

自己的频道消息按发送操作的成功确认显示，忽略服务器对自己频道消息的回显；每次发送独立跟踪，因此相同文字可以连续发送。其他成员的消息通过服务器通知显示。

事件队列最多保留 512 个事件，并合并被新快照替代的旧快照。`qs_poll` 返回 Rust 分配的 UTF-8 JSON 字符串，Swift 使用后调用 `qs_free_string` 释放。

可编辑图源：[总体架构](architecture.mmd) · [音频链路](audio-flow.mmd)。

