//! Checked documents: loading a document with its unsaved neighbours, running
//! the checker, and finding the module a document is.

use crate::index::Occurrence;
use crate::lint::LintFinding;
use crate::uri;
use ms_check::syntax::ModRef;
use ms_check::{Program, stdlib};
use ms_driver::{CheckRequest, EditorOptions, Graph, LoadOptions};
use ms_project::Overlay;
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
    /// Loading, parse and checker diagnostics in report order.
    pub diagnostics: Vec<Diagnostic>,
    pub(crate) index: OnceCell<Vec<Occurrence>>,
    pub(crate) lints: OnceCell<Vec<LintFinding>>,
}

impl Analysis {
    /// The occurrence index, built once per analysis; empty without a program.
    pub fn index(&self) -> &[Occurrence] {
        if self.program.is_none() {
            return &[];
        }
        self.index.get_or_init(|| crate::index::source_index(self))
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
        if ms_project::gopath::is_abs(file) {
            return file.to_string();
        }
        ms_project::gopath::join(&[self.root(), file])
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
    pub fn source_modules(&self) -> Vec<ModRef> {
        let Some(program) = &self.program else {
            return Vec::new();
        };
        let mut modules: Vec<ModRef> = program
            .modules
            .iter()
            .filter(|m| !m.file.as_str().starts_with("@std/"))
            .cloned()
            .collect();
        modules.extend(stdlib::standard_modules());
        modules
    }

    /// The module whose source a document is, if the program contains it.
    pub fn module(&self, d: &Document) -> Option<ModRef> {
        let program = self.program.as_ref()?;
        if let Some(m) = standard_library_document(d) {
            return Some(m);
        }
        let mut path = d.path();
        if let Ok(canonical) = ms_project::gopath::eval_symlinks(&path) {
            path = canonical;
        }
        program
            .modules
            .iter()
            .find(|m| m.file.as_str() == path || self.module_path(m.file.as_str()) == path)
            .cloned()
    }

    /// The logical file of a document's module, or empty.
    pub fn module_file(&self, d: &Document) -> String {
        self.module(d)
            .map(|m| m.file.as_str().to_string())
            .unwrap_or_default()
    }
}

/// The bundled module a document stands for: a `manuscript-stdlib:` URI, or a
/// file that is byte-for-byte a bundled declaration file.
pub fn standard_library_document(d: &Document) -> Option<ModRef> {
    if uri::is_standard_library(&d.uri) {
        return standard_library_module(&d.uri).ok();
    }
    let url = uri::parse(&d.uri)?;
    if url.scheme != "file" || url.query || url.fragment {
        return None;
    }
    let base = ms_project::gopath::base(&d.path());
    stdlib::standard_modules().into_iter().find(|m| {
        m.file.as_str().strip_prefix("@std/") == Some(base.as_str()) && *m.source == *d.text
    })
}

/// The bundled module a `manuscript-stdlib:` URI names.
pub fn standard_library_module(uri: &str) -> Result<ModRef, &'static str> {
    let path = uri::standard_library_path(uri)?;
    stdlib::standard_modules()
        .into_iter()
        .find(|m| {
            m.file
                .as_str()
                .strip_prefix("@std/")
                .is_some_and(|rest| path == format!("/{rest}"))
        })
        .ok_or("unknown standard-library module")
}

/// The source of a bundled module by URI.
pub fn standard_library_source(uri: &str) -> Result<String, &'static str> {
    standard_library_module(uri).map(|m| m.source.to_string())
}

/// Checks a file or manifest with unsaved sources (`compiler.CompileFile`).
pub fn compile_file(filename: &str, options: &Options) -> Analysis {
    let editor = EditorOptions {
        recover: options.recover,
        module: options.module.clone(),
        project_sources: options.project_sources,
        overlay: options.overlay.clone(),
    };
    let graph = ms_driver::load_editor_file(filename, LoadOptions::default(), &editor);
    check(graph, options)
}

/// Checks in-memory source without filesystem resolution (`compiler.CompileSource`).
pub fn compile_source(filename: &str, source: &str, options: &Options) -> Analysis {
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
            graph.modules.push(ms_check::load_module(&module));
        }
    }
    check(graph, options)
}

fn check(graph: Graph, options: &Options) -> Analysis {
    let checked = ms_driver::check_graph_at(
        graph,
        CheckRequest::default(),
        options.scope_marker.as_deref(),
    );
    Analysis {
        source_root: checked.source_root,
        project_root: checked.project_root,
        program: checked.program,
        diagnostics: checked.diagnostics,
        ..Analysis::default()
    }
}

/// The empty program used for standard-library documents, whose signatures the
/// compiler already checked at startup.
fn library_analysis() -> Analysis {
    Analysis {
        program: Some(Program::default()),
        ..Analysis::default()
    }
}

/// Selection and overlay validation shared by uncached and cached analysis.
pub fn analyze_with(
    d: &Document,
    docs: &Documents,
    mut options: Options,
    compile: &mut dyn FnMut(&str, &Options) -> Rc<Analysis>,
) -> Rc<Analysis> {
    if standard_library_document(d).is_some() {
        return Rc::new(library_analysis());
    }
    if uri::is_standard_library(&d.uri) {
        return Rc::new(Analysis::default());
    }
    let path = d.path();
    let mut overlay = Overlay::new();
    for open in docs.values() {
        if uri::is_standard_library(&open.uri) || standard_library_document(open).is_some() {
            continue;
        }
        overlay.insert(open.path(), open.text.clone());
    }
    overlay.insert(path.clone(), d.text.clone());
    options.overlay = overlay;
    let target = ms_project::find_manifest(&path).unwrap_or_else(|| path.clone());
    if options.scope_marker.is_some() && target != path {
        options.module = Some(path.clone());
    }
    let result = compile(&target, &options);
    if result.program.is_none() && result.source_root.is_empty() && target == path {
        return Rc::new(compile_source(&path, &d.text, &options));
    }
    if target != path && result.program.is_some() && result.module(d).is_none() {
        options.module = Some(path);
        return compile(&target, &options);
    }
    result
}

/// An uncached analysis of one document.
pub fn analyze(d: &Document, docs: &Documents) -> Rc<Analysis> {
    analyze_options(
        d,
        docs,
        Options {
            recover: true,
            ..Options::default()
        },
    )
}

/// An uncached analysis with explicit options.
pub fn analyze_options(d: &Document, docs: &Documents, options: Options) -> Rc<Analysis> {
    analyze_with(d, docs, options, &mut |target, options| {
        Rc::new(compile_file(target, options))
    })
}

/// A strict analysis of a workspace file, for cross-file queries.
pub fn workspace_analysis(d: &Document, docs: &Documents) -> Rc<Analysis> {
    analyze_options(
        d,
        docs,
        Options {
            module: Some(d.path()),
            ..Options::default()
        },
    )
}
