//! Structural type keys that the tests compare; the checker itself never needs them.

use crate::types::{Kind, Ty};

// A key identifying a type's structure.
pub(crate) fn type_key(syms: ms_syntax::Names, t: &Ty) -> String {
    let mut key = String::new();
    write_type_key(syms, &mut key, t, false);
    key
}

// `type_key` plus which function parameters are represented as optionals.
pub(crate) fn lowering_key(syms: ms_syntax::Names, t: &Ty) -> String {
    let mut key = String::new();
    write_type_key(syms, &mut key, t, true);
    key
}

fn write_type_key(syms: ms_syntax::Names, key: &mut String, t: &Ty, lifted: bool) {
    key.push_str(syms.str(t.id));
    if t.kind == Kind::Function {
        for p in &t.params {
            key.push('[');
            if p.mutable {
                key.push_str("var ");
            }
            write_type_key(syms, key, &p.ty, lifted);
            if lifted && t.is_lifted(p.name) {
                key.push('=');
            }
            key.push(']');
        }
        key.push_str("[result:");
        if let Some(r) = &t.result {
            write_type_key(syms, key, r, lifted);
        }
        key.push(']');
    }
    for a in &t.args {
        key.push('[');
        write_type_key(syms, key, a, lifted);
        key.push(']');
    }
}
