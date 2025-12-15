#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_CFG="$HOME/.config/eww/popups/brightness"
EWW_BIN=$(which eww)

# We use two files:
# 1. A timestamp file to record exactly WHEN the last brightness change happened.
# 2. A lock file to ensure only ONE background "closer" process runs at a time.
TIMESTAMP_FILE="/tmp/eww_brightness_timestamp"
CLOSER_LOCK="/tmp/eww_brightness_closer.lock"

# --- HELPER FUNCTIONS ---

get_value() {
    # Returns percentage 0-100
    # Note: Using 'head -n 1' gets the first backlight device found.
    CARD=$(ls /sys/class/backlight | head -n 1)
    
    # Safety check: if no card is found, return 0 to avoid errors
    if [ -z "$CARD" ]; then
        echo "0"
        return
    fi
    
    CURRENT=$(brightnessctl -d "$CARD" get)
    MAX=$(brightnessctl -d "$CARD" max)
    
    if [ "$MAX" -eq 0 ]; then echo "0"; else echo $(( CURRENT * 100 / MAX )); fi
}

get_icon() {
    val=$(get_value)
    if [ "$val" -ge 70 ]; then
        echo "󰃠" # High
    elif [ "$val" -ge 30 ]; then
        echo "󰃟" # Medium
    else
        echo "󰃞" # Low
    fi
}

run_closer_daemon() {
    # This function attempts to start a background loop.
    # 'flock -n' ensures that if a loop is ALREADY running, this new instance 
    # just exits immediately. This prevents duplicate processes.
    (
        flock -n 9 || exit 0

        # If we are here, we are the one true Closer Daemon.
        while true; do
            # Read the time of the last activity
            if [ -f "$TIMESTAMP_FILE" ]; then
                LAST_TIME=$(cat "$TIMESTAMP_FILE")
            else
                LAST_TIME=0
            fi
            
            CURRENT_TIME=$(date +%s%3N) # Milliseconds for precision
            TIME_DIFF=$((CURRENT_TIME - LAST_TIME))

            # If 2000ms (2 seconds) have passed since the last activity:
            if [ "$TIME_DIFF" -ge 2000 ]; then
                $EWW_BIN -c "$EWW_CFG" close brightness_osd
                exit 0
            fi

            # Wait 0.5s before checking again
            sleep 0.5
        done
    ) 9>"$CLOSER_LOCK" &
}

show_osd() {
    # 1. Get current values
    VAL=$(get_value)
    ICON=$(get_icon)

    # 2. Update the "Last Activity" timestamp (in milliseconds)
    date +%s%3N > "$TIMESTAMP_FILE"

    # 3. Update Eww variables & Open Window
    # Update variables first so the window renders correct info immediately
    $EWW_BIN -c "$EWW_CFG" update brightness_value="$VAL" brightness_icon="$ICON"
    $EWW_BIN -c "$EWW_CFG" open brightness_osd

    # 4. Ensure the background closer is running
    run_closer_daemon
}

# --- ACTIONS ---

change_brightness() {
    CARD=$(ls /sys/class/backlight | head -n 1)
    
    # Safety check
    if [ -z "$CARD" ]; then return; fi

    if [[ "$1" == "inc" ]]; then
        brightnessctl -d "$CARD" set 5%+ -q
    elif [[ "$1" == "dec" ]]; then
        brightnessctl -d "$CARD" set 5%- -q
    fi
    show_osd
}

# --- EXECUTION ---

if [[ "$1" == "--inc" ]]; then
    change_brightness "inc"
elif [[ "$1" == "--dec" ]]; then
    change_brightness "dec"
else
    get_value
fi
