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
    let source = format!("export def main() -> Int:\n    let x = {terms}\n    return x - 9000\n");
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
    let source = "from \"@std/io.ms\" import stdout\n\
        from \"@std/collections.ms\" import range\n\
        type L:\n\
        \x20   case Nil\n\
        \x20   case Cons(head: Int, tail: L)\n\
        export def main() -> Int:\n\
        \x20   var l: L = Nil\n\
        \x20   for i in range(0, 100000):\n\
        \x20       l = Cons(i, l)\n\
        \x20   let text = f\"{l}\"\n\
        \x20   var xs: List[Int] = []\n\
        \x20   for i in range(0, 300000):\n\
        \x20       xs.append(i)\n\
        \x20   let list_text = f\"{xs}\"\n\
        \x20   stdout().write(f\"{text.length()} {list_text.length()}\\n\").get()\n\
        \x20   return 0\n\
        ";
    std::fs::write(dir.join("text.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let (status, text) = run_ms(&["run", "text.ms"], &dir);
    assert_eq!(status, Some(0), "{text}");
    // 64 levels of `L.Cons(<head>, ` plus the cut-off, then the 300000-item list.
    assert_eq!(text.trim(), "961 2288890", "{text}");
    assert!(started.elapsed().as_secs() < 20, "formatting is not linear");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn lower_applies_final_sigma_after_titlecase_letters() {
    let dir = std::env::temp_dir().join(format!("ms-cli-sigma-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "from \"@std/io.ms\" import stdout\n\
        export def main() -> Int:\n\
        \x20   let lowered = f\"\\u{1C5}\\u{3A3}\".lower()\n\
        \x20   stdout().write(f\"{lowered.scalar_values()}\\n\").get()\n\
        \x20   return 0\n\
        ";
    std::fs::write(dir.join("sigma.ms"), source).unwrap();
    let (status, text) = run_ms(&["run", "sigma.ms"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(text.trim(), "[454, 962]", "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_match_over_thousands_of_cases_builds_in_linear_time() {
    let dir = std::env::temp_dir().join(format!("ms-cli-cases-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    // Every payload read and construction used to copy the layout of all cases.
    let cases = 10_000;
    let mut source = String::from("from \"@std/io.ms\" import stdout\ntype E:\n");
    for i in 0..cases {
        source.push_str(&format!("    case C{i}(x: Int)\n"));
    }
    source.push_str("\ndef g(e: E) -> Int:\n    match e:\n");
    for i in 0..cases {
        source.push_str(&format!("        case C{i}(x): return x + {i}\n"));
    }
    source.push_str(
        "\nexport def main() -> Int:\n    stdout().write(f\"{g(C9999(1))}\\n\").get()\n    return 0\n",
    );
    std::fs::write(dir.join("cases.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let (status, text) = run_ms(&["build", "cases.ms", "--build-type", "Debug"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(
        started.elapsed().as_secs() < 15,
        "took {:?}",
        started.elapsed()
    );
    let _ = std::fs::remove_dir_all(&dir);
}
