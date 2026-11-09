# The only place where the distro name is written down.
# Everything else derives from it. Renaming means changing this file only.
rec {
  # Display name for people: boot menu, os-release, user interface.
  name = "Strix";

  # Technical name: packages, programs, services, NixOS options, folders,
  # file system label. Lowercase letters, digits and hyphens only.
  id = "strix";

  # Prefix for D-Bus names (D-Bus requires a reversed domain).
  dbus = "org.${id}";
}
