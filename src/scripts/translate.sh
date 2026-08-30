#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
else
    SCRIPT_DIR="$(pwd -P)"
fi

source "$SCRIPT_DIR/caching.sh" 2>/dev/null || true
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true
source "$SCRIPT_DIR/i18n.sh" 2>/dev/null || true

PYTHON_SCRIPT="$SCRIPT_DIR/translate.py"

show_help() {
    echo "Usage: serpantinum translate [OPTIONS] [TEXT]"
    echo ""
    echo "Ultra-fast Multi-Language Translator for Serpantinum."
    echo ""
    echo "Options:"
    echo "  --selection, -s       Translate currently selected text (primary clipboard)"
    echo "  --gui, -g             Open full Translator window"
    echo "  --from, -f <LANG>     Source language code (default: auto)"
    echo "  --to, -t <LANG>       Target language code (default: from settings or ru)"
    echo "  --json                Output result in JSON format"
    echo "  --notify              Send translation result via desktop notification"
    echo "  --copy                Copy translated text to clipboard"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  serpantinum translate 'Hello world'"
    echo "  serpantinum translate --selection"
    echo "  serpantinum translate -f ru -t en 'Привет'"
    echo "  serpantinum translate --gui"
}

# Determine default target language from settings
TARGET_LANG="ru"
if command -v get_setting &>/dev/null; then
    CONFIGURED_LANG="$(get_setting "translator" '{}' | jq -r '.targetLang // empty' 2>/dev/null)"
    if [[ -z "$CONFIGURED_LANG" ]]; then
        CONFIGURED_LANG="$(get_setting "general" '{}' | jq -r '.language // empty' 2>/dev/null)"
    fi
    if [[ -n "$CONFIGURED_LANG" && "$CONFIGURED_LANG" != "null" ]]; then
        TARGET_LANG="$CONFIGURED_LANG"
    fi
fi

IS_SELECTION=false
IS_GUI=false
IS_NOTIFY=false
IS_COPY=false
IS_JSON=false
SRC_LANG="auto"
INPUT_TEXT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --selection|-s)
            IS_SELECTION=true
            shift
            ;;
        --gui|-g)
            IS_GUI=true
            shift
            ;;
        --notify)
            IS_NOTIFY=true
            shift
            ;;
        --copy)
            IS_COPY=true
            shift
            ;;
        --json)
            IS_JSON=true
            shift
            ;;
        --from|-f)
            SRC_LANG="$2"
            shift 2
            ;;
        --to|-t)
            TARGET_LANG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$INPUT_TEXT" ]]; then
                INPUT_TEXT="$1"
            else
                INPUT_TEXT="$INPUT_TEXT $1"
            fi
            shift
            ;;
    esac
done

if [ "$IS_GUI" = true ]; then
    "$SCRIPT_DIR/qs_manager.sh" toggle translator "$INPUT_TEXT"
    exit 0
fi

if [ "$IS_SELECTION" = true ]; then
    SELECTED=""
    PREV_CLIP=""

    if command -v wl-paste &>/dev/null; then
        PREV_CLIP="$(wl-paste 2>/dev/null || true)"
        
        # Release any lingering modifiers, send Ctrl+C to focused window
        if command -v wtype &>/dev/null; then
            sleep 0.05
            wtype -M ctrl -k c -m ctrl 2>/dev/null || true
            sleep 0.06
            SELECTED="$(wl-paste --no-newline 2>/dev/null || true)"
        fi

        # If Ctrl+C yielded nothing new or empty, fallback to primary selection
        if [[ -z "$SELECTED" || "$SELECTED" == "$PREV_CLIP" ]]; then
            PRIMARY_SEL="$(wl-paste --primary --no-newline 2>/dev/null || true)"
            if [[ -n "$PRIMARY_SEL" ]]; then
                SELECTED="$PRIMARY_SEL"
            fi
        fi

        # Restore previous clipboard content so user's clipboard is not corrupted
        if [[ -n "$PREV_CLIP" && "$SELECTED" != "$PREV_CLIP" ]]; then
            (sleep 0.3; printf '%s' "$PREV_CLIP" | wl-copy 2>/dev/null) &
        fi
    elif command -v xclip &>/dev/null; then
        SELECTED="$(xclip -o -selection primary 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || true)"
    fi

    SELECTED="$(printf '%s' "$SELECTED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "$SELECTED" ]]; then
        exit 0
    fi

    INPUT_TEXT="$SELECTED"

    # Get cursor position for popup placement
    CURSOR_POS=""
    if command -v hyprctl &>/dev/null; then
        CURSOR_POS="$(hyprctl cursorpos 2>/dev/null | tr -d ' ')"
    fi

    # Trigger Quickshell Selection popup via IPC
    SAFE_TEXT="$(printf '%s' "$INPUT_TEXT" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
    if [[ -n "$MAIN_QML" ]]; then
        quickshell -p "$MAIN_QML" ipc call main handleCommand "translate-selection" "$SAFE_TEXT" "$CURSOR_POS" >/dev/null 2>&1 &
    else
        quickshell ipc call main handleCommand "translate-selection" "$SAFE_TEXT" "$CURSOR_POS" >/dev/null 2>&1 &
    fi
    exit 0
fi

if [[ -z "$INPUT_TEXT" ]]; then
    if [ -t 0 ]; then
        show_help
        exit 1
    else
        INPUT_TEXT="$(cat)"
    fi
fi

ARGS=("--text" "$INPUT_TEXT" "--from" "$SRC_LANG" "--to" "$TARGET_LANG")
if [ "$IS_JSON" = true ]; then
    ARGS+=("--json")
fi

RESULT="$(python3 "$PYTHON_SCRIPT" "${ARGS[@]}")"

if [ "$IS_COPY" = true ]; then
    if command -v wl-copy &>/dev/null; then
        printf '%s' "$RESULT" | wl-copy
    elif command -v xclip &>/dev/null; then
        printf '%s' "$RESULT" | xclip -selection clipboard
    fi
fi

if [ "$IS_NOTIFY" = true ]; then
    if command -v notify-send &>/dev/null; then
        notify-send "Serpantinum Translator" "$RESULT" -i preferences-desktop-locale
    fi
fi

printf '%s\n' "$RESULT"
