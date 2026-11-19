//! `ms.toml` reading: a TOML 1.0 document with the tables `[project]`, `[aliases]`, `[embed]`,
//! `[dependencies]` and `[effects]`. Diagnostics, locations and their order are pinned by the
//! project tests.
use std::collections::BTreeMap;

use crate::project::error::{Location, ProjectError};
use crate::project::overlay::Overlay;
use crate::project::pathops;
use crate::project::paths::source_path;
use crate::project::quoting;
use crate::project::semver::{Requirement, Version};

/// The longest manifest line `bufio.Scanner` accepts (`MaxScanTokenSize - 1`).
const MAX_LINE: usize = 65535;

/// Both spellings of an assignment, so invalid keys and targets have distinct sites.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Assignment {
    pub key: Location,
    pub value: Location,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Project {
    pub root: String,
    pub name: String,
    pub source: String,
    pub entry: String,
    /// The manifest text as read.
    pub configuration: String,
    pub aliases: BTreeMap<String, String>,
    /// `[embed]` names mapped to canonical directories whose files are baked into the program.
    pub embed: BTreeMap<String, String>,
    /// `[dependencies]`: package names mapped to where each comes from.
    pub dependencies: BTreeMap<String, Dependency>,
    /// `[dependencies]` written `{ path = "../util" }`: names mapped to the canonical directory
    /// of another workspace member. Never locked.
    pub path_dependencies: BTreeMap<String, String>,
    /// `[workspace] members`, as written; `Some` only in a workspace root.
    pub members: Option<Vec<String>>,
    /// `[project] version`: the version a package declares, if it does.
    pub version: Option<Version>,
    /// `[effects]`: for each dependency, the effects this project allows it.
    pub allowed_effects: BTreeMap<String, Vec<String>>,
    /// `[project] effects`: the effects this project, as a package, may use.
    pub effects: Vec<String>,
    /// Dependency names mapped to the source directory of the fetched package.
    pub deps: BTreeMap<String, String>,
    /// Every fetched package this project reaches, directly or not. Empty in a package.
    pub packages: Vec<crate::project::packages::Package>,
    /// The `[project]` table header (or 1:1 when the table is absent).
    pub location: Location,
    pub assignments: BTreeMap<String, Assignment>,
}

impl Project {
    /// The fetched package that holds `path`, if any (the longest matching root).
    pub fn package_of(&self, path: &str) -> Option<&crate::project::packages::Package> {
        let path = std::path::Path::new(path);
        self.packages
            .iter()
            .filter(|p| path.starts_with(&p.root))
            .max_by_key(|p| p.root.len())
    }

    /// The manifest whose aliases and dependencies apply to imports written in `importer`.
    pub fn scope(&self, importer: &str) -> &Project {
        self.package_of(importer).map_or(self, |p| &p.project)
    }

    /// The directory imports from `importer` that name `target` may not leave: the package
    /// holding `target` for an `@` import, otherwise the importer's own project or package.
    pub fn confinement_root(&self, importer: &str, path: &str, target: &str) -> &str {
        let own = self
            .package_of(importer)
            .map_or(self.root.as_str(), |p| p.root.as_str());
        if !path.starts_with('@') {
            return own;
        }
        self.package_of(target).map_or(own, |p| p.root.as_str())
    }

    /// The name diagnostics and metadata use for a canonical file: its path from the project
    /// root, or `@package/path` for a fetched package.
    pub fn logical(&self, canonical: &str) -> Result<String, ProjectError> {
        match self.package_of(canonical) {
            Some(package) => {
                let rel = pathops::rel(&package.root, canonical)?;
                Ok(format!("{}/{}", package.key, rel))
            }
            None => pathops::rel(&self.root, canonical),
        }
    }
}

/// The nearest containing manifest, even if it is invalid. A nested project's
/// errors must not silently select a parent's configuration.
pub fn find_manifest(filename: &str) -> Option<String> {
    let mut directory = pathops::dir(filename);
    loop {
        let manifest = pathops::join(&[&directory, "ms.toml"]);
        if std::fs::metadata(&manifest).is_ok() {
            return Some(manifest);
        }
        let parent = pathops::dir(&directory);
        if parent == directory {
            return None;
        }
        directory = parent;
    }
}

/// Validate the manifest and canonicalize its paths.
pub fn read_project(filename: &str) -> Result<Project, ProjectError> {
    let (project, error) = read_project_partial(filename);
    match error {
        Some(error) => Err(error),
        None => Ok(project),
    }
}

/// Like [`read_project`], but also returns what was parsed before a failure
/// (Go returns the partial `Project` next to the error).
pub fn read_project_partial(filename: &str) -> (Project, Option<ProjectError>) {
    let mut project = Project::default();
    let error = read_manifest(filename, &mut project)
        .and_then(|()| crate::project::packages::attach(&mut project))
        .err();
    (project, error)
}

struct Failure;

impl Failure {
    fn at(&self, location: &Location, message: impl Into<String>) -> ProjectError {
        ProjectError::manifest(location.clone(), ProjectError::msg(message))
    }
}

/// Read and validate one manifest without resolving its dependencies.
pub fn read_manifest(filename: &str, p: &mut Project) -> Result<(), ProjectError> {
    read_into(filename, p)
}

fn read_into(filename: &str, p: &mut Project) -> Result<(), ProjectError> {
    let absolute = pathops::abs(filename)?;
    let root = pathops::eval_symlinks(&pathops::dir(&absolute))?;
    let file_name = pathops::base(&absolute);
    p.root = root.clone();
    p.location = Location {
        file: file_name.clone(),
        line: 1,
        column: 1,
        offset: 0,
    };
    let data = std::fs::read(&absolute).map_err(|e| ProjectError::path("open", &absolute, &e))?;
    p.configuration = String::from_utf8_lossy(&data).into_owned();
    let configuration = p.configuration.clone();
    let fail = Failure;

    if let Some(line) = configuration.split('\n').position(|l| l.len() > MAX_LINE) {
        let location = Location {
            file: file_name.clone(),
            line: line + 1,
            column: 1,
            offset: 0,
        };
        return Err(fail.at(
            &location,
            "line too long; keep each ms.toml line under 64 KiB",
        ));
    }
    // A byte-order mark is not part of the document.
    let bom = if configuration.starts_with('\u{feff}') {
        '\u{feff}'.len_utf8()
    } else {
        0
    };
    let text = &configuration[bom..];
    let at = |offset: usize| locate(&configuration, &file_name, offset + bom);
    let document = match toml_edit::Document::parse(text) {
        Ok(document) => document,
        Err(error) => {
            let start = error.span().map_or(0, |s| s.start);
            return Err(fail.at(&at(start), format!("invalid ms.toml: {}", error.message())));
        }
    };
    let mut location;
    for (name, item) in document.as_table().iter() {
        let header = item
            .as_table()
            .and_then(toml_edit::Table::span)
            .map_or(0, |s| s.start);
        location = at(header);
        let Some(table) = item.as_table_like() else {
            return Err(fail.at(
                &location,
                format!("invalid manifest assignment; {name} is not a table, so put it under a [project] table header: ms.toml starts with [project] and name = \"app\" and source = \"src\" under it"),
            ));
        };
        let section = match name {
            "project" => "project",
            "aliases" => "aliases",
            "embed" => "embed",
            "dependencies" => "dependencies",
            "effects" => "effects",
            "workspace" => "workspace",
            _ => {
                let advice = if name == "package" {
                    "rename it to [project] with name, source, and entry"
                } else {
                    "ms.toml has no other tables"
                };
                return Err(fail.at(&location, format!("unsupported manifest table [{name}]; ms.toml supports only [project], [workspace], [aliases], [embed], [dependencies] and [effects]: {advice}")));
            }
        };
        if section == "project" {
            p.location = location.clone();
        }
        if section == "workspace" {
            // A bare [workspace] is a root with no members yet, reported as such.
            p.members.get_or_insert_with(Vec::new);
        }
        for (key, value) in table.iter() {
            let (key_span, value_span) = table.get_key_value(key).map_or((0..0, 0..0), |(k, v)| {
                (k.span().unwrap_or(0..0), v.span().unwrap_or(0..0))
            });
            let key_location = at(key_span.start);
            location = at(value_span.start);
            let key = key.to_string();
            let id = format!("{section}.{key}");
            p.assignments.insert(
                id,
                Assignment {
                    key: key_location.clone(),
                    value: location.clone(),
                },
            );
            match section {
                "effects" => {
                    let list = string_list(value, &EFFECT_LIST)
                        .map_err(|e| fail.at(&location, format!("{key}: {e}")))?;
                    check_package_name(&fail, &key, &key_location)?;
                    p.allowed_effects.insert(key, list);
                }
                "workspace" => {
                    if key != "members" {
                        return Err(fail.at(
                            &key_location,
                            format!("unknown workspace key {key}; [workspace] accepts members"),
                        ));
                    }
                    let list = string_list(value, &MEMBER_LIST)
                        .map_err(|e| fail.at(&location, format!("members: {e}")))?;
                    p.members = Some(list);
                }
                "dependencies" => {
                    check_package_name(&fail, &key, &key_location)?;
                    match dependency(value)
                        .map_err(|e| fail.at(&location, format!("dependency {key}: {e}")))?
                    {
                        Declared::Git(found) => {
                            p.dependencies.insert(key, found);
                        }
                        Declared::Path(path) => {
                            let target = pathops::join(&[&root, &path]);
                            let target = pathops::eval_symlinks(&target).map_err(|e| {
                                fail.at(
                                    &location,
                                    format!(
                                        "dependency {key}: path {path:?} cannot be resolved: {e}"
                                    ),
                                )
                            })?;
                            p.path_dependencies.insert(key, target);
                        }
                    }
                }
                "project" if key == "effects" => {
                    p.effects = string_list(value, &EFFECT_LIST)
                        .map_err(|e| fail.at(&location, format!("effects: {e}")))?;
                }
                _ => {
                    // An unknown key is reported as unknown whatever its value's type.
                    if section == "project"
                        && !matches!(key.as_str(), "name" | "source" | "entry" | "version")
                    {
                        return Err(fail.at(
                            &key_location,
                            format!("unknown project key {key}; [project] accepts name, source, entry, version, and effects"),
                        ));
                    }
                    let value = text_value(&fail, &location, &key, value)?;
                    match section {
                        "project" => match key.as_str() {
                            "name" => p.name = value,
                            "source" => p.source = value,
                            "entry" => p.entry = value,
                            "version" => {
                                p.version =
                                    Some(Version::parse(&value).map_err(|e| {
                                        fail.at(&location, format!("version: {e}"))
                                    })?);
                            }
                            _ => {
                                return Err(fail.at(
                                    &key_location,
                                    format!("unknown project key {key}; [project] accepts name, source, entry, version, and effects"),
                                ));
                            }
                        },
                        "embed" => {
                            if !valid_alias(&key) || key == "@std" {
                                return Err(fail.at(
                                    &key_location,
                                    format!("invalid or reserved embed name {key}; embed names look like @assets (start with @, letters/digits/underscore) and cannot be @std"),
                                ));
                            }
                            if value.starts_with('@') {
                                return Err(fail.at(&location, format!("invalid embed target {value}; map it to a project-local directory, not an alias")));
                            }
                            p.embed.insert(key, value);
                        }
                        _ => {
                            if !valid_alias(&key) || key == "@std" {
                                return Err(fail.at(
                                    &key_location,
                                    format!("invalid or reserved alias {key}{}; aliases look like @lib (start with @, letters/digits/underscore), cannot be @std, and must map to a path, not another alias", if key != "std" && valid_alias(&format!("@{key}")) { format!(" (did you mean @{key}?)") } else { String::new() }),
                                ));
                            }
                            if value.starts_with('@') {
                                return Err(fail.at(&location, format!("invalid alias target {value}; map it to a project-local path, not another alias")));
                            }
                            p.aliases.insert(key, value);
                        }
                    }
                }
            }
        }
    }
    location = p.location.clone();
    // A root that only lists members has no source of its own.
    if p.members.is_some() && !p.assignments.keys().any(|k| k.starts_with("project.")) {
        if let Some(extra) = p.assignments.keys().find(|k| !k.starts_with("workspace.")) {
            let table = extra.split('.').next().unwrap_or(extra);
            return Err(fail.at(
                &p.assignments[extra].key.clone(),
                format!("a workspace root without [project] holds only [workspace]; move [{table}] into a member or add a [project] table"),
            ));
        }
        return Ok(());
    }
    if p.name.is_empty() || p.source.is_empty() {
        let mut missing = Vec::new();
        if p.name.is_empty() {
            missing.push("name");
        }
        if p.source.is_empty() {
            missing.push("source");
        }
        return Err(fail.at(
            &location,
            format!(
                "[project] requires name and source; missing: {}, e.g. name = \"app\", source = \"src\" (add entry = \"src/main.ms\" for an executable)",
                missing.join(", ")
            ),
        ));
    }
    let no_overlay = Overlay::new();
    location = p.assignments["project.source"].value.clone();
    p.source = source_path(&root, &p.source, &no_overlay)
        .map_err(|e| ProjectError::manifest(location.clone(), e))?;
    if !std::fs::metadata(&p.source).is_ok_and(|m| m.is_dir()) {
        return Err(fail.at(
            &location,
            format!(
                "project source must be an existing directory; {} does not exist or is not a directory, so create it or fix source in [project]",
                quoting::quote(&p.source)
            ),
        ));
    }
    if let Some(entry) = p.assignments.get("project.entry") {
        location = entry.value.clone();
        if p.entry.is_empty() {
            return Err(fail.at(
                &location,
                "project entry cannot be empty; omit entry for a library or set it to a .ms file such as \"src/main.ms\"",
            ));
        }
        p.entry = source_path(&root, &p.entry, &no_overlay)
            .map_err(|e| ProjectError::manifest(location.clone(), e))?;
        if pathops::ext(&p.entry) != ".ms" {
            return Err(fail.at(
                &location,
                "entry requires .ms extension; set entry to a .ms file such as \"src/main.ms\"",
            ));
        }
        if !std::fs::metadata(&p.entry).is_ok_and(|m| m.is_file()) {
            return Err(fail.at(
                &location,
                format!("project entry must be an existing regular file; create {} or fix entry in [project]", p.entry),
            ));
        }
    }
    let keys: Vec<String> = p.aliases.keys().cloned().collect();
    for key in keys {
        location = p.assignments[&format!("aliases.{key}")].value.clone();
        match source_path(&root, &p.aliases[&key], &no_overlay) {
            Ok(target) => {
                p.aliases.insert(key, target);
            }
            Err(error) => {
                return Err(fail.at(
                    &location,
                    format!("alias {key} target cannot be resolved: {error}; external Manuscript dependency projects are unsupported, so copy the sources inside this project root and point the alias at that copy"),
                ));
            }
        }
    }
    for key in p.dependencies.keys().chain(p.path_dependencies.keys()) {
        if p.aliases.contains_key(key) || p.embed.contains_key(key) {
            return Err(fail.at(
                &p.assignments[&format!("dependencies.{key}")].key.clone(),
                format!("{key} is declared in [dependencies] and also as an alias or embed; rename one so an import names a single thing"),
            ));
        }
    }
    for key in p.path_dependencies.keys() {
        if p.dependencies.contains_key(key) {
            return Err(fail.at(
                &p.assignments[&format!("dependencies.{key}")].key.clone(),
                format!("{key} is declared twice in [dependencies]; keep one"),
            ));
        }
    }
    for key in p.allowed_effects.keys() {
        if !p.dependencies.contains_key(key) && !p.path_dependencies.contains_key(key) {
            return Err(fail.at(
                &p.assignments[&format!("effects.{key}")].key.clone(),
                format!("[effects] names {key}, which is not under [dependencies]; remove it or add the dependency"),
            ));
        }
    }
    let keys: Vec<String> = p.embed.keys().cloned().collect();
    for key in keys {
        location = p.assignments[&format!("embed.{key}")].value.clone();
        if p.aliases.contains_key(&key) {
            return Err(fail.at(
                &p.assignments[&format!("embed.{key}")].key.clone(),
                format!("{key} is declared in both [aliases] and [embed]; rename one so an import names a single thing"),
            ));
        }
        match source_path(&root, &p.embed[&key], &no_overlay) {
            Ok(target) if std::fs::metadata(&target).is_ok_and(|m| m.is_dir()) => {
                p.embed.insert(key, target);
            }
            Ok(target) => {
                return Err(fail.at(
                    &location,
                    format!(
                        "embed {key} must name an existing directory; {} is not one, so create it or fix the path in [embed]",
                        quoting::quote(&target)
                    ),
                ));
            }
            Err(error) => {
                return Err(fail.at(
                    &location,
                    format!("embed {key} target cannot be resolved: {error}; keep embedded directories inside the project root"),
                ));
            }
        }
    }
    Ok(())
}

pub(crate) fn valid_alias(key: &str) -> bool {
    let Some(rest) = key.strip_prefix('@') else {
        return false;
    };
    if rest.is_empty() {
        return false;
    }
    rest.chars()
        .enumerate()
        .all(|(i, c)| c.is_ascii_alphabetic() || c == '_' || (i > 0 && c.is_ascii_digit()))
}

/// The position of the byte `offset` in the manifest text.
fn locate(text: &str, file: &str, offset: usize) -> Location {
    let offset = offset.min(text.len());
    let before = &text[..offset];
    let line_start = before.rfind('\n').map_or(0, |i| i + 1);
    Location {
        file: file.to_string(),
        line: before.matches('\n').count() + 1,
        column: offset - line_start + 1,
        offset,
    }
}

/// A string value, or what shape the key wants.
fn text_value(
    fail: &Failure,
    location: &Location,
    key: &str,
    item: &toml_edit::Item,
) -> Result<String, ProjectError> {
    let Some(value) = item.as_str() else {
        return Err(fail.at(
            location,
            format!(
                "{key} must be a string; write {key} = \"{}\"",
                item.as_value().map_or(String::new(), |v| v
                    .to_string()
                    .trim()
                    .trim_matches('"')
                    .to_string())
            ),
        ));
    };
    if value.chars().any(|c| (c as u32) < 0x20 || c as u32 == 0x7f) {
        return Err(fail.at(
            location,
            format!("manifest value for {key} contains a NUL or control character; remove it"),
        ));
    }
    Ok(value.to_string())
}

/// What a manifest string list holds, for its errors and what it may contain.
struct ListKind {
    noun: &'static str,
    plural: &'static str,
    example: &'static str,
    /// Directory names may hold spaces; effect patterns may not.
    spaces: bool,
}

const EFFECT_LIST: ListKind = ListKind {
    noun: "effect",
    plural: "effects",
    example: "[\"std.net.*\", \"std.fs.read\"]",
    spaces: false,
};

const MEMBER_LIST: ListKind = ListKind {
    noun: "member",
    plural: "members",
    example: "[\"app\", \"libs/*\"]",
    spaces: true,
};

/// An array of strings, such as the effects `["std.net.*", "std.fs.read"]`.
fn string_list(item: &toml_edit::Item, kind: &ListKind) -> Result<Vec<String>, String> {
    let shape = format!("{} are a list of strings: {}", kind.plural, kind.example);
    let array = item.as_array().ok_or_else(|| shape.clone())?;
    let mut list = Vec::new();
    for entry in array {
        let text = entry.as_str().ok_or_else(|| shape.clone())?;
        let bad_char = |c: char| c.is_control() || (!kind.spaces && c.is_whitespace());
        if text.is_empty() || text.chars().any(bad_char) {
            return Err(format!(
                "invalid {} {text:?}; write one {} per string, such as {}",
                kind.noun,
                if kind.spaces { "directory" } else { "pattern" },
                kind.example
                    .trim_matches(['[', ']'])
                    .split(", ")
                    .next()
                    .unwrap_or("")
            ));
        }
        if list.iter().any(|seen| seen == text) {
            return Err(format!("{} {text} is listed twice; remove one", kind.noun));
        }
        list.push(text.to_string());
    }
    Ok(list)
}

fn check_package_name(fail: &Failure, key: &str, at: &Location) -> Result<(), ProjectError> {
    if valid_alias(key) && key != "@std" {
        return Ok(());
    }
    Err(fail.at(
        at,
        format!("invalid or reserved package name {key}; names look like @pg (start with @, letters/digits/underscore) and cannot be @std"),
    ))
}

/// Where a dependency comes from: a tag, a commit, or a semver requirement on the repository's tags.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    Tag(String),
    Sha(String),
    Version(Requirement),
}

/// One entry of `[dependencies]`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Dependency {
    pub url: String,
    pub source: Source,
}

impl Dependency {
    /// The `url#reference` a lock line records for a tag or a commit; a requirement has none
    /// until it is resolved to a tag.
    pub fn spec(&self) -> Option<String> {
        match &self.source {
            Source::Tag(r) | Source::Sha(r) => Some(format!("{}#{r}", self.url)),
            Source::Version(_) => None,
        }
    }

    /// The source as a person would write it: `v1.0.0`, a commit, or `^1.2`.
    pub fn describe(&self) -> String {
        match &self.source {
            Source::Tag(r) | Source::Sha(r) => r.clone(),
            Source::Version(r) => r.to_string(),
        }
    }
}

/// A dependency read from `[dependencies]`.
enum Declared {
    Git(Dependency),
    /// A path to another workspace member, as written.
    Path(String),
}

/// A dependency is a table with `url` and exactly one of `tag`, `sha` and `version`, or only
/// `path` (another workspace member).
fn dependency(item: &toml_edit::Item) -> Result<Declared, String> {
    let shape = "write { url = \"https://github.com/acme/pg.git\", version = \"1.0\" }, or tag = \"v1.0.0\" or sha = \"<40-digit commit>\" in place of version";
    let table = item
        .as_table_like()
        .ok_or_else(|| format!("a dependency is a table; {shape}"))?;
    let (mut url, mut tag, mut sha, mut version, mut path) = (None, None, None, None, None);
    for (field, value) in table.iter() {
        let text = value
            .as_str()
            .ok_or_else(|| format!("{field} must be a string; {shape}"))?;
        match field {
            "url" => url = Some(text),
            "tag" => tag = Some(text),
            "sha" => sha = Some(text),
            "version" => version = Some(text),
            "path" => path = Some(text),
            _ => {
                return Err(format!(
                    "unknown field {field}; a dependency has url and one of version, tag or sha, or only path"
                ));
            }
        }
    }
    if let Some(path) = path {
        if url.is_some() || tag.is_some() || sha.is_some() || version.is_some() || path.is_empty() {
            return Err("a path dependency has only path = \"../member\"".to_string());
        }
        return Ok(Declared::Path(path.to_string()));
    }
    let url = url.ok_or_else(|| format!("url is missing; {shape}"))?;
    let source = match (version, tag, sha) {
        (Some(version), None, None) => Source::Version(Requirement::parse(version)?),
        (None, Some(tag), None) => Source::Tag(tag.to_string()),
        (None, None, Some(sha)) => {
            if !crate::project::packages::is_hex(sha, 40) {
                return Err("sha must be the full 40-digit lowercase commit".to_string());
            }
            Source::Sha(sha.to_string())
        }
        _ => {
            return Err(format!("name exactly one of version, tag and sha; {shape}"));
        }
    };
    let found = Dependency {
        url: url.to_string(),
        source,
    };
    // A requirement has no tag to check yet; a url is checked the same way as a pinned spec.
    let reference = match &found.source {
        Source::Tag(r) | Source::Sha(r) => r.clone(),
        Source::Version(_) => "v0.0.0".to_string(),
    };
    crate::project::packages::check_spec(&format!("{url}#{reference}"))?;
    Ok(Declared::Git(found))
}
