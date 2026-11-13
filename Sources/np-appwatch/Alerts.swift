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
    /// How long an event is remembered: the plugin's and the personal hooks' copies of one event
    /// both run, and it should buzz once. Different events buzz however close they come.
    static let sameEventWithin: TimeInterval = 30

    static var seen: [String: Date] = [:]

    /// `event`: what identifies the hook's event (nil for `notify` by hand, which always goes).
    static func shouldBuzz(_ alert: Alert, app: String?, event: String?) -> (Bool, String) {
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < sameEventWithin }
        if let event, seen[event] != nil { return (false, "the same event again (another copy of the hooks)") }
        if let app, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle < lookingWithin { return (false, "\(app) is in front and in use") }
        }
        if let event { seen[event] = now }
        return (true, "")
    }

    static func forget(_ event: String?) { if let event { seen[event] = nil } }
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
func notify(_ alert: Alert, app: String?, event: String? = nil) -> Never {
    if WatcherFile.running {
        var info: [String: String] = ["kind": alert.rawValue]
        if let app { info["app"] = app }
        if let event { info["event"] = event }
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
