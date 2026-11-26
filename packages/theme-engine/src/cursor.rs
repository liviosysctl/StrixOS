//! The pointer in the colours of a theme: a copy of an Xcursor theme (Bibata) whose dark body
//! takes a deep shade of the accent and whose light rim the text colour of the theme. Made once
//! per god when the system is built (`cursor`); the session hook switches Hyprland to the one of
//! the god shown.
//!
//! An Xcursor file is a table of chunks; an image chunk holds premultiplied ARGB pixels. The
//! pixels are recoloured by their lightness, so the soft edges stay soft, and only the sizes a
//! screen asks for are kept (a theme has 14, most of them never drawn).

use crate::color::Rgb;
use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;

const MAGIC: &[u8; 4] = b"Xcur";
const IMAGE: u32 = 0xfffd_0002;
const COMMENT: u32 = 0xfffe_0001;
/// The nominal sizes kept: 24 (the size of the session), twice it for scaled screens, and the
/// ones between
pub const SIZES: [u32; 4] = [24, 32, 48, 64];

/// The two colours of a pointer
#[derive(Clone, Copy, Debug)]
pub struct Paint {
    /// What was black
    pub body: Rgb,
    /// What was white
    pub rim: Rgb,
}

fn word(data: &[u8], at: usize) -> Result<u32, String> {
    data.get(at..at + 4)
        .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .ok_or_else(|| "the file ends inside a chunk".to_string())
}

/// One pixel, premultiplied ARGB, in the paint: its lightness says how far from body to rim
fn recolor_pixel(pixel: u32, paint: Paint) -> u32 {
    let a = pixel >> 24;
    if a == 0 {
        return pixel;
    }
    let straight =
        |shift: u32| (f64::from((pixel >> shift) & 0xff) * 255.0 / f64::from(a)).min(255.0);
    let light = (0.2126 * straight(16) + 0.7152 * straight(8) + 0.0722 * straight(0)) / 255.0;
    let color = paint.body.mix(paint.rim, light);
    let pre = |c: u8| ((f64::from(c) * f64::from(a) / 255.0).round() as u32).min(a);
    (a << 24) | (pre(color.r) << 16) | (pre(color.g) << 8) | pre(color.b)
}

/// One chunk as it stands in the file, and how long it is
struct Chunk<'a> {
    kind: u32,
    size: u32,
    bytes: &'a [u8],
}

/// The chunks of an Xcursor file in the order of its table
fn chunks(data: &[u8]) -> Result<Vec<Chunk<'_>>, String> {
    if data.get(..4) != Some(MAGIC.as_slice()) {
        return Err("not an Xcursor file".to_string());
    }
    let count = word(data, 12)? as usize;
    let mut out = Vec::with_capacity(count);
    for entry in 0..count {
        let at = 16 + entry * 12;
        let (kind, size, position) = (
            word(data, at)?,
            word(data, at + 4)?,
            word(data, at + 8)? as usize,
        );
        let header = word(data, position)? as usize;
        let length = match kind {
            IMAGE => {
                header
                    + 4 * (word(data, position + 16)? as usize)
                        * (word(data, position + 20)? as usize)
            }
            COMMENT => header + word(data, position + 16)? as usize,
            other => return Err(format!("a chunk of the unknown kind {other:#x}")),
        };
        let bytes = data
            .get(position..position + length)
            .ok_or_else(|| "a chunk reaches past the end of the file".to_string())?;
        out.push(Chunk { kind, size, bytes });
    }
    Ok(out)
}

/// One Xcursor file in the paint, with the images of `sizes` (every image when it has none of
/// them, so no pointer is lost)
pub fn recolor_file(data: &[u8], paint: Paint, sizes: &[u32]) -> Result<Vec<u8>, String> {
    let all = chunks(data)?;
    let wanted = |c: &Chunk| c.kind != IMAGE || sizes.contains(&c.size);
    let any = all
        .iter()
        .any(|c| c.kind == IMAGE && sizes.contains(&c.size));
    let kept: Vec<&Chunk> = all.iter().filter(|c| !any || wanted(c)).collect();

    let mut out = Vec::with_capacity(data.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&0x0001_0000u32.to_le_bytes());
    out.extend_from_slice(&(kept.len() as u32).to_le_bytes());
    let mut position = 16 + 12 * kept.len();
    for chunk in &kept {
        out.extend_from_slice(&chunk.kind.to_le_bytes());
        out.extend_from_slice(&chunk.size.to_le_bytes());
        out.extend_from_slice(&(position as u32).to_le_bytes());
        position += chunk.bytes.len();
    }
    for chunk in &kept {
        let start = out.len();
        out.extend_from_slice(chunk.bytes);
        if chunk.kind == IMAGE {
            let header = word(chunk.bytes, 0)? as usize;
            for pixel in out[start + header..].chunks_exact_mut(4) {
                let value = u32::from_le_bytes([pixel[0], pixel[1], pixel[2], pixel[3]]);
                pixel.copy_from_slice(&recolor_pixel(value, paint).to_le_bytes());
            }
        }
    }
    Ok(out)
}

/// A whole theme: SOURCE (with its cursors/ folder) into TARGET, named NAME, the files in the
/// paint and the links (the other names of a pointer) as links
pub fn recolor_theme(source: &Path, target: &Path, name: &str, paint: Paint) -> Result<(), String> {
    let from = source.join("cursors");
    let to = target.join("cursors");
    fs::create_dir_all(&to).map_err(|e| format!("cannot create {}: {e}", to.display()))?;
    let entries =
        fs::read_dir(&from).map_err(|e| format!("cannot read {}: {e}", from.display()))?;
    let mut files = 0;
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        let file = to.join(entry.file_name());
        let kind = entry.file_type().map_err(|e| e.to_string())?;
        if kind.is_symlink() {
            let link = fs::read_link(&path).map_err(|e| e.to_string())?;
            symlink(&link, &file).map_err(|e| format!("cannot link {}: {e}", file.display()))?;
            continue;
        }
        let data = fs::read(&path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        let new =
            recolor_file(&data, paint, &SIZES).map_err(|e| format!("{}: {e}", path.display()))?;
        fs::write(&file, new).map_err(|e| format!("cannot write {}: {e}", file.display()))?;
        files += 1;
    }
    if files == 0 {
        return Err(format!("{} has no pointers", from.display()));
    }
    let index = format!(
        "[Icon Theme]\nName={name}\nComment=The pointer of {name}, made by the theme engine\nInherits=Adwaita\n"
    );
    fs::write(target.join("index.theme"), index).map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAINT: Paint = Paint {
        body: Rgb::new(80, 14, 24),
        rim: Rgb::new(236, 230, 218),
    };

    /// An Xcursor file with one image of each size, every pixel `pixel`, and a comment
    fn file(sizes: &[u32], pixel: u32) -> Vec<u8> {
        let comment = b"made in a test";
        let mut chunks: Vec<(u32, u32, Vec<u8>)> = sizes
            .iter()
            .map(|&size| {
                let mut c = Vec::new();
                for v in [36, IMAGE, size, 1, 2, 2, 1, 1, 0] {
                    c.extend_from_slice(&u32::to_le_bytes(v));
                }
                for _ in 0..4 {
                    c.extend_from_slice(&pixel.to_le_bytes());
                }
                (IMAGE, size, c)
            })
            .collect();
        let mut c = Vec::new();
        for v in [20, COMMENT, 1, 1, comment.len() as u32] {
            c.extend_from_slice(&u32::to_le_bytes(v));
        }
        c.extend_from_slice(comment);
        chunks.push((COMMENT, 1, c));
        let mut out = MAGIC.to_vec();
        for v in [16, 0x0001_0000, chunks.len() as u32] {
            out.extend_from_slice(&u32::to_le_bytes(v));
        }
        let mut position = 16 + 12 * chunks.len();
        for (kind, size, bytes) in &chunks {
            for v in [*kind, *size, position as u32] {
                out.extend_from_slice(&v.to_le_bytes());
            }
            position += bytes.len();
        }
        for (_, _, bytes) in &chunks {
            out.extend_from_slice(bytes);
        }
        out
    }

    #[test]
    fn black_becomes_the_body_and_white_the_rim() {
        assert_eq!(recolor_pixel(0xff00_0000, PAINT), 0xff50_0e18);
        assert_eq!(recolor_pixel(0xffff_ffff, PAINT), 0xffec_e6da);
        // Transparent stays, half transparent keeps its alpha and is premultiplied again
        assert_eq!(recolor_pixel(0, PAINT), 0);
        assert_eq!(recolor_pixel(0x8000_0000, PAINT) >> 24, 0x80);
        assert_eq!(recolor_pixel(0x8000_0000, PAINT) & 0xff, 12);
    }

    #[test]
    fn only_the_sizes_asked_for_are_kept() {
        let out = recolor_file(&file(&[16, 24, 48, 96], 0xff00_0000), PAINT, &SIZES).unwrap();
        let kept = chunks(&out).unwrap();
        let sizes: Vec<u32> = kept
            .iter()
            .filter(|c| c.kind == IMAGE)
            .map(|c| c.size)
            .collect();
        assert_eq!(sizes, [24, 48]);
        assert!(kept.iter().any(|c| c.kind == COMMENT));
        let image = kept.iter().find(|c| c.kind == IMAGE).unwrap();
        assert_eq!(word(image.bytes, 36).unwrap(), 0xff50_0e18);
    }

    #[test]
    fn a_file_without_those_sizes_keeps_all() {
        let out = recolor_file(&file(&[16, 20], 0xffff_ffff), PAINT, &SIZES).unwrap();
        assert_eq!(
            chunks(&out)
                .unwrap()
                .iter()
                .filter(|c| c.kind == IMAGE)
                .count(),
            2
        );
    }

    #[test]
    fn not_a_cursor_is_refused() {
        assert!(recolor_file(b"PNG and more", PAINT, &SIZES).is_err());
        let mut short = file(&[24], 0);
        short.truncate(60);
        assert!(recolor_file(&short, PAINT, &SIZES).is_err());
    }

    #[test]
    fn a_theme_with_its_links() {
        let base = std::env::temp_dir().join(format!("cursor-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let source = base.join("source");
        fs::create_dir_all(source.join("cursors")).unwrap();
        fs::write(source.join("cursors/left_ptr"), file(&[24], 0xff00_0000)).unwrap();
        symlink("left_ptr", source.join("cursors/default")).unwrap();
        recolor_theme(&source, &base.join("target"), "Test", PAINT).unwrap();
        assert_eq!(
            fs::read_link(base.join("target/cursors/default")).unwrap(),
            Path::new("left_ptr")
        );
        let index = fs::read_to_string(base.join("target/index.theme")).unwrap();
        assert!(index.contains("Name=Test"));
        let _ = fs::remove_dir_all(&base);
    }
}
