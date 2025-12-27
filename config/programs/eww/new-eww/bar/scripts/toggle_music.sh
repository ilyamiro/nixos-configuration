#!/usr/bin/env bash

# --- CONFIGURATION ---
# Set to "false" to disable the Cava/Kitty visualizer window
ENABLE_VISUALIZER="false"

# PATHS
EWW=`which eww`
CFG="$HOME/.config/eww/bar"
LOCK_FILE="$HOME/.cache/eww_launch.musicbar"

# CUSTOM CONFIGS
# We use a custom Cava config to force the bars to look right for the widget size
CAVA_CFG="$HOME/.config/eww/bar/scripts/cava_widget.conf"
# We pass specific flags to Kitty to make it minimalist
KITTY_CLASS="music_vis"

run_widgets() {
    # 1. Open Eww Music Window
    ${EWW} --config "$CFG" open music_win 

    # 2. Open Cava in a special Kitty window (Only if enabled)
    if [[ "$ENABLE_VISUALIZER" == "true" ]]; then
        # --class: Allows Hyprland to target this specific window
        # --hold: Keeps it open
        # -o: Overrides kitty config settings on the fly (transparency, font size)
        kitty --class "$KITTY_CLASS" \
              -o window_padding_width=10 \
              -o font_size=6 \
              -o confirm_os_window_close=0 \
              cava -p "$CAVA_CFG" &
    fi
}

close_widgets() {
    # Close Eww
    ${EWW} --config "$CFG" close music_win      
    
    # Close the specific Kitty window
    # We use Hyprland's dispatcher to close it gracefully by class name
    # We run this regardless of ENABLE_VISUALIZER setting to ensure cleanup of previous sessions
    hyprctl dispatch closewindow "address:$(hyprctl clients -j | jq -r ".[] | select(.class==\"$KITTY_CLASS\") | .address")"
}

if [[ ! -f "$LOCK_FILE" ]]; then
    touch "$LOCK_FILE"
    run_widgets
else
    close_widgets
    rm "$LOCK_FILE"
fi
