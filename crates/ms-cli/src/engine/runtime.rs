//! The native static library embedded in `ms`: `libms_native.a` (the runtime plus every standard
//! library native), built by `build.rs`. The linker needs a file, so the first build extracts it
//! to a per-version cache entry that later builds reuse.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

static ARCHIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a"));

/// Path of the extracted archive, written when absent or of the wrong size.
pub fn embedded() -> Result<PathBuf, String> {
    let directory = cache_root()
        .join("ms")
        .join("native")
        .join(env!("MS_NATIVE_ID"));
    let path = directory.join("libms_native.a");
    if std::fs::metadata(&path).is_ok_and(|m| m.len() == ARCHIVE.len() as u64) {
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
        ".libms_native-{}-{}.a",
        std::process::id(),
        STAGED.fetch_add(1, Ordering::Relaxed)
    ));
    let written = std::fs::write(&staged, ARCHIVE).and_then(|()| std::fs::rename(&staged, &path));
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
