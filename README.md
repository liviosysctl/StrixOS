# Strix

Strix is a NixOS-based Linux distribution for people coming from Windows. The goal is NixOS without the terminal: create the install stick on Windows with one click, install apps from a store with one click, and switch the look of the whole desktop with a theme.

This is an early work in progress. Nothing here builds a usable system yet.

## Branches

| Branch | Content |
|---|---|
| `main` | The proof of concept for the school module M245: Windows bootstick app, app store, signed ISO. |
| `personal` | The distribution as I use it myself, without the store and the beginner parts. |

Changes that matter for both go into both branches. When M245 is over, `personal` becomes `main` and the proof of concept moves to its own branch.

## What is in the repository

| Path | Content |
|---|---|
| `branding.nix` | The only place the distro name appears. Everything else derives from it. |
| `lib/mk-system.nix` | `lib.mkSystem`: builds a machine from the files in `/etc/nixos`. |
| `modules/` | The distro modules: os-release, base system, the three tools, apps from `apps.json`, disk layout. |
| `modules/storage/btrfs.nix` | Disk layout with disko: GPT, ESP, optional LUKS, btrfs with flat subvolumes, Snapper for `/home`, hibernation. |
| `modules/boot-splash.nix` | Graphical boot with Plymouth: wordmark, progress line, a styled passphrase field. |
| `modules/theme.nix` | The theme engine on the system: the `strix-theme` command, the service that applies the theme at boot, the boot splash that follows it. |
| `themes/` | The themes, one folder with a `theme.toml` each: `neutral` (black and red) and `chamber` (Chamber UI, light and dark). [themes/README.md](themes/README.md) describes the format. |
| `packages/theme-engine/` | The theme engine in Rust: reads and checks themes, switches them at runtime. |
| `lib/themes.nix` | Themes at build time: the checked themes folder, a Plymouth theme per variant, the installer's colors. |
| `packages/plymouth-theme/` | Builds the Plymouth theme of one theme variant. |
| `templates/machine/` | Template for `/etc/nixos` that the installer fills in. |
| `hosts/` | Made-up machines for CI and testing: `reference` and `vmware`. |
| `iso/default.nix` | The installer ISO, built on the minimal NixOS installer. |
| `installer/` | `strix-install`: asks a few questions in the console, then partitions, encrypts and installs. `--core --answers FILE` installs without asking. |
| `tests/` | Checks for `nix flake check`. |
| `flake.nix` | Version, modules, machines, the ISO, checks and a dev shell. |

## On an installed machine

`/etc/nixos` holds `flake.nix`, `flake.lock`, `hardware.nix`, `machine.nix` and `apps.json`. These commands work with it:

| Command | Does |
|---|---|
| `sudo strix-rebuild [switch\|boot\|test\|build]` | Rebuilds from `/etc/nixos` |
| `sudo strix-update` | Fetches the newest release and switches to it, keeps the old version if the build fails |
| `sudo strix-apps add\|remove <package>`, `strix-apps list` | Installs or removes a package from nixpkgs. This is what the Store calls. |
| `sudo strix-theme set <theme>`, `strix-theme list` | Switches the theme without a rebuild, see [themes/README.md](themes/README.md). |

SSH is on: `ssh <user>@<address>` with the user's password. Root cannot log in. To turn it off, add `services.openssh.enable = false;` to `machine.nix` and rebuild.

## Planned

- Strix base system with Hyprland and Quickshell
- Theme engine for the desktop: Quickshell, Ghostty, GTK and Qt follow the theme (the engine, the console, the boot splash and `tokens.json` are done)
- Store: install packages from nixpkgs with one click
- Bootstick app for Windows (separate repository)

## Building the ISO

Needs Nix with flakes on Linux (NixOS-WSL works) and about 20 GB of free disk.

```sh
nix build .#iso-dev -L    # faster compression, for testing
nix build .#iso -L        # release compression
ls -lh result/iso/
```

Machines installed from `iso` follow the branch `stable`, which only moves when a release is published. Machines installed from `iso-dev` follow `main` and get every fix with `strix-update`. CI builds an `iso-dev` on every push to `main` (Actions, the run, "Artifacts").

The ISO boots on UEFI with Secure Boot off. Write it to a USB stick as a raw image, not by copying files onto a FAT32 stick.

Commit and push before building a release ISO. Only an ISO from a clean tree with a `flake.lock` pins the installed system to its own commit; from a dirty tree the installer locks during the install and needs the network for it.

## Installing

Boot the ISO, then:

```sh
sudo strix-install
```

It asks for the language first, and every screen after that is in German, French, Italian or English. Then keyboard, time zone, name, user, password, computer name, disk, encryption and hibernation, a summary, and it only starts after you type the disk's name. The whole disk is used. The log ends up in `/var/log/strix-install.log` on the installed system.

SSH already runs on the live system. To install over SSH, set a password with `passwd`, look up the address with `ip -4 addr` and connect with `ssh nixos@<address>`.

## Development

```sh
nix develop
```

The dev shell activates the commit hook and has the Rust tools for the theme engine. Commit and release rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

```sh
nix flake check                                       # fast checks, also run by CI on every push
(cd packages/theme-engine && cargo test && cargo clippy --all-targets -- -D warnings)
nix build .#tests.theme -L                            # the theme engine in a VM, needs KVM
nix build .#tests.install -L                          # install on an empty disk and boot it, needs KVM
```

### Releasing

Same flow as the other repositories (CONTRIBUTING.md): bump the version in `flake.nix`, commit `chore(release): vX.Y.Z`, push an annotated tag. The release workflow then creates the release with the notes, builds the ISO, attaches it with `SHA256SUMS` and `manifest.json` (the bootstick app reads that), and moves `stable` to the tag. An ISO larger than 2 GiB is attached in parts, `manifest.json` lists them.

Before tagging, try the packaging without a release: Actions, "Release", "Run workflow". The files land in the run as an artifact.
