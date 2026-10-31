//! Test and source module discovery.

use std::collections::BTreeSet;

use crate::project::error::ProjectError;
use crate::project::manifest::Project;
use crate::project::overlay::Overlay;
use crate::project::pathops;

fn skipped_name(name: &str) -> bool {
    name.starts_with('.') || name == "vendor" || name == "node_modules"
}

fn is_test_name(name: &str) -> bool {
    is_test_name_bytes(name.as_bytes())
}

fn is_test_name_bytes(name: &[u8]) -> bool {
    name == b"test.ms"
        || name.ends_with(b"_test.ms")
        || name == b"bench.ms"
        || name.ends_with(b"_bench.ms")
}

/// `filepath.WalkDir` semantics: lexical order, symlinks are not followed
/// (a symlink is a non-directory entry), the root is `lstat`ed first.
fn walk(
    root: &str,
    include_source: bool,
    visit: &mut dyn FnMut(&str, &str, bool) -> bool,
) -> Result<(), ProjectError> {
    let meta =
        std::fs::symlink_metadata(root).map_err(|e| ProjectError::path("lstat", root, &e))?;
    walk_entry(
        root,
        &pathops::base(root),
        meta.is_dir(),
        include_source,
        visit,
    )
}

fn walk_entry(
    path: &str,
    name: &str,
    is_dir: bool,
    include_source: bool,
    visit: &mut dyn FnMut(&str, &str, bool) -> bool,
) -> Result<(), ProjectError> {
    // `visit` returns false to skip a directory.
    if !visit(path, name, is_dir) || !is_dir {
        return Ok(());
    }
    let read = std::fs::read_dir(path).map_err(|e| ProjectError::path("open", path, &e))?;
    let mut entries = Vec::new();
    for entry in read {
        let entry = entry.map_err(|e| ProjectError::path("readdirent", path, &e))?;
        let file_type = entry
            .file_type()
            .map_err(|e| ProjectError::path("lstat", path, &e))?;
        // A symlink to a directory is skipped, even when its name ends in `.ms`.
        let linked_dir =
            file_type.is_symlink() && std::fs::metadata(entry.path()).is_ok_and(|m| m.is_dir());
        if linked_dir {
            continue;
        }
        let native_name = entry.file_name();
        let Some(name) = native_name.to_str() else {
            let bytes = native_name.as_encoded_bytes();
            if file_type.is_dir() && bytes.starts_with(b".") {
                continue;
            }
            if !file_type.is_dir()
                && !(is_test_name_bytes(bytes) || (include_source && bytes.ends_with(b".ms")))
            {
                continue;
            }
            return Err(ProjectError::msg(format!(
                "discovered source path {:?} is not valid UTF-8; rename the file or directory using valid UTF-8",
                entry.path()
            )));
        };
        entries.push((name.to_string(), file_type.is_dir()));
    }
    entries.sort();
    for (child, child_is_dir) in entries {
        walk_entry(
            &pathops::join(&[path, &child]),
            &child,
            child_is_dir,
            include_source,
            visit,
        )?;
    }
    Ok(())
}

/// Find project `test.ms`, `*_test.ms`, `bench.ms` and `*_bench.ms` files. With `include_source`, also
/// every `.ms` file below the configured source directory. Hidden, `vendor`
/// and `node_modules` directories are skipped and directory symlinks are not
/// followed. Traversal errors are returned so callers cannot report a partial
/// scan as success.
pub fn discover_modules(
    project: &Project,
    include_source: bool,
) -> Result<Vec<String>, ProjectError> {
    let mut files = BTreeSet::new();
    let mut scan = |root: &str, all: bool| {
        walk(root, all, &mut |path, name, is_dir| {
            if is_dir {
                // The source walk already collected its tests and modules.
                if include_source && !all && path == project.source {
                    return false;
                }
                return !(path != root && skipped_name(name));
            }
            if (all && pathops::ext(name) == ".ms") || is_test_name(name) {
                files.insert(path.to_string());
            }
            true
        })
    };
    if include_source {
        scan(&project.source, true)?;
    }
    scan(&project.root, false)?;
    Ok(files.into_iter().collect())
}

/// Like [`discover_modules`], also including new editor files that meet the
/// same rules. Overlay keys must already be confined and canonicalized.
pub fn discover_modules_with_overlay(
    project: &Project,
    include_source: bool,
    overlay: &Overlay,
) -> Result<Vec<String>, ProjectError> {
    let files = discover_modules(project, include_source)?;
    if overlay.is_empty() {
        return Ok(files);
    }
    let mut seen: BTreeSet<String> = files.into_iter().collect();
    for file in overlay.keys() {
        let name = pathops::base(file);
        if (include_source
            && pathops::ext(&name) == ".ms"
            && discovered_below(&project.source, file))
            || (is_test_name(&name) && discovered_below(&project.root, file))
        {
            seen.insert(file.clone());
        }
    }
    Ok(seen.into_iter().collect())
}

fn discovered_below(root: &str, file: &str) -> bool {
    let Ok(rel) = pathops::rel(root, file) else {
        return false;
    };
    if pathops::escapes(&rel) || pathops::is_abs(&rel) {
        return false;
    }
    pathops::dir(&rel)
        .split('/')
        .all(|dir| dir == "." || !skipped_name(dir))
}
