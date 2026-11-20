//! The C back end (`MS_BACKEND=c`): the lowered module goes to `ms_mir_build` as MIR text, which
//! runs the optimizer and finishing passes and prints QBE text (debug) or LLVM IR (release); the
//! text is then assembled into the object the linker takes. Opt-in while the C emitters cover
//! less than Cranelift; a program they cannot write fails with the reason instead of falling back,
//! so the corpus diff (`compiler/tests/build-diff.sh`) counts the gaps.
//!
//! Tools come from `MS_C_BACKEND_DIR` (a folder holding `ms_mir_build` and `qbe`), else from the
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
            "MS_BACKEND=c needs {}; set MS_C_BACKEND_DIR to a folder with ms_mir_build and qbe",
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

/// Compiles `module` to an object file with the C pipeline. `llvm` selects the release emitter.
pub fn compile(module: &Module, speed: bool, llvm: bool, checks: bool) -> Result<Vec<u8>, String> {
    let dir = std::env::temp_dir().join(format!("ms-cbackend-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let result = compile_in(&dir, module, speed, llvm, checks);
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn compile_in(
    dir: &Path,
    module: &Module,
    speed: bool,
    llvm: bool,
    checks: bool,
) -> Result<Vec<u8>, String> {
    let mir = dir.join("program.mir");
    std::fs::write(&mir, ms_mir::print::print_module(module))
        .map_err(|e| format!("cannot write {}: {e}", mir.display()))?;
    let mut build = Command::new(tool("ms_mir_build")?);
    build
        .arg(&mir)
        .args(["--backend", if llvm { "llvm" } else { "qbe" }])
        .args(["--opt", if speed { "speed" } else { "none" }]);
    if !checks {
        build.arg("--no-checks");
    }
    let text = run(&mut build, "ms_mir_build")?;
    let object = dir.join("program.o");
    if llvm {
        let ir = dir.join("program.ll");
        std::fs::write(&ir, text).map_err(|e| format!("cannot write {}: {e}", ir.display()))?;
        let opt = if speed { "-O3" } else { "-O0" };
        run(
            Command::new("clang")
                .args(["-c", opt, "-o"])
                .arg(&object)
                .arg(&ir),
            "clang",
        )?;
    } else {
        let target = match (std::env::consts::OS, std::env::consts::ARCH) {
            ("macos", "aarch64") => "arm64_apple",
            ("macos", _) => "amd64_apple",
            (_, "aarch64") => "arm64",
            _ => "amd64_sysv",
        };
        let ssa = dir.join("program.ssa");
        std::fs::write(&ssa, text).map_err(|e| format!("cannot write {}: {e}", ssa.display()))?;
        let asm = run(
            Command::new(tool("qbe")?).args(["-t", target]).arg(&ssa),
            "qbe",
        )?;
        let s = dir.join("program.s");
        std::fs::write(&s, asm).map_err(|e| format!("cannot write {}: {e}", s.display()))?;
        run(
            Command::new("cc").arg("-c").arg("-o").arg(&object).arg(&s),
            "cc",
        )?;
    }
    std::fs::read(&object).map_err(|e| format!("cannot read {}: {e}", object.display()))
}
