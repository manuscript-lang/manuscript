//! Package dependencies: the lock file, the read-only package cache and the content hash.
//!
//! `ms fetch` (in `ms-cli`) is the only code that uses the network. Everything here reads the
//! lock and the cache, so a locked project builds offline.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use crate::project::error::ProjectError;
use crate::project::manifest::Project;
use crate::project::pathops;
use crate::sha256;

/// The most nested packages one project may pull in a chain.
const MAX_DEPTH: usize = 8;
/// The most bytes one package may hold.
const MAX_BYTES: u64 = 64 << 20;

/// A fetched package a project can import from.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Package {
    /// The path from the project in the lock file, such as `@pg` or `@pg/@wire`.
    pub key: String,
    /// The canonical cache directory holding the package files.
    pub root: String,
    /// The package's own manifest, with its dependencies resolved.
    pub project: Project,
}

/// One line of `ms.lock`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LockEntry {
    /// The manifest value, `url#tag`.
    pub spec: String,
    /// The full commit the tag pointed to.
    pub revision: String,
    /// The hash of the package files, lowercase hex.
    pub sha256: String,
}

/// The directory holding fetched packages, one subdirectory per content hash.
pub fn cache_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("MS_PACKAGE_CACHE").filter(|v| !v.is_empty()) {
        return PathBuf::from(dir);
    }
    let var = |name: &str| {
        std::env::var_os(name)
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
    };
    let base = if cfg!(windows) {
        var("LOCALAPPDATA")
    } else {
        None
    }
    .or_else(|| var("XDG_CACHE_HOME"))
    .or_else(|| var("HOME").map(|home| home.join(".cache")))
    .unwrap_or_else(std::env::temp_dir);
    base.join("ms").join("packages")
}

/// Parse `ms.lock`. A missing file is an empty lock.
pub fn read_lock(root: &str) -> Result<BTreeMap<String, LockEntry>, ProjectError> {
    let path = pathops::join(&[root, "ms.lock"]);
    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(BTreeMap::new()),
        Err(e) => return Err(ProjectError::path("open", &path, &e)),
    };
    let mut entries = BTreeMap::new();
    for (index, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let bad = || {
            ProjectError::msg(format!(
                "ms.lock line {} is not `\"@name\" = \"url#tag revision sha256:hash\"`; run ms fetch to rewrite it",
                index + 1
            ))
        };
        let (key, value) = line.split_once('=').ok_or_else(bad)?;
        let key = key.trim().trim_matches('"');
        let value = value.trim().trim_matches('"');
        let parts: Vec<&str> = value.split_whitespace().collect();
        let [spec, revision, hash] = parts[..] else {
            return Err(bad());
        };
        let hash = hash.strip_prefix("sha256:").ok_or_else(bad)?;
        entries.insert(
            key.to_string(),
            LockEntry {
                spec: spec.to_string(),
                revision: revision.to_string(),
                sha256: hash.to_string(),
            },
        );
    }
    Ok(entries)
}

/// The text of `ms.lock` for `entries`, in key order.
pub fn lock_text(entries: &BTreeMap<String, LockEntry>) -> String {
    let mut text = String::from(
        "# Written by `ms fetch`. Commit it: it pins each package to a commit and a content hash.\n",
    );
    for (key, e) in entries {
        text.push_str(&format!(
            "\"{key}\" = \"{} {} sha256:{}\"\n",
            e.spec, e.revision, e.sha256
        ));
    }
    text
}

/// The hash of the files under `dir`, ignoring a top-level `.git`: for each file in byte order of
/// its `/` path, the path, a zero byte, the length, a zero byte and the bytes.
pub fn hash_tree(dir: &Path) -> Result<String, ProjectError> {
    let mut files = BTreeSet::new();
    collect(dir, "", &mut files)?;
    let mut data = Vec::new();
    for relative in files {
        let path = dir.join(&relative);
        let bytes = std::fs::read(&path)
            .map_err(|e| ProjectError::path("read", &path.to_string_lossy(), &e))?;
        data.extend_from_slice(relative.as_bytes());
        data.push(0);
        data.extend_from_slice(bytes.len().to_string().as_bytes());
        data.push(0);
        data.extend_from_slice(&bytes);
        if data.len() as u64 > MAX_BYTES {
            return Err(ProjectError::msg(format!(
                "package is larger than {} MiB; a package holds source only",
                MAX_BYTES >> 20
            )));
        }
    }
    Ok(sha256::hex(&data))
}

fn collect(dir: &Path, prefix: &str, out: &mut BTreeSet<String>) -> Result<(), ProjectError> {
    let entries = std::fs::read_dir(dir)
        .map_err(|e| ProjectError::path("read directory", &dir.to_string_lossy(), &e))?;
    for entry in entries {
        let entry =
            entry.map_err(|e| ProjectError::path("read directory", &dir.to_string_lossy(), &e))?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            return Err(ProjectError::msg(format!(
                "package file name in {} is not valid UTF-8; rename it",
                dir.display()
            )));
        };
        if prefix.is_empty() && name == ".git" {
            continue;
        }
        let relative = format!("{prefix}{name}");
        let kind = entry
            .file_type()
            .map_err(|e| ProjectError::path("stat", &relative, &e))?;
        if kind.is_symlink() {
            return Err(ProjectError::msg(format!(
                "package contains the symbolic link {relative}; a package holds regular files only"
            )));
        }
        if kind.is_dir() {
            collect(&entry.path(), &format!("{relative}/"), out)?;
        } else {
            out.insert(relative);
        }
    }
    Ok(())
}

/// Whether the effect pattern `declared` is inside what the pattern `allowed` permits.
pub fn pattern_covers(allowed: &str, declared: &str) -> bool {
    if allowed == "*" || allowed == declared {
        return true;
    }
    if let Some(prefix) = allowed.strip_suffix(".*") {
        return declared == prefix || declared.starts_with(&format!("{prefix}."));
    }
    if let Some(suffix) = allowed.strip_prefix("*.") {
        return !declared.contains('*') && declared.ends_with(&format!(".{suffix}"));
    }
    false
}

/// An effect in `declared` that no pattern in `allowed` covers.
pub fn uncovered<'a>(allowed: &str, declared: &'a str) -> Option<&'a str> {
    declared
        .split_whitespace()
        .find(|d| !allowed.split_whitespace().any(|a| pattern_covers(a, d)))
}

static VERIFIED: OnceLock<Mutex<BTreeSet<String>>> = OnceLock::new();

/// Resolve every dependency of `project` through its lock and the cache, recursively.
pub fn attach(project: &mut Project) -> Result<(), ProjectError> {
    if project.dependencies.is_empty() {
        return Ok(());
    }
    let lock = read_lock(&project.root)?;
    let mut packages = Vec::new();
    resolve(project, "", &lock, &mut packages, &mut Vec::new())?;
    project.packages = packages;
    Ok(())
}

fn resolve(
    scope: &mut Project,
    prefix: &str,
    lock: &BTreeMap<String, LockEntry>,
    packages: &mut Vec<Package>,
    chain: &mut Vec<String>,
) -> Result<(), ProjectError> {
    if chain.len() >= MAX_DEPTH {
        return Err(ProjectError::msg(format!(
            "packages nest more than {MAX_DEPTH} deep at {prefix}"
        )));
    }
    let dependencies = scope.dependencies.clone();
    for (alias, spec) in dependencies {
        let key = format!("{prefix}{alias}");
        let entry = lock.get(&key).filter(|e| e.spec == spec).ok_or_else(|| {
            ProjectError::msg(format!(
                "ms.lock has no entry for {key} = {spec:?}; run `ms fetch` to resolve and pin it"
            ))
        })?;
        let directory = cache_dir().join(&entry.sha256);
        if !directory.is_dir() {
            return Err(ProjectError::msg(format!(
                "package {key} ({}) is not in the cache {}; run `ms fetch` to download it",
                entry.spec,
                directory.display()
            )));
        }
        verify(&directory, &entry.sha256, &key)?;
        let root = pathops::eval_symlinks(&directory.to_string_lossy())?;
        let manifest = pathops::join(&[&root, "ms.toml"]);
        let mut package = Project::default();
        crate::project::manifest::read_manifest(&manifest, &mut package)
            .map_err(|e| ProjectError::msg(format!("package {key}: {e}")))?;
        if !package.embed.is_empty() {
            return Err(ProjectError::msg(format!(
                "package {key} declares [embed]; a package holds source only"
            )));
        }
        if let Some(missing) = uncovered(
            scope.allowed_effects.get(&alias).map_or("", String::as_str),
            &package.effects,
        ) {
            return Err(ProjectError::msg(format!(
                "package {key} may use {missing}, which this project does not allow; add `{alias} = \"{missing}\"` under [effects] in ms.toml if you trust it"
            )));
        }
        scope.deps.insert(alias.clone(), package.source.clone());
        let sub = format!("{key}/");
        let nested = package.dependencies.clone();
        chain.push(entry.sha256.clone());
        if !nested.is_empty() {
            if chain[..chain.len() - 1].contains(&entry.sha256) {
                return Err(ProjectError::msg(format!(
                    "package {key} depends on itself"
                )));
            }
            resolve(&mut package, &sub, lock, packages, chain)?;
        }
        chain.pop();
        packages.push(Package {
            key,
            root,
            project: package,
        });
    }
    Ok(())
}

fn verify(directory: &Path, expected: &str, key: &str) -> Result<(), ProjectError> {
    let verified = VERIFIED.get_or_init(Default::default);
    let name = directory.to_string_lossy().into_owned();
    if verified.lock().is_ok_and(|v| v.contains(&name)) {
        return Ok(());
    }
    let actual = hash_tree(directory)?;
    if actual != expected {
        return Err(ProjectError::msg(format!(
            "package {key} in the cache does not match ms.lock (hash {actual}, locked {expected}); delete {} and run `ms fetch`",
            directory.display()
        )));
    }
    if let Ok(mut v) = verified.lock() {
        v.insert(name);
    }
    Ok(())
}
