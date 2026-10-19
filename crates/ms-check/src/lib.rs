//! The Manuscript type checker: a port of `pkg/checker` over the `ms-syntax`
//! tree. The Go checker is the behavioural authority: diagnostics (message,
//! position, phase) are byte-identical.
//!
//! Facts live in per-module side tables indexed by node id, not on the tree
//! (see [`syntax::Facts`]). Types are [`types::Ty`], reference-counted and
//! immutable apart from a type variable's bounds and default.

pub mod callbacks;
pub mod calls;
pub mod checker;
pub mod constants;
pub mod contracts;
pub mod effects;
pub mod exprs;
pub mod hints;
pub mod inference;
pub mod json;
pub mod native;
pub mod native_defaults;
pub mod passes;
pub mod prelude_imports;
pub mod receivers;
pub mod recursion;
pub mod stdlib;
pub mod stmts;
pub mod syntax;
pub mod types;

pub use checker::{CheckOptions, ImportMap, Program, TestFixture};
pub use syntax::{ModRef, ModuleData};

use ms_syntax::ast::Module;
use ms_syntax::{Diagnostic, Phase};
use std::rc::Rc;
use syntax::DeclRef;

/// Wraps a parsed module for checking: desugars inherent `impl Type:` blocks
/// and allocates the fact tables.
pub fn load_module(m: &Module) -> ModRef {
    let (decls, errors, node_count) = passes::desugar_inherent_impls(m);
    let decls: Vec<DeclRef> = decls.into_iter().map(DeclRef::new).collect();
    let mut data = ModuleData::new(m, decls, node_count);
    data.inherent = errors
        .into_iter()
        .map(|e| Diagnostic {
            file: m.file.clone(),
            pos: e.pos,
            phase: Phase::Type,
            message: e.message,
            end: None,
            fix: None,
        })
        .collect();
    Rc::new(data)
}

/// Checks modules given in dependency order. `imports` resolves each local
/// import to the module it names.
pub fn check(modules: Vec<ModRef>, imports: ImportMap, options: CheckOptions) -> Program {
    stdlib::ensure_standard();
    let mut checker = checker::Checker::new(&options);
    checker.imports = imports;
    let bundled = options.bundled;
    checker.check_modules(modules, bundled)
}
