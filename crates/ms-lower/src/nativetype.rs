//! Operations of the plain-data native types, by identity. The runtime function behind each
//! is whatever the type's `.ms` declaration calls; lowering calls the declared method.

use crate::cx::Cx;
use ms_check::Program;
use ms_check::api::NodeId;
use ms_check::api::hir::Callable;
use ms_check::api::types::Name;
use ms_check::fxmap::HashMap;
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{NativeType, Ty as MTy, TyKind};
use std::rc::Rc;

/// The native type `t` is, if any; lowering sets it on the type when it declares it.
pub(crate) fn native_type(m: &Module, t: MTy) -> Option<NativeType> {
    let TyKind::Type(rid) = m.types.kind(t) else {
        return None;
    };
    m.type_defs[rid.index()].native
}

/// Whether the type orders itself through the `compare` its declaration defines.
pub(crate) fn has_declared_order(r: NativeType) -> bool {
    matches!(
        r,
        NativeType::Timestamp | NativeType::Instant | NativeType::Decimal
    )
}

const NATIVE_RECS: usize = 4;

fn slot(r: NativeType) -> usize {
    match r {
        NativeType::Timestamp => 0,
        NativeType::Instant => 1,
        NativeType::Decimal => 2,
        NativeType::Duration => 3,
    }
}

/// A flat table of the methods that supply `Comparable` for each native type.
pub struct NativeOps {
    table: [Option<Rc<Callable>>; NATIVE_RECS],
}

impl NativeOps {
    pub(crate) fn new(
        syms: ms_check::api::Names,
        program: &Program,
        callables: &HashMap<(Name, NodeId), Rc<Callable>>,
    ) -> NativeOps {
        let mut table: [Option<Rc<Callable>>; NATIVE_RECS] = Default::default();
        let comparable = program.session.standard("Comparable", Vec::new());
        for method in &program.methods {
            let Some(decl) = method.decl.as_ref() else {
                continue;
            };
            if !method.supplies(syms, &comparable) {
                continue;
            }
            let r = &method.receiver;
            let tval = if r.is(ms_check::api::types::Builtin::Timestamp) {
                NativeType::Timestamp
            } else if r.is(ms_check::api::types::Builtin::Instant) {
                NativeType::Instant
            } else if r.is(ms_check::api::types::Builtin::Duration) {
                NativeType::Duration
            } else if r.is_std(syms, "Decimal") {
                NativeType::Decimal
            } else {
                continue;
            };
            let entry = &mut table[slot(tval)];
            if entry.is_none() {
                *entry = callables.get(&(method.module, decl.id())).cloned();
            }
        }
        NativeOps { table }
    }
}

impl Cx {
    /// The function of the `Comparable` method of native type `r`, if its `.ms` declaration has one.
    pub(crate) fn native_method(
        &mut self,
        m: &mut Module,
        r: NativeType,
    ) -> Result<Option<FuncId>, crate::Error> {
        let Some(callable) = self.native_ops.table[slot(r)].clone() else {
            return Ok(None);
        };
        Ok(Some(self.function_for(
            m,
            &callable,
            &ms_check::api::types::Subst::default(),
        )?))
    }
}

impl crate::func::FnLower<'_> {
    /// `a.compare(b)` of a native type that orders itself, through the `compare` method its
    /// `.ms` declaration defines; `None` for any other type.
    pub(crate) fn native_compare(
        &mut self,
        t: MTy,
        a: ms_mir::ir::Value,
        b: ms_mir::ir::Value,
    ) -> Result<Option<ms_mir::ir::Value>, crate::Error> {
        let Some(tval) = native_type(self.b.m, t).filter(|r| has_declared_order(*r)) else {
            return Ok(None);
        };
        let Some(f) = self.cx.native_method(self.b.m, tval)? else {
            return Ok(None);
        };
        Ok(Some(self.b.call(f, &[a, b])))
    }
}
