# Hyprland as a systemd session through UWSM. It reads the configuration of the distribution from
# /etc/xdg/<id>/hypr (HYPRLAND_CONFIG): shell/hypr/hyprland.lua, machine.lua from this module,
# bindings.lua made by <id>-search from shell/menu.toml, and theme.lua, which reads the colors of
# the session's theme.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;

  xkb = config.services.xserver.xkb;

  runtimeDir = "/run/${id}/theme";

  luaString = s: builtins.toJSON s;

  cyclePeriod = cfg.themeCycle;

  # theme.lua: the session's colors, else the machine's (before the session service started)
  themeLua = pkgs.writeText "theme.lua" ''
    -- The colors of the current theme (modules/desktop/hyprland.nix): the session's theme, which
    -- changes every ${cyclePeriod} (${id}-theme session), else the machine's.
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    local files = { "${runtimeDir}/hyprland.lua" }
    if runtime then
        table.insert(files, 1, runtime .. "/${id}/theme/hyprland.lua")
    end
    for _, file in ipairs(files) do
        local handle = io.open(file, "r")
        if handle then
            handle:close()
            dofile(file)
            return
        end
    end
  '';

  machineLua = pkgs.writeText "machine.lua" (
    ''
      -- This machine, from machine.nix (modules/desktop/hyprland.nix).
      hl.config({
          input = {
              kb_layout = ${luaString xkb.layout},
              kb_variant = ${luaString xkb.variant},
              kb_options = ${luaString xkb.options},
          },
      })
    ''
    + lib.optionalString (cfg.extraConfig != "") ''

      -- strix.desktop.extraConfig
      ${cfg.extraConfig}
    ''
  );

  search = config.${id}.search.package;

  # Everything Hyprland reads, in one folder: `require` looks next to hyprland.lua
  hyprConfig = pkgs.runCommand "${id}-hyprland-config" { } ''
    mkdir $out
    cp ${../../shell/hypr/hyprland.lua} $out/hyprland.lua
    cp ${machineLua} $out/machine.lua
    MENU_FILE=${search}/share/${id}-search/menu.toml SEARCH_ID=${id} \
      ${lib.getExe search} bindings > $out/bindings.lua
    cp ${themeLua} $out/theme.lua
  '';
in
{
  options.${id}.desktop = {
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        hl.config({ general = { gaps_out = 4 } })
        hl.bind("SUPER + B", hl.dsp.exec_cmd("uwsm app -- zen-beta"))
      '';
      description = ''
        Own Hyprland settings in Lua, read after the ones of ${branding.name}. Each user can also
        keep their own in ~/.config/${id}/hyprland.lua.
      '';
    };

    hyprlandConfig = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = hyprConfig;
      description = "The folder Hyprland reads, for tests.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    environment.etc."xdg/${id}/hypr".source = hyprConfig;

    environment.sessionVariables = {
      HYPRLAND_CONFIG = "/etc/xdg/${id}/hypr/hyprland.lua";
      NIXOS_OZONE_WL = "1";
    };

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
