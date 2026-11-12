//! Own keys: what a person changed in Settings › Hotkeys. They are kept in
//! `<config>/<id>/keys.json` (binding id to keys as the cheat sheet writes them, "" for none)
//! and written as `<config>/<id>/keys.lua`, which Hyprland reads after the keys of Strix: the
//! old combination is unbound, the new one bound to the same dispatcher.

use crate::bindings::{self, Bound, Hotkey};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

pub type Own = BTreeMap<String, String>;

pub fn load(dir: &Path) -> Own {
    fs::read_to_string(dir.join("keys.json"))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default()
}

/// The combination each binding has with the own keys applied, None when it is off
fn effective(bound: &[Bound], own: &Own) -> Vec<(String, Option<String>)> {
    bound
        .iter()
        .map(|b| {
            let combo = match own.get(&b.id) {
                Some(keys) if keys.is_empty() => None,
                Some(keys) => bindings::single_combo(keys).ok(),
                None => Some(b.combo.clone()),
            };
            (b.id.clone(), combo)
        })
        .collect()
}

/// keys.lua: every changed binding unbound first, then bound again where it has keys
pub fn lua(bound: &[Bound], own: &Own) -> String {
    let mut out = String::from(
        "-- Own keys from Settings › Hotkeys (keys.json beside this file). Do not edit: change\n\
         -- them in Settings, or put your own lines in hyprland.lua beside this file.\n\n",
    );
    let changed: Vec<&Bound> = bound.iter().filter(|b| own.contains_key(&b.id)).collect();
    for b in &changed {
        out.push_str(&format!("hl.unbind({})\n", bindings::lua_string(&b.combo)));
    }
    for b in &changed {
        if let Some(keys) = own.get(&b.id).filter(|k| !k.is_empty())
            && let Ok(combo) = bindings::single_combo(keys)
        {
            out.push_str(&bindings::bind_line(b, &combo));
        }
    }
    out
}

fn write(dir: &Path, name: &str, text: &str) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let path = dir.join(name);
    let tmp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    fs::write(&tmp, text)
        .and_then(|()| fs::rename(&tmp, &path))
        .map_err(|e| format!("cannot write {}: {e}", path.display()))
}

/// Gives binding `id` other keys (Some("Super Shift B")), none (Some("")), or its own back (None)
pub fn set(bound: &[Bound], dir: &Path, id: &str, keys: Option<&str>) -> Result<Own, String> {
    let combos = bound.iter().filter(|b| b.id == id).count();
    if combos == 0 {
        return Err(format!("there is no key \"{id}\" to change"));
    }
    if combos > 1 {
        return Err(format!(
            "the keys of \"{id}\" come as a set and cannot be changed one by one"
        ));
    }
    let mut own = load(dir);
    match keys.map(str::trim) {
        None => {
            own.remove(id);
        }
        Some("") => {
            own.insert(id.to_string(), String::new());
        }
        Some(keys) => {
            let combo = bindings::single_combo(keys)?;
            let original = &bound.iter().find(|b| b.id == id).expect("counted").combo;
            if combo.eq_ignore_ascii_case(original) {
                own.remove(id);
            } else {
                for (other, taken) in effective(bound, &own) {
                    if other != id && taken.is_some_and(|t| t.eq_ignore_ascii_case(&combo)) {
                        let title = &bound
                            .iter()
                            .find(|b| b.id == other)
                            .expect("listed")
                            .description;
                        return Err(format!("{keys} is already \"{title}\""));
                    }
                }
                own.insert(id.to_string(), keys.to_string());
            }
        }
    }
    let json = serde_json::to_string_pretty(&own).map_err(|e| e.to_string())?;
    write(dir, "keys.json", &(json + "\n"))?;
    write(dir, "keys.lua", &lua(bound, &own))?;
    Ok(own)
}

/// The cheat sheet with the own keys
pub fn apply(rows: &mut [Hotkey], own: &Own) {
    for row in rows {
        if let Some(keys) = own.get(&row.id) {
            row.keys = keys.clone();
            row.changed = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bound(id: &str, combo: &str) -> Bound {
        Bound {
            id: id.into(),
            combo: combo.into(),
            dispatcher: format!("hl.dsp.exec_cmd(\"{id}\")"),
            description: id.replace('-', " "),
            repeat: false,
            locked: false,
        }
    }

    fn all() -> Vec<Bound> {
        vec![
            bound("all-hotkeys", "SUPER + K"),
            bound("terminal", "SUPER + Return"),
            bound("workspace", "SUPER + 1"),
            bound("workspace", "SUPER + 2"),
        ]
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("keys-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn change_a_key_and_take_it_back() {
        let dir = scratch("change");
        let own = set(&all(), &dir, "all-hotkeys", Some("Super H")).unwrap();
        assert_eq!(own.get("all-hotkeys").map(String::as_str), Some("Super H"));
        let text = fs::read_to_string(dir.join("keys.lua")).unwrap();
        assert!(text.contains("hl.unbind(\"SUPER + K\")\n"), "{text}");
        assert!(
            text.contains("hl.bind(\"SUPER + H\", hl.dsp.exec_cmd(\"all-hotkeys\")"),
            "{text}"
        );
        assert_eq!(load(&dir), own);

        // Off: unbound, not bound again
        set(&all(), &dir, "terminal", Some("")).unwrap();
        let text = fs::read_to_string(dir.join("keys.lua")).unwrap();
        assert!(text.contains("hl.unbind(\"SUPER + Return\")"));
        assert!(!text.contains("hl.bind(\"SUPER + Return\""));

        // Its own keys again
        let own = set(&all(), &dir, "all-hotkeys", None).unwrap();
        assert!(!own.contains_key("all-hotkeys"));
        let own = set(&all(), &dir, "terminal", Some("Super Return")).unwrap();
        assert!(own.is_empty(), "the original keys need no entry");
    }

    #[test]
    fn refused() {
        let dir = scratch("refused");
        let e = set(&all(), &dir, "terminal", Some("Super K")).unwrap_err();
        assert!(e.contains("already \"all hotkeys\""), "{e}");
        assert!(
            set(&all(), &dir, "workspace", Some("Super W"))
                .unwrap_err()
                .contains("as a set")
        );
        assert!(
            set(&all(), &dir, "nope", Some("Super W"))
                .unwrap_err()
                .contains("no key")
        );
        assert!(set(&all(), &dir, "terminal", Some("Super Banana")).is_err());
        assert!(!dir.join("keys.json").exists());
        // A key set free elsewhere can be taken
        set(&all(), &dir, "all-hotkeys", Some("Super H")).unwrap();
        set(&all(), &dir, "terminal", Some("Super K")).unwrap();
    }

    #[test]
    fn the_cheat_sheet_shows_own_keys() {
        let mut rows = vec![Hotkey {
            id: "terminal".into(),
            group: "Apps".into(),
            title: "Terminal".into(),
            keys: "Super Return".into(),
            target: "Ghostty".into(),
            scope: None,
            changed: false,
        }];
        let own: Own = [("terminal".to_string(), "Super T".to_string())].into();
        apply(&mut rows, &own);
        assert_eq!(rows[0].keys, "Super T");
        assert!(rows[0].changed);
    }
}
