# Secure Boot

The installer ISO boots with Secure Boot on: shim, signed by Microsoft, starts
GRUB and the kernel when they are signed with the distribution's key. Its
certificate lives here as `<id>.crt`. The private key is the repository secret
`SECURE_BOOT_KEY` and nowhere else in the repository.

On a machine, the first start of the stick shows MokManager once: "Enroll key
from disk", the stick, `<id>.cer`, "Continue", "Yes", "Reboot". After that the
stick boots normally.

Installed machines boot the same chain with the same key, so the one
enrollment from the stick is all a machine ever asks for: GRUB is one image
that is the same on every machine (`packages/grub-image`), and the kernel comes
from cache.nixos.org, so CI can sign both once. Their detached signatures are
in `signatures/<sha256 of the unsigned file>.p7`; `<id>-secure-boot sign`
attaches them on the machine, without the private key. On every push to
m245-poc the first CI job signs whatever `.#boot-files` lists and has no
signature yet, commits it and stops; the next run builds on that commit, and
the check `boot-signatures` keeps a missing one from going further.

A kernel without a distro signature (another kernel in `machine.nix`, or
before CI has signed a new one) is signed with a key made on the machine
instead (`/var/lib/<id>/secure-boot`). Only then MokManager asks a second
time, for that key (`sudo <id>-secure-boot enroll`, a code to type).

| What | Where |
|---|---|
| shim and MokManager | `packages/shim` (Debian's, signed by Microsoft and Debian) |
| GRUB with an SBAT section | `packages/grub-sb` |
| Signing the ISO | `packages/sign-iso`, run by CI after the build |
| Making the key, once | `nix run .#secure-boot-key -- FOLDER` |
| GRUB of installed machines | `packages/grub-image` |
| Signatures of GRUB and the kernel | `signatures/`, by `.github/scripts/sign-boot-files.sh` in CI |
| Installed machines | `modules/secure-boot.nix`, `packages/secure-boot` |
