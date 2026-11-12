//! Starting what an entry runs. Programs start in their own systemd scope, so they belong to the
//! session and not to the search service (a restart of the service leaves them running).

use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;

use crate::config::Config;
use crate::entry::{Entry, Run};

pub fn on_path(program: &str) -> bool {
    if program.contains('/') {
        return Path::new(program).exists();
    }
    std::env::var_os("PATH")
        .is_some_and(|paths| std::env::split_paths(&paths).any(|d| d.join(program).is_file()))
}

/// The command line that starts an entry, or `None` for entries that only open inside Search.
pub fn argv(cfg: &Config, entry: &Entry) -> Option<Vec<String>> {
    match &entry.run {
        Run::None => None,
        Run::Spawn(argv) => Some(scoped(cfg, &entry.id, argv)),
        Run::Terminal(argv) => Some(scoped(cfg, &entry.id, &in_terminal(cfg, argv))),
    }
}

/// Text that matched nothing, as a command line in the terminal.
pub fn text_argv(cfg: &Config, text: &str) -> Vec<String> {
    scoped(
        cfg,
        "command",
        &in_terminal(cfg, &["sh".into(), "-c".into(), text.into()]),
    )
}

fn in_terminal(cfg: &Config, argv: &[String]) -> Vec<String> {
    cfg.terminal.iter().chain(argv).cloned().collect()
}

fn scoped(cfg: &Config, id: &str, argv: &[String]) -> Vec<String> {
    if cfg.direct_spawn || !on_path("systemd-run") {
        return argv.to_vec();
    }
    let name: String = id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    let unit = format!(
        "app-{}-{}-{}",
        cfg.id,
        name.trim_matches('-'),
        std::process::id() ^ (crate::usage::now() as u32)
    );
    let mut out: Vec<String> = ["systemd-run", "--user", "--scope", "--collect", "--quiet"]
        .map(String::from)
        .to_vec();
    out.push(format!("--unit={unit}"));
    out.push("--".into());
    out.extend(argv.iter().cloned());
    out
}

/// Starts a command line and returns at once; a thread waits for it so no zombie stays behind.
pub fn spawn(argv: &[String]) -> Result<(), String> {
    use std::os::unix::process::CommandExt;
    let (program, args) = argv.split_first().ok_or("nothing to run")?;
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map_err(|e| format!("cannot start {program}: {e}"))?;
    thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::Kind;

    #[test]
    fn terminal_commands_get_the_terminal_in_front() {
        let cfg = Config::empty();
        let mut e = Entry::new("command:strix-update", Kind::Command, "strix-update");
        e.run = Run::Terminal(vec!["strix-update".into()]);
        assert_eq!(argv(&cfg, &e).unwrap(), ["term", "-e", "strix-update"]);
        assert_eq!(
            text_argv(&cfg, "ls -l"),
            ["term", "-e", "sh", "-c", "ls -l"]
        );
        assert_eq!(
            argv(&cfg, &Entry::new("menu:style", Kind::Menu, "Style")),
            None
        );
    }

    #[test]
    fn through_systemd_run_each_start_has_its_own_scope() {
        let mut cfg = Config::empty();
        cfg.direct_spawn = false;
        let a = scoped(&cfg, "app:firefox.desktop", &["firefox".into()]);
        if a[0] == "systemd-run" {
            assert!(
                a.iter()
                    .any(|w| w.starts_with("--unit=app-strix-app-firefox-desktop-"))
            );
            assert_eq!(a.last().unwrap(), "firefox");
        }
    }
}
