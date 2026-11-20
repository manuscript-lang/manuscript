//! Per-symbol selection between the Rust and the C runtime. `cargo xtask runtime` sets `MS_C_RUNTIME`
//! and links the objects built from `runtime/**/*.c`; every symbol named in a `runtime/symbols/<module>.txt`
//! then gets the cfg `ms_c = "<symbol>"`, which compiles its Rust definition out. Without the
//! variable (unit tests, clippy) the Rust definitions stay, and this script compiles the C itself
//! (`runtime/build_c.rs`, the code `cargo xtask runtime` uses, no `cc` crate) into `libms_c.a` and links it after
//! the Rust code: a symbol whose Rust body was deleted is then defined by its C object, while one Rust still defines
//! never pulls that object in.

#[path = "../../runtime/build_c.rs"]
mod build_c;

fn main() {
    println!("cargo::rustc-check-cfg=cfg(ms_c, values(any()))");
    println!("cargo::rerun-if-env-changed=MS_C_RUNTIME");
    let root = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../..");
    let dir = root.join("runtime/symbols");
    println!("cargo::rerun-if-changed={}", dir.display());
    println!("cargo::rerun-if-env-changed=MS_C_REACTOR");
    let archive_build = std::env::var_os("MS_C_RUNTIME").is_some();
    // Test and clippy builds on Linux and macOS link the C runtime. Windows hosts keep the Rust definitions: their
    // tests build for MSVC, and the runtime's C is built for mingw (`cargo xtask runtime`).
    let native = std::env::var("TARGET").ok() == std::env::var("HOST").ok();
    let test_c = !archive_build && native && !cfg!(windows);
    if test_c {
        link_c_runtime(&root);
    }
    if !archive_build {
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

/// Compiles `runtime/**/*.c` for the host and links it into this crate's test binaries as `libms_c.a`, not bundled
/// (a bundled copy would land in `libms_native.a` beside the objects `cargo xtask runtime` adds) (an archive:
/// the linker takes an object only for a symbol nothing else defines).
fn link_c_runtime(root: &std::path::Path) {
    for dir in ["include", "sys", "core", "io", "net", "std"] {
        println!(
            "cargo::rerun-if-changed={}",
            root.join("runtime").join(dir).display()
        );
    }
    println!("cargo::rerun-if-env-changed=MS_C_REGEX");
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let plan = build_c::plan_c_runtime(root, None).expect("plan the C runtime");
    let objects =
        build_c::compile_c_objects(root, &out, None, &plan).expect("compile the C runtime");
    let archive = out.join("libms_c.a");
    let _ = std::fs::remove_file(&archive);
    let ar = build_c::archiver(root, None);
    let status = std::process::Command::new(&ar)
        .arg("rcs")
        .arg(&archive)
        .args(&objects)
        .status()
        .expect("run ar");
    assert!(status.success(), "ar failed");
    println!("cargo::rustc-link-search=native={}", out.display());
    println!("cargo::rustc-link-lib=static:-bundle=ms_c");
}
