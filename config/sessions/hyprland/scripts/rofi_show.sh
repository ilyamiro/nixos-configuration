#!/usr/bin/env bash

MODE=${1:-drun}

if pgrep -x "rofi" > /dev/null; then
    pkill rofi
else
    rofi -show "$MODE" -config ~/.config/rofi/config.rasi
fi
