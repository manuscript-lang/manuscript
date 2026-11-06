use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const SUM: &str = r#"module "sum"
entry @main
fn @sum(%n: int) -> int {
b0:
  %z: int = iconst 0
  br loop(%z, %z)
loop(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), done()
body:
  %a: int = iadd.chk %acc, %i
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j, %a)
done:
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 100
  %r: int = call @sum(%n)
  ret %r
}
"#;

#[test]
fn parse_verify_roundtrip() {
    let m = parse_module(SUM).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let text = print_module(&m);
    let m2 = parse_module(&text).unwrap_or_else(|e| panic!("{e}\n{text}"));
    assert_eq!(text, print_module(&m2));
}

#[test]
fn extern_attributes_roundtrip() {
    let src = r#"module "e"
extern @msrt_string_concat(str, str) -> str fresh
extern @msrt_fault_string(str) noreturn
extern @msrt_string_len(str) -> int pure
fn @main() -> int {
b0:
  %a: str = str "a"
  %b: str = call.rt @msrt_string_concat (%a, %a)
  %n: int = call.rt @msrt_string_len (%b)
  drop %b
  ret %n
}
"#;
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    assert!(m.externs[0].fresh && !m.externs[1].fresh && !m.externs[2].fresh);
    assert!(m.externs[1].noreturn && m.externs[2].pure_);
    let text = print_module(&m);
    assert!(text.contains("-> str fresh\n"), "{text}");
    let m2 = parse_module(&text).unwrap_or_else(|e| panic!("{e}\n{text}"));
    assert_eq!(text, print_module(&m2));
}

const CONST_POOLS: &str = r#"module "pools"
blob 0 "00ff80"
blob 1 ""
consts 0 [1, -2, 9223372036854775807]
entry @main
fn @main() -> int {
b0:
  %data: bytes = bytes 0
  %n: int = list.len %data
  ret %n
}
"#;

#[test]
fn constant_pools_survive_text_roundtrip() {
    let m = parse_module(CONST_POOLS).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(m.blobs, vec![vec![0, 255, 128], vec![]]);
    assert_eq!(m.list_consts, vec![vec![1, -2, i64::MAX]]);
    let text = print_module(&m);
    let m2 = parse_module(&text).unwrap_or_else(|e| panic!("{e}\n{text}"));
    verify_module(&m2).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(m.blobs, m2.blobs);
    assert_eq!(m.list_consts, m2.list_consts);
    assert_eq!(text, print_module(&m2));
}
