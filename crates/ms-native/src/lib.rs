//! One static library for compiled programs.
//!
//! Each `ms-std-*` crate exports `msstd_*` C symbols and `ms-rt` exports the `msrt_*` runtime. A
//! program links a single archive, because a second Rust staticlib would repeat the Rust runtime's
//! own symbols. A new `ms-std-*` crate joins the archive by being listed in `Cargo.toml` and below.
extern crate ms_rt;
extern crate ms_std_archive;
extern crate ms_std_core;
extern crate ms_std_fs;
extern crate ms_std_json;
extern crate ms_std_net;
extern crate ms_std_process;
extern crate ms_std_table;

/// Rust-side allocations of the native standard library share the runtime's allocator.
#[global_allocator]
static HEAP: ms_rt::alloc::StdHeap = ms_rt::alloc::StdHeap;

#[cfg(all(feature = "entry", target_os = "linux", target_env = "gnu"))]
mod entry;
