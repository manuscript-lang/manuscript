//! Deterministic mutation testing of the parser, partial parser and formatter. Each accepted and
//! rejected conformance program is damaged in seeded ways (delete, duplicate, swap, insert,
//! truncate); whatever the damage, nothing may panic, diagnostics must point into the source,
//! formatting must refuse exactly the sources the parser refuses, and formatted output must parse
//! and format to itself.

use ms_syntax::parser::parse;
use ms_syntax::{format, parse_partial};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::sync::Arc;

const MUTATIONS_PER_FILE: u64 = 24;
const MAX_SOURCE: usize = 8000;

/// SplitMix64, so a failing seed reproduces on every platform.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
}

const FRAGMENTS: &[&str] = &[
    "(", ")", "[", "]", "{", "}", ":", ",", "=", "\"", "\"{", "}\"", "\n", "\r\n", "\t", "    ",
    "fn ", "type ", "import ", "match ", "if ", "return ", "with ", "😀", "é", "\u{0}", "# note\n",
    "->", "?", "..", "0x", "1e", "'",
];

fn char_boundary(text: &str, mut at: usize) -> usize {
    at = at.min(text.len());
    while !text.is_char_boundary(at) {
        at -= 1;
    }
    at
}

fn mutate(source: &str, rng: &mut Rng) -> String {
    let mut text = source.to_string();
    for _ in 0..1 + rng.below(3) {
        let a = char_boundary(&text, rng.below(text.len() + 1));
        let b = char_boundary(&text, a + rng.below(40));
        match rng.below(5) {
            0 => text.replace_range(a..b, ""),
            1 => {
                let copy = text[a..b].to_string();
                text.insert_str(b, &copy);
            }
            2 => text.insert_str(a, FRAGMENTS[rng.below(FRAGMENTS.len())]),
            3 => text.truncate(a),
            _ => {
                let c = char_boundary(&text, b + rng.below(40));
                let (first, second) = (text[a..b].to_string(), text[b..c].to_string());
                text.replace_range(a..c, &(second + &first));
            }
        }
    }
    text
}

fn sources() -> Vec<(PathBuf, String)> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/e2e/testdata");
    let mut out = Vec::new();
    for dir in ["accept", "reject"] {
        let mut paths: Vec<PathBuf> = std::fs::read_dir(root.join(dir))
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|e| e == "ms"))
            .collect();
        paths.sort();
        for path in paths {
            let text = std::fs::read_to_string(&path).unwrap();
            if text.len() <= MAX_SOURCE {
                out.push((path, text));
            }
        }
    }
    out
}

fn check(source: &str) {
    let file: Arc<str> = Arc::from("fuzz.ms");
    let len = source.len() as u32;
    let in_source = |offset: u32| offset <= len;

    let parsed = parse(&file, source);
    if let Err(diagnostic) = &parsed {
        assert!(
            in_source(diagnostic.pos.offset),
            "parse error outside source"
        );
        assert!(diagnostic.pos.line >= 1 && !diagnostic.message.is_empty());
    }

    let (module, diagnostics) = parse_partial(&file, source);
    assert_eq!(&*module.source, source, "partial parse lost the source");
    for decl in &module.decls {
        assert!(in_source(decl.pos.offset), "declaration outside source");
    }
    for diagnostic in &diagnostics {
        assert!(
            in_source(diagnostic.pos.offset),
            "diagnostic outside source"
        );
        if let Some(end) = diagnostic.end {
            assert!(in_source(end.offset) && end.offset >= diagnostic.pos.offset);
        }
    }

    match (format(&file, source), parsed) {
        (Err(_), Err(_)) => {}
        (Ok(formatted), Ok(_)) => {
            assert!(
                parse(&file, &formatted).is_ok(),
                "formatted output does not parse"
            );
            assert_eq!(
                format(&file, &formatted).as_deref().ok(),
                Some(formatted.as_str()),
                "formatting is not idempotent"
            );
        }
        (Ok(_), Err(_)) => panic!("invalid syntax produced formatted output"),
        (Err(error), Ok(_)) => panic!("valid syntax failed to format: {}", error.message),
    }
}

#[test]
fn mutated_programs_never_break_the_parser_or_formatter() {
    std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(|| {
            let files = sources();
            assert!(files.len() > 100, "found {} sources", files.len());
            for (path, original) in files {
                // The unmodified program is case zero.
                let mut cases = vec![original.clone()];
                let mut rng = Rng(path
                    .to_string_lossy()
                    .bytes()
                    .fold(7, |h, b| h.wrapping_mul(31).wrapping_add(u64::from(b))));
                cases.extend((0..MUTATIONS_PER_FILE).map(|_| mutate(&original, &mut rng)));
                for case in cases {
                    if catch_unwind(AssertUnwindSafe(|| check(&case))).is_err() {
                        panic!("{} failed on:\n{case:?}", path.display());
                    }
                }
            }
        })
        .unwrap()
        .join()
        .unwrap();
}
