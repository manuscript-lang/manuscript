//! Operations of the plain-data native records, by identity. The runtime function behind each
//! is whatever the record's `.ms` declaration calls; lowering calls the declared method.

use crate::cx::Cx;
use ms_check::Program;
use ms_check::api::NodeId;
use ms_check::api::hir::Callable;
use ms_check::api::types::Name;
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{NativeRec, Ty as MTy, TyKind};
use std::collections::HashMap;
use std::rc::Rc;

/// The native record `t` is, if any; lowering sets it on the record when it declares it.
pub(crate) fn native_rec(m: &Module, t: MTy) -> Option<NativeRec> {
    let TyKind::Rec(rid) = m.types.kind(t) else {
        return None;
    };
    m.records[rid.index()].native
}

/// Whether the record's text is the `to_string` its declaration defines rather than its fields.
pub(crate) fn has_declared_text(r: NativeRec) -> bool {
    matches!(r, NativeRec::Timestamp | NativeRec::Decimal)
}

/// Whether the record orders itself through the `compare` its declaration defines.
pub(crate) fn has_declared_order(r: NativeRec) -> bool {
    matches!(
        r,
        NativeRec::Timestamp | NativeRec::Instant | NativeRec::Decimal
    )
}

/// The operations of a native record that lowering calls through its `.ms` declaration.
#[derive(Clone, Copy)]
pub(crate) enum NativeOp {
    Compare,
    ToString,
}

const NATIVE_RECS: usize = 4;
const NATIVE_OPS: usize = 2;

fn slot(r: NativeRec, op: NativeOp) -> usize {
    let rec = match r {
        NativeRec::Timestamp => 0,
        NativeRec::Instant => 1,
        NativeRec::Decimal => 2,
        NativeRec::Duration => 3,
    };
    rec * NATIVE_OPS + op as usize
}

/// A flat table of the declared `compare` and `to_string` methods, indexed by record and operation.
pub struct NativeOps {
    table: [Option<Rc<Callable>>; NATIVE_RECS * NATIVE_OPS],
}

impl NativeOps {
    pub(crate) fn new(
        syms: ms_check::api::Names,
        program: &Program,
        callables: &HashMap<(Name, NodeId), Rc<Callable>>,
    ) -> NativeOps {
        let mut table: [Option<Rc<Callable>>; NATIVE_RECS * NATIVE_OPS] = Default::default();
        for method in &program.methods {
            let Some(decl) = method.decl.as_ref() else {
                continue;
            };
            let op = match syms.str(decl.name()) {
                "compare" => NativeOp::Compare,
                "to_string" => NativeOp::ToString,
                _ => continue,
            };
            let r = &method.receiver;
            let rec = if r.is(ms_check::api::types::Builtin::Timestamp) {
                NativeRec::Timestamp
            } else if r.is(ms_check::api::types::Builtin::Instant) {
                NativeRec::Instant
            } else if r.is(ms_check::api::types::Builtin::Duration) {
                NativeRec::Duration
            } else if r.is_std(syms, "Decimal") {
                NativeRec::Decimal
            } else {
                continue;
            };
            let entry = &mut table[slot(rec, op)];
            if entry.is_none() {
                *entry = callables.get(&(method.module, decl.id())).cloned();
            }
        }
        NativeOps { table }
    }
}

impl Cx {
    /// The function of the declared `op` of native record `r`, if its `.ms` declaration has one.
    pub(crate) fn native_method(
        &mut self,
        m: &mut Module,
        r: NativeRec,
        op: NativeOp,
    ) -> Result<Option<FuncId>, crate::Error> {
        let Some(callable) = self.native_ops.table[slot(r, op)].clone() else {
            return Ok(None);
        };
        Ok(Some(self.function_for(
            m,
            &callable,
            &ms_check::api::types::Subst::new(),
        )?))
    }
}

impl crate::func::FnLower<'_> {
    /// `a.compare(b)` of a native record that orders itself, through the `compare` method its
    /// `.ms` declaration defines; `None` for any other type.
    pub(crate) fn native_compare(
        &mut self,
        t: MTy,
        a: ms_mir::ir::Value,
        b: ms_mir::ir::Value,
    ) -> Result<Option<ms_mir::ir::Value>, crate::Error> {
        let Some(rec) = native_rec(self.b.m, t).filter(|r| has_declared_order(*r)) else {
            return Ok(None);
        };
        let Some(f) = self.cx.native_method(self.b.m, rec, NativeOp::Compare)? else {
            return Ok(None);
        };
        Ok(Some(self.b.call(f, &[a, b])))
    }
}
