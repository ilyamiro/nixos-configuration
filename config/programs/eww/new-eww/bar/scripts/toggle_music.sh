#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/bar"
FILE="$HOME/.cache/eww_launch.musicbar"

run_eww() {
	${EWW} --config "$CFG" open music_win 
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close music_win
	rm "$FILE"
fi


