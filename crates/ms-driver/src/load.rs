//! Module graph loading.
//!
//! Resolves a source file or `ms.toml`, parses every reachable local module
//! once in dependency order, and records which module each import names.
//! Standard (`@std/`) imports belong to the checker.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::project::{Overlay, Project, ProjectError, pathops};
use ms_check::types::{Name, n};
use ms_check::{ImportMap, ModRef};
use ms_syntax::{Diagnostic, Phase, Pos};

/// What to load besides the modules reachable from the entry.
#[derive(Clone, Copy, Debug, Default)]
pub struct LoadOptions {
    /// Add the project's `test.ms`, `*_test.ms`, `bench.ms` and `*_bench.ms` files.
    pub tests: bool,
}

/// Editor loading: unsaved sources, syntax recovery and module selection
/// (`Recover`, `Module`, `Overlay` and `ProjectSources`).
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

/// Diagnostics pass through import edges unchanged; plain errors and cycles
/// acquire the position of the edge that encountered them.
#[derive(Clone)]
enum Failure {
    Diagnostic(Box<Diagnostic>, Arc<[Diagnostic]>),
    Error(ProjectError),
    Cycle(String),
    // Keep cycle attribution traversal-dependent when propagating it through imports.
    CycleDiagnostic(Box<Diagnostic>),
}

impl Failure {
    fn diagnostic(d: Box<Diagnostic>) -> Self {
        Self::Diagnostic(d, Arc::from([]))
    }

    fn into_diagnostic(self, file: &Arc<str>, cycle_pos: Pos) -> Diagnostic {
        match self {
            Failure::Diagnostic(d, _) | Failure::CycleDiagnostic(d) => *d,
            Failure::Error(e) => from_error(file, &e),
            Failure::Cycle(m) => resolution(file, cycle_pos, m),
        }
    }

    fn message(&self) -> String {
        match self {
            Failure::Diagnostic(d, _) | Failure::CycleDiagnostic(d) => d.message.clone(),
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
    let overlay = match crate::project::canonical_overlay(&config.root, &editor.overlay) {
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
        failed: HashMap::new(),
        resolved: HashMap::new(),
    };
    let file: Arc<str> = Arc::from(filename);
    if !config.entry.is_empty() {
        let entry = match crate::project::source_path(&config.root, &config.entry, &overlay) {
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
                loader
                    .graph
                    .diagnostics
                    .push(failure.into_diagnostic(&file, start()));
                return graph;
            }
        }
    }
    if manifest && (library || options.tests || editor.project_sources) {
        match crate::project::discover_modules_with_overlay(
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
    let absolute = pathops::abs(filename).map_err(|e| (String::new(), e))?;
    if pathops::base(&absolute) == "ms.toml" {
        let (config, error) = crate::project::read_project_partial(&absolute);
        return match error {
            Some(error) => Err((config.root, error)),
            None => Ok((config, true)),
        };
    }
    let root = pathops::eval_symlinks(&pathops::dir(&absolute)).map_err(|e| (String::new(), e))?;
    // The nearest enclosing ms.toml supplies the import root and aliases, so entry
    // files can share a library above them. The file stays the sole entry.
    if let Some(manifest) = enclosing_manifest(&root) {
        let (mut config, error) = crate::project::read_project_partial(&manifest);
        if let Some(error) = error {
            return Err((config.root, error));
        }
        config.entry = absolute;
        return Ok((config, false));
    }
    let config = Project {
        root,
        entry: absolute,
        ..Project::default()
    };
    Ok((config, false))
}

/// The nearest `ms.toml` in `dir` or an ancestor.
pub fn enclosing_manifest(dir: &str) -> Option<String> {
    let mut current = dir.to_string();
    loop {
        let candidate = pathops::join(&[&current, "ms.toml"]);
        if std::fs::metadata(&candidate).is_ok_and(|m| m.is_file()) {
            return Some(candidate);
        }
        let parent = pathops::dir(&current);
        if parent == current {
            return None;
        }
        current = parent;
    }
}

/// Builds a diagnostic for an error that is not already one.
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
    // `pathops` speaks `/` only; Windows spells the same paths with `\` and a `\\?\` prefix.
    let slashed = |path: &str| {
        if cfg!(windows) {
            path.trim_start_matches(r"\\?\").replace('\\', "/")
        } else {
            path.to_string()
        }
    };
    let mut name = slashed(&path_error.path);
    // The working directory can be spelled differently from the error's path (`/var` and
    // `/private/var`, a Windows short name), so the canonical spelling is tried as well.
    if let Ok(cwd) = std::env::current_dir() {
        let canonical = std::fs::canonicalize(&cwd).ok();
        for base in std::iter::once(&cwd).chain(canonical.as_ref()) {
            if let Ok(relative) = pathops::rel(&slashed(&base.to_string_lossy()), &name)
                && !relative.starts_with("..")
            {
                name = relative;
                break;
            }
        }
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
    // Replay secondary parse diagnostics too, preserving their order and multiplicity.
    failed: HashMap<String, Failure>,
    // Project and overlay are fixed for this load; relative paths are directory-local.
    resolved: HashMap<(String, Box<str>), String>,
}

impl Loader<'_> {
    fn add_discovered(&mut self, files: &[String]) {
        for file in files {
            let result = crate::project::source_path(&self.config.root, file, self.overlay)
                .map_err(Failure::Error)
                .and_then(|canonical| self.visit(&canonical));
            if let Err(failure) = result {
                let logical: Arc<str> = Arc::from(file.as_str());
                self.graph
                    .diagnostics
                    .push(failure.into_diagnostic(&logical, start()));
            }
        }
    }

    /// Accepts an already resolved canonical path. Resolution happens at the
    /// graph's edges, never again during traversal or checking.
    fn visit(&mut self, canonical: &str) -> Result<Name, Failure> {
        let logical = pathops::rel(&self.config.root, canonical).map_err(Failure::Error)?;
        let file: Arc<str> = Arc::from(logical.as_str());
        if self.active.contains(canonical) {
            return Err(Failure::Cycle(format!(
                "cyclic module dependency at {logical}; modules cannot import each other in a loop, so move the shared declarations into a third module that both import"
            )));
        }
        if let Some(key) = self.loaded.get(canonical) {
            return Ok(*key);
        }
        if let Some(failure) = self.failed.get(canonical) {
            if let Failure::Diagnostic(_, diagnostics) = failure {
                self.graph.diagnostics.extend(diagnostics.iter().cloned());
            }
            return Err(failure.clone());
        }
        self.active.insert(canonical.to_string());
        let result = self.load(canonical, &file);
        self.active.remove(canonical);
        if let Err(failure @ (Failure::Diagnostic(..) | Failure::Error(_))) = &result {
            self.failed.insert(canonical.to_string(), failure.clone());
        }
        result
    }

    fn load(&mut self, canonical: &str, file: &Arc<str>) -> Result<Name, Failure> {
        let bytes = match self.overlay.get(canonical) {
            Some(source) => source.clone().into_bytes(),
            None => std::fs::read(canonical)
                .map_err(|e| Failure::Error(ProjectError::path("open", canonical, &e)))?,
        };
        let text = String::from_utf8(bytes).map_err(|_| {
            Failure::diagnostic(Box::new(Diagnostic::parse(
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
            match ms_syntax::parser::parse(file, &text) {
                Ok(module) => module,
                Err(first) => {
                    // Report every independent syntax error in the file, not
                    // only the first, so one run shows all that need fixing.
                    let (_, issues) = ms_syntax::parse_partial(file, &text);
                    let secondary: Arc<[Diagnostic]> = issues
                        .into_iter()
                        .filter(|d| d.pos != first.pos && d.pos.line > 0)
                        // One unclosed delimiter is one mistake: the strict
                        // parse reports it at the end of the file and recovery
                        // at the next declaration, naming the same opener.
                        .filter(|d| {
                            !(d.message == first.message && d.message.contains(" opened at line "))
                        })
                        .collect();
                    self.graph.diagnostics.extend(secondary.iter().cloned());
                    return Err(Failure::Diagnostic(first, secondary));
                }
            }
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
                    self.graph
                        .diagnostics
                        .push(failure.into_diagnostic(file, item.pos));
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
        let request = (pathops::dir(importer), item.path.clone());
        let target = if let Some(target) = self.resolved.get(&request) {
            target.clone()
        } else {
            let target =
                crate::project::resolve_import(self.config, importer, &item.path, self.overlay)
                    .map_err(|e| {
                        Failure::diagnostic(Box::new(resolution(
                            file,
                            item.pos,
                            explain_path_error(&e, &item.path),
                        )))
                    })?;
            self.resolved.insert(request, target.clone());
            target
        };
        self.visit(&target).map_err(|failure| match failure {
            failure @ Failure::Diagnostic(..) => failure,
            Failure::CycleDiagnostic(d) => Failure::CycleDiagnostic(d),
            Failure::Cycle(message) => {
                Failure::CycleDiagnostic(Box::new(resolution(file, item.pos, message)))
            }
            other => Failure::diagnostic(Box::new(resolution(file, item.pos, other.message()))),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn with_loader(test: impl FnOnce(&mut Loader<'_>, &str)) {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "ms-loader-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let root = pathops::eval_symlinks(dir.to_str().unwrap()).unwrap();
        let config = Project {
            root: root.clone(),
            ..Project::default()
        };
        let mut graph = Graph::default();
        let overlay = Overlay::new();
        let mut loader = Loader {
            config: &config,
            overlay: &overlay,
            recover: false,
            graph: &mut graph,
            active: HashSet::new(),
            loaded: HashMap::new(),
            failed: HashMap::new(),
            resolved: HashMap::new(),
        };
        test(&mut loader, &root);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn failed_suffixes_are_reused_without_changing_diagnostics() {
        with_loader(|loader, root| {
            for i in 0..64 {
                std::fs::write(
                    format!("{root}/m{i}.ms"),
                    format!("import value from \"./m{}.ms\"\n", i + 1),
                )
                .unwrap();
            }
            let first = loader
                .visit(&format!("{root}/m0.ms"))
                .err()
                .unwrap()
                .into_diagnostic(&Arc::from("unused"), start());
            assert_eq!(loader.failed.len(), 64);
            assert_eq!(&*first.file, "m63.ms");
            std::fs::remove_file(format!("{root}/m63.ms")).unwrap();
            for i in 0..64 {
                let repeated = loader
                    .visit(&format!("{root}/m{i}.ms"))
                    .err()
                    .unwrap()
                    .into_diagnostic(&Arc::from("unused"), start());
                assert_eq!(format!("{first:?}"), format!("{repeated:?}"));
            }
            assert!(loader.loaded.is_empty());
        });
    }

    #[test]
    fn cached_parse_failures_replay_secondary_diagnostics() {
        with_loader(|loader, root| {
            let file = format!("{root}/bad.ms");
            std::fs::write(
                &file,
                "fn first() Int:\n    return +\n\nfn second() Int:\n    return +\n",
            )
            .unwrap();
            let first = loader.visit(&file).err().unwrap();
            let diagnostics = std::mem::take(&mut loader.graph.diagnostics);
            assert!(!diagnostics.is_empty());
            std::fs::remove_file(&file).unwrap();
            let repeated = loader.visit(&file).err().unwrap();
            assert_eq!(first.message(), repeated.message());
            assert_eq!(
                format!("{diagnostics:?}"),
                format!("{:?}", loader.graph.diagnostics)
            );
        });
    }

    #[test]
    fn cycle_failures_keep_the_current_closing_edge() {
        with_loader(|loader, root| {
            std::fs::write(format!("{root}/a.ms"), "import b from \"./b.ms\"\n").unwrap();
            std::fs::write(format!("{root}/b.ms"), "import a from \"./a.ms\"\n").unwrap();
            for (entry, closing) in [("a", "b"), ("b", "a")] {
                let d = loader
                    .visit(&format!("{root}/{entry}.ms"))
                    .err()
                    .unwrap()
                    .into_diagnostic(&Arc::from("unused"), start());
                assert_eq!(&*d.file, format!("{closing}.ms"));
                assert!(d.message.contains(&format!("at {entry}.ms")));
                assert!(loader.failed.is_empty());
            }
        });
    }
    #[test]
    fn failed_ancestors_share_secondary_diagnostics() {
        with_loader(|loader, root| {
            for i in 0..16 {
                let source = if i == 15 {
                    "fn first() Int:\n    return +\n\nfn second() Int:\n    return +\n".to_string()
                } else {
                    format!("import value from \"./m{}.ms\"\n", i + 1)
                };
                std::fs::write(format!("{root}/m{i}.ms"), source).unwrap();
            }
            assert!(loader.visit(&format!("{root}/m0.ms")).is_err());
            assert_eq!(loader.failed.len(), 16);
            let Failure::Diagnostic(_, shared) =
                loader.failed.get(&format!("{root}/m0.ms")).unwrap()
            else {
                panic!("expected parse diagnostic")
            };
            assert!(!shared.is_empty());
            for failure in loader.failed.values() {
                let Failure::Diagnostic(_, secondary) = failure else {
                    panic!("expected parse diagnostic")
                };
                assert!(Arc::ptr_eq(shared, secondary));
            }
        });
    }

    fn import(loader: &mut Loader<'_>, importer: &str, path: &str) -> Result<Name, Failure> {
        let file: Arc<str> = Arc::from(pathops::rel(&loader.config.root, importer).unwrap());
        let module =
            ms_syntax::parser::parse(&file, &format!("import value from \"{path}\"\n")).unwrap();
        loader.import_module(importer, &file, &module.imports[0])
    }

    #[test]
    fn repeated_edges_reuse_resolution_but_directories_remain_distinct() {
        with_loader(|loader, root| {
            std::fs::create_dir(format!("{root}/nested")).unwrap();
            for dir in [root.to_string(), format!("{root}/nested")] {
                std::fs::write(
                    format!("{dir}/leaf.ms"),
                    "export fn value() Int: return 1\n",
                )
                .unwrap();
            }
            let first = import(loader, &format!("{root}/a.ms"), "./leaf.ms")
                .unwrap_or_else(|e| panic!("{}", e.message()));
            std::fs::remove_file(format!("{root}/leaf.ms")).unwrap();
            let second = import(loader, &format!("{root}/b.ms"), "./leaf.ms")
                .unwrap_or_else(|e| panic!("{}", e.message()));
            assert_eq!(first, second);
            assert_eq!(loader.resolved.len(), 1);
            let nested = import(loader, &format!("{root}/nested/a.ms"), "./leaf.ms")
                .unwrap_or_else(|e| panic!("{}", e.message()));
            assert_ne!(first, nested);
            assert_eq!(loader.resolved.len(), 2);
            assert_eq!(loader.graph.modules.len(), 2);
        });
    }

    #[test]
    fn resolution_failures_keep_each_import_position_and_are_not_cached() {
        with_loader(|loader, root| {
            for name in ["a", "b"] {
                let failure = import(loader, &format!("{root}/{name}.ms"), "./new.ms")
                    .err()
                    .unwrap();
                let d = failure.into_diagnostic(&Arc::from("unused"), start());
                assert_eq!(&*d.file, format!("{name}.ms"));
            }
            assert!(loader.resolved.is_empty());
            std::fs::write(
                format!("{root}/new.ms"),
                "export fn value() Int: return 1\n",
            )
            .unwrap();
            assert!(import(loader, &format!("{root}/a.ms"), "./new.ms").is_ok());
            assert_eq!(loader.resolved.len(), 1);
        });
    }
}
