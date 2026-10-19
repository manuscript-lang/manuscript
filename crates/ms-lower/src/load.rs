//! Loads a `.ms` file and its relative imports into checker modules.

use ms_check::{ImportMap, ModRef};
use ms_syntax::{Diagnostic, Phase, Pos};
use std::collections::{HashMap, HashSet};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

pub(crate) struct Loader {
    root: PathBuf,
    active: HashSet<PathBuf>,
    loaded: HashMap<PathBuf, ms_check::types::Name>,
    modules: Vec<ModRef>,
    imports: ImportMap,
    diagnostics: Vec<Diagnostic>,
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

fn clean(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

impl Loader {
    fn visit(&mut self, canonical: &Path) -> Result<ms_check::types::Name, Diagnostic> {
        let logical = canonical
            .strip_prefix(&self.root)
            .unwrap_or(canonical)
            .to_string_lossy()
            .replace('\\', "/");
        let file: Arc<str> = Arc::from(logical.as_str());
        if self.active.contains(canonical) {
            return Err(resolution(
                &file,
                Pos::new(0, 1, 1),
                format!(
                    "cyclic module dependency at {logical}; modules cannot import each other in a loop, so move the shared declarations into a third module that both import"
                ),
            ));
        }
        if let Some(key) = self.loaded.get(canonical) {
            return Ok(*key);
        }
        self.active.insert(canonical.to_path_buf());
        let result = self.load(canonical, &file);
        self.active.remove(canonical);
        result
    }

    fn load(
        &mut self,
        canonical: &Path,
        file: &Arc<str>,
    ) -> Result<ms_check::types::Name, Diagnostic> {
        let bytes = std::fs::read(canonical)
            .map_err(|e| resolution(file, Pos::new(0, 1, 1), e.to_string()))?;
        let text = String::from_utf8(bytes).map_err(|_| {
            Diagnostic::parse(
                file,
                Pos::new(0, 1, 1),
                "source must be valid UTF-8; re-save the file with UTF-8 encoding",
            )
        })?;
        let module = ms_syntax::parser::parse(file, &text).map_err(|d| *d)?;
        let key = ms_check::types::n(file);
        let mut resolved: Vec<(ms_syntax::NodeId, ms_check::types::Name)> = Vec::new();
        for item in &module.imports {
            if item.path.starts_with("@std/") {
                continue;
            }
            let target = self
                .resolve(canonical, &item.path)
                .map_err(|message| resolution(file, item.pos, message))?;
            let key = self.visit(&target).map_err(|d| {
                if d.phase == Phase::Resolution
                    && d.pos == Pos::new(0, 1, 1)
                    && d.message.starts_with("cyclic")
                {
                    resolution(file, item.pos, d.message)
                } else {
                    d
                }
            })?;
            resolved.push((item.id, key));
        }
        for (id, target) in resolved {
            self.imports.insert(key, id, target);
        }
        self.loaded.insert(canonical.to_path_buf(), key);
        self.modules.push(ms_check::load_module(&module));
        Ok(key)
    }

    fn resolve(&self, importer: &Path, path: &str) -> Result<PathBuf, String> {
        if path.contains('\\') {
            return Err(
                "import paths use / separators; write \"./dir/file.ms\" instead of backslashes"
                    .to_string(),
            );
        }
        if path.starts_with("./") || path.starts_with("../") {
            if !path.ends_with(".ms") {
                let stem = path.rsplit_once('.').map(|(s, _)| s).unwrap_or(path);
                return Err(format!(
                    "import path requires .ms extension; write \"{stem}.ms\""
                ));
            }
            let target = clean(&importer.parent().unwrap_or(Path::new("")).join(path));
            let canonical = std::fs::canonicalize(&target).map_err(|_| {
                format!("cannot find module {path} (looked for {}); check the spelling, make sure the file exists, and that the path is relative to the importing file", missing_component(&target))
            })?;
            if !canonical.starts_with(&self.root) {
                return Err(format!(
                    "path escapes project root: {}; keep imported files inside the directory containing ms.toml (or the entry file's directory)",
                    target.display()
                ));
            }
            return Ok(canonical);
        }
        if path.starts_with('@') {
            return Err(format!(
                "unknown import alias {}; this project declares none, so add one under [aliases] in ms.toml, e.g. @lib = \"src/lib\" (use @std/... for the standard library)",
                path.split('/').next().unwrap_or(path)
            ));
        }
        if path.starts_with('/') {
            return Err("absolute import paths are not supported; write a relative path such as \"../name.ms\" from this file, or declare an alias under [aliases] in ms.toml".to_string());
        }
        Err(format!(
            "imports require a relative path or alias; write \"./{path}\" for a file next to this one, \"@std/name.ms\" for the standard library, or declare an alias under [aliases] in ms.toml"
        ))
    }
}

/// The first path component that does not exist, relative to the working
/// directory when it lies beneath it (the name Go's path error reports).
fn missing_component(target: &Path) -> String {
    let mut prefix = PathBuf::new();
    for c in target.components() {
        prefix.push(c);
        if std::fs::symlink_metadata(&prefix).is_err() {
            break;
        }
    }
    let cwd = std::env::current_dir().unwrap_or_default();
    match prefix.strip_prefix(&cwd) {
        Ok(relative) => relative.display().to_string(),
        Err(_) => prefix.display().to_string(),
    }
}

/// A loaded and checked program.
pub struct Loaded {
    /// Resolution and parse diagnostics followed by the checker's.
    pub diagnostics: Vec<Diagnostic>,
    /// The checked program, when loading succeeded.
    pub program: Option<ms_check::Program>,
    /// Canonical path of the entry module.
    pub entry: String,
}

/// Parses, resolves and checks `path`.
pub fn load(path: &Path) -> Loaded {
    let canonical = match std::fs::canonicalize(path) {
        Ok(p) => p,
        Err(_) => {
            return Loaded {
                diagnostics: vec![resolution(
                    &Arc::from(path.to_string_lossy().as_ref()),
                    Pos::new(0, 1, 1),
                    format!("file not found: {}", path.display()),
                )],
                program: None,
                entry: String::new(),
            };
        }
    };
    let mut loader = Loader {
        root: canonical
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_default(),
        active: HashSet::new(),
        loaded: HashMap::new(),
        modules: Vec::new(),
        imports: ImportMap::default(),
        diagnostics: Vec::new(),
    };
    let entry = match loader.visit(&canonical) {
        Ok(k) => k.as_str().to_string(),
        Err(d) => {
            return Loaded {
                diagnostics: vec![d],
                program: None,
                entry: String::new(),
            };
        }
    };
    let options = ms_check::CheckOptions::default();
    let program = ms_check::check(loader.modules, loader.imports, options);
    let mut diagnostics = loader.diagnostics;
    diagnostics.extend(program.diagnostics.iter().cloned());
    Loaded {
        diagnostics,
        program: Some(program),
        entry,
    }
}
