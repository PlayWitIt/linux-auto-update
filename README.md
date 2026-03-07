<div align="center">
  <h1>Linux Auto-Update</h1>
  <p>A universal tool that automatically keeps your Linux system fresh and up-to-date.</p>
  
  <p>
    <img alt="Maintenance" src="https://img.shields.io/badge/Maintained%3F-yes-green.svg" />
    <img alt="License" src="https://img.shields.io/github/license/PlayWitIt/linux-auto-update" />
  </p>
</div>

---

## Features

- **Automatic Updates**: Set a time and your system updates itself daily
- **CLI & GUI Modes**: Use CLI flags for servers, GUI (zenity) for desktops
- **Multi-Distro**: Works with yay, pacman, apt, dnf, yum, zypper
- **Systemd Timers**: Modern, reliable scheduling
- **Passwordless Sudo**: Optional automatic sudo configuration

## Installation

### Quick Install (Auto-Runs)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PlayWitIt/linux-auto-update/main/setup_autoupdate.sh)"
```

### Manual Install

```bash
curl -fsSL https://raw.githubusercontent.com/PlayWitIt/linux-auto-update/main/setup_autoupdate.sh -o setup_autoupdate.sh
chmod +x setup_autoupdate.sh
./setup_autoupdate.sh --install --time 07:30
```

## Usage

### CLI Mode (Headless/Server)

```bash
# Install/update service
linux-autoupdate --install --time 07:30

# Check status
linux-autoupdate --status

# Remove service
linux-autoupdate --remove

# Grant passwordless sudo
linux-autoupdate --grant-sudo

# Revoke sudo
linux-autoupdate --revoke-sudo

# Show help
linux-autoupdate --help
```

### GUI Mode (Desktop)

Run without arguments (requires zenity):

```bash
./setup_autoupdate.sh
# or
./setup_autoupdate.sh --gui
```

## Requirements

- systemd
- One of: yay, pacman, apt, dnf, yum, zypper
- zenity (for GUI mode only)

Install zenity if needed:

- **Debian/Ubuntu**: `sudo apt install zenity`
- **Fedora**: `sudo dnf install zenity`
- **Arch**: `sudo pacman -S zenity`

## Files & Locations

- **Service**: `~/.config/systemd/user/linux-autoupdate.service`
- **Timer**: `~/.config/systemd/user/linux-autoupdate.timer`
- **Script**: `~/.local/share/linux-autoupdate/linux-autoupdate.sh`
- **Log**: `~/linux-autoupdate.log`

## License

MIT License - see [LICENSE](LICENSE) file.
