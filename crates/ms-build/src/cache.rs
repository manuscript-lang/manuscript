//! Whole-build cache: a finished executable is reused when nothing that shapes it changed.
//!
//! The key hashes the optimized module (including file names and lines), the build profile, the
//! `ms` executable, the runtime archive, `--link` inputs, every codegen environment variable, the
//! working directory (it is baked into debug info) and the output file name (the macOS debug
//! companion names it). `MS_CACHE=off` skips the cache; `MS_CACHE=verify` rebuilds and compares.

use std::fmt::Write as _;
use std::path::Path;

use sha2::{Digest, Sha256};

/// Environment variables that change generated code or the link.
const ENV: &[&str] = &[
    "MS_BACKEND",
    "MS_COUNT_STR",
    "MS_LLVM_TOOLS",
    "MS_RT_HOT",
    "MS_VECTORIZE",
    "MS_KEEP_LL",
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

struct Feed(Sha256);

impl std::fmt::Write for Feed {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        self.0.update(s.as_bytes());
        Ok(())
    }
}

fn file_hash(hasher: &mut Sha256, path: &Path) -> std::io::Result<()> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut buffer = vec![0u8; 1 << 16];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            return Ok(());
        }
        hasher.update(&buffer[..n]);
    }
}

/// The cache key, or `None` when an input cannot be read (the build then runs uncached).
pub fn key(module: &[&str], profile: &str, output: &Path, inputs: &[&Path]) -> Option<String> {
    let mut feed = Feed(Sha256::new());
    let _ = write!(feed, "ms-build-cache-v1\n{profile}\n");
    let _ = writeln!(feed, "{}", output.file_name()?.to_string_lossy());
    let _ = writeln!(feed, "{}", std::env::current_dir().ok()?.display());
    let _ = writeln!(feed, "{}", std::env::consts::OS);
    for name in ENV {
        let _ = writeln!(feed, "{name}={:?}", std::env::var_os(name));
    }
    for part in module {
        let _ = writeln!(feed, "{}", part.len());
        let _ = feed.write_str(part);
    }
    let mut hasher = feed.0;
    file_hash(&mut hasher, &std::env::current_exe().ok()?).ok()?;
    for input in inputs {
        hasher.update(input.to_string_lossy().as_bytes());
        file_hash(&mut hasher, input).ok()?;
    }
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(64);
    for byte in digest {
        let _ = write!(hex, "{byte:02x}");
    }
    Some(hex)
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

/// Stores the finished `executable` (and its debug companion) under `key`.
pub fn store(dir: &Path, key: &str, executable: &Path, companion: Option<&Path>) {
    let entry = dir.join(key);
    if entry.exists() {
        return;
    }
    let staged = dir.join(format!(".{key}.{}", std::process::id()));
    let done = (|| -> std::io::Result<()> {
        std::fs::create_dir_all(&staged)?;
        std::fs::copy(executable, staged.join("exe"))?;
        if let Some(companion) = companion.filter(|c| c.exists()) {
            copy_tree(companion, &staged.join("companion"))?;
        }
        std::fs::rename(&staged, &entry)
    })();
    if done.is_err() {
        let _ = std::fs::remove_dir_all(&staged);
        return;
    }
    prune(dir, KEEP);
}

/// Entries kept per cache directory; the oldest are removed when a build stores another.
const KEEP: usize = 8;

fn prune(dir: &Path, keep: usize) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<_> = entries
        .filter_map(Result::ok)
        .filter(|e| !e.file_name().to_string_lossy().starts_with('.'))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    entries.sort();
    let excess = entries.len().saturating_sub(keep);
    for (_, path) in entries.into_iter().take(excess) {
        let _ = std::fs::remove_dir_all(path);
    }
}

/// Copies the cached entry for `key` to `staged` (and `companion`); `false` on any miss.
pub fn restore(dir: &Path, key: &str, staged: &Path, companion: Option<&Path>) -> bool {
    let entry = dir.join(key);
    if !entry.join("exe").is_file() {
        return false;
    }
    let restored = (|| -> std::io::Result<()> {
        std::fs::copy(entry.join("exe"), staged)?;
        if let Some(companion) = companion {
            let cached = entry.join("companion");
            if cached.exists() {
                copy_tree(&cached, companion)?;
            }
        }
        Ok(())
    })();
    restored.is_ok()
}

/// Whether two files have the same bytes.
pub fn same_bytes(a: &Path, b: &Path) -> bool {
    matches!((std::fs::read(a), std::fs::read(b)), (Ok(x), Ok(y)) if x == y)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ms-cache-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn key_depends_on_module_profile_output_and_inputs() {
        let dir = scratch("key");
        let input = dir.join("rt.a");
        std::fs::write(&input, b"one").unwrap();
        let out = dir.join("prog");
        let base = key(&["m"], "Debug", &out, &[&input]).unwrap();
        assert_eq!(base, key(&["m"], "Debug", &out, &[&input]).unwrap());
        assert_ne!(base, key(&["n"], "Debug", &out, &[&input]).unwrap());
        assert_ne!(base, key(&["m"], "Release", &out, &[&input]).unwrap());
        assert_ne!(
            base,
            key(&["m"], "Debug", &dir.join("other"), &[&input]).unwrap()
        );
        std::fs::write(&input, b"two").unwrap();
        assert_ne!(base, key(&["m"], "Debug", &out, &[&input]).unwrap());
        assert!(key(&["m"], "Debug", &out, &[&dir.join("missing")]).is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn stored_entries_restore_and_misses_do_not() {
        let dir = scratch("store");
        let cache = dir.join("exe");
        let built = dir.join("built");
        std::fs::write(&built, b"binary").unwrap();
        let companion = dir.join("built.dSYM");
        std::fs::create_dir_all(companion.join("Contents")).unwrap();
        std::fs::write(companion.join("Contents/x"), b"dwarf").unwrap();
        let staged = dir.join("staged");
        assert!(!restore(&cache, "k", &staged, None));
        store(&cache, "k", &built, Some(&companion));
        let again = dir.join("again.dSYM");
        assert!(restore(&cache, "k", &staged, Some(&again)));
        assert!(same_bytes(&built, &staged));
        assert_eq!(std::fs::read(again.join("Contents/x")).unwrap(), b"dwarf");
        assert!(!restore(&cache, "other", &staged, None));
        for i in 0..KEEP + 3 {
            store(&cache, &format!("e{i}"), &built, None);
        }
        assert_eq!(std::fs::read_dir(&cache).unwrap().count(), KEEP);
        let _ = std::fs::remove_dir_all(dir);
    }
}
