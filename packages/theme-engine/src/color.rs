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

    /// "#rrggbb", lowercase.
    pub fn hex(self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.r, self.g, self.b)
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
    fn formats() {
        let accent = Rgb::new(200, 16, 46);
        assert_eq!(accent.hex(), "#c8102e");
        assert_eq!(accent.to_string(), "#c8102e");
    }
}
