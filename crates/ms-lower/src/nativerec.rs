//! Operations of the plain-data native records, by identity.

use ms_mir::ir::Module;
use ms_mir::types::{NativeRec, Ty as MTy, TyKind};

/// The native record `t` is, if any; lowering sets it on the record when it declares it.
pub(crate) fn native_rec(m: &Module, t: MTy) -> Option<NativeRec> {
    let TyKind::Rec(rid) = m.types.kind(t) else {
        return None;
    };
    m.records[rid.index()].native
}

impl crate::func::FnLower<'_> {
    /// `a.compare(b)` of a native record that orders itself (`Timestamp`, `Instant`,
    /// `Decimal`), through the `compare` method its `.ms` declaration defines; `None` for any
    /// other type.
    pub(crate) fn native_compare(
        &mut self,
        t: MTy,
        a: ms_mir::ir::Value,
        b: ms_mir::ir::Value,
    ) -> Result<Option<ms_mir::ir::Value>, crate::Error> {
        if !matches!(
            native_rec(self.b.m, t),
            Some(NativeRec::Timestamp | NativeRec::Instant | NativeRec::Decimal)
        ) {
            return Ok(None);
        }
        let Some(ty) = self.cx.source_tys.get(&t).cloned() else {
            return Ok(None);
        };
        let key = ms_check::types::type_key(&ty);
        let Some(method) = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.decl.as_ref().is_some_and(|d| d.name() == "compare")
                    && ms_check::types::type_key(&m.receiver) == key
            })
            .cloned()
        else {
            return Ok(None);
        };
        let callable =
            self.callable_of_decl(method.module, method.decl.as_ref().map(|d| d.id()))?;
        let f = self
            .cx
            .function_for(self.b.m, &callable, &ms_check::types::Subst::new())?;
        Ok(Some(self.b.call(f, &[a, b])))
    }
}

/// The runtime formatter, for records whose text is not their fields.
pub(crate) fn text_symbol(r: NativeRec) -> Option<&'static str> {
    match r {
        NativeRec::Decimal => Some("msstd_decimal_to_string"),
        NativeRec::Timestamp => Some("msstd_time_timestamp_to_string"),
        _ => None,
    }
}
