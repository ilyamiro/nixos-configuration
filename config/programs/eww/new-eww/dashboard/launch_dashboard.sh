#!/usr/bin/env bash

## Files and cmd
FILE="$HOME/.cache/eww_launch.dashboard"
CFG="$HOME/.config/eww/dashboard"
EWW=`which eww`
## Open widgets 

run_eww() {
	${EWW} --config "$CFG" --debug open-many \
		   background \
		   profile \
		   system \
		   clock \
		   uptime \
		   music \
		   github \
		   reddit \
		   twitter \
		   youtube \
		   weather \
		   apps \
		   mail \
		   logout \
		   sleep \
		   reboot \
		   poweroff \
		   folders
}

## Launch or close widgets accordingly
if [[ ! -f "$FILE" ]]; then
	touch "$FILE"
	run_eww
else
	${EWW} --config "$CFG" close \
					background profile system clock uptime music github \
					reddit twitter youtube weather apps mail logout sleep reboot poweroff folders
	rm "$FILE"
fi
