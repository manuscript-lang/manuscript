//! Workspace-wide queries: the documents of a project, cross-file references
//! and workspace symbols.

use crate::analysis::{Analysis, Document, Documents, workspace_analysis};
use crate::index::{Occurrence, source_index};
use crate::json::{Json, obj};
use crate::nav::{self, go_location_order};
use crate::text::Position;
use crate::uri;
use ms_project::gopath;
use std::collections::{BTreeMap, HashSet};
use std::path::Path;

/// A request the client canceled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Canceled;

/// Polls cancellation of the request being answered.
pub type CancelCheck<'a> = &'a dyn Fn() -> bool;

fn canceled(check: Option<CancelCheck>) -> Result<(), Canceled> {
    match check {
        Some(f) if f() => Err(Canceled),
        _ => Ok(()),
    }
}

/// The directory a document's workspace scan covers, and whether to descend.
pub fn workspace_scope(d: &Document, recursive: bool) -> (String, bool) {
    let path = d.path();
    let mut root = gopath::dir(&path);
    let mut recursive = recursive;
    if let Some(manifest) = ms_project::find_manifest(&path) {
        root = gopath::dir(&manifest);
        recursive = true;
    }
    (root, recursive)
}

/// Why a scan stopped: cancellation, or a filesystem failure.
#[derive(Debug)]
pub enum ScanError {
    /// The client canceled the request.
    Canceled,
    /// A directory or file could not be read.
    Io(std::io::Error),
}

impl From<Canceled> for ScanError {
    fn from(_: Canceled) -> ScanError {
        ScanError::Canceled
    }
}

/// The open and on-disk `.ms` documents under a document's project (or its
/// directory), sorted by URI.
pub fn workspace_documents(
    d: &Document,
    docs: &Documents,
    recursive: bool,
    cancel: Option<CancelCheck>,
) -> Result<Vec<Document>, ScanError> {
    canceled(cancel)?;
    let path = d.path();
    let (root, nested) = workspace_scope(d, recursive);
    let mut files: BTreeMap<String, Document> = BTreeMap::new();
    for open in docs.values() {
        canceled(cancel)?;
        let name = open.path();
        if let Ok(relative) = gopath::rel(&root, &name)
            && relative != ".."
            && !relative.starts_with("../")
        {
            files.insert(name, open.clone());
        }
    }
    files.insert(path, d.clone());
    match walk(
        Path::new(&root),
        Path::new(&root),
        nested,
        &mut files,
        cancel,
    ) {
        Ok(()) => {}
        Err(ScanError::Io(e)) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    let mut result: Vec<Document> = files.into_values().collect();
    result.sort_by(|a, b| a.uri.cmp(&b.uri));
    Ok(result)
}

fn walk(
    root: &Path,
    dir: &Path,
    nested: bool,
    files: &mut BTreeMap<String, Document>,
    cancel: Option<CancelCheck>,
) -> Result<(), ScanError> {
    canceled(cancel)?;
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .map_err(ScanError::Io)?
        .collect::<Result<_, _>>()
        .map_err(ScanError::Io)?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        canceled(cancel)?;
        let path = entry.path();
        let kind = entry.file_type().map_err(ScanError::Io)?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if kind.is_dir() {
            if !nested || name.starts_with('.') || name == "node_modules" || name == "vendor" {
                continue;
            }
            walk(root, &path, nested, files, cancel)?;
            continue;
        }
        let text_path = path.to_string_lossy().into_owned();
        if kind.is_symlink() || !text_path.ends_with(".ms") || files.contains_key(&text_path) {
            continue;
        }
        let data = std::fs::read(&path).map_err(ScanError::Io)?;
        files.insert(
            text_path.clone(),
            Document::new(uri::file_uri(&text_path), String::from_utf8_lossy(&data)),
        );
    }
    let _ = root;
    Ok(())
}

/// References to the identity at a position across the project.
pub fn workspace_references(
    analysis: &Analysis,
    index: &[Occurrence],
    d: &Document,
    docs: &Documents,
    p: Position,
    include: bool,
    cancel: Option<CancelCheck>,
) -> Vec<Json> {
    if canceled(cancel).is_err() {
        return Vec::new();
    }
    let Some(selected) = nav::occurrence_at(analysis, d, p, index) else {
        return Vec::new();
    };
    let is_binding = selected.key.starts_with("binding:")
        && selected.info.as_ref().is_some_and(|i| i.binding.is_some());
    if is_binding {
        return nav::references_with_index(analysis, index, d, p, include);
    }
    let documents = match workspace_documents(d, docs, false, cancel) {
        Ok(documents) => documents,
        Err(ScanError::Canceled) => return Vec::new(),
        Err(ScanError::Io(_)) => {
            return nav::references_with_index(analysis, index, d, p, include);
        }
    };
    let selected_key = selected.key.clone();
    let mut locations: Vec<Json> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for file in &documents {
        if canceled(cancel).is_err() {
            return Vec::new();
        }
        let checked = workspace_analysis(file, docs);
        if canceled(cancel).is_err() {
            return Vec::new();
        }
        for entry in source_index(&checked) {
            if canceled(cancel).is_err() {
                return Vec::new();
            }
            if entry.key != selected_key || (!include && entry.declaration) {
                continue;
            }
            let Some(location) = nav::occurrence_location(&checked, &entry) else {
                continue;
            };
            if seen.insert(go_location_order(&location)) {
                locations.push(location);
            }
        }
    }
    locations.sort_by_cached_key(go_location_order);
    locations
}

/// Declarations whose name contains `query` (case-insensitive), across the
/// open documents and the given workspace roots.
pub fn workspace_symbols(
    docs: &Documents,
    roots: &[String],
    query: &str,
    cancel: Option<CancelCheck>,
) -> Option<Vec<Json>> {
    let mut documents: Vec<Document> = Vec::new();
    let mut walked: HashSet<(String, bool)> = HashSet::new();
    let mut discover = |d: &Document, recursive: bool| -> Result<Vec<Document>, ScanError> {
        let (root, nested) = workspace_scope(d, recursive);
        if !walked.insert((root, nested)) {
            return Ok(Vec::new());
        }
        workspace_documents(d, docs, recursive, cancel)
    };
    let mut open: Vec<&Document> = docs.values().collect();
    open.sort_by(|a, b| a.uri.cmp(&b.uri));
    for d in open {
        if canceled(cancel).is_err() {
            return None;
        }
        match discover(d, false) {
            Ok(files) => documents.extend(files),
            Err(ScanError::Canceled) => return None,
            Err(ScanError::Io(_)) => {}
        }
    }
    for root in roots {
        if canceled(cancel).is_err() {
            return None;
        }
        let dummy = Document::new(
            uri::file_uri(&gopath::join(&[root, "__workspace_index.ms"])),
            "",
        );
        match discover(&dummy, true) {
            Ok(files) => documents.extend(files.into_iter().filter(|f| f.uri != dummy.uri)),
            Err(ScanError::Canceled) => return None,
            Err(ScanError::Io(_)) => {}
        }
    }
    let lowered = query.to_lowercase();
    let mut analyzed: HashSet<String> = HashSet::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut result: Vec<(String, Json)> = Vec::new();
    for d in &documents {
        if canceled(cancel).is_err() {
            return None;
        }
        if !analyzed.insert(d.uri.clone()) {
            continue;
        }
        let checked = workspace_analysis(d, docs);
        if canceled(cancel).is_err() {
            return None;
        }
        for entry in source_index(&checked) {
            if canceled(cancel).is_err() {
                return None;
            }
            let Some(info) = &entry.info else { continue };
            if entry.file.as_str().starts_with("@std/")
                || !entry.declaration
                || (info.symbol.is_none() && info.method.is_none())
                || !entry.name.to_lowercase().contains(&lowered)
            {
                continue;
            }
            let Some(location) = nav::occurrence_location(&checked, &entry) else {
                continue;
            };
            let id = go_location_order(&location);
            if !seen.insert(id.clone()) {
                continue;
            }
            let kind = match &info.symbol {
                Some(s) if s.kind == ms_check::types::SymKind::Type => 5,
                Some(s) if s.is_constant() => 14,
                _ => 12,
            };
            // Go orders by the printed map: kind, location, name.
            let order = format!("map[kind:{kind} location:{} name:{}]", id, entry.name);
            result.push((
                order,
                obj([
                    ("name", entry.name.clone().into()),
                    ("kind", (kind as i64).into()),
                    ("location", location),
                ]),
            ));
        }
    }
    result.sort_by(|a, b| a.0.cmp(&b.0));
    Some(result.into_iter().map(|(_, v)| v).collect())
}
