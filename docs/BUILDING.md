# 构建与发布0.1.4

需要Windows x64、PowerShell 5.1+或7，以及系统.NET Framework 4.x的64位csc.exe。无NuGet/npm依赖。`src/app`是AHK运行逻辑及C# UIA代理，`src/host`是启动器/安装卸载程序。

```powershell
.\scripts\Check-PublicContent.ps1
.\scripts\Build.ps1
.\scripts\Test.ps1 -UnitOnly
.\scripts\Test-Lifecycle.ps1
.\scripts\Test-BrokerLifecycle.ps1
.\scripts\Test-Packages.ps1
```

后两项是Default桌面上的无输入本机验证，不是云CI真实语音测试。代理fixture使用独立隐蔽文本控件/空候选与最终唤醒测试回调，不安装全局输入钩子、不录音。包测试在out独立目录安装/升级/卸载，不使用用户日常目录或个人配置。不要为测试绕过执行策略、提权运行实际听写或启用系统功能；权限受限时报告未验证项。

`Build.ps1`固定AutoHotkey2.0.30二进制和对应源码ZIP的SHA-256，首次从官方HTTPS源下载并校验，也可把原文件放入.cache。项目根LICENSE缺失时拒绝构建。out已存在会停止：请保留旧产物并换到干净检出或明确归档该生成目录再构建，不要覆盖证据。

构建输出：

- win-voice-hotkey-0.1.4-windows-x64-setup.exe
- win-voice-hotkey-0.1.4-windows-x64-portable.zip
- win-voice-hotkey-0.1.4-source.zip
- SHA256SUMS.txt

二进制包附AutoHotkey许可和对应上游源码；源码包仅取src/scripts/tests/docs/third-party/.github和根项目文本。不得加入.cache、out、个人配置、原始状态/日志、私有报告、机器路径或凭据。公开内容模式扫描只补充人工差异和归档清单检查，不是安全认证。

安装验证入口是 `setup.exe --silent --isolated --target "<空目录或带项目标记的隔离安装目录>"`；测试同时给子进程设置独立WIN_VOICE_HOTKEY_DATA_DIR。`--isolated`不创建真实桌面/开始菜单入口。卸载使用同setup的 `--silent --isolated --uninstall --target "..."`。不能对无项目标记的非空目录执行覆盖或删除。

带真实钩子的旧退出/安装停止回归仍只允许Windows Sandbox的WDAGUtilityAccount：`Test.ps1`不带-UnitOnly时按守卫执行，不可在日常宿主绕过。按需待机的CloseBrokerPID=0/CloseBrokerReady=0是合法就绪，测试与诊断应同时看BrokerMode/BrokerLifecycleReady。

发布前核对GitHub实际分支与版本，更新Build.ps1、RuntimeState版本/发行标记、安装标记、工作流标签守卫、README、CHANGELOG、Release notes及TEST_RESULTS。先提交并推送main，确认该提交CI通过，再推送新的v0.1.4标签。标签工作流重新构建并创建正式Release，拒绝覆盖已存在Release/资产；本次不改历史提交或标签。

CI只发布4个干净发行文件，不发布原始测试证据。发布后核对标签目标提交和CI结果，匿名重新下载Release资产，按该次SHA256SUMS校验并验证实际下载包。不同机器/编译器版本、PE时间戳和ZIP元数据可能使本机构建与CI的SHA不同；以同一次Release资产清单为准，不宣称字节级可复现。