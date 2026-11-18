//! What the answers must look like, and what follows from them. Pure functions, unit-tested.

/// The languages the system can use
pub const LOCALES: [&str; 6] = [
    "de_CH.UTF-8",
    "fr_CH.UTF-8",
    "it_CH.UTF-8",
    "de_DE.UTF-8",
    "en_US.UTF-8",
    "en_GB.UTF-8",
];

/// Smallest disk to install on
pub const MIN_DISK_BYTES: u64 = 32 * 1024 * 1024 * 1024;
/// Least memory for an installation
pub const MIN_RAM_GIB: u64 = 4;
/// Space left for the system and /home after the swap file, in GiB
pub const MIN_FREE_GIB: u64 = 48;

/// The keyboard of the console and of the desktop for a keyboard code
pub struct Keyboard {
    pub console_map: &'static str,
    pub xkb_layout: &'static str,
    pub xkb_variant: &'static str,
}

pub fn keyboard(code: &str) -> Option<Keyboard> {
    let (console_map, xkb_layout, xkb_variant) = match code {
        "ch" => ("sg", "ch", ""),
        "ch-fr" => ("fr_CH", "ch", "fr"),
        "de" => ("de", "de", ""),
        "fr" => ("fr", "fr", ""),
        "it" => ("it", "it", ""),
        "gb" => ("uk", "gb", ""),
        "us" => ("us", "us", ""),
        _ => return None,
    };
    Some(Keyboard {
        console_map,
        xkb_layout,
        xkb_variant,
    })
}

pub fn valid_locale(locale: &str) -> bool {
    LOCALES.contains(&locale)
}

/// A login name: a lowercase letter or _ first, then up to 31 of a-z, 0-9, _ and -, not one
/// the system uses itself. Whether it already exists is checked separately.
pub fn valid_user_name(name: &str, distro_id: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first.is_ascii_lowercase() || first == '_')
        && name.len() <= 32
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
        && !["root", "nixos", "nobody", distro_id].contains(&name)
}

/// A host name: 1 to 63 of a-z, 0-9 and -, not starting or ending with -
pub fn valid_host_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 63
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && !name.starts_with('-')
        && !name.ends_with('-')
}

/// The full name: 1 to 64 characters on one line
pub fn valid_full_name(name: &str) -> bool {
    let count = name.chars().count();
    (1..=64).contains(&count) && !name.contains('\n')
}

/// A time zone name: only the characters zone names use (the caller checks it exists)
pub fn time_zone_chars(zone: &str) -> bool {
    !zone.is_empty()
        && !zone.contains("..")
        && zone
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_+/-".contains(c))
}

/// Swap size for machine.nix, e.g. "17G": as large as the RAM plus 1 GiB with hibernation,
/// otherwise the RAM up to 8 GiB
pub fn swap_size(ram_gib: u64, hibernation: bool) -> String {
    if hibernation {
        format!("{}G", ram_gib + 1)
    } else {
        format!("{}G", ram_gib.min(8))
    }
}

/// Whether hibernation fits: the swap file plus enough space left for the system
pub fn hibernation_fits(disk_gib: u64, ram_gib: u64) -> bool {
    disk_gib.saturating_sub(ram_gib + 1) >= MIN_FREE_GIB
}

/// Free text for a string in a Nix file
pub fn nix_escape(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("${", "\\${")
}

/// The answers of a front end, checked
#[derive(Debug, Clone, PartialEq)]
pub struct Answers {
    pub host_name: String,
    pub time_zone: String,
    pub locale: String,
    pub keyboard: String,
    pub user_name: String,
    pub full_name: String,
    pub disk: String,
    pub encrypt: bool,
    pub hibernation: bool,
    /// Ends the partition labels (Q6): given by the answers, else chosen at random by the core
    pub label_suffix: Option<String>,
}

impl Answers {
    /// Reads the answers file. Booleans may be JSON booleans or the strings "true" and "false".
    pub fn parse(json: &serde_json::Value) -> Result<Answers, String> {
        let text = |path: &[&str]| -> Result<String, String> {
            let mut value = json;
            for key in path {
                value = value.get(key).unwrap_or(&serde_json::Value::Null);
            }
            match value {
                serde_json::Value::String(s) if !s.is_empty() => Ok(s.clone()),
                serde_json::Value::Bool(b) => Ok(b.to_string()),
                serde_json::Value::Number(n) => Ok(n.to_string()),
                _ => Err(format!(
                    "The answers file has no value for .{}",
                    path.join(".")
                )),
            }
        };
        let flag = |key: &str| -> Result<bool, String> {
            match text(&[key])?.as_str() {
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(format!("{key} must be true or false")),
            }
        };
        Ok(Answers {
            host_name: text(&["hostName"])?,
            time_zone: text(&["timeZone"])?,
            locale: text(&["locale"])?,
            keyboard: text(&["keyboard"])?,
            user_name: text(&["user", "name"])?,
            full_name: text(&["user", "fullName"])?,
            disk: text(&["disk"])?,
            encrypt: flag("encrypt")?,
            hibernation: flag("hibernation")?,
            label_suffix: text(&["labelSuffix"]).ok(),
        })
    }

    /// Everything that can be checked without the computer
    pub fn check(&self, distro_id: &str) -> Result<(), String> {
        if !valid_host_name(&self.host_name) {
            return Err(format!("Not a valid computer name: {}", self.host_name));
        }
        if !time_zone_chars(&self.time_zone) {
            return Err(format!("Unknown time zone: {}", self.time_zone));
        }
        if !valid_locale(&self.locale) {
            return Err(format!("Unsupported language: {}", self.locale));
        }
        if keyboard(&self.keyboard).is_none() {
            return Err(format!("Unknown keyboard: {}", self.keyboard));
        }
        if !valid_user_name(&self.user_name, distro_id) {
            return Err(format!("Not a valid user name: {}", self.user_name));
        }
        if !valid_full_name(&self.full_name) {
            return Err("The name must be 1 to 64 characters on one line.".into());
        }
        if let Some(suffix) = &self.label_suffix
            && !valid_label_suffix(suffix)
        {
            return Err(format!("Not a valid label suffix: {suffix}"));
        }
        Ok(())
    }
}

/// The end of the partition labels: lowercase letters and digits, 1 to 8 (GPT allows 36
/// characters, `<id>-system-` takes the rest)
pub fn valid_label_suffix(text: &str) -> bool {
    (1..=8).contains(&text.len())
        && text
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

/// Fills the placeholders of the machine.nix template. The full name goes in last, escaped,
/// so a name with @ signs cannot look like a placeholder.
pub fn render_machine_nix(
    template: &str,
    answers: &Answers,
    swap: &str,
    state_version: &str,
) -> Result<String, String> {
    let kb = keyboard(&answers.keyboard).ok_or("Unknown keyboard")?;
    let mut content = template.to_string();
    for (key, value) in [
        ("hostName", answers.host_name.as_str()),
        ("timeZone", &answers.time_zone),
        ("locale", &answers.locale),
        ("consoleKeyMap", kb.console_map),
        ("xkbLayout", kb.xkb_layout),
        ("xkbVariant", kb.xkb_variant),
        ("userName", &answers.user_name),
        ("disk", &answers.disk),
        ("encrypt", if answers.encrypt { "true" } else { "false" }),
        ("swapSize", swap),
        (
            "hibernation",
            if answers.hibernation { "true" } else { "false" },
        ),
        ("labelSuffix", answers.label_suffix.as_deref().unwrap_or("")),
        ("stateVersion", state_version),
    ] {
        content = content.replace(&format!("@{key}@"), value);
    }
    if let Some(left) = placeholder_left(&content) {
        return Err(format!(
            "machine.nix still has an unfilled placeholder: {left}"
        ));
    }
    Ok(content.replace("@fullName@", &nix_escape(&answers.full_name)))
}

/// The first @word@ left in the text, apart from @fullName@
fn placeholder_left(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut i = 0;
    while let Some(start) = text[i..].find('@').map(|p| p + i) {
        let rest = &bytes[start + 1..];
        let len = rest.iter().take_while(|b| b.is_ascii_alphabetic()).count();
        if len > 0 && rest.get(len) == Some(&b'@') {
            let word = &text[start..start + len + 2];
            if word != "@fullName@" {
                return Some(word.to_string());
            }
            i = start + len + 2;
        } else {
            i = start + 1;
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn answers() -> Answers {
        Answers::parse(&json!({
            "hostName": "livio-laptop", "timeZone": "Europe/Zurich", "locale": "de_CH.UTF-8",
            "keyboard": "ch", "user": { "name": "livio", "fullName": "Livio" },
            "disk": "/dev/disk/by-id/ata-disk", "encrypt": true, "hibernation": true
        }))
        .unwrap()
    }

    #[test]
    fn user_names() {
        assert!(valid_user_name("livio", "strix"));
        assert!(valid_user_name("_svc-1", "strix"));
        assert!(!valid_user_name("Root", "strix"));
        assert!(!valid_user_name("root", "strix"));
        assert!(!valid_user_name("strix", "strix"));
        assert!(!valid_user_name("1abc", "strix"));
        assert!(!valid_user_name(&"a".repeat(33), "strix"));
    }

    #[test]
    fn label_suffixes() {
        assert!(valid_label_suffix("4f2a") && valid_label_suffix("test"));
        assert!(
            !valid_label_suffix("") && !valid_label_suffix("ABC") && !valid_label_suffix("a-b")
        );
        assert!(!valid_label_suffix("123456789"));
        let mut a = answers();
        a.label_suffix = Some("Bad!".into());
        assert!(a.check("strix").unwrap_err().contains("label suffix"));
        let parsed = Answers::parse(&json!({
            "hostName": "x", "timeZone": "Europe/Zurich", "locale": "de_CH.UTF-8", "keyboard": "ch",
            "user": { "name": "livio", "fullName": "Livio" }, "disk": "/dev/vda",
            "encrypt": false, "hibernation": false, "labelSuffix": "4f2a"
        }))
        .unwrap();
        assert_eq!(parsed.label_suffix.as_deref(), Some("4f2a"));
        assert_eq!(answers().label_suffix, None);
    }

    #[test]
    fn host_names() {
        assert!(valid_host_name("livio-laptop"));
        assert!(!valid_host_name("livio_laptop"));
        assert!(!valid_host_name("livio-"));
        assert!(!valid_host_name("-livio"));
        assert!(!valid_host_name(""));
    }

    #[test]
    fn full_names() {
        assert!(valid_full_name("Livio \"LD\" Müller"));
        assert!(!valid_full_name(""));
        assert!(!valid_full_name("a\nb"));
        assert!(valid_full_name(&"ü".repeat(64)));
        assert!(!valid_full_name(&"ü".repeat(65)));
    }

    #[test]
    fn locales_and_keyboards() {
        assert!(valid_locale("de_CH.UTF-8"));
        assert!(!valid_locale("xx_XX.UTF-8"));
        let ch = keyboard("ch").unwrap();
        assert_eq!(
            (ch.console_map, ch.xkb_layout, ch.xkb_variant),
            ("sg", "ch", "")
        );
        let chfr = keyboard("ch-fr").unwrap();
        assert_eq!(
            (chfr.console_map, chfr.xkb_layout, chfr.xkb_variant),
            ("fr_CH", "ch", "fr")
        );
        assert!(keyboard("xx").is_none());
    }

    #[test]
    fn time_zones() {
        assert!(time_zone_chars("Europe/Zurich"));
        assert!(time_zone_chars("America/Port-au-Prince"));
        assert!(!time_zone_chars("../etc/passwd"));
        assert!(!time_zone_chars("Europe/Zurich;rm"));
    }

    #[test]
    fn swap_and_hibernation() {
        assert_eq!(swap_size(16, true), "17G");
        assert_eq!(swap_size(4, false), "4G");
        assert_eq!(swap_size(32, false), "8G");
        assert!(hibernation_fits(64, 8));
        assert!(!hibernation_fits(40, 8));
    }

    #[test]
    fn escaping() {
        assert_eq!(nix_escape("a\"b"), "a\\\"b");
        assert_eq!(nix_escape("x${y}"), "x\\${y}");
        assert_eq!(nix_escape("a\\b"), "a\\\\b");
    }

    #[test]
    fn answers_with_false_and_strings() {
        let a = Answers::parse(&json!({
            "hostName": "strix-test", "timeZone": "Europe/Zurich", "locale": "de_CH.UTF-8",
            "keyboard": "ch", "user": { "name": "livio", "fullName": "Livio" },
            "disk": "/dev/null", "encrypt": false, "hibernation": "false"
        }))
        .unwrap();
        assert!(!a.encrypt && !a.hibernation);
        assert!(a.check("strix").is_ok());
        let missing = Answers::parse(&json!({ "hostName": "x" }));
        assert!(missing.unwrap_err().contains(".timeZone"));
    }

    #[test]
    fn machine_nix_with_tricky_name() {
        let template =
            include_str!("../../templates/machine/machine.nix").replace("@distroId@", "strix");
        let mut a = answers();
        a.full_name = r#"Tom "TJ" & ${Jerry} @hostName@ \ end"#.into();
        let out = render_machine_nix(&template, &a, "17G", "26.11").unwrap();
        assert!(out.contains(r#"description = "Tom \"TJ\" & \${Jerry} @hostName@ \\ end";"#));
        assert!(out.contains("console.keyMap = \"sg\";"));
        assert!(out.contains("layout = \"ch\";"));
        assert!(out.contains("swapSize = \"17G\";"));
        assert!(out.contains("encrypt = true;"));
        assert!(out.contains("system.stateVersion = \"26.11\";"));
        let without_name: String = out.lines().filter(|l| !l.contains("description")).collect();
        assert!(placeholder_left(&without_name).is_none());
    }

    #[test]
    fn unfilled_placeholder() {
        let err = render_machine_nix("x = \"@nothing@\";", &answers(), "8G", "26.11").unwrap_err();
        assert!(err.contains("@nothing@"));
    }
}
