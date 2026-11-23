# The tools around /etc/nixos: rebuild, update (with the theme repositories), apps, generations,
# and doctor, which looks the system over.
# The names come from branding.nix (e.g. strix-rebuild).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;

  env = {
    DEFAULT_CONFIG_DIR = "/etc/nixos";
    CONFIG_ATTR = branding.id;
    LOCK_FILE = "/run/${branding.id}/rebuild.lock";
  };

  tool =
    {
      name,
      runtimeInputs,
      extraEnv ? { },
      excludeShellChecks ? [ ],
    }:
    pkgs.writeShellApplication {
      inherit excludeShellChecks;
      name = "${branding.id}-${name}";
      runtimeInputs = runtimeInputs ++ [
        pkgs.coreutils
        pkgs.util-linux
      ];
      runtimeEnv = env // extraEnv;
      text = builtins.readFile ./tools/common.sh + builtins.readFile ./tools/${name}.sh;
    };

  rebuild = tool {
    name = "rebuild";
    runtimeInputs = [
      config.system.build.nixos-rebuild
      config.nix.package
      # The build as a tree, and what changes package by package
      pkgs.nix-output-monitor
      pkgs.dix
    ];
  };

  update = tool {
    name = "update";
    runtimeInputs = [
      config.nix.package
      pkgs.diffutils
      pkgs.jq
      pkgs.systemd
      pkgs.gitMinimal
    ];
    extraEnv = {
      REBUILD = lib.getExe rebuild;
    }
    # The shell of the desktop is restarted and asked whether it works; if not, the update goes back
    // lib.optionalAttrs config.${branding.id}.desktop.enable {
      SHELL_UNIT = "${branding.id}-shell.service";
      SHELL_QS = lib.getExe' pkgs.quickshell "qs";
      SHELL_CONFIG = branding.id;
    }
    // lib.optionalAttrs config.services.fwupd.enable {
      FWUPDMGR = "${pkgs.fwupd}/bin/fwupdmgr";
    }
    # The theme repositories are fetched by the theme engine
    // lib.optionalAttrs config.${branding.id}.theme.enable {
      THEME_COMMAND = lib.getExe config.${branding.id}.theme.package;
    };
  };

  generations = tool {
    name = "generations";
    runtimeInputs = [
      config.nix.package
      config.system.build.nixos-rebuild
      pkgs.dix
    ];
    # It has nothing to do with /etc/nixos: config_dir of the shared start stays unused
    excludeShellChecks = [ "SC2034" ];
  };

  doctor = tool {
    name = "doctor";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
      pkgs.gitMinimal
      pkgs.curl
      pkgs.gawk
      pkgs.gnused
      pkgs.gnutar
      pkgs.gzip
    ];
    extraEnv.ID = branding.id;
  };

  apps = tool {
    name = "apps";
    runtimeInputs = [
      config.nix.package
      pkgs.jq
    ];
    extraEnv.REBUILD = lib.getExe rebuild;
  };
in
{
  environment.systemPackages = [
    rebuild
    update
    apps
    generations
    doctor
  ];

  # Reachable for tests: nix build .#nixosConfigurations.<name>.config.system.build.distroTools.apps
  system.build.distroTools = {
    inherit
      rebuild
      update
      apps
      generations
      doctor
      ;
  };
}
