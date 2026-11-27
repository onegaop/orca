# Orca 任务收件箱

macOS 26+ SwiftUI 菜单栏伴侣，在 Mini 本地查看 Orca Agent 状态。它不是 Orca 客户端或更新渠道，不创建工作区，也不管理 Agent。

- 状态：待处理（阻塞优先，然后等待输入）、进行中、已完成。
- 层级：项目 → 工作区 → Agent；Git 工作区用 Orca 的工作区标识归类，不按分支名称合并。
- 只在面板打开时读取。打开立即刷新，之后每 15 秒刷新，支持手动刷新。
- 数据源：Mini 现有 Orca 自带的 `agent list --environment local --json`；不调用 `agent read`、不保存或展示回复正文、不配置其他主机、不发任何通知。
- 启动入口：`~/Applications/Orca Inbox.app`。不配置登录启动。右键任务可复制会话 ID；目前只支持打开 Orca 主窗口，不跳转具体会话。
- 断线时保留本次面板上一次结果并明确标为旧数据；不把断线显示为没有任务。

本地重建安装：`./install.sh`（同时保留 `./install-mini.sh` 兼容入口）。测试：`swift test --disable-sandbox`（在外层沙盒中避免 SwiftPM 再请求不受支持的嵌套沙盒；没有外部依赖）。
