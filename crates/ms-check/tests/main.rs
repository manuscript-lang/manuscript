//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod call_chains;
mod callable_identity;
mod callback_identity;
mod constant_index;
mod control_flow;
mod diagnostic_wording;
mod error_values;
mod follow_on_errors;
mod generic_recursion;
mod golden;
mod impl_parameter_names;
mod import_collision;
mod list_methods;
mod long_chains;
mod match_patterns;
mod member_names;
mod module_exports;
mod opaque_cases;
mod optional_result_return;
mod ownership;
mod prelude_import_fixes;
mod promise_fixes;
mod subcodes;
mod type_display;
mod wrapper_passthrough;
