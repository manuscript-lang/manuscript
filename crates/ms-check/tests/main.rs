//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod call_chains;
mod callable_identity;
mod error_values;
mod follow_on_errors;
mod generic_recursion;
mod golden;
mod impl_parameter_names;
mod import_collision;
mod list_methods;
mod match_patterns;
mod module_exports;
mod opaque_cases;
mod optional_result_return;
mod ownership;
mod promise_fixes;
mod subcodes;
mod type_display;
mod wrapper_passthrough;
