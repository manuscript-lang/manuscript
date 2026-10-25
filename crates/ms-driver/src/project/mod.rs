//! Manuscript project manifests and confined source-path resolution.
//!
//! This crate owns project manifests, module paths and diagnostics. It has
//! no dependency on parsing, checking or code generation. Paths are `String`s
//! using Go's `path/filepath` lexical rules (see [`pathops`]), with native Windows
//! volumes and separators. Unix error values render in the established
//! wording, so existing diagnostics do not change.
//!
//! Entry points:
//!
//! * [`find_manifest`] - the nearest containing `ms.toml`, even if invalid.
//! * [`read_project`] / [`read_project_partial`] - validate the supported
//!   `ms.toml` subset (`[project]`, `[aliases]`) and canonicalize its paths.
//! * [`resolve_import`] / [`source_path`] - confined, symlink-canonical import
//!   resolution with optional editor overlays.
//! * [`canonical_overlay`] - canonicalize unsaved editor snapshots.
//! * [`discover_modules`] / [`discover_modules_with_overlay`] - test and source
//!   module discovery.
//!
//! `ms.lock` handling and build-cache file locks belong to the build driver, not here.

pub mod discovery;
pub mod error;
pub mod manifest;
pub mod overlay;
pub mod pathops;
pub mod paths;
pub mod quoting;

pub use discovery::{discover_modules, discover_modules_with_overlay};
pub use error::{Location, ManifestError, PathError, ProjectError};
pub use manifest::{Assignment, Project, find_manifest, read_project, read_project_partial};
pub use overlay::{Overlay, canonical_overlay};
pub use paths::{resolve_import, source_path};
