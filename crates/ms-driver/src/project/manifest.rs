//! `ms.toml` reading: the supported subset is `[project]` and `[aliases]`
//! tables holding double-quoted string values, and `[imports]` holding arrays of them. Diagnostics, locations and their
//! order are pinned by the project tests.

use std::collections::{BTreeMap, BTreeSet};

use crate::project::error::{Location, ProjectError};
use crate::project::imports::ImportRule;
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
    /// The `[imports]` rules in manifest order.
    pub imports: Vec<ImportRule>,
    /// The `[project]` table header (or 1:1 when the table is absent).
    pub location: Location,
    pub assignments: BTreeMap<String, Assignment>,
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
    let error = read_into(filename, &mut project).err();
    (project, error)
}

struct Failure;

impl Failure {
    fn at(&self, location: &Location, message: impl Into<String>) -> ProjectError {
        ProjectError::manifest(location.clone(), ProjectError::msg(message))
    }
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
                "[imports]" => "imports",
                _ => {
                    let advice = if !line.ends_with(']') {
                        "close the header with ']'"
                    } else if line.starts_with("[[") {
                        "array tables are not supported"
                    } else if line == "[package]" {
                        "rename it to [project] with name, source, and entry"
                    } else if line == "[dependencies]" {
                        "there are no dependency tables, so copy the sources into the project and map them with [aliases]"
                    } else {
                        "ms.toml has no other tables"
                    };
                    return Err(fail.at(&location, format!("unsupported manifest table {line}; ms.toml supports only [project], [aliases], and [imports]: {advice}")));
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
        if section == "imports" {
            let id = format!("imports.{key}");
            if !seen.insert(id.clone()) {
                return Err(fail.at(
                    &key_location,
                    format!("duplicate manifest key {id}; each key may be set once"),
                ));
            }
            let allowed = import_list(value)
                .ok_or_else(|| fail.at(&location, format!("[imports] values are arrays of double-quoted patterns; write \"{key}\" = [\"src/**\", \"@std/json.ms\"]")))?;
            if key.is_empty()
                || key.starts_with('/')
                || key.contains('\\')
                || allowed
                    .iter()
                    .any(|a| a.is_empty() || a.starts_with('/') || a.contains('\\'))
            {
                return Err(fail.at(&key_location, format!("[imports] patterns are project-relative paths with / separators, such as \"src/**\" or \"@std/json.ms\"; fix \"{key}\"")));
            }
            p.assignments.insert(
                id,
                Assignment {
                    key: key_location.clone(),
                    value: location.clone(),
                },
            );
            p.imports.push(ImportRule {
                pattern: key,
                allowed,
                location: key_location,
            });
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
                _ => {
                    return Err(fail.at(
                        &key_location,
                        format!(
                            "unknown project key {key}; [project] accepts name, source, and entry"
                        ),
                    ));
                }
            }
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
    Ok(())
}

/// `["a", "b"]`: a one-line array of double-quoted strings, or `None` when malformed.
fn import_list(value: &str) -> Option<Vec<String>> {
    let inner = value.strip_prefix('[')?.strip_suffix(']')?.trim();
    let mut items = Vec::new();
    let mut rest = inner;
    while !rest.is_empty() {
        if !rest.starts_with('"') {
            return None;
        }
        let (quoted, after) = quoted_prefix(rest)?;
        items.push(quoting::unquote(quoted)?);
        rest = after.trim_start();
        match rest.strip_prefix(',') {
            Some(after) => rest = after.trim_start(),
            None if rest.is_empty() => {}
            None => return None,
        }
    }
    Some(items)
}

fn valid_alias(key: &str) -> bool {
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
