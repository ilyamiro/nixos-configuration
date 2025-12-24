#!/usr/bin/env bash

if [ -d /sys/class/power_supply/BAT0 ]; then
    BATTERY_DIR="/sys/class/power_supply/BAT0"
elif [ -d /sys/class/power_supply/BAT1 ]; then
    BATTERY_DIR="/sys/class/power_supply/BAT1"
else
    echo ""
    exit 0
fi

STATUS=$(cat "$BATTERY_DIR/status")
CAPACITY=$(cat "$BATTERY_DIR/capacity")

# Define icons based on capacity
if [ "$STATUS" = "Charging" ]; then
    ICON="󰂄"
else
    if [ "$CAPACITY" -ge 90 ]; then
        ICON="󰁹"
    elif [ "$CAPACITY" -ge 80 ]; then
        ICON="󰂂"
    elif [ "$CAPACITY" -ge 70 ]; then
        ICON="󰂁"
    elif [ "$CAPACITY" -ge 60 ]; then
        ICON="󰂀"
    elif [ "$CAPACITY" -ge 50 ]; then
        ICON="󰁿"
    elif [ "$CAPACITY" -ge 40 ]; then
        ICON="󰁾"
    elif [ "$CAPACITY" -ge 30 ]; then
        ICON="󰁽"
    elif [ "$CAPACITY" -ge 20 ]; then
        ICON="󰁼"
    elif [ "$CAPACITY" -ge 10 ]; then
        ICON="󰁻"
    else
        ICON="󰁺"
    fi
fi

echo "$ICON $CAPACITY%"
