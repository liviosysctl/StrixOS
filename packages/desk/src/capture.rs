//! `<id>-capture region|window|screen|annotate|text|record|record-screen|stop|colour`:
//! screenshots, screen recordings and the colour picker of the cheat sheet (Print, Shift Print,
//! Ctrl Print, Alt Print, Ctrl Alt Print, Super Print). annotate opens a region in Satty to draw
//! and write on before it is saved (Ctrl Shift Print); text reads the words in a region and puts
//! them into the clipboard (Super Shift Print).
//!
//! Screenshots go to ~/Pictures/Screenshots and to the clipboard, recordings to
//! ~/Videos/Recordings; a notification says where. Either recording key a second time, or the red
//! mark the bar shows while it runs, stops the recording (stop).
//!
//! Choosing a region takes the keyboard, and what the shell has open over the desktop (the
//! search, the theme picker, a panel of the bar) closes when it loses it. So the screen is frozen
//! first: the region is chosen on a still picture of everything that was there, and that is what
//! is saved.

use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitCode, Stdio};
use std::thread::sleep;
use std::time::Duration;

use serde_json::Value;

use crate::run::{become_it, feed, home, notify, ok, quiet, read};
use crate::{Call, usage};

const USAGE: &str = "region|window|screen|annotate|text|record|record-screen|stop|colour";
const APP: &str = "Capture";

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    let [command] = args else {
        return Ok(usage(call, USAGE));
    };
    match command.as_str() {
        "region" => {
            let Some((area, still)) = region() else {
                return Ok(ExitCode::SUCCESS);
            };
            let done = shot(&["-g", &area]);
            still.thaw();
            done?;
        }
        "window" => {
            let Some(area) =
                read("hyprctl", &["-j", "activewindow"]).and_then(|json| window(&json))
            else {
                notify(APP, "Screenshot", "No window has the focus");
                return Ok(ExitCode::FAILURE);
            };
            shot(&["-g", &area])?;
        }
        "screen" => shot(&[])?,
        "annotate" => {
            let Some(picture) = region_picture()? else {
                return Ok(ExitCode::SUCCESS);
            };
            let file = screenshots().join(format!("{}.png", stamp()));
            fs::create_dir_all(screenshots()).map_err(|e| e.to_string())?;
            ok(
                "satty",
                &[
                    "--filename",
                    &picture.to_string_lossy(),
                    "--output-filename",
                    &file.to_string_lossy(),
                    "--copy-command",
                    "wl-copy",
                    "--early-exit",
                    "--initial-tool",
                    "arrow",
                ],
            );
            let _ = fs::remove_file(picture);
        }
        "text" => {
            let Some(picture) = region_picture()? else {
                return Ok(ExitCode::SUCCESS);
            };
            let words = read(
                "tesseract",
                &[
                    &picture.to_string_lossy(),
                    "stdout",
                    "-l",
                    "eng+deu+fra+ita",
                ],
            )
            .map(|text| lines_with_words(&text))
            .unwrap_or_default();
            let _ = fs::remove_file(picture);
            if words.is_empty() {
                notify(APP, "No text found", "Nothing readable in that region");
                return Ok(ExitCode::SUCCESS);
            }
            feed("wl-copy", &[], words.as_bytes())?;
            let start: Vec<&str> = words.lines().take(3).collect();
            notify(APP, "Text copied", &start.join("\n"));
        }
        "record" | "record-screen" | "stop" => {
            let videos = pictures_or("XDG_VIDEOS_DIR", "Videos").join("Recordings");
            if quiet("pkill", &["-INT", "-x", "wf-recorder"]) {
                notify(
                    APP,
                    "Recording stopped",
                    &format!("In {}", videos.display()),
                );
                return Ok(ExitCode::SUCCESS);
            }
            if command == "stop" {
                return Ok(ExitCode::SUCCESS);
            }
            let place = if command == "record" {
                // Chosen on the live screen: what is recorded is what moves
                let Some(area) = read("slurp", &["-d"]) else {
                    return Ok(ExitCode::SUCCESS);
                };
                ["-g".to_string(), area]
            } else {
                let screen = read("hyprctl", &["-j", "monitors"])
                    .and_then(|json| focused_screen(&json))
                    .ok_or("no screen has the focus")?;
                ["-o".to_string(), screen]
            };
            fs::create_dir_all(&videos).map_err(|e| e.to_string())?;
            notify(
                APP,
                "Recording",
                "The same key again, or the red mark in the bar, stops it",
            );
            let file = videos.join(format!("{}.mp4", stamp()));
            return become_it(
                "wf-recorder",
                &[&place[0], &place[1], "-f", &file.to_string_lossy()],
            );
        }
        "colour" => {
            if let Some(colour) = read("hyprpicker", &["--autocopy", "--format=hex"])
                && !colour.is_empty()
            {
                notify(APP, &format!("Colour {colour}"), "In the clipboard");
            }
        }
        _ => return Ok(usage(call, USAGE)),
    }
    Ok(ExitCode::SUCCESS)
}

/// A still picture of every screen over everything, until it is thawed
struct Still(Option<Child>);

impl Still {
    fn freeze() -> Still {
        let child = Command::new("hyprpicker")
            .args(["-r", "-z"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .ok();
        // until it is on the screen
        sleep(Duration::from_millis(200));
        Still(child)
    }

    fn thaw(mut self) {
        if let Some(mut child) = self.0.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// The region chosen on the frozen screen and the still picture it was chosen on, or nothing
/// after Esc, which is not an error worth a message
fn region() -> Option<(String, Still)> {
    let still = Still::freeze();
    match read("slurp", &["-d"]) {
        Some(area) => Some((area, still)),
        None => {
            still.thaw();
            None
        }
    }
}

/// The chosen region as a picture in a file of its own, for a program that reads one
fn region_picture() -> Result<Option<PathBuf>, String> {
    let Some((area, still)) = region() else {
        return Ok(None);
    };
    let picture = std::env::temp_dir().join(format!("capture-{}.png", std::process::id()));
    let taken = ok("grim", &["-g", &area, &picture.to_string_lossy()]);
    still.thaw();
    if taken {
        Ok(Some(picture))
    } else {
        Err("grim failed".into())
    }
}

/// A screenshot into the folder and the clipboard, with a message that says where
fn shot(place: &[&str]) -> Result<(), String> {
    let folder = screenshots();
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let file = folder.join(format!("{}.png", stamp()));
    let path = file.to_string_lossy();
    let mut args = place.to_vec();
    args.push(&path);
    if !ok("grim", &args) {
        return Err("grim failed".into());
    }
    let picture = File::open(&file).map_err(|e| e.to_string())?;
    let copied = Command::new("wl-copy")
        .args(["--type", "image/png"])
        .stdin(picture)
        .status()
        .is_ok_and(|status| status.success());
    if !copied {
        return Err("wl-copy failed".into());
    }
    ok(
        "notify-send",
        &[
            &format!("--app-name={APP}"),
            &format!("--icon={path}"),
            "Screenshot",
            &format!("In the clipboard and in {path}"),
        ],
    );
    Ok(())
}

fn screenshots() -> PathBuf {
    pictures_or("XDG_PICTURES_DIR", "Pictures").join("Screenshots")
}

/// The folder a variable names, else the one of that name in the home
fn pictures_or(variable: &str, folder: &str) -> PathBuf {
    std::env::var_os(variable)
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| Path::new(&home()).join(folder))
}

/// Where the window with the focus stands, as grim takes it: "X,Y WxH"
fn window(json: &str) -> Option<String> {
    let window: Value = serde_json::from_str(json).ok()?;
    let at = window.get("at")?.as_array()?;
    let size = window.get("size")?.as_array()?;
    Some(format!(
        "{},{} {}x{}",
        at.first()?.as_i64()?,
        at.get(1)?.as_i64()?,
        size.first()?.as_i64()?,
        size.get(1)?.as_i64()?
    ))
}

/// The name of the screen that has the focus
fn focused_screen(json: &str) -> Option<String> {
    let screens: Value = serde_json::from_str(json).ok()?;
    screens
        .as_array()?
        .iter()
        .find(|screen| screen.get("focused").and_then(Value::as_bool) == Some(true))?
        .get("name")?
        .as_str()
        .map(String::from)
}

/// The text without its empty lines
fn lines_with_words(text: &str) -> String {
    let lines: Vec<&str> = text
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect();
    lines.join("\n")
}

/// Now, as the name of a file: 2026-11-23_15-04-05, in the time of the machine
fn stamp() -> String {
    let mut text = [0u8; 32];
    // SAFETY: time and localtime_r only write the values they are handed, and strftime writes
    // at most the length of `text`, which it is told
    let length = unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut parts: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut parts);
        libc::strftime(
            text.as_mut_ptr().cast(),
            text.len(),
            c"%Y-%m-%d_%H-%M-%S".as_ptr(),
            &parts,
        )
    };
    String::from_utf8_lossy(&text[..length]).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_window_with_the_focus_is_a_region() {
        let json = r#"{"address": "0x1", "at": [12, 46], "size": [1896, 1022], "class": "x"}"#;
        assert_eq!(window(json).as_deref(), Some("12,46 1896x1022"));
        // Nothing has the focus: Hyprland answers an empty object
        assert_eq!(window("{}"), None);
    }

    #[test]
    fn the_focused_screen_is_found_by_name() {
        let json = r#"[{"name": "DP-1", "focused": false}, {"name": "eDP-1", "focused": true}]"#;
        assert_eq!(focused_screen(json).as_deref(), Some("eDP-1"));
        assert_eq!(focused_screen("[]"), None);
    }

    #[test]
    fn empty_lines_are_not_text() {
        assert_eq!(lines_with_words("one\n\n   \ntwo\n"), "one\ntwo");
        assert_eq!(lines_with_words(" \n\n"), "");
    }

    #[test]
    fn the_stamp_names_a_file() {
        let stamp = stamp();
        assert_eq!(stamp.len(), 19);
        assert!(
            stamp
                .chars()
                .all(|c| c.is_ascii_digit() || c == '-' || c == '_')
        );
    }
}
