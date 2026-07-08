# Blooming8 Widget

A macOS menu bar app for the [BLOOMIN8](https://bloomin8.com/) e-ink photo frame — see what's currently on your frame, and push a random photo to it with one click, right from your menu bar.

> 🤖 **This entire project — every line of code, this README included — was built by [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant, working from plain-English requests in a chat conversation.** No hand-written Swift went into it.

## Features

- **Live preview** — shows the photo currently displayed on your frame, pulled straight from the frame's local API.
- **Random Photo** — pick a random image from one or more galleries on the frame and push it to the frame instantly.
- **Gallery tabs** — group galleries into named tabs so you're not picking from every gallery at once. Tabs can optionally be locked behind a password (a UI-level deterrent, not real security — see [Security notes](#security-notes)).
- **Randomize by photo or by gallery** — pool every photo across selected galleries (bigger galleries contribute more candidates), or give every gallery equal odds regardless of size.
- **Bluetooth wake** — if the frame's Wi‑Fi radio has gone to sleep, the app sends a BLE wake pulse and automatically retries once the frame is reachable again. Also available as a one-click button.
- **Battery indicator** — see the frame's current battery level at a glance.
- **Right-click quick menu** — Random Photo, Wake Frame, and Quit, without opening the popover.

## How it works

The BLOOMIN8 frame exposes an undocumented local HTTP API on your Wi-Fi network (no cloud, no auth) — this app talks to it directly:

- `GET /deviceInfo` — current photo, active gallery, battery level, device name
- `GET /gallery/list`, `GET /gallery` — list galleries and their images (with cursor-based pagination for galleries over 51 photos)
- `POST /show` — display a specific image on the frame

Since the frame's Wi‑Fi radio sleeps to save battery, waking it requires Bluetooth Low Energy: the app scans for the frame by its advertised BLE name, connects, and writes a short pulse to one of its known GATT characteristics, which brings Wi‑Fi back up.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (for the Swift toolchain — `xcode-select --install` if you don't already have it)

No Xcode project is needed; this is a plain Swift Package Manager executable.

## Building & running

```sh
git clone https://github.com/philipholtom/Blooming8-Mac-Widget.git
cd Blooming8-Mac-Widget
./build_app.sh
```

`build_app.sh` builds a release binary, packages it into `Blooming8Widget.app`, installs it to `/Applications` (replacing any previous copy), and launches it. Re-run it any time after pulling changes.

On first launch, click the menu bar icon and open Settings (gear icon) to enter:

- **Frame IP address** — your frame's local network IP (find it via the BLOOMIN8 phone app or your router's device list)
- **Bluetooth device name** — the frame's advertised BLE name, used to wake it when asleep

To launch automatically at login, add `/Applications/Blooming8Widget.app` in System Settings → General → Login Items.

## Security notes

- The frame's HTTP API has no authentication of its own — anyone on your local network can talk to it directly. This app doesn't add any security to the frame itself.
- Gallery tab passwords are a convenience feature only: they gate the app's UI (so a locked tab's galleries won't show or get randomized until unlocked) but don't touch the frame's actual access control. Don't rely on them for genuinely sensitive photos.

## Project structure

```
Sources/Blooming8Widget/
  main.swift            entry point
  AppDelegate.swift      menu bar item, popover, right-click menu
  ContentView.swift       the popover UI
  PhotoController.swift   app state and business logic
  Settings.swift          persisted settings (UserDefaults)
  GalleryTab.swift        gallery tab / password model
  BloominClient.swift     the frame's local HTTP API client
  BLEWaker.swift          CoreBluetooth wake pulse
Resources/AppIcon.icns   app icon
build_app.sh              build, package, install, and relaunch
```
