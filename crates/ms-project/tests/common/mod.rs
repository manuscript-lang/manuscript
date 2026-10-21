#![allow(dead_code)]
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use ms_project::{Project, read_project};

pub const MANIFEST: &str =
    "[project]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n";

/// A temporary directory removed on drop (canonical path, like Go's `t.TempDir`
/// after symlink resolution).
pub struct TempDir(pub PathBuf);

impl TempDir {
    pub fn new() -> TempDir {
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "ms-project-test-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(std::fs::canonicalize(dir).unwrap())
    }
    pub fn path(&self) -> &str {
        self.0.to_str().unwrap()
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        // Directories made unreadable by a test must be reopened first.
        #[cfg(unix)]
        {
            let _ = std::fs::set_permissions(
                &self.0,
                std::os::unix::fs::PermissionsExt::from_mode(0o700),
            );
        }
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub fn write(root: &str, name: &str, source: &str) -> String {
    let path = Path::new(root).join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, source).unwrap();
    path.to_str().unwrap().to_string()
}

pub fn join(a: &str, b: &str) -> String {
    ms_project::gopath::join(&[a, b])
}

pub fn fixture(source: &str) -> (TempDir, Project) {
    let dir = TempDir::new();
    write(dir.path(), "src/main.ms", "");
    write(dir.path(), "src/value.ms", "");
    let manifest = write(dir.path(), "ms.toml", source);
    let project = read_project(&manifest).unwrap();
    (dir, project)
}
