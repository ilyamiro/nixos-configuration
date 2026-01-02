#!/usr/bin/env bash

# Helper to get device icon
# Now checks both the reported type AND the device name for better accuracy
get_icon() {
    local type=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local name=$(echo "$2" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$type" == *"headset"* ]] || [[ "$type" == *"headphone"* ]] || [[ "$name" == *"headphone"* ]] || [[ "$name" == *"buds"* ]] || [[ "$name" == *"pods"* ]]; then
        echo "🎧"
    elif [[ "$type" == *"audio"* ]] || [[ "$type" == *"speaker"* ]] || [[ "$type" == *"card"* ]] || [[ "$name" == *"speaker"* ]]; then
        echo "蓼"
    elif [[ "$type" == *"phone"* ]] || [[ "$name" == *"phone"* ]] || [[ "$name" == *"iphone"* ]] || [[ "$name" == *"android"* ]]; then
        echo ""
    elif [[ "$type" == *"mouse"* ]] || [[ "$name" == *"mouse"* ]]; then
        echo ""
    elif [[ "$type" == *"keyboard"* ]] || [[ "$name" == *"keyboard"* ]]; then
        echo ""
    elif [[ "$type" == *"controller"* ]] || [[ "$name" == *"controller"* ]]; then
        echo ""
    else
        echo ""
    fi
}

get_status() {
    # Check Power
    power="off"
    if bluetoothctl show | grep -q "Powered: yes"; then
        power="on"
    fi

    connected_json="null"
    devices_json="[]"

    if [ "$power" == "on" ]; then
        # 1. Get List of Paired MACs first (fast)
        # We store them in a string to grep later
        paired_macs=$(bluetoothctl devices Paired | cut -d ' ' -f 2)

        # 2. Get ALL discovered devices
        mapfile -t devices < <(bluetoothctl devices)

        connected_mac=""
        disconnected_list=()

        # 3. Find Connected Device
        connected_info=$(bluetoothctl devices Connected)
        if [ -n "$connected_info" ]; then
            connected_mac=$(echo "$connected_info" | cut -d ' ' -f 2)
            name=$(echo "$connected_info" | cut -d ' ' -f 3-)
            
            # Get detailed info
            info=$(bluetoothctl info "$connected_mac")
            
            # Icon logic: Pass both Type and Name
            icon_type=$(echo "$info" | grep "Icon:" | cut -d: -f2 | xargs)
            icon=$(get_icon "$icon_type" "$name")
            
            # Battery Parsing
            bat=$(echo "$info" | grep "Battery Percentage" | awk '{print $NF}' | tr -d '()')
            if [ -z "$bat" ] || [ "$bat" == "?" ]; then bat="0"; fi

            connected_json=$(jq -n \
                                --arg name "$name" \
                                --arg mac "$connected_mac" \
                                --arg icon "$icon" \
                                --arg bat "$bat" \
                                '{name: $name, mac: $mac, icon: $icon, battery: $bat}')
        fi

        # 4. Process Available Devices
        for line in "${devices[@]}"; do
            if [ -z "$line" ]; then continue; fi
            mac=$(echo "$line" | cut -d ' ' -f 2)
            
            # Skip the currently connected device
            if [ "$mac" == "$connected_mac" ]; then continue; fi

            name=$(echo "$line" | cut -d ' ' -f 3-)
            
            # Determine Icon (We pass name twice as a fallback if we don't fetch full info)
            # Fetching full 'info' for every device is too slow, so we rely on Name for icons here
            icon=$(get_icon "unknown" "$name")

            # Determine Action: Pair vs Connect
            if echo "$paired_macs" | grep -q "$mac"; then
                action="Connect"
            else
                action="Pair"
            fi

            obj=$(jq -n \
                    --arg name "$name" \
                    --arg mac "$mac" \
                    --arg icon "$icon" \
                    --arg action "$action" \
                    '{name: $name, mac: $mac, icon: $icon, action: $action}')
            disconnected_list+=("$obj")
        done

        if [ ${#disconnected_list[@]} -gt 0 ]; then
            devices_json=$(printf '%s\n' "${disconnected_list[@]}" | jq -s '.')
        fi
    fi

    jq -n \
        --arg power "$power" \
        --argjson connected "$connected_json" \
        --argjson devices "$devices_json" \
        '{power: $power, connected: $connected, devices: $devices}'
}

toggle_power() {
    if bluetoothctl show | grep -q "Powered: yes"; then
        bluetoothctl power off
    else
        bluetoothctl power on
    fi
    sleep 0.5
    get_status
}

connect_dev() {
    bluetoothctl connect "$1"
}

disconnect_dev() {
    bluetoothctl disconnect "$1"
}

cmd="$1"
case $cmd in
    --status) get_status ;;
    --toggle) toggle_power ;;
    --connect) connect_dev "$2" ;;
    --disconnect) disconnect_dev "$2" ;;
esac
