//! The two externs of `@std/test/test.ms` that need the compiler: the debug text of a value and a
//! fault trap. The expectations themselves are Manuscript source.

use crate::Error;
use crate::cx::HelperKey;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::api::ast::Expr;
use ms_check::api::hir::CallView;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, Imm, InlineHint, Linkage, Mode, Op, Param, Value};
use ms_mir::types::{AltId, Ty as MTy, TyKind};

impl FnLower<'_> {
    /// The `ok` and `error` case indexes of a Result alternative.
    fn result_cases(&self, rty: MTy) -> Result<(AltId, u32, u32), Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("not a Result"));
        };
        let find = |n: &str| {
            self.b.m.alts[a.index()]
                .cases
                .iter()
                .position(|c| c.name == n)
                .map(|i| i as u32)
        };
        match (find("ok"), find("error")) {
            (Some(ok), Some(err)) => Ok((a, ok, err)),
            _ => Err(Error::new("not a Result")),
        }
    }

    /// `ok(payload)` of the Result type (payload owned).
    pub(crate) fn testing_ok(&mut self, rty: MTy, payload: Value) -> Result<Value, Error> {
        let (a, ok, _) = self.result_cases(rty)?;
        Ok(self.b.alt_new(a, ok, &[payload]))
    }

    /// A borrowed string literal.
    pub(crate) fn lit(&mut self, text: &str) -> Val {
        let v = self.b.str_lit(text);
        Val { v, own: false }
    }

    /// The hand-lowered externs of `@std/internal/test.ms`: `repr` and `catch_fault`.
    pub fn testing_native(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        name: &str,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let rty = self.emty(e)?;
        self.at(e.pos);
        let operand = self.borrow(args[0].val);
        match name {
            "repr" => Ok(self.repr_text(operand)),
            "catch_fault" => self.catch_fault(rty, operand),
            other => Err(Error::new(format!("unsupported testing function {other}"))),
        }
    }

    /// Keeps the trap in a frame that owns none of the caller's values. Windows faults jump
    /// back into this frame: inlining it before unwind lowering would register drops for
    /// caller locals inside the operation, then resume the caller after freeing those locals.
    fn fault_trap(&mut self, operation_ty: MTy) -> FuncId {
        let key = HelperKey::TestingTrap(operation_ty);
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let begin = runtime_fn(self.b.m, "msrt_trap_begin", &[], MTy::BOOL);
        let end = runtime_fn(self.b.m, "msrt_trap_end", &[], MTy::UNIT);
        let wait = runtime_fn(self.b.m, "msrt_trap_wait", &[MTy::PTR], MTy::BOOL);
        let mut b = FuncBuilder::new(
            self.b.m,
            "test.trap",
            vec![
                Param {
                    ty: operation_ty,
                    mode: Mode::Borrow,
                },
                Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                },
            ],
            MTy::BOOL,
        );
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().inline = InlineHint::Never;
        let params = b.params();
        let parent_side = b.call_rt(begin, &[]);
        let (child, parent) = (b.new_block(), b.new_block());
        b.br_if(parent_side, parent, &[], child, &[]);
        b.seal_block(child);
        b.seal_block(parent);
        b.switch_to(child);
        b.call_ind(params[0], &[]);
        b.call_rt(end, &[]);
        b.unreachable();
        b.switch_to(parent);
        let faulted = b.call_rt(wait, &[params[1]]);
        b.ret(Some(faulted));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// Runs `operation` behind the platform's fault trap: the fault message, or none when it returns.
    fn catch_fault(&mut self, rty: MTy, operation: Value) -> Result<Val, Error> {
        let trap = self.fault_trap(self.ty_of(operation));
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        let faulted = self.b.call(trap, &[operation, slot]);
        self.two_ways(
            faulted,
            rty,
            &mut |s| {
                let m =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                        .expect("take");
                Ok(Some(s.b.opt_some(m)))
            },
            &mut |s| {
                let none = s.b.opt_none(rty);
                Ok(Some(s.owned(Val {
                    v: none,
                    own: false,
                })))
            },
        )
    }
}
