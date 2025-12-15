#!/usr/bin/env bash

EWW=`which eww`
CFG="$HOME/.config/eww/bar/"
FILE="$HOME/.cache/eww_launch.bar"

run_eww() {
	${EWW} --config "$CFG" open bar 
}

if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close bar
	rm "$FILE"
fi


