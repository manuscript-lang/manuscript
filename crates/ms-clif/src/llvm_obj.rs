//! Compiles LLVM IR text to an object file.

use crate::Error;
use crate::link::llvm_tools;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Whether release builds can use LLVM: the tools are embedded in `ms` or named by `MS_LLVM_TOOLS`.
pub fn available() -> bool {
    llvm_tools().is_ok_and(|tools| tools.is_some())
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

/// Optimizes and assembles `ir` at `-O<level>`.
pub fn compile(ir: &str, level: &str) -> Result<LlvmObject, Error> {
    let dir: PathBuf = std::env::temp_dir().join(format!(
        "ms-llvm-{}-{}",
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
    std::fs::write(&ll, ir).map_err(|e| Error(e.to_string()))?;
    if std::env::var_os("MS_KEEP_LL").is_some() {
        let _ = std::fs::copy(&ll, "ms-keep.ll");
    }
    let tools = llvm_tools()?.ok_or_else(|| {
        Error(
            "this ms was built without the LLVM tools (opt, llc); see scripts/fetch-lld.sh".into(),
        )
    })?;
    // What `clang -O<level>` does for IR input: the default pipeline, then code generation.
    let (pipeline, codegen) = match level {
        "s" => ("default<Os>", "-O2"),
        _ => (&*format!("default<O{level}>"), &*format!("-O{level}")),
    };
    let bitcode = dir.join("m.bc");
    let tool =
        |name: &str| Command::new(tools.join(format!("{name}{}", std::env::consts::EXE_SUFFIX)));
    let mut input = ll;
    if let Some(hot) = hot_library(&dir, &tools, ir) {
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
    ])
    .arg(&bitcode)
    .arg("-o")
    .arg(&obj);
    run(llc, "llc (LLVM code generator)")?;
    Ok(this)
}

/// The runtime helper IR written into `dir`, or `None` when this `ms` has none, `MS_RT_HOT=0` turns
/// it off (to compare against a build without inlined helpers) or names another file, `llvm-link` is not in `tools`, or the
/// `program` IR calls none of the helpers (linking would only cost time).
fn hot_library(dir: &Path, tools: &Path, program: &str) -> Option<PathBuf> {
    // `MS_RT_HOT=<file>` links another helper library, for experiments.
    let custom = std::env::var_os("MS_RT_HOT")
        .filter(|v| v != "0" && v != "1")
        .and_then(|path| std::fs::read_to_string(path).ok());
    let ir = custom.as_deref().unwrap_or(ms_linker::RUNTIME_HOT_IR);
    let linker = tools.join(format!("llvm-link{}", std::env::consts::EXE_SUFFIX));
    if ir.is_empty()
        || std::env::var_os("MS_RT_HOT").is_some_and(|v| v == "0")
        || !linker.is_file()
        || !calls_hot_helper(ir, program)
    {
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
