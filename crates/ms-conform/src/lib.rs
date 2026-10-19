//! Conformance corpus runner for any `ms` binary.
//!
//! The corpus under `tests/conformance/fixtures` pairs Manuscript programs with
//! expectations recorded from the Go implementation (the oracle). This crate
//! discovers fixtures, observes what an `ms` binary does with them, compares the
//! observation with the recorded expectation, records new expectations, runs
//! differential fuzzing and benchmarks. See `tests/conformance/README.md`.

pub mod bench;
pub mod cli;
pub mod compare;
pub mod exec;
pub mod fixture;
pub mod fuzz;
pub mod harvest;
pub mod json;
pub mod observe;
pub mod record;
pub mod report;
pub mod runner;
