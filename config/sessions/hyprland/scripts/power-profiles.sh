#!/usr/bin/env bash

# --- 1. Toggle Logic ---
if pgrep -x "rofi" > /dev/null; then
    pkill rofi
    exit 0
fi

# --- 2. Current Status ---
# We grab the status to display in the prompt
CURRENT=$(powerprofilesctl get)

# --- 3. Big & Colorful Theme Overrides ---
# - Width: 600px (Wide and spacious)
# - Font: Large (Size 14)
# - Radius: Strict 4px everywhere
# - Spacing: Generous padding to make it feel like a HUD
ROFI_OVERRIDE="window {
                 width: 600px;
                 height: 360px;
                 border: 3px;
                 border-color: #cba6f7; /* Mauve Border */
                 border-radius: 4px;
                 background-color: #1e1e2e;
               }
               mainbox {
                 padding: 30px;
                 background-color: inherit;
               }
               inputbar {
                 background-color: transparent;
                 margin: 0px 0px 20px 0px;
                 children: [ prompt ];
               }
               prompt {
                 background-color: #cba6f7; /* Mauve Header */
                 text-color: #1e1e2e;       /* Dark Text */
                 border-radius: 4px;
                 padding: 12px 20px;
                 margin: 0px;
                 font: \"JetBrainsMono Nerd Font Bold 16\";
               }
               listview {
                 columns: 1;
                 lines: 3;
                 spacing: 15px;
                 margin: 0px;
                 scrollbar: false;
                 background-color: transparent;
               }
               element {
                 orientation: horizontal;
                 children: [ element-text ];
                 padding: 15px 20px;
                 border-radius: 4px;
                 background-color: #313244; /* Surface0 */
               }
               element selected {
                 background-color: #45475a; /* Surface1 */
                 border: 2px;
                 border-color: #cba6f7;     /* Mauve Highlight */
                 text-color: #cdd6f4;
               }
               element-text {
                 vertical-align: 0.5;
                 horizontal-align: 0.0;
                 font: \"JetBrainsMono Nerd Font Bold 14\";
                 background-color: transparent;
                 text-color: inherit;
               }"

# --- 4. Colorful Options (Pango Markup) ---
# We inject Catppuccin Hex codes directly into the strings.
# Red (#f38ba8) for Performance
# Blue (#89b4fa) for Balanced
# Green (#a6e3a1) for Power Saver

# Note: We use hidden characters (ZWSP) or just rely on the text for the case switch later.
# To keep the case switch simple, I will check the raw text passed back.

OPT_PERF="<span color='#f38ba8'><b>PERFORMANCE</b></span>"
OPT_BAL="<span color='#89b4fa'><b>BALANCED</b></span>"
OPT_SAVER="<span color='#a6e3a1'><b>POWER SAVER</b></span>"

OPTIONS="$OPT_PERF\n$OPT_BAL\n$OPT_SAVER"

# --- 5. Rofi Execution ---
# -markup-rows enables the color coding
CHOICE=$(echo -e "$OPTIONS" | rofi -dmenu \
    -markup-rows \
    -p "Current: ${CURRENT^^}" \
    -config ~/.config/rofi/config.rasi \
    -theme-str "$ROFI_OVERRIDE")

if [ -z "$CHOICE" ]; then
    exit 0
fi

# --- 6. Apply Changes ---
# We match loosely against the text because the string now contains HTML tags.
# We use wildcard (*) matching inside the case statement.

case "$CHOICE" in
    *"PERFORMANCE"*)
        powerprofilesctl set performance
        notify-send "System" "Switched to Performance Mode"
        ;;
    *"BALANCED"*)
        powerprofilesctl set balanced
        notify-send "System" "Switched to Balanced Mode"
        ;;
    *"POWER SAVER"*)
        powerprofilesctl set power-saver
        # Optional: Disable animations on saver
        hyprctl keyword animations:enabled 0
        notify-send "System" "Switched to Power Saver"
        ;;
esac
