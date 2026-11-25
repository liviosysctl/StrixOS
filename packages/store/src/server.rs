//! The Store as a user service: one JSON object per line on `$XDG_RUNTIME_DIR/<id>/store.sock`,
//! like every back end of the shell.
//!
//! ```text
//! {"id": 1, "method": "search", "params": {"text": "gimp", "limit": 40}}  -> {"results": [...], "ready": true}
//! {"id": 1, "method": "home"}        -> {"ready": true, "count": 152000, "featured": [...], "categories": [...]}
//! {"id": 1, "method": "installed"}   -> {"store": [...], "system": [...]}
//! {"id": 2, "method": "install", "params": {"attr": "gimp"}}              -> {"started": true}
//! {"id": 2, "method": "install", "params": {"attr": "spotify", "proprietary": true}}
//!   (a proprietary package is installed only when the user agreed to it, Q7)
//! {"id": 3, "method": "remove", "params": {"attr": "gimp"}}
//! {"id": 4, "method": "job"}                                              -> the running or last job
//! {"event": "progress", "data": {"line": "..."}}                          while a job runs
//! {"event": "done", "data": {"action": "install", "attr": "gimp", "ok": true, "code": 0}}
//! ```
//!
//! Every package in an answer is a card: its fields of the index, `name` (the catalog's or the
//! package's), `installed`, `builtIn` (it comes with the system: it is not installed or removed
//! from here) and `icon`, the path of its icon when one was found.
//!
//! Installing and removing go through the apps tool (`<id>-apps add|remove`, which rebuilds the
//! system) with pkexec; polkit lets the active local session do that without a password (Q4).
//! One job at a time.

use crate::catalog::Catalog;
use crate::icons::Icons;
use crate::index::{self, Index, Package};
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime};

/// Lines of a job kept for a client that comes late
const KEEP_LINES: usize = 400;

pub struct Config {
    pub index_file: PathBuf,
    pub apps_file: PathBuf,
    /// The apps tool, `<id>-apps`
    pub apps_command: Option<PathBuf>,
    /// pkexec, or None to run the apps tool directly (tests)
    pub pkexec: Option<PathBuf>,
    pub socket: PathBuf,
    /// shell/store.toml: suggestions, categories, names and icons
    pub catalog_file: Option<PathBuf>,
    /// The folders of app icons, the first one wins
    pub icon_dirs: Vec<PathBuf>,
    /// What the system brings along (index::system)
    pub system_file: Option<PathBuf>,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct Job {
    pub action: String,
    pub attr: String,
    pub running: bool,
    pub ok: Option<bool>,
    pub code: Option<i32>,
    pub lines: Vec<String>,
}

pub struct State {
    pub cfg: Config,
    index: Option<Index>,
    index_time: Option<SystemTime>,
    /// The position of each attribute in the index
    by_attr: HashMap<String, usize>,
    catalog: Catalog,
    icons: Icons,
    /// The packages of the system
    system: Vec<Package>,
    /// Their names
    built_in: HashSet<String>,
    /// The catalog's names of apps by attribute, for the search
    names: HashMap<String, String>,
    pub job: Option<Job>,
}

/// Package attributes as the apps tool takes them; nothing else reaches a command line
pub fn valid_attr(attr: &str) -> bool {
    !attr.is_empty()
        && attr.len() <= 200
        && attr.split('.').all(|part| {
            !part.is_empty()
                && part
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '+' | '-'))
        })
}

impl State {
    pub fn new(cfg: Config) -> State {
        let catalog = match &cfg.catalog_file {
            Some(path) => Catalog::load(path).unwrap_or_else(|e| {
                eprintln!("store: {e}");
                Catalog::default()
            }),
            None => Catalog::default(),
        };
        let system = match &cfg.system_file {
            Some(path) => index::system(path).unwrap_or_else(|e| {
                eprintln!("store: {e}");
                Vec::new()
            }),
            None => Vec::new(),
        };
        let names = catalog
            .apps
            .iter()
            .filter_map(|(attr, app)| Some((attr.clone(), app.name.clone()?)))
            .collect();
        let mut state = State {
            names,
            icons: Icons::scan(&cfg.icon_dirs),
            built_in: system.iter().map(|p| p.pname.clone()).collect(),
            system,
            catalog,
            cfg,
            index: None,
            index_time: None,
            by_attr: HashMap::new(),
            job: None,
        };
        state.refresh();
        state
    }

    /// The icons again: an app that was just installed may have brought its own
    pub fn rescan_icons(&mut self) {
        self.icons = Icons::scan(&self.cfg.icon_dirs);
    }

    /// Reads the index again when the index service wrote a new one
    pub fn refresh(&mut self) {
        let time = fs::metadata(&self.cfg.index_file)
            .and_then(|m| m.modified())
            .ok();
        if time.is_some() && time == self.index_time {
            return;
        }
        match index::load(&self.cfg.index_file) {
            Ok(mut index) => {
                // What the system brings along and nixpkgs does not have joins the index
                let names: HashSet<&str> =
                    index.packages.iter().map(|p| p.pname.as_str()).collect();
                let extra: Vec<Package> = self
                    .system
                    .iter()
                    .filter(|p| !names.contains(p.pname.as_str()))
                    .cloned()
                    .collect();
                index.packages.extend(extra);
                self.by_attr = index
                    .packages
                    .iter()
                    .enumerate()
                    .map(|(i, p)| (p.attr.clone(), i))
                    .collect();
                self.index = Some(index);
                self.index_time = time;
            }
            Err(e) => {
                if time.is_some() {
                    eprintln!("store: {e}");
                }
                self.index = None;
                self.index_time = None;
                self.by_attr.clear();
            }
        }
    }

    /// A package as the window shows it (see the top of this file)
    fn card(&self, p: &Package, installed: &HashSet<String>) -> Value {
        let from_store = installed.contains(&p.attr);
        let built_in = !from_store && self.built_in.contains(&p.pname);
        let app = self.catalog.app(&p.attr);
        let mut card = serde_json::to_value(p).unwrap_or_else(|_| json!({}));
        card["name"] = json!(app.and_then(|a| a.name.as_deref()).unwrap_or(&p.pname));
        card["installed"] = json!(from_store || built_in);
        card["builtIn"] = json!(built_in);
        if let Some(icon) = self
            .icons
            .find(app.and_then(|a| a.icon.as_deref()), &p.pname, &p.attr)
        {
            card["icon"] = json!(icon.to_string_lossy());
        }
        card
    }

    fn package(&self, attr: &str) -> Option<&Package> {
        let index = self.index.as_ref()?;
        self.by_attr.get(attr).map(|&i| &index.packages[i])
    }

    /// The cards of these attributes, leaving out what the index does not have
    fn cards<'a>(
        &self,
        attrs: impl IntoIterator<Item = &'a String>,
        installed: &HashSet<String>,
    ) -> Vec<Value> {
        attrs
            .into_iter()
            .filter_map(|attr| self.package(attr))
            .map(|p| self.card(p, installed))
            .collect()
    }

    /// The first page: the suggestions and every category with its apps
    pub fn home(&mut self) -> Value {
        self.refresh();
        let installed = self.installed();
        if self.index.is_none() {
            return json!({ "ready": false, "featured": [], "categories": [] });
        }
        let categories: Vec<Value> = self
            .catalog
            .categories
            .iter()
            .map(|c| {
                json!({
                    "id": c.id,
                    "name": c.name,
                    "symbol": c.symbol,
                    "about": c.about,
                    "apps": self.cards(&c.apps, &installed),
                })
            })
            .collect();
        json!({
            "ready": true,
            "count": self.index.as_ref().map_or(0, |i| i.packages.len()),
            "featured": self.cards(&self.catalog.featured, &installed),
            "categories": categories,
        })
    }

    /// What is installed from the Store, and the apps the system brings along that the catalog
    /// knows (the rest of the system is tools and libraries)
    pub fn installed_cards(&mut self) -> Value {
        self.refresh();
        let installed = self.installed();
        let mut store: Vec<&String> = installed.iter().collect();
        store.sort();
        let known: HashSet<&str> = self.catalog.attrs().collect();
        let system: Vec<Value> = self
            .system
            .iter()
            .filter(|p| !installed.contains(&p.attr))
            .filter_map(|p| {
                // The index's entry where it has one: its description and its attribute
                let found = self
                    .index
                    .as_ref()
                    .and_then(|i| i.packages.iter().find(|q| q.pname == p.pname))
                    .unwrap_or(p);
                (known.contains(found.attr.as_str()) || known.contains(found.pname.as_str()))
                    .then(|| self.card(found, &installed))
            })
            .collect();
        json!({ "store": self.cards(store, &installed), "system": system })
    }

    fn installed(&self) -> HashSet<String> {
        index::installed(&self.cfg.apps_file)
    }

    pub fn search(&mut self, text: &str, limit: usize) -> Value {
        self.refresh();
        let installed = self.installed();
        match &self.index {
            Some(index) => json!({
                "ready": true,
                "count": index.packages.len(),
                "results": index::search(index, text, &installed, &self.names, limit)
                    .iter()
                    .map(|hit| self.card(hit.package, &installed))
                    .collect::<Vec<_>>(),
            }),
            None => json!({ "ready": false, "results": [] }),
        }
    }

    /// Checks a request to install or remove; the job itself runs in `start`. A proprietary
    /// package is installed only with `proprietary` set: the user has seen the question (Q7)
    pub fn check(&mut self, action: &str, attr: &str, proprietary: bool) -> Result<(), String> {
        if !valid_attr(attr) {
            return Err(format!("\"{attr}\" is not a package name"));
        }
        if self.job.as_ref().is_some_and(|j| j.running) {
            return Err("another installation is still running".into());
        }
        if self.cfg.apps_command.is_none() {
            return Err("APPS_COMMAND is not set, this system cannot install from here".into());
        }
        let installed = self.installed().contains(attr);
        if !installed
            && self
                .package(attr)
                .is_some_and(|p| self.built_in.contains(&p.pname))
        {
            return Err(format!(
                "{attr} comes with the system, it is not installed or removed here"
            ));
        }
        match action {
            "install" if installed => Err(format!("{attr} is already installed")),
            "remove" if !installed => Err(format!("{attr} is not installed")),
            "install" => {
                self.refresh();
                let package = self
                    .index
                    .as_ref()
                    .map(|index| index.packages.iter().find(|p| p.attr == attr));
                match package {
                    Some(None) => Err(format!("there is no package {attr}")),
                    Some(Some(p)) if p.unfree && !proprietary => Err(format!(
                        "{attr} is proprietary software: install it with \"proprietary\": true"
                    )),
                    _ => Ok(()),
                }
            }
            _ => Ok(()),
        }
    }
}

type Clients = Arc<Mutex<Vec<UnixStream>>>;

fn broadcast(clients: &Clients, message: &Value) {
    let line = format!("{message}\n");
    let mut clients = clients.lock().unwrap_or_else(|p| p.into_inner());
    clients.retain_mut(|c| c.write_all(line.as_bytes()).is_ok());
}

/// Runs the apps tool for one job and reports every line
fn start(
    state: &Arc<Mutex<State>>,
    clients: &Clients,
    action: &str,
    attr: &str,
    proprietary: bool,
) -> Result<(), String> {
    let (argv, apps_action) = {
        let mut s = state.lock().unwrap_or_else(|p| p.into_inner());
        s.check(action, attr, proprietary)?;
        let tool = s.cfg.apps_command.clone().expect("checked");
        let apps_action = if action == "install" { "add" } else { "remove" };
        let mut argv: Vec<String> = Vec::new();
        if let Some(pkexec) = &s.cfg.pkexec {
            argv.push(pkexec.to_string_lossy().into_owned());
        }
        argv.push(tool.to_string_lossy().into_owned());
        argv.push(apps_action.into());
        argv.push(attr.into());
        s.job = Some(Job {
            action: action.into(),
            attr: attr.into(),
            running: true,
            ..Job::default()
        });
        (argv, apps_action)
    };
    let mut child = Command::new(&argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            let mut s = state.lock().unwrap_or_else(|p| p.into_inner());
            s.job = None;
            format!("cannot run {}: {e}", argv[0])
        })?;
    eprintln!("store: {apps_action} {attr}");

    // Both streams, line by line, to the job and to every client
    let readers: Vec<_> = [
        child
            .stdout
            .take()
            .map(|o| Box::new(o) as Box<dyn std::io::Read + Send>),
        child
            .stderr
            .take()
            .map(|e| Box::new(e) as Box<dyn std::io::Read + Send>),
    ]
    .into_iter()
    .flatten()
    .map(|stream| {
        let state = Arc::clone(state);
        let clients = Arc::clone(clients);
        thread::spawn(move || {
            for line in BufReader::new(stream).lines() {
                let Ok(line) = line else { break };
                {
                    let mut s = state.lock().unwrap_or_else(|p| p.into_inner());
                    if let Some(job) = &mut s.job {
                        job.lines.push(line.clone());
                        if job.lines.len() > KEEP_LINES {
                            job.lines.remove(0);
                        }
                    }
                }
                broadcast(
                    &clients,
                    &json!({ "event": "progress", "data": { "line": line } }),
                );
            }
        })
    })
    .collect();

    let state = Arc::clone(state);
    let clients = Arc::clone(clients);
    thread::spawn(move || {
        let status = child.wait();
        for reader in readers {
            let _ = reader.join();
        }
        let code = status.as_ref().ok().and_then(|s| s.code()).unwrap_or(-1);
        let done = {
            let mut s = state.lock().unwrap_or_else(|p| p.into_inner());
            s.rescan_icons();
            let job = s.job.get_or_insert_with(Job::default);
            job.running = false;
            job.code = Some(code);
            job.ok = Some(code == 0);
            json!({ "action": job.action, "attr": job.attr, "ok": code == 0, "code": code })
        };
        broadcast(&clients, &json!({ "event": "done", "data": done }));
    });
    Ok(())
}

/// The answer to one line from a client
pub fn answer(state: &Arc<Mutex<State>>, clients: &Clients, line: &str) -> Value {
    let call: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(e) => return json!({ "error": format!("not JSON: {e}") }),
    };
    let id = call.get("id").cloned().unwrap_or(Value::Null);
    let method = call.get("method").and_then(Value::as_str).unwrap_or("");
    let params = call.get("params").cloned().unwrap_or(json!({}));
    let text = |key: &str| {
        params
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    };
    let result: Result<Value, String> = match method {
        "search" => {
            let limit = params
                .get("limit")
                .and_then(Value::as_u64)
                .unwrap_or(40)
                .min(200) as usize;
            Ok(state
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .search(&text("text"), limit))
        }
        "home" => Ok(state.lock().unwrap_or_else(|p| p.into_inner()).home()),
        "installed" => Ok(state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .installed_cards()),
        "install" | "remove" => {
            let proprietary = params
                .get("proprietary")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            start(state, clients, method, &text("attr"), proprietary)
                .map(|()| json!({ "started": true }))
        }
        "job" => Ok(json!(state.lock().unwrap_or_else(|p| p.into_inner()).job)),
        "version" => Ok(json!(env!("CARGO_PKG_VERSION"))),
        _ => Err(format!("unknown method \"{method}\"")),
    };
    match result {
        Ok(result) => json!({ "id": id, "result": result }),
        Err(error) => json!({ "id": id, "error": error }),
    }
}

fn client(state: Arc<Mutex<State>>, clients: Clients, stream: UnixStream) {
    let Ok(mut out) = stream.try_clone() else {
        return;
    };
    if let Ok(copy) = stream.try_clone() {
        clients.lock().unwrap_or_else(|p| p.into_inner()).push(copy);
    }
    for line in BufReader::new(stream).lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let reply = answer(&state, &clients, &line);
        if out.write_all(format!("{reply}\n").as_bytes()).is_err() {
            break;
        }
    }
}

pub fn serve(cfg: Config) -> Result<(), String> {
    let socket = cfg.socket.clone();
    if let Some(dir) = socket.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
        let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
    }
    let _ = fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket)
        .map_err(|e| format!("cannot listen on {}: {e}", socket.display()))?;
    let state = Arc::new(Mutex::new(State::new(cfg)));
    let clients: Clients = Arc::new(Mutex::new(Vec::new()));
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let state = Arc::clone(&state);
        let clients = Arc::clone(&clients);
        thread::spawn(move || client(state, clients, stream));
    }
    Ok(())
}

/// One call to a running Store, for scripts and tests. With `follow`, the events of a job are
/// printed until it is done.
pub fn call(
    socket: &std::path::Path,
    method: &str,
    params: Value,
    follow: bool,
) -> Result<Value, String> {
    let mut stream = UnixStream::connect(socket)
        .map_err(|e| format!("no Store service at {}: {e}", socket.display()))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(3600)))
        .ok();
    stream
        .write_all(
            format!(
                "{}\n",
                json!({ "id": 1, "method": method, "params": params })
            )
            .as_bytes(),
        )
        .map_err(|e| e.to_string())?;
    let mut result = None;
    for line in BufReader::new(stream).lines() {
        let value: Value =
            serde_json::from_str(&line.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        match value.get("event").and_then(Value::as_str) {
            Some("progress") if follow => {
                println!("{}", value["data"]["line"].as_str().unwrap_or(""));
            }
            Some("done") if follow => return Ok(value["data"].clone()),
            Some(_) => {}
            None => {
                if let Some(error) = value.get("error").and_then(Value::as_str) {
                    return Err(error.to_string());
                }
                result = Some(value.get("result").cloned().unwrap_or(Value::Null));
                if !follow {
                    break;
                }
            }
        }
    }
    result.ok_or_else(|| "the service closed the connection".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup(name: &str) -> (PathBuf, Config) {
        let dir = std::env::temp_dir().join(format!("store-server-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let file = fs::File::open(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/fixtures/nix-env.json"
        ))
        .unwrap();
        let index = index::parse(file, "x").unwrap();
        fs::write(
            dir.join("index.json"),
            serde_json::to_string(&index).unwrap(),
        )
        .unwrap();
        fs::write(
            dir.join("apps.json"),
            r#"{"version": 1, "packages": [{"attr": "gimp"}]}"#,
        )
        .unwrap();
        // A stand-in for the apps tool: says what it does, fails for "discord"
        let tool = dir.join("apps");
        fs::write(
            &tool,
            "#!/bin/sh\necho \"building $1 $2\"\necho 'a warning' >&2\n[ \"$2\" = discord ] && exit 3\nexit 0\n",
        )
        .unwrap();
        fs::set_permissions(&tool, fs::Permissions::from_mode(0o755)).unwrap();
        fs::write(
            dir.join("store.toml"),
            "featured = [\"firefox\", \"gone\"]\n\n[[category]]\nid = \"internet\"\nname = \"Internet\"\nsymbol = \"globe\"\napps = [\"zen-beta\", \"firefox\", \"gimp\"]\n\n[apps]\nzen-beta = { name = \"Zen\", icon = \"zen-browser\" }\n",
        )
        .unwrap();
        // The system brings Zen (not in nixpkgs) and Firefox ESR along, and a tool
        fs::write(
            dir.join("system.json"),
            r#"[{"name": "zen-beta", "version": "1.0", "description": "Zen Browser"}, {"name": "firefox-esr", "version": "140"}, {"name": "jq"}]"#,
        )
        .unwrap();
        fs::create_dir_all(dir.join("icons")).unwrap();
        fs::write(dir.join("icons/zen-browser.svg"), "<svg/>").unwrap();
        fs::write(dir.join("icons/org.mozilla.firefox.svg"), "<svg/>").unwrap();
        let cfg = Config {
            index_file: dir.join("index.json"),
            apps_file: dir.join("apps.json"),
            apps_command: Some(tool),
            pkexec: None,
            socket: dir.join("run/store.sock"),
            catalog_file: Some(dir.join("store.toml")),
            icon_dirs: vec![dir.join("icons")],
            system_file: Some(dir.join("system.json")),
        };
        (dir, cfg)
    }

    #[test]
    fn attribute_names() {
        for good in [
            "gimp",
            "kdePackages.kate",
            "gtk+3",
            "python313Packages.requests",
            "a_b-c",
        ] {
            assert!(valid_attr(good), "{good}");
        }
        for bad in ["", "a..b", ".a", "a.", "a b", "a;rm", "$(x)", "a/b"] {
            assert!(!valid_attr(bad), "{bad}");
        }
    }

    #[test]
    fn checks_before_a_job() {
        let (_, cfg) = setup("check");
        let mut s = State::new(cfg);
        assert!(
            s.check("install", "gimp", false)
                .unwrap_err()
                .contains("already installed")
        );
        assert!(
            s.check("remove", "firefox", false)
                .unwrap_err()
                .contains("not installed")
        );
        assert!(
            s.check("install", "nope", false)
                .unwrap_err()
                .contains("no package")
        );
        assert!(
            s.check("install", "a;b", false)
                .unwrap_err()
                .contains("not a package name")
        );
        assert!(s.check("install", "firefox", false).is_ok());
        assert!(s.check("remove", "gimp", false).is_ok());
        // Proprietary only when the user agreed
        assert!(
            s.check("install", "spotify", false)
                .unwrap_err()
                .contains("proprietary")
        );
        assert!(s.check("install", "spotify", true).is_ok());
        s.job = Some(Job {
            running: true,
            ..Job::default()
        });
        assert!(
            s.check("install", "firefox", false)
                .unwrap_err()
                .contains("still running")
        );
    }

    #[test]
    fn the_first_page_and_what_is_installed() {
        let (_, cfg) = setup("home");
        let mut s = State::new(cfg);
        let home = s.home();
        assert_eq!(home["ready"], true);
        // A featured app the index does not have is left out
        let featured: Vec<&str> = home["featured"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["attr"].as_str().unwrap())
            .collect();
        assert_eq!(featured, ["firefox"]);
        let firefox = &home["featured"][0];
        assert_eq!(firefox["name"], "firefox");
        assert_eq!(firefox["installed"], false);
        assert!(
            firefox["icon"]
                .as_str()
                .unwrap()
                .ends_with("org.mozilla.firefox.svg")
        );
        let internet = &home["categories"][0];
        assert_eq!(internet["symbol"], "globe");
        // Zen is not in nixpkgs but comes with the system: built in, with its own name and icon
        let zen = &internet["apps"][0];
        assert_eq!(zen["name"], "Zen");
        assert_eq!(zen["builtIn"], true);
        assert_eq!(zen["installed"], true);
        assert!(zen["icon"].as_str().unwrap().ends_with("zen-browser.svg"));
        assert_eq!(internet["apps"][2]["attr"], "gimp");
        assert_eq!(internet["apps"][2]["installed"], true);
        assert_eq!(internet["apps"][2]["builtIn"], false);

        // The search finds what the system brings along too, marked
        let found = s.search("zen", 5);
        assert_eq!(found["results"][0]["attr"], "zen-beta");
        assert_eq!(found["results"][0]["builtIn"], true);
        let esr = s.search("firefox-esr", 5);
        assert_eq!(esr["results"][0]["builtIn"], true);

        let installed = s.installed_cards();
        assert_eq!(installed["store"][0]["attr"], "gimp");
        // Only the apps the catalog knows: not firefox-esr or jq
        let system: Vec<&str> = installed["system"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["attr"].as_str().unwrap())
            .collect();
        assert_eq!(system, ["zen-beta"]);

        // Neither installed nor removed from here
        for action in ["install", "remove"] {
            assert!(
                s.check(action, "zen-beta", false)
                    .unwrap_err()
                    .contains("comes with the system")
            );
            assert!(
                s.check(action, "firefox-esr", false)
                    .unwrap_err()
                    .contains("comes with the system")
            );
        }
    }

    #[test]
    fn a_new_index_is_read_without_a_restart() {
        let (dir, cfg) = setup("refresh");
        fs::remove_file(dir.join("index.json")).unwrap();
        let mut s = State::new(cfg);
        assert_eq!(s.search("gimp", 5)["ready"], false);
        let file = fs::File::open(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/fixtures/nix-env.json"
        ))
        .unwrap();
        fs::write(
            dir.join("index.json"),
            serde_json::to_string(&index::parse(file, "x").unwrap()).unwrap(),
        )
        .unwrap();
        let found = s.search("gimp", 5);
        assert_eq!(found["ready"], true);
        assert_eq!(found["results"][0]["attr"], "gimp");
        assert_eq!(found["results"][0]["installed"], true);
    }

    #[test]
    fn jobs_over_the_socket() {
        let (_, cfg) = setup("socket");
        let socket = cfg.socket.clone();
        thread::spawn(move || serve(cfg).unwrap());
        for _ in 0..100 {
            if socket.exists() {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        let hits = call(&socket, "search", json!({ "text": "fire" }), false).unwrap();
        assert_eq!(hits["results"][0]["attr"], "firefox");

        let done = call(&socket, "install", json!({ "attr": "firefox" }), true).unwrap();
        assert_eq!(
            done,
            json!({ "action": "install", "attr": "firefox", "ok": true, "code": 0 })
        );
        let job = call(&socket, "job", json!({}), false).unwrap();
        assert_eq!(job["running"], false);
        let lines: Vec<&str> = job["lines"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| l.as_str().unwrap())
            .collect();
        assert!(lines.contains(&"building add firefox"), "{lines:?}");
        assert!(lines.contains(&"a warning"), "{lines:?}");

        assert!(
            call(&socket, "install", json!({ "attr": "discord" }), false)
                .unwrap_err()
                .contains("proprietary")
        );
        let done = call(
            &socket,
            "install",
            json!({ "attr": "discord", "proprietary": true }),
            true,
        )
        .unwrap();
        assert_eq!(done["ok"], false);
        assert_eq!(done["code"], 3);
        assert!(
            call(&socket, "remove", json!({ "attr": "spotify" }), false)
                .unwrap_err()
                .contains("not installed")
        );
        assert!(
            call(&socket, "dance", json!({}), false)
                .unwrap_err()
                .contains("unknown method")
        );
    }
}
