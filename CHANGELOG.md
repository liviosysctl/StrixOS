# Changelog

All notable changes to this project. Versions follow [Semantic Versioning](https://semver.org); entries are generated from [Conventional Commits](https://www.conventionalcommits.org) with git-cliff.

## v0.8.0 — 2026-11-26

The look of design version 2 with dark and light for every god, a fuller desktop around Hyprland, and an installer that puts Strix next to Windows.

### Added
- The dock shows the apps, and what is playing
- The dock holds tools and what is playing, no apps
- List the btrfs subvolumes in Files
- Set up the editor for a first day, with a cheat sheet
- Add the stay awake cup to the bar, steaming while on
- Start the tree at the root and keep the Nix config a key away
- Show the build and what changes in a rebuild
- Add comma and the hint for a missing command
- Suggest the options of NixOS while typing
- Close the calendar on a click elsewhere, add wheel actions
- Add a tray to the bar, with the menus in its look
- Answer calculations and unit conversions
- Float dialogs, pin picture-in-picture, swipe workspaces
- Add strix-doctor, which looks the system over
- Add the window switcher and screenshots to draw on
- Gather the tray behind one symbol with a small panel
- Find files and folders of the home
- Keep the messages of the session under Earlier
- Open on a first page with a card for every page
- Mark the microphone in use, set the volume per app
- Give Zen the shapes of the shell, not only its colors
- Blur what lies behind the glass of the shell
- Keep the choice of light or dark through the change of gods
- Rebuild every surface on one grid of smoked glass
- Grow the search into the browser window (mockup)
- Let what lies behind show through the selection
- Grow the search into the browser itself
- Play DRM video and decode video on Intel cards
- Let the search grow into the new frame of the browser
- Take signs, umlauts and the keys over the arrows
- Give Zen the colours of the theme and a shape of its own
- Hand what the search does not find to Zen
- Draw Zen as smoked glass like the shell
- Add the newest kernel, systemd-oomd and thermald
- Run programs built for other systems with nix-ld
- Add Lua and TOML language servers to Neovim
- Add Flatpak with Flathub
- Show Chinese, Japanese and Korean text
- Recolour the pointer and add a terminal effect
- Ask for polkit passwords in a window of the shell
- Add an overview of the workspaces
- Show a clock and what plays on the bare desktop
- Add account, time, apps, storage and printers pages
- Bind mouse drags, all workspaces and the scratchpad
- Dim the login screen after five idle minutes
- Leave the time to the clock of the desktop while it shows
- Round plates by the inset of the controls inside them
- Put the buttons of the bar on shared plates
- Allow the system next to others on one disk
- Install into a partition or free space next to Windows

### Changed
- Replace the owl with the pen drawing of design version 2
- Change the terminal and monospace font to IBM Plex Mono
- Change the theme picker to Super G, add Super L
- Remove the captions of the engravings
- Hold the picker's pictures only while it is open
- Stop Xwayland and the printer applet
- Remove the styling of Zen
- Go back to the Ghostty of nixpkgs
- Keep the terminal waiting in the background
- Replace udiskie with strix-automount
- Run tailscaled only while Tailscale is on
- Start CUPS on demand without cups-browsed
- Start sshd for each connection
- Decode the wallpaper at the size of the screen
- Remove Flatpak
- Change the first page to the pages in three groups

### Fixed
- Small things of the look, found by rendering every surface
- Find a new version within an hour of the last update
- Ask GitHub's Git server for the newest commit
- Open the system monitor at nine tenths of the screen
- Keep a toast whole and in place, and let a click dismiss it
- Load the fonts of the new design system
- Use the accent more sparingly
- Follow held keys without falling behind
- Close every popup on a click elsewhere or a hotkey
- Take a region of what the shell has open, too
- Stop the Secure Boot errors at every start
- Give the waiting terminal the session's PATH
- Delete pictures that left the history
- Fill the columns of the cheat sheet from the top
- Stack the clock of the login closely, greet without spacing
- Drop the label in capitals over the carousel

### Breaking
- Change the look to version 2 of the design system — every god has the variants dark and light; the fonts are Hanken Grotesk, Cormorant Garamond and IBM Plex Mono
- Replace Zen with the browser of Strix — Zen is no longer installed; its profile stays in ~/.zen and can be removed
- Make Zen the browser again — the browser of Strix and Firefox are no longer installed; what the own browser kept stays in ~/.local/share/strix-browser and can be removed

## v0.7.0 — 2026-11-19

Strix 0.7.0

### Added
- Add the dock at the bottom edge
- Give Zen the colours of the theme
- Choose in the theme picker with Space
- Give the prompt the colours of the god
- Record the whole screen, warn on low battery, printers
- Fade the engraving behind the theme picker
- Daily apps, night light, firmware, zram and terminal tools
- Zsh, keyring, idle times, stay awake and input settings
- Screens, folders, pointer, Qt and terminal follow the theme

### Changed
- Drop quick panels from the symbols of the bar
- Update mark, rollback of a broken update, versions, Tailscale

### Fixed
- Slide the theme picker like the StrixUI carousel
- Round owl in fastfetch, larger monitor, pictures in clipboard
- Find the night light as a setting

## v0.6.3 — 2026-11-19

Updates install the boot loader again.

### Fixed
- Let the update install the boot loader again

## v0.6.2 — 2026-11-19

Clicks in the bar and Search work, the theme picker sets the theme, and the terminal gets its font, prompt and window motion.

### Added
- Slide windows in, scale a laptop's Full HD to 125 %
- Add Geist Mono and a prompt with bars to the terminal

### Changed
- Change to ruled sections with symbols
- Make everything in the bar a button, drop the hint

### Fixed
- Start programs from the bar, Search and the picker
- Say to pull the stick only once the screen is dark
- Scroll the cheat sheet on a small screen
- Stop the GRUB errors at every start
- Draw the wallpaper undistorted

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

