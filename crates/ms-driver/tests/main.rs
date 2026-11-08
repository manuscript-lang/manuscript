//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod common;
mod export_names;
mod import_hints;
mod load;
mod mutation;
mod project_directory_links;
mod project_discovery;
mod project_filenames;
mod project_library;
mod project_project;
mod project_windows_paths;
mod watch_inputs;
