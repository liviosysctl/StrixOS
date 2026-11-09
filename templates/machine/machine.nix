# This machine. Written by the installer, editing it by hand is fine.
{
  networking.hostName = "@hostName@";

  time.timeZone = "@timeZone@";
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
  };
@vmwareLine@
  # Release the machine was installed with. Never change it, not even after updates.
  system.stateVersion = "@stateVersion@";
}
