# Secure Boot in VMs: OVMF with Secure Boot on, Microsoft's keys in the
# firmware (only the 2011 CAs, like an older PC) and the SbatLevel of
# November 2026, the newest revocations shim knows of.
#
#   nix build .#tests.secure-boot-iso -L   the signed ISO boots from a stick
#   nix build .#tests.secure-boot -L       an installed machine boots, keeps
#                                          booting after a new boot loader
#                                          install, and refuses an unsigned
#                                          boot loader
#
# The test key is made in the Nix store, so it is only good for tests. The
# keys are already in shim's MOK list here; enrolling with MokManager is a
# step at the keyboard, tested by hand on a real laptop.
#
# Not part of nix flake check: the firmware with Secure Boot needs SMM, and
# without KVM every boot takes minutes.
{ self, pkgs }:

let
  inherit (pkgs) lib;
  branding = import ../branding.nix;
  id = branding.id;
  system = pkgs.stdenv.hostPlatform.system;
  qemu-common = import "${pkgs.path}/nixos/lib/qemu-common.nix" { inherit lib; inherit (pkgs) stdenv; };

  # shim's owner GUID for MOK list entries
  shimLock = "605dab50-e046-4300-abb6-3dd810dd8b23";

  testKey = pkgs.runCommand "${id}-secure-boot-test-key" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
      -subj "/CN=${branding.name} Secure Boot test key" \
      -keyout $out/key.pem -out $out/cert.pem
  '';

  # Built with Secure Boot and SMM, and on cache.nixos.org
  ovmf = pkgs.OVMFFull;

  # The revocation list shim 16.1 does not even carry yet: GRUB has to be
  # generation 7 to pass it
  sbatLevel = pkgs.writeText "sbat-level" ''
    sbat,1,2026102600
    shim,4
    grub,7
    fwupd-efi,2
  '';

  # Firmware variables: Secure Boot on, Microsoft's KEK of 2011 and in db
  # only the third-party CA of 2011, the one older PCs have (shim is signed
  # with it); the given certificates in the MOK list
  microsoft = "77fa9abd-0359-4d32-bd60-28f4e78f784b";
  msCerts = "${pkgs.python3Packages.virt-firmware}/${pkgs.python3.sitePackages}/virt/firmware/certs/microsoft.com";
  variables =
    name: certs:
    pkgs.runCommand "${id}-ovmf-vars-${name}" { nativeBuildInputs = [ pkgs.python3Packages.virt-firmware ]; } ''
      virt-fw-vars --input ${ovmf.variables} --output $out \
        --enroll-redhat --microsoft-db none --microsoft-kek 2011 --secure-boot \
        --add-db ${microsoft} ${msCerts}/ms-uefi-2011.pem \
        --set-sbat-level ${sbatLevel} \
        ${lib.concatMapStringsSep " " (cert: "--add-mok ${shimLock} ${cert}") certs}
    '';

  # The real ISO configuration, small: nothing preloaded in its store, fast
  # compression, the test driver's backdoor
  iso =
    (self.nixosConfigurations."${id}-iso".extendModules {
      modules = [
        (
          { config, modulesPath, ... }:
          {
            imports = [ "${modulesPath}/testing/test-instrumentation.nix" ];
            isoImage.storeContents = lib.mkForce [ config.system.build.toplevel ];
            isoImage.squashfsCompression = "zstd -Xcompression-level 1";
          }
        )
      ];
    }).config.system.build.isoImage;

  signedIso =
    pkgs.runCommand "${id}-signed-test.iso"
      {
        nativeBuildInputs = [ self.packages.${system}.sign-iso pkgs.xorriso pkgs.mtools ];
      }
      ''
        export SECURE_BOOT_KEY=${testKey}/key.pem SECURE_BOOT_CERT=${testKey}/cert.pem
        sign-iso ${iso}/iso/*.iso $out

        # The layout the bootstick writes and the firmware reads
        xorriso -osirrox on -indev $out -extract /boot/efi.img efi.img
        mdir -i efi.img ::/EFI/BOOT | tee listing
        for f in BOOTX64 grubx64 mmx64; do grep -qi "^$f *efi" listing; done
        mdir -i efi.img ::/ | grep -qi "^${id} *cer"
      '';

  qemuFlags =
    vars:
    lib.concatStringsSep " " [
      (qemu-common.qemuBinary pkgs.qemu_test)
      "-m 2048"
      "-machine q35,smm=on"
      "-global driver=cfi.pflash01,property=secure,value=on"
      "-drive if=pflash,format=raw,unit=0,readonly=on,file=${ovmf.firmware}"
      "-drive if=pflash,format=raw,unit=1,file=${vars}"
    ];
in
{
  secure-boot-iso = pkgs.testers.runNixOSTest {
    name = "${id}-secure-boot-iso";
    nodes = { };
    testScript = ''
      import os
      import shutil

      # A writable copy: shim writes MokListRT and SbatLevel
      vars = os.path.abspath("vars.fd")
      shutil.copy("${variables "iso" [ "${testKey}/cert.pem" ]}", vars)
      os.chmod(vars, 0o644)

      stick = create_machine(
          "${qemuFlags "VARS"}".replace("VARS", vars)
          + " -device qemu-xhci -drive id=stick,file=${signedIso},if=none,format=raw,readonly=on"
          + " -device usb-storage,drive=stick",
          name="stick",
      )
      stick.start()
      stick.wait_for_unit("multi-user.target")

      with subtest("the stick booted with Secure Boot on, through shim"):
          stick.succeed("mokutil --sb-state | grep -x 'SecureBoot enabled'")
          # shim leaves its MOK list for the kernel, with the test key in it
          stick.succeed("mokutil --list-enrolled | grep -F '${branding.name} Secure Boot test key'")
          # The firmware's SbatLevel is the November 2026 one, GRUB passed it
          stick.succeed("mokutil --list-sbat-revocations | grep -x 'grub,7'")
      stick.shutdown()

      with subtest("without the key in the MOK list, shim refuses GRUB"):
          vars = os.path.abspath("vars-empty.fd")
          shutil.copy("${variables "iso-no-key" [ ]}", vars)
          os.chmod(vars, 0o644)
          refused = create_machine(
              "${qemuFlags "VARS"}".replace("VARS", vars)
              + " -device qemu-xhci -drive id=stick,file=${signedIso},if=none,format=raw,readonly=on"
              + " -device usb-storage,drive=stick",
              name="refused",
          )
          refused.start()
          refused.wait_for_console_text("BdsDxe: starting")
          # shim draws its refusal and MokManager without line ends, so check
          # the other way round: the kernel never starts. With the key it
          # prints its version a few seconds after the firmware.
          try:
              refused.wait_for_console_text("Linux version", timeout=180)
          except Exception:
              pass
          else:
              raise AssertionError("GRUB and the kernel started without the key in the MOK list")
          refused.crash()
    '';
  };

  secure-boot = pkgs.testers.runNixOSTest {
    name = "${id}-secure-boot";

    node.specialArgs.distroFlake = self;

    nodes.machine =
      { lib, ... }:
      {
        imports = [ ../modules/secure-boot.nix ];

        ${id}.secureBoot.testKey = testKey;

        virtualisation.useBootLoader = true;
        virtualisation.useEFIBoot = true;
        virtualisation.efi = {
          OVMF = ovmf;
          variables = variables "machine" [ "${testKey}/cert.pem" ];
          keepVariables = false;
        };
        boot.loader.systemd-boot.enable = true;
        boot.consoleLogLevel = lib.mkForce 7;

        # The unsigned systemd-boot for the last subtest
        virtualisation.additionalPaths = [ pkgs.systemd ];
      };

    testScript = ''
      machine.start(allow_reboot=True)
      machine.wait_for_unit("multi-user.target")

      with subtest("booted through shim with Secure Boot on"):
          machine.succeed("mokutil --sb-state | grep -x 'SecureBoot enabled'")
          machine.succeed("bootctl status | grep -E 'Secure Boot: enabled'")
          print(machine.succeed("${id}-secure-boot status"))
          machine.succeed("cmp /boot/EFI/BOOT/BOOTX64.EFI ${self.packages.${system}.shim}/share/shim/shimx64.efi")
          machine.fail("${id}-secure-boot status | grep '^unsigned'")
          machine.succeed("test -s /boot/${id}.cer")

      with subtest("a new boot loader install keeps everything signed"):
          machine.succeed("/run/current-system/bin/switch-to-configuration boot")
          machine.fail("${id}-secure-boot status | grep '^unsigned'")
          machine.reboot()
          machine.wait_for_unit("multi-user.target")
          machine.succeed("mokutil --sb-state | grep -x 'SecureBoot enabled'")

      with subtest("an unsigned systemd-boot does not start"):
          machine.succeed(
              "cp ${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi /boot/EFI/BOOT/grubx64.efi && sync"
          )
          machine.reboot()
          # shim refuses it and starts MokManager instead
          machine.wait_for_console_text("Security Violation|Verification failed|MOK management")
          machine.crash()
    '';
  };
}
