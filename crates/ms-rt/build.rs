//! Per-symbol selection between the Rust and the C runtime. `cargo xtask runtime` sets `MS_C_RUNTIME`
//! and links the objects built from `runtime/**/*.c`; every symbol named in `runtime/c-symbols.txt`
//! then gets the cfg `ms_c = "<symbol>"`, which compiles its Rust definition out. Without the
//! variable (unit tests, clippy) the Rust definitions stay.

fn main() {
    println!("cargo::rustc-check-cfg=cfg(ms_c, values(any()))");
    println!("cargo::rerun-if-env-changed=MS_C_RUNTIME");
    let list = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../../runtime/c-symbols.txt");
    println!("cargo::rerun-if-changed={}", list.display());
    if std::env::var_os("MS_C_RUNTIME").is_none() {
        return;
    }
    let text = std::fs::read_to_string(&list).expect("read runtime/c-symbols.txt");
    for symbol in text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
    {
        println!("cargo::rustc-cfg=ms_c=\"{symbol}\"");
    }
}
