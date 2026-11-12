//! Where entries come from: desktop entries, the system menu, the schema of the settings app,
//! the command files and the person's own entries. Each source only sets `parent`; the index
//! works out places, ancestors and which entries can be entered.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use serde::Deserialize;

use crate::config::Config;
use crate::desktop::{DesktopFile, exec_argv};
use crate::entry::{Entry, Kind, Run};

/// Groups the sources hang their entries under, when the menu has them.
pub const APPS: &str = "menu:apps";
pub const SETTINGS: &str = "menu:settings";
pub const COMMANDS: &str = "menu:commands";

pub(crate) fn read_toml<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))
}

// ------------------------------------------------------------------ apps

/// Every app of the desktop entries, with its own actions as entries below it.
pub fn apps(cfg: &Config, parent: Option<&str>) -> Vec<Entry> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for dir in &cfg.app_dirs {
        let mut files = Vec::new();
        collect_desktop_files(dir, dir, &mut files);
        files.sort();
        for (desktop_id, file) in files {
            // the first folder that has an id wins, also when it hides the app
            if !seen.insert(desktop_id.clone()) {
                continue;
            }
            if let Ok(text) = fs::read_to_string(&file) {
                out.extend(app(cfg, &desktop_id, &file, &text, parent));
            }
        }
    }
    out
}

fn collect_desktop_files(root: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) {
    let Ok(read) = fs::read_dir(dir) else { return };
    for item in read.flatten() {
        let p = item.path();
        if p.is_dir() {
            collect_desktop_files(root, &p, out);
        } else if p.extension().is_some_and(|e| e == "desktop")
            && let Ok(rel) = p.strip_prefix(root)
        {
            out.push((rel.to_string_lossy().replace('/', "-"), p));
        }
    }
}

/// One desktop file: nothing for hidden, foreign or broken entries.
pub fn app(
    cfg: &Config,
    desktop_id: &str,
    file: &Path,
    text: &str,
    parent: Option<&str>,
) -> Vec<Entry> {
    let df = DesktopFile::parse(text);
    let Some(e) = df.group("Desktop Entry") else {
        return Vec::new();
    };
    if e.raw("Type") != Some("Application") || e.boolean("NoDisplay") || e.boolean("Hidden") {
        return Vec::new();
    }
    let only = e.list("OnlyShowIn");
    if !only.is_empty() && !only.iter().any(|d| cfg.desktops.contains(d)) {
        return Vec::new();
    }
    if e.list("NotShowIn").iter().any(|d| cfg.desktops.contains(d)) {
        return Vec::new();
    }
    if let Some(try_exec) = e.string("TryExec")
        && !crate::run::on_path(&try_exec)
    {
        return Vec::new();
    }
    let Some(name) = e.localised("Name", &cfg.locale) else {
        return Vec::new();
    };
    let icon = e.string("Icon");
    let file_s = file.to_string_lossy();
    let Some(argv) = e
        .string("Exec")
        .and_then(|x| exec_argv(&x, &name, icon.as_deref(), &file_s))
    else {
        return Vec::new();
    };
    let mut words: Vec<String> = Vec::new();
    words.extend(e.localised("GenericName", &cfg.locale));
    words.extend(e.localised_list("Keywords", &cfg.locale));
    words.extend(e.list("Categories"));
    words.push(desktop_id.trim_end_matches(".desktop").to_string());

    let id = format!("app:{desktop_id}");
    let mut app = Entry::new(&id, Kind::App, &name);
    app.icon = icon.clone();
    app.detail = e.localised("Comment", &cfg.locale);
    app.words = words.join(" ");
    app.parent = parent.map(String::from);
    app.run = Run::Spawn(argv);
    let mut out = vec![app];
    for action in e.list("Actions") {
        let Some(g) = df.group(&format!("Desktop Action {action}")) else {
            continue;
        };
        let (Some(title), Some(argv)) = (
            g.localised("Name", &cfg.locale),
            g.string("Exec")
                .and_then(|x| exec_argv(&x, &name, icon.as_deref(), &file_s)),
        ) else {
            continue;
        };
        let mut a = Entry::new(format!("{id}:{action}"), Kind::App, title);
        a.icon = g.string("Icon").or_else(|| icon.clone());
        a.parent = Some(id.clone());
        a.words = name.clone();
        a.run = Run::Spawn(argv);
        out.push(a);
    }
    out
}

// ------------------------------------------------------------------ the system menu

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MenuFile {
    #[serde(default)]
    group: Vec<MenuGroup>,
    #[serde(default)]
    action: Vec<MenuAction>,
    /// Keybindings that are no action of Search: read by `bindings`
    #[serde(default)]
    #[allow(dead_code)]
    binding: Vec<toml::Value>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MenuGroup {
    id: String,
    title: String,
    symbol: Option<String>,
    #[serde(default)]
    words: Vec<String>,
    parent: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MenuAction {
    id: String,
    title: String,
    group: String,
    symbol: Option<String>,
    #[serde(default)]
    words: Vec<String>,
    keys: Option<String>,
    run: Option<Vec<String>>,
    #[serde(default)]
    terminal: bool,
    /// The keys only work inside one view, e.g. "picker"; no global binding
    #[allow(dead_code)]
    scope: Option<String>,
}

/// The groups and actions of `menu.toml`. Groups are `menu:<id>`, actions `action:<id>`; `group`
/// and `parent` name either by the bare id.
pub fn menu(path: &Path, distro: &str) -> Result<Vec<Entry>, String> {
    let file: MenuFile = read_toml(path)?;
    let fill = |argv: &[String]| {
        argv.iter()
            .map(|w| w.replace("{id}", distro))
            .collect::<Vec<_>>()
    };
    let mut full: HashMap<&str, String> = HashMap::new();
    for g in &file.group {
        full.insert(&g.id, format!("menu:{}", g.id));
    }
    for a in &file.action {
        full.entry(&a.id)
            .or_insert_with(|| format!("action:{}", a.id));
    }
    let resolve = |bare: &str, what: &str| {
        full.get(bare).cloned().ok_or_else(|| {
            format!(
                "{}: {what} names \"{bare}\", which is no group or action",
                path.display()
            )
        })
    };
    let mut out = Vec::new();
    for g in &file.group {
        let mut e = Entry::new(format!("menu:{}", g.id), Kind::Menu, &g.title);
        e.icon = g.symbol.clone();
        e.words = g.words.join(" ");
        e.parent = g
            .parent
            .as_deref()
            .map(|p| resolve(p, &format!("group {}", g.id)))
            .transpose()?;
        out.push(e);
    }
    for a in &file.action {
        let mut e = Entry::new(format!("action:{}", a.id), Kind::Action, &a.title);
        e.icon = a.symbol.clone();
        e.words = a.words.join(" ");
        e.keys = a.keys.clone();
        e.parent = Some(resolve(&a.group, &format!("action {}", a.id))?);
        e.run = match &a.run {
            Some(argv) if a.terminal => Run::Terminal(fill(argv)),
            Some(argv) => Run::Spawn(fill(argv)),
            None => Run::None,
        };
        out.push(e);
    }
    Ok(out)
}

// ------------------------------------------------------------------ the settings schema

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SettingsFile {
    /// How Settings is opened at a row: `{page}` and `{row}` are filled in; a word with `{row}`
    /// is left out when a whole page is opened.
    open: Vec<String>,
    #[serde(default)]
    page: Vec<SettingsPage>,
    #[serde(default)]
    row: Vec<SettingsRow>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SettingsPage {
    id: String,
    title: String,
    symbol: Option<String>,
    #[serde(default)]
    words: Vec<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SettingsRow {
    id: String,
    page: String,
    title: String,
    description: Option<String>,
    symbol: Option<String>,
    #[serde(default)]
    words: Vec<String>,
    #[serde(rename = "type")]
    kind: String,
    /// The current value: a text, or a command whose first line is the value.
    value: Option<Value>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Value {
    Text(String),
    Command(Vec<String>),
}

const ROW_TYPES: [&str; 6] = ["switch", "choice", "slider", "text", "keys", "action"];

pub fn settings(path: &Path, parent: Option<&str>, distro: &str) -> Result<Vec<Entry>, String> {
    let mut file: SettingsFile = read_toml(path)?;
    // `{id}` in the commands that print a value, as in `open`
    for row in &mut file.row {
        if let Some(Value::Command(argv)) = &mut row.value {
            for word in argv.iter_mut() {
                *word = word.replace("{id}", distro);
            }
        }
    }
    if file.open.is_empty() {
        return Err(format!("{}: open is empty", path.display()));
    }
    let open = |page: &str, row: Option<&str>| -> Vec<String> {
        file.open
            .iter()
            .filter(|w| row.is_some() || !w.contains("{row}"))
            .map(|w| {
                w.replace("{id}", distro)
                    .replace("{page}", page)
                    .replace("{row}", row.unwrap_or(""))
            })
            .collect()
    };
    let pages: HashSet<&str> = file.page.iter().map(|p| p.id.as_str()).collect();
    let mut out = Vec::new();
    for p in &file.page {
        let mut e = Entry::new(format!("setting:{}", p.id), Kind::Setting, &p.title);
        e.icon = p.symbol.clone();
        e.words = p.words.join(" ");
        e.parent = parent.map(String::from);
        e.run = Run::Spawn(open(&p.id, None));
        out.push(e);
    }
    let values = current_values(&file.row);
    for (r, value) in file.row.iter().zip(values) {
        if !pages.contains(r.page.as_str()) {
            return Err(format!(
                "{}: row {} is on page \"{}\", which does not exist",
                path.display(),
                r.id,
                r.page
            ));
        }
        if !ROW_TYPES.contains(&r.kind.as_str()) {
            return Err(format!(
                "{}: row {} has type \"{}\"; known are {}",
                path.display(),
                r.id,
                r.kind,
                ROW_TYPES.join(", ")
            ));
        }
        let mut e = Entry::new(
            format!("setting:{}/{}", r.page, r.id),
            Kind::Setting,
            &r.title,
        );
        e.icon = r.symbol.clone();
        e.words = r.words.join(" ");
        e.detail = r.description.clone();
        e.value = value;
        e.parent = Some(format!("setting:{}", r.page));
        e.run = Run::Spawn(open(&r.page, Some(&r.id)));
        out.push(e);
    }
    Ok(out)
}

/// The values of every row; commands run side by side, each with half a second.
fn current_values(rows: &[SettingsRow]) -> Vec<Option<String>> {
    let (tx, rx) = mpsc::channel();
    let mut out: Vec<Option<String>> = vec![None; rows.len()];
    let mut waiting = 0;
    for (i, r) in rows.iter().enumerate() {
        match &r.value {
            Some(Value::Text(t)) => out[i] = Some(t.clone()),
            Some(Value::Command(argv)) if !argv.is_empty() => {
                let argv = argv.clone();
                let tx = tx.clone();
                waiting += 1;
                thread::spawn(move || {
                    let _ = tx.send((i, first_line(&argv, Duration::from_millis(500))));
                });
            }
            _ => {}
        }
    }
    drop(tx);
    for _ in 0..waiting {
        match rx.recv_timeout(Duration::from_millis(600)) {
            Ok((i, v)) => out[i] = v,
            Err(_) => break,
        }
    }
    out
}

/// The first line a command prints, if it ends in time and successfully.
pub fn first_line(argv: &[String], timeout: Duration) -> Option<String> {
    output(argv, timeout)
        .and_then(|o| o.lines().next().map(|l| l.trim().to_string()))
        .filter(|l| !l.is_empty())
}

fn output(argv: &[String], timeout: Duration) -> Option<String> {
    let (program, args) = argv.split_first()?;
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut stdout = child.stdout.take()?;
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let mut s = String::new();
        let _ = std::io::Read::read_to_string(&mut stdout, &mut s);
        let _ = tx.send(s);
    });
    let text = rx.recv_timeout(timeout).ok();
    if text.is_none() {
        let _ = child.kill();
    }
    let ok = child.wait().map(|s| s.success()).unwrap_or(false);
    text.filter(|_| ok)
}

// ------------------------------------------------------------------ own commands

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CommandFile {
    name: String,
    description: String,
    #[serde(default)]
    words: Vec<String>,
    #[serde(default)]
    root: bool,
    /// With sub-commands: the command alone is an entry too
    #[serde(default)]
    bare: bool,
    #[serde(default)]
    sub: Vec<SubCommand>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SubCommand {
    /// One or more words, e.g. "repos update" or "--themes"
    name: String,
    /// `{value}` stands for the argument of a sub-command with values.
    description: String,
    #[serde(default)]
    words: Vec<String>,
    #[serde(default)]
    root: bool,
    /// A command that prints the possible values, one per line, a tab before an optional description.
    values: Option<Vec<String>>,
}

/// One entry per sub-command, or per sub-command and value; the command itself when it has none
/// or when `bare` is set.
/// `{id}` in names and value commands stands for the distro id.
pub fn commands(dir: &Path, parent: Option<&str>, distro: &str) -> Result<Vec<Entry>, String> {
    let mut files: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .flatten()
        .map(|d| d.path())
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    files.sort();
    let mut out = Vec::new();
    for f in files {
        let mut c: CommandFile = read_toml(&f)?;
        c.name = c.name.replace("{id}", distro);
        for s in &mut c.sub {
            if let Some(v) = &mut s.values {
                for w in v.iter_mut() {
                    *w = w.replace("{id}", distro);
                }
            }
        }
        let mk = |line: Vec<String>, description: String, words: &[String], root: bool| {
            let title = line.join(" ");
            let mut e = Entry::new(format!("command:{title}"), Kind::Command, &title);
            e.icon = Some("square-terminal".into());
            e.detail = Some(description);
            e.words = c
                .words
                .iter()
                .chain(words)
                .cloned()
                .collect::<Vec<_>>()
                .join(" ");
            e.parent = parent.map(String::from);
            let mut argv = if root {
                vec!["sudo".to_string()]
            } else {
                Vec::new()
            };
            argv.extend(line);
            e.run = Run::Terminal(argv);
            e
        };
        if c.sub.is_empty() || c.bare {
            out.push(mk(vec![c.name.clone()], c.description.clone(), &[], c.root));
        }
        for s in &c.sub {
            let root = c.root || s.root;
            let argv_of = |more: Option<&str>| {
                std::iter::once(c.name.clone())
                    .chain(s.name.split_whitespace().map(String::from))
                    .chain(more.map(String::from))
                    .collect::<Vec<_>>()
            };
            match &s.values {
                None => out.push(mk(argv_of(None), s.description.clone(), &s.words, root)),
                Some(argv) => {
                    for line in output(argv, Duration::from_secs(2))
                        .unwrap_or_default()
                        .lines()
                    {
                        let (value, about) = match line.split_once('\t') {
                            Some((v, a)) => (v.trim(), a.trim()),
                            None => (line.trim(), ""),
                        };
                        if value.is_empty() {
                            continue;
                        }
                        let mut words = s.words.clone();
                        if !about.is_empty() {
                            words.push(about.to_string());
                        }
                        out.push(mk(
                            argv_of(Some(value)),
                            s.description.replace("{value}", value),
                            &words,
                            root,
                        ));
                    }
                }
            }
        }
    }
    Ok(out)
}

// ------------------------------------------------------------------ the person's own entries

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct OwnFile {
    #[serde(default)]
    pub hide: Vec<String>,
    #[serde(default)]
    entry: Vec<OwnEntry>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OwnEntry {
    id: String,
    #[serde(default = "own_kind")]
    kind: String,
    title: String,
    group: Option<String>,
    symbol: Option<String>,
    #[serde(default)]
    words: Vec<String>,
    keys: Option<String>,
    run: Vec<String>,
    #[serde(default)]
    terminal: bool,
}

fn own_kind() -> String {
    "action".into()
}

/// The entries of `entries.toml` (`own:<id>`) and the ids to hide. `group` names a menu group.
pub fn own(path: &Path) -> Result<(Vec<Entry>, Vec<String>), String> {
    if !path.exists() {
        return Ok((Vec::new(), Vec::new()));
    }
    let file: OwnFile = read_toml(path)?;
    let mut out = Vec::new();
    for o in file.entry {
        let kind = match Kind::parse(&o.kind) {
            Some(k @ (Kind::Action | Kind::App | Kind::Command)) => k,
            _ => {
                return Err(format!(
                    "{}: entry {} has kind \"{}\"; known are action, app, command",
                    path.display(),
                    o.id,
                    o.kind
                ));
            }
        };
        if o.run.is_empty() {
            return Err(format!("{}: entry {} runs nothing", path.display(), o.id));
        }
        let mut e = Entry::new(format!("own:{}", o.id), kind, o.title);
        e.icon = o.symbol;
        e.words = o.words.join(" ");
        e.keys = o.keys;
        e.parent = o.group.map(|g| format!("menu:{g}"));
        e.run = if o.terminal || kind == Kind::Command {
            Run::Terminal(o.run)
        } else {
            Run::Spawn(o.run)
        };
        out.push(e);
    }
    Ok((out, file.hide))
}
