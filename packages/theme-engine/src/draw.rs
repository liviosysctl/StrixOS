//! What the boot pictures of a theme variant are made of, written into a folder: the GRUB theme
//! (packages/grub-theme) and the Plymouth theme (packages/plymouth-theme).
//!
//! Text and the wallpaper go into SVG, which rsvg-convert draws with the real fonts; the small
//! pieces GRUB and Plymouth tile (a box cut into nine, a colour) are written as PNG right here.

use crate::color::Rgb;
use crate::theme::{Theme, Variant};
use std::fs;
use std::path::Path;

/// A colour of the variant, or the first of the fallbacks a theme from outside surely has
fn pick(variant: &Variant, names: &[&str]) -> Rgb {
    names
        .iter()
        .find_map(|n| variant.colors.get(*n))
        .map(|c| c.rgb)
        .unwrap_or_else(|| variant.color(names[names.len() - 1]))
}

fn write(dir: &Path, name: &str, data: &[u8]) -> Result<(), String> {
    fs::write(dir.join(name), data).map_err(|e| format!("cannot write {name}: {e}"))
}

/// Text for XML
fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

// ---------------------------------------------------------------------------------------- PNG

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &byte in data {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &byte in data {
        a = (a + u32::from(byte)) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

/// An RGBA picture as PNG, uncompressed (the pieces are a few pixels)
pub fn png(width: u32, height: u32, rgba: &[u8]) -> Vec<u8> {
    let row = width as usize * 4;
    let mut raw = Vec::with_capacity((row + 1) * height as usize);
    for line in rgba.chunks(row) {
        raw.push(0);
        raw.extend_from_slice(line);
    }
    // zlib with stored blocks of at most 65535 bytes
    let mut zlib = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = raw.chunks(65535).collect();
    for (i, block) in blocks.iter().enumerate() {
        zlib.push(u8::from(i + 1 == blocks.len()));
        let len = u16::try_from(block.len()).expect("blocks of at most 65535 bytes");
        zlib.extend_from_slice(&len.to_le_bytes());
        zlib.extend_from_slice(&(!len).to_le_bytes());
        zlib.extend_from_slice(block);
    }
    zlib.extend_from_slice(&adler32(&raw).to_be_bytes());

    let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut chunk = |kind: &[u8], data: &[u8]| {
        let len = u32::try_from(data.len()).expect("small pictures");
        out.extend_from_slice(&len.to_be_bytes());
        let mut body = kind.to_vec();
        body.extend_from_slice(data);
        out.extend_from_slice(&body);
        out.extend_from_slice(&crc32(&body).to_be_bytes());
    };
    let mut header = Vec::new();
    header.extend_from_slice(&width.to_be_bytes());
    header.extend_from_slice(&height.to_be_bytes());
    header.extend_from_slice(&[8, 6, 0, 0, 0]);
    chunk(b"IHDR", &header);
    chunk(b"IDAT", &zlib);
    chunk(b"IEND", &[]);
    out
}

fn solid(color: Rgb, alpha: u8, width: u32) -> Vec<u8> {
    png(
        width,
        1,
        &[color.r, color.g, color.b, alpha].repeat(width as usize),
    )
}

/// How much of the pixel (x, y) lies inside a rounded square of `size` with corner radius `r`
fn coverage(x: u32, y: u32, size: f64, r: f64) -> f64 {
    const STEPS: u32 = 8;
    let mut inside = 0;
    for sy in 0..STEPS {
        for sx in 0..STEPS {
            let px = f64::from(x) + (f64::from(sx) + 0.5) / f64::from(STEPS);
            let py = f64::from(y) + (f64::from(sy) + 0.5) / f64::from(STEPS);
            let dx = (r - px).max(px - (size - r)).max(0.0);
            let dy = (r - py).max(py - (size - r)).max(0.0);
            if dx * dx + dy * dy <= r * r {
                inside += 1;
            }
        }
    }
    f64::from(inside) / f64::from(STEPS * STEPS)
}

/// A box with a 1px border and rounded corners, cut into GRUB's nine pieces
/// (`<prefix>_nw.png` .. `<prefix>_se.png`)
fn pieces(dir: &Path, prefix: &str, fill: (Rgb, f64), border: Rgb) -> Result<(), String> {
    const K: u32 = 4;
    let size = K * 2 + 1;
    let mut pixels = vec![[0u8; 4]; (size * size) as usize];
    for y in 0..size {
        for x in 0..size {
            let outer = coverage(x, y, f64::from(size), f64::from(K));
            let inner = coverage(
                x.wrapping_sub(1),
                y.wrapping_sub(1),
                f64::from(size - 2),
                f64::from(K - 1),
            );
            let inner = if x == 0 || y == 0 { 0.0 } else { inner };
            // The fill over the border colour, both cut to their shapes
            let (fa, ba) = (fill.1 * inner, outer - inner);
            let alpha = (fa + ba).clamp(0.0, 1.0);
            let mix = |f: u8, b: u8| -> u8 {
                if alpha == 0.0 {
                    0
                } else {
                    channel((f64::from(f) * fa + f64::from(b) * ba) / alpha)
                }
            };
            pixels[(y * size + x) as usize] = [
                mix(fill.0.r, border.r),
                mix(fill.0.g, border.g),
                mix(fill.0.b, border.b),
                channel(alpha * 255.0),
            ];
        }
    }
    let parts = [
        ("nw", 0, 0, K, K),
        ("n", K, 0, 1, K),
        ("ne", K + 1, 0, K, K),
        ("w", 0, K, K, 1),
        ("c", K, K, 1, 1),
        ("e", K + 1, K, K, 1),
        ("sw", 0, K + 1, K, K),
        ("s", K, K + 1, 1, K),
        ("se", K + 1, K + 1, K, K),
    ];
    for (part, x0, y0, w, h) in parts {
        let mut cut = Vec::new();
        for y in y0..y0 + h {
            for x in x0..x0 + w {
                cut.extend_from_slice(&pixels[(y * size + x) as usize]);
            }
        }
        write(dir, &format!("{prefix}_{part}.png"), &png(w, h, &cut))?;
    }
    Ok(())
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn channel(value: f64) -> u8 {
    value.round().clamp(0.0, 255.0) as u8
}

// --------------------------------------------------------------------------------------- GRUB

pub struct Grub<'a> {
    pub name: &'a str,
    pub motto: &'a str,
    /// The font GRUB draws the menu with (its .pf2 is made beside)
    pub font_name: &'a str,
    pub wallpaper: Option<&'a Path>,
}

/// Pixels of the 1920 by 1080 picture: where the column with the wordmark, menu and hints stands
const W: u32 = 1920;
const H: u32 = 1080;
const X: u32 = 150;
const COL: u32 = 640;

/// background.svg (rsvg-convert makes background.png of it), the pieces of the menu box, the
/// terminal box and the selection, and theme.txt
pub fn grub(dir: &Path, theme: &Theme, variant: &Variant, grub: &Grub) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let hex = |names: &[&str]| pick(variant, names).hex();
    let background = hex(&["background"]);

    // The god's picture covers the screen; the background colour lies over it, almost solid
    // behind the column and thinning out to the right, so the menu reads like the lock screen
    let picture = match grub.wallpaper {
        Some(file) => {
            fs::copy(file, dir.join("wallpaper.jpg"))
                .map_err(|e| format!("cannot copy {}: {e}", file.display()))?;
            format!(
                r#"<image href="wallpaper.jpg" width="{W}" height="{H}" preserveAspectRatio="xMidYMid slice"/>"#
            )
        }
        None => String::new(),
    };
    let start = f64::from(COL + X);
    let span = f64::from(W) * 0.55;
    let stops: String = (0..=10)
        .map(|i| {
            let t = f64::from(i) / 10.0;
            let smooth = t * t * (3.0 - 2.0 * t);
            format!(
                r#"<stop offset="{:.3}" stop-color="{background}" stop-opacity="{:.3}"/>"#,
                (start + t * span) / f64::from(W),
                0.94 - 0.62 * smooth
            )
        })
        .collect();

    // The keys, quiet, at the foot of the column
    let keys: String = [("Enter", "start"), ("E", "edit"), ("C", "console")]
        .iter()
        .enumerate()
        .map(|(i, (key, what))| {
            format!(
                r#"<tspan fill="{}">{}{key}</tspan><tspan fill="{}"> {what}</tspan>"#,
                hex(&["text"]),
                if i == 0 { "" } else { "    " },
                hex(&["text-faint", "text-muted"])
            )
        })
        .collect();

    // Baselines from the fonts' ascents: the wordmark 185 below its top, the motto 28, the keys 18
    let svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs><linearGradient id="veil" x1="0" x2="1" y1="0" y2="0">{stops}</linearGradient></defs>
<rect width="{W}" height="{H}" fill="{background}"/>
{picture}
<rect width="{W}" height="{H}" fill="url(#veil)"/>
<text x="{}" y="305" font-family="Grenze Gotisch" font-weight="300" font-size="168" fill="{}">{}</text>
<text x="{X}" y="358" font-family="IM FELL English" font-style="italic" font-size="30" fill="{}">{}</text>
<rect x="{X}" y="392" width="{COL}" height="1" fill="{}"/>
<rect x="{X}" y="391" width="56" height="3" fill="{}"/>
<text x="{X}" y="{}" font-family="JetBrains Mono" font-size="17" xml:space="preserve">{keys}</text>
</svg>
"##,
        X - 6,
        hex(&["text"]),
        escape(grub.name),
        hex(&["text-muted"]),
        escape(grub.motto),
        hex(&["border-strong", "border"]),
        hex(&["accent"]),
        H - 120 + 18,
    );
    write(dir, "background.svg", svg.as_bytes())?;

    pieces(
        dir,
        "menu",
        (pick(variant, &["surface"]), 0.88),
        pick(variant, &["border"]),
    )?;
    pieces(
        dir,
        "term",
        (pick(variant, &["surface-sunken", "background"]), 0.96),
        pick(variant, &["border"]),
    )?;
    // The chosen row: raised, with a 3px bar in the accent on its left edge
    let raised = pick(variant, &["surface-raised", "surface"]);
    let mark = pick(variant, &["accent"]);
    for part in ["nw", "w", "sw"] {
        write(dir, &format!("select_{part}.png"), &solid(mark, 255, 3))?;
    }
    for part in ["n", "c", "s", "ne", "e", "se"] {
        write(dir, &format!("select_{part}.png"), &solid(raised, 255, 1))?;
    }

    let menu_top = 440;
    let menu_h = 6 * 40 + 24;
    let font = grub.font_name;
    let theme_txt = format!(
        r#"# The boot menu of {name} in the colours of {theme}, made by packages/grub-theme. Do not edit.
title-text: ""
desktop-image: "background.png"
desktop-color: "{background}"
terminal-font: "{font} 16"
terminal-box: "term_*.png"
terminal-left: "{X}"
terminal-top: "{menu_top}"
terminal-width: "1200"
terminal-height: "520"
terminal-border: "0"

+ boot_menu {{
  left = {X}
  top = {menu_top}
  width = {COL}
  height = {menu_h}
  menu_pixmap_style = "menu_*.png"
  item_font = "{font} 16"
  item_color = "{muted}"
  selected_item_font = "{font} 16"
  selected_item_color = "{text}"
  selected_item_pixmap_style = "select_*.png"
  icon_width = 0
  icon_height = 0
  item_icon_space = 14
  item_height = 40
  item_padding = 12
  item_spacing = 0
  scrollbar = false
}}

+ label {{
  id = "__timeout__"
  left = {X}
  top = {label_top}
  width = {COL}
  height = 24
  align = "left"
  font = "{font} 14"
  color = "{faint}"
  text = "Starting in %d s, any key stops"
}}
"#,
        name = grub.name,
        theme = theme.name,
        muted = hex(&["text-muted"]),
        text = hex(&["text"]),
        faint = hex(&["text-faint", "text-muted"]),
        label_top = menu_top + menu_h + 18,
    );
    write(dir, "theme.txt", theme_txt.as_bytes())
}

// ----------------------------------------------------------------------------------- Plymouth

/// "0.7843 0.0627 0.1804": a colour as Plymouth's script takes it
fn floats(color: Rgb) -> [String; 3] {
    [color.r, color.g, color.b].map(|c| format!("{:.4}", f64::from(c) / 255.0))
}

/// wordmark.svg (the distro's name, rsvg-convert and a trim make wordmark.png), accent.png,
/// `<id>.script` from the script with the colours filled in and `<id>.plymouth`, whose image
/// folder is `dir` itself
pub fn plymouth(
    dir: &Path,
    variant: &Variant,
    id: &str,
    name: &str,
    script: &str,
) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let (bg, fg, acc) = (
        variant.color("background"),
        variant.color("text"),
        variant.color("accent"),
    );
    // Large, Plymouth scales it to the screen
    let svg = format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="700"><text x="100" y="500" font-family="Inter" font-weight="800" font-size="400" fill="{}">{}</text></svg>
"#,
        fg.hex(),
        escape(name)
    );
    write(dir, "wordmark.svg", svg.as_bytes())?;
    write(dir, "accent.png", &solid(acc, 255, 1))?;

    let mut text = script.to_string();
    for (key, color) in [("BG", bg), ("FG", fg), ("ACC", acc)] {
        let [r, g, b] = floats(color);
        text = text
            .replace(&format!("@{key}_R@"), &r)
            .replace(&format!("@{key}_G@"), &g)
            .replace(&format!("@{key}_B@"), &b);
    }
    write(dir, &format!("{id}.script"), text.as_bytes())?;
    let folder = dir.to_string_lossy();
    write(
        dir,
        &format!("{id}.plymouth"),
        format!(
            "[Plymouth Theme]\nName={name}\nDescription={name} boot splash\nModuleName=script\n\n[script]\nImageDir={folder}\nScriptFile={folder}/{id}.script\n"
        )
        .as_bytes(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::tests::good;

    fn temp(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("theme-draw-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn png_signature_and_checksums() {
        let data = png(1, 1, &[200, 16, 46, 255]);
        assert_eq!(&data[..8], b"\x89PNG\r\n\x1a\n");
        assert_eq!(crc32(b"IEND"), 0xae42_6082);
        assert_eq!(adler32(b"Wikipedia"), 0x11e6_0398);
        assert!(data.ends_with(&[0, 0, 0, 0, b'I', b'E', b'N', b'D', 0xae, 0x42, 0x60, 0x82]));
    }

    #[test]
    fn rounded_corners() {
        assert!(coverage(0, 0, 9.0, 4.0) < 0.2);
        assert!((coverage(4, 4, 9.0, 4.0) - 1.0).abs() < f64::EPSILON);
        assert!((coverage(4, 0, 9.0, 4.0) - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn grub_files() {
        let theme = good();
        let dir = temp("grub");
        let options = Grub {
            name: "Strix",
            motto: "Sees in the dark & <knows>",
            font_name: "Strix Mono Regular",
            wallpaper: None,
        };
        grub(&dir, &theme, &theme.variants["dark"], &options).unwrap();
        let svg = fs::read_to_string(dir.join("background.svg")).unwrap();
        assert!(svg.contains("&amp; &lt;knows&gt;"));
        let txt = fs::read_to_string(dir.join("theme.txt")).unwrap();
        assert!(txt.contains(r#"item_font = "Strix Mono Regular 16""#));
        assert!(txt.contains("top = 722"));
        for part in ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"] {
            for prefix in ["menu", "term", "select"] {
                assert!(dir.join(format!("{prefix}_{part}.png")).is_file());
            }
        }
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn plymouth_files() {
        let theme = good();
        let dir = temp("plymouth");
        plymouth(
            &dir,
            &theme.variants["dark"],
            "strix-test-dark",
            "Strix",
            "c = @ACC_R@, @ACC_G@, @ACC_B@;",
        )
        .unwrap();
        let script = fs::read_to_string(dir.join("strix-test-dark.script")).unwrap();
        assert_eq!(script, "c = 0.7843, 0.0627, 0.1804;");
        let conf = fs::read_to_string(dir.join("strix-test-dark.plymouth")).unwrap();
        assert!(conf.contains(&format!(
            "ScriptFile={}/strix-test-dark.script",
            dir.display()
        )));
        fs::remove_dir_all(&dir).unwrap();
    }
}
