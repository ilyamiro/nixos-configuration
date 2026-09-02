#!/usr/bin/env bash
set -euo pipefail

TEMP_MIN=1000
TEMP_MAX=10000
DAY_TEMP=6500
UPDATE_INTERVAL=300
PIDDIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-bluelight"

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

qs_ensure_cache "bluelight"

VERBOSE=0
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
    set -- "${ARGS[@]}"
else
    set --
fi

log() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "[verbose] $*" >&2
    fi
}

usage() {
    exit 1
}

require_binary() {
    local bin="$1"
    if [[ "$VERBOSE" -eq 1 ]]; then
        if ! command -v "$bin" >/dev/null; then
            log "Required binary '$bin' not found."
            exit 1
        fi
    else
        if ! command -v "$bin" >/dev/null 2>&1; then
            exit 1
        fi
    fi
}

run_busctl() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        busctl --user "$@"
    else
        busctl --user "$@" >/dev/null 2>&1
    fi
}

sanitize_output() {
    local name="$1"
    echo "${name//-/_}"
}

pid_key() {
    local output="${1:-}"
    if [[ -n "$output" ]]; then
        sanitize_output "$output"
    else
        echo "global"
    fi
}

object_path() {
    local output="${1:-}"
    if [[ -n "$output" ]]; then
        echo "/outputs/$(sanitize_output "$output")"
    else
        echo "/"
    fi
}

output_exists() {
    local path="$1"
    busctl --user introspect rs.wl-gammarelay "$path" >/dev/null 2>&1
}

wait_for_output_path() {
    local path="$1"
    local timeout="${2:-50}"
    local i=0
    while ! output_exists "$path" && (( i < timeout )); do
        sleep 0.1
        i=$((i+1))
    done
    output_exists "$path"
}

set_property_safe() {
    local path="$1"
    local prop="$2"
    local type="$3"
    local val="$4"

    if ! busctl --user set-property rs.wl-gammarelay "$path" rs.wl.gammarelay "$prop" "$type" "$val" >/dev/null 2>&1; then
        log "Failed to set $prop on $path."
        return 1
    fi
}

gammarelay_running() {
    busctl --user status rs.wl-gammarelay >/dev/null 2>&1
}

gammarelay_start() {
    require_binary wl-gammarelay-rs
    log "Starting wl-gammarelay-rs."
    if [[ "$VERBOSE" -eq 1 ]]; then
        nohup wl-gammarelay-rs >/dev/null 200>&- &
    else
        nohup wl-gammarelay-rs >/dev/null 2>&1 200>&- &
    fi
    disown
    local i=0
    while ! gammarelay_running && (( i < 30 )); do
        sleep 0.1
        i=$((i+1))
    done
}

gammarelay_ensure_running() {
    if ! gammarelay_running; then
        gammarelay_start
    fi
}

gammarelay_ensure_output_ready() {
    local path="$1"
    gammarelay_ensure_running

    if [[ "$path" == "/" ]]; then
        return 0
    fi

    if wait_for_output_path "$path" 50; then
        return 0
    fi

    log "Output object $path never appeared on the bus."
    return 1
}

stop_pid_confirmed() {
    local pid="$1"
    if [[ -z "$pid" ]]; then
        return 0
    fi
    kill "$pid" 2>/dev/null || true
    pkill -P "$pid" 2>/dev/null || true
    local i=0
    while kill -0 "$pid" 2>/dev/null && (( i < 20 )); do
        sleep 0.05
        i=$((i+1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        pkill -9 -P "$pid" 2>/dev/null || true
    fi
}

stop_auto_loop() {
    local output="${1:-}"
    mkdir -p "$PIDDIR"
    if [[ -n "$output" ]]; then
        local pidfile="$PIDDIR/auto-$(pid_key "$output").pid"
        if [[ -f "$pidfile" ]]; then
            local pid
            pid="$(cat "$pidfile" 2>/dev/null || true)"
            stop_pid_confirmed "$pid"
            rm -f "$pidfile"
        fi
    else
        for pidfile in "$PIDDIR"/auto-*.pid; do
            if [[ -f "$pidfile" ]]; then
                local pid
                pid="$(cat "$pidfile" 2>/dev/null || true)"
                stop_pid_confirmed "$pid"
                rm -f "$pidfile"
            fi
        done
    fi
}

calculate_solar_temp() {
    local lat="$1"
    local lon="$2"
    local night_temp="$3"
    local day_temp="$4"
    local now_ts
    now_ts="$(date +%s)"
    local local_time
    local_time="$(date +%H:%M:%S)"

    awk -v t="$now_ts" -v ltime="$local_time" -v lat="$lat" -v lon="$lon" -v ntemp="$night_temp" -v dtemp="$day_temp" '
        function torad(d) { return d * 0.017453292519943295 }
        function todeg(r) { return r * 57.29577951308232 }
        function norm360(x) { x = x % 360; return x < 0 ? x + 360 : x }
        function asin_safe(x) {
            if (x >= 1) return 1.5707963267948966
            if (x <= -1) return -1.5707963267948966
            return atan2(x, sqrt(1 - x * x))
        }
        BEGIN {
            is_zero_lat = (lat == 0 || lat == "0" || lat == "0.0")
            is_zero_lon = (lon == 0 || lon == "0" || lon == "0.0")
            if (is_zero_lat && is_zero_lon) {
                split(ltime, p, ":")
                h = p[1] + p[2] / 60.0 + p[3] / 3600.0
                if (h >= 7.0 && h < 19.0) {
                    target = dtemp
                } else if (h >= 19.0 && h < 21.0) {
                    x = (h - 19.0) / 2.0
                    smooth = x * x * (3 - 2 * x)
                    target = dtemp + (ntemp - dtemp) * smooth
                } else if (h >= 6.0 && h < 7.0) {
                    x = (h - 6.0) / 1.0
                    smooth = x * x * (3 - 2 * x)
                    target = ntemp + (dtemp - ntemp) * smooth
                } else {
                    target = ntemp
                }
                printf "%d\n", target + 0.5
                exit
            }

            d = (t - 946728000) / 86400
            M = norm360(357.529 + 0.98560028 * d)
            L = norm360(280.459 + 0.98564736 * d)
            lambda = norm360(L + 1.915 * sin(torad(M)) + 0.020 * sin(torad(2 * M)))
            eps = 23.439 - 0.00000036 * d
            sinDec = sin(torad(eps)) * sin(torad(lambda))
            cosDec = sqrt(1 - sinDec * sinDec)
            RA = todeg(atan2(cos(torad(eps)) * sin(torad(lambda)), cos(torad(lambda))))
            GMST = norm360(280.46061837 + 360.98564736629 * d)
            H = norm360(GMST + lon - RA)
            sinAlt = sin(torad(lat)) * sinDec + cos(torad(lat)) * cosDec * cos(torad(H))
            alt = todeg(asin_safe(sinAlt))

            low = -6.0
            high = 3.0
            if (alt <= low) {
                target = ntemp
            } else if (alt >= high) {
                target = dtemp
            } else {
                x = (alt - low) / (high - low)
                smooth = x * x * (3 - 2 * x)
                target = ntemp + (dtemp - ntemp) * smooth
            }
            printf "%d\n", target + 0.5
        }'
}

gammarelay_auto_loop() {
    local path="$1"
    local night_temp="$2"
    local lat="$3"
    local lon="$4"

    while :; do
        if [[ "$path" == "/" ]] || output_exists "$path"; then
            local temp
            temp="$(calculate_solar_temp "$lat" "$lon" "$night_temp" "$DAY_TEMP")"
            set_property_safe "$path" Temperature q "$temp"
        fi
        sleep "$UPDATE_INTERVAL"
    done
}

gammarelay_set_manual() {
    local temp="$1"
    local output="${2:-}"
    local path
    path="$(object_path "$output")"

    require_binary busctl
    stop_auto_loop "$output"

    if ! gammarelay_ensure_output_ready "$path"; then
        log "Not touching $path — output not ready."
        return 1
    fi

    log "Setting manual temperature $temp on $path."
    set_property_safe "$path" Temperature q "$temp"
}

gammarelay_set_auto() {
    local temp="$1"
    local output="${2:-}"
    local lat="${3:-0}"
    local lon="${4:-0}"
    local path
    path="$(object_path "$output")"

    require_binary busctl
    stop_auto_loop "$output"

    if ! gammarelay_ensure_output_ready "$path"; then
        log "Not starting auto-schedule for $path — output never appeared."
        return 1
    fi

    local current_auto_temp
    current_auto_temp="$(calculate_solar_temp "$lat" "$lon" "$temp" "$DAY_TEMP")"
    set_property_safe "$path" Temperature q "$current_auto_temp"

    mkdir -p "$PIDDIR"
    local pidfile="$PIDDIR/auto-$(pid_key "$output").pid"

    log "Starting auto-schedule loop for $path (night_temp=$temp lat=$lat lon=$lon current=$current_auto_temp)."
    if [[ "$VERBOSE" -eq 1 ]]; then
        gammarelay_auto_loop "$path" "$temp" "$lat" "$lon" 200>&- &
    else
        gammarelay_auto_loop "$path" "$temp" "$lat" "$lon" >/dev/null 2>&1 200>&- &
    fi
    local loop_pid=$!
    echo "$loop_pid" > "$pidfile"
    disown "$loop_pid" 2>/dev/null || true
}

gammarelay_set() {
    local temp="$1"
    local output="${2:-}"
    local mode="${3:-manual}"
    local lat="${4:-0}"
    local lon="${5:-0}"

    mkdir -p "$PIDDIR"
    local lockfile="$PIDDIR/lock-$(pid_key "$output").lock"
    exec 200>"$lockfile"
    flock 200

    local ret=0
    if [[ "$mode" == "auto" ]]; then
        gammarelay_set_auto "$temp" "$output" "$lat" "$lon" || ret=$?
    else
        gammarelay_set_manual "$temp" "$output" || ret=$?
    fi

    flock -u 200 2>/dev/null || true
    exec 200>&-
    return $ret
}

gammarelay_reset() {
    local output="${1:-}"
    local path
    path="$(object_path "$output")"

    mkdir -p "$PIDDIR"
    local lockfile="$PIDDIR/lock-$(pid_key "$output").lock"
    exec 200>"$lockfile"
    flock 200

    local ret=0
    require_binary busctl
    stop_auto_loop "$output"

    if ! gammarelay_running; then
        log "wl-gammarelay-rs is not running."
        flock -u 200 2>/dev/null || true
        exec 200>&-
        return 0
    fi

    if [[ "$path" != "/" ]] && ! output_exists "$path"; then
        log "Output object $path not present; nothing to reset."
        flock -u 200 2>/dev/null || true
        exec 200>&-
        return 0
    fi

    log "Resetting $path to neutral temperature and full brightness."
    set_property_safe "$path" Temperature q "$DAY_TEMP" || ret=$?
    set_property_safe "$path" Brightness d 1 || ret=$?
    set_property_safe "$path" Gamma d 1 || ret=$?
    set_property_safe "$path" Inverted b false || ret=$?

    flock -u 200 2>/dev/null || true
    exec 200>&-
    return $ret
}

gammarelay_status() {
    local output="${1:-}"
    local path
    path="$(object_path "$output")"

    if ! gammarelay_running; then
        echo "stopped"
        return
    fi

    if [[ "$VERBOSE" -eq 1 ]]; then
        local temp brightness
        temp="$(busctl --user get-property rs.wl-gammarelay "$path" rs.wl.gammarelay Temperature 2>/dev/null | awk '{print $2}')"
        brightness="$(busctl --user get-property rs.wl-gammarelay "$path" rs.wl.gammarelay Brightness 2>/dev/null | awk '{print $2}')"
        log "Path: $path, Temperature: ${temp:-unknown}K, Brightness: ${brightness:-unknown}"
    fi

    echo "running"
}

[[ $# -ge 1 ]] || usage

CMD="$1"
shift

case "$CMD" in
    set)
        [[ $# -ge 1 ]] || usage
        temp="$1"
        output="${2:-}"
        mode="${3:-manual}"
        lat="${4:-0}"
        lon="${5:-0}"
        if ! [[ "$temp" =~ ^[0-9]+$ ]] || (( temp < TEMP_MIN || temp > TEMP_MAX )); then
            log "Temperature $temp is outside valid range ($TEMP_MIN-$TEMP_MAX)."
            exit 1
        fi
        if ! [[ "$lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$lon" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            log "Latitude '$lat' or longitude '$lon' is not a valid number."
            exit 1
        fi
        gammarelay_set "$temp" "$output" "$mode" "$lat" "$lon"
        ;;
    reset)
        output="${1:-}"
        gammarelay_reset "$output"
        ;;
    status)
        output="${1:-}"
        gammarelay_status "$output"
        ;;
    *)
        usage
        ;;
esac
