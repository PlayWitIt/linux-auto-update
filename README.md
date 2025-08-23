# Universal Update Manager 🚀

Tired of manually typing update commands every day? Say hello to your new best friend! This little script is a friendly, set-it-and-forget-it tool that automatically keeps your Linux system fresh and up-to-date.

## ✨ Why You'll Love It

*   **Effortless Updates**: Simply set a time, and the script handles the rest. Your system will update itself automatically every day while you do more important things.
*   **Super Simple Menu**: No scary command lines! A straightforward graphical menu guides you through every step.
*   **Plays Well with Others**: Works on a wide range of Linux distributions, including Arch, Ubuntu, Debian, Fedora, openSUSE, and more. It automatically detects your system's package manager.
*   **You're in Control**: Easily install, reconfigure the update time, or remove the service whenever you want.
*   **Peace of Mind**: Keep your system secure with the latest patches without even thinking about it.

## 🏁 How to Get Started

Getting up and running is as easy as 1-2-3!

1.  **Save the script**: Save the code as `setup_autoupdate.sh`.
2.  **Make it executable**: Open your terminal, navigate to where you saved the file, and run:
    ```bash
    chmod +x setup_autoupdate.sh
    ```3.  **Launch it!**: Run the script from your terminal:
    ```bash
    ./setup_autoupdate.sh
    ```

## exploring-the-menu The Menu Options Explained

A friendly window will pop up to show you the current status and your options. Here’s what they do:

*   **Install / Reconfigure Service**: This is your starting point!
    *   Choose this to set up the automatic updates for the first time.
    *   You'll be asked to enter your desired daily update time (like `08:30` or `19:00`).
    *   You can also run this again anytime you want to change the update schedule.

*   **Grant Sudo Permission**: For the magic to happen without bugging you for a password every day, the script needs permission to run updates.
    *   This option safely grants the necessary permission *only* for the package manager. It’s like giving a key to the gardener, but not your whole house.

*   **Remove Service**: If you decide you want to go back to manual updates, this option cleans everything up for you. It removes the scripts, the schedule, and all related files.

*   **Revoke Sudo Permission**: This takes back the password-free permission you granted. It's the perfect way to tidy up if you're uninstalling the service.

## 🔧 For the Curious: How It Works

This tool is made of a few simple parts:

*   **The Main Script (`setup_autoupdate.sh`)**: The friendly menu you interact with.
*   **The Worker Bee (`AutoUpdatePackages.sh`)**: This is the script that does the actual work of checking for and installing updates. It gets placed in `~/.local/share/autoupdate/`.
*   **The Scheduler (`systemd` timers)**: The script creates a simple service and timer file in `~/.config/systemd/user/` to tell your system *when* to run the updates.
*   **The Log Book (`autoupdate.log`)**: A log file is kept in your home directory so you can see a history of when updates were run and what was updated.

---

That's it! Enjoy a perpetually up-to-date and secure system with zero effort. Happy computing! 🎉
