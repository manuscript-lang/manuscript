//! Method values retain a mutable alias's saved path, not a snapshot of its value.

use crate::Error;
use crate::closure::{LambdaCapture, restore_alias_capture};
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Local, Val};
use ms_check::hir::{ModuleHir, Resolution};
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Mode, Module, Op, Param};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::Expr;
use std::rc::Rc;

pub(crate) struct BoundAliasJob {
    expr: Expr,
    hir: Rc<ModuleHir>,
    subst: ct::Subst,
    capture: LambdaCapture,
}

impl FnLower<'_> {
    pub(crate) fn bound_alias_method(
        &mut self,
        e: &Expr,
        left: &Expr,
        method: &ct::MethodRef,
    ) -> Result<Option<Val>, Error> {
        if !crate::mutation::method_changes_receiver(method, &self.cx.mutated) {
            return Ok(None);
        }
        let Resolution::Local(binding) = self.hir.resolution(left) else {
            return Ok(None);
        };
        let Some(alias) = self.aliases.get(&binding.uid).cloned() else {
            return Ok(None);
        };
        let fty = self.emty(e)?;
        let TyKind::Fn(params, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("method value without function type"));
        };
        let mut types = Vec::new();
        let mut values = Vec::new();
        let capture = self.capture_alias(&binding, alias, &mut types, &mut values)?;
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(params.into_iter().map(|ty| Param {
            ty,
            mode: Mode::Borrow,
        }));
        let mut f = ms_mir::ir::Func::new("<borrowed method>", ps, ret);
        f.kind = FuncKind::Closure { captures: types };
        // Each site has its own saved field path; method/type-only caches cannot
        // distinguish two aliases of same-typed sibling fields.
        let id = self.b.m.add_func(f);
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::BoundAlias(Rc::new(BoundAliasJob {
                expr: e.clone(),
                hir: self.hir.clone(),
                subst: self.subst.clone(),
                capture,
            })),
        });
        let v = self
            .b
            .emit(Op::ClosureNew, &values, Imm::Func(id), Some(fty))
            .expect("closure");
        Ok(Some(Val { v, own: true }))
    }
}

pub(crate) fn build_bound_alias(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &BoundAliasJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("bound alias without closure kind"));
    };
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), job.subst.clone(), file, proto.ret);
    let params = fl.b.params();
    let values: Vec<_> = captures
        .iter()
        .enumerate()
        .map(|(i, ty)| {
            fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(i as u32), Some(*ty))
                .expect("capture")
        })
        .collect();
    restore_alias_capture(&mut fl, &job.capture, &values)?;
    let LambdaCapture::Alias { binding, .. } = &job.capture else {
        return Err(Error::new("bound alias without a place"));
    };
    let alias = fl.aliases.remove(&binding.uid).expect("restored alias");
    let current = fl.alias_read(&alias)?;
    let ty = fl.ty_of(current.v);
    let owned = fl.owned(current);
    let slot =
        fl.b.emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
            .expect("slot");
    fl.move_into(slot, owned);
    let var = fl.b.declare_var(ty, Mode::Borrow);
    fl.locals.insert(
        binding.uid,
        Local {
            var,
            ty,
            slot: Some(slot),
        },
    );
    // Reuse the existing source/native/default method thunk, now sharing this
    // invocation's leaf slot. The owning root remains live during callbacks.
    let method = fl.expr(&job.expr)?;
    let result = fl.b.call_ind(method.v, &params[1..]);
    fl.drop_value(method.v);
    let updated = fl.move_out(slot, ty);
    fl.alias_update(&alias, &[], &mut |s, old| {
        s.drop_value(old);
        Ok(updated)
    })?;
    fl.emit_return(Some(fl.val(result, true)));
    let mut f = fl.b.into_func();
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}
