//! Linker driver: runs the system C compiler driver over the object and the runtime.

use crate::Error;
use std::path::Path;
use std::process::Command;

/// Links `object` and the runtime static library into the executable `out`.
pub fn link(object: &Path, runtime: &Path, out: &Path) -> Result<(), Error> {
    link_all(object, &[runtime], out)
}

/// Like [`link`] with several runtime inputs (objects or static libraries), in order.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    let o = Command::new("cc")
        .arg("-o")
        .arg(out)
        .arg(object)
        .args(inputs)
        .args(["-lm", "-lpthread", "-ldl"])
        .output()
        .map_err(|e| Error(format!("cannot run cc: {e}")))?;
    if o.status.success() {
        Ok(())
    } else {
        Err(Error(format!(
            "link failed: {}",
            String::from_utf8_lossy(&o.stderr)
        )))
    }
}
