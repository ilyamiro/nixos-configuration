#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

[[ ${1:-} == "--verbose" ]] && shift
ACTION=${1:-get}
VALUE=${2:-}
DDC_CACHE="$QS_RUN_DIR/brightness-ddc"
DDC_LOCK="$QS_RUN_DIR/brightness-ddc.lock"
BRIGHTNESS_STATE="$QS_RUN_DIR/brightness"

has_backlight() {
    [[ -n "$(brightnessctl --class=backlight -m 2>/dev/null)" ]]
}

detect_ddc_bus() {
    local bus

    if [[ -f "$DDC_CACHE" ]] && read -r bus _ < "$DDC_CACHE" && [[ -c "/dev/i2c-$bus" ]]; then
        printf '%s\n' "$bus"
        return 0
    fi

    command -v ddcutil >/dev/null 2>&1 || return 1
    bus=$(timeout 5s ddcutil detect --brief 2>/dev/null | awk '/I2C bus:/ { sub(".*/i2c-", "", $3); print $3; exit }')
    [[ "$bus" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$bus" > "$DDC_CACHE"
    printf '%s\n' "$bus"
}

ddc_get_locked() {
    local attempt bus output current maximum

    for attempt in 1 2; do
        bus=$(detect_ddc_bus) || return 1
        output=$(timeout 5s ddcutil --bus "$bus" --brief getvcp 10 2>/dev/null) || {
            rm -f "$DDC_CACHE"
            continue
        }
        read -r _ _ _ current maximum <<< "$output"
        [[ "$current" =~ ^[0-9]+$ && "$maximum" =~ ^[0-9]+$ && "$maximum" -gt 0 ]] || return 1
        printf '%s %s\n' "$bus" "$maximum" > "$DDC_CACHE"
        printf '%d\n' "$((current * 100 / maximum))"
        return 0
    done

    return 1
}

ddc_get() {
    exec 9>"$DDC_LOCK"
    flock 9 || return 1
    ddc_get_locked
}

ddc_set_locked() {
    local percent=$1
    local attempt bus output current maximum raw

    for attempt in 1 2; do
        bus=
        maximum=
        if [[ -f "$DDC_CACHE" ]]; then
            read -r bus maximum < "$DDC_CACHE"
        fi
        if [[ ! "$bus" =~ ^[0-9]+$ || ! "$maximum" =~ ^[0-9]+$ || "$maximum" -le 0 ]]; then
            bus=$(detect_ddc_bus) || return 1
            output=$(timeout 5s ddcutil --bus "$bus" --brief getvcp 10 2>/dev/null) || {
                rm -f "$DDC_CACHE"
                continue
            }
            read -r _ _ _ current maximum <<< "$output"
            [[ "$maximum" =~ ^[0-9]+$ && "$maximum" -gt 0 ]] || return 1
            printf '%s %s\n' "$bus" "$maximum" > "$DDC_CACHE"
        fi

        raw=$((percent * maximum / 100))
        if timeout 5s ddcutil --bus "$bus" setvcp 10 "$raw" >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$DDC_CACHE"
    done

    return 1
}

ddc_set() {
    exec 9>"$DDC_LOCK"
    flock 9 || return 1
    ddc_set_locked "$1"
}

get_brightness() {
    if has_backlight; then
        brightnessctl --class=backlight -m 2>/dev/null | awk -F, 'NR == 1 { gsub(/%/, "", $4); print $4 }'
    else
        ddc_get
    fi
}

set_brightness() {
    local target=$1
    local status=0
    [[ "$target" =~ ^-?[0-9]+$ ]] || return 1
    (( target < 0 )) && target=0
    (( target > 100 )) && target=100

    if has_backlight; then
        brightnessctl --class=backlight set "${target}%" >/dev/null || status=$?
    else
        ddc_set "$target" || status=$?
    fi
    if (( status == 0 )); then
        printf '%s\n' "$target" > "$BRIGHTNESS_STATE"
    else
        printf '\n' >> "$BRIGHTNESS_STATE"
    fi
    return "$status"
}

adjust_brightness() {
    local delta=$1
    local current target

    if has_backlight; then
        if (( delta > 0 )); then
            brightnessctl --class=backlight set "${delta}%+" >/dev/null
        else
            brightnessctl --class=backlight set "$((-delta))%-" >/dev/null
        fi
        return
    fi

    exec 9>"$DDC_LOCK"
    flock 9 || return 1
    current=$(ddc_get_locked) || return 1
    target=$((current + delta))
    (( target < 0 )) && target=0
    (( target > 100 )) && target=100
    if ddc_set_locked "$target"; then
        printf '%s\n' "$target" > "$BRIGHTNESS_STATE"
    else
        printf '\n' >> "$BRIGHTNESS_STATE"
        return 1
    fi
}

watch_brightness() {
    local path
    local paths=("$BRIGHTNESS_STATE")

    touch "$BRIGHTNESS_STATE"
    for path in /sys/class/backlight/*/brightness; do
        [[ -e "$path" ]] && paths+=("$path")
    done
    inotifywait -m -e modify "${paths[@]}" 2>/dev/null
}

case "$ACTION" in
    get)
        get_brightness
        ;;
    set)
        set_brightness "$VALUE"
        ;;
    backend)
        if has_backlight; then
            printf 'backlight\n'
        elif command -v ddcutil >/dev/null 2>&1; then
            printf 'ddc\n'
        else
            printf 'none\n'
        fi
        ;;
    raise)
        adjust_brightness 5
        ;;
    lower)
        adjust_brightness -5
        ;;
    watch)
        watch_brightness
        ;;
    *)
        printf 'Unknown brightness action: %s\n' "$ACTION" >&2
        exit 2
        ;;
esac
