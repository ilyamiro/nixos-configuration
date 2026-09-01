#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh" 2>/dev/null || true

ACTION=${1:-get}

get_locks() {
    local caps=0
    local num=0

    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        local data
        data=$(LC_ALL=C hyprctl devices -j 2>/dev/null | jq -r '((.keyboards[] | select(.main == true)) // .keyboards[0]) | "\(.capsLock) \(.numLock)"' 2>/dev/null)
        if [[ "$data" =~ (true|false) ]]; then
            [[ "$data" =~ ^true ]] && caps=1
            [[ "$data" =~ true$ ]] && num=1
            echo "$caps $num"
            return
        fi
    elif [ -n "${SWAYSOCK:-}" ]; then
        local data
        data=$(swaymsg -t get_inputs 2>/dev/null | jq -r '[.[] | select(.type == "keyboard")] | .[0] | "\(.caps_lock) \(.num_lock)"' 2>/dev/null)
        if [[ "$data" =~ (true|false) ]]; then
            [[ "$data" =~ ^true ]] && caps=1
            [[ "$data" =~ true$ ]] && num=1
            echo "$caps $num"
            return
        fi
    fi

    grep -q '1' /sys/class/leds/*::capslock/brightness 2>/dev/null && caps=1
    grep -q '1' /sys/class/leds/*::numlock/brightness 2>/dev/null && num=1
    echo "$caps $num"
}

watch_locks() {
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        LC_ALL=C socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock 2>/dev/null | grep --line-buffered -E "keylock>>|activelayout>>"
    elif [ -n "${SWAYSOCK:-}" ]; then
        swaymsg -t subscribe -m '["input"]' 2>/dev/null | jq --unbuffered -c 'select(.change == "xkb_layout" or .change == "xkb_keymap" or .change == "input")'
    elif [ -n "${NIRI_SOCKET:-}" ]; then
        niri msg -j event-stream 2>/dev/null | jq --unbuffered -c 'select(has("KeyboardLayoutSwitched") or has("KeyboardLayoutsChanged"))'
    else
        while true; do
            get_locks
            sleep 0.25
        done
    fi
}

case "$ACTION" in
    get)
        get_locks
        ;;
    watch)
        watch_locks
        ;;
    *)
        get_locks
        ;;
esac
