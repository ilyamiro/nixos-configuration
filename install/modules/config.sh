CONFIG_DIR="$HOME/.config/serpantinum"
CONFIG_FILE="$CONFIG_DIR/settings.json"

init_serpantinum_config() {
    local project_root="$1"
    local wallpaper_dir="$2"
    local install_state="$3"
    local is_reinstall="$4"
    local template_json="$project_root/config/serpantinum/settings.json"
    local script_path="$project_root/src/scripts/location.sh"

    if [[ "$install_state" == "current" && "$is_reinstall" != "true" ]]; then
        return 0
    fi

    mkdir -p "$CONFIG_DIR"

    if [ -f "$template_json" ]; then
        if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
            local merged_json
            merged_json=$(jq -s --arg wp "$wallpaper_dir" '
                .[0] * .[1]
            ' "$template_json" "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$merged_json" ]; then
                echo "$merged_json" > "$CONFIG_FILE"
            fi
        else
            local initial_json
            initial_json=$(jq --arg wp "$wallpaper_dir" '
                . * (if ($wp | length > 0) then {wallpaperDir: $wp} else {} end)
            ' "$template_json" 2>/dev/null)
            if [ -n "$initial_json" ]; then
                echo "$initial_json" > "$CONFIG_FILE"
            else
                cp "$template_json" "$CONFIG_FILE"
            fi
        fi
    elif [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi

    if [[ "$is_reinstall" == "true" || "$install_state" == "fresh" || "$install_state" == "legacy" ]]; then
        if [ -f "$script_path" ]; then
            bash "$script_path" --refresh >/dev/null 2>&1 || true
        elif [ -f "$HOME/.local/share/serpantinum/src/scripts/location.sh" ]; then
            bash "$HOME/.local/share/serpantinum/src/scripts/location.sh" --refresh >/dev/null 2>&1 || true
        fi
    fi
}
