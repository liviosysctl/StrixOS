# Disk layout
#
# GPT with an ESP and one system partition (optional LUKS), holding btrfs with
# flat subvolumes. Needs disko: the flake imports disko.nixosModules.disko
# together with this module.
#
# No snapshots of "/": the system itself can be rolled back through NixOS
# generations, and /nix never belongs in a snapshot. Only /home is backed up,
# where the data lives that Nix cannot rebuild.
{ config, lib, ... }:

let
  # Imported directly instead of as a module argument: the option names depend
  # on the name, and module arguments are only known after the options.
  branding = import ../../branding.nix;
  cfg = config.${branding.id}.storage;

  # zstd:1 is practically free on NVMe and saves a lot of space in /nix.
  # noatime avoids a write on every read (important with snapshots).
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
      # Own subvolumes, so logs and caches are not pulled into home snapshots
      # or into a later reset of "/".
      "@log" = mkSubvolume "/var/log";
      "@cache" = mkSubvolume "/var/cache";
    }
    // lib.optionalAttrs cfg.homeSnapshots {
      # Separate from @home, so restoring @home does not delete the snapshots.
      "@home-snapshots" = mkSubvolume "/home/.snapshots";
    }
    // lib.optionalAttrs (cfg.swapSize != null) {
      # No compression: swap files on btrfs must be NOCOW and uncompressed.
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
    enable = lib.mkEnableOption "the disk layout (GPT, ESP, btrfs)";

    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANS0T123456";
      description = ''
        Whole disk that is overwritten during installation.
        A path under /dev/disk/by-id is more stable than /dev/nvme0n1.
      '';
    };

    encrypt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Encrypt the system partition with LUKS2.";
    };

    swapSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "8G";
      example = "16G";
      description = "Size of the swap file in @swap, null for no swap.";
    };

    homeSnapshots = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hourly Snapper snapshots of /home with automatic cleanup.";
    };

    hibernation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow hibernation (suspend to disk) into the swap file.
        swapSize must be at least as large as the RAM for that.

        No resume_offset is needed: when hibernating, systemd writes the
        location of the swap file into an EFI variable (HibernateLocation), and
        the initrd reads it on the next boot. NixOS always uses the systemd
        initrd, so nothing else needs to be set. This also works with LUKS,
        because the initrd unlocks first and resumes after.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hibernation -> cfg.swapSize != null;
        message = "${branding.id}.storage.hibernation needs a swap file: swapSize must not be null.";
      }
      {
        # With this protection the kernel refuses to hibernate.
        assertion = cfg.hibernation -> !config.security.protectKernelImage;
        message = "${branding.id}.storage.hibernation does not work together with security.protectKernelImage.";
      }
    ];

    disko.devices.disk.main = {
      type = "disk";
      inherit (cfg) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            # 1 GiB holds many kernel generations for systemd-boot.
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

    # journald should write to disk from early boot on.
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
