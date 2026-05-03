#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CONSTANTS & ARGUMENTS
# -----------------------------------------------------------------------------
QS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_PID_FILE="$HOME/.cache/bt_scan_pid"
BT_SCAN_LOG="$HOME/.cache/bt_scan.log"
SRC_DIR="${WALLPAPER_DIR:-${srcdir:-$HOME/Pictures/Wallpapers}}"
THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"

# User-specific cache directory matching the QML logic
QS_NETWORK_CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/qs_network"
mkdir -p "$QS_NETWORK_CACHE"

IPC_FILE="/tmp/qs_widget_state"
NETWORK_MODE_FILE="$QS_NETWORK_CACHE/mode"

ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

# -----------------------------------------------------------------------------
# FAST PATH: WORKSPACE SWITCHING
# -----------------------------------------------------------------------------
if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
    WORKSPACE_NUM="$ACTION"
    echo "close" > "$IPC_FILE"
    
    CMD="workspace $WORKSPACE_NUM"
    [[ "$2" == "move" ]] && CMD="movetoworkspace $WORKSPACE_NUM"
    hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
    exit 0
fi

MANIFEST="$THUMB_DIR/.manifest"

build_manifest() {
    find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.source_dir' ! -name '.manifest' \
        -printf "%f\n" | sort > "$MANIFEST"
}

handle_wallpaper_prep() {
    mkdir -p "$THUMB_DIR"

    (
        export THUMB_DIR SRC_DIR MANIFEST

        process_one() {
            img="$1"
            filename=$(basename "$img")
            extension="${filename##*.}"
            if [[ "${extension,,}" == "webp" ]]; then
                new_img="${img%.*}.jpg"
                magick "$img" "$new_img" && rm -f "$img"
                img="$new_img"; filename=$(basename "$img"); extension="jpg"
            fi
            if [[ "${extension,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
                thumb="$THUMB_DIR/000_$filename"
                [ -f "$THUMB_DIR/$filename" ] && rm -f "$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                    ffmpeg -y -ss 00:00:05 -i "$img" -vframes 1 \
                        -f image2 -q:v 2 "$thumb" >/dev/null 2>&1
                    echo "000_$filename" >> "$MANIFEST"
                fi
            else
                thumb="$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                    magick "$img" -resize x420 -quality 70 "$thumb"
                    echo "$filename" >> "$MANIFEST"
                fi
            fi
        }
        export -f process_one

        # Source dir change — nuke everything and rebuild
        THUMB_SOURCE_FILE="$THUMB_DIR/.source_dir"
        if [ -f "$THUMB_SOURCE_FILE" ]; then
            read -r CACHED_SRC < "$THUMB_SOURCE_FILE"
            if [ "$CACHED_SRC" != "$SRC_DIR" ]; then
                find "$THUMB_DIR" -maxdepth 1 -type f \
                    ! -name '.source_dir' ! -name '.manifest' -delete
                echo "$SRC_DIR" > "$THUMB_SOURCE_FILE"
                > "$MANIFEST"  # reset manifest
            fi
        else
            echo "$SRC_DIR" > "$THUMB_SOURCE_FILE"
            > "$MANIFEST"
        fi

        # Build manifest if missing
        [ ! -f "$MANIFEST" ] && build_manifest

        # Get current src files (one find, sorted)
        SRC_LIST=$(mktemp)
        find "$SRC_DIR" -maxdepth 1 -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
               -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mkv" \
               -o -iname "*.mov" -o -iname "*.webm" \) \
            -printf "%f\n" | sort > "$SRC_LIST"

        # Orphans: in manifest but not in src anymore
        comm -23 \
            <(sed 's/^000_//' "$MANIFEST" | sort) \
            "$SRC_LIST" \
        | while read -r orphan; do
            rm -f "$THUMB_DIR/$orphan" "$THUMB_DIR/000_$orphan"
            # Remove from manifest
            sed -i "/^${orphan}$/d;/^000_${orphan}$/d" "$MANIFEST"
        done

        # New files: in src but not in manifest
        comm -23 \
            "$SRC_LIST" \
            <(sed 's/^000_//' "$MANIFEST" | sort) \
        | xargs -P 8 -I{} bash -c 'process_one "$SRC_DIR/$@"' _ {}

        rm -f "$SRC_LIST"

    ) </dev/null >/dev/null 2>&1 &

    # awww/mpvpaper detection (unchanged, fast)
    TARGET_THUMB=""
    CURRENT_SRC=""
    if pgrep -a "mpvpaper" > /dev/null; then
        CURRENT_SRC=$(pgrep -a mpvpaper | grep -o "$SRC_DIR/[^' ]*" | head -n1)
        CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi
    if [ -z "$CURRENT_SRC" ] && command -v awww >/dev/null; then
        CURRENT_SRC=$(awww query 2>/dev/null | grep -o "$SRC_DIR/[^ ]*" | head -n1)
        CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi
    if [ -n "$CURRENT_SRC" ]; then
        EXT="${CURRENT_SRC##*.}"
        [[ "${EXT,,}" =~ ^(mp4|mkv|mov|webm)$ ]] \
            && TARGET_THUMB="000_$CURRENT_SRC" \
            || TARGET_THUMB="$CURRENT_SRC"
    fi
    export WALLPAPER_THUMB="$TARGET_THUMB"
}


handle_network_prep() {
    echo "" > "$BT_SCAN_LOG"
    { echo "scan on"; sleep infinity; } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &
    echo $! > "$BT_PID_FILE"
    (nmcli device wifi rescan) >/dev/null 2>&1 &
}

# -----------------------------------------------------------------------------
# ZOMBIE WATCHDOG
# -----------------------------------------------------------------------------
MAIN_QML_PATH="$HOME/.config/hypr/scripts/quickshell/Main.qml"
BAR_QML_PATH="$HOME/.config/hypr/scripts/quickshell/TopBar.qml"
FLOATING_QML_PATH="$HOME/.config/hypr/scripts/quickshell/Floating.qml"

if ! pgrep -f "quickshell.*Main\.qml" >/dev/null; then
    quickshell -p "$MAIN_QML_PATH" >/dev/null 2>&1 &
    disown
fi

if ! pgrep -f "quickshell.*Floating\.qml" >/dev/null; then
    quickshell -p "$FLOATING_QML_PATH" >/dev/null 2>&1 &
    disown
fi

if ! pgrep -f "quickshell.*TopBar\.qml" >/dev/null; then
    quickshell -p "$BAR_QML_PATH" >/dev/null 2>&1 &
    disown
fi

# -----------------------------------------------------------------------------
# IPC ROUTING
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "close" ]]; then
    echo "close" > "$IPC_FILE"
    if [[ "$TARGET" == "network" || "$TARGET" == "all" || -z "$TARGET" ]]; then
        if [ -f "$BT_PID_FILE" ]; then
            kill $(cat "$BT_PID_FILE") 2>/dev/null
            rm -f "$BT_PID_FILE"
        fi
        (bluetoothctl scan off > /dev/null 2>&1) &
    fi
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    CURRENT_MODE=$(cat "$NETWORK_MODE_FILE" 2>/dev/null)

    if [[ "$TARGET" == "network" ]]; then
        handle_network_prep
        [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
        echo "$ACTION:$TARGET:$SUBTARGET" > "$IPC_FILE"
        exit 0
    fi

    if [[ "$TARGET" == "wallpaper" ]]; then
        handle_wallpaper_prep
        echo "$ACTION:$TARGET:$WALLPAPER_THUMB" > "$IPC_FILE"
    else
        echo "$ACTION:$TARGET:$SUBTARGET" > "$IPC_FILE"
    fi
    exit 0
fi
