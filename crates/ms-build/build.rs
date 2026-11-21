//! Builds the C back end (`compiler/`, target `ms_backend` of the CMake project) for this host and links it, so
//! `c_backend.rs` calls it in process. CMake and Ninja do the work (`runtime/build_c.rs`), as for the runtime.

#[path = "../../runtime/build_c.rs"]
mod build_c;

fn main() {
    let root = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../..");
    for path in [
        "compiler/src",
        "compiler/include",
        "runtime/include",
        "cmake",
        "CMakeLists.txt",
    ] {
        println!("cargo::rerun-if-changed={}", root.join(path).display());
    }
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let dir = build_c::build_c_backend(&root, &out).expect("build the C back end");
    println!("cargo::rustc-link-search=native={}", dir.display());
    println!("cargo::rustc-link-lib=static=ms_backend");
}
