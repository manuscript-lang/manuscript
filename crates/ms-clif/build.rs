//! Bundles what linking needs so `ms build` runs no C toolchain: the pinned static `lld` (built by
//! `scripts/build-llvm-bundle.sh`) and, on Linux, the self-contained musl startup objects and libc
//! that Rust's musl target carries, or, on Windows, the mingw-w64 startup object, libraries and import
//! libraries of the pinned llvm-mingw release (`scripts/fetch-mingw.sh`).

use std::path::{Path, PathBuf};
use std::process::Command;

/// Files copied from the toolchain's musl `self-contained` directory.
const MUSL_FILES: [&str; 5] = ["crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a"];

/// Files copied from llvm-mingw's `<arch>-w64-mingw32/lib`: the C startup object, the CRT and unwinder
/// libraries, and the import libraries for every DLL the runtime (Rust's `std` plus the standard library
/// crates) calls.
const MINGW_FILES: [&str; 18] = [
    "crt2.o",
    "libmingw32.a",
    "libmingwex.a",
    "libmoldname.a",
    "libunwind.a",
    "libucrt.a",
    "libmsvcrt.a",
    "libkernel32.a",
    "libadvapi32.a",
    "libbcrypt.a",
    "libcrypt32.a",
    "libdbghelp.a",
    "libntdll.a",
    "libsecur32.a",
    "libuserenv.a",
    "libws2_32.a",
    "libuser32.a",
    "libshell32.a",
];

/// mingw files compiled with `-g` (`libucrt.a` carries compatibility objects beside its imports); the
/// pure import libraries have none.
const DEBUG_INFO: [&str; 7] = [
    "libucrt.a",
    "libmsvcrt.a",
    "crt2.o",
    "libmingw32.a",
    "libmingwex.a",
    "libmoldname.a",
    "libunwind.a",
];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=MS_LLD");
    println!("cargo:rerun-if-env-changed=RUSTC");
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let bundle = out.join("linker");
    std::fs::create_dir_all(&bundle).expect("create the linker bundle directory");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS");
    let mut names = vec![if target_os == "windows" {
        "lld.exe"
    } else {
        "lld"
    }];
    copy(&lld(), &bundle.join(names[0]), "lld");
    if target_os == "windows" {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
        println!("cargo:rerun-if-env-changed=MS_MINGW");
        let lib = mingw().join(format!("{arch}-w64-mingw32/lib"));
        for name in MINGW_FILES {
            let to = bundle.join(name);
            copy(&lib.join(name), &to, name);
            // The CRT objects carry line tables for code the program never shows in a debugger.
            if DEBUG_INFO.contains(&name) {
                strip_debug(&to, Some(&mingw().join("bin/llvm-strip")));
            }
            names.push(name);
        }
    }
    if target_os == "linux" {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
        let musl = sysroot()
            .join("lib/rustlib")
            .join(format!("{arch}-unknown-linux-musl"))
            .join("lib/self-contained");
        for name in MUSL_FILES {
            let to = bundle.join(name);
            copy(
                &musl.join(name),
                &to,
                &format!("{name} (run `rustup target add {arch}-unknown-linux-musl`)"),
            );
            strip_debug(&to, None);
            names.push(name);
        }
    }
    let mut id = 0xcbf29ce484222325u64;
    for name in &names {
        let bytes = std::fs::read(bundle.join(name)).expect("read bundled file");
        for byte in bytes.iter().chain(&(bytes.len() as u64).to_le_bytes()) {
            id = (id ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
        }
    }
    println!("cargo:rustc-env=MS_LINKER_ID={id:016x}");
}

/// `MS_MINGW`, else the llvm-mingw tree `scripts/fetch-mingw.sh` leaves in `target/llvm-bundle/mingw`.
fn mingw() -> PathBuf {
    let root = std::env::var_os("MS_MINGW").map_or_else(
        || Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/llvm-bundle/mingw"),
        PathBuf::from,
    );
    assert!(
        root.join("bin").is_dir(),
        "no llvm-mingw to bundle: run `sh scripts/fetch-mingw.sh` or set MS_MINGW to its root"
    );
    root
}

/// `MS_LLD`, else the bundle `scripts/build-llvm-bundle.sh` leaves in `target/llvm-bundle`.
fn lld() -> PathBuf {
    if let Some(path) = std::env::var_os("MS_LLD") {
        return PathBuf::from(path);
    }
    let exe = if cfg!(windows) { "lld.exe" } else { "lld" };
    let built = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target/llvm-bundle/install/bin")
        .join(exe);
    println!("cargo:rerun-if-changed={}", built.display());
    assert!(
        built.is_file(),
        "no lld to bundle: run `sh scripts/build-llvm-bundle.sh <os> <arch>` or set MS_LLD to a static lld"
    );
    built
}

fn sysroot() -> PathBuf {
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let output = Command::new(rustc)
        .args(["--print", "sysroot"])
        .output()
        .expect("run rustc --print sysroot");
    assert!(output.status.success(), "rustc --print sysroot failed");
    PathBuf::from(
        String::from_utf8(output.stdout)
            .expect("sysroot path")
            .trim(),
    )
}

fn copy(from: &Path, to: &Path, what: &str) {
    println!("cargo:rerun-if-changed={}", from.display());
    let bytes = std::fs::read(from)
        .unwrap_or_else(|e| panic!("cannot bundle {what} from {}: {e}", from.display()));
    if std::fs::read(to).ok().as_deref() != Some(&bytes) {
        std::fs::write(to, bytes).expect("write bundled file");
    }
}

/// musl's startup objects and archives carry line tables for code the program never sees in a
/// debugger; they would land in every linked executable. Without a strip tool the file is used as
/// shipped.
fn strip_debug(file: &Path, preferred: Option<&Path>) {
    let original = std::fs::read(file).expect("read bundled file");
    let tools = preferred
        .into_iter()
        .map(Path::as_os_str)
        .chain(["strip".as_ref(), "llvm-strip".as_ref()]);
    for tool in tools {
        let done = Command::new(tool)
            .arg("--strip-debug")
            .arg(file)
            .status()
            .is_ok_and(|status| status.success());
        if done {
            return;
        }
        // A failed tool may have left a partial file: start the next one from the original.
        std::fs::write(file, &original).expect("restore bundled file");
    }
}
