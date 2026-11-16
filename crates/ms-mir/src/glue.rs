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
    /// `fn(block)` that calls the function in the key with the parameters stored at `block` and
    /// stores its results after them: the body `msrt_task_grow` runs on a new stack segment.
    GrowShim(u32),
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
            Glue::GrowShim(_) => "grow_shim",
            Glue::SlotDrop => "slot_drop",
            Glue::SlotCopy => "slot_copy",
        }
    }
}

use crate::builder::FuncBuilder;
use crate::ir::{FuncId, Imm, Mode, Module, Op, Param};
use crate::layout::Layouts;
use crate::types::{Ty, TyKind};
use std::collections::HashSet;

/// Makes the drop function of every type whose drop is a walk of its fields (a record or an
/// alternative that does not contain itself) and records it in [`Module::drop_glue`]. Backends
/// call these functions instead of writing a drop body of their own, so they cannot disagree on
/// which cases and fields a drop releases. Returns whether anything was made.
pub fn run(m: &mut Module) -> bool {
    let wanted = wanted_types(m);
    let lay_tys: Vec<Ty> = wanted
        .into_iter()
        .filter(|t| matches!(m.types.kind(*t), TyKind::Type(_) | TyKind::Alt(_)))
        .filter(|t| m.needs_drop(*t) && !m.drop_recurses(*t))
        .collect();
    let mut made = false;
    for ty in lay_tys {
        let id = make_drop(m, ty);
        m.drop_glue.insert(ty, id);
        made = true;
    }
    made
}

/// Every type a backend can be asked to drop: the type of any value, and what dropping those
/// types drops in turn.
fn wanted_types(m: &Module) -> Vec<Ty> {
    let mut seen: HashSet<Ty> = HashSet::new();
    let mut todo: Vec<Ty> = Vec::new();
    for f in &m.funcs {
        todo.extend(f.values.iter().copied());
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            if let Imm::Ty(t) = inst.imm {
                todo.push(t);
            }
        }
    }
    let mut out = Vec::new();
    while let Some(t) = todo.pop() {
        if !seen.insert(t.unscoped()) {
            continue;
        }
        out.push(t.unscoped());
        todo.extend(m.drop_children(t.unscoped()));
    }
    out
}

fn make_drop(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.drop", m.drop_glue.len());
    let lay_boxed = |m: &Module, a| Layouts::new(m).is_boxed(a);
    let params = vec![Param { ty, mode: Mode::Move }];
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
                .map(|(c, case)| {
                    !def.borrows(c) && case.fields.iter().any(|f| m.needs_drop(f.1))
                })
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
        _ => unreachable!("drop glue is made for records and alternatives"),
    }
}
