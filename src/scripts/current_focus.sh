#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

RUN_DIR="${QS_RUN_FOCUSTIME:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/serpantinum/focustime}"
mkdir -p "$RUN_DIR"

LOG_FILE="$RUN_DIR/focus_events.jsonl"
STATE_FILE="$RUN_DIR/focus_state.json"
touch "$LOG_FILE" "$STATE_FILE"

for pid in $(pgrep -f "$(basename "$0")"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

cleanup() {
    trap - EXIT SIGTERM SIGINT
    pkill -P $$ 2>/dev/null
    exit 0
}
trap cleanup EXIT SIGTERM SIGINT

detect_compositor() {
    if [ -n "$NIRI_SOCKET" ] || pgrep -x niri >/dev/null 2>&1; then
        echo "niri"
    elif [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || pgrep -x Hyprland >/dev/null 2>&1; then
        echo "hyprland"
    else
        echo "unknown"
    fi
}

COMPOSITOR=$(detect_compositor)

is_locked() {
    pgrep -x hyprlock >/dev/null 2>&1 || pgrep -x swaylock >/dev/null 2>&1 || pgrep -x gtklock >/dev/null 2>&1 || pgrep -x waylock >/dev/null 2>&1
}

get_active_window_hyprland() {
    local data cls title cls_lower title_lower
    data=$(timeout 2 hyprctl activewindow -j 2>/dev/null)
    if [ -z "$data" ] || [ "$data" = "{}" ]; then
        echo "Desktop|Desktop"
        return
    fi
    IFS='|' read -r cls title < <(echo "$data" | jq -r '(.initialClass // .class // "Unknown") as $c | "\($c)|\(.initialTitle // .title // $c)"')
    cls_lower="${cls,,}"
    title_lower="${title,,}"
    if [[ "$cls_lower" == *quickshell* ]] || [[ "$title_lower" == *qs-master* ]] || [[ "$cls_lower" == *qs-master* ]]; then
        echo "Quickshell|Quickshell"
        return
    fi
    echo "${cls}|${title}"
}

get_active_window_niri() {
    local data cls title cls_lower title_lower
    data=$(timeout 2 niri msg -j focused-window 2>/dev/null)
    if [ -z "$data" ] || [ "$data" = "null" ] || [ "$data" = "{}" ]; then
        echo "Desktop|Desktop"
        return
    fi
    IFS='|' read -r cls title < <(echo "$data" | jq -r '(.app_id // "Unknown") as $c | "\($c)|\(.title // $c)"')
    cls_lower="${cls,,}"
    title_lower="${title,,}"
    if [[ "$cls_lower" == *quickshell* ]] || [[ "$title_lower" == *qs-master* ]] || [[ "$cls_lower" == *qs-master* ]]; then
        echo "Quickshell|Quickshell"
        return
    fi
    echo "${cls}|${title}"
}

get_active_window() {
    if [ "$COMPOSITOR" = "niri" ]; then
        get_active_window_niri
    else
        get_active_window_hyprland
    fi
}

last_cls=""
last_title=""

emit_state() {
    local cls="$1" title="$2" ts json_payload

    if is_locked || [ "$cls" = "hyprlock" ] || [ "$cls" = "swaylock" ] || [ "$cls" = "gtklock" ] || [ "$cls" = "waylock" ]; then
        cls="Locked"
        title="Locked"
    fi

    if [ "$cls" = "$last_cls" ] && [ "$title" = "$last_title" ]; then
        return
    fi
    last_cls="$cls"
    last_title="$title"

    ts=$(date +%s)
    json_payload=$(jq -nc --arg cls "$cls" --arg title "$title" --argjson ts "$ts" \
        '{timestamp: $ts, app_class: $cls, app_title: $title}')

    echo "$json_payload" >> "$LOG_FILE"
    echo "$json_payload" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

listen_events() {
    if [ "$COMPOSITOR" = "niri" ]; then
        niri msg --json event-stream 2>/dev/null | grep --line-buffered -E '"(WindowFocusChanged|WindowOpenedOrChanged|WindowClosed)"'
    else
        socat -u UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - 2>/dev/null
    fi
}

IFS='|' read -r cur_cls cur_title < <(get_active_window)
emit_state "$cur_cls" "$cur_title"

while true; do
    while read -r line; do
        case "$COMPOSITOR" in
            niri)
                while read -t 0.05 -r extra_line; do
                    continue
                done
                IFS='|' read -r cls title < <(get_active_window)
                emit_state "$cls" "$title"
                ;;
            *)
                case "$line" in
                    activewindow*|closewindow*)
                        while read -t 0.05 -r extra_line; do
                            continue
                        done
                        IFS='|' read -r cls title < <(get_active_window)
                        emit_state "$cls" "$title"
                        ;;
                esac
                ;;
        esac
    done < <(listen_events)
    sleep 1
done
