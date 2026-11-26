//! The commands of the desktop that the shell, Settings and the keys start. One program under
//! several names: `<id>-capture`, `<id>-idle`, `<id>-monitor`, `<id>-defaults`, `<id>-storage`,
//! `<id>-printers` and `<id>-automount`. The name it is started by says which command it is and
//! what the distribution is called, so nothing here knows that name.

mod automount;
mod capture;
mod defaults;
mod idle;
mod monitor;
mod printers;
mod run;
mod storage;

use std::path::Path;
use std::process::ExitCode;

/// How the program was started: the distribution's id, the command, and the name to call it by
/// again (hypridle is given it)
pub struct Call {
    pub id: String,
    pub command: String,
    pub program: String,
}

impl Call {
    /// `/run/current-system/sw/bin/strix-idle` is the command `idle` of `strix`
    fn parse(program: &str) -> Option<Call> {
        let name = Path::new(program).file_name()?.to_str()?;
        let (id, command) = name.rsplit_once('-')?;
        if id.is_empty() {
            return None;
        }
        Some(Call {
            id: id.to_string(),
            command: command.to_string(),
            program: program.to_string(),
        })
    }
}

/// Wrong arguments: the usage, and the exit code for it
pub fn usage(call: &Call, arguments: &str) -> ExitCode {
    eprintln!("Usage: {}-{} {arguments}", call.id, call.command);
    ExitCode::from(64)
}

fn main() -> ExitCode {
    let mut args = std::env::args();
    let program = args.next().unwrap_or_default();
    let args: Vec<String> = args.collect();
    let Some(call) = Call::parse(&program) else {
        eprintln!(
            "{program}: started under a name that is not <id>-capture, <id>-idle, <id>-monitor, <id>-defaults, <id>-storage, <id>-printers or <id>-automount"
        );
        return ExitCode::from(64);
    };
    let result = match call.command.as_str() {
        "capture" => capture::run(&call, &args),
        "idle" => idle::run(&call, &args),
        "monitor" => monitor::run(&call),
        "defaults" => defaults::run(&call, &args),
        "storage" => storage::run(&call, &args),
        "printers" => printers::run(&call, &args),
        "automount" => automount::run(&call, &args),
        _ => {
            eprintln!("{program}: no such command");
            return ExitCode::from(64);
        }
    };
    match result {
        Ok(code) => code,
        Err(message) => {
            eprintln!("{}-{}: {message}", call.id, call.command);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_name_says_the_distribution_and_the_command() {
        let call = Call::parse("/nix/store/x-strix-idle/bin/strix-idle").unwrap();
        assert_eq!((call.id.as_str(), call.command.as_str()), ("strix", "idle"));
        let call = Call::parse("my-distro-capture").unwrap();
        assert_eq!(
            (call.id.as_str(), call.command.as_str()),
            ("my-distro", "capture")
        );
        assert!(Call::parse("desk").is_none());
        assert!(Call::parse("-idle").is_none());
    }
}
