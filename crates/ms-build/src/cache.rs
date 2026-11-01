//! Build cache: a finished executable is reused while the files it came from are unchanged.
//!
//! An entry is keyed by the cheap facts of a build (profile, output, working directory, codegen
//! environment variables, the `ms` executable's and runtime's size and modification time). Its
//! manifest lists every source file with the size and modification time it had; the entry is
//! valid while all of them still match. Nothing is read or hashed, so a hit skips the whole
//! front end. `MS_CACHE=off` skips the cache; `MS_CACHE=verify` rebuilds and compares.
//!
//! A new file that would shadow an imported one (a different resolution of the same import) is
//! not noticed until some listed file changes; `MS_CACHE=off` or deleting `.ms-cache` covers it.

use std::fmt::Write as _;
use std::hash::{DefaultHasher, Hasher};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

/// Environment variables that change generated code or the link.
const ENV: &[&str] = &[
    "MS_BACKEND",
    "MS_COUNT_STR",
    "MS_LLVM_TOOLS",
    "MS_RT_HOT",
    "MS_VECTORIZE",
    "MS_KEEP_LL",
    "MS_RT_LIB",
];

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
    if !meta.is_file() {
        return None;
    }
    let mtime = meta
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_nanos();
    Some(Stamp {
        mtime,
        size: meta.len(),
    })
}

/// The entry name for a build: a digest of `parts`, the codegen environment, the working
/// directory and the stamps of `inputs` (the `ms` executable, the runtime, `--link` files).
/// `None` when an input cannot be stamped.
pub fn key(parts: &[&str], inputs: &[&Path]) -> Option<String> {
    let mut text = String::from("ms-build-cache-v2\n");
    for part in parts {
        let _ = writeln!(text, "{part}");
    }
    let _ = writeln!(text, "{}", std::env::current_dir().ok()?.display());
    let _ = writeln!(text, "{}", std::env::consts::OS);
    for name in ENV {
        let _ = writeln!(text, "{name}={:?}", std::env::var_os(name));
    }
    for input in inputs {
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
    /// The source root recorded with the build (reported in `--json` output).
    pub source_root: String,
}

fn parse(manifest: &str) -> Option<(String, Vec<(Stamp, &str)>)> {
    let mut lines = manifest.lines();
    let root = lines.next()?.to_string();
    let mut files = Vec::new();
    for line in lines {
        let mut f = line.splitn(3, '\t');
        let mtime = f.next()?.parse().ok()?;
        let size = f.next()?.parse().ok()?;
        files.push((Stamp { mtime, size }, f.next()?));
    }
    Some((root, files))
}

/// The entry for `key` in `dir` when every listed source still has its recorded stamp.
pub fn lookup(dir: &Path, key: &str) -> Option<Entry> {
    let entry = dir.join(key);
    if !entry.join("exe").is_file() {
        return None;
    }
    let manifest = std::fs::read_to_string(entry.join("manifest")).ok()?;
    let (source_root, files) = parse(&manifest)?;
    if files.is_empty() || files.iter().any(|(s, p)| stamp(Path::new(p)) != Some(*s)) {
        return None;
    }
    touch(&entry);
    Some(Entry {
        dir: entry,
        source_root,
    })
}

fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
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
    sources: &[PathBuf],
    executable: &Path,
    companion: Option<&Path>,
) {
    let mut manifest = format!("{}\n", source_root.replace('\n', " "));
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
    let staged = dir.join(format!(".{key}.{}", std::process::id()));
    let done = (|| -> std::io::Result<()> {
        std::fs::create_dir_all(&staged)?;
        std::fs::copy(executable, staged.join("exe"))?;
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

fn prune(dir: &Path, keep: usize) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<_> = entries
        .filter_map(Result::ok)
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
    /// Copies the executable to `staged`, and the debug companion to `companion`, whose DWARF
    /// resource is renamed after `staged` as the publication step expects. `false` on failure.
    pub fn restore(&self, staged: &Path, companion: Option<&Path>) -> bool {
        let restored = (|| -> std::io::Result<()> {
            std::fs::copy(self.dir.join("exe"), staged)?;
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
            (std::fs::read(self.dir.join("exe")), std::fs::read(built)),
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
        let base = key(&["Debug", "out"], &[&input]).unwrap();
        assert_eq!(base, key(&["Debug", "out"], &[&input]).unwrap());
        assert_ne!(base, key(&["Release", "out"], &[&input]).unwrap());
        assert_ne!(base, key(&["Debug", "other"], &[&input]).unwrap());
        std::fs::write(&input, b"longer").unwrap();
        assert_ne!(base, key(&["Debug", "out"], &[&input]).unwrap());
        assert!(key(&["Debug"], &[&dir.join("missing")]).is_none());
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
            std::slice::from_ref(&source),
            &built,
            None,
        );
        let entry = lookup(&cache, "k").expect("fresh entry");
        assert_eq!(entry.source_root, "/root");
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
                std::slice::from_ref(&source),
                &built,
                None,
            );
        }
        assert_eq!(std::fs::read_dir(&cache).unwrap().count(), KEEP);
        let _ = std::fs::remove_dir_all(dir);
    }
}
