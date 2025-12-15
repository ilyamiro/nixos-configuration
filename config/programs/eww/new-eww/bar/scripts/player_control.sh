#!/usr/bin/env bash

# 1. Get the name of the currently active player (e.g., firefox, spotify)
PLAYER=$(playerctl status -f "{{playerName}}" 2>/dev/null | head -n 1)

if [ -z "$PLAYER" ]; then exit 0; fi

command=$1
arg=$2

case $command in
    "seek")
        # Get total length in microseconds (1 second = 1,000,000 microseconds)
        LEN=$(playerctl -p "$PLAYER" metadata mpris:length 2>/dev/null)
        
        # specific check: if length is 0 or empty, we can't seek (it's a live stream or bugged)
        if [[ -z "$LEN" ]] || [[ "$LEN" -eq 0 ]]; then exit 0; fi

        # Use AWK for safe math. 
        # Formula: (Length_Microseconds * Target_Percent) / 100 / 1,000,000 = Target_Seconds
        # We perform the division by 100,000,000 directly.
        TARGET_SEC=$(awk -v len="$LEN" -v perc="$arg" 'BEGIN { printf "%.2f", (len * perc) / 100000000 }')

        # Send the position command explicitly to the detected player
        playerctl -p "$PLAYER" position "$TARGET_SEC"
        ;;
    
    "toggle_shuffle")
        playerctl -p "$PLAYER" shuffle toggle
        ;;
    
    "toggle_loop")
        # Your previous loop logic, but targeting the specific player
        current=$(playerctl -p "$PLAYER" loop)
        if [ "$current" == "None" ]; then
            playerctl -p "$PLAYER" loop Playlist
        elif [ "$current" == "Playlist" ]; then
            playerctl -p "$PLAYER" loop Track
        else
            playerctl -p "$PLAYER" loop None
        fi
        ;;
esac
