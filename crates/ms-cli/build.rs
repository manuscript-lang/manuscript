//! Embed the release version shared with the Go implementation (`.msversion`).

fn main() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../.msversion");
    println!("cargo:rerun-if-changed={}", path.display());
    let version = std::fs::read_to_string(&path).unwrap_or_else(|_| "0.0.0".to_string());
    println!("cargo:rustc-env=MS_VERSION={}", version.trim());
}
