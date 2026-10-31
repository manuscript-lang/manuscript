//! Helpers shared by the integration tests.

use std::path::PathBuf;

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
