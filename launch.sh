#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
swiftc SleepToggle.swift -o SleepToggle -framework IOKit 2>&1
"$DIR/SleepToggle" &
