#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/popups/search-bar"
FILE="$HOME/.cache/eww_launch.searchbar"

run_eww() {
	${EWW} --config "$CFG" open search_bar 
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close search_bar
	rm "$FILE"
fi


