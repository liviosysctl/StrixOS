//! The theme engine: lists, checks and applies themes.
//!
//! Paths and names come from the environment, set by the NixOS module, so the
//! program itself knows nothing about the distribution it runs in.

mod adapters;
mod color;
mod system;
mod theme;

use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use theme::{Catalog, Selection, Theme, Variant};

const USAGE: &str = "\
Usage: {name} <command>

  list                    Themes and their variants, the current one marked
  current                 The current theme, as <theme>:<variant>
  show [THEME]            Colors of a theme as JSON (default: the current one)
  status                  Whether every part of the system shows the current theme
  set THEME               Switch to THEME (<theme> or <theme>:<variant>), needs root
  apply                   Apply the stored theme again, needs root (runs at boot)

Build and boot:
  check DIR [--default THEME]
                          Check every theme in DIR, exit 1 on any problem
  render KIND THEME [--themes DIR]
                          Print what an adapter needs: tokens, installer,
                          plymouth, palette
  boot-select             In the initrd: pick the boot splash of the stored theme

Environment: THEMES_DIR, STATE_DIR, RUNTIME_DIR, DEFAULT_THEME, PLYMOUTH_PREFIX,
PLYMOUTH_BASE_CONF, PLYMOUTH_THEMES, PLYMOUTH_CONF, EFI_VARIABLE, EFIVARS_DIR,
CONSOLE_DEVICE.
";

/// Settings from the environment. Each command takes what it needs.
struct Config {
    themes_dir: Option<PathBuf>,
    state_dir: Option<PathBuf>,
    runtime_dir: Option<PathBuf>,
    default_theme: Option<String>,
    plymouth_prefix: Option<String>,
    plymouth_base_conf: Option<PathBuf>,
    plymouth_themes: Option<PathBuf>,
    plymouth_conf: Option<PathBuf>,
    efi_variable: Option<String>,
    efivars_dir: PathBuf,
    console_device: PathBuf,
}

impl Config {
    fn from_env() -> Config {
        let text = |name: &str| env::var(name).ok().filter(|value| !value.is_empty());
        let path = |name: &str| text(name).map(PathBuf::from);
        Config {
            themes_dir: path("THEMES_DIR"),
            state_dir: path("STATE_DIR"),
            runtime_dir: path("RUNTIME_DIR"),
            default_theme: text("DEFAULT_THEME"),
            plymouth_prefix: text("PLYMOUTH_PREFIX"),
            plymouth_base_conf: path("PLYMOUTH_BASE_CONF"),
            plymouth_themes: path("PLYMOUTH_THEMES"),
            plymouth_conf: path("PLYMOUTH_CONF"),
            efi_variable: text("EFI_VARIABLE"),
            efivars_dir: path("EFIVARS_DIR")
                .unwrap_or_else(|| PathBuf::from("/sys/firmware/efi/efivars")),
            console_device: path("CONSOLE_DEVICE").unwrap_or_else(|| PathBuf::from("/dev/tty0")),
        }
    }

    fn require<'a, T>(value: &'a Option<T>, name: &str) -> Result<&'a T, String> {
        value.as_ref().ok_or_else(|| format!("{name} is not set"))
    }

    fn catalog(&self) -> Result<Catalog, String> {
        Catalog::load(Config::require(&self.themes_dir, "THEMES_DIR")?)
    }

    fn selection_file(&self) -> Result<PathBuf, String> {
        Ok(Config::require(&self.state_dir, "STATE_DIR")?.join("selection"))
    }

    fn default_selection(&self) -> Result<Selection, String> {
        Selection::parse(Config::require(&self.default_theme, "DEFAULT_THEME")?)
    }
}

/// Where the current selection came from
enum Source {
    Stored,
    Default,
    /// The stored one did not work, with the reason
    Fallback(String),
}

/// The theme in effect: the stored selection if it resolves, else the default.
fn current<'a>(
    config: &Config,
    catalog: &'a Catalog,
) -> Result<(&'a Theme, &'a Variant, Source), String> {
    let stored = match config.state_dir {
        Some(_) => match fs::read_to_string(config.selection_file()?) {
            Ok(text) => Some(text),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(format!("cannot read the stored theme: {error}")),
        },
        None => None,
    };
    let mut source = Source::Default;
    if let Some(text) = stored {
        match Selection::parse(&text)
            .and_then(|selection| catalog.resolve(&selection).map(|_| selection))
        {
            Ok(selection) => {
                let (theme, variant) = catalog.resolve(&selection)?;
                return Ok((theme, variant, Source::Stored));
            }
            Err(reason) => source = Source::Fallback(reason),
        }
    }
    let (theme, variant) = catalog
        .resolve(&config.default_selection()?)
        .map_err(|error| format!("the default theme does not work: {error}"))?;
    Ok((theme, variant, source))
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let name = args
        .first()
        .map(|arg0| {
            Path::new(arg0)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default()
        })
        .unwrap_or_else(|| "theme".to_string());
    let config = Config::from_env();
    let rest: Vec<&str> = args.iter().skip(1).map(String::as_str).collect();

    let result = match rest.as_slice() {
        ["list"] => list(&config),
        ["current"] => print_current(&config),
        ["show"] => show(&config, None),
        ["show", selection] => show(&config, Some(selection)),
        ["status"] => status(&config),
        ["set", selection] => set(&config, selection),
        ["apply"] => apply_stored(&config),
        ["check", dir] => check(Path::new(dir), None),
        ["check", dir, "--default", selection] => check(Path::new(dir), Some(selection)),
        ["render", kind, selection] => render(&config, kind, selection, None),
        ["render", kind, selection, "--themes", dir] => {
            render(&config, kind, selection, Some(Path::new(dir)))
        }
        ["boot-select"] => boot_select(&config),
        [] | ["help"] | ["--help"] | ["-h"] => {
            print!("{}", USAGE.replace("{name}", &name));
            Ok(true)
        }
        ["--version"] => {
            println!("{name} {}", env!("CARGO_PKG_VERSION"));
            Ok(true)
        }
        _ => {
            eprint!("{}", USAGE.replace("{name}", &name));
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(message) => {
            eprintln!("{name}: {message}");
            ExitCode::FAILURE
        }
    }
}

fn warn_fallback(source: &Source) {
    if let Source::Fallback(reason) = source {
        eprintln!("warning: the stored theme does not work ({reason}), using the default");
    }
}

fn list(config: &Config) -> Result<bool, String> {
    let catalog = config.catalog()?;
    let current = current(config, &catalog).ok().map(|(t, v, source)| {
        warn_fallback(&source);
        (t.id.clone(), v.id.clone())
    });
    for theme in &catalog.themes {
        for variant_id in theme.variant_ids() {
            let variant = &theme.variants[variant_id];
            let mark = if current.as_ref() == Some(&(theme.id.clone(), variant.id.clone())) {
                "*"
            } else {
                " "
            };
            let selection = format!("{}:{}", theme.id, variant.id);
            println!("{mark} {selection:<24} {} · {}", theme.name, variant.name);
        }
    }
    for (id, _) in &catalog.broken {
        println!("  {id:<24} has errors, run the check to see them");
    }
    Ok(true)
}

fn print_current(config: &Config) -> Result<bool, String> {
    let catalog = config.catalog()?;
    let (theme, variant, source) = current(config, &catalog)?;
    warn_fallback(&source);
    println!("{}", Selection::resolved(theme, variant));
    Ok(true)
}

fn show(config: &Config, selection: Option<&str>) -> Result<bool, String> {
    let catalog = config.catalog()?;
    let (theme, variant) = match selection {
        Some(text) => catalog.resolve(&Selection::parse(text)?)?,
        None => {
            let (theme, variant, source) = current(config, &catalog)?;
            warn_fallback(&source);
            (theme, variant)
        }
    };
    let json = serde_json::to_string_pretty(&adapters::tokens(theme, variant))
        .map_err(|e| e.to_string())?;
    println!("{json}");
    Ok(true)
}

/// One adapter's outcome, printed as one line by `set`, `apply` and `status`.
enum Outcome {
    Done(String),
    Skipped(String),
    Failed(String),
}

fn report(part: &str, outcome: &Outcome) {
    match outcome {
        Outcome::Done(text) => println!("  {part:<10}{text}"),
        Outcome::Skipped(text) => println!("  {part:<10}skipped: {text}"),
        Outcome::Failed(text) => println!("  {part:<10}FAILED: {text}"),
    }
}

fn set(config: &Config, text: &str) -> Result<bool, String> {
    let selection = Selection::parse(text)?;
    let catalog = config.catalog()?;
    // Check before storing anything
    catalog.resolve(&selection)?;
    if !system::is_root() {
        return Err("switching the theme needs root, run it with sudo".to_string());
    }
    let state_dir = Config::require(&config.state_dir, "STATE_DIR")?;
    fs::create_dir_all(state_dir)
        .map_err(|e| format!("cannot create {}: {e}", state_dir.display()))?;
    let _lock = system::Lock::take(&state_dir.join(".lock"))
        .map_err(|e| format!("cannot lock {}: {e}", state_dir.display()))?;
    system::write_atomic(
        &config.selection_file()?,
        format!("{selection}\n").as_bytes(),
        0o644,
    )
    .map_err(|e| format!("cannot store the theme: {e}"))?;
    apply(config, &catalog)
}

fn apply_stored(config: &Config) -> Result<bool, String> {
    if !system::is_root() {
        return Err("applying the theme needs root, run it with sudo".to_string());
    }
    let catalog = config.catalog()?;
    for (id, _) in &catalog.broken {
        eprintln!("warning: the theme \"{id}\" has errors and is left out");
    }
    match &config.state_dir {
        Some(state_dir) => {
            fs::create_dir_all(state_dir)
                .map_err(|e| format!("cannot create {}: {e}", state_dir.display()))?;
            let _lock = system::Lock::take(&state_dir.join(".lock"))
                .map_err(|e| format!("cannot lock {}: {e}", state_dir.display()))?;
            apply(config, &catalog)
        }
        None => apply(config, &catalog),
    }
}

/// Brings every part of the system to the current theme.
fn apply(config: &Config, catalog: &Catalog) -> Result<bool, String> {
    let (theme, variant, source) = current(config, catalog)?;
    warn_fallback(&source);
    let selection = Selection::resolved(theme, variant);
    println!("{} · {} ({selection})", theme.name, variant.name);

    let outcomes = [
        ("tokens", apply_tokens(config, theme, variant)),
        ("console", apply_console(config, variant)),
        ("plymouth", apply_plymouth(config, &selection)),
        ("boot", apply_boot(config, &selection)),
    ];
    let mut ok = true;
    for (part, outcome) in &outcomes {
        report(part, outcome);
        ok &= !matches!(outcome, Outcome::Failed(_));
    }
    Ok(ok)
}

fn apply_tokens(config: &Config, theme: &Theme, variant: &Variant) -> Outcome {
    let Some(runtime_dir) = &config.runtime_dir else {
        return Outcome::Skipped("RUNTIME_DIR is not set".to_string());
    };
    let json = match serde_json::to_string_pretty(&adapters::tokens(theme, variant)) {
        Ok(json) => json + "\n",
        Err(error) => return Outcome::Failed(error.to_string()),
    };
    let result = fs::create_dir_all(runtime_dir)
        .and_then(|()| {
            system::write_atomic(&runtime_dir.join("tokens.json"), json.as_bytes(), 0o644)
        })
        .and_then(|()| system::symlink_atomic(&theme.dir, &runtime_dir.join("current")));
    match result {
        Ok(()) => Outcome::Done(format!("{}", runtime_dir.join("tokens.json").display())),
        Err(error) => Outcome::Failed(format!(
            "cannot write to {}: {error}",
            runtime_dir.display()
        )),
    }
}

fn apply_console(config: &Config, variant: &Variant) -> Outcome {
    let device = &config.console_device;
    match system::set_console_palette(device, &adapters::console_palette(variant)) {
        Ok(()) => match system::redraw_console(device) {
            Ok(true) => Outcome::Done("palette set, screen redrawn".to_string()),
            Ok(false) => Outcome::Done(
                "palette set (the visible console is in graphics mode, the others redraw when switched to)"
                    .to_string(),
            ),
            Err(error) => Outcome::Failed(format!(
                "palette set, but the screen could not be redrawn: {error}"
            )),
        },
        Err(error) if error.kind() == io::ErrorKind::NotFound => Outcome::Skipped(format!(
            "no virtual console ({} is missing)",
            config.console_device.display()
        )),
        Err(error) => Outcome::Failed(format!(
            "cannot set the palette on {}: {error}",
            config.console_device.display()
        )),
    }
}

/// Plymouth outside the initrd: the splash at shutdown and reboot.
fn apply_plymouth(config: &Config, selection: &Selection) -> Outcome {
    let (Some(prefix), Some(base), Some(runtime_dir)) = (
        &config.plymouth_prefix,
        &config.plymouth_base_conf,
        &config.runtime_dir,
    ) else {
        return Outcome::Skipped("no boot splash configured".to_string());
    };
    let variant = selection.variant.as_deref().expect("resolved selection");
    let name = adapters::plymouth_name(prefix, &selection.theme, variant);
    let base_text = match fs::read_to_string(base) {
        Ok(text) => text,
        Err(error) => return Outcome::Failed(format!("cannot read {}: {error}", base.display())),
    };
    let missing = config
        .plymouth_themes
        .as_ref()
        .is_some_and(|dir| !dir.join(&name).join(format!("{name}.plymouth")).is_file());
    let (conf, text) = if missing {
        (
            base_text.clone(),
            format!("no splash \"{name}\", kept the default"),
        )
    } else {
        (
            adapters::plymouth_conf(&base_text, &name),
            format!("splash {name}"),
        )
    };
    match system::write_atomic(&runtime_dir.join("plymouthd.conf"), conf.as_bytes(), 0o644) {
        Ok(()) if missing => Outcome::Failed(text),
        Ok(()) => Outcome::Done(text),
        Err(error) => Outcome::Failed(format!("cannot write plymouthd.conf: {error}")),
    }
}

/// The boot splash in the initrd reads the theme from an EFI variable.
fn apply_boot(config: &Config, selection: &Selection) -> Outcome {
    let Some(name) = &config.efi_variable else {
        return Outcome::Skipped("no boot splash configured".to_string());
    };
    let variable = system::EfiVariable::new(&config.efivars_dir, name);
    if !variable.available() {
        return Outcome::Skipped("not booted with EFI".to_string());
    }
    let value = selection.to_string();
    match variable.read() {
        Ok(Some(stored)) if stored == value.as_bytes() => {
            return Outcome::Done("next boot already shows it".to_string())
        }
        Ok(_) => {}
        Err(error) => {
            return Outcome::Failed(format!("cannot read {}: {error}", variable.path.display()))
        }
    }
    match variable.write(value.as_bytes()) {
        Ok(()) => Outcome::Done("from the next boot".to_string()),
        Err(error) => Outcome::Failed(format!("cannot write {}: {error}", variable.path.display())),
    }
}

fn status(config: &Config) -> Result<bool, String> {
    let catalog = config.catalog()?;
    let (theme, variant, source) = current(config, &catalog)?;
    let selection = Selection::resolved(theme, variant);
    let origin = match &source {
        Source::Stored => "stored".to_string(),
        Source::Default => "default, nothing stored".to_string(),
        Source::Fallback(reason) => format!("default, the stored one does not work: {reason}"),
    };
    println!("{} · {} ({selection}, {origin})", theme.name, variant.name);

    let tokens = match &config.runtime_dir {
        None => Outcome::Skipped("RUNTIME_DIR is not set".to_string()),
        Some(dir) => {
            let path = dir.join("tokens.json");
            match fs::read_to_string(&path)
                .map(|text| serde_json::from_str::<serde_json::Value>(&text))
            {
                Ok(Ok(value)) if value == adapters::tokens(theme, variant) => {
                    Outcome::Done(format!("{}", path.display()))
                }
                Ok(Ok(_)) => {
                    Outcome::Failed(format!("{} holds another theme, run apply", path.display()))
                }
                Ok(Err(error)) => Outcome::Failed(format!("{} is broken: {error}", path.display())),
                Err(error) => Outcome::Failed(format!("cannot read {}: {error}", path.display())),
            }
        }
    };
    let console = match system::console_palette(&config.console_device) {
        Ok(palette) if palette == adapters::console_palette(variant) => {
            Outcome::Done("palette matches".to_string())
        }
        Ok(_) => Outcome::Failed("another palette is set, run apply".to_string()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            Outcome::Skipped("no virtual console".to_string())
        }
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            Outcome::Skipped("needs root to read".to_string())
        }
        Err(error) => Outcome::Failed(format!("cannot read the palette: {error}")),
    };
    let plymouth = match (&config.plymouth_prefix, &config.runtime_dir) {
        (Some(prefix), Some(dir)) => {
            let name = adapters::plymouth_name(prefix, &selection.theme, &variant.id);
            match fs::read_to_string(dir.join("plymouthd.conf")) {
                Ok(text)
                    if text
                        .lines()
                        .any(|line| line.trim() == format!("Theme={name}")) =>
                {
                    Outcome::Done(format!("splash {name}"))
                }
                Ok(_) => Outcome::Failed(format!("plymouthd.conf does not name {name}, run apply")),
                Err(error) => Outcome::Failed(format!("cannot read plymouthd.conf: {error}")),
            }
        }
        _ => Outcome::Skipped("no boot splash configured".to_string()),
    };
    let boot = match &config.efi_variable {
        None => Outcome::Skipped("no boot splash configured".to_string()),
        Some(name) => {
            let variable = system::EfiVariable::new(&config.efivars_dir, name);
            if !variable.available() {
                Outcome::Skipped("not booted with EFI".to_string())
            } else {
                match variable.read() {
                    Ok(Some(value)) if value == selection.to_string().as_bytes() => {
                        Outcome::Done("next boot shows it".to_string())
                    }
                    Ok(Some(value)) => Outcome::Failed(format!(
                        "next boot shows {}, run apply",
                        String::from_utf8_lossy(&value)
                    )),
                    Ok(None) => {
                        Outcome::Failed("nothing stored for the next boot, run apply".to_string())
                    }
                    Err(error) => {
                        Outcome::Failed(format!("cannot read {}: {error}", variable.path.display()))
                    }
                }
            }
        }
    };

    let mut ok = true;
    for (part, outcome) in [
        ("tokens", &tokens),
        ("console", &console),
        ("plymouth", &plymouth),
        ("boot", &boot),
    ] {
        report(part, outcome);
        ok &= !matches!(outcome, Outcome::Failed(_));
    }
    Ok(ok)
}

fn check(dir: &Path, default: Option<&str>) -> Result<bool, String> {
    let catalog = Catalog::load(dir)?;
    for theme in &catalog.themes {
        println!(
            "ok      {:<16} {}",
            theme.id,
            theme.variant_ids().join(", ")
        );
    }
    for (id, errors) in &catalog.broken {
        println!("ERROR   {id}");
        for error in errors {
            println!("          {error}");
        }
    }
    let mut ok = catalog.broken.is_empty();
    if catalog.themes.is_empty() && catalog.broken.is_empty() {
        println!("ERROR   no theme in {}", dir.display());
        ok = false;
    }
    if let Some(text) = default {
        match Selection::parse(text).and_then(|selection| catalog.resolve(&selection).map(|_| ())) {
            Ok(()) => println!("ok      default {text}"),
            Err(error) => {
                println!("ERROR   default {text}: {error}");
                ok = false;
            }
        }
    }
    Ok(ok)
}

fn render(config: &Config, kind: &str, text: &str, themes: Option<&Path>) -> Result<bool, String> {
    let catalog = match themes {
        Some(dir) => Catalog::load(dir)?,
        None => config.catalog()?,
    };
    let (theme, variant) = catalog.resolve(&Selection::parse(text)?)?;
    let output = match kind {
        "tokens" => {
            serde_json::to_string_pretty(&adapters::tokens(theme, variant))
                .map_err(|e| e.to_string())?
                + "\n"
        }
        "installer" => adapters::installer(theme, variant),
        "plymouth" => adapters::plymouth_colors(variant),
        "palette" => adapters::palette_lines(variant).join("\n") + "\n",
        other => {
            return Err(format!(
                "unknown kind \"{other}\" (known: tokens, installer, plymouth, palette)"
            ))
        }
    };
    print!("{output}");
    Ok(true)
}

/// Runs in the initrd before Plymouth starts. Never fails the boot: on any
/// problem the default splash stays.
fn boot_select(config: &Config) -> Result<bool, String> {
    let result = (|| -> Result<String, String> {
        let name = Config::require(&config.efi_variable, "EFI_VARIABLE")?;
        let prefix = Config::require(&config.plymouth_prefix, "PLYMOUTH_PREFIX")?;
        let themes = Config::require(&config.plymouth_themes, "PLYMOUTH_THEMES")?;
        let conf_path = Config::require(&config.plymouth_conf, "PLYMOUTH_CONF")?;
        let variable = system::EfiVariable::new(&config.efivars_dir, name);
        if !variable.available() {
            return Ok("not booted with EFI, default splash".to_string());
        }
        let value = match variable
            .read()
            .map_err(|e| format!("cannot read {}: {e}", variable.path.display()))?
        {
            Some(value) => value,
            None => return Ok("no theme stored, default splash".to_string()),
        };
        let text =
            String::from_utf8(value).map_err(|_| "the stored theme is not text".to_string())?;
        let selection = Selection::parse(&text)?;
        let variant = selection
            .variant
            .as_deref()
            .ok_or_else(|| format!("the stored theme \"{text}\" has no variant"))?;
        let splash = adapters::plymouth_name(prefix, &selection.theme, variant);
        if !themes
            .join(&splash)
            .join(format!("{splash}.plymouth"))
            .is_file()
        {
            return Ok(format!(
                "no splash \"{splash}\" in this initrd, default splash"
            ));
        }
        let conf = fs::read_to_string(conf_path)
            .map_err(|e| format!("cannot read {}: {e}", conf_path.display()))?;
        // The file may be a link into the read-only store; the rename replaces the link
        system::write_atomic(
            conf_path,
            adapters::plymouth_conf(&conf, &splash).as_bytes(),
            0o644,
        )
        .map_err(|e| format!("cannot write {}: {e}", conf_path.display()))?;
        Ok(format!("splash {splash} for {selection}"))
    })();
    match result {
        Ok(message) => println!("{message}"),
        Err(message) => println!("{message}, default splash"),
    }
    Ok(true)
}
