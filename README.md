# NotchAgent

把 MacBook 刘海变成 AI Agent 实时控制面板。

开源、本地优先、原生 macOS 应用。监控你的 AI 编程助手，不离开当前工作流。

## 功能

- **Notch 面板** — 在刘海区域显示 Agent 状态，鼠标悬停展开详情
- **多 Agent 支持** — Claude Code、Codex、Gemini CLI、Kiro CLI 同时监控
- **零配置** — 首次启动自动注入 hooks，自动备份原始配置
- **实时状态** — 运行中(蓝)、等待审批(橙)、已完成(绿) 颜色区分
- **Session 管理** — 自动创建、状态跟踪、5 分钟后自动清理
- **通知音效** — 13 种系统音效可选，可静音
- **外接显示器兼容** — 有刘海在刘海区域，无刘海在菜单栏下方
- **纯 Swift 原生** — SwiftUI + AppKit，非 Electron，内存占用低
- **本地通信** — Unix Socket，数据不出本机

## 支持的 AI 工具

| 工具 | 配置文件 | 事件 |
|------|---------|------|
| Claude Code | `~/.claude/settings.json` | SessionStart/End, PreToolUse, PostToolUse, PermissionRequest, Stop 等 13 个事件 |
| Codex | `~/.codex/config.toml` + `hooks.json` | SessionStart, UserPromptSubmit, PostToolUse, Stop |
| Gemini CLI | `~/.gemini/settings.json` | SessionStart/End, BeforeAgent/AfterAgent, BeforeTool/AfterTool |
| Kiro CLI | `~/.kiro/agents/default.json` | agentSpawn, userPromptSubmit, postToolUse, stop |

## 快速开始

### 方式一：从源码构建 .app

```bash
git clone <repo>
cd NotchAgent
bash Scripts/package-app.sh
cp -R output/NotchAgent.app ~/Applications/
open ~/Applications/NotchAgent.app
```

首次打开：右键 → 打开 → 打开（绕过 Gatekeeper）

### 方式二：Xcode 开发调试

```bash
cd NotchAgent
open Package.swift
# Xcode 中选 NotchAgent scheme → Cmd+R
```

## 架构

```
NotchAgent/
├── Sources/
│   ├── NotchAgent/              # 主应用
│   │   ├── NotchAgentApp.swift  # 入口 + AppDelegate
│   │   ├── Models/              # AgentSession, SocketMessage
│   │   ├── Services/            # SocketServer, SessionManager, HookConfigurator, SoundManager
│   │   └── Views/               # NotchWindow, NotchContentView, NotchShape, ApprovalView, SettingsView
│   └── NotchBridge/             # 轻量 CLI，hook 调用 → socket 转发
│       └── main.swift
├── Scripts/
│   ├── package-app.sh           # 打包成 .app
│   ├── install_kiro_hooks.sh    # Kiro CLI hook 安装
│   └── test_states.py           # 模拟测试数据
└── Resources/
    └── AppIcon.icns
```

## 工作原理

```
AI 工具 (Claude/Codex/Gemini/Kiro)
  ↓ hook 事件 (stdin JSON)
NotchBridge CLI
  ↓ Unix Socket
SocketServer (in-app)
  ↓ 状态更新
SessionManager → NotchContentView
  ↓ 用户看到
刘海面板 UI
```

- Hook 失败不影响 AI 工具正常运行（fail-open）
- 所有通信通过本地 Unix Socket，无网络请求
- 配置注入前自动备份到 `~/.notch-agent/backups/`

## 设置

点击展开面板右上角 ⚙️ 图标打开设置：

- **通用** — 开机自启动
- **声音** — 音效开关、音效选择
- **Hooks** — 查看各 CLI 的 hook 配置状态
- **关于** — 版本信息、退出应用

## 系统要求

- macOS 14+
- Apple Silicon 或 Intel Mac
- Swift 5.9+（构建需要）

## License

MIT
