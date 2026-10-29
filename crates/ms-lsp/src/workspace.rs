//! Workspace-wide queries: the documents of a project, cross-file references
//! and workspace symbols.

use crate::analysis::{Analysis, Document, Documents, workspace_analysis};
use crate::index::Occurrence;
use crate::json::{Json, obj};
use crate::nav::{self, go_location_order};
use crate::text::Position;
use crate::uri;
use ms_driver::project::pathops;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

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
    let mut root = pathops::dir(&path);
    let mut recursive = recursive;
    if let Some(manifest) = ms_driver::project::find_manifest(&path) {
        root = pathops::dir(&manifest);
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

/// A file's identity: its path with symlinks resolved, so an open buffer and
/// the file it is a link to are one document.
fn identity(path: &str) -> String {
    pathops::eval_symlinks(path).unwrap_or_else(|_| path.to_string())
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
        if let Ok(relative) = pathops::rel(&root, &name)
            && relative != ".."
            && !relative.starts_with("../")
        {
            files.insert(identity(&name), open.clone());
        }
    }
    files.insert(identity(&path), d.clone());
    match walk(Path::new(&root), nested, &mut files, cancel) {
        Ok(()) => {}
        Err(ScanError::Io(e)) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    let mut result: Vec<Document> = files.into_values().collect();
    result.sort_by(|a, b| a.uri.cmp(&b.uri));
    Ok(result)
}

fn walk(
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
            walk(&path, nested, files, cancel)?;
            continue;
        }
        let text_path = path.to_string_lossy().into_owned();
        if kind.is_symlink()
            || !text_path.ends_with(".ms")
            || files.contains_key(&identity(&text_path))
        {
            continue;
        }
        let data = std::fs::read(&path).map_err(ScanError::Io)?;
        files.insert(
            identity(&text_path),
            Document::new(uri::file_uri(&text_path), String::from_utf8_lossy(&data)),
        );
    }
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
    // A private module function (or constant) cannot be imported elsewhere.
    // Its complete set of uses is already in the selected checked graph.
    if selected
        .info
        .as_ref()
        .and_then(|info| info.symbol.as_ref())
        .is_some_and(|symbol| symbol.kind == ms_check::types::SymKind::Fn && !symbol.export)
    {
        let mut locations = nav::references_with_index(analysis, index, d, p, include);
        locations.sort_by_cached_key(go_location_order);
        return locations;
    }
    let documents = match workspace_documents(d, docs, false, cancel) {
        Ok(documents) => documents,
        Err(ScanError::Canceled) => return Vec::new(),
        Err(ScanError::Io(_)) => {
            let mut locations = nav::references_with_index(analysis, index, d, p, include);
            locations.sort_by_cached_key(go_location_order);
            return locations;
        }
    };
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
        for entry in checked.index() {
            if canceled(cancel).is_err() {
                return Vec::new();
            }
            if entry.key != selected.key || (!include && entry.declaration) {
                continue;
            }
            let Some(location) = nav::occurrence_location(&checked, entry) else {
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
    let lowered = query.to_lowercase();
    workspace_symbols_matching(
        docs,
        roots,
        &|name| name.to_lowercase().contains(&lowered),
        cancel,
    )
}

/// Share discovery and checked symbol identities with CLI fuzzy lookup, while
/// rejecting sources without matching identifiers before running the checker.
pub(crate) fn workspace_symbols_matching(
    docs: &Documents,
    roots: &[String],
    matches: &dyn Fn(&str) -> bool,
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
            uri::file_uri(&pathops::join(&[root, "__workspace_index.ms"])),
            "",
        );
        match discover(&dummy, true) {
            Ok(files) => documents.extend(files.into_iter().filter(|f| f.uri != dummy.uri)),
            Err(ScanError::Canceled) => return None,
            Err(ScanError::Io(_)) => {}
        }
    }
    let mut analyzed: HashSet<String> = HashSet::new();
    let mut names = HashMap::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut result: Vec<(String, Json)> = Vec::new();
    for d in &documents {
        if canceled(cancel).is_err() {
            return None;
        }
        if !analyzed.insert(d.uri.clone()) {
            continue;
        }
        if !may_contain_symbol(d, matches, &mut names) {
            continue;
        }
        let checked = workspace_analysis(d, docs);
        if canceled(cancel).is_err() {
            return None;
        }
        for entry in checked.index() {
            if canceled(cancel).is_err() {
                return None;
            }
            let Some(info) = &entry.info else { continue };
            if entry.file.as_str().starts_with("@std/")
                || !entry.declaration
                || (info.symbol.is_none() && info.method.is_none())
                || !matches(&entry.name)
            {
                continue;
            }
            let Some(location) = nav::occurrence_location(&checked, entry) else {
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

/// This is only a conservative filter: imports and uses can also match. The
/// checker and occurrence index remain the authority for returned declarations.
/// If lexing fails, keep the file so loading/recovery behaves as before.
fn may_contain_symbol(
    d: &Document,
    matches: &dyn Fn(&str) -> bool,
    names: &mut HashMap<String, bool>,
) -> bool {
    let file: Arc<str> = Arc::from(d.path());
    let Ok(lexed) = ms_syntax::lexer::lex(&file, &d.text) else {
        return true;
    };
    lexed.tokens.iter().enumerate().any(|(i, token)| {
        if token.kind == ms_syntax::token::Tok::Import {
            // Local imports can contribute declarations not written here,
            // including modules outside discovery's scan scope. Only the
            // ordinary, unescaped standard path spelling proves otherwise;
            // unusual strings or malformed imports conservatively stay in.
            let standard = i
                .checked_sub(1)
                .and_then(|i| lexed.tokens.get(i))
                .is_some_and(|path| {
                    let text = &lexed.source[path.lo as usize..path.hi as usize];
                    path.kind == ms_syntax::token::Tok::String
                        && (text.starts_with("\"@std/") || text.starts_with("'@std/"))
                });
            if !standard {
                return true;
            }
        }
        if token.kind != ms_syntax::token::Tok::Name {
            return false;
        }
        let name = &lexed.source[token.lo as usize..token.hi as usize];
        if let Some(found) = names.get(name) {
            return *found;
        }
        let found = matches(name);
        names.insert(name.to_string(), found);
        found
    })
}
