# Installer medium. Built on the minimal NixOS installer:
# console with autologin, NetworkManager (nmtui), drivers for every disk controller.
{ config, lib, pkgs, modulesPath, distroFlake, version, ... }:

let
  branding = import ../branding.nix;
  system = pkgs.stdenv.hostPlatform.system;
  reference = distroFlake.nixosConfigurations."${branding.id}-reference";
in
{
  imports = [
    ./options.nix
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../modules/os-release.nix
    # Downloads the distro's own packages during the install instead of compiling them
    ../modules/cache.nix
    # No emoji from systemd tools, same as on installed machines
    ../modules/systemd-tools.nix
    # The console in the colors of the default theme. No splash on the ISO,
    # so nothing is written to the EFI variables of the machine.
    ../modules/theme.nix
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

    # Put the installed system and the flake sources into the store up front.
    # nixos-install copies whatever already exists in the live store instead of
    # downloading it, so a real installation only builds a few small parts.
    storeContents = [
      reference.config.system.build.toplevel
      # sgdisk, cryptsetup, mkfs.btrfs and friends for formatting
      reference.config.system.build.diskoScript
      distroFlake.outPath
    ]
    ++ map (input: input.outPath) (lib.attrValues distroFlake.inputs);
  };

  # The live system keeps everything Nix downloads in a RAM disk. By default it
  # gets half the RAM, which ran out during a 4 GB test install. The file
  # system comes from installation-cd-base.nix with mkImageMediaOverride on
  # all of fileSystems, so it is resized at boot instead of redefined.
  systemd.services."${branding.id}-grow-store" = {
    description = "Give the live Nix store 85 % of the memory";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.util-linux ];
    script = "mount -o remount,size=85% /nix/.rw-store";
    serviceConfig.Type = "oneshot";
  };

  # The installer works with flakes (nix eval, disko --flake, nixos-install --flake)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Same as on installed machines: SSH in from any common terminal works.
  environment.enableAllTerminfo = true;

  # Swiss German keyboard on the console. The installer will ask for the
  # layout later, until then this is the right default.
  console.keyMap = "sg";

  # The installer speaks German, French and Italian. Lat2-Terminus16, the
  # default, has no ê, û, ì, ò or ù, Terminus in the same size has them all
  # plus the block characters of the logo.
  console.packages = [ pkgs.terminus_font ];
  console.font = "ter-v16n";

  # Show the distro version in the boot menu instead of the nixpkgs version
  system.nixos.label = version;

  environment.systemPackages = [
    distroFlake.packages.${system}.${if config.${branding.id}.iso.dev then "installer-dev" else "installer"}
    distroFlake.inputs.disko.packages.${system}.disko
  ];

  # Hint on the console after autologin
  services.getty.helpLine = lib.mkAfter ''

    ${branding.name} ${version}: start the installation with  sudo ${branding.id}-install
    SSH is running. Set a password with  passwd , find the address with  ip -4 addr ,
    then connect with  ssh nixos@<address>
  '';

  # Explicitly off: no guest tools on the installer.
  virtualisation.vmware.guest.enable = false;
  virtualisation.virtualbox.guest.enable = false;
}
