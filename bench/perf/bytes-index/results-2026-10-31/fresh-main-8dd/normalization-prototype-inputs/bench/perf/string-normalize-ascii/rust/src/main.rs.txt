use std::{hint::black_box, time::Instant};
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, PartialEq)]
enum NormalizeError {
    LimitExceeded,
    InvalidInput,
}

fn collect_bounded(
    iter: impl Iterator<Item = char>,
    limit: usize,
) -> Result<String, NormalizeError> {
    let mut out = String::new();
    for ch in iter {
        if ch.len_utf8() > limit.saturating_sub(out.len()) {
            return Err(NormalizeError::LimitExceeded);
        }
        out.push(ch);
    }
    Ok(out)
}

fn normalize(text: &str, form: &str, max: Option<i64>) -> Result<String, NormalizeError> {
    if max.is_some_and(|n| n < 0) {
        return Err(NormalizeError::InvalidInput);
    }
    let kind = match form {
        "NFC" => 0,
        "NFD" => 1,
        "NFKC" => 2,
        "NFKD" => 3,
        _ => return Err(NormalizeError::InvalidInput),
    };
    let limit = max.map_or(usize::MAX, |n| n as usize);
    #[cfg(feature = "ascii-identity")]
    if text.is_ascii() {
        return if text.len() > limit {
            Err(NormalizeError::LimitExceeded)
        } else {
            Ok(text.to_owned())
        };
    }
    #[cfg(feature = "eager-input")]
    {
        let mut chars = Vec::new();
        for ch in text.chars() {
            chars.push(ch);
        }
        apply(chars.iter().copied(), kind, limit)
    }
    #[cfg(not(feature = "eager-input"))]
    apply(text.chars(), kind, limit)
}

fn apply(
    chars: impl Iterator<Item = char>,
    kind: usize,
    limit: usize,
) -> Result<String, NormalizeError> {
    match kind {
        0 => collect_bounded(chars.nfc(), limit),
        1 => collect_bounded(chars.nfd(), limit),
        2 => collect_bounded(chars.nfkc(), limit),
        _ => collect_bounded(chars.nfkd(), limit),
    }
}

#[inline(never)]
fn consume(text: &str, form: &str, max: Option<i64>, expected: &str, status: usize) -> usize {
    let result = normalize(text, form, max);
    if status == 0 {
        let out = result.expect("normalization success");
        assert_eq!(out, expected);
        return out.len() + 17;
    }
    let error = if status == 1 {
        NormalizeError::LimitExceeded
    } else {
        NormalizeError::InvalidInput
    };
    assert_eq!(result, Err(error));
    17
}

struct Pattern {
    name: &'static str,
    text: &'static str,
    expected: [&'static str; 4],
}
const FORMS: [&str; 4] = ["NFC", "NFD", "NFKC", "NFKD"];
fn iterations(size: usize) -> usize {
    if size <= 128 {
        return 200000;
    }
    if size >= 65536 {
        return 16;
    }
    if size >= 4096 {
        return 256;
    }
    4096
}
fn measure(
    name: &str,
    text: &str,
    form: &str,
    max: Option<i64>,
    expected: &str,
    status: usize,
    count: usize,
) {
    let expected_sum = if status == 0 { expected.len() + 17 } else { 17 };
    assert_eq!(consume(text, form, max, expected, status), expected_sum);
    let started = Instant::now();
    let mut checksum = 0usize;
    for _ in 0..count {
        checksum += black_box(consume(
            black_box(text),
            black_box(form),
            black_box(max),
            black_box(expected),
            black_box(status),
        ));
    }
    let elapsed = started.elapsed().as_nanos();
    assert_eq!(checksum, expected_sum * count);
    println!("{name},{},{count},{elapsed},{checksum}", text.len());
}
fn main() {
    println!("case,input_bytes,iterations,elapsed_ns,checksum");
    for p in [
        Pattern {
            name: "empty",
            text: "",
            expected: [""; 4],
        },
        Pattern {
            name: "one_ascii",
            text: "x",
            expected: ["x"; 4],
        },
        Pattern {
            name: "ascii_controls",
            text: "abC9\0\t",
            expected: ["abC9\0\t"; 4],
        },
        Pattern {
            name: "compose",
            text: "e\u{301}",
            expected: ["é", "e\u{301}", "é", "e\u{301}"],
        },
        Pattern {
            name: "decompose",
            text: "é",
            expected: ["é", "e\u{301}", "é", "e\u{301}"],
        },
        Pattern {
            name: "compatibility",
            text: "ﬁ①",
            expected: ["ﬁ①", "ﬁ①", "fi1", "fi1"],
        },
        Pattern {
            name: "reorder",
            text: "a\u{315}\u{300}",
            expected: ["à\u{315}", "a\u{300}\u{315}", "à\u{315}", "a\u{300}\u{315}"],
        },
        Pattern {
            name: "hangul",
            text: "각",
            expected: ["각", "각", "각", "각"],
        },
        Pattern {
            name: "replacement_nul",
            text: "a\u{fffd}\0",
            expected: ["a\u{fffd}\0"; 4],
        },
    ] {
        for (form, expected) in FORMS.into_iter().zip(p.expected) {
            measure(
                &format!("{}_{form}_full", p.name),
                p.text,
                form,
                None,
                expected,
                0,
                iterations(p.text.len()),
            );
        }
    }
    for p in [
        Pattern {
            name: "ascii_scale",
            text: "aZ09\0",
            expected: ["aZ09\0"; 4],
        },
        Pattern {
            name: "canonical_scale",
            text: "e\u{301}",
            expected: ["é", "e\u{301}", "é", "e\u{301}"],
        },
        Pattern {
            name: "compatibility_scale",
            text: "ﬁ①",
            expected: ["ﬁ①", "ﬁ①", "fi1", "fi1"],
        },
    ] {
        for copies in [4096, 65536] {
            let text = p.text.repeat(copies);
            for (form, expected) in FORMS.into_iter().zip(p.expected) {
                let expected = expected.repeat(copies);
                measure(
                    &format!("{}_{copies}_{form}_full", p.name),
                    &text,
                    form,
                    None,
                    &expected,
                    0,
                    iterations(text.len()),
                );
            }
        }
    }
    let cluster = "a".to_owned() + &"\u{315}\u{300}".repeat(256);
    let decomposed = "a".to_owned() + &"\u{300}".repeat(256) + &"\u{315}".repeat(256);
    let composed = "à".to_owned() + &"\u{300}".repeat(255) + &"\u{315}".repeat(256);
    for form in FORMS {
        let expected = if ["NFC", "NFKC"].contains(&form) {
            &composed
        } else {
            &decomposed
        };
        measure(
            &format!("combining_segment_{form}_full"),
            &cluster,
            form,
            None,
            expected,
            0,
            64,
        );
    }
    let budget_text = "e\u{301}".repeat(4096);
    for form in FORMS {
        let expected = if ["NFC", "NFKC"].contains(&form) {
            "é"
        } else {
            "e\u{301}"
        }
        .repeat(4096);
        let exact = expected.len() as i64;
        let count = iterations(budget_text.len());
        measure(
            &format!("budget_{form}_zero"),
            &budget_text,
            form,
            Some(0),
            "",
            1,
            count,
        );
        measure(
            &format!("budget_{form}_exact"),
            &budget_text,
            form,
            Some(exact),
            &expected,
            0,
            count,
        );
        measure(
            &format!("budget_{form}_exceeded"),
            &budget_text,
            form,
            Some(exact - 1),
            "",
            1,
            count,
        );
        measure(
            &format!("negative_{form}"),
            "é",
            form,
            Some(-1),
            "",
            2,
            200000,
        );
    }
    for (name, form, max) in [
        ("invalid_lowercase", "nfc", None),
        ("invalid_unknown", "UNKNOWN", None),
        ("invalid_nul", "NFC\0", None),
        ("invalid_negative", "UNKNOWN", Some(-1)),
    ] {
        measure(name, "é", form, max, "", 2, 200000);
    }
    let boundary = Pattern {
        name: "unicode_boundary",
        text: "éﬁ",
        expected: ["éﬁ", "e\u{301}ﬁ", "éfi", "e\u{301}fi"],
    };
    for length in [4096, 1048576] {
        let prefix = "x".repeat(length);
        for (form, block) in FORMS.into_iter().zip(boundary.expected) {
            let count = iterations(length + boundary.text.len());
            measure(
                &format!("early_unicode_{length}_{form}"),
                &(boundary.text.to_owned() + &prefix),
                form,
                None,
                &(block.to_owned() + &prefix),
                0,
                count,
            );
            measure(
                &format!("late_unicode_{length}_{form}"),
                &(prefix.clone() + boundary.text),
                form,
                None,
                &(prefix.clone() + block),
                0,
                count,
            );
        }
    }
}
