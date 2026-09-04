#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/config.sh"

ACTION=$1

# Upper limit for wpctl, as a factor. general.maxVolume is a percentage written
# by the settings panel; keep the media keys in sync with the GUI sliders.
max_volume_factor() {
    local gen_json max
    gen_json="$(get_setting "general" '{}')"
    max="$(printf '%s' "$gen_json" | jq -r '.maxVolume // 100' 2>/dev/null)"
    [[ "$max" =~ ^[0-9]+$ ]] || max=100
    (( max < 100 )) && max=100
    (( max > 200 )) && max=200
    awk -v m="$max" 'BEGIN { printf "%.2f", m / 100 }'
}

LIMIT="$(max_volume_factor)"

case $ACTION in
    raise)
        wpctl set-volume -l "$LIMIT" @DEFAULT_AUDIO_SINK@ 5%+
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
        wpctl set-volume -l "$LIMIT" @DEFAULT_AUDIO_SOURCE@ 5%+
        ;;
    mic-lower)
        wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-
        ;;
esac
