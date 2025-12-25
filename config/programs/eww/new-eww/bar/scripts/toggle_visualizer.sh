#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/bar"
FILE="$HOME/.cache/eww_launch.music_vis_bar"

run_eww() {
	${EWW} --config "$CFG" open visualizer_win 
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close visualizer_win 
	rm "$FILE"
fi



