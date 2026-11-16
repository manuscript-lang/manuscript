//! Cancel by return: a native never ends a cancelled call with the runtime's jump
//! (`msrt_cancelled`). It calls `ms_rt::fault::cancel_return` (or `glue::cancel_return`) and
//! returns a zero result; the frames above take their cancel exits. The jump stays only where
//! nothing sits above it: the cancel-return fallback while a module has no cancel edges, and the
//! main task's boundary. See `proposals/cancel-cleanup-by-edge.md`.

/// Files that may still call `msrt_cancelled`.
const ALLOWED: &[&str] = &["crates/ms-rt/src/fault.rs", "crates/ms-rt/src/start.rs"];

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files {
        let in_scope = path.ends_with(".rs")
            && path.contains("/src/")
            && (path.starts_with("crates/ms-rt/") || path.starts_with("crates/ms-std-"));
        if !in_scope || ALLOWED.contains(&path.as_str()) {
            continue;
        }
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        for (n, line) in source.lines().enumerate() {
            let code = line.split("//").next().unwrap_or("");
            if code.contains("msrt_cancelled") {
                issues.push(format!(
                    "{path}:{}: a native must not jump on cancel; call `cancel_return()` and return a zero result",
                    n + 1
                ));
            }
        }
    }
    issues
}
