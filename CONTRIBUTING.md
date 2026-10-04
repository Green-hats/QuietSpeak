# 开发与贡献

欢迎提交 Issue 和 PR，中文或英文均可。尊重不同观点，不公开密码、身份密钥或私人通信；安全问题请参考 [SECURITY](SECURITY.md)。

## 开发

环境要求和运行方式见 [README](README.md#快速开始)。

```bash
./check.sh                   # Rustfmt、Clippy、Swift-format、Shell 语法和版本
./test.sh                    # Rust 测试与 Swift 模型检查
./build.sh                   # 构建、签名及 App 校验
```

默认缓存为 `work/build/`，App 为 `dist/QuietSpeak.app`；支持 `QUIETSPEAK_BUILD_DIR`、`QUIETSPEAK_APP_PATH`、`CARGO_HOME` 和 `CARGO_TARGET_DIR` 覆盖路径。

从 `main` 创建分支，每个 PR 围绕一个问题，写明行为变化和验证结果。不要提交 `work/`、`dist/`、密码、证书或私人日志。格式化自有代码：

```bash
cargo fmt --manifest-path Core/Cargo.toml
xcrun swift-format format --in-place --recursive --configuration .swift-format Native Tests Scripts/make-icon.swift
```

不要使用 `cargo fmt --all` 重排第三方源码。行为改动应有能复现问题的测试；音频、协议和 FFI 改动还需检查线程边界、字符串释放、静音及发送权限，并进行两端手动验收。

## 验证范围

0.1.7 已通过本机 Apple Silicon 构建、签名、15 项 Rust 测试和 Swift 模型检查。自动测试覆盖编解码、帧拼接、重采样、包乱序 / 回绕、聊天回显、地址和频道排序，不自动连接公共服务器或打开麦克风。

双端语音、蓝牙、Intel 实机及更多 macOS 版本仍需验收。相关改动在 PR 中记录 macOS、架构、设备、频道编码和结果；远端构建结果见 [Actions](https://github.com/Green-hats/QuietSpeak/actions)。

## 打包与发布

1. 更新 `VERSION`、自有 Cargo 包及锁文件的版本、`Resources/Info.plist` 的短版本和构建号。
2. 更新 README、CHANGELOG 和供发布工作流使用的 `Docs/RELEASE_NOTES.md`。
3. 运行检查、测试和构建，再打包：

```bash
python3 Scripts/package-release.py
(cd dist/releases && shasum -a 256 -c SHA256SUMS-arm64.txt)
```

打包生成当前架构的 App ZIP、源码 ZIP 和 SHA-256 文件。Opus 静态链接，App 使用 ad-hoc 签名；Developer ID 签名与公证尚未接入。

维护者决定发布并完成验收后，推送与 VERSION 相符的 `v版本` 标签。工作流完成双架构构建并创建 **Release 草稿**；核对安装包、源码、校验文件和说明后再手动发布。当前已公开发布 [0.1.7](https://github.com/Green-hats/QuietSpeak/releases/tag/v0.1.7)。

## 第三方与后续工作

第三方来源及本地补丁见 [Vendor](Vendor/README.md)。更新上游或补丁时保留版权和许可证，更新来源记录及补丁文件，并重新生成声明：

```bash
python3 Scripts/generate-notices.py
```

缺失的许可证文本需按固定上游修订补齐，不能忽略。自有代码按 [MIT](LICENSE) 发布，第三方修改保留原许可。

优先完善设备选择和切换恢复、双端语音及多系统验收；后续考虑全局按键说话、语音激活、回声处理、私信与身份导入，以及签名公证。计划不代表已实现，也没有承诺日期。
