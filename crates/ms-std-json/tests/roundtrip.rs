//! Seeded mutations of JSON texts: whatever parses must stringify, and the stringified text must
//! parse again and stringify to itself.
use ms_std_json::*;

const SEEDS: &[&str] = &[
    "null",
    "[1,2.5,-0,1e3]",
    r#"{"a":{"b":[true,false,null]}}"#,
    "\"😀\"",
    r#"{"n":9007199254740993}"#,
    r#""a\u0000b""#,
    "[[[[]]]]",
    r#"{"k":"😀","e":"é\n\t\"","x":-1.5E+10}"#,
];

const FRAGMENTS: &[&str] = &[
    "[", "]", "{", "}", ",", ":", "\"", "\\", "\\u", "\\ud800", "null", "true", "-", "0", "1e5",
    ".", " ", "\n", "😀", "é", "\u{0}",
];

struct Rng(u64);

impl Rng {
    fn below(&mut self, n: usize) -> usize {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        ((z ^ (z >> 31)) % n.max(1) as u64) as usize
    }
}

fn boundary(text: &str, mut at: usize) -> usize {
    at = at.min(text.len());
    while !text.is_char_boundary(at) {
        at -= 1;
    }
    at
}

fn mutate(seed: &str, rng: &mut Rng) -> String {
    let mut text = seed.to_string();
    for _ in 0..rng.below(3) {
        let a = boundary(&text, rng.below(text.len() + 1));
        let b = boundary(&text, a + rng.below(6));
        match rng.below(3) {
            0 => text.replace_range(a..b, ""),
            1 => text.insert_str(a, FRAGMENTS[rng.below(FRAGMENTS.len())]),
            _ => text.truncate(a),
        }
    }
    text
}

fn limits() -> Limits {
    Limits {
        max_bytes: Some(1 << 16),
        max_depth: Some(32),
        max_values: Some(1 << 12),
    }
}

#[test]
fn parsed_values_stringify_and_parse_back_unchanged() {
    let mut rng = Rng(0x15_0A);
    let mut parsed = 0;
    for round in 0..4000 {
        let text = mutate(SEEDS[round % SEEDS.len()], &mut rng);
        let Ok((doc, root)) = parse(&text, limits()) else {
            continue;
        };
        parsed += 1;
        let out = doc
            .stringify(root, Some(1 << 20), None)
            .unwrap_or_else(|e| panic!("parsed value does not stringify: {text:?} -> {e:?}"));
        let (again, again_root) =
            parse(&out, limits()).unwrap_or_else(|e| panic!("{text:?} -> {out:?} reparse {e:?}"));
        assert_eq!(
            again.stringify(again_root, Some(1 << 20), None).unwrap(),
            out,
            "round trip changed value: {text:?}"
        );
    }
    assert!(parsed > 500, "only {parsed} mutants parsed");
}
