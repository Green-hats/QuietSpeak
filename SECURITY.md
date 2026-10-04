# 安全问题

维护范围为最新开发预览版本。项目尚处于早期开发阶段，关注网络输入处理、FFI 内存所有权、第三方依赖及身份/密码保护。

请不要在公开 Issue 中贴出可利用的完整攻击步骤、服务器密码、身份密钥、证书或个人通信记录。

请通过 [Report a vulnerability](https://github.com/Green-hats/QuietSpeak/security/advisories/new) 私下报告。若入口暂不可用，可先提交不包含漏洞细节的联系请求。

报告请包括版本、系统环境、受影响模块、影响范围和最小复现。修复后会在 CHANGELOG 中记录相关更新；目前没有约定的响应时限。

收藏保存在 UserDefaults，身份和记住的密码保存在 macOS Keychain。CI 和自动测试不读取用户钥匙串、不启动真实麦克风、不默认连接公共服务器。
