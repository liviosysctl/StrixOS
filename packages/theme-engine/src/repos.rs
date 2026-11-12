//! Theme repositories: themes from outside the distribution, in Git
//! repositories with a fixed layout (layout 1, see the theme template).
//!
//! The connected repositories are listed in `themes.json` next to the machine
//! configuration (`/etc/nixos`). For every repository it holds the address,
//! the commit in use and the ids of its themes. The checked theme folders of
//! that commit are copied into `themes/` next to the file, so a rebuild needs
//! no network and a repository that disappears cannot break it.
//!
//! An update fetches the newest commit of every repository, checks it with the
//! same rules as the template's `check.py` plus the engine's own check, and only
//! then takes it. A repository that fails keeps its commit and gets a problem
//! line instead, so a broken theme never stops an update.

use crate::system;
use crate::theme;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::thread;
use std::time::{Duration, Instant};

/// The only layout there is so far
pub const LAYOUT: i64 = 1;
/// A theme folder holds exactly these files: data, never code
pub const THEME_FILES: [&str; 3] = ["theme.toml", "wallpaper.jpg", "wallpaper.toml"];
pub const LICENCES: [&str; 2] = ["public domain", "CC0"];
pub const WALLPAPER_SIZE: (u32, u32) = (2560, 1440);
pub const MAX_WALLPAPER: u64 = 4 * 1024 * 1024;
/// The whole checkout, Git data included
pub const MAX_REPOSITORY: u64 = 50 * 1024 * 1024;

/// themes.json
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct File {
    pub version: u32,
    #[serde(default)]
    pub repos: Vec<Repo>,
}

impl Default for File {
    fn default() -> File {
        File {
            version: 1,
            repos: Vec::new(),
        }
    }
}

/// One connected repository
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Repo {
    pub url: String,
    /// From strix-themes.toml
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// The commit in use; its themes are in themes/
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    /// Ids of the themes of that commit
    #[serde(default)]
    pub themes: Vec<String>,
    /// Why the newest commit was not taken, from the last update
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub problem: Option<String>,
}

impl Repo {
    pub fn label(&self) -> &str {
        self.name.as_deref().unwrap_or(&self.url)
    }

    /// Whether `text` (an address, owner/repo or the name) means this repository
    pub fn matches(&self, text: &str, allow_local: bool) -> bool {
        let text = text.trim();
        self.url == text
            || normalize(text, allow_local).is_ok_and(|url| url == self.url)
            || self
                .name
                .as_deref()
                .is_some_and(|name| name.eq_ignore_ascii_case(text))
    }
}

/// Where themes.json and the copied themes live
pub struct Store {
    pub file: PathBuf,
    pub dir: PathBuf,
}

impl Store {
    pub fn new(file: &Path) -> Store {
        let dir = file
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("themes");
        Store {
            file: file.to_path_buf(),
            dir,
        }
    }

    /// The file, or an empty list when there is none yet
    pub fn load(&self) -> Result<File, String> {
        match fs::read_to_string(&self.file) {
            Ok(text) => {
                let file: File = serde_json::from_str(&text)
                    .map_err(|e| format!("{} is not readable: {e}", self.file.display()))?;
                if file.version != 1 {
                    return Err(format!(
                        "{} has format {}, this engine only knows format 1",
                        self.file.display(),
                        file.version
                    ));
                }
                Ok(file)
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(File::default()),
            Err(e) => Err(format!("cannot read {}: {e}", self.file.display())),
        }
    }

    pub fn save(&self, file: &File) -> Result<(), String> {
        let mut text = serde_json::to_string_pretty(file).map_err(|e| e.to_string())?;
        text.push('\n');
        system::write_atomic(&self.file, text.as_bytes(), 0o644).map_err(|e| denied(&self.file, e))
    }

    /// Puts the themes of a checked checkout into themes/, replacing the ones
    /// the repository had before. Each theme folder is swapped in whole.
    pub fn install(&self, checkout: &Path, new: &[String], old: &[String]) -> Result<(), String> {
        fs::create_dir_all(&self.dir).map_err(|e| denied(&self.dir, e))?;
        set_mode(&self.dir, 0o755)?;
        for id in new {
            let target = self.dir.join(id);
            let fresh = self.dir.join(format!(".{id}.{}.new", std::process::id()));
            let stale = self.dir.join(format!(".{id}.{}.old", std::process::id()));
            let _ = fs::remove_dir_all(&fresh);
            fs::create_dir(&fresh).map_err(|e| denied(&fresh, e))?;
            set_mode(&fresh, 0o755)?;
            for name in THEME_FILES {
                let to = fresh.join(name);
                fs::copy(checkout.join("themes").join(id).join(name), &to)
                    .map_err(|e| format!("cannot copy {name} of {id}: {e}"))?;
                set_mode(&to, 0o644)?;
            }
            let had = target.exists();
            if had {
                fs::rename(&target, &stale).map_err(|e| denied(&target, e))?;
            }
            fs::rename(&fresh, &target).map_err(|e| denied(&target, e))?;
            if had {
                let _ = fs::remove_dir_all(&stale);
            }
        }
        for id in old.iter().filter(|id| !new.contains(id)) {
            self.uninstall(id)?;
        }
        Ok(())
    }

    pub fn uninstall(&self, id: &str) -> Result<(), String> {
        // Only plain ids, never a path: the id comes from the file
        if !theme::valid_id(id) {
            return Ok(());
        }
        match fs::remove_dir_all(self.dir.join(id)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(denied(&self.dir.join(id), e)),
        }
    }
}

fn set_mode(path: &Path, mode: u32) -> Result<(), String> {
    fs::set_permissions(path, fs::Permissions::from_mode(mode)).map_err(|e| denied(path, e))
}

fn denied(path: &Path, error: io::Error) -> String {
    if error.kind() == io::ErrorKind::PermissionDenied {
        format!(
            "cannot write {}: permission denied, run it with sudo",
            path.display()
        )
    } else {
        format!("cannot write {}: {error}", path.display())
    }
}

/// Turns what someone typed into the address that is stored: `owner/repo`
/// means GitHub, everything else must be an https:// address. Local paths and
/// file:// only when `allow_local` (tests).
pub fn normalize(text: &str, allow_local: bool) -> Result<String, String> {
    let text = text.trim();
    let text = text.strip_suffix('/').unwrap_or(text);
    if text.is_empty() {
        return Err("no address given".into());
    }
    if text.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return Err(format!("\"{text}\" is not an address"));
    }
    let short = |part: &str| {
        !part.is_empty()
            && part
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
            && !part.starts_with('.')
    };
    if let Some((owner, repo)) = text.split_once('/')
        && !text.contains(':')
        && short(owner)
        && short(repo)
    {
        return Ok(format!("https://github.com/{owner}/{repo}"));
    }
    if let Some(rest) = text.strip_prefix("https://") {
        let host = rest.split('/').next().unwrap_or("");
        if host.is_empty() || rest.len() == host.len() {
            return Err(format!("\"{text}\" names no repository"));
        }
        if host.contains('@') {
            return Err("an address with a user name or password is not taken".into());
        }
        if !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '.' | ':'))
        {
            return Err(format!("\"{host}\" is not a host name"));
        }
        return Ok(text.to_string());
    }
    if allow_local && (text.starts_with("file://") || text.starts_with('/')) {
        return Ok(text.to_string());
    }
    Err(format!(
        "\"{text}\" is not taken: only https:// addresses or owner/repo for GitHub"
    ))
}

/// Fetching with git: HTTPS only, the default branch, one commit, no
/// submodules, no LFS, no settings of the machine or the user.
pub struct Fetcher {
    pub git: PathBuf,
    pub allow_local: bool,
    pub max_bytes: u64,
    pub timeout: Duration,
}

impl Fetcher {
    pub fn new(git: PathBuf, allow_local: bool) -> Fetcher {
        Fetcher {
            git,
            allow_local,
            max_bytes: MAX_REPOSITORY,
            timeout: Duration::from_secs(180),
        }
    }

    fn git(&self) -> Command {
        let mut command = Command::new(&self.git);
        command
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_LFS_SKIP_SMUDGE", "1")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .args([
                "-c",
                "protocol.allow=never",
                "-c",
                "protocol.https.allow=always",
            ])
            .args(["-c", "core.symlinks=false", "-c", "submodule.recurse=false"])
            .args([
                "-c",
                "http.lowSpeedLimit=1024",
                "-c",
                "http.lowSpeedTime=30",
            ])
            .stdin(Stdio::null());
        if self.allow_local {
            command.args(["-c", "protocol.file.allow=always"]);
        }
        command
    }

    /// Clones the newest commit of `url` into `dest` (which must not exist)
    /// and returns the commit id.
    pub fn fetch(&self, url: &str, dest: &Path) -> Result<String, String> {
        let url = normalize(url, self.allow_local)?;
        let mut child = self
            .git()
            .args([
                "clone",
                "--quiet",
                "--depth",
                "1",
                "--single-branch",
                "--no-tags",
            ])
            .args(["--no-recurse-submodules", "--", &url])
            .arg(dest)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("cannot run {}: {e}", self.git.display()))?;
        let mut stderr = child.stderr.take().expect("piped");
        let reader = thread::spawn(move || {
            let mut text = String::new();
            let _ = stderr.read_to_string(&mut text);
            text
        });
        let start = Instant::now();
        let status = loop {
            if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
                break status;
            }
            if start.elapsed() > self.timeout {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!(
                    "fetching took longer than {} seconds",
                    self.timeout.as_secs()
                ));
            }
            thread::sleep(Duration::from_millis(50));
        };
        let message = reader.join().unwrap_or_default();
        if !status.success() {
            let line = message
                .lines()
                .rev()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("git failed")
                .trim()
                .trim_start_matches("fatal: ")
                .to_string();
            return Err(format!("cannot fetch: {line}"));
        }
        let size = tree_size(dest).map_err(|e| format!("cannot read the checkout: {e}"))?;
        if size > self.max_bytes {
            return Err(format!(
                "the repository is {} MiB, at most {} MiB are taken",
                size.div_ceil(1024 * 1024),
                self.max_bytes / (1024 * 1024)
            ));
        }
        let output = self
            .git()
            .arg("-C")
            .arg(dest)
            .args(["rev-parse", "HEAD"])
            .output()
            .map_err(|e| format!("cannot run {}: {e}", self.git.display()))?;
        let rev = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !output.status.success() || rev.len() < 40 || !rev.chars().all(|c| c.is_ascii_hexdigit())
        {
            return Err("the repository has no commit".into());
        }
        Ok(rev)
    }
}

fn tree_size(path: &Path) -> io::Result<u64> {
    let meta = fs::symlink_metadata(path)?;
    if !meta.is_dir() {
        return Ok(meta.len());
    }
    let mut total = 0;
    for entry in fs::read_dir(path)? {
        total += tree_size(&entry?.path())?;
    }
    Ok(total)
}

/// Width and height from the first frame header, or None for anything that
/// is not a JPEG
pub fn jpeg_size(data: &[u8]) -> Option<(u32, u32)> {
    if data.get(..2)? != [0xff, 0xd8] {
        return None;
    }
    let mut i = 2;
    loop {
        if *data.get(i)? != 0xff {
            return None;
        }
        while *data.get(i)? == 0xff {
            i += 1;
        }
        let marker = *data.get(i)?;
        i += 1;
        if marker == 0x01 || (0xd0..=0xd8).contains(&marker) {
            continue;
        }
        let length = u16::from_be_bytes([*data.get(i)?, *data.get(i + 1)?]) as usize;
        if (0xc0..=0xcf).contains(&marker) && !matches!(marker, 0xc4 | 0xc8 | 0xcc) {
            let h = u16::from_be_bytes([*data.get(i + 3)?, *data.get(i + 4)?]);
            let w = u16::from_be_bytes([*data.get(i + 5)?, *data.get(i + 6)?]);
            return Some((w as u32, h as u32));
        }
        if length < 2 {
            return None;
        }
        i += length;
    }
}

/// What a good repository holds
#[derive(Debug, PartialEq)]
pub struct Checked {
    pub name: String,
    pub themes: Vec<String>,
}

/// Checks a checkout against layout 1. `builtin` are the ids of the themes of
/// the distribution, `taken` the ids other connected repositories use, with
/// their names. Returns every problem, not just the first.
pub fn check(
    root: &Path,
    builtin: &[String],
    taken: &[(String, String)],
) -> Result<Checked, Vec<String>> {
    let mut fails = Vec::new();
    let marker = root.join("strix-themes.toml");
    let meta = match regular(&marker)
        .and_then(|()| fs::read_to_string(&marker).map_err(|e| format!("cannot read it: {e}")))
    {
        Ok(text) => match toml::from_str::<toml::Table>(&text) {
            Ok(table) => table,
            Err(e) => return Err(vec![format!("strix-themes.toml: {}", e.message())]),
        },
        Err(_) => {
            return Err(vec![
                "strix-themes.toml is missing: this is no theme repository".into(),
            ]);
        }
    };
    if meta.get("layout").and_then(toml::Value::as_integer) != Some(LAYOUT) {
        fails.push(format!("strix-themes.toml: layout must be {LAYOUT}"));
    }
    let text = |key: &str| {
        meta.get(key)
            .and_then(toml::Value::as_str)
            .map(str::trim)
            .filter(|t| !t.is_empty())
    };
    for key in ["name", "description"] {
        if text(key).is_none() {
            fails.push(format!("strix-themes.toml: {key} is missing"));
        }
    }
    let name = text("name").unwrap_or("").to_string();

    let dir = root.join("themes");
    let mut ids = Vec::new();
    match fs::read_dir(&dir) {
        Ok(entries) => {
            for entry in entries.flatten() {
                let file = entry.file_name().to_string_lossy().into_owned();
                let kind = entry.file_type().ok();
                if kind.is_some_and(|k| k.is_dir()) {
                    ids.push(file);
                } else if file != ".gitkeep" {
                    fails.push(format!("themes/{file}: only folders belong in themes/"));
                }
            }
        }
        Err(_) => fails.push("themes/ is missing".into()),
    }
    ids.sort();
    if ids.is_empty() && !fails.iter().any(|f| f.starts_with("themes/ ")) {
        fails.push("themes/ holds no theme".into());
    }
    for id in &ids {
        let at = format!("themes/{id}");
        if !theme::valid_id(id) {
            fails.push(format!(
                "{at}: the id must be lowercase letters, digits and single hyphens, at most 32 characters"
            ));
            continue;
        }
        if builtin.contains(id) {
            fails.push(format!(
                "{at}: {id} is a built-in theme, pick another id"
            ));
        }
        if let Some((_, other)) = taken.iter().find(|(t, _)| t == id) {
            fails.push(format!(
                "{at}: {id} is already a theme of the repository {other}"
            ));
        }
        let folder = dir.join(id);
        let files: BTreeSet<String> = fs::read_dir(&folder)
            .map(|e| {
                e.flatten()
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .collect()
            })
            .unwrap_or_default();
        for need in THEME_FILES {
            if !files.contains(need) {
                fails.push(format!("{at}: {need} is missing"));
            } else if let Err(e) = regular(&folder.join(need)) {
                fails.push(format!("{at}/{need}: {e}"));
            }
        }
        for extra in files.iter().filter(|f| !THEME_FILES.contains(&f.as_str())) {
            fails.push(format!(
                "{at}: {extra} does not belong here, a theme holds only {}",
                THEME_FILES.join(", ")
            ));
        }
        if files.contains("wallpaper.jpg") && regular(&folder.join("wallpaper.jpg")).is_ok() {
            let path = folder.join("wallpaper.jpg");
            let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            if size > MAX_WALLPAPER {
                fails.push(format!("{at}: wallpaper.jpg is larger than 4 MiB"));
            } else {
                let data = fs::read(&path).unwrap_or_default();
                if jpeg_size(&data) != Some(WALLPAPER_SIZE) {
                    fails.push(format!(
                        "{at}: wallpaper.jpg must be a JPEG of {} by {}",
                        WALLPAPER_SIZE.0, WALLPAPER_SIZE.1
                    ));
                }
            }
        }
        if files.contains("wallpaper.toml") && regular(&folder.join("wallpaper.toml")).is_ok() {
            check_wallpaper_toml(&folder.join("wallpaper.toml"), &at, &mut fails);
        }
        if files.contains("theme.toml")
            && regular(&folder.join("theme.toml")).is_ok()
            && let Err(errors) = theme::load(&folder)
        {
            fails.extend(errors.into_iter().map(|e| format!("{at}/theme.toml: {e}")));
        }
    }
    if fails.is_empty() {
        Ok(Checked { name, themes: ids })
    } else {
        Err(fails)
    }
}

fn check_wallpaper_toml(path: &Path, at: &str, fails: &mut Vec<String>) {
    let table = match fs::read_to_string(path)
        .map_err(|e| e.to_string())
        .and_then(|t| toml::from_str::<toml::Table>(&t).map_err(|e| e.message().to_string()))
    {
        Ok(table) => table,
        Err(e) => {
            fails.push(format!("{at}/wallpaper.toml: {e}"));
            return;
        }
    };
    for key in ["caption", "credit"] {
        if table
            .get(key)
            .and_then(toml::Value::as_str)
            .is_none_or(|t| t.trim().is_empty())
        {
            fails.push(format!("{at}/wallpaper.toml: {key} is missing"));
        }
    }
    if !table
        .get("licence")
        .and_then(toml::Value::as_str)
        .is_some_and(|l| LICENCES.contains(&l))
    {
        fails.push(format!(
            "{at}/wallpaper.toml: licence must be \"public domain\" or \"CC0\""
        ));
    }
    let unknown: Vec<&str> = table
        .keys()
        .map(String::as_str)
        .filter(|k| !matches!(*k, "caption" | "credit" | "licence"))
        .collect();
    if !unknown.is_empty() {
        fails.push(format!(
            "{at}/wallpaper.toml: unknown keys {}",
            unknown.join(", ")
        ));
    }
}

/// A plain file: no link, no folder
fn regular(path: &Path) -> Result<(), String> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.file_type().is_file() => Ok(()),
        Ok(_) => Err("is not a plain file".into()),
        Err(e) => Err(e.to_string()),
    }
}

/// A scratch folder for one checkout, removed when dropped
pub struct Scratch(pub PathBuf);

impl Scratch {
    pub fn new(base: &Path) -> io::Result<Scratch> {
        static COUNT: AtomicU32 = AtomicU32::new(0);
        fs::create_dir_all(base)?;
        let dir = base.join(format!(
            "theme-repo-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir(&dir)?;
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
        Ok(Scratch(dir))
    }

    pub fn checkout(&self) -> PathBuf {
        self.0.join("checkout")
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// What happened to one repository in an update
#[derive(Debug, PartialEq)]
pub enum Outcome {
    /// The newest commit is the one in use
    Current,
    /// A newer commit was taken
    Taken { rev: String },
    /// The newest commit was not taken; the old one stays
    Kept { problem: String },
}

/// Everything an update needs
pub struct Updater<'a> {
    pub store: &'a Store,
    pub fetcher: &'a Fetcher,
    pub builtin: &'a [String],
    pub scratch: &'a Path,
}

impl Updater<'_> {
    /// Fetches and checks one repository. `others` are the ids of every other
    /// connected repository.
    fn fetch_checked(
        &self,
        url: &str,
        others: &[(String, String)],
    ) -> Result<(String, Checked, Scratch), String> {
        let scratch = Scratch::new(self.scratch).map_err(|e| {
            format!(
                "cannot make a scratch folder in {}: {e}",
                self.scratch.display()
            )
        })?;
        let rev = self.fetcher.fetch(url, &scratch.checkout())?;
        let checked =
            check(&scratch.checkout(), self.builtin, others).map_err(|fails| fails.join("; "))?;
        Ok((rev, checked, scratch))
    }

    fn others(file: &File, except: usize) -> Vec<(String, String)> {
        file.repos
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != except)
            .flat_map(|(_, r)| r.themes.iter().map(|t| (t.clone(), r.label().to_string())))
            .collect()
    }

    /// Connects a repository. Nothing is stored unless it passes.
    pub fn add(&self, text: &str) -> Result<Repo, String> {
        let url = normalize(text, self.fetcher.allow_local)?;
        let mut file = self.store.load()?;
        if let Some(repo) = file.repos.iter().find(|r| r.url == url) {
            return Err(format!("{} is already connected", repo.label()));
        }
        let others = Updater::others(&file, usize::MAX);
        let (rev, checked, scratch) = self.fetch_checked(&url, &others)?;
        self.store
            .install(&scratch.checkout(), &checked.themes, &[])?;
        let repo = Repo {
            url,
            name: Some(checked.name),
            rev: Some(rev),
            themes: checked.themes,
            problem: None,
        };
        file.repos.push(repo.clone());
        self.store.save(&file)?;
        Ok(repo)
    }

    /// Disconnects a repository and removes its themes
    pub fn remove(&self, text: &str) -> Result<Repo, String> {
        let mut file = self.store.load()?;
        let index = file
            .repos
            .iter()
            .position(|r| r.matches(text, self.fetcher.allow_local))
            .ok_or_else(|| format!("no connected repository is called \"{}\"", text.trim()))?;
        let repo = file.repos.remove(index);
        self.store.save(&file)?;
        for id in &repo.themes {
            self.store.uninstall(id)?;
        }
        Ok(repo)
    }

    /// Moves every repository (or the one `only` names) to its newest commit
    /// that passes. Problems are stored, never returned as an error: the error
    /// is only for a themes.json that cannot be read or written.
    pub fn update(&self, only: Option<&str>) -> Result<Vec<(String, Outcome)>, String> {
        let mut file = self.store.load()?;
        let before = file.clone();
        if let Some(text) = only
            && !file
                .repos
                .iter()
                .any(|r| r.matches(text, self.fetcher.allow_local))
        {
            return Err(format!(
                "no connected repository is called \"{}\"",
                text.trim()
            ));
        }
        let mut report = Vec::new();
        for index in 0..file.repos.len() {
            if only.is_some_and(|text| !file.repos[index].matches(text, self.fetcher.allow_local)) {
                continue;
            }
            let others = Updater::others(&file, index);
            let url = file.repos[index].url.clone();
            let outcome = match self.fetch_checked(&url, &others) {
                Ok((rev, checked, scratch)) => {
                    let repo = &file.repos[index];
                    let missing = repo
                        .themes
                        .iter()
                        .any(|id| !self.store.dir.join(id).is_dir());
                    if repo.rev.as_deref() == Some(rev.as_str()) && !missing {
                        Outcome::Current
                    } else {
                        let old = repo.themes.clone();
                        match self
                            .store
                            .install(&scratch.checkout(), &checked.themes, &old)
                        {
                            Ok(()) => {
                                let repo = &mut file.repos[index];
                                repo.rev = Some(rev.clone());
                                repo.name = Some(checked.name);
                                repo.themes = checked.themes;
                                Outcome::Taken { rev }
                            }
                            Err(problem) => Outcome::Kept { problem },
                        }
                    }
                }
                Err(problem) => Outcome::Kept { problem },
            };
            file.repos[index].problem = match &outcome {
                Outcome::Kept { problem } => Some(problem.clone()),
                _ => None,
            };
            report.push((file.repos[index].label().to_string(), outcome));
        }
        // Untouched when nothing changed: no file appears on a machine without
        // repositories, and the time stamp stays
        if file != before {
            self.store.save(&file)?;
        }
        Ok(report)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::tests::GOOD as GOOD_TOML;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("repos-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// The smallest JPEG header with a frame of `w` by `h`
    fn jpeg(w: u16, h: u16) -> Vec<u8> {
        let mut data = vec![0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00];
        data.extend([0xff, 0xc0, 0x00, 0x0b, 0x08]);
        data.extend(h.to_be_bytes());
        data.extend(w.to_be_bytes());
        data.extend([0x01, 0x01, 0x11, 0x00, 0xff, 0xd9]);
        data
    }

    const WALLPAPER: &str = "caption = \"A plate\"\ncredit = \"An engraver, a museum, public domain\"\nlicence = \"public domain\"\n";

    fn theme(root: &Path, id: &str) {
        let dir = root.join("themes").join(id);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("theme.toml"), GOOD_TOML).unwrap();
        fs::write(dir.join("wallpaper.jpg"), jpeg(2560, 1440)).unwrap();
        fs::write(dir.join("wallpaper.toml"), WALLPAPER).unwrap();
    }

    fn repo(root: &Path, ids: &[&str]) {
        fs::create_dir_all(root).unwrap();
        fs::write(
            root.join("strix-themes.toml"),
            "layout = 1\nname = \"Test themes\"\ndescription = \"For the tests\"\n",
        )
        .unwrap();
        for id in ids {
            theme(root, id);
        }
    }

    fn git(dir: &Path, args: &[&str]) {
        let status = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args([
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@t",
                "-c",
                "commit.gpgsign=false",
            ])
            .args(args)
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .expect("git");
        assert!(status.success(), "git {args:?}");
    }

    fn commit(dir: &Path, message: &str) {
        git(dir, &["add", "-A"]);
        git(dir, &["commit", "-q", "-m", message]);
    }

    fn origin(base: &Path, ids: &[&str]) -> PathBuf {
        let dir = base.join("origin");
        repo(&dir, ids);
        git(&dir, &["init", "-q", "-b", "main"]);
        commit(&dir, "first");
        dir
    }

    fn head(dir: &Path) -> String {
        let out = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(["rev-parse", "HEAD"])
            .output()
            .unwrap();
        String::from_utf8(out.stdout).unwrap().trim().to_string()
    }

    fn builtin() -> Vec<String> {
        vec!["saturnus".into(), "janus".into()]
    }

    #[test]
    fn addresses() {
        assert_eq!(
            normalize("someone/strix-theme-x", false).unwrap(),
            "https://github.com/someone/strix-theme-x"
        );
        assert_eq!(
            normalize(" https://github.com/a/b/ ", false).unwrap(),
            "https://github.com/a/b"
        );
        assert_eq!(
            normalize("https://codeberg.org/a/b.git", false).unwrap(),
            "https://codeberg.org/a/b.git"
        );
        for bad in [
            "",
            "http://github.com/a/b",
            "git@github.com:a/b",
            "ssh://github.com/a/b",
            "https://user:pw@github.com/a/b",
            "https://github.com",
            "file:///tmp/x",
            "/tmp/x",
            "a b/c",
            "../a",
        ] {
            assert!(normalize(bad, false).is_err(), "{bad}");
        }
        assert!(normalize("/tmp/x", true).is_ok());
    }

    #[test]
    fn jpeg_sizes() {
        assert_eq!(jpeg_size(&jpeg(2560, 1440)), Some((2560, 1440)));
        assert_eq!(jpeg_size(&jpeg(1920, 1080)), Some((1920, 1080)));
        assert_eq!(jpeg_size(b"\x89PNG\r\n"), None);
        assert_eq!(jpeg_size(&[0xff, 0xd8, 0xff]), None);
        assert_eq!(jpeg_size(&[]), None);
    }

    #[test]
    fn a_good_repository_passes() {
        let dir = scratch("good");
        repo(&dir, &["lucifer", "ember"]);
        fs::write(dir.join("themes/.gitkeep"), "").unwrap();
        fs::write(dir.join("README.md"), "hi").unwrap();
        let checked = check(&dir, &builtin(), &[]).unwrap();
        assert_eq!(checked.name, "Test themes");
        assert_eq!(checked.themes, ["ember", "lucifer"]);
    }

    #[test]
    fn every_rule_is_checked() {
        let dir = scratch("bad");
        assert!(check(&dir, &[], &[]).unwrap_err()[0].contains("strix-themes.toml is missing"));

        fs::write(dir.join("strix-themes.toml"), "layout = 2\nname = \"\"\n").unwrap();
        theme(&dir, "janus");
        theme(&dir, "taken");
        theme(&dir, "Bad_Id");
        theme(&dir, "extra");
        fs::write(dir.join("themes/extra/run.sh"), "#!/bin/sh").unwrap();
        theme(&dir, "nojpeg");
        fs::write(dir.join("themes/nojpeg/wallpaper.jpg"), b"\x89PNG").unwrap();
        theme(&dir, "small");
        fs::write(dir.join("themes/small/wallpaper.jpg"), jpeg(1920, 1080)).unwrap();
        theme(&dir, "licence");
        fs::write(
            dir.join("themes/licence/wallpaper.toml"),
            "caption = \"x\"\ncredit = \"y\"\nlicence = \"CC BY\"\nmore = 1\n",
        )
        .unwrap();
        theme(&dir, "colors");
        fs::write(dir.join("themes/colors/theme.toml"), "name = \"x\"\n").unwrap();
        theme(&dir, "link");
        fs::remove_file(dir.join("themes/link/wallpaper.toml")).unwrap();
        std::os::unix::fs::symlink("/etc/passwd", dir.join("themes/link/wallpaper.toml")).unwrap();
        fs::write(dir.join("themes/loose.toml"), "").unwrap();

        let fails = check(&dir, &builtin(), &[("taken".into(), "Other".into())]).unwrap_err();
        let has = |text: &str| fails.iter().any(|f| f.contains(text));
        assert!(has("layout must be 1"), "{fails:?}");
        assert!(has("name is missing"));
        assert!(has("description is missing"));
        assert!(has("themes/janus: janus is a built-in theme"));
        assert!(has(
            "themes/taken: taken is already a theme of the repository Other"
        ));
        assert!(has("themes/Bad_Id: the id must be"));
        assert!(has("themes/extra: run.sh does not belong here"));
        assert!(has(
            "themes/nojpeg: wallpaper.jpg must be a JPEG of 2560 by 1440"
        ));
        assert!(has("themes/small: wallpaper.jpg must be a JPEG"));
        assert!(has("themes/licence/wallpaper.toml: licence must be"));
        assert!(has("themes/licence/wallpaper.toml: unknown keys more"));
        assert!(has("themes/colors/theme.toml:"));
        assert!(has("themes/link/wallpaper.toml: is not a plain file"));
        assert!(has("themes/loose.toml: only folders belong in themes/"));
    }

    #[test]
    fn a_big_wallpaper_is_refused() {
        let dir = scratch("big");
        repo(&dir, &["huge"]);
        let mut data = jpeg(2560, 1440);
        data.resize(MAX_WALLPAPER as usize + 1, 0);
        fs::write(dir.join("themes/huge/wallpaper.jpg"), data).unwrap();
        let fails = check(&dir, &[], &[]).unwrap_err();
        assert!(fails[0].contains("larger than 4 MiB"), "{fails:?}");
    }

    fn setup(name: &str) -> (PathBuf, Store, Fetcher) {
        let base = scratch(name);
        let store = Store::new(&base.join("etc/themes.json"));
        let fetcher = Fetcher::new(PathBuf::from("git"), true);
        (base, store, fetcher)
    }

    #[test]
    fn add_update_and_remove() {
        let (base, store, fetcher) = setup("cycle");
        let origin = origin(&base, &["lucifer"]);
        let tmp = base.join("tmp");
        let builtin = builtin();
        let up = Updater {
            store: &store,
            fetcher: &fetcher,
            builtin: &builtin,
            scratch: &tmp,
        };
        let url = origin.to_string_lossy().into_owned();

        let repo = up.add(&url).unwrap();
        assert_eq!(repo.themes, ["lucifer"]);
        assert_eq!(repo.rev.as_deref(), Some(head(&origin).as_str()));
        assert!(store.dir.join("lucifer/wallpaper.jpg").is_file());
        assert_eq!(
            fs::metadata(&store.file).unwrap().permissions().mode() & 0o777,
            0o644
        );
        assert!(up.add(&url).unwrap_err().contains("already connected"));
        // Nothing is left in the scratch folder
        assert_eq!(fs::read_dir(&tmp).unwrap().count(), 0);

        // Nothing new
        let report = up.update(None).unwrap();
        assert_eq!(report, [("Test themes".to_string(), Outcome::Current)]);

        // A new commit with a second theme and one renamed
        fs::rename(
            origin.join("themes/lucifer"),
            origin.join("themes/morningstar"),
        )
        .unwrap();
        theme(&origin, "ember");
        commit(&origin, "second");
        let report = up.update(Some("Test themes")).unwrap();
        assert_eq!(report[0].1, Outcome::Taken { rev: head(&origin) });
        let file = store.load().unwrap();
        assert_eq!(file.repos[0].themes, ["ember", "morningstar"]);
        assert!(store.dir.join("ember/theme.toml").is_file());
        assert!(!store.dir.join("lucifer").exists());

        // A broken commit is not taken, the old one stays and the problem is stored
        let good = head(&origin);
        fs::write(origin.join("themes/ember/wallpaper.jpg"), b"not a jpeg").unwrap();
        commit(&origin, "broken");
        let report = up.update(None).unwrap();
        match &report[0].1 {
            Outcome::Kept { problem } => assert!(
                problem.contains("wallpaper.jpg must be a JPEG"),
                "{problem}"
            ),
            other => panic!("{other:?}"),
        }
        let file = store.load().unwrap();
        assert_eq!(file.repos[0].rev.as_deref(), Some(good.as_str()));
        assert!(file.repos[0].problem.is_some());
        assert_eq!(
            jpeg_size(&fs::read(store.dir.join("ember/wallpaper.jpg")).unwrap()),
            Some((2560, 1440))
        );

        // Fixed again: taken, the problem is gone
        theme(&origin, "ember");
        commit(&origin, "fixed");
        up.update(None).unwrap();
        let file = store.load().unwrap();
        assert_eq!(file.repos[0].rev.as_deref(), Some(head(&origin).as_str()));
        assert_eq!(file.repos[0].problem, None);

        // Gone from the net: the themes stay
        fs::remove_dir_all(&origin).unwrap();
        let report = up.update(None).unwrap();
        assert!(
            matches!(&report[0].1, Outcome::Kept { problem } if problem.starts_with("cannot fetch"))
        );
        assert!(store.dir.join("ember/theme.toml").is_file());

        let removed = up.remove("test THEMES").unwrap();
        assert_eq!(removed.themes, ["ember", "morningstar"]);
        assert!(!store.dir.join("ember").exists());
        assert!(store.load().unwrap().repos.is_empty());
        assert!(
            up.remove(&url)
                .unwrap_err()
                .contains("no connected repository")
        );
    }

    #[test]
    fn a_failing_repository_is_not_added() {
        let (base, store, fetcher) = setup("refused");
        let origin = origin(&base, &["saturnus"]);
        let tmp = base.join("tmp");
        let builtin = builtin();
        let up = Updater {
            store: &store,
            fetcher: &fetcher,
            builtin: &builtin,
            scratch: &tmp,
        };
        let error = up.add(&origin.to_string_lossy()).unwrap_err();
        assert!(
            error.contains("saturnus is a built-in theme"),
            "{error}"
        );
        assert!(!store.file.exists());
        assert!(
            up.add(&base.join("nothing").to_string_lossy())
                .unwrap_err()
                .starts_with("cannot fetch")
        );
    }

    #[test]
    fn two_repositories_cannot_share_an_id() {
        let (base, store, fetcher) = setup("shared");
        let first = origin(&base.join("a"), &["ember"]);
        let second = origin(&base.join("b"), &["ember"]);
        let tmp = base.join("tmp");
        let builtin = builtin();
        let up = Updater {
            store: &store,
            fetcher: &fetcher,
            builtin: &builtin,
            scratch: &tmp,
        };
        up.add(&first.to_string_lossy()).unwrap();
        let error = up.add(&second.to_string_lossy()).unwrap_err();
        assert!(
            error.contains("ember is already a theme of the repository Test themes"),
            "{error}"
        );
    }

    #[test]
    fn a_big_repository_is_refused() {
        let (base, store, mut fetcher) = setup("huge");
        let origin = origin(&base, &["lucifer"]);
        fetcher.max_bytes = 1024;
        let tmp = base.join("tmp");
        let builtin = builtin();
        let up = Updater {
            store: &store,
            fetcher: &fetcher,
            builtin: &builtin,
            scratch: &tmp,
        };
        assert!(
            up.add(&origin.to_string_lossy())
                .unwrap_err()
                .contains("MiB are taken")
        );
    }

    #[test]
    fn only_https_without_the_test_switch() {
        let (base, _, _) = setup("https");
        let fetcher = Fetcher::new(PathBuf::from("git"), false);
        let error = fetcher
            .fetch(&base.to_string_lossy(), &base.join("x"))
            .unwrap_err();
        assert!(error.contains("only https://"), "{error}");
    }

    #[test]
    fn an_update_without_repositories_writes_nothing() {
        let (base, store, fetcher) = setup("empty");
        let builtin = builtin();
        let tmp = base.join("tmp");
        let up = Updater {
            store: &store,
            fetcher: &fetcher,
            builtin: &builtin,
            scratch: &tmp,
        };
        assert!(up.update(None).unwrap().is_empty());
        assert!(!store.file.exists());
        assert!(
            up.update(Some("x"))
                .unwrap_err()
                .contains("no connected repository")
        );
    }

    #[test]
    fn the_file_format() {
        let (_, store, _) = setup("format");
        assert_eq!(store.load().unwrap(), File::default());
        fs::create_dir_all(store.file.parent().unwrap()).unwrap();
        fs::write(&store.file, r#"{"version": 2, "repos": []}"#).unwrap();
        assert!(store.load().unwrap_err().contains("format 2"));
        fs::write(
            &store.file,
            r#"{"version": 1, "repos": [{"url": "https://x.org/a/b"}]}"#,
        )
        .unwrap();
        assert_eq!(store.load().unwrap().repos[0].themes, Vec::<String>::new());
    }
}
