//! How often and how recently each entry was taken, for ranking. Kept in the state home.

use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Use {
    pub count: u32,
    /// Seconds since 1970.
    pub last: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Usage(pub HashMap<String, Use>);

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl Usage {
    /// A missing or broken file is an empty history, never an error.
    pub fn load(path: Option<&Path>) -> Usage {
        path.and_then(|p| fs::read_to_string(p).ok())
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default()
    }

    /// Writes through a temporary file, so a crash never leaves half a file.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec(self).unwrap_or_default())?;
        fs::rename(tmp, path)
    }

    pub fn record(&mut self, id: &str, at: u64) {
        let u = self.0.entry(id.to_string()).or_default();
        u.count = u.count.saturating_add(1);
        u.last = at;
    }

    /// The ranking bonus: grows with the count (slower and slower), halves every 30 days unused.
    pub fn bonus(&self, id: &str, at: u64) -> f64 {
        let Some(u) = self.0.get(id) else { return 0.0 };
        let days = at.saturating_sub(u.last) as f64 / 86_400.0;
        12.0 * (1.0 + f64::from(u.count)).ln() * 0.5_f64.powf(days / 30.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn more_and_recent_use_ranks_higher() {
        let mut u = Usage::default();
        u.record("a", 1_000_000);
        for _ in 0..9 {
            u.record("b", 1_000_000);
        }
        let at = 1_000_000;
        assert!(u.bonus("b", at) > u.bonus("a", at));
        assert!(u.bonus("b", at + 60 * 86_400) < u.bonus("b", at) / 3.0);
        assert_eq!(u.bonus("never", at), 0.0);
    }

    #[test]
    fn saves_and_loads() {
        let dir = std::env::temp_dir().join(format!("search-usage-{}", std::process::id()));
        let f = dir.join("usage.json");
        let mut u = Usage::default();
        u.record("app:firefox.desktop", 42);
        u.save(&f).unwrap();
        assert_eq!(
            Usage::load(Some(&f)).0["app:firefox.desktop"],
            Use { count: 1, last: 42 }
        );
        fs::write(&f, "not json").unwrap();
        assert!(Usage::load(Some(&f)).0.is_empty());
        let _ = fs::remove_dir_all(dir);
    }
}
