# Changelog

All notable changes to this project. Versions follow [Semantic Versioning](https://semver.org); entries are generated from [Conventional Commits](https://www.conventionalcommits.org) with git-cliff.

## v0.6.1 — 2026-11-19

Fixes the graphical installer: it sets the password and the Secure Boot key again, and its window fits small screens.

### Fixed
- Give commands in the new system its own PATH
- Fit the window on small screens

## v0.6.0 — 2026-11-19

Installer fully in Rust, the theme's owl from boot menu to lock screen, Neovim for text and Zen as the only browser.

### Added
- Open btop from the load figures of the bar
- Animate search, settings, lock screen and notifications
- Show the owl in fastfetch
- Let the fastfetch owl follow the theme
- Reveal new themes and animate the remaining panels
- Let the owl blink in the splash and on the lock screen
- Draw the boot pictures in Rust, complete outside themes
- Let theme repositories join the change of gods
- Show the owl in the login, in About and in the README
- Give the partition labels a suffix per machine
- Draw the owl of the theme in the boot menu
- Copy the caption with a borrowed picture
- Open text in Neovim, drop gnome-text-editor
- Set Files up as in the own configuration

### Fixed
- Ship only the themes of StrixUI, not its whole repository

### Breaking
- Rewrite the installer in Rust, drop the console UI — there is no interactive console installer any more.
Without a screen, run strix-install --core --answers FILE (README).
- Make Zen the only browser — Firefox is no longer installed.
- Remove the Store from main — there is no Store window or strix-store service on
machines that follow main.

## v0.5.0 — 2026-11-14

A graphical installer in a live desktop, and GRUB in the theme that finds Windows.

### Added
- Draw the GRUB menu in the look of StrixUI and the theme
- Add texts, facts and secrets for other front ends
- Add a graphical installer in the look of StrixUI
- Start into a live desktop with the graphical installer

### Changed
- Replace systemd-boot with GRUB and list Windows in the menu

## v0.4.0 — 2026-11-13

Symbols that move and colour themselves under the pointer.

### Added
- Let symbols move and take their colour under the pointer

## v0.3.0 — 2026-11-13

A single signed ISO again and Neovim in the colours of the theme.

### Added
- Add Neovim in the colors of the theme
- Download the installed system instead of carrying it

### Changed
- Remove the manifest of the bootstick app
- Remove the explanations meant for beginners

### Fixed
- Move stable with a token that may change workflows

## v0.2.0 — 2026-11-13

The desktop with Hyprland, the shell, the Store and Settings, a binary cache, and an ISO that starts with Secure Boot on.

### Added
- Add the search for apps, actions, settings and commands
- Fetch, check and pin theme repositories
- Fetch every theme repository with each update
- Allow bare commands and sub-commands of several words
- Run the session's theme with the 10-minute cycle
- Add Hyprland, the shell, the login and Settings
- Bind the volume, brightness and media keys
- Add laptop parts, capture and the clipboard history
- Search, install and remove apps from nixpkgs
- Add network, Bluetooth, sound, display and power pages
- Give GTK apps the god's colors and show media in the bar
- Ask before installing proprietary apps
- Download the distro's own packages from a binary cache
- Sign the installer ISO for Secure Boot
- Boot installed machines through shim with Secure Boot on

### Changed
- Make the Hyprland keys and Settings findable

### Fixed
- Find the certificate when signing in CI

### Breaking
- Take the eight gods of StrixUI as the themes — the themes chamber and neutral are gone; a machine.nix that sets strix.theme.default to one of them must name a god, e.g. saturnus
- Remove everything for VMware — a machine.nix that sets virtualisation.vmware.guest.enable keeps it, but loses the hibernation fix for VMware

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

