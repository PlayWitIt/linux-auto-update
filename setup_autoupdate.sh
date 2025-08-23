#!/bin/bash
# SCRIPT: setup_autoupdate.sh

# --- Configuration ---
INSTALL_DIR="$HOME/.local/share/autoupdate"
WORKER_SCRIPT_NAME="AutoUpdatePackages.sh"
SERVICE_NAME="autoupdate"
SCRIPT_FULL_PATH="${INSTALL_DIR}/${WORKER_SCRIPT_NAME}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"
LOG_FILE="$HOME/autoupdate.log"
SUDOERS_FILE="/etc/sudoers.d/99-autoupdate-permissions"

# --- Pre-flight Check ---
if ! command -v zenity &>/dev/null; then exit 1; fi

# --- Functions ---

install_routine() {
    local user_time
    user_time=$(zenity --entry --title="Set Update Time" --text="Enter desired update time (e.g., 07:40 or 0740):")
    if [ -z "$user_time" ]; then return; fi

    local sanitized_time
    sanitized_time=$(echo "$user_time" | tr -d ':')

    if [[ ! "$sanitized_time" =~ ^[0-9]{4}$ ]]; then
        zenity --error --text="Invalid format. Please enter a 4-digit time like 0740 or 07:40."
        return
    fi

    local hour=${sanitized_time:0:2}
    local minute=${sanitized_time:2:2}

    if (( 10#$hour > 23 || 10#$minute > 59 )); then
        zenity --error --text="Invalid time. Hour must be 00-23 and minute must be 00-59."
        return
    fi

    local formatted_time="$hour:$minute"

    mkdir -p "$INSTALL_DIR"
    tee "$SCRIPT_FULL_PATH" > /dev/null << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/autoupdate.log"

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

    mkdir -p "$HOME/.config/systemd/user/"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Run universal autoupdate script
[Service]
ExecStart=$SCRIPT_FULL_PATH
EOF
    cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run autoupdate daily at ${formatted_time}
[Timer]
OnCalendar=*-*-* ${formatted_time}:00
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    if systemctl --user enable --now "${SERVICE_NAME}".timer; then
        zenity --info --text="Service Installed for ${formatted_time} daily."
    else
        zenity --error --text="Failed to enable or start the systemd timer."
    fi
}

remove_routine() {
    if systemctl --user disable --now "${SERVICE_NAME}".timer >/dev/null 2>&1; then
        rm -f "$SERVICE_FILE" "$TIMER_FILE"
        rm -rf "$INSTALL_DIR"
        zenity --info --text="Service Removed Successfully."
    else
        rm -f "$SERVICE_FILE" "$TIMER_FILE"
        rm -rf "$INSTALL_DIR"
        zenity --warning --text="Could not disable systemd timer, but files were removed."
    fi
}

add_sudo() {
    local pm_path=""
    if command -v yay &>/dev/null || command -v pacman &>/dev/null; then pm_path=$(command -v pacman);
    elif command -v apt &>/dev/null; then pm_path=$(command -v apt);
    elif command -v dnf &>/dev/null; then pm_path=$(command -v dnf);
    elif command -v yum &>/dev/null; then pm_path=$(command -v yum);
    elif command -v zypper &>/dev/null; then pm_path=$(command -v zypper);
    fi

    if [ -z "$pm_path" ]; then
        zenity --error --text="Could not find a supported package manager to configure."
        return
    fi

    CURRENT_USER=$(whoami)
    COMMAND="echo '$CURRENT_USER ALL=(ALL) NOPASSWD: $pm_path' > '$SUDOERS_FILE' && chmod 0440 '$SUDOERS_FILE'"
    if pkexec --user root bash -c "$COMMAND"; then
        zenity --info --text="Sudo permission granted successfully for $pm_path."
    else
        zenity --error --text="Failed to grant sudo permission. Authentication may have been canceled."
    fi
}

remove_sudo() {
    local pm_path_base=""
    # Get the base name of the package manager executable (e.g., "pacman")
    if command -v yay &>/dev/null || command -v pacman &>/dev/null; then pm_path_base="pacman";
    elif command -v apt &>/dev/null; then pm_path_base="apt";
    elif command -v dnf &>/dev/null; then pm_path_base="dnf";
    elif command -v yum &>/dev/null; then pm_path_base="yum";
    elif command -v zypper &>/dev/null; then pm_path_base="zypper";
    fi

    if [ -z "$pm_path_base" ]; then
        zenity --error --text="Could not find a supported package manager to revoke permissions for."
        return
    fi

    # This comprehensive command removes our specific file AND searches for any other rules.
    local COMMAND_TO_RUN="
    rm -f '$SUDOERS_FILE'
    sed -i.bak '/NOPASSWD.*$pm_path_base/d' /etc/sudoers
    for file in /etc/sudoers.d/*; do
        if [ -f \\\"\$file\\\" ]; then
            sed -i.bak '/NOPASSWD.*$pm_path_base/d' \\\"\$file\\\"
        fi
    done
    "
    if pkexec --user root bash -c "$COMMAND_TO_RUN"; then
        zenity --info --text="Sudo permission revoked successfully."
    else
        zenity --error --text="Failed to revoke sudo permission. Authentication may have been canceled."
    fi
}


# --- Main Menu ---
while true; do
    status_service="NOT INSTALLED"
    status_permissions="REQUIRES PASSWORD"
    is_service_installed=false
    has_passwordless_sudo=false

    if [ -f "$TIMER_FILE" ]; then
        local scheduled_time
        scheduled_time=$(grep 'OnCalendar=' "$TIMER_FILE" | cut -d' ' -f2)
        status_service="INSTALLED (${scheduled_time})"
        is_service_installed=true
    fi

    # FUNCTIONAL CHECK: Test if sudo works without a password for the detected package manager.
    # This is reliable, unlike checking for a file we don't have permission to see.
    pm_test_path=""
    if command -v yay &>/dev/null || command -v pacman &>/dev/null; then pm_test_path=$(command -v pacman);
    elif command -v apt &>/dev/null; then pm_test_path=$(command -v apt);
    elif command -v dnf &>/dev/null; then pm_test_path=$(command -v dnf);
    elif command -v yum &>/dev/null; then pm_test_path=$(command -v yum);
    elif command -v zypper &>/dev/null; then pm_test_path=$(command -v zypper);
    fi

    if [ -n "$pm_test_path" ]; then
        # Use a simple, non-destructive command like --version to test sudo access.
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
        "Install / Reconfigure Service") install_routine ;;
        "Remove Service") remove_routine ;;
        "Grant Sudo Permission") add_sudo ;;
        "Revoke Sudo Permission") remove_sudo ;;
    esac
done
