//! Confined import resolution.

use std::collections::BTreeMap;

use crate::project::error::ProjectError;
use crate::project::gopath;
use crate::project::manifest::Project;
use crate::project::overlay::Overlay;

/// Resolve a local import; standard (`@std/`) imports belong to the checker.
pub fn resolve_import(
    project: &Project,
    importer: &str,
    path: &str,
    overlay: &Overlay,
) -> Result<String, ProjectError> {
    if path.contains('\\') {
        return Err(ProjectError::msg(
            "import paths use / separators; write \"./dir/file.ms\" instead of backslashes",
        ));
    }
    let target;
    if path.starts_with("./") || path.starts_with("../") {
        if gopath::ext(path) != ".ms" {
            let stem = &path[..path.len() - gopath::ext(path).len()];
            return Err(ProjectError::msg(format!(
                "import path requires .ms extension; write \"{stem}.ms\""
            )));
        }
        target = gopath::join(&[&gopath::dir(importer), path]);
    } else if path.starts_with('@') {
        let (alias, remainder) = path.split_once('/').unwrap_or((path, ""));
        let base = project.aliases.get(alias).map(String::as_str).unwrap_or("");
        if base.is_empty() {
            return Err(ProjectError::msg(format!(
                "unknown import alias {alias}{}",
                alias_hint(&project.aliases)
            )));
        }
        let info = std::fs::metadata(base).map_err(|e| ProjectError::path("stat", base, &e))?;
        if info.is_dir() {
            if remainder.is_empty() || gopath::ext(remainder) != ".ms" {
                return Err(ProjectError::msg(format!(
                    "directory alias requires a .ms path; write \"{alias}/<file>.ms\""
                )));
            }
            target = gopath::join(&[base, remainder]);
        } else {
            if !remainder.is_empty() || gopath::ext(base) != ".ms" {
                return Err(ProjectError::msg(format!(
                    "file alias does not accept a suffix; alias {alias} names one file, so import it as \"{alias}\" alone"
                )));
            }
            target = base.to_string();
        }
    } else if path.starts_with('/') {
        return Err(ProjectError::msg(
            "absolute import paths are not supported; write a relative path such as \"../name.ms\" from this file, or declare an alias under [aliases] in ms.toml",
        ));
    } else {
        return Err(ProjectError::msg(format!(
            "imports require a relative path or alias; write \"./{path}\" for a file next to this one, \"@std/name.ms\" for the standard library, or declare an alias under [aliases] in ms.toml"
        )));
    }
    source_path(&project.root, &target, overlay)
}

/// Canonicalize a source path within `root`, which must be canonical. An
/// overlay may supply a new file only beneath an existing, confined directory.
pub fn source_path(root: &str, path: &str, overlay: &Overlay) -> Result<String, ProjectError> {
    let path = if gopath::is_abs(path) {
        path.to_string()
    } else {
        gopath::join(&[root, path])
    };
    let canonical = match gopath::eval_symlinks(&path) {
        Ok(canonical) => canonical,
        Err(error) => {
            if overlay.is_empty() || !error.is_not_exist() {
                return Err(error);
            }
            // A dangling link is an existing entry, not a new editor file.
            match std::fs::symlink_metadata(&path) {
                Ok(_) => return Err(error),
                Err(e) if e.raw_os_error() != Some(crate::project::error::ENOENT) => {
                    return Err(error);
                }
                Err(_) => {}
            }
            let parent = gopath::eval_symlinks(&gopath::dir(&path))?;
            let canonical = gopath::join(&[&parent, &gopath::base(&path)]);
            if !(cfg!(windows) && overlay.contains_key(&path))
                && !overlay.contains_key(&gopath::clean(&path))
                && !overlay.contains_key(&canonical)
            {
                return Err(error);
            }
            canonical
        }
    };
    match gopath::rel(root, &canonical) {
        Ok(rel) if !gopath::escapes(&rel) => Ok(canonical),
        _ => Err(ProjectError::msg(format!(
            "path escapes project root: {path}; keep imported files inside the directory containing ms.toml (or the entry file's directory)"
        ))),
    }
}

fn alias_hint(aliases: &BTreeMap<String, String>) -> String {
    if aliases.is_empty() {
        return "; this project declares none, so add one under [aliases] in ms.toml, e.g. @lib = \"src/lib\" (use @std/... for the standard library)".to_string();
    }
    let names: Vec<&str> = aliases.keys().map(String::as_str).collect();
    format!("; declared aliases: {}", names.join(", "))
}
