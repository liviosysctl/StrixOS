# What every installed machine gets, whatever was answered in the installer.
{ config, lib, distroFlake, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id};
in
{
  options.${branding.id}.user = {
    name = lib.mkOption {
      type = lib.types.strMatching "^[a-z_][a-z0-9_-]{0,31}$";
      example = "livio";
      description = "Login name of the main user.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Livio";
      description = "Display name, shown at login.";
    };
  };

  config = {
    # Boot loader
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 10; # a 1 GiB ESP easily holds that many
    boot.loader.efi.canTouchEfiVariables = true;

    # Nix. nixosSystem already sets the registry entry for nixpkgs.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.settings.auto-optimise-store = true;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Keep the sources of the distro and its inputs in the store, so /etc/nixos
    # can be rebuilt without a network.
    system.extraDependencies = [ distroFlake.outPath ]
      ++ map (input: input.outPath) (lib.attrValues distroFlake.inputs);

    networking.networkmanager.enable = true;

    # SSH is on, so the machine can be reached from another computer right
    # after the install. Logging in needs the user's password, root cannot log
    # in. NixOS opens port 22 in the firewall for it.
    # Turn it off in machine.nix with:  services.openssh.enable = false;
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PermitRootLogin = lib.mkDefault "no";
        PasswordAuthentication = lib.mkDefault true;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };

    # Know every common terminal (Ghostty, kitty, Alacritty, WezTerm, foot, ...).
    # Over SSH the client's TERM comes along; without its terminfo, clear,
    # nano and less fail with "unknown terminal type".
    environment.enableAllTerminfo = true;

    # No emoji in the output of systemd tools (hostnamectl shows one for the
    # chassis, systemctl and others use them too). sudo would drop the
    # variable, so it is kept explicitly.
    environment.variables.SYSTEMD_EMOJI = "0";
    security.sudo.extraConfig = ''
      Defaults env_keep += "SYSTEMD_EMOJI"
    '';

    # The password is not in the config (it would end up readable in the store).
    # The installer sets it once with chpasswd, after that it lives in /etc/shadow.
    users.mutableUsers = lib.mkDefault true;
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      inherit (cfg.user) description;
      extraGroups = [ "wheel" "networkmanager" ];
    };
    security.sudo.wheelNeedsPassword = true;
  };
}
