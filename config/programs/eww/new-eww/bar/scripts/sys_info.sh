#!/usr/bin/env bash

## WIFI
get_wifi_status() {
    nmcli -t -f WIFI g 2>/dev/null || echo "disabled"
}

get_wifi_ssid() {
    local ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2)
    if [ -z "$ssid" ]; then
        echo ""
    else
        echo "$ssid"
    fi
}

get_kb_layout() {
    # Get active keyboard layout from Hyprland
    # Requires jq installed
    local layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -n1)
    
    # Shorten the name (e.g., "English (US)" -> "US", "Spanish" -> "ES")
    # You might need to adjust the cut logic depending on your specific layout names
    echo "$layout" | cut -c1-2 | tr '[:lower:]' '[:upper:]'
}

get_wifi_icon() {
    local status=$(get_wifi_status)
    local ssid=$(get_wifi_ssid)
    
    if [ "$status" = "enabled" ]; then
        if [ -n "$ssid" ]; then
            # Get signal strength for better icon
            local signal=$(get_wifi_strength)
            if [ "$signal" -ge 75 ]; then
                echo "󰤨"
            elif [ "$signal" -ge 50 ]; then
                echo "󰤥"
            elif [ "$signal" -ge 25 ]; then
                echo "󰤢"
            else
                echo "󰤟"
            fi
        else
            echo "󰤯"  # WiFi on but not connected
        fi
    else
        echo "󰤮"  # WiFi off
    fi
}

get_wifi_strength() {
    local signal=$(nmcli -f IN-USE,SIGNAL dev wifi 2>/dev/null | grep '^\*' | awk '{print $2}')
    echo "${signal:-0}"
}

toggle_wifi() {
    if [ "$(nmcli -t -f WIFI g 2>/dev/null)" = "enabled" ]; then
        nmcli radio wifi off
        notify-send -u low -i network-wireless-disabled "WiFi" "Disabled"
    else
        nmcli radio wifi on
        notify-send -u low -i network-wireless-enabled "WiFi" "Enabled"
    fi
}

## BLUETOOTH
get_bt_status() {
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        echo "on"
    else
        echo "off"
    fi
}

get_bt_icon() {
    local status=$(get_bt_status)
    
    if [ "$status" = "on" ]; then
        # Check if any device is connected
        if bluetoothctl devices Connected 2>/dev/null | grep -q "Device"; then
            echo "󰂱"  # Connected
        else
            echo "󰂯"  # On but not connected
        fi
    else
        echo "󰂲"  # Off
    fi
}

get_bt_connected_device() {
    if [ "$(get_bt_status)" = "on" ]; then
        # Get name, trim whitespace
        local device=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)
        if [ -z "$device" ]; then
            echo "Disconnected"
        else
            echo "$device"
        fi
    else
        echo "Off"
    fi
}

toggle_bt() {
    local status=$(get_bt_status)
    
    if [ "$status" = "on" ]; then
        bluetoothctl power off 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        bluetoothctl power on 2>/dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}

## BRIGHTNESS
get_brightness() {
    if command -v brightnessctl &> /dev/null; then
        local percent=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
        echo "${percent:-50}"
    elif command -v light &> /dev/null; then
        local percent=$(light -G 2>/dev/null | cut -d. -f1)
        echo "${percent:-50}"
    elif [ -f /sys/class/backlight/*/brightness ]; then
        local current=$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -n1)
        local max=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n1)
        if [ -n "$current" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
            echo $(( current * 100 / max ))
        else
            echo "50"
        fi
    else
        echo "50"
    fi
}

## AUDIO
get_volume() {
    if command -v pamixer &> /dev/null; then
        pamixer --get-volume 2>/dev/null || echo "50"
    elif command -v pactl &> /dev/null; then
        pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+%' | head -n1 | tr -d '%' || echo "50"
    else
        echo "50"
    fi
}

is_muted() {
    if command -v pamixer &> /dev/null; then
        if pamixer --get-mute 2>/dev/null | grep -q "true"; then
            echo "true"
        else
            echo "false"
        fi
    elif command -v pactl &> /dev/null; then
        if pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q "yes"; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

toggle_mute() {
    if command -v pamixer &> /dev/null; then
        pamixer --toggle-mute 2>/dev/null
        if [ "$(is_muted)" = "true" ]; then
            notify-send -u low -i audio-volume-muted "Volume" "Muted"
        else
            notify-send -u low -i audio-volume-high "Volume" "Unmuted ($(get_volume)%)"
        fi
    elif command -v pactl &> /dev/null; then
        pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null
        if [ "$(is_muted)" = "true" ]; then
            notify-send -u low -i audio-volume-muted "Volume" "Muted"
        else
            notify-send -u low -i audio-volume-high "Volume" "Unmuted ($(get_volume)%)"
        fi
    fi
}

get_volume_icon() {
    local vol muted

    # Get volume and strip non-numeric characters
    vol=$(get_volume | tr -cd '0-9')
    muted=$(is_muted)

    # Default to 0 if volume is empty
    [ -z "$vol" ] && vol=0

    if [ "$muted" = "true" ]; then
        echo "󰝟"  # Muted
    elif [ "$vol" -ge 70 ]; then
        echo "󰕾"  # High
    elif [ "$vol" -ge 30 ]; then
        echo "󰖀"  # Medium
    elif [ "$vol" -gt 0 ]; then
        echo "󰕿"  # Low
    else
        echo "󰝟"  # Zero/Muted
    fi
}

## BATTERY
get_battery_percent() {
    if [ -f /sys/class/power_supply/BAT*/capacity ]; then
        local percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)
        echo "${percent:-100}"
    else
        echo "100"
    fi
}

get_battery_status() {
    if [ -f /sys/class/power_supply/BAT*/status ]; then
        cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1
    else
        echo "Full"
    fi
}

get_battery_icon() {
    local percent=$(get_battery_percent)
    local status=$(get_battery_status)
    
    # Show charging icons when charging or full
    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        if [ "$percent" -ge 90 ]; then
            echo "󰂅"  # Charging full
        elif [ "$percent" -ge 80 ]; then
            echo "󰂋"  # Charging 80
        elif [ "$percent" -ge 60 ]; then
            echo "󰂊"  # Charging 60
        elif [ "$percent" -ge 40 ]; then
            echo "󰢞"  # Charging 40
        elif [ "$percent" -ge 20 ]; then
            echo "󰂆"  # Charging 20
        else
            echo "󰢜"  # Charging low
        fi
    else
        # Discharging icons
        if [ "$percent" -ge 90 ]; then
            echo "󰁹"  # 100%
        elif [ "$percent" -ge 80 ]; then
            echo "󰂂"  # 90%
        elif [ "$percent" -ge 70 ]; then
            echo "󰂁"  # 80%
        elif [ "$percent" -ge 60 ]; then
            echo "󰂀"  # 70%
        elif [ "$percent" -ge 50 ]; then
            echo "󰁿"  # 60%
        elif [ "$percent" -ge 40 ]; then
            echo "󰁾"  # 50%
        elif [ "$percent" -ge 30 ]; then
            echo "󰁽"  # 40%
        elif [ "$percent" -ge 20 ]; then
            echo "󰁼"  # 30%
        elif [ "$percent" -ge 10 ]; then
            echo "󰁻"  # 20%
        else
            echo "󰁺"  # 10% or less
        fi
    fi
}

## SYSTEM
get_cpu_usage() {
    if command -v top &> /dev/null; then
        top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2 + $4)}' || echo "0"
    else
        echo "0"
    fi
}

get_memory_usage() {
    if command -v free &> /dev/null; then
        free 2>/dev/null | grep Mem | awk '{print int($3/$2 * 100)}' || echo "0"
    else
        echo "0"
    fi
}

get_uptime() {
    if command -v uptime &> /dev/null; then
        uptime -p 2>/dev/null | sed 's/up //' || echo "unknown"
    else
        echo "unknown"
    fi
}

## EXECUTION
cmd="$1"
case $cmd in
    --wifi-status) get_wifi_status ;;
    --wifi-ssid) get_wifi_ssid ;;
    --wifi-icon) get_wifi_icon ;;
    --wifi-strength) get_wifi_strength ;;
    --wifi-toggle) toggle_wifi ;;
    
    --bt-status) get_bt_status ;;
    --bt-icon) get_bt_icon ;;
    --bt-connected) get_bt_connected_device ;;
    --bt-toggle) toggle_bt ;;
    
    --brightness) get_brightness ;;
    
    --volume) get_volume ;;
    --volume-icon) get_volume_icon ;;
    --is-muted) is_muted ;;
    --toggle-mute) toggle_mute ;;
    
    --battery-percent) get_battery_percent ;;
    --battery-status) get_battery_status ;;
    --battery-icon) get_battery_icon ;;
    
    --cpu-usage) get_cpu_usage ;;
    --memory-usage) get_memory_usage ;;
    --uptime) get_uptime ;;

    --kb-layout) get_kb_layout ;;
    
    *) echo "Unknown command: $cmd" ;;
esac
