#!/usr/bin/env bash

player_status=$(playerctl status 2>/dev/null)
if [ "$player_status" = "Playing" ] || [ "$player_status" = "Paused" ]; then
    # Get metadata safely using playerctl's format to handle special chars
    # We strip 'file://' from the art url for CSS compatibility
    playerctl metadata --format '{"text": "{{title}}", "artist": "{{artist}}", "status": "{{status}}", "artUrl": "{{mpris:artUrl}}"}' \
    | sed 's/file:\/\///g'

else
    echo '{"text": "", "artist": "", "status": "Stopped", "artUrl": ""}'
fi 
