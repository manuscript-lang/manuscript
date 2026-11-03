//! Operations of the plain-data native records, by identity. The runtime function behind each
//! is whatever the record's `.ms` declaration calls; lowering calls the declared method.

use crate::cx::Cx;
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{NativeRec, Ty as MTy, TyKind};

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

impl Cx {
    /// The function of the method `name` declared on the native record `t`, found through the
    /// checker type behind the MIR record.
    pub(crate) fn native_method(
        &mut self,
        m: &mut Module,
        t: MTy,
        name: &'static str,
    ) -> Result<Option<FuncId>, crate::Error> {
        if let Some(found) = self.native_methods.get(&(t, name)) {
            return Ok(*found);
        }
        let found = self.find_native_method(m, t, name)?;
        self.native_methods.insert((t, name), found);
        Ok(found)
    }

    fn find_native_method(
        &mut self,
        m: &mut Module,
        t: MTy,
        name: &str,
    ) -> Result<Option<FuncId>, crate::Error> {
        let Some(ty) = self.source_tys.get(&t).cloned() else {
            return Ok(None);
        };
        let key = ms_check::types::type_key(&ty);
        let Some(method) = self
            .methods
            .iter()
            .find(|im| {
                im.decl.as_ref().is_some_and(|d| d.name() == name)
                    && ms_check::types::type_key(&im.receiver) == key
            })
            .cloned()
        else {
            return Ok(None);
        };
        let id = method
            .decl
            .as_ref()
            .map(|d| d.id())
            .ok_or_else(|| crate::Error::new("method without declaration"))?;
        let callable = self
            .callables
            .get(&(method.module, id))
            .cloned()
            .ok_or_else(|| crate::Error::new("callee not found"))?;
        Ok(Some(self.function_for(
            m,
            &callable,
            &ms_check::types::Subst::new(),
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
        if !native_rec(self.b.m, t).is_some_and(has_declared_order) {
            return Ok(None);
        }
        let Some(f) = self.cx.native_method(self.b.m, t, "compare")? else {
            return Ok(None);
        };
        Ok(Some(self.b.call(f, &[a, b])))
    }
}
