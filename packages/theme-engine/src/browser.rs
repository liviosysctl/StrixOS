//! How the browser is shaped and set, beyond the colours of the theme: browser.toml, first the
//! one of the distribution (BROWSER_BASE), then the user's (BROWSER_USER), which changes single
//! lines of it. Read every time the session writes its files, so a change needs no restart of
//! the engine. A file that cannot be read as written is reported and leaves what stood before.

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

/// The shape of Zen and the settings it is given
#[derive(Clone, Debug, PartialEq)]
pub struct Browser {
    /// The corners of the page, the panels, the dialogs and the address bar, in pixels
    pub radius: u32,
    /// The corners of tabs, essentials and buttons
    pub control: u32,
    /// The size of the type of tabs, address bar and menus
    pub font_size: u32,
    /// The accent as a line on what is selected
    pub stroke: bool,
    /// The gap between the page and the edge of the window
    pub gap: u32,
    /// How much of what is behind the window its glass covers, in percent; 100 is no glass
    pub glass: u32,
    /// Settings of Zen by their names in about:config
    pub prefs: BTreeMap<String, Pref>,
}

/// The value of one setting of Zen
#[derive(Clone, Debug, PartialEq)]
pub enum Pref {
    Bool(bool),
    Number(i64),
    Text(String),
}

impl Default for Browser {
    fn default() -> Browser {
        Browser {
            radius: 12,
            control: 8,
            font_size: 13,
            stroke: true,
            gap: 8,
            glass: 72,
            prefs: BTreeMap::new(),
        }
    }
}

impl Browser {
    /// The files in their order, each over the one before; one that is not there is passed over
    pub fn read(files: &[PathBuf]) -> Browser {
        let mut browser = Browser::default();
        for file in files {
            let Ok(text) = fs::read_to_string(file) else {
                continue;
            };
            for error in browser.layer(&text) {
                eprintln!("{}: {error}", file.display());
            }
        }
        browser
    }

    /// Takes the lines of one file. What is wrong in it is said and left out; the rest counts
    pub fn layer(&mut self, text: &str) -> Vec<String> {
        let table: toml::Table = match text.parse() {
            Ok(table) => table,
            Err(error) => return vec![format!("not valid TOML: {}", error.to_string().trim_end())],
        };
        let mut errors = Vec::new();
        for (name, value) in &table {
            let pixels = |most: i64| match value.as_integer() {
                Some(n) if (0..=most).contains(&n) => Ok(n as u32),
                _ => Err(format!("{name} must be a number from 0 to {most}")),
            };
            let taken = match name.as_str() {
                "radius" => pixels(32).map(|n| self.radius = n),
                "control" => pixels(24).map(|n| self.control = n),
                "gap" => pixels(32).map(|n| self.gap = n),
                "glass" => match value.as_integer() {
                    Some(n) if (40..=100).contains(&n) => {
                        self.glass = n as u32;
                        Ok(())
                    }
                    _ => Err("glass must be a number from 40 to 100".to_string()),
                },
                "font-size" => match value.as_integer() {
                    Some(n) if (9..=20).contains(&n) => {
                        self.font_size = n as u32;
                        Ok(())
                    }
                    _ => Err("font-size must be a number from 9 to 20".to_string()),
                },
                "stroke" => value
                    .as_bool()
                    .map(|on| self.stroke = on)
                    .ok_or_else(|| "stroke must be true or false".to_string()),
                "prefs" => match value.as_table() {
                    Some(prefs) => {
                        for (pref, value) in prefs {
                            match Pref::from(value) {
                                Some(value) => {
                                    self.prefs.insert(pref.clone(), value);
                                }
                                None => errors.push(format!(
                                    "prefs.\"{pref}\" must be true, false, a whole number or a text"
                                )),
                            }
                        }
                        Ok(())
                    }
                    None => Err("prefs must be a table: [prefs]".to_string()),
                },
                _ => Err(format!("{name} is not a setting of the browser")),
            };
            if let Err(error) = taken {
                errors.push(error);
            }
        }
        errors
    }

    /// The corners of what stands in a list: rows of menus, of the address bar
    pub fn item(&self) -> u32 {
        self.control * 2 / 3
    }

    /// What the glass of a plate over a page covers (the address bar, a menu): more than the
    /// window, since a page behind it can be white where the desktop never is
    pub fn raised(&self) -> u32 {
        (self.glass + 16).min(100)
    }
}

impl Pref {
    fn from(value: &toml::Value) -> Option<Pref> {
        match value {
            toml::Value::Boolean(on) => Some(Pref::Bool(*on)),
            toml::Value::Integer(n) => Some(Pref::Number(*n)),
            toml::Value::String(text) => Some(Pref::Text(text.clone())),
            _ => None,
        }
    }

    /// As user.js writes a value
    pub fn written(&self) -> String {
        match self {
            Pref::Bool(on) => on.to_string(),
            Pref::Number(n) => n.to_string(),
            // A JSON text is a JavaScript text
            Pref::Text(text) => serde_json::Value::String(text.clone()).to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_file_of_the_distribution_says_what_the_engine_knows() {
        let file =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../shell/browser.toml");
        // Built apart from the repository, the file is not there
        let Ok(text) = fs::read_to_string(file) else {
            return;
        };
        let mut browser = Browser::default();
        assert_eq!(browser.layer(&text), Vec::<String>::new());
        assert_eq!(browser, Browser::default());
    }

    #[test]
    fn a_later_file_changes_single_lines() {
        let mut browser = Browser::default();
        assert!(browser.layer("radius = 12\ncontrol = 9\n").is_empty());
        assert!(
            browser
                .layer("radius = 4\n[prefs]\n\"zen.watermark.enabled\" = false\n")
                .is_empty()
        );
        assert_eq!((browser.radius, browser.control, browser.item()), (4, 9, 6));
        assert_eq!((browser.glass, browser.raised()), (72, 88));
        assert!(browser.layer("glass = 90").is_empty());
        assert_eq!((browser.glass, browser.raised()), (90, 100));
        assert_eq!(browser.layer("glass = 10").len(), 1);
        assert_eq!(browser.prefs["zen.watermark.enabled"].written(), "false");
    }

    #[test]
    fn what_is_wrong_is_said_and_the_rest_counts() {
        let mut browser = Browser::default();
        let errors = browser.layer("radius = 400\nfont-size = 14\nround = true\n[prefs]\n\"a\" = 1.5\n\"b\" = \"x\\\"y\"\n");
        assert_eq!(errors.len(), 3, "{errors:?}");
        assert_eq!((browser.radius, browser.font_size), (12, 14));
        assert_eq!(browser.prefs["b"].written(), r#""x\"y""#);
        assert_eq!(Browser::default().layer("radius =").len(), 1);
    }
}
