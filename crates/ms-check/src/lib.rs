//! The Manuscript type checker over the `ms-syntax` tree.
//!
//! Facts live in per-module side tables indexed by node id, not on the tree
//! (see [`syntax::Facts`]). Types are [`types::Ty`], reference-counted and
//! immutable apart from a type variable's bounds and default.

mod bundled;
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
pub mod recursion;
pub mod stdlib;
pub mod stmts;
pub mod suggestions;
pub mod syntax;
pub mod types;
pub mod tytable;
mod unused;

#[cfg(test)]
mod generic_defaults_tests;
#[cfg(test)]
mod record_fields_tests;
#[cfg(test)]
mod type_argument_defaults_tests;
#[cfg(test)]
mod type_graph_tests;
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
    let (decls, errors, node_count) = passes::desugar_inherent_impls(syms, m);
    let decls: Vec<DeclRef> = decls.into_iter().map(DeclRef::new).collect();
    let mut data = ModuleData::new(m, decls, node_count);
    data.inherent = errors
        .into_iter()
        .map(|e| Diagnostic {
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
        let own = program.hir().ownership(syms);
        program.close_moves = Rc::new(own.close_moves);
        program.resource_moves = Rc::new(own.resource_moves);
        program.moves = Rc::new(own.moves);
        program.borrowed_captures = Rc::new(own.borrowed_captures);
        program.moving_params = Rc::new(own.moving_params);
        program.node_facts = Rc::new(own.node_facts);
        program.binding_facts = Rc::new(own.binding_facts);
        program.owned_borrows = Rc::new(own.owned_borrows);
        program.getter_borrows = Rc::new(own.getter_borrows);
        program.diagnostics.extend(own.diagnostics);
    }
    if program.diagnostics.is_empty() {
        program.diagnostics.extend(unused::check(syms, &program));
    }
    program
}
