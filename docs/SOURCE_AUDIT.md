# 发布来源与边界

运行入口 WinHGate.ahk 使用 RuntimeState、AppPaths、KeyCatalog、SupportDiagnostics、InputRouter、KeyboardObserver（含 MouseObserver）、KeySettings（含 CloseBindings）、GlobalRuntime 与 CloseBrokerRuntime（含 PanelWindowTracker）。C# 代理由 VoicePanelCore/VoicePanelBroker 构建，宿主为 Launcher/Installer。保留的测试 fixture 不进入正常应用入口。

项目来自所有者的本地 Win+H 原型，不包含 CapsWriter ASR 模型、Python 客户端/服务器、旧焦点适配器或第三方 UIA-v2 代码。项目所有者已授权项目专用代码采用原仓库 MIT 许可；没有把这一授权扩展到第三方解释器。

AutoHotkey 2.0.30 未修改，固定运行时摘要、完整许可和对应上游源码按原声明保留。系统 Windows/.NET 二进制不随包分发。具体来源、许可和摘要见 THIRD_PARTY_NOTICES.md、dependencies.lock.json 与 third-party。

公开仓库按源码、脚本、测试、文档和声明清单组装，不复制日常安装目录或整个工作目录。排除真实配置、状态、日志、备份、录音、凭据、本机路径及个人报告。测试公开结果只含脱敏计数和布尔摘要。默认不保存触发历史；支持诊断需显式启用且不自动上传。

0.1.3 汇总已经使用的本地修复、状态持久化及生命周期核验，仅改公开版本元数据和文档，不借发布新增系统设置或更改日常个人绑定。检查脚本与人工审查互相补充，不把模式扫描当作安全认证。
0.1.4新增DictationLanguagePolicy/Runtime（原目标zh-CN请求、确认与取消）及BrokerIdlePolicy（有确认和活动保护的空闲租约）；GlobalRuntime/CloseBrokerRuntime管理按需代理队列、token/实例生命周期和恢复。WinHGate不再为正常待机预热代理；Smoke测试显式启动它。新增语言、租约及真实代理无输入夹具均是合成测试源码，不包含用户数据。正式发布与本机已验证功能实现相同，仅调整发行元数据及说明；不引入新的识别引擎或后台服务。