# This machine. Written by the installer, editing it by hand is fine.
{
  networking.hostName = "@distroId@-test";

  # The time zone is the machine's own, kept in /etc/localtime: Settings › Date and time changes
  # it without a rebuild. The installer set it.
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
    # false: only the two partitions with the labels below, next to the other systems on the disk
    wholeDisk = true;
    encrypt = true;
    swapSize = "6G";
    hibernation = true;
    # Ends the partition labels, so a second disk of the same system never has the same ones
    labelSuffix = "test";
  };

  # Release the machine was installed with. Never change it, not even after updates.
  system.stateVersion = "@stateVersion@";
}
