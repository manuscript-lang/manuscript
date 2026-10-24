//! `@std/html.ms` natives: HTML5 parsing and HTML escaping, with resource limits.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

mod atoms;
mod doctype;
mod entity;
mod escape;
pub mod ffi;
mod foreign;
mod parse;
mod token;

use alloc::vec::Vec;
use ms_rt::ffi::Fail;

pub use escape::{escape_string as escape, unescape_string as unescape};
pub use parse::{Id, Node, NodeType};
pub use token::Attribute;

#[derive(Clone, Copy, Default)]
pub struct Limits {
    pub max_bytes: Option<i64>,
    pub max_depth: Option<i64>,
    pub max_nodes: Option<i64>,
}

impl Limits {
    /// Applied when the caller supplies no limits record.
    pub const DEFAULT: Limits = Limits {
        max_bytes: None,
        max_depth: Some(10000),
        max_nodes: Some(1_000_000),
    };
}

/// A parsed document; node ids index [`Tree::nodes`].
pub struct Tree {
    pub nodes: Vec<Node>,
    pub root: Id,
}

fn budget(o: Option<i64>) -> Result<usize, Fail> {
    match o {
        None => Ok(usize::MAX),
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
    }
}

/// Parses `text` and checks the byte, depth and node budgets.
pub fn parse(text: &str, limits: Limits) -> Result<Tree, Fail> {
    let (max_bytes, max_depth, max_nodes) = (
        budget(limits.max_bytes)?,
        budget(limits.max_depth)?,
        budget(limits.max_nodes)?,
    );
    if text.len() > max_bytes {
        return Err(Fail::LimitExceeded);
    }
    let mut p = parse::Parser::new(text.as_bytes());
    // Twice the depth budget plus slack for elements the tree places shallower than the stack.
    p.max_open = max_depth.saturating_mul(2).saturating_add(64);
    p.parse();
    if p.exceeded {
        return Err(Fail::LimitExceeded);
    }
    let tree = Tree {
        root: p.doc,
        nodes: p.nodes,
    };
    // Count reachable nodes and the deepest level (the document is depth zero).
    let (mut count, mut deepest) = (0usize, 0usize);
    let mut stack = alloc::vec![(tree.root, 0usize)];
    while let Some((id, depth)) = stack.pop() {
        count += 1;
        deepest = deepest.max(depth);
        let mut c = tree.nodes[id].first;
        while let Some(child) = c {
            stack.push((child, depth + 1));
            c = tree.nodes[child].next;
        }
    }
    if count > max_nodes || deepest > max_depth {
        return Err(Fail::LimitExceeded);
    }
    Ok(tree)
}
