//! Manuscript project manifests and confined source-path resolution.
//!
//! This crate is a behavior-exact port of the Go package `pkg/project`. It has
//! no dependency on parsing, checking or code generation. Paths are `String`s
//! using Go's `path/filepath` lexical rules (see [`gopath`]), with native Windows
//! volumes and separators. Unix error values render byte-for-byte like the Go
//! ones, so existing diagnostics do not change.
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
pub mod gopath;
pub mod manifest;
pub mod overlay;
pub mod paths;
pub mod strconv;

pub use discovery::{discover_modules, discover_modules_with_overlay};
pub use error::{Location, ManifestError, PathError, ProjectError};
pub use manifest::{Assignment, Project, find_manifest, read_project, read_project_partial};
pub use overlay::{Overlay, canonical_overlay};
pub use paths::{resolve_import, source_path};
