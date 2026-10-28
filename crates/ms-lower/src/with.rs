//! `with name = value:` — the value's `close` runs on every way out of the block.

use crate::Error;
use crate::func::FnLower;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, FuncKind, Imm, Linkage, Mode, Op, Param, Value};
use ms_mir::types::{AltId, IfaceId, RecId, Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// How a `with` binding is closed.
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

/// A `with` binding's close operation and its entry on the runtime cleanup stack, which a fault
/// runs.
#[derive(Clone)]
pub(crate) struct Closer {
    kind: CloseKind,
    handle: ms_mir::ir::Value,
}

/// Calls the close operation on `v` of type `ty`.
fn close_call(b: &mut FuncBuilder<'_>, kind: &CloseKind, v: Value, ty: MTy) {
    match kind {
        CloseKind::Iface(iface, k) => {
            b.call_method(*iface, *k, v, &[]);
        }
        CloseKind::Func {
            fid,
            writes_back: false,
        } => {
            b.call(*fid, &[v]);
        }
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
            b.call(*fid, &[slot]);
            let take = if droppable { Op::Take } else { Op::Load };
            let after = b.emit(take, &[slot], Imm::Ty(ty), Some(ty)).expect("take");
            if droppable {
                b.emit(Op::Drop, &[after], Imm::None, None);
            }
        }
    }
}

impl FnLower<'_> {
    pub(crate) fn with_stmt(&mut self, s: &Stmt, value: &Expr, body: &[Stmt]) -> Result<(), Error> {
        let info = self.hir.stmt(s);
        let binding = info
            .loop_binding
            .ok_or_else(|| Error::new("with without a binding"))?;
        let cleanup = info
            .cleanup
            .ok_or_else(|| Error::new("with without a cleanup operation"))?;
        let mark = self.temps.len();
        let x = self.expr(value)?;
        if self.dead {
            return Ok(());
        }
        self.push_scope();
        self.bind_closing(&binding, x, Some(&cleanup))?;
        self.flush_temps(mark);
        let r = self.stmts(body);
        self.pop_scope();
        r
    }

    /// Binds `binding` to `x` and registers its close operation: a fault runs it through the
    /// runtime's cleanup stack, and leaving the binding's scope closes the current value.
    pub(crate) fn bind_closing(
        &mut self,
        binding: &ct::BindingRef,
        x: crate::func::Val,
        cleanup: Option<&ct::MethodRef>,
    ) -> Result<(), Error> {
        let kind = self.closer_for(cleanup, &binding.ty)?;
        // A `var` binding that changes lives in memory, so a fault or cancellation closes its
        // value at that moment and not the one it started with.
        if binding.mutable {
            self.slotted.insert(binding.uid);
        }
        self.redefined.insert(binding.uid);
        self.bind_local(binding, x);
        let ty = self.locals[&binding.uid].ty;
        let slot = self.locals[&binding.uid].slot;
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
        self.closers.insert(binding.uid, Closer { kind, handle });
        // A binding that needs no drop is not registered by `bind_local`; closing still runs.
        let scope = self.scopes.last_mut().expect("scope");
        if !scope.contains(&binding.uid) {
            scope.push(binding.uid);
        }
        Ok(())
    }

    /// How a binding of `ty` is closed: its own close operation, if it has one, and then the
    /// resources it holds.
    fn closer_for(
        &mut self,
        cleanup: Option<&ct::MethodRef>,
        ty: &ct::Ty,
    ) -> Result<CloseKind, Error> {
        let ty = ct::sub(ty, &self.subst);
        let mt = self.mty(&ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            let k = self.b.m.ifaces[iface.index()]
                .methods
                .iter()
                .position(|m| m.name == "close")
                .ok_or_else(|| Error::new("interface without close"))?;
            return Ok(CloseKind::Iface(iface, k as u32));
        }
        let own = match cleanup {
            Some(c) => Some(self.own_closer(c, &ty)?),
            None => None,
        };
        self.close_with_parts(&ty, own)?
            .ok_or_else(|| Error::new(format!("{ty} has no close operation")))
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
    fn part_closer(&mut self, ty: &ct::Ty) -> Result<Option<CloseKind>, Error> {
        if self.cx.classes.class(ty) != ms_check::ownership::Class::Resource {
            return Ok(None);
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
        // A lock guard hands its payload back to the box when it closes, and the last holder of
        // the box closes it then; closing the guard's copy as a part would close it early.
        if ty.is_source_type("@std/sync.ms", "SharedGuard") {
            return Ok(own);
        }
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
        close_call(&mut b, kind, v, ty);
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
        close_call(&mut self.b, &closer.kind, old, ty);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }

    /// Leaves the `with` binding `uid`: the cleanup entry goes away and its close runs on the
    /// current value.
    pub(crate) fn emit_close(&mut self, uid: usize, closer: &Closer) {
        let l = self.locals[&uid];
        let v = self.local_get(&l);
        let _ = self.call_runtime("msrt_cleanup_discard", &[closer.handle], MTy::UNIT);
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
            self.b.call(*fid, &[slot]);
            if l.slot.is_none() {
                let after = self.take_slot(slot, l.ty);
                self.local_put(&l, after);
            }
            let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
            return;
        }
        close_call(&mut self.b, &closer.kind, v, l.ty);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }
}
