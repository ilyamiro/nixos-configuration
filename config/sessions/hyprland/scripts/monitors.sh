#!/usr/bin/env bash

# --- 1. Toggle Logic ---
if pgrep -x "rofi" > /dev/null; then
    pkill rofi
    exit 0
fi

# --- 2. Configuration ---
MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')

# --- 3. Theme Overrides ---
ROFI_OVERRIDE="
    * {
        font: \"JetBrainsMono Nerd Font 11\";
        background-color: transparent;
        text-color: #cdd6f4;
        margin: 0;
        padding: 0;
        spacing: 0;
    }

    window {
        width: 450px;
        background-color: #1e1e2ef2;
        border: 2px;
        border-color: rgba(255, 255, 255, 0.08);
        border-radius: 20px;
        anchor: center;
        location: center;
    }

    mainbox {
        orientation: vertical;
        children: [ inputbar, listview ];
        padding: 20px;
        spacing: 15px;
    }

    inputbar {
        children: [ prompt ];
        orientation: horizontal;
    }

    prompt {
        background-image: linear-gradient(to right, #cba6f7, #89b4fa);
        text-color: #1e1e2e;
        padding: 10px 14px;
        border-radius: 12px;
        font: \"JetBrainsMono Nerd Font ExtraBold 12\";
        horizontal-align: 0.5;
        width: 100%;
    }

    listview {
        layout: vertical;
        lines: 6; 
        columns: 1;
        spacing: 6px;
    }

    element {
        orientation: horizontal;
        children: [ element-text ];
        padding: 10px;
        border-radius: 10px;
        border: 1px;
        border-color: transparent;
    }

    /* THE FIX: Explicitly set background for Normal AND Alternate rows */
    element normal.normal, element alternate.normal {
        background-color: rgba(49, 50, 68, 0.2); 
        text-color: #cdd6f4;
    }

    /* Selected State */
    element selected.normal {
        background-image: linear-gradient(to bottom, #45475a, #313244);
        border-color: #cba6f7;
        text-color: #cba6f7;
    }

    element-text {
        vertical-align: 0.5;
        horizontal-align: 0.5;
        text-color: inherit;
    }
"

# --- 4. Resolution ---
RESOLUTIONS="1920x1080
1600x900
1366x768
1280x720
1024x768
800x600"

SEL_RES=$(echo -e "$RESOLUTIONS" | rofi -dmenu \
    -p "Resolution" \
    -config /dev/null \
    -theme-str "$ROFI_OVERRIDE")

if [ -z "$SEL_RES" ]; then exit 0; fi

# --- 5. Refresh Rate ---
RATES="144Hz
120Hz
100Hz
75Hz
60Hz
30Hz"

SEL_RATE_LABEL=$(echo -e "$RATES" | rofi -dmenu \
    -p "Refresh Rate" \
    -config /dev/null \
    -theme-str "$ROFI_OVERRIDE")

if [ -z "$SEL_RATE_LABEL" ]; then exit 0; fi

# --- 6. Apply ---
SEL_RATE=${SEL_RATE_LABEL%Hz}
CMD="$MONITOR,${SEL_RES}@${SEL_RATE},auto,1"

notify-send "Display Update" "Applying: $SEL_RES @ ${SEL_RATE}Hz"
hyprctl keyword monitor "$CMD"
