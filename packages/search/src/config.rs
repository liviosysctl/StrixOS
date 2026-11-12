//! Where everything is. Every path reaches the program through the environment, so the program
//! knows nothing about the distro (the same rule as the theme engine).
//!
//! | Variable | What | Default |
//! |---|---|---|
//! | `SEARCH_ID` | Name of the folders under the runtime, config and state homes | `strix` |
//! | `MENU_FILE` | The system menu (`shell/menu.toml`) | none: no actions |
//! | `SETTINGS_FILE` | The schema of the settings app | none: no settings |
//! | `COMMANDS_DIR` | One TOML file per own command | none: no commands |
//! | `TERMINAL` | JSON list: the terminal and its options before the command | Ghostty, kept open |
//! | `SEARCH_SPAWN` | `direct` starts programs as children instead of through `systemd-run` | |

use std::env;
use std::path::PathBuf;

use crate::desktop::Locale;

#[derive(Clone, Debug)]
pub struct Config {
    pub id: String,
    pub menu: Option<PathBuf>,
    pub settings: Option<PathBuf>,
    pub commands: Option<PathBuf>,
    pub terminal: Vec<String>,
    pub direct_spawn: bool,
    /// `applications/` folders, the one that wins first (`XDG_DATA_HOME`, then `XDG_DATA_DIRS`).
    pub app_dirs: Vec<PathBuf>,
    pub own_entries: Option<PathBuf>,
    pub usage_file: Option<PathBuf>,
    /// Own keys from Settings › Hotkeys: keys.json and keys.lua
    pub keys_dir: Option<PathBuf>,
    pub socket: Option<PathBuf>,
    pub locale: Locale,
    /// `XDG_CURRENT_DESKTOP`, for `OnlyShowIn` and `NotShowIn`.
    pub desktops: Vec<String>,
}

fn path(var: &str) -> Option<PathBuf> {
    env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

impl Config {
    pub fn from_env() -> Config {
        let id = env::var("SEARCH_ID")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "strix".to_string());
        let home = path("HOME");
        let config_home =
            path("XDG_CONFIG_HOME").or_else(|| home.as_ref().map(|h| h.join(".config")));
        let state_home =
            path("XDG_STATE_HOME").or_else(|| home.as_ref().map(|h| h.join(".local/state")));
        let data_home =
            path("XDG_DATA_HOME").or_else(|| home.as_ref().map(|h| h.join(".local/share")));
        let data_dirs = env::var("XDG_DATA_DIRS")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".to_string());
        let mut app_dirs: Vec<PathBuf> = data_home
            .into_iter()
            .map(|d| d.join("applications"))
            .collect();
        for d in data_dirs.split(':').filter(|d| !d.is_empty()) {
            let p = PathBuf::from(d).join("applications");
            if !app_dirs.contains(&p) {
                app_dirs.push(p);
            }
        }
        let terminal = env::var("TERMINAL")
            .ok()
            .and_then(|t| serde_json::from_str::<Vec<String>>(&t).ok())
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| {
                ["ghostty", "--wait-after-command=true", "-e"]
                    .map(String::from)
                    .to_vec()
            });
        Config {
            menu: path("MENU_FILE"),
            settings: path("SETTINGS_FILE"),
            commands: path("COMMANDS_DIR"),
            terminal,
            direct_spawn: env::var("SEARCH_SPAWN").as_deref() == Ok("direct"),
            app_dirs,
            own_entries: config_home
                .as_ref()
                .map(|c| c.join(&id).join("search/entries.toml")),
            usage_file: state_home.map(|s| s.join(&id).join("search/usage.json")),
            keys_dir: config_home.map(|c| c.join(&id)),
            socket: path("XDG_RUNTIME_DIR").map(|r| r.join(&id).join("search.sock")),
            locale: Locale::from_env(),
            desktops: env::var("XDG_CURRENT_DESKTOP")
                .map(|d| d.split(':').map(String::from).collect())
                .unwrap_or_default(),
            id,
        }
    }

    /// Nothing at all, for tests: each test fills in what it needs.
    #[cfg(test)]
    pub fn empty() -> Config {
        Config {
            id: "strix".into(),
            menu: None,
            settings: None,
            commands: None,
            terminal: vec!["term".into(), "-e".into()],
            direct_spawn: true,
            app_dirs: Vec::new(),
            own_entries: None,
            usage_file: None,
            keys_dir: None,
            socket: None,
            locale: Locale::default(),
            desktops: vec!["Hyprland".into()],
        }
    }
}
