//! The package index: every package of the system's nixpkgs with its name, version and
//! description, read once from `nix-env -qaP --json --meta` after each update, and searched with
//! the same matcher as Search.

use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config as MatcherConfig, Matcher, Utf32Str};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::Path;

/// One package as the Store shows it
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Package {
    /// The attribute path, what apps.json stores ("firefox", "kdePackages.kate")
    pub attr: String,
    pub pname: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub unfree: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub homepage: Option<String>,
}

/// The file the index service writes
#[derive(Serialize, Deserialize, Debug, PartialEq)]
pub struct Index {
    /// Where the packages came from (the nixpkgs path): an index of another source is rebuilt
    pub source: String,
    pub packages: Vec<Package>,
}

#[derive(Deserialize)]
struct RawPackage {
    #[serde(default)]
    pname: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    meta: RawMeta,
}

#[derive(Deserialize, Default)]
struct RawMeta {
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    homepage: Option<serde_json::Value>,
    #[serde(default)]
    unfree: Option<bool>,
    #[serde(default)]
    broken: Option<bool>,
    #[serde(default)]
    available: Option<bool>,
    #[serde(default)]
    license: Option<serde_json::Value>,
}

/// A license is free unless it says `"free": false`; a list is free when every entry is
fn license_unfree(license: &serde_json::Value) -> bool {
    match license {
        serde_json::Value::Object(map) => map.get("free").and_then(|f| f.as_bool()) == Some(false),
        serde_json::Value::Array(list) => list.iter().any(license_unfree),
        _ => false,
    }
}

/// The package list a NixOS channel publishes (`packages.json.br`, unpacked): the same entries
/// as nix-env, under `packages`
#[derive(Deserialize)]
struct ChannelList {
    #[serde(default)]
    packages: Option<BTreeMap<String, RawPackage>>,
}

/// Reads the package list of a channel or the output of `nix-env -qaP --json --meta`. Broken and
/// unavailable packages are left out; the rest is sorted by attribute.
pub fn parse(mut reader: impl Read, source: &str) -> Result<Index, String> {
    let mut text = String::new();
    reader
        .read_to_string(&mut text)
        .map_err(|e| format!("cannot read the package list: {e}"))?;
    let raw: BTreeMap<String, RawPackage> = match serde_json::from_str::<ChannelList>(&text) {
        Ok(ChannelList {
            packages: Some(packages),
        }) => packages,
        _ => serde_json::from_str(&text)
            .map_err(|e| format!("not a package list of nixpkgs: {e}"))?,
    };
    let packages = raw
        .into_iter()
        .filter(|(_, p)| p.meta.broken != Some(true) && p.meta.available != Some(false))
        .map(|(attr, p)| {
            let pname = p
                .pname
                .or_else(|| p.name.clone())
                .unwrap_or_else(|| attr.rsplit('.').next().unwrap_or(&attr).to_string());
            let homepage = match p.meta.homepage {
                Some(serde_json::Value::String(s)) => Some(s),
                Some(serde_json::Value::Array(list)) => {
                    list.first().and_then(|v| v.as_str()).map(String::from)
                }
                _ => None,
            };
            Package {
                pname,
                version: p.version.unwrap_or_default(),
                description: p.meta.description.unwrap_or_default().trim().to_string(),
                unfree: p.meta.unfree.unwrap_or(false)
                    || p.meta.license.as_ref().is_some_and(license_unfree),
                homepage,
                attr,
            }
        })
        .collect();
    Ok(Index {
        source: source.to_string(),
        packages,
    })
}

pub fn load(path: &Path) -> Result<Index, String> {
    let text =
        fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    serde_json::from_str(&text).map_err(|e| format!("{} is not an index: {e}", path.display()))
}

/// One search result
#[derive(Serialize, Debug, PartialEq)]
pub struct Hit<'a> {
    #[serde(flatten)]
    pub package: &'a Package,
    pub installed: bool,
    pub score: u32,
}

/// The packages that fit `text`, best first. The name counts fully, the attribute path a little
/// less, the description at a third; an exact name wins. Without text: the installed ones.
pub fn search<'a>(
    index: &'a Index,
    text: &str,
    installed: &HashSet<String>,
    limit: usize,
) -> Vec<Hit<'a>> {
    let text = text.trim();
    if text.is_empty() {
        return index
            .packages
            .iter()
            .filter(|p| installed.contains(&p.attr))
            .map(|p| Hit {
                package: p,
                installed: true,
                score: 0,
            })
            .take(limit)
            .collect();
    }
    let mut config = MatcherConfig::DEFAULT;
    config.prefer_prefix = true;
    let mut matcher = Matcher::new(config);
    let pattern = Pattern::parse(text, CaseMatching::Ignore, Normalization::Smart);
    let words = Pattern::parse(text, CaseMatching::Ignore, Normalization::Smart);
    let lower = text.to_lowercase();
    let mut buf = Vec::new();
    let mut hits: Vec<Hit> = index
        .packages
        .iter()
        .filter_map(|p| {
            let name = pattern.score(Utf32Str::new(&p.pname, &mut buf), &mut matcher);
            let attr = pattern
                .score(Utf32Str::new(&p.attr, &mut buf), &mut matcher)
                .map(|s| s * 4 / 5);
            let description = if p.description.is_empty() {
                None
            } else {
                words
                    .score(Utf32Str::new(&p.description, &mut buf), &mut matcher)
                    .map(|s| s / 3)
            };
            let mut score = name.max(attr).max(description)?;
            if p.pname.to_lowercase() == lower {
                score += 1000;
            }
            Some(Hit {
                package: p,
                installed: installed.contains(&p.attr),
                score,
            })
        })
        .collect();
    hits.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then(a.package.pname.len().cmp(&b.package.pname.len()))
            .then(a.package.attr.cmp(&b.package.attr))
    });
    hits.truncate(limit);
    hits
}

/// The attributes in apps.json
pub fn installed(apps_file: &Path) -> HashSet<String> {
    #[derive(Deserialize)]
    struct Apps {
        #[serde(default)]
        packages: Vec<Entry>,
    }
    #[derive(Deserialize)]
    struct Entry {
        attr: String,
    }
    fs::read_to_string(apps_file)
        .ok()
        .and_then(|t| serde_json::from_str::<Apps>(&t).ok())
        .map(|a| a.packages.into_iter().map(|e| e.attr).collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn fixture() -> Index {
        let file = fs::File::open(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/fixtures/nix-env.json"
        ))
        .unwrap();
        parse(file, "/nix/store/x-source").unwrap()
    }

    #[test]
    fn reads_nix_env_and_leaves_broken_ones_out() {
        let index = fixture();
        let attrs: Vec<&str> = index.packages.iter().map(|p| p.attr.as_str()).collect();
        assert_eq!(
            attrs,
            [
                "discord",
                "firefox",
                "firefox-esr",
                "gimp",
                "kdePackages.kate",
                "nodesc",
                "spotify"
            ]
        );
        let get = |a: &str| index.packages.iter().find(|p| p.attr == a).unwrap();
        assert!(get("spotify").unfree);
        assert!(get("discord").unfree, "license free = false");
        assert!(!get("gimp").unfree, "a list of free licenses");
        assert_eq!(
            get("firefox").homepage.as_deref(),
            Some("https://www.mozilla.org/firefox/")
        );
        assert_eq!(get("kdePackages.kate").pname, "kate");
        assert_eq!(get("nodesc").description, "");
        assert!(
            parse("[1, 2]".as_bytes(), "x")
                .unwrap_err()
                .contains("not a package list")
        );
    }

    #[test]
    fn reads_the_list_of_a_channel_too() {
        let text = fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/fixtures/nix-env.json"
        ))
        .unwrap();
        let channel = format!("{{\"version\": 2, \"packages\": {text}}}");
        let index = parse(
            channel.as_bytes(),
            "https://channels.example/packages.json.br",
        )
        .unwrap();
        assert_eq!(index.packages.len(), fixture().packages.len());
        assert_eq!(index.source, "https://channels.example/packages.json.br");
    }

    #[test]
    fn the_exact_name_comes_first() {
        let index = fixture();
        let none = HashSet::new();
        let hits = search(&index, "firefox", &none, 10);
        assert_eq!(hits[0].package.attr, "firefox");
        assert_eq!(hits[1].package.attr, "firefox-esr");
        assert_eq!(
            search(&index, "kate", &none, 10)[0].package.attr,
            "kdePackages.kate"
        );
        // The description finds it, below any name
        let hits = search(&index, "image manipulation", &none, 10);
        assert_eq!(hits[0].package.attr, "gimp");
        assert!(search(&index, "zzzzqqq", &none, 10).is_empty());
        assert_eq!(search(&index, "e", &none, 2).len(), 2);
    }

    #[test]
    fn installed_ones_are_marked_and_listed_without_text() {
        let index = fixture();
        let dir = std::env::temp_dir().join(format!("store-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let apps = dir.join("apps.json");
        fs::write(&apps, r#"{"version": 1, "packages": [{"attr": "gimp"}, {"attr": "spotify", "unfree": "spotify"}]}"#).unwrap();
        let installed = installed(&apps);
        assert_eq!(installed.len(), 2);
        let hits = search(&index, "", &installed, 10);
        assert_eq!(
            hits.iter()
                .map(|h| h.package.attr.as_str())
                .collect::<Vec<_>>(),
            ["gimp", "spotify"]
        );
        assert!(search(&index, "gimp", &installed, 10)[0].installed);
        assert!(super::installed(&dir.join("missing.json")).is_empty());
    }

    #[test]
    fn the_index_file_round_trips() {
        let index = fixture();
        let text = serde_json::to_string(&index).unwrap();
        let back: Index = serde_json::from_str(&text).unwrap();
        assert_eq!(back, index);
        assert!(
            !text.contains("\"unfree\":false"),
            "false is left out to keep the file small"
        );
    }
}
