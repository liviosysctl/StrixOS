//! The installation: reads an answers file and installs without asking anything. The graphical
//! installer and the automated test both call it (`<id>-install --core`), as root.
//!
//! Its output is read by the graphical installer's back end, line by line:
//!
//! ```text
//! [3/9] Checking the configuration before touching the disk   a step starts
//! Error: The disk is smaller than 32 GiB.                    why it stopped
//! MOK 4711 0                                                  the Secure Boot code, or "-"
//! ```
//!
//! Secrets never go into the answers file. They come from a secrets file of the front end
//! (deleted after reading), or from the password and passphrase files the test writes.

use crate::checks::{self, Answers, MIN_DISK_BYTES, MIN_RAM_GIB};
use crate::facts;
use crate::layout::{self, Plan};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::{FileTypeExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// The titles of the steps, in the log and on stdout. The window shows them translated (st1..st9).
pub const STEPS: [&str; 9] = [
    "Checking the answers and this computer",
    "Writing the configuration",
    "Checking the configuration before touching the disk",
    "Partitioning, encrypting and formatting the disk",
    "Copying the configuration onto the disk",
    "Installing the system",
    "Setting the password",
    "Keeping the log",
    "Finishing",
];

/// Must match the LUKS name in modules/storage/btrfs.nix
const LUKS_NAME: &str = "cryptsystem";

/// What the build fills in (installer/package.nix)
pub struct Env {
    pub id: String,
    pub name: String,
    pub version: String,
    pub state_version: String,
    pub template_dir: PathBuf,
    /// The flake.lock prepared for this ISO, or None to lock during the install
    pub machine_lock: Option<PathBuf>,
}

impl Env {
    pub fn from_environment() -> Env {
        let var = |k: &str| std::env::var(k).unwrap_or_default();
        Env {
            id: var("DISTRO_ID"),
            name: var("DISTRO_NAME"),
            version: var("DISTRO_VERSION"),
            state_version: var("STATE_VERSION"),
            template_dir: PathBuf::from(var("TEMPLATE_DIR")),
            machine_lock: Some(var("MACHINE_LOCK"))
                .filter(|s| !s.is_empty())
                .map(PathBuf::from),
        }
    }

    pub fn work_dir(&self) -> PathBuf {
        PathBuf::from(format!("/run/{}-install", self.id))
    }
    pub fn log_file(&self) -> PathBuf {
        PathBuf::from(format!("/tmp/{}-install.log", self.id))
    }
    pub fn password_file(&self) -> PathBuf {
        self.work_dir().join("user.pass")
    }
    /// Must match passwordFile in modules/storage/btrfs.nix
    pub fn luks_key_file(&self) -> PathBuf {
        PathBuf::from(format!("/tmp/{}-luks.key", self.id))
    }
}

pub struct Options {
    pub answers: PathBuf,
    pub secrets: Option<PathBuf>,
    pub hardware_nix: Option<PathBuf>,
    pub unmount: bool,
}

/// Writes every line to the log and to stdout
struct Log(File);

impl Log {
    fn line(&mut self, text: &str) {
        let _ = writeln!(self.0, "{text}");
        println!("{text}");
    }
    fn quiet(&mut self, text: &str) {
        let _ = writeln!(self.0, "{text}");
    }
}

struct Install<'a> {
    env: &'a Env,
    log: Log,
    mounted: bool,
}

impl Install<'_> {
    fn step(&mut self, n: usize) {
        let text = format!("[{n}/{}] {}", STEPS.len(), STEPS[n - 1]);
        self.log.quiet("");
        self.log.line(&text);
    }

    /// Runs a command, its output shown and logged
    fn run(&mut self, program: &str, args: &[&str]) -> Result<(), String> {
        self.run_with_input(program, args, None)
    }

    fn run_with_input(
        &mut self,
        program: &str,
        args: &[&str],
        input: Option<&str>,
    ) -> Result<(), String> {
        let (reader, writer) = std::io::pipe().map_err(|e| e.to_string())?;
        let mut cmd = Command::new(program);
        cmd.args(args)
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(writer.try_clone().map_err(|e| e.to_string())?)
            .stderr(writer);
        let mut child = cmd
            .spawn()
            .map_err(|e| format!("cannot run {program}: {e}"))?;
        drop(cmd);
        if let (Some(text), Some(mut stdin)) = (input, child.stdin.take()) {
            let _ = stdin.write_all(text.as_bytes());
        }
        let mut last = String::new();
        for line in BufReader::new(reader).lines() {
            let Ok(line) = line else { break };
            self.log.line(&line);
            if !line.trim().is_empty() {
                last = line;
            }
        }
        let status = child.wait().map_err(|e| e.to_string())?;
        if status.success() {
            Ok(())
        } else {
            self.log
                .quiet(&format!("Failed ({status}): {program} {}", args.join(" ")));
            Err(if last.is_empty() {
                format!("{program} failed ({status})")
            } else {
                last
            })
        }
    }

    fn release_disk(&mut self) {
        for (program, args) in [
            ("swapoff", vec!["-a"]),
            ("umount", vec!["-R", "/mnt"]),
            ("cryptsetup", vec!["close", LUKS_NAME]),
        ] {
            let _ = Command::new(program)
                .args(&args)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        self.mounted = false;
    }
}

/// Overwrites a file with zeros and removes it
pub fn shred(path: &Path) {
    if let Ok(meta) = fs::metadata(path) {
        if let Ok(mut f) = OpenOptions::new().write(true).open(path) {
            let _ = f.write_all(&vec![0u8; meta.len() as usize]);
            let _ = f.sync_all();
        }
        let _ = fs::remove_file(path);
    }
}

/// Writes a file only its owner can read
fn write_private(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let mut f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| format!("cannot write {}: {e}", path.display()))?;
    f.write_all(data).map_err(|e| e.to_string())
}

/// The password and the passphrase of a front end's secrets file
/// (`{"password": ..., "passphrase": ...}`); the file is gone afterwards
pub fn take_secrets(file: &Path) -> Result<(String, String), String> {
    let text = fs::read_to_string(file).map_err(|_| format!("No secrets in {}", file.display()))?;
    shred(file);
    let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let field = |k: &str| {
        json.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string()
    };
    Ok((field("password"), field("passphrase")))
}

fn user_exists(name: &str) -> bool {
    fs::read_to_string("/etc/passwd")
        .map(|t| t.lines().any(|l| l.split(':').next() == Some(name)))
        .unwrap_or(false)
}

/// Four random hex digits, for the partition labels
fn label_suffix() -> String {
    let mut b = [0u8; 2];
    if let Ok(mut f) = File::open("/dev/urandom") {
        let _ = f.read_exact(&mut b);
    }
    format!("{:04x}", u16::from_le_bytes(b))
}

/// The labels of the ESP and the system partition, as modules/storage/btrfs.nix names them
fn partition_labels(id: &str, suffix: &str) -> [String; 2] {
    ["esp", "system"].map(|kind| format!("{id}-{kind}-{suffix}"))
}

fn by_partlabel(label: &str) -> PathBuf {
    Path::new("/dev/disk/by-partlabel").join(label)
}

/// A suffix no partition of this computer carries yet: next to an earlier installation on the
/// same disk, the labels must not point at its partitions
fn unused_label_suffix(id: &str) -> String {
    let mut suffix = label_suffix();
    for _ in 0..100 {
        if partition_labels(id, &suffix)
            .iter()
            .all(|l| !by_partlabel(l).exists())
        {
            break;
        }
        suffix = label_suffix();
    }
    suffix
}

/// A random code from 1000 to 9999, for MokManager
fn mok_code() -> u16 {
    let mut b = [0u8; 2];
    if let Ok(mut f) = File::open("/dev/urandom") {
        let _ = f.read_exact(&mut b);
    }
    1000 + (u16::from_le_bytes(b) % 9000)
}

/// Copies every file of the template except its README and machine.nix, so this works on
/// branches with and without apps.json
fn copy_template(template_dir: &Path, stage: &Path) -> Result<(), String> {
    for entry in fs::read_dir(template_dir)
        .map_err(|e| e.to_string())?
        .flatten()
    {
        let name = entry.file_name();
        if name == "README.md" || name == "machine.nix" {
            continue;
        }
        let to = stage.join(&name);
        fs::copy(entry.path(), &to)
            .map_err(|e| format!("cannot copy {}: {e}", name.to_string_lossy()))?;
        let _ = fs::set_permissions(&to, fs::Permissions::from_mode(0o644));
    }
    Ok(())
}

/// Installs from the answers. On failure the disk is released and the error returned.
pub fn install(env: &Env, opts: &Options) -> Result<(), String> {
    let log_path = env.log_file();
    let file =
        File::create(&log_path).map_err(|e| format!("cannot write {}: {e}", log_path.display()))?;
    let mut job = Install {
        env,
        log: Log(file),
        mounted: false,
    };
    // Secrets of a front end go into the files the core reads, so the passphrase is where
    // disko looks for it
    if let Some(secrets) = &opts.secrets {
        let (password, passphrase) = take_secrets(secrets)?;
        if !password.is_empty() {
            write_private(&env.password_file(), format!("{password}\n").as_bytes())?;
        }
        if !passphrase.is_empty() {
            write_private(&env.luks_key_file(), passphrase.as_bytes())?;
        }
    }
    let result = steps(&mut job, opts);
    shred(&env.password_file());
    shred(&env.luks_key_file());
    match result {
        Ok(()) => {
            job.log.quiet("\nDone.");
            Ok(())
        }
        Err(e) => {
            job.log.quiet(&format!("Error: {e}"));
            if job.mounted {
                job.release_disk();
            }
            Err(e)
        }
    }
}

fn steps(job: &mut Install, opts: &Options) -> Result<(), String> {
    let env = job.env;
    let stage = env.work_dir().join("etc-nixos");

    job.step(1);
    if unsafe { libc::geteuid() } != 0 {
        return Err(format!(
            "Run the installer as root: sudo {}-install",
            env.id
        ));
    }
    if !facts::uefi() {
        return Err(format!(
            "{} needs a computer that starts in UEFI mode.",
            env.name
        ));
    }
    if facts::ram_kib() < MIN_RAM_GIB * 1024 * 1024 {
        return Err(format!(
            "{} needs at least {MIN_RAM_GIB} GiB of memory.",
            env.name
        ));
    }
    let text = fs::read_to_string(&opts.answers)
        .map_err(|e| format!("cannot read {}: {e}", opts.answers.display()))?;
    let json = serde_json::from_str(&text).map_err(|e| format!("The answers are not JSON: {e}"))?;
    let mut answers = Answers::parse(&json)?;
    answers.check(&env.id)?;
    // Q6: the partition labels end with something of this machine alone
    if answers.label_suffix.is_none() {
        answers.label_suffix = Some(unused_label_suffix(&env.id));
    }
    let labels = partition_labels(&env.id, answers.label_suffix.as_deref().unwrap_or(""));
    if user_exists(&answers.user_name) {
        return Err(format!("Not a valid user name: {}", answers.user_name));
    }
    if !Path::new("/etc/zoneinfo").join(&answers.time_zone).exists() {
        return Err(format!("Unknown time zone: {}", answers.time_zone));
    }
    let is_block = fs::metadata(&answers.disk)
        .map(|m| m.file_type().is_block_device())
        .unwrap_or(false);
    if !is_block {
        return Err(format!("Not a disk: {}", answers.disk));
    }
    let device = fs::canonicalize(&answers.disk).map_err(|e| e.to_string())?;
    let device_name = device.file_name().map(|n| n.to_string_lossy().into_owned());
    if device_name.is_some() && device_name == facts::boot_disk() {
        return Err(format!(
            "{} is the stick the installer runs from.",
            answers.disk
        ));
    }
    let device = device.to_string_lossy().into_owned();
    // Into a part of the disk: the space must still be there as the window was shown it, and
    // free to use. The plan says what is deleted and what is made in its place.
    let (bytes, plan, place) = match answers.space {
        None => (
            facts::disk_bytes(&device).unwrap_or(0),
            None,
            answers.disk.clone(),
        ),
        Some(space) => {
            let (table, spaces) = facts::disk_spaces(&device).ok_or(format!(
                "{} has no GPT partition table to install next to.",
                answers.disk
            ))?;
            let chosen = spaces
                .iter()
                .find(|s| s.start == space.start && s.end == space.end)
                .ok_or("The disk changed since the installer read it. Open the installer again.")?;
            let place = if chosen.kind == "free" {
                format!("the free space of {device}")
            } else {
                chosen.path.clone()
            };
            if !chosen.blocked.is_empty() {
                return Err(format!("{place} cannot be used ({}).", chosen.blocked));
            }
            if let Some(taken) = labels.iter().find(|l| by_partlabel(l).exists()) {
                return Err(format!(
                    "A partition labelled {taken} is already on this computer."
                ));
            }
            let plan = layout::plan(&table, space.start, space.end)?;
            (chosen.bytes, Some(plan), place)
        }
    };
    if bytes < MIN_DISK_BYTES {
        return Err(format!("{place} is smaller than 32 GiB."));
    }
    let ram = facts::ram_gib();
    if answers.hibernation && !checks::hibernation_fits(bytes / (1 << 30), ram) {
        return Err(format!(
            "{place} is too small for hibernation with {ram} GiB of RAM."
        ));
    }
    let luks_key = env.luks_key_file();
    if answers.encrypt && fs::metadata(&luks_key).map(|m| m.len()).unwrap_or(0) == 0 {
        return Err(format!(
            "Encryption is on, but there is no passphrase in {}.",
            luks_key.display()
        ));
    }
    let password = fs::read_to_string(env.password_file()).unwrap_or_default();
    let password = password.trim_end_matches('\n');
    if password.is_empty() {
        return Err(format!(
            "There is no password in {}.",
            env.password_file().display()
        ));
    }
    let swap = checks::swap_size(ram, answers.hibernation);
    job.log.line(&format!(
        "Installing on {place} ({} GiB{}), swap {swap}, encryption {}, hibernation {}",
        bytes >> 30,
        if plan.is_some() {
            ", the rest of the disk stays"
        } else {
            ""
        },
        answers.encrypt,
        answers.hibernation
    ));

    job.step(2);
    let _ = fs::remove_dir_all(&stage);
    fs::create_dir_all(&stage).map_err(|e| e.to_string())?;
    copy_template(&env.template_dir, &stage)?;
    let template =
        fs::read_to_string(env.template_dir.join("machine.nix")).map_err(|e| e.to_string())?;
    let machine = checks::render_machine_nix(&template, &answers, &swap, &env.state_version)?;
    fs::write(
        stage.join("machine.nix"),
        format!("{}\n", machine.trim_end_matches('\n')),
    )
    .map_err(|e| e.to_string())?;
    match &opts.hardware_nix {
        Some(file) => {
            fs::copy(file, stage.join("hardware.nix")).map_err(|e| e.to_string())?;
        }
        None => {
            let out = Command::new("nixos-generate-config")
                .args(["--no-filesystems", "--show-hardware-config"])
                .output()
                .map_err(|e| format!("cannot run nixos-generate-config: {e}"))?;
            if !out.status.success() {
                return Err("nixos-generate-config failed".into());
            }
            fs::write(stage.join("hardware.nix"), out.stdout).map_err(|e| e.to_string())?;
        }
    }
    let _ = fs::set_permissions(
        stage.join("hardware.nix"),
        fs::Permissions::from_mode(0o644),
    );
    let stage_s = stage.to_string_lossy().into_owned();
    match &env.machine_lock {
        Some(lock) => {
            fs::copy(lock, stage.join("flake.lock")).map_err(|e| e.to_string())?;
            let _ =
                fs::set_permissions(stage.join("flake.lock"), fs::Permissions::from_mode(0o644));
        }
        None => {
            job.log
                .line("This ISO has no prepared lock file, locking now (needs the network).");
            job.run("nix", &["flake", "lock", &stage_s])?;
        }
    }

    job.step(3);
    let attr = format!(
        "{stage_s}#nixosConfigurations.{}.config.system.build.toplevel.drvPath",
        env.id
    );
    job.run("nix", &["eval", "--raw", &attr])?;
    job.log.line("");

    job.step(4);
    job.mounted = true;
    let flake = format!("{stage_s}#{}", env.id);
    match &plan {
        None => job.run(
            "disko",
            &[
                "--mode",
                "destroy,format,mount",
                "--yes-wipe-all-disks",
                "--flake",
                &flake,
            ],
        )?,
        Some(plan) => {
            partition(job, plan, &device, &labels)?;
            job.run("disko", &["--mode", "format,mount", "--flake", &flake])?;
        }
    }
    // The passphrase is only needed while formatting
    shred(&luks_key);

    job.step(5);
    fs::create_dir_all("/mnt/etc/nixos").map_err(|e| e.to_string())?;
    job.run("cp", &["-a", &format!("{stage_s}/."), "/mnt/etc/nixos/"])?;
    job.run("chown", &["-R", "root:root", "/mnt/etc/nixos"])?;

    job.step(6);
    let target = format!("/mnt/etc/nixos#{}", env.id);
    job.run(
        "nixos-install",
        &[
            "--root",
            "/mnt",
            "--flake",
            &target,
            "--no-root-passwd",
            "--no-channel-copy",
        ],
    )?;

    job.step(7);
    let line = format!("{}:{password}\n", answers.user_name);
    let args = in_target("chpasswd");
    job.run_with_input(
        "nixos-enter",
        &args.each_ref().map(String::as_str),
        Some(&line),
    )
    .map_err(|_| "Setting the password failed.".to_string())?;
    shred(&env.password_file());

    job.step(8);
    let kept = PathBuf::from(format!("/mnt/var/log/{}-install.log", env.id));
    let _ = job.log.0.flush();
    fs::create_dir_all("/mnt/var/log").map_err(|e| e.to_string())?;
    fs::copy(env.log_file(), &kept).map_err(|e| e.to_string())?;
    let _ = fs::set_permissions(&kept, fs::Permissions::from_mode(0o600));

    job.step(9);
    let (code, from_disk) = secure_boot(job)?;
    unsafe { libc::sync() };
    if opts.unmount {
        job.release_disk();
    }
    // For the graphical installer: what its done screen shows
    job.log.line(&format!(
        "MOK {} {}",
        code.map(|c| c.to_string()).unwrap_or_else(|| "-".into()),
        u8::from(from_disk)
    ));
    Ok(())
}

/// Deletes the chosen partition (if any) and makes the ESP and the system partition in its
/// place; the other partitions stay as they are. Both are left empty, for disko to format: it
/// keeps a file system it finds (the NTFS of the partition that was there).
fn partition(
    job: &mut Install,
    plan: &Plan,
    disk: &str,
    labels: &[String; 2],
) -> Result<(), String> {
    let args = plan.sgdisk_args(disk, &labels[0], &labels[1]);
    job.run(
        "sgdisk",
        &args.iter().map(String::as_str).collect::<Vec<_>>(),
    )?;
    // sgdisk tells the kernel itself; partx is for a disk the kernel kept busy
    let _ = Command::new("partx")
        .args(["--update", disk])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    job.run("udevadm", &["settle"])?;
    let links = labels.each_ref().map(|l| by_partlabel(l));
    for _ in 0..40 {
        if links.iter().all(|l| l.exists()) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
    for link in &links {
        if !link.exists() {
            return Err(format!(
                "{} did not appear after partitioning.",
                link.display()
            ));
        }
        job.run("wipefs", &["--all", "--force", &link.to_string_lossy()])?;
    }
    Ok(())
}

/// The arguments for `nixos-enter` to run a shell command inside the new system. The command gets
/// that system's PATH: nixos-enter passes the caller's PATH on, and the graphical installer runs
/// through sudo from a user service, whose PATH only holds the installer's own tools.
fn in_target(command: &str) -> [String; 4] {
    [
        "--root".into(),
        "/mnt".into(),
        "-c".into(),
        format!("PATH=/run/wrappers/bin:/nix/var/nix/profiles/system/sw/bin; {command}"),
    ]
}

/// Whether a shell command inside the new system succeeds, without logging it
fn succeeds_in_target(command: &str) -> bool {
    Command::new("nixos-enter")
        .args(in_target(command))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// Only machines with modules/secure-boot.nix have this tool. It points a firmware boot entry at
/// shim and, with Secure Boot on and only if shim does not trust the keys of the boot files yet,
/// asks MokManager to enroll them at the next start; the done screen then shows the code.
fn secure_boot(job: &mut Install) -> Result<(Option<u16>, bool), String> {
    let tool = format!("{}-secure-boot", job.env.id);
    if !succeeds_in_target(&format!("command -v {tool}")) {
        return Ok((None, false));
    }
    let args = in_target(&format!("{tool} boot-entry"));
    if job
        .run("nixos-enter", &args.each_ref().map(String::as_str))
        .is_err()
    {
        job.log
            .line("No boot entry for shim, the firmware will start the fallback path EFI/BOOT/BOOTX64.EFI.");
    }
    if !facts::secure_boot() {
        return Ok((None, false));
    }
    // GRUB and the kernel normally carry the distro signature, and shim trusts that key since
    // the stick: then nothing is left to enroll
    if !succeeds_in_target(&format!("{tool} needs-enroll")) {
        job.log
            .line("shim already trusts the keys of GRUB and the kernel, nothing to enroll.");
        return Ok((None, false));
    }
    let code = mok_code();
    let args = in_target(&format!("{tool} enroll --code {code}"));
    if job
        .run("nixos-enter", &args.each_ref().map(String::as_str))
        .is_ok()
    {
        Ok((Some(code), false))
    } else {
        job.log.line(
            "Could not ask MokManager to enroll the key, it can still be enrolled from disk.",
        );
        Ok((None, true))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secrets_file() {
        let dir = std::env::temp_dir().join(format!("installer-secrets-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("secrets.json");
        fs::write(
            &file,
            r#"{"password": "secret 12", "passphrase": "pass phrase"}"#,
        )
        .unwrap();
        let (password, passphrase) = take_secrets(&file).unwrap();
        assert_eq!(
            (password.as_str(), passphrase.as_str()),
            ("secret 12", "pass phrase")
        );
        assert!(!file.exists());
        let private = dir.join("user.pass");
        write_private(&private, b"x").unwrap();
        assert_eq!(
            fs::metadata(&private).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn mok_codes() {
        for _ in 0..50 {
            assert!((1000..=9999).contains(&mok_code()));
        }
    }

    #[test]
    fn label_suffixes() {
        for _ in 0..20 {
            assert!(checks::valid_label_suffix(&label_suffix()));
        }
        assert_eq!(
            partition_labels("strix", "4f2a"),
            ["strix-esp-4f2a", "strix-system-4f2a"]
        );
        assert!(checks::valid_label_suffix(&unused_label_suffix("strix")));
    }

    #[test]
    fn step_titles() {
        assert_eq!(STEPS.len(), 9);
    }
}
