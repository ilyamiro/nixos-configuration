#!/usr/bin/env bash

## Files and CMD
FILE="$HOME/.cache/eww_launch.sidebar"
CFG="$HOME/.config/eww/arin/sidedar"
EWW=`which eww`

## Run eww daemon if not running already
if [[ ! `pidof eww` ]]; then
	${EWW} daemon
	sleep 1
fi

## Open widgets 
run_eww() {
	${EWW} --config "$CFG" open-many \
			resources \
			logout \
			suspend \
			lock \
			reboot \
			shutdown \
			quotes
}

## Launch or close widgets accordingly
if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close resources logout suspend lock reboot shutdown quotes
	rm "$FILE"
fi
