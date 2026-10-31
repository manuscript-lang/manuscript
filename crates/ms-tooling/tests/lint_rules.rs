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

#[test]
fn every_rule_has_a_severity_and_findings_carry_it() {
    use ms_tooling::lint::{RULES, Severity, explain};
    assert_eq!(explain("MSL110").unwrap().severity, Severity::Warning);
    assert_eq!(explain("MSL112").unwrap().severity, Severity::Error);
    for rule in RULES {
        let finding = ms_tooling::lint::lint_source(&"a.ms".into(), "x \n");
        assert!(finding.iter().all(|f| f.severity == Severity::Warning));
        assert!(!rule.family.is_empty());
    }
}
