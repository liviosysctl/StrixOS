//! Every entry in memory, and the ranking.
//!
//! Ranking: the fuzzy score of the title (nucleo-matcher, the matcher of the Helix editor), an
//! exact title counts extra; an entry found only by its place or extra words counts half. Then
//! usage. Ties go to the kind order (action, app, setting, command, menu), then the shorter title.
//! Results far below the best one are dropped.

use std::collections::{HashMap, HashSet};

use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config as MatcherConfig, Matcher, Utf32Str};
use serde::Serialize;

use crate::config::Config;
use crate::entry::{Entry, Kind, Run, is_emoji};
use crate::sources;
use crate::usage::Usage;

pub struct Index {
    pub entries: Vec<Entry>,
    by_id: HashMap<String, usize>,
    /// Problems found while reading the sources. The index works without the broken parts.
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct Query {
    pub text: String,
    pub filter: Option<Kind>,
    pub scope: Option<String>,
    pub limit: usize,
}

#[derive(Serialize)]
pub struct Hit<'a> {
    #[serde(flatten)]
    pub entry: &'a Entry,
    pub score: f64,
    /// Positions (in characters) of the title that matched, for the bold letters.
    pub hits: Vec<u32>,
}

/// An exact title is worth this much more than its fuzzy score.
const EXACT: f64 = 50.0;
/// Results under this share of the best score are dropped.
const KEEP: f64 = 0.5;

impl Index {
    /// Reads every source of the configuration. Never fails: a broken source is a warning.
    pub fn build(cfg: &Config) -> Index {
        let mut entries = Vec::new();
        let mut warnings = Vec::new();
        let mut take = |what: Result<Vec<Entry>, String>, entries: &mut Vec<Entry>| match what {
            Ok(e) => entries.extend(e),
            Err(e) => warnings.push(e),
        };
        if let Some(m) = &cfg.menu {
            take(sources::menu(m, &cfg.id), &mut entries);
        }
        let has = |id: &str, entries: &[Entry]| {
            entries.iter().any(|e| e.id == id).then(|| id.to_string())
        };
        let (apps, settings, commands) = (
            has(sources::APPS, &entries),
            has(sources::SETTINGS, &entries),
            has(sources::COMMANDS, &entries),
        );
        entries.extend(sources::apps(cfg, apps.as_deref()));
        if let Some(s) = &cfg.settings {
            take(
                sources::settings(s, settings.as_deref(), &cfg.id),
                &mut entries,
            );
        }
        if let Some(c) = &cfg.commands {
            take(
                sources::commands(c, commands.as_deref(), &cfg.id),
                &mut entries,
            );
        }
        let mut hide = Vec::new();
        if let Some(o) = &cfg.own_entries {
            match sources::own(o) {
                Ok((own, h)) => {
                    entries.extend(own);
                    hide = h;
                }
                Err(e) => warnings.push(e),
            }
        }
        let mut index = Index::from_entries(entries, &hide);
        warnings.append(&mut index.warnings);
        index.warnings = warnings;
        index
    }

    /// Places, ancestors and which entries can be entered; hidden entries and everything below
    /// them left out. A second entry with an id already taken is dropped with a warning.
    pub fn from_entries(entries: Vec<Entry>, hide: &[String]) -> Index {
        let mut warnings = Vec::new();
        let mut seen = HashSet::new();
        let mut list: Vec<Entry> = Vec::with_capacity(entries.len());
        for e in entries {
            if seen.insert(e.id.clone()) {
                list.push(e);
            } else {
                warnings.push(format!("{} is there twice; the first one counts", e.id));
            }
        }
        let pos: HashMap<String, usize> = list
            .iter()
            .enumerate()
            .map(|(i, e)| (e.id.clone(), i))
            .collect();
        for e in &mut list {
            if let Some(p) = &e.parent
                && !pos.contains_key(p)
            {
                warnings.push(format!("{} sits in {p}, which does not exist", e.id));
                e.parent = None;
            }
        }
        // ancestors, nearest first, with a guard against loops
        let parents: Vec<Option<usize>> = list
            .iter()
            .map(|e| e.parent.as_ref().and_then(|p| pos.get(p).copied()))
            .collect();
        for i in 0..list.len() {
            let mut chain = Vec::new();
            let mut cur = parents[i];
            while let Some(p) = cur {
                if p == i || chain.contains(&p) {
                    warnings.push(format!("{} sits inside itself", list[i].id));
                    break;
                }
                chain.push(p);
                cur = parents[p];
            }
            list[i].ancestors = chain.iter().map(|&p| list[p].id.clone()).collect();
            list[i].path = chain.iter().rev().map(|&p| list[p].title.clone()).collect();
        }
        let hidden: HashSet<&str> = hide.iter().map(String::as_str).collect();
        let mut list: Vec<Entry> = list
            .into_iter()
            .filter(|e| {
                !hidden.contains(e.id.as_str())
                    && !e.ancestors.iter().any(|a| hidden.contains(a.as_str()))
            })
            .collect();
        let with_children: HashSet<String> = list.iter().filter_map(|e| e.parent.clone()).collect();
        for e in &mut list {
            e.enter = e.kind == Kind::Menu || with_children.contains(&e.id);
        }
        let by_id = list
            .iter()
            .enumerate()
            .map(|(i, e)| (e.id.clone(), i))
            .collect();
        Index {
            entries: list,
            by_id,
            warnings,
        }
    }

    pub fn get(&self, id: &str) -> Option<&Entry> {
        self.by_id.get(id).map(|&i| &self.entries[i])
    }

    /// The entries right inside `scope`, in source order; the top level without one.
    pub fn browse(&self, scope: Option<&str>, filter: Option<Kind>) -> Vec<&Entry> {
        self.entries
            .iter()
            .filter(|e| e.parent.as_deref() == scope)
            .filter(|e| {
                filter.is_none_or(|k| {
                    e.kind == k || (e.kind == Kind::Menu && e.enter && scope.is_none())
                })
            })
            .collect()
    }

    fn in_scope(e: &Entry, q: &Query) -> bool {
        let scope_ok = q
            .scope
            .as_deref()
            .is_none_or(|s| e.ancestors.iter().any(|a| a == s));
        let kind_ok = match q.filter {
            Some(k) => e.kind == k,
            None => true,
        };
        scope_ok && kind_ok
    }

    /// The results for a text, best first. An empty text browses.
    pub fn query(&self, q: &Query, usage: &Usage, at: u64) -> Vec<Hit<'_>> {
        let text = q.text.trim();
        let limit = if q.limit == 0 { 50 } else { q.limit };
        if text.is_empty() {
            return self
                .browse(q.scope.as_deref(), q.filter)
                .into_iter()
                .take(limit)
                .map(|entry| Hit {
                    entry,
                    score: 0.0,
                    hits: Vec::new(),
                })
                .collect();
        }
        let mut config = MatcherConfig::DEFAULT;
        config.prefer_prefix = true;
        let mut matcher = Matcher::new(config);
        let pattern = Pattern::parse(text, CaseMatching::Ignore, Normalization::Smart);
        let lower = text.to_lowercase();
        let mut buf = Vec::new();
        let mut indices = Vec::new();
        let mut hits: Vec<Hit> = Vec::new();
        for e in self.entries.iter().filter(|e| Index::in_scope(e, q)) {
            indices.clear();
            let score = if let Some(s) = pattern.indices(
                Utf32Str::new(&e.title, &mut buf),
                &mut matcher,
                &mut indices,
            ) {
                f64::from(s)
                    + if e.title.to_lowercase() == lower {
                        EXACT
                    } else {
                        0.0
                    }
            } else {
                indices.clear();
                let hay = format!("{} {} {}", e.title, e.path.join(" "), e.words);
                match pattern.score(Utf32Str::new(&hay, &mut buf), &mut matcher) {
                    Some(s) => f64::from(s) * 0.5,
                    None => continue,
                }
            };
            let mut positions = indices.clone();
            positions.sort_unstable();
            positions.dedup();
            hits.push(Hit {
                entry: e,
                score: score + usage.bonus(&e.id, at),
                hits: positions,
            });
        }
        hits.sort_by(|a, b| {
            b.score
                .total_cmp(&a.score)
                .then(a.entry.kind.cmp(&b.entry.kind))
                .then(
                    a.entry
                        .title
                        .chars()
                        .count()
                        .cmp(&b.entry.title.chars().count()),
                )
                .then(a.entry.title.cmp(&b.entry.title))
        });
        if let Some(best) = hits.first().map(|h| h.score)
            && best > 0.0
        {
            hits.retain(|h| h.score >= best * KEEP);
        }
        hits.truncate(limit);
        hits
    }

    /// Everything that `nix flake check` refuses: broken sources, ids twice, entries in places
    /// that do not exist, emoji, actions that run nothing, and with `programs` programs not on PATH.
    pub fn check(&self, programs: bool) -> Vec<String> {
        let mut problems = self.warnings.clone();
        for e in &self.entries {
            for (what, text) in [
                ("title", Some(e.title.as_str())),
                ("words", Some(e.words.as_str())),
                ("detail", e.detail.as_deref()),
            ] {
                if text.is_some_and(|t| t.chars().any(is_emoji)) {
                    problems.push(format!("{}: the {what} has an emoji", e.id));
                }
            }
            match &e.run {
                Run::None if !e.enter && e.kind != Kind::Menu => {
                    problems.push(format!("{}: runs nothing and has nothing inside", e.id))
                }
                Run::Spawn(argv) | Run::Terminal(argv) if argv.is_empty() => {
                    problems.push(format!("{}: runs an empty command", e.id))
                }
                Run::Spawn(argv) | Run::Terminal(argv) if programs && e.kind != Kind::App => {
                    let program = if argv[0] == "sudo" {
                        argv.get(1)
                    } else {
                        argv.first()
                    };
                    if let Some(p) = program
                        && !crate::run::on_path(p)
                    {
                        problems.push(format!("{}: runs {p}, which is not installed", e.id));
                    }
                }
                _ => {}
            }
        }
        problems
    }
}
