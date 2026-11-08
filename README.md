# Unscrew

Undoes the things macOS screwed up. A menu bar app that runs feature scripts you can switch on and off.

## Install

Needs macOS 14 or later.

1. Download `Unscrew.zip` from the [latest release](https://github.com/TheKerbecs/unscrew/releases/latest) and unzip it.
2. Move `Unscrew.app` to `/Applications`.
3. The app is not notarized, so macOS blocks the first launch. Remove the download flag once:
   ```
   xattr -dr com.apple.quarantine /Applications/Unscrew.app
   ```
   Or open it, then click "Open Anyway" in System Settings > Privacy & Security.
4. Open Unscrew. Its icon appears in the menu bar.
5. Add Unscrew in System Settings > Privacy & Security > Accessibility and switch it on. Window stretching, scroll inversion and quitting apps need it.
6. Switch features on from the menu bar icon. Settings… shows each feature's fields and last output.

Allow it when macOS asks whether Unscrew may control System Events.

To update, quit Unscrew and replace the app. You may need to switch Accessibility off and on again for the new version.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```
tools/make-signing-cert.sh   # once, keeps permissions across rebuilds
./build.sh                   # builds, signs, installs ~/Applications/Unscrew.app
```

`Unscrew --selftest` checks the header parser.

## Features

| Script | Does |
|---|---|
| `menubar-autohide.sh` | Hides the menu bar while an external display is connected, stretches windows into the space |
| `mouse-scroll-invert.sh` | Mouse wheel scrolls opposite to the trackpad (`scroll-invert` helper) |
| `bluetooth-mic-off.sh` | Bluetooth headsets are never the input, so they keep high quality audio (`mic-guard` helper) |
| `dock-delay.sh` | Auto-hidden Dock delay and slide time |
| `finder-show-all.sh` | Extensions, hidden files, path bar and status bar |
| `no-ds-store.sh` | No `.DS_Store` on network shares and USB drives |
| `quit-windowless.sh` | Quits apps that have had no window for a few minutes |
| `companion-apps.sh` | Starts the apps you list (default BetterSnapTool, Raycast) |

On launch Unscrew copies its bundled scripts to `~/Library/Application Support/Unscrew/features` and never overwrites existing ones, so your edits stay. Delete a script there to get the bundled version back.

## Writing a feature

Any executable file in the features folder. Unscrew runs `<script> apply` when it is switched on or a trigger fires, and `<script> off` when it is switched off. Runs time out after 30 s. `UNSCREW_APP` holds the path of the app bundle.

Header comments in the first 20 lines, all optional:

```
# name: Dock show delay
# description: Shown under the name in Settings.
# on: launch, displays, wake
# interval: 30
# setting: delay | Delay (seconds) |
```

A setting shows as a field in Settings and reaches the script as `UNSCREW_DELAY`. An empty default reads as "macOS default". Return re-runs the feature, "Reset to default" clears the fields.
