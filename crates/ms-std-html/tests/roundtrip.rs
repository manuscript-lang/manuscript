//! Seeded text: unescape(escape(text)) is the text.
use ms_std_html::{escape, unescape};

const SEEDS: &[&str] = &[
    "",
    "a b&c=d",
    "é🙂%/?#",
    "&amp;<>\"'",
    "&#x;",
    "&lt",
    "&notit;",
    "&",
];
const PIECES: &[&str] = &[
    "&", "&amp;", "&#", "&#x", ";", "<", ">", "\"", "'", "é", "😀", "x", "lt", "#38;",
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

#[test]
fn escaped_text_unescapes_to_itself() {
    let mut rng = Rng(0x47);
    for seed in SEEDS {
        assert_eq!(unescape(&escape(seed)), *seed, "{seed:?}");
    }
    for _ in 0..4000 {
        let text: String = (0..rng.below(10))
            .map(|_| PIECES[rng.below(PIECES.len())])
            .collect();
        assert_eq!(unescape(&escape(&text)), text, "{text:?}");
    }
}
