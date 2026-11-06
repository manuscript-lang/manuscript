//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod analysis_invalidation;
mod completion;
mod completion_contexts;
mod document_updates;
mod editing_regressions;
mod editor_sessions;
mod enum_declarations;
mod hover_fallback;
mod inlay_names;
mod match_cases;
mod name_recycling;
mod navigation_identity;
mod opaque_completion;
mod recovery_navigation;
mod reference_order;
mod search_symbol;
mod semantic_positions;
mod signature_help;
mod snapshots;
mod source_coordinates;
mod supervise;
mod support;
