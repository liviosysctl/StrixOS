# Name und Version der Distro in /etc/os-release.
# Wird vom Installations-ISO und von jedem installierten System verwendet.
# Braucht `version` als specialArg (aus flake.nix).
{ version, ... }:

let
  branding = import ../branding.nix;
in
{
  # NAME= und PRETTY_NAME=
  system.nixos.distroName = branding.name;

  # ID=. Ist die ID nicht "nixos", setzt nixpkgs automatisch ID_LIKE=nixos
  # und lässt die nixos.org-Links weg.
  system.nixos.distroId = branding.id;

  # IMAGE_VERSION=, darüber lesen Store und Einstellungen die Distro-Version.
  # VERSION_ID bleibt die NixOS-Version.
  system.image.version = version;

  # Sonst zeigt PRETTY_NAME die NixOS-Version ("Strix 26.11 (Zokor)"),
  # und das sieht man im Login, in fastfetch und in den Einstellungen.
  system.nixos.extraOSReleaseArgs = {
    PRETTY_NAME = "${branding.name} ${version}";
    HOME_URL = "https://github.com/liviosysctl/strixos";
  };
}
