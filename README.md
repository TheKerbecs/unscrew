# Unscrew

Undoes the things macOS screwed up. A menu bar app that runs feature scripts you can switch on and off.

## Build

```
tools/make-signing-cert.sh   # once, keeps permissions across rebuilds
./build.sh                   # builds, signs, installs ~/Applications/Unscrew.app
```

Grant Unscrew Accessibility in System Settings > Privacy & Security. `Unscrew --selftest` checks the header parser.

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
| `companion-apps.sh` | Keeps BetterSnapTool and Raycast running |

`build.sh` copies new scripts to `~/Library/Application Support/Unscrew/features` and never overwrites existing ones.

## Writing a feature

Any executable file in the features folder. Unscrew runs `<script> apply` when it is switched on or a trigger fires, and `<script> off` when it is switched off. Runs time out after 30 s.

Header comments in the first 20 lines, all optional:

```
# name: Dock show delay
# description: Shown under the name in Settings.
# on: launch, displays, wake
# interval: 30
# setting: delay | Delay (seconds) |
```

A setting shows as a field in Settings and reaches the script as `UNSCREW_DELAY`. An empty default reads as "macOS default". Return re-runs the feature, "Reset to default" clears the fields.
