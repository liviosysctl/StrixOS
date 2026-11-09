# Installer medium. Built on the minimal NixOS installer:
# console with autologin, NetworkManager (nmtui), drivers for every disk controller.
{ lib, pkgs, modulesPath, version, ... }:

let
  branding = import ../branding.nix;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../modules/os-release.nix
  ];

  # File name: strix-0.1.0-x86_64.iso. iso-image.nix sets baseName
  # without a priority, hence mkForce.
  image.baseName = lib.mkForce "${branding.id}-${version}-${pkgs.stdenv.hostPlatform.parsed.cpu.name}";

  isoImage = {
    # The initrd finds the medium at boot through this label (/dev/disk/by-label/...).
    # At most 32 characters, nixpkgs asserts that. The image must therefore be
    # written raw to the stick, FAT32 labels only allow 11 characters.
    volumeID = lib.toUpper "${branding.id}-${lib.replaceStrings [ "." ] [ "_" ] version}";

    # Boot menu: "Strix 0.1.0 Installer"
    appendToMenuLabel = " Installer";
  };

  # The installer works with flakes (nix eval, disko --flake, nixos-install --flake)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Swiss German keyboard on the console. The installer will ask for the
  # layout later, until then this is the right default.
  console.keyMap = "sg";

  # Show the distro version in the boot menu instead of the nixpkgs version
  system.nixos.label = version;

  environment.systemPackages = [
    (pkgs.callPackage ../installer/package.nix { inherit version; })
  ];

  # Hint on the console after autologin
  services.getty.helpLine = lib.mkAfter ''

    ${branding.name} ${version}: start the installation with  sudo ${branding.id}-install
  '';

  # Explicitly off: guest tools only belong in the test machine.
  virtualisation.vmware.guest.enable = false;
  virtualisation.virtualbox.guest.enable = false;
}
