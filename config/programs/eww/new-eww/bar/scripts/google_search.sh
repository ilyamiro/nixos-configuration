#!/usr/bin/env bash

QUERY="$1"
EWW=`which eww`
CFG="$HOME/.config/eww/popups/search-bar"
FILE="$HOME/.cache/eww_launch.searchbar"

# 1. Check if query is empty
if [[ -z "$QUERY" ]]; then
    exit 0
fi

# 2. Open the browser
xdg-open "https://www.google.com/search?q=${QUERY}"

# List of common browser class names (regex). Add yours here if it's unique (e.g. 'vivaldi|zen').
BROWSER_REGEX="firefox|google-chrome|zen-browser"

# Use hyprctl to get clients, jq to filter for the browser, and extract the window address
# 'test' performs a case-insensitive regex match on the window class
WINDOW_ADDRESS=$(hyprctl clients -j | jq -r ".[] | select(.class | test(\"$BROWSER_REGEX\"; \"i\")) | .address" | head -n 1)

# If a browser window was found, switch focus to it
if [[ -n "$WINDOW_ADDRESS" ]]; then
    hyprctl dispatch focuswindow address:$WINDOW_ADDRESS
fi

${EWW} --config ${CFG} close search_bar

# 4. Clear the input variable
${EWW} --config ${CFG} update search_input=""

# rm "$FILE"
