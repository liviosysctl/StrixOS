//! The back end of the graphical installer, in the live session of the ISO.
//!
//! Like the installer of Fedora, the window only asks; this service knows the computer and does
//! the work. It listens on `$SOCKET`, one JSON object per line like the shell's other services:
//! `{"id", "method", "params"}` in, `{"id", "result"}` or `{"id", "error"}` back, and
//! `{"event", "data"}` unasked. The installation itself runs as root through sudo
//! (`<id>-install --core`), with the answers and the secrets in files only it and root can read.
//!
//! ```text
//! facts                the computer: memory, disks with their partitions, Secure Boot
//! timezones            the time zones of tzdata
//! network              {online}: whether cache.nixos.org answers
//! wifi.list            the Wi-Fi networks NetworkManager sees
//! wifi.connect         {ssid, password}
//! install              {answers, password, passphrase}: starts the installation
//! state                where an installation stands, for a window opened later
//! reboot
//!
//! event step {n, total}                      a step started
//! event line {text}                          a line of its output
//! event done {ok, error, mokCode, mokFromDisk}
//! ```

use crate::core::{self, STEPS};
use crate::facts;
use serde::Serialize;
use serde_json::{Value, json};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

/// Lines of the installation kept for a window opened later
const KEEP_LINES: usize = 300;

pub struct Config {
    pub socket: PathBuf,
    /// This program, run as root for the installation
    pub install_command: PathBuf,
    pub sudo: PathBuf,
    pub nmcli: String,
    pub name: String,
    pub id: String,
    pub version: String,
}

#[derive(Serialize, Clone, Debug)]
struct State {
    phase: String,
    step: usize,
    total: usize,
    lines: Vec<String>,
    error: String,
    #[serde(rename = "mokCode")]
    mok_code: String,
    #[serde(rename = "mokFromDisk")]
    mok_from_disk: bool,
}

impl Default for State {
    fn default() -> State {
        State {
            phase: "setup".into(),
            step: 0,
            total: STEPS.len(),
            lines: Vec::new(),
            error: String::new(),
            mok_code: String::new(),
            mok_from_disk: false,
        }
    }
}

type Clients = Arc<Mutex<Vec<UnixStream>>>;

struct Service {
    cfg: Config,
    state: Mutex<State>,
    clients: Clients,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

fn broadcast(clients: &Clients, event: &str, data: Value) {
    let line = format!("{}\n", json!({ "event": event, "data": data }));
    lock(clients).retain_mut(|c| c.write_all(line.as_bytes()).is_ok());
}

/// Runs a short command and returns its output, or its last line of error
fn run(program: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(program)
        .args(args)
        .output()
        .map_err(|e| format!("cannot run {program}: {e}"))?;
    if out.status.success() {
        return Ok(String::from_utf8_lossy(&out.stdout).into_owned());
    }
    let text = if out.stderr.is_empty() {
        &out.stdout
    } else {
        &out.stderr
    };
    let text = String::from_utf8_lossy(text);
    Err(text
        .lines()
        .rev()
        .find(|l| !l.trim().is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| format!("{program} failed")))
}

/// Whether the binary cache answers
fn online() -> bool {
    Command::new("curl")
        .args([
            "--silent",
            "--head",
            "--fail",
            "--max-time",
            "5",
            "https://cache.nixos.org/nix-cache-info",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// The fields of one line of `nmcli -t -e yes`: `:` separates, `\` escapes
pub fn nmcli_fields(line: &str) -> Vec<String> {
    let mut fields = vec![String::new()];
    let mut escaped = false;
    for c in line.chars() {
        match (escaped, c) {
            (true, _) => {
                fields.last_mut().unwrap().push(c);
                escaped = false;
            }
            (false, '\\') => escaped = true,
            (false, ':') => fields.push(String::new()),
            (false, _) => fields.last_mut().unwrap().push(c),
        }
    }
    fields
}

/// The networks of `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list`, each SSID once,
/// the connected one first, then by signal
pub fn wifi_networks(output: &str) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut nets: Vec<(bool, i64, Value)> = Vec::new();
    for line in output.lines() {
        let f = nmcli_fields(line);
        if f.len() < 4 || f[1].is_empty() || !seen.insert(f[1].clone()) {
            continue;
        }
        let active = f[0] == "*";
        let signal: i64 = f[2].parse().unwrap_or(0);
        let secure = !(f[3].is_empty() || f[3] == "--");
        nets.push((
            active,
            signal,
            json!({ "ssid": f[1], "active": active, "signal": signal, "secure": secure }),
        ));
    }
    nets.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    nets.into_iter().map(|n| n.2).collect()
}

fn write_private(path: &Path, value: &Value) -> Result<(), String> {
    let mut f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| format!("cannot write {}: {e}", path.display()))?;
    f.write_all(value.to_string().as_bytes())
        .map_err(|e| e.to_string())
}

impl Service {
    fn work_dir(&self) -> PathBuf {
        self.cfg
            .socket
            .parent()
            .unwrap_or(Path::new("/tmp"))
            .join("install")
    }

    fn call(self: &Arc<Self>, method: &str, params: &Value) -> Result<Value, String> {
        match method {
            "facts" => Ok(self.facts()),
            "timezones" => {
                let out = run("timedatectl", &["list-timezones", "--no-pager"])?;
                Ok(json!(
                    out.split_whitespace()
                        .filter(|z| z.contains('/')
                            && !z.starts_with("Etc/")
                            && !z.starts_with("SystemV/"))
                        .collect::<Vec<_>>()
                ))
            }
            "network" => Ok(json!({ "online": online() })),
            "wifi.list" => {
                let out = run(
                    &self.cfg.nmcli,
                    &[
                        "-t",
                        "-e",
                        "yes",
                        "-f",
                        "IN-USE,SSID,SIGNAL,SECURITY",
                        "device",
                        "wifi",
                        "list",
                        "--rescan",
                        "auto",
                    ],
                )?;
                Ok(json!(wifi_networks(&out)))
            }
            "wifi.connect" => {
                let ssid = params.get("ssid").and_then(Value::as_str).unwrap_or("");
                let password = params.get("password").and_then(Value::as_str).unwrap_or("");
                let mut args = vec!["device", "wifi", "connect", ssid];
                if !password.is_empty() {
                    args.extend(["password", password]);
                }
                run(&self.cfg.nmcli, &args)?;
                Ok(json!({ "online": online() }))
            }
            "install" => self.install(params),
            "state" => Ok(json!(*lock(&self.state))),
            "reboot" => run("systemctl", &["reboot"]).map(|_| json!({})),
            _ => Err(format!("unknown method {method}")),
        }
    }

    /// As root through sudo, so each disk's partitions are known; else only the disks, which
    /// can then only be used whole
    fn facts(&self) -> Value {
        let as_root = Command::new(&self.cfg.sudo)
            .arg("-n")
            .arg(&self.cfg.install_command)
            .arg("--facts")
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output();
        if let Ok(out) = as_root
            && out.status.success()
            && let Ok(facts) = serde_json::from_slice(&out.stdout)
        {
            return facts;
        }
        facts::facts(&self.cfg.name, &self.cfg.id, &self.cfg.version)
    }

    fn install(self: &Arc<Self>, params: &Value) -> Result<Value, String> {
        {
            let mut s = lock(&self.state);
            if s.phase == "installing" {
                return Err("An installation is already running.".into());
            }
            *s = State {
                phase: "installing".into(),
                ..State::default()
            };
        }
        let work = self.work_dir();
        let answers = work.join("answers.json");
        let secrets = work.join("secrets.json");
        let text = |k: &str| {
            params
                .get(k)
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string()
        };
        let written = fs::create_dir_all(&work)
            .map_err(|e| e.to_string())
            .and_then(|()| {
                let _ = fs::set_permissions(&work, fs::Permissions::from_mode(0o700));
                write_private(&answers, params.get("answers").unwrap_or(&Value::Null))
            })
            .and_then(|()| {
                write_private(
                    &secrets,
                    &json!({ "password": text("password"), "passphrase": text("passphrase") }),
                )
            });
        if let Err(e) = written {
            lock(&self.state).phase = "setup".into();
            return Err(e);
        }
        let service = Arc::clone(self);
        thread::spawn(move || service.watch(&answers, &secrets));
        Ok(json!({ "started": true }))
    }

    /// Runs the installation as root and passes its output on
    fn watch(&self, answers: &Path, secrets: &Path) {
        let finish = |ok: bool, error: String| {
            for leftover in [answers, secrets] {
                core::shred(leftover);
            }
            let data = {
                let mut s = lock(&self.state);
                s.phase = if ok { "done" } else { "failed" }.into();
                s.error = error.clone();
                json!({ "ok": ok, "error": error, "mokCode": s.mok_code, "mokFromDisk": s.mok_from_disk })
            };
            broadcast(&self.clients, "done", data);
        };
        let (reader, writer) = match std::io::pipe() {
            Ok(p) => p,
            Err(e) => return finish(false, e.to_string()),
        };
        let Ok(writer2) = writer.try_clone() else {
            return finish(false, "cannot start the installer".into());
        };
        let child = Command::new(&self.cfg.sudo)
            .arg("-n")
            .arg(&self.cfg.install_command)
            .arg("--core")
            .arg("--answers")
            .arg(answers)
            .arg("--secrets")
            .arg(secrets)
            .stdin(Stdio::null())
            .stdout(writer)
            .stderr(writer2)
            .spawn();
        let mut child = match child {
            Ok(c) => c,
            Err(e) => return finish(false, format!("cannot start the installer: {e}")),
        };
        let mut error = String::new();
        for line in BufReader::new(reader).lines() {
            let Ok(text) = line else { break };
            if let Some((n, total)) = step_of(&text) {
                {
                    let mut s = lock(&self.state);
                    s.step = n;
                    s.total = total;
                }
                broadcast(&self.clients, "step", json!({ "n": n, "total": total }));
                continue;
            }
            if let Some(rest) = text.strip_prefix("MOK ") {
                let mut parts = rest.split_whitespace();
                let mut s = lock(&self.state);
                s.mok_code = parts.next().filter(|c| *c != "-").unwrap_or("").to_string();
                s.mok_from_disk = parts.next() == Some("1");
                continue;
            }
            if let Some(rest) = text.strip_prefix("Error: ") {
                error = rest.to_string();
            }
            {
                let mut s = lock(&self.state);
                s.lines.push(text.clone());
                let over = s.lines.len().saturating_sub(KEEP_LINES);
                s.lines.drain(..over);
            }
            broadcast(&self.clients, "line", json!({ "text": text }));
        }
        let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);
        let ok = code == 0;
        if !ok && error.is_empty() {
            error = format!("The installer stopped (exit {code}).");
        }
        finish(ok, error);
    }
}

/// "[3/9] Title" -> (3, 9)
pub fn step_of(line: &str) -> Option<(usize, usize)> {
    let inner = line.strip_prefix('[')?.split(']').next()?;
    let (n, total) = inner.split_once('/')?;
    Some((n.parse().ok()?, total.parse().ok()?))
}

fn client(service: Arc<Service>, stream: UnixStream) {
    let Ok(mut out) = stream.try_clone() else {
        return;
    };
    if let Ok(copy) = stream.try_clone() {
        lock(&service.clients).push(copy);
    }
    for line in BufReader::new(stream).lines() {
        let Ok(line) = line else { break };
        let Ok(msg) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = msg.get("id").cloned().unwrap_or(Value::Null);
        let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
        let params = msg.get("params").cloned().unwrap_or(json!({}));
        // Slow calls (Wi-Fi, network) do not hold up events: each line gets its own thread
        let service = Arc::clone(&service);
        let Ok(mut reply_to) = out.try_clone() else {
            break;
        };
        let method = method.to_string();
        thread::spawn(move || {
            let reply = match service.call(&method, &params) {
                Ok(result) => json!({ "id": id, "result": result }),
                Err(error) => json!({ "id": id, "error": error }),
            };
            let _ = reply_to.write_all(format!("{reply}\n").as_bytes());
        });
    }
    let _ = out.flush();
}

pub fn serve(cfg: Config) -> Result<(), String> {
    let socket = cfg.socket.clone();
    if let Some(dir) = socket.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }
    let _ = fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket)
        .map_err(|e| format!("cannot listen on {}: {e}", socket.display()))?;
    let _ = fs::set_permissions(&socket, fs::Permissions::from_mode(0o600));
    let service = Arc::new(Service {
        cfg,
        state: Mutex::new(State::default()),
        clients: Arc::new(Mutex::new(Vec::new())),
    });
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let service = Arc::clone(&service);
        thread::spawn(move || client(service, stream));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nmcli_escapes() {
        assert_eq!(
            nmcli_fields(r"*:Home\:5G:80:WPA2"),
            ["*", "Home:5G", "80", "WPA2"]
        );
        assert_eq!(
            nmcli_fields(r":back\\slash:10:"),
            ["", r"back\slash", "10", ""]
        );
    }

    #[test]
    fn networks_sorted_once() {
        let out = ":Cafe:40:--\n*:Home:60:WPA2\n:Office:90:WPA2\n:Office:30:WPA2\n:::\n";
        let nets = wifi_networks(out);
        let names: Vec<_> = nets.iter().map(|n| n["ssid"].as_str().unwrap()).collect();
        assert_eq!(names, ["Home", "Office", "Cafe"]);
        assert_eq!(nets[2]["secure"], false);
        assert_eq!(nets[0]["active"], true);
    }

    #[test]
    fn steps() {
        assert_eq!(step_of("[3/9] Checking"), Some((3, 9)));
        assert_eq!(step_of("[warn] something"), None);
        assert_eq!(step_of("plain"), None);
    }

    #[test]
    fn socket_answers_and_errors() {
        let dir = std::env::temp_dir().join(format!("installer-serve-{}", std::process::id()));
        let socket = dir.join("install.sock");
        let cfg = Config {
            socket: socket.clone(),
            install_command: "/nonexistent".into(),
            sudo: "/nonexistent".into(),
            nmcli: "/nonexistent".into(),
            name: "Strix".into(),
            id: "strix".into(),
            version: "0.0.0".into(),
        };
        thread::spawn(move || serve(cfg).unwrap());
        let mut stream = None;
        for _ in 0..100 {
            if let Ok(s) = UnixStream::connect(&socket) {
                stream = Some(s);
                break;
            }
            thread::sleep(std::time::Duration::from_millis(20));
        }
        let mut stream = stream.expect("the service listens");
        let mut reader = BufReader::new(stream.try_clone().unwrap());
        let mut ask = |line: &str| {
            stream.write_all(format!("{line}\n").as_bytes()).unwrap();
            let mut answer = String::new();
            reader.read_line(&mut answer).unwrap();
            serde_json::from_str::<Value>(&answer).unwrap()
        };
        let state = ask(r#"{"id": 1, "method": "state"}"#);
        assert_eq!(state["result"]["phase"], "setup");
        assert_eq!(state["result"]["total"], 9);
        let facts = ask(r#"{"id": 2, "method": "facts"}"#);
        assert_eq!(facts["result"]["id"], "strix");
        let wrong = ask(r#"{"id": 3, "method": "nothing"}"#);
        assert_eq!(wrong["id"], 3);
        assert!(wrong["error"].as_str().unwrap().contains("unknown method"));
        let _ = fs::remove_dir_all(&dir);
    }
}
