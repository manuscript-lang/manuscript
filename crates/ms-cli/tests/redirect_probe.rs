//! Temporary diagnostic for the macOS exit 67 in redirect_null.
use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn probe() {
    if !cfg!(target_os = "macos") {
        return;
    }
    let mut report = String::new();
    for name in ["probe_none", "probe_out", "probe_err", "probe_in"] {
        let file = format!("{}/tests/redirect_null/{name}.ms", env!("CARGO_MANIFEST_DIR"));
        let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &file])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let _ = child.stdin.take().unwrap().write_all(b"unread\n");
        let out = child.wait_with_output().unwrap();
        report += &format!(
            "PROBE {name}: code={:?} stdout={:?} stderr={:?}\n",
            out.status.code(),
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
    }
    panic!("{report}");
}
