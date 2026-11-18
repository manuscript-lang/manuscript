//! Loops that LLVM's early-exit vectorizer would only slow down.
//!
//! A loop that leaves from two places (the end of a range and a hit inside the body) and reads
//! no list or string element is an arithmetic search: advance a counter until something
//! matches, as the `next` of an iterator adapter does. The vectorizer turns it into a vector
//! loop whose setup and exit cost about 50 instructions per match, and a match comes within
//! a few steps, so such a loop ran 7x slower than the scalar one. A scan over list or string
//! elements keeps the pass: there its wide loads win. The loops found here get
//! `llvm.loop.vectorize.enable = false` on their back edges (see `bench/perf/everyday-round5`).

use ms_mir::ir::{Func, Op, Term};

/// For each loop (a header and its body) of `f` that is an arithmetic search, the header and
/// a flag per block saying whether the block lies in the loop.
pub(super) fn arithmetic_searches(f: &Func) -> Vec<(usize, Vec<bool>)> {
    let n = f.blocks.len();
    let order = f.rpo();
    let mut at = vec![usize::MAX; n];
    for (i, b) in order.iter().enumerate() {
        at[b.index()] = i;
    }
    let preds = f.predecessors();
    // Loops by header: the union of the bodies of every back edge into it.
    let mut loops: Vec<(usize, Vec<bool>)> = Vec::new();
    for u in order.iter().map(|b| b.index()) {
        for s in f.blocks[u].term.successors() {
            let h = s.index();
            if at[h] > at[u] {
                continue;
            }
            // `u -> h` is a back edge; the body is `h` and what reaches `u` without crossing `h`.
            let mut body = vec![false; n];
            body[h] = true;
            let mut work = vec![u];
            while let Some(b) = work.pop() {
                if std::mem::replace(&mut body[b], true) && b != u {
                    continue;
                }
                if b == h {
                    continue;
                }
                for p in &preds[b] {
                    let p = p.index();
                    if at[p] != usize::MAX && !body[p] {
                        work.push(p);
                    }
                }
            }
            match loops.iter_mut().find(|(hh, _)| *hh == h) {
                Some((_, b)) => b.iter_mut().zip(&body).for_each(|(x, y)| *x |= *y),
                None => loops.push((h, body)),
            }
        }
    }
    loops
        .into_iter()
        .filter(|(_, body)| is_search(f, body))
        .collect()
}

fn is_search(f: &Func, body: &[bool]) -> bool {
    let mut exits = 0;
    for (b, _) in body.iter().enumerate().filter(|(_, inb)| **inb) {
        let bd = &f.blocks[b];
        if bd.insts.iter().any(|i| reads_element(i.op)) {
            return false;
        }
        match &bd.term {
            Term::Ret(_) => exits += 1,
            term => term.for_each_target(|t| {
                if !body[t.block.index()] && !f.cold.contains(&t.block) {
                    exits += 1;
                }
            }),
        }
    }
    exits >= 2
}

fn reads_element(op: Op) -> bool {
    matches!(
        op,
        Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::ListTake
            | Op::ListAddr
            | Op::ListAddrU
            | Op::StrByte
    )
}
