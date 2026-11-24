# The themes the proof of concept comes with: Saturnus only, in its dark variant and, for whoever
# asks for it with `strix-theme set saturnus:light`, its light one. With a single theme the
# session never moves on to another god, and the lock screen keeps the desktop's look; the boot
# menu and the splash are built for it alone. main keeps all eight gods of StrixUI.
strixui:

let
  root = "${strixui}/design-system/themes";
  only = [ "saturnus" ];
  inside = path: id: path == "${root}/${id}" || builtins.substring 0 (builtins.stringLength "${root}/${id}/") path == "${root}/${id}/";
in
builtins.path {
  name = "strix-themes-builtin";
  path = root;
  filter = path: _type: builtins.any (inside path) only;
}
