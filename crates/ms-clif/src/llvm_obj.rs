//! Compiles LLVM IR text to an object file and merges it with the Cranelift object.

use crate::Error;
use std::path::PathBuf;
use std::process::Command;

fn tool(var: &str, default: &str) -> String {
    std::env::var(var).unwrap_or_else(|_| default.to_string())
}

fn run(mut c: Command, what: &str) -> Result<(), Error> {
    let o = c
        .output()
        .map_err(|e| Error(format!("cannot run {what}: {e}")))?;
    if o.status.success() {
        return Ok(());
    }
    Err(Error(format!(
        "{what} failed ({}):\n{}",
        o.status,
        String::from_utf8_lossy(&o.stderr).trim_end()
    )))
}

/// Optimizes and assembles `ir` at `-O<level>`, then merges the result with `clif` (data,
/// descriptors and `main`) into one relocatable object.
pub fn build(ir: &str, clif: &[u8], level: &str) -> Result<Vec<u8>, Error> {
    let dir: PathBuf = std::env::temp_dir().join(format!(
        "ms-llvm-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    std::fs::create_dir_all(&dir).map_err(|e| Error(format!("create {}: {e}", dir.display())))?;
    let result = (|| {
        let (ll, lo, co, out) = (
            dir.join("m.ll"),
            dir.join("llvm.o"),
            dir.join("clif.o"),
            dir.join("merged.o"),
        );
        std::fs::write(&ll, ir).map_err(|e| Error(e.to_string()))?;
        std::fs::write(&co, clif).map_err(|e| Error(e.to_string()))?;
        if std::env::var_os("MS_KEEP_LL").is_some() {
            let _ = std::fs::copy(&ll, "ms-keep.ll");
        }
        let mut cc = Command::new(tool("MS_LLVM_CC", "clang"));
        cc.args(["-c", "-x", "ir", &format!("-O{level}"), "-fPIC", "-Wno-override-module"])
            .arg(&ll)
            .arg("-o")
            .arg(&lo);
        run(cc, "clang (LLVM optimizer)")?;
        let mut ld = Command::new(tool("MS_LINKER", "cc"));
        ld.args(["-r", "-nostdlib"]).arg(&co).arg(&lo).arg("-o").arg(&out);
        run(ld, "relocatable link")?;
        std::fs::read(&out).map_err(|e| Error(e.to_string()))
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}
