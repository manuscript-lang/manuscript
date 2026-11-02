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
