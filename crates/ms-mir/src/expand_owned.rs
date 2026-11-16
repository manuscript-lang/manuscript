//! Expansion of the ownership shorthands into plain loads, drops and frees.
//!
//! Lowering and the optimizer use ops that bundle a layout decision with a release or a copy:
//! `alt.own`, `alt.unbox`, `alt.release`, `type.release`, `opt.unbox`, `opt.unwrap`. After the last pass
//! that reads them (`unwind`), this pass rewrites each into `alt.get`/`type.get`/`opt.get`
//! reads, `drop`s of the fields that stay, and one `free` of the heap block when the value
//! lives behind one. The backends then lower only primitives, and the interpreter needs no
//! copy of the rules.

use crate::ir::*;
use crate::layout::Layouts;
use crate::types::TyKind;

/// Whether `op` is one the pass rewrites.
fn expands(op: Op) -> bool {
    matches!(
        op,
        Op::AltOwn | Op::AltUnbox | Op::AltRelease | Op::TypeRelease | Op::OptUnbox | Op::OptUnwrap
    )
}

/// Whether any function of `m` still has a shorthand.
pub fn needed(m: &Module) -> bool {
    m.funcs.iter().any(has_shorthand)
}

fn has_shorthand(f: &Func) -> bool {
    f.blocks
        .iter()
        .any(|b| b.insts.iter().any(|i| expands(i.op)))
}

/// Rewrites every shorthand in `m`; returns whether any was found.
pub fn run(m: &mut Module) -> bool {
    let todo: Vec<usize> = (0..m.funcs.len())
        .filter(|&i| has_shorthand(&m.funcs[i]))
        .collect();
    if todo.is_empty() {
        return false;
    }
    let mut rewritten = Vec::new();
    {
        let lay = Layouts::new(m);
        for &i in &todo {
            let mut f = m.funcs[i].clone();
            expand_func(&lay, &mut f);
            rewritten.push((i, f));
        }
    }
    for (i, f) in rewritten {
        m.funcs[i] = f;
    }
    true
}

fn expand_func(lay: &Layouts, f: &mut Func) {
    for b in 0..f.blocks.len() {
        if !f.blocks[b].insts.iter().any(|i| expands(i.op)) {
            continue;
        }
        let old = std::mem::take(&mut f.blocks[b].insts);
        let mut out = Vec::with_capacity(old.len() + 4);
        for inst in old {
            if expands(inst.op) {
                expand_inst(lay, f, inst, &mut out);
            } else {
                out.push(inst);
            }
        }
        f.blocks[b].insts = out;
    }
}

fn inst(op: Op, args: &[Value], imm: Imm, res: Option<Value>, loc: Loc) -> Inst {
    Inst {
        op,
        args: args.to_vec(),
        imm,
        res,
        loc,
    }
}

fn expand_inst(lay: &Layouts, f: &mut Func, i: Inst, out: &mut Vec<Inst>) {
    let loc = i.loc;
    let v = i.args[0];
    match (i.op, i.imm) {
        // A copy of the borrowing variant read as its ordinary alternative.
        (Op::AltOwn, _) => {
            let res = i.res.expect("alt.own result");
            let plain = f.new_value(f.ty(res));
            out.push(inst(Op::AltPlain, &[v], Imm::None, Some(plain), loc));
            out.push(inst(Op::Clone, &[plain], Imm::None, Some(res), loc));
        }
        // The owned payload of an optional known to be some (`expand` branched to the fault).
        (Op::OptUnwrap, _) => {
            let res = i.res.expect("opt.unwrap result");
            let payload = f.new_value(f.ty(res));
            out.push(inst(Op::OptGet, &[v], Imm::None, Some(payload), loc));
            out.push(inst(Op::Clone, &[payload], Imm::None, Some(res), loc));
        }
        // The payload leaves the box; the box is freed, the payload lives on.
        (Op::OptUnbox, _) => {
            let res = i.res.expect("opt.unbox result");
            out.push(inst(Op::OptGet, &[v], Imm::None, Some(res), loc));
            let TyKind::Opt(inner) = lay.m.types.kind(f.ty(v)) else {
                unreachable!("opt.unbox of a non-optional")
            };
            if lay.opt_is_boxed(*inner) {
                out.push(inst(Op::Free, &[v], Imm::None, None, loc));
            }
        }
        (Op::AltUnbox, Imm::AltField(a, c, k)) => {
            let res = i.res.expect("alt.unbox result");
            out.push(inst(Op::AltGet, &[v], i.imm, Some(res), loc));
            release_alt_fields(lay, f, v, (a, c), 1 << k, loc, out);
        }
        (Op::AltRelease, Imm::AltMask(a, c, mask)) => {
            release_alt_fields(lay, f, v, (a, c), mask, loc, out);
        }
        (Op::TypeRelease, Imm::TypeMask(r, mask)) => {
            // An indirect type is one pointer to a heap block whose map and set fields sit behind
            // their own nullable boxes: each box is freed, kept field or not, then the block.
            let indirect = lay.m.type_defs[r.index()].indirect;
            let fields = lay.m.type_defs[r.index()].fields.clone();
            for (k, (_, fty)) in fields.iter().enumerate() {
                if mask >> k & 1 == 0 && lay.m.needs_drop(*fty) {
                    let x = f.new_value(*fty);
                    out.push(inst(
                        Op::TypeGet,
                        &[v],
                        Imm::Field(r, k as u32),
                        Some(x),
                        loc,
                    ));
                    out.push(inst(Op::Drop, &[x], Imm::None, None, loc));
                }
                if indirect && lay.type_field_boxed(*fty) {
                    out.push(inst(Op::Free, &[v], Imm::Field(r, k as u32), None, loc));
                }
            }
            if indirect {
                out.push(inst(Op::Free, &[v], Imm::None, None, loc));
            }
        }
        _ => unreachable!("expand_inst is only called for its own ops"),
    }
}

/// Drops every payload field of case `c` of `v` that is not in `skip` (a bit set; `alt.release`
/// passes the moved fields, `alt.unbox` every field but the one it returns), then frees the box.
fn release_alt_fields(
    lay: &Layouts,
    f: &mut Func,
    v: Value,
    (a, c): (crate::types::AltId, u32),
    skip: u32,
    loc: Loc,
    out: &mut Vec<Inst>,
) {
    let fields = lay.m.alts[a.index()].cases[c as usize].fields.clone();
    for (k, (_, fty)) in fields.iter().enumerate() {
        if skip >> k & 1 == 1 || !lay.m.needs_drop(*fty) {
            continue;
        }
        let x = f.new_value(*fty);
        out.push(inst(
            Op::AltGet,
            &[v],
            Imm::AltField(a, c, k as u32),
            Some(x),
            loc,
        ));
        out.push(inst(Op::Drop, &[x], Imm::None, None, loc));
    }
    // A case without payload is one shared static block: nothing to free.
    if lay.is_boxed(a) && !fields.is_empty() {
        out.push(inst(Op::Free, &[v], Imm::None, None, loc));
    }
}
