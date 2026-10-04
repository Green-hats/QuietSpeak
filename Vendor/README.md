# 第三方源码与补丁

这份项目基于现有的 TS3 协议和音频库开发。QuietSpeak 新增的界面、业务、FFI 和音频设备桥接采用根目录 MIT 许可证；这里的第三方代码保留原作者、版权和许可。

| 源码 | 固定来源 | 许可 | 本地改动 |
| --- | --- | --- | --- |
| `tsclientlib/` | ReSpeak/tsclientlib，修订见 `UPSTREAM_REVISION` | MIT OR Apache-2.0 | 接收音频队列 |
| `tsclientlib/utils/tsproto-structs/declarations/` | 上游嵌入的 tsdeclarations | MIT OR Apache-2.0 | 无本地源码修改 |
| `audiopus_sys/` | crates.io audiopus_sys 0.2.2 | ISC | CMake 和部署版本配置 |
| `audiopus_sys/opus/` | audiopus_sys 包附带的 Opus 源码 | 见 `COPYING` 及 IPR 说明 | 编解码源码未修改 |

完整来源、固定修订和 crate 下载校验值见 [PROVENANCE.json](PROVENANCE.json)。未使用 Git 子模块：源码包和普通 clone 都包含构建所需的这些文件。

## 音频补丁

`patches/tsclientlib-audio.patch` 相对固定 tsclientlib 修订生成，修改 `tsclientlib/src/audio.rs`：

- 新说话者以 60ms 为初始起播缓冲目标。
- 起播前接收较早到达序号的乱序包。
- 统一每声道样本计数，修正序号回绕的缓冲计算。

QuietSpeak 自己的 `Core/src/audio.rs` 另外处理正常迟到/重复包和较大正向序号跳变恢复。这些桥接行为不属于第三方补丁。

`patches/audiopus-sys-build.patch` 相对 audiopus_sys 0.2.2 crate 中的 `build.rs` 生成，设置 CMake 4 兼容策略和 macOS 最低部署版本；没有修改 Opus 算法。

在相应的原始源码根目录，可用 `git apply --check 补丁路径` 检查补丁。更新上游后重新生成补丁并检查 `./check.sh`、`./test.sh` 和 `./build.sh`。

## 依赖声明

`Scripts/generate-notices.py` 从锁定的 Cargo 依赖源码生成完整声明和 `Docs/DEPENDENCIES.json`。部分 crate 的发布包未包含许可证文本，对应固定上游提交的文本保存在 `Docs/third-party-licenses/`，`index.json` 记录 URL 和 SHA-256。

请保留本目录中的许可证、版权和来源文件。生成声明时不能忽略缺少许可证的依赖。
