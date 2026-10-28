//! Every lint code the rules emit has a `ms guide` entry.

use std::collections::BTreeSet;
use std::path::Path;

#[test]
fn every_emitted_code_is_explained() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/lint");
    let mut emitted = BTreeSet::new();
    for entry in std::fs::read_dir(dir).expect("lint sources") {
        let text = std::fs::read_to_string(entry.expect("entry").path()).expect("reads");
        for part in text.split("\"MSL").skip(1) {
            let digits: String = part.chars().take_while(char::is_ascii_digit).collect();
            if digits.len() == 3 && part[3..].starts_with('"') {
                emitted.insert(format!("MSL{digits}"));
            }
        }
    }
    assert!(emitted.contains("MSL114"), "{emitted:?}");
    for code in &emitted {
        assert!(ms_tooling::lint::explain(code).is_some(), "{code}");
    }
    for rule in ms_tooling::lint::RULES {
        assert!(
            emitted.contains(rule.code),
            "{} is never emitted",
            rule.code
        );
    }
}
