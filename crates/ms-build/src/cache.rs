//! Build cache: a finished executable is reused while the files it came from are unchanged.
//!
//! An entry is keyed by the cheap facts of a build (profile, output, working directory, codegen
//! environment variables, the `ms` executable's and runtime's size and modification time). Its
//! manifest lists every source file with the size and modification time it had; the entry is
//! valid while all of them still match. Source contents are not read or hashed; project requests
//! resolve the manifest's entry before lookup. A hit skips the source front end.
//! `MS_CACHE=off` skips the cache; `MS_CACHE=verify` rebuilds and compares.
//!
//! A new file that would shadow an imported one (a different resolution of the same import) is
//! not noticed until some listed file changes; `MS_CACHE=off` or deleting `.ms-cache` covers it.

use crate::Backend;
use ms_clif::BuildOptions;
use std::fmt::Write as _;
use std::hash::{DefaultHasher, Hasher};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

/// How the cache is used for one build.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Off,
    On,
    Verify,
}

pub fn mode() -> Mode {
    match std::env::var("MS_CACHE").as_deref() {
        Ok("off" | "0") => Mode::Off,
        Ok("verify") => Mode::Verify,
        _ => Mode::On,
    }
}

/// A file's modification time (nanoseconds since the epoch) and size.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Stamp {
    pub mtime: u128,
    pub size: u64,
}

pub fn stamp(path: &Path) -> Option<Stamp> {
    let meta = std::fs::metadata(path).ok()?;
    // Directories are stamped too: an embedded directory changes when entries are added or removed.
    if !meta.is_file() && !meta.is_dir() {
        return None;
    }
    let mut modified = meta.modified().ok()?;
    // A symbolic link retargeted at an older file would otherwise keep the old stamp; its own
    // modification time is when it was last created or replaced.
    if let Some(link) = std::fs::symlink_metadata(path)
        .ok()
        .filter(|link| link.is_symlink())
        .and_then(|link| link.modified().ok())
    {
        modified = modified.max(link);
    }
    let mtime = modified.duration_since(UNIX_EPOCH).ok()?.as_nanos();
    Some(Stamp {
        mtime,
        size: meta.len(),
    })
}

/// The entry name for a build: a digest of `parts`, the codegen environment, the working
/// directory and the stamps of `inputs` (the `ms` executable, the runtime, `--link` files).
/// `None` when an input cannot be stamped.
pub fn key(parts: &[&str], inputs: &[&Path], build: &BuildOptions) -> Option<String> {
    let mut text = String::from("ms-build-cache-v2\n");
    for part in parts {
        let _ = writeln!(text, "{part}");
    }
    let _ = writeln!(text, "{}", std::env::current_dir().ok()?.display());
    let _ = writeln!(text, "{}", std::env::consts::OS);
    let _ = writeln!(text, "{build:?}");
    for input in inputs.iter().copied() {
        let s = stamp(input)?;
        let _ = writeln!(text, "{} {} {}", input.display(), s.mtime, s.size);
    }
    // `DefaultHasher::new` has fixed keys, and the `ms` executable's stamp is part of the text,
    // so a different toolchain never reads another's entries. This is a cache name, not a security digest.
    let mut hasher = DefaultHasher::new();
    hasher.write(text.as_bytes());
    Some(format!("{:016x}", hasher.finish()))
}

/// A stored build whose sources are unchanged.
pub struct Entry {
    dir: PathBuf,
    manifest: String,
    /// The source root recorded with the build (reported in `--json` output).
    pub source_root: String,
    /// The backend that produced this executable, independent of current tool availability.
    pub backend: Backend,
}

struct Manifest<'a> {
    source_root: String,
    backend: Backend,
    files: Vec<(Stamp, &'a str)>,
}

fn parse(manifest: &str) -> Option<Manifest<'_>> {
    let mut lines = manifest.lines();
    if lines.next()? != "ms-build-cache-v3" {
        return None;
    }
    let backend = Backend::parse(lines.next()?)?;
    let root = lines.next()?.to_string();
    let mut files = Vec::new();
    for line in lines {
        let mut f = line.splitn(3, '\t');
        let mtime = f.next()?.parse().ok()?;
        let size = f.next()?.parse().ok()?;
        files.push((Stamp { mtime, size }, f.next()?));
    }
    Some(Manifest {
        source_root: root,
        backend,
        files,
    })
}

// A retained lookup must not reopen another backend's executable after a store
// replaces the same key. Tool availability can change without changing that key.
fn executable(dir: &Path, backend: Backend) -> PathBuf {
    dir.join(format!("exe-{}", backend.as_str()))
}

/// The entry for `key` in `dir` when every listed source still has its recorded stamp.
pub fn lookup(dir: &Path, key: &str) -> Option<Entry> {
    let entry = dir.join(key);
    let manifest = std::fs::read_to_string(entry.join("manifest")).ok()?;
    let Manifest {
        source_root,
        backend,
        files,
    } = parse(&manifest)?;
    if !executable(&entry, backend).is_file() {
        return None;
    }
    if files.is_empty() || files.iter().any(|(s, p)| stamp(Path::new(p)) != Some(*s)) {
        return None;
    }
    touch(&entry);
    Some(Entry {
        dir: entry,
        source_root,
        backend,
        manifest,
    })
}

pub(crate) fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
    if from.is_dir() {
        std::fs::create_dir_all(to)?;
        for entry in std::fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        return Ok(());
    }
    std::fs::copy(from, to).map(|_| ())
}

/// Stores the finished `executable` (and its debug companion) under `key`, valid while
/// `sources` keep their stamps. Sources that cannot be stamped or named in the manifest make
/// the build uncacheable.
pub fn store(
    dir: &Path,
    key: &str,
    source_root: &str,
    backend: Backend,
    sources: &[PathBuf],
    executable: &Path,
    companion: Option<&Path>,
) {
    store_with(dir, key, (source_root, backend), sources, companion, |to| {
        std::fs::copy(executable, to).map(|_| ())
    });
}

/// The production copy is supplied separately so tests can coordinate actual store attempts.
fn store_with(
    dir: &Path,
    key: &str,
    identity: (&str, Backend),
    sources: &[PathBuf],
    companion: Option<&Path>,
    copy: impl FnOnce(&Path) -> std::io::Result<()>,
) {
    let (source_root, backend) = identity;
    let mut manifest = format!(
        "ms-build-cache-v3\n{}\n{}\n",
        backend.as_str(),
        source_root.replace('\n', " ")
    );
    for source in sources {
        let (Some(s), Some(text)) = (stamp(source), source.to_str()) else {
            return;
        };
        if text.contains(['\n', '\t']) {
            return;
        }
        let _ = writeln!(manifest, "{}\t{}\t{text}", s.mtime, s.size);
    }
    let entry = dir.join(key);
    let Ok(staged) = store_stage(dir, key) else {
        return;
    };
    let done = (|| -> std::io::Result<()> {
        copy(&executable(&staged, backend))?;
        if let Some(companion) = companion.filter(|c| c.exists()) {
            copy_tree(companion, &staged.join("companion"))?;
        }
        std::fs::write(staged.join("manifest"), manifest)?;
        let _ = std::fs::remove_dir_all(&entry);
        std::fs::rename(&staged, &entry)
    })();
    if done.is_err() {
        let _ = std::fs::remove_dir_all(&staged);
        return;
    }
    prune(dir, KEEP);
}

/// Own a new stage rather than sharing one with another attempt or a reused process ID.
fn store_stage(dir: &Path, key: &str) -> std::io::Result<PathBuf> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    std::fs::create_dir_all(dir)?;
    loop {
        let staged = dir.join(format!(
            ".{key}.{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        match std::fs::create_dir(&staged) {
            Ok(()) => return Ok(staged),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

/// Entries kept per cache directory; the least recently used are removed when a build stores another.
const KEEP: usize = 8;

/// When an entry was last stored or hit: the modification time of its manifest.
fn used(entry: &Path) -> Option<std::time::SystemTime> {
    std::fs::metadata(entry.join("manifest"))
        .ok()?
        .modified()
        .ok()
}

/// Marks an entry as just used so pruning removes the least recently hit entries.
fn touch(entry: &Path) {
    let _ = std::fs::OpenOptions::new()
        .write(true)
        .open(entry.join("manifest"))
        .and_then(|f| f.set_modified(std::time::SystemTime::now()));
}

/// How long a store stage may sit untouched before pruning treats its build as dead.
const STALE_STAGE: std::time::Duration = std::time::Duration::from_secs(24 * 60 * 60);

fn prune(dir: &Path, keep: usize) {
    prune_stages(dir, keep, STALE_STAGE);
}

fn prune_stages(dir: &Path, keep: usize, stale: std::time::Duration) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let entries: Vec<_> = entries.filter_map(Result::ok).collect();
    // Stages are named uniquely per attempt, so one left by a killed build is never reused.
    for stage in entries
        .iter()
        .filter(|e| e.file_name().to_string_lossy().starts_with('.'))
    {
        let age = stage
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.elapsed().ok());
        if age.is_some_and(|age| age > stale) {
            let _ = std::fs::remove_dir_all(stage.path());
        }
    }
    let mut entries: Vec<_> = entries
        .into_iter()
        .filter(|e| !e.file_name().to_string_lossy().starts_with('.'))
        .filter_map(|e| Some((used(&e.path())?, e.path())))
        .collect();
    entries.sort();
    let excess = entries.len().saturating_sub(keep);
    for (_, path) in entries.into_iter().take(excess) {
        let _ = std::fs::remove_dir_all(path);
    }
}

impl Entry {
    /// Inputs validated by this hit, retained for artifact/source collision checks.
    pub fn inputs(&self) -> impl Iterator<Item = &Path> {
        self.manifest
            .lines()
            .skip(3)
            .filter_map(|line| line.splitn(3, '\t').nth(2))
            .map(Path::new)
    }

    /// Copies the executable to `staged`, and the debug companion to `companion`, whose DWARF
    /// resource is renamed after `staged` as the publication step expects. `false` on failure.
    pub fn restore(&self, staged: &Path, companion: Option<&Path>) -> bool {
        let restored = (|| -> std::io::Result<()> {
            std::fs::copy(executable(&self.dir, self.backend), staged)?;
            let cached = self.dir.join("companion");
            if let (Some(companion), true) = (companion, cached.exists()) {
                copy_tree(&cached, companion)?;
                let resources = companion.join("Contents/Resources/DWARF");
                if let (Ok(mut found), Some(name)) =
                    (std::fs::read_dir(&resources), staged.file_name())
                    && let Some(Ok(only)) = found.next()
                    && only.file_name() != name
                {
                    std::fs::rename(only.path(), resources.join(name))?;
                }
            }
            Ok(())
        })();
        restored.is_ok()
    }

    /// Whether the stored executable has the same bytes as `built`.
    pub fn matches(&self, built: &Path) -> bool {
        matches!(
            (std::fs::read(executable(&self.dir, self.backend)), std::fs::read(built)),
            (Ok(x), Ok(y)) if x == y
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ms-cache-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn key_depends_on_parts_and_input_stamps() {
        let dir = scratch("key");
        let input = dir.join("rt.a");
        std::fs::write(&input, b"one").unwrap();
        let build = BuildOptions::default();
        let base = key(&["Debug", "out"], &[&input], &build).unwrap();
        assert_eq!(base, key(&["Debug", "out"], &[&input], &build).unwrap());
        assert_ne!(base, key(&["Release", "out"], &[&input], &build).unwrap());
        assert_ne!(base, key(&["Debug", "other"], &[&input], &build).unwrap());
        std::fs::write(&input, b"longer").unwrap();
        assert_ne!(base, key(&["Debug", "out"], &[&input], &build).unwrap());
        assert!(key(&["Debug"], &[&dir.join("missing")], &build).is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn entries_are_valid_until_a_source_changes() {
        let dir = scratch("store");
        let cache = dir.join("build");
        let built = dir.join("built");
        std::fs::write(&built, b"binary").unwrap();
        let source = dir.join("main.ms");
        std::fs::write(&source, b"fn main() Int: return 0").unwrap();
        assert!(lookup(&cache, "k").is_none());
        store(
            &cache,
            "k",
            "/root",
            Backend::Cranelift,
            std::slice::from_ref(&source),
            &built,
            None,
        );
        let entry = lookup(&cache, "k").expect("fresh entry");
        assert_eq!(entry.source_root, "/root");
        assert_eq!(entry.backend, Backend::Cranelift);
        let staged = dir.join("staged");
        assert!(entry.restore(&staged, None));
        assert!(entry.matches(&staged));
        std::fs::write(&source, b"fn main() Int: return 12").unwrap();
        assert!(lookup(&cache, "k").is_none());
        std::fs::remove_file(&source).unwrap();
        assert!(lookup(&cache, "k").is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn cache_backend_and_all_inputs_survive_the_manifest_round_trip() {
        let dir = scratch("backend-manifest");
        let sources: Vec<_> = ["first source.ms", "second.ms", "runtime.a", "helper.ll"]
            .into_iter()
            .map(|name| {
                let path = dir.join(name);
                std::fs::write(&path, b"input").unwrap();
                path
            })
            .collect();
        let built = dir.join("program");
        std::fs::write(&built, b"executable bytes").unwrap();
        let cache = dir.join("cache");
        for backend in [Backend::Cranelift, Backend::Llvm] {
            store(
                &cache,
                "same-key",
                "source root",
                backend,
                &sources,
                &built,
                None,
            );
            let entry = lookup(&cache, "same-key").unwrap();
            assert_eq!(entry.backend, backend);
            assert_eq!(entry.source_root, "source root");
            assert_eq!(entry.inputs().collect::<Vec<_>>(), sources);
            assert!(entry.matches(&built));
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn cache_entries_without_known_backend_provenance_are_misses() {
        let dir = scratch("unknown-backend");
        let cache = dir.join("cache");
        let source = dir.join("source.ms");
        let built = dir.join("program");
        std::fs::write(&source, b"source").unwrap();
        std::fs::write(&built, b"executable").unwrap();
        store(&cache, "k", "root", Backend::Llvm, &[source], &built, None);
        let path = cache.join("k/manifest");
        let good = std::fs::read_to_string(&path).unwrap();
        for invalid in [
            good.lines().skip(2).collect::<Vec<_>>().join("\n"), // Legacy entries have no provenance.
            good.replacen("\nllvm\n", "\nunknown\n", 1),
            good.replacen("\nllvm\n", "\n\n", 1),
            "ms-build-cache-v3\nllvm\nroot\ninvalid stamp\n".into(),
        ] {
            std::fs::write(&path, invalid).unwrap();
            assert!(lookup(&cache, "k").is_none());
            assert_eq!(std::fs::read(&built).unwrap(), b"executable");
        }
        std::fs::write(path, good).unwrap();
        assert_eq!(lookup(&cache, "k").unwrap().backend, Backend::Llvm);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn retained_cache_hits_never_restore_another_backends_executable() {
        let dir = scratch("retained-backend");
        let cache = dir.join("cache");
        let source = dir.join("source.ms");
        let built = dir.join("program");
        let restored = dir.join("restored");
        std::fs::write(&source, b"source").unwrap();
        for (first, second) in [
            (Backend::Llvm, Backend::Cranelift),
            (Backend::Cranelift, Backend::Llvm),
        ] {
            std::fs::write(&built, b"first backend's executable").unwrap();
            store(
                &cache,
                "k",
                "root",
                first,
                std::slice::from_ref(&source),
                &built,
                None,
            );
            let retained = lookup(&cache, "k").unwrap();
            std::fs::write(&built, b"second backend's executable").unwrap();
            store(
                &cache,
                "k",
                "root",
                second,
                std::slice::from_ref(&source),
                &built,
                None,
            );
            assert!(!retained.restore(&restored, None));
            assert!(!retained.matches(&built));
            let current = lookup(&cache, "k").unwrap();
            assert_eq!(current.backend, second);
            assert!(current.restore(&restored, None));
            assert_eq!(
                std::fs::read(&restored).unwrap(),
                b"second backend's executable"
            );
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    fn concurrent_stores(first_fails: bool) {
        use std::sync::mpsc;
        use std::time::Duration;
        let dir = scratch(if first_fails {
            "concurrent-failure"
        } else {
            "concurrent-success"
        });
        let cache = dir.join("build");
        let first_source = dir.join("first.ms");
        let second_source = dir.join("second.ms");
        let first_exe = dir.join("first");
        let second_exe = dir.join("second");
        std::fs::write(&first_source, b"first source").unwrap();
        std::fs::write(&second_source, b"second source").unwrap();
        std::fs::write(&first_exe, b"first executable").unwrap();
        std::fs::write(&second_exe, b"second executable").unwrap();
        store(
            &cache,
            "k",
            "original",
            Backend::Cranelift,
            std::slice::from_ref(&first_source),
            &first_exe,
            None,
        );
        let (first_ready, first_waiting) = mpsc::channel();
        let (first_release, first_continue) = mpsc::channel();
        let a_cache = cache.clone();
        let a_source = first_source.clone();
        let a_exe = first_exe.clone();
        let first = std::thread::spawn(move || {
            store_with(
                &a_cache,
                "k",
                ("first", Backend::Llvm),
                &[a_source],
                None,
                |to| {
                    std::fs::copy(&a_exe, to)?;
                    first_ready.send(()).unwrap();
                    first_continue.recv().unwrap();
                    if first_fails {
                        return Err(std::io::Error::other("fixture copy failed"));
                    }
                    Ok(())
                },
            );
        });
        first_waiting.recv_timeout(Duration::from_secs(30)).unwrap();
        let (second_ready, second_waiting) = mpsc::channel();
        let (second_release, second_continue) = mpsc::channel();
        let b_cache = cache.clone();
        let b_source = second_source.clone();
        let b_exe = second_exe.clone();
        let second = std::thread::spawn(move || {
            store_with(
                &b_cache,
                "k",
                ("second", Backend::Cranelift),
                &[b_source],
                None,
                |to| {
                    std::fs::copy(&b_exe, to)?;
                    second_ready.send(()).unwrap();
                    second_continue.recv().unwrap();
                    Ok(())
                },
            );
        });
        second_waiting
            .recv_timeout(Duration::from_secs(30))
            .unwrap();
        first_release.send(()).unwrap();
        first.join().unwrap();
        let entry = lookup(&cache, "k").expect("original or first completed entry");
        assert_eq!(
            entry.source_root,
            if first_fails { "original" } else { "first" }
        );
        assert_eq!(
            entry.backend,
            if first_fails {
                Backend::Cranelift
            } else {
                Backend::Llvm
            }
        );
        assert!(
            entry.matches(&first_exe),
            "a second attempt must not overwrite the first executable"
        );
        second_release.send(()).unwrap();
        second.join().unwrap();
        let entry = lookup(&cache, "k").expect("second completed entry");
        assert_eq!(entry.source_root, "second");
        assert!(entry.matches(&second_exe));
        let restored = dir.join("restored");
        assert!(entry.restore(&restored, None));
        assert_eq!(std::fs::read(restored).unwrap(), b"second executable");
        std::fs::write(&second_source, b"changed second source").unwrap();
        assert!(
            lookup(&cache, "k").is_none(),
            "manifest must track the second source"
        );
        assert_eq!(
            std::fs::read_dir(&cache).unwrap().count(),
            1,
            "completed and failed stages must be cleaned"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn concurrent_stores_keep_each_executable_paired_with_its_manifest() {
        concurrent_stores(false);
    }

    #[test]
    fn a_failed_store_does_not_remove_another_attempt() {
        concurrent_stores(true);
    }

    #[test]
    fn pruning_removes_only_stages_older_than_the_limit() {
        let dir = scratch("prune-stage");
        let stage = dir.join(".k.1-0");
        std::fs::create_dir_all(&stage).unwrap();
        prune_stages(&dir, 8, std::time::Duration::from_secs(3600));
        assert!(stage.exists(), "a recent stage may belong to a live build");
        std::thread::sleep(std::time::Duration::from_millis(20));
        prune_stages(&dir, 8, std::time::Duration::from_millis(1));
        assert!(!stage.exists(), "an abandoned stage is reclaimed");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn stale_store_stages_keep_their_contents() {
        let dir = scratch("stale-stage");
        let cache = dir.join("build");
        let stale = cache.join(format!(".k.{}", std::process::id()));
        std::fs::create_dir_all(&stale).unwrap();
        std::fs::write(stale.join("retained"), b"another attempt").unwrap();
        let source = dir.join("source");
        let executable = dir.join("executable");
        std::fs::write(&source, b"source").unwrap();
        std::fs::write(&executable, b"executable").unwrap();
        store(
            &cache,
            "k",
            "root",
            Backend::Cranelift,
            &[source],
            &executable,
            None,
        );
        assert_eq!(
            std::fs::read(stale.join("retained")).unwrap(),
            b"another attempt"
        );
        let entry = lookup(&cache, "k").unwrap();
        assert_eq!(entry.source_root, "root");
        assert!(entry.matches(&executable));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn companion_round_trip_keeps_the_executable_and_debug_resource() {
        let dir = scratch("companion");
        let cache = dir.join("build");
        let source = dir.join("source");
        let executable = dir.join("executable");
        std::fs::write(&source, b"source").unwrap();
        std::fs::write(&executable, b"executable").unwrap();
        let companion = dir.join("debug");
        let resources = companion.join("Contents/Resources/DWARF");
        std::fs::create_dir_all(&resources).unwrap();
        std::fs::write(resources.join("executable"), b"debug resource").unwrap();
        store(
            &cache,
            "k",
            "root",
            Backend::Cranelift,
            &[source],
            &executable,
            Some(&companion),
        );
        let entry = lookup(&cache, "k").unwrap();
        let restored = dir.join("restored");
        let restored_companion = dir.join("restored.debug");
        assert!(entry.restore(&restored, Some(&restored_companion)));
        assert!(entry.matches(&restored));
        assert_eq!(
            std::fs::read(restored_companion.join("Contents/Resources/DWARF/restored")).unwrap(),
            b"debug resource"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_hit_keeps_its_entry_from_being_pruned() {
        let dir = scratch("lru");
        let cache = dir.join("build");
        let built = dir.join("built");
        let source = dir.join("a.ms");
        std::fs::write(&built, b"x").unwrap();
        std::fs::write(&source, b"y").unwrap();
        let put = |name: &str| {
            store(
                &cache,
                name,
                "/r",
                Backend::Cranelift,
                std::slice::from_ref(&source),
                &built,
                None,
            );
        };
        put("old");
        let past = std::time::SystemTime::now() - std::time::Duration::from_secs(1000);
        let age = |name: &str, secs: u64| {
            let f = std::fs::OpenOptions::new()
                .write(true)
                .open(cache.join(name).join("manifest"))
                .unwrap();
            f.set_modified(past + std::time::Duration::from_secs(secs))
                .unwrap();
        };
        age("old", 0);
        for i in 0..KEEP - 1 {
            put(&format!("e{i}"));
            age(&format!("e{i}"), 10 + i as u64);
        }
        assert!(lookup(&cache, "old").is_some());
        put("new");
        assert!(cache.join("old").exists());
        assert!(!cache.join("e0").exists());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn only_the_newest_entries_stay() {
        let dir = scratch("prune");
        let cache = dir.join("build");
        let built = dir.join("built");
        let source = dir.join("a.ms");
        std::fs::write(&built, b"x").unwrap();
        std::fs::write(&source, b"y").unwrap();
        for i in 0..KEEP + 3 {
            store(
                &cache,
                &format!("e{i}"),
                "/r",
                Backend::Cranelift,
                std::slice::from_ref(&source),
                &built,
                None,
            );
        }
        assert_eq!(std::fs::read_dir(&cache).unwrap().count(), KEEP);
        let _ = std::fs::remove_dir_all(dir);
    }
}
