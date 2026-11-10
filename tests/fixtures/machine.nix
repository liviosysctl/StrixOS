# This machine. Written by the installer, editing it by hand is fine.
{
  networking.hostName = "@distroId@-test";

  time.timeZone = "Europe/Zurich";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "sg";
  services.xserver.xkb = {
    layout = "ch";
    variant = "";
  };

  @distroId@.user = {
    name = "test";
    description = "Test User";
  };

  @distroId@.storage = {
    enable = true;
    device = "/dev/vda";
    encrypt = true;
    swapSize = "6G";
    hibernation = true;
  };

  # Release the machine was installed with. Never change it, not even after updates.
  system.stateVersion = "@stateVersion@";
}
