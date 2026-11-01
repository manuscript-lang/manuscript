//! Closing resources: a binding's `close` runs on every way out of its scope, and the parts a
//! holder owns close with it.

use crate::Error;
use crate::func::FnLower;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, FuncKind, Imm, Linkage, Mode, Op, Param, Value};
use ms_mir::types::{AltId, IfaceId, RecId, Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// How a binding is closed.
#[derive(Clone)]
pub(crate) enum CloseKind {
    /// An interface value: the vtable entry.
    Iface(IfaceId, u32),
    /// A source instance, which may hand `self` back through a slot.
    Func { fid: FuncId, writes_back: bool },
}

/// A field to close: its index, MIR type and close.
type Part = (u32, MTy, CloseKind);

/// What a record, alternative or collection holds that needs closing.
enum Shape {
    /// Record fields: index, type, close; last declared first.
    Rec(RecId, Vec<Part>),
    /// The fields to close in each case that has any.
    Alt(AltId, Vec<(u32, Vec<Part>)>),
    /// The payload of an `Optional`.
    Opt(MTy, CloseKind),
    /// The elements of a list, last first.
    List(MTy, CloseKind),
}

/// Closes the parts `shape` names in `v`.
fn emit_parts(b: &mut FuncBuilder<'_>, v: Value, shape: Shape) {
    match shape {
        Shape::Rec(r, parts) => {
            for (i, ft, k) in parts {
                let f = b.rec_get(r, i, v);
                close_call(b, &k, f, ft);
            }
        }
        Shape::Alt(a, cases) => {
            let tag = b.alt_tag(v);
            let exit = b.new_block();
            let blocks: Vec<_> = cases.iter().map(|_| b.new_block()).collect();
            let arms: Vec<(i64, _)> = cases
                .iter()
                .zip(&blocks)
                .map(|((c, _), blk)| (*c as i64, *blk))
                .collect();
            b.switch(tag, &arms, exit);
            for ((c, parts), blk) in cases.into_iter().zip(blocks) {
                b.seal_block(blk);
                b.switch_to(blk);
                for (j, ft, k) in parts {
                    let f = b.alt_get(a, c, j, v);
                    close_call(b, &k, f, ft);
                }
                b.br(exit, &[]);
            }
            b.seal_block(exit);
            b.switch_to(exit);
        }
        Shape::Opt(inner, k) => {
            let some = b.opt_is_some(v);
            let (yes, exit) = (b.new_block(), b.new_block());
            b.br_if(some, yes, &[], exit, &[]);
            b.seal_block(yes);
            b.switch_to(yes);
            let x = b.opt_get(v);
            close_call(b, &k, x, inner);
            b.br(exit, &[]);
            b.seal_block(exit);
            b.switch_to(exit);
        }
        Shape::List(elem, k) => {
            let n = b.list_len(v);
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            b.def_var(idx, n);
            let (header, body, exit) = (b.new_block(), b.new_block(), b.new_block());
            b.br(header, &[]);
            b.switch_to(header);
            let i = b.use_var(idx);
            let zero = b.iconst(0);
            let more = b.icmp(Cc::Gt, i, zero);
            b.br_if(more, body, &[], exit, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let j = b.binop(Op::ISub, i, one);
            b.def_var(idx, j);
            let e = b.list_get(v, j);
            close_call(b, &k, e, elem);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(exit);
            b.switch_to(exit);
        }
    }
}

/// A closing binding's close operation and its entry on the runtime cleanup stack, which a fault
/// runs.
#[derive(Clone)]
pub(crate) struct Closer {
    kind: CloseKind,
    handle: ms_mir::ir::Value,
    /// Set while the binding still holds the resource; a move clears it. Present only for a
    /// binding some path moves.
    flag: Option<ms_mir::builder::Var>,
    /// The current cleanup entry of a binding that can be reassigned after a move, which pushes
    /// a new one.
    entry: Option<ms_mir::builder::Var>,
    /// Set once the program calls `close()` on the binding itself: the scope end still closes
    /// it, which releases what the call left, but a result the program handled is dropped
    /// instead of returned again. Present only for a binding with such a call.
    explicit: Option<ms_mir::builder::Var>,
    /// A binding some path moves a resource field out of closes field by field.
    pub(crate) split: Option<std::rc::Rc<Split>>,
}

/// The resource fields of a binding that has parts moved out: each closes on its own cleanup
/// entry, so a move takes exactly that part out of the binding's duty.
pub(crate) struct Split {
    /// Every resource field, in declaration order (the scope closes them last first).
    items: Vec<SplitItem>,
    /// The moved places: field indexes from the root, and the flag set while the binding
    /// still holds the place.
    moved: Vec<(Vec<u32>, Vec<ct::Name>, ms_mir::builder::Var)>,
}

struct SplitItem {
    path: Vec<u32>,
    ty: MTy,
    kind: CloseKind,
    handle: Value,
    flag: Option<ms_mir::builder::Var>,
}

/// Calls the close operation on `v` of type `ty`. A close that fails here has nowhere to return
/// its error (a part of a holder, a temporary, a replaced value), so it faults; only the scope-end
/// close of a binding propagates it, through [`close_call_result`].
fn close_call(b: &mut FuncBuilder<'_>, kind: &CloseKind, v: Value, ty: MTy) {
    let r = close_call_result(b, kind, v, ty);
    close_error_fault(b, r);
}

/// Calls the close operation and drops its result: for the cleanup stack a fault runs, where the
/// failure is already being reported.
fn close_call_silent(b: &mut FuncBuilder<'_>, kind: &CloseKind, v: Value, ty: MTy) {
    let r = close_call_result(b, kind, v, ty);
    if b.m.needs_drop(b.ty(r)) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
}

/// Faults when `r`, the `Result` of a close, is an error; otherwise releases it.
fn close_error_fault(b: &mut FuncBuilder<'_>, r: Value) {
    let rty = b.ty(r);
    let TyKind::Alt(a) = b.m.types.kind(rty).clone() else {
        return;
    };
    let Some(err) = b.m.alts[a.index()]
        .cases
        .iter()
        .position(|c| c.name == "error")
    else {
        return;
    };
    let tag = b.alt_tag(r);
    let k = b.iconst(err as i64);
    let is_err = b.icmp(Cc::Eq, tag, k);
    let (bad, good) = (b.new_block(), b.new_block());
    b.br_if(is_err, bad, &[], good, &[]);
    b.seal_block(bad);
    b.seal_block(good);
    b.switch_to(bad);
    let msg = b.str_lit("a resource could not be closed: its close returned an error");
    let ext = crate::text::runtime_fn(b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
    b.call_rt(ext, &[msg]);
    b.unreachable();
    b.switch_to(good);
    if b.m.needs_drop(rty) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
}

/// Calls the close operation on `v` of type `ty`; the result is `Unit`, or the `Result` of a
/// close that can fail, which the caller owns.
fn close_call_result(b: &mut FuncBuilder<'_>, kind: &CloseKind, v: Value, ty: MTy) -> Value {
    match kind {
        CloseKind::Iface(iface, k) => b.call_method(*iface, *k, v, &[]),
        CloseKind::Func {
            fid,
            writes_back: false,
        } => b.call(*fid, &[v]),
        CloseKind::Func {
            fid,
            writes_back: true,
        } => {
            // The method changes `self`; the value being closed is a copy.
            let droppable = b.m.needs_drop(ty);
            let own = if droppable {
                b.emit(Op::Copy, &[v], Imm::None, Some(ty)).expect("copy")
            } else {
                v
            };
            let slot = b
                .emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
                .expect("slot");
            b.emit(
                if droppable { Op::Put } else { Op::Store },
                &[slot, own],
                Imm::None,
                None,
            );
            let r = b.call(*fid, &[slot]);
            let take = if droppable { Op::Take } else { Op::Load };
            let after = b.emit(take, &[slot], Imm::Ty(ty), Some(ty)).expect("take");
            if droppable {
                b.emit(Op::Drop, &[after], Imm::None, None);
            }
            r
        }
    }
}

impl FnLower<'_> {
    /// Closes an owned temporary that is a resource (`open().id()`) before it is dropped at the
    /// end of its statement.
    pub(crate) fn close_temp(&mut self, v: Value) {
        let mt = self.b.ty(v);
        let Some(ty) = self.cx.source_tys.get(&mt).cloned() else {
            return;
        };
        // A resource, or a record or list holding one (only read in place: the checker rejects
        // moving a resource part out of a computed value). A wrapper (`Result`, `Optional`) may
        // have had its payload moved out already, so it closes only when it is itself one.
        if self.cx.classes.class(&ty) != ms_check::ownership::Class::Resource
            || (self.closeable_impl(&ty).is_none()
                && (ty.is_std("Optional") || ty.is_std("Result")))
        {
            return;
        }
        let Ok(Some(kind)) = self.part_closer(&ty) else {
            return;
        };
        close_call(&mut self.b, &kind, v, mt);
    }

    /// Calls the close operation `kind` on `v` of MIR type `ty`.
    pub(crate) fn close_with(&mut self, kind: &CloseKind, v: Value, ty: MTy) {
        close_call(&mut self.b, kind, v, ty);
    }

    /// Closes `x` when it is an owned temporary of a resource type that nothing takes.
    pub(crate) fn close_owned_temp(&mut self, x: crate::func::Val) {
        if !x.own || self.dead {
            return;
        }
        let mt = self.b.ty(x.v);
        let Some(ty) = self.cx.source_tys.get(&mt).cloned() else {
            return;
        };
        if let Ok(Some(kind)) = self.part_closer(&ty) {
            self.close_discarded_kind(&kind, x.v);
        }
    }

    /// Closes a discarded statement result, which nothing took from: unlike a pending temporary
    /// it may be a wrapper (`xs.pop()` is an `Optional`).
    pub(crate) fn close_unused(&mut self, v: Value, ty: &ct::Ty) {
        let mt = self.b.ty(v);
        let Ok(Some(kind)) = self.part_closer(ty) else {
            return;
        };
        close_call(&mut self.b, &kind, v, mt);
    }

    /// Binds `binding` to `x` and registers its close operation: a fault runs it through the
    /// runtime's cleanup stack, and leaving the binding's scope closes the current value.
    pub(crate) fn bind_closing(
        &mut self,
        binding: &ct::BindingRef,
        x: crate::func::Val,
        cleanup: Option<&ct::MethodRef>,
    ) -> Result<(), Error> {
        let Some(kind) = self.closer_opt(cleanup, &binding.ty)? else {
            self.bind_local(binding, x);
            return Ok(());
        };
        self.bind_closing_kind(binding, x, kind)
    }

    /// [`Self::bind_closing`] with the close operation already chosen.
    pub(crate) fn bind_closing_kind(
        &mut self,
        binding: &ct::BindingRef,
        x: crate::func::Val,
        kind: CloseKind,
    ) -> Result<(), Error> {
        // A `var` binding that changes lives in memory, so a fault or cancellation closes its
        // value at that moment and not the one it started with.
        if binding.mutable {
            self.slotted.insert(binding.uid);
        }
        self.redefined.insert(binding.uid);
        self.bind_local(binding, x);
        let ty = self.locals[&binding.uid].ty;
        let slot = self.locals[&binding.uid].slot;
        if let Some(places) = self.cx.resource_moves.get(&binding.uid).cloned()
            && !places.is_empty()
            && slot.is_none()
        {
            return self.bind_split(binding, kind, places);
        }
        let thunk = self.close_thunk(&kind, ty, slot.is_some());
        let registered = match slot {
            Some(ptr) => ptr,
            None => self.read_local(binding)?.v,
        };
        let handle = self
            .b
            .emit(
                Op::CleanupPush,
                &[registered],
                Imm::Func(thunk),
                Some(MTy::INT),
            )
            .expect("handle");
        let flag = self.cx.close_moves.contains_key(&binding.uid).then(|| {
            let flag = self.b.declare_var(MTy::BOOL, Mode::Borrow);
            let held = self.b.bconst(true);
            self.b.def_var(flag, held);
            flag
        });
        let explicit = self.cx.explicit_closes.contains(&binding.uid).then(|| {
            let explicit = self.b.declare_var(MTy::BOOL, Mode::Borrow);
            let no = self.b.bconst(false);
            self.b.def_var(explicit, no);
            explicit
        });
        let entry = (flag.is_some() && binding.mutable).then(|| {
            let entry = self.b.declare_var(MTy::INT, Mode::Borrow);
            self.b.def_var(entry, handle);
            entry
        });
        self.closers.insert(
            binding.uid,
            Closer {
                kind,
                handle,
                flag,
                entry,
                explicit,
                split: None,
            },
        );
        // A binding that needs no drop is not registered by `bind_local`; closing still runs.
        let scope = self.scopes.last_mut().expect("scope");
        if !scope.contains(&binding.uid) {
            scope.push(binding.uid);
        }
        Ok(())
    }

    /// Registers the cleanup entries of a binding with moved resource fields, one per resource
    /// field, so that moving a field out discards exactly its entry.
    fn bind_split(
        &mut self,
        binding: &ct::BindingRef,
        kind: CloseKind,
        places: std::collections::HashMap<ms_syntax::ast::NodeId, Vec<ct::Name>>,
    ) -> Result<(), Error> {
        let root = self.read_local(binding)?.v;
        let ty = ct::sub(&binding.ty, &self.subst);
        let mut tails: Vec<Vec<ct::Name>> = places.into_values().collect();
        tails.sort_by_key(|t| t.iter().map(|n| n.as_str().to_string()).collect::<Vec<_>>());
        tails.dedup();
        let mut split = Split {
            items: Vec::new(),
            moved: Vec::new(),
        };
        self.split_fields(&ty, root, &[], &[], &tails, &mut split)?;
        let flag = self.cx.close_moves.contains_key(&binding.uid).then(|| {
            let flag = self.b.declare_var(MTy::BOOL, Mode::Borrow);
            let held = self.b.bconst(true);
            self.b.def_var(flag, held);
            flag
        });
        let handle = self.b.iconst(0);
        self.closers.insert(
            binding.uid,
            Closer {
                kind,
                handle,
                flag,
                entry: None,
                explicit: None,
                split: Some(std::rc::Rc::new(split)),
            },
        );
        self.redefined.insert(binding.uid);
        let scope = self.scopes.last_mut().expect("scope");
        if !scope.contains(&binding.uid) {
            scope.push(binding.uid);
        }
        Ok(())
    }

    /// The entries for the resource fields of the record `v` of checked type `ty`, reached by
    /// `prefix` from the binding; `tails` are the moved places below it, by name.
    fn split_fields(
        &mut self,
        ty: &ct::Ty,
        v: Value,
        prefix: &[u32],
        names: &[ct::Name],
        tails: &[Vec<ct::Name>],
        split: &mut Split,
    ) -> Result<(), Error> {
        let TyKind::Rec(r) = self.b.m.types.kind(self.ty_of(v)).clone() else {
            return Err(Error::new("a moved field of a non-record"));
        };
        for (i, f) in ct::fields(ty).iter().enumerate() {
            if self.cx.classes.class(&f.ty) != ms_check::ownership::Class::Resource {
                continue;
            }
            let fv = self.b.rec_get(r, i as u32, v);
            let mut path = prefix.to_vec();
            path.push(i as u32);
            let mut here = names.to_vec();
            here.push(f.name);
            let below: Vec<Vec<_>> = tails
                .iter()
                .filter(|t| t.starts_with(&here))
                .cloned()
                .collect();
            let moved = below.iter().any(|t| t.len() == here.len());
            if !below.is_empty() && !moved {
                self.split_fields(&f.ty, fv, &path, &here, tails, split)?;
                continue;
            }
            let Some(kind) = self.part_closer(&f.ty)? else {
                return Err(Error::new("a moved resource without a close operation"));
            };
            let fty = self.ty_of(fv);
            let thunk = self.close_thunk(&kind, fty, false);
            let handle = self
                .b
                .emit(Op::CleanupPush, &[fv], Imm::Func(thunk), Some(MTy::INT))
                .expect("handle");
            let flag = moved.then(|| {
                let flag = self.b.declare_var(MTy::BOOL, Mode::Borrow);
                let held = self.b.bconst(true);
                self.b.def_var(flag, held);
                split.moved.push((path.clone(), here.clone(), flag));
                flag
            });
            split.items.push(SplitItem {
                path,
                ty: fty,
                kind,
                handle,
                flag,
            });
        }
        Ok(())
    }

    /// The field of the record `root` at `path`.
    fn field_at(&mut self, root: Value, path: &[u32]) -> Value {
        let mut v = root;
        for &i in path {
            let TyKind::Rec(r) = self.b.m.types.kind(self.ty_of(v)).clone() else {
                unreachable!("a split path runs through records")
            };
            v = self.b.rec_get(r, i, v);
        }
        v
    }

    /// A move of the resource field `names` out of the binding `uid` at the member `e`: the
    /// new owner closes it, so the binding's entry for it goes away and the scope end skips it.
    pub(crate) fn moved_field(
        &mut self,
        uid: usize,
        names: &[ct::Name],
        field: Value,
    ) -> Result<Value, Error> {
        let split = self
            .closers
            .get(&uid)
            .and_then(|c| c.split.clone())
            .ok_or_else(|| Error::new("a resource field moves out of a binding with no closer"))?;
        let (path, _, flag) = split
            .moved
            .iter()
            .find(|(_, n, _)| n.as_slice() == names)
            .ok_or_else(|| Error::new("a moved field the binding does not track"))?;
        let item = split
            .items
            .iter()
            .find(|i| i.path == *path)
            .expect("an entry for a moved field");
        // The entries of later fields stay: only this one stops closing.
        let _ = self.call_runtime("msrt_cleanup_cancel", &[item.handle], MTy::UNIT);
        let gone = self.b.bconst(false);
        self.b.def_var(*flag, gone);
        Ok(self.b.move_out(field))
    }

    /// Leaves a split binding: every field's cleanup entry goes, and each field that the
    /// binding still holds closes, last declared first.
    fn close_split(&mut self, uid: usize, split: &Split, whole: Option<ms_mir::builder::Var>) {
        let l = self.locals[&uid];
        let root = self.local_get(&l);
        for item in split.items.iter().rev() {
            let _ = self.call_runtime("msrt_cleanup_discard", &[item.handle], MTy::UNIT);
            let join = self.b.new_block();
            for flag in whole.into_iter().chain(item.flag) {
                let next = self.b.new_block();
                let held = self.b.use_var(flag);
                self.b.br_if(held, next, &[], join, &[]);
                self.b.seal_block(next);
                self.b.switch_to(next);
            }
            let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
            let v = self.field_at(root, &item.path);
            close_call(&mut self.b, &item.kind, v, item.ty);
            let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
            self.b.br(join, &[]);
            self.b.seal_block(join);
            self.b.switch_to(join);
        }
    }

    /// Drops the local `uid` of a split binding without the places that were moved out.
    pub(crate) fn release_split(&mut self, uid: usize) {
        let Some(split) = self.closers.get(&uid).and_then(|c| c.split.clone()) else {
            return;
        };
        let l = self.locals[&uid];
        let v = self.local_take(&l);
        self.release_leaves(v, &[], &split.moved);
        // Every part is dropped or moved; this only consumes the record.
        let TyKind::Rec(r) = self.b.m.types.kind(l.ty).clone() else {
            return;
        };
        let n = self.b.m.records[r.index()].fields.len();
        let mask = if n >= 32 { u32::MAX } else { (1u32 << n) - 1 };
        self.b
            .emit(Op::RecRelease, &[v], Imm::RecMask(r, mask), None);
    }

    /// Drops the parts of the record `v` (reached by `prefix`) that were not moved out.
    fn release_leaves(
        &mut self,
        v: Value,
        prefix: &[u32],
        moved: &[(Vec<u32>, Vec<ct::Name>, ms_mir::builder::Var)],
    ) {
        let TyKind::Rec(r) = self.b.m.types.kind(self.ty_of(v)).clone() else {
            return;
        };
        let fields: Vec<MTy> = self.b.m.records[r.index()]
            .fields
            .iter()
            .map(|f| f.1)
            .collect();
        for (i, fty) in fields.into_iter().enumerate() {
            if !self.b.m.needs_drop(fty) {
                continue;
            }
            let mut path = prefix.to_vec();
            path.push(i as u32);
            let here = moved.iter().find(|(p, _, _)| *p == path).map(|m| m.2);
            let deeper = moved
                .iter()
                .any(|(p, _, _)| p.len() > path.len() && p.starts_with(&path));
            let (run, join) = (self.b.new_block(), self.b.new_block());
            match here {
                Some(flag) => {
                    let held = self.b.use_var(flag);
                    self.b.br_if(held, run, &[], join, &[]);
                }
                None => self.b.br(run, &[]),
            }
            self.b.seal_block(run);
            self.b.switch_to(run);
            let f = self.b.rec_get(r, i as u32, v);
            if deeper {
                self.release_leaves(f, &path, moved);
            } else {
                let o = self.b.move_out(f);
                self.b.emit(Op::Drop, &[o], Imm::None, None);
            }
            self.b.br(join, &[]);
            self.b.seal_block(join);
            self.b.switch_to(join);
        }
    }

    /// How a binding of `ty` is closed: its own close operation, if it has one, and then the
    /// resources it holds; `None` when this module sees no close operation for the type (its
    /// `Closeable` implementation is local to another file).
    pub(crate) fn closer_opt(
        &mut self,
        cleanup: Option<&ct::MethodRef>,
        ty: &ct::Ty,
    ) -> Result<Option<CloseKind>, Error> {
        let ty = ct::sub(ty, &self.subst);
        let mt = self.mty(&ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            return self
                .iface_closer(iface)
                .map(Some)
                .ok_or_else(|| Error::new("interface without close"));
        }
        let own = match cleanup {
            Some(c) => Some(self.own_closer(c, &ty)?),
            None => None,
        };
        self.close_with_parts(&ty, own)
    }

    /// The `close` entry of an interface value's vtable, if the interface declares one.
    fn iface_closer(&self, iface: IfaceId) -> Option<CloseKind> {
        let k = self.b.m.ifaces[iface.index()]
            .methods
            .iter()
            .position(|m| m.name == "close")?;
        Some(CloseKind::Iface(iface, k as u32))
    }

    /// The close operation `cleanup` names for the concrete receiver `ty`.
    fn own_closer(&mut self, cleanup: &ct::MethodRef, ty: &ct::Ty) -> Result<CloseKind, Error> {
        let im = if cleanup.native.as_str() == "contract" {
            self.contract_impl(cleanup, ty)
                .ok_or_else(|| Error::new(format!("{ty} has no close operation")))?
        } else {
            cleanup.clone()
        };
        if !im.native.is_empty() {
            return Err(Error::new(format!(
                "unsupported native close {}",
                im.native
            )));
        }
        let decl = im
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("close without declaration"))?;
        let c = self.callable_of_decl(im.module, Some(decl.id()))?;
        // The checked reference fixes an implementation's variables; its declaration keeps them.
        let declared = self
            .cx
            .methods
            .iter()
            .find(|d| d.module == im.module && d.decl.as_ref().map(|x| x.id()) == Some(decl.id()))
            .unwrap_or(&im);
        let mut subst = ct::Subst::new();
        if !ct::unify(
            &declared.receiver,
            ty,
            &ct::variable_set(&declared.variables),
            &mut subst,
        ) {
            return Err(Error::new("cannot bind close receiver type"));
        }
        let fid = self.instance(&c, &subst)?;
        let writes_back = self.cx.var_positions(&c).contains(&0);
        Ok(CloseKind::Func { fid, writes_back })
    }

    /// The method `name` the standard library implements for the collection `ty`.
    fn collection_method(&mut self, name: &str, ty: &ct::Ty) -> Result<CloseKind, Error> {
        let found = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.name().is_some_and(|n| n.as_str() == name)
                    && m.decl.is_some()
                    && ct::unify(
                        &m.receiver,
                        ty,
                        &ct::variable_set(&m.variables),
                        &mut ct::Subst::new(),
                    )
            })
            .cloned()
            .ok_or_else(|| Error::new(format!("{ty} has no {name}")))?;
        self.own_closer(&found, ty)
    }

    /// The `Closeable` implementation of a concrete type, if it has one.
    fn closeable_impl(&self, ty: &ct::Ty) -> Option<ct::MethodRef> {
        self.cx
            .methods
            .iter()
            .find(|m| {
                m.name().is_some_and(|n| n.as_str() == "close")
                    && m.contract.as_ref().is_some_and(|c| c.is_std("Closeable"))
                    && ct::unify(
                        &m.receiver,
                        ty,
                        &ct::variable_set(&m.variables),
                        &mut ct::Subst::new(),
                    )
            })
            .cloned()
    }

    /// The close of a resource held inside another: its own `close`, then what it holds in turn.
    /// `None` for a value that is not a resource.
    pub(crate) fn part_closer(&mut self, ty: &ct::Ty) -> Result<Option<CloseKind>, Error> {
        if self.cx.classes.class(ty) != ms_check::ownership::Class::Resource {
            return Ok(None);
        }
        let mt = self.mty(ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            return Ok(self.iface_closer(iface));
        }
        let own = match self.closeable_impl(ty) {
            Some(m) => Some(self.own_closer(&m, ty)?),
            None => None,
        };
        match self.close_with_parts(ty, own)? {
            Some(k) => Ok(Some(k)),
            None => Err(Error::new(format!(
                "{ty} holds a resource with no close operation"
            ))),
        }
    }

    /// `own`, followed by the close of every resource `ty` holds, last declared first: the
    /// close of a record, alternative, `Optional`, `List` or `Map` is generated from its parts.
    fn close_with_parts(
        &mut self,
        ty: &ct::Ty,
        own: Option<CloseKind>,
    ) -> Result<Option<CloseKind>, Error> {
        let mt = self.mty(ty)?;
        let shape = match self.b.m.types.kind(mt).clone() {
            TyKind::Rec(r) => {
                let held = ct::fields(ty);
                let mut parts = Vec::new();
                for (i, f) in held.iter().enumerate().rev() {
                    let ft = self.b.m.records[r.index()].fields[i].1;
                    if let Some(k) = self.part_closer(&f.ty)? {
                        parts.push((i as u32, ft, k));
                    }
                }
                (!parts.is_empty()).then_some(Shape::Rec(r, parts))
            }
            TyKind::Alt(a) => {
                let s = ct::substitution(ty);
                let mut cases = Vec::new();
                if let Some(def) = &ty.def {
                    let defs: Vec<_> = def.cases.borrow().iter().cloned().collect();
                    for (c, case) in defs.iter().enumerate() {
                        let mut parts = Vec::new();
                        for (j, f) in case.fields.iter().enumerate().rev() {
                            let ft = self.b.m.alts[a.index()].cases[c].fields[j].1;
                            if let Some(k) = self.part_closer(&ct::sub(&f.ty, &s))? {
                                parts.push((j as u32, ft, k));
                            }
                        }
                        if !parts.is_empty() {
                            cases.push((c as u32, parts));
                        }
                    }
                }
                (!cases.is_empty()).then_some(Shape::Alt(a, cases))
            }
            TyKind::Opt(inner) => match ty.args.first() {
                Some(arg) => self.part_closer(arg)?.map(|k| Shape::Opt(inner, k)),
                None => None,
            },
            TyKind::List(elem) => match ty.args.first() {
                Some(arg) => self.part_closer(arg)?.map(|k| Shape::List(elem, k)),
                None => None,
            },
            _ if ty.is_std("Map") => {
                let holds = ty.args.get(1).map(|v| self.part_closer(v)).transpose()?;
                match holds.flatten() {
                    Some(_) => return Ok(Some(self.collection_method("close_values", ty)?)),
                    None => None,
                }
            }
            _ => None,
        };
        let Some(shape) = shape else {
            return Ok(own);
        };
        let key = format!("close_parts:{ty}:{}", own.is_some());
        if let Some(f) = self.cx.helpers.get(&key) {
            return Ok(Some(CloseKind::Func {
                fid: *f,
                writes_back: false,
            }));
        }
        let ps = vec![Param {
            ty: mt,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close_parts", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let v = b.params()[0];
        if let Some(o) = &own {
            close_call(&mut b, o, v, mt);
        }
        emit_parts(&mut b, v, shape);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let fid = self.b.m.add_func(f);
        self.cx.helpers.insert(key, fid);
        Ok(Some(CloseKind::Func {
            fid,
            writes_back: false,
        }))
    }

    /// Makes the last holder's drop of a `Shared` over `held` close the payload, unless a
    /// `lock` guard has taken it out (the guard puts it back and the box is closed then).
    pub(crate) fn register_shared_close(
        &mut self,
        held: &ct::Ty,
        handle: MTy,
    ) -> Result<(), Error> {
        let Some(kind) = self.part_closer(held)? else {
            return Ok(());
        };
        let rec = self.builder_rec(handle)?;
        let state = self.b.m.types.rec(rec);
        if self.b.m.shared_close.iter().any(|(t, _)| *t == state) {
            return Ok(());
        }
        let value_ty = self.b.m.records[rec.index()].fields[0].1;
        let shield = |m: &mut ms_mir::ir::Module, name: &str| {
            m.add_extern(ms_mir::ir::ExternDef {
                name: name.to_string(),
                params: Vec::new(),
                ret: MTy::UNIT,
                noreturn: false,
                pure_: false,
                fresh: false,
            })
        };
        let (enter, exit) = (
            shield(self.b.m, "msrt_shield_enter"),
            shield(self.b.m, "msrt_shield_exit"),
        );
        let ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close_shared", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let p = b.params()[0];
        let s = b
            .emit(Op::Load, &[p], Imm::Ty(state), Some(state))
            .expect("load");
        let taken = b.rec_get(rec, 1, s);
        let (open, exit_blk) = (b.new_block(), b.new_block());
        b.br_if(taken, exit_blk, &[], open, &[]);
        b.seal_block(open);
        b.switch_to(open);
        b.call_rt(enter, &[]);
        let v = b.rec_get(rec, 0, s);
        close_call(&mut b, &kind, v, value_ty);
        b.call_rt(exit, &[]);
        b.br(exit_blk, &[]);
        b.seal_block(exit_blk);
        b.switch_to(exit_blk);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let fid = self.b.m.add_func(f);
        self.b.m.shared_close.push((state, fid));
        Ok(())
    }

    /// The function the cleanup stack calls with the registered value.
    pub(crate) fn close_thunk(&mut self, kind: &CloseKind, ty: MTy, in_slot: bool) -> FuncId {
        let key = match kind {
            CloseKind::Iface(i, k) => format!("close:iface{}:{k}:{in_slot}", i.0),
            CloseKind::Func { fid, writes_back } => {
                format!("close:{}:{writes_back}:{in_slot}", fid.index())
            }
        };
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        // A slot-held binding registers the address of its storage; the close reads it then.
        let ps = vec![Param {
            ty: if in_slot { MTy::PTR } else { ty },
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let mut v = b.params()[0];
        if in_slot {
            v = b.emit(Op::Load, &[v], Imm::Ty(ty), Some(ty)).expect("load");
        }
        close_call_silent(&mut b, kind, v, ty);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// Closes `old`, the value a reassignment replaces, shielded like any other close. The
    /// binding's cleanup entry stays: it closes whatever the binding holds when its scope ends.
    pub(crate) fn close_replaced(&mut self, closer: &Closer, old: Value, ty: MTy) {
        let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
        if let Some(explicit) = closer.explicit {
            // The program already closed `old` and handled the result: closing it again
            // releases what is left, and its result is dropped.
            let called = self.b.use_var(explicit);
            let (again, first, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
            self.b.br_if(called, again, &[], first, &[]);
            self.b.seal_block(again);
            self.b.seal_block(first);
            self.b.switch_to(again);
            close_call_silent(&mut self.b, &closer.kind, old, ty);
            self.b.br(join, &[]);
            self.b.switch_to(first);
            close_call(&mut self.b, &closer.kind, old, ty);
            self.b.br(join, &[]);
            self.b.seal_block(join);
            self.b.switch_to(join);
        } else {
            close_call(&mut self.b, &closer.kind, old, ty);
        }
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }

    /// The cleanup entry the binding's scope end discards.
    fn entry_of(&mut self, closer: &Closer) -> Value {
        match closer.entry {
            Some(v) => self.b.use_var(v),
            None => closer.handle,
        }
    }

    /// Stores `new` over the closing binding `uid`, whose value is `old`: the old value is
    /// closed when the binding still holds one, and a binding a move emptied registers a new
    /// cleanup entry for `new`.
    pub(crate) fn assign_closing(
        &mut self,
        uid: usize,
        closer: &Closer,
        old: Value,
        ty: MTy,
    ) -> Result<(), Error> {
        self.replace_closing(uid, closer, old, ty)?;
        // The new value has not been closed by the program.
        if let Some(explicit) = closer.explicit {
            let no = self.b.bconst(false);
            self.b.def_var(explicit, no);
        }
        Ok(())
    }

    fn replace_closing(
        &mut self,
        uid: usize,
        closer: &Closer,
        old: Value,
        ty: MTy,
    ) -> Result<(), Error> {
        let Some(flag) = closer.flag else {
            self.close_replaced(closer, old, ty);
            return Ok(());
        };
        let held = self.b.use_var(flag);
        let (close, empty, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(held, close, &[], empty, &[]);
        self.b.seal_block(close);
        self.b.seal_block(empty);
        self.b.switch_to(close);
        self.close_replaced(closer, old, ty);
        self.b.br(join, &[]);
        self.b.switch_to(empty);
        if let (Some(entry), Some(ptr)) = (closer.entry, self.locals[&uid].slot) {
            let thunk = self.close_thunk(&closer.kind, ty, true);
            let handle = self
                .b
                .emit(Op::CleanupPush, &[ptr], Imm::Func(thunk), Some(MTy::INT))
                .expect("handle");
            self.b.def_var(entry, handle);
        }
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
        let held = self.b.bconst(true);
        self.b.def_var(flag, held);
        Ok(())
    }

    /// The function that closes a value of the closing binding `uid` held by a closure built at
    /// `e`, when `e` moves the binding into its environment.
    pub(crate) fn capture_closer(&mut self, uid: usize, e: &Expr, ty: MTy) -> Option<FuncId> {
        let closer = self.closers.get(&uid).cloned()?;
        closer.flag?;
        let moves = self.cx.close_moves.get(&uid)?;
        if self.dead || !moves.contains(&e.id) {
            return None;
        }
        Some(self.close_thunk(&closer.kind, ty, false))
    }

    /// A move of the closing binding `uid` at the name expression `e`: the new owner closes the
    /// value, so neither the cleanup entry nor the scope end does.
    pub(crate) fn moved_closer(&mut self, uid: usize, e: &Expr) {
        let Some(closer) = self.closers.get(&uid).cloned() else {
            return;
        };
        let Some(flag) = closer.flag else {
            return;
        };
        if self.dead
            || !self
                .cx
                .close_moves
                .get(&uid)
                .is_some_and(|n| n.contains(&e.id))
        {
            return;
        }
        if let Some(split) = &closer.split {
            for item in &split.items {
                let _ = self.call_runtime("msrt_cleanup_cancel", &[item.handle], MTy::UNIT);
            }
        } else {
            // Cancel, not discard: entries registered after this one must still run on a fault.
            let handle = self.entry_of(&closer);
            let _ = self.call_runtime("msrt_cleanup_cancel", &[handle], MTy::UNIT);
        }
        let gone = self.b.bconst(false);
        self.b.def_var(flag, gone);
    }

    /// The close at scope end: its failure is returned like `try`, unless the program already
    /// called `close()` on this path and handled the result, which is not returned a second time.
    fn scope_close(&mut self, uid: usize, closer: &Closer) {
        let Some(explicit) = closer.explicit else {
            if let Some(r) = self.emit_close(uid, closer) {
                self.propagate_close_error(uid, r);
            }
            return;
        };
        let called = self.b.use_var(explicit);
        let (again, first, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(called, again, &[], first, &[]);
        self.b.seal_block(again);
        self.b.seal_block(first);
        self.b.switch_to(again);
        if let Some(r) = self.emit_close(uid, closer) {
            self.drop_value(r);
        }
        self.b.br(join, &[]);
        self.b.switch_to(first);
        if let Some(r) = self.emit_close(uid, closer) {
            self.propagate_close_error(uid, r);
        }
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
    }

    /// Records that the program called `close()` on the closing binding `recv` named.
    pub(crate) fn note_explicit_close(&mut self, recv: &Expr) {
        let ms_check::hir::Resolution::Local(b) = self.hir.resolution(recv) else {
            return;
        };
        let Some(explicit) = self.closers.get(&b.uid).and_then(|c| c.explicit) else {
            return;
        };
        if self.dead {
            return;
        }
        let yes = self.b.bconst(true);
        self.b.def_var(explicit, yes);
    }

    /// Leaves the binding `uid` at the end of its scope, closing it unless a move took it.
    pub(crate) fn close_at_scope_end(&mut self, uid: usize, closer: &Closer) {
        if closer.split.is_some() {
            self.emit_close(uid, closer);
            return;
        }
        let Some(flag) = closer.flag else {
            self.scope_close(uid, closer);
            return;
        };
        let held = self.b.use_var(flag);
        let (close, moved, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(held, close, &[], moved, &[]);
        self.b.seal_block(close);
        self.b.seal_block(moved);
        self.b.switch_to(close);
        self.scope_close(uid, closer);
        self.b.br(join, &[]);
        // A move cancelled the entry; it leaves the stack now.
        self.b.switch_to(moved);
        let handle = self.entry_of(closer);
        let _ = self.call_runtime("msrt_cleanup_discard", &[handle], MTy::UNIT);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
    }

    /// Closes `v`, a value of the place `place` that the program is about to overwrite or
    /// discard, when it holds a resource: shielded like any other close. A value with nothing to
    /// close adds no code.
    pub(crate) fn close_discarded(&mut self, place: &Expr, v: Value) -> Result<(), Error> {
        let ty = ct::sub(&self.hir.ty(place), &self.subst);
        self.close_discarded_ty(&ty, v)
    }

    /// [`Self::close_discarded`] for a value of checked type `ty`.
    pub(crate) fn close_discarded_ty(&mut self, ty: &ct::Ty, v: Value) -> Result<(), Error> {
        let Some(kind) = self.part_closer(ty)? else {
            return Ok(());
        };
        self.close_discarded_kind(&kind, v);
        Ok(())
    }

    /// Closes `v` with `kind`, shielded like any other close.
    pub(crate) fn close_discarded_kind(&mut self, kind: &CloseKind, v: Value) {
        let mt = self.ty_of(v);
        let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
        close_call(&mut self.b, kind, v, mt);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }

    /// Leaves the closing binding `uid`: the cleanup entry goes away and its close runs on the
    /// current value.
    /// The result of a close that can fail is returned for the caller to propagate.
    pub(crate) fn emit_close(&mut self, uid: usize, closer: &Closer) -> Option<Value> {
        if let Some(split) = &closer.split {
            self.close_split(uid, split, closer.flag);
            return None;
        }
        let l = self.locals[&uid];
        let v = self.local_get(&l);
        let handle = self.entry_of(closer);
        let _ = self.call_runtime("msrt_cleanup_discard", &[handle], MTy::UNIT);
        // Like the cleanup stack on a fault, a stop request that arrives while the close runs
        // must not interrupt it.
        let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
        if let CloseKind::Func {
            fid,
            writes_back: true,
        } = &closer.kind
            && self.b.m.needs_drop(l.ty)
        {
            // The block is over, so the close works on the binding's own value: no copy of what
            // it holds. The scope still drops the value the close leaves behind.
            let slot = match l.slot {
                Some(p) => p,
                None => {
                    let moved = self.local_take(&l);
                    self.put_slot(moved)
                }
            };
            let r = self.b.call(*fid, &[slot]);
            if l.slot.is_none() {
                let after = self.take_slot(slot, l.ty);
                self.local_put(&l, after);
            }
            let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
            return self.fallible_result(r);
        }
        let r = close_call_result(&mut self.b, &closer.kind, v, l.ty);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
        self.fallible_result(r)
    }

    /// `r` when it is the `Result` of a close that can fail; a `Unit` result needs nothing.
    fn fallible_result(&mut self, r: Value) -> Option<Value> {
        (self.b.ty(r) != MTy::UNIT).then_some(r)
    }

    /// A scope-end close returned `r`: on an error, the function returns it after closing what
    /// is still open, like `try value.close()`. A close that fails while an error is already on its
    /// way out is dropped, so the first error is the one returned.
    fn propagate_close_error(&mut self, uid: usize, r: Value) {
        if self.returning_close_error {
            self.drop_value(r);
            return;
        }
        let rty = self.b.ty(r);
        let case_of = |m: &ms_mir::ir::Module, alt: AltId, name: &str| {
            m.alts[alt.index()]
                .cases
                .iter()
                .position(|c| c.name == name)
        };
        let TyKind::Alt(a) = self.b.m.types.kind(rty).clone() else {
            return;
        };
        let err = case_of(self.b.m, a, "error").expect("a close returns a Result");
        // A function that cannot return the close's `Error` faults on a failed close instead.
        let returned = match self.b.m.types.kind(self.result_ty()).clone() {
            TyKind::Alt(ra) => case_of(self.b.m, ra, "error")
                .filter(|&e| {
                    self.b.m.alts[ra.index()].cases[e].fields[0].1
                        == self.b.m.alts[a.index()].cases[err].fields[0].1
                })
                .map(|e| (ra, e)),
            _ => None,
        };
        let Some((ra, ret_err)) = returned else {
            close_error_fault(&mut self.b, r);
            return;
        };
        let tag = self.b.alt_tag(r);
        let k = self.b.iconst(err as i64);
        let is_err = self.b.icmp(Cc::Eq, tag, k);
        let (errb, okb) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(is_err, errb, &[], okb, &[]);
        self.b.seal_block(errb);
        self.b.seal_block(okb);

        self.enter(errb);
        let payload = self.b.alt_get(a, err as u32, 0, r);
        let po = self.owned(crate::func::Val {
            v: payload,
            own: false,
        });
        let out = self.b.alt_new(ra, ret_err as u32, &[po]);
        self.drop_value(r);
        if let Some(pending) = self.pending_return {
            self.drop_value(pending);
        }
        // This binding is closed; release its value, then return through the enclosing scopes
        // without closing again what this path has already closed.
        let l = self.locals[&uid];
        if self.needs_drop(l.ty) {
            let v = self.local_take(&l);
            self.b.emit(Op::Drop, &[v], Imm::None, None);
        }
        let before = self.closed_on_path.clone();
        self.closed_on_path.insert(uid);
        let done = self.scope_done.clone();
        self.closed_on_path.extend(done);
        self.returning_close_error = true;
        self.emit_return(Some(crate::func::Val { v: out, own: true }));
        self.returning_close_error = false;
        self.closed_on_path = before;

        self.enter(okb);
        self.drop_value(r);
    }
}
