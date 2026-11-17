# The tools around /etc/nixos: rebuild, update (with the theme repositories), apps, and shell,
# which tries packages without installing them.
# The names come from branding.nix (e.g. strix-rebuild).
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;

  env = {
    DEFAULT_CONFIG_DIR = "/etc/nixos";
    CONFIG_ATTR = branding.id;
    LOCK_FILE = "/run/${branding.id}/rebuild.lock";
  };

  tool =
    { name, runtimeInputs, extraEnv ? { }, common ? true }:
    pkgs.writeShellApplication {
      name = "${branding.id}-${name}";
      runtimeInputs = runtimeInputs ++ [ pkgs.coreutils pkgs.util-linux ];
      runtimeEnv = env // extraEnv;
      text = lib.optionalString common (builtins.readFile ./tools/common.sh) + builtins.readFile ./tools/${name}.sh;
    };

  rebuild = tool {
    name = "rebuild";
    runtimeInputs = [ config.system.build.nixos-rebuild ];
  };

  update = tool {
    name = "update";
    runtimeInputs = [ config.nix.package pkgs.diffutils pkgs.jq ];
    extraEnv = {
      REBUILD = lib.getExe rebuild;
    }
    # The theme repositories are fetched by the theme engine
    // lib.optionalAttrs config.${branding.id}.theme.enable {
      THEME_COMMAND = lib.getExe config.${branding.id}.theme.package;
    };
  };

  apps = tool {
    name = "apps";
    runtimeInputs = [ config.nix.package pkgs.jq ];
    extraEnv.REBUILD = lib.getExe rebuild;
  };
  # nix-shell -p with flakes: the packages in a shell, from the nixpkgs the system is built from
  # (the registry entry nixosSystem sets), so they match what an install would bring
  # It does not touch /etc/nixos, so it needs nothing of common.sh
  shell = tool {
    name = "shell";
    runtimeInputs = [ config.nix.package ];
    common = false;
  };
in
{
  environment.systemPackages = [ rebuild update apps shell ];

  # Reachable for tests: nix build .#nixosConfigurations.<name>.config.system.build.distroTools.apps
  system.build.distroTools = { inherit rebuild update apps shell; };
}
