//! The catalog (shell/store.toml): what the first page of the Store suggests, its categories,
//! and the names and icons of apps where nixpkgs' own name does not say it. nixpkgs has neither
//! categories nor icons, so they are chosen by hand; the search still finds every package.

use serde::Deserialize;
use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::Path;

#[derive(Deserialize, Debug, Default)]
#[serde(deny_unknown_fields)]
pub struct Catalog {
    /// The suggestions at the top of the first page
    #[serde(default)]
    pub featured: Vec<String>,
    #[serde(default, rename = "category")]
    pub categories: Vec<Category>,
    /// Names and icons by attribute (or by the name of an app the system brings along)
    #[serde(default)]
    pub apps: BTreeMap<String, App>,
}

#[derive(Deserialize, Debug)]
#[serde(deny_unknown_fields)]
pub struct Category {
    pub id: String,
    pub name: String,
    /// A symbol of StrixUI for the list of categories
    pub symbol: String,
    #[serde(default)]
    pub about: String,
    pub apps: Vec<String>,
}

#[derive(Deserialize, Debug, Default)]
#[serde(deny_unknown_fields)]
pub struct App {
    /// The name shown instead of the package's ("Zed" for zed-editor)
    #[serde(default)]
    pub name: Option<String>,
    /// The name of its icon in the icon folders ("dev.zed.Zed")
    #[serde(default)]
    pub icon: Option<String>,
}

impl Catalog {
    pub fn parse(text: &str) -> Result<Catalog, String> {
        let catalog: Catalog = toml::from_str(text).map_err(|e| e.to_string())?;
        catalog.check()?;
        Ok(catalog)
    }

    pub fn load(path: &Path) -> Result<Catalog, String> {
        let text =
            fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        Catalog::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
    }

    /// Unique categories, none empty, no app twice in one list
    fn check(&self) -> Result<(), String> {
        let mut ids = HashSet::new();
        for category in &self.categories {
            if !ids.insert(category.id.as_str()) {
                return Err(format!("the category {} is there twice", category.id));
            }
            if category.apps.is_empty() {
                return Err(format!("the category {} has no apps", category.id));
            }
            twice(&category.apps).map_or(Ok(()), |attr| {
                Err(format!("{attr} is in the category {} twice", category.id))
            })?;
        }
        twice(&self.featured).map_or(Ok(()), |attr| Err(format!("{attr} is featured twice")))
    }

    /// Every app the catalog names, in its order
    pub fn attrs(&self) -> impl Iterator<Item = &str> {
        self.featured
            .iter()
            .chain(self.categories.iter().flat_map(|c| c.apps.iter()))
            .chain(self.apps.keys())
            .map(String::as_str)
    }

    pub fn app(&self, attr: &str) -> Option<&App> {
        self.apps.get(attr)
    }
}

fn twice(list: &[String]) -> Option<&str> {
    let mut seen = HashSet::new();
    list.iter()
        .map(String::as_str)
        .find(|attr| !seen.insert(*attr))
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD: &str = r#"
featured = ["gimp", "firefox"]

[[category]]
id = "internet"
name = "Internet"
symbol = "globe"
about = "Browsers and mail"
apps = ["firefox", "zen-beta"]

[[category]]
id = "graphics"
name = "Graphics"
symbol = "palette"
apps = ["gimp"]

[apps]
zen-beta = { name = "Zen", icon = "zen-browser" }
"kdePackages.kate" = { name = "Kate" }
"#;

    #[test]
    fn reads_a_catalog() {
        let catalog = Catalog::parse(GOOD).unwrap();
        assert_eq!(catalog.featured, ["gimp", "firefox"]);
        assert_eq!(catalog.categories.len(), 2);
        assert_eq!(catalog.categories[1].about, "");
        assert_eq!(
            catalog.app("zen-beta").unwrap().name.as_deref(),
            Some("Zen")
        );
        assert!(catalog.app("kdePackages.kate").unwrap().icon.is_none());
        assert!(catalog.app("gimp").is_none());
        let attrs: HashSet<&str> = catalog.attrs().collect();
        assert_eq!(attrs.len(), 4);
    }

    #[test]
    fn says_what_is_wrong() {
        let twice = GOOD.replace("id = \"graphics\"", "id = \"internet\"");
        assert!(
            Catalog::parse(&twice)
                .unwrap_err()
                .contains("internet is there twice")
        );
        let empty = GOOD.replace("apps = [\"gimp\"]", "apps = []");
        assert!(
            Catalog::parse(&empty)
                .unwrap_err()
                .contains("graphics has no apps")
        );
        let again = GOOD.replace("[\"firefox\", \"zen-beta\"]", "[\"firefox\", \"firefox\"]");
        assert!(
            Catalog::parse(&again)
                .unwrap_err()
                .contains("firefox is in the category internet twice")
        );
        let unknown = GOOD.replace("symbol = \"palette\"", "symbol = \"palette\"\ncolour = 1");
        assert!(Catalog::parse(&unknown).unwrap_err().contains("colour"));
        assert!(Catalog::parse("").unwrap().categories.is_empty());
    }

    #[test]
    fn the_catalog_of_the_distribution_reads() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../shell/store.toml");
        if Path::new(path).exists() {
            Catalog::load(Path::new(path)).unwrap();
        }
    }
}
