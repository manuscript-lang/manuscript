//! The C back end (`MS_BACKEND=c`): the lowered module goes to `ms_mir_build` as MIR text, which
//! runs the optimizer and finishing passes and prints LLVM IR (debug and release); clang
//! assembles it into the object the linker takes. Opt-in while the C emitters cover
//! less than Cranelift; a program they cannot write fails with the reason instead of falling back,
//! so the corpus diff (`compiler/tests/build-diff.sh`) counts the gaps.
//!
//! Tools come from `MS_C_BACKEND_DIR` (a folder holding `ms_mir_build` and `ms_asm_tables`), else from the
//! folder of the running `ms`.

use std::path::{Path, PathBuf};
use std::process::Command;

use ms_mir::ir::Module;

/// Whether `MS_BACKEND=c` asks for the C back end.
pub fn enabled() -> bool {
    std::env::var("MS_BACKEND").is_ok_and(|v| v == "c")
}

fn tool(name: &str) -> Result<PathBuf, String> {
    let exe = if cfg!(windows) { ".exe" } else { "" };
    let dir = match std::env::var_os("MS_C_BACKEND_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(Path::to_path_buf))
            .ok_or("cannot find the folder of ms; set MS_C_BACKEND_DIR")?,
    };
    let path = dir.join(format!("{name}{exe}"));
    if path.is_file() {
        Ok(path)
    } else {
        Err(format!(
            "MS_BACKEND=c needs {}; set MS_C_BACKEND_DIR to a folder with ms_mir_build and ms_asm_tables",
            path.display()
        ))
    }
}

fn run(command: &mut Command, what: &str) -> Result<Vec<u8>, String> {
    let output = command
        .output()
        .map_err(|e| format!("cannot run {what}: {e}"))?;
    if output.status.success() {
        Ok(output.stdout)
    } else {
        Err(format!(
            "{what} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim_end()
        ))
    }
}

/// Compiles `module` to an object file with the C pipeline.
pub fn compile(
    module: &Module,
    speed: bool,
    checks: bool,
    keep_ll: bool,
) -> Result<Vec<u8>, String> {
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "ms-cbackend-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let result = compile_in(&dir, module, speed, checks, keep_ll);
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn compile_in(
    dir: &Path,
    module: &Module,
    speed: bool,
    checks: bool,
    keep_ll: bool,
) -> Result<Vec<u8>, String> {
    let mir = dir.join("program.mir");
    std::fs::write(&mir, ms_mir::print::print_module_unique(module))
        .map_err(|e| format!("cannot write {}: {e}", mir.display()))?;
    let mut build = Command::new(tool("ms_mir_build")?);
    build
        .arg(&mir)
        .args(["--opt", if speed { "speed" } else { "none" }]);
    if !checks {
        build.arg("--no-checks");
    }
    let meta = dir.join("program.meta");
    build.arg("--tables-meta").arg(&meta);
    let names = dir.join("program.names");
    std::fs::write(&names, ms_mir::print::display_names(module))
        .map_err(|e| format!("cannot write {}: {e}", names.display()))?;
    build.arg("--display-names").arg(&names);
    let ir_text = run(&mut build, "ms_mir_build")?;
    let ir = dir.join("program.ll");
    std::fs::write(&ir, ir_text).map_err(|e| format!("cannot write {}: {e}", ir.display()))?;
    if keep_ll {
        std::fs::copy(&ir, "ms-keep.ll").map_err(|e| format!("cannot write ms-keep.ll: {e}"))?;
    }
    let plain = dir.join("program.plain.s");
    let opt = if speed { "-O3" } else { "-O0" };
    run(
        Command::new("clang")
            .args(["-S", opt, "-o"])
            .arg(&plain)
            .arg(&ir),
        "clang",
    )?;
    // The fault tables: ms_asm_tables labels the assembly and appends them (no debug info is read).
    // The `.loc` lines are dropped afterwards, so the object carries no line tables.
    let mut tables = Command::new(tool("ms_asm_tables")?);
    tables.arg(&meta).arg(&plain).arg("--strip-lines");
    if std::env::consts::OS == "macos" {
        tables.args(["--prefix", "_"]);
    }
    let asm = run(&mut tables, "ms_asm_tables")?;
    let s = dir.join("program.s");
    std::fs::write(&s, asm).map_err(|e| format!("cannot write {}: {e}", s.display()))?;
    let object = dir.join("program.o");
    run(
        Command::new("clang")
            .arg("-c")
            .arg("-o")
            .arg(&object)
            .arg(&s),
        "clang",
    )?;
    std::fs::read(&object).map_err(|e| format!("cannot read {}: {e}", object.display()))
}
