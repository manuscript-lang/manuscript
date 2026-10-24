//! Editor overlays: unsaved file contents keyed by path.

use std::collections::BTreeMap;

use crate::project::error::ProjectError;
use crate::project::paths::source_path;

/// Unsaved editor contents keyed by path (sorted, so iteration is deterministic).
pub type Overlay = BTreeMap<String, String>;

/// Canonicalize editor snapshots exactly as filesystem reads and imports are
/// canonicalized, so two spellings of one file cannot select conflicting
/// content. Documents outside the project never enter its module graph.
pub fn canonical_overlay(root: &str, overlay: &Overlay) -> Result<Overlay, ProjectError> {
    let mut normalized = Overlay::new();
    for (filename, source) in overlay {
        let Ok(canonical) = source_path(root, filename, overlay) else {
            continue;
        };
        if let Some(previous) = normalized.get(&canonical)
            && previous != source
        {
            return Err(ProjectError::msg(format!(
                "conflicting editor overlays for {canonical}; two spellings of one path carry different unsaved contents, so send a single snapshot per file"
            )));
        }
        normalized.insert(canonical, source.clone());
    }
    Ok(normalized)
}
