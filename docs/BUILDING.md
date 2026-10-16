# 构建与发行

`src/app` 包含可阅读的 AutoHotkey 脚本与 C# 语音关闭辅助程序；`src/host` 是启动程序与按用户安装/卸载程序。

1. 在 Windows x64 的获准开发环境检出仓库。
2. 执行 `scripts/Build.ps1`。脚本验证固定依赖，使用系统 .NET Framework 的 64 位 `csc.exe` 编译，不需要 NuGet。项目根目录必须已有获批准的 `LICENSE`，否则拒绝公开发行构建。本地审查可显式用 `-AllowLicensePending`，生成带 `-draft` 名称的包。
3. 执行 `scripts/Test.ps1`。只跑自动化逻辑时使用 `-UnitOnly`。
4. 审查 `out` 的资产，确认测试结果、系统适配与隐私扫描。二进制包内的第三方对应源码不可删除。
5. 创建版本标签前更新 CHANGELOG 和 Release 说明。`v*` 标签工作流会构建、测试并创建同名 Release；不会修改已存在的 Release。需要仓库默认的 `GITHUB_TOKEN` 的 `contents: write`，不会创建长期凭证。

`Build.ps1` 使用固定的 AutoHotkey 2.0.30 发布文件与 SHA-256。首次下载保持正常 HTTPS 证书验证；离线环境可把官方文件放入 `.cache`，仍会验证摘要。没有自动接受新版本或忽略校验的选项。

“可复现构建”在这里指：源码、依赖、命令和产物组成均已记录，可以重新构建可用发行包。系统 C# 编译器的版本、PE 时间戳与 ZIP 元数据可能影响二进制字节；本版没有声称不同机器构建出完全相同的 SHA-256。

安装包为自带 ZIP 资源的 C# 程序，按用户解压，不更改 .ahk 文件关联，不注册服务、不调用第三方安装器、不请求管理员权限。静默验证选项为 `--silent --isolated --target <空目录>`；`--isolated` 跳过真实开始菜单和启动目录。仅测试时传入 `WIN_VOICE_HOTKEY_DATA_DIR` 把数据限制在临时配置目录。

卸载只应处理带本项目安装标记的目录。命令行 `WinVoiceHotkey.exe --stop` 使用窗口所属 PID 和随机实例属性确认目标后发出退出消息；不会扫描后终止其他映射程序。
