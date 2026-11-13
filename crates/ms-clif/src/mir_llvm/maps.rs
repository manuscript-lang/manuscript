//! Maps and sets.
//!
//! A `Map` or `Set` is seven `i64` leaves (`MapVal`), so it travels through calls, phis and
//! returns like any other leaf list. An empty one is all zero words (`ms_rt::map::empty()`, pinned
//! by a runtime test), so `map_new` is seven constants and no call. Every other map operation is a
//! runtime call, which passes the map by address.

use ms_mir::ir::{ExternRole, Imm, Inst, Module, Op};

/// Whether `inst` is the `map_new` runtime call that makes an empty map or set.
pub fn is_map_new(m: &Module, inst: &Inst) -> bool {
    matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].role == ExternRole::MapNew)
}

#[cfg(test)]
mod tests {
    use super::super::{Plan, emit, supports};
    use crate::layout::Layouts;

    const SRC: &str = r#"module "maps"
extern @msrt_map_new() -> Map<int, int> map_new
entry @main
fn @fresh() -> Map<int, int> {
b0:
  %m: Map<int, int> = call.rt @msrt_map_new ()
  ret %m
}
fn @main() -> int {
b0:
  %x: int = iconst 1
  ret %x
}
"#;

    /// A map lookup's null test is one `icmp` against zero, widened to the `Bool` leaf.
    #[test]
    fn a_null_test_compares_with_zero() {
        let m = ms_mir::parse::parse_module(
            "module \"n\"\nentry @main\nfn @main(%p: ptr) -> bool {\nb0:\n  %r: bool = ptr.is_null %p\n  ret %r\n}\n",
        )
        .expect("parse");
        let lay = Layouts::new(&m);
        let f = &m.funcs[0];
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, &Plan::default(), 0, &|i| format!("f{i}"));
        assert!(out.body.contains("icmp eq i64 %a0_0, 0"), "{}", out.body);
        assert!(out.body.contains("zext i1"), "{}", out.body);
    }

    /// An empty map is seven zero leaves: no call, and a seven-leaf return.
    #[test]
    fn an_empty_map_is_seven_zero_words() {
        let m = ms_mir::parse::parse_module(SRC).expect("parse");
        let lay = Layouts::new(&m);
        let f = m.funcs.iter().find(|f| f.name == "fresh").expect("fresh");
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, &Plan::default(), 0, &|i| format!("f{i}"));
        assert!(!out.body.contains("call"), "{}", out.body);
        assert!(
            out.ret.contains("{ i64, i64, i64, i64, i64, i64, i64 }"),
            "{}",
            out.ret
        );
        assert_eq!(out.body.matches("i64 0, ").count(), 7, "{}", out.body);
    }
}
