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
    /// prefix of the other. Distinct fields are disjoint; all elements alias.
    pub fn overlaps(&self, other: &Place) -> bool {
        self.root == other.root && self.path.iter().zip(&other.path).all(|(a, b)| a == b)
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
            }
        }
        s
    }
}

impl fmt::Display for Step {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Step::Field(n) => write!(f, ".{n}"),
            Step::Element => f.write_str("[..]"),
        }
    }
}
