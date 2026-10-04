# 贡献指南

欢迎提交问题、文档改进和代码。界面目前为简体中文，Issue 和 PR 可以使用中文或英文。

## 开发环境

需要 macOS、Xcode Command Line Tools（包含 `swift-format`）、Rust、CMake 和 Python 3.9 或以上。`rust-toolchain.toml` 固定 Rust 版本及 rustfmt/clippy；首次使用会下载对应工具链。

```bash
./check.sh
./test.sh
./build.sh
```

开发缓存位于 `work/build/`，App 位于 `dist/QuietSpeak.app`。不要提交构建产物、服务器密码、身份密钥、证书或私人日志。

## 修改与验证

1. 从 `main` 创建分支，围绕一个明确问题修改代码。
2. Rust 代码使用 `cargo fmt --manifest-path Core/Cargo.toml` 格式化；不要用 `--all` 批量重排第三方代码。
3. Swift 使用 `xcrun swift-format format --in-place --recursive --configuration .swift-format Native Tests Scripts/make-icon.swift`。
4. 运行检查、测试和构建；为行为改变添加能复现问题的测试。
5. 音频或协议改动还需两端手动验收，记录 macOS、架构、设备、频道编码和结果。自动测试不默认连接公共服务器。
6. PR 写明问题、最终行为和验证结果，关联相应 Issue。

FFI 的字符串所有权、线程边界、输入静音和发送权限判断都属于重要行为；相关变更需要具体测试。

## 第三方代码

`Vendor/` 保留固定版本和原许可证。修改第三方源码时更新 `Vendor/patches/`、`Vendor/README.md`，并说明上游修订和补丁原因。生成依赖声明：

```bash
python3 Scripts/generate-notices.py
```

依赖更新后重新检查生成的声明和 `Docs/DEPENDENCIES.json`。新增依赖缺少许可证文本时，补齐来自对应上游提交的文本和来源记录，不能静默跳过。

## 许可

新提交的项目代码按根目录 MIT 许可证发布；第三方修改保留该文件的原许可证。贡献时请确认你有权提交对应内容，并保留所需的版权归属。

功能规划见 [ROADMAP](Docs/ROADMAP.md)，发布流程见 [RELEASING](Docs/RELEASING.md)。
