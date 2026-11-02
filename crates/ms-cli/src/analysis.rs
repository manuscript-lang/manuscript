//! Input selection for `ms check` and `ms lint`: a collection is a set of
//! independent compiler requests, never a combined program. Engines call
//! [`select_analysis_inputs`] with the request's targets.

use std::collections::BTreeSet;

use ms_driver::project::{ProjectError, pathops, source_path};

use crate::diagnostic::{CommandDiagnostic, Position};
use crate::util::{file_error, format_cwd, format_display};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AnalysisInput {
    pub path: String,
    pub display: String,
}

#[derive(Clone, Debug, Default)]
pub struct AnalysisSelection {
    pub inputs: Vec<AnalysisInput>,
    /// Resolution failures for targets that could not be selected.
    pub diagnostics: Vec<CommandDiagnostic>,
    pub cwd: String,
    /// More than one input: diagnostics carry paths relative to the working directory.
    pub collection: bool,
}

pub fn select_analysis_inputs(targets: &[String]) -> Result<AnalysisSelection, ProjectError> {
    let cwd = format_cwd()?;
    let mut selection = AnalysisSelection {
        cwd: cwd.clone(),
        collection: targets.len() > 1,
        ..Default::default()
    };
    let mut seen: BTreeSet<String> = BTreeSet::new();

    fn report(selection: &mut AnalysisSelection, cwd: &str, path: &str, error: &ProjectError) {
        selection.diagnostics.push(CommandDiagnostic::source(
            "resolution",
            &file_error(error),
            Position::new(format_display(cwd, path), 1, 1),
        ));
    }

    fn add(selection: &mut AnalysisSelection, seen: &mut BTreeSet<String>, cwd: &str, path: &str) {
        if !selection.collection {
            selection.inputs.push(AnalysisInput {
                path: path.to_string(),
                display: path.to_string(),
            });
            return;
        }
        let resolve = || -> Result<String, ProjectError> {
            let absolute = pathops::abs(path)?;
            let mut canonical = pathops::eval_symlinks(&absolute)?;
            if pathops::base(path) == "ms.toml" {
                // Manifest configuration paths belong to its containing directory,
                // even if the manifest itself is a file symlink.
                let parent = pathops::eval_symlinks(&pathops::dir(&absolute))?;
                canonical = pathops::join(&[&parent, "ms.toml"]);
            }
            Ok(canonical)
        };
        match resolve() {
            Err(error) => report(selection, cwd, path, &error),
            Ok(canonical) => {
                if seen.insert(canonical.clone()) {
                    let display = format_display(cwd, &canonical);
                    selection.inputs.push(AnalysisInput {
                        path: canonical,
                        display,
                    });
                }
            }
        }
    }

    for target in targets {
        let is_dir = std::fs::metadata(target).is_ok_and(|m| m.is_dir());
        if !is_dir {
            add(&mut selection, &mut seen, &cwd, target);
            continue;
        }
        let manifest = pathops::join(&[target, "ms.toml"]);
        if !matches!(std::fs::metadata(&manifest), Err(e) if e.kind() == std::io::ErrorKind::NotFound)
        {
            add(&mut selection, &mut seen, &cwd, &manifest);
            continue;
        }
        selection.collection = true;
        let root = match pathops::abs(target).and_then(|absolute| pathops::eval_symlinks(&absolute))
        {
            Ok(root) => root,
            Err(error) => {
                report(&mut selection, &cwd, target, &error);
                continue;
            }
        };
        let (paths, error) = standalone_analysis_files(&root);
        if let Some(error) = error {
            report(&mut selection, &cwd, target, &error);
        }
        for path in paths {
            match source_path(&root, &path, &ms_driver::project::Overlay::new()) {
                Ok(canonical) => add(&mut selection, &mut seen, &cwd, &canonical),
                Err(error) => report(&mut selection, &cwd, &path, &error),
            }
        }
    }
    selection.inputs.sort_by(|a, b| a.display.cmp(&b.display));
    Ok(selection)
}

/// Established directory exclusions: hidden, `vendor` and `node_modules`
/// directories and nested projects (which require explicit selection) are skipped.
fn standalone_analysis_files(root: &str) -> (Vec<String>, Option<ProjectError>) {
    let mut files = Vec::new();
    let error = walk(root, &mut files).err();
    (files, error)
}

fn walk(directory: &str, files: &mut Vec<String>) -> Result<(), ProjectError> {
    let read =
        std::fs::read_dir(directory).map_err(|e| ProjectError::path("open", directory, &e))?;
    let mut entries = Vec::new();
    for entry in read {
        let entry = entry.map_err(|e| ProjectError::path("readdirent", directory, &e))?;
        let file_type = entry
            .file_type()
            .map_err(|e| ProjectError::path("lstat", directory, &e))?;
        let name = entry.file_name();
        let is_dir = file_type.is_dir();
        if is_dir {
            if name.as_encoded_bytes().starts_with(b".")
                || name == "vendor"
                || name == "node_modules"
            {
                continue;
            }
        } else {
            // A symlink to a directory is skipped, even when its name ends in `.ms`.
            let linked_dir =
                file_type.is_symlink() && std::fs::metadata(entry.path()).is_ok_and(|m| m.is_dir());
            if linked_dir || !name.as_encoded_bytes().ends_with(b".ms") {
                continue;
            }
        }
        let Ok(name) = name.into_string() else {
            // Nested projects are excluded even when their directory name is not UTF-8.
            if is_dir && std::fs::metadata(entry.path().join("ms.toml")).is_ok() {
                continue;
            }
            return Err(ProjectError::Message(format!(
                "source filename in {directory} is not valid UTF-8; rename it using UTF-8 and re-run the command"
            )));
        };
        entries.push((name, is_dir));
    }
    entries.sort();
    for (name, is_dir) in entries {
        let path = pathops::join(&[directory, &name]);
        if is_dir {
            match std::fs::metadata(pathops::join(&[&path, "ms.toml"])) {
                Ok(_) => continue,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => {
                    return Err(ProjectError::path(
                        "stat",
                        &pathops::join(&[&path, "ms.toml"]),
                        &e,
                    ));
                }
            }
            walk(&path, files)?;
        } else {
            files.push(path);
        }
    }
    Ok(())
}

impl AnalysisSelection {
    /// Map a diagnostic position to the display form for a collection.
    pub fn position(&self, root: &str, position: &Position) -> Position {
        if !self.collection || position.file.starts_with("@std/") {
            return position.clone();
        }
        let mut position = position.clone();
        if !root.is_empty() && !pathops::is_abs(&position.file) {
            position.file = pathops::join(&[root, &position.file]);
        }
        position.file = format_display(&self.cwd, &position.file);
        position
    }
}
