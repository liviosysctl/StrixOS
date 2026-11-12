//! The Store of Strix: a package index of the system's nixpkgs, search, and installing and
//! removing apps through the apps tool. Every path comes from the environment, so the program
//! knows nothing about the distribution (the same rule as the theme engine and Search).

mod index;
mod server;

use serde_json::{Value, json};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

const USAGE: &str = "\
Usage: {name} <command>

  index build [--force]   Read every package of NIXPKGS with nix-env into INDEX_FILE; nothing
                          to do when the index is of the same NIXPKGS already. Needs several
                          GB of memory; the channel's list (index read) does not
  index read FILE [SOURCE]
                          Take the package list of a channel (packages.json, unpacked) or the
                          output of `nix-env -qaP --json --meta` from FILE (- for stdin)
  search TEXT             The packages that fit TEXT, best first
  serve                   The service for the Store window, on SOCKET
  call METHOD [JSON]      One call to the service: search, installed, install, remove, job
  follow METHOD JSON      Like call, then print the job's output until it is done

Environment: INDEX_FILE, NIXPKGS, NIX_ENV, APPS_FILE, APPS_COMMAND, PKEXEC (\"none\": run the
apps tool directly), SOCKET (default $XDG_RUNTIME_DIR/$STORE_ID/store.sock), STORE_ID.
";

fn var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|v| !v.is_empty())
}

fn index_file() -> Result<PathBuf, String> {
    var("INDEX_FILE")
        .map(PathBuf::from)
        .ok_or_else(|| "INDEX_FILE is not set".to_string())
}

fn socket() -> Result<PathBuf, String> {
    if let Some(s) = var("SOCKET") {
        return Ok(PathBuf::from(s));
    }
    let runtime = var("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR is not set")?;
    let id = var("STORE_ID").unwrap_or_else(|| "strix".into());
    Ok(PathBuf::from(runtime).join(id).join("store.sock"))
}

/// Writes a file so a reader sees the old or the new one, never half of it
fn write_atomic(path: &Path, text: &str) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&tmp, text)
        .and_then(|()| fs::rename(&tmp, path))
        .map_err(|e| {
            let _ = fs::remove_file(&tmp);
            format!("cannot write {}: {e}", path.display())
        })
}

fn save(index: &index::Index) -> Result<(), String> {
    let file = index_file()?;
    let text = serde_json::to_string(index).map_err(|e| e.to_string())?;
    write_atomic(&file, &text)?;
    println!("{} packages in {}", index.packages.len(), file.display());
    Ok(())
}

fn index_build(force: bool) -> Result<(), String> {
    let nixpkgs = var("NIXPKGS").ok_or("NIXPKGS is not set")?;
    if !force
        && let Ok(old) = index::load(&index_file()?)
        && old.source == nixpkgs
    {
        println!(
            "The index is of {nixpkgs} already ({} packages)",
            old.packages.len()
        );
        return Ok(());
    }
    let nix_env = var("NIX_ENV").unwrap_or_else(|| "nix-env".into());
    // Unfree packages are listed, marked; apps.json allows them one by one
    let mut child = Command::new(&nix_env)
        .args(["-f", &nixpkgs, "-qaP", "--json", "--meta"])
        .env("NIXPKGS_ALLOW_UNFREE", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("cannot run {nix_env}: {e}"))?;
    let stdout = child.stdout.take().expect("piped");
    let parsed = index::parse(stdout, &nixpkgs);
    let status = child.wait().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("{nix_env} failed: {status}"));
    }
    save(&parsed?)
}

fn read_list(file: &str, source: &str) -> Result<(), String> {
    if file == "-" {
        return save(&index::parse(std::io::stdin().lock(), source)?);
    }
    let reader = fs::File::open(file).map_err(|e| format!("cannot read {file}: {e}"))?;
    save(&index::parse(reader, source)?)
}

fn print(value: &Value) {
    let _ = writeln!(
        std::io::stdout(),
        "{}",
        serde_json::to_string_pretty(value).unwrap_or_default()
    );
}

fn run(args: &[&str]) -> Result<(), String> {
    match args {
        ["index", "build"] => index_build(false),
        ["index", "build", "--force"] => index_build(true),
        ["index", "read", file] => read_list(file, file),
        ["index", "read", file, source] => read_list(file, source),
        ["search", text @ ..] => {
            let index = index::load(&index_file()?)?;
            let installed = var("APPS_FILE")
                .map(|f| index::installed(Path::new(&f)))
                .unwrap_or_default();
            for hit in index::search(&index, &text.join(" "), &installed, 20) {
                let p = hit.package;
                let mark = if hit.installed { "*" } else { " " };
                let unfree = if p.unfree { " (unfree)" } else { "" };
                println!(
                    "{mark} {:<32} {:<14} {}{unfree}",
                    p.attr, p.version, p.description
                );
            }
            Ok(())
        }
        ["serve"] => {
            let pkexec = match var("PKEXEC").as_deref() {
                Some("none") => None,
                Some(p) => Some(PathBuf::from(p)),
                None => Some(PathBuf::from("pkexec")),
            };
            server::serve(server::Config {
                index_file: index_file()?,
                apps_file: PathBuf::from(
                    var("APPS_FILE").unwrap_or_else(|| "/etc/nixos/apps.json".into()),
                ),
                apps_command: var("APPS_COMMAND").map(PathBuf::from),
                pkexec,
                socket: socket()?,
            })
        }
        ["call", method] => server::call(&socket()?, method, json!({}), false).map(|v| print(&v)),
        ["call", method, params] | ["follow", method, params] => {
            let params: Value = serde_json::from_str(params)
                .map_err(|e| format!("the parameters are not JSON: {e}"))?;
            let follow = args[0] == "follow";
            let result = server::call(&socket()?, method, params, follow)?;
            print(&result);
            if follow && result.get("ok") == Some(&Value::Bool(false)) {
                return Err("the job failed".into());
            }
            Ok(())
        }
        _ => Err(String::new()),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let name = args
        .first()
        .and_then(|a| Path::new(a).file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "store".into());
    let rest: Vec<&str> = args.iter().skip(1).map(String::as_str).collect();
    if matches!(rest.as_slice(), [] | ["help"] | ["--help"] | ["-h"]) {
        print!("{}", USAGE.replace("{name}", &name));
        return ExitCode::SUCCESS;
    }
    match run(&rest) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) if e.is_empty() => {
            eprint!("{}", USAGE.replace("{name}", &name));
            ExitCode::from(64)
        }
        Err(e) => {
            eprintln!("{name}: {e}");
            ExitCode::FAILURE
        }
    }
}
