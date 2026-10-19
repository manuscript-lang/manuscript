//! Source file to native executable.

use crate::load;
use ms_mir::opt::{self, Level};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Pipeline options.
#[derive(Clone, Debug, Default)]
pub struct BuildOptions {
    /// Skip the MIR optimizer.
    pub no_opt: bool,
    /// Print MIR text to stderr.
    pub dump_mir: bool,
}

/// Failure of a stage; `Diagnostics` were already printed.
#[derive(Debug)]
pub enum BuildError {
    /// The program has checker diagnostics.
    Diagnostics,
    /// Lowering or code generation failed.
    Failed(String),
}

fn runtime_library() -> Result<PathBuf, String> {
    if let Ok(p) = std::env::var("MSRT_LIB") {
        return Ok(PathBuf::from(p));
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dir = exe.parent().ok_or("no executable directory")?;
    for d in [dir, dir.parent().unwrap_or(dir)] {
        let p = d.join("libms_rt.a");
        if p.exists() {
            return Ok(p);
        }
    }
    Err("libms_rt.a not found; build `cargo build -p ms-rt` or set MSRT_LIB".to_string())
}

/// Checks, lowers and compiles `source` into the executable `out`.
pub fn build(source: &Path, out: &Path, options: &BuildOptions) -> Result<(), BuildError> {
    let loaded = load::load(source);
    if !loaded.diagnostics.is_empty() {
        for d in &loaded.diagnostics {
            eprintln!("{d}");
        }
        return Err(BuildError::Diagnostics);
    }
    let program = loaded
        .program
        .ok_or_else(|| BuildError::Failed("no program".to_string()))?;
    let mut m = crate::lower_program(
        &program,
        &crate::Options {
            entry: loaded.entry.clone(),
        },
    )
    .map_err(|e| BuildError::Failed(format!("lowering: {e}")))?;
    if let Err(errs) = ms_mir::verify::verify_module(&m) {
        let text = errs
            .iter()
            .take(8)
            .map(|e| e.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        if options.dump_mir {
            eprintln!("{}", ms_mir::print::print_module(&m));
        }
        return Err(BuildError::Failed(format!(
            "MIR verification failed:\n{text}"
        )));
    }
    if !options.no_opt {
        opt::optimize(&mut m, Level::Speed, true);
    }
    if options.dump_mir {
        eprintln!("{}", ms_mir::print::print_module(&m));
    }
    let obj = ms_clif::compile(&m, &ms_clif::Options::default())
        .map_err(|e| BuildError::Failed(format!("codegen: {e}")))?;
    let objp = out.with_extension("o");
    std::fs::write(&objp, obj).map_err(|e| BuildError::Failed(e.to_string()))?;
    let rt = runtime_library().map_err(BuildError::Failed)?;
    ms_clif::link::link(&objp, &rt, out).map_err(|e| BuildError::Failed(e.to_string()))?;
    let _ = std::fs::remove_file(&objp);
    Ok(())
}

/// Builds into a temporary directory and runs; returns the program's exit status.
pub fn run(source: &Path, args: &[String], options: &BuildOptions) -> Result<i32, BuildError> {
    let dir = std::env::temp_dir().join(format!("msl-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| BuildError::Failed(e.to_string()))?;
    let exe = dir.join("program");
    let built = build(source, &exe, options);
    let result = built.and_then(|()| {
        let status = Command::new(&exe)
            .args(args)
            .status()
            .map_err(|e| BuildError::Failed(e.to_string()))?;
        Ok(status.code().unwrap_or(1))
    });
    let _ = std::fs::remove_dir_all(&dir);
    result
}
