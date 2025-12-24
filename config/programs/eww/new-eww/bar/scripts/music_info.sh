#!/usr/bin/env bash

# Check status first
STATUS=$(playerctl status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
    # --- 1. GET METADATA ---
    metadata=$(playerctl metadata --format '{{mpris:length}} {{position}}')
    len_micro=$(echo "$metadata" | awk '{print $1}')
    pos_micro=$(echo "$metadata" | awk '{print $2}')
    
    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then len_micro=1000000; fi

    len_sec=$((len_micro / 1000000))
    pos_sec=$((pos_micro / 1000000))
    percent=$((pos_sec * 100 / len_sec))

    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))
    time_str="${pos_str} / ${len_str}"

    player_raw=$(playerctl status -f "{{playerName}}" | head -n 1)
    player_nice="${player_raw^}"

    # --- 2. GET AUDIO DEVICE INFO (UPDATED) ---
    # Get default sink name
    sink_name=$(pactl get-default-sink 2>/dev/null)
    
    # Defaults
    dev_icon="󰓃" # Generic Speaker
    dev_name="Speaker"

    if [[ "$sink_name" == *"bluez"* ]]; then
        dev_icon="󰂯"
        # Extract the human-readable description (Device Name)
        # We find the sink name, look for "Description:", and clean it
        readable_name=$(pactl list sinks | grep -A 20 "$sink_name" | grep -m 1 "Description:" | cut -d: -f2 | xargs)
        
        if [ -n "$readable_name" ]; then
            dev_name="$readable_name"
        else
            dev_name="Bluetooth"
        fi
    elif [[ "$sink_name" == *"usb"* ]]; then
        dev_icon="󰓃"
        dev_name="USB Audio"
    elif [[ "$sink_name" == *"pci"* ]]; then
        dev_icon="󰓃" 
        dev_name="System" # Likely internal speakers
    fi

    # --- 3. IMAGE & COLOR PROCESSING ---
    artUrl=$(playerctl metadata mpris:artUrl | sed 's/file:\/\///g')
    tmpDir="/tmp/eww_covers"
    mkdir -p "$tmpDir"

    # Default Gradient & Text Color
    grad="linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)"
    txtColor="#cdd6f4"
    blurPath=""

    if [ -n "$artUrl" ]; then
        urlHash=$(echo "$artUrl" | md5sum | cut -d" " -f1)
        blurPath="$tmpDir/${urlHash}_blur.png"
        colorPath="$tmpDir/${urlHash}_grad.txt"
        textColorPath="$tmpDir/${urlHash}_text.txt"

        if [ ! -f "$blurPath" ]; then
            convert "$artUrl" -blur 0x25 -brightness-contrast -30x-10 "$blurPath" &
            if [ -f "$artUrl" ]; then
                colors=$(convert "$artUrl" -resize 100x100 -quantize RGB -colors 3 -depth 8 -format "%c" histogram:info: | \
                         sed -n 's/.*#\([0-9A-Fa-f]\{6\}\).*/#\1/p' | tr '\n' ' ')
                read -r -a color_array <<< "$colors"
                c1=${color_array[0]:-#cba6f7}
                c2=${color_array[1]:-$c1}
                c3=${color_array[2]:-$c1}
                echo "linear-gradient(45deg, $c1, $c2, $c3, $c1)" > "$colorPath"
                opp_raw=$(convert xc:"$c1" -negate -depth 8 -format "%[hex:u]" info: | tr -d '\n')
                echo "#$opp_raw" > "$textColorPath"
            fi
            (cd "$tmpDir" && ls -1t | tail -n +51 | xargs -r rm) &
        fi
        if [ -f "$colorPath" ]; then grad=$(cat "$colorPath"); fi
        if [ -f "$textColorPath" ]; then txtColor=$(cat "$textColorPath"); fi
    fi

    # --- 4. JSON OUTPUT ---
    playerctl metadata --format '{"title": "{{title}}", "artist": "{{artist}}", "artUrl": "{{mpris:artUrl}}", "status": "{{status}}"}' \
    | sed 's/file:\/\///g' | jq -c \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg time_str "$time_str" \
        --arg percent "$percent" \
        --arg source "$player_nice" \
        --arg pname "$player_raw" \
        --arg blur "$blurPath" \
        --arg grad "$grad" \
        --arg txtColor "$txtColor" \
        --arg devIcon "$dev_icon" \
        --arg devName "$dev_name" \
        '. + {
            length: $len, 
            position: $pos, 
            lengthStr: $len_str, 
            positionStr: $pos_str, 
            timeStr: $time_str,
            percent: $percent,
            source: $source,
            playerName: $pname,
            blur: $blur,
            grad: $grad,
            textColor: $txtColor,
            deviceIcon: $devIcon,
            deviceName: $devName
        }'

else
    # Fallback
    echo '{"title": "Not Playing", "artist": "", "status": "Stopped", "percent": 0, "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--", "source": "Offline", "playerName": "", "blur": "", "grad": "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)", "textColor": "#cdd6f4", "deviceIcon": "󰓃", "deviceName": "Speaker"}'
fi
