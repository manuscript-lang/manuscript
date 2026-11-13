//! Compiles LLVM IR text to an object file.

use crate::link::llvm_tools;
use crate::llvm_ir::Unit;
use crate::{BuildOptions, Error, RtHot};
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
    if let [unit] = irs {
        return Ok(vec![compile(unit, level, build, 0)?]);
    }
    std::thread::scope(|scope| {
        let jobs: Vec<_> = irs
            .iter()
            .enumerate()
            .map(|(k, unit)| scope.spawn(move || compile(unit, level, build, k)))
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
    let mut input = ll;
    if let Some(hot) = hot_library(build, &dir, &tools, ir) {
        // The runtime's pure helpers (`ms-rt-hot`): only the definitions the program calls are
        // linked, internalized so the archive's copies stay the only exported ones, and LLVM
        // inlines them.
        let linked = dir.join("linked.bc");
        let mut link = tool("llvm-link");
        link.args(["--only-needed", "--internalize"])
            .arg(&input)
            .arg(&hot)
            .arg("-o")
            .arg(&linked);
        run(link, "llvm-link (runtime helpers)")?;
        input = linked;
    }
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
    }
    run(llc, "llc (LLVM code generator)")?;
    Ok(this)
}

/// The runtime helper IR written into `dir`, or `None` when this `ms` has none, `build.rt_hot` turns
/// it off or names another file, `llvm-link` is not in `tools`, or the `program` IR calls none of
/// the helpers (linking would only cost time).
fn hot_library(build: &BuildOptions, dir: &Path, tools: &Path, program: &str) -> Option<PathBuf> {
    let custom = match &build.rt_hot {
        RtHot::Embedded => None,
        RtHot::Off => return None,
        RtHot::File(path) => std::fs::read_to_string(path).ok(),
    };
    let ir = custom.as_deref().unwrap_or(crate::link::RUNTIME_HOT_IR);
    let linker = tools.join(format!("llvm-link{}", std::env::consts::EXE_SUFFIX));
    if ir.is_empty() || !linker.is_file() || !calls_hot_helper(ir, program) {
        return None;
    }
    let path = dir.join("ms_rt_hot.ll");
    std::fs::write(&path, ir).ok()?;
    Some(path)
}

/// Whether `program` mentions a function that `hot` defines under a runtime symbol name.
fn calls_hot_helper(hot: &str, program: &str) -> bool {
    hot.lines()
        .filter(|line| line.starts_with("define "))
        .filter_map(|line| line.split("@msrt_").nth(1))
        .filter_map(|rest| rest.split('(').next())
        .any(|name| program.contains(&format!("@\"msrt_{name}\"")))
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

#[cfg(test)]
mod tests {
    use super::*;

    const HOT: &str = "define noundef i64 @msrt_map_length(i64 noundef %m) alwaysinline #0 {\n\
                       define internal i64 @_ZN6ms_rt_hot3foo() #1 {\n";

    #[test]
    fn links_only_programs_that_name_a_defined_helper() {
        assert!(calls_hot_helper(
            HOT,
            "%t = call i64 @\"msrt_map_length\"(i64 %m)"
        ));
        assert!(!calls_hot_helper(
            HOT,
            "declare i64 @\"msrt_map_length_other\"(i64)"
        ));
        assert!(!calls_hot_helper(HOT, "call void @\"msrt_print\"()"));
    }
}
