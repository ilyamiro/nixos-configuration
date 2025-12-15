#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/bar"
FILE="$HOME/.cache/eww_launch.favoritesbar"

run_eww() {
	${EWW} --config "$CFG" open favorites_win
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close favorites_win
	rm "$FILE"
fi


