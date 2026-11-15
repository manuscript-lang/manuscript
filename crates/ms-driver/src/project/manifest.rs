//! `ms.toml` reading: the supported subset is `[project]`, `[aliases]` and
//! `[embed]` tables holding double-quoted string values. Diagnostics, locations and their
//! order are pinned by the project tests.

use std::collections::{BTreeMap, BTreeSet};

use crate::project::error::{Location, ProjectError};
use crate::project::overlay::Overlay;
use crate::project::pathops;
use crate::project::paths::source_path;
use crate::project::quoting;

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
    /// `[dependencies]`: package names mapped to `url#tag`.
    pub dependencies: BTreeMap<String, String>,
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

    let mut section = String::new();
    let mut tables: BTreeSet<&'static str> = BTreeSet::new();
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let (mut line_number, mut offset) = (0usize, 0usize);
    let mut location;
    while offset < configuration.len() {
        line_number += 1;
        let line_start_offset = offset;
        let newline = configuration[offset..].find('\n');
        let raw_end = newline.map_or(configuration.len(), |i| offset + i);
        if raw_end - offset > MAX_LINE {
            location = Location {
                file: file_name.clone(),
                line: line_number,
                column: 1,
                offset,
            };
            return Err(fail.at(
                &location,
                "line too long; keep each ms.toml line under 64 KiB",
            ));
        }
        let mut raw = &configuration[offset..raw_end];
        offset = newline.map_or(configuration.len(), |i| offset + i + 1);
        raw = raw.strip_suffix('\r').unwrap_or(raw);
        let mut line_start = line_start_offset;
        if line_number == 1
            && let Some(rest) = raw.strip_prefix('\u{feff}')
        {
            line_start += '\u{feff}'.len_utf8();
            raw = rest;
        }
        let content = manifest_line(raw);
        let mut line = content.trim();
        let leading = content.len() - content.trim_start().len();
        location = Location {
            file: file_name.clone(),
            line: line_number,
            column: leading + 1,
            offset: line_start + leading,
        };
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let header;
        if line.starts_with('[') {
            if line.ends_with(']') && !line.starts_with("[[") {
                header = format!("[{}]", line[1..line.len() - 1].trim());
                line = &header;
            }
            let table = match line {
                "[project]" => "project",
                "[aliases]" => "aliases",
                "[embed]" => "embed",
                "[dependencies]" => "dependencies",
                "[effects]" => "effects",
                _ => {
                    let advice = if !line.ends_with(']') {
                        "close the header with ']'"
                    } else if line.starts_with("[[") {
                        "array tables are not supported"
                    } else if line == "[package]" {
                        "rename it to [project] with name, source, and entry"
                    } else {
                        "ms.toml has no other tables"
                    };
                    return Err(fail.at(&location, format!("unsupported manifest table {line}; ms.toml supports only [project], [aliases], [embed], [dependencies] and [effects]: {advice}")));
                }
            };
            if !tables.insert(table) {
                return Err(fail.at(
                    &location,
                    format!("duplicate manifest table {line}; merge its keys into the first one"),
                ));
            }
            section = table.to_string();
            if table == "project" {
                p.location = location.clone();
            }
            continue;
        }
        let (key, value, ok);
        if line.starts_with('"') {
            let Some((quoted, rest)) = quoted_prefix(line) else {
                return Err(fail.at(&location, "unterminated quoted key; close the key's double quote, e.g. \"name\" = \"value\""));
            };
            let Some(unquoted) = quoting::unquote(quoted) else {
                return Err(fail.at(
                    &location,
                    format!("invalid quoted key {quoted}: invalid syntax; escape backslashes and quotes inside the key"),
                ));
            };
            key = unquoted;
            match rest.trim().strip_prefix('=') {
                Some(v) => (value, ok) = (v, true),
                None => (value, ok) = ("", false),
            }
        } else {
            match line.split_once('=') {
                Some((k, v)) => (key, value, ok) = (k.trim().to_string(), v, true),
                None => (key, value, ok) = (String::new(), "", false),
            }
        }
        if !ok || section.is_empty() {
            let advice = if section.is_empty() {
                "this line is before any table header, so start the file with [project] and put name = \"app\" and source = \"src\" under it"
            } else {
                "this line has no '=', so write key = \"value\" (values are double-quoted strings)"
            };
            return Err(fail.at(&location, format!("invalid manifest assignment; {advice}")));
        }
        let key_location = location.clone();
        let value = value.trim();
        let value_start = line.len() - value.len();
        location.column += value_start;
        location.offset += value_start;
        if section == "effects" || (section == "project" && key == "effects") {
            let mut text = value.to_string();
            if !text.starts_with('[') {
                return Err(fail.at(
                    &location,
                    format!("effects are a list of strings; write {key} = [\"std.net.*\", \"std.fs.read\"]"),
                ));
            }
            while !array_closed(&text) {
                if offset >= configuration.len() {
                    return Err(fail.at(&location, "unterminated effects list; close it with ']'"));
                }
                let end = configuration[offset..]
                    .find('\n')
                    .map_or(configuration.len(), |i| offset + i);
                let more = configuration[offset..end]
                    .strip_suffix('\r')
                    .unwrap_or(&configuration[offset..end]);
                text.push(' ');
                text.push_str(manifest_line(more).trim());
                offset = (end + 1).min(configuration.len());
                line_number += 1;
            }
            let list = parse_list(&text).map_err(|e| fail.at(&location, e))?;
            let id = format!("{section}.{key}");
            if !seen.insert(id.clone()) {
                return Err(fail.at(
                    &key_location,
                    format!("duplicate manifest key {id}; each key may be set once"),
                ));
            }
            p.assignments.insert(
                id,
                Assignment {
                    key: key_location.clone(),
                    value: location.clone(),
                },
            );
            if section == "project" {
                p.effects = list;
            } else {
                if !valid_alias(&key) || key == "@std" {
                    return Err(fail.at(
                        &key_location,
                        format!("invalid or reserved package name {key}; names look like @pg (start with @, letters/digits/underscore) and cannot be @std"),
                    ));
                }
                p.allowed_effects.insert(key, list);
            }
            continue;
        }
        if value.len() < 2 || !value.starts_with('"') || !value.ends_with('"') {
            return Err(fail.at(
                &location,
                format!(
                    "manifest values must be double-quoted strings; write {} = \"{}\"",
                    key.trim(),
                    value.trim_matches(['"', '\'', ' '])
                ),
            ));
        }
        let Some(value) = quoting::unquote(value) else {
            return Err(fail.at(
                &location,
                "manifest values must be quoted strings: invalid syntax; escape backslashes and quotes inside the value",
            ));
        };
        if value.chars().any(|c| (c as u32) < 0x20 || c as u32 == 0x7f) {
            return Err(fail.at(
                &location,
                format!("manifest value for {key} contains a NUL or control character; remove it"),
            ));
        }
        let id = format!("{section}.{key}");
        if !seen.insert(id.clone()) {
            return Err(fail.at(
                &key_location,
                format!("duplicate manifest key {id}; each key may be set once"),
            ));
        }
        p.assignments.insert(
            id,
            Assignment {
                key: key_location.clone(),
                value: location.clone(),
            },
        );
        if section == "project" {
            match key.as_str() {
                "name" => p.name = value,
                "source" => p.source = value,
                "entry" => p.entry = value,
                "effects" => unreachable!("handled above"),
                _ => {
                    return Err(fail.at(
                        &key_location,
                        format!(
                            "unknown project key {key}; [project] accepts name, source, entry, and effects"
                        ),
                    ));
                }
            }
        } else if section == "dependencies" || section == "effects" {
            if !valid_alias(&key) || key == "@std" {
                return Err(fail.at(
                    &key_location,
                    format!("invalid or reserved package name {key}; names look like @pg (start with @, letters/digits/underscore) and cannot be @std"),
                ));
            }
            {
                match value.split_once('#') {
                    Some((url, tag))
                        if !url.is_empty()
                            && !tag.is_empty()
                            && !value.contains(char::is_whitespace) => {}
                    _ => {
                        return Err(fail.at(
                            &location,
                            format!("invalid dependency {value:?}; write \"<git url>#<tag or commit>\", for example \"https://github.com/acme/pg.git#v1.0.0\""),
                        ));
                    }
                }
                p.dependencies.insert(key, value);
            }
        } else if section == "embed" {
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
        } else {
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
    location = p.location.clone();
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
    for key in p.dependencies.keys() {
        if p.aliases.contains_key(key) || p.embed.contains_key(key) {
            return Err(fail.at(
                &p.assignments[&format!("dependencies.{key}")].key.clone(),
                format!("{key} is declared in [dependencies] and also as an alias or embed; rename one so an import names a single thing"),
            ));
        }
    }
    for key in p.allowed_effects.keys() {
        if !p.dependencies.contains_key(key) {
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

/// Strip a `#` comment that is not inside a double-quoted string.
fn manifest_line(line: &str) -> &str {
    let (mut quoted, mut escaped) = (false, false);
    for (i, c) in line.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if quoted && c == '\\' {
            escaped = true;
            continue;
        }
        if c == '"' {
            quoted = !quoted;
        }
        if c == '#' && !quoted {
            return &line[..i];
        }
    }
    line
}

/// Whether the `[` that starts `text` has its closing `]` outside the strings.
fn array_closed(text: &str) -> bool {
    let (mut quoted, mut escaped) = (false, false);
    for c in text.chars() {
        if escaped {
            escaped = false;
        } else if quoted && c == '\\' {
            escaped = true;
        } else if c == '"' {
            quoted = !quoted;
        } else if c == ']' && !quoted {
            return true;
        }
    }
    false
}

/// The strings of `["a", "b"]`: double-quoted, comma-separated, a trailing comma allowed.
fn parse_list(text: &str) -> Result<Vec<String>, String> {
    let bad = "an effects list is [\"std.net.*\", \"std.fs.read\"]: double-quoted strings separated by commas";
    let inner = text
        .trim()
        .strip_prefix('[')
        .and_then(|t| t.strip_suffix(']'))
        .ok_or_else(|| format!("invalid list; {bad}"))?;
    let mut rest = inner.trim();
    let mut items = Vec::new();
    while !rest.is_empty() {
        let (quoted, after) = quoted_prefix(rest).ok_or_else(|| format!("invalid list; {bad}"))?;
        let item = quoting::unquote(quoted)
            .ok_or_else(|| format!("invalid string {quoted} in the list; {bad}"))?;
        if item.is_empty() || item.chars().any(|c| c.is_whitespace() || c.is_control()) {
            return Err(format!(
                "invalid effect {item:?}; write one pattern per string, such as \"std.net.*\""
            ));
        }
        if items.contains(&item) {
            return Err(format!("effect {item} is listed twice; remove one"));
        }
        items.push(item);
        rest = after.trim();
        match rest.strip_prefix(',') {
            Some(more) => rest = more.trim(),
            None if rest.is_empty() => {}
            None => return Err(format!("invalid list; {bad}")),
        }
    }
    Ok(items)
}

/// Split a leading double-quoted string, honoring backslash escapes.
fn quoted_prefix(line: &str) -> Option<(&str, &str)> {
    let bytes = line.as_bytes();
    let mut i = 1;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' => i += 1,
            b'"' => return Some((&line[..=i], &line[i + 1..])),
            _ => {}
        }
        i += 1;
    }
    None
}
