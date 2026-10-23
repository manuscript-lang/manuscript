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
    let mut opt = Command::new(tools.join(format!("opt{}", std::env::consts::EXE_SUFFIX)));
    opt.arg(format!("-passes={pipeline}"))
        .arg(&ll)
        .arg("-o")
        .arg(&bitcode);
    run(opt, "opt (LLVM optimizer)")?;
    let mut llc = Command::new(tools.join(format!("llc{}", std::env::consts::EXE_SUFFIX)));
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
