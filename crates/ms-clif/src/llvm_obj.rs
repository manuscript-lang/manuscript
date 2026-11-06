//! Compiles LLVM IR text to object files with the bundled `opt`, `llc` and `llvm-link`.
//!
//! A small module is one object: link the runtime helpers, optimize, generate code. A large one
//! is compiled in parallel without giving up cross-function optimization: a single whole-program
//! inlining pass runs first, `llvm-split` then cuts the result into parts, and each part is
//! optimized and assembled on its own thread.

use crate::link::llvm_tools;
use crate::{BuildOptions, Error, RtHot};
use std::path::{Path, PathBuf};
use std::process::Command;

/// The pass that runs over the whole program before it is split, so a function can be inlined
/// into callers that end up in other parts. Everything else runs per part.
const WHOLE_PROGRAM_PASSES: &str = "cgscc(inline)";

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

/// A fresh scratch directory under the system temp directory.
fn scratch_dir(label: &str) -> Result<PathBuf, Error> {
    let dir = std::env::temp_dir().join(format!(
        "ms-llvm-{}-{}-{label}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    std::fs::create_dir_all(&dir).map_err(|e| Error(format!("create {}: {e}", dir.display())))?;
    Ok(dir)
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

/// The intermediate files of one compilation; removed on drop.
struct Workspace(PathBuf);

impl Drop for Workspace {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// The directory of LLVM tools, with a constructor for each command.
struct Tools(PathBuf);

impl Tools {
    fn locate(build: &BuildOptions) -> Result<Tools, Error> {
        let dir = llvm_tools(build)?.ok_or_else(|| {
            Error(
                "no LLVM tools are available for this platform; set MS_LLVM_TOOLS to a directory with opt, llc, llvm-link and llvm-split".into(),
            )
        })?;
        Ok(Tools(dir))
    }

    fn command(&self, name: &str) -> Command {
        Command::new(
            self.0
                .join(format!("{name}{}", std::env::consts::EXE_SUFFIX)),
        )
    }
}

/// Optimizes and assembles `ir` at `-O<level>` into `parts` objects, one per thread. One part is
/// the whole module; more are cut from it after a whole-program inlining pass.
pub fn compile(
    ir: &str,
    parts: usize,
    level: &str,
    build: &BuildOptions,
) -> Result<Vec<LlvmObject>, Error> {
    let tools = Tools::locate(build)?;
    let workspace = Workspace(scratch_dir("work")?);
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
    let source = workspace.0.join("m.ll");
    std::fs::write(&source, ir).map_err(|e| Error(e.to_string()))?;
    if build.keep_ll {
        let _ = std::fs::copy(&source, "ms-keep.ll");
    }
    let program = link_runtime_helpers(&tools, build, &workspace.0, source, ir)?;
    if parts <= 1 {
        return Ok(vec![assemble(&tools, level, build, &program)?]);
    }
    let pieces = split(&tools, &workspace.0, &program, parts)?;
    std::thread::scope(|scope| {
        let jobs: Vec<_> = pieces
            .iter()
            .map(|piece| scope.spawn(|| assemble(&tools, level, build, piece)))
            .collect();
        jobs.into_iter()
            .map(|job| {
                job.join()
                    .unwrap_or_else(|_| Err(Error("LLVM compile thread panicked".into())))
            })
            .collect()
    })
}

/// Links the runtime's pure helpers (`ms-rt-hot`) into `program`: only the definitions it calls
/// are linked, internalized so the archive's copies stay the only exported ones, and LLVM inlines
/// them. Returns the module to optimize, which is `program` itself when nothing is linked.
fn link_runtime_helpers(
    tools: &Tools,
    build: &BuildOptions,
    dir: &Path,
    program: PathBuf,
    ir: &str,
) -> Result<PathBuf, Error> {
    let Some(hot) = hot_library(build, dir, &tools.0, ir) else {
        return Ok(program);
    };
    let linked = dir.join("linked.bc");
    let mut link = tools.command("llvm-link");
    link.args(["--only-needed", "--internalize"])
        .arg(&program)
        .arg(&hot)
        .arg("-o")
        .arg(&linked);
    run(link, "llvm-link (runtime helpers)")?;
    Ok(linked)
}

/// Runs the whole-program pass over `program` and cuts it into `parts` modules of similar size.
/// Symbols that parts share are made external and renamed by `llvm-split`.
fn split(tools: &Tools, dir: &Path, program: &Path, parts: usize) -> Result<Vec<PathBuf>, Error> {
    let inlined = dir.join("inlined.bc");
    let mut opt = tools.command("opt");
    opt.arg(format!("-passes={WHOLE_PROGRAM_PASSES}"))
        .arg(program)
        .arg("-o")
        .arg(&inlined);
    run(opt, "opt (whole-program inlining)")?;
    let prefix = dir.join("part");
    let mut split = tools.command("llvm-split");
    split
        .arg(format!("-j{parts}"))
        .arg("-o")
        .arg(&prefix)
        .arg(&inlined);
    run(split, "llvm-split")?;
    Ok((0..parts).map(|k| dir.join(format!("part{k}"))).collect())
}

/// Optimizes `input` at `-O<level>` and generates its object.
fn assemble(
    tools: &Tools,
    level: &str,
    build: &BuildOptions,
    input: &Path,
) -> Result<LlvmObject, Error> {
    let dir = scratch_dir("object")?;
    let (bitcode, obj) = (dir.join("m.bc"), dir.join("llvm.o"));
    let this = LlvmObject {
        dir,
        obj: obj.clone(),
    };
    // What `clang -O<level>` does for IR input: the default pipeline, then code generation.
    let (pipeline, codegen) = match level {
        "s" => ("default<O2>", "-O2"),
        _ => (&*format!("default<O{level}>"), &*format!("-O{level}")),
    };
    let mut opt = tools.command("opt");
    if !build.vectorize {
        opt.args(["-vectorize-loops=false", "-vectorize-slp=false"]);
    }
    opt.arg(format!("-passes={pipeline}"))
        .arg(input)
        .arg("-o")
        .arg(&bitcode);
    run(opt, "opt (LLVM optimizer)")?;
    let mut llc = tools.command("llc");
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
