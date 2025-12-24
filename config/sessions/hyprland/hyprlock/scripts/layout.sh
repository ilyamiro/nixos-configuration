#!/usr/bin/env bash

LAYOUT=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -n 1)

# Shorten the layout name (e.g., "English (US)" -> "US")
if [[ "$LAYOUT" == *"English (US)"* ]]; then
    echo "US"
elif [[ "$LAYOUT" == *"Russian"* ]]; then
    echo "RU"
else
    echo "${LAYOUT:0:3}"
fi
