#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_BIN="eww"
EWW_BT_CFG="/etc/nixos/config/programs/eww/new-eww/popups/bluetooth"
CACHE_FILE="/tmp/eww_bt_session_ignore"
SESSION_FILE="/tmp/eww_bt_daemon_pid"

# --- HELPER: ICONS ---
get_icon() {
    local name="$1"
    local lower="${name,,}"
    
    case $lower in
        *headset*|*headphone*|*buds*|*earbuds*|*airpods*) echo "󰋋" ;;
        *mouse*) echo "󰍽" ;;
        *keyboard*) echo "󰌌" ;;
        *phone*|*galaxy*|*iphone*) echo "󰏲" ;;
        *controller*|*gamepad*|*xbox*|*playstation*) echo "󰊴" ;;
        *speaker*) echo "󰓃" ;;
        *watch*) echo "󰘐" ;;
        *) echo "󰂯" ;;
    esac
}

# --- HELPER: GET DEVICE INFO ---
get_device_info() {
    local mac="$1"
    local name icon connected
    
    # Use bluetoothctl to get device info
    local info
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    
    if [ -z "$info" ]; then
        return 1
    fi
    
    # Extract name
    name=$(echo "$info" | grep -m1 "Name:" | cut -d: -f2- | xargs)
    [ -z "$name" ] && name=$(echo "$info" | grep -m1 "Alias:" | cut -d: -f2- | xargs)
    [ -z "$name" ] && name="Unknown Device"
    
    # Check if connected
    connected=$(echo "$info" | grep -m1 "Connected:" | awk '{print $2}')
    
    # Get icon
    icon=$(get_icon "$name")
    
    echo "$name|$icon|$connected"
}

# --- HELPER: CHECK IF DEVICE IS IGNORED ---
is_ignored() {
    local mac="$1"
    grep -qx "$mac" "$CACHE_FILE" 2>/dev/null
}

# --- HELPER: SHOW POPUP ---
show_popup() {
    local mac="$1"
    local name="$2"
    local icon="$3"
    
    echo "[$(date '+%H:%M:%S')] Showing popup for: $name ($mac)"
    
    # Update eww variables
    $EWW_BIN -c "$EWW_BT_CFG" update \
        bt_found_mac="$mac" \
        bt_found_name="$name" \
        bt_found_icon="$icon" 2>/dev/null
    
    # Open popup
    $EWW_BIN -c "$EWW_BT_CFG" open bluetooth_popup 2>/dev/null
    
    # Mark as ignored for this session
    echo "$mac" >> "$CACHE_FILE"
}

# --- DAEMON: MONITOR BLUETOOTH EVENTS ---
run_daemon() {
    echo "=== Starting Bluetooth Popup Daemon ==="
    echo "PID: $$"
    echo "$$ " > "$SESSION_FILE"
    
    # Initialize cache file
    : > "$CACHE_FILE"
    
    # Ensure bluetooth is powered on
    echo "Powering on Bluetooth adapter..."
    bluetoothctl power on >/dev/null 2>&1
    sleep 1
    
    # Check if bluetooth is working
    if ! bluetoothctl show >/dev/null 2>&1; then
        echo "ERROR: Bluetooth adapter not found or not working"
        exit 1
    fi
    
    echo "Monitoring Bluetooth D-Bus events..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Monitor D-Bus for bluetooth device property changes
    dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path_namespace='/org/bluez'" 2>/dev/null | \
    while read -r line; do
        # Look for RSSI changes (device is nearby) or device discovery
        if echo "$line" | grep -q "RSSI\|Connected"; then
            # Extract device path from previous lines in buffer
            # We need to parse the object path which appears before properties
            continue
        fi
        
        # Look for object path (device identifier)
        if echo "$line" | grep -q "path=/org/bluez/hci0/dev_"; then
            # Extract MAC address from path: /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX
            mac=$(echo "$line" | grep -o 'dev_[0-9A-F_]*' | sed 's/dev_//;s/_/:/g')
            
            if [ -n "$mac" ]; then
                # Small delay to let properties settle
                sleep 0.5
                
                # Check if already ignored this session
                if is_ignored "$mac"; then
                    continue
                fi
                
                # Get device info
                info=$(get_device_info "$mac")
                if [ -z "$info" ]; then
                    continue
                fi
                
                IFS='|' read -r name icon connected <<< "$info"
                
                # Only show popup if device is:
                # 1. Paired (we got info)
                # 2. Not connected
                # 3. Not ignored
                if [ "$connected" != "yes" ]; then
                    show_popup "$mac" "$name" "$icon"
                fi
            fi
        fi
    done
}

# --- ALTERNATIVE: POLLING METHOD (More Reliable) ---
run_daemon_polling() {
    echo "=== Starting Bluetooth Popup Daemon (Polling Mode) ==="
    echo "PID: $$"
    echo "$$" > "$SESSION_FILE"
    
    # Initialize cache file
    : > "$CACHE_FILE"
    
    # Ensure bluetooth is powered on
    echo "Powering on Bluetooth adapter..."
    bluetoothctl power on >/dev/null 2>&1
    sleep 1
    
    echo "Scanning for nearby paired devices..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Keep track of seen devices this run
    declare -A seen_devices
    
    while true; do
        # Get all paired devices
        while IFS= read -r line; do
            mac=$(echo "$line" | awk '{print $2}')
            
            # Skip if we've already processed this device
            if [ -n "${seen_devices[$mac]}" ]; then
                continue
            fi
            
            # Skip if ignored this session
            if is_ignored "$mac"; then
                seen_devices[$mac]=1
                continue
            fi
            
            # Get device info
            info=$(get_device_info "$mac")
            if [ -z "$info" ]; then
                continue
            fi
            
            IFS='|' read -r name icon connected <<< "$info"
            
            # Check RSSI to see if device is nearby
            rssi=$(bluetoothctl info "$mac" 2>/dev/null | grep -m1 "RSSI:" | awk '{print $2}')
            
            # If device has RSSI, it's been detected nearby
            if [ -n "$rssi" ] && [ "$connected" != "yes" ]; then
                show_popup "$mac" "$name" "$icon"
                seen_devices[$mac]=1
            fi
        done < <(bluetoothctl devices Paired 2>/dev/null)
        
        sleep 3
    done
}

# --- ACTIONS ---
connect_device() {
    local mac="$1"
    echo "Connecting to $mac..."
    
    $EWW_BIN -c "$EWW_BT_CFG" close bluetooth_popup 2>/dev/null
    
    notify-send "Bluetooth" "Connecting..." -t 2000 2>/dev/null
    
    if bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful"; then
        notify-send "Bluetooth" "Connected successfully!" -t 3000 2>/dev/null
    else
        notify-send "Bluetooth" "Connection failed" -u critical -t 3000 2>/dev/null
    fi
}

ignore_device() {
    local mac="$1"
    echo "Ignoring $mac for this session"
    
    $EWW_BIN -c "$EWW_BT_CFG" close bluetooth_popup 2>/dev/null
    echo "$mac" >> "$CACHE_FILE"
}

cleanup() {
    echo ""
    echo "Cleaning up..."
    rm -f "$SESSION_FILE"
    exit 0
}

# --- EXECUTION ---
case "$1" in
    --daemon)
        trap cleanup INT TERM
        # Use polling method by default (more reliable)
        run_daemon_polling
        ;;
    --daemon-dbus)
        trap cleanup INT TERM
        # Alternative: D-Bus monitoring (less CPU but may miss events)
        run_daemon
        ;;
    --connect)
        if [ -z "$2" ]; then
            echo "Usage: $0 --connect <MAC_ADDRESS>"
            exit 1
        fi
        connect_device "$2"
        ;;
    --ignore)
        if [ -z "$2" ]; then
            echo "Usage: $0 --ignore <MAC_ADDRESS>"
            exit 1
        fi
        ignore_device "$2"
        ;;
    --stop)
        if [ -f "$SESSION_FILE" ]; then
            pid=$(cat "$SESSION_FILE")
            kill "$pid" 2>/dev/null && echo "Daemon stopped (PID: $pid)"
        else
            echo "No daemon running"
        fi
        ;;
    *)
        echo "Bluetooth Popup Daemon"
        echo ""
        echo "Usage:"
        echo "  $0 --daemon          Start daemon (polling mode)"
        echo "  $0 --daemon-dbus     Start daemon (D-Bus monitoring)"
        echo "  $0 --connect <MAC>   Connect to device"
        echo "  $0 --ignore <MAC>    Ignore device this session"
        echo "  $0 --stop            Stop daemon"
        exit 1
        ;;
esac
