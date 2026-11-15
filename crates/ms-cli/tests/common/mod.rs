//! Helpers shared by the integration tests.

use std::path::{Path, PathBuf};

/// A fresh, empty directory unique to this test binary, `name` and process.
#[allow(dead_code)]
pub fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "ms-{}-{name}-{}",
        env!("CARGO_CRATE_NAME"),
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A file link using the platform's native symbolic-link API.
#[allow(dead_code, reason = "Not every integration-test binary creates links.")]
pub fn symlink_file(from: &Path, to: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(from, to)
    }
    #[cfg(windows)]
    {
        std::os::windows::fs::symlink_file(from, to)
    }
}

/// A directory link using the platform's native symbolic-link API.
#[allow(dead_code, reason = "Not every integration-test binary creates links.")]
pub fn symlink_dir(from: &Path, to: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(from, to)
    }
    #[cfg(windows)]
    {
        std::os::windows::fs::symlink_dir(from, to)
    }
}

/// The cache directory `ms` uses when a test leaves `XDG_CACHE_HOME` alone.
#[allow(
    dead_code,
    reason = "Not every integration-test binary reads the cache."
)]
pub fn cache_root() -> PathBuf {
    let variable = |name| {
        std::env::var_os(name)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
    };
    variable("LOCALAPPDATA")
        .filter(|_| cfg!(windows))
        .or_else(|| variable("XDG_CACHE_HOME"))
        .or_else(|| variable("HOME").map(|home| home.join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
}

/// Makes the tools `ms` downloads on first use (the pinned lld and LLVM bundle) resolve to the
/// ones in the ambient cache from the isolated cache `cache`. A test that points
/// `XDG_CACHE_HOME` at an empty directory otherwise downloads lld from GitHub on every build, so
/// it fails whenever the runner cannot reach the network, which CI avoids by restoring the
/// ambient cache.
#[allow(
    dead_code,
    reason = "Not every integration-test binary isolates the cache."
)]
pub fn share_downloaded_tools(cache: &Path) {
    let ambient = cache_root().join("ms");
    for tool in ["lld", "llvm"] {
        let source = ambient.join(tool);
        let link = cache.join("ms").join(tool);
        if source.is_dir() && !link.exists() {
            std::fs::create_dir_all(link.parent().unwrap()).unwrap();
            symlink_dir(&source, &link).unwrap();
        }
    }
}
