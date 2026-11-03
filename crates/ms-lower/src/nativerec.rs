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

/// The runtime function ordering two values (`-1`, `0` or `1`).
pub(crate) fn compare_symbol(r: NativeRec) -> Option<&'static str> {
    match r {
        NativeRec::Timestamp => Some("msstd_time_timestamp_compare"),
        NativeRec::Instant => Some("msstd_time_instant_compare"),
        NativeRec::Decimal => Some("msstd_decimal_compare"),
        NativeRec::Duration => None,
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
