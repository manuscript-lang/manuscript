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
//! All arrays are indexed by a binding uid (relative to the function's own span) or a slot position, never hashed.

use super::Borrow;

const NONE: u32 = u32::MAX;

/// A per-binding array that stores only the span of uids it has seen.
///
/// Ordinary uids count up from zero across the whole checker, so a function late in a large
/// program has uids in the hundreds of thousands; indexing by uid would zero that many entries for
/// every function. Hidden bindings count down from `usize::MAX` and are stored as their distance
/// from it. Each run keeps a base and grows toward either end, so the array spans the function's
/// own bindings.
#[derive(Clone)]
struct ByBinding {
    runs: [Run; 2],
    fill: u32,
}

#[derive(Clone, Default)]
struct Run {
    base: usize,
    items: Vec<u32>,
}

fn locate(uid: usize) -> (usize, usize) {
    if uid > usize::MAX / 2 {
        (1, usize::MAX - uid)
    } else {
        (0, uid)
    }
}

impl ByBinding {
    fn new(fill: u32) -> ByBinding {
        ByBinding {
            runs: [Run::default(), Run::default()],
            fill,
        }
    }

    fn get(&self, uid: usize) -> Option<u32> {
        let (run, at) = locate(uid);
        let run = &self.runs[run];
        run.items.get(at.checked_sub(run.base)?).copied()
    }

    fn slot(&mut self, uid: usize) -> &mut u32 {
        let (run, at) = locate(uid);
        let fill = self.fill;
        let run = &mut self.runs[run];
        if run.items.is_empty() {
            run.base = at;
        }
        if at < run.base {
            run.items
                .splice(0..0, std::iter::repeat_n(fill, run.base - at));
            run.base = at;
        }
        let k = at - run.base;
        if run.items.len() <= k {
            run.items.resize(k + 1, fill);
        }
        &mut run.items[k]
    }
}

#[derive(Clone)]
pub(super) struct ActiveBorrows {
    slots: Vec<Option<Borrow>>,
    next: Vec<u32>,
    head: ByBinding,
    holes: usize,
    live: ByBinding,
    exclusive: ByBinding,
}

impl Default for ActiveBorrows {
    fn default() -> ActiveBorrows {
        ActiveBorrows {
            slots: Vec::new(),
            next: Vec::new(),
            head: ByBinding::new(NONE),
            holes: 0,
            live: ByBinding::new(0),
            exclusive: ByBinding::new(0),
        }
    }
}

impl ActiveBorrows {
    pub(super) fn push(&mut self, borrow: Borrow) {
        let at = u32::try_from(self.slots.len()).expect("fewer than 2^32 live borrows");
        let head = self.head.slot(borrow.holder);
        self.next.push(*head);
        *head = at;
        self.count(&borrow, true);
        self.slots.push(Some(borrow));
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = &Borrow> {
        self.slots.iter().flatten()
    }

    /// Whether some borrow is held by `holder`.
    pub(super) fn held_by(&self, holder: usize) -> bool {
        self.head.get(holder).is_some_and(|h| h != NONE)
    }

    /// Whether some live borrow has an origin rooted at `root`; with `exclusive`, only borrows
    /// holding it exclusively.
    pub(super) fn touches(&self, root: usize, exclusive: bool) -> bool {
        let counts = if exclusive {
            &self.exclusive
        } else {
            &self.live
        };
        counts.get(root).is_some_and(|n| n > 0)
    }

    /// Ends the borrows of `holders` for which `release` holds; the rest stay where they are.
    pub(super) fn release(&mut self, holders: &[usize], release: impl Fn(&Borrow) -> bool) {
        for &holder in holders {
            let Some(first) = self.head.get(holder) else {
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
            *self.head.slot(holder) = link;
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
            if add {
                *self.live.slot(place.root) += 1;
                *self.exclusive.slot(place.root) += u32::from(*exclusive);
            } else {
                *self.live.slot(place.root) -= 1;
                *self.exclusive.slot(place.root) -= u32::from(*exclusive);
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn by_binding_spans_only_the_uids_it_sees() {
        let mut counts = ByBinding::new(0);
        *counts.slot(1_000_000) += 1;
        assert_eq!(
            counts.runs[0].items.len(),
            1,
            "a late uid allocates no prefix"
        );
        *counts.slot(999_998) += 2;
        *counts.slot(1_000_003) += 3;
        let hidden = usize::MAX - 4;
        *counts.slot(hidden) += 4;
        assert_eq!(counts.get(1_000_000), Some(1));
        assert_eq!(counts.get(999_998), Some(2));
        assert_eq!(counts.get(1_000_003), Some(3));
        assert_eq!(counts.get(hidden), Some(4));
        assert_eq!(
            counts.get(999_999),
            Some(0),
            "a gap inside the span reads as the fill"
        );
        assert_eq!(counts.get(5), None, "below the span nothing was counted");
        assert_eq!(counts.get(1_000_004), None);
        assert_eq!(counts.get(usize::MAX), None);
        assert!(counts.runs[0].items.len() <= 6);
    }

    #[test]
    fn by_binding_fills_with_its_default() {
        let mut heads = ByBinding::new(NONE);
        *heads.slot(70) = 9;
        *heads.slot(68) = 8;
        assert_eq!(heads.get(69), Some(NONE));
        assert_eq!(heads.get(68), Some(8));
        assert_eq!(heads.get(70), Some(9));
    }
}
