//! The owl of the distro as SVG: frontal, wings spread, in a double ring.
//!
//! The owl and the ring are drawn in the accent, the engraved lines in the background it is shown
//! on, the eyes are always white with the pupils in the accent. `lid` from 0 (open) to 1 (closed)
//! lowers the eyelids, for the frames of a blink. packages/logo rasterises it for every variant.

use std::f64::consts::PI;
use std::fmt::Write;

const EYE: &str = "#ffffff";

fn mirror(x: f64) -> f64 {
    1000.0 - x
}

/// A number as it is: 458, 409.6
fn n(x: f64) -> String {
    format!("{x}")
}

/// A number with one decimal: 458.0, 409.6
fn d(x: f64) -> String {
    format!("{x:.1}")
}

fn points(pts: &[(f64, f64)]) -> String {
    pts.iter()
        .map(|(x, y)| format!("{x:.1},{y:.1}"))
        .collect::<Vec<_>>()
        .join(" ")
}

/// The left half as drawn, the right one mirrored
const SIDES: [fn(f64) -> f64; 2] = [|x| x, mirror];

struct Drawing {
    out: String,
    ink: String,
}

impl Drawing {
    fn line_in(&mut self, d: &str, width: f64, color: &str) {
        let _ = write!(
            self.out,
            r#"<path d="{d}" stroke="{color}" stroke-width="{}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>"#,
            n(width)
        );
    }

    fn line(&mut self, d: &str, width: f64) {
        let ink = self.ink.clone();
        self.line_in(d, width, &ink);
    }

    fn push(&mut self, text: &str) {
        self.out.push_str(text);
    }
}

#[allow(clippy::too_many_lines)]
fn owl(fig: &str, ink: &str, pupil: &str, lid: f64) -> String {
    let mut o = Drawing {
        out: String::new(),
        ink: ink.to_string(),
    };

    // Wings: ten primaries fanning out, the coverts above them, rows of small feathers
    for f in SIDES {
        let count = 10;
        for k in 0..count {
            let t = f64::from(k) / f64::from(count - 1);
            let (tx, ty) = (136.0 + t * (424.0 - 136.0), 470.0 + t * 24.0);
            let angle = (-13.0 * (1.0 - t).powf(1.2)).to_radians();
            let length = 262.0 - 36.0 * t;
            let (bx, by) = (tx + length * angle.sin(), ty + length * angle.cos());
            let w = 16.0;
            o.push(&format!(
                r#"<path d="M{} {} L{} {} Q{} {} {} {} L{} {} Z" fill="{fig}"/>"#,
                d(f(tx - w)),
                d(ty),
                d(f(bx - w + 2.0)),
                d(by - 30.0),
                d(f(bx)),
                d(by + 14.0),
                d(f(bx + w - 2.0)),
                d(by - 30.0),
                d(f(tx + w)),
                d(ty)
            ));
            o.line(
                &format!(
                    "M{} {} L{} {}",
                    d(f(tx)),
                    d(ty + 4.0),
                    d(f(bx)),
                    d(by - 6.0)
                ),
                3.0,
            );
            let barbs = 13;
            for j in 1..barbs {
                let s = f64::from(j) / f64::from(barbs);
                let (sx, sy) = (tx + (bx - tx) * s, ty + 4.0 + (by - 10.0 - ty) * s);
                for side in [-1.0, 1.0] {
                    o.line(
                        &format!(
                            "M{} {} L{} {}",
                            d(f(sx + side * 2.5)),
                            d(sy),
                            d(f(sx + side * 11.0)),
                            d(sy + 9.0)
                        ),
                        1.5,
                    );
                }
            }
        }
        let coverts: Vec<(f64, f64)> = [
            (450, 404),
            (396, 376),
            (320, 352),
            (240, 340),
            (176, 350),
            (130, 380),
            (108, 428),
            (112, 470),
            (136, 484),
            (300, 496),
            (432, 510),
            (454, 476),
        ]
        .iter()
        .map(|&(x, y)| (f(f64::from(x)), f64::from(y)))
        .collect();
        o.push(&format!(
            r#"<polygon points="{}" fill="{fig}" stroke="{fig}" stroke-width="8" stroke-linejoin="round"/>"#,
            points(&coverts)
        ));
        for (row, (base, amp, x0, x1)) in [
            (384.0, -28.0, 170.0, 420.0),
            (420.0, -22.0, 132.0, 430.0),
            (456.0, -8.0, 122.0, 432.0),
        ]
        .into_iter()
        .enumerate()
        {
            // Whole feathers between x0 and x1, about 30 apart
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            let count = ((x1 - x0) / 30.0) as u32 + 1;
            for i in 0..count {
                let x = x0 + f64::from(i) * (x1 - x0) / f64::from(count - 1);
                let u = (x - 150.0) / (430.0 - 150.0);
                let y =
                    base + amp * (PI * u).sin() + if x > 400.0 && row == 0 { 12.0 } else { 0.0 };
                o.line(
                    &format!(
                        "M{} {} Q{} {} {} {}",
                        d(f(x - 14.0)),
                        d(y - 7.0),
                        d(f(x)),
                        d(y + 12.0),
                        d(f(x + 14.0)),
                        d(y - 7.0)
                    ),
                    2.4,
                );
                o.push(&format!(
                    r#"<circle cx="{}" cy="{}" r="2.4" fill="{ink}"/>"#,
                    d(f(x)),
                    d(y - 1.0)
                ));
            }
        }
        for i in 0..12 {
            let u = f64::from(i) / 11.0;
            let (x, y) = (128.0 + u * (432.0 - 128.0), 484.0 + u * 22.0);
            o.push(&format!(
                r#"<circle cx="{}" cy="{}" r="15" fill="{fig}"/>"#,
                d(f(x)),
                d(y)
            ));
            o.line(
                &format!(
                    "M{} {} Q{} {} {} {}",
                    d(f(x - 14.0)),
                    d(y + 2.0),
                    d(f(x)),
                    d(y + 22.0),
                    d(f(x + 14.0)),
                    d(y + 2.0)
                ),
                2.4,
            );
        }
        o.line(
            &format!(
                "M{} 372 Q{} 330 {} 396",
                d(f(150.0)),
                d(f(290.0)),
                d(f(436.0))
            ),
            2.2,
        );
    }

    // Body with scales
    let left = [
        (500.0, 380.0),
        (450.0, 388.0),
        (426.0, 430.0),
        (418.0, 510.0),
        (422.0, 590.0),
        (436.0, 660.0),
        (462.0, 712.0),
        (500.0, 732.0),
    ];
    let mut body = left.to_vec();
    body.extend(
        left[1..left.len() - 1]
            .iter()
            .rev()
            .map(|&(x, y)| (mirror(x), y)),
    );
    let body = points(&body);
    o.push(&format!(
        r#"<clipPath id="body"><polygon points="{body}"/></clipPath><polygon points="{body}" fill="{fig}"/>"#
    ));
    let mut scales = Drawing {
        out: String::new(),
        ink: ink.to_string(),
    };
    for (row, y) in (420..724).step_by(24).enumerate() {
        let start = 404 + if row % 2 == 1 { 12 } else { 0 };
        for x in (start..604).step_by(24) {
            scales.line(
                &format!("M{} {} Q{x} {} {} {}", x - 11, y - 6, y + 11, x + 11, y - 6),
                2.5,
            );
            scales.push(&format!(
                r#"<circle cx="{x}" cy="{y}" r="1.8" fill="{ink}"/>"#
            ));
        }
    }
    o.push(&format!(r#"<g clip-path="url(#body)">{}</g>"#, scales.out));

    // Legs and talons
    for f in SIDES {
        o.push(&format!(
            r#"<path d="M{} 696 L{} 766 L{} 766 L{} 706 Z" fill="{fig}"/>"#,
            n(f(458.0)),
            n(f(456.0)),
            n(f(488.0)),
            n(f(490.0))
        ));
        for y in (712..764).step_by(9) {
            o.line(
                &format!(
                    "M{} {y} L{} {} L{} {y}",
                    n(f(460.0)),
                    n(f(473.0)),
                    y + 6,
                    n(f(486.0))
                ),
                1.8,
            );
        }
        for (ex, ey) in [(424.0, 800.0), (462.0, 814.0), (500.0, 804.0)] {
            o.line_in(
                &format!("M{} 766 L{} {}", n(f(472.0)), n(f(ex)), n(ey)),
                14.0,
                fig,
            );
            o.line_in(
                &format!(
                    "M{} {} Q{} {} {} {}",
                    n(f(ex)),
                    n(ey),
                    n(f(ex + (ex - 472.0) * 0.3)),
                    n(ey + 16.0),
                    n(f(ex - 3.0)),
                    n(ey + 24.0)
                ),
                5.0,
                fig,
            );
            for q in [0.35, 0.6, 0.82] {
                let (px, py) = (472.0 + (ex - 472.0) * q, 766.0 + (ey - 766.0) * q);
                o.line(
                    &format!(
                        "M{} {} L{} {}",
                        d(f(px - 4.0)),
                        d(py - 2.0),
                        d(f(px + 4.0)),
                        d(py + 2.0)
                    ),
                    1.8,
                );
            }
        }
    }

    // Head: a superellipse with ear tufts
    let mut half = Vec::new();
    for i in (0..181).step_by(6) {
        let a = f64::from(90 + i).to_radians();
        let (c, s) = (a.cos(), a.sin());
        let x = 500.0 + 158.0 * c.abs().powf(2.0 / 2.3).copysign(c);
        let mut y = 292.0 - 120.0 * s.abs().powf(2.0 / 2.3).copysign(s);
        if y < 240.0 {
            y -= 26.0 * (-((x - 382.0).powi(2)) / 700.0).exp();
        }
        half.push((x, y));
    }
    let mut head = half.clone();
    head.extend(
        half[1..half.len() - 1]
            .iter()
            .rev()
            .map(|&(x, y)| (mirror(x), y)),
    );
    o.push(&format!(
        r#"<polygon points="{}" fill="{fig}" stroke="{fig}" stroke-width="6" stroke-linejoin="round"/>"#,
        points(&head)
    ));
    for x in (400..604).step_by(16) {
        if (x - 500_i32).abs() >= 20 {
            o.line(&format!("M{} 190 L{x} 198 L{} 190", x - 5, x + 5), 1.8);
        }
    }

    // Eyes: white, a ring of fine lines, the pupil in the accent
    for f in SIDES {
        let (cx, cy) = (432.0, 296.0);
        o.push(&format!(
            r#"<circle cx="{}" cy="{}" r="74" fill="{EYE}" stroke="{ink}" stroke-width="3.4"/>"#,
            n(f(cx)),
            n(cy)
        ));
        o.push(&format!(
            r#"<circle cx="{}" cy="{}" r="66" fill="none" stroke="{ink}" stroke-width="1.6"/>"#,
            n(f(cx)),
            n(cy)
        ));
        for i in 0..36 {
            let a = 2.0 * PI * f64::from(i) / 36.0;
            let (x1, y1) = (cx + 44.0 * a.cos(), cy + 44.0 * a.sin());
            let (x2, y2) = (cx + 62.0 * a.cos(), cy + 62.0 * a.sin());
            o.line(
                &format!("M{} {} L{} {}", d(f(x1)), d(y1), d(f(x2)), d(y2)),
                2.6,
            );
        }
        o.push(&format!(
            r#"<circle cx="{}" cy="{}" r="38" fill="{ink}"/>"#,
            n(f(cx)),
            n(cy)
        ));
        o.push(&format!(
            r#"<circle cx="{}" cy="{}" r="32" fill="{pupil}"/>"#,
            n(f(cx)),
            n(cy)
        ));
        o.push(&format!(
            r#"<circle cx="{}" cy="{}" r="7" fill="{EYE}"/>"#,
            n(f(cx + 10.0)),
            n(cy - 11.0)
        ));
        if lid > 0.0 {
            // The eyelid in the feathers' colour, down from the top of the eye inside its outline;
            // its rim an engraved line that sags a little more the further it is closed, and the
            // seam of the closed eye a little below the middle
            let side = if f(0.0) == 0.0 { "l" } else { "r" };
            let edge = cy - 74.0 + 148.0 * lid;
            let sag = 10.0 + 16.0 * lid;
            o.push(&format!(
                r#"<clipPath id="eye-{side}"><circle cx="{}" cy="{}" r="73"/></clipPath><g clip-path="url(#eye-{side})"><path d="M{} {} L{} {} L{} {} Q{} {} {} {} Z" fill="{fig}"/></g>"#,
                n(f(cx)),
                n(cy),
                n(f(cx - 80.0)),
                n(cy - 80.0),
                n(f(cx + 80.0)),
                n(cy - 80.0),
                n(f(cx + 80.0)),
                d(edge),
                n(f(cx)),
                d(edge + 2.0 * sag),
                n(f(cx - 80.0)),
                d(edge)
            ));
            let seam = (edge + sag / 2.0).min(cy + 18.0);
            let rim = (72.0_f64.powi(2) - (seam - cy).powi(2)).max(0.0).sqrt();
            o.line(
                &format!(
                    "M{} {} Q{} {} {} {}",
                    d(f(cx - rim)),
                    d(seam),
                    n(f(cx)),
                    d(seam + sag),
                    d(f(cx + rim)),
                    d(seam)
                ),
                3.4,
            );
        }
        o.line(
            &format!(
                "M{} 222 Q{} 196 {} 248",
                n(f(360.0)),
                n(f(440.0)),
                n(f(496.0))
            ),
            3.6,
        );
    }
    o.push(&format!(
        r#"<path d="M484 338 Q500 328 516 338 L500 374 Z" fill="{ink}"/>"#
    ));
    o.out
}

/// The whole picture: the double ring and the owl, 1000 by 1000
pub fn svg(accent: &str, background: &str, lid: f64) -> String {
    let ring = format!(
        r#"<circle cx="500" cy="500" r="484" fill="none" stroke="{accent}" stroke-width="12"/><circle cx="500" cy="500" r="456" fill="none" stroke="{accent}" stroke-width="4"/>"#
    );
    // The owl a little smaller than the ring, so the talons and wing tips keep clear of it
    format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">{ring}<g transform="translate(70 66) scale(0.86)">{}</g></svg>
"#,
        owl(accent, background, accent, lid.clamp(0.0, 1.0))
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn closed_eyes_only_when_blinking() {
        let open = svg("#c8102e", "#0d0d0d", 0.0);
        let closed = svg("#c8102e", "#0d0d0d", 1.0);
        assert!(open.starts_with("<svg") && open.ends_with("</svg>\n"));
        assert!(!open.contains("eye-l") && closed.contains("eye-l") && closed.contains("eye-r"));
        // White eyes and the accent pupil, whatever the theme
        assert!(open.contains(r##"r="32" fill="#c8102e""##));
        assert!(open.contains(r##"r="74" fill="#ffffff""##));
    }

    #[test]
    fn numbers() {
        assert_eq!(n(542.0), "542");
        assert_eq!(n(409.6), "409.6");
        assert_eq!(d(458.0), "458.0");
        assert_eq!(points(&[(1.25, 2.0)]), "1.2,2.0");
    }
}
