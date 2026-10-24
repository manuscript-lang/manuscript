//! `with name = value:` — the value's `close` runs on every way out of the block.

use crate::Error;
use crate::func::FnLower;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Linkage, Mode, Op, Param, Value};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// How a `with` binding is closed.
#[derive(Clone)]
pub(crate) enum CloseKind {
    /// An interface value: the vtable entry.
    Iface(IfaceId, u32),
    /// A source instance, which may hand `self` back through a slot.
    Func { fid: FuncId, writes_back: bool },
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
        let kind = self.closer_for(&cleanup, &binding.ty)?;
        self.push_scope();
        self.bind_local(&binding, x);
        self.flush_temps(mark);
        // A fault inside the block runs the close through the runtime's cleanup stack; leaving
        // normally discards the entry and closes the current value.
        let ty = self.locals[&binding.uid].ty;
        let thunk = self.close_thunk(&kind, ty);
        let current = self.read_local(&binding)?;
        let handle = self
            .b
            .emit(
                Op::CleanupPush,
                &[current.v],
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
        let r = self.stmts(body);
        self.pop_scope();
        r
    }

    fn closer_for(&mut self, cleanup: &ct::MethodRef, ty: &ct::Ty) -> Result<CloseKind, Error> {
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
        let im = if cleanup.native.as_str() == "contract" {
            self.contract_impl(cleanup, &ty)
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
            &ty,
            &ct::variable_set(&declared.variables),
            &mut subst,
        ) {
            return Err(Error::new("cannot bind close receiver type"));
        }
        let fid = self.instance(&c, &subst)?;
        let writes_back = self.cx.var_positions(&c).contains(&0);
        Ok(CloseKind::Func { fid, writes_back })
    }

    /// The function the cleanup stack calls with the registered value.
    fn close_thunk(&mut self, kind: &CloseKind, ty: MTy) -> FuncId {
        let key = match kind {
            CloseKind::Iface(i, k) => format!("close:iface{}:{k}", i.0),
            CloseKind::Func { fid, writes_back } => {
                format!("close:{}:{writes_back}", fid.index())
            }
        };
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let ps = vec![Param {
            ty,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let v = b.params()[0];
        close_call(&mut b, kind, v, ty);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
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
        close_call(&mut self.b, &closer.kind, v, l.ty);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }
}
