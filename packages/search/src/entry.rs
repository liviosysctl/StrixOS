//! One thing the search can find, whatever source it came from.

use serde::Serialize;

/// What kind of thing an entry is. The order is the tie-break when two entries score the same.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Action,
    App,
    Setting,
    Command,
    Menu,
}

impl Kind {
    pub fn parse(text: &str) -> Option<Kind> {
        Some(match text {
            "action" => Kind::Action,
            "app" => Kind::App,
            "setting" => Kind::Setting,
            "command" => Kind::Command,
            "menu" => Kind::Menu,
            _ => return None,
        })
    }
}

/// What Enter does.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Run {
    /// Nothing to run: a menu or a settings page is opened inside Search.
    #[default]
    None,
    /// A program started on its own, outside the service.
    Spawn(Vec<String>),
    /// A command line in a terminal that stays open.
    Terminal(Vec<String>),
}

/// One result. `path` is its place, the titles of the menus above it ("Settings", "Display").
#[derive(Clone, Debug, Serialize)]
pub struct Entry {
    pub id: String,
    pub kind: Kind,
    pub title: String,
    pub path: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    /// Keys of the matching hotkey, as on the cheat sheet ("Super Ctrl Space").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keys: Option<String>,
    /// The current value of a setting ("Off").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// One line about it: a setting's description, what a command does.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// Enter opens it inside Search (it has entries below it).
    pub enter: bool,
    /// Extra words it is found by, besides the title and the path.
    #[serde(skip)]
    pub words: String,
    /// Id of the entry it sits in, if any.
    #[serde(skip)]
    pub parent: Option<String>,
    /// Ids of every entry above it, nearest first. Filled in by the index.
    #[serde(skip)]
    pub ancestors: Vec<String>,
    #[serde(skip)]
    pub run: Run,
}

impl Entry {
    pub fn new(id: impl Into<String>, kind: Kind, title: impl Into<String>) -> Entry {
        Entry {
            id: id.into(),
            kind,
            title: title.into(),
            path: Vec::new(),
            icon: None,
            keys: None,
            value: None,
            detail: None,
            enter: false,
            words: String::new(),
            parent: None,
            ancestors: Vec::new(),
            run: Run::None,
        }
    }
}

/// True for characters that are emoji or turn text into emoji. Strix shows no emoji anywhere.
pub fn is_emoji(c: char) -> bool {
    matches!(c as u32,
        0x1F000..=0x1FAFF | 0x2600..=0x27BF | 0x2B50 | 0x2B55 | 0x2300..=0x23FF | 0xFE0F | 0x200D | 0x20E3)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_emoji_but_not_the_symbols_strix_uses() {
        assert!("Update \u{1F680}".chars().any(is_emoji));
        assert!("Ok \u{2705}".chars().any(is_emoji));
        assert!(!"Settings \u{203A} Display :: 8%".chars().any(is_emoji));
    }
}
