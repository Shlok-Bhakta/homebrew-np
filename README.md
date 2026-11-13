# np-appwatch

A small macOS menu bar helper for the NP Band Remote dongle (a Meta Neural Band → Bluetooth
keyboard/mouse bridge). It tells the dongle which app is in front, so the band's gestures switch
profile with the app: a browser profile in Chrome, an editor profile in Xcode, and back to your
usual profile everywhere else.

It only sends the front app's bundle id (like `com.google.Chrome`) to the dongle, over the
Bluetooth link the Mac already has with it. Nothing goes over the network.

## Install

```sh
brew install shlok-bhakta/np/np-appwatch
brew services start np-appwatch        # runs it now and at every login
```

It builds from source, so it needs the Xcode Command Line Tools (`xcode-select --install`;
Homebrew already asks for them). macOS 13 or later.

The first time it runs, macOS asks to let **np-appwatch** use Bluetooth: allow it. A hand appears
in the menu bar (crossed out until it's connected to the dongle).

**Needs:** dongle firmware **0.12.0** or later, and the Mac paired with the dongle as a computer
(it's then the Mac's keyboard and mouse; the helper shares that connection).

## Which apps switch to which profile

The dongle decides, from the `apps` of its gesture profiles (the profile file the NP Dongle iPhone
app edits):

```json
{
  "id": "browser",
  "name": "Browser",
  "hosts": ["computer"],
  "apps": ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser"],
  "gestures": { "swipe.left": "key:cmd+[", "swipe.right": "key:cmd+]", "index.doubleTap": "key:cmd+t" }
}
```

- An app a profile lists comes to the front: the Mac switches to that profile (quietly, no buzz).
- Any other app: the Mac goes back to the profile it was in before.
- Switching by hand (the letter menu, the app) sticks until the next listed app.
- Pausing or quitting the helper puts the Mac back in its own profile.

To find an app's bundle id, bring it to the front and open the menu bar item (it shows it, with a
copy button), or run:

```sh
np-appwatch front     # the app in front
np-appwatch apps      # every running app
```

## Commands

```text
np-appwatch              watch the app in front, with the menu bar item
np-appwatch --no-menu    the same, without it
np-appwatch front        print the front app's bundle id
np-appwatch apps         print every running app's bundle id
np-appwatch send <id>    tell the dongle once that <id> is in front ("" for none)
np-appwatch status       print the dongle's status JSON
```

Logs (when run by `brew services`): `$(brew --prefix)/var/log/np-appwatch.log`.

## Troubleshooting

- **The hand stays crossed out.** Is the Mac paired with the dongle (System Settings › Bluetooth
  shows "NP Band Remote" connected)? Is Bluetooth allowed for np-appwatch (System Settings ›
  Privacy & Security › Bluetooth)?
- **macOS asks for Bluetooth again after an upgrade.** It's built on your Mac and not signed by a
  developer, so macOS sees each build as a new app. Allow it again.
- **Nothing switches.** Check the bundle id against the profile's `apps` (case doesn't matter),
  and that the dongle runs 0.12.0 or later (`np-appwatch status` shows `"fw"`).

## Uninstall

```sh
brew services stop np-appwatch
brew uninstall np-appwatch
brew untap shlok-bhakta/np
```

MIT licensed. Not open to contributions.
