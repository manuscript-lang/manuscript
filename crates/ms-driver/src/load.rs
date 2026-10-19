//! Module graph loading: the port of Go `pkg/frontend.LoadFile`.
//!
//! Resolves a source file or `ms.toml`, parses every reachable local module
//! once in dependency order, and records which module each import names.
//! Standard (`@std/`) imports belong to the checker.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use ms_check::types::{Name, n};
use ms_check::{ImportMap, ModRef};
use ms_project::{Overlay, Project, ProjectError, gopath};
use ms_syntax::{Diagnostic, Phase, Pos};

/// What to load besides the modules reachable from the entry.
#[derive(Clone, Copy, Debug, Default)]
pub struct LoadOptions {
    /// Add the project's `test.ms` and `*_test.ms` files.
    pub tests: bool,
}

/// Editor loading: unsaved sources, syntax recovery and module selection
/// (`Recover`, `Module`, `Overlay` and `ProjectSources` of Go `frontend.Options`).
#[derive(Clone, Debug, Default)]
pub struct EditorOptions {
    /// Keep the declarations that parse in unfinished source, and keep going
    /// after an import fails. The graph then carries every diagnostic.
    pub recover: bool,
    /// Select this module of a project as the entry (an editor's current file).
    pub module: Option<String>,
    /// Add every source and test module of the project, imported or not.
    pub project_sources: bool,
    /// Unsaved contents by absolute path.
    pub overlay: Overlay,
}

/// The parsed, dependency-ordered module graph of one command.
#[derive(Default)]
pub struct Graph {
    pub modules: Vec<ModRef>,
    pub imports: ImportMap,
    /// Logical path (relative to `source_root`) of the entry module; empty for a library.
    pub entry: String,
    /// A project manifest without an entry.
    pub library: bool,
    /// Where `ms.toml` declares its `[project]` table.
    pub manifest_position: Option<(String, Pos)>,
    pub source_root: String,
    /// Empty for a standalone file.
    pub project_root: String,
    pub configuration: String,
    pub diagnostics: Vec<Diagnostic>,
}

/// A loading failure that is not yet a diagnostic: Go distinguishes
/// diagnostics, which pass through import edges unchanged, from plain errors,
/// which each edge wraps with its own position.
enum Failure {
    Diagnostic(Box<Diagnostic>),
    Error(ProjectError),
    Cycle(String),
}

impl Failure {
    fn message(&self) -> String {
        match self {
            Failure::Diagnostic(d) => d.message.clone(),
            Failure::Error(e) => e.to_string(),
            Failure::Cycle(m) => m.clone(),
        }
    }
}

fn resolution(file: &Arc<str>, pos: Pos, message: String) -> Diagnostic {
    Diagnostic {
        file: file.clone(),
        pos,
        phase: Phase::Resolution,
        message,
        end: None,
        fix: None,
    }
}

fn start() -> Pos {
    Pos::new(0, 1, 1)
}

/// Resolve a module or manifest, then load each reachable local module.
pub fn load_file(filename: &str, options: LoadOptions) -> Graph {
    load_editor_file(filename, options, &EditorOptions::default())
}

/// [`load_file`] over an editor's unsaved sources, with optional recovery.
pub fn load_editor_file(filename: &str, options: LoadOptions, editor: &EditorOptions) -> Graph {
    let (mut config, manifest) = match source_project(filename) {
        Ok(found) => found,
        Err((root, error)) => {
            let file: Arc<str> = Arc::from(filename);
            return Graph {
                source_root: root,
                diagnostics: vec![from_error(&file, &error)],
                ..Graph::default()
            };
        }
    };
    let mut graph = Graph {
        source_root: config.root.clone(),
        ..Graph::default()
    };
    if manifest {
        graph.project_root = config.root.clone();
        graph.configuration = config.configuration.clone();
        graph.library = config.entry.is_empty();
        graph.manifest_position = Some((config.location.file.clone(), manifest_pos(&config)));
    }
    if let Some(module) = &editor.module {
        config.entry = module.clone();
    }
    let overlay = match ms_project::canonical_overlay(&config.root, &editor.overlay) {
        Ok(overlay) => overlay,
        Err(error) => {
            graph.diagnostics = vec![from_error(&Arc::from(filename), &error)];
            return graph;
        }
    };
    let library = graph.library;
    let mut loader = Loader {
        config: &config,
        overlay: &overlay,
        recover: editor.recover,
        graph: &mut graph,
        active: HashSet::new(),
        loaded: HashMap::new(),
    };
    let file: Arc<str> = Arc::from(filename);
    if !config.entry.is_empty() {
        let entry = match ms_project::source_path(&config.root, &config.entry, &overlay) {
            Ok(entry) => entry,
            Err(error) => {
                loader.graph.diagnostics = vec![from_error(&file, &error)];
                return graph;
            }
        };
        match loader.visit(&entry) {
            Ok(key) => loader.graph.entry = key.to_string(),
            Err(failure) => {
                // An incomplete strict graph cannot be checked.
                loader.graph.modules.clear();
                let d = match failure {
                    Failure::Diagnostic(d) => *d,
                    Failure::Error(e) => from_error(&file, &e),
                    Failure::Cycle(m) => resolution(&file, start(), m),
                };
                loader.graph.diagnostics.push(d);
                return graph;
            }
        }
    }
    if manifest && (library || options.tests || editor.project_sources) {
        match ms_project::discover_modules_with_overlay(
            &config,
            library || editor.project_sources,
            &overlay,
        ) {
            Ok(files) => loader.add_discovered(&files),
            Err(error) => {
                loader.graph.diagnostics.push(from_error(&file, &error));
            }
        }
    }
    graph
}

fn manifest_pos(config: &Project) -> Pos {
    Pos::new(
        config.location.offset as u32,
        config.location.line as u32,
        config.location.column as u32,
    )
}

/// `(project, is_manifest)`, or the root and the error.
fn source_project(filename: &str) -> Result<(Project, bool), (String, ProjectError)> {
    let absolute = gopath::abs(filename).map_err(|e| (String::new(), e))?;
    if gopath::base(&absolute) == "ms.toml" {
        let (config, error) = ms_project::read_project_partial(&absolute);
        return match error {
            Some(error) => Err((config.root, error)),
            None => Ok((config, true)),
        };
    }
    let root = gopath::eval_symlinks(&gopath::dir(&absolute)).map_err(|e| (String::new(), e))?;
    let config = Project {
        root,
        entry: absolute,
        ..Project::default()
    };
    Ok((config, false))
}

/// Go's `diagnostic(filename, phase, err)` for an error that is not already one.
fn from_error(file: &Arc<str>, error: &ProjectError) -> Diagnostic {
    if let Some(manifest) = error.manifest_error() {
        let location = &manifest.location;
        return resolution(
            &Arc::from(location.file.as_str()),
            Pos::new(
                location.offset as u32,
                location.line as u32,
                location.column as u32,
            ),
            explain_path_error(&manifest.cause, ""),
        );
    }
    resolution(file, start(), explain_path_error(error, ""))
}

/// Turn raw filesystem failures into a cause and a fix. `import_path` is the
/// import string when the failure came from an import.
pub fn explain_path_error(error: &ProjectError, import_path: &str) -> String {
    let ProjectError::Path(path_error) = error else {
        return error.to_string();
    };
    let mut name = path_error.path.clone();
    if let Ok(cwd) = std::env::current_dir()
        && let Ok(relative) = gopath::rel(&cwd.to_string_lossy(), &name)
        && !relative.starts_with("..")
    {
        name = relative;
    }
    if error.is_not_exist() && !import_path.is_empty() {
        return format!(
            "cannot find module {import_path} (looked for {name}); check the spelling, make sure the file exists, and that the path is relative to the importing file"
        );
    }
    if error.is_not_exist() {
        return format!(
            "file not found: {name}; check the path, pass a .ms file or a project ms.toml, and run from the directory that contains it"
        );
    }
    if path_error.errno == 13 {
        return format!("permission denied reading {name}; make the file readable");
    }
    error.to_string()
}

struct Loader<'a> {
    config: &'a Project,
    overlay: &'a Overlay,
    recover: bool,
    graph: &'a mut Graph,
    active: HashSet<String>,
    loaded: HashMap<String, Name>,
}

impl Loader<'_> {
    fn add_discovered(&mut self, files: &[String]) {
        for file in files {
            let result = ms_project::source_path(&self.config.root, file, self.overlay)
                .map_err(Failure::Error)
                .and_then(|canonical| self.visit(&canonical));
            if let Err(failure) = result {
                let logical: Arc<str> = Arc::from(file.as_str());
                let d = match failure {
                    Failure::Diagnostic(d) => *d,
                    Failure::Error(e) => from_error(&logical, &e),
                    Failure::Cycle(m) => resolution(&logical, start(), m),
                };
                self.graph.diagnostics.push(d);
            }
        }
    }

    /// Accepts an already resolved canonical path. Resolution happens at the
    /// graph's edges, never again during traversal or checking.
    fn visit(&mut self, canonical: &str) -> Result<Name, Failure> {
        let logical = gopath::rel(&self.config.root, canonical).map_err(Failure::Error)?;
        let file: Arc<str> = Arc::from(logical.as_str());
        if self.active.contains(canonical) {
            return Err(Failure::Cycle(format!(
                "cyclic module dependency at {logical}; modules cannot import each other in a loop, so move the shared declarations into a third module that both import"
            )));
        }
        if let Some(key) = self.loaded.get(canonical) {
            return Ok(*key);
        }
        self.active.insert(canonical.to_string());
        let result = self.load(canonical, &file);
        self.active.remove(canonical);
        result
    }

    fn load(&mut self, canonical: &str, file: &Arc<str>) -> Result<Name, Failure> {
        let bytes = match self.overlay.get(canonical) {
            Some(source) => source.clone().into_bytes(),
            None => std::fs::read(canonical)
                .map_err(|e| Failure::Error(ProjectError::path("open", canonical, &e)))?,
        };
        let text = String::from_utf8(bytes).map_err(|_| {
            Failure::Diagnostic(Box::new(Diagnostic::parse(
                file,
                start(),
                "source must be valid UTF-8; re-save the file with UTF-8 encoding",
            )))
        })?;
        let module = if self.recover {
            let (module, issues) = ms_syntax::parse_partial(file, &text);
            self.graph.diagnostics.extend(issues);
            module
        } else {
            ms_syntax::parser::parse(file, &text).map_err(Failure::Diagnostic)?
        };
        let key = n(file);
        let mut resolved: Vec<(ms_syntax::NodeId, Name)> = Vec::new();
        for item in &module.imports {
            if item.path.starts_with("@std/") {
                continue;
            }
            match self.import_module(canonical, file, item) {
                Ok(target) => resolved.push((item.id, target)),
                Err(failure) if self.recover => {
                    let d = match failure {
                        Failure::Diagnostic(d) => *d,
                        Failure::Error(e) => from_error(file, &e),
                        Failure::Cycle(m) => resolution(file, item.pos, m),
                    };
                    self.graph.diagnostics.push(d);
                }
                Err(failure) => return Err(failure),
            }
        }
        for (id, target) in resolved {
            self.graph.imports.insert(key, id, target);
        }
        self.loaded.insert(canonical.to_string(), key);
        self.graph.modules.push(ms_check::load_module(&module));
        Ok(key)
    }

    fn import_module(
        &mut self,
        importer: &str,
        file: &Arc<str>,
        item: &ms_syntax::Import,
    ) -> Result<Name, Failure> {
        let target = ms_project::resolve_import(self.config, importer, &item.path, self.overlay)
            .map_err(|e| {
                Failure::Diagnostic(Box::new(resolution(
                    file,
                    item.pos,
                    explain_path_error(&e, &item.path),
                )))
            })?;
        self.visit(&target).map_err(|failure| match failure {
            Failure::Diagnostic(d) => Failure::Diagnostic(d),
            other => Failure::Diagnostic(Box::new(resolution(file, item.pos, other.message()))),
        })
    }
}
