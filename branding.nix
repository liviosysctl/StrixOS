# Die einzige Stelle, an der der Name der Distro steht.
# Alles andere leitet sich hiervon ab. Umbenennen heisst: nur diese Datei ändern.
rec {
  # Anzeigename für Menschen: Bootmenü, os-release, Oberfläche.
  name = "Strix";

  # Technischer Name: Pakete, Programme, Dienste, NixOS-Optionen, Ordner,
  # Dateisystem-Label. Nur Kleinbuchstaben, Ziffern und Bindestriche.
  id = "strix";

  # Präfix für D-Bus-Namen (umgekehrte Domain ist bei D-Bus Pflicht).
  dbus = "org.${id}";
}
