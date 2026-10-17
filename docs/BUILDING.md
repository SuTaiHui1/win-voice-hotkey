# 构建与发布

在 Windows x64、Windows PowerShell 5.1+ 或 PowerShell 7 下执行 scripts/Build.ps1，再执行 scripts/Test.ps1 -UnitOnly。使用系统 .NET Framework 4.x 的 64 位 C# 编译器，不需要 NuGet、npm 或额外运行时。

构建要求根目录 LICENSE。AutoHotkey 2.0.30 的运行 ZIP、解释器与对应源码均由 dependencies.lock.json 固定 SHA-256；首次通过正常 HTTPS 从固定上游 URL 下载，缓存仍需校验。二进制包保留完整许可及对应上游源码，不重新许可解释器。

out 已存在时构建拒绝覆盖。先保留旧资产，再仅处理确认过的生成目录。安装程序嵌入同次便携 ZIP；输出 setup.exe、portable.zip、source.zip、SHA256SUMS.txt。源码包只选源码、脚本、测试、文档、声明等清单，不含 .git、依赖缓存、out、个人配置或运行日志。

版本字符串位于 Build.ps1、WinHGate.ahk 和 Installer.cs；发布前同步更新 README、CHANGELOG、RELEASE_NOTES 与工作流标签保护。不要覆盖旧标签或 Release 资产。

GitHub Actions 对主分支和标签构建、扫描并测试。标签发布步骤使用仓库现有 GITHUB_TOKEN 的 contents:write，只发布本次版本且拒绝已存在 Release；不创建长期凭据。

源码、固定依赖和命令可重复执行。C# 编译器版本、PE 时间戳和 ZIP 元数据会影响字节，不承诺不同机器产物 SHA-256 完全相同。下载文件应与同一 Release 的 SHA256SUMS.txt 比较。

纯检查在专用不可见测试桌面运行，不切换用户屏幕。完整正常模式输入钩子/安装门禁回归受隔离环境账号保护；不要在日常主机绕过条件或为了测试启用系统功能。默认发布工作只跑 -UnitOnly。

静默安装检查使用 --silent --isolated --target <专用空目录>，跳过真实开始菜单和自启写入；测试可用进程级 WIN_VOICE_HOTKEY_DATA_DIR 指向专用测试数据目录。--smoke-test 禁用钩子且使用隔离自启位置，仍会创建应用自身设置窗口与代理。已知状态陈旧边界和升级前退出注意事项见 README 与 TESTING.md。