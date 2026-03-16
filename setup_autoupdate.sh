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

# --- Configuration ---
INSTALL_DIR="$HOME/.local/share/linux-autoupdate"
WORKER_SCRIPT_NAME="linux-autoupdate.sh"
SERVICE_NAME="linux-autoupdate"
SCRIPT_FULL_PATH="${INSTALL_DIR}/${WORKER_SCRIPT_NAME}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"
LOG_FILE="$HOME/linux-autoupdate.log"
SUDOERS_FILE="/etc/sudoers.d/99-autoupdate-permissions"

# --- Globals ---
MODE="gui" # Default mode
UPDATE_TIME="" # Will be set by user

# --- Helper Functions ---
msg() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
warn() { echo "[WARNING] $*" >&2; }

show_help() {
    cat << 'HELP'
Usage: linux-autoupdate [OPTIONS]

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
  linux-autoupdate --install --time 07:30
  linux-autoupdate --status
  linux-autoupdate --remove
  linux-autoupdate --grant-sudo
  linux-autoupdate --gui

GUI MODE:
  Run without arguments or with --gui to launch an interactive zenity dialog.

REQUIREMENTS:
  - systemd
  - zenity (for GUI mode only)
  - One of: yay, pacman, apt, dnf, yum, zypper
HELP
}

parse_args() {
    # If no arguments are provided, keep default GUI mode
    if [[ $# -eq 0 ]]; then
        return
    fi

    # Set mode to an empty string if any argument is passed, so we don't default to gui
    MODE=""
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

    # If no primary mode was selected after parsing, it's an error
    if [[ -z "$MODE" ]]; then
        err "No action specified. Use --install, --remove, etc."
        show_help
        exit 1
    fi
}

validate_time() {
    local time="$1"
    local sanitized
    sanitized=$(echo "$time" | tr -d ':')

    if [[ ! "$sanitized" =~ ^[0-9]{3,4}$ ]]; then
        err "Invalid time format. Use HH:MM or H:MM (e.g., 07:30 or 7:30)"
        return 1
    fi

    # Pad with leading zero if needed (e.g., 730 -> 0730)
    if [[ ${#sanitized} -eq 3 ]]; then
        sanitized="0${sanitized}"
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
    # Prefer yay if it exists
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    fi
}

# --- Core Logic Functions ---

do_install() {
    if [[ -z "${UPDATE_TIME:-}" ]]; then
        err "Update time was not provided to the install function."
        return 1
    fi

    local formatted_time
    formatted_time=$(validate_time "$UPDATE_TIME") || exit 1

    msg "Stopping existing timer if present..."
    systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true

    msg "Creating update script in $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    tee "$SCRIPT_FULL_PATH" > /dev/null << 'EOF'
#!/bin/bash
# This is the worker script that performs the actual update
LOG_FILE="$HOME/linux-autoupdate.log"

run_system_update() {
    if command -v yay &>/dev/null; then
        echo "--- Found yay. Updating Arch Linux + AUR packages... ---"
        yay -Syu --noconfirm
    elif command -v pacman &>/dev/null; then
        echo "--- Found pacman. Updating Arch Linux packages... ---"
        sudo pacman -Syu --noconfirm
    elif command -v apt &>/dev/null; then
        echo "--- Found apt. Updating Debian/Ubuntu packages... ---"
        sudo apt update && sudo apt upgrade -y
    elif command -v dnf &>/dev/null; then
        echo "--- Found dnf. Updating Fedora packages... ---"
        sudo dnf upgrade -y
    elif command -v yum &>/dev/null; then
        echo "--- Found yum. Updating CentOS/RHEL packages... ---"
        sudo yum update -y
    elif command -v zypper &>/dev/null; then
        echo "--- Found zypper. Updating openSUSE packages... ---"
        sudo zypper --non-interactive ref && sudo zypper --non-interactive dup
    else
        echo "--- ERROR: No supported package manager found (yay, pacman, apt, dnf, yum, zypper). ---"
        return 1
    fi
}

# Redirect all output to a log file
{
    echo "--- SCRIPT STARTED AT $(date) ---"
    run_system_update
    echo "--- SCRIPT FINISHED AT $(date) ---"
} >> "$LOG_FILE" 2>&1
EOF
    chmod +x "$SCRIPT_FULL_PATH"

    msg "Creating systemd service and timer files..."
    mkdir -p "$(dirname "$SERVICE_FILE")"

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
Persistent=true
[Install]
WantedBy=timers.target
EOF

    msg "Reloading systemd, then enabling and starting timer..."
    systemctl --user daemon-reload
    if ! systemctl --user enable --now "${SERVICE_NAME}.timer"; then
        err "Failed to enable and start systemd timer."
        exit 1
    fi

    if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null; then
        msg "Service installed successfully. It will run daily at ${formatted_time}."
        msg "Log file can be found at: ${LOG_FILE}"
    else
        err "Timer installed but failed to start. Check systemd logs with 'journalctl --user -u ${SERVICE_NAME}.timer'"
        exit 1
    fi
}

do_remove() {
    msg "Stopping and disabling timer..."
    systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true

    msg "Removing files..."
    rm -f "$SERVICE_FILE" "$TIMER_FILE" "$LOG_FILE"
    rm -rf "$INSTALL_DIR"

    systemctl --user daemon-reload
    msg "Service removed successfully."
}

do_status() {
    echo "=== Autoupdate Service Status ==="

    if [ -f "$TIMER_FILE" ]; then
        local scheduled_time
        scheduled_time=$(grep 'OnCalendar=' "$TIMER_FILE" | cut -d' ' -f2)
        if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
            echo "Timer Status: ACTIVE (runs daily at $scheduled_time)"
        else
            echo "Timer Status: INACTIVE (scheduled for $scheduled_time, but not running)"
        fi
        systemctl --user status --no-pager "${SERVICE_NAME}.timer"
    else
        echo "Timer Status: NOT INSTALLED"
    fi

    local pm
    pm=$(get_pm)
    if [ -n "$pm" ]; then
        echo "Package Manager Detected: $pm"
        if sudo -n "$(command -v "$pm")" --version >/dev/null 2>&1; then
            echo "Passwordless Sudo: CONFIGURED"
        else
            echo "Passwordless Sudo: NOT CONFIGURED (will ask for password)"
        fi
    else
        echo "Package Manager Detected: NOT FOUND"
    fi

    if [ -f "$LOG_FILE" ]; then
        echo -e "\n--- Last 5 lines of log ($LOG_FILE) ---"
        tail -n 5 "$LOG_FILE"
    fi
}

do_grant_sudo() {
    local pm
    pm=$(get_pm)

    if [ -z "$pm" ]; then
        err "No supported package manager found."
        exit 1
    fi

    local pm_path
    pm_path=$(command -v "$pm")
    local current_user
    current_user=$(whoami)

    msg "This will grant passwordless sudo for the command: $pm_path"
    local content="$current_user ALL=(ALL) NOPASSWD: $pm_path"

    echo "Creating '$SUDOERS_FILE' with content:"
    echo "$content"

    # Use pkexec to run a shell that creates and sets permissions on the sudoers file
    if pkexec bash -c "echo '$content' > '$SUDOERS_FILE' && chmod 0440 '$SUDOERS_FILE'"; then
        msg "Passwordless sudo granted successfully for $pm."
    else
        err "Failed to grant sudo permission. pkexec might have failed or been cancelled."
        exit 1
    fi
}

do_revoke_sudo() {
    if [ ! -f "$SUDOERS_FILE" ]; then
        warn "Sudoers file ($SUDOERS_FILE) not found. Nothing to revoke."
        return
    fi

    msg "This will remove the file: $SUDOERS_FILE"
    if pkexec rm -f "$SUDOERS_FILE"; then
        msg "Passwordless sudo permissions have been revoked."
    else
        err "Failed to revoke sudo permission. pkexec might have failed or been cancelled."
        exit 1
    fi
}

gui_mode() {
    if ! command -v zenity &>/dev/null; then
        err "Zenity is not installed. Please install it to use GUI mode."
        err "On Debian/Ubuntu: sudo apt install zenity"
        err "On Fedora: sudo dnf install zenity"
        err "On Arch: sudo pacman -S zenity"
        exit 1
    fi

    while true; do
        # Refresh status every loop
        local status_service="NOT INSTALLED"
        local status_permissions="REQUIRES PASSWORD"
        local is_service_installed=false
        local has_passwordless_sudo=false

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

        local pm
        pm=$(get_pm)
        if [ -n "$pm" ]; then
            if sudo -n "$(command -v "$pm")" --version >/dev/null 2>&1; then
                status_permissions="CONFIGURED"
                has_passwordless_sudo=true
            fi
        fi

        # Build menu based on current status
        local menu_items=()
        menu_items+=( "Install / Reconfigure Service" )
        if $is_service_installed; then
            menu_items+=( "Remove Service" )
        fi

        if $has_passwordless_sudo; then
            menu_items+=( "Revoke Sudo Permission" )
        else
            menu_items+=( "Grant Sudo Permission" )
        fi

        local zenity_options=()
        for item in "${menu_items[@]}"; do
             zenity_options+=( FALSE "$item" )
        done

        local choice
        choice=$(zenity --list \
            --title="Universal Update Manager" \
            --text="<b>Current Status:</b>\n  Service: <b>$status_service</b>\n  Permissions: <b>$status_permissions</b>\n\nWhat would you like to do?" \
            --radiolist \
            --height=400 \
            --width=450 \
            --column="" --column="Option" \
            "${zenity_options[@]}")

        # Exit if user cancels or closes the window
        if [ $? -ne 0 ]; then break; fi

        case "$choice" in
            "Install / Reconfigure Service")
                local user_time
                user_time=$(zenity --entry \
                    --title="Set Update Time" \
                    --text="Please enter the daily update time in HH:MM format (e.g., 03:00 or 15:30):")

                if [ $? -eq 0 ] && [ -n "$user_time" ]; then
                    UPDATE_TIME="$user_time"
                    do_install | zenity --progress --pulsate --no-cancel --auto-close --title="Installation" --text="Installing service..."
                    zenity --info --text="Installation complete!" --width=300
                fi
                ;;
            "Remove Service")
                if zenity --question --text="Are you sure you want to completely remove the autoupdate service?"; then
                    do_remove | zenity --progress --pulsate --no-cancel --auto-close --title="Removal" --text="Removing service..."
                    zenity --info --text="Service removed." --width=300
                fi
                ;;
            "Grant Sudo Permission")
                zenity --info --text="You will be asked for your password to grant permission." --width=300
                do_grant_sudo
                ;;
            "Revoke Sudo Permission")
                zenity --info --text="You will be asked for your password to revoke permission." --width=300
                do_revoke_sudo
                ;;
        esac
    done
}

# --- Main Execution ---

main() {
    parse_args "$@"

    case "$MODE" in
        install)
            if [[ -z "${UPDATE_TIME:-}" ]]; then
                read -p "Enter update time (HH:MM): " -r REPLY
                [[ -z "$REPLY" ]] && { msg "Install cancelled."; exit 0; }
                UPDATE_TIME="$REPLY"
            fi
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
