#!/bin/bash
# SCRIPT: setup_autoupdate.sh
# DESCRIPTION: Universal Linux automatic package updater with systemd timer support
# Supports: Arch (yay/pacman), Debian/Ubuntu (apt), Fedora (dnf), CentOS (yum), openSUSE (zypper)
# Usage: ./setup_autoupdate.sh [OPTIONS]
#   --install, -i          Install/update the autoupdate service
#   --remove, -r           Remove the autoupdate service
#   --status, -s           Show current status
#   --time HH:MM          Set update time (use with --install)
#   --grant-sudo, -g       Grant passwordless sudo for package manager
#   --revoke-sudo, -x     Revoke passwordless sudo
#   --help, -h            Show this help message
#   (no args)             Launch GUI mode (requires zenity)

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/autoupdate"
WORKER_SCRIPT_NAME="AutoUpdatePackages.sh"
SERVICE_NAME="autoupdate"
SCRIPT_FULL_PATH="${INSTALL_DIR}/${WORKER_SCRIPT_NAME}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"
LOG_FILE="$HOME/autoupdate.log"
SUDOERS_FILE="/etc/sudoers.d/99-autoupdate-permissions"
MODE="gui"

msg() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
warn() { echo "[WARNING] $*" >&2; }

show_help() {
    cat << 'HELP'
Usage: autoupdate [OPTIONS]

Universal Linux automatic package updater using systemd timers.

OPTIONS:
  --gui                 Launch GUI mode (requires zenity)
  --install, -i            Install/update the autoupdate service
  --remove, -r             Remove the autoupdate service completely
  --status, -s            Show current service status
  --time HH:MM            Set daily update time (use with --install)
  --grant-sudo, -G        Grant passwordless sudo for package manager
  --revoke-sudo, -x       Revoke passwordless sudo permissions
  --help, -h             Show this help message

EXAMPLES:
  autoupdate --install --time 07:30
  autoupdate --status
  autoupdate --remove
  autoupdate --grant-sudo
  autoupdate --gui

GUI MODE:
  Run without arguments or with --gui to launch interactive zenity dialog.

REQUIREMENTS:
  - systemd
  - zenity (for GUI mode only)
  - One of: yay, pacman, apt, dnf, yum, zypper
HELP
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gui)
                MODE="gui"
                ;;
            --install|-i)
                MODE="install"
                ;;
            --remove|-r)
                MODE="remove"
                ;;
            --status|-s)
                MODE="status"
                ;;
            --time)
                shift
                if [[ $# -eq 0 ]]; then
                    err "--time requires a time argument (e.g., 07:30)"
                    exit 1
                fi
                UPDATE_TIME="$1"
                ;;
            --grant-sudo|-G)
                MODE="grant-sudo"
                ;;
            --revoke-sudo|-x)
                MODE="revoke-sudo"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

validate_time() {
    local time="$1"
    local sanitized
    sanitized=$(echo "$time" | tr -d ':')
    
    if [[ ! "$sanitized" =~ ^[0-9]{4}$ ]]; then
        err "Invalid time format. Use HH:MM (e.g., 07:30 or 0730)"
        return 1
    fi
    
    local hour="${sanitized:0:2}"
    local minute="${sanitized:2:2}"
    
    if (( 10#$hour > 23 || 10#$minute > 59 )); then
        err "Invalid time. Hour must be 00-23, minute must be 00-59"
        return 1
    fi
    
    echo "$hour:$minute"
}

get_pm() {
    local pm_path=""
    if command -v yay &>/dev/null || command -v pacman &>/dev/null; then
        pm_path="pacman"
    elif command -v apt &>/dev/null; then
        pm_path="apt"
    elif command -v dnf &>/dev/null; then
        pm_path="dnf"
    elif command -v yum &>/dev/null; then
        pm_path="yum"
    elif command -v zypper &>/dev/null; then
        pm_path="zypper"
    fi
    echo "$pm_path"
}

do_install() {
    local formatted_time=""
    
    if [[ -n "${UPDATE_TIME:-}" ]]; then
        formatted_time=$(validate_time "$UPDATE_TIME") || exit 1
    else
        if [[ "$MODE" == "cli" ]]; then
            read -p "Enter update time (HH:MM): " -r
            [[ -z "$REPLY" ]] && exit 0
            formatted_time=$(validate_time "$REPLY") || exit 1
        else
            return
        fi
    fi

    msg "Stopping existing timer if present..."
    systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl --user daemon-reload

    msg "Creating update script in $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    tee "$SCRIPT_FULL_PATH" > /dev/null << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/autoupdate.log"

run_system_update() {
    if command -v yay &>/dev/null; then
        echo "--- Found yay. Updating Arch Linux + AUR packages... ---"
        yay -Syu --noconfirm --answerclean All --answerdiff All
    elif command -v pacman &>/dev/null; then
        echo "--- Found pacman. Updating Arch Linux packages... ---"
        sudo pacman -Syu --noconfirm
    elif command -v apt &>/dev/null; then
        echo "--- Found apt. Updating Debian/Ubuntu packages... ---"
        sudo apt update && sudo apt upgrade -y
    elif command -v dnf &>/dev/null; then
        echo "--- Found dnf. Updating Fedora/CentOS packages... ---"
        sudo dnf upgrade -y
    elif command -v yum &>/dev/null; then
        echo "--- Found yum. Updating RHEL/CentOS legacy packages... ---"
        sudo yum update -y
    elif command -v zypper &>/dev/null; then
        echo "--- Found zypper. Updating openSUSE packages... ---"
        sudo zypper ref && sudo zypper dup -y
    else
        echo "--- ERROR: No supported package manager found (yay, pacman, apt, dnf, yum, zypper). ---"
        return 1
    fi
}

{
    echo "--- SCRIPT STARTED AT $(date) ---"
    run_system_update
    echo "--- SCRIPT FINISHED ---"
} > "$LOG_FILE" 2>&1
EOF
    chmod +x "$SCRIPT_FULL_PATH"

    msg "Creating systemd service and timer files..."
    mkdir -p "$HOME/.config/systemd/user/"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Run universal autoupdate script
[Service]
Type=oneshot
ExecStart=$SCRIPT_FULL_PATH
EOF
    cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run autoupdate daily at ${formatted_time}
[Timer]
OnCalendar=*-*-* ${formatted_time}:00
Unit=${SERVICE_NAME}.service
[Install]
WantedBy=timers.target
EOF

    msg "Enabling and starting timer..."
    systemctl --user daemon-reload
    if ! systemctl --user enable "${SERVICE_NAME}.timer" 2>&1; then
        err "Failed to enable systemd timer"
        exit 1
    fi
    if ! systemctl --user start "${SERVICE_NAME}.timer" 2>&1; then
        err "Failed to start systemd timer"
        exit 1
    fi
    
    if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
        msg "Service installed successfully for ${formatted_time} daily"
    else
        err "Timer installed but not running"
        exit 1
    fi
}

do_remove() {
    msg "Stopping and disabling timer..."
    systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.service" 2>/dev/null || true
    
    msg "Removing files..."
    rm -f "$SERVICE_FILE" "$TIMER_FILE"
    rm -rf "$INSTALL_DIR"
    
    systemctl --user daemon-reload
    systemctl --user reset-failed 2>/dev/null || true
    
    if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
        err "Failed to stop timer"
        exit 1
    fi
    msg "Service removed successfully"
}

do_status() {
    echo "=== Autoupdate Service Status ==="
    
    if [ -f "$TIMER_FILE" ]; then
        local scheduled_time
        scheduled_time=$(grep 'OnCalendar=' "$TIMER_FILE" | cut -d' ' -f2)
        if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
            echo "Timer: ACTIVE - runs daily at $scheduled_time"
        else
            echo "Timer: INACTIVE (scheduled for $scheduled_time)"
        fi
    else
        echo "Timer: NOT INSTALLED"
    fi
    
    local pm
    pm=$(get_pm)
    if [ -n "$pm" ]; then
        echo "Package Manager: $pm"
        if sudo -n "$pm" --version >/dev/null 2>&1; then
            echo "Passwordless Sudo: CONFIGURED"
        else
            echo "Passwordless Sudo: NOT CONFIGURED"
        fi
    else
        echo "Package Manager: NOT FOUND"
    fi
    
    echo ""
    echo "Timer details:"
    systemctl --user list-timers --all | grep -E "^.*${SERVICE_NAME}" || echo "  (no timer found)"
}

do_grant_sudo() {
    local pm_path
    pm_path=$(get_pm)
    
    if [ -z "$pm_path" ]; then
        err "No supported package manager found"
        exit 1
    fi
    
    local current_user
    current_user=$(whoami)
    local cmd="echo '$current_user ALL=(ALL) NOPASSWD: $(command -v $pm_path)' > '$SUDOERS_FILE' && chmod 0440 '$SUDOERS_FILE'"
    
    if pkexec --user root bash -c "$cmd"; then
        msg "Passwordless sudo granted for $pm_path"
    else
        err "Failed to grant sudo permission"
        exit 1
    fi
}

do_revoke_sudo() {
    local pm_path_base
    pm_path_base=$(get_pm)
    
    if [ -z "$pm_path_base" ]; then
        err "No supported package manager found"
        exit 1
    fi
    
    local cmd="
        rm -f '$SUDOERS_FILE'
        sed -i '/NOPASSWD.*$pm_path_base/d' /etc/sudoers 2>/dev/null || true
        for file in /etc/sudoers.d/*; do
            [ -f \"\$file\" ] && sed -i '/NOPASSWD.*$pm_path_base/d' \"\$file\" 2>/dev/null || true
        done
    "
    
    if pkexec --user root bash -c "$cmd"; then
        msg "Passwordless sudo revoked"
    else
        err "Failed to revoke sudo permission"
        exit 1
    fi
}

gui_mode() {
    if ! command -v zenity &>/dev/null; then
        err "zenity not found. Use CLI mode or install zenity."
        exit 1
    fi
    
    while true; do
        status_service="NOT INSTALLED"
        status_permissions="REQUIRES PASSWORD"
        is_service_installed=false
        has_passwordless_sudo=false

        if [ -f "$TIMER_FILE" ]; then
            local scheduled_time
            scheduled_time=$(grep 'OnCalendar=' "$TIMER_FILE" | cut -d' ' -f2)
            if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
                status_service="ACTIVE (${scheduled_time})"
            else
                status_service="INACTIVE (${scheduled_time})"
            fi
            is_service_installed=true
        fi

        local pm_test_path
        pm_test_path=$(get_pm)

        if [ -n "$pm_test_path" ]; then
            if sudo -n "$pm_test_path" --version >/dev/null 2>&1; then
                status_permissions="CONFIGURED"
                has_passwordless_sudo=true
            fi
        fi

        menu_items=( "Install / Reconfigure Service" )
        if $is_service_installed; then
            menu_items+=( "Remove Service" )
        fi

        if $has_passwordless_sudo; then
            menu_items+=( "Revoke Sudo Permission" )
        else
            menu_items+=( "Grant Sudo Permission" )
        fi

        zenity_options=()
        is_first=true
        for item in "${menu_items[@]}"; do
            if $is_first; then zenity_options+=( TRUE "$item" ); is_first=false; else zenity_options+=( FALSE "$item" ); fi
        done

        choice=$(zenity --list \
            --title="Universal Update Manager" \
            --text="<b>Current Status:</b>\n  Service: <b>$status_service</b>\n  Permissions: <b>$status_permissions</b>\n\nWhat would you like to do?" \
            --radiolist \
            --height=400 \
            --column="" --column="Option" \
            "${zenity_options[@]}")

        if [ $? -ne 0 ]; then break; fi

        case "$choice" in
            "Install / Reconfigure Service") 
                UPDATE_TIME="" do_install 
                ;;
            "Remove Service") 
                do_remove 
                ;;
            "Grant Sudo Permission") 
                do_grant_sudo 
                ;;
            "Revoke Sudo Permission") 
                do_revoke_sudo 
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    case "$MODE" in
        install)
            MODE="cli"
            do_install
            ;;
        remove)
            do_remove
            ;;
        status)
            do_status
            ;;
        grant-sudo)
            do_grant_sudo
            ;;
        revoke-sudo)
            do_revoke_sudo
            ;;
        gui)
            gui_mode
            ;;
    esac
}

main "$@"
