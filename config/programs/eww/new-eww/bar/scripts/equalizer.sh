#!/usr/bin/env bash

STATE_FILE="/tmp/eww_eq_state.json"
PRESET_DIR="$HOME/.config/easyeffects/output"
PRESET_NAME="eww_live_eq"
PRESET_FILE="$PRESET_DIR/${PRESET_NAME}.json"

mkdir -p "$PRESET_DIR"

# Default state (Now includes "pending": false)
if [ ! -f "$STATE_FILE" ]; then
    echo '{"b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0, "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0, "preset": "Flat", "pending": false}' > "$STATE_FILE"
fi

apply_eq() {
    vals=$(cat "$STATE_FILE")
    python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    slider_map = { 0:0, 1:3, 2:6, 3:9, 4:12, 5:15, 6:18, 7:21, 8:24, 9:27 }
    freqs = [32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000]
    gains = [float(data['b1']), float(data['b2']), float(data['b3']), float(data['b4']), float(data['b5']), float(data['b6']), float(data['b7']), float(data['b8']), float(data['b9']), float(data['b10'])]
    bands = {}
    for i in range(32):
        freq = freqs[i] if i < len(freqs) else 20000.0
        gain = 0.0
        for s_idx, b_idx in slider_map.items():
            if i == b_idx:
                gain = gains[s_idx]
                break
        bands[f\"band{i}\"] = { \"frequency\": freq, \"gain\": gain, \"mode\": \"Bell\", \"mute\": False, \"q\": 1.0, \"solo\": False, \"width\": 1.0, \"slope\": \"x1\" }
    preset = { \"output\": { \"blocklist\": [], \"plugins_order\": [ \"equalizer\" ], \"equalizer\": { \"bypass\": False, \"input-gain\": 0.0, \"output-gain\": 0.0, \"left\": bands, \"right\": bands, \"mode\": \"IIR\", \"num-bands\": 32, \"split-channels\": False } } }
    print(json.dumps(preset, indent=4))
except:
    sys.exit(1)
" "$vals" > "$PRESET_FILE"

    easyeffects -l "$PRESET_NAME" >/dev/null 2>&1 &
}

# Save state helper (Always sets pending to false because Presets apply instantly)
save_preset() {
    jq -n -c --arg b1 "$1" --arg b2 "$2" --arg b3 "$3" --arg b4 "$4" --arg b5 "$5" \
          --arg b6 "$6" --arg b7 "$7" --arg b8 "$8" --arg b9 "$9" --arg b10 "${10}" --arg p "${11}" \
       '{"b1": $b1, "b2": $b2, "b3": $b3, "b4": $b4, "b5": $b5, "b6": $b6, "b7": $b7, "b8": $b8, "b9": $b9, "b10": $b10, "preset": $p, "pending": false}' > "$STATE_FILE"
}

cmd=$1
arg1=$2
arg2=$3

case $cmd in
    "get") cat "$STATE_FILE" ;;
    "set_band")
        # SLIDER MOVE: Set pending = true, Preset = Custom. DO NOT APPLY.
        tmp=$(cat "$STATE_FILE")
        updated=$(echo "$tmp" | jq -c --arg val "$arg2" ".b$arg1 = \$val | .preset = \"Custom\" | .pending = true")
        echo "$updated" > "$STATE_FILE"
        ;;
    "apply")
        # APPLY BUTTON: Set pending = false, then Apply.
        tmp=$(cat "$STATE_FILE")
        updated=$(echo "$tmp" | jq -c ".pending = false")
        echo "$updated" > "$STATE_FILE"
        apply_eq
        ;;
    "preset")
        # PRESET CLICK: Save values (pending=false) and Apply Instantly.
        case $arg1 in
            "Flat")    save_preset 0 0 0 0 0 0 0 0 0 0 "Flat" ;;
            "Bass")    save_preset 5 7 5 2 1 0 0 0 1 2 "Bass" ;;
            "Treble")  save_preset -2 -1 0 1 2 3 4 5 6 6 "Treble" ;;
            "Vocal")   save_preset -2 -1 1 3 5 5 4 2 1 0 "Vocal" ;;
            "Pop")     save_preset 2 4 2 0 1 2 4 2 1 2 "Pop" ;;
            "Rock")    save_preset 5 4 2 -1 -2 -1 2 4 5 6 "Rock" ;;
            "Jazz")    save_preset 3 3 1 1 1 1 2 1 2 3 "Jazz" ;;
            "Classic") save_preset 0 1 2 2 2 2 1 2 3 4 "Classic" ;;
        esac
        apply_eq
        ;;
esac
