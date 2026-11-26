//! `<id>-printers`: the printers CUPS knows, for Settings › Printers. Printers on the network
//! that speak IPP are found by CUPS itself (Avahi) and get a queue of their own the moment
//! something is printed on them; others are added in the printer settings of CUPS
//! (system-config-printer).
//!
//!   list           JSON: every printer, its state and whether it is the default
//!   default NAME   NAME is the printer of this person from now on (lpoptions)

use std::process::ExitCode;

use serde_json::{Value, json};

use crate::Call;
use crate::run::{ok, read};

/// The printers in what `lpstat -p -d` prints (the queues: name, state, and the default), then
/// the ones of `lpstat -e` that have no queue yet: found on the network, ready for a job
pub fn parse(queues: &str, found: &str) -> Vec<Value> {
    let default = queues
        .lines()
        .find_map(|l| l.strip_prefix("system default destination: "))
        .map(str::trim);
    let mut names = Vec::new();
    let mut printers: Vec<Value> = queues
        .lines()
        .filter_map(|line| {
            let rest = line.strip_prefix("printer ")?;
            let (name, state) = rest.split_once(' ')?;
            let state = if state.starts_with("disabled") {
                "off"
            } else if state.starts_with("now printing") {
                "printing"
            } else {
                "ready"
            };
            names.push(name);
            Some(json!({ "name": name, "state": state, "default": Some(name) == default }))
        })
        .collect();
    for name in found.lines().map(str::trim) {
        if name.is_empty() || name.contains(' ') || names.contains(&name) {
            continue;
        }
        names.push(name);
        printers.push(json!({ "name": name, "state": "ready", "default": Some(name) == default }));
    }
    printers
}

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        [] | ["list"] => {
            // Without CUPS or without printers lpstat fails: no printers
            let queues = read("lpstat", &["-p", "-d"]).unwrap_or_default();
            let found = read("lpstat", &["-e"]).unwrap_or_default();
            println!("{}", Value::Array(parse(&queues, &found)));
            Ok(ExitCode::SUCCESS)
        }
        ["default", name] => {
            if ok("lpoptions", &["-d", name]) {
                Ok(ExitCode::SUCCESS)
            } else {
                Err(format!("{name} could not be made the default"))
            }
        }
        _ => Ok(crate::usage(call, "list | default NAME")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn printers_their_state_and_the_default() {
        let text = "printer HP_LaserJet is idle.  enabled since Mon 24 Nov 2026\n\
                    printer Office now printing Office-12.  enabled since Tue\n\
                    printer Old disabled since Wed -\n\treason unknown\n\
                    system default destination: Office\n";
        let printers = parse(text, "");
        assert_eq!(printers.len(), 3);
        assert_eq!(printers[0]["name"], "HP_LaserJet");
        assert_eq!(printers[0]["state"], "ready");
        assert_eq!(printers[1]["state"], "printing");
        assert_eq!(printers[1]["default"], true);
        assert_eq!(printers[2]["state"], "off");
        assert!(parse("lpstat: No destinations added.\n", "").is_empty());
    }

    #[test]
    fn printers_found_on_the_network_without_a_queue() {
        let queues = "printer Office is idle.  enabled since Tue\n\
                      system default destination: Brother_HL_L2350DW\n";
        let found = "Office\nBrother_HL_L2350DW\n";
        let printers = parse(queues, found);
        assert_eq!(printers.len(), 2);
        assert_eq!(printers[0]["name"], "Office");
        assert_eq!(printers[0]["default"], false);
        assert_eq!(printers[1]["name"], "Brother_HL_L2350DW");
        assert_eq!(printers[1]["state"], "ready");
        assert_eq!(printers[1]["default"], true);
        assert_eq!(parse("", "Office\n")[0]["name"], "Office");
    }
}
