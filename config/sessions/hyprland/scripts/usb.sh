#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_CFG="$HOME/.config/eww/popups/usb"
EWW_BIN=$(which eww)

# --- STATE FILES ---
CLOSER_PID_FILE="/tmp/eww_usb_closer.pid"
ACTIVE_PATH_FILE="/tmp/eww_usb_active_path"
LAST_EVENT_FILE="/tmp/eww_usb_last_event"

# --- STATE TRACKING (Associative Array) ---
# We use this to track devices that are currently plugged in.
# This prevents "add" events for devices that were already there at script start.
declare -A KNOWN_DEVICES

# --- FUNCTION: Snapshot Existing Devices ---
# Scans the system for devices present at launch to ignore their initial "add" events.
scan_initial_devices() {
    # Scan USB devices
    for dev in /sys/bus/usb/devices/*; do
        if [ -L "$dev" ]; then
            # Resolve the symlink to get the real /sys/devices/... path
            real_path=$(realpath "$dev")
            # Extract the part after /sys
            sys_path=${real_path#"/sys"}
            KNOWN_DEVICES["$sys_path"]=1
        fi
    done
    
    # Scan Block devices
    for dev in /sys/class/block/*; do
        if [ -L "$dev" ]; then
            real_path=$(realpath "$dev")
            sys_path=${real_path#"/sys"}
            KNOWN_DEVICES["$sys_path"]=1
        fi
    done
}

# Run the snapshot immediately
scan_initial_devices

# --- HELPER: Manage Closer Process ---
reset_closer_timer() {
    if [ -f "$CLOSER_PID_FILE" ]; then
        old_pid=$(cat "$CLOSER_PID_FILE")
        if [ -n "$old_pid" ]; then kill "$old_pid" 2>/dev/null; fi
    fi

    (
        sleep 10
        $EWW_BIN -c "$EWW_CFG" close usb_popup
        rm "$CLOSER_PID_FILE" "$ACTIVE_PATH_FILE" 2>/dev/null
    ) &
    echo $! > "$CLOSER_PID_FILE"
}

# --- HELPER: Debounce ---
should_notify() {
    local new_model="$1"
    local current_time=$(date +%s)
    local last_model=""
    local last_time=0
    
    if [ -f "$LAST_EVENT_FILE" ]; then
        local content=$(cat "$LAST_EVENT_FILE")
        if [[ "$content" == *"|"* ]]; then
            last_model="${content%|*}"
            last_time="${content##*|}"
        fi
    fi

    if ! [[ "$last_time" =~ ^[0-9]+$ ]]; then last_time=0; fi
    local time_diff=$((current_time - last_time))
    
    # If same device appears within 3 seconds, ignore it
    if [[ "$new_model" == "$last_model" ]] && [[ "$time_diff" -lt 3 ]]; then
        return 1
    fi
    
    echo "${new_model}|${current_time}" > "$LAST_EVENT_FILE"
    return 0
}

# --- MAIN LOOP ---
# We use stdbuf to ensure immediate output from udevadm
stdbuf -oL udevadm monitor --udev --subsystem-match=usb --subsystem-match=block | while read -r line; do
    
    DEVPATH=$(echo "$line" | awk '{print $4}')
    ACTION=$(echo "$line" | awk '{print $1}')

    # --- UNPLUG LOGIC ---
    if [[ "$line" == *"remove"* ]] || [[ "$line" == *"unbind"* ]]; then
        # Remove from known devices list so it can be detected if replugged
        unset KNOWN_DEVICES["$DEVPATH"]

        if [ -f "$ACTIVE_PATH_FILE" ]; then
            active_path=$(cat "$ACTIVE_PATH_FILE")
            if [[ "$DEVPATH" == "$active_path" ]]; then
                if [ -f "$CLOSER_PID_FILE" ]; then kill $(cat "$CLOSER_PID_FILE") 2>/dev/null; fi
                $EWW_BIN -c "$EWW_CFG" close usb_popup
                rm "$LAST_EVENT_FILE" "$ACTIVE_PATH_FILE" "$CLOSER_PID_FILE" 2>/dev/null
            fi
        fi
        continue
    fi

    # --- ADD LOGIC ---
    if [[ "$line" == *"add"* ]] || [[ "$line" == *"bind"* ]]; then
        
        # 1. CHECK IF ALREADY KNOWN (The Fix for Startup Spam)
        if [[ -n "${KNOWN_DEVICES[$DEVPATH]}" ]]; then
            # It was already there. Ignore this event.
            continue
        fi

        # Mark as known now, so duplicate "add" events are ignored
        KNOWN_DEVICES["$DEVPATH"]=1

        # --- CASE A: STORAGE DEVICES (Block) ---
        if [[ "$line" == *"/block/"* ]]; then
            DEVNAME=$(echo "$DEVPATH" | awk -F/ '{print $NF}')
            
            # Filter unwanted devices (partitions, loop, ram)
            if [[ "$DEVNAME" =~ [0-9]$ ]] || [[ "$DEVNAME" == loop* ]] || [[ "$DEVNAME" == ram* ]]; then continue; fi
            
            # Size Detection
            SIZE=""
            for i in {1..5}; do
                BYTES=$(lsblk -b -d -n -o SIZE "/dev/$DEVNAME" 2>/dev/null)
                if [ -n "$BYTES" ] && [ "$BYTES" -gt 0 ]; then
                    SIZE=$(echo "$BYTES" | numfmt --to=iec-i --suffix=B)
                    break
                fi
                sleep 0.4
            done
            if [ -z "$SIZE" ]; then SIZE="Unknown Size"; fi

            # Info
            eval "$(udevadm info --query=property --name="/dev/$DEVNAME" | grep -E 'ID_VENDOR=|ID_MODEL=')"
            VENDOR="${ID_VENDOR//_/ }"
            MODEL="${ID_MODEL//_/ }"
            FULL_DESC="$VENDOR $MODEL"
            if [ -z "$VENDOR" ]; then FULL_DESC="$MODEL"; fi

            if ! should_notify "$FULL_DESC"; then continue; fi
            
            $EWW_BIN -c "$EWW_CFG" update \
                usb_title="Storage Connected" \
                usb_desc="$SIZE • $FULL_DESC" \
                usb_icon="󰋊"
            $EWW_BIN -c "$EWW_CFG" open usb_popup
            
            echo "$DEVPATH" > "$ACTIVE_PATH_FILE"
            reset_closer_timer
        fi

        # --- CASE B: OTHER USB DEVICES ---
        if [[ "$line" == *"(usb)"* ]]; then
            eval "$(udevadm info --query=property --path="/sys$DEVPATH" | grep -E 'ID_VENDOR=|ID_MODEL=|ID_USB_DRIVER=|ID_INPUT_KEYBOARD=|ID_INPUT_MOUSE=|ID_USB_INTERFACE_NUM=')"
            
            # Skip sub-interfaces
            if [[ "$ID_USB_INTERFACE_NUM" != "00" ]] && [[ -n "$ID_USB_INTERFACE_NUM" ]]; then continue; fi

            VENDOR="${ID_VENDOR//_/ }"
            MODEL="${ID_MODEL//_/ }"
            
            if [ -z "$MODEL" ]; then continue; fi
            if [[ "$ID_USB_DRIVER" == "usb-storage" ]]; then continue; fi
            
            FULL_DESC="$VENDOR $MODEL"
            if [ -z "$VENDOR" ]; then FULL_DESC="$MODEL"; fi

            if ! should_notify "$FULL_DESC"; then continue; fi

            ICON=""; TITLE="New Device"
            if [[ "$ID_INPUT_KEYBOARD" == "1" ]]; then ICON="󰌌"; TITLE="Keyboard Connected";
            elif [[ "$ID_INPUT_MOUSE" == "1" ]]; then ICON="󰍽"; TITLE="Mouse Connected";
            elif [[ "$MODEL" == *"Audio"* ]] || [[ "$MODEL" == *"Mic"* ]]; then ICON="󰍬"; TITLE="Audio Device";
            elif [[ "$MODEL" == *"Camera"* ]]; then ICON="󰄀"; TITLE="Camera Connected"; fi

            $EWW_BIN -c "$EWW_CFG" update \
                usb_title="$TITLE" \
                usb_desc="$FULL_DESC" \
                usb_icon="$ICON"
            $EWW_BIN -c "$EWW_CFG" open usb_popup

            echo "$DEVPATH" > "$ACTIVE_PATH_FILE"
            reset_closer_timer
        fi
    fi
done
