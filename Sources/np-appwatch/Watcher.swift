import AppKit

/// Tells the dongle the bundle id of the app in front, whenever it changes and whenever the
/// dongle (re)connects. The dongle picks the profile (the `apps` of its profiles).
final class Watcher {
    let link = DongleLink()
    var onChange: (() -> Void)?

    /// The app in front.
    private(set) var front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    private(set) var paused = false
    /// What the dongle last acknowledged (nil: nothing yet on this connection).
    private var sent: String?
    private var sending = false

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            front = app
            onChange?()
            push()
        }
        link.onReady = { [weak self] in
            self?.sent = nil
            self?.push()
        }
        link.onChange = { [weak self] in self?.onChange?() }
        DistributedNotificationCenter.default().addObserver(forName: Alert.notification, object: nil, queue: .main) { [weak self] note in
            guard let self, let kind = note.userInfo?["kind"] as? String, let alert = Alert(rawValue: kind) else { return }
            buzz(alert, app: note.userInfo?["app"] as? String, event: note.userInfo?["event"] as? String)
        }
        WatcherFile.claim()
    }

    /// An agent's news on the band (`np-appwatch notify`), unless you're already looking at it.
    func buzz(_ alert: Alert, app: String?, event: String?) {
        let (go, why) = AlertGate.shouldBuzz(alert, app: app, event: event)
        guard go else { return log("Not buzzing \(alert.rawValue): \(why)") }
        link.send("buzz \(alert.rawValue)") { error in
            if error != nil { AlertGate.forget(event) }  // didn't reach the band: the next one may go
            log(error.map { "Couldn't buzz \(alert.rawValue): \($0.localizedDescription)" } ?? "Buzzed: \(alert.rawValue)")
        }
    }

    /// What the dongle should hear: the front app's bundle id, or "" (no app) while paused.
    private var wanted: String { paused ? "" : front?.bundleIdentifier ?? "" }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        log(paused ? "Paused: the Mac goes back to its own profile" : "Resumed")
        onChange?()
        push()
    }

    /// One write at a time; the newest app wins.
    private func push() {
        let app = wanted
        guard link.state == .ready, !sending, app != sent else { return }
        sending = true
        link.send(app.isEmpty ? "app" : "app \(app)") { [weak self] error in
            guard let self else { return }
            sending = false
            if let error {
                log("Couldn't tell the dongle about \(app.isEmpty ? "no app" : app): \(error.localizedDescription)")
            } else {
                sent = app
                log(app.isEmpty ? "Told the dongle: no app" : "Told the dongle: \(app)")
                push()
            }
        }
    }

    /// Before quitting: the Mac goes back to its own profile.
    func letGo(then done: @escaping () -> Void) {
        guard link.state == .ready, sent != "" else { return done() }
        var finished = false
        let finish = { if !finished { finished = true; done() } }
        link.send("app") { _ in finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: finish)
    }
}
