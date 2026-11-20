//! Per-symbol selection between the Rust and the C runtime. `cargo xtask runtime` sets `MS_C_RUNTIME`
//! and links the objects built from `runtime/**/*.c`; every symbol named in a `runtime/symbols/<module>.txt`
//! then gets the cfg `ms_c = "<symbol>"`, which compiles its Rust definition out. Without the
//! variable (unit tests, clippy) the Rust definitions stay.

fn main() {
    println!("cargo::rustc-check-cfg=cfg(ms_c, values(any()))");
    println!("cargo::rerun-if-env-changed=MS_C_RUNTIME");
    let dir = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../../runtime/symbols");
    println!("cargo::rerun-if-changed={}", dir.display());
    println!("cargo::rerun-if-env-changed=MS_C_REACTOR");
    if std::env::var_os("MS_C_RUNTIME").is_none() {
        return;
    }
    // The libuv reactor replaces the mio poller on this build (`cargo xtask runtime` with `MS_C_REACTOR=1`).
    if std::env::var_os("MS_C_REACTOR").is_some() {
        println!("cargo::rustc-cfg=ms_c=\"msio_open\"");
    }
    let mut files: Vec<_> = std::fs::read_dir(&dir)
        .expect("read runtime/symbols")
        .map(|e| e.expect("entry").path())
        .filter(|p| p.extension().is_some_and(|e| e == "txt"))
        .collect();
    files.sort();
    for file in files {
        let text = std::fs::read_to_string(&file).expect("read a symbol list");
        for symbol in text
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
        {
            println!("cargo::rustc-cfg=ms_c=\"{symbol}\"");
        }
    }
}
