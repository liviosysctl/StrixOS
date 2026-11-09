//! The parts that touch the running system: files, the console, EFI variables.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

/// Writes a file so that readers see either the old or the new content:
/// a temporary file next to it, synced, then renamed over it.
pub fn write_atomic(path: &Path, content: &[u8], mode: u32) -> io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path without a folder"))?;
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path without a file name"))?;
    let mut temporary = PathBuf::from(dir);
    temporary.push(format!(
        ".{}.{}.tmp",
        name.to_string_lossy(),
        std::process::id()
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&temporary)?;
        file.write_all(content)?;
        // The umask may have taken bits away
        file.set_permissions(fs::Permissions::from_mode(mode))?;
        file.sync_all()?;
        fs::rename(&temporary, path)?;
        // The rename itself is only durable once the folder is synced
        File::open(dir)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

/// An exclusive lock on a file, released when dropped.
pub struct Lock {
    _file: File,
}

impl Lock {
    pub fn take(path: &Path) -> io::Result<Lock> {
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .mode(0o600)
            .open(path)?;
        // Safety: flock on a valid descriptor
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Lock { _file: file })
    }
}

pub fn is_root() -> bool {
    // Safety: geteuid has no preconditions
    unsafe { libc::geteuid() == 0 }
}

/// Points `link` at `target`, replacing what was there, in one step.
pub fn symlink_atomic(target: &Path, link: &Path) -> io::Result<()> {
    let dir = link
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path without a folder"))?;
    let temporary = dir.join(format!(
        ".{}.{}.tmp",
        link.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id()
    ));
    let _ = fs::remove_file(&temporary);
    std::os::unix::fs::symlink(target, &temporary)?;
    fs::rename(&temporary, link).inspect_err(|_| {
        let _ = fs::remove_file(&temporary);
    })
}

// The console palette. PIO_CMAP and GIO_CMAP from linux/kd.h.
const GIO_CMAP: libc::c_ulong = 0x4B70;
const PIO_CMAP: libc::c_ulong = 0x4B71;

/// Sets the palette of every virtual console. Needs root.
pub fn set_console_palette(device: &Path, palette: &[u8; 48]) -> io::Result<()> {
    let file = OpenOptions::new()
        .write(true)
        .custom_flags(libc::O_NOCTTY)
        .open(device)?;
    // Safety: PIO_CMAP reads exactly 48 bytes from the pointer
    if unsafe { libc::ioctl(file.as_raw_fd(), PIO_CMAP as _, palette.as_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

// Console modes, from linux/kd.h
const KDSETMODE: libc::c_ulong = 0x4B3A;
const KDGETMODE: libc::c_ulong = 0x4B3B;
const KD_TEXT: libc::c_int = 0;
const KD_GRAPHICS: libc::c_int = 1;

/// Draws the visible console again, so a new palette shows on the whole
/// screen. On a framebuffer console the palette only applies to what is
/// drawn after it changed; the text already on screen keeps its old colors.
///
/// Switching the console to graphics mode and back makes the kernel redraw
/// everything, the same as leaving a graphical session. A console that is
/// already in graphics mode belongs to a compositor and is left alone; the
/// other consoles are redrawn by the kernel anyway when they are switched to.
/// Returns whether the screen was redrawn.
pub fn redraw_console(device: &Path) -> io::Result<bool> {
    let file = OpenOptions::new()
        .write(true)
        .custom_flags(libc::O_NOCTTY)
        .open(device)?;
    let fd = file.as_raw_fd();
    let mut mode: libc::c_int = -1;
    // Safety: KDGETMODE writes one int
    if unsafe { libc::ioctl(fd, KDGETMODE as _, &mut mode) } != 0 {
        return Err(io::Error::last_os_error());
    }
    if mode != KD_TEXT {
        return Ok(false);
    }
    // Safety: KDSETMODE takes the mode as its value
    if unsafe { libc::ioctl(fd, KDSETMODE as _, KD_GRAPHICS as libc::c_ulong) } != 0 {
        return Err(io::Error::last_os_error());
    }
    // Back to text in any case, a console left in graphics mode shows nothing.
    // Safety: as above
    if unsafe { libc::ioctl(fd, KDSETMODE as _, KD_TEXT as libc::c_ulong) } != 0 {
        let error = io::Error::last_os_error();
        // One more try before giving up
        // Safety: as above
        if unsafe { libc::ioctl(fd, KDSETMODE as _, KD_TEXT as libc::c_ulong) } != 0 {
            return Err(error);
        }
    }
    Ok(true)
}

/// Reads the palette of the virtual consoles.
pub fn console_palette(device: &Path) -> io::Result<[u8; 48]> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOCTTY)
        .open(device)?;
    let mut palette = [0u8; 48];
    // Safety: GIO_CMAP writes exactly 48 bytes to the pointer
    if unsafe { libc::ioctl(file.as_raw_fd(), GIO_CMAP as _, palette.as_mut_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(palette)
}

/// An EFI variable in efivarfs, e.g. /sys/firmware/efi/efivars/Name-<guid>.
pub struct EfiVariable {
    pub path: PathBuf,
}

// Non-volatile, reachable while booting and at runtime
const EFI_ATTRIBUTES: u32 = 0x1 | 0x2 | 0x4;
const FS_IMMUTABLE_FL: libc::c_int = 0x10;

impl EfiVariable {
    pub fn new(efivars: &Path, name: &str) -> EfiVariable {
        EfiVariable {
            path: efivars.join(name),
        }
    }

    /// Whether the system runs on EFI with efivarfs mounted.
    pub fn available(&self) -> bool {
        self.path.parent().is_some_and(Path::is_dir)
    }

    /// The value, or None if the variable does not exist.
    pub fn read(&self) -> io::Result<Option<Vec<u8>>> {
        let mut file = match File::open(&self.path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes)?;
        // The first four bytes are the attributes
        if bytes.len() < 4 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "EFI variable shorter than its attributes",
            ));
        }
        Ok(Some(bytes.split_off(4)))
    }

    /// Creates or replaces the variable.
    pub fn write(&self, value: &[u8]) -> io::Result<()> {
        // efivarfs marks variables of unknown vendors immutable. Lift that first.
        if self.path.exists() {
            set_immutable(&self.path, false)?;
        }
        let mut buffer = Vec::with_capacity(4 + value.len());
        buffer.extend_from_slice(&EFI_ATTRIBUTES.to_ne_bytes());
        buffer.extend_from_slice(value);
        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o644)
            .open(&self.path)?;
        // efivarfs needs the whole variable in one write
        // Safety: writes buffer.len() bytes from a valid buffer
        let written =
            unsafe { libc::write(file.as_raw_fd(), buffer.as_ptr().cast(), buffer.len()) };
        let Ok(written) = usize::try_from(written) else {
            return Err(io::Error::last_os_error());
        };
        if written != buffer.len() {
            return Err(io::Error::new(
                io::ErrorKind::WriteZero,
                "EFI variable written only in part",
            ));
        }
        Ok(())
    }
}

fn set_immutable(path: &Path, immutable: bool) -> io::Result<()> {
    let file = File::open(path)?;
    let mut flags: libc::c_int = 0;
    // Safety: FS_IOC_GETFLAGS writes one int
    if unsafe { libc::ioctl(file.as_raw_fd(), libc::FS_IOC_GETFLAGS as _, &mut flags) } != 0 {
        let error = io::Error::last_os_error();
        // A file system without these flags cannot have the file immutable either
        return match error.raw_os_error() {
            Some(libc::ENOTTY | libc::EOPNOTSUPP | libc::EINVAL) => Ok(()),
            _ => Err(error),
        };
    }
    let wanted = if immutable {
        flags | FS_IMMUTABLE_FL
    } else {
        flags & !FS_IMMUTABLE_FL
    };
    if wanted == flags {
        return Ok(());
    }
    // Safety: FS_IOC_SETFLAGS reads one int
    if unsafe { libc::ioctl(file.as_raw_fd(), libc::FS_IOC_SETFLAGS as _, &wanted) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("theme-engine-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn atomic_write_replaces_and_sets_the_mode() {
        let dir = scratch("atomic");
        let path = dir.join("file");
        write_atomic(&path, b"one", 0o644).unwrap();
        write_atomic(&path, b"two", 0o600).unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"two");
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        // No temporary file left behind
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn atomic_symlink_replaces() {
        let dir = scratch("symlink");
        let link = dir.join("current");
        symlink_atomic(Path::new("/a"), &link).unwrap();
        symlink_atomic(Path::new("/b"), &link).unwrap();
        assert_eq!(fs::read_link(&link).unwrap(), PathBuf::from("/b"));
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn efi_variable_format_on_a_plain_folder() {
        // efivarfs itself is not available in tests, a plain folder shows the layout
        let dir = scratch("efi");
        let variable = EfiVariable::new(&dir, "Theme-00000000-0000-0000-0000-000000000000");
        assert!(variable.available());
        assert_eq!(variable.read().unwrap(), None);
        fs::write(&variable.path, [7, 0, 0, 0, b'a', b':', b'b']).unwrap();
        assert_eq!(variable.read().unwrap(), Some(b"a:b".to_vec()));
        fs::write(&variable.path, [7, 0]).unwrap();
        assert!(variable.read().is_err());
        assert!(!EfiVariable::new(&dir.join("missing"), "x").available());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn lock_can_be_taken_twice_in_a_row() {
        let dir = scratch("lock");
        drop(Lock::take(&dir.join("lock")).unwrap());
        drop(Lock::take(&dir.join("lock")).unwrap());
        fs::remove_dir_all(dir).unwrap();
    }
}
