# Name and version of the distro in /etc/os-release.
# Used by the installer ISO and by every installed system.
# Needs `version` as a specialArg (from flake.nix).
{ version, ... }:

let
  branding = import ../branding.nix;
in
{
  # NAME= and PRETTY_NAME=
  system.nixos.distroName = branding.name;

  # ID=. If the ID is not "nixos", nixpkgs adds ID_LIKE=nixos by itself
  # and leaves out the nixos.org links.
  system.nixos.distroId = branding.id;

  # IMAGE_VERSION=, the Store and the settings read the distro version from it.
  # VERSION_ID stays the NixOS version.
  system.image.version = version;

  # Otherwise PRETTY_NAME shows the NixOS version ("Strix 26.11 (Zokor)"),
  # which appears at login, in fastfetch and in the settings.
  system.nixos.extraOSReleaseArgs = {
    PRETTY_NAME = "${branding.name} ${version}";
    HOME_URL = "https://github.com/liviosysctl/strixos";
  };
}
