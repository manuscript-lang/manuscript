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
use crate::ir::{Cc, ExternDef, ExternRole, FuncId, Imm, Mode, Module, Op, Param};
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
        TyKind::Type(_) | TyKind::Alt(_) | TyKind::List(_) | TyKind::Bytes | TyKind::Iface(_) => {
            true
        }
        // A present flag and the payload's leaves, or a box; the other layouts are one pointer.
        TyKind::Opt(inner) => {
            (lay.opt_is_boxed(*inner) || !lay.opt_is_nullable(*inner)) && !lay.is_str_like(*t)
        }
        TyKind::Obj(n, _) => n.is_map_or_set(),
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
            TyKind::Bytes | TyKind::Iface(_) => false,
            _ => true,
        })
        .collect();
    let (slots, blocks) = addr_types(m, &lay);
    drop(lay);
    let (closure_drops, closure_clones) = closure_demand(m);
    // The same order every run.
    drop_tys.sort_by_key(|t| t.0);
    clone_tys.sort_by_key(|t| t.0);
    let made =
        !drop_tys.is_empty() || !clone_tys.is_empty() || !slots.is_empty() || !blocks.is_empty();
    for ty in drop_tys {
        let id = make_drop(m, ty);
        m.drop_glue.insert(ty, id);
    }
    for ty in clone_tys {
        let id = make_clone(m, ty);
        m.clone_glue.insert(ty, id);
    }
    for ty in slots {
        let id = make_slot_drop(m, ty);
        m.addr_glue.insert((Glue::SlotDrop, ty), id);
        let id = make_slot_copy(m, ty);
        m.addr_glue.insert((Glue::SlotCopy, ty), id);
    }
    for ty in blocks {
        let id = make_block_drop(m, ty);
        m.addr_glue.insert((Glue::BlockDrop, ty), id);
        let id = make_block_clone(m, ty);
        m.addr_glue.insert((Glue::BlockClone, ty), id);
    }
    let mut dropped: HashSet<u32> = HashSet::new();
    for (c, framed) in closure_drops {
        let kind = if framed {
            Glue::ClosureDropFramed(c.0)
        } else {
            Glue::ClosureDrop(c.0)
        };
        let id = make_closure_drop(m, c, framed);
        m.addr_glue.insert((kind, Ty::VOID), id);
        if !framed {
            dropped.insert(c.0);
        }
    }
    for c in closure_clones {
        if !dropped.contains(&c.0) {
            let id = make_closure_drop(m, c, false);
            m.addr_glue.insert((Glue::ClosureDrop(c.0), Ty::VOID), id);
        }
        let id = make_closure_clone(m, c);
        m.addr_glue.insert((Glue::ClosureClone(c.0), Ty::VOID), id);
    }
    made
}

/// The closure functions whose objects the program makes, with whether the object lives in a
/// stack frame (and so is not freed), and those whose objects get a clone entry.
fn closure_demand(m: &Module) -> (Vec<(FuncId, bool)>, Vec<FuncId>) {
    let mut drops: Vec<(FuncId, bool)> = Vec::new();
    let mut clones: Vec<FuncId> = Vec::new();
    for f in &m.funcs {
        let framed = crate::frames::framed_closure_objects(m, f);
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            if let (Op::ClosureNew, Imm::Func(c), Some(r)) = (inst.op, inst.imm, inst.res) {
                drops.push((c, framed.contains(&r.index())));
                clones.push(c);
            }
        }
    }
    drops.sort_by_key(|(c, framed)| (c.0, *framed));
    drops.dedup();
    clones.sort_by_key(|c| c.0);
    clones.dedup();
    (drops, clones)
}

fn ptr_at(b: &mut FuncBuilder, base: crate::ir::Value, off: i64) -> crate::ir::Value {
    if off == 0 {
        return base;
    }
    let n = b.iconst(off);
    b.emit(Op::PtrAdd, &[base, n], Imm::None, Some(Ty::PTR))
        .expect("address")
}

fn rt_extern(m: &mut Module, name: &str, params: &[Ty], ret: Ty, fresh: bool) -> crate::ir::ExtId {
    m.add_extern(ExternDef {
        name: name.into(),
        params: params
            .iter()
            .map(|&ty| Param {
                ty,
                mode: Mode::Borrow,
            })
            .collect(),
        ret,
        noreturn: false,
        pure_: false,
        fresh,
        leaf: false,
        reads: false,
        retains: false,
        role: ExternRole::None,
    })
}

/// The capture types of closure function `c` with their offsets in the object.
fn captures_of(m: &Module, c: FuncId) -> (Vec<(Ty, i64)>, i64) {
    let layout = Layouts::new(m).closure(&m.funcs[c.index()]);
    let caps = (layout.captures.iter())
        .map(|k| (k.ty, i64::from(k.offset)))
        .collect();
    (caps, i64::from(layout.size))
}

/// `fn(obj)` that drops the captures of a closure object and frees it (a framed object lives in
/// a stack slot and is not freed). A capture with a closer is closed in place first, with a
/// cleanup registered that releases the rest of the object if the close faults.
fn make_closure_drop(m: &mut Module, c: FuncId, framed: bool) -> FuncId {
    let (caps, _) = captures_of(m, c);
    let closers = m.funcs[c.index()].capture_closers.clone();
    let needs: Vec<bool> = caps.iter().map(|(t, _)| m.needs_drop(*t)).collect();
    let tails: Vec<Option<FuncId>> = (0..caps.len())
        .map(|k| {
            (closers.iter().any(|(i, _)| *i as usize == k)).then(|| make_closure_drop_from(m, c, k))
        })
        .collect();
    let discard = rt_extern(m, "msrt_cleanup_discard", &[Ty::INT], Ty::VOID, false);
    let name = format!("{GLUE_PREFIX}mir.{}.closure_drop", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
    let obj = b.params()[0];
    for (k, (ty, off)) in caps.iter().enumerate() {
        let at = ptr_at(&mut b, obj, *off);
        if let (Some((_, close)), Some(tail)) =
            (closers.iter().find(|(i, _)| *i as usize == k), tails[k])
        {
            let h = b
                .emit(Op::CleanupPush, &[obj], Imm::Func(tail), Some(Ty::INT))
                .expect("handle");
            b.emit(Op::Call, &[at], Imm::Func(*close), None);
            b.call_rt(discard, &[h]);
        }
        if needs[k] {
            let v = b
                .emit(Op::Take, &[at], Imm::Ty(*ty), Some(*ty))
                .expect("capture");
            b.emit(Op::Drop, &[v], Imm::None, None);
        }
    }
    if !framed {
        b.emit(Op::Free, &[obj], Imm::None, None);
    }
    b.ret(None);
    b.finish()
}

/// `fn(obj)` registered while the close of capture `k` of a closure runs: when a guarded task
/// unwinds out of it, it drops the later captures (the close owns capture `k`) and frees the
/// object. It does nothing otherwise.
fn make_closure_drop_from(m: &mut Module, c: FuncId, k: usize) -> FuncId {
    let (caps, _) = captures_of(m, c);
    let needs: Vec<bool> = caps.iter().map(|(t, _)| m.needs_drop(*t)).collect();
    let on_ext = rt_extern(m, "msrt_unwind_drops", &[], Ty::BOOL, false);
    let name = format!("{GLUE_PREFIX}mir.{}.closure_drop_from", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
    b.func_mut().unwind_only = true;
    let obj = b.params()[0];
    let (body, done) = (b.new_block(), b.new_block());
    let on = b.call_rt(on_ext, &[]);
    b.br_if(on, body, &[], done, &[]);
    b.switch_to(body);
    for (j, (ty, off)) in caps.iter().enumerate() {
        if j > k && needs[j] {
            let at = ptr_at(&mut b, obj, *off);
            let v = b
                .emit(Op::Take, &[at], Imm::Ty(*ty), Some(*ty))
                .expect("capture");
            b.emit(Op::Drop, &[v], Imm::None, None);
        }
    }
    b.emit(Op::Free, &[obj], Imm::None, None);
    b.br(done, &[]);
    b.switch_to(done);
    b.ret(None);
    let id = b.finish();
    m.addr_glue
        .insert((Glue::ClosureDropFrom(c.0, k as u32), Ty::VOID), id);
    id
}

/// `fn(obj) -> obj`: a new closure object with the same clone and code entries, the heap drop
/// entry, and a clone of every capture.
fn make_closure_clone(m: &mut Module, c: FuncId) -> FuncId {
    let (caps, size) = captures_of(m, c);
    let drop = m.addr_glue[&(Glue::ClosureDrop(c.0), Ty::VOID)];
    let alloc = rt_extern(m, "msrt_alloc", &[Ty::INT], Ty::PTR, true);
    let name = format!("{GLUE_PREFIX}mir.{}.closure_clone", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let mut b = FuncBuilder::new(m, &name, params, Ty::PTR);
    let src = b.params()[0];
    let copies: Vec<_> = caps
        .iter()
        .map(|(ty, off)| {
            let at = ptr_at(&mut b, src, *off);
            let v = b
                .emit(Op::Load, &[at], Imm::Ty(*ty), Some(*ty))
                .expect("capture");
            b.clone_value(v)
        })
        .collect();
    let n = b.iconst(size);
    let obj = b.call_rt(alloc, &[n]);
    // The clone and code entries carry over; the drop entry is the heap one even when `src` lives
    // in a frame.
    for at in [0, ms_rt_abi::CLOSURE_CODE_OFFSET as i64] {
        let from = ptr_at(&mut b, src, at);
        let word = b
            .emit(Op::Load, &[from], Imm::Ty(Ty::PTR), Some(Ty::PTR))
            .expect("word");
        let to = ptr_at(&mut b, obj, at);
        b.emit(Op::Put, &[to, word], Imm::None, None);
    }
    let da = b
        .emit(Op::FuncAddr, &[], Imm::Func(drop), Some(Ty::PTR))
        .expect("address");
    let to = ptr_at(&mut b, obj, 8);
    b.emit(Op::Put, &[to, da], Imm::None, None);
    for ((_, off), v) in caps.iter().zip(copies) {
        let to = ptr_at(&mut b, obj, *off);
        b.emit(Op::Put, &[to, v], Imm::None, None);
    }
    b.ret(Some(obj));
    b.finish()
}

/// The types whose descriptors point at slot drop and copy functions, and the data types of the
/// interface vtables (whose payload blocks get drop and clone functions).
fn addr_types(m: &Module, lay: &Layouts) -> (Vec<Ty>, Vec<Ty>) {
    let mut keys: Vec<Ty> = Vec::new();
    for f in &m.funcs {
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            if let (Op::TypeDesc, Imm::Ty(t)) = (inst.op, inst.imm) {
                keys.push(t);
            }
        }
    }
    let mut seen: HashSet<Ty> = HashSet::new();
    let mut slots: Vec<Ty> = Vec::new();
    while let Some(key) = keys.pop() {
        if !seen.insert(key) {
            continue;
        }
        let crate::statics::DescPlan::Table(t) = crate::statics::descriptor(m, lay, key) else {
            continue;
        };
        keys.extend(t.inner.into_iter().flatten());
        slots.extend(t.slot_glue);
    }
    let mut blocks: Vec<Ty> = m.vtables.iter().map(|v| v.data_ty.unscoped()).collect();
    for v in [&mut slots, &mut blocks] {
        v.sort_by_key(|t| t.0);
        v.dedup();
    }
    (slots, blocks)
}

/// `fn(slot)`: drops the value stored at `slot`.
fn make_slot_drop(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.slot_drop", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
    let p = b.params()[0];
    let v = b
        .emit(Op::Take, &[p], Imm::Ty(ty), Some(ty))
        .expect("value");
    b.emit(Op::Drop, &[v], Imm::None, None);
    b.ret(None);
    b.finish()
}

/// `fn(src, dst)`: clones the value at `src` into uninitialised `dst`.
fn make_slot_copy(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.slot_copy", m.funcs.len());
    let ptr = Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    };
    let mut b = FuncBuilder::new(m, &name, vec![ptr, ptr], Ty::VOID);
    let (src, dst) = (b.params()[0], b.params()[1]);
    let v = b
        .emit(Op::Load, &[src], Imm::Ty(ty), Some(ty))
        .expect("value");
    let c = b.clone_value(v);
    b.emit(Op::Put, &[dst, c], Imm::None, None);
    b.ret(None);
    b.finish()
}

/// `fn(block)`: drops the `ty` value the heap block holds and frees the block.
fn make_block_drop(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.block_drop", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let needs = m.needs_drop(ty);
    let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
    let p = b.params()[0];
    if needs {
        let v = b
            .emit(Op::Take, &[p], Imm::Ty(ty), Some(ty))
            .expect("value");
        b.emit(Op::Drop, &[v], Imm::None, None);
    }
    b.emit(Op::Free, &[p], Imm::None, None);
    b.ret(None);
    b.finish()
}

/// `fn(block) -> block`: a new heap block holding a clone of the `ty` value in `block`.
fn make_block_clone(m: &mut Module, ty: Ty) -> FuncId {
    let name = format!("{GLUE_PREFIX}mir.{}.block_clone", m.funcs.len());
    let params = vec![Param {
        ty: Ty::PTR,
        mode: Mode::Borrow,
    }];
    let size = i64::from(Layouts::new(m).mem(ty).size);
    let alloc = m.add_extern(ExternDef {
        name: "msrt_alloc".into(),
        params: vec![Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        }],
        ret: Ty::PTR,
        noreturn: false,
        pure_: false,
        fresh: true,
        leaf: false,
        reads: false,
        retains: false,
        role: ExternRole::None,
    });
    let mut b = FuncBuilder::new(m, &name, params, Ty::PTR);
    let p = b.params()[0];
    let v = b
        .emit(Op::Load, &[p], Imm::Ty(ty), Some(ty))
        .expect("value");
    let c = b.clone_value(v);
    let n = b.iconst(size.max(1));
    let blk = b.call_rt(alloc, &[n]);
    b.emit(Op::Put, &[blk, c], Imm::None, None);
    b.ret(Some(blk));
    b.finish()
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
        TyKind::Opt(inner) => {
            let boxed = Layouts::new(m).opt_is_boxed(inner);
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let (some, done) = (b.new_block(), b.new_block());
            let present = b.opt_is_some(p);
            b.br_if(present, some, &[], done, &[]);
            b.switch_to(some);
            // A boxed payload is moved out of its box, which is freed.
            let payload = if boxed { b.opt_unbox(p) } else { b.opt_get(p) };
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
        TyKind::Obj(..) => {
            // The runtime drops a map or set it finds in memory, through its descriptor.
            let drop = rt_extern(m, "msrt_slot_drop", &[Ty::PTR, Ty::PTR], Ty::VOID, false);
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let slot = b
                .emit(Op::Slot, &[], Imm::Ty(ty), Some(Ty::PTR))
                .expect("slot");
            b.emit(Op::Put, &[slot, p], Imm::None, None);
            let d = b
                .emit(Op::TypeDesc, &[], Imm::Ty(ty), Some(Ty::PTR))
                .expect("descriptor");
            b.call_rt(drop, &[d, slot]);
            b.ret(None);
            b.finish()
        }
        TyKind::Iface(_) => {
            // The vtable word's tag says what the value owns: 0 the box and its payload, 1 only
            // the box (`iface.borrow`), 2 nothing (`iface.view`).
            let mut b = FuncBuilder::new(m, &name, params, Ty::VOID);
            let p = b.params()[0];
            let (owned, rest, boxed, done) =
                (b.new_block(), b.new_block(), b.new_block(), b.new_block());
            let tag = b
                .emit(Op::IfaceTag, &[p], Imm::None, Some(Ty::INT))
                .expect("tag");
            let zero = b.iconst(0);
            let is_owned = b.icmp(Cc::Eq, tag, zero);
            b.br_if(is_owned, owned, &[], rest, &[]);
            b.switch_to(owned);
            b.emit(Op::IfaceDestroy, &[p], Imm::None, None);
            b.br(done, &[]);
            b.switch_to(rest);
            let one = b.iconst(1);
            let is_box = b.icmp(Cc::Eq, tag, one);
            b.br_if(is_box, boxed, &[], done, &[]);
            b.switch_to(boxed);
            let data = b
                .emit(Op::IfaceData, &[p], Imm::None, Some(Ty::PTR))
                .expect("data");
            b.emit(Op::Free, &[data], Imm::None, None);
            b.br(done, &[]);
            b.switch_to(done);
            b.ret(None);
            b.finish()
        }
        _ => unreachable!(
            "drop glue is made for records, alternatives, optionals, lists and interfaces"
        ),
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
        TyKind::Obj(..) => {
            let copy = rt_extern(
                m,
                "msrt_slot_copy",
                &[Ty::PTR, Ty::PTR, Ty::PTR],
                Ty::VOID,
                false,
            );
            let mut b = FuncBuilder::new(m, &name, params, ty);
            let p = b.params()[0];
            let src = b
                .emit(Op::Slot, &[], Imm::Ty(ty), Some(Ty::PTR))
                .expect("slot");
            b.emit(Op::Store, &[src, p], Imm::None, None);
            let dst = b
                .emit(Op::Slot, &[], Imm::Ty(ty), Some(Ty::PTR))
                .expect("slot");
            let d = b
                .emit(Op::TypeDesc, &[], Imm::Ty(ty), Some(Ty::PTR))
                .expect("descriptor");
            b.call_rt(copy, &[d, src, dst]);
            let out = b
                .emit(Op::Take, &[dst], Imm::Ty(ty), Some(ty))
                .expect("copy");
            b.ret(Some(out));
            b.finish()
        }
        _ => {
            unreachable!("clone glue is made for records, alternatives, optionals, lists and maps")
        }
    }
}
