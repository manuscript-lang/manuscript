//! Differential test against vectors produced by the Go matcher (see `golden/glob_gen_test.go.txt`).
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_path::glob::Glob;

fn unhex(s: &str) -> String {
    let bytes: Vec<u8> = (0..s.len() / 2)
        .map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap())
        .collect();
    String::from_utf8(bytes).unwrap()
}

#[test]
fn matches_go() {
    let text = include_str!("golden/glob_golden.txt");
    let mut checked = 0;
    let mut current: Option<(String, Option<Glob>)> = None;
    for line in text.lines() {
        let mut f = line.split(' ');
        let (pattern, value, result) = (
            unhex(f.next().unwrap()),
            f.next().unwrap(),
            f.next().unwrap(),
        );
        if current.as_ref().is_none_or(|(p, _)| *p != pattern) {
            current = Some((pattern.clone(), Glob::new(&pattern)));
        }
        let glob = &current.as_ref().unwrap().1;
        if result == "E" {
            assert!(glob.is_none(), "pattern {pattern:?} should not parse");
            continue;
        }
        let glob = glob
            .as_ref()
            .unwrap_or_else(|| panic!("pattern {pattern:?} should parse"));
        let value = unhex(value);
        assert_eq!(
            glob.matches(&value),
            result == "1",
            "pattern {pattern:?} value {value:?}"
        );
        checked += 1;
    }
    assert!(checked > 10_000, "only {checked} vectors");
}
