//! Deterministic mutation testing of loading and checking. Accepted and rejected conformance
//! programs are damaged in seeded ways; whatever the damage, nothing may panic, diagnostics must
//! repeat exactly, point into the source, and carry fixes that remove their own diagnostic.

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};

use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};
use ms_syntax::Diagnostic;

const MUTATIONS_PER_FILE: u64 = 6;
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

fn char_boundary(text: &str, mut at: usize) -> usize {
    at = at.min(text.len());
    while !text.is_char_boundary(at) {
        at -= 1;
    }
    at
}

fn mutate(source: &str, rng: &mut Rng) -> String {
    let mut text = source.to_string();
    for _ in 0..1 + rng.below(2) {
        let a = char_boundary(&text, rng.below(text.len() + 1));
        let b = char_boundary(&text, a + rng.below(30));
        match rng.below(4) {
            0 => text.replace_range(a..b, ""),
            1 => {
                let copy = text[a..b].to_string();
                text.insert_str(b, &copy);
            }
            2 => {
                let c = char_boundary(&text, b + rng.below(30));
                let (first, second) = (text[a..b].to_string(), text[b..c].to_string());
                text.replace_range(a..c, &(second + &first));
            }
            _ => text.truncate(a),
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

fn diagnostics(path: &Path, source: &str) -> Vec<Diagnostic> {
    std::fs::write(path, source).unwrap();
    let graph = load_file(path.to_str().unwrap(), LoadOptions::default());
    check_graph(graph, CheckRequest::default()).diagnostics
}

fn check(path: &Path, source: &str) {
    let first = diagnostics(path, source);
    let second = diagnostics(path, source);
    assert_eq!(first, second, "diagnostics are not deterministic");
    let own = |d: &Diagnostic| &*d.file == "fuzz.ms";
    let len = source.len() as u32;
    for d in first.iter().filter(|d| own(d)) {
        assert!(!d.message.is_empty(), "empty message");
        assert!(
            d.pos.line >= 1 && d.pos.offset <= len,
            "{d:?} outside source"
        );
        if let Some(end) = d.end {
            assert!(
                end.offset <= len && end.offset >= d.pos.offset,
                "{d:?} range"
            );
        }
        if let Some(fix) = &d.fix {
            assert!(
                fix.end.offset <= len && fix.end.offset >= fix.pos.offset,
                "{d:?} fix range"
            );
        }
    }
    // A machine-applicable fix must remove its own diagnostic.
    for d in first.iter().filter(|d| own(d)) {
        let Some(fix) = &d.fix else { continue };
        let (a, b) = (fix.pos.offset as usize, fix.end.offset as usize);
        if !source.is_char_boundary(a) || !source.is_char_boundary(b) {
            continue;
        }
        let fixed = format!("{}{}{}", &source[..a], fix.replacement, &source[b..]);
        let left = diagnostics(path, &fixed);
        assert!(
            !left
                .iter()
                .any(|r| r.message == d.message && r.pos == d.pos),
            "fix for {:?} leaves the diagnostic: {fixed:?}",
            d.message
        );
    }
}

#[test]
fn mutated_programs_never_break_the_checker() {
    std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(|| {
            let dir =
                std::env::temp_dir().join(format!("ms-driver-mutation-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            let path = dir.join("fuzz.ms");
            let files = sources();
            assert!(files.len() > 100, "found {} sources", files.len());
            for (origin, original) in files {
                let mut cases = vec![original.clone()];
                let mut rng = Rng(origin
                    .to_string_lossy()
                    .bytes()
                    .fold(7, |h, b| h.wrapping_mul(31).wrapping_add(u64::from(b))));
                cases.extend((0..MUTATIONS_PER_FILE).map(|_| mutate(&original, &mut rng)));
                for case in cases {
                    if catch_unwind(AssertUnwindSafe(|| check(&path, &case))).is_err() {
                        panic!("{} failed on:\n{case:?}", origin.display());
                    }
                }
            }
            let _ = std::fs::remove_dir_all(&dir);
        })
        .unwrap()
        .join()
        .unwrap();
}
