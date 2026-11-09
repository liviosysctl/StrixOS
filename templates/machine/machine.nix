# Diese Maschine. Vom Installer geschrieben, Änderungen von Hand sind erlaubt.
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
  # Release, mit dem installiert wurde. Nie ändern, auch nicht nach Updates.
  system.stateVersion = "@stateVersion@";
}
