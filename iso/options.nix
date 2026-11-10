# Options of the installer medium
{ lib, ... }:

let
  branding = import ../branding.nix;
in
{
  options.${branding.id}.iso.dev = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Dev ISO: machines installed from it follow the development branch
      (upstream.devRef in flake.nix) instead of stable.
    '';
  };
}
