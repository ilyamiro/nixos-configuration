#!/usr/bin/env bash

# Directory to save screenshots
SAVE_DIR="$HOME/Screenshots"
mkdir -p "$SAVE_DIR"

# If hyprshot is already running → cancel it
if pgrep -x hyprshot > /dev/null; then
    pkill -x hyprshot
    exit 0
fi

# Take screenshot directly into SAVE_DIR
hyprshot -m region -c -o "$SAVE_DIR"
