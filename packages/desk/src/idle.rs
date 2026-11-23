//! `<id>-idle`: what happens when nobody is at the machine, on power and on battery. The times
//! are in ~/.config/<id>/idle.json (seconds, 0 for never); Settings › Power writes them.
//!
//!   run                      start hypridle with those times (the user service hypridle)
//!   show                     the times as JSON, with the ones not set
//!   set ac|battery ACTION N  change one and start again; ACTION is dim, lock, off or sleep
//!   awake on|off|state       stay awake: nothing dims, locks or sleeps until it is turned off
//!   do POWER ACTION          a time has passed (called by hypridle)
//!   undo ACTION              somebody is back

use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use serde_json::{Value, json};

use crate::run::{become_it, config_home, ok, quiet, runtime_dir};
use crate::{Call, usage};

const USAGE: &str = "run|show|set ac|battery dim|lock|off|sleep SECONDS|awake on|off|state";
const POWERS: [&str; 2] = ["ac", "battery"];
const ACTIONS: [&str; 4] = ["dim", "lock", "off", "sleep"];

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let file = config_home().join(&call.id).join("idle.json");
    let runtime = runtime_dir().join(&call.id);
    match args.as_slice() {
        ["show"] => println!("{}", pretty(&times(&file))),
        ["run"] => {
            fs::create_dir_all(&runtime).map_err(|e| e.to_string())?;
            let config = runtime.join("hypridle.conf");
            fs::write(
                &config,
                hypridle(&call.id, &program(&call.program), &times(&file)),
            )
            .map_err(|e| format!("{}: {e}", config.display()))?;
            return become_it("hypridle", &["-c", &config.to_string_lossy()]);
        }
        ["set", power, action, seconds] => {
            let (true, true, Ok(seconds)) = (
                POWERS.contains(power),
                ACTIONS.contains(action),
                seconds.parse::<u64>(),
            ) else {
                return Ok(usage(call, USAGE));
            };
            let mut all = times(&file);
            all[*power][*action] = json!(seconds);
            if let Some(folder) = file.parent() {
                fs::create_dir_all(folder).map_err(|e| e.to_string())?;
            }
            let new = file.with_extension("json.new");
            fs::write(&new, pretty(&all) + "\n").map_err(|e| e.to_string())?;
            fs::rename(&new, &file).map_err(|e| e.to_string())?;
            if quiet(
                "systemctl",
                &["--user", "is-active", "--quiet", "hypridle.service"],
            ) {
                ok("systemctl", &["--user", "restart", "hypridle.service"]);
            }
        }
        // An inhibitor that hypridle honours; locking before sleep stays as it is
        ["awake"] | ["awake", "state"] => {
            println!("{}", if awake(&call.id) { "on" } else { "off" });
        }
        ["awake", "on"] => {
            if !awake(&call.id) {
                ok(
                    "systemd-run",
                    &[
                        "--user",
                        "--quiet",
                        &format!("--unit={}-awake", call.id),
                        "systemd-inhibit",
                        "--what=idle",
                        &format!("--who={}", call.id),
                        "--why=Stay awake",
                        "sleep",
                        "infinity",
                    ],
                );
            }
        }
        ["awake", "off"] => {
            quiet(
                "systemctl",
                &["--user", "stop", &format!("{}-awake.service", call.id)],
            );
        }
        ["do", power, action] => {
            let now = if on_battery(Path::new("/sys/class/power_supply")) {
                "battery"
            } else {
                "ac"
            };
            if *power != now {
                return Ok(ExitCode::SUCCESS);
            }
            match *action {
                "dim" => {
                    fs::create_dir_all(&runtime).map_err(|e| e.to_string())?;
                    fs::write(runtime.join("dimmed"), "").map_err(|e| e.to_string())?;
                    ok(
                        "brightnessctl",
                        &["-q", "-s", "-c", "backlight", "set", "30%"],
                    );
                }
                "lock" => {
                    ok("loginctl", &["lock-session"]);
                }
                "off" => {
                    ok("hyprctl", &["dispatch", "hl.dsp.dpms({action = \"off\"})"]);
                }
                "sleep" => {
                    ok("systemctl", &["suspend"]);
                }
                _ => return Ok(usage(call, USAGE)),
            }
        }
        ["undo", "dim"] => {
            if fs::remove_file(runtime.join("dimmed")).is_ok() {
                ok("brightnessctl", &["-q", "-r", "-c", "backlight"]);
            }
        }
        ["undo", "off"] => {
            ok("hyprctl", &["dispatch", "hl.dsp.dpms({action = \"on\"})"]);
        }
        _ => return Ok(usage(call, USAGE)),
    }
    Ok(ExitCode::SUCCESS)
}

fn defaults() -> Value {
    json!({
        "ac": { "dim": 240, "lock": 300, "off": 600, "sleep": 0 },
        "battery": { "dim": 120, "lock": 300, "off": 600, "sleep": 900 },
    })
}

/// The times in effect: the ones of the file over the defaults. A file that is not there or not
/// JSON counts as empty.
fn times(file: &Path) -> Value {
    let own = fs::read_to_string(file)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok());
    let mut all = defaults();
    if let Some(own) = own {
        merge(&mut all, &own);
    }
    all
}

/// `over` laid on `under`: objects go into each other, everything else replaces
fn merge(under: &mut Value, over: &Value) {
    match (under, over) {
        (Value::Object(under), Value::Object(over)) => {
            for (key, value) in over {
                merge(under.entry(key.clone()).or_insert(Value::Null), value);
            }
        }
        (under, over) => *under = over.clone(),
    }
}

fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_default()
}

/// The configuration of hypridle: a listener for every time that is set, on power and on
/// battery; each calls this program again, which looks at the power then
fn hypridle(id: &str, program: &str, times: &Value) -> String {
    let mut out = format!(
        "general {{\n    lock_cmd = qs -c {id} ipc call lock lock\n    \
         before_sleep_cmd = loginctl lock-session\n    after_sleep_cmd = {program} undo off\n}}\n"
    );
    for power in POWERS {
        for action in ACTIONS {
            let seconds = times[power][action].as_u64().unwrap_or(0);
            if seconds == 0 {
                continue;
            }
            out.push_str(&format!(
                "listener {{\n    timeout = {seconds}\n    on-timeout = {program} do {power} {action}\n"
            ));
            if action == "dim" || action == "off" {
                out.push_str(&format!("    on-resume = {program} undo {action}\n"));
            }
            out.push_str("}\n");
        }
    }
    out
}

/// The name hypridle calls this program by: the path it was started with, found in PATH when
/// it was started by its bare name
fn program(started: &str) -> String {
    if started.contains('/') {
        return started.to_string();
    }
    std::env::var_os("PATH")
        .and_then(|path| {
            std::env::split_paths(&path)
                .map(|folder| folder.join(started))
                .find(|file| file.is_file())
        })
        .unwrap_or_else(|| PathBuf::from(started))
        .to_string_lossy()
        .into_owned()
}

fn awake(id: &str) -> bool {
    quiet(
        "systemctl",
        &[
            "--user",
            "is-active",
            "--quiet",
            &format!("{id}-awake.service"),
        ],
    )
}

/// On battery: there is one and nothing feeds the machine
fn on_battery(supplies: &Path) -> bool {
    let Ok(entries) = fs::read_dir(supplies) else {
        return false;
    };
    let mut battery = false;
    for entry in entries.flatten() {
        if fs::read_to_string(entry.path().join("online")).is_ok_and(|online| online.trim() == "1")
        {
            return false;
        }
        battery |= entry.file_name().to_string_lossy().starts_with("BAT");
    }
    battery
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("desk-idle-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_file_lies_over_the_defaults() {
        let dir = scratch("times");
        let file = dir.join("idle.json");
        assert_eq!(times(&file), defaults());
        fs::write(&file, r#"{"battery": {"sleep": 0}}"#).unwrap();
        let all = times(&file);
        assert_eq!(all["battery"]["sleep"], 0);
        assert_eq!(all["battery"]["dim"], 120);
        assert_eq!(all["ac"], defaults()["ac"]);
        fs::write(&file, "not json").unwrap();
        assert_eq!(times(&file), defaults());
    }

    #[test]
    fn hypridle_gets_a_listener_for_every_time_that_is_set() {
        let config = hypridle("strix", "/bin/strix-idle", &defaults());
        assert!(config.starts_with("general {\n    lock_cmd = qs -c strix ipc call lock lock\n"));
        assert!(config.contains("    after_sleep_cmd = /bin/strix-idle undo off\n"));
        // ac.sleep is 0: seven of the eight
        assert_eq!(config.matches("listener {").count(), 7);
        assert!(config.contains(
            "listener {\n    timeout = 240\n    on-timeout = /bin/strix-idle do ac dim\n    \
             on-resume = /bin/strix-idle undo dim\n}\n"
        ));
        assert!(config.contains(
            "listener {\n    timeout = 300\n    on-timeout = /bin/strix-idle do battery lock\n}\n"
        ));
        assert!(!config.contains("do ac sleep"));
    }

    #[test]
    fn on_battery_needs_a_battery_and_no_supply() {
        let dir = scratch("power");
        assert!(!on_battery(&dir));
        fs::create_dir_all(dir.join("BAT0")).unwrap();
        assert!(on_battery(&dir));
        fs::create_dir_all(dir.join("AC")).unwrap();
        fs::write(dir.join("AC/online"), "0\n").unwrap();
        assert!(on_battery(&dir));
        fs::write(dir.join("AC/online"), "1\n").unwrap();
        assert!(!on_battery(&dir));
    }
}
