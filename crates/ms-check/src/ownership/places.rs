//! Places: a local binding and a path of field and element projections.

use crate::types::*;
use std::fmt;

/// One projection step.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Step {
    /// A record field.
    Field(Name),
    /// Some element of a collection (an index, a map value, an accessor).
    Element,
    /// The element of a list at a non-negative literal index. Two different literal indexes are
    /// disjoint; the same index, or any other element step, may be the same element.
    Index(u64),
}

/// A part of a local binding's value.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Place {
    /// The root binding's identity.
    pub root: usize,
    /// Projections from the root.
    pub path: Vec<Step>,
}

impl Place {
    /// The whole binding.
    pub fn local(root: usize) -> Place {
        Place {
            root,
            path: Vec::new(),
        }
    }

    /// This place followed by one more step.
    pub fn then(&self, step: Step) -> Place {
        let mut path = self.path.clone();
        path.push(step);
        Place {
            root: self.root,
            path,
        }
    }

    /// This place followed by `more`.
    pub fn join(&self, more: &[Step]) -> Place {
        let mut path = self.path.clone();
        path.extend_from_slice(more);
        Place {
            root: self.root,
            path,
        }
    }

    /// Whether the two places share storage: same root, and one path is a
    /// prefix of the other. Distinct fields and distinct literal list indexes are disjoint; any
    /// other pair of elements may alias.
    pub fn overlaps(&self, other: &Place) -> bool {
        self.root == other.root
            && self
                .path
                .iter()
                .zip(&other.path)
                .all(|(a, b)| a.may_alias(b))
    }

    /// Source-like text with the root's name.
    pub fn show(&self, root: Name) -> String {
        let mut s = root.as_str().to_string();
        for step in &self.path {
            match step {
                Step::Field(f) => {
                    s.push('.');
                    s.push_str(f.as_str());
                }
                Step::Element => s.push_str("[..]"),
                Step::Index(i) => s.push_str(&format!("[{i}]")),
            }
        }
        s
    }
}

impl Step {
    /// Whether the two steps can denote the same storage.
    fn may_alias(&self, other: &Step) -> bool {
        match (self, other) {
            (Step::Index(a), Step::Index(b)) => a == b,
            (Step::Field(_), Step::Field(_)) => self == other,
            (Step::Field(_), _) | (_, Step::Field(_)) => false,
            _ => true,
        }
    }
}

impl fmt::Display for Step {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Step::Field(n) => write!(f, ".{n}"),
            Step::Element => f.write_str("[..]"),
            Step::Index(i) => write!(f, "[{i}]"),
        }
    }
}
