//! Compiles LLVM IR text to an object file.

use ms_clif::link::llvm_tools;
use ms_clif::{BuildOptions, Error};
use ms_mir_llvm::Unit;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Whether release builds can use LLVM: the tools are fetched or named by `build.llvm_tools`.
pub fn available(build: &BuildOptions) -> bool {
    llvm_tools(build).is_ok_and(|tools| tools.is_some())
}

fn run(mut c: Command, what: &str) -> Result<(), Error> {
    let o = c
        .output()
        .map_err(|e| Error(format!("cannot run {what}: {e}")))?;
    // LLVM drops malformed debug info with a warning; that would silently lose line tables.
    let invalid = String::from_utf8_lossy(&o.stderr).contains("invalid debug info");
    if o.status.success() && !invalid {
        return Ok(());
    }
    Err(Error(format!(
        "{what} failed ({}):\n{}",
        o.status,
        String::from_utf8_lossy(&o.stderr).trim_end()
    )))
}

/// An optimized object in a scratch directory, removed on drop.
pub struct LlvmObject {
    dir: PathBuf,
    obj: PathBuf,
}

impl Drop for LlvmObject {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Optimizes and assembles each of `irs` at `-O<level>`, one thread per module.
pub fn compile_all(
    irs: &[Unit],
    level: &str,
    build: &BuildOptions,
) -> Result<Vec<LlvmObject>, Error> {
    compile_numbered(irs, level, build, 0)
}

/// Like [`compile_all`] for modules numbered from `first` in the program (their names and kept
/// IR files must not collide with the earlier ones).
pub fn compile_numbered(
    irs: &[Unit],
    level: &str,
    build: &BuildOptions,
    first: usize,
) -> Result<Vec<LlvmObject>, Error> {
    if let [unit] = irs {
        return Ok(vec![compile(unit, level, build, first)?]);
    }
    std::thread::scope(|scope| {
        let jobs: Vec<_> = irs
            .iter()
            .enumerate()
            .map(|(k, unit)| scope.spawn(move || compile(unit, level, build, first + k)))
            .collect();
        jobs.into_iter()
            .map(|job| {
                job.join()
                    .unwrap_or_else(|_| Err(Error("LLVM compile thread panicked".into())))
            })
            .collect()
    })
}

/// Optimizes and assembles `ir`, unit number `unit` of the program, at `-O<level>`.
fn compile(
    module: &Unit,
    level: &str,
    build: &BuildOptions,
    unit: usize,
) -> Result<LlvmObject, Error> {
    let ir = module.ir.as_str();
    let dir: PathBuf = std::env::temp_dir().join(format!(
        "ms-llvm-{}-{}-{unit}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    std::fs::create_dir_all(&dir).map_err(|e| Error(format!("create {}: {e}", dir.display())))?;
    let (ll, obj) = (dir.join("m.ll"), dir.join("llvm.o"));
    let this = LlvmObject {
        dir: dir.clone(),
        obj: obj.clone(),
    };
    // LLVM 20 and later dropped the `Os` pipeline: it is `O2` with `optsize` on every function.
    let sized;
    let ir = if level == "s" {
        sized = ir
            .replace("attributes #0 = { ", "attributes #0 = { optsize ")
            .replace("attributes #1 = { ", "attributes #1 = { optsize ");
        &sized
    } else {
        ir
    };
    std::fs::write(&ll, ir).map_err(|e| Error(e.to_string()))?;
    if build.keep_ll {
        let _ = std::fs::copy(
            &ll,
            if unit == 0 {
                "ms-keep.ll".to_string()
            } else {
                format!("ms-keep-{unit}.ll")
            },
        );
    }
    let tools = llvm_tools(build)?.ok_or_else(|| {
        Error(
            "no LLVM tools are available for this platform; set MS_LLVM_TOOLS to a directory with opt, llc and llvm-link".into(),
        )
    })?;
    // What `clang -O<level>` does for IR input: the default pipeline, then code generation.
    let (pipeline, codegen) = match level {
        "s" => ("default<O2>", "-O2"),
        _ => (&*format!("default<O{level}>"), &*format!("-O{level}")),
    };
    // A unit of `optnone` functions is code generated at `-O0` (fast instruction selection and
    // register allocation, linear in the function's size); `llc -O2` would still run the greedy
    // allocator, which is superlinear (`Unit::unoptimized`).
    let codegen = if module.unoptimized { "-O0" } else { codegen };
    let bitcode = dir.join("m.bc");
    let tool =
        |name: &str| Command::new(tools.join(format!("{name}{}", std::env::consts::EXE_SUFFIX)));
    let input = ll;
    let mut opt = tool("opt");
    if !build.vectorize {
        opt.args(["-vectorize-loops=false", "-vectorize-slp=false"]);
    }
    if build.llvm_verify {
        opt.arg("-verify-each");
    }
    opt.arg(format!("-passes={pipeline}"))
        .arg(&input)
        .arg("-o")
        .arg(&bitcode);
    run(opt, "opt (LLVM optimizer)")?;
    let mut llc = tool("llc");
    // The line tables address every function from one anchor, so code must stay in a single section; without this
    // LLVM 20 and later move functions that only reach a noreturn call into `.text.unlikely.`.
    llc.args([
        codegen,
        "-filetype=obj",
        "-relocation-model=pic",
        "-profile-guided-section-prefix=false",
        // The debug info is line tables only (no variables), so tracking variable locations is
        // dead work: object bytes are identical and `llc` runs about 18% faster.
        "-live-debug-variables=false",
    ])
    .arg(&bitcode)
    .arg("-o")
    .arg(&obj);
    if cfg!(target_arch = "x86_64") {
        // Start every loop on a 32-byte boundary. At the default 16 a small loop may straddle a
        // 32-byte or cache-line boundary depending on where the linker put the function, which
        // slowed a five-instruction loop 2x when the runtime grew (#1871).
        llc.arg("-align-loops=32");
        // Name the portable baseline CPU. LLVM's unnamed "generic" CPU dropped the tuning that
        // guards a 64-bit divide with a cheap 32-bit one when both operands are small, which
        // rustc and clang keep for `x86-64` (the trial-division loop in `workers` ran 1.4x slower).
        llc.arg("-mcpu=x86-64");
    }
    run(llc, "llc (LLVM code generator)")?;
    Ok(this)
}

impl LlvmObject {
    /// The object file `llc` wrote, whose DWARF the line tables are rebuilt from.
    pub fn path(&self) -> &Path {
        &self.obj
    }

    /// The object's bytes.
    pub fn bytes(&self) -> Result<Vec<u8>, Error> {
        std::fs::read(&self.obj).map_err(|e| Error(e.to_string()))
    }
}
