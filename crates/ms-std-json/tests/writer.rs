//! The streaming writer's layout, undo and failure rules.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_json::Writer;

fn sample(w: &mut Writer) {
    w.begin_object();
    w.key("a");
    w.begin_array();
    w.item();
    w.int(-9_223_372_036_854_775_807 - 1);
    w.item();
    w.string("q\"\\\n\u{1}é");
    w.item();
    w.null();
    w.end_array();
    w.key("empty");
    w.begin_object();
    w.end_object();
    w.key("dropped");
    w.int(1);
    w.undo();
    w.key("b");
    w.boolean(true);
    w.end_object();
}

#[test]
fn compact_output() {
    let mut w = Writer::new(None, None);
    sample(&mut w);
    assert_eq!(
        w.finish().unwrap(),
        "{\"a\":[-9223372036854775808,\"q\\\"\\\\\\n\\u0001é\",null],\"empty\":{},\"b\":true}"
    );
}

#[test]
fn indented_output() {
    let mut w = Writer::new(None, Some(2));
    sample(&mut w);
    assert_eq!(
        w.finish().unwrap(),
        "{\n  \"a\": [\n    -9223372036854775808,\n    \"q\\\"\\\\\\n\\u0001é\",\n    null\n  ],\n  \"empty\": {},\n  \"b\": true\n}"
    );
}

#[test]
fn undo_of_the_only_member_leaves_an_empty_object() {
    let mut w = Writer::new(None, Some(2));
    w.begin_array();
    w.item();
    w.undo();
    w.end_array();
    assert_eq!(w.finish().unwrap(), "[]");
}

#[test]
fn failures_are_kept() {
    let mut w = Writer::new(Some(3), None);
    w.string("abc");
    assert!(matches!(w.finish(), Err(Fail::LimitExceeded)));

    let mut w = Writer::new(None, None);
    w.number("01");
    w.null();
    assert!(matches!(w.finish(), Err(Fail::InvalidData)));

    assert!(matches!(
        Writer::new(Some(-1), None).finish(),
        Err(Fail::InvalidInput)
    ));
    assert!(matches!(
        Writer::new(None, Some(-1)).finish(),
        Err(Fail::InvalidInput)
    ));
}

#[test]
fn nesting_past_the_ceiling_fails() {
    let mut w = Writer::new(None, None);
    for _ in 0..=ms_std_json::DEPTH_CEILING {
        w.begin_array();
    }
    assert!(matches!(w.finish(), Err(Fail::InvalidData)));
}

#[test]
fn escapes_agree_for_short_and_long_strings() {
    let unit = "a\"b\\c\u{8}\u{c}\n\r\t\u{1f}é";
    let want = "a\\\"b\\\\c\\b\\f\\n\\r\\t\\u001fé";
    for reps in [1, 2, 8] {
        let mut w = Writer::new(None, None);
        w.string(&unit.repeat(reps));
        assert_eq!(w.finish().unwrap(), format!("\"{}\"", want.repeat(reps)));
    }
}

#[test]
fn quoted_keys_and_whole_floats() {
    let mut w = Writer::new(None, Some(1));
    w.begin_object();
    w.key_quoted("\"k\\n\"");
    w.begin_array();
    for v in [3.0, -0.0, -7.0, 1e14, 1e15, 1.5, 0.0] {
        w.item();
        w.float(v);
    }
    w.end_array();
    w.end_object();
    assert_eq!(
        w.finish().unwrap(),
        "{\n \"k\\n\": [\n  3,\n  -0,\n  -7,\n  100000000000000,\n  1000000000000000,\n  1.5,\n  0\n ]\n}"
    );
}

#[test]
fn floats_match_the_shortest_round_trip_text() {
    // A seeded walk over magnitudes and digit counts; `f64`'s own `{}` is the oracle for the digits.
    let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
    let mut next = || {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x
    };
    for i in 0..200_000u64 {
        let v = match i % 4 {
            0 => f64::from_bits(next()),
            1 => (next() % 1_000_000) as f64 / 100.0,
            2 => (next() % 100_000_000_000) as f64 / 10f64.powi((next() % 15) as i32),
            _ => (next() % 10_000) as f64 * 10f64.powi((next() % 40) as i32 - 20),
        };
        if !v.is_finite() {
            continue;
        }
        let mut w = Writer::new(None, None);
        w.float(v);
        let got = w.finish().unwrap();
        let back: f64 = got.parse().unwrap();
        assert_eq!(back.to_bits(), v.to_bits(), "{v:e} -> {got}");
        // Shortest: Rust's shortest digits, however placed, have the same count.
        let digits = |t: &str| {
            t.split(['e', 'E'])
                .next()
                .unwrap()
                .chars()
                .filter(char::is_ascii_digit)
                .collect::<String>()
                .trim_matches('0')
                .len()
        };
        assert_eq!(digits(&got), digits(&format!("{v:e}")), "{v:e} -> {got}");
    }
}

#[test]
fn integers_cover_every_digit_count() {
    let values = [
        0,
        5,
        9,
        10,
        11,
        99,
        100,
        101,
        999,
        1000,
        12345,
        99_999,
        100_000,
        -1,
        -10,
        -100,
        -123_456,
        i64::MAX,
        i64::MIN,
        1_000_000_007,
    ];
    let mut w = Writer::new(None, None);
    w.begin_array();
    for v in values {
        w.item();
        w.int(v);
    }
    w.end_array();
    let want: Vec<String> = values.iter().map(i64::to_string).collect();
    assert_eq!(w.finish().unwrap(), format!("[{}]", want.join(",")));
}

/// What `serde_json`-style escaping gives, one byte at a time.
fn escaped(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[test]
fn short_strings_and_names_match_the_byte_escape_at_every_length_and_position() {
    for len in 0..=20usize {
        let mut texts = vec!["a".repeat(len)];
        for at in 0..len {
            for bad in ['"', '\\', '\n', '\u{1f}', ' ', '\u{7f}'] {
                let mut chars: Vec<char> = "a".repeat(len).chars().collect();
                chars[at] = bad;
                texts.push(chars.into_iter().collect());
            }
        }
        for text in texts {
            let mut w = Writer::new(None, None);
            w.begin_object();
            w.key(&text);
            w.string(&text);
            w.key(&text);
            w.int(1);
            w.key_quoted(&escaped(&text));
            w.null();
            w.end_object();
            let name = escaped(&text);
            assert_eq!(
                w.finish().unwrap(),
                format!("{{{name}:{name},{name}:1,{name}:null}}"),
                "{text:?}"
            );
        }
    }
}

#[test]
fn number_text_is_validated_whatever_its_length() {
    for ok in [
        "0",
        "7",
        "10",
        "123456789012345",
        "1234567890123456",
        "12345678901234567890",
        "-1",
        "1.5",
        "1e5",
        "0.5",
        "-0",
        "1E+2",
    ] {
        let mut w = Writer::new(None, None);
        w.number(ok);
        assert_eq!(w.finish().unwrap(), ok);
    }
    for bad in [
        "",
        "01",
        "00",
        "0123",
        "1a",
        "a1",
        "12345678a",
        " 1",
        "1 ",
        "+1",
        ".5",
        "1.",
        "1e",
        "-",
        "0x10",
        "١٢٣",
    ] {
        let mut w = Writer::new(None, None);
        w.number(bad);
        assert!(matches!(w.finish(), Err(Fail::InvalidData)), "{bad:?}");
    }
}

#[test]
fn plain_decimals_print_as_rust_displays_them() {
    // Between 1e-3 and 1e11 a JSON float and Rust's `{}` are the same text.
    let mut x: u64 = 0x2545_f491_4f6c_dd1d;
    let mut next = || {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x
    };
    for i in 0..400_000u64 {
        let k = (next() % 7) as i32;
        let v = match i % 3 {
            0 => (next() % 1_000_000_000) as f64 / 10f64.powi(k),
            1 => (next() % 1_000_000_000_000_000) as f64 / 10f64.powi(k + 3),
            _ => f64::from_bits(0x3f50_0000_0000_0000 + next() % 0x0200_0000_0000_0000),
        };
        for v in [v, -v] {
            if v == 0.0 || !(1e-3..1e11).contains(&v.abs()) {
                continue;
            }
            let mut w = Writer::new(None, None);
            w.float(v);
            assert_eq!(w.finish().unwrap(), format!("{v}"), "{v:e}");
        }
    }
}
