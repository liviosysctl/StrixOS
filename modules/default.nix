# All distro modules. They need the specialArgs from lib/mk-system.nix
# (distroFlake, version), so only use them through mkSystem.
# disko is added in flake.nix because it is a flake input.
#   core      what every machine has, also without a screen: Nix, the user, the tools
#   boot      the boot loader, the splash, Secure Boot
#   hardware  what the machine itself needs looked after
#   storage   the disk layout
#   desktop   the session of a user, the same for everyone: Hyprland, the shell, the theme
#   apps      the terminal's tools and the packages added on this machine
{
  imports = [
    ./core
    ./boot
    ./hardware
    ./storage
    ./desktop
    ./apps
  ];
}
