//! Semantic versions and the requirements a dependency names, as Cargo reads them.
//!
//! A version is `MAJOR.MINOR.PATCH` with an optional `-pre` suffix. A requirement is a version
//! of one to three numbers, optionally behind `^` (the default), `~` or `=`. Requirements that
//! could span incompatible releases (`^0`, `^0.0`) are rejected, so every requirement lies inside
//! one [`Bucket`] and one copy per bucket is enough.

use std::cmp::Ordering;
use std::fmt;

/// A version such as `1.4.2` or `1.0.0-rc.1`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
    /// The dot-separated pre-release identifiers, empty for a release.
    pub pre: Vec<String>,
}

impl Version {
    /// A version written `1.2.3` or `1.2.3-rc.1`, with no `v` and no build metadata.
    pub fn parse(text: &str) -> Result<Version, String> {
        let bad = || {
            format!(
                "{text:?} is not a version; write three numbers such as 1.2.3 (a suffix such as -rc.1 is allowed)"
            )
        };
        let (numbers, pre) = match text.split_once('-') {
            Some((numbers, pre)) => (numbers, Some(pre)),
            None => (text, None),
        };
        let parts: Vec<&str> = numbers.split('.').collect();
        let [major, minor, patch] = parts[..] else {
            return Err(bad());
        };
        let number = |part: &str| number(part).ok_or_else(bad);
        let pre = match pre {
            None => Vec::new(),
            Some(pre) => {
                let ids: Vec<String> = pre.split('.').map(str::to_string).collect();
                if !ids.iter().all(|id| identifier(id)) {
                    return Err(bad());
                }
                ids
            }
        };
        Ok(Version {
            major: number(major)?,
            minor: number(minor)?,
            patch: number(patch)?,
            pre,
        })
    }

    /// The version a git tag names: `v1.4.2` and `1.4.2` both name 1.4.2. A tag that is anything
    /// else names no version.
    pub fn of_tag(tag: &str) -> Option<Version> {
        Version::parse(tag.strip_prefix('v').unwrap_or(tag)).ok()
    }

    /// The compatibility class: versions in one bucket may share one copy.
    pub fn bucket(&self) -> Bucket {
        if self.major > 0 {
            Bucket::Major(self.major)
        } else if self.minor > 0 {
            Bucket::Minor(self.minor)
        } else {
            Bucket::Patch(self.patch)
        }
    }

    fn triple(&self) -> (u64, u64, u64) {
        (self.major, self.minor, self.patch)
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if !self.pre.is_empty() {
            write!(f, "-{}", self.pre.join("."))?;
        }
        Ok(())
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        self.triple().cmp(&other.triple()).then_with(|| {
            match (self.pre.is_empty(), other.pre.is_empty()) {
                (true, true) => Ordering::Equal,
                (true, false) => Ordering::Greater,
                (false, true) => Ordering::Less,
                (false, false) => compare_pre(&self.pre, &other.pre),
            }
        })
    }
}

fn compare_pre(a: &[String], b: &[String]) -> Ordering {
    for (x, y) in a.iter().zip(b) {
        let order = match (x.parse::<u64>(), y.parse::<u64>()) {
            (Ok(x), Ok(y)) => x.cmp(&y),
            (Ok(_), Err(_)) => Ordering::Less,
            (Err(_), Ok(_)) => Ordering::Greater,
            (Err(_), Err(_)) => x.cmp(y),
        };
        if order != Ordering::Equal {
            return order;
        }
    }
    a.len().cmp(&b.len())
}

/// A decimal number without a leading zero.
fn number(part: &str) -> Option<u64> {
    if part.is_empty() || (part.len() > 1 && part.starts_with('0')) {
        return None;
    }
    part.bytes()
        .all(|b| b.is_ascii_digit())
        .then(|| part.parse().ok())?
}

/// A pre-release identifier: ASCII letters, digits and `-`, and no leading zero when numeric.
fn identifier(id: &str) -> bool {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
        return false;
    }
    !(id.bytes().all(|b| b.is_ascii_digit()) && id.len() > 1 && id.starts_with('0'))
}

/// The versions that may share one copy: `1.x` for a major of 1 or more, `0.4.x` for a zero
/// major, and one exact version for `0.0.x`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Bucket {
    Major(u64),
    Minor(u64),
    Patch(u64),
}

impl fmt::Display for Bucket {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Bucket::Major(major) => write!(f, "{major}.x"),
            Bucket::Minor(minor) => write!(f, "0.{minor}.x"),
            Bucket::Patch(patch) => write!(f, "0.0.{patch}"),
        }
    }
}

/// The operator of a requirement.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Op {
    Caret,
    Tilde,
    Exact,
}

/// A requirement such as `^1.2`, `~1.2.3`, `=0.4.1` or `1.2` (which is `^1.2`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Requirement {
    pub op: Op,
    pub major: u64,
    pub minor: Option<u64>,
    pub patch: Option<u64>,
    pub pre: Vec<String>,
}

impl Requirement {
    pub fn parse(text: &str) -> Result<Requirement, String> {
        let bad = |why: &str| format!("{text:?} is not a version requirement: {why}");
        let (op, rest) = match text.as_bytes().first() {
            Some(b'^') => (Op::Caret, &text[1..]),
            Some(b'~') => (Op::Tilde, &text[1..]),
            Some(b'=') => (Op::Exact, &text[1..]),
            _ => (Op::Caret, text),
        };
        let (numbers, pre) = match rest.split_once('-') {
            Some((numbers, pre)) => (numbers, pre.split('.').map(str::to_string).collect()),
            None => (rest, Vec::new()),
        };
        if !pre.iter().all(|id: &String| identifier(id)) && !pre.is_empty() {
            return Err(bad("the suffix after - is not a pre-release name"));
        }
        let parts: Vec<Option<u64>> = numbers.split('.').map(number).collect();
        if parts.is_empty() || parts.len() > 3 || parts.iter().any(Option::is_none) {
            return Err(bad(
                "write one to three numbers such as 1, 1.2 or 1.2.3, with an optional ^, ~ or =",
            ));
        }
        let get = |i: usize| parts.get(i).copied().flatten();
        let requirement = Requirement {
            op,
            major: get(0).unwrap_or(0),
            minor: get(1),
            patch: get(2),
            pre,
        };
        if !requirement.pre.is_empty() && requirement.patch.is_none() {
            return Err(bad("a pre-release needs all three numbers"));
        }
        // A zero major makes the next number the compatibility boundary, so it must be there.
        if requirement.major == 0 && requirement.minor.is_none() {
            return Err(bad(
                "0 alone covers incompatible releases; write 0.4 or 0.4.1",
            ));
        }
        if requirement.major == 0 && requirement.minor == Some(0) && requirement.patch.is_none() {
            return Err(bad("0.0 alone covers incompatible releases; write 0.0.3"));
        }
        Ok(requirement)
    }

    /// The bucket every version this requirement accepts lies in.
    pub fn bucket(&self) -> Bucket {
        if self.major > 0 {
            Bucket::Major(self.major)
        } else if self.minor.unwrap_or(0) > 0 {
            Bucket::Minor(self.minor.unwrap_or(0))
        } else {
            Bucket::Patch(self.patch.unwrap_or(0))
        }
    }

    /// Whether `version` satisfies the requirement. A pre-release satisfies it only when the
    /// requirement names a pre-release.
    pub fn matches(&self, version: &Version) -> bool {
        if !version.pre.is_empty() && self.pre.is_empty() {
            return false;
        }
        if version.bucket() != self.bucket() {
            return false;
        }
        let floor = Version {
            major: self.major,
            minor: self.minor.unwrap_or(0),
            patch: self.patch.unwrap_or(0),
            pre: self.pre.clone(),
        };
        if *version < floor {
            return false;
        }
        match self.op {
            Op::Exact => match (self.minor, self.patch) {
                (Some(_), Some(_)) => *version == floor,
                (Some(minor), None) => version.minor == minor,
                _ => true,
            },
            Op::Tilde => self.minor.is_none_or(|minor| version.minor == minor),
            Op::Caret => {
                // Inside the bucket, a caret on a fully written 0.0.x is that one version.
                self.major != 0 || self.minor != Some(0) || *version == floor
            }
        }
    }
}

impl fmt::Display for Requirement {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let op = match self.op {
            Op::Caret => "^",
            Op::Tilde => "~",
            Op::Exact => "=",
        };
        write!(f, "{op}{}", self.major)?;
        if let Some(minor) = self.minor {
            write!(f, ".{minor}")?;
        }
        if let Some(patch) = self.patch {
            write!(f, ".{patch}")?;
        }
        if !self.pre.is_empty() {
            write!(f, "-{}", self.pre.join("."))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(text: &str) -> Version {
        Version::parse(text).unwrap()
    }
    fn r(text: &str) -> Requirement {
        Requirement::parse(text).unwrap()
    }

    #[test]
    fn versions_have_three_numbers_and_an_optional_pre_release() {
        for good in ["1.2.3", "0.0.0", "2026.11.0", "1.0.0-rc.1", "1.0.0-alpha"] {
            assert_eq!(v(good).to_string(), good);
        }
        for bad in [
            "1.2", "1.2.3.4", "v1.2.3", "01.2.3", "1.2.x", "", "1.2.3-", "1.2.3-01", "1.2.3+b",
            "-1.2.3",
        ] {
            assert!(Version::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn a_tag_names_a_version_with_or_without_v() {
        assert_eq!(Version::of_tag("v1.4.2"), Some(v("1.4.2")));
        assert_eq!(Version::of_tag("1.4.2"), Some(v("1.4.2")));
        assert_eq!(Version::of_tag("release-1"), None);
        assert_eq!(Version::of_tag("v1.4"), None);
    }

    #[test]
    fn versions_order_as_semver_does() {
        let order = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "1.1.0",
            "2.0.0",
        ];
        for pair in order.windows(2) {
            assert!(v(pair[0]) < v(pair[1]), "{} < {}", pair[0], pair[1]);
        }
    }

    #[test]
    fn caret_and_default_accept_the_same_major() {
        for text in ["^1.2", "1.2", "^1.2.0"] {
            let req = r(text);
            assert!(req.matches(&v("1.2.0")), "{text}");
            assert!(req.matches(&v("1.9.4")), "{text}");
            assert!(!req.matches(&v("1.1.9")), "{text}");
            assert!(!req.matches(&v("2.0.0")), "{text}");
        }
        assert!(r("1").matches(&v("1.0.0")));
        assert!(!r("1").matches(&v("2.0.0")));
    }

    #[test]
    fn a_zero_major_makes_the_minor_the_boundary() {
        let req = r("^0.4.1");
        assert!(req.matches(&v("0.4.1")));
        assert!(req.matches(&v("0.4.9")));
        assert!(!req.matches(&v("0.5.0")));
        assert!(!req.matches(&v("0.4.0")));
        let patch = r("^0.0.3");
        assert!(patch.matches(&v("0.0.3")));
        assert!(!patch.matches(&v("0.0.4")));
    }

    #[test]
    fn tilde_and_exact_narrow_the_caret_range() {
        let tilde = r("~1.2.3");
        assert!(tilde.matches(&v("1.2.9")));
        assert!(!tilde.matches(&v("1.3.0")));
        assert!(!tilde.matches(&v("1.2.2")));
        assert!(r("~1").matches(&v("1.9.0")));
        let exact = r("=1.2.3");
        assert!(exact.matches(&v("1.2.3")));
        assert!(!exact.matches(&v("1.2.4")));
        assert!(r("=1.2").matches(&v("1.2.7")));
        assert!(!r("=1.2").matches(&v("1.3.0")));
    }

    #[test]
    fn pre_releases_match_only_a_requirement_that_names_one() {
        assert!(!r("^1.0").matches(&v("1.1.0-rc.1")));
        assert!(r("^1.0.0-rc.1").matches(&v("1.0.0-rc.2")));
        assert!(r("^1.0.0-rc.1").matches(&v("1.0.0")));
        assert!(!r("^1.0.0-rc.2").matches(&v("1.0.0-rc.1")));
    }

    #[test]
    fn a_requirement_lies_in_one_bucket() {
        assert_eq!(r("^1.2").bucket(), Bucket::Major(1));
        assert_eq!(r("~1.2.3").bucket(), Bucket::Major(1));
        assert_eq!(r("^0.4.1").bucket(), Bucket::Minor(4));
        assert_eq!(r("^0.0.3").bucket(), Bucket::Patch(3));
        assert_eq!(v("0.4.9").bucket(), Bucket::Minor(4));
        assert_eq!(v("2026.11.0").bucket(), Bucket::Major(2026));
    }

    #[test]
    fn requirements_that_span_buckets_or_are_malformed_are_errors() {
        for bad in [
            "0", "^0", "0.0", "~0", ">=1.0", "1.2.3.4", "^", "", "1.x", "*", "1.0-rc", "^v1.2",
            "1,2",
        ] {
            assert!(Requirement::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn a_requirement_prints_in_the_form_the_error_messages_use() {
        assert_eq!(r("1.2").to_string(), "^1.2");
        assert_eq!(r("~1.2.3").to_string(), "~1.2.3");
        assert_eq!(r("=0.4.1").to_string(), "=0.4.1");
    }
}
