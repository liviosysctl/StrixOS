# The search service (10-search in the plan): <id>-search on PATH and a user service that keeps
# the index in memory and answers on $XDG_RUNTIME_DIR/<id>/search.sock, one JSON object per line.
# Off until the desktop comes; the Quickshell UI talks to the socket.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.search;
  search = pkgs.callPackage ../packages/search { };
in
{
  options.${branding.id}.search = {
    enable = lib.mkEnableOption "the search for apps, actions, settings and commands";
    package = lib.mkOption {
      type = lib.types.package;
      default = search;
      readOnly = true;
      description = "The search service with the system menu and the command files.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services."${branding.id}-search" = {
      description = "Search for apps, actions, settings and commands";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # where NixOS puts desktop entries: the user's profiles first, then the system
      environment.XDG_DATA_DIRS = lib.concatStringsSep ":" [
        "%h/.nix-profile/share"
        "/etc/profiles/per-user/%u/share"
        "/nix/var/nix/profiles/default/share"
        "/run/current-system/sw/share"
      ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
