use ms_mir::ir::{Module, Op};
use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const APPEND_LOOP: &str = r#"module "t"
extern @msrt_list_new() -> bytes
extern @msrt_strbuilder_append(ptr, str)
extern @msrt_strbuilder_freeze(ptr) -> str
entry @main

fn @main() -> int export {
b0:
  %b: bytes = call.rt @msrt_list_new ()
  %z: int = iconst 0
  %n: int = iconst 1000
  %one: int = iconst 1
  br b1(%z, %b)
b1(%i: int, %buf: own bytes):
  %lt: bool = icmp.lt %i, %n
  br_if %lt, b2(), b3()
b2():
  %s: str = str "ab"
  %slot: ptr = slot bytes
  put %slot, %buf
  %u: unit = call.rt @msrt_strbuilder_append (%slot, %s)
  %next: bytes = take bytes %slot
  %i2: int = iadd %i, %one
  br b1(%i2, %next)
b3():
  %slot2: ptr = slot bytes
  put %slot2, %buf
  %r: str = call.rt @msrt_strbuilder_freeze (%slot2)
  %len: int = str.len %r
  drop %r
  ret %len
}
"#;

fn count(m: &Module, op: Op) -> usize {
    m.funcs
        .iter()
        .flat_map(|f| &f.blocks)
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == op)
        .count()
}

#[test]
fn a_loop_carried_buffer_lives_in_one_slot() {
    let mut m = parse_module(APPEND_LOOP).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    assert!(opt::loopslot::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    // One slot and one put on entry; no per-pass move into or out of memory.
    assert_eq!(count(&m, Op::Slot), 1, "{}", print_module(&m));
    assert_eq!(count(&m, Op::Put), 1);
    assert_eq!(count(&m, Op::Take), 0);
    assert!(!opt::loopslot::run(&mut m));
}
