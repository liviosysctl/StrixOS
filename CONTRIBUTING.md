# Commit and release conventions

Every app repository uses the same rules, so history, changelogs and releases look alike everywhere.

## Commits

```
<type>(<scope>): <description>

[optional body: why the change was made]

[optional footers, e.g. BREAKING CHANGE: what users must do]
```

- English, imperative mood ("add", not "added"), no full stop, first line at most 72 characters, second line empty
- One logical change per commit
- `scope` is optional, lowercase, and names the area: `ui`, `api`, `config`, `nix`, `instances` …
- `!` after the type or scope marks a breaking change

| Type | Use for | Changelog | Version |
|---|---|---|---|
| `feat` | New capability | Added | minor |
| `feat` starting with change/update/improve/rename/remove/replace/… | Changed behaviour of an existing capability | Changed | minor |
| `fix` | Bug fix | Fixed | patch |
| `perf` | Faster or leaner, same behaviour | Changed | patch |
| `revert` | Revert an earlier commit | Changed | patch |
| `refactor` `docs` `style` `test` `build` `ci` `chore` | Internal work | not listed | patch |
| any type with `!` | Breaking change | Breaking | major (minor while 0.x) |

Examples:

```
feat(instances): add bulk start action
feat(ui): improve loading states in the table
fix(api): retry on 503 from incus
perf(api): cache instance state for 5 s
feat(config)!: rename PORT to KENOS_PORT
docs: explain the NixOS module options
chore(release): v1.4.0
```

## Versions

[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`, tags are `v1.4.0`. New projects start at `0.1.0`; while the major version is 0, breaking changes raise the minor version. `1.0.0` is a deliberate decision, not an automatic bump.

The version lives in every manifest (`package.json`, `Cargo.toml`, `tauri.conf.json`, `flake.nix`) and is always changed in all of them together.

## Releases

Each release has:

1. A release commit `chore(release): vX.Y.Z` that updates the version everywhere and `CHANGELOG.md`
2. An annotated tag `vX.Y.Z` whose message is one sentence describing the release
3. A GitHub release, created automatically from the tag by `.github/workflows/release.yml`

`CHANGELOG.md` and the GitHub release are generated from the commits with git-cliff (`cliff.toml`) and always have this structure; empty sections are left out:

```markdown
## v1.3.0 — 2026-10-01

One sentence on what this release is about.

### Added
### Changed
### Fixed
### Breaking
```

## Tooling

- `git config core.hooksPath .githooks` once per clone activates the commit-message check (the Nix dev shell does this automatically)
- `git-cliff --bumped-version` shows the next version, `git-cliff --unreleased --bump` previews the next changelog entry
