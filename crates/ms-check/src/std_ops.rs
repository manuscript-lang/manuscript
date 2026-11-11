//! Facts about the standard collections and builders that the effect scan and the ownership
//! walk both read: which methods change their receiver, which can discard an entry, which types
//! are text builders. A foundation module: it names only types, never a later stage.

use crate::types::*;

/// Whether a standard collection method mutates its receiver: `List`, `Map` and `Set`
/// methods say so with `var fn` in their `@std` declaration; so do `StringBuilder` and `BytesBuilder`.
pub fn collection_mutation(syms: ms_syntax::Names, method: &Method) -> bool {
    let receiver = &method.receiver;
    (receiver.is(Builtin::List)
        || receiver.is(Builtin::Map)
        || receiver.is(Builtin::Set)
        || is_text_builder(syms, receiver))
        && method
            .decl
            .as_ref()
            .and_then(|d| d.method())
            .is_some_and(|m| m.mutating)
}

/// Whether the mutator `name` can discard an entry the receiver holds (`set`, `add`, `remove`,
/// `clear`, `splice`). A direct call closes a resource entry it discards; a method value cannot,
/// so the checker rejects one over one-owner elements and lowering closes only at the call.
pub fn discards_entries(name: &str) -> bool {
    matches!(name, "set" | "add" | "remove" | "clear" | "splice")
}

/// `StringBuilder` and `BytesBuilder`: owned values whose `build` moving_params them.
pub fn is_text_builder(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.is_std(syms, "StringBuilder") || t.is(Builtin::BytesBuilder)
}
