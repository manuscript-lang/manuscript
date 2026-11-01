//! The native static library embedded in `ms`: `libms_native.a` (the runtime plus every standard
//! library native), built by `build.rs`. The linker needs a file, so the first build extracts it
//! to a per-version cache entry that later builds reuse.

use std::io::Read;
use std::path::PathBuf;
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
    std::fs::create_dir_all(&directory).map_err(|e| failed("create the cache for", e))?;
    // Staged beside the destination so concurrent builds never see a partial archive; the counter
    // keeps threads of one process (the engine tests) from sharing a staged file.
    static STAGED: AtomicUsize = AtomicUsize::new(0);
    let staged = directory.join(format!(
        ".{name}-{}-{}",
        std::process::id(),
        STAGED.fetch_add(1, Ordering::Relaxed)
    ));
    let written = (|| {
        let mut bytes = Vec::with_capacity(len as usize);
        flate2::read::GzDecoder::new(archive).read_to_end(&mut bytes)?;
        std::fs::write(&staged, bytes)?;
        std::fs::rename(&staged, &path)
    })();
    written.map_err(|e| {
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
