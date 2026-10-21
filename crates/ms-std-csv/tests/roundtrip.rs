//! Seeded CSV rows: stringify then parse returns the same rows for every valid delimiter and
//! line ending.
use ms_std_csv::{options, parse, stringify};

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

const ALPHABET: &[&str] = &[
    "a", "b", " ", "\"", "\n", "\r", ",", ";", "\t", "\\.", "é", "😀", "x y", "\\", "",
];

fn field(rng: &mut Rng, delimiter: &str) -> String {
    let mut out = String::new();
    for _ in 0..rng.below(5) {
        out += ALPHABET[rng.below(ALPHABET.len())];
    }
    if rng.below(4) == 0 {
        out += delimiter;
    }
    out
}

#[test]
fn stringified_rows_parse_back_unchanged() {
    let mut rng = Rng(0xC5);
    for round in 0..3000 {
        let delimiter = [",", ";", "\t", "|"][round % 4];
        let ending = if round % 2 == 0 { "\n" } else { "\r\n" };
        let opts = options(delimiter, ending).unwrap();
        let rows: Vec<Vec<String>> = (0..1 + rng.below(4))
            .map(|_| {
                (0..1 + rng.below(4))
                    .map(|_| field(&mut rng, delimiter))
                    .collect()
            })
            .collect();
        // Reading normalizes CRLF inside a quoted field to LF, so such fields cannot round trip.
        if rows.iter().flatten().any(|f| f.contains("\r\n")) {
            continue;
        }
        let out = stringify(&rows, opts, Some(1 << 20)).expect("stringify");
        let back = parse(&out, opts, Some(1 << 20), Some(1 << 20)).expect("parse back");
        assert_eq!(back, rows, "round trip changed rows: {out:?}");
    }
}
