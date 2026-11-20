# Starting the machine: the boot loader, the splash, Secure Boot.
{
  imports = [
    ./loader.nix
    ./splash.nix
    ./secure-boot.nix
  ];
}
