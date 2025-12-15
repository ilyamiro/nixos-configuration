#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_CFG="$HOME/.config/eww/popups/volume"
EWW_BIN=$(which eww)

# We use two files:
# 1. A timestamp file to record exactly WHEN the last volume change happened.
# 2. A lock file to ensure only ONE background "closer" process runs at a time.
TIMESTAMP_FILE="/tmp/eww_volume_timestamp"
CLOSER_LOCK="/tmp/eww_volume_closer.lock"

# --- HELPER FUNCTIONS ---

get_icon() {
    # Get mute status and raw volume number
    IS_MUTED=$(pamixer --get-mute)
    VOL_NUM=$(pamixer --get-volume)

    # Show mute icon if technically muted OR if volume is 0
    if [[ "$IS_MUTED" == "true" ]] || [[ "$VOL_NUM" -eq 0 ]]; then
        echo "󰝟" # Muted / Silent
    else
        echo "" # Volume High
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
            # Read the time of the last volume change
            if [ -f "$TIMESTAMP_FILE" ]; then
                LAST_TIME=$(cat "$TIMESTAMP_FILE")
            else
                LAST_TIME=0
            fi
            
            CURRENT_TIME=$(date +%s%3N) # Milliseconds for precision
            TIME_DIFF=$((CURRENT_TIME - LAST_TIME))

            # If 2000ms (2 seconds) have passed since the last activity:
            if [ "$TIME_DIFF" -ge 2000 ]; then
                $EWW_BIN -c "$EWW_CFG" close volume_osd
                exit 0
            fi

            # Wait 0.5s before checking again
            sleep 0.5
        done
    ) 9>"$CLOSER_LOCK" &
}

show_osd() {
    # 1. Get current values
    VOL=$(pamixer --get-volume)
    ICON=$(get_icon)

    # 2. Update the "Last Activity" timestamp (in milliseconds)
    date +%s%3N > "$TIMESTAMP_FILE"
    
    # 3. Update Eww variables & Open Window
    # We update the variables first so the window doesn't flicker with old data
    $EWW_BIN -c "$EWW_CFG" update volume_value="$VOL" volume_icon="$ICON"
    $EWW_BIN -c "$EWW_CFG" open volume_osd

    # 4. Ensure the background closer is running
    run_closer_daemon
}

# --- ACTIONS ---

get_volume() {
    volume=$(pamixer --get-volume)
    if [[ "$volume" -eq "0" ]]; then
        echo "Muted"
    else
        echo "$volume %"
    fi
}

inc_volume() {
    if [ "$(pamixer --get-mute)" == "true" ]; then
        pamixer -u
    else
        pamixer -i 5 
    fi
    show_osd
}

dec_volume() {
    if [ "$(pamixer --get-mute)" == "true" ]; then
        pamixer -u
    else
        pamixer -d 5
    fi
    show_osd
}

toggle_mute() {
    pamixer -t
    show_osd
}

toggle_mic() {
    pamixer --default-source -t
}

# --- EXECUTION ---

if [[ "$1" == "--get" ]]; then
    get_volume
elif [[ "$1" == "--inc" ]]; then
    inc_volume
elif [[ "$1" == "--dec" ]]; then
    dec_volume
elif [[ "$1" == "--toggle" ]]; then
    toggle_mute
elif [[ "$1" == "--toggle-mic" ]]; then
    toggle_mic
else
    get_volume
fi
