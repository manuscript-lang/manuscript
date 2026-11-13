//! The natives whose result points into their receiver. This is the only place a method name
//! decides ownership: the checker reads it for bindings, returns and overlap, and lowering reads
//! the checker's `borrowed_reads` fact instead of matching names again. A method written in
//! Manuscript never comes here; its body is analysed (`ResultBorrow`).

use crate::types::{Builtin, Ty};

/// How a native call's result relates to its receiver.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NativeBorrow {
    /// `xs.get(i)` on a `List`: the element itself.
    ListGet,
    /// `m.get(k)` on a `Map`: an `Optional` view of the entry.
    MapGet,
    /// `get()` on an `Optional` or `Result`: its payload.
    PayloadGet,
    /// `view`, `split`, `lines`, `chars`, `keys`, `values`, `slice`: a new value whose parts
    /// borrow the receiver. Keeping it takes `.clone()`.
    Derived,
}

/// The borrow a call of `name` with `args` arguments on a receiver of type `recv` returns, if any.
pub fn native_borrow(recv: &Ty, name: &str, args: usize) -> Option<NativeBorrow> {
    use NativeBorrow::*;
    Some(match (name, args) {
        ("get", 1) if recv.is(Builtin::Map) => MapGet,
        ("get", 1) if recv.is(Builtin::List) => ListGet,
        ("get", 0) if recv.is(Builtin::Optional) || recv.is(Builtin::Result) => PayloadGet,
        ("view", 2) if recv.is(Builtin::Bytes) || recv.is_string() => Derived,
        ("split", 1 | 2) | ("lines", 0) | ("chars", 0) if recv.is_string() => Derived,
        ("keys" | "values", 0) if recv.is(Builtin::Map) => Derived,
        // A slice borrows only elements that own nothing: iterating it by value drops each
        // element, which would free what the receiver still holds.
        ("slice", 2)
            if recv.is(Builtin::List)
                && recv
                    .args
                    .first()
                    .and_then(|a| a.builtin)
                    .is_some_and(|b| b.is_int() || b.is_float() || b == Builtin::Bool) =>
        {
            Derived
        }
        _ => return None,
    })
}
