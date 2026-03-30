# Simple Lid Sleep Toggle

A minimal macOS menu bar app to toggle lid-close sleep and monitor CPU temperature — no Terminal needed.

## Features

- **Menu bar icon**: ☕ when lid sleep is disabled, 🙂 when enabled
- **One-click toggle**: enables/disables `pmset disablesleep` without opening Terminal
- **Continuous CPU temperature monitoring**: samples every 30 seconds via IOKit (no sudo, no third-party tools)
- **Inline temperature plot** in the menu dropdown:
  - Full history shown as a dim white line (lid open + closed)
  - Lid-closed period highlighted in orange/yellow with a shaded background
  - Shows `lid-closed max: XX°C` so you can compare closed vs open temps
  - X-axis shows how far back the history goes (up to 4 hours)
- **Tooltip** on the menu bar icon shows live temp and session max while lid sleep is disabled

## Usage

```bash
bash launch.sh
```

This compiles `SleepToggle.swift` with `swiftc` and launches the app. No Xcode required.

On first launch, an admin prompt configures passwordless `sudo` for `pmset` (one-time setup). Temperature reading uses IOKit directly — no sudo needed.

## Requirements

- macOS on Apple Silicon (M1/M2/M3)
- Swift / Xcode Command Line Tools (`xcode-select --install`)
- Admin password on first launch (for `pmset` sudoers setup only)
