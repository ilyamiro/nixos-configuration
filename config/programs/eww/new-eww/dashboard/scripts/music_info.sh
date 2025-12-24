#!/usr/bin/env bash

STATUS=$(playerctl status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
    # Get metadata numbers
    metadata=$(playerctl metadata --format '{{mpris:length}} {{position}}')
    len_micro=$(echo "$metadata" | awk '{print $1}')
    pos_micro=$(echo "$metadata" | awk '{print $2}')
    
    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then
        len_micro=1000000
    fi

    len_sec=$((len_micro / 1000000))
    pos_sec=$((pos_micro / 1000000))
    percent=$((pos_sec * 100 / len_sec))

    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))
    time_str="${pos_str} / ${len_str}"

    # Get the raw player name for the control script
    player_raw=$(playerctl status -f "{{playerName}}" | head -n 1)
    # Make a pretty name for the UI
    player_nice="${player_raw^}"

    # JSON Construction
    # We add 'playerName' explicitly here
    playerctl metadata --format '
    {
        "title": "{{title}}",
        "artist": "{{artist}}",
        "artUrl": "{{mpris:artUrl}}",
        "status": "{{status}}"
    }' | sed 's/file:\/\///g' | jq -c \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg time_str "$time_str" \
        --arg percent "$percent" \
        --arg source "$player_nice" \
        --arg pname "$player_raw" \
        '. + {
            length: $len, 
            position: $pos, 
            lengthStr: $len_str, 
            positionStr: $pos_str, 
            timeStr: $time_str,
            percent: $percent,
            source: $source,
            playerName: $pname
        }'
else
    echo '{"title": "Not Playing", "artist": "", "status": "Stopped", "percent": 0, "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--", "source": "Offline", "playerName": ""}'
fi
