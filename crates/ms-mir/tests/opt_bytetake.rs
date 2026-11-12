use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const DECODE: &str = r#"module "t"
file 0 "t.ms"
extern @msrt_bytes_decode_utf8(bytes, ptr) -> bool fresh leaf takes_dying
entry @main

fn @dying(%0: move bytes) -> int inline(never) {
b0:
  %s: ptr = slot str
  %ok: bool = call.rt @msrt_bytes_decode_utf8 (%0, %s)
  drop %0
  %n: int = iconst 0
  ret %n
}

fn @kept(%0: bytes) -> int inline(never) {
b0:
  %s: ptr = slot str
  %ok: bool = call.rt @msrt_bytes_decode_utf8 (%0, %s)
  %n: int = iconst 0
  ret %n
}

fn @main() -> int export {
b0:
  %n: int = iconst 0
  ret %n
}
"#;

fn function<'a>(text: &'a str, name: &str) -> &'a str {
    let start = text.find(&format!("fn @{name}(")).expect("function");
    let rest = &text[start..];
    &rest[..rest.find("\n}").expect("end")]
}

/// A `Bytes` dropped right after its decode moves into `bytes_decode_utf8_take`; a borrowed one
/// keeps the copying call.
#[test]
fn decoding_a_dying_buffer_takes_it() {
    let mut m = parse_module(DECODE).expect("parse");
    verify_module(&m).expect("verify");
    opt::bytetake::run(&mut m);
    verify_module(&m).expect("output verifies");
    let text = print_module(&m);
    let dying = function(&text, "dying");
    assert!(dying.contains("@msrt_bytes_decode_utf8_take"), "{text}");
    assert!(!dying.contains("drop"), "{text}");
    let kept = function(&text, "kept");
    assert!(!kept.contains("_take"), "{text}");
}

const UPPER: &str = r#"module "t"
file 0 "t.ms"
extern @msrt_string_upper(str) -> str fresh leaf takes_dying
entry @main

fn @dying(%0: move str) -> int inline(never) {
b0:
  %u: str = call.rt @msrt_string_upper (%0)
  drop %0
  %n: int = str.len %u
  drop %u
  ret %n
}

fn @kept(%0: str) -> int inline(never) {
b0:
  %u: str = call.rt @msrt_string_upper (%0)
  %n: int = str.len %u
  drop %u
  ret %n
}

fn @main() -> int export {
b0:
  %n: int = iconst 0
  ret %n
}
"#;

/// A `String` dropped right after `upper` moves into `upper_take`; a borrowed one keeps the copy.
#[test]
fn upper_of_a_dying_string_takes_it() {
    let mut m = parse_module(UPPER).expect("parse");
    verify_module(&m).expect("verify");
    opt::bytetake::run(&mut m);
    verify_module(&m).expect("output verifies");
    let text = print_module(&m);
    let dying = function(&text, "dying");
    assert!(dying.contains("@msrt_string_upper_take"), "{text}");
    assert!(!dying.contains("drop %0"), "{text}");
    let kept = function(&text, "kept");
    assert!(!kept.contains("_take"), "{text}");
}
