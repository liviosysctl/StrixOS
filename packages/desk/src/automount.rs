//! `<id>-automount`: a stick, a card or a drive that is plugged in is mounted by itself (udisks2,
//! as Files mounts one on a click), and a message says so; its button opens it in the file
//! manager that is chosen (`<id>-defaults run files`). One that is locked (LUKS) asks for its
//! passphrase in a terminal and is mounted once it is open. What is plugged in at the start of
//! the session is mounted too. Started with the session (`<id>-automount.service`); it waits on
//! the system bus and does nothing in between.
//!
//! What udisks2 marks as part of the machine (HintSystem), to be ignored (HintIgnore) or not to
//! be mounted by itself (HintAuto) stays as it is.

use std::collections::HashMap;
use std::process::{Command, ExitCode, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use dbus::Path;
use dbus::arg::{PropMap, RefArg};
use dbus::blocking::stdintf::org_freedesktop_dbus::{
    ObjectManager, ObjectManagerInterfacesAdded, Properties,
};
use dbus::blocking::{Connection, Proxy};

use crate::Call;

const UDISKS: &str = "org.freedesktop.UDisks2";
const ROOT: &str = "/org/freedesktop/UDisks2";
const BLOCK: &str = "org.freedesktop.UDisks2.Block";
const FILESYSTEM: &str = "org.freedesktop.UDisks2.Filesystem";
const ENCRYPTED: &str = "org.freedesktop.UDisks2.Encrypted";
/// A call to udisks2; mounting may wait for a password in the polkit window
const WAIT: Duration = Duration::from_secs(120);

/// Objects that udisks2 announced, with the interfaces they got
type Added = Vec<(Path<'static>, HashMap<String, PropMap>)>;

/// What udisks2 says of a block device, as far as mounting it by itself goes
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Device {
    /// /dev/sdb1
    pub file: String,
    pub label: String,
    pub auto: bool,
    pub ignore: bool,
    pub system: bool,
    /// It has a file system (the Filesystem interface)
    pub filesystem: bool,
    pub mounted: bool,
    /// It is LUKS (the Encrypted interface)
    pub encrypted: bool,
    /// LUKS that is open: its cleartext device is there
    pub open: bool,
    /// The LUKS device this is the cleartext of, else None
    pub backing: Option<String>,
}

#[derive(Debug, PartialEq)]
pub enum Act {
    Mount,
    Unlock,
    Nothing,
}

/// What to do with a device; `backing` is the LUKS device a cleartext device belongs to, whose
/// hints count for it
pub fn act(device: &Device, backing: Option<&Device>) -> Act {
    let hints = backing.unwrap_or(device);
    if hints.ignore || hints.system || !hints.auto {
        return Act::Nothing;
    }
    if device.filesystem && !device.mounted {
        Act::Mount
    } else if device.encrypted && !device.open {
        Act::Unlock
    } else {
        Act::Nothing
    }
}

/// The device from the properties of its interfaces
pub fn device(interfaces: &HashMap<String, PropMap>) -> Option<Device> {
    let block = interfaces.get(BLOCK)?;
    let filesystem = interfaces.get(FILESYSTEM);
    let encrypted = interfaces.get(ENCRYPTED);
    let label = text(block, "IdLabel");
    let file = bytes(block, "PreferredDevice")
        .filter(|f| !f.is_empty())
        .or_else(|| bytes(block, "Device"))
        .unwrap_or_default();
    Some(Device {
        label: if label.is_empty() {
            file.clone()
        } else {
            label
        },
        file,
        auto: flag(block, "HintAuto"),
        ignore: flag(block, "HintIgnore"),
        system: flag(block, "HintSystem"),
        filesystem: filesystem.is_some(),
        mounted: filesystem.is_some_and(|f| count(f, "MountPoints") > 0),
        encrypted: encrypted.is_some(),
        open: encrypted.is_some_and(|e| path(e, "CleartextDevice").is_some()),
        backing: path(block, "CryptoBackingDevice"),
    })
}

fn flag(map: &PropMap, key: &str) -> bool {
    map.get(key)
        .and_then(|v| v.0.as_u64())
        .is_some_and(|v| v != 0)
}

fn text(map: &PropMap, key: &str) -> String {
    map.get(key)
        .and_then(|v| v.0.as_str())
        .unwrap_or_default()
        .to_string()
}

/// An object path, None for "/" (none)
fn path(map: &PropMap, key: &str) -> Option<String> {
    map.get(key)
        .and_then(|v| v.0.as_str())
        .filter(|p| *p != "/")
        .map(str::to_string)
}

/// A byte string (ay), without its closing zero
fn bytes(map: &PropMap, key: &str) -> Option<String> {
    let bytes: Vec<u8> = map
        .get(key)?
        .0
        .as_iter()?
        .filter_map(|b| b.as_u64())
        .map(|b| b as u8)
        .take_while(|b| *b != 0)
        .collect();
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

/// How many items an array has
fn count(map: &PropMap, key: &str) -> usize {
    map.get(key)
        .and_then(|v| v.0.as_iter().map(Iterator::count))
        .unwrap_or(0)
}

/// Every interface of an object with its properties, asked of udisks2
fn interfaces(bus: &Connection, object: &str) -> HashMap<String, PropMap> {
    let proxy = udisks(bus, object);
    [BLOCK, FILESYSTEM, ENCRYPTED]
        .into_iter()
        .filter_map(|name| Some((name.to_string(), proxy.get_all(name).ok()?)))
        .collect()
}

fn udisks<'a>(bus: &'a Connection, object: &'a str) -> Proxy<'a, &'a Connection> {
    bus.with_proxy(UDISKS, object, WAIT)
}

/// Mounts or unlocks the object when it should be
fn handle(bus: &Connection, id: &str, object: &str, interfaces: &HashMap<String, PropMap>) {
    let Some(device) = device(interfaces) else {
        return;
    };
    let backing = device
        .backing
        .as_deref()
        .and_then(|b| self::device(&self::interfaces(bus, b)));
    match act(&device, backing.as_ref()) {
        Act::Mount => {
            let mounted: Result<(String,), _> =
                udisks(bus, object).method_call(FILESYSTEM, "Mount", (PropMap::new(),));
            match mounted {
                Ok((place,)) => tell(
                    id,
                    &device.label,
                    &format!("Mounted at {place}"),
                    Some((
                        "open",
                        "Open",
                        vec![
                            format!("{id}-defaults"),
                            "run".into(),
                            "files".into(),
                            place,
                        ],
                    )),
                ),
                Err(e) => tell(
                    id,
                    &device.label,
                    &format!(
                        "Could not be mounted: {}",
                        e.message().unwrap_or("udisks2 failed")
                    ),
                    None,
                ),
            }
        }
        Act::Unlock => tell(
            id,
            &device.label,
            "Locked. Unlock asks for its passphrase.",
            Some((
                "unlock",
                "Unlock",
                [
                    "uwsm",
                    "app",
                    "--",
                    "ghostty",
                    "--title=Unlock",
                    "-e",
                    "udisksctl",
                    "unlock",
                    "-b",
                    &device.file,
                ]
                .map(String::from)
                .to_vec(),
            )),
        ),
        Act::Nothing => {}
    }
}

/// A message about a drive; its button, when it has one, starts `argv`. The message waits for
/// its button on a thread of its own (notify-send --wait)
fn tell(id: &str, title: &str, body: &str, button: Option<(&str, &str, Vec<String>)>) {
    let mut message = Command::new("notify-send");
    message.args(["--app-name=Files", "--icon=drive-removable-media"]);
    let Some((name, label, argv)) = button else {
        let _ = message.args([title, body]).status();
        return;
    };
    message
        .args(["--wait", &format!("--action={name}={label}"), title, body])
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let name = name.to_string();
    let id = id.to_string();
    thread::spawn(move || {
        let Ok(output) = message.output() else {
            return;
        };
        if String::from_utf8_lossy(&output.stdout).trim() == name
            && let Some((program, args)) = argv.split_first()
            && let Err(e) = Command::new(program).args(args).spawn()
        {
            eprintln!("{id}-automount: {program}: {e}");
        }
    });
}

pub fn run(call: &Call, args: &[String]) -> Result<ExitCode, String> {
    if !args.is_empty() {
        return Ok(crate::usage(call, ""));
    }
    let bus = Connection::new_system().map_err(|e| format!("system bus: {e}"))?;

    // What udisks2 announces, handled between two waits: a call to it inside the callback would
    // wait inside the wait
    let added: Arc<Mutex<Added>> = Arc::default();
    let queue = Arc::clone(&added);
    udisks(&bus, ROOT)
        .match_signal(
            move |signal: ObjectManagerInterfacesAdded, _: &Connection, _: &dbus::Message| {
                if let Ok(mut queue) = queue.lock() {
                    queue.push((signal.object, signal.interfaces));
                }
                true
            },
        )
        .map_err(|e| format!("udisks2: {e}"))?;

    // What is plugged in already, as the session starts
    let objects = udisks(&bus, ROOT)
        .get_managed_objects()
        .map_err(|e| format!("udisks2: {e}"))?;
    for (object, interfaces) in &objects {
        handle(&bus, &call.id, object, interfaces);
    }

    loop {
        bus.process(Duration::from_secs(3600))
            .map_err(|e| format!("system bus: {e}"))?;
        let batch: Vec<_> = added
            .lock()
            .map(|mut queue| queue.drain(..).collect())
            .unwrap_or_default();
        for (object, new) in batch {
            // A file system or LUKS that comes: the whole object, the block device included
            if new.contains_key(FILESYSTEM) || new.contains_key(ENCRYPTED) {
                handle(&bus, &call.id, &object, &interfaces(&bus, &object));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dbus::arg::Variant;

    fn props(entries: Vec<(&str, Box<dyn RefArg>)>) -> PropMap {
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), Variant(v)))
            .collect()
    }

    fn stick() -> HashMap<String, PropMap> {
        let mut interfaces = HashMap::new();
        interfaces.insert(
            BLOCK.to_string(),
            props(vec![
                ("Device", Box::new(b"/dev/sdb1\0".to_vec())),
                ("PreferredDevice", Box::new(b"/dev/sdb1\0".to_vec())),
                ("IdLabel", Box::new("STICK".to_string())),
                ("HintAuto", Box::new(true)),
                ("HintIgnore", Box::new(false)),
                ("HintSystem", Box::new(false)),
                ("CryptoBackingDevice", Box::new(Path::from("/"))),
            ]),
        );
        interfaces.insert(
            FILESYSTEM.to_string(),
            props(vec![("MountPoints", Box::new(Vec::<Vec<u8>>::new()))]),
        );
        interfaces
    }

    #[test]
    fn a_stick_is_read_from_its_interfaces() {
        let d = device(&stick()).unwrap();
        assert_eq!(d.file, "/dev/sdb1");
        assert_eq!(d.label, "STICK");
        assert!(d.auto && !d.ignore && !d.system);
        assert!(d.filesystem && !d.mounted && !d.encrypted);
        assert_eq!(d.backing, None);
        assert_eq!(act(&d, None), Act::Mount);
        assert!(device(&HashMap::new()).is_none());
    }

    #[test]
    fn mounted_or_part_of_the_machine_stays() {
        let mut interfaces = stick();
        interfaces.insert(
            FILESYSTEM.to_string(),
            props(vec![(
                "MountPoints",
                Box::new(vec![b"/run/media/x/STICK\0".to_vec()]),
            )]),
        );
        assert_eq!(act(&device(&interfaces).unwrap(), None), Act::Nothing);
        let d = device(&stick()).unwrap();
        for hints in [
            Device {
                system: true,
                ..d.clone()
            },
            Device {
                ignore: true,
                ..d.clone()
            },
            Device {
                auto: false,
                ..d.clone()
            },
        ] {
            assert_eq!(act(&hints, None), Act::Nothing);
        }
    }

    #[test]
    fn locked_asks_and_open_mounts_by_the_hints_of_its_luks() {
        let luks = Device {
            file: "/dev/sdb1".into(),
            auto: true,
            encrypted: true,
            ..Device::default()
        };
        assert_eq!(act(&luks, None), Act::Unlock);
        assert_eq!(
            act(
                &Device {
                    open: true,
                    ..luks.clone()
                },
                None
            ),
            Act::Nothing
        );
        // The cleartext device is marked as part of the machine; its LUKS is not
        let clear = Device {
            filesystem: true,
            system: true,
            backing: Some("/org/freedesktop/UDisks2/block_devices/sdb1".into()),
            ..Device::default()
        };
        assert_eq!(act(&clear, Some(&luks)), Act::Mount);
        assert_eq!(act(&clear, None), Act::Nothing);
    }
}
