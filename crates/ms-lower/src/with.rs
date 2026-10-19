//! `with name = value:` — the value's `close` runs on every way out of the block.

use crate::Error;
use crate::func::FnLower;
use ms_check::types as ct;
use ms_mir::ir::{FuncId, Imm, Mode, Op};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// How a `with` binding is closed.
#[derive(Clone)]
pub(crate) enum Closer {
    /// An interface value: the vtable entry.
    Iface(IfaceId, u32),
    /// A source instance, which may hand `self` back through a slot.
    Func { fid: FuncId, writes_back: bool },
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
        let closer = self.closer_for(&cleanup, &binding.ty)?;
        self.push_scope();
        self.bind_local(&binding, x);
        self.flush_temps(mark);
        self.closers.insert(binding.uid, closer);
        // A binding that needs no drop is not registered by `bind_local`; closing still runs.
        let scope = self.scopes.last_mut().expect("scope");
        if !scope.contains(&binding.uid) {
            scope.push(binding.uid);
        }
        let r = self.stmts(body);
        self.pop_scope();
        r
    }

    fn closer_for(&mut self, cleanup: &ct::MethodRef, ty: &ct::Ty) -> Result<Closer, Error> {
        let ty = ct::sub(ty, &self.subst);
        let mt = self.mty(&ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            let k = self.b.m.ifaces[iface.index()]
                .methods
                .iter()
                .position(|m| m.name == "close")
                .ok_or_else(|| Error::new("interface without close"))?;
            return Ok(Closer::Iface(iface, k as u32));
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
        let mut subst = ct::Subst::new();
        if !ct::unify(
            &im.receiver,
            &ty,
            &ct::variable_set(&im.variables),
            &mut subst,
        ) {
            return Err(Error::new("cannot bind close receiver type"));
        }
        let fid = self.cx.function_for(self.b.m, &c, &subst)?;
        let writes_back = self.cx.var_positions(&c).contains(&0);
        Ok(Closer::Func { fid, writes_back })
    }

    /// Runs the close operation of the `with` binding `uid` on its current value.
    pub(crate) fn emit_close(&mut self, uid: usize, closer: &Closer) {
        let l = self.locals[&uid];
        let v = self.b.use_var(l.var);
        match closer {
            Closer::Iface(iface, k) => {
                self.b.call_method(*iface, *k, v, &[]);
            }
            Closer::Func {
                fid,
                writes_back: false,
            } => {
                self.b.call(*fid, &[v]);
            }
            Closer::Func {
                fid,
                writes_back: true,
            } => {
                let own = self.owned(crate::func::Val { v, own: false });
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(l.ty), Some(MTy::PTR))
                    .expect("slot");
                self.move_into(slot, own);
                let r = self.b.call(*fid, &[slot]);
                let after = self.move_out(slot, l.ty);
                self.drop_value(after);
                self.drop_value(r);
            }
        }
        let _ = Mode::Borrow;
    }
}
