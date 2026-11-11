# Playing Crowns of Caern on an iPhone

The repo carries an iOS export preset (`export_presets.cfg`, preset "iOS") that makes an Xcode project. Xcode
signs it and installs it on the phone. Everything below happens on a Mac.

## What you need once

1. **Xcode** from the Mac App Store. Open it once so it installs its components.
2. **An Apple ID in Xcode**: Xcode → Settings → Accounts → `+` → Apple ID. A free Apple ID works, but apps it
   signs stop opening after 7 days (export and install again). A paid Apple Developer account lasts a year and
   allows TestFlight.
3. **Godot's export templates for 4.5.1**: in Godot, Editor → Manage Export Templates → Download and Install.
4. **The team id** in the preset: Project → Export → iOS → `Application → App Store Team ID`. It is the
   10-character id Xcode shows for your team (Settings → Accounts → select the team; for a free account it is
   the "Personal Team"). Godot refuses to export without it. It is not a secret and can be committed.
5. **Developer Mode on the iPhone**: plug it in, then Settings → Privacy & Security → Developer Mode → On and
   restart. Trust the Mac when the phone asks.

## One click: newest main onto the phone

`tools/ios/Install on iPhone.command` (copy it anywhere, e.g. next to your clone) updates a separate
clean checkout (default `$HOME/CrownsOfCaern-ios`, or set `CROWNS_IOS_REPO`; e.g. a git worktree, so local work in the main folder is never touched) to
`origin/main`, then runs `tools/ios/install_on_iphone.sh`. That script finds the connected iPhone, exports with
Godot, builds and signs with `xcodebuild -allowProvisioningUpdates`, installs with `devicectl` and starts the game.

Per-Mac settings go in `~/.crowns_of_cinder_ios` (not in the repo):

```sh
TEAM_ID=ABCDE12345                      # your team id (Personal Team works)
BUNDLE_ID=com.example.crownsofcaern.yourname
```

The phone must be plugged in and unlocked. With a free Apple ID, run it again at least every 7 days.

## Each build

```sh
mkdir -p export/ios
godot --headless --path . --export-debug "iOS" export/ios/CrownsOfCinder.ipa
open export/ios/CrownsOfCinder.xcodeproj
```

The preset has *Export Project Only* on, so Godot writes the Xcode project and stops. In Xcode:

1. Select the `CrownsOfCinder` target → Signing & Capabilities → tick *Automatically manage signing* and pick
   your team. If Xcode says no profiles were found for the bundle id `com.crownsofcaern.game` (it is taken, or registered to another team), change it to something unique such as `com.example.crownsofcaern.<yourname>`.
2. Pick the iPhone as the run destination (top bar) and press Run (⌘R).
3. The first time, the phone says the developer is untrusted: Settings → General → VPN & Device Management →
   your Apple ID → Trust. Run again.

`export/` is in `.gitignore`.

## Controls on a touch screen

Buttons, lists and dialogs work with taps (Godot turns touches into clicks). On the adventure map
(`TouchGestures`, `MapView`):

| Gesture | Does |
|---|---|
| Tap a tile | Plans a route and shows what is there; tap it again to march (or open the battle forecast) |
| Hold a finger still | Shows the info card for that tile without moving |
| Drag | Pans the map |
| Two fingers spread or pinch | Zooms in or out a level per step, centred between the fingers |
| Quick two-finger tap | Cancels the planned route (the right click) |

Scouting on a phone goes through the forecast's *Send scout* button. Keyboard shortcuts all have a button in the
side panel (Hero, Town, Next, Save, Load, Menu, End Turn).

## Phone layout

A touch screen gets one uniform scale (`TouchLayout`): the canvas is sized so one unit is about 0.78 points
(500 units tall on an iPhone held sideways; tablets keep the 800-unit desktop canvas). At that scale body text
lands near 11 pt, nothing is smaller than 13 units (about 10 pt), and buttons, tabs, fields and slots are at
least 56 units (44 pt, Apple's minimum touch target) with 18-unit text. Controls are not inflated on top of that.

The safe area (notch, rounded corners, home indicator) comes from `DisplayServer.get_display_safe_area()`; the
HUD, dialogs, the town and the New Game form stay inside it, and the strips outside it are filled in the HUD's
colour. Dialogs are centred, never taller than the screen: their body scrolls and the button row (Attack,
Close, Save...) is pinned below it. The side panel shows the hero first (a hero strip, card, bars and army),
the minimap at the end of its scroll, then one row of commands (Town, Next, Save, Menu) and End Turn in the
bottom-right thumb corner. The hero portrait and army open the hero screen; Load is in the main menu.

Phone screenshots of the main screens, with an iPhone 12 Pro's safe area simulated:

```sh
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 2532x1170 \
    --script res://tools/phone_screenshots.gd -- /tmp/phone
```

To check finger interactions on a desktop (including swipes over dropdowns and tapping Begin):

```sh
godot --headless --path . --script res://tools/mobile_menu_check.gd
```


## Remaining device checks

- Control tooltips (resource income, unit details) depend on Godot showing tooltips after a tap; check on the device.
- The minimum iOS version is 15.0. Xcode 27 rejects lower deployment targets.
