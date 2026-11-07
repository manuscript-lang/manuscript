//! The standard library's declared effect sets are API: a new tag, or a lost one, changes what
//! every caller must permit. This golden lists each exported function that declares effects,
//! so a change shows up in review. Regenerate with `UPDATE_SNAPSHOTS=1`.

use ms_tooling::guide::api::standard_library;

const GOLDEN: &str = "tests/stdlib_effects.txt";

fn listing() -> String {
    let syms = ms_syntax::Names::global();
    let mut lines: Vec<String> = Vec::new();
    for module in standard_library(syms) {
        for d in module.declarations.iter().filter(|d| !d.effects.is_empty()) {
            lines.push(format!(
                "{} {}: {}",
                module.path,
                d.name,
                d.effects.join(", ")
            ));
        }
    }
    lines.sort();
    lines.join("\n") + "\n"
}

#[test]
fn declared_stdlib_effects_match_the_golden_listing() {
    let got = listing();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(GOLDEN);
    if std::env::var("UPDATE_SNAPSHOTS").is_ok() {
        std::fs::write(&path, &got).expect("write golden");
        return;
    }
    let want = std::fs::read_to_string(&path).expect("golden exists; run with UPDATE_SNAPSHOTS=1");
    assert_eq!(
        got, want,
        "stdlib effect tags changed; review the diff, then run with UPDATE_SNAPSHOTS=1"
    );
}

#[test]
fn only_the_documented_vocabulary_is_used() {
    const ALLOWED: [&str; 17] = [
        "std.fs.read",
        "std.fs.write",
        "std.fs.delete",
        "std.net.connect",
        "std.net.listen",
        "std.process.run",
        "std.process.signal",
        "std.process.read",
        "std.process.write",
        "std.env.read",
        "std.env.write",
        "std.clock.read",
        "std.clock.sleep",
        "std.random.read",
        "std.console.read",
        "std.console.write",
        "std.system.read",
    ];
    for line in listing().lines() {
        let (_, effects) = line.split_once(": ").expect("listing line");
        for effect in effects.split(", ") {
            assert!(
                ALLOWED.contains(&effect) && effect.starts_with("std."),
                "{line}: `{effect}` is not in the stdlib vocabulary"
            );
        }
    }
}
