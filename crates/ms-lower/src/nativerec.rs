//! Identity of the plain-data native records whose operations the runtime implements.

use ms_mir::ir::Module;
use ms_mir::types::{Ty as MTy, TyKind};

/// A native record type known by identity instead of by repeated name tests.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum NativeRec {
    Timestamp,
    Instant,
    Decimal,
    Duration,
}

impl NativeRec {
    /// The native record `t` is, if any.
    pub(crate) fn of(m: &Module, t: MTy) -> Option<NativeRec> {
        let TyKind::Rec(rid) = m.types.kind(t) else {
            return None;
        };
        match m.records[rid.index()].name.as_str() {
            "Timestamp" => Some(NativeRec::Timestamp),
            "Instant" => Some(NativeRec::Instant),
            "Decimal" => Some(NativeRec::Decimal),
            "Duration" => Some(NativeRec::Duration),
            _ => None,
        }
    }

    /// The runtime function ordering two values (`-1`, `0` or `1`).
    pub(crate) fn compare_symbol(self) -> Option<&'static str> {
        match self {
            NativeRec::Timestamp => Some("msstd_time_timestamp_compare"),
            NativeRec::Instant => Some("msstd_time_instant_compare"),
            NativeRec::Decimal => Some("msstd_decimal_compare"),
            NativeRec::Duration => None,
        }
    }

    /// The runtime formatter, for records whose text is not their fields.
    pub(crate) fn text_symbol(self) -> Option<&'static str> {
        match self {
            NativeRec::Decimal => Some("msstd_decimal_to_string"),
            NativeRec::Timestamp => Some("msstd_time_timestamp_to_string"),
            _ => None,
        }
    }
}
