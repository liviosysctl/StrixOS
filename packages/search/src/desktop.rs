//! Desktop entries (freedesktop.org Desktop Entry Specification 1.5): the files apps install
//! under `applications/` so that menus and launchers find them.

use std::collections::HashMap;

/// The groups of one file, each a map of key to raw value.
pub struct DesktopFile {
    groups: Vec<(String, HashMap<String, String>)>,
}

impl DesktopFile {
    pub fn parse(text: &str) -> DesktopFile {
        let mut groups: Vec<(String, HashMap<String, String>)> = Vec::new();
        for line in text.lines() {
            let line = line.trim_end();
            let trimmed = line.trim_start();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if let Some(name) = trimmed.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
                groups.push((name.to_string(), HashMap::new()));
                continue;
            }
            if let (Some((key, value)), Some(group)) = (trimmed.split_once('='), groups.last_mut())
            {
                // the first value of a key counts, as in GLib
                group
                    .1
                    .entry(key.trim().to_string())
                    .or_insert_with(|| value.trim().to_string());
            }
        }
        DesktopFile { groups }
    }

    pub fn group(&self, name: &str) -> Option<Group<'_>> {
        self.groups
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, keys)| Group { keys })
    }
}

/// One group, read with the escapes and locales of the specification.
pub struct Group<'a> {
    keys: &'a HashMap<String, String>,
}

impl Group<'_> {
    pub fn raw(&self, key: &str) -> Option<&str> {
        self.keys.get(key).map(String::as_str)
    }

    pub fn string(&self, key: &str) -> Option<String> {
        self.raw(key).map(unescape)
    }

    pub fn boolean(&self, key: &str) -> bool {
        self.raw(key) == Some("true")
    }

    /// A localised string: `Name[de_CH]`, then `Name[de]`, then `Name`.
    pub fn localised(&self, key: &str, locale: &Locale) -> Option<String> {
        for variant in locale.variants() {
            if let Some(v) = self.raw(&format!("{key}[{variant}]")) {
                return Some(unescape(v));
            }
        }
        self.string(key)
    }

    /// A list separated by `;`, where `\;` is a literal semicolon.
    pub fn list(&self, key: &str) -> Vec<String> {
        self.raw(key).map(split_list).unwrap_or_default()
    }

    pub fn localised_list(&self, key: &str, locale: &Locale) -> Vec<String> {
        for variant in locale.variants() {
            if let Some(v) = self.raw(&format!("{key}[{variant}]")) {
                return split_list(v);
            }
        }
        self.list(key)
    }
}

/// The language of messages, from `LC_ALL`, `LC_MESSAGES` or `LANG`, as the specification matches it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Locale {
    lang: String,
    country: Option<String>,
    modifier: Option<String>,
}

impl Locale {
    pub fn from_env() -> Locale {
        for var in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let Ok(v) = std::env::var(var)
                && !v.is_empty()
            {
                return Locale::parse(&v);
            }
        }
        Locale::default()
    }

    /// `de_CH.UTF-8@euro` and the like; `C` and `POSIX` mean no locale.
    pub fn parse(text: &str) -> Locale {
        let (rest, modifier) = match text.split_once('@') {
            Some((r, m)) => (r, Some(m.to_string())),
            None => (text, None),
        };
        let rest = rest.split('.').next().unwrap_or("");
        let (lang, country) = match rest.split_once('_') {
            Some((l, c)) => (l.to_string(), Some(c.to_string())),
            None => (rest.to_string(), None),
        };
        if lang == "C" || lang == "POSIX" {
            return Locale::default();
        }
        Locale {
            lang,
            country,
            modifier,
        }
    }

    fn variants(&self) -> Vec<String> {
        if self.lang.is_empty() {
            return Vec::new();
        }
        let mut out = Vec::new();
        if let (Some(c), Some(m)) = (&self.country, &self.modifier) {
            out.push(format!("{}_{c}@{m}", self.lang));
        }
        if let Some(c) = &self.country {
            out.push(format!("{}_{c}", self.lang));
        }
        if let Some(m) = &self.modifier {
            out.push(format!("{}@{m}", self.lang));
        }
        out.push(self.lang.clone());
        out
    }
}

fn unescape(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

fn split_list(raw: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut chars = raw.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => match chars.next() {
                Some(';') => cur.push(';'),
                Some(other) => {
                    cur.push('\\');
                    cur.push(other);
                }
                None => {}
            },
            ';' => out.push(std::mem::take(&mut cur)),
            _ => cur.push(c),
        }
    }
    out.push(cur);
    out.into_iter()
        .map(|s| unescape(&s))
        .filter(|s| !s.is_empty())
        .collect()
}

/// The argument list of an `Exec` line, with the field codes filled in for a start without files.
/// `None` when the line cannot be split (an unclosed quote).
pub fn exec_argv(exec: &str, name: &str, icon: Option<&str>, file: &str) -> Option<Vec<String>> {
    let mut args = Vec::new();
    for word in split_exec(exec)? {
        match word.as_str() {
            "%f" | "%F" | "%u" | "%U" | "%d" | "%D" | "%n" | "%N" | "%v" | "%m" => continue,
            "%i" => {
                if let Some(icon) = icon {
                    args.push("--icon".to_string());
                    args.push(icon.to_string());
                }
                continue;
            }
            _ => {}
        }
        let mut out = String::new();
        let mut chars = word.chars().peekable();
        while let Some(c) = chars.next() {
            if c != '%' {
                out.push(c);
                continue;
            }
            match chars.next() {
                Some('%') => out.push('%'),
                Some('c') => out.push_str(name),
                Some('k') => out.push_str(file),
                // a field code inside a word that needs files: the word goes away
                Some('f' | 'F' | 'u' | 'U' | 'd' | 'D' | 'n' | 'N' | 'v' | 'm' | 'i') => {}
                Some(other) => {
                    out.push('%');
                    out.push(other);
                }
                None => out.push('%'),
            }
        }
        if !out.is_empty() {
            args.push(out);
        }
    }
    if args.is_empty() { None } else { Some(args) }
}

/// Splits an `Exec` value into words: spaces separate, double quotes group, and inside quotes
/// `\"`, `` \` ``, `\$` and `\\` stand for the character.
fn split_exec(exec: &str) -> Option<Vec<String>> {
    let exec = unescape(exec);
    let mut words = Vec::new();
    let mut cur = String::new();
    let mut in_word = false;
    let mut quoted = false;
    let mut chars = exec.chars();
    while let Some(c) = chars.next() {
        if quoted {
            match c {
                '"' => quoted = false,
                '\\' => match chars.next() {
                    Some(n @ ('"' | '`' | '$' | '\\')) => cur.push(n),
                    Some(n) => {
                        cur.push('\\');
                        cur.push(n);
                    }
                    None => return None,
                },
                _ => cur.push(c),
            }
            continue;
        }
        match c {
            '"' => {
                quoted = true;
                in_word = true;
            }
            ' ' | '\t' => {
                if in_word {
                    words.push(std::mem::take(&mut cur));
                    in_word = false;
                }
            }
            _ => {
                cur.push(c);
                in_word = true;
            }
        }
    }
    if quoted {
        return None;
    }
    if in_word {
        words.push(cur);
    }
    Some(words)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIREFOX: &str = "[Desktop Entry]\nType=Application\nName=Firefox\nName[de]=Firefox Webbrowser\nGenericName=Web Browser\nKeywords=Internet;WWW;Browser\\;Web;\nExec=firefox --name firefox %U\nIcon=firefox\nActions=new-private-window;\n\n[Desktop Action new-private-window]\nName=New private window\nName[de]=Neues privates Fenster\nExec=firefox --private-window %U\n";

    #[test]
    fn reads_groups_and_localised_names() {
        let f = DesktopFile::parse(FIREFOX);
        let e = f.group("Desktop Entry").unwrap();
        assert_eq!(
            e.localised("Name", &Locale::parse("de_CH.UTF-8"))
                .as_deref(),
            Some("Firefox Webbrowser")
        );
        assert_eq!(
            e.localised("Name", &Locale::parse("fr_CH.UTF-8"))
                .as_deref(),
            Some("Firefox")
        );
        assert_eq!(
            e.localised("Name", &Locale::parse("C")).as_deref(),
            Some("Firefox")
        );
        assert_eq!(e.list("Keywords"), ["Internet", "WWW", "Browser;Web"]);
        let a = f.group("Desktop Action new-private-window").unwrap();
        assert_eq!(
            a.localised("Name", &Locale::parse("de")).as_deref(),
            Some("Neues privates Fenster")
        );
    }

    #[test]
    fn exec_drops_file_codes_and_keeps_quotes() {
        assert_eq!(
            exec_argv("firefox --name firefox %U", "Firefox", None, "/f").unwrap(),
            ["firefox", "--name", "firefox"]
        );
        assert_eq!(
            exec_argv(r#"sh -c "echo \"a b\" \$HOME" %f"#, "X", None, "/f").unwrap(),
            ["sh", "-c", r#"echo "a b" $HOME"#]
        );
        assert_eq!(
            exec_argv("app %i --title=%c 100%%", "App", Some("app-icon"), "/f").unwrap(),
            ["app", "--icon", "app-icon", "--title=App", "100%"]
        );
        assert_eq!(exec_argv("broken \"quote", "X", None, "/f"), None);
        assert_eq!(exec_argv("%U", "X", None, "/f"), None);
    }
}
