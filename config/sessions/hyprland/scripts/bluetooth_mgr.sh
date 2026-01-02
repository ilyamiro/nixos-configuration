#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_CFG="$HOME/.config/eww/popups/usb"
EWW_BIN=$(which eww)

# --- STATE FILES ---
CLOSER_PID_FILE="/tmp/eww_usb_closer.pid"
LAST_EVENT_FILE="/tmp/eww_usb_last_event"

# --- IN-MEMORY STATE ---
# We track connected Model Names to prevent "Ghost" popups when drivers reload
declare -A CONNECTED_MODELS

# --- HELPER: Normalize String ---
# Cleans up model names for consistent comparison
clean_name() {
    echo "$1" | tr -d '[:cntrl:]' | sed 's/^ *//;s/ *//'
}

# --- SNAPSHOT EXISTING DEVICES ---
# Scans currently connected USB/Block devices and adds their names to the "Ignore List"
scan_initial_devices() {
    # 1. Block Devices
    for dev in /sys/class/block/*; do
        if [ -e "$dev/device/model" ]; then
            model=$(cat "$dev/device/model")
            name=$(clean_name "$model")
            [ -n "$name" ] && CONNECTED_MODELS["$name"]=1
        fi
    done

    # 2. USB Devices
    for dev in /sys/bus/usb/devices/*; do
        if [ -e "$dev/product" ]; then
            model=$(cat "$dev/product")
            name=$(clean_name "$model")
            [ -n "$name" ] && CONNECTED_MODELS["$name"]=1
        fi
    done
}

# Run scan immediately
scan_initial_devices

# --- HELPER: Manage Closer Process ---
reset_closer_timer() {
    if [ -f "$CLOSER_PID_FILE" ]; then
        old_pid=$(cat "$CLOSER_PID_FILE")
        if [ -n "$old_pid" ]; then kill "$old_pid" 2>/dev/null; fi
    fi

    (
        sleep 6
        $EWW_BIN -c "$EWW_CFG" close usb_popup
        rm "$CLOSER_PID_FILE" 2>/dev/null
    ) &
    echo $! > "$CLOSER_PID_FILE"
}

# --- MAIN LOOP ---
udevadm monitor --udev --subsystem-match=usb --subsystem-match=block | while read -r line; do
    
    DEVPATH=$(echo "$line" | awk '{print $4}')
    ACTION=$(echo "$line" | awk '{print $1}')

    # --- REMOVE LOGIC ---
    # If a device is removed, we remove it from our memory so it can be detected again
    if [[ "$line" == *"remove"* ]] || [[ "$line" == *"unbind"* ]]; then
        # We can't easily get the model name after it's removed, 
        # so we rely on the debounce timer to allow re-connection
        continue
    fi

    # --- ADD LOGIC ---
    if [[ "$line" == *"add"* ]] || [[ "$line" == *"bind"* ]]; then
        
        # --- CASE A: STORAGE ---
        if [[ "$line" == *"/block/"* ]]; then
            DEVNAME=$(echo "$DEVPATH" | awk -F/ '{print $NF}')
            if [[ "$DEVNAME" =~ [0-9]$ ]] || [[ "$DEVNAME" == loop* ]] || [[ "$DEVNAME" == ram* ]]; then continue; fi
            
            # Robust Size Get
            SIZE=""
            for i in {1..4}; do
                BYTES=$(lsblk -b -d -n -o SIZE "/dev/$DEVNAME" 2>/dev/null)
                if [ -n "$BYTES" ] && [ "$BYTES" -gt 0 ]; then
                    SIZE=$(echo "$BYTES" | numfmt --to=iec-i --suffix=B)
                    break
                fi
                sleep 0.2
            done
            if [ -z "$SIZE" ]; then SIZE="Unknown"; fi

            eval "$(udevadm info --query=property --name="/dev/$DEVNAME" | grep -E 'ID_VENDOR=|ID_MODEL=')"
            FULL_DESC=$(clean_name "${ID_VENDOR//_/ } ${ID_MODEL//_/ }")
            
            # CHECK: Is this model already known/connected?
            if [[ -n "${CONNECTED_MODELS[$FULL_DESC]}" ]]; then continue; fi
            CONNECTED_MODELS["$FULL_DESC"]=1

            $EWW_BIN -c "$EWW_CFG" update usb_title="Drive Connected" usb_desc="$SIZE • $FULL_DESC" usb_icon="󰋊"
            $EWW_BIN -c "$EWW_CFG" open usb_popup
            reset_closer_timer
        fi

        # --- CASE B: USB/PERIPHERALS ---
        if [[ "$line" == *"(usb)"* ]]; then
            # Filter out hubs and internal roots to reduce noise
            if [[ "$DEVPATH" == *"/usb1/"* ]] || [[ "$DEVPATH" == *"/usb2/"* ]] || [[ "$DEVPATH" == *"/usb3/"* ]]; then continue; fi

            eval "$(udevadm info --query=property --path="/sys$DEVPATH" | grep -E 'ID_VENDOR=|ID_MODEL=|ID_USB_DRIVER=|ID_INPUT_KEYBOARD=|ID_INPUT_MOUSE=|ID_USB_INTERFACE_NUM=')"
            
            if [[ "$ID_USB_INTERFACE_NUM" != "00" ]] && [[ -n "$ID_USB_INTERFACE_NUM" ]]; then continue; fi
            if [[ "$ID_USB_DRIVER" == "usb-storage" ]]; then continue; fi

            FULL_DESC=$(clean_name "${ID_VENDOR//_/ } ${ID_MODEL//_/ }")
            if [ -z "$FULL_DESC" ] || [ "$FULL_DESC" == " " ]; then continue; fi

            # CHECK: Is this model already known/connected?
            # This is the line that fixes your Bluetooth ghost mouse issue.
            if [[ -n "${CONNECTED_MODELS[$FULL_DESC]}" ]]; then continue; fi
            
            # Add to memory
            CONNECTED_MODELS["$FULL_DESC"]=1

            ICON=""; TITLE="New Device"
            if [[ "$ID_INPUT_KEYBOARD" == "1" ]]; then ICON="󰌌"; TITLE="Keyboard Connected";
            elif [[ "$ID_INPUT_MOUSE" == "1" ]]; then ICON="󰍽"; TITLE="Mouse Connected";
            elif [[ "$FULL_DESC" == *"Audio"* ]] || [[ "$FULL_DESC" == *"Mic"* ]]; then ICON="󰍬"; TITLE="Audio Device";
            elif [[ "$FULL_DESC" == *"Camera"* ]]; then ICON="󰄀"; TITLE="Camera Connected"; fi

            $EWW_BIN -c "$EWW_CFG" update usb_title="$TITLE" usb_desc="$FULL_DESC" usb_icon="$ICON"
            $EWW_BIN -c "$EWW_CFG" open usb_popup
            reset_closer_timer
        fi
    fi
done
