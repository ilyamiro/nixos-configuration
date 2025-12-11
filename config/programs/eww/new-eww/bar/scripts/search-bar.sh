#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/bar/search-bar"
FILE="$HOME/.cache/eww_launch.searchbar"

run_eww() {
	${EWW} --config "$CFG" open search 
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close search
	rm "$FILE"
fi

