//! The `buildmove` pass: `builder.build()` moves the bytes out of a builder that is not used again.
//!
//! `build()` lowers to `load` of the builder's buffer and a `copy` of it, because a builder may be
//! built twice. When the builder handle is local and every use of it after the copy is its drop,
//! the copy is the last use: the buffer moves out and an empty one takes its place, so the drop
//! frees nothing. Building a large string then costs no second copy of its bytes.

use crate::ir::{ExternDef, Func, Imm, Inst, Module, Op, Value};
use crate::types::Ty;

const LIST_NEW: &str = "msrt_list_new";

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        while move_one(m, fi) {
            changed = true;
        }
    }
    changed
}

/// A `load`/`copy` pair of a builder's bytes: positions of the load and the copy.
struct Site {
    block: usize,
    load: usize,
    field: Value,
}

fn move_one(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    for b in &f.blocks {
        for inst in &b.insts {
            if inst.op == Op::CellNew
                && let Some(site) = find_site(f, inst.res.expect("cell.new has a result"))
            {
                apply(m, fi, site);
                return true;
            }
        }
    }
    false
}

/// The one copy of the buffer of handle `h` after which the handle is only dropped, if any.
fn find_site(f: &Func, h: Value) -> Option<Site> {
    let n = f.values.len();
    // The family: the handle, its addresses and the field pointers into them.
    let mut kind = vec![0u8; n]; // 1 handle, 2 address, 3 field
    kind[h.index()] = 1;
    let mut def_block = usize::MAX;
    let mut drops = 0;
    for (bi, b) in f.blocks.iter().enumerate() {
        for i in &b.insts {
            let (Some(r), Some(&a)) = (i.res, i.args.first()) else {
                continue;
            };
            if r == h {
                def_block = bi;
            }
            match i.op {
                Op::CellAddr if kind[a.index()] == 1 => kind[r.index()] = 2,
                Op::PtrField if kind[a.index()] == 2 => kind[r.index()] = 3,
                _ => {}
            }
        }
    }
    // Every use stays inside the family's few shapes; anything else (a call, a capture, a block
    // argument) may keep the handle alive.
    let mut loads = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        let mut escapes = false;
        b.term.for_each_use(|v| escapes |= kind[v.index()] != 0);
        if escapes {
            return None;
        }
        for (ii, i) in b.insts.iter().enumerate() {
            for (k, a) in i.args.iter().enumerate() {
                let ok = match kind[a.index()] {
                    0 => true,
                    1 => matches!(i.op, Op::CellAddr | Op::Drop),
                    2 => i.op == Op::PtrField,
                    // A runtime call borrows the pointer while it runs (the appends of a builder).
                    _ => {
                        i.op == Op::CallRt
                            || k == 0 && matches!(i.op, Op::Load | Op::Take | Op::Put | Op::Store)
                    }
                };
                if !ok {
                    return None;
                }
            }
            if i.op == Op::Drop && i.args[0] == h {
                drops += 1;
            }
            if i.op == Op::Load
                && kind[i.args[0].index()] == 3
                && i.imm == Imm::Ty(Ty::BYTES)
                && let Some(next) = b.insts.get(ii + 1)
                && next.op == Op::Copy
                && next.args[0] == i.res.expect("load has a result")
            {
                loads.push(Site {
                    block: bi,
                    load: ii,
                    field: i.args[0],
                });
            }
        }
    }
    if drops != 1 || def_block == usize::MAX {
        return None;
    }
    loads.into_iter().find(|s| last_use(f, &kind, def_block, s))
}

/// Whether nothing but the handle's drop touches its family after the load at `site`.
fn last_use(f: &Func, kind: &[u8], def_block: usize, site: &Site) -> bool {
    let touches = |i: &Inst| {
        i.op != Op::Drop && i.args.iter().any(|a| kind[a.index()] != 0)
            || i.op == Op::Drop && kind[i.args[0].index()] > 1
    };
    let b = &f.blocks[site.block];
    // The copy itself (the load's partner) is the next instruction; the rest of the block follows.
    if b.insts[site.load + 2..].iter().any(touches) {
        return false;
    }
    // Blocks reachable afterwards must not touch the family either. Reaching the block that
    // creates the handle starts a new handle, so that block ends the search.
    let mut seen = vec![false; f.blocks.len()];
    let mut work: Vec<usize> = b.term.successors().iter().map(|s| s.index()).collect();
    while let Some(x) = work.pop() {
        if x == def_block || std::mem::replace(&mut seen[x], true) {
            continue;
        }
        if x == site.block {
            // The load is reachable again with the same handle.
            return false;
        }
        let blk = &f.blocks[x];
        if blk.insts.iter().any(touches) {
            return false;
        }
        work.extend(blk.term.successors().iter().map(|s| s.index()));
    }
    true
}

/// `c = copy (load p)` becomes `c = take p; put p, empty`.
fn apply(m: &mut Module, fi: usize, site: Site) {
    let ext = m.add_extern(ExternDef {
        name: LIST_NEW.to_string(),
        params: Vec::new(),
        ret: Ty::BYTES,
        noreturn: false,
        pure_: false,
        fresh: true,
    });
    let f = &mut m.funcs[fi];
    let empty = f.new_value(Ty::BYTES);
    let blk = &mut f.blocks[site.block];
    let load = blk.insts[site.load].clone();
    let copy = blk.insts[site.load + 1].clone();
    let take = Inst {
        op: Op::Take,
        args: load.args.clone(),
        imm: load.imm,
        res: copy.res,
        loc: copy.loc,
    };
    let new = Inst {
        op: Op::CallRt,
        args: Vec::new(),
        imm: Imm::Ext(ext),
        res: Some(empty),
        loc: copy.loc,
    };
    let put = Inst {
        op: Op::Put,
        args: vec![site.field, empty],
        imm: Imm::None,
        res: None,
        loc: copy.loc,
    };
    blk.insts
        .splice(site.load..=site.load + 1, [take, new, put]);
}
