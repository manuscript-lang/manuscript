//! The extern of `@std/test/test.ms` that needs the compiler: the debug text of a value. The
//! expectations themselves are Manuscript source.

use crate::Error;
use crate::cx::Cx;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::api::ast::Expr;
use ms_check::api::hir::CallView;
use ms_check::api::hir::Resolution;
use ms_check::api::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::Value;
use ms_mir::ir::{Func, Imm, Mode, Module, Op};
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

    /// The hand-lowered externs of `@std/internal/test.ms`: `repr`.
    pub fn testing_native(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        name: &str,
    ) -> Result<Val, Error> {
        if name == "fake" {
            return self.fake_call(e, view);
        }
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::VOID));
        }
        self.at(e.pos);
        let operand = self.borrow(args[0].val);
        match name {
            "repr" => Ok(self.repr_text(operand)),
            other => Err(Error::new(format!("unsupported testing function {other}"))),
        }
    }
}

impl FnLower<'_> {
    /// `fake(original, replacement, body)`: `original` names a source function, whose calls the
    /// test build routes through the fake table; `replacement` answers them while `body` runs.
    fn fake_call(&mut self, e: &Expr, view: &CallView<'_>) -> Result<Val, Error> {
        let [original, replacement, body] = view.arguments.as_slice() else {
            return Err(Error::new(
                "fake takes the original, its replacement and a body",
            ));
        };
        // A function, or a method named through an object (`shop.price`), which stands for the
        // method of that type on every object; the replacement then takes no receiver.
        let (callee, id, receiver) = match self.hir.resolution(original.expr) {
            Resolution::Function(sym)
                if sym.native == ct::Native::Source
                    && ct::variable_set(&sym.variables()).is_empty() =>
            {
                let callee =
                    self.callable_of_decl(sym.module, sym.decl.as_ref().map(|d| d.id()))?;
                (callee, sym.id, false)
            }
            Resolution::Method(m) if m.native == ct::Native::Source && m.variables.is_empty() => {
                let callee = self.callable_of_decl(m.module, m.decl.as_ref().map(|d| d.id()))?;
                (callee, m.id, true)
            }
            _ => {
                return Err(Error::new(
                    "fake: name a function, or a method on an object (`shop.price`), written in Manuscript without type parameters",
                ));
            }
        };
        let fid = self.instance(&callee, &ct::Subst::default())?;
        let proto = &self.b.m.funcs[fid.index()];
        if !proto.noalias.is_empty()
            || proto.ret_borrowed
            || proto.ret_view
            || proto.params.iter().any(|p| p.mode != Mode::Borrow)
        {
            return Err(Error::new(
                "fake: a function or method that changes an argument or its object, or returns a borrow, cannot be replaced",
            ));
        }
        if !self.cx.faked.iter().any(|(f, _)| *f == fid) {
            self.cx.faked.push((fid, receiver));
            let shown = self.syms.str(callee.name).to_string();
            let file = self
                .b
                .m
                .files
                .get(self.file as usize)
                .cloned()
                .unwrap_or_default();
            let at = format!(
                "{file}:{}:{}",
                original.expr.pos.line, original.expr.pos.column
            );
            self.cx.faked_names.push((id, shown, at));
        }
        let replacement = self.expr(replacement.expr)?;
        if self.dead {
            return Ok(replacement);
        }
        let replacement = self.borrow(replacement);
        let body = self.expr(body.expr)?;
        if self.dead {
            return Ok(body);
        }
        let body = self.borrow(body);
        self.at(e.pos);
        let closure_ty = self.ty_of(replacement);
        let push = runtime_fn(
            self.b.m,
            "msrt_fake_push",
            &[MTy::INT, closure_ty],
            MTy::VOID,
        );
        let pop = runtime_fn(self.b.m, "msrt_fake_pop", &[MTy::INT], MTy::VOID);
        let index = self.b.iconst(fid.index() as i64);
        self.b.call_rt(push, &[index, replacement]);
        let result = self.b.call_ind(body, &[]);
        self.b.call_rt(pop, &[index]);
        Ok(self.val(result, true))
    }
}

/// Gives every function a test faked a prologue that calls the replacement when the running
/// test installed one: the body moves to a new function and the original id becomes the router.
pub(crate) fn route_fakes(cx: &mut Cx, m: &mut Module) {
    let faked = std::mem::take(&mut cx.faked);
    for (id, receiver) in faked {
        let params = m.funcs[id.index()].params.clone();
        let ret = m.funcs[id.index()].ret;
        let name = m.funcs[id.index()].name.clone();
        let body = std::mem::replace(
            &mut m.funcs[id.index()],
            Func::new(&name, params.clone(), ret),
        );
        let real = m.add_func(body);
        let skip = usize::from(receiver);
        let ptys: Vec<MTy> = params.iter().skip(skip).map(|p| p.ty).collect();
        let fty = m.types.func(ptys, ret);
        let has = runtime_fn(m, "msrt_fake_has", &[MTy::INT], MTy::BOOL);
        let get = runtime_fn(m, "msrt_fake_get", &[MTy::INT], fty);
        let pop = runtime_fn(m, "msrt_fake_pop", &[MTy::INT], MTy::VOID);
        let push = runtime_fn(m, "msrt_fake_push", &[MTy::INT, fty], MTy::VOID);
        let mut b = FuncBuilder::new(m, &name, params, ret);
        let args = b.params();
        let index = b.iconst(id.index() as i64);
        let faked_here = b.call_rt(has, &[index]);
        let (fake, plain) = (b.new_block(), b.new_block());
        b.br_if(faked_here, fake, &[], plain, &[]);
        b.switch_to(fake);
        let closure = b.call_rt(get, &[index]);
        // While the replacement runs, calls it makes to the function reach the original, so a
        // replacement can wrap the real function.
        b.call_rt(pop, &[index]);
        let r = b.call_ind(closure, &args[skip..]);
        b.call_rt(push, &[index, closure]);
        // The table lends the replacement; calling it is all the router does with it.
        b.emit(Op::Forget, &[closure], Imm::None, None);
        b.ret(Some(r));
        b.switch_to(plain);
        let r = b.call(real, &args);
        b.ret(Some(r));
        let router = b.into_func();
        m.funcs[id.index()] = router;
    }
}

/// A test fakes only the program's boundaries: functions that declare an effect, such as the
/// standard library's `now` or a project function marked `// ms: effect db.write`.
pub(crate) fn check_fakes_are_boundaries(
    cx: &mut Cx,
    program: &ms_check::Program,
) -> Result<(), Error> {
    for (id, name, at) in std::mem::take(&mut cx.faked_names) {
        if program.declared_effects_of(id).is_empty() {
            return Err(Error::new(format!(
                "{at}: fake: {name} declares no effect, so it is not a boundary to the outside world; \
                 pass what it computes in as a parameter, or declare the boundary with `// ms: effect NAME`"
            )));
        }
    }
    Ok(())
}
