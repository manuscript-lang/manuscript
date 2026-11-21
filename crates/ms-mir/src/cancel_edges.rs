//! What cancel exits share: whether the explicit exits are switched on, the extern they declare, and
//! which instructions can reach a cancellation point. The pass itself is `compiler/src/mir/mir_cancel_edges.c`.

use crate::ir::*;
use crate::types::Ty;

/// Whether the edges are switched on for this build.
pub fn enabled() -> bool {
    std::env::var_os("MS_CANCEL_EDGES").is_some()
}

pub(crate) fn extern_of(
    m: &mut Module,
    name: &str,
    params: &[Ty],
    ret: Ty,
    leaf: bool,
    role: ExternRole,
) -> ExtId {
    if let Some(i) = m.externs.iter().position(|e| e.name == name) {
        return ExtId(i as u32);
    }
    m.add_extern(ExternDef {
        name: name.into(),
        params: params
            .iter()
            .map(|ty| Param {
                ty: *ty,
                mode: Mode::Borrow,
            })
            .collect(),
        ret,
        noreturn: false,
        pure_: false,
        fresh: false,
        retains: false,
        role,
        leaf,
        reads: false,
    })
}

/// Whether `inst` can reach a cancellation point.
pub(crate) fn parks(m: &Module, parks: &[bool], inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::Poll | Op::CallInd | Op::CallMethod, _) => true,
        (Op::CallRt, Imm::Ext(e)) => {
            let d = &m.externs[e.index()];
            !(d.noreturn || d.leaf)
        }
        (Op::Call, Imm::Func(g)) => parks.get(g.index()).copied().unwrap_or(true),
        _ => false,
    }
}
