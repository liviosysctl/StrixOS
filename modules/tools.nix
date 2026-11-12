# The three tools around /etc/nixos: rebuild, update (with the theme repositories), apps.
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
    { name, runtimeInputs, extraEnv ? { } }:
    pkgs.writeShellApplication {
      name = "${branding.id}-${name}";
      runtimeInputs = runtimeInputs ++ [ pkgs.coreutils pkgs.util-linux ];
      runtimeEnv = env // extraEnv;
      text = builtins.readFile ./tools/common.sh + builtins.readFile ./tools/${name}.sh;
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
in
{
  environment.systemPackages = [ rebuild update apps ];

  # Reachable for tests: nix build .#nixosConfigurations.<name>.config.system.build.distroTools.apps
  system.build.distroTools = { inherit rebuild update apps; };
}
