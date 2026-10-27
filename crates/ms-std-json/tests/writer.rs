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
