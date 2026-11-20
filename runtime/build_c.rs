//! The C half of the runtime build, shared by `cargo xtask runtime` (crates/xtask) and the build script of `ms-rt`
//! (crates/ms-rt/build.rs), which both include this file with `#[path]`: which C sources a target compiles, which
//! libraries they need (found through `runtime/third_party/libs.sh`), and the objects, library members included.
//! No `cc` crate: the compilers are run directly.
#![allow(dead_code)]

use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::Command;

/// What `add_c_runtime` compiles and folds into one runtime archive: the C sources for the target, the flags
/// that find the libraries' headers, and the static archives of every library those sources include.
pub struct CRuntime {
    pub sources: Vec<PathBuf>,
    pub cflags: Vec<String>,
    /// Static archives of the libraries the sources use, to fold into the runtime archive.
    pub libraries: Vec<PathBuf>,
}

impl CRuntime {
    /// Whether `runtime/std/<name>` is part of the archive.
    pub fn has_std_source(&self, root: &Path, name: &str) -> bool {
        let wanted = root.join("runtime/std").join(name);
        self.sources.contains(&wanted)
    }

    /// Whether the libuv reactor (`runtime/io`) is part of the archive; `ms-rt` then leaves its mio poller out.
    pub fn has_reactor(&self, root: &Path) -> bool {
        let io = root.join("runtime/io");
        self.sources.iter().any(|s| s.starts_with(&io))
    }
}

/// The library names (as `libs.sh` knows them) whose headers `source` includes, directly or through a header
/// of its own folder.
pub fn libraries_of(source: &Path) -> Vec<&'static str> {
    const HEADERS: [(&str, &[&str]); 6] = [
        ("<uv.h>", &["uv"]),
        ("<llhttp.h>", &["llhttp"]),
        ("<nghttp2/", &["nghttp2"]),
        ("<openssl/", &["ssl", "crypto"]),
        ("<pcre2.h>", &["pcre2"]),
        ("<zlib.h>", &["z"]),
    ];
    let mut text = std::fs::read_to_string(source).unwrap_or_default();
    let local: Vec<String> = text
        .lines()
        .filter_map(|l| l.trim().strip_prefix("#include \""))
        .filter_map(|l| l.split('"').next())
        .map(str::to_string)
        .collect();
    for header in local {
        if let Some(dir) = source.parent() {
            text.push_str(&std::fs::read_to_string(dir.join(header)).unwrap_or_default());
        }
    }
    let mut found = Vec::new();
    for (include, names) in HEADERS {
        if text.contains(&format!("#include {include}")) {
            found.extend_from_slice(names);
        }
    }
    found
}

/// The C compiler for the musl runtime: musl's own headers decide how libuv and OpenSSL compile (`musl-tools`).
pub fn musl_compiler() -> PathBuf {
    std::env::var_os("MS_MUSL_CC").map_or_else(|| PathBuf::from("musl-gcc"), PathBuf::from)
}

/// Runs `libs.sh` (the one place that names library paths) for `triple`. The musl archive takes pinned builds
/// made with the musl compiler (system packages are glibc's); the others take the system packages.
pub fn libs_sh(root: &Path, triple: Option<&str>, args: &[&str]) -> Result<Vec<String>, String> {
    let mut command = Command::new("sh");
    if triple.is_some_and(|t| t.contains("musl")) {
        command
            .env("MS_C_LIBS", "pinned")
            .env("CC", musl_compiler());
    }
    command
        .arg(root.join("runtime/third_party/libs.sh"))
        .args(args);
    if let Some(t) = triple {
        command.env("MS_C_TRIPLE", t);
    }
    let output = command.output().map_err(|e| format!("run libs.sh: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "libs.sh {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .map(str::to_string)
        .collect())
}

/// Whether the C libraries are wired for `triple`. Each target joins as its build is proven (workstream W0b);
/// a source that needs a library the target lacks stays out of that archive and the Rust runtime serves it.
pub fn c_libs_wired(triple: Option<&str>) -> bool {
    match std::env::consts::OS {
        "linux" => triple.is_none_or(|t| t.ends_with("linux-gnu") || t.ends_with("linux-musl")),
        "macos" => true,
        _ => false,
    }
}

/// Folders of `runtime` that hold code for one platform only: the target's own is compiled, the rest are not.
pub fn platform_dirs(triple: Option<&str>) -> Vec<&'static str> {
    let t = triple.map(str::to_string).unwrap_or_else(|| {
        format!(
            "{}-{}",
            std::env::consts::ARCH,
            match std::env::consts::OS {
                "linux" => "unknown-linux-gnu",
                "macos" => "apple-darwin",
                _ => "pc-windows-gnullvm",
            }
        )
    });
    let mut dirs = Vec::new();
    if t.contains("linux") || t.contains("apple") {
        dirs.push("posix");
    }
    if t.contains("linux") {
        dirs.push("linux");
    }
    if t.ends_with("linux-gnu") {
        dirs.push("glibc");
    }
    if t.contains("musl") {
        dirs.push("musl");
    }
    if t.contains("apple") {
        dirs.push("darwin");
    }
    if t.contains("windows") {
        dirs.push("windows");
    }
    dirs
}

/// Every C source of the runtime (`runtime/{sys,core,io,net,std}`; `third_party` and `tests` are not part of it).
/// A folder named for a platform (`posix` for Linux and macOS, `linux`, `glibc`, `musl`, `darwin`, `windows`) is compiled only for it.
pub fn c_sources(dir: &Path, platform: &[&str], found: &mut Vec<PathBuf>) {
    const PLATFORMS: [&str; 6] = ["posix", "linux", "glibc", "musl", "darwin", "windows"];
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if path.is_dir() {
            let other = PLATFORMS.contains(&name.as_ref()) && !platform.contains(&name.as_ref());
            if name != "third_party" && name != "tests" && !other {
                c_sources(&path, platform, found);
            }
        } else if path.extension().is_some_and(|e| e == "c") {
            found.push(path);
        }
    }
}

/// Plans the C half of the runtime archive for `triple`.
pub fn plan_c_runtime(root: &Path, triple: Option<&str>) -> Result<CRuntime, String> {
    let runtime = root.join("runtime");
    let platform = platform_dirs(triple);
    let mut sources = Vec::new();
    for layer in ["sys", "core", "io", "net", "std"] {
        c_sources(&runtime.join(layer), &platform, &mut sources);
    }
    sources.sort();
    let wired = c_libs_wired(triple);
    // The libuv reactor replaces the mio poller. It joins the glibc Linux archive, where the corpus passes with
    // it; musl, macOS and Windows keep mio until their builds are proven (workstream W5).
    let io = runtime.join("io");
    let reactor = platform.contains(&"glibc");
    sources.retain(|s| (wired || libraries_of(s).is_empty()) && (reactor || !s.starts_with(&io)));
    // The PCRE2 regex natives change the pattern dialect, so they join every target together (workstream W8):
    // opt-in with `MS_C_REGEX=1` until Windows has the libraries too. Removal: delete this filter with `ms-std-regex`.
    let regex = std::env::var_os("MS_C_REGEX").is_some();
    sources.retain(|s| {
        regex
            || !s
                .file_name()
                .is_some_and(|n| n.to_string_lossy().starts_with("regex"))
    });
    let mut names: Vec<&str> = sources.iter().flat_map(|s| libraries_of(s)).collect();
    names.sort_unstable();
    names.dedup();
    if names.is_empty() {
        return Ok(CRuntime {
            sources,
            cflags: Vec::new(),
            libraries: Vec::new(),
        });
    }
    let cflags = libs_sh(root, triple, &["cflags"])?;
    let mut args = vec!["archives"];
    args.extend(&names);
    let libraries = libs_sh(root, triple, &args)?
        .into_iter()
        .map(PathBuf::from)
        .collect();
    Ok(CRuntime {
        sources,
        cflags,
        libraries,
    })
}

/// The archiver for `triple`: llvm-mingw's on Windows, else `ar`.
pub fn archiver(root: &Path, triple: Option<&str>) -> PathBuf {
    match triple {
        Some(t) if t.contains("windows") => c_compiler(root, t, std::env::consts::ARCH)
            .with_file_name(format!("llvm-ar{}", std::env::consts::EXE_SUFFIX)),
        _ => PathBuf::from("ar"),
    }
}

/// Compiles the planned C sources for `triple` under `work` and returns the objects: ours, and every member of
/// the libraries they use (the linker takes a member only when a program reaches it). The objects define the
/// symbols the Rust runtime compiles out (`runtime/symbols/<module>.txt`).
pub fn compile_c_objects(
    root: &Path,
    work: &Path,
    triple: Option<&str>,
    plan: &CRuntime,
) -> Result<Vec<PathBuf>, String> {
    let runtime = root.join("runtime");
    if plan.sources.is_empty() {
        return Ok(Vec::new());
    }
    let arch = std::env::consts::ARCH;
    let host = triple.is_none_or(|t| t.ends_with("linux-gnu"));
    let cc = match triple {
        Some(t) if t.contains("windows") => c_compiler(root, t, arch),
        Some(t) if t.contains("musl") => musl_compiler(),
        _ => PathBuf::from("clang"),
    };
    let objects = work.join("c-objects");
    let _ = std::fs::remove_dir_all(&objects);
    std::fs::create_dir_all(&objects).map_err(|e| e.to_string())?;
    let mut files = Vec::new();
    for (n, source) in plan.sources.iter().enumerate() {
        let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("x");
        let object = objects.join(format!("{n}-{stem}.o"));
        let mut command = Command::new(&cc);
        command
            .args(["-c", "-O2", "-std=c11", "-fPIC", "-fno-stack-protector"])
            // A null check stays even where an attribute says the pointer is never null.
            .args(["-fno-strict-aliasing", "-fno-delete-null-pointer-checks"])
            // A fault walks frame pointers to name the program line that called into the runtime, and
            // the Rust runtime is built with them (.cargo/config.toml), so C frames must keep theirs.
            .arg("-fno-omit-frame-pointer")
            .args(["-Wall", "-Wextra", "-Werror"])
            .arg("-I")
            .arg(runtime.join("include"))
            .arg("-I")
            .arg(source.parent().unwrap_or(&runtime))
            .args(&plan.cflags)
            .arg("-o")
            .arg(&object)
            .arg(source);
        // glibc and macOS check libc calls whose destination size is known (documentation/contributing/c-style.md).
        // Level 2: its `__*_chk` entry points are all older than the glibc floor.
        if !triple.is_some_and(|t| t.contains("windows") || t.contains("musl")) {
            command.arg("-D_FORTIFY_SOURCE=2");
        }
        // `musl-gcc` already targets musl, and llvm-mingw's clang wrapper mingw-w64 (Rust's `gnullvm` is not a
        // clang environment); a clang for another target needs it named.
        if let Some(t) = triple.filter(|t| !host && !t.contains("musl") && !t.contains("windows")) {
            command.arg(format!("--target={t}"));
        }
        let status = command
            .status()
            .map_err(|e| format!("run {}: {e}", cc.display()))?;
        if !status.success() {
            return Err(format!("compiling {} failed", source.display()));
        }
        files.push(object);
    }
    let ar = archiver(root, triple);
    let run_ar = |args: &[&OsStr], dir: &Path| -> Result<std::process::Output, String> {
        Command::new(&ar)
            .args(args)
            .current_dir(dir)
            .output()
            .map_err(|e| format!("run {}: {e}", ar.display()))
    };
    // Each library's members are extracted under a prefix naming the library, so equal member names in two
    // libraries stay apart (`ar rcs` replaces by name). A library with equal names inside itself cannot be
    // extracted whole; that is reported, not folded wrong.
    for (n, library) in plan.libraries.iter().enumerate() {
        let dir = objects.join(format!("lib{n}"));
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let listing = run_ar(&["t".as_ref(), library.as_os_str()], &dir)?;
        if !listing.status.success() {
            return Err(format!("listing {} failed", library.display()));
        }
        let members: Vec<String> = String::from_utf8_lossy(&listing.stdout)
            .lines()
            .filter(|m| m.ends_with(".o") || m.ends_with(".obj"))
            .map(str::to_string)
            .collect();
        let mut unique = members.clone();
        unique.sort();
        unique.dedup();
        if unique.len() != members.len() {
            return Err(format!(
                "{} has members with equal names",
                library.display()
            ));
        }
        let extracted = run_ar(&["x".as_ref(), library.as_os_str()], &dir)?;
        if !extracted.status.success() {
            return Err(format!("extracting {} failed", library.display()));
        }
        let stem = library
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("lib");
        for member in &members {
            let renamed = dir.join(format!("{stem}.{member}"));
            std::fs::rename(dir.join(member), &renamed).map_err(|e| format!("{member}: {e}"))?;
            files.push(renamed);
        }
    }
    Ok(files)
}

/// The C compiler for the runtime's C sources: `cc` where the target is Linux, else llvm-mingw's clang
/// (`MS_MINGW`, else the tree `toolchain/fetch-mingw.sh` leaves in `target/llvm-bundle/mingw`).
pub fn c_compiler(root: &Path, triple: &str, arch: &str) -> PathBuf {
    if !triple.contains("windows") {
        return PathBuf::from("cc");
    }
    let mingw = std::env::var_os("MS_MINGW")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("target/llvm-bundle/mingw"));
    mingw.join("bin").join(format!("{arch}-w64-mingw32-clang"))
}
