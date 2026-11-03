//! Per-node ownership flags in one dense table per module, indexed by `NodeId`, so lowering
//! reads one byte instead of probing a hash set per fact.

use crate::types::Name;
use ms_syntax::ast::NodeId;
use std::collections::HashMap;

/// A boolean ownership fact about a node.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Fact {
    /// A callable whose result is a reference into its arguments.
    Lender = 1,
    /// A callable whose result is an owned interface view of its arguments.
    ViewLender = 1 << 1,
    /// A wrapper (`x?`, `ok(x)`, `error(x)`) of a lent value that stays a reference.
    ViewWrap = 1 << 2,
    /// A method value that stays local and borrows its receiver's place.
    BoundBorrow = 1 << 3,
    /// A name expression moving an interface view out of its local.
    ViewMove = 1 << 4,
    /// A conditional or match expression whose value is a reference.
    LentMatch = 1 << 5,
}

/// Fact flags by module file, then by node id.
#[derive(Default, Debug)]
pub struct NodeFacts {
    files: HashMap<Name, Vec<u8>>,
}

impl NodeFacts {
    /// Records `fact` for `id` of module `file`.
    pub fn set(&mut self, file: Name, id: NodeId, fact: Fact) {
        let flags = self.files.entry(file).or_default();
        if flags.len() <= id.index() {
            flags.resize(id.index() + 1, 0);
        }
        flags[id.index()] |= fact as u8;
    }

    /// Whether `fact` holds for `id` of module `file`.
    pub fn has(&self, file: Name, id: NodeId, fact: Fact) -> bool {
        self.files
            .get(&file)
            .and_then(|f| f.get(id.index()))
            .is_some_and(|b| b & fact as u8 != 0)
    }
}
