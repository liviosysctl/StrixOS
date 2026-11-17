//! What the installer knows about this computer: memory, disks, firmware.

use crate::checks::{MIN_DISK_BYTES, MIN_FREE_GIB, MIN_RAM_GIB};
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::path::Path;
use std::process::Command;

/// A disk that can be installed on
#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Disk {
    pub path: String,
    /// A path that stays the same between boots, from /dev/disk/by-id, else `path`
    #[serde(rename = "stablePath")]
    pub stable_path: String,
    pub bytes: u64,
    pub model: String,
    pub transport: String,
}

/// The firmware variable that says whether Secure Boot is on
const SECURE_BOOT_VAR: &str =
    "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c";

pub fn ram_kib() -> u64 {
    fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|text| {
            text.lines()
                .find(|l| l.starts_with("MemTotal:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|n| n.parse().ok())
        })
        .unwrap_or(0)
}

/// Memory in GiB, rounded up
pub fn ram_gib() -> u64 {
    ram_kib().div_ceil(1024 * 1024)
}

pub fn uefi() -> bool {
    Path::new("/sys/firmware/efi/efivars").is_dir()
}

/// Secure Boot is on when the variable's first byte after its 4 attribute bytes is 1
pub fn secure_boot() -> bool {
    fs::read(SECURE_BOOT_VAR)
        .map(|bytes| bytes.get(4) == Some(&1))
        .unwrap_or(false)
}

pub fn laptop() -> bool {
    fs::read_dir("/sys/class/power_supply")
        .map(|dir| {
            dir.flatten().any(|entry| {
                fs::read_to_string(entry.path().join("type"))
                    .map(|t| t.trim() == "Battery")
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

fn output(program: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(program).args(args).output().ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The disk the live system was started from (e.g. "sdb"), so it is never offered
pub fn boot_disk() -> Option<String> {
    let source = output("findmnt", &["--noheadings", "--output", "SOURCE", "/iso"])?;
    let source = source.trim();
    if source.is_empty() {
        return None;
    }
    let parent = output("lsblk", &["--noheadings", "--output", "PKNAME", source])
        .and_then(|p| p.lines().next().map(|l| l.trim().to_string()))
        .filter(|p| !p.is_empty());
    Some(parent.unwrap_or_else(|| {
        Path::new(source)
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default()
    }))
}

/// Size of a block device in bytes
pub fn disk_bytes(device: &str) -> Option<u64> {
    output(
        "lsblk",
        &[
            "--bytes",
            "--nodeps",
            "--noheadings",
            "--output",
            "SIZE",
            device,
        ],
    )?
    .trim()
    .parse()
    .ok()
}

/// The disks of `lsblk --json` that can be installed on: whole, writable, big enough, not the
/// stick the installer runs from and not zram
pub fn candidate_disks(lsblk_json: &Value, boot: Option<&str>) -> Vec<Disk> {
    let empty = Vec::new();
    lsblk_json
        .get("blockdevices")
        .and_then(Value::as_array)
        .unwrap_or(&empty)
        .iter()
        .filter_map(|d| {
            let s = |k: &str| d.get(k).and_then(Value::as_str).unwrap_or("").to_string();
            let name = s("name");
            let bytes = d.get("size").and_then(Value::as_u64).unwrap_or(0);
            let ok = s("type") == "disk"
                && !d.get("ro").and_then(Value::as_bool).unwrap_or(false)
                && Some(name.as_str()) != boot
                && !name.starts_with("zram")
                && bytes >= MIN_DISK_BYTES;
            ok.then(|| {
                let model = s("model");
                let model = model.trim_end();
                Disk {
                    path: s("path"),
                    stable_path: String::new(),
                    bytes,
                    model: if model.is_empty() {
                        "Disk".into()
                    } else {
                        model.into()
                    },
                    transport: s("tran"),
                }
            })
        })
        .collect()
}

/// Rank of a /dev/disk/by-id name: lower is better; partitions are skipped
fn id_rank(name: &str) -> Option<u8> {
    if name.contains("-part") {
        return None;
    }
    Some(if name.starts_with("nvme-eui.") {
        6
    } else if name.starts_with("nvme-") {
        1
    } else if name.starts_with("ata-") {
        2
    } else if name.starts_with("scsi-") {
        3
    } else if name.starts_with("usb-") {
        4
    } else if name.starts_with("wwn-") {
        5
    } else {
        7
    })
}

/// A path for the disk that does not change between boots, if one exists. disko only uses it
/// while formatting; the installed system mounts by partition label.
pub fn stable_disk_path(device: &str) -> String {
    let target = fs::canonicalize(device).unwrap_or_else(|_| device.into());
    let mut best: Option<(u8, String)> = None;
    if let Ok(dir) = fs::read_dir("/dev/disk/by-id") {
        for entry in dir.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(rank) = id_rank(&name) else { continue };
            if fs::canonicalize(entry.path()).ok().as_ref() != Some(&target) {
                continue;
            }
            if best.as_ref().is_none_or(|(r, _)| rank < *r) {
                best = Some((rank, entry.path().to_string_lossy().into_owned()));
            }
        }
    }
    best.map(|(_, p)| p).unwrap_or_else(|| device.to_string())
}

/// The computer and its disks as JSON, for the graphical installer
pub fn facts(name: &str, id: &str, version: &str) -> Value {
    let lsblk = output(
        "lsblk",
        &[
            "--json",
            "--bytes",
            "--nodeps",
            "--output",
            "NAME,PATH,SIZE,TYPE,TRAN,MODEL,RO",
        ],
    )
    .and_then(|o| serde_json::from_str(&o).ok())
    .unwrap_or(Value::Null);
    let boot = boot_disk();
    let disks: Vec<Disk> = candidate_disks(&lsblk, boot.as_deref())
        .into_iter()
        .map(|mut d| {
            d.stable_path = stable_disk_path(&d.path);
            d
        })
        .collect();
    serde_json::json!({
        "name": name, "id": id, "version": version,
        "ramGib": ram_gib(), "minRamGib": MIN_RAM_GIB, "minFreeGib": MIN_FREE_GIB,
        "uefi": uefi(), "secureBoot": secure_boot(), "laptop": laptop(),
        "disks": disks,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn disks_to_offer() {
        // sdb is the boot stick, sdc too small, zram and the CD are no disks to install on
        let lsblk = json!({"blockdevices": [
            {"name":"sda","path":"/dev/sda","size":42949672960u64,"type":"disk","tran":"sata","model":"VMware Virtual S  ","ro":false},
            {"name":"sdb","path":"/dev/sdb","size":64424509440u64,"type":"disk","tran":"usb","model":"Stick","ro":false},
            {"name":"sdc","path":"/dev/sdc","size":21474836480u64,"type":"disk","tran":"sata","model":"Small","ro":false},
            {"name":"nvme0n1","path":"/dev/nvme0n1","size":1000204886016u64,"type":"disk","tran":"nvme","model":null,"ro":false},
            {"name":"sr0","path":"/dev/sr0","size":1610612736u64,"type":"rom","tran":"sata","model":"CD","ro":true},
            {"name":"zram0","path":"/dev/zram0","size":42949672960u64,"type":"disk","tran":null,"model":null,"ro":false}
        ]});
        let disks = candidate_disks(&lsblk, Some("sdb"));
        let paths: Vec<_> = disks.iter().map(|d| d.path.as_str()).collect();
        assert_eq!(paths, ["/dev/sda", "/dev/nvme0n1"]);
        assert_eq!(disks[0].model, "VMware Virtual S");
        assert_eq!(disks[1].model, "Disk");
        assert_eq!(disks[1].transport, "nvme");
    }

    #[test]
    fn id_ranks() {
        assert_eq!(id_rank("nvme-Samsung_SSD_980_1TB"), Some(1));
        assert_eq!(id_rank("nvme-eui.002538"), Some(6));
        assert_eq!(id_rank("ata-WDC-part1"), None);
        assert!(id_rank("ata-WDC") < id_rank("usb-Stick"));
    }
}
