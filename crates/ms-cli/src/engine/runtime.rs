//! The native static library embedded in `ms`: `libms_native.a` (the runtime plus every standard
//! library native), built by `build.rs`. The linker needs a file, so the first build extracts it
//! to a per-version cache entry that later builds reuse.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

/// The runtime archive, gzipped by the build script; `MS_NATIVE_LEN` is its unpacked size.
static ARCHIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a.gz"));
const ARCHIVE_LEN: u64 = length(env!("MS_NATIVE_LEN"));

/// The musl build that `ms build --static` links (Linux only).
#[cfg(target_os = "linux")]
static MUSL_ARCHIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native_musl.a.gz"));
#[cfg(target_os = "linux")]
const MUSL_ARCHIVE_LEN: u64 = length(env!("MS_NATIVE_MUSL_LEN"));

const fn length(text: &str) -> u64 {
    match u64::from_str_radix(text, 10) {
        Ok(len) => len,
        Err(_) => panic!("an archive length is not a number"),
    }
}

/// Path of the extracted archive for the glibc runtime, or the musl one when `musl`, written when
/// absent or of the wrong size.
pub fn embedded(musl: bool) -> Result<PathBuf, String> {
    #[cfg(target_os = "linux")]
    if musl {
        return extract(
            MUSL_ARCHIVE,
            MUSL_ARCHIVE_LEN,
            env!("MS_NATIVE_MUSL_ID"),
            "libms_native_musl.a",
        );
    }
    #[cfg(not(target_os = "linux"))]
    let _ = musl;
    extract(ARCHIVE, ARCHIVE_LEN, env!("MS_NATIVE_ID"), "libms_native.a")
}

fn extract(archive: &[u8], len: u64, id: &str, name: &str) -> Result<PathBuf, String> {
    let directory = cache_root().join("ms").join("native").join(id);
    static STAGED: AtomicUsize = AtomicUsize::new(0);
    extract_at(&directory, archive, len, name, &STAGED)
}

fn extract_at(
    directory: &Path,
    archive: &[u8],
    len: u64,
    name: &str,
    next: &AtomicUsize,
) -> Result<PathBuf, String> {
    let path = directory.join(name);
    if std::fs::metadata(&path).is_ok_and(|m| m.len() == len) {
        return Ok(path);
    }
    let failed = |action: &str, error: std::io::Error| {
        format!(
            "cannot {action} the runtime library in {}: {error}",
            directory.display()
        )
    };
    std::fs::create_dir_all(directory).map_err(|e| failed("create the cache for", e))?;
    // Exclusively own the neighboring stage: stale files or links from a reused PID must neither
    // be followed nor removed. The counter keeps simultaneous callers from sharing a candidate.
    let (staged, mut file) = loop {
        let staged = directory.join(format!(
            ".{name}-{}-{}",
            std::process::id(),
            next.fetch_add(1, Ordering::Relaxed)
        ));
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staged)
        {
            Ok(file) => break (staged, file),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(failed("write", error)),
        }
    };
    let written = (|| {
        let mut bytes = Vec::with_capacity(len as usize);
        flate2::read::GzDecoder::new(archive).read_to_end(&mut bytes)?;
        std::io::Write::write_all(&mut file, &bytes)
    })();
    // Windows publication and cleanup require the owned handle to be closed on every path.
    drop(file);
    let published = written.and_then(|()| std::fs::rename(&staged, &path));
    published.map_err(|e| {
        let _ = std::fs::remove_file(&staged);
        failed("write", e)
    })?;
    Ok(path)
}

/// `$XDG_CACHE_HOME`, else `$HOME/.cache`, else the temporary directory.
fn cache_root() -> PathBuf {
    let set = |name| {
        std::env::var_os(name)
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
    };
    set("XDG_CACHE_HOME")
        .or_else(|| set("HOME").map(|home| home.join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;

    struct Scratch(PathBuf);

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn scratch(name: &str) -> Scratch {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        loop {
            let path = std::env::temp_dir().join(format!(
                "ms-runtime-extract-{name}-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            match std::fs::create_dir(&path) {
                Ok(()) => return Scratch(path),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("cannot create test directory: {error}"),
            }
        }
    }

    fn gzip(bytes: &[u8]) -> Vec<u8> {
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        encoder.write_all(bytes).unwrap();
        encoder.finish().unwrap()
    }

    fn staged(directory: &Path, counter: usize) -> PathBuf {
        directory.join(format!(".runtime.a-{}-{counter}", std::process::id()))
    }

    #[test]
    fn runtime_extraction_preserves_stale_links_and_directories() {
        let root = scratch("collisions");
        let directory = &root.0;
        let sentinel = directory.join("sentinel");
        std::fs::write(&sentinel, b"keep the original bytes").unwrap();
        std::fs::hard_link(&sentinel, staged(directory, 0)).unwrap();
        std::fs::create_dir(staged(directory, 1)).unwrap();
        let next = AtomicUsize::new(0);
        let bytes = b"complete runtime archive";
        let output = extract_at(
            directory,
            &gzip(bytes),
            bytes.len() as u64,
            "runtime.a",
            &next,
        )
        .unwrap();
        assert_eq!(
            std::fs::read(&sentinel).unwrap(),
            b"keep the original bytes"
        );
        assert_eq!(
            std::fs::read(staged(directory, 0)).unwrap(),
            b"keep the original bytes"
        );
        assert!(staged(directory, 1).is_dir());
        assert_eq!(std::fs::read(&output).unwrap(), bytes);
        assert!(
            !std::fs::symlink_metadata(output)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(next.load(Ordering::Relaxed), 3);
        assert!(!staged(directory, 2).exists());
    }

    #[test]
    fn runtime_decode_failure_removes_only_its_owned_stage() {
        let root = scratch("decode-error");
        let directory = &root.0;
        let sentinel = directory.join("sentinel");
        std::fs::write(&sentinel, b"keep").unwrap();
        std::fs::hard_link(&sentinel, staged(directory, 0)).unwrap();
        let next = AtomicUsize::new(0);
        assert!(extract_at(directory, b"invalid gzip", 12, "runtime.a", &next).is_err());
        assert_eq!(std::fs::read(sentinel).unwrap(), b"keep");
        assert_eq!(std::fs::read(staged(directory, 0)).unwrap(), b"keep");
        assert!(!directory.join("runtime.a").exists());
        assert!(!staged(directory, 1).exists());
        assert_eq!(next.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn runtime_publication_failure_preserves_other_files() {
        let root = scratch("publish-error");
        let directory = &root.0;
        let sentinel = directory.join("sentinel");
        std::fs::write(&sentinel, b"keep").unwrap();
        std::fs::hard_link(&sentinel, staged(directory, 0)).unwrap();
        let output = directory.join("runtime.a");
        std::fs::create_dir(&output).unwrap();
        // Ensure the directory cannot look like a cache hit, on every host filesystem.
        let bytes = vec![b'x'; std::fs::metadata(&output).unwrap().len() as usize + 1];
        let next = AtomicUsize::new(0);
        assert!(
            extract_at(
                directory,
                &gzip(&bytes),
                bytes.len() as u64,
                "runtime.a",
                &next
            )
            .is_err()
        );
        assert_eq!(std::fs::read(sentinel).unwrap(), b"keep");
        assert_eq!(std::fs::read(staged(directory, 0)).unwrap(), b"keep");
        assert!(output.is_dir());
        assert!(!staged(directory, 1).exists());
        assert_eq!(next.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn runtime_cache_rebuilds_wrong_sizes_and_reuses_complete_archives() {
        let root = scratch("cache");
        let directory = &root.0;
        let output = directory.join("runtime.a");
        std::fs::write(&output, b"wrong").unwrap();
        let bytes = b"complete runtime archive";
        let next = AtomicUsize::new(0);
        assert_eq!(
            extract_at(
                directory,
                &gzip(bytes),
                bytes.len() as u64,
                "runtime.a",
                &next
            )
            .unwrap(),
            output
        );
        assert_eq!(std::fs::read(&output).unwrap(), bytes);
        assert_eq!(next.load(Ordering::Relaxed), 1);
        assert_eq!(
            extract_at(
                directory,
                b"unused gzip",
                bytes.len() as u64,
                "runtime.a",
                &next
            )
            .unwrap(),
            output
        );
        assert_eq!(next.load(Ordering::Relaxed), 1);
        assert_eq!(std::fs::read(output).unwrap(), bytes);
    }

    #[test]
    fn concurrent_runtime_extraction_publishes_complete_archives() {
        let root = scratch("concurrent");
        let directory = &root.0;
        let bytes = b"complete runtime archive";
        let archive = gzip(bytes);
        let next = AtomicUsize::new(0);
        let ready = std::sync::Barrier::new(8);
        std::thread::scope(|scope| {
            let handles: Vec<_> = (0..8)
                .map(|_| {
                    scope.spawn(|| {
                        ready.wait();
                        let output =
                            extract_at(directory, &archive, bytes.len() as u64, "runtime.a", &next)
                                .unwrap();
                        assert_eq!(std::fs::read(output).unwrap(), bytes);
                    })
                })
                .collect();
            for handle in handles {
                handle.join().unwrap();
            }
        });
        assert_eq!(std::fs::read_dir(directory).unwrap().count(), 1);
    }
}
