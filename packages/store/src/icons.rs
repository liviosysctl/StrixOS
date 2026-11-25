//! The icons of apps: nixpkgs has none, so they come from icon folders (the apps of Papirus,
//! then the icons the installed apps bring along). A package is looked up by the icon the
//! catalog names, then by its own names; many icons are named the reverse-domain way
//! (com.mitchellh.ghostty), so their last part counts too. Without a hit the window draws a
//! letter.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// The endings of package names that an icon does not carry
const SUFFIXES: [&str; 9] = [
    "-bin",
    "-unwrapped",
    "-desktop",
    "-wayland",
    "-beta",
    "-stable",
    "-git",
    "-editor",
    "-app",
];

#[derive(Default)]
pub struct Icons {
    /// By the file's name without .svg or .png, lowercase; the first folder wins
    exact: HashMap<String, PathBuf>,
    /// By the last part of a reverse-domain name (ghostty for com.mitchellh.ghostty)
    tail: HashMap<String, PathBuf>,
}

impl Icons {
    /// Reads the names in every folder; a folder that is not there is left out
    pub fn scan(dirs: &[PathBuf]) -> Icons {
        let mut icons = Icons::default();
        for dir in dirs {
            let Ok(entries) = fs::read_dir(dir) else {
                continue;
            };
            let mut files: Vec<(String, PathBuf)> = entries
                .flatten()
                .filter_map(|entry| {
                    let path = entry.path();
                    let ext = path.extension()?.to_str()?;
                    if ext != "svg" && ext != "png" {
                        return None;
                    }
                    let stem = path.file_stem()?.to_str()?.to_lowercase();
                    Some((stem, path))
                })
                .collect();
            // The same order on every machine: svg before png, then by name
            files.sort();
            for (stem, path) in files {
                if let Some((_, last)) = stem.rsplit_once('.')
                    && stem.matches('.').count() >= 2
                {
                    icons.tail.entry(last.to_string()).or_insert(path.clone());
                }
                icons.exact.entry(stem).or_insert(path);
            }
        }
        icons
    }

    /// The icon of a package: `named` (from the catalog) first, then the package's names
    pub fn find(&self, named: Option<&str>, pname: &str, attr: &str) -> Option<&Path> {
        let last = attr.rsplit('.').next().unwrap_or(attr);
        let mut names: Vec<String> = Vec::new();
        names.extend(named.map(str::to_lowercase));
        for name in [pname, last] {
            let name = name.to_lowercase();
            if let Some(short) = SUFFIXES.iter().find_map(|s| name.strip_suffix(s)) {
                names.push(name.clone());
                names.push(short.to_string());
            } else {
                names.push(name);
            }
        }
        // A name of the catalog is meant exactly; the package's own may be a reverse-domain one
        if let Some(path) = named.and_then(|n| self.exact.get(&n.to_lowercase())) {
            return Some(path);
        }
        names
            .iter()
            .find_map(|n| self.exact.get(n).or_else(|| self.tail.get(n)))
            .map(PathBuf::as_path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str, files: &[&str]) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("store-icons-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for file in files {
            fs::write(dir.join(file), "<svg/>").unwrap();
        }
        dir
    }

    #[test]
    fn finds_icons_by_every_name() {
        let papirus = folder(
            "papirus",
            &[
                "gimp.svg",
                "com.mitchellh.ghostty.svg",
                "dev.zed.Zed.svg",
                "zen-browser.svg",
                "libreoffice-main.svg",
                "readme.txt",
            ],
        );
        let own = folder("own", &["gimp.png", "kate.png"]);
        let icons = Icons::scan(&[papirus.clone(), own.clone(), papirus.join("missing")]);
        let name = |named: Option<&str>, pname: &str, attr: &str| {
            icons.find(named, pname, attr).map(|p| {
                p.strip_prefix(p.parent().unwrap().parent().unwrap())
                    .unwrap()
                    .to_owned()
            })
        };
        let papirus_name = papirus.file_name().unwrap();
        let own_name = own.file_name().unwrap();
        // The first folder wins
        assert_eq!(
            name(None, "gimp", "gimp"),
            Some(Path::new(papirus_name).join("gimp.svg"))
        );
        // The last part of a reverse-domain name
        assert_eq!(
            name(None, "ghostty", "ghostty"),
            Some(Path::new(papirus_name).join("com.mitchellh.ghostty.svg"))
        );
        // A known ending left out: zed-editor finds zed
        assert_eq!(
            name(None, "zed-editor", "zed-editor"),
            Some(Path::new(papirus_name).join("dev.zed.Zed.svg"))
        );
        // The catalog's name first, then the attribute's last part
        assert_eq!(
            name(Some("zen-browser"), "zen-beta", "zen-beta"),
            Some(Path::new(papirus_name).join("zen-browser.svg"))
        );
        assert_eq!(
            name(Some("libreoffice-main"), "libreoffice", "libreoffice"),
            Some(Path::new(papirus_name).join("libreoffice-main.svg"))
        );
        assert_eq!(
            name(None, "kate", "kdePackages.kate"),
            Some(Path::new(own_name).join("kate.png"))
        );
        assert_eq!(name(None, "nothing", "nothing"), None);
        assert!(Icons::scan(&[]).find(None, "gimp", "gimp").is_none());
    }
}
