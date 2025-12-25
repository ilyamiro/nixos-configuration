#!/usr/bin/env bash

# --- CONFIGURATION ---
EWW_CFG="$HOME/.config/eww/popups/volume"
EWW_BIN=$(which eww)

# We use a PID file to track the current "sleep" process.
# This prevents overflowing processes by killing the previous sleep command
# before starting a new one.
TIMER_PID="/tmp/eww_volume_timer.pid"

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

show_osd() {
    # 1. Kill the previous sleep timer if it exists.
    #    This "resets" the 2-second countdown.
    if [ -f "$TIMER_PID" ]; then
        kill "$(cat "$TIMER_PID")" 2>/dev/null
    fi

    # 2. Get current values
    VOL=$(pamixer --get-volume)
    ICON=$(get_icon)

    # 3. Update Eww variables & Open Window
    $EWW_BIN -c "$EWW_CFG" update volume_value="$VOL" volume_icon="$ICON"
    $EWW_BIN -c "$EWW_CFG" open volume_osd

    # 4. Start a background process that waits 2 seconds then closes the window.
    #    We put this in the background (&) so the script doesn't freeze.
    (
        sleep 2
        $EWW_BIN -c "$EWW_CFG" close volume_osd
        rm "$TIMER_PID" 2>/dev/null
    ) &

    # 5. Save the PID of the background process we just started.
    #    This allows step #1 to find and kill it next time.
    echo $! > "$TIMER_PID"
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
