//! The theme of a desktop session: `theme session`, a user service.
//!
//! The theme chosen by hand (`theme set`, root) stays the stored choice of the
//! machine, with the boot splash and the EFI variable. On top of it the session
//! changes its own theme every period (10 minutes) to another god, unless the
//! theme is kept (Q14: only the runtime theme moves; Q15: only the themes of the
//! distribution take part). The session writes its colors into its own folder
//! (`SESSION_DIR`, in `$XDG_RUNTIME_DIR`): tokens.json for the shell, and the
//! files of Hyprland and Ghostty, then runs `SESSION_HOOK` so they reload.
//!
//! The shell's theme picker talks to it over a Unix socket, one JSON object per
//! line, like every back end of the shell:
//!
//! ```text
//! {"id": 1, "method": "state"}                         -> the state below
//! {"id": 2, "method": "preview", "params": {"theme": "mars"}}  this session only
//! {"id": 3, "method": "set", "params": {"theme": "mars"}}      the machine's choice (pkexec)
//! {"id": 4, "method": "keep", "params": {"keep": true}}
//! {"id": 5, "method": "next"}
//! {"event": "changed", "data": <state>}                after every change
//! ```

use crate::adapters;
use crate::system;
use crate::theme::{Catalog, Selection, Theme, Variant};
use serde_json::{Value, json};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::FromRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// When the desktop moves on to another theme. The same rules as `Cycle` in
/// StrixUI's crate `strix-design`: keeping a theme does not stop the count, a
/// change that falls due while kept is skipped, a theme chosen by hand starts
/// a new period.
#[derive(Clone, Debug, PartialEq)]
pub struct Cycle {
    pub period: Duration,
    pub elapsed: Duration,
    pub kept: bool,
}

impl Cycle {
    pub fn new(period: Duration, kept: bool) -> Cycle {
        assert!(!period.is_zero(), "a cycle needs a period");
        Cycle {
            period,
            elapsed: Duration::ZERO,
            kept,
        }
    }

    pub fn remaining(&self) -> Duration {
        self.period.saturating_sub(self.elapsed)
    }

    /// A theme chosen by hand
    pub fn restart(&mut self) {
        self.elapsed = Duration::ZERO;
    }

    /// Lets `dt` go by. True when the period ran out and the theme is not kept.
    /// After a long pause it changes once, not once per missed period.
    pub fn tick(&mut self, dt: Duration) -> bool {
        self.elapsed += dt;
        if self.elapsed < self.period {
            return false;
        }
        self.elapsed =
            Duration::from_nanos((self.elapsed.as_nanos() % self.period.as_nanos()) as u64);
        !self.kept
    }
}

/// Another entry of `ids` than `current`, every other one equally likely.
pub fn other<'a>(
    ids: &'a [String],
    current: &str,
    pick: &mut impl FnMut(usize) -> usize,
) -> Option<&'a str> {
    let choices: Vec<&String> = ids.iter().filter(|id| *id != current).collect();
    if choices.is_empty() {
        return None;
    }
    Some(choices[pick(choices.len()) % choices.len()])
}

/// A number below `n` from the kernel's random source
fn random_below(n: usize) -> usize {
    let mut bytes = [0u8; 8];
    let ok = fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .is_ok();
    let value = if ok {
        u64::from_ne_bytes(bytes)
    } else {
        Instant::now().elapsed().as_nanos() as u64 ^ std::process::id() as u64
    };
    (value % n.max(1) as u64) as usize
}

/// Everything the session needs from the environment
pub struct Settings {
    pub themes_dir: PathBuf,
    /// The machine's runtime folder (RUNTIME_DIR): its tokens.json says what `set` chose
    pub system_dir: Option<PathBuf>,
    pub selection_file: Option<PathBuf>,
    pub default_theme: String,
    /// The ids of the themes that take part in the cycle
    pub cycle: Vec<String>,
    pub dir: PathBuf,
    pub state_file: PathBuf,
    pub socket: PathBuf,
    pub period: Duration,
    pub hook: Option<PathBuf>,
    /// pkexec and the theme command, for `set`
    pub pkexec: PathBuf,
    pub command: Option<PathBuf>,
}

/// The session: which theme it shows and whether it is kept
pub struct Session {
    pub settings: Settings,
    pub catalog: Catalog,
    pub theme: String,
    pub variant: String,
    /// The machine's choice when the session last looked
    pub system: String,
    pub cycle: Cycle,
}

impl Session {
    pub fn new(settings: Settings) -> Result<Session, String> {
        let catalog = Catalog::load(&settings.themes_dir)?;
        let kept = read_kept(&settings.state_file);
        let cycle = Cycle::new(settings.period, kept);
        let mut session = Session {
            settings,
            catalog,
            theme: String::new(),
            variant: String::new(),
            system: String::new(),
            cycle,
        };
        let system = session.system_choice();
        session.adopt(&system)?;
        Ok(session)
    }

    /// The machine's choice: the stored selection if it works, else the default
    pub fn system_choice(&self) -> String {
        let stored = self
            .settings
            .selection_file
            .as_ref()
            .and_then(|file| fs::read_to_string(file).ok())
            .and_then(|text| Selection::parse(&text).ok())
            .filter(|s| self.catalog.resolve(s).is_ok());
        let selection = stored
            .or_else(|| Selection::parse(&self.settings.default_theme).ok())
            .and_then(|s| {
                self.catalog
                    .resolve(&s)
                    .ok()
                    .map(|(t, v)| Selection::resolved(t, v))
            });
        selection.map(|s| s.to_string()).unwrap_or_default()
    }

    fn resolve(&self, text: &str) -> Result<(&Theme, &Variant), String> {
        self.catalog.resolve(&Selection::parse(text)?)
    }

    /// Shows `text` (theme or theme:variant) in this session and starts a new period
    pub fn show(&mut self, text: &str) -> Result<(), String> {
        let (theme, variant) = self.resolve(text)?;
        write_output(&self.settings.dir, theme, variant)?;
        let (theme_id, variant_id) = (theme.id.clone(), variant.id.clone());
        self.theme = theme_id;
        self.variant = variant_id;
        self.cycle.restart();
        self.run_hook();
        Ok(())
    }

    /// Takes the machine's choice
    fn adopt(&mut self, system: &str) -> Result<(), String> {
        self.system = system.to_string();
        self.show(system)
    }

    /// Called when the machine's runtime folder changed: someone ran `set`
    pub fn system_changed(&mut self) -> Result<bool, String> {
        // A theme folder may have come or gone with a rebuild
        if let Ok(catalog) = Catalog::load(&self.settings.themes_dir) {
            self.catalog = catalog;
        }
        let system = self.system_choice();
        if system.is_empty() || system == self.system {
            return Ok(false);
        }
        self.adopt(&system)?;
        Ok(true)
    }

    /// One step of the clock. True when the theme changed.
    pub fn tick(
        &mut self,
        dt: Duration,
        pick: &mut impl FnMut(usize) -> usize,
    ) -> Result<bool, String> {
        if !self.cycle.tick(dt) {
            return Ok(false);
        }
        self.next(pick)
    }

    /// Another god now
    pub fn next(&mut self, pick: &mut impl FnMut(usize) -> usize) -> Result<bool, String> {
        let ids: Vec<String> = self
            .settings
            .cycle
            .iter()
            .filter(|id| self.catalog.theme(id).is_some())
            .cloned()
            .collect();
        let Some(id) = other(&ids, &self.theme, pick).map(String::from) else {
            return Ok(false);
        };
        self.show(&id)?;
        Ok(true)
    }

    pub fn keep(&mut self, kept: bool) -> Result<(), String> {
        self.cycle.kept = kept;
        let text = format!("{}\n", json!({ "keep": kept }));
        if let Some(dir) = self.settings.state_file.parent() {
            fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
        }
        system::write_atomic(&self.settings.state_file, text.as_bytes(), 0o600)
            .map_err(|e| format!("cannot store the keep flag: {e}"))
    }

    /// The machine's choice, through pkexec and the theme command. polkit lets
    /// the active local session do this without a password.
    pub fn set(&mut self, text: &str) -> Result<(), String> {
        let selection = {
            let (theme, variant) = self.resolve(text)?;
            Selection::resolved(theme, variant).to_string()
        };
        let command =
            self.settings.command.clone().ok_or(
                "THEME_COMMAND is not set, the machine's theme cannot be chosen from here",
            )?;
        let output = Command::new(&self.settings.pkexec)
            .arg(&command)
            .arg("set")
            .arg(&selection)
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("cannot run {}: {e}", self.settings.pkexec.display()))?;
        if !output.status.success() {
            let text = String::from_utf8_lossy(&output.stderr);
            let line = text
                .lines()
                .rev()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("failed");
            return Err(format!("the theme could not be set: {}", line.trim()));
        }
        self.adopt(&selection)
    }

    fn run_hook(&self) {
        let Some(hook) = self.settings.hook.clone() else {
            return;
        };
        // Never wait for Hyprland or Ghostty here; what the hook says goes to the journal
        thread::spawn(
            move || match Command::new(&hook).stdin(Stdio::null()).status() {
                Ok(status) if !status.success() => eprintln!("hook {}: {status}", hook.display()),
                Ok(_) => {}
                Err(e) => eprintln!("hook {}: {e}", hook.display()),
            },
        );
    }

    pub fn state(&self) -> Value {
        let themes: Vec<Value> = self
            .catalog
            .themes
            .iter()
            .map(|theme| {
                let variant = theme.variant(&theme.default_variant);
                json!({
                    "id": theme.id,
                    "name": theme.name,
                    "description": theme.description,
                    "variants": theme.variant_ids(),
                    "cycle": self.settings.cycle.contains(&theme.id),
                    "accent": variant.map(|v| v.color("accent").hex()),
                    "background": variant.map(|v| v.color("background").hex()),
                    "dir": theme.dir.to_string_lossy(),
                })
            })
            .collect();
        json!({
            "theme": self.theme,
            "variant": self.variant,
            "system": self.system,
            "keep": self.cycle.kept,
            "remaining": self.cycle.remaining().as_secs(),
            "period": self.cycle.period.as_secs(),
            "themes": themes,
        })
    }

    /// One call from a client
    pub fn handle(&mut self, method: &str, params: &Value) -> Result<(Value, bool), String> {
        let text = |key: &str| {
            params
                .get(key)
                .and_then(Value::as_str)
                .ok_or_else(|| format!("{method} needs {key}"))
        };
        let changed = match method {
            "state" => false,
            "preview" => {
                self.show(text("theme")?)?;
                true
            }
            "set" => {
                self.set(text("theme")?)?;
                true
            }
            "keep" => {
                let kept = params
                    .get("keep")
                    .and_then(Value::as_bool)
                    .ok_or("keep needs keep (true or false)")?;
                self.keep(kept)?;
                true
            }
            "next" => self.next(&mut random_below)?,
            "version" => return Ok((json!(env!("CARGO_PKG_VERSION")), false)),
            _ => return Err(format!("unknown method \"{method}\"")),
        };
        Ok((self.state(), changed))
    }
}

fn read_kept(file: &Path) -> bool {
    fs::read_to_string(file)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|v| v.get("keep").and_then(Value::as_bool))
        .unwrap_or(false)
}

/// tokens.json, hyprland.lua, ghostty and the GTK files for one theme; tokens.json last, so
/// whoever watches it finds the others already new
pub fn write_output(dir: &Path, theme: &Theme, variant: &Variant) -> Result<(), String> {
    let tokens = serde_json::to_string_pretty(&adapters::tokens(theme, variant))
        .map_err(|e| e.to_string())?
        + "\n";
    let files = [
        ("hyprland.lua", adapters::hyprland(theme, variant)),
        ("ghostty", adapters::ghostty(theme, variant)),
        ("gtk3.css", adapters::gtk3(theme, variant)),
        ("gtk4.css", adapters::gtk4(theme, variant)),
        ("tokens.json", tokens),
    ];
    fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o755));
    for (name, text) in files {
        system::write_atomic(&dir.join(name), text.as_bytes(), 0o644)
            .map_err(|e| format!("cannot write {}: {e}", dir.join(name).display()))?;
    }
    system::symlink_atomic(&theme.dir, &dir.join("current"))
        .map_err(|e| format!("cannot link {}: {e}", dir.join("current").display()))
}

/// The answer to one line from a client
pub fn answer(session: &Mutex<Session>, line: &str) -> (Value, Option<Value>) {
    let call: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(e) => return (json!({ "error": format!("not JSON: {e}") }), None),
    };
    let id = call.get("id").cloned().unwrap_or(Value::Null);
    let method = call.get("method").and_then(Value::as_str).unwrap_or("");
    let params = call.get("params").cloned().unwrap_or(json!({}));
    let mut session = session.lock().unwrap_or_else(|p| p.into_inner());
    match session.handle(method, &params) {
        Ok((result, changed)) => {
            let event = changed.then(|| json!({ "event": "changed", "data": result.clone() }));
            (json!({ "id": id, "result": result }), event)
        }
        Err(error) => (json!({ "id": id, "error": error }), None),
    }
}

/// The clients, to tell every one of them about a change
type Clients = Arc<Mutex<Vec<UnixStream>>>;

fn broadcast(clients: &Clients, message: &Value) {
    let line = format!("{message}\n");
    let mut clients = clients.lock().unwrap_or_else(|p| p.into_inner());
    clients.retain_mut(|c| c.write_all(line.as_bytes()).is_ok());
}

fn client(session: Arc<Mutex<Session>>, clients: Clients, stream: UnixStream) {
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
        let (reply, event) = answer(&session, &line);
        if out.write_all(format!("{reply}\n").as_bytes()).is_err() {
            break;
        }
        if let Some(event) = event {
            broadcast(&clients, &event);
        }
    }
}

/// Watches the machine's runtime folder with inotify
fn watch(dir: &Path) -> io::Result<fs::File> {
    let path = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path with a NUL"))?;
    // Safety: plain system calls on a fresh descriptor
    unsafe {
        let fd = libc::inotify_init1(libc::IN_CLOEXEC);
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let mask =
            libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_CREATE | libc::IN_DELETE_SELF;
        if libc::inotify_add_watch(fd, path.as_ptr(), mask) < 0 {
            let error = io::Error::last_os_error();
            libc::close(fd);
            return Err(error);
        }
        Ok(fs::File::from_raw_fd(fd))
    }
}

/// Runs the session: the socket, the clock and the watch on the machine's choice
pub fn serve(settings: Settings) -> Result<(), String> {
    let socket = settings.socket.clone();
    let system_dir = settings.system_dir.clone();
    if let Some(dir) = socket.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
        let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
    }
    let _ = fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket)
        .map_err(|e| format!("cannot listen on {}: {e}", socket.display()))?;
    let session = Arc::new(Mutex::new(Session::new(settings)?));
    let clients: Clients = Arc::new(Mutex::new(Vec::new()));
    {
        let s = session.lock().unwrap_or_else(|p| p.into_inner());
        eprintln!(
            "session theme {}:{} (machine: {}), kept: {}",
            s.theme, s.variant, s.system, s.cycle.kept
        );
    }
    // The colors are written and the socket listens: the shell may start (Type=notify)
    notify_ready();

    // The clock: one step a second
    {
        let session = Arc::clone(&session);
        let clients = Arc::clone(&clients);
        thread::spawn(move || {
            let mut last = Instant::now();
            loop {
                thread::sleep(Duration::from_secs(1));
                let now = Instant::now();
                let dt = now - last;
                last = now;
                let mut s = session.lock().unwrap_or_else(|p| p.into_inner());
                match s.tick(dt, &mut random_below) {
                    Ok(true) => {
                        eprintln!("cycle: now {}", s.theme);
                        let state = s.state();
                        drop(s);
                        broadcast(&clients, &json!({ "event": "changed", "data": state }));
                    }
                    Ok(false) => {}
                    Err(e) => eprintln!("cycle: {e}"),
                }
            }
        });
    }

    // `set` from anywhere: the machine's runtime folder changes
    if let Some(dir) = system_dir {
        let session = Arc::clone(&session);
        let clients = Arc::clone(&clients);
        thread::spawn(move || {
            loop {
                match watch(&dir) {
                    Ok(mut file) => {
                        let mut buffer = [0u8; 4096];
                        while file.read(&mut buffer).is_ok_and(|n| n > 0) {
                            // Let the engine finish its files
                            thread::sleep(Duration::from_millis(100));
                            let mut s = session.lock().unwrap_or_else(|p| p.into_inner());
                            if let Ok(true) = s.system_changed() {
                                eprintln!("machine: now {}", s.system);
                                let state = s.state();
                                drop(s);
                                broadcast(&clients, &json!({ "event": "changed", "data": state }));
                            }
                        }
                    }
                    // Not there yet (early in the boot): try again
                    Err(_) => thread::sleep(Duration::from_secs(5)),
                }
            }
        });
    }

    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let session = Arc::clone(&session);
        let clients = Arc::clone(&clients);
        thread::spawn(move || client(session, clients, stream));
    }
    Ok(())
}

/// Tells systemd the service is ready, when it runs as Type=notify
fn notify_ready() {
    let Some(path) = std::env::var_os("NOTIFY_SOCKET") else {
        return;
    };
    if let Ok(socket) = std::os::unix::net::UnixDatagram::unbound() {
        let _ = socket.send_to(b"READY=1", PathBuf::from(path));
    }
}

/// One call to a running session, for scripts and tests
pub fn call(socket: &Path, method: &str, params: Value) -> Result<Value, String> {
    let mut stream = UnixStream::connect(socket)
        .map_err(|e| format!("no session theme service at {}: {e}", socket.display()))?;
    stream.set_read_timeout(Some(Duration::from_secs(30))).ok();
    let line = format!(
        "{}\n",
        json!({ "id": 1, "method": method, "params": params })
    );
    stream
        .write_all(line.as_bytes())
        .map_err(|e| e.to_string())?;
    for line in BufReader::new(stream).lines() {
        let line = line.map_err(|e| e.to_string())?;
        let value: Value = serde_json::from_str(&line).map_err(|e| e.to_string())?;
        if value.get("event").is_some() {
            continue;
        }
        if let Some(error) = value.get("error").and_then(Value::as_str) {
            return Err(error.to_string());
        }
        return Ok(value.get("result").cloned().unwrap_or(Value::Null));
    }
    Err("the service closed the connection".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::tests::GOOD;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("session-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn themes(dir: &Path, ids: &[&str]) {
        for id in ids {
            fs::create_dir_all(dir.join(id)).unwrap();
            fs::write(dir.join(id).join("theme.toml"), GOOD).unwrap();
        }
    }

    fn settings(base: &Path) -> Settings {
        themes(
            &base.join("themes"),
            &["apollo", "janus", "saturnus", "outside"],
        );
        Settings {
            themes_dir: base.join("themes"),
            system_dir: Some(base.join("system")),
            selection_file: Some(base.join("selection")),
            default_theme: "saturnus".into(),
            cycle: vec!["apollo".into(), "janus".into(), "saturnus".into()],
            dir: base.join("session"),
            state_file: base.join("state/theme-session.json"),
            socket: base.join("run/theme.sock"),
            period: Duration::from_secs(600),
            hook: None,
            pkexec: PathBuf::from("/nonexistent/pkexec"),
            command: None,
        }
    }

    fn first(_: usize) -> usize {
        0
    }

    #[test]
    fn the_cycle_follows_the_rules_of_the_design_system() {
        let mut c = Cycle::new(Duration::from_secs(600), false);
        assert!(!c.tick(Duration::from_secs(599)));
        assert_eq!(c.remaining(), Duration::from_secs(1));
        assert!(c.tick(Duration::from_secs(1)));
        // A long pause changes once, the rest of the period carries over
        assert!(c.tick(Duration::from_secs(3 * 600 + 20)));
        assert_eq!(c.remaining(), Duration::from_secs(580));
        // Kept: the count goes on, the change that falls due is skipped
        c.kept = true;
        assert!(!c.tick(Duration::from_secs(580)));
        assert_eq!(c.remaining(), Duration::from_secs(600));
        // Let go: nothing at once, the change comes at the next turn
        c.kept = false;
        assert!(!c.tick(Duration::from_secs(1)));
        assert!(c.tick(Duration::from_secs(599)));
        // Chosen by hand: a new period
        c.tick(Duration::from_secs(300));
        c.restart();
        assert_eq!(c.remaining(), Duration::from_secs(600));
    }

    #[test]
    fn another_theme_never_the_same() {
        let ids: Vec<String> = ["a", "b", "c"].iter().map(|s| s.to_string()).collect();
        for n in 0..10 {
            let got = other(&ids, "b", &mut |len| n % len).unwrap();
            assert_ne!(got, "b");
        }
        assert_eq!(other(&ids[..1], "a", &mut first), None);
    }

    #[test]
    fn the_session_starts_on_the_machines_choice_and_cycles_over_the_gods() {
        let base = scratch("cycle");
        let s = settings(&base);
        fs::write(base.join("selection"), "janus\n").unwrap();
        let mut session = Session::new(s).unwrap();
        assert_eq!(session.theme, "janus");
        assert_eq!(session.system, "janus:dark");
        let tokens = fs::read_to_string(base.join("session/tokens.json")).unwrap();
        assert!(tokens.contains("\"theme\": \"janus\""), "{tokens}");
        assert!(base.join("session/hyprland.lua").is_file());
        assert!(base.join("session/ghostty").is_file());
        assert!(base.join("session/gtk3.css").is_file());
        assert!(base.join("session/gtk4.css").is_file());

        // Ten minutes later: another god, never the outside theme
        for _ in 0..20 {
            let before = session.theme.clone();
            assert!(
                session
                    .tick(Duration::from_secs(600), &mut random_below)
                    .unwrap()
            );
            assert_ne!(session.theme, before);
            assert_ne!(session.theme, "outside");
        }
        // The machine's choice did not move
        assert_eq!(
            fs::read_to_string(base.join("selection")).unwrap(),
            "janus\n"
        );
    }

    #[test]
    fn keep_is_stored_and_skips_the_change() {
        let base = scratch("keep");
        let mut session = Session::new(settings(&base)).unwrap();
        assert_eq!(session.theme, "saturnus");
        session.keep(true).unwrap();
        assert!(!session.tick(Duration::from_secs(600), &mut first).unwrap());
        assert_eq!(session.theme, "saturnus");
        // A new session reads the flag
        let again = Session::new(settings(&base)).unwrap();
        assert!(again.cycle.kept);
        assert_eq!(
            fs::metadata(base.join("state/theme-session.json"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }

    #[test]
    fn preview_and_a_choice_of_the_machine() {
        let base = scratch("preview");
        let mut session = Session::new(settings(&base)).unwrap();
        session.tick(Duration::from_secs(300), &mut first).unwrap();
        let (state, changed) = session
            .handle("preview", &json!({ "theme": "outside" }))
            .unwrap();
        assert!(changed);
        assert_eq!(state["theme"], "outside");
        assert_eq!(state["remaining"], 600);
        assert!(
            session
                .handle("preview", &json!({ "theme": "nope" }))
                .unwrap_err()
                .contains("no theme")
        );
        assert!(
            session
                .handle("preview", &json!({}))
                .unwrap_err()
                .contains("needs theme")
        );
        assert!(
            session
                .handle("dance", &json!({}))
                .unwrap_err()
                .contains("unknown method")
        );

        // `set` somewhere else: the machine's runtime folder changed
        fs::write(base.join("selection"), "apollo:dark\n").unwrap();
        assert!(session.system_changed().unwrap());
        assert_eq!(session.theme, "apollo");
        assert!(!session.system_changed().unwrap());

        // Without the theme command `set` says why
        let error = session
            .handle("set", &json!({ "theme": "janus" }))
            .unwrap_err();
        assert!(error.contains("THEME_COMMAND"), "{error}");
    }

    #[test]
    fn the_state_lists_the_themes() {
        let base = scratch("state");
        let session = Session::new(settings(&base)).unwrap();
        let state = session.state();
        assert_eq!(state["keep"], false);
        assert_eq!(state["period"], 600);
        let themes = state["themes"].as_array().unwrap();
        assert_eq!(themes.len(), 4);
        let outside = themes.iter().find(|t| t["id"] == "outside").unwrap();
        assert_eq!(outside["cycle"], false);
        assert_eq!(outside["accent"], "#c8102e");
    }

    #[test]
    fn calls_over_the_socket() {
        let base = scratch("socket");
        let mut s = settings(&base);
        s.system_dir = None;
        let socket = s.socket.clone();
        thread::spawn(move || serve(s).unwrap());
        for _ in 0..100 {
            if socket.exists() {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        // A client that waits for events
        let listener = UnixStream::connect(&socket).unwrap();
        listener
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut events = BufReader::new(listener.try_clone().unwrap());
        (&listener)
            .write_all(b"{\"id\": 9, \"method\": \"state\"}\n")
            .unwrap();
        let mut line = String::new();
        events.read_line(&mut line).unwrap();
        assert!(line.contains("\"id\":9"), "{line}");

        let state = call(&socket, "keep", json!({ "keep": true })).unwrap();
        assert_eq!(state["keep"], true);
        line.clear();
        events.read_line(&mut line).unwrap();
        assert!(line.contains("\"event\":\"changed\""), "{line}");
        let state = call(&socket, "next", json!({})).unwrap();
        assert_ne!(state["theme"], "saturnus");
        assert!(
            call(&socket, "nope", json!({}))
                .unwrap_err()
                .contains("unknown method")
        );
    }
}
