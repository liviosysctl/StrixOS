//! `<id>-monitor`: the system monitor behind the load figures of the bar: btop in Ghostty, in the
//! colors of the theme. A monitor that is already open gets the focus instead of a second
//! window. The window's class is `<id>.monitor`.

use std::fs;
use std::os::unix::fs::symlink;
use std::process::ExitCode;

use serde_json::Value;

use crate::Call;
use crate::run::{become_it, config_home, read, runtime_dir};

pub fn run(call: &Call) -> Result<ExitCode, String> {
    let id = &call.id;
    let class = format!("{id}.monitor");
    if read("hyprctl", &["-j", "clients"]).is_some_and(|json| open(&json, &class)) {
        return become_it(
            "hyprctl",
            &[
                "dispatch",
                &format!("hl.dsp.focus({{ window = \"class:^{class}$\" }})"),
            ],
        );
    }

    // The theme engine writes btop.theme next to Ghostty's colors: the session's, else the
    // machine's. btop finds it as the theme <id> and reads it again on SIGUSR2, after every
    // change of theme.
    let mut theme = runtime_dir().join(id).join("theme/btop.theme");
    if !theme.is_file() {
        theme = format!("/run/{id}/theme/btop.theme").into();
    }
    let config = config_home().join("btop");
    fs::create_dir_all(config.join("themes")).map_err(|e| e.to_string())?;
    let link = config.join("themes").join(format!("{id}.theme"));
    let _ = fs::remove_file(&link);
    symlink(&theme, &link).map_err(|e| format!("{}: {e}", link.display()))?;
    let file = config.join("btop.conf");
    let settings = settings(fs::read_to_string(&file).ok().as_deref(), id);
    fs::write(&file, settings).map_err(|e| format!("{}: {e}", file.display()))?;

    become_it(
        "uwsm",
        &[
            "app",
            "--",
            "ghostty",
            &format!("--class={class}"),
            "--title=System monitor",
            "-e",
            "btop",
        ],
    )
}

/// A window of that class is open
fn open(clients: &str, class: &str) -> bool {
    serde_json::from_str::<Value>(clients)
        .ok()
        .and_then(|clients| {
            Some(
                clients
                    .as_array()?
                    .iter()
                    .any(|client| client.get("class").and_then(Value::as_str) == Some(class)),
            )
        })
        .unwrap_or(false)
}

/// btop.conf with the theme of the distribution: a new one with the look that goes with it, an
/// existing one with only its theme changed
fn settings(existing: Option<&str>, id: &str) -> String {
    let theme = format!("color_theme = \"{id}\"");
    match existing {
        None => format!(
            "{theme}\ntheme_background = False\nrounded_corners = False\ngraph_symbol = \"braille\"\n"
        ),
        Some(text) => text
            .split_inclusive('\n')
            .map(|line| {
                if line.starts_with("color_theme = ") {
                    format!("{theme}{}", if line.ends_with('\n') { "\n" } else { "" })
                } else {
                    line.to_string()
                }
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_open_monitor_is_found_by_its_class() {
        let clients = r#"[{"class": "zen"}, {"class": "strix.monitor"}]"#;
        assert!(open(clients, "strix.monitor"));
        assert!(!open(clients, "other.monitor"));
        assert!(!open("not json", "strix.monitor"));
    }

    #[test]
    fn a_new_btop_gets_the_look_and_an_old_one_only_the_theme() {
        assert_eq!(
            settings(None, "strix"),
            "color_theme = \"strix\"\ntheme_background = False\nrounded_corners = False\n\
             graph_symbol = \"braille\"\n"
        );
        assert_eq!(
            settings(
                Some("update_ms = 2000\ncolor_theme = \"Default\"\nvim_keys = True\n"),
                "strix"
            ),
            "update_ms = 2000\ncolor_theme = \"strix\"\nvim_keys = True\n"
        );
    }
}
