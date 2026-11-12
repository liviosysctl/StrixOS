# The Store (main only, the school proof of concept): find an app in nixpkgs and install or remove
# it with one click. The window is shell/qml/Store.qml, the service <id>-store behind it; both
# install through <id>-apps, which writes apps.json and rebuilds.
#
# The package index comes from the channel's package list (packages.json.br, made by Hydra for
# every channel update): reading all of nixpkgs with nix-env needs more memory than an old laptop
# has. The index service fetches it after every switch that brings another nixpkgs and once a week.
#
# Q4: the active local session may run `<id>-apps add|remove <package>` without a password
# (polkit); everything else of pkexec still asks.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  cfg = config.${id}.store;
  store = pkgs.callPackage ../packages/store { };
  appsTool = lib.getExe config.system.build.distroTools.apps;
  cacheDir = "/var/cache/${id}/store";
  indexFile = "${cacheDir}/index.json";
in
{
  options.${id}.store = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.${id}.desktop.enable;
      defaultText = lib.literalExpression "config.${id}.desktop.enable";
      description = "The Store: apps from nixpkgs with one click.";
    };

    packageList = lib.mkOption {
      type = lib.types.str;
      default = "https://channels.nixos.org/nixos-unstable/packages.json.br";
      description = "Where the package list of the channel comes from (brotli JSON, as Hydra publishes it).";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = store;
      readOnly = true;
      description = "The Store service and command.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [ "d ${cacheDir} 0755 root root -" ];

    # The index: at boot, after a switch to another nixpkgs (the unit changes with it), weekly
    systemd.services."${id}-store-index" = {
      description = "Fetch the package list for the Store";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.curl pkgs.brotli cfg.package ];
      environment = {
        INDEX_FILE = indexFile;
        # Not read: it ties the unit to this nixpkgs, so a switch to another one runs it again
        NIXPKGS = builtins.unsafeDiscardStringContext "${pkgs.path}";
      };
      script = ''
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        curl --fail --silent --show-error --location --retry 3 --max-time 600 \
          -o "$tmp/packages.json.br" ${lib.escapeShellArg cfg.packageList}
        brotli --decompress --stdout "$tmp/packages.json.br" > "$tmp/packages.json"
        ${id}-store index read "$tmp/packages.json" ${lib.escapeShellArg cfg.packageList}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Nice = 19;
        IOSchedulingClass = "idle";
        # Never hold up the boot or a switch
        TimeoutStartSec = 900;
      };
    };
    systemd.timers."${id}-store-index" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        RandomizedDelaySec = "6h";
        Persistent = true;
      };
    };

    # The service behind the window
    systemd.user.services."${id}-store" = {
      description = "The Store: search nixpkgs, install and remove apps";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      environment = {
        INDEX_FILE = indexFile;
        APPS_FILE = "/etc/nixos/apps.json";
        APPS_COMMAND = appsTool;
        PKEXEC = "/run/wrappers/bin/pkexec";
        SOCKET = "%t/${id}/store.sock";
      };
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # Q4 A: installing and removing an app from the Store asks for the password once, then five
    # minutes free (the Store service is the subject, so the grant holds for its next calls).
    # Only `<id>-apps add|remove <package>` in the active local session, nothing else.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" &&
            action.lookup("program") == "${appsTool}" &&
            /^\S+ (add|remove) [A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*$/.test(action.lookup("command_line") || "") &&
            subject.local && subject.active) {
          return polkit.Result.AUTH_ADMIN_KEEP;
        }
      });
    '';
  };
}
