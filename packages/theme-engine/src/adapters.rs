//! Adapters: turn a theme variant into what a program reads.
//! Everything here is pure, the parts that touch the system are in system.rs.

use crate::color::Rgb;
use crate::theme::{FORMAT, PALETTE_NAMES, Theme, Variant};
use serde_json::{Map, Value, json};

/// tokens.json: the selected variant for programs that read the tokens
/// directly (Quickshell). Colors keep their names from theme.toml.
pub fn tokens(theme: &Theme, variant: &Variant) -> Value {
    let colors: Map<String, Value> = variant
        .colors
        .iter()
        .map(|(name, color)| (name.clone(), Value::String(color.hex())))
        .collect();
    let terminal = &variant.terminal;
    json!({
        "format": FORMAT,
        "theme": theme.id,
        "name": theme.name,
        "description": theme.description,
        "variant": variant.id,
        "variant-name": variant.name,
        "appearance": variant.appearance.as_str(),
        "dir": theme.dir.to_string_lossy(),
        "colors": colors,
        "terminal": {
            "background": terminal.background.hex(),
            "foreground": terminal.foreground.hex(),
            "cursor": terminal.cursor.hex(),
            "selection": terminal.selection.hex(),
            "palette": terminal.palette.iter().map(|c| c.hex()).collect::<Vec<_>>(),
        },
    })
}

/// An extra color by name, else a required one (themes from outside may lack the extras)
fn extra_or(variant: &Variant, extra: &str, required: &str) -> Rgb {
    variant
        .colors
        .get(extra)
        .map(|c| c.rgb)
        .unwrap_or_else(|| variant.color(required))
}

fn bare(color: Rgb) -> String {
    color.hex().trim_start_matches('#').to_string()
}

/// hyprland.lua: the window borders and the background behind everything, as Hyprland's Lua
/// configuration requires it. The active border is `border-active` of the design system (the
/// accent quietened), else the accent; the inactive one `border`.
pub fn hyprland(theme: &Theme, variant: &Variant) -> String {
    let active = extra_or(variant, "border-active", "accent");
    let inactive = variant.color("border");
    let background = variant.color("background");
    format!(
        "-- The colors of {name} ({id}:{variant_id}), written by the theme engine.\n\
         hl.config({{\n\
         \x20   general = {{ col = {{ active_border = \"rgb({active})\", inactive_border = \"rgb({inactive})\" }} }},\n\
         \x20   misc = {{ background_color = 0x{background} }},\n\
         }})\n",
        name = theme.name,
        id = theme.id,
        variant_id = variant.id,
        active = bare(active),
        inactive = bare(inactive),
        background = bare(background),
    )
}

/// ghostty: the terminal colors as a Ghostty config file
pub fn ghostty(theme: &Theme, variant: &Variant) -> String {
    let t = &variant.terminal;
    let mut out = format!(
        "# The colors of {} ({}:{}), written by the theme engine.\n\
         background = {}\nforeground = {}\ncursor-color = {}\n\
         selection-background = {}\nselection-foreground = {}\n",
        theme.name,
        theme.id,
        variant.id,
        t.background.hex(),
        t.foreground.hex(),
        t.cursor.hex(),
        t.selection.hex(),
        t.foreground.hex(),
    );
    for (index, color) in t.palette.iter().enumerate() {
        out.push_str(&format!("palette = {index}={}\n", color.hex()));
    }
    out
}

/// The named colors of libadwaita (and adw-gtk3) for one variant, in the order they are written
fn gtk_colors(variant: &Variant) -> Vec<(&'static str, Rgb)> {
    let background = variant.color("background");
    let surface = variant.color("surface");
    let raised = extra_or(variant, "surface-raised", "surface");
    let sunken = extra_or(variant, "surface-sunken", "background");
    let text = variant.color("text");
    let accent = variant.color("accent");
    let on_accent = variant.color("on-accent");
    let error = variant.color("error");
    let warning = variant.color("warning");
    let success = extra_or(variant, "success", "accent");
    // Text on a colored fill: the one of text and background that reads better
    let on = |fill: Rgb| {
        if fill.contrast(text) >= fill.contrast(background) {
            text
        } else {
            background
        }
    };
    vec![
        ("accent_color", accent),
        ("accent_bg_color", accent),
        ("accent_fg_color", on_accent),
        ("destructive_color", error),
        ("destructive_bg_color", error),
        ("destructive_fg_color", on(error)),
        ("error_color", error),
        ("error_bg_color", error),
        ("error_fg_color", on(error)),
        ("warning_color", warning),
        ("warning_bg_color", warning),
        ("warning_fg_color", on(warning)),
        ("success_color", success),
        ("success_bg_color", success),
        ("success_fg_color", on(success)),
        ("window_bg_color", background),
        ("window_fg_color", text),
        ("view_bg_color", sunken),
        ("view_fg_color", text),
        ("headerbar_bg_color", surface),
        ("headerbar_fg_color", text),
        ("headerbar_backdrop_color", background),
        ("sidebar_bg_color", surface),
        ("sidebar_fg_color", text),
        ("sidebar_backdrop_color", background),
        ("secondary_sidebar_bg_color", surface),
        ("secondary_sidebar_fg_color", text),
        ("card_bg_color", surface),
        ("card_fg_color", text),
        ("dialog_bg_color", raised),
        ("dialog_fg_color", text),
        ("popover_bg_color", raised),
        ("popover_fg_color", text),
        ("thumbnail_bg_color", raised),
        ("thumbnail_fg_color", text),
    ]
}

/// gtk.css for GTK 3 (adw-gtk3 and the default theme read the libadwaita names): named colors only,
/// GTK 3 does not know CSS variables
pub fn gtk3(theme: &Theme, variant: &Variant) -> String {
    let mut out = format!(
        "/* The colors of {} ({}:{}), written by the theme engine. */\n",
        theme.name, theme.id, variant.id
    );
    for (name, color) in gtk_colors(variant) {
        out.push_str(&format!("@define-color {name} {};\n", color.hex()));
    }
    out
}

/// gtk.css for GTK 4: the named colors for libadwaita before 1.6 and the same as CSS variables
/// (`--accent-bg-color`) for libadwaita 1.6 and later
pub fn gtk4(theme: &Theme, variant: &Variant) -> String {
    let colors = gtk_colors(variant);
    let mut out = gtk3(theme, variant);
    out.push_str("\n:root {\n");
    for (name, color) in &colors {
        out.push_str(&format!(
            "  --{}: {};\n",
            name.replace('_', "-"),
            color.hex()
        ));
    }
    out.push_str("}\n");
    out
}

/// The console palette as the kernel takes it (`PIO_CMAP`): 16 RGB triples in
/// ANSI order. The console draws its text in color 7 on color 0, so those two
/// become the terminal's foreground and background. The console then looks
/// like the terminal, at the price of ANSI white and black matching them.
pub fn console_palette(variant: &Variant) -> [u8; 48] {
    let terminal = &variant.terminal;
    let mut colors = terminal.palette;
    colors[0] = terminal.background;
    colors[7] = terminal.foreground;
    let mut bytes = [0u8; 48];
    for (index, color) in colors.iter().enumerate() {
        bytes[index * 3] = color.r;
        bytes[index * 3 + 1] = color.g;
        bytes[index * 3 + 2] = color.b;
    }
    bytes
}

/// Shell variables for the console installer: accent, shadow and faint text,
/// each as true color ("r;g;b"), xterm 256-color index and, for the accent,
/// the closest of the 16 console colors.
pub fn installer(theme: &Theme, variant: &Variant) -> String {
    let terminal = &variant.terminal;
    let accent = variant.color("accent");
    // The shadow under the logo: the accent sunk into the background
    let shadow = accent.mix(terminal.background, 0.58);
    let faint = variant.color("text-muted");
    // Colors 1 to 15: 0 is the background of the console
    let accent_16 = 1 + accent.nearest_in(&terminal.palette[1..]);
    let line = |name: &str, color: Rgb| -> String {
        format!(
            "THEME_{name}_RGB='{}'\nTHEME_{name}_256={}\n",
            color.sgr(),
            color.nearest_xterm256()
        )
    };
    format!(
        "# Generated by the theme engine from {}:{}. Do not edit.\n# shellcheck disable=SC2034\nTHEME_ACCENT_HEX='{}'\n{}THEME_ACCENT_16={}\n{}{}",
        theme.id,
        variant.id,
        accent.hex(),
        line("ACCENT", accent),
        accent_16,
        line("SHADOW", shadow),
        line("FAINT", faint),
    )
}

/// Background, text and accent for the Plymouth theme, as rrggbb without '#'.
pub fn plymouth_colors(variant: &Variant) -> String {
    let hex = |name: &str| variant.color(name).hex()[1..].to_string();
    format!("{} {} {}\n", hex("background"), hex("text"), hex("accent"))
}

/// Name of the Plymouth theme built for a variant.
pub fn plymouth_name(prefix: &str, theme: &str, variant: &str) -> String {
    format!("{prefix}{theme}-{variant}")
}

/// Sets Theme= in the [Daemon] section of a plymouthd.conf, keeping every other line.
pub fn plymouth_conf(conf: &str, theme: &str) -> String {
    let mut out = Vec::new();
    let mut in_daemon = false;
    let mut seen_daemon = false;
    let mut written = false;
    for line in conf.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            // Leaving [Daemon] without a Theme= line: add it at its end
            if in_daemon && !written {
                out.push(format!("Theme={theme}"));
                written = true;
            }
            in_daemon = trimmed.eq_ignore_ascii_case("[Daemon]");
            seen_daemon |= in_daemon;
            out.push(line.to_string());
            continue;
        }
        let is_theme = trimmed
            .split_once('=')
            .is_some_and(|(key, _)| key.trim() == "Theme");
        if in_daemon && is_theme {
            if !written {
                out.push(format!("Theme={theme}"));
                written = true;
            }
            // A second Theme= line is dropped
            continue;
        }
        out.push(line.to_string());
    }
    if !written {
        if !seen_daemon {
            out.push("[Daemon]".to_string());
        }
        out.push(format!("Theme={theme}"));
    }
    out.join("\n") + "\n"
}

/// Everything `set` takes, for shell completion: per theme first the theme
/// alone (its default variant), then each variant, as "<name>\t<description>".
/// Shells show the description next to the name.
pub fn names(themes: &[Theme]) -> Vec<String> {
    let mut lines = Vec::new();
    for theme in themes {
        let default = &theme.variants[&theme.default_variant];
        lines.push(format!("{}\t{} ({})", theme.id, theme.name, default.name));
        for variant_id in theme.variant_ids() {
            let variant = &theme.variants[variant_id];
            lines.push(format!(
                "{}:{}\t{} · {}",
                theme.id, variant.id, theme.name, variant.name
            ));
        }
    }
    lines
}

/// Human-readable list of the palette, for `show`.
pub fn palette_lines(variant: &Variant) -> Vec<String> {
    PALETTE_NAMES
        .iter()
        .zip(variant.terminal.palette.iter())
        .map(|(name, color)| format!("{name:<15}{color}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::tests::good;

    #[test]
    fn gtk_follows_the_variant() {
        let theme = good();
        let variant = theme.variant("dark").unwrap();
        let three = gtk3(&theme, variant);
        let four = gtk4(&theme, variant);
        let accent = variant.color("accent").hex();
        assert!(three.contains(&format!("@define-color accent_bg_color {accent};")));
        assert!(!three.contains(":root"));
        assert!(four.contains(&format!("--accent-bg-color: {accent};")));
        assert!(four.starts_with(&three));
        assert!(four.contains("--window-bg-color:"));
    }

    #[test]
    fn hyprland_and_ghostty() {
        let theme = good();
        let variant = theme.variant("dark").unwrap();
        let lua = hyprland(&theme, variant);
        // no border-active in the test theme: the accent
        assert!(lua.contains("active_border = \"rgb(c8102e)\""), "{lua}");
        assert!(lua.contains("inactive_border = \"rgb(2a2a2a)\""), "{lua}");
        assert!(lua.contains("background_color = 0x000000"), "{lua}");
        assert!(lua.starts_with("-- The colors of Test (test:dark)"));
        let ghostty = ghostty(&theme, variant);
        assert!(ghostty.contains("background = #000000\n"));
        assert!(ghostty.contains("cursor-color = #c8102e\n"));
        assert!(ghostty.contains("palette = 1=#c8102e\n"));
        assert!(ghostty.contains("palette = 15=#ffffff\n"));
        assert_eq!(ghostty.matches("palette = ").count(), 16);
    }

    #[test]
    fn tokens_hold_every_color() {
        let theme = good();
        let value = tokens(&theme, &theme.variants["dark"]);
        assert_eq!(value["format"], 1);
        assert_eq!(value["theme"], "test");
        assert_eq!(value["variant"], "dark");
        assert_eq!(value["variant-name"], "Dark");
        assert_eq!(value["appearance"], "dark");
        assert_eq!(value["dir"], "/themes/test");
        assert_eq!(value["colors"]["accent"], "#c8102e");
        assert_eq!(value["colors"]["shade"], "#00000080");
        assert_eq!(value["colors"].as_object().unwrap().len(), 11);
        assert_eq!(value["terminal"]["palette"].as_array().unwrap().len(), 16);
        assert_eq!(value["terminal"]["palette"][1], "#c8102e");
        assert_eq!(value["terminal"]["selection"], "#3a3a3a");
    }

    #[test]
    fn console_palette_uses_terminal_background_and_foreground() {
        let mut theme = good();
        let variant = theme.variants.get_mut("dark").unwrap();
        variant.terminal.background = Rgb::new(1, 2, 3);
        variant.terminal.foreground = Rgb::new(250, 251, 252);
        let bytes = console_palette(variant);
        assert_eq!(&bytes[0..3], &[1, 2, 3]);
        assert_eq!(&bytes[3..6], &[200, 16, 46]);
        assert_eq!(&bytes[21..24], &[250, 251, 252]);
        assert_eq!(&bytes[45..48], &[255, 255, 255]);
    }

    #[test]
    fn installer_values_match_the_old_installer() {
        let theme = good();
        let text = installer(&theme, &theme.variants["dark"]);
        for expected in [
            "THEME_ACCENT_HEX='#c8102e'",
            "THEME_ACCENT_RGB='200;16;46'",
            "THEME_ACCENT_256=160",
            "THEME_ACCENT_16=1",
            "THEME_SHADOW_RGB='84;7;19'",
            "THEME_SHADOW_256=52",
            "THEME_FAINT_RGB='128;128;128'",
            "THEME_FAINT_256=244",
        ] {
            assert!(
                text.lines().any(|line| line == expected),
                "missing {expected} in\n{text}"
            );
        }
        assert!(text.starts_with("# Generated by the theme engine from test:dark."));
    }

    #[test]
    fn plymouth() {
        let theme = good();
        assert_eq!(
            plymouth_colors(&theme.variants["dark"]),
            "000000 ffffff c8102e\n"
        );
        assert_eq!(plymouth_name("os-", "janus", "dark"), "os-janus-dark");
    }

    #[test]
    fn plymouth_conf_replaces_the_theme() {
        let conf = "[Daemon]\nShowDelay=0\nTheme=os-saturnus-dark\nDeviceTimeout=8\n";
        assert_eq!(
            plymouth_conf(conf, "os-janus-light"),
            "[Daemon]\nShowDelay=0\nTheme=os-janus-light\nDeviceTimeout=8\n"
        );
        // Spaces around = and a second Theme= line
        let conf = "[Daemon]\nTheme = a\nTheme=b\n";
        assert_eq!(plymouth_conf(conf, "c"), "[Daemon]\nTheme=c\n");
    }

    #[test]
    fn plymouth_conf_adds_a_missing_theme() {
        assert_eq!(
            plymouth_conf("[Daemon]\nShowDelay=0\n[Other]\nTheme=x\n", "c"),
            "[Daemon]\nShowDelay=0\nTheme=c\n[Other]\nTheme=x\n"
        );
        assert_eq!(
            plymouth_conf("[Daemon]\nShowDelay=0\n", "c"),
            "[Daemon]\nShowDelay=0\nTheme=c\n"
        );
        assert_eq!(plymouth_conf("", "c"), "[Daemon]\nTheme=c\n");
        assert_eq!(
            plymouth_conf("[Other]\nTheme=x\n", "c"),
            "[Other]\nTheme=x\n[Daemon]\nTheme=c\n"
        );
    }

    #[test]
    fn names_for_completion() {
        let theme = good();
        assert_eq!(
            names(&[theme]),
            vec!["test\tTest (Dark)", "test:dark\tTest · Dark"]
        );
    }

    #[test]
    fn palette_listing() {
        let theme = good();
        let lines = palette_lines(&theme.variants["dark"]);
        assert_eq!(lines.len(), 16);
        assert_eq!(lines[1], "red            #c8102e");
    }
}
