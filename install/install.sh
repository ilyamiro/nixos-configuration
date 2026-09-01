#!/usr/bin/env bash

set -e

setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

RAW_SLUG="${REPO_SLUG:-ilyamiro/serpantinum}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"
export REPO_SLUG

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    command -v git &>/dev/null || sudo pacman -Sy --noconfirm --needed git
    if [ ! -d "$CACHE_BASE/.git" ]; then
        rm -rf "$CACHE_BASE"
        mkdir -p "$CACHE_BASE"
        git clone "https://github.com/${REPO_SLUG}.git" "$CACHE_BASE"
    else
        git -C "$CACHE_BASE" remote set-url origin "https://github.com/${REPO_SLUG}.git" 2>/dev/null || true
        git -C "$CACHE_BASE" fetch origin 2>/dev/null || true
        git -C "$CACHE_BASE" reset --hard origin/HEAD 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/main 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/master 2>/dev/null || true
    fi
    INSTALL_DIR="$CACHE_BASE/install"
    PROJECT_ROOT="$CACHE_BASE"
fi

export SERPANTINUM_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

MODULES_DIR="$INSTALL_DIR/modules"

source "$PROJECT_ROOT/src/scripts/i18n.sh"
source "$MODULES_DIR/deps.sh"
source "$MODULES_DIR/state.sh"
source "$MODULES_DIR/migrate.sh"
source "$MODULES_DIR/deploy.sh"
source "$MODULES_DIR/version.sh"
source "$MODULES_DIR/config.sh"
source "$MODULES_DIR/service.sh"
source "$MODULES_DIR/ui.sh"

TELEMETRY_ID=$(get_telemetry_id)
ENABLE_TELEMETRY=$(get_telemetry_enabled)

check_supported_os
bootstrap_installer_deps

INSTALL_STATE=$(detect_install_state)
OLD_VERSION=$(get_installed_version)
TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=$(get_installed_commit)

init_compositor_detection
run_installer_ui

TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode init --version "$TARGET_VERSION" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY"
fi

if [[ "$INSTALL_STATE" == "legacy" ]]; then
    migrate_legacy "${SELECTED_COMPOSITORS[@]}"
elif [[ "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    backup_compositors "${SELECTED_COMPOSITORS[@]}"
fi

install_dependencies "${SELECTED_COMPOSITORS[@]}"

deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
setup_sddm "$PROJECT_ROOT"
install_wallpapers "$INSTALL_FULL_WALLPAPERS"

WALLPAPER_DIR=$(get_wallpaper_dir)
init_serpantinum_config "$PROJECT_ROOT" "$WALLPAPER_DIR" "$INSTALL_STATE" "$IS_REINSTALL"

setup_services
write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$TELEMETRY_ID" "$ENABLE_TELEMETRY" "${SELECTED_COMPOSITORS[*]}"

if [[ "$INSTALL_STATE" == "legacy" || "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    rm -f "$HOME/.local/state/serpantinum/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
fi

if [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY" --failed "${FAILED_PKGS[*]}"
fi

draw_completion_screen "$TARGET_VERSION" "$TARGET_COMMIT"
