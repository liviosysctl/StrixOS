# The boot loader: GRUB on the ESP (mounted at /boot), as the firmware's
# fallback EFI/BOOT/BOOTX64.EFI (behind shim when Secure Boot is on, see
# secure-boot.nix).
#
# The menu stays hidden: GRUB waits a moment for Esc, F4 or Shift and starts
# the system. When it finds another system on the machine (Windows), the menu
# shows for a few seconds at every start instead, so either can be picked
# without holding a key.
#
# The menu is drawn in the look of StrixUI and follows the theme: theme.nix
# copies the GRUB theme of the selected theme to /boot/grub/<id>/theme.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.boot;
  # GRUB's own folder on the ESP, and ours in it
  grubDir = "${config.boot.loader.efi.efiSysMountPoint}/grub";
  ownDir = "${grubDir}/${branding.id}";

  # After every install: show the menu when os-prober found another system
  menuForOthers = pkgs.writeShellScript "${branding.id}-grub-menu" ''
    set -eu
    # switch-to-configuration runs this with no PATH to speak of
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.diffutils ]}
    cfg=${grubDir}/grub.cfg
    menu=${ownDir}/menu.cfg
    mkdir -p ${ownDir}
    if sed -n '/BEGIN .*30_os-prober/,/END .*30_os-prober/p' "$cfg" | grep -q '^menuentry'; then
      printf 'set timeout=%s\nset timeout_style=menu\n' ${toString cfg.menuTimeout} > "$menu.new"
      if ! cmp -s "$menu.new" "$menu"; then mv "$menu.new" "$menu"; else rm "$menu.new"; fi
    else
      rm -f "$menu"
    fi
  '';
in
{
  options.${branding.id}.boot = {
    menuTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Seconds the boot menu shows when another system (Windows) is on the machine.";
    };
  };

  config = {
    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      # EFI/BOOT/BOOTX64.EFI, the path every firmware starts without a boot entry.
      # The installer adds a boot entry for that path (<id>-secure-boot boot-entry).
      efiInstallAsRemovable = true;
      # Windows and other systems on the machine get an entry
      useOSProber = true;
      configurationLimit = 10; # a 1 GiB ESP easily holds that many
      # Esc, F4 or Shift during that second shows the menu
      timeoutStyle = "hidden";
      # The theme brings its own fonts and its own background: the picture of NixOS would be set
      # before any video mode is ("no video mode activated")
      font = null;
      splashImage = null;
      # grub.cfg lies on the ESP GRUB was started from, and so do the kernels: no search by
      # UUID. A search probes every disk, and for each it cannot read GRUB tries to load a file
      # system module, which Secure Boot forbids ("prohibited by secure boot policy").
      fsIdentifier = "provided";
      gfxmodeEfi = "1920x1080,auto";
      extraConfig = ''
        if [ -f $prefix/${branding.id}/theme/theme.txt ]; then
          insmod all_video
          insmod gfxterm
          insmod gfxmenu
          insmod png
          loadfont $prefix/${branding.id}/theme/mono-16.pf2
          loadfont $prefix/${branding.id}/theme/mono-14.pf2
          set gfxmode=${config.boot.loader.grub.gfxmodeEfi}
          set gfxpayload=keep
          terminal_output gfxterm
          set theme=$prefix/${branding.id}/theme/theme.txt
          export theme
        fi
        if [ -z "''${boot_once}" -a -f $prefix/${branding.id}/menu.cfg ]; then
          source $prefix/${branding.id}/menu.cfg
        fi
      '';
      extraInstallCommands = lib.mkBefore ''
        ${menuForOthers}
      '';
    };
    boot.loader.timeout = lib.mkDefault 1;
    # A removable install never writes boot entries
    boot.loader.efi.canTouchEfiVariables = false;
  };
}
