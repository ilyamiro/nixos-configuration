#!/usr/bin/env bash

# If hyprshot is already running → cancel it
if pgrep -x hyprshot > /dev/null; then
    pkill -x hyprshot
    exit 0
fi

hyprshot -m region -c

