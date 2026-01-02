#!/bin/bash

# Function to get the title
get_title() {
    title=$(hyprctl activewindow -j | jq -r '.title')
    if [ "$title" == "null" ] || [ -z "$title" ]; then
        echo "Desktop"
    else
        echo "$title"
    fi
}

# Print initial title
get_title

# Listen for changes
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
    if [[ $line == *"activewindow>>"* ]]; then
        get_title
    fi
done
