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
    ReturnsBorrow = 1,
    /// A callable whose result is an owned interface view of its arguments.
    ReturnsView = 1 << 1,
    /// A wrapper (`x?`, `ok(x)`, `error(x)`) of a borrowed value that stays a reference.
    ViewWrap = 1 << 2,
    /// A method value that stays local and borrows its receiver's place.
    BoundBorrow = 1 << 3,
    /// A name expression moving an interface view out of its local.
    ViewMove = 1 << 4,
    /// A conditional or match expression whose value is a reference.
    BorrowedMatch = 1 << 5,
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

/// A boolean ownership fact about a binding.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum BindingFact {
    /// A `let` binding that borrows a place another binding owns.
    SharedBorrow = 1,
    /// A `var` binding that borrows a place exclusively.
    ExclusiveBorrow = 1 << 1,
    /// A resource closed implicitly when its scope ends.
    ImplicitClose = 1 << 2,
    /// A closed resource that also has an explicit `.close()` call.
    ExplicitClose = 1 << 3,
    /// A payload binding of a consumed match scrutinee that some path moves out.
    MovedPayload = 1 << 4,
    /// A moved binding some path keeps to the end of its scope.
    ConditionalMove = 1 << 5,
}

/// Binding fact flags in one dense table indexed by binding identity (`Binding::uid`, handed out
/// in sequence while checking).
#[derive(Default, Debug)]
pub struct BindingFlags {
    flags: Vec<u8>,
}

impl BindingFlags {
    /// Records `fact` for binding `uid`.
    pub fn set(&mut self, uid: usize, fact: BindingFact) {
        if self.flags.len() <= uid {
            self.flags.resize(uid + 1, 0);
        }
        self.flags[uid] |= fact as u8;
    }

    /// Whether `fact` holds for binding `uid`.
    pub fn has(&self, uid: usize, fact: BindingFact) -> bool {
        self.flags.get(uid).is_some_and(|b| b & fact as u8 != 0)
    }

    /// How binding `uid` borrows a place, if it does.
    pub fn borrow(&self, uid: usize) -> Option<super::BorrowKind> {
        if self.has(uid, BindingFact::ExclusiveBorrow) {
            Some(super::BorrowKind::Exclusive)
        } else if self.has(uid, BindingFact::SharedBorrow) {
            Some(super::BorrowKind::Shared)
        } else {
            None
        }
    }
}
