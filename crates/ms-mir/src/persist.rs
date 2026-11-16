//! A persistent set of dense `u32` indices: copying it is one `Rc` clone, an update copies one
//! path, and comparing two sets skips the subtrees they share. The verifier's per-block owner
//! sets (`verify::check_ownership`) are cloned at every block entry and edge; as a `BTreeSet`
//! that costs the size of the set each time, which made a function with N live owners
//! quadratic to verify (#4020).

use std::rc::Rc;

/// Bits one leaf word holds, and the fan-out of a branch (a power of two).
const LEAF_BITS: u32 = 6;
const BRANCH_BITS: u32 = 4;
const FAN: usize = 1 << BRANCH_BITS;

#[derive(Debug)]
enum Node {
    /// Values `base..base + 64`, one bit each; never zero.
    Leaf(u64),
    /// `FAN` children; at least one is present.
    Branch(Box<[Option<Rc<Node>>; FAN]>),
}

/// A set of `u32`. Equal contents compare equal whatever order they were built in.
#[derive(Clone, Debug, Default)]
pub struct OwnerSet {
    root: Option<Rc<Node>>,
    /// 0: the root is a leaf covering `0..64`; each level multiplies the range by `FAN`.
    height: u32,
}

/// The bits of a value that choose a child of a branch of `height`.
fn slot(v: u32, height: u32) -> usize {
    ((v >> (LEAF_BITS + BRANCH_BITS * (height - 1))) as usize) & (FAN - 1)
}

/// The largest value a tree of `height` holds, plus one.
fn capacity(height: u32) -> u64 {
    1u64 << (LEAF_BITS + BRANCH_BITS * height)
}

fn insert_in(node: Option<&Rc<Node>>, height: u32, v: u32) -> Rc<Node> {
    if height == 0 {
        let word = match node.map(|n| &**n) {
            Some(Node::Leaf(w)) => *w,
            _ => 0,
        };
        return Rc::new(Node::Leaf(word | 1u64 << (v & 63)));
    }
    let mut kids: Box<[Option<Rc<Node>>; FAN]> = match node.map(|n| &**n) {
        Some(Node::Branch(k)) => k.clone(),
        _ => Box::new(std::array::from_fn(|_| None)),
    };
    let i = slot(v, height);
    kids[i] = Some(insert_in(kids[i].as_ref(), height - 1, v));
    Rc::new(Node::Branch(kids))
}

fn remove_in(node: &Rc<Node>, height: u32, v: u32) -> Option<Rc<Node>> {
    match &**node {
        Node::Leaf(w) => {
            let left = *w & !(1u64 << (v & 63));
            if left == *w {
                Some(node.clone())
            } else if left == 0 {
                None
            } else {
                Some(Rc::new(Node::Leaf(left)))
            }
        }
        Node::Branch(kids) => {
            let i = slot(v, height);
            let Some(child) = &kids[i] else {
                return Some(node.clone());
            };
            let next = remove_in(child, height - 1, v);
            if next.as_ref().is_some_and(|n| Rc::ptr_eq(n, child)) {
                return Some(node.clone());
            }
            let mut kids = kids.clone();
            kids[i] = next;
            kids.iter()
                .any(Option::is_some)
                .then(|| Rc::new(Node::Branch(kids)))
        }
    }
}

fn contains_in(node: &Rc<Node>, height: u32, v: u32) -> bool {
    match &**node {
        Node::Leaf(w) => w & (1u64 << (v & 63)) != 0,
        Node::Branch(kids) => kids[slot(v, height)]
            .as_ref()
            .is_some_and(|c| contains_in(c, height - 1, v)),
    }
}

fn collect(node: &Node, height: u32, base: u64, out: &mut Vec<u32>) {
    match node {
        Node::Leaf(w) => {
            let mut bits = *w;
            while bits != 0 {
                out.push((base + u64::from(bits.trailing_zeros())) as u32);
                bits &= bits - 1;
            }
        }
        Node::Branch(kids) => {
            let span = capacity(height - 1);
            for (i, k) in kids.iter().enumerate() {
                if let Some(k) = k {
                    collect(k, height - 1, base + i as u64 * span, out);
                }
            }
        }
    }
}

/// Whether the two subtrees (of one height) hold the same values.
fn same(a: Option<&Rc<Node>>, b: Option<&Rc<Node>>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(x), Some(y)) if Rc::ptr_eq(x, y) => true,
        (Some(x), Some(y)) => match (&**x, &**y) {
            (Node::Leaf(p), Node::Leaf(q)) => p == q,
            (Node::Branch(p), Node::Branch(q)) => p
                .iter()
                .zip(q.iter())
                .all(|(c, d)| same(c.as_ref(), d.as_ref())),
            _ => false,
        },
        _ => false,
    }
}

impl OwnerSet {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn contains(&self, v: u32) -> bool {
        u64::from(v) < capacity(self.height)
            && self
                .root
                .as_ref()
                .is_some_and(|r| contains_in(r, self.height, v))
    }

    /// Adds `v`.
    pub fn insert(&mut self, v: u32) {
        while u64::from(v) >= capacity(self.height) {
            // Grow: the old root becomes the first child of a new one.
            if let Some(old) = self.root.take() {
                let mut kids: Box<[Option<Rc<Node>>; FAN]> =
                    Box::new(std::array::from_fn(|_| None));
                kids[0] = Some(old);
                self.root = Some(Rc::new(Node::Branch(kids)));
            }
            self.height += 1;
        }
        self.root = Some(insert_in(self.root.as_ref(), self.height, v));
    }

    /// Removes `v`; whether it was present.
    pub fn remove(&mut self, v: u32) -> bool {
        if !self.contains(v) {
            return false;
        }
        let root = self.root.as_ref().expect("a set that holds v");
        self.root = remove_in(root, self.height, v);
        true
    }

    pub fn is_empty(&self) -> bool {
        self.root.is_none()
    }

    /// The members in ascending order.
    pub fn to_vec(&self) -> Vec<u32> {
        let mut out = Vec::new();
        if let Some(r) = &self.root {
            collect(r, self.height, 0, &mut out);
        }
        out
    }

    /// The smallest member.
    pub fn first(&self) -> Option<u32> {
        let mut node = self.root.as_ref()?;
        let mut base = 0u64;
        let mut height = self.height;
        loop {
            match &**node {
                Node::Leaf(w) => return Some((base + u64::from(w.trailing_zeros())) as u32),
                Node::Branch(kids) => {
                    let i = kids.iter().position(Option::is_some)?;
                    base += i as u64 * capacity(height - 1);
                    height -= 1;
                    node = kids[i].as_ref()?;
                }
            }
        }
    }

    /// The values in exactly one of the two sets, ascending (for an error message).
    pub fn symmetric_difference(&self, other: &Self) -> Vec<u32> {
        let (a, b) = (self.to_vec(), other.to_vec());
        let mut out: Vec<u32> = a.iter().filter(|v| !other.contains(**v)).copied().collect();
        out.extend(b.iter().filter(|v| !self.contains(**v)));
        out.sort_unstable();
        out
    }
}

impl PartialEq for OwnerSet {
    fn eq(&self, other: &Self) -> bool {
        // Compare at the taller height: the shorter tree is the first child all the way up.
        let (tall, short) = if self.height >= other.height {
            (self, other)
        } else {
            (other, self)
        };
        let mut s = short.root.clone();
        let mut h = short.height;
        while h < tall.height {
            let Some(old) = s.take() else { break };
            let mut kids: Box<[Option<Rc<Node>>; FAN]> = Box::new(std::array::from_fn(|_| None));
            kids[0] = Some(old);
            s = Some(Rc::new(Node::Branch(kids)));
            h += 1;
        }
        same(tall.root.as_ref(), s.as_ref())
    }
}

impl Eq for OwnerSet {}

/// Bits of a key a [`PosMap`] leaf or branch consumes; both hold `MAP_FAN` entries.
const MAP_BITS: u32 = 4;
const MAP_FAN: usize = 1 << MAP_BITS;

#[derive(Debug)]
enum MapNode<T> {
    Leaf(Box<[Option<T>; MAP_FAN]>),
    Branch(Box<[Option<Rc<MapNode<T>>>; MAP_FAN]>),
}

/// A persistent map from dense `u32` keys to values, iterated in key order: the same sharing as
/// [`OwnerSet`]. `elaborate`'s owner state keys it by definition position, which only grows, so
/// the tree stays compact.
#[derive(Debug)]
pub struct PosMap<T> {
    root: Option<Rc<MapNode<T>>>,
    /// 0: the root is a leaf covering `0..16`; each level multiplies the range by 16.
    height: u32,
    len: usize,
}

impl<T> Clone for PosMap<T> {
    fn clone(&self) -> Self {
        PosMap {
            root: self.root.clone(),
            height: self.height,
            len: self.len,
        }
    }
}

impl<T> Default for PosMap<T> {
    fn default() -> Self {
        PosMap {
            root: None,
            height: 0,
            len: 0,
        }
    }
}

fn map_slot(k: u32, height: u32) -> usize {
    ((k >> (MAP_BITS * height)) as usize) & (MAP_FAN - 1)
}

fn map_capacity(height: u32) -> u64 {
    1u64 << (MAP_BITS * (height + 1))
}

fn empty_slots<U>() -> Box<[Option<U>; MAP_FAN]> {
    Box::new(std::array::from_fn(|_| None))
}

fn map_insert<T: Clone>(
    node: Option<&Rc<MapNode<T>>>,
    height: u32,
    k: u32,
    v: T,
    grew: &mut bool,
) -> Rc<MapNode<T>> {
    if height == 0 {
        let mut slots = match node.map(|n| &**n) {
            Some(MapNode::Leaf(s)) => s.clone(),
            _ => empty_slots(),
        };
        let i = map_slot(k, 0);
        *grew = slots[i].is_none();
        slots[i] = Some(v);
        return Rc::new(MapNode::Leaf(slots));
    }
    let mut kids = match node.map(|n| &**n) {
        Some(MapNode::Branch(s)) => s.clone(),
        _ => empty_slots(),
    };
    let i = map_slot(k, height);
    kids[i] = Some(map_insert(kids[i].as_ref(), height - 1, k, v, grew));
    Rc::new(MapNode::Branch(kids))
}

fn map_remove<T: Clone>(
    node: &Rc<MapNode<T>>,
    height: u32,
    k: u32,
    gone: &mut bool,
) -> Option<Rc<MapNode<T>>> {
    match &**node {
        MapNode::Leaf(slots) => {
            let i = map_slot(k, 0);
            if slots[i].is_none() {
                return Some(node.clone());
            }
            *gone = true;
            let mut slots = slots.clone();
            slots[i] = None;
            slots
                .iter()
                .any(Option::is_some)
                .then(|| Rc::new(MapNode::Leaf(slots)))
        }
        MapNode::Branch(kids) => {
            let i = map_slot(k, height);
            let Some(child) = &kids[i] else {
                return Some(node.clone());
            };
            let next = map_remove(child, height - 1, k, gone);
            if !*gone {
                return Some(node.clone());
            }
            let mut kids = kids.clone();
            kids[i] = next;
            kids.iter()
                .any(Option::is_some)
                .then(|| Rc::new(MapNode::Branch(kids)))
        }
    }
}

fn map_walk<'a, T>(node: &'a MapNode<T>, out: &mut Vec<&'a T>) {
    match node {
        MapNode::Leaf(slots) => out.extend(slots.iter().flatten()),
        MapNode::Branch(kids) => {
            for k in kids.iter().flatten() {
                map_walk(k, out);
            }
        }
    }
}

impl<T: Clone> PosMap<T> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn get(&self, k: u32) -> Option<&T> {
        if u64::from(k) >= map_capacity(self.height) {
            return None;
        }
        let mut node = self.root.as_ref()?;
        let mut height = self.height;
        loop {
            match &**node {
                MapNode::Leaf(slots) => return slots[map_slot(k, 0)].as_ref(),
                MapNode::Branch(kids) => {
                    node = kids[map_slot(k, height)].as_ref()?;
                    height -= 1;
                }
            }
        }
    }

    /// Sets the value of `k`.
    pub fn insert(&mut self, k: u32, v: T) {
        while u64::from(k) >= map_capacity(self.height) {
            if let Some(old) = self.root.take() {
                let mut kids = empty_slots();
                kids[0] = Some(old);
                self.root = Some(Rc::new(MapNode::Branch(kids)));
            }
            self.height += 1;
        }
        let mut grew = false;
        self.root = Some(map_insert(self.root.as_ref(), self.height, k, v, &mut grew));
        self.len += usize::from(grew);
    }

    /// Removes `k`; whether it was present.
    pub fn remove(&mut self, k: u32) -> bool {
        let Some(root) = self.root.as_ref() else {
            return false;
        };
        if u64::from(k) >= map_capacity(self.height) {
            return false;
        }
        let mut gone = false;
        let next = map_remove(root, self.height, k, &mut gone);
        if gone {
            self.root = next;
            self.len -= 1;
        }
        gone
    }

    /// The values in key order.
    pub fn values(&self) -> std::vec::IntoIter<&T> {
        let mut out = Vec::with_capacity(self.len);
        if let Some(r) = &self.root {
            map_walk(r, &mut out);
        }
        out.into_iter()
    }

    /// Whether both maps are the same tree (sharing everything), a quick equality.
    pub fn same_tree(&self, other: &Self) -> bool {
        match (&self.root, &other.root) {
            (None, None) => true,
            (Some(a), Some(b)) => Rc::ptr_eq(a, b) && self.height == other.height,
            _ => false,
        }
    }
}
