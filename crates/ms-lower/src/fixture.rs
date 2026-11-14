//! The shared test fixture. A file with `make_fixture` hands one fixture to all of its tests:
//! each test takes it as a final `var` parameter, and `@std/internal/test_runner.ms`
//! `run_fixture_file` makes it and runs the `TestHooks` around the tests. This module finds
//! the hooks the fixture type declares.

use crate::cx::Cx;
use ms_check::api::hir::Callable;
use ms_check::api::types as ct;
use std::rc::Rc;

impl Cx {
    /// The `TestHooks` method `name` the fixture type implements.
    pub(crate) fn fixture_hook(&mut self, fixture: &ct::Ty, name: &str) -> Option<Rc<Callable>> {
        let syms = self.syms;
        let key = self.tys.shape(fixture);
        let tys = &mut self.tys;
        let named = |m: &ct::MethodRef| m.name().is_some_and(|n| syms.str(n) == name);
        let m = self
            .methods
            .iter()
            .find(|m| {
                m.contract.as_ref().is_some_and(|c| c.is_test_hooks(syms))
                    && tys.shape(&m.receiver) == key
                    && named(m)
            })
            // A fixture's own hook of that name needs no `impl TestHooks`.
            .or_else(|| {
                self.methods
                    .iter()
                    .find(|m| m.is_inherent(syms) && named(m) && tys.shape(&m.receiver) == key)
            })?;
        let decl = m.decl.as_ref()?;
        self.callables.get(&(m.module, decl.id())).cloned()
    }
}
