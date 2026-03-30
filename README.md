# Simple Lid Sleep Toggle

A minimal macOS menu bar app to toggle lid-close sleep without touching the terminal.

## What it does

- Adds a menu bar icon (☕ sleep disabled / 🙂 sleep enabled) showing current state
- Toggles `pmset disablesleep` with one click — no Terminal needed
- On first launch, configures passwordless `sudo` for `pmset` via an admin prompt (one-time setup)

## Usage

```bash
bash launch.sh
```

This compiles `SleepToggle.swift` with `swiftc` and launches the app. No Xcode required.

## Requirements

- macOS
- Swift (comes with Xcode Command Line Tools)
- Admin password on first launch (for sudoers setup)
