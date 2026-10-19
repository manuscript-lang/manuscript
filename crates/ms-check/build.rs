//! Embeds `pkg/stdlib/*.ms` and `bindings.json` unchanged.

use std::fmt::Write as _;
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let dir = manifest.join("../../pkg/stdlib").canonicalize().expect("pkg/stdlib");
    println!("cargo:rerun-if-changed={}", dir.display());
    let mut names: Vec<String> = std::fs::read_dir(&dir)
        .expect("read stdlib")
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.ends_with(".ms"))
        .collect();
    names.sort();
    let mut out = String::from("/// Bundled standard declarations in file-name order.\npub const SOURCES: &[(&str, &str)] = &[\n");
    for name in &names {
        let path = dir.join(name);
        println!("cargo:rerun-if-changed={}", path.display());
        writeln!(out, "    ({name:?}, include_str!({:?})),", path.display().to_string()).unwrap();
    }
    out.push_str("];\n");
    let bindings = dir.join("bindings.json");
    println!("cargo:rerun-if-changed={}", bindings.display());
    writeln!(out, "/// The native binding table.\npub const BINDINGS: &str = include_str!({:?});", bindings.display().to_string()).unwrap();
    let dest = PathBuf::from(std::env::var("OUT_DIR").expect("out dir")).join("std_sources.rs");
    std::fs::write(dest, out).expect("write");
}
