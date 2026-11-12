//! Colors: parsing, contrast after WCAG 2.x, mixing, terminal approximations.

use std::fmt;

/// An opaque sRGB color.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

/// A color with optional alpha, as written in a theme ("#rrggbb" or "#rrggbbaa").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Color {
    pub rgb: Rgb,
    pub alpha: Option<u8>,
}

impl Rgb {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Rgb { r, g, b }
    }

    /// Relative luminance after WCAG 2.x (sRGB, D65).
    pub fn luminance(self) -> f64 {
        fn channel(value: u8) -> f64 {
            let c = f64::from(value) / 255.0;
            if c <= 0.04045 {
                c / 12.92
            } else {
                ((c + 0.055) / 1.055).powf(2.4)
            }
        }
        0.2126 * channel(self.r) + 0.7152 * channel(self.g) + 0.0722 * channel(self.b)
    }

    /// Contrast ratio after WCAG 2.x, from 1.0 (same) to 21.0 (black on white).
    pub fn contrast(self, other: Rgb) -> f64 {
        let (a, b) = (self.luminance(), other.luminance());
        let (light, dark) = if a > b { (a, b) } else { (b, a) };
        (light + 0.05) / (dark + 0.05)
    }

    /// Mixes towards `other`: 0.0 gives self, 1.0 gives other. Per channel in sRGB.
    pub fn mix(self, other: Rgb, amount: f64) -> Rgb {
        let amount = amount.clamp(0.0, 1.0);
        let channel = |from: u8, to: u8| -> u8 {
            let value = f64::from(from) + (f64::from(to) - f64::from(from)) * amount;
            // Between two u8 values, so always 0 to 255
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            {
                value.round() as u8
            }
        };
        Rgb::new(
            channel(self.r, other.r),
            channel(self.g, other.g),
            channel(self.b, other.b),
        )
    }

    /// "#rrggbb", lowercase.
    pub fn hex(self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.r, self.g, self.b)
    }

    /// "r;g;b" for true-color escape sequences.
    pub fn sgr(self) -> String {
        format!("{};{};{}", self.r, self.g, self.b)
    }

    fn distance(self, other: Rgb) -> u32 {
        let d = |a: u8, b: u8| -> u32 {
            let diff = i32::from(a) - i32::from(b);
            (diff * diff).unsigned_abs()
        };
        d(self.r, other.r) + d(self.g, other.g) + d(self.b, other.b)
    }

    /// The closest color of the xterm 256-color palette, from its fixed part
    /// (16 to 255). 0 to 15 are left out: every terminal defines them itself.
    pub fn nearest_xterm256(self) -> u8 {
        let mut best = (16u8, u32::MAX);
        for index in 16..=255u8 {
            let distance = self.distance(xterm256(index));
            if distance < best.1 {
                best = (index, distance);
            }
        }
        best.0
    }

    /// Index of the closest color in a palette. Ties go to the lower index.
    pub fn nearest_in(self, palette: &[Rgb]) -> usize {
        let mut best = (0usize, u32::MAX);
        for (index, color) in palette.iter().enumerate() {
            let distance = self.distance(*color);
            if distance < best.1 {
                best = (index, distance);
            }
        }
        best.0
    }
}

impl fmt::Display for Rgb {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.hex())
    }
}

impl Color {
    /// Reads "#rrggbb" or "#rrggbbaa". Upper and lower case are both fine.
    /// Short forms (#rgb) are not accepted, so every value is exact.
    pub fn parse(text: &str) -> Result<Color, String> {
        let digits = text
            .strip_prefix('#')
            .ok_or_else(|| format!("\"{text}\" is not a color, write it as #rrggbb"))?;
        if !digits.chars().all(|c| c.is_ascii_hexdigit())
            || !(digits.len() == 6 || digits.len() == 8)
        {
            return Err(format!(
                "\"{text}\" is not a color, write it as #rrggbb or #rrggbbaa"
            ));
        }
        let byte =
            |i: usize| u8::from_str_radix(&digits[i..i + 2], 16).expect("checked hex digits");
        Ok(Color {
            rgb: Rgb::new(byte(0), byte(2), byte(4)),
            alpha: (digits.len() == 8).then(|| byte(6)),
        })
    }

    /// "#rrggbb" or "#rrggbbaa", lowercase.
    pub fn hex(self) -> String {
        match self.alpha {
            Some(alpha) => format!("{}{:02x}", self.rgb.hex(), alpha),
            None => self.rgb.hex(),
        }
    }
}

/// The color of an xterm 256-color index from 16 to 255.
pub fn xterm256(index: u8) -> Rgb {
    const LEVELS: [u8; 6] = [0, 95, 135, 175, 215, 255];
    match index {
        16..=231 => {
            let i = index - 16;
            Rgb::new(
                LEVELS[usize::from(i / 36)],
                LEVELS[usize::from(i / 6 % 6)],
                LEVELS[usize::from(i % 6)],
            )
        }
        232..=255 => {
            let level = 8 + (index - 232) * 10;
            Rgb::new(level, level, level)
        }
        _ => panic!("xterm256 is only defined for 16 to 255, got {index}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rgb(text: &str) -> Rgb {
        Color::parse(text).unwrap().rgb
    }

    #[test]
    fn parses_both_lengths_and_cases() {
        assert_eq!(
            Color::parse("#C8102E").unwrap(),
            Color {
                rgb: Rgb::new(200, 16, 46),
                alpha: None
            }
        );
        assert_eq!(
            Color::parse("#16181b4d").unwrap(),
            Color {
                rgb: Rgb::new(22, 24, 27),
                alpha: Some(77)
            }
        );
        assert_eq!(Color::parse("#C8102E").unwrap().hex(), "#c8102e");
        assert_eq!(Color::parse("#16181B4D").unwrap().hex(), "#16181b4d");
    }

    #[test]
    fn rejects_everything_else() {
        for bad in [
            "C8102E",
            "#fff",
            "#c8102",
            "#c8102e0",
            "#c8102eff0",
            "#g8102e",
            "red",
            "",
            "#",
            "rgb(0,0,0)",
            " #c8102e",
        ] {
            assert!(Color::parse(bad).is_err(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn contrast_matches_wcag_reference_values() {
        let white = Rgb::new(255, 255, 255);
        let black = Rgb::new(0, 0, 0);
        assert!((white.contrast(black) - 21.0).abs() < 1e-9);
        assert!((black.contrast(black) - 1.0).abs() < 1e-9);
        // #777777 on white is the textbook example just below 4.5:1
        let ratio = rgb("#777777").contrast(white);
        assert!((ratio - 4.48).abs() < 0.01, "got {ratio}");
        // Symmetric
        assert_eq!(
            rgb("#c8102e").contrast(white),
            white.contrast(rgb("#c8102e"))
        );
    }

    #[test]
    fn contrast_matches_known_ratios() {
        // WCAG 2 ratios of known pairs, worked out by hand
        let check = |fg: &str, bg: &str, expected: f64| {
            let ratio = rgb(fg).contrast(rgb(bg));
            assert!(
                (ratio - expected).abs() < 0.06,
                "{fg} on {bg}: {ratio}, expected {expected}"
            );
        };
        check("#16181b", "#ffffff", 17.8);
        check("#5b6168", "#ffffff", 6.3);
        check("#d93a2f", "#ffffff", 4.6);
        check("#16181b", "#ff9419", 8.1);
        check("#16181b", "#f2c230", 10.6);
        check("#ffffff", "#d93a2f", 4.6);
    }

    #[test]
    fn mixing() {
        let accent = Rgb::new(200, 16, 46);
        let black = Rgb::new(0, 0, 0);
        assert_eq!(accent.mix(black, 0.0), accent);
        assert_eq!(accent.mix(black, 1.0), black);
        assert_eq!(accent.mix(black, 0.58), Rgb::new(84, 7, 19));
        assert_eq!(accent.mix(black, 7.0), black);
    }

    #[test]
    fn xterm_palette() {
        assert_eq!(xterm256(16), Rgb::new(0, 0, 0));
        assert_eq!(xterm256(160), Rgb::new(215, 0, 0));
        assert_eq!(xterm256(52), Rgb::new(95, 0, 0));
        assert_eq!(xterm256(231), Rgb::new(255, 255, 255));
        assert_eq!(xterm256(232), Rgb::new(8, 8, 8));
        assert_eq!(xterm256(244), Rgb::new(128, 128, 128));
        assert_eq!(xterm256(255), Rgb::new(238, 238, 238));
    }

    #[test]
    fn nearest_xterm_colors_match_the_installer() {
        // The values the installer used before the theme engine
        assert_eq!(Rgb::new(200, 16, 46).nearest_xterm256(), 160);
        assert_eq!(Rgb::new(84, 7, 19).nearest_xterm256(), 52);
        assert_eq!(Rgb::new(128, 128, 128).nearest_xterm256(), 244);
    }

    #[test]
    fn nearest_in_palette() {
        let palette = [
            Rgb::new(0, 0, 0),
            Rgb::new(200, 16, 46),
            Rgb::new(255, 255, 255),
        ];
        assert_eq!(Rgb::new(190, 20, 40).nearest_in(&palette), 1);
        assert_eq!(Rgb::new(10, 10, 10).nearest_in(&palette), 0);
    }

    #[test]
    fn formats() {
        let accent = Rgb::new(200, 16, 46);
        assert_eq!(accent.hex(), "#c8102e");
        assert_eq!(accent.sgr(), "200;16;46");
        assert_eq!(accent.to_string(), "#c8102e");
    }
}
