# 发布流程

## 本地准备

1. 更新 `VERSION`、`Core/Cargo.toml`、`Core/Cargo.lock` 中本项目版本，以及 `Resources/Info.plist` 的短版本；增加 `CFBundleVersion`。
2. 更新 CHANGELOG、README 中的版本与 `Docs/RELEASE_NOTES.md`。
3. 执行 `./check.sh`、`./test.sh`、`./build.sh`。
4. 执行 `python3 Scripts/package-release.py`。

输出位于 `dist/releases/`：当前架构的 App zip、源码 zip、对应 `SHA256SUMS-架构.txt`。校验命令：

```bash
cd dist/releases
shasum -a 256 -c SHA256SUMS-arm64.txt
```

打包脚本先验证版本、签名、架构、macOS 最低版本和动态依赖，再生成归档。源码 ZIP 使用固定时间戳和规范文件权限；CI 只在 arm64 作业生成一次源码包，避免两个作业覆盖同名文件。不把 `work/`、`dist/`、`.git` 或证书放进源码包。

## GitHub 流程

只有在维护者决定发布并完成相应验收后，才推送与 VERSION 相符的 `v版本` 标签。

`release.yml` 调用双架构 CI，成功后创建 **Release 草稿**。维护者核对两个架构包、源码包、校验文件和发行说明，再手动发布草稿。

本地整理不会创建远端、推送标签或发布 GitHub Release。自动构建产物使用 ad-hoc 签名，Developer ID 签名与公证尚未接入。

公开仓库时还需启用 Issues、Private vulnerability reporting，并为 `main` 配置 CI 状态检查。先运行远端 CI，不能把本地通过当作 GitHub Actions 已通过。

Runner 标签依据 [GitHub 官方 runner-images](https://github.com/actions/runner-images)：`macos-15` 为 arm64，`macos-15-intel` 为 x86_64。使用固定标签并定期维护；Actions 使用固定提交号。
