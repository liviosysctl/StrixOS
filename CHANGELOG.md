# Changelog

All notable changes to this project. Versions follow [Semantic Versioning](https://semver.org); entries are generated from [Conventional Commits](https://www.conventionalcommits.org) with git-cliff.

## v0.1.0 — 2026-11-10

First release: an ISO that installs Strix from a few questions in the console, with encryption, hibernation and updates.

### Added
- Add branding as the single source of the distro name
- Add btrfs disk layout with disko
- Add hibernation to the swap file
- Show the distro name and version in os-release
- Add the installer ISO
- Add a strix-install placeholder to the ISO
- Start the console with the Swiss German keyboard layout
- Add user, boot loader and nix settings to the base module
- Install the packages listed in apps.json
- Add rebuild, update and apps commands
- Add mkSystem to build a machine from /etc/nixos
- Add the template for /etc/nixos
- Enable flakes on the live system
- Show a graphical boot splash with Plymouth
- Tell the user when the passphrase was wrong
- Read the LUKS passphrase from a file during install
- Prepare the live system for installing
- Pin installed machines to the commit of the ISO
- Install from a few questions in the console
- Give the console installer the Strix look
- Bring back the shadow under the logo
- Use a console font with every accented letter
- Ask for the language first and follow it everywhere
- Turn on SSH on installed machines and explain it on the ISO
- Know the terminfo of every common terminal
- Keep emoji out of the systemd tools
- Add the theme engine
- Complete commands and themes with tab
- Follow stable on release installs and main on dev installs

### Changed
- Change the default language to English (US)

### Fixed
- Stop infinite recursion when evaluating the module
- Replace the inaccurate progress bar with an activity line
- Stop failing when encryption or hibernation is off
- Stop freezing after resume from hibernation
- Redraw the console after switching the palette
- Drop the hostnamectl emoji and show the keymap in localectl

