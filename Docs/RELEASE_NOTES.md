# QuietSpeak 0.1.8

轻语，原生 macOS TeamSpeak 3 客户端。

- 应用图标更新为浅绿色 `#02A86F`（RGB 2, 168, 111）。
- Apple Silicon 和 Intel 安装包改为 DMG，打开后将 App 拖入“应用程序”即可安装。
- 保留可折叠三栏、玻璃材质、语音交流和频道文字消息等功能。

## 下载与安装

- `QuietSpeak-0.1.8-macOS-arm64.dmg`：Apple Silicon（M 系列芯片）。
- `QuietSpeak-0.1.8-macOS-x86_64.dmg`：Intel Mac。
- `QuietSpeak-0.1.8-source.zip`：完整源码与第三方许可证。
- `SHA256SUMS.txt`：以上文件的 SHA-256 校验值。

需要 macOS 14+。打开 DMG，将 `QuietSpeak.app` 拖入“应用程序”，弹出磁盘映像后从“应用程序”打开。运行无需 Rust 或 Homebrew；首次开启麦克风需要授予系统权限。

## 验证与限制

双架构构建会执行检查、测试，并挂载 DMG 验证 App 的签名、架构和安装快捷方式。Intel 实机、蓝牙及更多系统版本仍需进一步验收。

App 使用 ad-hoc 签名，尚未进行 Developer ID 签名和公证。语音仅支持 OpusVoice / OpusMusic；暂不支持全局按键说话、语音激活、回声消除、私信发送、文件传输、权限管理和身份导入。
