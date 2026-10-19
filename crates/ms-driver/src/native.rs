//! MIR to executable: optimize, generate Cranelift code, link with the runtime.

use std::path::{Path, PathBuf};

use ms_clif::Options;
use ms_mir::ir::Module;
use ms_mir::opt::{Level, optimize};

/// The native build levels, in the CMake spelling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profile {
    Debug,
    Release,
    RelWithDebInfo,
    MinSizeRel,
}

impl Profile {
    fn options(self) -> (Level, Options) {
        let mut options = Options::default();
        let level = match self {
            // Debug keeps every check and skips MIR and Cranelift optimization so
            // locals and line tables stay faithful.
            Profile::Debug => {
                options.opt_level = "none";
                Level::None
            }
            Profile::Release | Profile::RelWithDebInfo => Level::Speed,
            Profile::MinSizeRel => {
                options.opt_level = "speed_and_size";
                Level::Speed
            }
        };
        (level, options)
    }
}

/// Where the runtime static library is found, in order: `MS_RT_LIB`, next to
/// the running executable (and one level up, for cargo's `deps` directory).
pub fn locate_runtime() -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os("MS_RT_LIB") {
        let path = PathBuf::from(path);
        return if path.is_file() {
            Ok(path)
        } else {
            Err(format!(
                "MS_RT_LIB={} does not name a file; point it at libms_rt.a",
                path.display()
            ))
        };
    }
    if let Ok(exe) = std::env::current_exe() {
        for directory in exe.ancestors().skip(1).take(2) {
            let candidate = directory.join("libms_rt.a");
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }
    Err("cannot find the Manuscript runtime library libms_rt.a next to ms; build it with 'cargo build -p ms-rt' or set MS_RT_LIB".to_string())
}

/// Optimize `module`, generate code and link the executable at `output`. The
/// executable replaces `output` only when the whole build succeeds.
pub fn build_executable(
    module: &mut Module,
    output: &Path,
    profile: Profile,
    runtime: &Path,
) -> Result<(), String> {
    if let Err(errors) = ms_mir::verify::verify_module(module) {
        let text: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
        return Err(format!(
            "the compiler produced invalid code (this is a Manuscript bug, so report it with the source that triggers it):\n{}",
            text.join("\n")
        ));
    }
    let (level, options) = profile.options();
    optimize(module, level, cfg!(debug_assertions));
    let object = ms_clif::compile(module, &options).map_err(|e| e.to_string())?;

    let directory = output
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let stem = format!(".ms-build-{}", std::process::id());
    let object_path = directory.join(format!("{stem}.o"));
    let staged = directory.join(format!("{stem}.exe"));
    let cleanup = || {
        let _ = std::fs::remove_file(&object_path);
        let _ = std::fs::remove_file(&staged);
    };
    if let Err(error) = std::fs::write(&object_path, object) {
        cleanup();
        return Err(format!("cannot write {}: {error}", object_path.display()));
    }
    let linked = ms_clif::link::link_all(&object_path, &[runtime], &staged);
    let _ = std::fs::remove_file(&object_path);
    if let Err(error) = linked {
        cleanup();
        return Err(error.to_string());
    }
    std::fs::rename(&staged, output).map_err(|error| {
        cleanup();
        format!("cannot write {}: {error}", output.display())
    })
}
