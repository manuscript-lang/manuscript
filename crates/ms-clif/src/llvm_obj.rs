//! Compiles LLVM IR text to an object file and merges it with the Cranelift object.

use crate::Error;
use std::path::{Path, PathBuf};
use std::process::Command;

fn tool(var: &str, default: &str) -> String {
    std::env::var(var).unwrap_or_else(|_| default.to_string())
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
    let mut cc = Command::new(tool("MS_LLVM_CC", "clang"));
    cc.args([
        "-c",
        "-x",
        "ir",
        &format!("-O{level}"),
        "-fPIC",
        "-Wno-override-module",
    ])
    .arg(&ll)
    .arg("-o")
    .arg(&obj);
    run(cc, "clang (LLVM optimizer)")?;
    Ok(this)
}

impl LlvmObject {
    /// Links the object alone (undefined symbols ignored) so its code has final offsets for the
    /// line tables. The result is only read, never run.
    pub fn image(&self) -> Result<PathBuf, Error> {
        let image = self.dir.join("image.so");
        let mut ld = Command::new(tool("MS_LINKER", "cc"));
        ld.args([
            "-shared",
            "-nostdlib",
            "-Wl,--unresolved-symbols=ignore-all",
            "-Wl,-z,notext",
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
        let mut ld = Command::new(tool("MS_LINKER", "cc"));
        ld.args(["-r", "-nostdlib"])
            .arg(&co)
            .arg(&self.obj)
            .arg("-o")
            .arg(&out);
        run(ld, "relocatable link")?;
        std::fs::read(&out).map_err(|e| Error(e.to_string()))
    }
}

#[allow(dead_code)]
fn _unused(_: &Path) {}
