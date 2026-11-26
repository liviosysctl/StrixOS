//! The effect of the terminal: a custom shader for Ghostty (Shadertoy style), written beside
//! the colours of the theme when the effect is on. Fine diagonal lines like the hatching of a
//! copperplate, in the accent, with a slow light passing over them; only on the background of
//! the terminal, so text, the cursor and a selection keep their colours, and the window stays as
//! translucent as it is.
//!
//! The colours come from Ghostty itself (iCursorColor is the accent of every theme), so one
//! shader serves all of them. It stays in Rust as text, like the style sheets of Zen.

/// The shader. Ghostty hands over the terminal premultiplied; the padding of the window in its
/// corner is always background, so a pixel is background where it equals that corner.
pub const GHOSTTY: &str = r#"// The hatching of the theme behind the text, written by the theme engine.

// Lines 7 pixels apart, 45 degrees, about 1.5 pixels wide
const float SPACING = 7.0;
const float WIDTH = 0.75;
// How strong the lines are at most, and where no light falls on them
const float STRENGTH = 0.30;
const float SHADE = 0.30;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 term = texture(iChannel0, uv);
    vec4 ground = texture(iChannel0, vec2(1.5) / iResolution.xy);

    // 1 on the background, 0 on text, the cursor and selections
    float background = 1.0 - smoothstep(0.015, 0.06, distance(term, ground));

    // The hatching
    float along = (fragCoord.x + fragCoord.y) * 0.70710678;
    float offset = abs(mod(along, SPACING) - SPACING * 0.5);
    float line = 1.0 - smoothstep(WIDTH - 0.5, WIDTH + 0.5, offset);

    // A broad band of light that crosses the window in about a minute, and a slower swell
    float across = (fragCoord.x - fragCoord.y) / max(iResolution.x, iResolution.y);
    float band = 0.5 + 0.5 * sin(across * 3.14159 - iTime * 0.1);
    float swell = 0.5 + 0.5 * sin(fragCoord.x * 0.0021 + iTime * 0.07) * sin(fragCoord.y * 0.0027 - iTime * 0.05);
    float light = SHADE + (1.0 - SHADE) * pow(band, 4.0) * (0.6 + 0.4 * swell);

    float amount = background * line * light * STRENGTH;
    fragColor = vec4(term.rgb + iCursorColor * amount * term.a, term.a);
}
"#;

/// The lines of the Ghostty config that turn the effect on, with the shader in `path`. It moves
/// only in the window that has the focus.
pub fn ghostty_lines(path: &std::path::Path) -> String {
    format!(
        "# The effect of the terminal (Settings › Themes)\ncustom-shader = {}\ncustom-shader-animation = true\n",
        path.display()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shader_has_its_entry_and_no_colours_of_its_own() {
        assert!(GHOSTTY.contains("void mainImage(out vec4 fragColor, in vec2 fragCoord)"));
        assert!(GHOSTTY.contains("iCursorColor"));
        assert!(!GHOSTTY.contains('#'));
    }

    #[test]
    fn the_config_lines_point_at_the_file() {
        let text = ghostty_lines(std::path::Path::new(
            "/run/user/1000/strix/theme/ghostty.glsl",
        ));
        assert!(text.contains("custom-shader = /run/user/1000/strix/theme/ghostty.glsl\n"));
        assert!(text.contains("custom-shader-animation = true\n"));
    }
}
