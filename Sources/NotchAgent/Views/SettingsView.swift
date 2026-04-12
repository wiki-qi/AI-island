import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("selectedSound") private var selectedSound = "Tink"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let availableSounds = ["Tink", "Glass", "Bottle", "Pop", "Purr", "Sosumi", "Basso", "Blow", "Frog", "Hero", "Morse", "Ping", "Submarine"]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape.fill") }
            soundTab
                .tabItem { Label("声音", systemImage: "speaker.wave.2.fill") }
            hookTab
                .tabItem { Label("Hooks", systemImage: "link") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle.fill") }
        }
        .frame(width: 450, height: 380)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sound

    private var soundTab: some View {
        Form {
            Section("通知音效") {
                Toggle("启用音效", isOn: $soundEnabled)
            }

            Section("选择音效") {
                List(availableSounds, id: \.self) { name in
                    Button {
                        selectedSound = name
                        NSSound(named: NSSound.Name(name))?.play()
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if name == selectedSound {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hooks

    private var hookTab: some View {
        Form {
            Section("Hook 状态") {
                hookRow("Claude Code", path: "~/.claude/settings.json")
                hookRow("Codex", path: "~/.codex/hooks.json")
                hookRow("Gemini CLI", path: "~/.gemini/settings.json")
                hookRow("Kiro CLI", path: "~/.kiro/agents/default.json")
            }

            Section {
                Button("重新配置所有 Hooks") {
                    HookConfigurator.configureAll()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hookRow(_ name: String, path: String) -> some View {
        let expandedPath = (path as NSString).expandingTildeInPath
        let installed = FileManager.default.fileExists(atPath: expandedPath)

        return HStack {
            Text(name)
            Spacer()
            if installed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                    Text("未安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("NotchAgent")
                .font(.title.bold())

            Text("Dynamic Island for your AI Agents")
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Divider()

            Button("退出 NotchAgent") {
                NSApp.terminate(nil)
            }
            .foregroundStyle(.red)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
}
