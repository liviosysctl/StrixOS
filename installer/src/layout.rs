//! The partition table of a disk: what sfdisk reads, the free space between the partitions, and
//! the two partitions the installer makes when it goes into part of a disk (next to Windows).
//! Pure functions, unit-tested; only `Table::read` runs a program.

use serde_json::Value;
use std::process::Command;

/// GPT partition types the installer never touches
pub const ESP_TYPE: &str = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
pub const MSR_TYPE: &str = "E3C9E316-0B5C-4DB8-817D-F92DF00215AE";
pub const RECOVERY_TYPE: &str = "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC";

/// The ESP the installer makes, as large as in modules/storage/btrfs.nix
pub const ESP_BYTES: u64 = 1 << 30;
/// Partitions start on whole MiB, as Windows and every other partitioner does
const ALIGN_BYTES: u64 = 1 << 20;
/// GPT holds 128 partitions unless made otherwise
const MAX_PARTITIONS: u32 = 128;

/// A partition, first and last sector included
#[derive(Debug, Clone, PartialEq)]
pub struct Partition {
    pub path: String,
    pub number: u32,
    pub start: u64,
    pub end: u64,
    /// The GPT type, upper case
    pub type_guid: String,
}

/// The GPT of a disk. Disks with an MBR are only ever used whole.
#[derive(Debug, Clone, PartialEq)]
pub struct Table {
    /// First and last sector partitions may use
    pub first: u64,
    pub last: u64,
    pub sector: u64,
    /// Ordered by start
    pub partitions: Vec<Partition>,
}

/// The number at the end of a partition's device: /dev/nvme0n1p5 -> 5, /dev/sda12 -> 12
fn partition_number(path: &str) -> Option<u32> {
    let digits = path.len() - path.trim_end_matches(|c: char| c.is_ascii_digit()).len();
    path[path.len() - digits..].parse().ok()
}

impl Table {
    /// The table of `sfdisk --json`, if it is a GPT
    pub fn parse(sfdisk: &Value) -> Option<Table> {
        let table = sfdisk.get("partitiontable")?;
        if table.get("label")?.as_str()? != "gpt" {
            return None;
        }
        let number = |v: &Value, k: &str| v.get(k).and_then(Value::as_u64);
        let mut partitions: Vec<Partition> = table
            .get("partitions")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or_default()
            .iter()
            .filter_map(|p| {
                let path = p.get("node")?.as_str()?.to_string();
                let start = number(p, "start")?;
                let size = number(p, "size")?;
                Some(Partition {
                    number: partition_number(&path)?,
                    path,
                    start,
                    end: start + size.checked_sub(1)?,
                    type_guid: p
                        .get("type")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_ascii_uppercase(),
                })
            })
            .collect();
        partitions.sort_by_key(|p| p.start);
        Some(Table {
            first: number(table, "firstlba")?,
            last: number(table, "lastlba")?,
            sector: number(table, "sectorsize").unwrap_or(512),
            partitions,
        })
    }

    /// Reads the table of a disk (as root)
    pub fn read(disk: &str) -> Option<Table> {
        let out = Command::new("sfdisk")
            .args(["--json", disk])
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        Table::parse(&serde_json::from_slice(&out.stdout).ok()?)
    }

    pub fn bytes(&self, start: u64, end: u64) -> u64 {
        (end + 1).saturating_sub(start) * self.sector
    }

    fn align(&self) -> u64 {
        (ALIGN_BYTES / self.sector).max(1)
    }

    /// The free space between the partitions, each piece starting and ending on a whole MiB
    pub fn free(&self) -> Vec<(u64, u64)> {
        let align = self.align();
        let mut gaps = Vec::new();
        let mut cursor = self.first;
        let mut gap = |from: u64, to: u64| {
            let start = from.div_ceil(align) * align;
            let end = ((to + 1) / align * align).checked_sub(1);
            if let Some(end) = end
                && end >= start
            {
                gaps.push((start, end));
            }
        };
        for p in &self.partitions {
            if p.start > cursor {
                gap(cursor, p.start - 1);
            }
            cursor = cursor.max(p.end + 1);
        }
        if cursor <= self.last {
            gap(cursor, self.last);
        }
        gaps
    }
}

/// A partition the installer makes
#[derive(Debug, Clone, PartialEq)]
pub struct NewPartition {
    pub number: u32,
    pub start: u64,
    pub end: u64,
}

/// How the installer goes into a part of a disk: the partition there is deleted (if any), an ESP
/// of its own and the system partition take its place. Windows keeps its own ESP untouched.
#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub delete: Option<u32>,
    pub esp: NewPartition,
    pub system: NewPartition,
}

/// The plan for the sectors `start..=end`: exactly one partition, or free space
pub fn plan(table: &Table, start: u64, end: u64) -> Result<Plan, String> {
    if start < table.first || end > table.last || end <= start {
        return Err("The chosen space is not on the disk.".into());
    }
    let replaced = table
        .partitions
        .iter()
        .find(|p| p.start == start && p.end == end);
    let others = || {
        table
            .partitions
            .iter()
            .filter(|p| Some(p.number) != replaced.map(|r| r.number))
    };
    if others().any(|p| p.start <= end && p.end >= start) {
        return Err("The chosen space overlaps a partition. Open the installer again.".into());
    }
    let esp_start = start.div_ceil(table.align()) * table.align();
    let esp_end = esp_start + ESP_BYTES / table.sector - 1;
    if esp_end >= end {
        return Err("The chosen space is too small.".into());
    }
    let used: Vec<u32> = others().map(|p| p.number).collect();
    let mut free_numbers = (1..=MAX_PARTITIONS).filter(|n| !used.contains(n));
    let (Some(esp_number), Some(system_number)) = (free_numbers.next(), free_numbers.next()) else {
        return Err("The partition table is full.".into());
    };
    Ok(Plan {
        delete: replaced.map(|p| p.number),
        esp: NewPartition {
            number: esp_number,
            start: esp_start,
            end: esp_end,
        },
        system: NewPartition {
            number: system_number,
            start: esp_end + 1,
            end,
        },
    })
}

impl Plan {
    /// The arguments for sgdisk, which does it all in one go
    pub fn sgdisk_args(&self, disk: &str, esp_label: &str, system_label: &str) -> Vec<String> {
        let mut args = Vec::new();
        if let Some(n) = self.delete {
            args.push(format!("--delete={n}"));
        }
        for (p, code, label) in [
            (&self.esp, "EF00", esp_label),
            (&self.system, "8300", system_label),
        ] {
            let n = p.number;
            args.push(format!("--new={n}:{}:{}", p.start, p.end));
            args.push(format!("--typecode={n}:{code}"));
            args.push(format!("--change-name={n}:{label}"));
        }
        args.push(disk.to_string());
        args
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use serde_json::json;

    /// A 512 GB NVMe disk as Windows 11 leaves it after C: was shrunk and D: made in the space:
    /// ESP, MSR, C:, D:, the recovery partition at the end, and 1 MiB gaps from the alignment
    pub fn windows_disk() -> Value {
        json!({"partitiontable": {
            "label": "gpt", "id": "9A1B", "device": "/dev/nvme0n1", "unit": "sectors",
            "firstlba": 34, "lastlba": 1000215182, "sectorsize": 512,
            "partitions": [
                {"node": "/dev/nvme0n1p1", "start": 2048, "size": 204800, "type": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B", "uuid": "A1", "name": "EFI system partition"},
                {"node": "/dev/nvme0n1p2", "start": 206848, "size": 32768, "type": "E3C9E316-0B5C-4DB8-817D-F92DF00215AE", "uuid": "A2", "name": "Microsoft reserved partition"},
                {"node": "/dev/nvme0n1p3", "start": 239616, "size": 498073600, "type": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7", "uuid": "A3", "name": "Basic data partition"},
                {"node": "/dev/nvme0n1p5", "start": 498313216, "size": 499908608, "type": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7", "uuid": "A5", "name": "Basic data partition"},
                {"node": "/dev/nvme0n1p4", "start": 998221824, "size": 1992704, "type": "de94bba4-06d1-4d40-a16a-bfd50179d6ac", "uuid": "A4", "name": ""}
            ]
        }})
    }

    #[test]
    fn reads_gpt_only() {
        let t = Table::parse(&windows_disk()).unwrap();
        assert_eq!(t.sector, 512);
        let numbers: Vec<_> = t.partitions.iter().map(|p| p.number).collect();
        assert_eq!(numbers, [1, 2, 3, 5, 4]);
        assert_eq!(t.partitions[4].type_guid, RECOVERY_TYPE);
        assert_eq!(t.partitions[0].end, 206847);
        let mbr = json!({"partitiontable": {"label": "dos", "partitions": []}});
        assert!(Table::parse(&mbr).is_none());
        assert_eq!(partition_number("/dev/mmcblk0p12"), Some(12));
        assert_eq!(partition_number("/dev/sda"), None);
    }

    #[test]
    fn free_space_on_whole_mib() {
        let mut t = Table::parse(&windows_disk()).unwrap();
        // The gaps before the ESP and after the recovery partition are less than a whole MiB
        assert!(t.free().is_empty());
        // D: deleted in Windows: its space is free, aligned
        t.partitions.retain(|p| p.number != 5);
        let big: Vec<_> = t
            .free()
            .into_iter()
            .filter(|&(s, e)| t.bytes(s, e) > 1 << 30)
            .collect();
        assert_eq!(big, [(498313216, 998221823)]);
        // An empty table: everything from the first to the last whole MiB
        let empty = Table {
            first: 34,
            last: 4194270,
            sector: 512,
            partitions: vec![],
        };
        assert_eq!(empty.free(), [(2048, 4192255)]);
        let four_k = Table {
            first: 6,
            last: 524282,
            sector: 4096,
            partitions: vec![],
        };
        assert_eq!(four_k.free(), [(256, 524031)]);
    }

    #[test]
    fn plan_for_a_partition() {
        let t = Table::parse(&windows_disk()).unwrap();
        let d = &t.partitions[3];
        let plan = plan(&t, d.start, d.end).unwrap();
        assert_eq!(plan.delete, Some(5));
        // 5 is free again once D: is gone, 6 is the next
        assert_eq!((plan.esp.number, plan.system.number), (5, 6));
        assert_eq!(plan.esp.start, d.start);
        assert_eq!(t.bytes(plan.esp.start, plan.esp.end), ESP_BYTES);
        assert_eq!(plan.system.start, plan.esp.end + 1);
        assert_eq!(plan.system.end, d.end);
        let args = plan.sgdisk_args("/dev/nvme0n1", "strix-esp-4f2a", "strix-system-4f2a");
        assert_eq!(
            args,
            [
                "--delete=5",
                "--new=5:498313216:500410367",
                "--typecode=5:EF00",
                "--change-name=5:strix-esp-4f2a",
                "--new=6:500410368:998221823",
                "--typecode=6:8300",
                "--change-name=6:strix-system-4f2a",
                "/dev/nvme0n1",
            ]
        );
    }

    #[test]
    fn plan_for_free_space() {
        let mut t = Table::parse(&windows_disk()).unwrap();
        t.partitions.retain(|p| p.number != 5);
        let (start, end) = (498313216, 998221823);
        let plan = plan(&t, start, end).unwrap();
        assert_eq!(plan.delete, None);
        assert_eq!((plan.esp.number, plan.system.number), (5, 6));
        assert_eq!(plan.system.end, end);
        // Reaching into C: or into the recovery partition, or too small: refused. Whether a whole
        // partition may be replaced is not for the plan to say (facts::spaces knows Windows).
        assert!(super::plan(&t, start - 2048, end).is_err());
        assert!(super::plan(&t, start, end + 4096).is_err());
        assert!(super::plan(&t, start, start + 1000).is_err());
    }
}
