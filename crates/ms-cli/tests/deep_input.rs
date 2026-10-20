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

#[test]
fn text_of_deep_and_large_values_is_capped_and_linear() {
    let dir = std::env::temp_dir().join(format!("ms-cli-text-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    // Nesting depth 64 prints `...`; a long list formats in linear time.
    let source = "import stdout from \"@std/io.ms\"\n\
        import range from \"@std/collections.ms\"\n\
        type L:\n    case Nil\n    case Cons(head: Int, tail: L)\n\
        export fn main() Int:\n\
        \x20   var l: L = Nil\n\
        \x20   for i in range(0, 100000):\n\
        \x20       l = Cons(i, l)\n\
        \x20   let text = \"{l}\"\n\
        \x20   var xs: List[Int] = []\n\
        \x20   for i in range(0, 300000):\n\
        \x20       xs.append(i)\n\
        \x20   let list_text = \"{xs}\"\n\
        \x20   stdout().write(\"{text.length()} {list_text.length()}\\n\").get()\n\
        \x20   return 0\n";
    std::fs::write(dir.join("text.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let (status, text) = run_ms(&["run", "text.ms"], &dir);
    assert_eq!(status, Some(0), "{text}");
    // 64 levels of `L.Cons(<head>, ` plus the cut-off, then the 300000-item list.
    assert_eq!(text.trim(), "961 2288890", "{text}");
    assert!(started.elapsed().as_secs() < 20, "formatting is not linear");
    let _ = std::fs::remove_dir_all(&dir);
}
