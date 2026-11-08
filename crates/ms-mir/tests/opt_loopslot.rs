use ms_mir::ir::{Module, Op};
use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const APPEND_LOOP: &str = r#"module "t"
extern @msrt_list_new() -> bytes list_new
extern @msrt_strbuilder_append(ptr, str) strbuilder_append
extern @msrt_strbuilder_freeze(ptr) -> str
entry @main

fn @main() -> int export {
b0:
  %b: bytes = call.rt @msrt_list_new ()
  %z: int = iconst 0
  %n: int = iconst 1000
  %one: int = iconst 1
  br b1(%z, %b)
b1(%i: int, %buf: move bytes):
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

/// `n` blocks in a row, each taking an owned list parameter it drops and replacing it.
fn owned_params(n: usize) -> String {
    let mut s = String::from(
        "module \"t\"\nfile 0 \"t.ms\"\nentry @main\n\nfn @main() -> int export {\nb0:\n  %l0: list<int> = list.lit\n  br b1(%l0)\n",
    );
    for k in 1..=n {
        s.push_str(&format!(
            "b{k}(%p{k}: move list<int>):\n  drop %p{k}\n  %l{k}: list<int> = list.lit\n  br b{}(%l{k})\n",
            k + 1
        ));
    }
    s.push_str(&format!(
        "b{}(%p: move list<int>):\n  drop %p\n  %z: int = iconst 0\n  ret %z\n}}\n",
        n + 1
    ));
    s
}

/// Looking for the puts of each owned parameter used to scan the whole function, so a function
/// with many such parameters was quadratic.
#[test]
fn many_owned_block_parameters_take_linear_time() {
    let mut m = parse_module(&owned_params(60_000)).expect("parse");
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let start = std::time::Instant::now();
    assert!(!opt::loopslot::run(&mut m));
    assert!(start.elapsed().as_secs() < 3, "took {:?}", start.elapsed());
}
