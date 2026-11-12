//! One search for apps, actions, settings and commands. Installed as `<id>-search`.

mod config;
mod desktop;
mod entry;
mod index;
mod run;
mod server;
mod sources;
mod usage;

use std::env;
use std::path::Path;
use std::process::ExitCode;

use serde_json::{Value, json};

use crate::config::Config;
use crate::server::State;

const USAGE: &str = "\
Usage:
  {name} query TEXT [--filter KIND] [--scope ID] [--limit N] [--json]
  {name} browse [ID] [--filter KIND] [--json]
  {name} activate ID [--dry-run]       start an entry
  {name} run TEXT [--dry-run]          run text as a command line in the terminal
  {name} list [--json]                 every entry
  {name} check [--programs]            what nix flake check refuses; with --programs also programs not on PATH
  {name} serve                         the service: socket in $XDG_RUNTIME_DIR/<id>/search.sock
  {name} reload                        ask the running service to read everything again

KIND is app, action, setting or command. Paths come from MENU_FILE, SETTINGS_FILE, COMMANDS_DIR
and the XDG variables; TERMINAL is a JSON list of the terminal and its options.
";

struct Args {
    words: Vec<String>,
    flags: Vec<String>,
    filter: Option<String>,
    scope: Option<String>,
    limit: usize,
}

fn parse(rest: &[String]) -> Result<Args, String> {
    let mut a = Args {
        words: Vec::new(),
        flags: Vec::new(),
        filter: None,
        scope: None,
        limit: 20,
    };
    let mut it = rest.iter();
    while let Some(w) = it.next() {
        match w.as_str() {
            "--filter" => a.filter = Some(it.next().ok_or("--filter needs a kind")?.clone()),
            "--scope" => a.scope = Some(it.next().ok_or("--scope needs an id")?.clone()),
            "--limit" => {
                a.limit = it
                    .next()
                    .and_then(|n| n.parse().ok())
                    .ok_or("--limit needs a number")?
            }
            f if f.starts_with("--") => a.flags.push(f.to_string()),
            _ => a.words.push(w.clone()),
        }
    }
    Ok(a)
}

fn print_results(result: &Value, as_json: bool) {
    if as_json {
        println!("{result}");
        return;
    }
    for r in result["results"].as_array().into_iter().flatten() {
        let place = r["path"]
            .as_array()
            .map(|p| {
                p.iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(" \u{203a} ")
            })
            .unwrap_or_default();
        let mut line = format!(
            "{:<8} {}",
            r["kind"].as_str().unwrap_or(""),
            r["title"].as_str().unwrap_or("")
        );
        if r["enter"].as_bool() == Some(true) {
            line.push_str(" \u{203a}");
        }
        if !place.is_empty() {
            line.push_str(&format!("  ({place})"));
        }
        for k in ["value", "keys"] {
            if let Some(v) = r[k].as_str() {
                line.push_str(&format!("  {v}"));
            }
        }
        println!("{line}");
        println!("         {}", r["id"].as_str().unwrap_or(""));
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let name = args
        .first()
        .and_then(|a| Path::new(a).file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "search".into());
    let usage = USAGE.replace("{name}", &name);
    let Some(command) = args.get(1) else {
        eprint!("{usage}");
        return ExitCode::from(2);
    };
    let a = match parse(&args[2..]) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{name}: {e}");
            return ExitCode::from(2);
        }
    };
    let cfg = Config::from_env();
    let as_json = a.flags.iter().any(|f| f == "--json");
    let dry = a.flags.iter().any(|f| f == "--dry-run");
    let result: Result<Option<Value>, String> = match command.as_str() {
        "query" | "browse" => {
            let state = State::new(cfg);
            let mut params = json!({ "text": a.words.join(" "), "limit": a.limit });
            if let Some(f) = &a.filter {
                params["filter"] = json!(f);
            }
            let scope = if command == "browse" {
                a.words.first().cloned()
            } else {
                a.scope.clone()
            };
            if let Some(s) = scope {
                params["scope"] = json!(s);
            }
            state.handle(command, &params).map(|r| {
                print_results(&r, as_json);
                None
            })
        }
        "activate" => match a.words.first() {
            Some(id) => State::new(cfg)
                .handle("activate", &json!({ "id": id, "dry_run": dry }))
                .map(Some),
            None => Err("activate needs an id".into()),
        },
        "run" => State::new(cfg)
            .handle("run", &json!({ "text": a.words.join(" "), "dry_run": dry }))
            .map(Some),
        "list" => {
            let state = State::new(cfg);
            let index = state.index.read().expect("index");
            if as_json {
                println!("{}", json!(index.entries));
            } else {
                for e in &index.entries {
                    println!("{:<44} {}", e.id, e.title);
                }
            }
            Ok(None)
        }
        "check" => {
            let state = State::new(cfg);
            let index = state.index.read().expect("index");
            let problems = index.check(a.flags.iter().any(|f| f == "--programs"));
            for p in &problems {
                println!("FAIL {p}");
            }
            println!("{} entries, FAILS {}", index.entries.len(), problems.len());
            if problems.is_empty() {
                Ok(None)
            } else {
                return ExitCode::FAILURE;
            }
        }
        "serve" => server::serve(cfg).map(|()| None),
        "reload" => match &cfg.socket {
            Some(s) => server::call(s, "reload", json!({})).map(Some),
            None => Err("XDG_RUNTIME_DIR is not set".into()),
        },
        "--version" => {
            println!("{name} {}", env!("CARGO_PKG_VERSION"));
            Ok(None)
        }
        "help" | "--help" | "-h" => {
            print!("{usage}");
            Ok(None)
        }
        _ => {
            eprint!("{usage}");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(Some(v)) => {
            println!("{v}");
            ExitCode::SUCCESS
        }
        Ok(None) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{name}: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests;
