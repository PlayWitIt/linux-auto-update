# Changelog

All notable changes to linux-autoupdate will be documented in this file.

## [1.0.0] - 2026-03-07

### Added
- CLI mode support (`--install`, `--remove`, `--status`, `--time`, `--grant-sudo`, `--revoke-sudo`)
- GUI mode (zenity) for desktop users
- Explicit `--gui` flag
- Multi-distro support (Arch, Debian/Ubuntu, Fedora, CentOS, openSUSE)
- Auto-answer yay AUR prompts (`--answerclean All --answerdiff All`)
- Proper systemd timer install/remove with stop/disable/daemon-reload

### Changed
- Renamed service to `linux-autoupdate` (was `autoupdate`)
- Updated file paths to use `linux-autoupdate` prefix

### Fixed
- Timer not firing after remove/reinstall
- Service file missing `Type=oneshot`
- Timer file missing `Unit=` directive
- Status showing incorrect state
