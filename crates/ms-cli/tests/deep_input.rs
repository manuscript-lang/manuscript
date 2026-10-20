//! Inputs the parser admits (up to `MAX_CHAIN` operators in a chain) must not overflow the compiler's stack.

use std::process::Command;

fn run_ms(args: &[&str], dir: &std::path::Path) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.code(), text)
}

#[test]
fn long_operator_chain_checks_and_runs() {
    let dir = std::env::temp_dir().join(format!("ms-cli-deep-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let terms = vec!["1"; 9000].join(" + ");
    let source = format!("export fn main() Int:\n    let x = {terms}\n    return x - 9000\n");
    std::fs::write(dir.join("chain.ms"), source).unwrap();
    for command in ["check", "fmt", "lint"] {
        let (status, text) = run_ms(&[command, "chain.ms"], &dir);
        assert!(
            matches!(status, Some(0) | Some(1)),
            "{command}: {status:?} {text}"
        );
        assert!(!text.contains("overflowed"), "{command}: {text}");
    }
    let (status, text) = run_ms(&["run", "chain.ms"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}
