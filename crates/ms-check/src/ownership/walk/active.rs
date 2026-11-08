//! The live borrows of a walk, laid out as flat arrays so an access or a release touches only the
//! borrows it concerns.
//!
//! A read or change used to scan every live borrow, and every statement that ended a borrow
//! filtered all of them again, so a function holding N borrows and making N accesses cost N^2.
//!
//! * `live[r]` counts borrows with an origin rooted at binding `r`, and `exclusive[r]` those among
//!   them holding it exclusively (a closure that changes it, a `var` borrow). A read conflicts
//!   only with an exclusive borrow and a change with any, so an access whose roots count zero
//!   skips the scan.
//! * `head[h]` and `next[pos]` chain the slots of each holder `h` (an intrusive list in two flat
//!   arrays), so releasing a holder visits its own borrows only.
//! * A released slot becomes a hole, keeping every other borrow where it was (diagnostics name the
//!   first conflicting borrow in push order); holes are squeezed out once they are half the slots.
//!
//! All arrays are indexed by a binding uid or a slot position, never hashed.

use super::Borrow;

const NONE: u32 = u32::MAX;

/// An array index for a binding uid. Ordinary uids count up from zero; hidden bindings count down
/// from `usize::MAX`. The two runs interleave (even and odd indices), so both stay dense.
fn chain(uid: usize) -> usize {
    if uid > usize::MAX / 2 {
        (usize::MAX - uid) * 2 + 1
    } else {
        uid * 2
    }
}

#[derive(Clone, Default)]
pub(super) struct ActiveBorrows {
    slots: Vec<Option<Borrow>>,
    next: Vec<u32>,
    head: Vec<u32>,
    holes: usize,
    live: Vec<u32>,
    exclusive: Vec<u32>,
}

impl ActiveBorrows {
    pub(super) fn push(&mut self, borrow: Borrow) {
        let at = u32::try_from(self.slots.len()).expect("fewer than 2^32 live borrows");
        let holder = chain(borrow.holder);
        if self.head.len() <= holder {
            self.head.resize(holder + 1, NONE);
        }
        self.next.push(self.head[holder]);
        self.head[holder] = at;
        self.count(&borrow, true);
        self.slots.push(Some(borrow));
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = &Borrow> {
        self.slots.iter().flatten()
    }

    /// Whether some borrow is held by `holder`.
    pub(super) fn held_by(&self, holder: usize) -> bool {
        self.head.get(chain(holder)).is_some_and(|&h| h != NONE)
    }

    /// Whether some live borrow has an origin rooted at `root`; with `exclusive`, only borrows
    /// holding it exclusively.
    pub(super) fn touches(&self, root: usize, exclusive: bool) -> bool {
        let counts = if exclusive {
            &self.exclusive
        } else {
            &self.live
        };
        counts.get(chain(root)).is_some_and(|&n| n > 0)
    }

    /// Ends the borrows of `holders` for which `release` holds; the rest stay where they are.
    pub(super) fn release(&mut self, holders: &[usize], release: impl Fn(&Borrow) -> bool) {
        for &holder in holders {
            let holder = chain(holder);
            let Some(&first) = self.head.get(holder) else {
                continue;
            };
            let (mut at, mut kept) = (first, Vec::new());
            while at != NONE {
                let following = self.next[at as usize];
                let ends = self.slots[at as usize].as_ref().is_some_and(&release);
                if ends {
                    let borrow = self.slots[at as usize]
                        .take()
                        .expect("chained slot is live");
                    self.count(&borrow, false);
                    self.holes += 1;
                } else {
                    kept.push(at);
                }
                at = following;
            }
            // Relink the survivors, in their original (newest first) order.
            let mut link = NONE;
            for &pos in kept.iter().rev() {
                self.next[pos as usize] = link;
                link = pos;
            }
            self.head[holder] = link;
        }
        if self.holes > 16 && self.holes * 2 > self.slots.len() {
            self.compact();
        }
    }

    fn compact(&mut self) {
        let all = std::mem::take(self);
        *self = all.into_iter().collect();
    }

    fn count(&mut self, borrow: &Borrow, add: bool) {
        for (place, exclusive) in &borrow.origins {
            let at = chain(place.root);
            if self.live.len() <= at {
                self.live.resize(at + 1, 0);
                self.exclusive.resize(at + 1, 0);
            }
            if add {
                self.live[at] += 1;
                self.exclusive[at] += u32::from(*exclusive);
            } else {
                self.live[at] -= 1;
                self.exclusive[at] -= u32::from(*exclusive);
            }
        }
    }
}

impl IntoIterator for ActiveBorrows {
    type Item = Borrow;
    type IntoIter = std::iter::Flatten<std::vec::IntoIter<Option<Borrow>>>;

    fn into_iter(self) -> Self::IntoIter {
        self.slots.into_iter().flatten()
    }
}

impl FromIterator<Borrow> for ActiveBorrows {
    fn from_iter<I: IntoIterator<Item = Borrow>>(iter: I) -> Self {
        let mut out = ActiveBorrows::default();
        for borrow in iter {
            out.push(borrow);
        }
        out
    }
}
