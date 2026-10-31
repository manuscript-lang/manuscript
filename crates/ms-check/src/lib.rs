//! The Manuscript type checker over the `ms-syntax` tree.
//!
//! Facts live in per-module side tables indexed by node id, not on the tree
//! (see [`syntax::Facts`]). Types are [`types::Ty`], reference-counted and
//! immutable apart from a type variable's bounds and default.

pub mod callbacks;
pub mod calls;
pub mod checker;
pub mod constants;
pub mod constfaults;
pub mod contracts;
pub mod editor;
pub mod effects;
pub mod exprs;
pub mod hints;
pub mod hir;
pub mod inference;
pub mod native;
pub mod native_defaults;
pub mod ownership;
pub mod passes;
pub mod prelude_imports;
pub mod receivers;
pub mod recursion;
pub mod stdlib;
pub mod stmts;
pub mod suggestions;
pub mod syntax;
pub mod types;
mod unused;

#[cfg(test)]
mod generic_defaults_tests;
#[cfg(test)]
mod operation_bounds_tests;
#[cfg(test)]
mod record_fields_tests;

pub use checker::{CheckOptions, ImportMap, Program, TestFixture, self_variable};
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
    let mut program = checker.check_modules(modules, bundled);
    if program.diagnostics.is_empty() {
        // Value semantics is part of the language: every program that type checks is also
        // checked for ownership and exclusivity.
        let own = program.hir().ownership();
        program.borrows = Rc::new(own.borrows);
        program.implicit_closes = Rc::new(own.closes);
        program.explicit_closes = Rc::new(own.explicit_closes);
        program.close_moves = Rc::new(own.close_moves);
        program.resource_moves = Rc::new(own.resource_moves);
        program.moved_payloads = Rc::new(own.moved_payloads);
        program.borrowed_captures = Rc::new(own.borrowed_captures);
        program.consumes = Rc::new(own.consumes);
        program.diagnostics.extend(own.diagnostics);
    }
    if program.diagnostics.is_empty() {
        program.diagnostics.extend(unused::check(&program));
    }
    program
}
