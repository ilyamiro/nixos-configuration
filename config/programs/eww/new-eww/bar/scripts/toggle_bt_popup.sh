#!/usr/bin/env bash

# Path to Eww binary
EWW=$(which eww)
CFG="$HOME/.config/eww/bar"
PID_FILE="$HOME/.cache/bt_scan_pid"

# Lock file to track state
FILE="$HOME/.cache/eww_launch.bluetooth"

run_eww() {
    ${EWW} --config ${CFG} open bluetooth_win
    { echo "scan on"; sleep infinity; } | bluetoothctl > /dev/null 2>&1 &
    echo $! > "$PID_FILE"
}

if [[ ! -f "$FILE" ]]; then
    touch "$FILE"
    run_eww
else
    ${EWW} --config ${CFG} close bluetooth_win

   if [ -f "$PID_FILE" ]; then
        # Kill the pipe process
        kill $(cat "$PID_FILE") 2>/dev/null
        rm "$PID_FILE"
    fi
    
    # Ensure scan is actually off
    bluetoothctl scan off > /dev/null 2>&1

    rm "$FILE"
fi
