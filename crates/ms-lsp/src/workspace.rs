//! Workspace-wide queries: the documents of a project, cross-file references
//! and workspace symbols.

use crate::analysis::{Analysis, Document, Documents, workspace_analysis};
use crate::index::Occurrence;
use crate::json::{Json, obj};
use crate::nav::{self, location_sort_key};
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
    crate::analysis::source_identity(path)
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
#[allow(clippy::too_many_arguments)]
pub fn workspace_references(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    index: &[Occurrence],
    d: &Document,
    docs: &Documents,
    p: Position,
    include: bool,
    cancel: Option<CancelCheck>,
) -> Vec<Json> {
    let session = &analysis.session;
    if canceled(cancel).is_err() {
        return Vec::new();
    }
    let Some(selected) = nav::occurrence_at(syms, analysis, d, p, index) else {
        return Vec::new();
    };
    let is_binding = selected.key.starts_with("binding:")
        && selected.info.as_ref().is_some_and(|i| i.binding.is_some());
    if is_binding {
        return nav::references_with_index(syms, analysis, index, d, p, include);
    }
    // A private module function (or constant) cannot be imported elsewhere.
    // Its complete set of uses is already in the selected checked graph.
    if selected
        .info
        .as_ref()
        .and_then(|info| info.symbol.as_ref())
        .is_some_and(|symbol| symbol.kind == ms_check::api::types::SymKind::Fn && !symbol.export)
    {
        let mut locations = nav::references_with_index(syms, analysis, index, d, p, include);
        locations.sort_by_cached_key(location_sort_key);
        return locations;
    }
    let documents = match workspace_documents(d, docs, false, cancel) {
        Ok(documents) => documents,
        Err(ScanError::Canceled) => return Vec::new(),
        Err(ScanError::Io(_)) => {
            let mut locations = nav::references_with_index(syms, analysis, index, d, p, include);
            locations.sort_by_cached_key(location_sort_key);
            return locations;
        }
    };
    let mut locations: Vec<Json> = Vec::new();
    let mut seen: HashSet<nav::LocationKey> = HashSet::new();
    for file in &documents {
        if canceled(cancel).is_err() {
            return Vec::new();
        }
        // A file that never spells the name cannot refer to it; skip the checker run.
        if file.uri != d.uri && !file.text.contains(selected.name.as_str()) {
            continue;
        }
        let checked = workspace_analysis(syms, session, file, docs);
        if canceled(cancel).is_err() {
            return Vec::new();
        }
        for entry in checked.occurrence_index(syms) {
            if canceled(cancel).is_err() {
                return Vec::new();
            }
            if entry.key != selected.key || (!include && entry.declaration) {
                continue;
            }
            let Some(location) = nav::occurrence_location(syms, &checked, entry) else {
                continue;
            };
            if seen.insert(location_sort_key(&location)) {
                locations.push(location);
            }
        }
    }
    locations.sort_by_cached_key(location_sort_key);
    locations
}

/// Declarations whose name contains `query` (case-insensitive), across the
/// open documents and the given workspace roots.
pub fn workspace_symbols(
    syms: ms_syntax::Names,
    session: &std::rc::Rc<ms_check::Session>,
    docs: &Documents,
    roots: &[String],
    query: &str,
    cancel: Option<CancelCheck>,
) -> Option<Vec<Json>> {
    let lowered = query.to_lowercase();
    workspace_symbols_matching(
        syms,
        session,
        docs,
        roots,
        &|name| name.to_lowercase().contains(&lowered),
        cancel,
    )
}

/// Share discovery and checked symbol identities with CLI fuzzy lookup, while
/// rejecting sources without matching identifiers before running the checker.
pub(crate) fn workspace_symbols_matching(
    syms: ms_syntax::Names,
    session: &std::rc::Rc<ms_check::Session>,
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
    let scanned: HashSet<String> = documents.iter().map(Document::path).collect();
    let mut analyzed: HashSet<String> = HashSet::new();
    let mut names = HashMap::new();
    let mut seen: HashSet<nav::LocationKey> = HashSet::new();
    let mut result: Vec<((i64, nav::LocationKey, String), Json)> = Vec::new();
    for d in &documents {
        if canceled(cancel).is_err() {
            return None;
        }
        if !analyzed.insert(d.uri.clone()) {
            continue;
        }
        if !may_contain_symbol(d, matches, &mut names, &scanned) {
            continue;
        }
        let checked = workspace_analysis(syms, session, d, docs);
        if canceled(cancel).is_err() {
            return None;
        }
        for entry in checked.project_occurrence_index(syms) {
            if canceled(cancel).is_err() {
                return None;
            }
            let Some(info) = &entry.info else { continue };
            if syms.str(entry.file).starts_with("@std/")
                || !entry.declaration
                || (info.symbol.is_none() && info.method.is_none())
                || !matches(&entry.name)
            {
                continue;
            }
            let Some(location) = nav::occurrence_location(syms, &checked, entry) else {
                continue;
            };
            let id = location_sort_key(&location);
            if !seen.insert(id.clone()) {
                continue;
            }
            let kind = match &info.symbol {
                Some(s) if s.kind == ms_check::api::types::SymKind::Type => {
                    if s.ty(syms).kind == ms_check::api::types::Kind::Alternative {
                        10
                    } else {
                        5
                    }
                }
                Some(s) if s.is_constant() => 14,
                _ => 12,
            };
            // Ordered by kind, location, then name.
            let order = (kind, id, entry.name.clone());
            result.push((
                order,
                obj([
                    ("name", entry.name.clone().into()),
                    ("kind", kind.into()),
                    ("location", location),
                ]),
            ));
        }
    }
    result.sort_by(|a, b| a.0.cmp(&b.0));
    Some(result.into_iter().map(|(_, v)| v).collect())
}

/// Whether the import string `text` (with its quotes) names a standard module or a relative file
/// of the scan, whose own declarations the scan reports without this file's help.
fn scanned_import(importer: &str, text: &str, scanned: &HashSet<String>) -> bool {
    if text.starts_with("\"@std/") || text.starts_with("'@std/") {
        return true;
    }
    let Some(inner) = text
        .strip_prefix('"')
        .and_then(|t| t.strip_suffix('"'))
        .filter(|t| !t.contains('\\'))
    else {
        return false;
    };
    (inner.starts_with("./") || inner.starts_with("../"))
        && scanned.contains(&pathops::join(&[&pathops::dir(importer), inner]))
}

/// This is only a conservative filter: imports and uses can also match. The
/// checker and occurrence index remain the authority for returned declarations.
/// If lexing fails, keep the file so loading/recovery behaves as before.
fn may_contain_symbol(
    d: &Document,
    matches: &dyn Fn(&str) -> bool,
    names: &mut HashMap<String, bool>,
    scanned: &HashSet<String>,
) -> bool {
    let file: Arc<str> = Arc::from(d.path());
    let Ok(lexed) = ms_syntax::lexer::lex(&file, &d.text) else {
        return true;
    };
    lexed.tokens.iter().enumerate().any(|(i, token)| {
        if token.kind == ms_syntax::token::Tok::Import {
            // An import can contribute declarations not written here. A standard module or a
            // relative file the scan already visits contributes none the scan would miss; any
            // other spelling (an alias, an escaped string, a file outside the scan) stays in.
            // A grouped import names several paths; every one must qualify.
            let mut paths = lexed.tokens[i + 1..]
                .iter()
                .take_while(|t| {
                    !matches!(
                        t.kind,
                        ms_syntax::token::Tok::Newline | ms_syntax::token::Tok::Eof
                    )
                })
                .filter(|t| t.kind == ms_syntax::token::Tok::String)
                .map(|path| &lexed.source[path.lo as usize..path.hi as usize])
                .peekable();
            let all_scanned =
                paths.peek().is_some() && paths.all(|text| scanned_import(&file, text, scanned));
            if !all_scanned {
                return true;
            }
        }
        if token.kind != ms_syntax::token::Tok::Name {
            return false;
        }
        // Only a name a declaration introduces can be a returned symbol; uses and fields of
        // the same spelling would send nearly every file of a large tree through the checker.
        let declares = i
            .checked_sub(1)
            .and_then(|i| lexed.tokens.get(i))
            .is_some_and(|before| {
                use ms_syntax::token::Tok;
                matches!(
                    before.kind,
                    Tok::Fn | Tok::Type | Tok::Enum | Tok::Interface | Tok::Var
                )
            })
            || lexed
                .tokens
                .get(i + 1)
                .is_some_and(|after| matches!(after.kind, ms_syntax::token::Tok::ColonAssign));
        if !declares {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn kept_in(text: &str, query: &str, scanned: &[&str]) -> bool {
        let document = Document::new(uri::file_uri("/tmp/a.ms"), text);
        may_contain_symbol(
            &document,
            &|name| name.eq_ignore_ascii_case(query),
            &mut HashMap::new(),
            &scanned.iter().map(|p| p.to_string()).collect(),
        )
    }

    fn kept(text: &str, query: &str) -> bool {
        kept_in(text, query, &[])
    }

    #[test]
    fn a_file_is_kept_only_for_a_name_it_declares_or_a_local_import() {
        let std_only = "import stdout from \"@std/io/io.ms\"\n\nfn helper() Int:\n    return 1\n";
        assert!(kept(std_only, "helper"));
        // Uses, imports and fields of the same spelling do not make a file a candidate.
        assert!(!kept(std_only, "stdout"));
        assert!(!kept(std_only, "missing"));
        // A local module can bring in declarations the scan has not seen.
        assert!(kept("import f from \"./other.ms\"\n", "missing"));
        assert!(kept(
            "import (\n    a,\n    b\n) from \"./other.ms\"\n",
            "missing"
        ));
    }

    #[test]
    fn an_import_of_a_scanned_file_adds_no_candidate() {
        let scanned = ["/tmp/other.ms", "/tmp/sub/deep.ms"];
        let text = "import f from \"./other.ms\"\nimport g from \"./sub/deep.ms\"\n";
        // The scan visits those files itself and reports their declarations once.
        assert!(!kept_in(text, "missing", &scanned));
        // A file the scan does not visit, an alias, or an escape keeps the importer in.
        assert!(kept_in(text, "missing", &["/tmp/other.ms"]));
        assert!(kept_in("import f from \"../x.ms\"\n", "missing", &scanned));
        assert!(kept_in(
            "import f from \"@lib/x.ms\"\n",
            "missing",
            &scanned
        ));
        // The importer's own declarations still count.
        assert!(kept_in(
            "import f from \"./other.ms\"\nfn helper() Int:\n    return 1\n",
            "helper",
            &scanned
        ));
    }
}
