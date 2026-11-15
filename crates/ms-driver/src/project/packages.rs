//! Package dependencies: the lock file, the read-only package cache and the content hash.
//!
//! `ms install` (in `ms-cli`) is the only code that uses the network. Everything here reads the
//! lock and the cache, so a locked project builds offline.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

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
    /// The manifest value the lock pinned, `url#tag`.
    pub spec: String,
    /// The canonical cache directory holding the package files.
    pub root: String,
    /// The package's own manifest, with its dependencies resolved.
    pub project: Project,
    /// The expected SHA-256 of each file by `/` path, from the verified index.
    pub files: BTreeMap<String, String>,
    /// A workspace member: its files are the project's own, so they are not hashed or locked
    /// and may declare natives.
    pub member: bool,
}

/// A workspace member name as the first part of a lock key: ASCII letters, digits, `_`, `-`.
fn is_member_name(text: &str) -> bool {
    !text.is_empty()
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Whether `text` is `len` lowercase hexadecimal digits.
pub fn is_hex(text: &str, len: usize) -> bool {
    text.len() == len
        && text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// A dependency value is `url#tag`: an `https://` or `file://` URL, never one that starts with
/// `-` or names another git transport, and a tag or commit that is not an option or a path.
/// Nested packages may use `https://` only; `ms install` checks that where the depth is known.
pub fn check_spec(spec: &str) -> Result<(), String> {
    let bad = || {
        format!(
            "invalid dependency {spec:?}; write \"<git url>#<tag or commit>\", for example \"https://github.com/acme/pg.git#v1.0.0\""
        )
    };
    let (url, tag) = spec.split_once('#').ok_or_else(bad)?;
    if url.is_empty()
        || tag.is_empty()
        || spec.contains(char::is_whitespace)
        || spec.chars().any(char::is_control)
    {
        return Err(bad());
    }
    if !(url.starts_with("https://") || url.starts_with("file://")) {
        return Err(format!(
            "dependency URL {url:?} must start with https:// (or file:// for a local repository); other git transports are not supported"
        ));
    }
    if tag.starts_with('-')
        || tag.contains("..")
        || tag.contains(['~', '^', ':', '?', '*', '[', '\\'])
        || tag.starts_with('/')
        || tag.ends_with('/')
    {
        return Err(format!(
            "dependency tag {tag:?} is not a plain tag name or full commit"
        ));
    }
    Ok(())
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
                "ms.lock line {} is not `\"@name\" = \"url#tag revision sha256:hash\"`; run ms install to rewrite it",
                index + 1
            ))
        };
        let (key, value) = line.split_once('=').ok_or_else(bad)?;
        let key = key.trim().trim_matches('"');
        if key.is_empty()
            || !key.split('/').enumerate().all(|(i, part)| {
                crate::project::manifest::valid_alias(part) || (i == 0 && is_member_name(part))
            })
        {
            return Err(bad());
        }
        let value = value.trim().trim_matches('"');
        let parts: Vec<&str> = value.split_whitespace().collect();
        let [spec, revision, hash] = parts[..] else {
            return Err(bad());
        };
        let hash = hash.strip_prefix("sha256:").ok_or_else(bad)?;
        if !is_hex(revision, 40) || !is_hex(hash, 64) {
            return Err(ProjectError::msg(format!(
                "ms.lock line {} must hold a 40-digit commit and a 64-digit sha256, both lowercase hexadecimal; run ms install to rewrite it",
                index + 1
            )));
        }
        check_spec(spec)
            .map_err(|why| ProjectError::msg(format!("ms.lock line {}: {why}", index + 1)))?;
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
        "# Written by `ms install`. Commit it: it pins each package to a commit and a content hash.\n",
    );
    for (key, e) in entries {
        text.push_str(&format!(
            "\"{key}\" = \"{} {} sha256:{}\"\n",
            e.spec, e.revision, e.sha256
        ));
    }
    text
}

/// The index of the files under `dir`, ignoring a top-level `.git`: one line per file in byte
/// order of its `/` path, holding the path, a zero byte and the SHA-256 of its bytes. Its own
/// SHA-256 is the package hash, so a file read later is checked against its line alone.
pub fn index_tree(dir: &Path) -> Result<String, ProjectError> {
    let mut files = BTreeSet::new();
    collect(dir, "", &mut files)?;
    let mut index = String::new();
    let mut total = 0u64;
    for relative in files {
        let path = dir.join(&relative);
        let bytes = std::fs::read(&path)
            .map_err(|e| ProjectError::path("read", &path.to_string_lossy(), &e))?;
        total += bytes.len() as u64;
        if total > MAX_BYTES {
            return Err(ProjectError::msg(format!(
                "package is larger than {} MiB; a package holds source only",
                MAX_BYTES >> 20
            )));
        }
        index.push_str(&format!("{relative}\0{}\n", sha256::hex(&bytes)));
    }
    Ok(index)
}

/// The package hash: the SHA-256 of the index.
pub fn hash_index(index: &str) -> String {
    sha256::hex(index.as_bytes())
}

/// Where the index of the package with hash `hash` is stored, beside its directory.
pub fn index_path(cache: &Path, hash: &str) -> PathBuf {
    cache.join(format!("{hash}.index"))
}

fn parse_index(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|l| l.split_once('\0'))
        .map(|(path, hash)| (path.to_string(), hash.to_string()))
        .collect()
}

/// Whether `bytes`, read from `relative` in this package, are what the lock pinned.
pub fn verify_file(package: &Package, relative: &str, bytes: &[u8]) -> Result<(), ProjectError> {
    if package.member {
        return Ok(());
    }
    match package.files.get(relative) {
        Some(expected) if *expected == sha256::hex(bytes) => Ok(()),
        Some(_) => Err(ProjectError::msg(format!(
            "{}/{relative} in the cache does not match ms.lock; delete {} and run `ms install`",
            package.key, package.root
        ))),
        None => Err(ProjectError::msg(format!(
            "{}/{relative} is not in the locked package; delete {} and run `ms install`",
            package.key, package.root
        ))),
    }
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
pub fn uncovered<'a>(allowed: &[String], declared: &'a [String]) -> Option<&'a str> {
    declared
        .iter()
        .find(|d| !allowed.iter().any(|a| pattern_covers(a, d)))
        .map(String::as_str)
}

/// Resolve every dependency of `project` through its lock and the cache, recursively.
pub fn attach(project: &mut Project) -> Result<(), ProjectError> {
    attach_in(project, &cache_dir())
}

fn attach_in(project: &mut Project, cache: &Path) -> Result<(), ProjectError> {
    if project.dependencies.is_empty() && project.path_dependencies.is_empty() {
        return Ok(());
    }
    let workspace = crate::project::workspace::find(&pathops::join(&[&project.root, "ms.toml"]))?;
    // Package files are named `@name/...`; a project path with that spelling would be mistaken
    // for package code.
    for alias in project
        .dependencies
        .keys()
        .chain(project.path_dependencies.keys())
    {
        if Path::new(&project.root).join(alias).exists() {
            return Err(ProjectError::msg(format!(
                "the project has a file or directory named {alias}, which is also a dependency name; rename it, names starting with @ are reserved for packages"
            )));
        }
    }
    // A workspace shares the lock at its root, and its keys start with the member name so two
    // members may use the same alias for different packages.
    let lock = read_lock(workspace.as_ref().map_or(&project.root, |w| &w.root))?;
    let lock_prefix = workspace
        .as_ref()
        .map_or(String::new(), |_| format!("{}/", project.name));
    let mut packages = Vec::new();
    let mut resolver = Resolver {
        workspace: workspace.as_ref(),
        lock: &lock,
        cache,
        packages: &mut packages,
        chain: Vec::new(),
        members: vec![project.root.clone()],
    };
    resolver.resolve(project, "", &lock_prefix)?;
    project.packages = packages;
    Ok(())
}

struct Resolver<'a> {
    workspace: Option<&'a crate::project::workspace::Workspace>,
    lock: &'a BTreeMap<String, LockEntry>,
    cache: &'a Path,
    packages: &'a mut Vec<Package>,
    chain: Vec<String>,
    /// The workspace members on the path from the project, to catch cycles.
    members: Vec<String>,
}

impl Resolver<'_> {
    /// Resolves the path dependencies of `scope`, then its git dependencies.
    fn resolve(
        &mut self,
        scope: &mut Project,
        prefix: &str,
        lock_prefix: &str,
    ) -> Result<(), ProjectError> {
        self.members_of(scope, prefix)?;
        resolve(
            scope,
            prefix,
            lock_prefix,
            self.lock,
            self.cache,
            self.packages,
            &mut self.chain,
        )
    }

    fn members_of(&mut self, scope: &mut Project, prefix: &str) -> Result<(), ProjectError> {
        let dependencies = scope.path_dependencies.clone();
        for (alias, dir) in dependencies {
            let key = format!("{prefix}{alias}");
            let Some(workspace) = self.workspace else {
                return Err(ProjectError::msg(format!(
                    "{key} is a path dependency, but no ancestor ms.toml has [workspace] members listing this project; add a workspace root or use a url dependency"
                )));
            };
            let Some(member) = workspace.member_at(&dir) else {
                return Err(ProjectError::msg(format!(
                    "{key} points at {dir}, which is not a workspace member; list it under [workspace] members in {}/ms.toml",
                    workspace.root
                )));
            };
            if self.members.contains(&member.root) {
                return Err(ProjectError::msg(format!(
                    "workspace member {} depends on itself through {key}; members cannot form a cycle",
                    member.name
                )));
            }
            let mut package = Project::default();
            crate::project::manifest::read_manifest(
                &crate::project::workspace::Workspace::manifest(member),
                &mut package,
            )
            .map_err(|e| ProjectError::msg(format!("package {key}: {e}")))?;
            check_effects(scope, &alias, &key, prefix, &package)?;
            scope.deps.insert(alias.clone(), package.source.clone());
            self.members.push(member.root.clone());
            let result = self.resolve(
                &mut package,
                &format!("{key}/"),
                &format!("{}/", member.name),
            );
            self.members.pop();
            result?;
            self.packages.push(Package {
                key,
                spec: format!("workspace member {}", member.name),
                root: member.root.clone(),
                project: package,
                files: BTreeMap::new(),
                member: true,
            });
        }
        Ok(())
    }
}

/// What a project allows a dependency, and what a package may hand on.
fn check_effects(
    scope: &Project,
    alias: &str,
    key: &str,
    prefix: &str,
    package: &Project,
) -> Result<(), ProjectError> {
    if let Some(missing) = uncovered(
        scope
            .allowed_effects
            .get(alias)
            .map_or(&[][..], Vec::as_slice),
        &package.effects,
    ) {
        return Err(ProjectError::msg(format!(
            "package {key} may use {missing}, which this project does not allow; add `{alias} = [\"{missing}\"]` under [effects] in ms.toml if you trust it"
        )));
    }
    if !prefix.is_empty()
        && let Some(missing) = uncovered(&scope.effects, &package.effects)
    {
        return Err(ProjectError::msg(format!(
            "package {key} may use {missing}, but {} declares only {:?}; a package cannot hand a dependency effects it does not have itself",
            prefix.trim_end_matches('/'),
            scope.effects
        )));
    }
    Ok(())
}

fn resolve(
    scope: &mut Project,
    prefix: &str,
    lock_prefix: &str,
    lock: &BTreeMap<String, LockEntry>,
    cache: &Path,
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
        let lock_key = format!("{lock_prefix}{alias}");
        let entry = lock.get(&lock_key).filter(|e| e.spec == spec).ok_or_else(|| {
            ProjectError::msg(format!(
                "ms.lock has no entry for {lock_key} = {spec:?}; run `ms install` to resolve and pin it"
            ))
        })?;
        let directory = cache.join(&entry.sha256);
        if !directory.is_dir() {
            return Err(ProjectError::msg(format!(
                "package {key} ({}) is not in the cache {}; run `ms install` to download it",
                entry.spec,
                directory.display()
            )));
        }
        let files = read_index(cache, &directory, &entry.sha256, &key)?;
        let root = pathops::eval_symlinks(&directory.to_string_lossy())?;
        let manifest = pathops::join(&[&root, "ms.toml"]);
        let manifest_text =
            std::fs::read(&manifest).map_err(|e| ProjectError::path("open", &manifest, &e))?;
        let package_check = Package {
            key: key.clone(),
            root: root.clone(),
            files: files.clone(),
            ..Package::default()
        };
        verify_file(&package_check, "ms.toml", &manifest_text)?;
        let mut package = Project::default();
        crate::project::manifest::read_manifest(&manifest, &mut package)
            .map_err(|e| ProjectError::msg(format!("package {key}: {e}")))?;
        if !package.embed.is_empty() {
            return Err(ProjectError::msg(format!(
                "package {key} declares [embed]; a package holds source only"
            )));
        }
        if !package.path_dependencies.is_empty() || package.members.is_some() {
            return Err(ProjectError::msg(format!(
                "package {key} uses a path dependency or [workspace]; only a project's own workspace members can, a fetched package depends on url packages"
            )));
        }
        check_effects(scope, &alias, &key, prefix, &package)?;
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
            resolve(
                &mut package,
                &sub,
                &format!("{lock_key}/"),
                lock,
                cache,
                packages,
                chain,
            )?;
        }
        chain.pop();
        packages.push(Package {
            key,
            spec: entry.spec.clone(),
            root,
            project: package,
            files,
            member: false,
        });
    }
    Ok(())
}

/// Reads the stored index and checks it is the one the lock names, then checks the manifest.
fn read_index(
    cache: &Path,
    directory: &Path,
    hash: &str,
    key: &str,
) -> Result<BTreeMap<String, String>, ProjectError> {
    let path = index_path(cache, hash);
    let text = std::fs::read_to_string(&path)
        .map_err(|e| ProjectError::path("open", &path.to_string_lossy(), &e))?;
    if hash_index(&text) != hash {
        return Err(ProjectError::msg(format!(
            "the index of package {key} does not match ms.lock; delete {} and {} and run `ms install`",
            directory.display(),
            path.display()
        )));
    }
    Ok(parse_index(&text))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const COMMIT: &str = "0123456789abcdef0123456789abcdef01234567";

    fn lock(line: &str) -> Result<BTreeMap<String, LockEntry>, ProjectError> {
        let dir =
            std::env::temp_dir().join(format!("ms-lock-{}-{}", std::process::id(), line.len()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("ms.lock"), line).unwrap();
        read_lock(dir.to_str().unwrap())
    }

    #[test]
    fn a_well_formed_lock_line_is_read() {
        let text = format!("\"@pg/@wire\" = \"https://h/x.git#v1 {COMMIT} sha256:{HASH}\"\n");
        assert_eq!(lock(&text).unwrap()["@pg/@wire"].revision, COMMIT);
    }

    #[test]
    fn lock_lines_that_could_reach_git_as_options_are_rejected() {
        for bad in [
            format!("\"@pg\" = \"https://h/x.git#v1 --upload-pack=touch_x sha256:{HASH}\"\n"),
            format!(
                "\"@pg\" = \"https://h/x.git#v1 {} sha256:{HASH}\"\n",
                &COMMIT[..39]
            ),
            format!(
                "\"@pg\" = \"https://h/x.git#v1 {COMMIT} sha256:{}\"\n",
                &HASH[..63]
            ),
            format!(
                "\"@pg\" = \"https://h/x.git#v1 {} sha256:{HASH}\"\n",
                COMMIT.to_uppercase()
            ),
            format!("\"@pg\" = \"-oProxyCommand=x#v1 {COMMIT} sha256:{HASH}\"\n"),
            format!("\"@pg\" = \"ext::sh -c x#v1 {COMMIT} sha256:{HASH}\"\n"),
            format!("\"../x\" = \"https://h/x.git#v1 {COMMIT} sha256:{HASH}\"\n"),
        ] {
            assert!(lock(&bad).is_err(), "{bad}");
        }
    }

    /// Stores a package with `manifest` and returns its lock entry.
    fn stored(cache: &Path, manifest: &str) -> LockEntry {
        let scratch = cache.join("scratch");
        let _ = std::fs::remove_dir_all(&scratch);
        std::fs::create_dir_all(scratch.join("src")).unwrap();
        std::fs::write(scratch.join("ms.toml"), manifest).unwrap();
        let index = index_tree(&scratch).unwrap();
        let sha256 = hash_index(&index);
        std::fs::write(index_path(cache, &sha256), index).unwrap();
        std::fs::rename(&scratch, cache.join(&sha256)).unwrap();
        LockEntry {
            spec: "https://h/x.git#v1".into(),
            revision: COMMIT.into(),
            sha256,
        }
    }

    #[test]
    fn a_package_cannot_hand_its_dependency_effects_it_lacks() {
        let root = std::env::temp_dir().join(format!("ms-nested-{}", std::process::id()));
        let cache = root.join("cache");
        let project_dir = root.join("app");
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(project_dir.join("src")).unwrap();
        let header = "[project]\nname = \"p\"\nsource = \"src\"\n";
        let inner = stored(&cache, &format!("{header}effects = [\"std.net.*\"]\n"));
        let outer_manifest = format!(
            "{header}\n[dependencies]\n\"@inner\" = {{ url = \"https://h/x.git\", tag = \"v1\" }}\n\n[effects]\n\"@inner\" = [\"std.net.*\"]\n"
        );
        let outer = stored(&cache, &outer_manifest);
        let lock = BTreeMap::from([
            ("@outer".to_string(), outer),
            ("@outer/@inner".to_string(), inner),
        ]);
        std::fs::write(project_dir.join("ms.lock"), lock_text(&lock)).unwrap();
        std::fs::write(
            project_dir.join("ms.toml"),
            "[project]\nname = \"a\"\nsource = \"src\"\n\n[dependencies]\n\"@outer\" = { url = \"https://h/x.git\", tag = \"v1\" }\n\n[effects]\n\"@outer\" = [\"std.net.*\"]\n",
        )
        .unwrap();
        let mut project = Project::default();
        crate::project::manifest::read_manifest(
            project_dir.join("ms.toml").to_str().unwrap(),
            &mut project,
        )
        .unwrap();
        let error = attach_in(&mut project, &cache).unwrap_err().to_string();
        assert!(
            error.contains("cannot hand a dependency effects"),
            "{error}"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn dependency_values_reject_options_and_other_transports() {
        for bad in [
            "-oX#v1",
            "ext::sh -c x#v1",
            "ssh://h/x#v1",
            "/etc#v1",
            "https://h/x.git#--upload-pack=x",
            "https://h/x.git#a..b",
            "https://h/x.git",
        ] {
            assert!(check_spec(bad).is_err(), "{bad}");
        }
        assert!(check_spec("https://h/x.git#v1.0.0").is_ok());
        assert!(check_spec("file:///tmp/x#v1").is_ok());
    }
}
