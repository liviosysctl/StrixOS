//! `<id>-defaults`: which app opens what (Settings › Default apps). A kind is a set of file
//! types that go together, a browser opens all of http, https and HTML. The choice is written to
//! the person's mimeapps.list, which every app and `xdg-open` read; the machine's choices
//! (/etc/xdg/mimeapps.list, from NixOS) stay below it.
//!
//!   list            every kind as JSON: its title, the app chosen and the apps that can do it
//!   set KIND APP    APP (a desktop id, firefox.desktop) for every type of KIND
//!   run KIND [ARG]  start the app chosen for KIND (the browser key does this)

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use serde_json::{Value, json};

use crate::Call;
use crate::run::{become_it, config_home, home};

/// A kind: its name, its title in Settings, its file types (the first decides what is chosen)
const KINDS: [(&str, &str, &[&str]); 8] = [
    (
        "browser",
        "Browser",
        &[
            "x-scheme-handler/https",
            "x-scheme-handler/http",
            "text/html",
            "application/xhtml+xml",
        ],
    ),
    (
        "editor",
        "Text",
        &[
            "text/plain",
            "text/markdown",
            "text/x-nix",
            "application/json",
            "application/toml",
            "application/x-shellscript",
        ],
    ),
    ("files", "Folders", &["inode/directory"]),
    (
        "images",
        "Pictures",
        &[
            "image/png",
            "image/jpeg",
            "image/gif",
            "image/webp",
            "image/svg+xml",
            "image/avif",
            "image/bmp",
            "image/tiff",
        ],
    ),
    (
        "video",
        "Video",
        &[
            "video/mp4",
            "video/x-matroska",
            "video/webm",
            "video/quicktime",
            "video/x-msvideo",
        ],
    ),
    (
        "music",
        "Music",
        &[
            "audio/mpeg",
            "audio/flac",
            "audio/ogg",
            "audio/x-vorbis+ogg",
            "audio/mp4",
            "audio/x-wav",
            "audio/opus",
        ],
    ),
    ("pdf", "PDF", &["application/pdf"]),
    (
        "archives",
        "Archives",
        &[
            "application/zip",
            "application/x-tar",
            "application/x-compressed-tar",
            "application/x-7z-compressed",
            "application/vnd.rar",
        ],
    ),
];

/// An app that can open something: its desktop id, name, symbol and file types
#[derive(Clone, Debug, PartialEq)]
pub struct App {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub types: Vec<String>,
}

/// Where desktop entries and mimeapps.list files are, most important first
struct Places {
    config: Vec<PathBuf>,
    data: Vec<PathBuf>,
}

impl Places {
    fn from_env() -> Places {
        let list = |name: &str, fallback: &str| -> Vec<PathBuf> {
            std::env::var(name)
                .ok()
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| fallback.to_string())
                .split(':')
                .filter(|d| !d.is_empty())
                .map(PathBuf::from)
                .collect()
        };
        let data_home = std::env::var_os("XDG_DATA_HOME")
            .filter(|d| !d.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home().join(".local/share"));
        let mut config = vec![config_home()];
        config.extend(list("XDG_CONFIG_DIRS", "/etc/xdg"));
        let mut data = vec![data_home];
        data.extend(list(
            "XDG_DATA_DIRS",
            "/run/current-system/sw/share:/var/lib/flatpak/exports/share",
        ));
        Places { config, data }
    }

    /// Every mimeapps.list in the order the specification reads them
    fn lists(&self) -> Vec<PathBuf> {
        self.config
            .iter()
            .map(|d| d.join("mimeapps.list"))
            .chain(
                self.data
                    .iter()
                    .map(|d| d.join("applications/mimeapps.list")),
            )
            .collect()
    }
}

/// The value of `key` in the [Desktop Entry] group of a desktop file
fn entry_value<'a>(text: &'a str, key: &str) -> Option<&'a str> {
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Desktop Entry]";
            continue;
        }
        if inside
            && let Some((k, v)) = line.split_once('=')
            && k.trim() == key
        {
            return Some(v.trim());
        }
    }
    None
}

/// One desktop file as an app, None when it is hidden or opens no file type
pub fn parse_app(id: &str, text: &str) -> Option<App> {
    if entry_value(text, "Hidden") == Some("true")
        || entry_value(text, "Type") != Some("Application")
    {
        return None;
    }
    let types: Vec<String> = entry_value(text, "MimeType")?
        .split(';')
        .filter(|t| !t.is_empty())
        .map(String::from)
        .collect();
    Some(App {
        id: id.to_string(),
        name: entry_value(text, "Name").unwrap_or(id).to_string(),
        icon: entry_value(text, "Icon").unwrap_or("").to_string(),
        types,
    })
}

/// Every app in the applications folders; the first folder that has an id wins
fn apps(places: &Places) -> Vec<App> {
    let mut found: BTreeMap<String, Option<App>> = BTreeMap::new();
    for dir in &places.data {
        let dir = dir.join("applications");
        let mut stack = vec![(dir.clone(), String::new())];
        while let Some((folder, prefix)) = stack.pop() {
            let Ok(entries) = fs::read_dir(&folder) else {
                continue;
            };
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                let path = entry.path();
                if path.is_dir() {
                    stack.push((path, format!("{prefix}{name}-")));
                } else if let Some(stem) = name.strip_suffix(".desktop") {
                    let id = format!("{prefix}{stem}.desktop");
                    if found.contains_key(&id) {
                        continue;
                    }
                    let app = fs::read_to_string(&path)
                        .ok()
                        .and_then(|t| parse_app(&id, &t));
                    found.insert(id, app);
                }
            }
        }
    }
    found.into_values().flatten().collect()
}

/// The [Default Applications] of one mimeapps.list: type to the desktop ids, in order
pub fn defaults_in(text: &str) -> BTreeMap<String, Vec<String>> {
    let mut out = BTreeMap::new();
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Default Applications]";
            continue;
        }
        if inside && let Some((k, v)) = line.split_once('=') {
            let ids = v
                .split(';')
                .filter(|i| !i.is_empty())
                .map(String::from)
                .collect();
            out.insert(k.trim().to_string(), ids);
        }
    }
    out
}

/// The app that opens `mime`: the first default of the lists that is installed and can do it
fn chosen(places: &Places, apps: &[App], mime: &str) -> Option<String> {
    for list in places.lists() {
        let Ok(text) = fs::read_to_string(&list) else {
            continue;
        };
        if let Some(ids) = defaults_in(&text).get(mime) {
            for id in ids {
                if apps.iter().any(|a| &a.id == id) {
                    return Some(id.clone());
                }
            }
        }
    }
    apps.iter()
        .find(|a| a.types.iter().any(|t| t == mime))
        .map(|a| a.id.clone())
}

/// mimeapps.list with every type in `mimes` opened by `app`; the rest of the file as it was
pub fn with_default(text: &str, mimes: &[&str], app: &str) -> String {
    let mut out = Vec::new();
    let mut inside = false;
    let mut seen_group = false;
    let write_ours = |out: &mut Vec<String>| {
        for mime in mimes {
            out.push(format!("{mime}={app};"));
        }
    };
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            inside = trimmed == "[Default Applications]";
            out.push(line.to_string());
            if inside {
                seen_group = true;
                write_ours(&mut out);
            }
            continue;
        }
        if inside
            && let Some((k, _)) = trimmed.split_once('=')
            && mimes.contains(&k.trim())
        {
            continue;
        }
        out.push(line.to_string());
    }
    if !seen_group {
        if out.last().is_some_and(|l| !l.trim().is_empty()) {
            out.push(String::new());
        }
        out.push("[Default Applications]".to_string());
        write_ours(&mut out);
    }
    out.join("\n") + "\n"
}

fn kind(name: &str) -> Result<(&'static str, &'static [&'static str]), String> {
    KINDS
        .iter()
        .find(|(k, _, _)| *k == name)
        .map(|(_, title, mimes)| (*title, *mimes))
        .ok_or_else(|| format!("no kind \"{name}\": {}", KINDS.map(|k| k.0).join(", ")))
}

fn list(places: &Places) -> Value {
    let all = apps(places);
    let kinds: Vec<Value> = KINDS
        .iter()
        .map(|(name, title, mimes)| {
            let able: Vec<Value> = all
                .iter()
                .filter(|a| a.types.iter().any(|t| mimes.contains(&t.as_str())))
                .map(|a| json!({ "id": a.id, "name": a.name, "icon": a.icon }))
                .collect();
            json!({
                "kind": name,
                "title": title,
                "current": chosen(places, &all, mimes[0]),
                "apps": able,
            })
        })
        .collect();
    Value::Array(kinds)
}

fn set(places: &Places, name: &str, app: &str) -> Result<(), String> {
    let (_, mimes) = kind(name)?;
    if !apps(places).iter().any(|a| a.id == app) {
        return Err(format!("no app {app} is installed"));
    }
    let file = config_home().join("mimeapps.list");
    let text = fs::read_to_string(&file).unwrap_or_default();
    write(&file, &with_default(&text, mimes, app))
}

fn write(file: &Path, text: &str) -> Result<(), String> {
    if let Some(dir) = file.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }
    let tmp = file.with_extension("list.tmp");
    fs::write(&tmp, text)
        .and_then(|()| fs::rename(&tmp, file))
        .map_err(|e| format!("cannot write {}: {e}", file.display()))
}

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    let places = Places::from_env();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        [] | ["list"] => {
            println!("{}", list(&places));
            Ok(ExitCode::SUCCESS)
        }
        ["set", name, app] => {
            set(&places, name, app)?;
            Ok(ExitCode::SUCCESS)
        }
        ["run", name, rest @ ..] => {
            let (title, mimes) = kind(name)?;
            let app = chosen(&places, &apps(&places), mimes[0])
                .ok_or_else(|| format!("no app is set for {}", title.to_lowercase()))?;
            let mut argv = vec!["app", "--", app.as_str()];
            argv.extend(rest);
            become_it("uwsm", &argv)
        }
        _ => Ok(crate::usage(
            call,
            "list | set KIND APP | run KIND [ARGUMENTS]",
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_app_from_its_desktop_file() {
        let text = "[Desktop Entry]\nType=Application\nName=Zen\nIcon=zen\nMimeType=text/html;x-scheme-handler/https;\n\n[Desktop Action new]\nName=New window\n";
        let app = parse_app("zen-beta.desktop", text).unwrap();
        assert_eq!(app.name, "Zen");
        assert_eq!(app.types, ["text/html", "x-scheme-handler/https"]);
        assert!(parse_app("x.desktop", "[Desktop Entry]\nType=Application\nName=X\n").is_none());
        assert!(
            parse_app(
                "x.desktop",
                "[Desktop Entry]\nType=Application\nHidden=true\nMimeType=text/plain;\n"
            )
            .is_none()
        );
    }

    #[test]
    fn the_defaults_of_a_list() {
        let text = "[Added Associations]\ntext/plain=a.desktop;\n[Default Applications]\ntext/plain=b.desktop;c.desktop;\n";
        assert_eq!(defaults_in(text)["text/plain"], ["b.desktop", "c.desktop"]);
    }

    #[test]
    fn setting_a_kind_keeps_the_rest() {
        let before = "[Added Associations]\nimage/png=loupe.desktop;\n\n[Default Applications]\ntext/html=old.desktop;\nimage/png=loupe.desktop;\n";
        let after = with_default(
            before,
            &["text/html", "x-scheme-handler/https"],
            "new.desktop",
        );
        let defaults = defaults_in(&after);
        assert_eq!(defaults["text/html"], ["new.desktop"]);
        assert_eq!(defaults["x-scheme-handler/https"], ["new.desktop"]);
        assert_eq!(defaults["image/png"], ["loupe.desktop"]);
        assert!(after.contains("[Added Associations]\nimage/png=loupe.desktop;"));
        assert_eq!(after.matches("text/html=").count(), 1);
        // A new file gets the group
        let fresh = with_default("", &["inode/directory"], "files.desktop");
        assert_eq!(
            fresh,
            "[Default Applications]\ninode/directory=files.desktop;\n"
        );
    }

    #[test]
    fn every_kind_is_known() {
        assert!(kind("browser").is_ok());
        assert!(kind("toaster").is_err());
        let names: Vec<&str> = KINDS.iter().map(|k| k.0).collect();
        let mut unique = names.clone();
        unique.sort_unstable();
        unique.dedup();
        assert_eq!(names.len(), unique.len());
    }
}
