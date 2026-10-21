//! The shared test fixture: `make_fixture`, then the `TestHooks` around each test.
//!
//! Every test runs in its own process, so the factory and `before_all` run once per test
//! and `after_all` follows `after_each`.

use crate::Error;
use crate::func::FnLower;
use ms_check::hir::Callable;
use ms_check::types::{self as ct, BindingRef, Subst};
use ms_mir::ir::{Imm, Op};
use ms_mir::types::Ty as MTy;
use std::rc::Rc;

/// Hook callables of the fixture type, and the local that holds the fixture.
#[derive(Clone)]
pub(crate) struct Hooks {
    binding: BindingRef,
    after_each: Option<Rc<Callable>>,
    after_all: Option<Rc<Callable>>,
}

impl FnLower<'_> {
    /// Builds the fixture into the local `binding` and runs `before_all` and `before_each`.
    pub(crate) fn begin_fixture(
        &mut self,
        test: &Callable,
        binding: &BindingRef,
    ) -> Result<(), Error> {
        let fixture = self
            .cx
            .fixtures
            .get(&test.module.file)
            .cloned()
            .ok_or_else(|| Error::new("test fixture without a factory"))?;
        let factory = self.callable_of_decl(
            fixture.factory.module,
            fixture.factory.decl.as_ref().map(|d| d.id()),
        )?;
        let fid = self.cx.function_for(self.b.m, &factory, &Subst::new())?;
        let made = self.b.call(fid, &[]);
        self.bind_local(binding, crate::func::Val { v: made, own: true });
        let hook = |s: &Self, name: &str| s.fixture_hook(&fixture.ty, name);
        let (before_all, before_each) = (hook(self, "before_all"), hook(self, "before_each"));
        self.fixture = Some(Hooks {
            binding: binding.clone(),
            after_each: hook(self, "after_each"),
            after_all: hook(self, "after_all"),
        });
        for c in [before_all, before_each].into_iter().flatten() {
            self.run_hook(&c, binding)?;
        }
        Ok(())
    }

    /// Runs `after_each` and `after_all` before the function returns.
    pub(crate) fn end_fixture(&mut self) {
        let Some(hooks) = self.fixture.take() else {
            return;
        };
        let mark = self.temps.len();
        for c in [&hooks.after_each, &hooks.after_all].into_iter().flatten() {
            // A hook that cannot be lowered was already reported when the fixture began.
            let _ = self.run_hook(c, &hooks.binding);
        }
        self.flush_temps(mark);
        self.fixture = Some(hooks);
    }

    /// The `TestHooks` method `name` the fixture type implements.
    fn fixture_hook(&self, fixture: &ct::Ty, name: &str) -> Option<Rc<Callable>> {
        let key = ct::type_key(fixture);
        let m = self.cx.methods.iter().find(|m| {
            m.contract.as_ref().is_some_and(|c| c.is_std("TestHooks"))
                && ct::type_key(&m.receiver) == key
                && m.name().is_some_and(|n| n.as_str() == name)
        })?;
        let decl = m.decl.as_ref()?;
        self.callable_of_decl(m.module, Some(decl.id())).ok()
    }

    /// Calls a hook on the fixture local; a hook that changes `self` works on the local's value
    /// through a slot, which is stored back.
    fn run_hook(&mut self, hook: &Rc<Callable>, binding: &BindingRef) -> Result<(), Error> {
        let fid = self.cx.function_for(self.b.m, hook, &Subst::new())?;
        let recv = self.read_local(binding)?;
        if self.cx.var_positions(hook).is_empty() {
            let v = self.b.call(fid, &[recv.v]);
            self.drop_if_owned(v);
            return Ok(());
        }
        // A hook that changes `self` takes the address of a slot holding a copy of the fixture
        // and puts the final value back into it.
        let ty = self.ty_of(recv.v);
        let copy = self.owned(recv);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
            .expect("slot");
        self.move_into(slot, copy);
        let v = self.b.call(fid, &[slot]);
        self.drop_if_owned(v);
        let updated = self.move_out(slot, ty);
        let l = self.local(binding)?;
        let old = self.local_take(&l);
        self.drop_value(old);
        self.local_put(&l, updated);
        Ok(())
    }

    fn drop_if_owned(&mut self, v: ms_mir::ir::Value) {
        if self.needs_drop(self.ty_of(v)) {
            self.drop_value(v);
        }
    }
}
