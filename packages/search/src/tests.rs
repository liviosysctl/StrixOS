//! The whole search with the real menu and command files of the repository and the fixtures:
//! the golden queries of the plan (10-search.md), sources, places, ranking, the socket.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use serde_json::{Value, json};

use crate::config::Config;
use crate::entry::{Entry, Kind, Run};
use crate::index::{Index, Query};
use crate::server::State;
use crate::usage::Usage;

fn here(p: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(p)
}

fn config() -> Config {
    let mut c = Config::empty();
    c.menu = Some(here("../../shell/menu.toml"));
    c.settings = Some(here("fixtures/settings.toml"));
    c.commands = Some(here("fixtures/commands"));
    c.app_dirs = vec![
        here("fixtures/data-home/applications"),
        here("fixtures/data-dir/applications"),
    ];
    c
}

fn index() -> Index {
    let i = Index::build(&config());
    assert!(i.warnings.is_empty(), "{:?}", i.warnings);
    i
}

fn first<'a>(i: &'a Index, text: &str, filter: Option<Kind>) -> &'a Entry {
    let q = Query {
        text: text.into(),
        filter,
        scope: None,
        limit: 10,
    };
    let hits = i.query(&q, &Usage::default(), 0);
    hits.first()
        .unwrap_or_else(|| panic!("nothing for {text}"))
        .entry
}

fn place(e: &Entry) -> String {
    e.path.join(" \u{203a} ")
}

#[test]
fn golden_queries() {
    let i = index();
    let cases: [(&str, Option<Kind>, &str, Kind, &str); 7] = [
        ("theme", None, "Theme", Kind::Action, "Style"),
        (
            "nl",
            None,
            "Night light",
            Kind::Setting,
            "Settings \u{203a} Display",
        ),
        ("rs", None, "Region screenshot", Kind::Action, "Capture"),
        ("fi", Some(Kind::App), "Files", Kind::App, "Apps"),
        (
            "clock",
            None,
            "Clock style",
            Kind::Setting,
            "Settings \u{203a} Lock screen",
        ),
        (
            "theme set neu",
            None,
            "strix-theme set neutral",
            Kind::Command,
            "Commands",
        ),
        ("shut", None, "Shut down", Kind::Action, "System"),
    ];
    for (text, filter, title, kind, where_) in cases {
        let e = first(&i, text, filter);
        assert_eq!(
            (e.title.as_str(), e.kind, place(e).as_str()),
            (title, kind, where_),
            "query {text:?}"
        );
    }
}

#[test]
fn apps_follow_the_specification() {
    let i = index();
    let titles: Vec<&str> = i
        .entries
        .iter()
        .filter(|e| e.kind == Kind::App)
        .map(|e| e.title.as_str())
        .collect();
    for shown in [
        "Firefox",
        "Ghostty",
        "Files",
        "Text Editor",
        "Image Viewer",
        "Calculator",
        "Music",
        "Nested",
        "New private window",
    ] {
        assert!(titles.contains(&shown), "{shown} is missing in {titles:?}");
    }
    // Hidden in the first folder hides the same id in the second; NoDisplay, other desktops,
    // links and missing TryExec programs stay out
    for gone in [
        "Hidden by the user",
        "Mime handler",
        "Only for KDE",
        "A link",
        "Not installed",
    ] {
        assert!(!titles.contains(&gone), "{gone} should not be there");
    }
    assert!(i.get("app:sub-nested.desktop").is_some());
    let private = i.get("app:firefox.desktop:new-private-window").unwrap();
    assert_eq!(place(private), "Apps \u{203a} Firefox");
    assert_eq!(
        private.run,
        Run::Spawn(vec!["firefox".into(), "--private-window".into()])
    );
    assert!(i.get("app:firefox.desktop").unwrap().enter);
}

#[test]
fn localised_names() {
    let mut c = config();
    c.locale = crate::desktop::Locale::parse("de_CH.UTF-8");
    let i = Index::build(&c);
    assert_eq!(
        i.get("app:org.gnome.Nautilus.desktop").unwrap().title,
        "Dateien"
    );
    // still found by its keywords
    assert_eq!(first(&i, "filesystem", Some(Kind::App)).title, "Dateien");
}

#[test]
fn the_top_level_and_menus() {
    let i = index();
    let top: Vec<&str> = i
        .browse(None, None)
        .iter()
        .map(|e| e.title.as_str())
        .collect();
    assert_eq!(
        top,
        [
            "Apps",
            "Style",
            "Capture",
            "Clipboard",
            "Settings",
            "Update",
            "System",
            "Learn",
            "Commands"
        ]
    );
    let theme = i.get("action:theme").unwrap();
    assert!(theme.enter && theme.run == Run::None);
    let inside: Vec<&str> = i
        .browse(Some("action:theme"), None)
        .iter()
        .map(|e| e.title.as_str())
        .collect();
    assert_eq!(
        &inside[..3],
        ["Theme picker", "Keep this theme", "Saturnus"]
    );
    let night = i.get("setting:display/night-light").unwrap();
    assert_eq!(
        (night.value.as_deref(), night.detail.as_deref()),
        (Some("Off"), Some("Warmer colours in the evening"))
    );
    assert_eq!(
        night.run,
        Run::Spawn(
            ["strix-settings", "--page", "display", "--row=night-light"]
                .map(String::from)
                .to_vec()
        )
    );
    assert_eq!(
        i.get("setting:display").unwrap().run,
        Run::Spawn(
            ["strix-settings", "--page", "display"]
                .map(String::from)
                .to_vec()
        )
    );
}

#[test]
fn setting_values_from_commands_and_their_timeout() {
    let start = Instant::now();
    let i = index();
    assert!(start.elapsed().as_millis() < 2500);
    assert_eq!(
        i.get("setting:appearance/theme").unwrap().value.as_deref(),
        Some("Saturnus")
    );
    // a command that is too slow leaves the value empty instead of holding up the index
    assert_eq!(i.get("setting:sound/output").unwrap().value, None);
}

#[test]
fn commands_with_values_and_root() {
    let i = index();
    let set = i.get("command:strix-theme set janus").unwrap();
    assert_eq!(set.detail.as_deref(), Some("Switch to janus"));
    assert_eq!(
        set.run,
        Run::Terminal(
            ["sudo", "strix-theme", "set", "janus"]
                .map(String::from)
                .to_vec()
        )
    );
    assert_eq!(
        i.get("command:strix-theme list").unwrap().run,
        Run::Terminal(vec!["strix-theme".into(), "list".into()])
    );
    assert!(i.get("command:strix-update").is_some());
    // the description of a value finds it too
    assert_eq!(
        first(&i, "patina", Some(Kind::Command)).title,
        "strix-theme set janus"
    );
}

#[test]
fn scope_filter_and_hits() {
    let i = index();
    let q = Query {
        text: "s".into(),
        filter: None,
        scope: Some("menu:system".into()),
        limit: 50,
    };
    let hits = i.query(&q, &Usage::default(), 0);
    assert!(!hits.is_empty());
    assert!(
        hits.iter()
            .all(|h| h.entry.ancestors.iter().any(|a| a == "menu:system"))
    );
    let q = Query {
        text: "rs".into(),
        ..Query::default()
    };
    let h = &i.query(&q, &Usage::default(), 0)[0];
    assert_eq!(h.hits, [0, 7]);
    let q = Query {
        text: "theme".into(),
        filter: Some(Kind::Setting),
        ..Query::default()
    };
    assert!(
        i.query(&q, &Usage::default(), 0)
            .iter()
            .all(|h| h.entry.kind == Kind::Setting)
    );
}

#[test]
fn usage_lifts_a_result() {
    let i = index();
    let q = Query {
        text: "s".into(),
        filter: Some(Kind::Action),
        scope: Some("menu:system".into()),
        limit: 20,
    };
    let before = i.query(&q, &Usage::default(), 0)[0].entry.id.clone();
    let mut u = Usage::default();
    let target = "action:hibernate";
    assert_ne!(before, target);
    for _ in 0..20 {
        u.record(target, 1_000);
    }
    assert_eq!(i.query(&q, &u, 1_000)[0].entry.id, target);
}

#[test]
fn hidden_entries_and_own_ones() {
    let dir = std::env::temp_dir().join(format!("search-own-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("entries.toml");
    std::fs::write(
        &f,
        "hide = [\"app:firefox.desktop\"]\n[[entry]]\nid = \"vpn\"\ntitle = \"Connect VPN\"\ngroup = \"system\"\nwords = [\"network\"]\nrun = [\"nmcli\", \"connection\", \"up\", \"vpn\"]\n",
    )
    .unwrap();
    let mut c = config();
    c.own_entries = Some(f);
    let i = Index::build(&c);
    assert!(i.warnings.is_empty(), "{:?}", i.warnings);
    assert!(i.get("app:firefox.desktop").is_none());
    assert!(
        i.get("app:firefox.desktop:new-window").is_none(),
        "the app's actions go with it"
    );
    let vpn = i.get("own:vpn").unwrap();
    assert_eq!(place(vpn), "System");
    assert_eq!(first(&i, "vpn", None).id, "own:vpn");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn the_real_files_pass_the_check() {
    let mut c = config();
    c.commands = Some(here("../../shell/commands"));
    c.settings = None;
    let i = Index::build(&c);
    assert!(i.check(false).is_empty(), "{:?}", i.check(false));
    assert!(i.get("command:strix-rebuild switch").is_some());
    assert_eq!(
        i.get("action:check-updates").unwrap().run,
        Run::Terminal(vec!["strix-update".into()])
    );
}

#[test]
fn the_check_finds_emoji_and_twins() {
    let mut a = Entry::new("action:a", Kind::Action, "Launch \u{1F680}");
    a.run = Run::Spawn(vec!["true".into()]);
    let mut b = Entry::new("action:a", Kind::Action, "Twin");
    b.run = Run::Spawn(vec!["true".into()]);
    let mut c = Entry::new("action:c", Kind::Action, "Nowhere");
    c.parent = Some("menu:missing".into());
    c.run = Run::Spawn(vec!["definitely-not-installed-program".into()]);
    let i = Index::from_entries(vec![a, b, c], &[]);
    let problems = i.check(true).join("\n");
    assert!(
        problems.contains("action:a: the title has an emoji"),
        "{problems}"
    );
    assert!(problems.contains("action:a is there twice"), "{problems}");
    assert!(
        problems.contains("action:c sits in menu:missing"),
        "{problems}"
    );
    assert!(
        problems.contains("runs definitely-not-installed-program, which is not installed"),
        "{problems}"
    );
}

#[test]
fn five_thousand_entries_in_five_milliseconds() {
    let mut entries = index().entries;
    for n in 0..5000 {
        let mut e = Entry::new(
            format!("app:generated-{n}.desktop"),
            Kind::App,
            format!("Generated app number {n} with a longer name"),
        );
        e.words = "utility office tool graphics".into();
        e.run = Run::Spawn(vec!["true".into()]);
        entries.push(e);
    }
    let i = Index::from_entries(entries, &[]);
    let q = Query {
        text: "nl".into(),
        ..Query::default()
    };
    let u = Usage::default();
    i.query(&q, &u, 0);
    let runs = 20;
    let start = Instant::now();
    for _ in 0..runs {
        assert_eq!(i.query(&q, &u, 0)[0].entry.title, "Night light");
    }
    let each = start.elapsed().as_secs_f64() * 1000.0 / f64::from(runs);
    // the budget holds for the release build, which `nix build` tests; a debug build gets ten times
    let budget = if cfg!(debug_assertions) { 50.0 } else { 5.0 };
    assert!(each < budget, "{each:.2} ms per query");
}

#[test]
fn calls_over_the_socket() {
    let state = Arc::new(State::new(config()));
    let (a, b) = UnixStream::pair().unwrap();
    let s = Arc::clone(&state);
    std::thread::spawn(move || crate::server::client(s, a));
    let mut out = b.try_clone().unwrap();
    let mut lines = BufReader::new(b).lines();
    let mut ask = |call: Value| -> Value {
        writeln!(out, "{call}").unwrap();
        serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap()
    };
    let r = ask(json!({"id": 1, "method": "query", "params": {"text": "shut"}}));
    assert_eq!(r["id"], 1);
    assert_eq!(r["result"]["results"][0]["title"], "Shut down");
    assert_eq!(r["result"]["results"][0]["path"], json!(["System"]));
    let r = ask(
        json!({"id": 2, "method": "activate", "params": {"id": "action:shut-down", "dry_run": true}}),
    );
    assert_eq!(r["result"]["ran"], json!(["systemctl", "poweroff"]));
    let r = ask(json!({"id": 3, "method": "activate", "params": {"id": "menu:style"}}));
    assert_eq!(r["result"]["enter"], true);
    let r = ask(json!({"id": 4, "method": "run", "params": {"text": "ls -l", "dry_run": true}}));
    assert_eq!(
        r["result"]["ran"],
        json!(["term", "-e", "sh", "-c", "ls -l"])
    );
    let r = ask(json!({"id": 5, "method": "nothing"}));
    assert_eq!(r["error"], "unknown method \"nothing\"");
    let r = ask(json!({"id": 6, "method": "query", "params": {"text": "x", "filter": "planet"}}));
    assert!(r["error"].as_str().unwrap().starts_with("unknown filter"));
    // a rebuild tells every client; the event comes before the answer
    writeln!(out, "{}", json!({"id": 7, "method": "reload"})).unwrap();
    let two: Vec<Value> = (0..2)
        .map(|_| serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap())
        .collect();
    assert_eq!(two[0]["event"], "changed");
    assert_eq!(two[1]["id"], 7);
    assert!(two[1]["result"]["entries"].as_u64().unwrap() > 50);
}
