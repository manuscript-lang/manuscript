//! Confined import resolution.

use std::collections::BTreeMap;

use crate::project::error::ProjectError;
use crate::project::manifest::Project;
use crate::project::overlay::Overlay;
use crate::project::pathops;

/// Resolve a local import; standard (`@std/`) imports belong to the checker.
pub fn resolve_import(
    project: &Project,
    importer: &str,
    path: &str,
    overlay: &Overlay,
) -> Result<String, ProjectError> {
    match import_target(project, importer, path)? {
        Target::Generated(module) => Ok(module),
        Target::Path(target) => source_path(&project.root, &target, overlay),
    }
}

/// An import before its symlinks are resolved.
pub enum Target {
    /// A module generated on load; no file exists.
    Generated(String),
    /// The path the import names, links unresolved.
    Path(String),
}

/// The path a local import names, before symlink resolution and confinement.
pub fn import_target(
    project: &Project,
    importer: &str,
    path: &str,
) -> Result<Target, ProjectError> {
    if path.contains('\\') {
        return Err(ProjectError::msg(
            "import paths use / separators; write \"./dir/file.ms\" instead of backslashes",
        ));
    }
    let target;
    if path.starts_with("./") || path.starts_with("../") {
        let last = path.rsplit('/').next().unwrap_or("");
        if matches!(last, "" | "." | "..") {
            return Err(ProjectError::msg(format!(
                "import path {path:?} names a directory, not a module; end it with a file such as \"./name.ms\""
            )));
        }
        if pathops::ext(path) != ".ms" {
            let stem = &path[..path.len() - pathops::ext(path).len()];
            return Err(ProjectError::msg(format!(
                "import path requires .ms extension; write \"{stem}.ms\""
            )));
        }
        target = pathops::join(&[&pathops::dir(importer), path]);
    } else if path.starts_with('@') {
        let (alias, remainder) = path.split_once('/').unwrap_or((path, ""));
        if project.embed.contains_key(alias) {
            if !remainder.is_empty() {
                return Err(ProjectError::msg(format!(
                    "embed {alias} names a generated module, so import it as \"{alias}\" alone"
                )));
            }
            // Generated on load; no file exists, so there is nothing to canonicalize.
            return Ok(Target::Generated(crate::project::embed::module_path(
                &project.root,
                alias,
            )));
        }
        let base = project.aliases.get(alias).map(String::as_str).unwrap_or("");
        if base.is_empty() {
            return Err(ProjectError::msg(format!(
                "unknown import alias {alias}{}",
                alias_hint(&project.aliases)
            )));
        }
        let info = std::fs::metadata(base).map_err(|e| ProjectError::path("stat", base, &e))?;
        if info.is_dir() {
            if remainder.is_empty() || pathops::ext(remainder) != ".ms" {
                return Err(ProjectError::msg(format!(
                    "directory alias requires a .ms path; write \"{alias}/<file>.ms\""
                )));
            }
            target = pathops::join(&[base, remainder]);
        } else {
            if !remainder.is_empty() || pathops::ext(base) != ".ms" {
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
        let sample = if matches!(path, "" | "." | "..") {
            "name.ms"
        } else {
            path
        };
        return Err(ProjectError::msg(format!(
            "imports require a relative path or alias; write \"./{sample}\" for a file next to this one, \"@std/name.ms\" for the standard library, or declare an alias under [aliases] in ms.toml"
        )));
    }
    Ok(Target::Path(target))
}

/// The most links one lookup follows, as in the resolver.
const MAX_LINKS: usize = 255;

/// The symbolic links among the components of `path` (relative paths are under `root`), as
/// absolute paths, and the links their targets pass through in turn: the entries whose
/// retargeting changes what the import resolves to.
pub fn link_components(root: &str, path: &str) -> Vec<String> {
    let full = if pathops::is_abs(path) {
        pathops::clean(path)
    } else {
        pathops::join(&[root, path])
    };
    let mut links: Vec<String> = Vec::new();
    let mut pending = vec![full];
    let mut followed = 0;
    while let Some(next) = pending.pop() {
        // Walk by path component, not by splitting on `/`: a Windows path may carry a drive or
        // verbatim prefix and backslash separators, which a text split would not see.
        let components: Vec<_> = std::path::Path::new(&next).components().collect();
        let mut walked = std::path::PathBuf::new();
        for (at, component) in components.iter().enumerate() {
            let parent = walked.clone();
            walked.push(component.as_os_str());
            if !matches!(component, std::path::Component::Normal(_))
                || !std::fs::symlink_metadata(&walked).is_ok_and(|m| m.file_type().is_symlink())
            {
                continue;
            }
            // Reported with `/` separators, like every other project path.
            let Some(walked_text) = walked.to_str().map(pathops::clean) else {
                break;
            };
            if links.contains(&walked_text) {
                break;
            }
            links.push(walked_text);
            followed += 1;
            let Some(target) = std::fs::read_link(&walked)
                .ok()
                .and_then(|t| t.to_str().map(str::to_string))
            else {
                break;
            };
            if followed > MAX_LINKS {
                return links;
            }
            // The target, resolved from the link's directory, followed by the rest of this path.
            let base = if pathops::is_abs(&target) {
                pathops::clean(&target)
            } else {
                pathops::join(&[parent.to_str().unwrap_or(""), &target])
            };
            let rest: std::path::PathBuf = components[at + 1..].iter().collect();
            pending.push(if rest.as_os_str().is_empty() {
                base
            } else {
                pathops::join(&[&base, &rest.to_string_lossy()])
            });
            break;
        }
    }
    links
}

/// Canonicalize a source path within `root`, which must be canonical. An
/// overlay may supply a new file only beneath an existing, confined directory.
pub fn source_path(root: &str, path: &str, overlay: &Overlay) -> Result<String, ProjectError> {
    let path = if pathops::is_abs(path) {
        path.to_string()
    } else {
        pathops::join(&[root, path])
    };
    let canonical = match pathops::eval_symlinks(&path) {
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
            let parent = pathops::eval_symlinks(&pathops::dir(&path))?;
            let canonical = pathops::join(&[&parent, &pathops::base(&path)]);
            if !(cfg!(windows) && overlay.contains_key(&path))
                && !overlay.contains_key(&pathops::clean(&path))
                && !overlay.contains_key(&canonical)
            {
                return Err(error);
            }
            canonical
        }
    };
    match pathops::rel(root, &canonical) {
        Ok(rel) if !pathops::escapes(&rel) => Ok(canonical),
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
