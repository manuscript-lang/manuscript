//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod bench_inputs;
mod bidi;
mod bracket_speculation;
mod comments;
mod corpus;
mod crlf_interpolation_positions;
mod enums;
mod format_comments;
mod format_edits;
mod grouped_imports;
mod interpolation_positions;
mod lambda_hints;
mod lexer_spans;
mod logical_fixes;
mod multiline;
mod mutation;
mod nested_text;
mod receiver_methods;
mod recovery_blanking;
mod recovery_comments;
mod recovery_declarations;
mod recovery_diagnostics;
mod type_suffix;
