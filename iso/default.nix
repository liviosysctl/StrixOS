# Installationsmedium. Baut auf dem minimalen NixOS-Installer auf:
# Konsole mit Autologin, NetworkManager (nmtui), alle Treiber für Festplatten.
{ lib, pkgs, modulesPath, version, ... }:

let
  branding = import ../branding.nix;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../modules/os-release.nix
  ];

  # Dateiname: strix-0.1.0-x86_64.iso. iso-image.nix setzt baseName
  # ohne Priorität, darum mkForce.
  image.baseName = lib.mkForce "${branding.id}-${version}-${pkgs.stdenv.hostPlatform.parsed.cpu.name}";

  isoImage = {
    # Darüber findet die initrd das Medium beim Start (/dev/disk/by-label/...).
    # Höchstens 32 Zeichen, nixpkgs prüft das. Das Medium muss darum roh
    # auf den Stick geschrieben werden, FAT32-Labels hätten nur 11 Zeichen.
    volumeID = lib.toUpper "${branding.id}-${lib.replaceStrings [ "." ] [ "_" ] version}";

    # Bootmenü: "Strix 0.1.0 Installer"
    appendToMenuLabel = " Installer";
  };

  # Im Bootmenü die Distro-Version statt der nixpkgs-Version zeigen
  system.nixos.label = version;

  environment.systemPackages = [
    (pkgs.callPackage ../installer/package.nix { inherit version; })
  ];

  # Hinweis auf der Konsole nach dem Autologin
  services.getty.helpLine = lib.mkAfter ''

    ${branding.name} ${version}: start the installation with  sudo ${branding.id}-install
  '';

  # Explizit aus: Gast-Tools gehören nur in die Testmaschine.
  virtualisation.vmware.guest.enable = false;
  virtualisation.virtualbox.guest.enable = false;
}
