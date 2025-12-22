#!/usr/bin/env bas#!/usr/bin/env bash

# --- 1. Toggle Logic ---
if pgrep -x "rofi" > /dev/null; then
    pkill rofi
    exit 0
fi

# --- 2. Configuration ---
MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')

# --- 3. Cool Theme Overrides ---
# We inject specific colors and sizing to make it pop.
# - window: smaller, centered, blue border, rounded
# - prompt: styled like a header badge
# - listview: spacing between items
# - element: rounded corners, slightly smaller to look like "cards"
ROFI_OVERRIDE="window {
                 width: 400px;
                 height: 450px;
                 border: 2px;
                 border-color: #89b4fa;
                 border-radius: 4px;
               }
               mainbox {
                 padding: 20px;
               }
               inputbar {
                 background-color: transparent;
                 margin: 0px 0px 10px 0px;
                 children: [ prompt ];
               }
               prompt {
                 background-color: #89b4fa;
                 text-color: #1e1e2e;
                 border-radius: 4px;
                 padding: 10px 14px;
                 margin: 0px;
               }
               listview {
                 columns: 1;
                 lines: 8;
                 spacing: 6px;
                 margin: 10px 0px 0px 0px;
               }
               element {
                 orientation: horizontal;
                 children: [ element-text ];
                 padding: 10px 15px;
                 border-radius: 4px;
               }
               element selected {
                 background-color: #313244;
                 text-color: #89b4fa;
                 border: 1px;
                 border-color: #89b4fa;
               }
               element-icon { enabled: false; }
               element-text {
                 vertical-align: 0.5;
                 horizontal-align: 0.0;
               }"

# --- 4. Step 1: Select Resolution (Max 1080p) ---
RESOLUTIONS="1920x1080 (FHD)
1600x900
1366x768
1280x720 (HD)
1024x768
800x600"

SEL_RES_LABEL=$(echo -e "$RESOLUTIONS" | rofi -dmenu \
    -p "Resolution" \
    -config ~/.config/rofi/config.rasi \
    -theme-str "$ROFI_OVERRIDE")

if [ -z "$SEL_RES_LABEL" ]; then exit 0; fi

# Extract resolution (remove labels like "(FHD)")
SEL_RES=$(echo "$SEL_RES_LABEL" | awk '{print $1}')

# --- 5. Step 2: Select Refresh Rate (Max 144Hz) ---
RATES="144Hz
120Hz
100Hz
75Hz
60Hz
50Hz
30Hz"

SEL_RATE_LABEL=$(echo -e "$RATES" | rofi -dmenu \
    -p "Rate @ $SEL_RES" \
    -config ~/.config/rofi/config.rasi \
    -theme-str "$ROFI_OVERRIDE")

if [ -z "$SEL_RATE_LABEL" ]; then exit 0; fi

# --- 6. Apply ---
SEL_RATE=${SEL_RATE_LABEL%Hz}
CMD="$MONITOR,${SEL_RES}@${SEL_RATE},auto,1"

notify-send "Display Update" "Applying: $SEL_RES @ ${SEL_RATE}Hz"
hyprctl keyword monitor "$CMD"
