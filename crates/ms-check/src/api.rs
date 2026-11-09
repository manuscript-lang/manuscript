//! The only public surface of `ms-check`.
//!
//! Every other module in this crate is private. A sibling crate (lowering,
//! driver, tooling, language server) names a checker type or query here or not
//! at all. Adding a line below is the review point for widening the contract.
//!
//! Groups follow what a consumer asks for:
//! - [`types`]: the type language and symbol tables.
//! - [`hir`]: the checked program as lowering reads it.
//! - [`ownership`]: borrow and move facts attached to expressions.
//! - [`syntax`]: per-module data the checker keeps beside the tree.
//! - [`effects`], [`stdlib`], [`hints`], [`editor`]: focused queries.

pub mod types {
    pub use crate::types::{
        BindingRef, Builtin, Definition, EXTERN_ERROR_CODE, EXTERN_ERROR_MESSAGE, Kind, Method,
        MethodRef, Name, Operation, Param, Subst, Sym, SymKind, SymRef, Ty, bool_, case_of, cases,
        constructor_signature, contract_mutates, fields, float_bits, function, int_bits,
        invalid_ty, n, primitive, same, same_opt, show, sub, substitution, unify, variable_set,
    };
}

pub mod tytable {
    pub use crate::tytable::{TyId, TyTable};
}

pub mod hir {
    pub use crate::hir::{Body, CallView, Callable, CallableKind, ModuleHir, Resolution};
}

pub mod ownership {
    pub use crate::ownership::{
        Access, BindingFact, BindingFlags, BorrowKind, Class, Classifier, Fact, NodeFacts,
        OwnedBorrow, ParamMode, native_method_argument_modes,
    };
}

pub mod syntax {
    pub use crate::syntax::{DeclRef, FuncRef, Info, ModRef, ScopeState};
}

pub mod checker {
    pub use crate::checker::Names;
}

pub mod effects {
    pub use crate::effect_directives::matches;
    pub use crate::effect_reach::Violation;
    pub use crate::effects::{collection_mutation, discards_entries, is_text_builder};
}

pub mod stdlib {
    pub use crate::stdlib::{
        PRIMITIVE_NAMES, SOURCES, STANDARD_PRELUDE_NAMES, is_bundled_source, keeps_callbacks,
        module_stem,
    };
}

pub mod hints {
    pub use crate::hints::{edit_distance, import_hint, type_import_hint};
}

pub mod editor {
    pub use crate::editor::{MemberKind, members, prelude_type_names, standard_export_inventory};
}

// The syntax-tree vocabulary lowering walks. Re-exported so that a consumer of checked
// programs names the tree through the checker's contract, not through `ms-syntax` directly.
pub use ms_syntax::{Names, NodeId, Pos, number, visit};

pub mod ast {
    pub use ms_syntax::ast::*;
}
