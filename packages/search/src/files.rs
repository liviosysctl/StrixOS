//! Files and folders of the home in Search, found by a part of their name. They are looked up
//! when asked (fd), not kept in the index: a home changes too often for that. Hidden files and
//! what a .gitignore leaves out stay out, as fd does it.

use crate::entry::{Entry, Kind, Run};
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// How many are shown under the other results
const MOST: usize = 6;
/// A search that takes longer than this is given up: Search must stay as fast as typing
const PATIENCE: Duration = Duration::from_millis(350);
/// The id of a result that is a file starts with this, the path follows
pub const PREFIX: &str = "file:";

/// The files and folders under `home` whose name holds `text`
pub fn find(text: &str, home: &Path) -> Vec<Entry> {
    let text = text.trim();
    if text.chars().count() < 3 {
        return Vec::new();
    }
    let child = Command::new("fd")
        .args([
            "--max-results",
            &MOST.to_string(),
            "--ignore-case",
            "--fixed-strings",
            "--",
        ])
        .arg(text)
        .arg(home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else {
        return Vec::new();
    };
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if started.elapsed() < PATIENCE => {
                std::thread::sleep(Duration::from_millis(5))
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break;
            }
        }
    }
    let mut found = String::new();
    if let Some(mut out) = child.stdout.take() {
        let _ = out.read_to_string(&mut found);
    }
    found
        .lines()
        .filter(|l| !l.is_empty())
        .map(|line| entry(line, home))
        .collect()
}

fn entry(line: &str, home: &Path) -> Entry {
    let folder = line.ends_with('/');
    let path = Path::new(line.trim_end_matches('/'));
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut e = Entry::new(format!("{PREFIX}{}", path.display()), Kind::File, name);
    // Where it is, with ~ for the home
    let place = path.parent().unwrap_or(home);
    e.path = vec![match place.strip_prefix(home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => place.display().to_string(),
    }];
    e.icon = Some(if folder { "folder" } else { "file" }.to_string());
    e.run = Run::Spawn(open(&path.display().to_string()));
    e
}

/// What opens a file or a folder: the app that is the default for it
pub fn open(path: &str) -> Vec<String> {
    vec!["xdg-open".to_string(), path.to_string()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_found_line_becomes_a_result() {
        let home = Path::new("/home/ada");
        let e = entry("/home/ada/Documents/notes/", home);
        assert_eq!(e.id, "file:/home/ada/Documents/notes");
        assert_eq!(e.title, "notes");
        assert_eq!(e.path, vec!["~/Documents"]);
        assert_eq!(e.icon.as_deref(), Some("folder"));
        let e = entry("/home/ada/plan.md", home);
        assert_eq!(e.path, vec!["~"]);
        assert_eq!(e.icon.as_deref(), Some("file"));
    }

    #[test]
    fn short_queries_find_nothing() {
        assert!(find("ab", Path::new("/")).is_empty());
    }
}
