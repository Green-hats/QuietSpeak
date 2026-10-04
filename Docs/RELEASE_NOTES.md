# QuietSpeak 0.1.7

轻语首个公开发布版本，原生 macOS TeamSpeak 3 客户端。

- 连接 TS3 服务器、收藏、频道树、密码频道与成员列表。
- Opus 语音收发、前台按键 / 持续说话、麦克风与耳机静音、菜单栏控制。
- 频道文字消息收发，修复自己的消息重复回显。
- 白色主调、绿色点缀；可折叠三栏、系统玻璃材质，底部语音条仅横跨频道和聊天区。

## 下载与安装

- `QuietSpeak-0.1.7-macOS-arm64.zip`：Apple Silicon（M 系列芯片）。
- `QuietSpeak-0.1.7-macOS-x86_64.zip`：Intel Mac。
- `QuietSpeak-0.1.7-source.zip`：完整源码与第三方许可证。
- `SHA256SUMS.txt`：以上文件的 SHA-256 校验值。

需要 macOS 14+。解压后将 `QuietSpeak.app` 放入“应用程序”并打开，运行无需 Rust 或 Homebrew。首次开启麦克风需要授予系统权限，按键说话仅在 App 位于前台时生效。

## 验证与限制

两个架构均通过 GitHub Actions 检查、测试、构建和签名校验。Apple Silicon 已有本机使用反馈；Intel 实机、蓝牙和更多系统版本仍需进一步验收。

App 使用 ad-hoc 签名，尚未进行 Developer ID 签名和公证。语音仅支持 OpusVoice / OpusMusic；暂不支持全局按键说话、语音激活、回声消除、私信发送、文件传输、权限管理和身份导入。
