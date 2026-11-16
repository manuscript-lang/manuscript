//! The kinds of generated helper functions ("glue") a backend synthesizes per type or function,
//! and their naming, shared by every backend so they agree on what each kind is.

/// The name prefix of generated glue functions, followed by the kind and an owner.
pub const GLUE_PREFIX: &str = "ms.glue.";

/// Kinds of generated helper functions.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Glue {
    /// Drops a value (takes the value's leaves).
    Drop,
    /// Clones a value (takes and returns the value's leaves).
    Clone,
    /// Closure object destructor `fn(obj)`; the `Ty` is unused (`Ty::VOID`) and the key carries the function id.
    ClosureDrop(u32),
    /// Like `ClosureDrop` for an object in a stack frame: drops the captures, frees nothing.
    ClosureDropFramed(u32),
    /// `fn(obj)` that releases a closure object after capture `k` while a fault unwinds out of the
    /// close of that capture (whose value that close owns): it drops the later captures without
    /// closing them and frees the object.
    ClosureDropFrom(u32, u32),
    /// Closure object clone entry `fn(obj) -> obj`, cloning the captures; keyed like `ClosureDrop`.
    ClosureClone(u32),
    /// Heap block destructor of an interface payload `fn(block)`.
    BlockDrop,
    /// Clone of an interface payload block `fn(block) -> block`.
    BlockClone,
    /// `fn(arg: *mut u8)` thunk used by cleanup.push; key carries the closer function.
    CleanupThunk(u32),
    /// `fn(slot)` that drops the value stored in memory at `slot` (descriptor `drop`).
    SlotDrop,
    /// `fn(src, dst)` that copies the value at `src` into uninitialised `dst` (descriptor `copy`).
    SlotCopy,
}

impl Glue {
    /// The kind's part of a glue symbol.
    pub fn suffix(self) -> &'static str {
        match self {
            Glue::Drop => "drop",
            Glue::Clone => "clone",
            Glue::ClosureDrop(_) => "closure_drop",
            Glue::ClosureDropFramed(_) => "closure_drop_framed",
            Glue::ClosureDropFrom(..) => "closure_drop_from",
            Glue::ClosureClone(_) => "closure_clone",
            Glue::BlockDrop => "block_drop",
            Glue::BlockClone => "block_clone",
            Glue::CleanupThunk(_) => "cleanup_thunk",
            Glue::SlotDrop => "slot_drop",
            Glue::SlotCopy => "slot_copy",
        }
    }
}

use crate::builder::FuncBuilder;
use crate::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param};
use crate::layout::Layouts;
use crate::types::{Ty, TyKind};
use std::collections::HashSet;

/// Makes the drop function of every type whose drop is a walk of its fields (a record or an
/// alternative that does not contain itself) and records it in [`Module::drop_glue`]. Backends
/// call these functions instead of writing a drop body of their own, so they cannot disagree on
/// which cases and fields a drop releases. Returns whether anything was made.
pub fn run(m: &mut Module) -> bool {
    let (drops, clones) = wanted_types(m);
    let lay = Layouts::new(m);
    let eligible = |t: &Ty| match m.types.kind(*t) {
        TyKind::Type(_) | TyKind::Alt(_) | TyKind::List(_) | TyKind::Bytes => true,
        // A present flag and the payload's leaves; the other layouts are one pointer.
        TyKind::Opt(inner) => {
            !lay.opt_is_nullable(*inner) && !lay.opt_is_boxed(*inner) && !lay.is_str_like(*t)
        }
        _ => false,
    };
    let eligible = |t: &Ty| eligible(t) && m.needs_drop(*t) && !m.drop_recurses(*t);
    let mut drop_tys: Vec<Ty> = drops.into_iter().filter(eligible).collect();
    // A list of plain elements is copied by the backends in one block copy.
    let mut clone_tys: Vec<Ty> = clones
        .into_iter()
        .filter(eligible)
        .filter(|t| match m.types.kind(*t) {
            TyKind::List(e) => m.needs_drop(*e),
            TyKind::Bytes => false,
            _ => true,
        })
        .collect();
    drop(lay);
    // The same order every run.
    drop_tys.sort_by_key(|t| t.0);
    clone_tys.sort_by_key(|t| t.0);
    let made = !drop_tys.is_empty() || !clone_tys.is_empty();
    for ty in drop_tys {
        let id = make_drop(m, ty);
        m.drop_glue.insert(ty, id);
    }
    for ty in clone_tys {
        let id = make_clone(m, ty);
        m.clone_glue.insert(ty, id);
    }
    made
}

/// The types a function of the program drops and the types it clones, with what dropping or
/// cloning those drops or clones in turn. A type missing here only keeps the backend's own
/// function, so this may under-count but never changes a result.
fn wanted_types(m: &Module) -> (HashSet<Ty>, HashSet<Ty>) {
    let mut drops: Vec<Ty> = Vec::new();
    let mut clones: Vec<Ty> = Vec::new();
    for f in &m.funcs {
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let arg = |k: usize| inst.args.get(k).map(|v| f.ty(*v));
            match inst.op {
                Op::Drop => drops.extend(arg(0)),
                Op::DropIf => drops.extend(arg(1)),
                Op::Clone => clones.extend(arg(0)),
                Op::OptUnwrap => clones.extend(arg(0).and_then(|t| m.opt_inner(t))),
                Op::AltOwn => clones.extend(inst.res.map(|r| f.ty(r))),
                Op::AltRelease | Op::AltUnbox | Op::AltTake | Op::TypeRelease | Op::OptUnbox => {
                    drops.extend(arg(0))
                }
                Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListDropLast | Op::ListRelease => {
                    drops.extend(arg(0).and_then(|t| m.seq_elem(t)))
                }
                Op::TypeDesc => {
                    if let Imm::Ty(t) = inst.imm {
                        drops.push(t);
                        clones.push(t);
                    }
                }
                _ => {}
            }
        }
    }
    (close(m, drops), close(m, clones))
}

/// `seed` and the types dropped (or cloned) when a value of one of them is.
fn close(m: &Module, seed: Vec<Ty>) -> HashSet<Ty> {
    let mut seen: HashSet<Ty> = HashSet::new();
    let mut todo = seed;
    while let Some(t) = todo.pop() {
        if seen.insert(t.unscoped()) {
            todo.extend(m.drop_children(t.unscoped()));
        }
    }
    seen
}

fn make_drop(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.drop", m.drop_glue.len());
    let lay_boxed = |m: &Module, a| Layouts::new(m).is_boxed(a);
    let params = vec![Param {
        ty,
        mode: Mode::Move,
    }];
    match m.types.kind(ty).clone() {
        TyKind::Type(r) => {
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            b.emit(Op::TypeRelease, &[p], Imm::TypeMask(r, 0), None);
            b.ret(None);
            b.finish()
        }
        TyKind::Alt(a) => {
            let boxed = lay_boxed(m, a);
            let def = m.alts[a.index()].clone();
            let owns: Vec<bool> = def
                .cases
                .iter()
                .enumerate()
                .map(|(c, case)| !def.borrows(c) && case.fields.iter().any(|f| m.needs_drop(f.1)))
                .collect();
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let done = b.new_block();
            // A case that owns nothing needs no code, unless it holds a block to free: payloadless
            // cases of a boxed alternative share a static block that is never freed.
            let mut arms = Vec::new();
            for (c, case) in def.cases.iter().enumerate() {
                if case.fields.is_empty() {
                    continue;
                }
                let drops = owns[c];
                if !boxed && !drops {
                    continue;
                }
                arms.push((c, drops, case.fields.len()));
            }
            if arms.is_empty() {
                b.ret(None);
                return b.finish();
            }
            let tag = b.alt_tag(p);
            let blocks: Vec<_> = arms.iter().map(|_| b.new_block()).collect();
            let cases: Vec<(i64, _)> = arms
                .iter()
                .zip(&blocks)
                .map(|((c, ..), blk)| (*c as i64, *blk))
                .collect();
            b.switch(tag, &cases, done);
            for ((c, drops, n), blk) in arms.into_iter().zip(blocks) {
                b.switch_to(blk);
                // Every field marked moved: the release only frees the block.
                let mask = match (drops, n) {
                    (true, _) => 0,
                    (false, 32..) => u32::MAX,
                    (false, _) => (1u32 << n) - 1,
                };
                b.alt_release(a, c as u32, mask, p);
                b.br(done, &[]);
            }
            b.switch_to(done);
            b.ret(None);
            b.finish()
        }
        TyKind::Opt(_) => {
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let (some, done) = (b.new_block(), b.new_block());
            let present = b.opt_is_some(p);
            b.br_if(present, some, &[], done, &[]);
            b.switch_to(some);
            let payload = b.opt_get(p);
            b.emit(Op::Drop, &[payload], Imm::None, None);
            b.br(done, &[]);
            b.switch_to(done);
            b.ret(None);
            b.finish()
        }
        TyKind::List(_) | TyKind::Bytes => {
            let elem = m.list_elem(ty).filter(|e| m.needs_drop(*e));
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let (owned, done) = (b.new_block(), b.new_block());
            // A view (capacity 0) borrows its elements: nothing to drop or free.
            let cap = b
                .emit(Op::ListCap, &[p], Imm::None, Some(Ty::INT))
                .expect("cap");
            let zero = b.iconst(0);
            let is_owned = b.icmp(Cc::Ne, cap, zero);
            b.br_if(is_owned, owned, &[], done, &[]);
            b.switch_to(owned);
            if elem.is_some() {
                let len = b.list_len(p);
                let (head, body, free) = (b.new_block(), b.new_block(), b.new_block());
                let i = b.add_block_param(head, Ty::INT, Mode::Borrow);
                let start = b.iconst(0);
                b.br(head, &[start]);
                b.switch_to(head);
                let more = b.icmp(Cc::Lt, i, len);
                b.br_if(more, body, &[], free, &[]);
                b.switch_to(body);
                let x = b
                    .emit(Op::ListGetU, &[p, i], Imm::None, elem)
                    .expect("element");
                b.emit(Op::Drop, &[x], Imm::None, None);
                let one = b.iconst(1);
                let next = b.binop(Op::IAdd, i, one);
                b.br(head, &[next]);
                b.switch_to(free);
            }
            b.emit(Op::Free, &[p], Imm::None, None);
            b.br(done, &[]);
            b.switch_to(done);
            b.ret(None);
            b.finish()
        }
        _ => unreachable!("drop glue is made for records, alternatives, optionals and lists"),
    }
}

/// `fn(&T) -> T` for a record or an enum: every field is cloned and the value rebuilt, so a
/// borrowing variant comes out as an ordinary owned value.
fn make_clone(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.clone", m.clone_glue.len());
    let params = vec![Param {
        ty,
        mode: Mode::Borrow,
    }];
    match m.types.kind(ty).clone() {
        TyKind::Type(r) => {
            let n = m.type_defs[r.index()].fields.len() as u32;
            let mut b = FuncBuilder::new(m, &name, params, ty);
            let p = b.params()[0];
            let fields: Vec<_> = (0..n)
                .map(|k| {
                    let v = b.type_get(r, k, p);
                    b.clone_value(v)
                })
                .collect();
            let out = b.type_new(r, &fields);
            b.ret(Some(out));
            b.finish()
        }
        TyKind::Alt(a) => {
            let cases: Vec<usize> = m.alts[a.index()]
                .cases
                .iter()
                .map(|c| c.fields.len())
                .collect();
            let mut b = FuncBuilder::new(m, &name, params, ty);
            let p = b.params()[0];
            let tag = b.alt_tag(p);
            let blocks: Vec<_> = cases.iter().map(|_| b.new_block()).collect();
            let default = b.new_block();
            let sw: Vec<(i64, _)> = blocks
                .iter()
                .enumerate()
                .map(|(c, k)| (c as i64, *k))
                .collect();
            b.switch(tag, &sw, default);
            for (c, (n, blk)) in cases.into_iter().zip(blocks).enumerate() {
                b.switch_to(blk);
                let fields: Vec<_> = (0..n as u32)
                    .map(|k| {
                        let v = b.alt_get(a, c as u32, k, p);
                        b.clone_value(v)
                    })
                    .collect();
                let out = b.alt_new(a, c as u32, &fields);
                b.ret(Some(out));
            }
            b.switch_to(default);
            b.unreachable();
            b.finish()
        }
        TyKind::Opt(_) => {
            let mut b = FuncBuilder::new(m, &name, params, ty);
            let p = b.params()[0];
            let (some, none) = (b.new_block(), b.new_block());
            let present = b.opt_is_some(p);
            b.br_if(present, some, &[], none, &[]);
            b.switch_to(some);
            let payload = b.opt_get(p);
            let copy = b.clone_value(payload);
            let out = b.opt_some(copy);
            b.ret(Some(out));
            b.switch_to(none);
            let out = b.opt_none(ty);
            b.ret(Some(out));
            b.finish()
        }
        TyKind::List(elem) => {
            let mut b = FuncBuilder::new(m, &name, params, ty);
            let p = b.params()[0];
            let len = b.list_len(p);
            let fresh = b.list_new(elem, len);
            let (head, body, exit) = (b.new_block(), b.new_block(), b.new_block());
            let i = b.add_block_param(head, Ty::INT, Mode::Borrow);
            let acc = b.add_block_param(head, ty, Mode::Move);
            let start = b.iconst(0);
            b.br(head, &[start, fresh]);
            b.switch_to(head);
            let more = b.icmp(Cc::Lt, i, len);
            b.br_if(more, body, &[], exit, &[]);
            b.switch_to(body);
            let x = b
                .emit(Op::ListGetU, &[p, i], Imm::None, Some(elem))
                .expect("element");
            let c = b.clone_value(x);
            let grown = b
                .emit(Op::ListPushU, &[acc, c], Imm::None, Some(ty))
                .expect("list");
            let one = b.iconst(1);
            let next = b.binop(Op::IAdd, i, one);
            b.br(head, &[next, grown]);
            b.switch_to(exit);
            b.ret(Some(acc));
            b.finish()
        }
        _ => unreachable!("clone glue is made for records, alternatives, optionals and lists"),
    }
}
