//! Shared traversal helpers.

use ms_check::ModuleData;
use ms_syntax::visit::{Visitor, walk_decl};

/// Walks every declaration of a module in source order.
pub fn walk_module<V: Visitor>(module: &ModuleData, v: &mut V) {
    for decl in &module.decls {
        walk_decl(v, decl.decl());
    }
}
