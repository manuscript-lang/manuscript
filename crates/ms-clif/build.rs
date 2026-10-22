//! Bundles what linking needs so `ms build` runs no C toolchain: the pinned static `lld` (released by
//! manuscript-lang/llvm-bundle and fetched by `scripts/fetch-lld.sh`) and, on Linux, the self-contained musl startup objects and libc
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

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=MS_LLD");
    println!("cargo:rerun-if-env-changed=RUSTC");
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let bundle = out.join("linker");
    std::fs::create_dir_all(&bundle).expect("create the linker bundle directory");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS");
    let exe = if target_os == "windows" {
        "lld.exe"
    } else {
        "lld"
    };
    let mut names: Vec<String> = vec![exe.to_string()];
    copy(&lld(), &bundle.join(exe), "lld");
    if target_os == "windows" {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
        println!("cargo:rerun-if-env-changed=MS_MINGW");
        let lib = mingw().join(format!("{arch}-w64-mingw32/lib"));
        for name in MINGW_FILES {
            let to = bundle.join(name);
            copy(&lib.join(name), &to, name);
            // The CRT objects carry line tables for code the program never shows in a debugger.
            strip_debug(&to, Some(&mingw().join("bin/llvm-strip")));
            // Import objects in an archive make the tool reject the whole file: strip member by member.
            if has_line_tables(&to) {
                strip_members(&to);
            }
            assert_no_line_tables(&to, name);
            names.push(name.to_string());
        }
    }
    if target_os == "linux" {
        // opt and llc sit beside lld when the LLVM tools were fetched; without them release builds
        // keep using Cranelift. They are embedded gzipped (together about 50 MB).
        let tools = lld().parent().map(Path::to_path_buf).unwrap_or_default();
        for tool in ["opt", "llc"] {
            let gz = format!("{tool}.gz");
            compress(&tools.join(tool), &bundle.join(&gz));
            names.push(gz);
        }
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
            names.push(name.to_string());
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

/// The number of DWARF line-table sections left in `file`, or `None` when llvm-objdump cannot be run.
fn line_tables(file: &Path) -> Option<usize> {
    let output = Command::new(mingw().join("bin/llvm-objdump"))
        .arg("--section-headers")
        .arg(file)
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    Some(text.lines().filter(|l| l.contains(".debug_line")).count())
}

fn has_line_tables(file: &Path) -> bool {
    line_tables(file).is_some_and(|n| n > 0)
}

/// Fails the build if `file` still carries DWARF line tables, naming what remains.
fn assert_no_line_tables(file: &Path, name: &str) {
    let left = line_tables(file).unwrap_or(0);
    assert!(
        left == 0,
        "{name} still has {left} .debug_line sections after stripping"
    );
}

/// Strips an archive one member at a time and rebuilds it in the original order. Members that are not
/// plain objects (the short import objects in `libucrt.a`) are kept as they are.
fn strip_members(archive: &Path) {
    let bin = mingw().join("bin");
    let dir = archive.with_extension("members");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create the member directory");
    let run = |program: &str, args: &[&std::ffi::OsStr]| {
        Command::new(bin.join(program))
            .args(args)
            .current_dir(&dir)
            .status()
            .is_ok_and(|status| status.success())
    };
    let listing = Command::new(bin.join("llvm-ar"))
        .arg("t")
        .arg(archive)
        .output()
        .expect("run llvm-ar");
    let members: Vec<String> = String::from_utf8_lossy(&listing.stdout)
        .lines()
        .map(str::to_string)
        .collect();
    assert!(
        run("llvm-ar", &["x".as_ref(), archive.as_os_str()]),
        "cannot unpack {}",
        archive.display()
    );
    // Import objects share member names, so only uniquely named members are extracted faithfully.
    // They are replaced in place, which keeps the rest of the archive as it was.
    let unique: Vec<&String> = members
        .iter()
        .filter(|m| members.iter().filter(|n| n == m).count() == 1)
        .collect();
    for member in &unique {
        // Import objects are not objects to llvm-strip; the failure leaves them untouched.
        run(
            "llvm-strip",
            &["--strip-debug".as_ref(), std::ffi::OsStr::new(member)],
        );
    }
    // Thousands of members overflow the Windows command line, so pass them in a response file.
    let list = dir.join("members.rsp");
    let names: Vec<&str> = unique.iter().map(|m| m.as_str()).collect();
    std::fs::write(&list, names.join("\n")).expect("write the member list");
    let response = format!("@{}", list.display());
    assert!(
        run(
            "llvm-ar",
            &[
                "rs".as_ref(),
                archive.as_os_str(),
                std::ffi::OsStr::new(&response)
            ]
        ),
        "cannot rebuild {}",
        archive.display()
    );
    let _ = std::fs::remove_dir_all(&dir);
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

/// Writes `from` gzipped to `to`, or an empty file when `from` does not exist.
fn compress(from: &Path, to: &Path) {
    use std::io::Write;
    println!("cargo:rerun-if-changed={}", from.display());
    let Ok(bytes) = std::fs::read(from) else {
        std::fs::write(to, b"").expect("write placeholder");
        return;
    };
    let mut packed = Vec::new();
    let mut encoder = flate2::write::GzEncoder::new(&mut packed, flate2::Compression::new(6));
    encoder.write_all(&bytes).expect("compress");
    encoder.finish().expect("compress");
    if std::fs::read(to).ok().as_deref() != Some(&packed) {
        std::fs::write(to, packed).expect("write compressed tool");
    }
}

/// `MS_LLD`, else the one `scripts/fetch-lld.sh` leaves in `target/llvm-bundle`.
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
        "no lld to bundle: run `sh scripts/fetch-lld.sh` or set MS_LLD to a static lld"
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
