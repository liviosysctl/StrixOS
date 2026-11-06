# Speicherlayout
#
# GPT mit ESP und einer Systempartition (optional LUKS), darauf btrfs mit
# flachen Subvolumes. Braucht disko: Die Flake importiert
# disko.nixosModules.disko zusammen mit diesem Modul.
#
# Kein Snapshot von "/": Das System selbst ist über NixOS-Generationen
# rücksetzbar, und /nix gehört nie in einen Snapshot. Gesichert wird nur
# /home, wo die Daten liegen, die Nix nicht neu bauen kann.
{ config, lib, ... }:

let
  # Direkt importiert statt als Modul-Argument: Die Optionsnamen hängen vom
  # Namen ab, und Modul-Argumente sind erst nach den Optionen bekannt.
  branding = import ../../branding.nix;
  cfg = config.${branding.id}.storage;

  # zstd:1 ist auf NVMe praktisch gratis und spart bei /nix viel Platz.
  # noatime verhindert Schreibzugriffe bei jedem Lesen (wichtig mit Snapshots).
  defaultMountOptions = [
    "compress=zstd:1"
    "noatime"
  ];

  mkSubvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = defaultMountOptions;
  };

  subvolumes =
    {
      "@root" = mkSubvolume "/";
      "@home" = mkSubvolume "/home";
      "@nix" = mkSubvolume "/nix";
      # Eigene Subvolumes, damit Logs und Caches nicht in Home-Snapshots
      # oder ein späteres Zurücksetzen von "/" hineingezogen werden.
      "@log" = mkSubvolume "/var/log";
      "@cache" = mkSubvolume "/var/cache";
    }
    // lib.optionalAttrs cfg.homeSnapshots {
      # Getrennt von @home, damit ein Restore von @home die Snapshots nicht löscht.
      "@home-snapshots" = mkSubvolume "/home/.snapshots";
    }
    // lib.optionalAttrs (cfg.swapSize != null) {
      # Ohne Kompression: Swapfiles auf btrfs müssen NOCOW und unkomprimiert sein.
      "@swap" = {
        mountpoint = "/swap";
        mountOptions = [ "noatime" ];
        swap.swapfile.size = cfg.swapSize;
      };
    };

  btrfsFilesystem = {
    type = "btrfs";
    extraArgs = [
      "-f"
      "--label"
      branding.id
    ];
    inherit subvolumes;
  };

  systemPartitionContent =
    if cfg.encrypt then
      {
        type = "luks";
        name = "cryptsystem";
        settings.allowDiscards = true;
        content = btrfsFilesystem;
      }
    else
      btrfsFilesystem;
in
{
  options.${branding.id}.storage = {
    enable = lib.mkEnableOption "das Speicherlayout (GPT, ESP, btrfs)";

    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANS0T123456";
      description = ''
        Ganze Festplatte, die bei der Installation überschrieben wird.
        Ein Pfad unter /dev/disk/by-id ist stabiler als /dev/nvme0n1.
      '';
    };

    encrypt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Systempartition mit LUKS2 verschlüsseln.";
    };

    swapSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "8G";
      example = "16G";
      description = "Grösse des Swapfiles in @swap, null für keinen Swap.";
    };

    homeSnapshots = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Stündliche Snapper-Snapshots von /home mit automatischer Bereinigung.";
    };

    hibernation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Ruhezustand (Suspend-to-Disk) in das Swapfile erlauben.
        swapSize muss dafür mindestens so gross wie das RAM sein.

        Ein resume_offset ist nicht nötig: systemd schreibt beim Ruhezustand
        die Lage des Swapfiles in eine EFI-Variable (HibernateLocation), und
        die initrd liest sie beim nächsten Start. NixOS verwendet immer die
        systemd-initrd, dafür ist also nichts weiter einzustellen. Das funktioniert
        auch mit LUKS, weil die initrd zuerst entschlüsselt und dann aufwacht.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hibernation -> cfg.swapSize != null;
        message = "${branding.id}.storage.hibernation braucht ein Swapfile: swapSize darf nicht null sein.";
      }
      {
        # Mit diesem Schutz verweigert der Kernel den Ruhezustand.
        assertion = cfg.hibernation -> !config.security.protectKernelImage;
        message = "${branding.id}.storage.hibernation geht nicht zusammen mit security.protectKernelImage.";
      }
    ];

    disko.devices.disk.main = {
      type = "disk";
      inherit (cfg) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            # 1 GiB reicht für viele Kernel-Generationen in systemd-boot.
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          system = {
            size = "100%";
            content = systemPartitionContent;
          };
        };
      };
    };

    # journald soll schon in der frühen Bootphase auf die Platte schreiben.
    fileSystems."/var/log".neededForBoot = true;

    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/" ];
    };

    services.snapper.configs = lib.mkIf cfg.homeSnapshots {
      home = {
        SUBVOLUME = "/home";
        ALLOW_GROUPS = [ "users" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 6;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 3;
        TIMELINE_LIMIT_YEARLY = 0;
      };
    };
  };
}
