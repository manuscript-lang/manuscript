//! Compiles LLVM IR text to an object file and merges it with the Cranelift object.

use crate::Error;
use crate::link::{lld_path, llvm_tools};
use std::path::PathBuf;
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
    let mut opt = Command::new(tools.join("opt"));
    opt.arg(format!("-passes={pipeline}"))
        .arg(&ll)
        .arg("-o")
        .arg(&bitcode);
    run(opt, "opt (LLVM optimizer)")?;
    let mut llc = Command::new(tools.join("llc"));
    llc.args([codegen, "-filetype=obj", "-relocation-model=pic"])
        .arg(&bitcode)
        .arg("-o")
        .arg(&obj);
    run(llc, "llc (LLVM code generator)")?;
    Ok(this)
}

impl LlvmObject {
    /// Links the object alone (undefined symbols ignored) so its code has final offsets for the
    /// line tables. The result is only read, never run.
    pub fn image(&self) -> Result<PathBuf, Error> {
        let image = self.dir.join("image.so");
        let mut ld = Command::new(lld_path()?);
        ld.args([
            "-flavor",
            "gnu",
            "-shared",
            "--unresolved-symbols=ignore-all",
            "-z",
            "notext",
        ])
        .arg(&self.obj)
        .arg("-o")
        .arg(&image);
        run(ld, "line table link")?;
        Ok(image)
    }

    /// Merges the Cranelift object (data, descriptors, tables, `main`) with this one.
    pub fn merge(&self, clif: &[u8]) -> Result<Vec<u8>, Error> {
        let (co, out) = (self.dir.join("clif.o"), self.dir.join("merged.o"));
        std::fs::write(&co, clif).map_err(|e| Error(e.to_string()))?;
        let mut ld = Command::new(lld_path()?);
        ld.args(["-flavor", "gnu", "-r"])
            .arg(&co)
            .arg(&self.obj)
            .arg("-o")
            .arg(&out);
        run(ld, "relocatable link")?;
        std::fs::read(&out).map_err(|e| Error(e.to_string()))
    }
}
