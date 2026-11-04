use ms_mir::copies::object_copies;
use ms_mir::parse::parse_module;

// A closure copy is an object copy; a copy of a string or of a bare `none` is not.
const SRC: &str = r#"module "t"
file 0 "t.ms"
entry @main

fn @add(%env: ptr, %x: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %r: int = iadd.chk %x, %k
  ret %r
}

fn @main() -> int {
b0:
  %k: int = iconst 1
  %f: fn(int) -> int = closure.new @add %k !0:3:5
  %g: fn(int) -> int = clone %f !0:4:5
  %s: str = str "ab"
  %t: str = clone %s
  %n: opt<fn(int) -> int> = opt.none
  %m: opt<fn(int) -> int> = clone %n
  drop %m
  drop %t
  drop %g
  %a: int = call.ind (%f, %k)
  ret %a
}
"#;

#[test]
fn lists_copies_of_object_values_only() {
    let m = parse_module(SRC).unwrap_or_else(|e| panic!("{e}"));
    let sites = object_copies(&m);
    assert_eq!(sites.len(), 1, "{sites:?}");
    assert_eq!(sites[0].func, "main");
    assert_eq!(sites[0].ty, "fn(int) -> int");
    assert_eq!((sites[0].file.as_str(), sites[0].line), ("t.ms", 4));
}
