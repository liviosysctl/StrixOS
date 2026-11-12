//! The Hyprland keybindings, made from `menu.toml`: every action with `keys`, and the
//! `[[binding]]` entries for what is not an action of Search (windows, workspaces, apps).
//! One file for Search, the cheat sheet and Hyprland, so a key shown is a key bound.
//!
//! Keys are written as on the cheat sheet: modifiers first, then one key, separated by spaces.
//! Three short forms stand for several bindings:
//!
//! | Written | Bindings | `{key}` becomes |
//! |---|---|---|
//! | `Super 1–9` | Super 1 to Super 9 | `1` to `9` |
//! | `Super Arrows` | the four arrow keys | `left`, `right`, `up`, `down` |
//! | `Super = -` | one per key after the modifiers | the Hyprland name of the key |
//!
//! A binding does one of: `run` (a command line, started with `uwsm app` so it gets its own
//! scope) or `hypr` (a Hyprland Lua dispatcher such as `hl.dsp.window.close()`, a list with one
//! per key for the third form, `{key}` replaced).

use std::collections::BTreeMap;
use std::path::Path;

use serde::Deserialize;

use crate::sources::read_toml;

#[derive(Deserialize)]
struct MenuFile {
    #[serde(default)]
    group: Vec<Group>,
    #[serde(default)]
    action: Vec<Action>,
    #[serde(default)]
    binding: Vec<Binding>,
}

#[derive(Deserialize)]
struct Group {
    id: String,
    title: String,
    parent: Option<String>,
}

/// The fields of an action this needs; the rest is read by `sources::menu`.
#[derive(Deserialize)]
struct Action {
    id: String,
    title: String,
    group: String,
    keys: Option<String>,
    run: Option<Vec<String>>,
    #[serde(default)]
    terminal: bool,
    scope: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Binding {
    pub id: String,
    pub title: String,
    /// The group on the cheat sheet
    pub group: String,
    /// What it acts on, the second line on the cheat sheet
    pub target: Option<String>,
    pub keys: String,
    pub run: Option<Vec<String>>,
    pub hypr: Option<Hypr>,
    /// Held down repeats (resizing)
    #[serde(default)]
    pub repeat: bool,
    /// Works on the lock screen too (volume, brightness)
    #[serde(default)]
    pub locked: bool,
}

#[derive(Deserialize, Clone)]
#[serde(untagged)]
pub enum Hypr {
    One(String),
    Each(Vec<String>),
}

/// One bound key combination
#[derive(Debug, PartialEq)]
pub struct Bound {
    pub id: String,
    /// "SUPER + SHIFT + RETURN"
    pub combo: String,
    /// A Lua expression giving the dispatcher
    pub dispatcher: String,
    pub description: String,
    pub repeat: bool,
    pub locked: bool,
}

const MODIFIERS: [(&str, &str); 4] = [
    ("Super", "SUPER"),
    ("Shift", "SHIFT"),
    ("Ctrl", "CTRL"),
    ("Alt", "ALT"),
];

/// The Hyprland name of one key as written on the cheat sheet
fn key_name(key: &str) -> Option<String> {
    let named = match key {
        "Return" => "Return",
        "Space" => "space",
        "Print" => "Print",
        "Escape" => "Escape",
        "Tab" => "Tab",
        "=" => "equal",
        "-" => "minus",
        "Left" => "left",
        "Right" => "right",
        "Up" => "up",
        "Down" => "down",
        // The keys of a laptop or a media keyboard, as the cheat sheet writes them
        "VolumeUp" => "XF86AudioRaiseVolume",
        "VolumeDown" => "XF86AudioLowerVolume",
        "Mute" => "XF86AudioMute",
        "MicMute" => "XF86AudioMicMute",
        "BrightnessUp" => "XF86MonBrightnessUp",
        "BrightnessDown" => "XF86MonBrightnessDown",
        "Play" => "XF86AudioPlay",
        "Next" => "XF86AudioNext",
        "Previous" => "XF86AudioPrev",
        _ => "",
    };
    if !named.is_empty() {
        return Some(named.to_string());
    }
    let mut chars = key.chars();
    match (chars.next(), chars.next()) {
        (Some(c), None) if c.is_ascii_uppercase() || c.is_ascii_digit() => Some(c.to_string()),
        _ => {
            // F1 to F12
            let n = key.strip_prefix('F')?.parse::<u8>().ok()?;
            (1..=12).contains(&n).then(|| key.to_string())
        }
    }
}

/// "Super Shift 1–9" into the modifier part and the keys it stands for
pub fn expand(keys: &str) -> Result<(String, Vec<String>), String> {
    let mut mods = Vec::new();
    let mut rest = Vec::new();
    for word in keys.split_whitespace() {
        match MODIFIERS.iter().find(|(name, _)| *name == word) {
            Some((_, hypr)) if rest.is_empty() => {
                if mods.contains(hypr) {
                    return Err(format!("\"{keys}\": {word} twice"));
                }
                mods.push(*hypr);
            }
            Some(_) => return Err(format!("\"{keys}\": modifiers come before the key")),
            None => rest.push(word),
        }
    }
    let keys_out: Vec<String> = match rest.as_slice() {
        [] => return Err(format!("\"{keys}\" has no key")),
        ["1–9"] | ["1-9"] => (1..=9).map(|n| n.to_string()).collect(),
        ["Arrows"] => ["left", "right", "up", "down"].map(String::from).to_vec(),
        words => words
            .iter()
            .map(|w| key_name(w).ok_or_else(|| format!("\"{keys}\": unknown key \"{w}\"")))
            .collect::<Result<_, _>>()?,
    };
    Ok((mods.join(" + "), keys_out))
}

fn combo(mods: &str, key: &str) -> String {
    if mods.is_empty() {
        key.to_string()
    } else {
        format!("{mods} + {key}")
    }
}

/// A Lua string literal
pub fn lua_string(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            c if c.is_control() => out.push_str(&format!("\\{}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// One argv as a shell command line: words with anything but safe characters in single quotes
pub fn shell_line(argv: &[String]) -> String {
    argv.iter()
        .map(|w| {
            if !w.is_empty()
                && w.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "-_./:=@%+,".contains(c))
            {
                w.clone()
            } else {
                format!("'{}'", w.replace('\'', "'\\''"))
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// A command line for Hyprland: long-running programs through `uwsm app`, calls into the shell
/// and other short commands as they are
fn exec(argv: &[String]) -> String {
    let short = matches!(
        argv.first().map(String::as_str),
        Some("qs" | "hyprctl" | "loginctl" | "systemctl" | "wpctl" | "brightnessctl" | "playerctl")
    );
    let line = if short {
        shell_line(argv)
    } else {
        format!("uwsm app -- {}", shell_line(argv))
    };
    format!("hl.dsp.exec_cmd({})", lua_string(&line))
}

/// Every binding of the menu file, in file order: the actions first, then `[[binding]]`.
/// Problems (unknown keys, one combination twice, a binding without anything to do) are errors.
pub fn read(path: &Path, distro: &str) -> Result<Vec<Bound>, String> {
    let file: MenuFile = read_toml(path)?;
    let fill = |argv: &[String]| -> Vec<String> {
        argv.iter().map(|w| w.replace("{id}", distro)).collect()
    };
    let mut out = Vec::new();
    let mut problems = Vec::new();

    for a in &file.action {
        let Some(keys) = &a.keys else { continue };
        // Keys that only work inside one view (the theme picker) are the view's own
        if a.scope.is_some() {
            continue;
        }
        let at = format!("action {}", a.id);
        let (mods, list) = match expand(keys) {
            Ok(x) => x,
            Err(e) => {
                problems.push(format!("{at}: {e}"));
                continue;
            }
        };
        match (&a.run, a.terminal) {
            (Some(argv), false) if list.len() == 1 => out.push(Bound {
                id: a.id.clone(),
                combo: combo(&mods, &list[0]),
                dispatcher: exec(&fill(argv)),
                description: a.title.clone(),
                repeat: false,
                locked: false,
            }),
            (Some(_), true) => {
                problems.push(format!("{at}: a key cannot start a terminal action yet"))
            }
            (Some(_), false) => problems.push(format!("{at}: an action has one key")),
            (None, _) => problems.push(format!("{at}: keys without run")),
        }
    }

    for b in &file.binding {
        let at = format!("binding {}", b.id);
        let (mods, list) = match expand(&b.keys) {
            Ok(x) => x,
            Err(e) => {
                problems.push(format!("{at}: {e}"));
                continue;
            }
        };
        let dispatchers: Vec<String> = match (&b.run, &b.hypr) {
            (Some(argv), None) if list.len() == 1 => vec![exec(&fill(argv))],
            (Some(_), None) => {
                problems.push(format!("{at}: run takes one key, use hypr for several"));
                continue;
            }
            (None, Some(Hypr::One(lua))) => list.iter().map(|k| lua.replace("{key}", k)).collect(),
            (None, Some(Hypr::Each(each))) if each.len() == list.len() => each
                .iter()
                .zip(&list)
                .map(|(lua, k)| lua.replace("{key}", k))
                .collect(),
            (None, Some(Hypr::Each(each))) => {
                problems.push(format!(
                    "{at}: {} dispatchers for {} keys",
                    each.len(),
                    list.len()
                ));
                continue;
            }
            (Some(_), Some(_)) => {
                problems.push(format!("{at}: run or hypr, not both"));
                continue;
            }
            (None, None) => {
                problems.push(format!("{at}: needs run or hypr"));
                continue;
            }
        };
        for (key, dispatcher) in list.iter().zip(dispatchers) {
            if !dispatcher.starts_with("hl.dsp.") {
                problems.push(format!("{at}: hypr must be an hl.dsp dispatcher"));
                break;
            }
            out.push(Bound {
                id: b.id.clone(),
                combo: combo(&mods, key),
                dispatcher,
                description: b.title.clone(),
                repeat: b.repeat,
                locked: b.locked,
            });
        }
    }

    let mut seen: BTreeMap<String, &str> = BTreeMap::new();
    for b in &out {
        // Hyprland does not tell Shift 1 from 1 with Shift; compare without case
        if let Some(other) = seen.insert(b.combo.to_lowercase(), &b.id) {
            problems.push(format!("{} is bound twice: {other} and {}", b.combo, b.id));
        }
    }
    if problems.is_empty() {
        Ok(out)
    } else {
        Err(problems.join("\n"))
    }
}

/// One row of the cheat sheet
#[derive(Debug, PartialEq, serde::Serialize)]
pub struct Hotkey {
    pub id: String,
    pub group: String,
    pub title: String,
    pub keys: String,
    pub target: String,
    /// Only inside one view, e.g. "picker"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
}

/// The groups of the cheat sheet, in this order; others follow in file order
const SHEET_ORDER: [&str; 8] = [
    "Learn",
    "Apps",
    "Windows",
    "Workspaces",
    "Style",
    "Capture",
    "Clipboard",
    "System",
];

/// Every key as the cheat sheet shows it: actions under the top group of the menu they sit in,
/// bindings under their own group, written as in the file ("Super 1–9" stays one row).
pub fn hotkeys(path: &Path) -> Result<Vec<Hotkey>, String> {
    let file: MenuFile = read_toml(path)?;
    let groups: BTreeMap<&str, &Group> = file.group.iter().map(|g| (g.id.as_str(), g)).collect();
    let actions: BTreeMap<&str, &Action> = file.action.iter().map(|a| (a.id.as_str(), a)).collect();
    // Up through actions and groups to the group at the top
    let top = |start: &str| -> String {
        let mut at = start;
        for _ in 0..16 {
            if let Some(a) = actions.get(at) {
                at = &a.group;
            } else if let Some(g) = groups.get(at) {
                match &g.parent {
                    Some(p) => at = p,
                    None => return g.title.clone(),
                }
            } else {
                break;
            }
        }
        at.to_string()
    };
    let mut rows: Vec<Hotkey> = file
        .action
        .iter()
        .filter_map(|a| {
            let keys = a.keys.clone()?;
            let group = top(&a.group);
            Some(Hotkey {
                id: a.id.clone(),
                target: group.clone(),
                group,
                title: a.title.clone(),
                keys,
                scope: a.scope.clone(),
            })
        })
        .chain(file.binding.iter().map(|b| Hotkey {
            id: b.id.clone(),
            group: b.group.clone(),
            title: b.title.clone(),
            keys: b.keys.clone(),
            target: b.target.clone().unwrap_or_default(),
            scope: None,
        }))
        .collect();
    let rank = |g: &str| {
        SHEET_ORDER
            .iter()
            .position(|o| *o == g)
            .unwrap_or(SHEET_ORDER.len())
    };
    rows.sort_by_key(|r| rank(&r.group));
    Ok(rows)
}

/// The Lua file Hyprland requires
pub fn lua(bound: &[Bound]) -> String {
    let mut out = String::from(
        "-- The keybindings, made by `strix-search bindings` from menu.toml. Do not edit:\n\
         -- change menu.toml, or add your own in strix.desktop.extraConfig.\n\n",
    );
    for b in bound {
        let mut opts = format!("description = {}", lua_string(&b.description));
        if b.locked {
            opts.push_str(", locked = true");
        }
        if b.repeat {
            opts.push_str(", repeating = true");
        }
        out.push_str(&format!(
            "hl.bind({}, {}, {{ {opts} }})\n",
            lua_string(&b.combo),
            b.dispatcher
        ));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_expand() {
        assert_eq!(
            expand("Super Return").unwrap(),
            ("SUPER".into(), vec!["Return".into()])
        );
        assert_eq!(expand("Super Shift 1–9").unwrap().1.len(), 9);
        assert_eq!(expand("Super Shift 1–9").unwrap().0, "SUPER + SHIFT");
        assert_eq!(
            expand("Super Arrows").unwrap().1,
            ["left", "right", "up", "down"]
        );
        assert_eq!(expand("Super = -").unwrap().1, ["equal", "minus"]);
        assert_eq!(
            expand("Print").unwrap(),
            (String::new(), vec!["Print".into()])
        );
        assert_eq!(expand("Ctrl Print").unwrap().0, "CTRL");
        assert_eq!(
            expand("Super Ctrl Space").unwrap(),
            ("SUPER + CTRL".into(), vec!["space".into()])
        );
        for bad in [
            "Super",
            "Super Super K",
            "K Super",
            "Super Hyper",
            "Super k",
            "Super F13",
        ] {
            assert!(expand(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn quoting() {
        assert_eq!(lua_string("a \"b\" \\c"), "\"a \\\"b\\\" \\\\c\"");
        assert_eq!(
            shell_line(&["qs".into(), "ipc".into(), "call".into()]),
            "qs ipc call"
        );
        assert_eq!(
            shell_line(&["echo".into(), "it's".into(), "".into()]),
            "echo 'it'\\''s' ''"
        );
    }

    fn file(text: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let p = std::env::temp_dir().join(format!(
            "bindings-{}-{}.toml",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&p, text).unwrap();
        p
    }

    #[test]
    fn actions_and_bindings() {
        let p = file(
            r#"
[[action]]
id = "lock"
title = "Lock"
group = "system"
keys = "Super Escape"
run = ["loginctl", "lock-session"]

[[action]]
id = "keep"
title = "Keep this theme"
group = "theme"
keys = "K"
scope = "picker"
run = ["qs", "ipc", "call", "theme", "keep"]

[[action]]
id = "update"
title = "Update"
group = "update"
run = ["{id}-update"]

[[binding]]
id = "terminal"
title = "Terminal"
group = "Apps"
keys = "Super Return"
run = ["ghostty"]

[[binding]]
id = "go"
title = "Go to workspace"
group = "Workspaces"
keys = "Super 1–9"
hypr = "hl.dsp.focus({ workspace = {key} })"

[[binding]]
id = "grow"
title = "Grow or shrink"
group = "Windows"
keys = "Super = -"
hypr = ["hl.dsp.window.resize({ x = 40, y = 40, relative = true })", "hl.dsp.window.resize({ x = -40, y = -40, relative = true })"]
repeat = true
"#,
        );
        let bound = read(&p, "strix").unwrap();
        assert_eq!(bound.len(), 1 + 1 + 9 + 2);
        assert_eq!(bound[0].combo, "SUPER + Escape");
        assert_eq!(
            bound[0].dispatcher,
            "hl.dsp.exec_cmd(\"loginctl lock-session\")"
        );
        assert_eq!(
            bound[1].dispatcher,
            "hl.dsp.exec_cmd(\"uwsm app -- ghostty\")"
        );
        assert_eq!(bound[2].combo, "SUPER + 1");
        assert_eq!(bound[2].dispatcher, "hl.dsp.focus({ workspace = 1 })");
        assert!(bound[12].dispatcher.contains("x = -40"));
        let text = lua(&bound);
        assert!(text.contains("hl.bind(\"SUPER + equal\", hl.dsp.window.resize({ x = 40, y = 40, relative = true }), { description = \"Grow or shrink\", repeating = true })"));
        assert!(!text.contains("theme keep"));
    }

    #[test]
    fn the_cheat_sheet() {
        let p = file(
            r#"
[[group]]
id = "style"
title = "Style"

[[action]]
id = "theme"
title = "Theme"
group = "style"

[[action]]
id = "keep"
title = "Keep this theme"
group = "theme"
keys = "K"
scope = "picker"
run = ["x"]

[[binding]]
id = "terminal"
title = "Terminal"
group = "Apps"
target = "Ghostty"
keys = "Super Return"
run = ["ghostty"]

[[binding]]
id = "search"
title = "Search"
group = "Learn"
keys = "Super Space"
run = ["x"]
"#,
        );
        let rows = hotkeys(&p).unwrap();
        let order: Vec<(&str, &str)> = rows
            .iter()
            .map(|r| (r.group.as_str(), r.title.as_str()))
            .collect();
        assert_eq!(
            order,
            [
                ("Learn", "Search"),
                ("Apps", "Terminal"),
                ("Style", "Keep this theme")
            ]
        );
        assert_eq!(rows[2].scope.as_deref(), Some("picker"));
        assert_eq!(rows[1].target, "Ghostty");
    }

    #[test]
    fn problems_are_listed() {
        let p = file(
            r#"
[[action]]
id = "a"
title = "A"
group = "g"
keys = "Super K"
run = ["x"]

[[binding]]
id = "b"
title = "B"
group = "G"
keys = "Super K"
hypr = "hl.dsp.window.close()"

[[binding]]
id = "c"
title = "C"
group = "G"
keys = "Super Arrows"
hypr = ["hl.dsp.focus({ direction = \"left\" })"]

[[binding]]
id = "d"
title = "D"
group = "G"
keys = "Super D"
hypr = "os.execute('x')"

[[binding]]
id = "e"
title = "E"
group = "G"
keys = "Super Nope"
run = ["x"]
"#,
        );
        let e = read(&p, "strix").unwrap_err();
        assert!(e.contains("SUPER + K is bound twice: a and b"), "{e}");
        assert!(e.contains("binding c: 1 dispatchers for 4 keys"), "{e}");
        assert!(
            e.contains("binding d: hypr must be an hl.dsp dispatcher"),
            "{e}"
        );
        assert!(e.contains("unknown key \"Nope\""), "{e}");
    }

    #[test]
    fn laptop_keys_work_on_the_lock_screen() {
        assert_eq!(
            key_name("VolumeUp").as_deref(),
            Some("XF86AudioRaiseVolume")
        );
        assert_eq!(
            key_name("BrightnessDown").as_deref(),
            Some("XF86MonBrightnessDown")
        );
        assert_eq!(key_name("Volume"), None);
        let text = lua(&[Bound {
            id: "volume-up".into(),
            combo: "XF86AudioRaiseVolume".into(),
            dispatcher: "hl.dsp.exec_cmd(\"wpctl\")".into(),
            description: "Louder".into(),
            repeat: true,
            locked: true,
        }]);
        assert!(
            text.contains("{ description = \"Louder\", locked = true, repeating = true }"),
            "{text}"
        );
    }
}
