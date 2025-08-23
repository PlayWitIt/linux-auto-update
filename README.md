***

<div align="center">
  <img src="https://i.imgur.com/g06aE8j.png" alt="Project Banner" style="width: 75%;"/>
  <h1>Universal Linux Auto-Update</h1>
  <p>A friendly, set-it-and-forget-it tool that automatically keeps your Linux system fresh and up-to-date.</p>
  
  <p>
    <img alt="Maintenance" src="https://img.shields.io/badge/Maintained%3F-yes-green.svg" />
    <img alt="License" src="https://img.shields.io/github/license/PlayWitIt/linux-auto-update" />
  </p>
</div>

Tired of manually typing update commands every day? This script uses a simple graphical menu to schedule automatic daily system updates. It's built to be safe, easy to use, and compatible with most major Linux distributions.

---

## ✨ Why You'll Love It

*   **Effortless Updates**: Simply set a time, and the script handles the rest. Your system will update itself automatically every day.
*   **Super Simple Menu**: No scary command lines! A straightforward graphical menu guides you through every step.
*   **Plays Well with Others**: Works on a wide range of Linux distributions, including Arch, Ubuntu, Debian, Fedora, openSUSE, and more.
*   **You're in Control**: Easily install, reconfigure the update time, manage permissions, or remove the service whenever you want.
*   **Peace of Mind**: Keep your system secure with the latest patches without even thinking about it.

## ⚙️ Prerequisites

Before you run the script, you need to have `zenity` installed. This is what creates the graphical pop-up menu.

You can usually install it with your system's package manager:

-   **On Debian/Ubuntu:** `sudo apt install zenity`
-   **On Fedora:** `sudo dnf install zenity`
-   **On Arch Linux:** `sudo pacman -S zenity`

## 🚀 One-Liner Installation & Usage

Getting up and running is as easy as pasting one command into your terminal. This will download and immediately run the setup script.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PlayWitIt/linux-auto-update/main/setup_autoupdate.sh)"
```

A graphical menu will appear. Just follow the on-screen options to install and configure the service.

## 📖 The Menu Options Explained

*   **Install / Reconfigure Service**: Your starting point! Use this to set up automatic updates for the first time or to change the daily schedule later on.
*   **Grant Sudo Permission**: To run updates without asking for your password every day, the script needs permission. This option safely grants password-free access *only* for your system's package manager.
*   **Remove Service**: If you want to go back to manual updates, this option cleanly removes all script files, schedules, and configurations.
*   **Revoke Sudo Permission**: This securely removes the password-free permissions you granted. It's the perfect way to tidy up if you're uninstalling.

## 🔧 For the Curious: How It Works

*   **Main Script (`setup_autoupdate.sh`)**: The friendly Zenity menu you interact with for configuration.
*   **Worker Script (`AutoUpdatePackages.sh`)**: This is the script that does the actual work of detecting your package manager and running the update commands. It gets placed in `~/.local/share/autoupdate/`.
*   **Scheduler (`systemd` timers)**: The script creates a modern user-level systemd service and timer in `~/.config/systemd/user/` to schedule the daily execution.
*   **Log File (`autoupdate.log`)**: A log is kept in your home directory so you can see a history of when updates were run.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

Enjoy a perpetually up-to-date and secure system with zero effort. Happy computing! 🎉
