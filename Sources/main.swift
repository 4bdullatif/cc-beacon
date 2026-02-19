import AppKit
import Foundation

// MARK: - Config

struct Config: Decodable {
    struct Sounds: Decodable {
        let permission: String?
        let feedback: String?
        let done: String?
        let info: String?
    }
    let theme: String?
    let sounds: Sounds?
    let duration: Double?

    var isDark: Bool {
        return (theme ?? "dark").lowercased() != "light"
    }
}

let configPath = NSString(string: "~/.config/ccbeacon.conf").expandingTildeInPath

func loadConfig() -> Config? {
    guard FileManager.default.fileExists(atPath: configPath),
          let data = FileManager.default.contents(atPath: configPath) else {
        return nil
    }
    return try? JSONDecoder().decode(Config.self, from: data)
}

// MARK: - Models

enum NotificationType: String {
    case permission = "permission"
    case feedback = "feedback"
    case done = "done"
    case info = "info"

    var color: NSColor {
        switch self {
        case .permission: return NSColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1.0)
        case .feedback:   return NSColor(red: 0.40, green: 0.65, blue: 1.0, alpha: 1.0)
        case .done:       return NSColor(red: 0.55, green: 0.87, blue: 0.40, alpha: 1.0)
        case .info:       return NSColor(red: 0.75, green: 0.75, blue: 0.80, alpha: 1.0)
        }
    }

    var icon: String {
        switch self {
        case .permission: return "⏸"
        case .feedback:   return "💬"
        case .done:       return "✓"
        case .info:       return "●"
        }
    }

    var defaultTitle: String {
        switch self {
        case .permission: return "Permission Required"
        case .feedback:   return "Waiting for Input"
        case .done:       return "Task Complete"
        case .info:       return "cc-beacon"
        }
    }

    func sound(from config: Config?) -> String? {
        guard let s = config?.sounds else { return nil }
        switch self {
        case .permission: return s.permission
        case .feedback:   return s.feedback
        case .done:       return s.done
        case .info:       return s.info
        }
    }
}

// Claude Code hook JSON schema
struct HookInput: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let message: String?
    let notification_type: String?
    let title: String?
    let transcript_path: String?
    let cwd: String?
    let stop_hook_active: Bool?
    let permission_mode: String?
}

// MARK: - Transcript Reader

struct TranscriptReader {
    static func lastAssistantMessage(from path: String) -> String? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath),
              let data = FileManager.default.contents(atPath: expandedPath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            guard let msg = obj["message"] as? [String: Any],
                  let role = msg["role"] as? String, role == "assistant",
                  let content = msg["content"] as? [[String: Any]] else {
                continue
            }

            for block in content {
                if let type = block["type"] as? String, type == "text",
                   let text = block["text"] as? String {
                    let clean = text
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if clean.count > 120 {
                        return String(clean.prefix(117)) + "..."
                    }
                    return clean
                }
            }
        }
        return nil
    }
}

// MARK: - Notification Window

class NotificationPanel: NSPanel {
    init(type: NotificationType, title: String, message: String, project: String?, duration: TimeInterval, dark: Bool) {
        let panelWidth: CGFloat = 340
        let hasProject = project != nil && !project!.isEmpty
        let panelHeight: CGFloat = hasProject ? 82 : 68

        guard let screen = NSScreen.main else {
            super.init(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            return
        }

        let f = screen.visibleFrame
        super.init(
            contentRect: NSRect(x: f.maxX - panelWidth - 16, y: f.maxY - panelHeight - 16,
                                width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        // Theme colors
        let titleColor: NSColor
        let msgColor: NSColor
        let projColor: NSColor
        let borderColor: NSColor
        let bgMaterial: NSVisualEffectView.Material

        if dark {
            titleColor = NSColor.white.withAlphaComponent(0.95)
            msgColor = NSColor.white.withAlphaComponent(0.50)
            projColor = NSColor.white.withAlphaComponent(0.30)
            borderColor = NSColor.white.withAlphaComponent(0.08)
            bgMaterial = .hudWindow
        } else {
            titleColor = NSColor.black.withAlphaComponent(0.85)
            msgColor = NSColor.black.withAlphaComponent(0.45)
            projColor = NSColor.black.withAlphaComponent(0.25)
            borderColor = NSColor.black.withAlphaComponent(0.08)
            bgMaterial = .sheet
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        let bg = NSVisualEffectView(frame: container.bounds)
        bg.material = bgMaterial
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = borderColor.cgColor
        container.addSubview(bg)

        let strip = NSView(frame: NSRect(x: 0, y: 8, width: 3, height: panelHeight - 16))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = type.color.cgColor
        strip.layer?.cornerRadius = 1.5
        container.addSubview(strip)

        let icon = NSTextField(labelWithString: type.icon)
        icon.font = NSFont.systemFont(ofSize: 18)
        icon.frame = NSRect(x: 14, y: panelHeight - 34, width: 26, height: 26)
        icon.alignment = .center
        container.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = titleColor
        titleLabel.frame = NSRect(x: 44, y: panelHeight - 28, width: panelWidth - 60, height: 16)
        titleLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(titleLabel)

        let msgLabel = NSTextField(labelWithString: message)
        msgLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        msgLabel.textColor = msgColor
        msgLabel.frame = NSRect(x: 44, y: panelHeight - 46, width: panelWidth - 60, height: 14)
        msgLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(msgLabel)

        if hasProject {
            let projLabel = NSTextField(labelWithString: "📁 \(project!)")
            projLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            projLabel.textColor = projColor
            projLabel.frame = NSRect(x: 44, y: 8, width: panelWidth - 60, height: 14)
            projLabel.lineBreakMode = .byTruncatingTail
            container.addSubview(projLabel)
        }

        self.contentView = container

        self.alphaValue = 0
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.animator().alphaValue = 0
            }, completionHandler: {
                self?.close()
                NSApp.terminate(nil)
            })
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotificationPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let config = loadConfig()

        // Parse CLI flags
        var cliType: NotificationType? = nil
        var cliTitle: String? = nil
        var cliMessage: String? = nil
        var cliDuration: TimeInterval? = nil
        var cliSound: String? = nil

        var i = 1
        while i < args.count {
            switch args[i] {
            case "-t", "--type":
                if i + 1 < args.count { cliType = NotificationType(rawValue: args[i + 1]); i += 1 }
            case "-T", "--title":
                if i + 1 < args.count { cliTitle = args[i + 1]; i += 1 }
            case "-m", "--message":
                if i + 1 < args.count { cliMessage = args[i + 1]; i += 1 }
            case "-d", "--duration":
                if i + 1 < args.count { cliDuration = Double(args[i + 1]); i += 1 }
            case "-s", "--sound":
                if i + 1 < args.count { cliSound = args[i + 1]; i += 1 }
            case "-h", "--help":
                printUsage(); exit(0)
            default: break
            }
            i += 1
        }

        // Read stdin JSON (Claude Code hook input)
        var hookInput: HookInput? = nil
        if isatty(STDIN_FILENO) == 0 {
            if let data = try? FileHandle.standardInput.availableData,
               !data.isEmpty {
                hookInput = try? JSONDecoder().decode(HookInput.self, from: data)
            }
        }

        // Resolve type
        let type: NotificationType
        if let t = cliType {
            type = t
        } else if let input = hookInput {
            switch input.hook_event_name {
            case "Notification":
                switch input.notification_type {
                case "permission_prompt": type = .permission
                case "idle_prompt":       type = .feedback
                default:                  type = .info
                }
            case "Stop", "SubagentStop":
                type = .done
            default:
                type = .info
            }
        } else {
            type = .info
        }

        // Resolve message
        let message: String
        if let m = cliMessage {
            message = m
        } else if let input = hookInput {
            if let m = input.message, !m.isEmpty {
                message = m
            } else if let tp = input.transcript_path,
                      let summary = TranscriptReader.lastAssistantMessage(from: tp) {
                message = summary
            } else {
                message = type == .done ? "Finished" : "Claude Code needs your attention"
            }
        } else {
            message = "Claude Code needs your attention"
        }

        // Resolve project
        let project: String?
        if let cwd = hookInput?.cwd {
            project = URL(fileURLWithPath: cwd).lastPathComponent
        } else if let dir = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] {
            project = URL(fileURLWithPath: dir).lastPathComponent
        } else {
            project = nil
        }

        let title = cliTitle ?? type.defaultTitle
        let duration = cliDuration ?? config?.duration ?? 4.0

        // Sound: CLI flag > config file > none
        let soundName = cliSound ?? type.sound(from: config)
        if let s = soundName, let ns = NSSound(named: NSSound.Name(s)) { ns.play() }

        // HUD
        let dark = config?.isDark ?? true
        panel = NotificationPanel(type: type, title: title, message: message, project: project, duration: duration, dark: dark)
    }
}

// MARK: - Usage

func printUsage() {
    let configExists = FileManager.default.fileExists(atPath: configPath)
    print("""
    cc-beacon — floating notifications for Claude Code

    USAGE:
      cc-beacon [OPTIONS]              Direct notification
      <hook-json> | cc-beacon          Pipe from Claude Code hook

    OPTIONS:
      -t, --type <TYPE>       permission | feedback | done | info  (auto from hook)
      -T, --title <TITLE>     Override title
      -m, --message <MSG>     Override message
      -d, --duration <SECS>   Auto-dismiss seconds                 (default: 4)
      -s, --sound <NAME>      macOS sound (overrides config)
      -h, --help              Show this help

    CONFIG: \(configPath) [\(configExists ? "found" : "not found")]
      theme, sounds per type, duration — see ccbeacon.conf

    AUTO-DETECTION (from hook JSON on stdin):
      Notification event  → type from notification_type, message from message field
      Stop event          → type=done, message from last assistant line in transcript
      Project name        → from cwd field

    EXAMPLES:
      cc-beacon -t done -m "Build passed" -s Glass
      echo '{"hook_event_name":"Stop","cwd":"/path/to/project"}' | cc-beacon
    """)
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
