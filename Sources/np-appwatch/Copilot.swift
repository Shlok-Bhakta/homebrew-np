import Foundation

/// The GitHub Copilot app (and Copilot CLI) run hooks on an agent's events. A small plugin (and
/// personal hooks, for the CLI) run `np-appwatch hook <event>`, which picks the buzz.
enum Copilot {
    static let app = "com.github.githubapp"
    static let pluginName = "np-band"

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("np-appwatch")
    }

    static var pluginDirectory: URL { supportDirectory.appendingPathComponent("copilot-plugin") }

    static var personalHooks: URL {
        let home = ProcessInfo.processInfo.environment["COPILOT_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot")
        return home.appendingPathComponent("hooks/np-band.json")
    }

    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/np-appwatch/copilot-hooks.log")
    }

    /// The stable path Homebrew links (survives upgrades), else this binary's own.
    static var command: String {
        for prefix in ["/opt/homebrew", "/usr/local"] where FileManager.default.isExecutableFile(atPath: "\(prefix)/bin/np-appwatch") {
            return "\(prefix)/bin/np-appwatch"
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    /// Tools an agent asks you something with (Copilot's is `ask_user`). Hook matchers must match
    /// the whole name, so this is a full-name pattern.
    static let askingTools = "ask_user|ask|Ask.*|.*[Qq]uestion.*|.*[Ee]licit.*"

    static var hooksJSON: String {
        func hook(_ event: String, matcher: String? = nil) -> String {
            let match = matcher.map { #", "matcher": "\#($0)""# } ?? ""
            return #"[{ "type": "command", "bash": "'\#(command)' hook \#(event)", "timeoutSec": 10\#(match) }]"#
        }
        return """
        {
          "version": 1,
          "hooks": {
            "agentStop": \(hook("agentStop")),
            "notification": \(hook("notification")),
            "preToolUse": \(hook("preToolUse", matcher: askingTools)),
            "errorOccurred": \(hook("errorOccurred"))
          }
        }

        """
    }

    static let pluginJSON = """
    {
      "name": "np-band",
      "description": "Buzzes the Meta Neural Band (through the NP Band Remote dongle and np-appwatch) when an agent finishes, asks you something, or fails.",
      "version": "\(version)",
      "hooks": "hooks.json"
    }

    """

    // MARK: install

    static func install() -> Never {
        do {
            try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
            try pluginJSON.write(to: pluginDirectory.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
            try hooksJSON.write(to: pluginDirectory.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: personalHooks.deletingLastPathComponent(), withIntermediateDirectories: true)
            try hooksJSON.write(to: personalHooks, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("np-appwatch: couldn't write the Copilot hooks: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        print("Personal hooks (Copilot CLI): \(personalHooks.path)")
        print("Plugin: \(pluginDirectory.path)")
        if let copilot = findCopilot() {
            _ = run(copilot, ["plugin", "uninstall", pluginName])  // an older copy, if any
            let status = run(copilot, ["plugin", "install", pluginDirectory.path])
            print(status == 0 ? "Installed the np-band plugin with \(copilot)." : "`copilot plugin install` failed (exit \(status)); see above.")
        } else {
            print("""
            No `copilot` command found, so the plugin isn't installed yet. Either install Copilot CLI
            (brew install copilot-cli) and run `np-appwatch copilot install` again, or add the plugin
            folder above in the Copilot app's plugin settings.
            """)
        }
        print("""

        Then restart the Copilot app. Each hook it runs is logged to:
          \(logFile.path)
        (tail -f that file while Copilot works to see what fires). Test the buzzes with
          np-appwatch notify done   ·   np-appwatch notify question   ·   np-appwatch notify error
        """)
        exit(0)
    }

    static func uninstall() -> Never {
        if let copilot = findCopilot() { _ = run(copilot, ["plugin", "uninstall", pluginName]) }
        try? FileManager.default.removeItem(at: personalHooks)
        try? FileManager.default.removeItem(at: pluginDirectory)
        print("Removed the np-band hooks.")
        exit(0)
    }

    /// `np-appwatch copilot check`: what's installed, and what Copilot has run lately.
    static func check() -> Never {
        func mark(_ ok: Bool) -> String { ok ? "yes" : "NO" }
        let files = FileManager.default
        print("np-appwatch \(version)")
        print("Watcher running (holds the dongle link): \(mark(WatcherFile.running))")
        print("Personal hooks (\(personalHooks.path)): \(mark(files.fileExists(atPath: personalHooks.path)))")
        print("Plugin folder (\(pluginDirectory.path)): \(mark(files.fileExists(atPath: pluginDirectory.path)))")
        if let copilot = findCopilot() {
            print("Copilot CLI: \(copilot); its plugins:")
            _ = run(copilot, ["plugin", "list"])
        } else {
            print("Copilot CLI: not found (the plugin is only installed if you added the folder in the app)")
        }
        let lines = ((try? String(contentsOf: logFile, encoding: .utf8)) ?? "").split(separator: "\n").suffix(15)
        if lines.isEmpty {
            print("\nNo hook has run yet: Copilot isn't running np-appwatch's hooks.")
        } else {
            print("\nThe last hooks Copilot ran (\(logFile.path)):")
            for line in lines { print("  " + String(line.prefix(300))) }
        }
        exit(0)
    }

    private static func findCopilot() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = path + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin"]
        return candidates.map { "\($0)/copilot" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: a hook firing

    /// `np-appwatch hook <event>`, with the event's JSON on stdin: logs it, picks a buzz, hands it
    /// to `notify`. Never blocks Copilot: no output, exit 0.
    static func hook(_ event: String) -> Never {
        let input = isatty(FileHandle.standardInput.fileDescriptor) == 0 ? FileHandle.standardInput.readDataToEndOfFile() : Data()
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let (alert, why) = decide(event, payload)
        record(event: event, input: input, decision: alert.map { "\($0.rawValue) (\(why))" } ?? "no buzz (\(why))")
        guard let alert else { exit(0) }
        notify(alert, app: Copilot.app)
    }

    static func decide(_ event: String, _ payload: [String: Any]) -> (Alert?, String) {
        func field(_ names: String...) -> Any? { names.lazy.compactMap { payload[$0] }.first }
        switch event {
        case "agentStop", "Stop":
            guard let path = field("transcriptPath", "transcript_path") as? String else { return (.done, "no transcript to read") }
            guard let text = lastAssistantText(path) else { return (.done, "no assistant text found") }
            return text.hasSuffix("?") ? (.question, "it ended on a question") : (.done, "the turn ended")
        case "notification", "Notification":
            let type = field("notification_type", "notificationType", "type") as? String ?? ""
            if ["permission_prompt", "elicitation_dialog"].contains(type) { return (.question, type) }
            return (nil, "notification \(type)")
        case "preToolUse", "PreToolUse":
            // Checked here too: a host that ignores the matcher would otherwise buzz on every tool.
            let tool = field("toolName", "tool_name") as? String ?? ""
            guard tool.range(of: "^(?:\(askingTools))$", options: .regularExpression) != nil else { return (nil, "tool \(tool)") }
            return (.question, "it asks with \(tool)")
        case "errorOccurred", "ErrorOccurred":
            return (.error, "an error")
        default:
            return (nil, "not an event that buzzes")
        }
    }

    /// The last thing the agent said, trimmed, from a transcript (JSON lines, read from the end).
    static func lastAssistantText(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else { continue }
            if let said = assistantText(in: object) { return said.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    /// Text in an object that looks like an assistant message (`role` or `type` "assistant"…).
    private static func assistantText(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            let role = (object["role"] as? String ?? object["type"] as? String ?? "").lowercased()
            if role.contains("assistant") {
                let text = strings(in: object["content"] ?? object["text"] ?? object["message"] ?? object["data"] as Any).joined(separator: "\n")
                if !text.isEmpty { return text }
            }
            for nested in object.values { if let found = assistantText(in: nested) { return found } }
        } else if let list = value as? [Any] {
            for item in list.reversed() { if let found = assistantText(in: item) { return found } }
        }
        return nil
    }

    private static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] { return list.flatMap(strings) }
        if let object = value as? [String: Any] {
            if let text = object["text"] as? String { return [text] }
            if let content = object["content"] { return strings(in: content) }
        }
        return []
    }

    private static func record(event: String, input: Data, decision: String) {
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let body = String(decoding: input.prefix(4096), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
        let line = "\(stamp) \(event) → \(decision) · \(body)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}
