import AppKit

let version = "0.2.2"

let usage = """
np-appwatch \(version): switches the Neural Band dongle's gesture profile to match the app in front.

  np-appwatch              Watch the app in front (a menu bar item; `brew services start np-appwatch` runs it at login)
  np-appwatch --no-menu    The same, without the menu bar item
  np-appwatch front        Print the bundle id of the app in front, to put in a profile's "apps"
  np-appwatch apps         Print the bundle ids of every running app
  np-appwatch send <id>    Tell the dongle once that <id> is in front ("" for no app), then exit
  np-appwatch status       Print the dongle's status (JSON), then exit
  np-appwatch notify done|question|error [--app <id>]
                           Buzz the band (skipped while app <id> is in front and in use)
  np-appwatch copilot install|uninstall|check
                           Buzz when GitHub Copilot finishes, asks something or fails (its hooks)
  np-appwatch hook <event> What Copilot's hooks run (the event's JSON on stdin)
"""

setvbuf(stdout, nil, _IOLBF, 0)
var signalSources: [DispatchSourceSignal] = []

func log(_ message: String) {
    let time = Date().formatted(.iso8601.time(includingFractionalSeconds: false).dateTimeSeparator(.space))
    print("\(time) \(message)")
}

/// Runs `body` once the dongle is connected, and exits if it isn't within 15 s.
func once(_ body: @escaping (DongleLink) -> Void) -> Never {
    let link = DongleLink()
    link.onReady = { body(link) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        FileHandle.standardError.write(Data("np-appwatch: no dongle (\(link.state.title))\n".utf8))
        exit(1)
    }
    withExtendedLifetime(link) { RunLoop.main.run() }
    exit(0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--version", "-v":
    print("np-appwatch \(version)")
case "--help", "-h", "help":
    print(usage)
case "front":
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
case "apps":
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    for app in apps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
        print("\(app.bundleIdentifier ?? "?")\t\(app.localizedName ?? "")")
    }
case "send" where arguments.count == 2:
    let app = arguments[1]
    once { link in
        link.send(app.isEmpty ? "app" : "app \(app)") { error in
            if let error { FileHandle.standardError.write(Data("np-appwatch: \(error.localizedDescription)\n".utf8)); exit(1) }
            exit(0)
        }
    }
case "notify" where arguments.count >= 2:
    guard let alert = Alert(rawValue: arguments[1]) else {
        FileHandle.standardError.write(Data("np-appwatch: notify done|question|error\n".utf8))
        exit(64)
    }
    let app = arguments.firstIndex(of: "--app").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    notify(alert, app: app)
case "hook" where arguments.count == 2:
    Copilot.hook(arguments[1])
case "copilot" where arguments.count == 2 && arguments[1] == "install":
    Copilot.install()
case "copilot" where arguments.count == 2 && arguments[1] == "check":
    Copilot.check()
case "copilot" where arguments.count == 2 && arguments[1] == "uninstall":
    Copilot.uninstall()
case "status":
    once { link in
        link.readStatus { text in
            guard let text else { FileHandle.standardError.write(Data("np-appwatch: couldn't read the status\n".utf8)); exit(1) }
            print(text)
            exit(0)
        }
    }
case nil, "--no-menu":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let watcher = Watcher()
    let menuBar = arguments.first == "--no-menu" ? nil : MenuBar(watcher: watcher)
    watcher.onChange = { menuBar?.refresh() }
    log("np-appwatch \(version) watching (in front: \(watcher.front?.bundleIdentifier ?? "nothing"))")
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { watcher.letGo { exit(0) } }
        source.resume()
        signalSources.append(source)
    }
    app.run()
default:
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}
