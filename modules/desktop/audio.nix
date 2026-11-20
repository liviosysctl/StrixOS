# Sound: PipeWire, also for apps that speak ALSA or PulseAudio.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;
in
{
  config = lib.mkIf cfg.enable {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    security.rtkit.enable = true;
  };
}
