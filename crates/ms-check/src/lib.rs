//! The Manuscript type checker over the `ms-syntax` tree.
//!
//! Facts live in per-module side tables indexed by node id, not on the tree
//! (see [`syntax::Facts`]). Types are [`types::Ty`], reference-counted and
//! immutable apart from a type variable's bounds and default.

pub mod api;
mod bundled;
mod callbacks;
mod calls;
mod checker;
mod constants;
mod constfaults;
mod contracts;
mod editor;
mod effect_directives;
mod effect_reach;
mod effects;
mod exprs;
pub mod fxmap;
mod hints;
mod hir;
mod inference;
mod native;
mod native_defaults;
mod ownership;
mod passes;
mod prelude_imports;
mod recursion;
mod std_ops;
mod stdlib;
mod stmts;
mod suggestions;
mod syntax;
mod types;
mod tytable;
mod unused;

#[cfg(test)]
mod diagnostic_cascade_tests;
#[cfg(test)]
mod generic_defaults_tests;
#[cfg(test)]
mod radix_literal_tests;
#[cfg(test)]
mod type_argument_defaults_tests;
#[cfg(test)]
mod type_classification_tests;
#[cfg(test)]
mod type_fields_tests;
#[cfg(test)]
mod type_graph_tests;
#[cfg(test)]
mod type_keys;
#[cfg(test)]
mod type_substitution_tests;
#[cfg(test)]
mod tytable_tests;

pub use checker::{CheckOptions, ImportMap, Program, TestFixture, self_variable};
pub use stdlib::Session;
pub use syntax::{ModRef, ModuleData};

use ms_syntax::ast::Module;
use ms_syntax::{Diagnostic, Phase};
use std::rc::Rc;
use syntax::DeclRef;

/// Wraps a parsed module for checking: desugars inherent `impl Type:` blocks
/// and allocates the fact tables.
pub fn load_module(syms: ms_syntax::Names, m: &Module) -> ModRef {
    load_module_with(syms, m, &[])
}

/// Like [`load_module`], for a module whose receiver methods also name `foreign` types that another
/// module declares (the native half of a bundled file).
pub fn load_module_with(
    syms: ms_syntax::Names,
    m: &Module,
    foreign: &[ms_syntax::ast::Decl],
) -> ModRef {
    let (decls, errors, node_count) = passes::desugar_inherent_impls(syms, m, foreign);
    let decls: Vec<DeclRef> = decls.into_iter().map(DeclRef::new).collect();
    let mut data = ModuleData::new(m, decls, node_count);
    data.inherent = errors
        .into_iter()
        .map(|e| Diagnostic {
            cause: Default::default(),
            opener_line: 0,
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
pub fn check(
    syms: ms_syntax::Names,
    modules: Vec<ModRef>,
    imports: ImportMap,
    options: CheckOptions,
) -> Program {
    check_in(syms, &Session::new(), modules, imports, options)
}

/// Like [`check`], against a session the caller keeps, so the standard library loads once.
pub fn check_in(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    modules: Vec<ModRef>,
    imports: ImportMap,
    options: CheckOptions,
) -> Program {
    session.ensure_standard();
    let mut checker = checker::Checker::new(session, &options);
    checker.imports = imports;
    let bundled = options.bundled;
    let mut program = checker.check_modules(modules, bundled);
    if program.diagnostics.is_empty() {
        // Value semantics is part of the language: every program that type checks is also
        // checked for ownership and exclusivity.
        let own = program.hir().ownership();
        program.ownership = Rc::new(own.tables);
        program.diagnostics.extend(own.diagnostics);
    }
    if program.diagnostics.is_empty() {
        program.diagnostics.extend(unused::check(syms, &program));
    }
    program
}
