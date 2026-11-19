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
    // The caption of the picture under it, for a theme from outside (the gods have theirs in
    // StrixUI)
    let plate = std::fs::read_to_string(theme.dir.join("wallpaper.toml"))
        .ok()
        .and_then(|text| text.parse::<toml::Table>().ok())
        .and_then(|table| table.get("caption")?.as_str().map(str::to_string));
    json!({
        "format": FORMAT,
        "plate": plate,
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

/// btop.theme: the system monitor in the colors of the theme. The boxes and lines are the
/// borders, figures that need attention the accent; loads run from quiet text to the accent,
/// temperatures from success over warning to error.
pub fn btop(theme: &Theme, variant: &Variant) -> String {
    let background = variant.color("background");
    let text = variant.color("text");
    let muted = variant.color("text-muted");
    let faint = extra_or(variant, "text-faint", "text-muted");
    let border = variant.color("border");
    let raised = extra_or(variant, "surface-raised", "surface");
    let accent = variant.color("accent");
    let accent_text = extra_or(variant, "accent-text", "accent");
    let success = extra_or(variant, "success", "accent");
    let warning = variant.color("warning");
    let error = variant.color("error");
    let info = extra_or(variant, "info", "text-muted");
    let palette = &variant.terminal.palette;
    let rows: [(&str, Rgb); 45] = [
        ("main_bg", background),
        ("main_fg", text),
        ("title", text),
        ("hi_fg", accent_text),
        ("selected_bg", raised),
        ("selected_fg", text),
        ("inactive_fg", faint),
        ("graph_text", muted),
        ("meter_bg", border),
        ("proc_misc", accent_text),
        ("cpu_box", border),
        ("mem_box", border),
        ("net_box", border),
        ("proc_box", border),
        ("div_line", border),
        ("temp_start", success),
        ("temp_mid", warning),
        ("temp_end", error),
        ("cpu_start", faint),
        ("cpu_mid", muted),
        ("cpu_end", accent),
        ("free_start", faint),
        ("free_mid", muted),
        ("free_end", success),
        ("cached_start", faint),
        ("cached_mid", muted),
        ("cached_end", info),
        ("available_start", faint),
        ("available_mid", muted),
        ("available_end", palette[6]),
        ("used_start", faint),
        ("used_mid", muted),
        ("used_end", accent),
        ("download_start", faint),
        ("download_mid", muted),
        ("download_end", info),
        ("upload_start", faint),
        ("upload_mid", muted),
        ("upload_end", accent_text),
        ("process_start", faint),
        ("process_mid", muted),
        ("process_end", accent),
        ("graph_bg", background),
        ("box_bg", background),
        ("cursor", accent),
    ];
    let mut out = format!(
        "# The colors of {} ({}:{}), written by the theme engine.\n",
        theme.name, theme.id, variant.id
    );
    for (name, color) in rows {
        out.push_str(&format!("theme[{name}]=\"{}\"\n", color.hex()));
    }
    out
}

/// The named colors of libadwaita (and adw-gtk3) for one variant, in the order they are written
fn gtk_colors(variant: &Variant) -> Vec<(&'static str, Rgb)> {
    let background = variant.color("background");
    let surface = variant.color("surface");
    let raised = extra_or(variant, "surface-raised", "surface");
    let sunken = extra_or(variant, "surface-sunken", "background");
    let border = variant.color("border");
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
        // The lines between the parts of a window (libadwaita 1.6 and later: --border-color), so
        // the sidebar and the header bar of Files are drawn like the panels of the shell
        ("border_color", border),
        ("headerbar_bg_color", surface),
        ("headerbar_fg_color", text),
        ("headerbar_backdrop_color", background),
        ("headerbar_border_color", border),
        ("sidebar_bg_color", surface),
        ("sidebar_fg_color", text),
        ("sidebar_backdrop_color", background),
        ("sidebar_border_color", border),
        ("secondary_sidebar_bg_color", surface),
        ("secondary_sidebar_fg_color", text),
        ("secondary_sidebar_border_color", border),
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

/// The colors Zen draws itself with, by the names of Zen and Firefox
fn zen_colors(variant: &Variant) -> Vec<(&'static str, Rgb)> {
    let background = variant.color("background");
    let surface = variant.color("surface");
    let raised = extra_or(variant, "surface-raised", "surface");
    let sunken = extra_or(variant, "surface-sunken", "background");
    let border = variant.color("border");
    let strong = extra_or(variant, "border-strong", "border");
    let text = variant.color("text");
    let accent = variant.color("accent");
    vec![
        // Zen mixes most of its palette from this one
        ("zen-primary-color", accent),
        ("zen-colors-primary", accent),
        ("zen-colors-secondary", raised),
        ("zen-colors-tertiary", surface),
        ("zen-colors-hover-bg", raised),
        ("zen-colors-primary-foreground", text),
        ("zen-colors-border", border),
        ("zen-colors-border-contrast", strong),
        ("zen-colors-input-bg", sunken),
        ("zen-main-browser-background", background),
        ("zen-dialog-background", raised),
        ("zen-toolbar-element-bg", surface),
        ("zen-toolbar-element-bg-hover", raised),
        ("zen-urlbar-background", surface),
        ("zen-branding-dark", background),
        ("zen-sidebar-notification-bg", accent),
        ("zen-sidebar-themed-icon-fill", text),
        ("toolbar-bgcolor", surface),
        ("toolbar-color", text),
        ("toolbox-textcolor", text),
        ("tab-selected-bgcolor", raised),
        ("tab-selected-textcolor", text),
        ("arrowpanel-background", raised),
        ("arrowpanel-color", text),
        ("arrowpanel-border-color", border),
    ]
}

/// zen-userChrome.css: the window of Zen (sidebar, toolbars, tabs, address bar, menus). Zen sets
/// its accent and the color of its ground as inline styles on the space and on the element that
/// paints the ground, so the names are set there as well, and with !important, which an inline
/// style without it loses to. Zen reads the file when it starts.
pub fn zen_chrome(theme: &Theme, variant: &Variant) -> String {
    let mut out = format!(
        "/* The colors of {} ({}:{}), written by the theme engine. */\n\
         :root, zen-workspace, .zen-browser-generic-background {{\n",
        theme.name, theme.id, variant.id
    );
    for (name, color) in zen_colors(variant) {
        out.push_str(&format!("  --{name}: {} !important;\n", color.hex()));
    }
    // Zen blends its ground as "screen", which only ever lightens it
    out.push_str(
        "}\n.zen-browser-generic-background {\n  background-blend-mode: normal !important;\n}\n",
    );
    out
}

/// zen-userContent.css: the pages of the browser itself (new tab, settings, about:), by the names
/// Firefox gives their colors. Web pages are left alone.
pub fn zen_content(theme: &Theme, variant: &Variant) -> String {
    let surface = variant.color("surface");
    let colors = [
        ("in-content-page-background", variant.color("background")),
        ("in-content-page-color", variant.color("text")),
        ("in-content-box-background", surface),
        ("in-content-box-background-odd", surface),
        ("in-content-box-border-color", variant.color("border")),
        (
            "in-content-primary-button-background",
            variant.color("accent"),
        ),
        (
            "in-content-primary-button-text-color",
            variant.color("on-accent"),
        ),
        ("color-accent-primary", variant.color("accent")),
        ("newtab-background-color", variant.color("background")),
        ("newtab-background-color-secondary", surface),
        ("newtab-text-primary-color", variant.color("text")),
    ];
    let mut out = format!(
        "/* The colors of {} ({}:{}), written by the theme engine. */\n\
         @-moz-document url-prefix(\"about:\") {{\n  :root {{\n",
        theme.name, theme.id, variant.id
    );
    for (name, color) in colors {
        out.push_str(&format!("    --{name}: {} !important;\n", color.hex()));
    }
    out.push_str("  }\n}\n");
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
        let border = variant.color("border").hex();
        assert!(four.contains(&format!("--border-color: {border};")));
        assert!(four.contains(&format!("--sidebar-border-color: {border};")));
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
        let btop = btop(&theme, variant);
        assert!(btop.contains("theme[main_bg]=\"#000000\"\n"));
        assert!(btop.contains("theme[cpu_end]=\"#c8102e\"\n"));
        assert_eq!(btop.matches("theme[").count(), 45);
    }

    #[test]
    fn zen_takes_the_colors_where_it_sets_its_own() {
        let theme = good();
        let variant = theme.variant("dark").unwrap();
        let chrome = zen_chrome(&theme, variant);
        assert!(chrome.starts_with("/* The colors of Test (test:dark)"));
        assert!(chrome.contains(":root, zen-workspace, .zen-browser-generic-background {\n"));
        assert!(
            chrome.contains("  --zen-primary-color: #c8102e !important;\n"),
            "{chrome}"
        );
        assert!(chrome.contains("  --zen-main-browser-background: #000000 !important;\n"));
        assert!(chrome.contains("background-blend-mode: normal !important;"));
        // Every color wins over an inline style
        assert_eq!(
            chrome.matches("  --").count(),
            chrome.matches(" !important;\n").count() - 1
        );
        let content = zen_content(&theme, variant);
        assert!(content.contains("@-moz-document url-prefix(\"about:\") {\n"));
        assert!(content.contains("    --in-content-page-background: #000000 !important;\n"));
        assert!(content.contains("    --color-accent-primary: #c8102e !important;\n"));
        assert_eq!(content.matches('{').count(), content.matches('}').count());
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
