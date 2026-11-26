//! `<id>-storage`: what the disk holds, for Settings › Storage.
//!
//!   show          JSON: the disk of the system (size, used, free), the trash (bytes and
//!                 items), the snapshots of /home (how many, the newest) and the versions of
//!                 the system still installed
//!   empty-trash   empty the trash of the person, for good

use std::ffi::CString;
use std::fs;
use std::path::Path;
use std::process::ExitCode;

use serde_json::{Value, json};

use crate::Call;
use crate::run::{home, read};

/// Size, used and free bytes of the filesystem of `path`
fn disk(path: &str) -> Option<(u64, u64, u64)> {
    let c = CString::new(path).ok()?;
    // SAFETY: statvfs is plain data, all zero is a valid value of it
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: c is a valid NUL-terminated path and stat a valid, writable statvfs
    if unsafe { libc::statvfs(c.as_ptr(), &mut stat) } != 0 {
        return None;
    }
    let block = stat.f_frsize as u64;
    let size = stat.f_blocks as u64 * block;
    let free = stat.f_bavail as u64 * block;
    Some((size, size.saturating_sub(stat.f_bfree as u64 * block), free))
}

/// Bytes and entries under `dir`, links not followed
fn tree(dir: &Path) -> (u64, u64) {
    let mut bytes = 0;
    let mut stack = vec![dir.to_path_buf()];
    while let Some(folder) = stack.pop() {
        let Ok(entries) = fs::read_dir(&folder) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(meta) = entry.path().symlink_metadata() else {
                continue;
            };
            if meta.is_dir() {
                stack.push(entry.path());
            } else {
                bytes += meta.len();
            }
        }
    }
    let items = fs::read_dir(dir).map(|e| e.count() as u64).unwrap_or(0);
    (bytes, items)
}

/// How many snapshots snapper keeps of /home, and the date of the newest
pub fn snapshots(json: &str) -> (usize, Option<String>) {
    let Ok(value) = serde_json::from_str::<Value>(json) else {
        return (0, None);
    };
    let list: Vec<&Value> = value
        .get("home")
        .and_then(Value::as_array)
        .map(|l| {
            l.iter()
                .filter(|s| s["number"].as_u64() != Some(0))
                .collect()
        })
        .unwrap_or_default();
    let newest = list
        .iter()
        .filter_map(|s| s["date"].as_str())
        .max()
        .map(String::from);
    (list.len(), newest)
}

/// The versions of the system still installed: the links system-N-link of its profile
fn generations(profiles: &Path) -> usize {
    fs::read_dir(profiles)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    name.starts_with("system-") && name.ends_with("-link")
                })
                .count()
        })
        .unwrap_or(0)
}

fn trash_dir() -> std::path::PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .filter(|d| !d.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"))
        .join("Trash")
}

fn show() -> Value {
    let (size, used, free) = disk("/").unwrap_or((0, 0, 0));
    let (trash, items) = tree(&trash_dir().join("files"));
    let (count, newest) = read("snapper", &["--jsonout", "-c", "home", "list"])
        .map(|text| snapshots(&text))
        .unwrap_or((0, None));
    json!({
        "disk": { "size": size, "used": used, "free": free },
        "trash": { "bytes": trash, "items": items },
        "snapshots": { "count": count, "newest": newest },
        "generations": generations(Path::new("/nix/var/nix/profiles")),
    })
}

/// Everything in the trash and what it knows about it, gone for good
fn empty_trash() -> Result<(), String> {
    let trash = trash_dir();
    for part in ["files", "info", "expunged"] {
        let dir = trash.join(part);
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let gone = if path.symlink_metadata().is_ok_and(|m| m.is_dir()) {
                fs::remove_dir_all(&path)
            } else {
                fs::remove_file(&path)
            };
            gone.map_err(|e| format!("cannot remove {}: {e}", path.display()))?;
        }
    }
    let _ = fs::remove_file(trash.join("directorysizes"));
    Ok(())
}

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        [] | ["show"] => {
            println!("{}", show());
            Ok(ExitCode::SUCCESS)
        }
        ["empty-trash"] => {
            empty_trash()?;
            Ok(ExitCode::SUCCESS)
        }
        _ => Ok(crate::usage(call, "show | empty-trash")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_snapshots_of_home() {
        let json = r#"{"home": [
            {"number": 0, "date": ""},
            {"number": 12, "date": "2026-11-25 12:00:01"},
            {"number": 13, "date": "2026-11-25 13:00:01"}
        ]}"#;
        assert_eq!(
            snapshots(json),
            (2, Some("2026-11-25 13:00:01".to_string()))
        );
        assert_eq!(snapshots("not json"), (0, None));
    }

    #[test]
    fn a_tree_and_the_disk() {
        let dir = std::env::temp_dir().join(format!("storage-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("a/b")).unwrap();
        fs::write(dir.join("a/b/one"), [0u8; 10]).unwrap();
        fs::write(dir.join("two"), [0u8; 5]).unwrap();
        assert_eq!(tree(&dir), (15, 2));
        let (size, used, free) = disk("/").unwrap();
        assert!(size > 0 && used <= size && free <= size);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_versions_of_the_system() {
        let dir = std::env::temp_dir().join(format!("generations-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for name in ["system", "system-41-link", "system-42-link", "per-user"] {
            fs::write(dir.join(name), "").unwrap();
        }
        assert_eq!(generations(&dir), 2);
        let _ = fs::remove_dir_all(&dir);
    }
}
