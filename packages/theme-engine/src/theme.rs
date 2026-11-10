//! Themes: the theme.toml format, loading and checking.
//!
//! A theme is a folder with a theme.toml. The folder name is the theme's id.
//! See themes/README.md in the repository for the format.

use crate::color::{Color, Rgb};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// The theme.toml format this engine reads.
pub const FORMAT: i64 = 1;

/// Colors every variant must define, opaque. Adapters rely on them.
pub const REQUIRED_COLORS: [&str; 10] = [
    "background",
    "surface",
    "border",
    "text",
    "text-muted",
    "accent",
    "on-accent",
    "focus",
    "error",
    "warning",
];

/// Minimum contrast between two colors of a variant, after WCAG 2.x.
/// 4.5:1 for text, 3:1 for focus rings and other parts of the interface.
const CONTRAST_RULES: [(&str, &str, f64); 7] = [
    ("text", "background", 4.5),
    ("text", "surface", 4.5),
    ("text-muted", "surface", 4.5),
    ("on-accent", "accent", 4.5),
    ("error", "surface", 4.5),
    ("focus", "background", 3.0),
    ("focus", "surface", 3.0),
];

/// The 16 terminal colors in ANSI order (index 0 to 15).
pub const PALETTE_NAMES: [&str; 16] = [
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "bright-black",
    "bright-red",
    "bright-green",
    "bright-yellow",
    "bright-blue",
    "bright-magenta",
    "bright-cyan",
    "bright-white",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Appearance {
    Light,
    Dark,
}

impl Appearance {
    pub fn as_str(self) -> &'static str {
        match self {
            Appearance::Light => "light",
            Appearance::Dark => "dark",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Terminal {
    pub background: Rgb,
    pub foreground: Rgb,
    pub cursor: Rgb,
    pub selection: Rgb,
    /// ANSI order, see `PALETTE_NAMES`
    pub palette: [Rgb; 16],
}

#[derive(Clone, Debug)]
pub struct Variant {
    pub id: String,
    pub name: String,
    pub appearance: Appearance,
    /// Required and extra colors, sorted by name
    pub colors: BTreeMap<String, Color>,
    pub terminal: Terminal,
}

impl Variant {
    /// A required color. Loading guarantees that it exists and is opaque.
    pub fn color(&self, name: &str) -> Rgb {
        debug_assert!(
            REQUIRED_COLORS.contains(&name),
            "{name} is not a required color"
        );
        self.colors[name].rgb
    }
}

#[derive(Clone, Debug)]
pub struct Theme {
    pub id: String,
    pub name: String,
    pub description: String,
    pub default_variant: String,
    /// Sorted by id
    pub variants: BTreeMap<String, Variant>,
    pub dir: PathBuf,
}

impl Theme {
    pub fn variant(&self, id: &str) -> Option<&Variant> {
        self.variants.get(id)
    }

    /// Variant ids in display order: the default first, then the others by id.
    pub fn variant_ids(&self) -> Vec<&str> {
        let mut ids = vec![self.default_variant.as_str()];
        ids.extend(
            self.variants
                .keys()
                .map(String::as_str)
                .filter(|id| *id != self.default_variant),
        );
        ids
    }
}

// The file as written. deny_unknown_fields turns typos into errors.

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct RawTheme {
    format: i64,
    name: String,
    description: String,
    default_variant: String,
    variants: BTreeMap<String, RawVariant>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawVariant {
    name: String,
    appearance: String,
    // Extra colors are allowed, so no struct here
    colors: BTreeMap<String, String>,
    terminal: RawTerminal,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct RawTerminal {
    background: String,
    foreground: String,
    cursor: String,
    selection: String,
    black: String,
    red: String,
    green: String,
    yellow: String,
    blue: String,
    magenta: String,
    cyan: String,
    white: String,
    bright_black: String,
    bright_red: String,
    bright_green: String,
    bright_yellow: String,
    bright_blue: String,
    bright_magenta: String,
    bright_cyan: String,
    bright_white: String,
}

impl RawTerminal {
    fn palette(&self) -> [&str; 16] {
        [
            &self.black,
            &self.red,
            &self.green,
            &self.yellow,
            &self.blue,
            &self.magenta,
            &self.cyan,
            &self.white,
            &self.bright_black,
            &self.bright_red,
            &self.bright_green,
            &self.bright_yellow,
            &self.bright_blue,
            &self.bright_magenta,
            &self.bright_cyan,
            &self.bright_white,
        ]
    }
}

/// Theme and variant ids: lowercase letters, digits and hyphens, starting
/// with a letter, at most 32 characters. They end up in file names, Plymouth
/// theme names and the EFI variable.
pub fn valid_id(id: &str) -> bool {
    let mut chars = id.chars();
    matches!(chars.next(), Some('a'..='z'))
        && id.len() <= 32
        && chars.all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
        && !id.ends_with('-')
        && !id.contains("--")
}

/// Names of extra colors: like ids, at most 40 characters.
fn valid_color_name(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some('a'..='z'))
        && name.len() <= 40
        && chars.all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
        && !name.ends_with('-')
}

fn check_text(errors: &mut Vec<String>, field: &str, text: &str, max: usize) {
    if text.trim().is_empty() {
        errors.push(format!("{field} is empty"));
    } else if text.chars().count() > max {
        errors.push(format!("{field} is longer than {max} characters"));
    } else if text.chars().any(char::is_control) {
        errors.push(format!("{field} contains a control character"));
    } else if text.trim() != text {
        errors.push(format!("{field} starts or ends with a space"));
    }
}

/// Reads and checks a theme from text. `id` is the folder name.
/// Returns every problem found, not just the first.
pub fn parse(id: &str, text: &str, dir: &Path) -> Result<Theme, Vec<String>> {
    let mut errors = Vec::new();
    if !valid_id(id) {
        errors.push(format!(
            "the folder name \"{id}\" is not a valid theme id (lowercase letters, digits and single hyphens, starting with a letter, at most 32 characters)"
        ));
    }

    let table: toml::Table = match toml::from_str(text) {
        Ok(table) => table,
        Err(error) => {
            errors.push(format!("not valid TOML: {}", error.to_string().trim_end()));
            return Err(errors);
        }
    };
    // Check the format first: a newer format may look different
    match table.get("format") {
        Some(toml::Value::Integer(FORMAT)) => {}
        Some(toml::Value::Integer(other)) => {
            errors.push(format!(
                "format {other} is not supported, this engine reads format {FORMAT}"
            ));
            return Err(errors);
        }
        Some(_) => {
            errors.push(format!("format must be a number, write format = {FORMAT}"));
            return Err(errors);
        }
        None => {
            errors.push(format!(
                "format is missing, write format = {FORMAT} at the top"
            ));
            return Err(errors);
        }
    }
    // Parsed again from the text, so the messages carry line numbers
    let raw: RawTheme = match toml::from_str(text) {
        Ok(raw) => raw,
        Err(error) => {
            errors.push(error.to_string().trim_end().to_string());
            return Err(errors);
        }
    };
    debug_assert_eq!(raw.format, FORMAT);

    check_text(&mut errors, "name", &raw.name, 40);
    check_text(&mut errors, "description", &raw.description, 200);

    if raw.variants.is_empty() {
        errors.push("there is no variant, add at least one [variants.<id>]".to_string());
    }
    if !raw.variants.contains_key(&raw.default_variant) {
        errors.push(format!(
            "default-variant is \"{}\", but there is no [variants.{}]",
            raw.default_variant, raw.default_variant
        ));
    }

    let mut variants = BTreeMap::new();
    for (variant_id, raw_variant) in &raw.variants {
        match parse_variant(variant_id, raw_variant) {
            Ok(variant) => {
                variants.insert(variant_id.clone(), variant);
            }
            Err(variant_errors) => {
                errors.extend(
                    variant_errors
                        .into_iter()
                        .map(|e| format!("variant {variant_id}: {e}")),
                );
            }
        }
    }

    if errors.is_empty() {
        Ok(Theme {
            id: id.to_string(),
            name: raw.name,
            description: raw.description,
            default_variant: raw.default_variant,
            variants,
            dir: dir.to_path_buf(),
        })
    } else {
        Err(errors)
    }
}

fn parse_variant(id: &str, raw: &RawVariant) -> Result<Variant, Vec<String>> {
    let mut errors = Vec::new();
    if !valid_id(id) {
        errors.push(format!(
            "\"{id}\" is not a valid variant id (lowercase letters, digits and single hyphens, starting with a letter, at most 32 characters)"
        ));
    }
    check_text(&mut errors, "name", &raw.name, 40);

    let appearance = match raw.appearance.as_str() {
        "light" => Some(Appearance::Light),
        "dark" => Some(Appearance::Dark),
        other => {
            errors.push(format!(
                "appearance is \"{other}\", it must be \"light\" or \"dark\""
            ));
            None
        }
    };

    let mut colors = BTreeMap::new();
    for (name, value) in &raw.colors {
        let required = REQUIRED_COLORS.contains(&name.as_str());
        if !required && !valid_color_name(name) {
            errors.push(format!(
                "colors.{name}: not a valid color name (lowercase letters, digits and hyphens, starting with a letter)"
            ));
            continue;
        }
        match Color::parse(value) {
            Ok(color) if required && color.alpha.is_some() => {
                errors.push(format!(
                    "colors.{name}: must be opaque, write it as #rrggbb"
                ));
            }
            Ok(color) => {
                colors.insert(name.clone(), color);
            }
            Err(message) => errors.push(format!("colors.{name}: {message}")),
        }
    }
    for name in REQUIRED_COLORS {
        if !raw.colors.contains_key(name) {
            errors.push(format!("colors.{name} is missing"));
        }
    }

    let terminal = parse_terminal(&raw.terminal, &mut errors);

    // Every rule runs as soon as its colors could be read, so one check shows
    // all problems at once
    let rgb = |name: &str| colors.get(name).map(|color: &Color| color.rgb);
    for (fg, bg, minimum) in CONTRAST_RULES {
        if let (Some(fg_rgb), Some(bg_rgb)) = (rgb(fg), rgb(bg)) {
            let ratio = fg_rgb.contrast(bg_rgb);
            if ratio < minimum {
                errors.push(format!(
                    "colors.{fg} on colors.{bg}: contrast {ratio:.2}:1, needs at least {minimum}:1"
                ));
            }
        }
    }

    // A dark variant has light text on a dark background, and the other way round
    if let (Some(appearance), Some(background), Some(text)) =
        (appearance, rgb("background"), rgb("text"))
    {
        let background_darker = background.luminance() < text.luminance();
        match appearance {
            Appearance::Dark if !background_darker => errors.push(
                "appearance is \"dark\", but colors.background is lighter than colors.text"
                    .to_string(),
            ),
            Appearance::Light if background_darker => errors.push(
                "appearance is \"light\", but colors.background is darker than colors.text"
                    .to_string(),
            ),
            _ => {}
        }
    }

    match (errors.is_empty(), appearance, terminal) {
        (true, Some(appearance), Some(terminal)) => Ok(Variant {
            id: id.to_string(),
            name: raw.name.clone(),
            appearance,
            colors,
            terminal,
        }),
        _ => Err(errors),
    }
}

fn parse_terminal(raw: &RawTerminal, errors: &mut Vec<String>) -> Option<Terminal> {
    let mut opaque = |field: &str, value: &str| -> Option<Rgb> {
        match Color::parse(value) {
            Ok(Color { rgb, alpha: None }) => Some(rgb),
            Ok(_) => {
                errors.push(format!(
                    "terminal.{field}: must be opaque, write it as #rrggbb"
                ));
                None
            }
            Err(message) => {
                errors.push(format!("terminal.{field}: {message}"));
                None
            }
        }
    };
    let background = opaque("background", &raw.background);
    let foreground = opaque("foreground", &raw.foreground);
    let cursor = opaque("cursor", &raw.cursor);
    let selection = opaque("selection", &raw.selection);
    let palette: Vec<Option<Rgb>> = raw
        .palette()
        .iter()
        .enumerate()
        .map(|(index, value)| opaque(PALETTE_NAMES[index], value))
        .collect();

    if let (Some(background), Some(foreground)) = (background, foreground) {
        let ratio = foreground.contrast(background);
        if ratio < 4.5 {
            errors.push(format!(
                "terminal.foreground on terminal.background: contrast {ratio:.2}:1, needs at least 4.5:1"
            ));
        }
    }

    let palette: Vec<Rgb> = palette.into_iter().collect::<Option<_>>()?;
    Some(Terminal {
        background: background?,
        foreground: foreground?,
        cursor: cursor?,
        selection: selection?,
        palette: palette.try_into().ok()?,
    })
}

/// Reads one theme folder.
pub fn load(dir: &Path) -> Result<Theme, Vec<String>> {
    let id = dir
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("")
        .to_string();
    let file = dir.join("theme.toml");
    let text = fs::read_to_string(&file)
        .map_err(|error| vec![format!("cannot read {}: {error}", file.display())])?;
    parse(&id, &text, dir)
}

/// The result of reading a themes folder: the good themes and, per broken
/// theme, its problems. Both sorted by id.
pub struct Catalog {
    pub themes: Vec<Theme>,
    pub broken: Vec<(String, Vec<String>)>,
}

impl Catalog {
    /// Reads every folder in `dir`. Files next to the folders (a README) are skipped.
    pub fn load(dir: &Path) -> Result<Catalog, String> {
        let entries = fs::read_dir(dir)
            .map_err(|error| format!("cannot read the themes folder {}: {error}", dir.display()))?;
        let mut folders = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|error| {
                format!("cannot read the themes folder {}: {error}", dir.display())
            })?;
            // Follows symlinks, the themes folder in the store is often made of them
            if entry.path().is_dir() {
                folders.push(entry.path());
            }
        }
        folders.sort();
        let mut catalog = Catalog {
            themes: Vec::new(),
            broken: Vec::new(),
        };
        for folder in folders {
            match load(&folder) {
                Ok(theme) => catalog.themes.push(theme),
                Err(errors) => {
                    let id = folder
                        .file_name()
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_default();
                    catalog.broken.push((id, errors));
                }
            }
        }
        Ok(catalog)
    }

    pub fn theme(&self, id: &str) -> Option<&Theme> {
        self.themes.iter().find(|theme| theme.id == id)
    }

    /// Finds the theme and variant of a selection.
    pub fn resolve(&self, selection: &Selection) -> Result<(&Theme, &Variant), String> {
        let theme = self.theme(&selection.theme).ok_or_else(|| {
            if self.broken.iter().any(|(id, _)| *id == selection.theme) {
                format!(
                    "the theme \"{}\" has errors, run the check to see them",
                    selection.theme
                )
            } else {
                let known: Vec<&str> = self.themes.iter().map(|t| t.id.as_str()).collect();
                format!(
                    "there is no theme \"{}\" (known: {})",
                    selection.theme,
                    known.join(", ")
                )
            }
        })?;
        let variant_id = selection
            .variant
            .as_deref()
            .unwrap_or(&theme.default_variant);
        let variant = theme.variant(variant_id).ok_or_else(|| {
            format!(
                "the theme \"{}\" has no variant \"{variant_id}\" (it has: {})",
                theme.id,
                theme.variant_ids().join(", ")
            )
        })?;
        Ok((theme, variant))
    }
}

/// A theme with an optional variant, written "theme" or "theme:variant".
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Selection {
    pub theme: String,
    pub variant: Option<String>,
}

impl Selection {
    pub fn parse(text: &str) -> Result<Selection, String> {
        let text = text.trim();
        let (theme, variant) = match text.split_once(':') {
            Some((theme, variant)) => (theme, Some(variant)),
            None => (text, None),
        };
        if !valid_id(theme) {
            return Err(format!(
                "\"{text}\" is not a theme, write it as <theme> or <theme>:<variant>"
            ));
        }
        if let Some(variant) = variant
            && !valid_id(variant)
        {
            return Err(format!(
                "\"{text}\" is not a theme, write it as <theme> or <theme>:<variant>"
            ));
        }
        Ok(Selection {
            theme: theme.to_string(),
            variant: variant.map(str::to_string),
        })
    }

    /// The selection with the variant filled in.
    pub fn resolved(theme: &Theme, variant: &Variant) -> Selection {
        Selection {
            theme: theme.id.clone(),
            variant: Some(variant.id.clone()),
        }
    }
}

impl std::fmt::Display for Selection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.variant {
            Some(variant) => write!(f, "{}:{variant}", self.theme),
            None => f.write_str(&self.theme),
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub const GOOD: &str = r##"
format = 1
name = "Test"
description = "A theme for the tests."
default-variant = "dark"

[variants.dark]
name = "Dark"
appearance = "dark"

[variants.dark.colors]
background = "#000000"
surface = "#111111"
border = "#2a2a2a"
text = "#ffffff"
text-muted = "#808080"
accent = "#c8102e"
on-accent = "#ffffff"
focus = "#c8102e"
error = "#ff5c6a"
warning = "#f2c230"
shade = "#00000080"

[variants.dark.terminal]
background = "#000000"
foreground = "#ffffff"
cursor = "#c8102e"
selection = "#3a3a3a"
black = "#000000"
red = "#c8102e"
green = "#3fa34d"
yellow = "#e0b000"
blue = "#3b82f6"
magenta = "#b0408a"
cyan = "#2aa198"
white = "#c8c8c8"
bright-black = "#6b6b6b"
bright-red = "#ff4d5e"
bright-green = "#6fd17a"
bright-yellow = "#ffd24a"
bright-blue = "#7aa7ff"
bright-magenta = "#e07ac0"
bright-cyan = "#5fd7d0"
bright-white = "#ffffff"
"##;

    pub fn good() -> Theme {
        parse("test", GOOD, Path::new("/themes/test")).expect("the good theme parses")
    }

    fn errors(text: &str) -> Vec<String> {
        parse("test", text, Path::new("/x")).expect_err("should fail")
    }

    fn has(errors: &[String], needle: &str) -> bool {
        errors.iter().any(|e| e.contains(needle))
    }

    #[test]
    fn reads_a_good_theme() {
        let theme = good();
        assert_eq!(theme.id, "test");
        assert_eq!(theme.name, "Test");
        assert_eq!(theme.default_variant, "dark");
        let variant = theme.variant("dark").unwrap();
        assert_eq!(variant.appearance, Appearance::Dark);
        assert_eq!(variant.color("accent"), Rgb::new(200, 16, 46));
        assert_eq!(variant.colors["shade"].alpha, Some(0x80));
        assert_eq!(variant.terminal.palette[1], Rgb::new(200, 16, 46));
        assert_eq!(variant.terminal.palette[15], Rgb::new(255, 255, 255));
        assert_eq!(theme.variant_ids(), vec!["dark"]);
    }

    #[test]
    fn variant_order_puts_the_default_first() {
        let text = GOOD.replace("default-variant = \"dark\"", "default-variant = \"zed\"")
            + &GOOD[GOOD.find("[variants.dark]").unwrap()..]
                .replace("variants.dark", "variants.zed")
            + &GOOD[GOOD.find("[variants.dark]").unwrap()..]
                .replace("variants.dark", "variants.alpha");
        let theme = parse("test", &text, Path::new("/x")).unwrap();
        assert_eq!(theme.variant_ids(), vec!["zed", "alpha", "dark"]);
    }

    #[test]
    fn format_is_checked_first() {
        assert!(has(
            &errors(&GOOD.replace("format = 1", "format = 2")),
            "format 2 is not supported"
        ));
        assert!(has(
            &errors(&GOOD.replace("format = 1", "")),
            "format is missing"
        ));
        assert!(has(
            &errors(&GOOD.replace("format = 1", "format = \"1\"")),
            "format must be a number"
        ));
    }

    #[test]
    fn typos_are_errors() {
        assert!(has(
            &errors(&GOOD.replace("default-variant", "default_variant")),
            "default_variant"
        ));
        assert!(has(
            &errors(&GOOD.replace("bright-white", "bright-whte")),
            "bright-whte"
        ));
        assert!(has(
            &errors(&GOOD.replace(
                "appearance = \"dark\"",
                "appearance = \"dark\"\nicon = \"x\""
            )),
            "icon"
        ));
        assert!(has(&errors("format = 1\nname = ["), "not valid TOML"));
    }

    #[test]
    fn missing_and_wrong_colors() {
        let e = errors(&GOOD.replace("on-accent = \"#ffffff\"\n", ""));
        assert!(has(&e, "colors.on-accent is missing"), "{e:?}");
        assert!(has(
            &errors(&GOOD.replace("\"#c8102e\"\non-accent", "\"red\"\non-accent")),
            "colors.accent: \"red\" is not a color"
        ));
        assert!(has(
            &errors(&GOOD.replace("text = \"#ffffff\"", "text = \"#ffffffcc\"")),
            "colors.text: must be opaque"
        ));
        assert!(has(
            &errors(&GOOD.replace("shade = ", "Shade = ")),
            "colors.Shade: not a valid color name"
        ));
        assert!(has(
            &errors(&GOOD.replace("cursor = \"#c8102e\"", "cursor = \"#c8102e80\"")),
            "terminal.cursor: must be opaque"
        ));
        assert!(has(
            &errors(&GOOD.replace("green = \"#3fa34d\"", "green = \"#3fa34\"")),
            "terminal.green:"
        ));
    }

    #[test]
    fn every_problem_is_reported() {
        let text = GOOD
            .replace("text = \"#ffffff\"", "text = \"nope\"")
            .replace("cyan = \"#2aa198\"", "cyan = \"x\"")
            .replace("name = \"Test\"", "name = \"\"");
        let e = errors(&text);
        assert!(has(&e, "colors.text:"), "{e:?}");
        assert!(has(&e, "terminal.cyan:"), "{e:?}");
        assert!(has(&e, "name is empty"), "{e:?}");
        // Contrast is checked even when other values are broken
        let text = GOOD
            .replace("text-muted = \"#808080\"", "text-muted = \"#444444\"")
            .replace("warning = \"#f2c230\"\n", "")
            .replace("cyan = \"#2aa198\"", "cyan = \"x\"")
            .replace("foreground = \"#ffffff\"", "foreground = \"#222222\"");
        let e = errors(&text);
        assert!(has(&e, "colors.warning is missing"), "{e:?}");
        assert!(has(&e, "colors.text-muted on colors.surface"), "{e:?}");
        assert!(has(&e, "terminal.cyan:"), "{e:?}");
        assert!(
            has(&e, "terminal.foreground on terminal.background"),
            "{e:?}"
        );
    }

    #[test]
    fn default_variant_must_exist() {
        assert!(has(
            &errors(&GOOD.replace("default-variant = \"dark\"", "default-variant = \"light\"")),
            "there is no [variants.light]"
        ));
    }

    #[test]
    fn contrast_is_checked() {
        let e = errors(&GOOD.replace("text-muted = \"#808080\"", "text-muted = \"#444444\""));
        assert!(
            has(&e, "colors.text-muted on colors.surface: contrast 1.9"),
            "{e:?}"
        );
        let e = errors(&GOOD.replace("on-accent = \"#ffffff\"", "on-accent = \"#000000\""));
        assert!(has(&e, "colors.on-accent on colors.accent"), "{e:?}");
        let e = errors(&GOOD.replace("foreground = \"#ffffff\"", "foreground = \"#333333\""));
        assert!(
            has(&e, "terminal.foreground on terminal.background"),
            "{e:?}"
        );
    }

    #[test]
    fn appearance_must_match_the_colors() {
        assert!(has(
            &errors(&GOOD.replace("appearance = \"dark\"", "appearance = \"light\"")),
            "background is darker than colors.text"
        ));
        assert!(has(
            &errors(&GOOD.replace("appearance = \"dark\"", "appearance = \"dim\"")),
            "must be \"light\" or \"dark\""
        ));
    }

    #[test]
    fn ids() {
        for good in ["neutral", "chamber", "a", "a1", "high-contrast", "x2-y3"] {
            assert!(valid_id(good), "{good}");
        }
        for bad in [
            "",
            "Neutral",
            "1st",
            "-a",
            "a-",
            "a--b",
            "a_b",
            "a b",
            "a:b",
            "ä",
            &"a".repeat(33),
        ] {
            assert!(!valid_id(bad), "{bad}");
        }
        assert!(has(
            &errors(
                &GOOD
                    .replace("[variants.dark", "[variants.Dark")
                    .replace("\"dark\"\n\n[", "\"Dark\"\n\n[")
            ),
            "\"Dark\" is not a valid variant id"
        ));
        assert!(parse("Bad", GOOD, Path::new("/x")).is_err());
    }

    #[test]
    fn texts() {
        assert!(has(
            &errors(&GOOD.replace("name = \"Test\"", "name = \" Test\"")),
            "starts or ends with a space"
        ));
        assert!(has(
            &errors(&GOOD.replace("name = \"Test\"", "name = \"Te\\u0007st\"")),
            "control character"
        ));
        assert!(has(
            &errors(&GOOD.replace("name = \"Test\"", &format!("name = \"{}\"", "x".repeat(41)))),
            "longer than 40"
        ));
    }

    #[test]
    fn selections() {
        assert_eq!(
            Selection::parse("chamber").unwrap(),
            Selection {
                theme: "chamber".into(),
                variant: None
            }
        );
        assert_eq!(
            Selection::parse(" chamber:dark\n").unwrap(),
            Selection {
                theme: "chamber".into(),
                variant: Some("dark".into())
            }
        );
        for bad in [
            "",
            ":",
            "chamber:",
            ":dark",
            "Chamber",
            "chamber:dark:x",
            "chamber dark",
            "../etc",
        ] {
            assert!(Selection::parse(bad).is_err(), "{bad:?}");
        }
        assert_eq!(
            Selection::parse("chamber:dark").unwrap().to_string(),
            "chamber:dark"
        );
        assert_eq!(Selection::parse("chamber").unwrap().to_string(), "chamber");
    }

    #[test]
    fn resolving() {
        let catalog = Catalog {
            themes: vec![good()],
            broken: vec![("broken".into(), vec!["x".into()])],
        };
        let (theme, variant) = catalog.resolve(&Selection::parse("test").unwrap()).unwrap();
        assert_eq!((theme.id.as_str(), variant.id.as_str()), ("test", "dark"));
        assert!(
            catalog
                .resolve(&Selection::parse("test:light").unwrap())
                .unwrap_err()
                .contains("has no variant \"light\" (it has: dark)")
        );
        assert!(
            catalog
                .resolve(&Selection::parse("other").unwrap())
                .unwrap_err()
                .contains("there is no theme \"other\" (known: test)")
        );
        assert!(
            catalog
                .resolve(&Selection::parse("broken").unwrap())
                .unwrap_err()
                .contains("has errors")
        );
    }
}
