# This machine. Written by the installer, editing it by hand is fine.
{
  networking.hostName = "@hostName@";

  # The time zone is the machine's own, kept in /etc/localtime: Settings › Date and time changes
  # it without a rebuild. The installer set it.
  i18n.defaultLocale = "@locale@";
  console.keyMap = "@consoleKeyMap@";
  services.xserver.xkb = {
    layout = "@xkbLayout@";
    variant = "@xkbVariant@";
  };

  @distroId@.user = {
    name = "@userName@";
    description = "@fullName@";
  };

  @distroId@.storage = {
    enable = true;
    device = "@disk@";
    encrypt = @encrypt@;
    swapSize = "@swapSize@";
    hibernation = @hibernation@;
    # Ends the partition labels, so a second disk of the same system never has the same ones
    labelSuffix = "@labelSuffix@";
  };

  # Release the machine was installed with. Never change it, not even after updates.
  system.stateVersion = "@stateVersion@";
}
