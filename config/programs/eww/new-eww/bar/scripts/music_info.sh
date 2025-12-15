#!/usr/bin/env bash

STATUS=$(playerctl status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
    # Get data in seconds (s) and microseconds (m)
    # We use mpris:length (microseconds) and position (microseconds)
    metadata=$(playerctl metadata --format '{{mpris:length}} {{position}} {{mpris:artUrl}} {{title}} {{artist}} {{album}} {{playerName}}')
    
    # Parse the data
    len_micro=$(echo "$metadata" | awk '{print $1}')
    pos_micro=$(echo "$metadata" | awk '{print $2}')
    
    # Check if length is valid (some streams return 0 or empty)
    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then
        len_micro=1000000 # Avoid division by zero
    fi

    # Calculate percentages and seconds for display
    len_sec=$((len_micro / 1000000))
    pos_sec=$((pos_micro / 1000000))
    percent=$((pos_sec * 100 / len_sec))

    # Format time string (MM:SS)
    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))

    # JSON Construction
    # We invoke playerctl again for safe string extraction (titles with quotes etc)
    playerctl metadata --format '
    {
        "title": "{{title}}",
        "artist": "{{artist}}",
        "album": "{{album}}",
        "artUrl": "{{mpris:artUrl}}",
        "status": "{{status}}",
        "playerName": "{{playerName}}"
    }' | sed 's/file:\/\///g' | jq -c \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg percent "$percent" \
        '. + {length: $len, position: $pos, lengthStr: $len_str, positionStr: $pos_str, percent: $percent}'
else
    echo '{"title": "Not Playing", "artist": "", "status": "Stopped", "percent": 0, "lengthStr": "00:00", "positionStr": "00:00"}'
fi
