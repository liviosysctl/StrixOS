//! Other programs: run one, read what it prints, or become it.

use std::io::Write;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, ExitCode, Stdio};

/// Runs a program and waits; true when it ended well. One that is missing counts as failed.
pub fn ok(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .status()
        .is_ok_and(|status| status.success())
}

/// The same without anything on the terminal
pub fn quiet(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}

/// What a program prints, without the line end; None when it failed
pub fn read(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program)
        .args(args)
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(
        String::from_utf8_lossy(&output.stdout)
            .trim_end()
            .to_string(),
    )
}

/// Runs a program with `input` as what it reads
pub fn feed(program: &str, args: &[&str], input: &[u8]) -> Result<(), String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{program}: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(input)
            .map_err(|e| format!("{program}: {e}"))?;
    }
    let status = child.wait().map_err(|e| format!("{program}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{program} failed"))
    }
}

/// Becomes the program: only an error comes back
pub fn become_it(program: &str, args: &[&str]) -> Result<ExitCode, String> {
    Err(format!(
        "{program}: {}",
        Command::new(program).args(args).exec()
    ))
}

/// A message on the screen
pub fn notify(app: &str, title: &str, body: &str) {
    ok("notify-send", &[&format!("--app-name={app}"), title, body]);
}

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

/// `$XDG_CONFIG_HOME`, else ~/.config
pub fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}

/// `$XDG_RUNTIME_DIR`, else /run/user/<uid>
pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        // SAFETY: getuid has no preconditions and cannot fail
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })))
}
