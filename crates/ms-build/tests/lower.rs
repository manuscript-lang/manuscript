//! Lowers the programs in `tests/lower/*.ms` and verifies the MIR.
//!
//! Header comments state what the printed MIR must contain:
//! - `// expect-mir: "text"` appears somewhere;
//! - `// expect-mir-count: N "text"` appears at least N times;
//! - `// expect-mir-order: "anchor" "a" "b"` finds `a` then `b` after the first `anchor`.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_driver::{CheckRequest, check_graph, load_file};
use ms_lower::{Options, lower_program};
use ms_rt as _;
use std::path::{Path, PathBuf};

fn lower_module(path: &Path) -> ms_mir::ir::Module {
    let syms = ms_syntax::Names::global();
    let loaded = check_graph(
        syms,
        load_file(syms, &path.to_string_lossy(), Default::default()),
        CheckRequest::default(),
    );
    assert!(loaded.success(), "{:?}", loaded.diagnostics);
    let program = loaded.program.expect("program");
    let module = lower_program(
        syms,
        &program,
        &Options {
            entry: loaded.entry,
        },
    )
    .expect("lower");
    ms_mir::verify::verify_module(&module).expect("verified MIR");
    module
}

fn lower(path: &Path) -> String {
    ms_mir::print::print_module(&lower_module(path))
}

fn quoted(rest: &str) -> Vec<&str> {
    rest.split('"').skip(1).step_by(2).collect()
}

fn check_expectations(source: &str, mir: &str) -> Vec<String> {
    let mut failures = Vec::new();
    for line in source.lines().take_while(|l| l.starts_with("//")) {
        let line = line.trim_start_matches('/').trim();
        if let Some(rest) = line.strip_prefix("expect-mir-count:") {
            let rest = rest.trim();
            let (count, text) = rest.split_once(' ').expect("count and text");
            let want: usize = count.parse().expect("count");
            let text = quoted(text)[0];
            let found = mir.matches(text).count();
            if found < want {
                failures.push(format!("{text:?}: {found} occurrences, want {want}"));
            }
        } else if let Some(rest) = line.strip_prefix("expect-mir-order:") {
            let parts = quoted(rest);
            let (anchor, steps) = parts.split_first().expect("anchor");
            let mut after = mir.split(anchor).nth(1).expect("anchor present");
            for step in steps {
                match after.find(step) {
                    Some(at) => after = &after[at..],
                    None => failures.push(format!("{step:?} not found in order after {anchor:?}")),
                }
            }
        } else if let Some(rest) = line.strip_prefix("expect-mir:") {
            let text = quoted(rest)[0];
            if !mir.contains(text) {
                failures.push(format!("{text:?} missing"));
            }
        }
    }
    failures
}

#[test]
fn fixtures_lower_and_match_their_expectations() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/lower");
    let mut files: Vec<PathBuf> = std::fs::read_dir(&dir)
        .expect("fixtures")
        .map(|e| e.expect("entry").path())
        .filter(|p| p.extension().is_some_and(|e| e == "ms"))
        .collect();
    files.sort();
    assert!(!files.is_empty());
    let mut failed = Vec::new();
    for file in &files {
        let source = std::fs::read_to_string(file).expect("source");
        let mir = lower(file);
        for failure in check_expectations(&source, &mir) {
            failed.push(format!("{}: {failure}", file.display()));
        }
    }
    assert!(failed.is_empty(), "{}", failed.join("\n"));
}

#[test]
fn rsa_source_calls_and_function_values() {
    let syms = ms_syntax::Names::global();
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/e2e/testdata/stdlib/crypto-rsa.ms");
    let loaded = check_graph(
        syms,
        load_file(syms, &path.to_string_lossy(), Default::default()),
        CheckRequest::default(),
    );
    assert!(loaded.success(), "{:?}", loaded.diagnostics);
    let (module, tests) = ms_lower::lower_tests(
        syms,
        &loaded.program.expect("program"),
        &Options {
            entry: loaded.entry,
        },
    )
    .expect("lower RSA fixture");
    assert_eq!(tests.len(), 4);
    ms_mir::verify::verify_module(&module).expect("verified RSA MIR");
    let mir = ms_mir::print::print_module(&module);
    for name in [
        "sign",
        "verify",
        "sign_pss",
        "verify_pss",
        "encrypt",
        "decrypt",
    ] {
        assert!(mir.contains(&format!("msstd_crypto_rsa_{name}")), "{name}");
    }
    assert!(mir.contains("alt.tag"));
}

#[test]
fn bound_native_scalar_resources_keep_ownership_in_capture_metadata() {
    use ms_mir::ir::FuncKind;
    use ms_mir::types::Ty;

    let path =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/lower/bound-native-scalar-resource.ms");
    let module = lower_module(&path);
    let mut owning = 0;
    let mut borrowed = 0;
    let mut plain = 0;
    for func in &module.funcs {
        let FuncKind::Closure { captures } = &func.kind else {
            continue;
        };
        if func.name == "is_error" {
            assert_eq!(captures.len(), 1);
            if captures[0] == Ty::PTR {
                // The named parameter and Holder.result projection borrow their receiver.
                assert!(func.capture_closers.is_empty());
                borrowed += 1;
            } else {
                assert!(
                    !module.needs_drop(captures[0]),
                    "must exercise a scalar resource"
                );
                assert_eq!(func.capture_closers.len(), 1);
                let (index, closer) = func.capture_closers[0];
                assert_eq!(index, 0);
                let closer = &module.funcs[closer.index()];
                assert_eq!(closer.params.len(), 1);
                assert_eq!(closer.params[0].ty, Ty::PTR);
                owning += 1;
            }
        } else if func.name == "abs" {
            assert_eq!(captures.as_slice(), &[Ty::INT]);
            assert!(func.capture_closers.is_empty());
            plain += 1;
        }
    }
    // Helper caching shares the borrowed thunk but separates it from the owning one.
    assert_eq!(owning, 1, "missing owning native resource capture");
    assert_eq!(borrowed, 1, "missing borrowed native resource capture");
    assert_eq!(plain, 1, "missing plain scalar native capture");
}
