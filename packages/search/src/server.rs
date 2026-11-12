//! The service: the index in memory, a Unix socket that speaks one JSON object per line, and a
//! watcher that rebuilds the index when apps or the system change.
//!
//! A call: `{"id": 7, "method": "query", "params": {"text": "theme"}}`.
//! Its answer: `{"id": 7, "result": ...}` or `{"id": 7, "error": "..."}`.
//! A message of the service itself: `{"event": "changed"}` after every rebuild.

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, RwLock};
use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

use crate::config::Config;
use crate::entry::Kind;
use crate::index::{Index, Query};
use crate::run;
use crate::usage::{Usage, now};

pub struct State {
    pub cfg: Config,
    pub index: RwLock<Index>,
    subscribers: Mutex<Vec<UnixStream>>,
}

impl State {
    pub fn new(cfg: Config) -> State {
        let index = Index::build(&cfg);
        State {
            cfg,
            index: RwLock::new(index),
            subscribers: Mutex::new(Vec::new()),
        }
    }

    pub fn rebuild(&self) -> usize {
        let index = Index::build(&self.cfg);
        for w in &index.warnings {
            eprintln!("warning: {w}");
        }
        let n = index.entries.len();
        if let Ok(mut i) = self.index.write() {
            *i = index;
        }
        self.broadcast(&json!({"event": "changed"}));
        n
    }

    fn broadcast(&self, message: &Value) {
        let line = format!("{message}\n");
        if let Ok(mut subs) = self.subscribers.lock() {
            subs.retain_mut(|s| s.write_all(line.as_bytes()).is_ok());
        }
    }

    /// One call, as the socket and the tests see it.
    pub fn handle(&self, method: &str, params: &Value) -> Result<Value, String> {
        let text = |k: &str| params.get(k).and_then(Value::as_str);
        let dry = params
            .get("dry_run")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let filter = match text("filter") {
            Some(f) if !f.is_empty() && f != "all" => Some(Kind::parse(f).ok_or_else(|| {
                format!("unknown filter \"{f}\"; use app, action, setting or command")
            })?),
            _ => None,
        };
        let index = self.index.read().map_err(|_| "the index is broken")?;
        match method {
            "query" | "browse" => {
                let q = Query {
                    text: if method == "query" {
                        text("text").unwrap_or("").to_string()
                    } else {
                        String::new()
                    },
                    filter,
                    scope: text("scope").map(String::from),
                    limit: params.get("limit").and_then(Value::as_u64).unwrap_or(50) as usize,
                };
                let usage = Usage::load(self.cfg.usage_file.as_deref());
                Ok(json!({ "results": index.query(&q, &usage, now()) }))
            }
            "activate" => {
                let id = text("id").ok_or("activate needs an id")?;
                let entry = index
                    .get(id)
                    .ok_or_else(|| format!("nothing has the id {id}"))?;
                // an entry with entries inside opens inside Search
                let argv = match run::argv(&self.cfg, entry) {
                    Some(argv) if !entry.enter => argv,
                    _ => return Ok(json!({ "enter": true })),
                };
                if !dry {
                    run::spawn(&argv)?;
                    record(&self.cfg, id);
                }
                Ok(json!({ "enter": false, "ran": argv }))
            }
            "run" => {
                let line = text("text")
                    .filter(|t| !t.trim().is_empty())
                    .ok_or("run needs a text")?;
                let argv = run::text_argv(&self.cfg, line);
                if !dry {
                    run::spawn(&argv)?;
                }
                Ok(json!({ "ran": argv }))
            }
            "reload" => {
                drop(index);
                Ok(json!({ "entries": self.rebuild() }))
            }
            "version" => {
                Ok(json!({ "version": env!("CARGO_PKG_VERSION"), "entries": index.entries.len() }))
            }
            _ => Err(format!("unknown method \"{method}\"")),
        }
    }
}

/// Counts a start; the file is read fresh, so the command line and the service share it.
pub fn record(cfg: &Config, id: &str) {
    if let Some(f) = &cfg.usage_file {
        let mut u = Usage::load(Some(f));
        u.record(id, now());
        if let Err(e) = u.save(f) {
            eprintln!("warning: cannot write {}: {e}", f.display());
        }
    }
}

fn answer(state: &State, line: &str) -> Value {
    let call: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(e) => return json!({ "error": format!("not JSON: {e}") }),
    };
    let id = call.get("id").cloned().unwrap_or(Value::Null);
    let method = call.get("method").and_then(Value::as_str).unwrap_or("");
    let params = call.get("params").cloned().unwrap_or(json!({}));
    match state.handle(method, &params) {
        Ok(result) => json!({ "id": id, "result": result }),
        Err(error) => json!({ "id": id, "error": error }),
    }
}

pub(crate) fn client(state: Arc<State>, stream: UnixStream) {
    if let Ok(clone) = stream.try_clone()
        && let Ok(mut subs) = state.subscribers.lock()
    {
        subs.push(clone);
    }
    let Ok(mut out) = stream.try_clone() else {
        return;
    };
    for line in BufReader::new(stream).lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let reply = format!("{}\n", answer(&state, &line));
        if out.write_all(reply.as_bytes()).is_err() {
            break;
        }
    }
}

/// Runs until killed: the socket, the watcher, one thread per client.
pub fn serve(cfg: Config) -> Result<(), String> {
    let socket = cfg
        .socket
        .clone()
        .ok_or("XDG_RUNTIME_DIR is not set, so there is no place for the socket")?;
    if let Some(dir) = socket.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
    }
    if UnixStream::connect(&socket).is_ok() {
        return Err(format!(
            "{} is already served by another instance",
            socket.display()
        ));
    }
    let _ = fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket).map_err(|e| format!("{}: {e}", socket.display()))?;
    let state = Arc::new(State::new(cfg));
    {
        let index = state.index.read().map_err(|_| "the index is broken")?;
        for w in &index.warnings {
            eprintln!("warning: {w}");
        }
        eprintln!(
            "{} entries, listening on {}",
            index.entries.len(),
            socket.display()
        );
    }
    let watched = Arc::clone(&state);
    thread::spawn(move || watch(&watched));
    for stream in listener.incoming().flatten() {
        let s = Arc::clone(&state);
        thread::spawn(move || client(s, stream));
    }
    Ok(())
}

// ------------------------------------------------------------------ the watcher

/// What to watch: every `applications/` folder, the folders of the data files, and `/run` for a
/// new `current-system` (a rebuild or an update). Folders behind links are watched where the link
/// points now, so after every change the watches are set up again.
fn watch_list(cfg: &Config) -> Vec<(PathBuf, Option<&'static str>)> {
    let mut out: Vec<(PathBuf, Option<&'static str>)> =
        cfg.app_dirs.iter().map(|d| (d.clone(), None)).collect();
    for f in [&cfg.menu, &cfg.settings, &cfg.own_entries]
        .into_iter()
        .flatten()
    {
        if let Some(d) = f.parent() {
            out.push((d.to_path_buf(), None));
        }
    }
    if let Some(c) = &cfg.commands {
        out.push((c.clone(), None));
    }
    out.push((PathBuf::from("/run"), Some("current-system")));
    out
}

fn watch(state: &State) {
    loop {
        match Inotify::new(&watch_list(&state.cfg)) {
            Ok(w) => {
                w.wait();
                // a rebuild or an install touches many files; let it settle
                thread::sleep(Duration::from_millis(400));
                w.drain();
                state.rebuild();
            }
            Err(e) => {
                eprintln!("warning: no watcher ({e}); the index is rebuilt every minute");
                thread::sleep(Duration::from_secs(60));
                state.rebuild();
            }
        }
    }
}

struct Inotify {
    fd: OwnedFd,
    /// Watch descriptors that only count for one name (`/run` and `current-system`).
    only: Vec<(i32, &'static str)>,
}

impl Inotify {
    fn new(list: &[(PathBuf, Option<&'static str>)]) -> Result<Inotify, String> {
        // SAFETY: inotify_init1 has no preconditions; a negative result is checked below.
        let raw = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
        if raw < 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
        // SAFETY: raw is a new, valid descriptor that nothing else owns.
        let fd = unsafe { OwnedFd::from_raw_fd(raw) };
        let mut only = Vec::new();
        let mask = libc::IN_CREATE
            | libc::IN_DELETE
            | libc::IN_MOVED_TO
            | libc::IN_MOVED_FROM
            | libc::IN_CLOSE_WRITE
            | libc::IN_ATTRIB
            | libc::IN_DELETE_SELF;
        for (dir, name) in list {
            if !dir.is_dir() {
                continue;
            }
            let Some(c) = cstring(dir) else { continue };
            // SAFETY: fd is a valid inotify descriptor and c a NUL-terminated path.
            let wd = unsafe { libc::inotify_add_watch(fd.as_raw_fd(), c.as_ptr(), mask) };
            if wd >= 0
                && let Some(n) = name
            {
                only.push((wd, *n));
            }
        }
        Ok(Inotify { fd, only })
    }

    /// Blocks until something that counts happened.
    fn wait(&self) {
        let mut buf = [0u8; 8192];
        loop {
            // SAFETY: buf is valid for its length; fd is a valid descriptor.
            let n = unsafe { libc::read(self.fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                thread::sleep(Duration::from_secs(1));
                continue;
            }
            if self.counts(&buf[..n as usize]) {
                return;
            }
        }
    }

    fn counts(&self, mut data: &[u8]) -> bool {
        // struct inotify_event { int wd; uint32_t mask, cookie, len; char name[len]; }
        while data.len() >= 16 {
            let wd = i32::from_ne_bytes([data[0], data[1], data[2], data[3]]);
            let len = u32::from_ne_bytes([data[12], data[13], data[14], data[15]]) as usize;
            let name = data.get(16..16 + len).unwrap_or(&[]);
            let name = name.split(|&b| b == 0).next().unwrap_or(&[]);
            match self.only.iter().find(|(w, _)| *w == wd) {
                Some((_, wanted)) if name != wanted.as_bytes() => {}
                _ => return true,
            }
            data = data.get(16 + len..).unwrap_or(&[]);
        }
        false
    }

    /// Reads what else arrived, without waiting.
    fn drain(&self) {
        let mut pfd = libc::pollfd {
            fd: self.fd.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let mut buf = [0u8; 8192];
        // SAFETY: pfd and buf are valid for the calls; fd is a valid descriptor.
        while unsafe { libc::poll(&mut pfd, 1, 0) } > 0 {
            let n = unsafe { libc::read(self.fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                break;
            }
        }
    }
}

fn cstring(p: &Path) -> Option<std::ffi::CString> {
    std::ffi::CString::new(p.as_os_str().as_encoded_bytes()).ok()
}

/// Sends one call to a running service and returns its result.
pub fn call(socket: &Path, method: &str, params: Value) -> Result<Value, String> {
    let mut s = UnixStream::connect(socket).map_err(|e| format!("{}: {e}", socket.display()))?;
    s.set_read_timeout(Some(Duration::from_secs(10))).ok();
    writeln!(
        s,
        "{}",
        json!({ "id": 1, "method": method, "params": params })
    )
    .map_err(|e| e.to_string())?;
    for line in BufReader::new(s).lines() {
        let v: Value =
            serde_json::from_str(&line.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        if v.get("event").is_some() {
            continue;
        }
        if let Some(e) = v.get("error").and_then(Value::as_str) {
            return Err(e.to_string());
        }
        return Ok(v.get("result").cloned().unwrap_or(Value::Null));
    }
    Err("the service closed the connection".into())
}
