#!/usr/bin/env bash

TMP_DIR="/tmp/eww_covers"
mkdir -p "$TMP_DIR"
PLACEHOLDER="$TMP_DIR/placeholder_blank.png"

# --- 1. ENSURE PLACEHOLDER EXISTS ---
if [ ! -f "$PLACEHOLDER" ]; then
    convert -size 500x500 xc:"#313244" "$PLACEHOLDER"
fi

# --- 2. CHECK STATUS ---
STATUS=$(playerctl status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then

    # --- 3. GET INFO ---
    rawUrl=$(playerctl metadata mpris:artUrl 2>/dev/null)
    title=$(playerctl metadata xesam:title 2>/dev/null)
    artist=$(playerctl metadata xesam:artist 2>/dev/null)
    
    # Generate Hash
    idStr="${title:-unknown}-${artist:-unknown}"
    trackHash=$(echo "$idStr" | md5sum | cut -d" " -f1)
    
    finalArt="$TMP_DIR/${trackHash}_art.jpg"
    blurPath="$TMP_DIR/${trackHash}_blur.png"
    colorPath="$TMP_DIR/${trackHash}_grad.txt"
    textPath="$TMP_DIR/${trackHash}_text.txt"
    lockFile="$TMP_DIR/${trackHash}.lock"

    # Default display values (Placeholder)
    displayArt="$PLACEHOLDER"
    displayBlur="$PLACEHOLDER"
    displayGrad="linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)"
    displayText="#cdd6f4"

    # --- 4. ASYNC BACKGROUND LOGIC ---
    if [ -f "$finalArt" ] && [ -s "$finalArt" ]; then
        # Cache Hit: Use the real files
        displayArt="$finalArt"
        # Only use blur/colors if they are ready too
        if [ -f "$blurPath" ]; then displayBlur="$blurPath"; fi
        if [ -f "$colorPath" ]; then displayGrad=$(cat "$colorPath"); fi
        if [ -f "$textPath" ]; then displayText=$(cat "$textPath"); fi
    else
        # Cache Miss: Trigger Background Download
        # We only spawn if not already downloading (checked via lockFile)
        if [ ! -f "$lockFile" ] && [ -n "$rawUrl" ]; then
            touch "$lockFile"
            (
                # A. Download/Copy Source
                if [[ "$rawUrl" == http* ]]; then
                    curl -s -L --max-time 10 -o "$finalArt" "$rawUrl"
                else
                    cleanPath=$(echo "$rawUrl" | sed 's/file:\/\///g')
                    if [ -f "$cleanPath" ]; then
                        cp "$cleanPath" "$finalArt"
                    else
                        # Invalid local file
                        cp "$PLACEHOLDER" "$finalArt"
                    fi
                fi

                # B. Validate Download
                if [ ! -s "$finalArt" ]; then
                    cp "$PLACEHOLDER" "$finalArt"
                fi

                # C. Generate Effects (Blur & Colors)
                # Check if it's just the placeholder (no need to compute colors)
                isPlaceholder=$(convert "$finalArt" -format "%[hex:u.p{0,0}]" info:)
                
                if [[ "$isPlaceholder" == "313244" ]]; then
                    cp "$finalArt" "$blurPath"
                    # Keep default colors
                else
                    convert "$finalArt" -blur 0x20 -brightness-contrast -30x-10 "$blurPath"
                    
                    colors=$(convert "$finalArt" -resize 100x100 -quantize RGB -colors 3 -depth 8 -format "%c" histogram:info: | \
                             sed -n 's/.*#\([0-9A-Fa-f]\{6\}\).*/#\1/p' | tr '\n' ' ')
                    read -r -a color_array <<< "$colors"
                    c1=${color_array[0]:-#cba6f7}
                    c2=${color_array[1]:-$c1}
                    c3=${color_array[2]:-$c1}
                    
                    echo "linear-gradient(45deg, $c1, $c2, $c3, $c1)" > "$colorPath"
                    opp_raw=$(convert xc:"$c1" -negate -depth 8 -format "%[hex:u]" info: | tr -d '\n')
                    echo "#$opp_raw" > "$textPath"
                fi

                # D. Cleanup
                rm "$lockFile"
                # Housekeeping: keep only recent 20 files
                (cd "$TMP_DIR" && ls -1t | tail -n +21 | xargs -r rm 2>/dev/null)
            ) &
        fi
        # While background job runs, we proceed to output the PLACEHOLDER immediately
    fi


    # --- 5. TIMING & DEVICE INFO ---
    metadata=$(playerctl metadata --format '{{mpris:length}} {{position}}' 2>/dev/null)
    len_micro=$(echo "$metadata" | awk '{print $1}')
    pos_micro=$(echo "$metadata" | awk '{print $2}')
    
    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then len_micro=1000000; fi
    len_sec=$((len_micro / 1000000))
    pos_sec=$((pos_micro / 1000000))
    percent=$((pos_sec * 100 / len_sec))
    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))
    time_str="${pos_str} / ${len_str}"

    player_raw=$(playerctl status -f "{{playerName}}" 2>/dev/null | head -n 1)
    player_nice="${player_raw^}"

    # Audio Device
    sink_name=$(pactl get-default-sink 2>/dev/null)
    dev_icon="󰓃"; dev_name="Speaker"
    if [[ "$sink_name" == *"bluez"* ]]; then
        dev_icon="󰂯"
        readable_name=$(pactl list sinks | grep -A 20 "$sink_name" | grep -m 1 "Description:" | cut -d: -f2 | xargs)
        if [ -n "$readable_name" ]; then dev_name="$readable_name"; else dev_name="Bluetooth"; fi
    elif [[ "$sink_name" == *"usb"* ]]; then
        dev_icon="󰓃"; dev_name="USB Audio"
    elif [[ "$sink_name" == *"pci"* ]]; then
        dev_icon="󰓃"; dev_name="System"
    fi

    # --- 6. JSON OUTPUT ---
    jq -n -c \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg status "$STATUS" \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg time_str "$time_str" \
        --arg percent "$percent" \
        --arg source "$player_nice" \
        --arg pname "$player_raw" \
        --arg blur "$displayBlur" \
        --arg grad "$displayGrad" \
        --arg txtColor "$displayText" \
        --arg devIcon "$dev_icon" \
        --arg devName "$dev_name" \
        --arg finalArt "$displayArt" \
        '{
            title: $title,
            artist: $artist,
            status: $status,
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
            deviceName: $devName,
            artUrl: $finalArt
        }'

else
    # Fallback
    jq -n -c \
    --arg placeholder "$PLACEHOLDER" \
    '{
        title: "Not Playing",
        artist: "",
        status: "Stopped",
        percent: 0,
        lengthStr: "00:00",
        positionStr: "00:00",
        timeStr: "--:-- / --:--",
        source: "Offline",
        playerName: "",
        blur: $placeholder,
        grad: "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)",
        textColor: "#cdd6f4",
        deviceIcon: "󰓃",
        deviceName: "Speaker",
        artUrl: $placeholder
    }'
fi
