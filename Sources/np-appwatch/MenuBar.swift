import AppKit

/// The menu bar item: whether the dongle is connected, the app in front (and its bundle id, to
/// copy into a profile), pause and quit.
final class MenuBar: NSObject, NSMenuDelegate {
    private let watcher: Watcher
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(watcher: Watcher) {
        self.watcher = watcher
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    func refresh() {
        let symbol = watcher.link.state != .ready ? "hand.raised.slash" : watcher.paused ? "pause.circle" : "hand.raised"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NP App Watch")
        item.button?.toolTip = "NP App Watch: \(watcher.link.state.title)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(label("Dongle: \(watcher.link.state.title)"))
        if let front = watcher.front {
            menu.addItem(label("In front: \(front.localizedName ?? "?")"))
            if let id = front.bundleIdentifier {
                menu.addItem(action("Copy “\(id)”", #selector(copyBundleID(_:)), represented: id))
            }
        }
        menu.addItem(.separator())
        let pause = action(watcher.paused ? "Resume switching" : "Pause switching", #selector(togglePause))
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(action("Quit NP App Watch", #selector(quit)))
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        return item
    }

    @objc private func copyBundleID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    @objc private func togglePause() { watcher.setPaused(!watcher.paused) }

    @objc private func quit() { watcher.letGo { NSApp.terminate(nil) } }
}
