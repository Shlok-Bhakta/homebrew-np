import AppKit
import CoreGraphics

/// Buzzes on the band for an agent (Copilot) that finished, asks something, or failed: `np-appwatch
/// notify <kind>` hands it to the running watcher (it holds the dongle's link), which sends
/// `buzz <kind>` unless you're already looking at that app.
enum Alert: String, CaseIterable {
    case done, question, error

    static let notification = Notification.Name("io.github.shlok-bhakta.np-appwatch.alert")
}

enum AlertGate {
    /// The app the alert is about is in front and the Mac was used this recently: you're on it.
    static let lookingWithin: TimeInterval = 30
    /// The same kind again this soon is the same news (a plugin and personal hooks may both fire).
    static let repeatWithin: TimeInterval = 4

    static var lastSent: [Alert: Date] = [:]

    /// Only hooks are held back as repeats: each buzz asked for by hand (`notify`) goes.
    static func shouldBuzz(_ alert: Alert, app: String?, fromHook: Bool) -> (Bool, String) {
        if fromHook {
            if let last = lastSent[alert], Date().timeIntervalSince(last) < repeatWithin { return (false, "a repeat") }
            // A turn that asked a question also ends: the question's buzz says it all.
            if alert == .done, let asked = lastSent[.question], Date().timeIntervalSince(asked) < repeatWithin { return (false, "the question's") }
        }
        if let app, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle < lookingWithin { return (false, "\(app) is in front and in use") }
        }
        if fromHook { lastSent[alert] = Date() }
        return (true, "")
    }

    static func forget(_ alert: Alert) { lastSent[alert] = nil }
}

/// Where the running watcher leaves its process id, so `notify` knows it's there.
enum WatcherFile {
    static var url: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("io.github.shlok-bhakta.np-appwatch/watcher.pid")
    }

    static func claim() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(getpid()).write(to: url, atomically: true, encoding: .utf8)
    }

    static var running: Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pid != getpid() && kill(pid, 0) == 0
    }
}

/// `np-appwatch notify <kind> [--app <bundle id>]`: through the watcher, or straight to the dongle
/// when it isn't running.
func notify(_ alert: Alert, app: String?, fromHook: Bool = false) -> Never {
    if WatcherFile.running {
        var info: [String: String] = ["kind": alert.rawValue]
        if let app { info["app"] = app }
        if fromHook { info["hook"] = "1" }
        DistributedNotificationCenter.default().postNotificationName(Alert.notification, object: nil, userInfo: info, deliverImmediately: true)
        exit(0)
    }
    once { link in
        link.send("buzz \(alert.rawValue)") { error in
            if let error { FileHandle.standardError.write(Data("np-appwatch: \(error.localizedDescription)\n".utf8)); exit(1) }
            exit(0)
        }
    }
}
