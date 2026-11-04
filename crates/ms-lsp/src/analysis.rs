//! Checked documents: loading a document with its unsaved neighbours, running
//! the checker, and finding the module a document is.

use crate::index::Occurrence;
use crate::lint::LintFinding;
use crate::uri;
use ms_check::syntax::ModRef;
use ms_check::{Program, Session};
use ms_driver::project::Overlay;
use ms_driver::{CheckRequest, EditorOptions, Graph, LoadOptions};
use ms_syntax::{Diagnostic, Phase};
use std::cell::OnceCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

/// An open (or queried) document.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Document {
    /// Document URI.
    pub uri: String,
    /// Full text.
    pub text: String,
    /// Client version.
    pub version: i64,
}

impl Document {
    /// A document with version 0.
    pub fn new(uri: impl Into<String>, text: impl Into<String>) -> Document {
        Document {
            uri: uri.into(),
            text: text.into(),
            version: 0,
        }
    }

    /// The file path the URI names.
    pub fn path(&self) -> String {
        uri::filename(&self.uri)
    }
}

/// Open documents by URI.
pub type Documents = HashMap<String, Document>;

/// What one analysis needs beyond the document (`compiler.Options`).
#[derive(Clone, Default)]
pub struct Options {
    /// Select a module of a project as the entry (the document's own file).
    pub module: Option<String>,
    /// Capture the lexical scope at names spelled like this.
    pub scope_marker: Option<String>,
    /// Check every project source and test module, imported or not.
    pub project_sources: bool,
    /// Recover from syntax errors (always on for editing queries).
    pub recover: bool,
    /// Unsaved sources by absolute path.
    pub overlay: Overlay,
    /// The session to check against; absent, each analysis loads its own standard library.
    pub session: Option<Rc<Session>>,
}

/// A checked program with its diagnostics (`compiler.Result`).
#[derive(Default)]
pub struct Analysis {
    /// The directory logical module names are relative to.
    pub source_root: String,
    /// The project directory; empty for a standalone file.
    pub project_root: String,
    /// The program, absent when loading failed before checking.
    pub program: Option<Program>,
    /// The session the analysis ran in; standard declarations are read through it.
    pub session: Rc<Session>,
    /// Loading, parse and checker diagnostics in report order.
    pub diagnostics: Vec<Diagnostic>,
    pub(crate) index: OnceCell<Vec<Occurrence>>,
    pub(crate) lints: OnceCell<Vec<LintFinding>>,
}

impl Analysis {
    /// The occurrence index, built once per analysis; empty without a program.
    pub fn occurrence_index(&self, syms: ms_syntax::Names) -> &[Occurrence] {
        if self.program.is_none() {
            return &[];
        }
        self.index
            .get_or_init(|| crate::index::source_index(syms, self))
    }

    /// Program lint findings, computed once per analysis.
    pub fn lints(&self, lint: &dyn crate::lint::Lint) -> &[LintFinding] {
        let Some(program) = &self.program else {
            return &[];
        };
        self.lints.get_or_init(|| lint.program(program))
    }

    /// Whether no diagnostic was reported.
    pub fn success(&self) -> bool {
        self.diagnostics.is_empty()
    }

    /// Whether the program resolves completely: no diagnostic, or only unread
    /// local bindings, which are style errors that leave every name resolved.
    pub fn resolves(&self) -> bool {
        self.diagnostics
            .iter()
            .all(|d| d.subcode() == Some("MS3000.1"))
    }

    /// The directory a module's logical path is relative to.
    fn root(&self) -> &str {
        if self.project_root.is_empty() {
            &self.source_root
        } else {
            &self.project_root
        }
    }

    /// The absolute path of a logical module file.
    pub fn module_path(&self, file: &str) -> String {
        if ms_driver::project::pathops::is_abs(file) {
            return file.to_string();
        }
        ms_driver::project::pathops::join(&[self.root(), file])
    }

    /// The URI of a module's source.
    pub fn source_uri(&self, file: &str) -> String {
        if file.starts_with("@std/") {
            uri::standard_library_uri(file)
        } else {
            uri::file_uri(&self.module_path(file))
        }
    }

    /// Project modules followed by every bundled standard module. Standard
    /// declarations are immutable virtual documents from the compiler that
    /// checked this workspace, so navigation cannot drift to another version.
    pub fn source_modules(&self, syms: ms_syntax::Names) -> Vec<ModRef> {
        let Some(program) = &self.program else {
            return Vec::new();
        };
        let mut modules: Vec<ModRef> = program
            .modules
            .iter()
            .filter(|m| !syms.str(m.file).starts_with("@std/"))
            .cloned()
            .collect();
        modules.extend(self.session.standard_modules());
        modules
    }

    /// The module whose source a document is, if the program contains it.
    pub fn module(&self, syms: ms_syntax::Names, d: &Document) -> Option<ModRef> {
        let program = self.program.as_ref()?;
        if let Some(m) = standard_library_document(syms, &self.session, d) {
            return Some(m);
        }
        let mut path = d.path();
        if let Ok(canonical) = ms_driver::project::pathops::eval_symlinks(&path) {
            path = canonical;
        }
        program
            .modules
            .iter()
            .find(|m| syms.str(m.file) == path || self.module_path(syms.str(m.file)) == path)
            .cloned()
    }

    /// The logical file of a document's module, or empty.
    pub fn module_file(&self, syms: ms_syntax::Names, d: &Document) -> String {
        self.module(syms, d)
            .map(|m| syms.str(m.file).to_string())
            .unwrap_or_default()
    }
}

/// The bundled module a document stands for: a `manuscript-stdlib:` URI, or a
/// file that is byte-for-byte a bundled declaration file.
pub fn standard_library_document(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    d: &Document,
) -> Option<ModRef> {
    if uri::is_standard_library(&d.uri) {
        return standard_library_module(syms, session, &d.uri).ok();
    }
    let url = uri::parse(&d.uri)?;
    if url.scheme != "file" || url.query || url.fragment {
        return None;
    }
    let base = ms_driver::project::pathops::base(&d.path());
    session.standard_modules().into_iter().find(|m| {
        syms.str(m.file).strip_prefix("@std/") == Some(base.as_str()) && *m.source == *d.text
    })
}

/// The bundled module a `manuscript-stdlib:` URI names.
pub fn standard_library_module(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    uri: &str,
) -> Result<ModRef, &'static str> {
    let path = uri::standard_library_path(uri)?;
    session
        .standard_modules()
        .into_iter()
        .find(|m| {
            syms.str(m.file)
                .strip_prefix("@std/")
                .is_some_and(|rest| path == format!("/{rest}"))
        })
        .ok_or("unknown standard-library module")
}

/// The source of a bundled module by URI.
pub fn standard_library_source(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    uri: &str,
) -> Result<String, &'static str> {
    standard_library_module(syms, session, uri).map(|m| m.source.to_string())
}

/// Checks a file or manifest with unsaved sources (`compiler.CompileFile`).
pub fn compile_file(syms: ms_syntax::Names, filename: &str, options: &Options) -> Analysis {
    let editor = EditorOptions {
        recover: options.recover,
        module: options.module.clone(),
        project_sources: options.project_sources,
        overlay: options.overlay.clone(),
    };
    let graph = ms_driver::load_editor_file(syms, filename, LoadOptions::default(), &editor);
    check(syms, graph, options)
}

/// Checks in-memory source without filesystem resolution (`compiler.CompileSource`).
pub fn compile_source(
    syms: ms_syntax::Names,
    filename: &str,
    source: &str,
    options: &Options,
) -> Analysis {
    let file: Arc<str> = Arc::from(filename);
    let mut graph = Graph {
        entry: filename.to_string(),
        ..Graph::default()
    };
    let parsed = if options.recover {
        let (module, issues) = ms_syntax::parse_partial(&file, source);
        graph.diagnostics.extend(issues);
        Some(module)
    } else {
        match ms_syntax::parser::parse(&file, source) {
            Ok(module) => Some(module),
            Err(issue) => {
                graph.diagnostics.push(*issue);
                None
            }
        }
    };
    if let Some(module) = parsed {
        let mut usable = true;
        for item in &module.imports {
            if item.path.starts_with("@std/") {
                continue;
            }
            graph.diagnostics.push(Diagnostic {
                opener_line: 0,
                file: file.clone(),
                pos: item.pos,
                phase: Phase::Resolution,
                message: "local imports require CompileFile".to_string(),
                end: None,
                fix: None,
            });
            usable &= options.recover;
        }
        if usable {
            graph.modules.push(ms_check::load_module(syms, &module));
        }
    }
    check(syms, graph, options)
}

fn check(syms: ms_syntax::Names, graph: Graph, options: &Options) -> Analysis {
    let session = options.session.clone().unwrap_or_default();
    let checked = ms_driver::check_graph_in(
        syms,
        &session,
        graph,
        CheckRequest::default(),
        options.scope_marker.as_deref(),
    );
    Analysis {
        source_root: checked.source_root,
        project_root: checked.project_root,
        program: checked.program,
        diagnostics: checked.diagnostics,
        session,
        ..Analysis::default()
    }
}

/// The empty program used for standard-library documents, whose signatures the
/// compiler already checked at startup.
fn library_analysis(session: Rc<Session>) -> Analysis {
    Analysis {
        program: Some(Program {
            session: session.clone(),
            ..Program::default()
        }),
        session,
        ..Analysis::default()
    }
}

/// Selection and overlay validation shared by uncached and cached analysis.
pub fn analyze_with(
    syms: ms_syntax::Names,
    d: &Document,
    docs: &Documents,
    mut options: Options,
    compile: &mut dyn FnMut(&str, &Options) -> Rc<Analysis>,
) -> Rc<Analysis> {
    let session = options.session.clone().unwrap_or_default();
    options.session = Some(session.clone());
    if standard_library_document(syms, &session, d).is_some() {
        return Rc::new(library_analysis(session));
    }
    if uri::is_standard_library(&d.uri) {
        return Rc::new(Analysis {
            session,
            ..Analysis::default()
        });
    }
    let path = d.path();
    let mut overlay = Overlay::new();
    for open in docs.values() {
        if uri::is_standard_library(&open.uri)
            || standard_library_document(syms, &session, open).is_some()
        {
            continue;
        }
        overlay.insert(open.path(), open.text.clone());
    }
    overlay.insert(path.clone(), d.text.clone());
    options.overlay = overlay;
    let target = ms_driver::project::find_manifest(&path).unwrap_or_else(|| path.clone());
    if options.scope_marker.is_some() && target != path {
        options.module = Some(path.clone());
    }
    let result = compile(&target, &options);
    if result.program.is_none() && result.source_root.is_empty() && target == path {
        return Rc::new(compile_source(syms, &path, &d.text, &options));
    }
    if target != path && result.program.is_some() && result.module(syms, d).is_none() {
        options.module = Some(path);
        return compile(&target, &options);
    }
    result
}

/// An uncached analysis of one document.
pub fn analyze(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    d: &Document,
    docs: &Documents,
) -> Rc<Analysis> {
    analyze_options(
        syms,
        d,
        docs,
        Options {
            recover: true,
            session: Some(session.clone()),
            ..Options::default()
        },
    )
}

/// An uncached analysis with explicit options.
pub fn analyze_options(
    syms: ms_syntax::Names,
    d: &Document,
    docs: &Documents,
    options: Options,
) -> Rc<Analysis> {
    analyze_with(syms, d, docs, options, &mut |target, options| {
        Rc::new(compile_file(syms, target, options))
    })
}

/// A strict analysis of a workspace file, for cross-file queries.
pub fn workspace_analysis(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    d: &Document,
    docs: &Documents,
) -> Rc<Analysis> {
    analyze_options(
        syms,
        d,
        docs,
        Options {
            module: Some(d.path()),
            session: Some(session.clone()),
            ..Options::default()
        },
    )
}
