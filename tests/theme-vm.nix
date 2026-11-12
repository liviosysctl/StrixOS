# The theme engine on a running system, in a VM with EFI, systemd-boot and
# Plymouth: switch the theme, reboot, check that the initrd picked the splash.
# Then a theme repository from a local Git repository: connect, refuse, remove.
#
#   nix build .#tests.theme -L
#
# Not part of nix flake check: it boots a VM twice (minutes with KVM, much
# longer without).
{ self, pkgs }:

let
  branding = import ../branding.nix;
  id = branding.id;
  efiVariable = "/sys/firmware/efi/efivars/Theme-595702b9-5e56-4cc8-9b1a-d145cfd71953";
  lucifer = ./fixtures/repos/themes/lucifer;
  git = "${pkgs.gitMinimal}/bin/git";
in
pkgs.testers.runNixOSTest {
  name = "${id}-theme";

  node.specialArgs.distroFlake = self;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/boot-splash.nix
        ../modules/theme.nix
      ];

      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # The test driver reads kernel messages from the serial console
      boot.consoleLogLevel = lib.mkForce 7;

      users.users.alice.isNormalUser = true;

      # The theme repository of the last subtest is made from these
      virtualisation.additionalPaths = [ lucifer pkgs.gitMinimal ];
    };

  # Pillow reads the screenshots to check the colors on screen
  extraPythonPackages = p: [ p.pillow ];

  testScript = ''
    from PIL import Image

    def screen_background(name):
        """The most common color in the rightmost pixel column of the screen.
        Text rarely reaches the last column, so this is the background."""
        machine.screenshot(name)
        image = Image.open(machine.out_dir / f"{name}.png").convert("RGB")
        width, height = image.size
        column = [image.getpixel((width - 2, y)) for y in range(height)]
        return "#%02x%02x%02x" % max(set(column), key=column.count)

    def expect_background(name, expected):
        found = screen_background(name)
        assert found == expected, f"{name}: the console background is {found}, expected {expected}"

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("first boot: the default theme everywhere"):
        machine.wait_for_unit("${id}-theme.service")
        machine.succeed("${id}-theme current | grep -x saturnus:dark")
        print(machine.succeed("${id}-theme status"))
        machine.succeed("grep -x 'Theme=${id}-saturnus-dark' /etc/plymouth/plymouthd.conf")
        machine.succeed("grep '\"theme\": \"saturnus\"' /run/${id}/theme/tokens.json")
        # Exactly once, although plymouth-start is pulled in twice in the initrd
        runs = machine.succeed("journalctl -b -o cat -u ${id}-theme-boot | grep -c 'no theme stored, default splash'")
        assert runs.strip() == "1", f"the initrd unit ran {runs.strip()} times"
        machine.succeed("od -An -c ${efiVariable} | tr -d ' \\n' | grep -F 'saturnus:dark'")
        # saturnus: the console background is its terminal background
        expect_background("saturnus", "#0b0a09")

    with subtest("list and show work without root"):
        machine.succeed("runuser -u alice -- ${id}-theme list | grep -E '^\\* saturnus:dark'")
        machine.succeed("runuser -u alice -- ${id}-theme show janus | grep '\"background\": \"#070c09\"'")

    with subtest("only root may switch"):
        out = machine.fail("runuser -u alice -- ${id}-theme set janus:dark 2>&1")
        assert "needs root" in out, out

    with subtest("a wrong theme changes nothing"):
        machine.fail("${id}-theme set nope")
        machine.fail("${id}-theme set janus:dusk")
        machine.succeed("${id}-theme current | grep -x saturnus:dark")

    with subtest("switch at runtime"):
        print(machine.succeed("${id}-theme set janus:dark"))
        print(machine.succeed("${id}-theme status"))
        machine.succeed("${id}-theme current | grep -x janus:dark")
        machine.succeed("grep -x 'Theme=${id}-janus-dark' /etc/plymouth/plymouthd.conf")
        machine.succeed("grep '\"variant\": \"dark\"' /run/${id}/theme/tokens.json")
        machine.succeed("od -An -c ${efiVariable} | tr -d ' \\n' | grep -F 'janus:dark'")
        # The whole screen, not just new text: janus's terminal background
        expect_background("janus", "#070c09")

    with subtest("after a reboot the initrd shows the chosen splash"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("${id}-theme.service")
        runs = machine.succeed("journalctl -b -o cat -u ${id}-theme-boot | grep -c '^splash ${id}-janus-dark for janus:dark$'")
        assert runs.strip() == "1", f"the initrd unit ran {runs.strip()} times"
        print(machine.succeed("${id}-theme status"))
        machine.succeed("${id}-theme current | grep -x janus:dark")
        expect_background("janus-after-reboot", "#070c09")

    with subtest("a broken stored theme falls back to the default"):
        machine.succeed("echo nope > /var/lib/${id}/theme/selection")
        machine.succeed("systemctl restart ${id}-theme.service")
        machine.succeed("${id}-theme current | grep -x saturnus:dark")
        machine.succeed("grep -x 'Theme=${id}-saturnus-dark' /etc/plymouth/plymouthd.conf")
        expect_background("fallback", "#0b0a09")

    with subtest("theme repositories"):
        # A theme repository in a local Git repository; on real machines only https://
        machine.succeed(
            "mkdir -p /root/odd/themes && cp -r ${lucifer} /root/odd/themes/lucifer && chmod -R u+w /root/odd",
            "printf 'layout = 1\\nname = \"Odd\"\\ndescription = \"For the test\"\\n' > /root/odd/strix-themes.toml",
            "cd /root/odd && ${git} init -q -b main && ${git} add -A"
            " && ${git} -c user.name=t -c user.email=t@t commit -q -m first",
        )
        out = machine.fail("${id}-theme repos add /root/odd 2>&1")
        assert "only https://" in out, out
        machine.succeed("mkdir -p /etc/nixos")
        out = machine.fail("runuser -u alice -- env THEME_REPOS_ALLOW_LOCAL=1 ${id}-theme repos add /root/odd 2>&1")
        assert "run it with sudo" in out or "cannot" in out, out
        print(machine.succeed("THEME_REPOS_ALLOW_LOCAL=1 ${id}-theme repos add /root/odd"))
        machine.succeed("test -s /etc/nixos/themes/lucifer/wallpaper.jpg")
        machine.succeed("grep -q '\"lucifer\"' /etc/nixos/themes.json")
        print(machine.succeed("runuser -u alice -- ${id}-theme repos list"))
        # A new commit that takes a built-in id is not taken; lucifer stays
        machine.succeed(
            "cd /root/odd && cp -r themes/lucifer themes/saturnus && ${git} add -A"
            " && ${git} -c user.name=t -c user.email=t@t commit -q -m god"
        )
        out = machine.fail("THEME_REPOS_ALLOW_LOCAL=1 ${id}-theme repos update 2>&1")
        assert "saturnus is a built-in theme" in out, out
        machine.succeed("grep -q problem /etc/nixos/themes.json")
        machine.succeed("test -d /etc/nixos/themes/lucifer && ! test -e /etc/nixos/themes/saturnus")
        print(machine.succeed("THEME_REPOS_ALLOW_LOCAL=1 ${id}-theme repos remove Odd"))
        machine.succeed("! test -e /etc/nixos/themes/lucifer")
  '';
}
