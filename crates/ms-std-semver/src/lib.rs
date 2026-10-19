//! `@std/semver.ms` natives: a port of `pkg/runtime/semver.go`.
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use core::cmp::Ordering;

/// The `Version` record of `@std/semver.ms`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Version {
    pub major: i64,
    pub minor: i64,
    pub patch: i64,
    pub prerelease: Vec<String>,
    pub build: Vec<String>,
}

/// The `SemverError` cases.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SemverFail {
    InvalidData,
    OutOfRange,
}

impl SemverFail {
    /// The status byte returned across the C ABI.
    pub fn status(self) -> u8 {
        match self {
            SemverFail::InvalidData => ms_rt_abi::STATUS_INVALID_DATA,
            SemverFail::OutOfRange => ms_rt_abi::STATUS_OUT_OF_RANGE,
        }
    }
}

fn numeric(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}

fn identifier(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
}

fn leading_zero(s: &str) -> bool {
    s.len() > 1 && s.starts_with('0')
}

/// Parses strict Semantic Versioning 2.0.0 text.
pub fn parse(text: &str) -> Result<Version, SemverFail> {
    let (rest, build) = split_once(text, '+');
    let (core, pre) = split_once(rest, '-');
    let mut parts = core.split('.');
    let (Some(a), Some(b), Some(c), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(SemverFail::InvalidData);
    };
    let mut numbers = [0i64; 3];
    let mut out_of_range = false;
    for (n, part) in numbers.iter_mut().zip([a, b, c]) {
        if !numeric(part) || leading_zero(part) {
            return Err(SemverFail::InvalidData);
        }
        match part.parse() {
            Ok(v) => *n = v,
            Err(_) => out_of_range = true,
        }
    }
    let mut prerelease = Vec::new();
    if let Some(pre) = pre {
        for id in pre.split('.') {
            if !identifier(id) || (numeric(id) && leading_zero(id)) {
                return Err(SemverFail::InvalidData);
            }
            prerelease.push(id.into());
        }
    }
    let mut build_ids = Vec::new();
    if let Some(build) = build {
        for id in build.split('.') {
            if !identifier(id) {
                return Err(SemverFail::InvalidData);
            }
            build_ids.push(id.into());
        }
    }
    if out_of_range {
        return Err(SemverFail::OutOfRange);
    }
    Ok(Version {
        major: numbers[0],
        minor: numbers[1],
        patch: numbers[2],
        prerelease,
        build: build_ids,
    })
}

fn split_once(s: &str, sep: char) -> (&str, Option<&str>) {
    match s.split_once(sep) {
        Some((a, b)) => (a, Some(b)),
        None => (s, None),
    }
}

/// Formats a version as `major.minor.patch[-prerelease][+build]`.
pub fn format(v: &Version) -> String {
    use core::fmt::Write;
    let mut s = String::new();
    let _ = write!(s, "{}.{}.{}", v.major, v.minor, v.patch);
    if !v.prerelease.is_empty() {
        s.push('-');
        s.push_str(&v.prerelease.join("."));
    }
    if !v.build.is_empty() {
        s.push('+');
        s.push_str(&v.build.join("."));
    }
    s
}

fn compare_identifier(a: &str, b: &str) -> Ordering {
    match (numeric(a), numeric(b)) {
        // Equal-length digit strings without leading zeros compare lexically.
        (true, true) => a.len().cmp(&b.len()).then_with(|| a.cmp(b)),
        (true, false) => Ordering::Less,
        (false, true) => Ordering::Greater,
        (false, false) => a.cmp(b),
    }
}

/// Compares two versions by precedence, returning -1, 0 or 1; build metadata is ignored.
pub fn compare(left: &Version, right: &Version) -> i64 {
    let ord = (left.major, left.minor, left.patch)
        .cmp(&(right.major, right.minor, right.patch))
        .then_with(
            || match (left.prerelease.is_empty(), right.prerelease.is_empty()) {
                (true, true) => Ordering::Equal,
                (true, false) => Ordering::Greater,
                (false, true) => Ordering::Less,
                (false, false) => left
                    .prerelease
                    .iter()
                    .zip(&right.prerelease)
                    .map(|(a, b)| compare_identifier(a, b))
                    .find(|o| o.is_ne())
                    .unwrap_or_else(|| left.prerelease.len().cmp(&right.prerelease.len())),
            },
        );
    ord as i64
}
