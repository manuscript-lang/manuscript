//! Linux linking without a C toolchain: the wild linker, run in-process over the musl startup
//! objects and libc that Rust's musl target carries, producing a static executable.

use crate::Error;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

macro_rules! bundled {
    ($($name:literal),*) => {
        const FILES: &[(&str, &[u8])] = &[
            $(($name, include_bytes!(concat!(env!("OUT_DIR"), "/linker/", $name)))),*
        ];
    };
}
bundled!("crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a");

/// Links `object` and `inputs` (the musl-built runtime) into the static executable `out`.
pub fn link(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    let dir = extract()?;
    let mut args: Vec<OsString> = ["ld", "-static", "--gc-sections", "-o"]
        .map(OsString::from)
        .into();
    args.push(out.into());
    if strip {
        args.push("--strip-all".into());
    }
    args.extend([dir.join("crt1.o"), dir.join("crti.o"), object.to_path_buf()].map(OsString::from));
    args.push("--start-group".into());
    args.extend(inputs.iter().map(OsString::from));
    args.extend([dir.join("libunwind.a"), dir.join("libc.a")].map(OsString::from));
    args.push("--end-group".into());
    args.push(dir.join("crtn.o").into());

    let warnings = Arc::new(Mutex::new(Vec::<String>::new()));
    let failed = |detail: String| {
        Error(format!(
            "linking failed; the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:\n{detail}"
        ))
    };
    let run = || -> libwild::error::Result {
        let mut linker =
            libwild::Args::new(|| args.iter().map(|a| a.to_string_lossy().into_owned()))?;
        let sink = Arc::clone(&warnings);
        linker.on_warning(Box::new(move |warning: libwild::error::Warning| {
            sink.lock()
                .expect("warning list")
                .push(warning.warning().to_string());
        }));
        linker.parse(|| args.iter().map(|a| a.to_string_lossy().into_owned()))?;
        libwild::run(linker)
    };
    run().map_err(|e| {
        let mut detail = warnings.lock().expect("warning list").join("\n");
        if !detail.is_empty() {
            detail.push('\n');
        }
        detail.push_str(&format!("{e:?}"));
        failed(detail)
    })
}

/// Writes the bundled startup files and libc to a per-build cache entry, once.
fn extract() -> Result<PathBuf, Error> {
    let dir = cache_root()
        .join("ms")
        .join("linker")
        .join(env!("MS_LINKER_ID"));
    let present = |name: &str, bytes: &[u8]| {
        std::fs::metadata(dir.join(name)).is_ok_and(|m| m.len() == bytes.len() as u64)
    };
    if FILES.iter().all(|(name, bytes)| present(name, bytes)) {
        return Ok(dir);
    }
    let failed = |e: std::io::Error| {
        Error(format!(
            "cannot unpack the linker support files into {}: {e}",
            dir.display()
        ))
    };
    std::fs::create_dir_all(&dir).map_err(failed)?;
    // Staged beside the destination so concurrent builds never see a partial file; the counter
    // keeps threads of one process from sharing a staged file.
    static STAGED: AtomicUsize = AtomicUsize::new(0);
    for (name, bytes) in FILES.iter().filter(|(name, bytes)| !present(name, bytes)) {
        let staged = dir.join(format!(
            ".{name}-{}-{}",
            std::process::id(),
            STAGED.fetch_add(1, Ordering::Relaxed)
        ));
        let written =
            std::fs::write(&staged, bytes).and_then(|()| std::fs::rename(&staged, dir.join(name)));
        written.map_err(|e| {
            let _ = std::fs::remove_file(&staged);
            failed(e)
        })?;
    }
    Ok(dir)
}

/// `$XDG_CACHE_HOME`, else `$HOME/.cache`, else the temporary directory.
fn cache_root() -> PathBuf {
    let set = |name| {
        std::env::var_os(name)
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
    };
    set("XDG_CACHE_HOME")
        .or_else(|| set("HOME").map(|home| home.join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
}
