//! One static library for compiled programs.
//!
//! Each `ms-std-*` crate exports `msstd_*` C symbols and `ms-rt` exports the `msrt_*` runtime. A
//! program links a single archive, because a second Rust staticlib would repeat the Rust runtime's
//! own symbols. A new `ms-std-*` crate joins the archive by being listed in `Cargo.toml` and below.
extern crate ms_rt;
extern crate ms_std_archive;
extern crate ms_std_bigint;
extern crate ms_std_compress;
extern crate ms_std_core;
extern crate ms_std_crypto;
extern crate ms_std_csv;
extern crate ms_std_decimal;
extern crate ms_std_encoding;
extern crate ms_std_fs;
extern crate ms_std_html;
extern crate ms_std_io;
extern crate ms_std_json;
extern crate ms_std_log;
extern crate ms_std_math;
extern crate ms_std_net;
extern crate ms_std_path;
extern crate ms_std_process;
extern crate ms_std_random;
extern crate ms_std_regex;
extern crate ms_std_rt;
extern crate ms_std_semver;
extern crate ms_std_time;
extern crate ms_std_url;
