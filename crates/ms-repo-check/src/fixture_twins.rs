//! A conformance fixture must not copy a program that `tests/e2e/testdata` already holds: the
//! e2e copy is the test, and a second recorded expectation only drifts from it. New behavior
//! tests belong in `tests/e2e/testdata` (an in-source `test` with `expect_equal`).

use std::collections::BTreeSet;

const ROOT: &str = "tests/conformance/fixtures/e2e/";
const TESTDATA: &str = "tests/e2e/testdata/";

pub fn check(files: &[String]) -> Vec<String> {
    let testdata: BTreeSet<&str> = files
        .iter()
        .filter_map(|p| p.strip_prefix(TESTDATA))
        .collect();
    files
        .iter()
        .filter(|p| p.ends_with(".ms"))
        .filter_map(|p| Some((p, p.strip_prefix(ROOT)?)))
        // Single-file fixtures are `<kind>/<name>.ms`; projects keep their own layout.
        .filter(|(_, rest)| rest.matches('/').count() == 1 && testdata.contains(rest))
        .map(|(p, _)| format!("{p}: copies a program in {TESTDATA}; delete the conformance copy"))
        .collect()
}
