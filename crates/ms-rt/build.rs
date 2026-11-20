//! Links the C runtime into this crate's test binaries (and `ms-std-net`'s): the Rust natives call the scheduler,
//! which is C. `cargo xtask runtime` (`MS_C_RUNTIME` set) builds the archive's C half itself, so nothing is compiled
//! here then. Otherwise the script compiles `runtime/**/*.c` with `runtime/build_c.rs` (CMake and Ninja, no `cc`
//! crate) into `libms_c.a`, linked after the Rust code.

#[path = "../../runtime/build_c.rs"]
mod build_c;

fn main() {
    println!("cargo::rerun-if-env-changed=MS_C_RUNTIME");
    let root = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../..");
    let archive_build = std::env::var_os("MS_C_RUNTIME").is_some();
    // Test and clippy builds link the C runtime. On a Windows host they build for MSVC, so the C is compiled for
    // MSVC too (clang `--target=<arch>-pc-windows-msvc`), unlike the runtime archive, which targets mingw.
    let native = std::env::var("TARGET").ok() == std::env::var("HOST").ok();
    let test_c = !archive_build && native;
    if test_c {
        link_c_runtime(&root);
    }
}

/// Compiles `runtime/**/*.c` for the host and links it into this crate's test binaries as `libms_c.a`, not bundled
/// (a bundled copy would land in `libms_native.a` beside the objects `cargo xtask runtime` adds) (an archive:
/// the linker takes an object only for a symbol nothing else defines).
fn link_c_runtime(root: &std::path::Path) {
    for dir in ["include", "sys", "core", "io", "entry", "net", "std"] {
        println!(
            "cargo::rerun-if-changed={}",
            root.join("runtime").join(dir).display()
        );
    }
    println!(
        "cargo::rerun-if-changed={}",
        root.join("CMakeLists.txt").display()
    );
    println!("cargo::rerun-if-changed={}", root.join("cmake").display());
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let plan =
        build_c::build_c_runtime(root, &out, None, true, false).expect("build the C runtime");
    let objects = plan.objects;
    let archive = out.join(if cfg!(windows) {
        "ms_c.lib"
    } else {
        "libms_c.a"
    });
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
