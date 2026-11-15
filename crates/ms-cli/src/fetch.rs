//! `ms install`, `ms add` and `ms remove`: resolve `[dependencies]`, download them with `git`, and
//! write `ms.lock`. These are the only commands that use the network; every other command reads the lock and the
//! package cache.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::process::Command;

use ms_driver::project::edit::{
    Pin, add_dependency, allow_effects, default_name, remove_dependency,
};
use ms_driver::project::manifest::{Project, find_manifest, read_manifest};
use ms_driver::project::packages::{
    LockEntry, cache_dir, hash_index, index_path, index_tree, lock_text, read_lock,
};
use ms_driver::project::pathops;
use ms_driver::project::workspace;

use crate::backend::Io;

/// `ms install`: download what `[dependencies]` names and pin it in `ms.lock`.
pub fn run_install(args: &[String], io: &mut Io) -> i32 {
    report("install", install(args, io).map(|_| ()), io)
}

/// `ms add <url> --tag T | --sha S`: add a dependency to `ms.toml` and install it.
pub fn run_add(args: &[String], io: &mut Io) -> i32 {
    report("add", add(args, io), io)
}

/// `ms remove @name`: drop a dependency from `ms.toml` and `ms.lock`.
pub fn run_remove(args: &[String], io: &mut Io) -> i32 {
    report("remove", remove(args, io), io)
}

fn report(command: &str, result: Result<(), String>, io: &mut Io) -> i32 {
    match result {
        Ok(()) => 0,
        Err(message) => {
            let _ = writeln!(io.stderr, "ms {command}: {message}");
            1
        }
    }
}

struct Run<'a, 'b> {
    old: BTreeMap<String, LockEntry>,
    new: BTreeMap<String, LockEntry>,
    update: BTreeSet<String>,
    /// The effects each top-level package declares.
    declared: BTreeMap<String, Vec<String>>,
    /// Whether the member being walked is the project the command was run in.
    record: bool,
    io: &'a mut Io<'b>,
}

/// The nearest `ms.toml` from the working directory.
fn find_project() -> Result<String, String> {
    let here = std::env::current_dir().map_err(|e| e.to_string())?;
    find_manifest(&here.join("x").to_string_lossy())
        .ok_or_else(|| "no ms.toml here or above; run `ms init` first".to_string())
}

fn install(args: &[String], io: &mut Io<'_>) -> Result<BTreeMap<String, Vec<String>>, String> {
    let mut update = BTreeSet::new();
    let mut manifest = None;
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == "--update" {
            let name = iter
                .next()
                .ok_or("--update needs a package name such as @pg")?;
            update.insert(name.clone());
        } else if arg.starts_with('-') {
            return Err(format!("unknown option {arg}; see ms install --help"));
        } else {
            manifest = Some(arg.clone());
        }
    }
    let manifest = match manifest {
        Some(manifest) => manifest,
        None => find_project()?,
    };
    install_manifest(&manifest, update, io)
}

fn install_manifest(
    manifest: &str,
    update: BTreeSet<String>,
    io: &mut Io<'_>,
) -> Result<BTreeMap<String, Vec<String>>, String> {
    let mut project = Project::default();
    read_manifest(manifest, &mut project).map_err(|e| e.to_string())?;
    // A workspace installs every member and shares the lock at its root; lock keys start with
    // the member name so members may use one alias for different packages.
    let workspace = workspace::find(manifest).map_err(|e| e.to_string())?;
    let lock_root = workspace
        .as_ref()
        .map_or(project.root.clone(), |w| w.root.clone());
    let mut run = Run {
        old: read_lock(&lock_root).map_err(|e| e.to_string())?,
        new: BTreeMap::new(),
        update,
        declared: BTreeMap::new(),
        record: false,
        io,
    };
    match &workspace {
        None => {
            run.record = true;
            walk(&mut run, &project, "", 0)?;
        }
        Some(workspace) => {
            for member in &workspace.members {
                let mut scope = Project::default();
                read_manifest(&workspace::Workspace::manifest(member), &mut scope)
                    .map_err(|e| e.to_string())?;
                run.record = member.root == project.root;
                walk(&mut run, &scope, &format!("{}/", member.name), 0)?;
            }
        }
    }
    for name in &run.update {
        if !run
            .new
            .keys()
            .any(|k| k == name || k.ends_with(&format!("/{name}")))
        {
            return Err(format!("--update {name}: no such dependency"));
        }
    }
    let path = pathops::join(&[&lock_root, "ms.lock"]);
    let text = lock_text(&run.new);
    if run.new.is_empty() {
        let _ = std::fs::remove_file(&path);
    } else if std::fs::read_to_string(&path).ok().as_deref() != Some(&text) {
        std::fs::write(&path, text).map_err(|e| format!("write {path}: {e}"))?;
    }
    Ok(run.declared)
}

fn add(args: &[String], io: &mut Io<'_>) -> Result<(), String> {
    let (mut url, mut pin, mut name, mut allow) = (None, None, None, false);
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        let mut value = |what: &str| {
            iter.next()
                .cloned()
                .ok_or_else(|| format!("{arg} needs {what}"))
        };
        match arg.as_str() {
            "--tag" => pin = Some((false, value("a tag")?)),
            "--sha" => pin = Some((true, value("a full commit")?)),
            "--as" => name = Some(value("a package name such as @pg")?),
            "--allow" => allow = true,
            _ if arg.starts_with('-') => {
                return Err(format!("unknown option {arg}; see ms add --help"));
            }
            _ if url.is_none() => url = Some(arg.clone()),
            _ => return Err("one repository URL at a time".to_string()),
        }
    }
    let url = url.ok_or("name a repository URL: ms add <url> --tag <tag>")?;
    let (sha, reference) = pin.ok_or("name the version: --tag <tag> or --sha <full commit>")?;
    let name = match name {
        Some(name) => name,
        None => default_name(&url).ok_or_else(|| {
            format!("cannot make a package name from {url}; give one with --as @name")
        })?,
    };
    let manifest = find_project()?;
    not_a_workspace_root(&manifest, "add")?;
    let original =
        std::fs::read_to_string(&manifest).map_err(|e| format!("read {manifest}: {e}"))?;
    let pin = if sha {
        Pin::Sha(&reference)
    } else {
        Pin::Tag(&reference)
    };
    let edited = add_dependency(&original, &name, &url, &pin)?;
    std::fs::write(&manifest, &edited).map_err(|e| format!("write {manifest}: {e}"))?;
    let declared = match install_manifest(&manifest, BTreeSet::new(), io) {
        Ok(declared) => declared,
        Err(message) => {
            // A dependency that cannot be installed is not left in the manifest.
            let _ = std::fs::write(&manifest, &original);
            return Err(message);
        }
    };
    let effects = declared.get(&name).cloned().unwrap_or_default();
    if effects.is_empty() {
        return Ok(());
    }
    if allow {
        let allowed = allow_effects(&edited, &name, &effects)?;
        std::fs::write(&manifest, allowed).map_err(|e| format!("write {manifest}: {e}"))?;
        let _ = writeln!(io.stdout, "{name} is allowed {}", effects.join(" "));
    } else {
        let list = effects
            .iter()
            .map(|e| format!("{e:?}"))
            .collect::<Vec<_>>()
            .join(", ");
        let _ = writeln!(
            io.stdout,
            "{name} declares effects. Allow them to build: add to [effects]\n  {name:?} = [{list}]\nor run `ms add --allow` next time."
        );
    }
    Ok(())
}

/// A workspace root without `[project]` has no dependencies of its own to edit.
fn not_a_workspace_root(manifest: &str, command: &str) -> Result<(), String> {
    match workspace::root_members(manifest).map_err(|e| e.to_string())? {
        Some(_) => Err(format!(
            "{manifest} is a workspace root, which has no dependencies of its own; run `ms {command}` inside a member directory"
        )),
        None => Ok(()),
    }
}

fn remove(args: &[String], io: &mut Io<'_>) -> Result<(), String> {
    let [name] = args else {
        return Err("name one package: ms remove @name".to_string());
    };
    let manifest = find_project()?;
    not_a_workspace_root(&manifest, "remove")?;
    let original =
        std::fs::read_to_string(&manifest).map_err(|e| format!("read {manifest}: {e}"))?;
    let edited = remove_dependency(&original, name)?;
    std::fs::write(&manifest, &edited).map_err(|e| format!("write {manifest}: {e}"))?;
    if let Err(message) = install_manifest(&manifest, BTreeSet::new(), io) {
        let _ = std::fs::write(&manifest, &original);
        return Err(message);
    }
    let _ = writeln!(io.stdout, "removed {name}");
    Ok(())
}

fn walk(run: &mut Run<'_, '_>, scope: &Project, prefix: &str, depth: usize) -> Result<(), String> {
    if depth >= 8 {
        return Err(format!("packages nest more than 8 deep at {prefix}"));
    }
    for (alias, spec) in &scope.dependencies {
        let key = format!("{prefix}{alias}");
        if depth > 0 && !spec.starts_with("https://") {
            return Err(format!(
                "package {} depends on {key} = {spec:?}; a package's own dependencies must use https:// URLs, because file:// reads the machine running ms fetch",
                prefix.trim_end_matches('/')
            ));
        }
        let locked = run
            .old
            .get(&key)
            .filter(|e| {
                &e.spec == spec && !run.update.contains(alias) && !run.update.contains(&key)
            })
            .cloned();
        let entry = match locked {
            Some(entry) => {
                let directory = cache_dir().join(&entry.sha256);
                if !directory.is_dir() || !index_path(&cache_dir(), &entry.sha256).is_file() {
                    download(&key, spec, Some(&entry), depth > 0)?;
                }
                entry
            }
            None => download(&key, spec, None, depth > 0)?,
        };
        let directory = cache_dir().join(&entry.sha256);
        let mut package = Project::default();
        read_manifest(
            &pathops::join(&[&directory.to_string_lossy(), "ms.toml"]),
            &mut package,
        )
        .map_err(|e| format!("package {key}: {e}"))?;
        let effects = if package.effects.is_empty() {
            "none".to_string()
        } else {
            package.effects.join(" ")
        };
        if depth == 0 && run.record {
            run.declared.insert(alias.clone(), package.effects.clone());
        }
        let _ = writeln!(
            run.io.stdout,
            "{key} {spec} {} (effects: {effects})",
            &entry.revision[..12.min(entry.revision.len())]
        );
        run.new.insert(key.clone(), entry);
        walk(run, &package, &format!("{key}/"), depth + 1)?;
    }
    Ok(())
}

/// Run git without prompts and with only the transports a package may use: `https` always, and
/// `file` for the project's own dependencies.
fn git(directory: Option<&Path>, protocols: &str, args: &[&str]) -> Result<String, String> {
    let mut command = Command::new("git");
    command
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_ALLOW_PROTOCOL", protocols);
    command.args([
        "-c",
        "core.autocrlf=false",
        "-c",
        "core.safecrlf=false",
        "-c",
        "advice.detachedHead=false",
    ]);
    if let Some(directory) = directory {
        command.arg("-C").arg(directory);
    }
    let output = command
        .args(args)
        .stdin(std::process::Stdio::null())
        .output()
        .map_err(|e| format!("cannot run git ({e}); install git and put it on PATH"))?;
    if !output.status.success() {
        return Err(format!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn is_commit(text: &str) -> bool {
    ms_driver::project::packages::is_hex(text, 40)
}

/// Download `spec` into the cache. With a lock entry it fetches exactly that revision and checks
/// its hash; otherwise it resolves the tag.
fn download(
    key: &str,
    spec: &str,
    locked: Option<&LockEntry>,
    nested: bool,
) -> Result<LockEntry, String> {
    let protocols = if nested { "https" } else { "https:file" };
    let (url, reference) = spec.split_once('#').ok_or("dependency needs url#tag")?;
    let root = cache_dir();
    std::fs::create_dir_all(&root).map_err(|e| format!("create {}: {e}", root.display()))?;
    let temporary = root.join(format!(".tmp-{}", std::process::id()));
    let _ = remove_all(&temporary);
    std::fs::create_dir_all(&temporary)
        .map_err(|e| format!("create {}: {e}", temporary.display()))?;
    let result = download_into(key, url, reference, locked, &temporary, &root, protocols);
    let _ = remove_all(&temporary);
    result.map(|mut entry| {
        entry.spec = spec.to_string();
        entry
    })
}

fn download_into(
    key: &str,
    url: &str,
    reference: &str,
    locked: Option<&LockEntry>,
    temporary: &Path,
    root: &Path,
    protocols: &str,
) -> Result<LockEntry, String> {
    git(Some(temporary), protocols, &["init", "--quiet"])?;
    git(
        Some(temporary),
        protocols,
        &["remote", "add", "--", "origin", url],
    )?;
    if let Some(entry) = locked {
        git(
            Some(temporary),
            protocols,
            &[
                "fetch",
                "--quiet",
                "--depth",
                "1",
                "--",
                "origin",
                &entry.revision,
            ],
        )
        .map_err(|e| format!("package {key}: {e}"))?;
    } else if is_commit(reference) {
        git(
            Some(temporary),
            protocols,
            &[
                "fetch", "--quiet", "--depth", "1", "--", "origin", reference,
            ],
        )
        .map_err(|e| format!("package {key}: {e}"))?;
    } else {
        let tag = format!("refs/tags/{reference}");
        git(
            Some(temporary),
            protocols,
            &[
                "fetch",
                "--quiet",
                "--depth",
                "1",
                "--",
                "origin",
                &format!("{tag}:{tag}"),
            ],
        )
        .map_err(|e| format!("package {key}: {reference} is not a tag of {url}? {e}"))?;
    }
    let revision = if locked.is_some() || is_commit(reference) {
        "FETCH_HEAD".to_string()
    } else {
        format!("refs/tags/{reference}^{{commit}}")
    };
    let commit = git(
        Some(temporary),
        protocols,
        &["rev-parse", "--verify", &revision],
    )?
    .trim()
    .to_string();
    git(
        Some(temporary),
        protocols,
        &["checkout", "--quiet", "--force", &commit, "--"],
    )?;
    remove_all(&temporary.join(".git"))?;
    let index = index_tree(temporary).map_err(|e| format!("package {key}: {e}"))?;
    let hash = hash_index(&index);
    if let Some(entry) = locked
        && entry.sha256 != hash
    {
        return Err(format!(
            "package {key} at {} no longer matches ms.lock (locked {}, got {hash}); the source changed, so review it and run `ms fetch --update {key}` if you trust it",
            entry.revision, entry.sha256
        ));
    }
    validate(key, temporary)?;
    let destination = root.join(&hash);
    if !destination.is_dir() {
        std::fs::rename(temporary, &destination)
            .map_err(|e| format!("store {}: {e}", destination.display()))?;
        read_only(&destination);
    }
    let index_file = index_path(root, &hash);
    if !index_file.is_file() {
        std::fs::write(&index_file, &index)
            .map_err(|e| format!("write {}: {e}", index_file.display()))?;
    }
    Ok(LockEntry {
        spec: String::new(),
        revision: commit,
        sha256: hash,
    })
}

/// A package is a library with a manifest, no entry, no embedded files and no top-level `@`
/// directory (which would look like a nested package in diagnostics). The checker enforces
/// everything about its source: no native declarations, and no effect beyond `effects`.
fn validate(key: &str, dir: &Path) -> Result<(), String> {
    let manifest = dir.join("ms.toml");
    if !manifest.is_file() {
        return Err(format!("package {key} has no ms.toml at its root"));
    }
    let mut package = Project::default();
    read_manifest(&manifest.to_string_lossy(), &mut package)
        .map_err(|e| format!("package {key}: {e}"))?;
    if !package.entry.is_empty() {
        return Err(format!(
            "package {key} has an entry; a package is a library, so remove entry"
        ));
    }
    if !package.embed.is_empty() {
        return Err(format!(
            "package {key} declares [embed]; a package holds source only"
        ));
    }
    let entries = std::fs::read_dir(dir).map_err(|e| format!("read {}: {e}", dir.display()))?;
    for entry in entries.flatten() {
        if entry.file_name().to_string_lossy().starts_with('@') {
            return Err(format!(
                "package {key} has a top-level {:?}; rename it, names starting with @ are reserved for packages",
                entry.file_name()
            ));
        }
    }
    Ok(())
}

fn read_only(dir: &Path) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                read_only(&path);
            } else if let Ok(meta) = std::fs::metadata(&path) {
                let mut permissions = meta.permissions();
                permissions.set_readonly(true);
                let _ = std::fs::set_permissions(&path, permissions);
            }
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o555));
    }
}

/// Remove a directory tree even when git made some files read-only.
fn remove_all(dir: &Path) -> Result<(), String> {
    if !dir.exists() {
        return Ok(());
    }
    fn writable(dir: &Path) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    writable(&path);
                } else if let Ok(meta) = std::fs::metadata(&path) {
                    let mut permissions = meta.permissions();
                    #[allow(clippy::permissions_set_readonly_false)]
                    permissions.set_readonly(false);
                    let _ = std::fs::set_permissions(&path, permissions);
                }
            }
        }
    }
    writable(dir);
    std::fs::remove_dir_all(dir).map_err(|e| format!("remove {}: {e}", dir.display()))
}

pub const HELP_INSTALL: &str = r#"Usage: ms install [--update @name]... [ms.toml]

Download the packages under [dependencies] with git and pin them in ms.lock.
Without a lock entry it resolves the tag to a commit and records the commit and a
content hash. With a lock entry it downloads exactly that commit and fails if the
content hash differs. Packages are cached read-only outside the project
(MS_PACKAGE_CACHE overrides the location). Every other command works offline from
the lock and the cache.

Options:
  --update @name  Resolve that package's tag again and rewrite its lock entry
  -h, --help      Show this help
"#;

pub const HELP_ADD: &str = r#"Usage: ms add <url> (--tag <tag> | --sha <commit>) [--as @name] [--allow]

Add a git dependency to ms.toml and install it. The package name defaults to the
repository name without a leading ms- (https://github.com/acme/ms-pg.git is @pg).
The package declares the effects it may use; ms prints them, and --allow writes
them under [effects] so the project accepts them.

Options:
  --tag <tag>     The tag to depend on
  --sha <commit>  The full 40-digit commit to depend on
  --as @name      The name imports use (@name/file.ms)
  --allow         Allow the effects the package declares
  -h, --help      Show this help
"#;

pub const HELP_REMOVE: &str = r#"Usage: ms remove @name

Remove a dependency from [dependencies] and [effects] in ms.toml and from ms.lock.
The cached copy stays in the package cache.

Options:
  -h, --help  Show this help
"#;
