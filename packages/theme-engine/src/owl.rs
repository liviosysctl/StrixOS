//! The owl of the distro as SVG: the pen drawing of the design system, a horned owl standing a
//! little sideways, without a ring.
//!
//! The lines are cream, the eyes are the accent of the theme, the pupils the background the owl
//! is shown on. `lid` from 0 (open) to 1 (closed) draws the frames of a blink.

/// The drawing in the colours of the design system, 208 units square from (-25, 22)
const DRAWING: &str = include_str!("owl.svg");
const ACCENT: &str = "#c8102e";
const INK: &str = "#080707";
/// Centre and radius of the two eyes in the drawing
const EYES: [(f64, f64); 2] = [(79.7, 65.8), (106.3, 65.8)];
const EYE: f64 = 5.1;
const LINE: &str = "#ece6da";

/// The eyelids at `lid`: the background drawn down over each eye inside its outline, and the edge
/// of the lid as a pen line
fn lids(background: &str, lid: f64) -> String {
    let mut out = String::new();
    for (i, (cx, cy)) in EYES.iter().enumerate() {
        let (top, edge) = (cy - EYE - 0.4, cy - EYE + 2.0 * EYE * lid);
        let half = (EYE * EYE - (edge - cy).powi(2))
            .max(0.0)
            .sqrt()
            .max(EYE * 0.55);
        out.push_str(&format!(
            r#"<clipPath id="lid-{i}"><circle cx="{cx}" cy="{cy}" r="{r:.2}"/></clipPath><rect x="{x:.2}" y="{top:.2}" width="{w:.2}" height="{h:.2}" fill="{background}" clip-path="url(#lid-{i})"/><path d="M{x0:.2} {edge:.2} Q{cx} {sag:.2} {x1:.2} {edge:.2}" fill="none" stroke="{LINE}" stroke-width="0.6"/>"#,
            r = EYE - 0.3,
            x = cx - EYE,
            w = 2.0 * EYE,
            h = edge - top,
            x0 = cx - half,
            x1 = cx + half,
            sag = edge + 1.2 * lid,
        ));
    }
    out
}

/// The whole picture, 1000 by 1000
pub fn svg(accent: &str, background: &str, lid: f64) -> String {
    let lid = lid.clamp(0.0, 1.0);
    let drawing = DRAWING
        .trim_end()
        .replace(ACCENT, accent)
        .replace(INK, background);
    let lids = if lid > 0.0 {
        lids(background, lid)
    } else {
        String::new()
    };
    format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000"><g transform="scale(4.8077) translate(25 -22)" stroke-linecap="round" stroke-linejoin="round">{drawing}{lids}</g></svg>
"#
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eyes_take_the_accent_and_lids_come_only_when_blinking() {
        let open = svg("#546d85", "#05080b", 0.0);
        let closed = svg("#546d85", "#05080b", 1.0);
        assert!(open.starts_with("<svg") && open.ends_with("</svg>\n"));
        assert!(
            open.contains(r##"fill="#546d85""##) && !open.contains(ACCENT) && !open.contains(INK)
        );
        assert!(!open.contains("lid-0") && closed.contains("lid-0") && closed.contains("lid-1"));
    }

    #[test]
    fn the_drawing_has_two_eyes_where_the_lids_fall() {
        for (cx, cy) in EYES {
            assert!(DRAWING.contains(&format!(r#"cx="{cx:.1}" cy="{cy:.1}" r="{EYE}""#)));
        }
    }
}
