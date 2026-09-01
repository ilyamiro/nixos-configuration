#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

ACTION=$1

case $ACTION in
    raise)
        wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
        ;;
    lower)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        ;;
    mute-toggle)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
    mic-toggle)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        ;;
    mic-raise)
        wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ 5%+
        ;;
    mic-lower)
        wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-
        ;;
esac
