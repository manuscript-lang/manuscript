//! How the loader sorts a bundled module, shared with `build.rs`, which uses it to choose the modules that load
//! on first import. It depends on `ms_syntax` only.

use ms_syntax::ast::{Decl, DeclKind, Module};

/// Bundled source modules whose methods extend native standard types in every program.
pub const EXTENSION_MODULES: [&str; 5] = [
    "@std/collections/collections.ms+source",
    "@std/bytes.ms+source",
    "@std/collections/ordering.ms",
    "@std/string.ms+source",
    "@std/math/decimal.ms",
];

/// Whether a declaration carries an implementation (a body, an `extern fn`, a constant or a test).
pub fn decl_has_body(d: &Decl) -> bool {
    match &d.kind {
        DeclKind::Fn(f) => !f.body.is_empty() || f.external,
        DeclKind::Const(_) | DeclKind::Alias(_) => true,
        DeclKind::Test(t) => !t.body.is_empty(),
        DeclKind::Impl(i) => i.methods.iter().any(|m| !m.func.body.is_empty()),
        DeclKind::Type(_) | DeclKind::Alternative(_) | DeclKind::Interface(_) => false,
    }
}

/// Whether a file declares native operations (a bodiless inherent `impl`) and also has bodies; the loader
/// splits it into a native half and a `+source` half.
pub fn is_mixed(module: &Module) -> bool {
    let bodyless_inherent = |d: &Decl| {
        matches!(&d.kind, DeclKind::Impl(i) if i.contract.is_none()
            && i.methods.iter().any(|m| m.func.body.is_empty()))
    };
    module.decls.iter().any(bodyless_inherent) && module.decls.iter().any(decl_has_body)
}

/// Whether a module is pure source: it has bodies, no native half and no `extern type`. Loading one only
/// records it, so it can wait until a program imports it.
pub fn is_pure_source(module: &Module) -> bool {
    !is_mixed(module)
        && module.decls.iter().any(decl_has_body)
        && !module
            .decls
            .iter()
            .any(|d| matches!(&d.kind, DeclKind::Type(r) if r.external))
}
