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
        type L:\n\
        \x20   case Nil\n\
        \x20   case Cons(head: Int, tail: L)\n\
        export fn main() Int:\n\
        \x20   var l: L = Nil\n\
        \x20   for i in 0..100000:\n\
        \x20       l = Cons(i, l)\n\
        \x20   let text = \"{l}\"\n\
        \x20   var xs: List[Int] = []\n\
        \x20   for i in 0..300000:\n\
        \x20       xs.append(i)\n\
        \x20   let list_text = \"{xs}\"\n\
        \x20   stdout().write(\"{text.length()} {list_text.length()}\\n\").get()\n\
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
    let source = "import stdout from \"@std/io.ms\"\n\
        export fn main() Int:\n\
        \x20   let lowered = \"\\u{1C5}\\u{3A3}\".lower()\n\
        \x20   stdout().write(\"{lowered.scalar_values()}\\n\").get()\n\
        \x20   return 0\n\
        ";
    std::fs::write(dir.join("sigma.ms"), source).unwrap();
    let (status, text) = run_ms(&["run", "sigma.ms"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(text.trim(), "[454, 962]", "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}

/// Builds a program whose enum has `cases` cases, each matched once; returns the build time.
fn build_time_for_cases(cases: usize) -> std::time::Duration {
    let dir = std::env::temp_dir().join(format!("ms-cli-cases-{}-{cases}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let mut source = String::from("import stdout from \"@std/io.ms\"\ntype E:\n");
    for i in 0..cases {
        source.push_str(&format!("    case C{i}(x: Int)\n"));
    }
    source.push_str("\nfn g(e: E) Int:\n    match e:\n");
    for i in 0..cases {
        source.push_str(&format!("        C{i}(x): return x + {i}\n"));
    }
    source.push_str(&format!(
        "\nexport fn main() Int:\n    stdout().write(\"{{g(C{}(1))}}\\n\").get()\n    return 0\n",
        cases - 1
    ));
    std::fs::write(dir.join("cases.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let (status, text) = run_ms(&["build", "cases.ms", "--build-type", "Debug"], &dir);
    let elapsed = started.elapsed();
    assert_eq!(status, Some(0), "{text}");
    let _ = std::fs::remove_dir_all(&dir);
    elapsed
}

/// Every payload read and construction used to copy the layout of all cases. Compare two sizes
/// instead of a wall-clock limit, which fails on slow runners: 4x the cases is about 4x the time
/// when linear and about 16x when quadratic.
#[test]
fn a_match_over_thousands_of_cases_builds_in_linear_time() {
    let small = build_time_for_cases(2_500);
    let large = build_time_for_cases(10_000);
    assert!(
        large < small * 10,
        "4x the cases took {large:?} against {small:?}"
    );
}
