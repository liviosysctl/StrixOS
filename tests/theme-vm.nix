# The theme engine on a running system, in a VM with EFI, systemd-boot and
# Plymouth: switch the theme, reboot, check that the initrd picked the splash.
#
#   nix build .#tests.theme -L
#
# Not part of nix flake check: it boots a VM twice (minutes with KVM, much
# longer without).
{ pkgs }:

let
  branding = import ../branding.nix;
  id = branding.id;
  efiVariable = "/sys/firmware/efi/efivars/Theme-595702b9-5e56-4cc8-9b1a-d145cfd71953";
in
pkgs.testers.runNixOSTest {
  name = "${id}-theme";

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
        machine.succeed("${id}-theme current | grep -x neutral:dark")
        print(machine.succeed("${id}-theme status"))
        machine.succeed("grep -x 'Theme=${id}-neutral-dark' /etc/plymouth/plymouthd.conf")
        machine.succeed("grep '\"theme\": \"neutral\"' /run/${id}/theme/tokens.json")
        # Exactly once, although plymouth-start is pulled in twice in the initrd
        runs = machine.succeed("journalctl -b -o cat -u ${id}-theme-boot | grep -c 'no theme stored, default splash'")
        assert runs.strip() == "1", f"the initrd unit ran {runs.strip()} times"
        machine.succeed("od -An -c ${efiVariable} | tr -d ' \\n' | grep -F 'neutral:dark'")
        # neutral: the console background is black
        expect_background("neutral", "#000000")

    with subtest("list and show work without root"):
        machine.succeed("runuser -u alice -- ${id}-theme list | grep -E '^\\* neutral:dark'")
        machine.succeed("runuser -u alice -- ${id}-theme show chamber:dark | grep '\"background\": \"#2a2d32\"'")

    with subtest("only root may switch"):
        out = machine.fail("runuser -u alice -- ${id}-theme set chamber:dark 2>&1")
        assert "needs root" in out, out

    with subtest("a wrong theme changes nothing"):
        machine.fail("${id}-theme set nope")
        machine.fail("${id}-theme set chamber:dusk")
        machine.succeed("${id}-theme current | grep -x neutral:dark")

    with subtest("switch at runtime"):
        print(machine.succeed("${id}-theme set chamber:dark"))
        print(machine.succeed("${id}-theme status"))
        machine.succeed("${id}-theme current | grep -x chamber:dark")
        machine.succeed("grep -x 'Theme=${id}-chamber-dark' /etc/plymouth/plymouthd.conf")
        machine.succeed("grep '\"variant\": \"dark\"' /run/${id}/theme/tokens.json")
        machine.succeed("od -An -c ${efiVariable} | tr -d ' \\n' | grep -F 'chamber:dark'")
        # The whole screen, not just new text: chamber:dark's terminal background
        expect_background("chamber-dark", "#1f2226")

    with subtest("after a reboot the initrd shows the chosen splash"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("${id}-theme.service")
        runs = machine.succeed("journalctl -b -o cat -u ${id}-theme-boot | grep -c '^splash ${id}-chamber-dark for chamber:dark$'")
        assert runs.strip() == "1", f"the initrd unit ran {runs.strip()} times"
        print(machine.succeed("${id}-theme status"))
        machine.succeed("${id}-theme current | grep -x chamber:dark")
        expect_background("chamber-dark-after-reboot", "#1f2226")

    with subtest("a broken stored theme falls back to the default"):
        machine.succeed("echo nope > /var/lib/${id}/theme/selection")
        machine.succeed("systemctl restart ${id}-theme.service")
        machine.succeed("${id}-theme current | grep -x neutral:dark")
        machine.succeed("grep -x 'Theme=${id}-neutral-dark' /etc/plymouth/plymouthd.conf")
        expect_background("fallback", "#000000")
  '';
}
