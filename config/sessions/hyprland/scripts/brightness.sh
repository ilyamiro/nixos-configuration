#!/usr/bin/env bash

# Select the same card as before
CARD=$(ls /sys/class/backlight | head -n 1)

if [[ "$1" == "--inc" ]]; then
    # Increase brightness by 5%
    brightnessctl -d "$CARD" set 5%+
elif [[ "$1" == "--dec" ]]; then
    # Decrease brightness by 5% (min-value is handled automatically by brightnessctl)
    brightnessctl -d "$CARD" set 5%-
else
    # Original 'get_blight' functionality (returns percentage)
    CURRENT=$(brightnessctl -d "$CARD" get)
    MAX=$(brightnessctl -d "$CARD" max)
    echo $(( CURRENT * 100 / MAX ))
fi
