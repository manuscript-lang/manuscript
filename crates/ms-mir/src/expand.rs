//! The `expand` pass: safety checks and list growth as explicit MIR, so the backends only lower.
//!
//! Run once after `unwind`, on the module a backend is about to compile. A checked list access
//! becomes the arithmetic that counts a negative index from the end, a compare of the index
//! against the length, a branch to a block that reports the fault, and the unchecked access
//! (`list.get.u`, `list.set.u`, `list.fill.u`, `list.addr.u`). `opt.unwrap` gets a branch to
//! the none fault ahead of it, and `list.push` becomes a test for a full list, growth to the
//! next capacity (4 when empty, else double) with `list.grow`, and `list.push.u`. With
//! `checks` off the branches are left out. After the pass no backend decides whether to check
//! or how a list grows.
//!
//! Overflow and division checks stay with the backends, which pick their cheapest form
//! (LLVM's overflow intrinsics, Cranelift's flags). Faults are the runtime's `msrt_*` calls:
//! `msrt_index_fault` takes the index and the length, so its block calls it and ends in
//! `unreachable`; the none fault has no operands and is a `fault` terminator. Both blocks, and
//! the block that grows a list, are marked in [`Func::cold`] so a backend lays them out of line
//! and treats the branch to them as unlikely.

use crate::ir::*;
use crate::types::Ty;

/// Expands the checked list accesses, `opt.unwrap` and `list.push` of every function. With
/// `checks` off the bounds and none checks are omitted (a negative index still counts from the
/// end). Returns whether anything changed.
pub fn run(m: &mut Module, checks: bool) -> bool {
    let mut index_fault = None;
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        let f = &m.funcs[fi];
        if !f
            .blocks
            .iter()
            .flat_map(|b| &b.insts)
            .any(|i| expands(i.op))
        {
            continue;
        }
        let ext = *index_fault.get_or_insert_with(|| {
            let int = Param {
                ty: Ty::INT,
                mode: Mode::Borrow,
            };
            m.add_extern(ExternDef {
                name: "msrt_index_fault".into(),
                params: vec![int; 2],
                ret: Ty::VOID,
                noreturn: true,
                pure_: false,
                fresh: false,
                retains: false,
                leaf: true,
                reads: false,
                role: ExternRole::None,
            })
        });
        let f = &mut m.funcs[fi];
        let blocks = std::mem::take(&mut f.blocks);
        f.blocks = Expander::new(f, checks, ext).run(blocks);
        changed = true;
    }
    changed
}

/// Whether `op` is one this pass rewrites.
fn expands(op: Op) -> bool {
    matches!(
        op,
        Op::ListGet
            | Op::ListGetNn
            | Op::ListSet
            | Op::ListSetNn
            | Op::ListFill
            | Op::ListAddr
            | Op::ListPush
            | Op::OptUnwrap
    )
}

/// How many blocks `op` adds after the one it is in, apart from fault blocks.
fn continuations(op: Op, checks: bool) -> usize {
    match op {
        Op::ListPush => 2,
        Op::OptUnwrap => usize::from(checks),
        op if expands(op) => usize::from(checks),
        _ => 0,
    }
}

/// Rewrites one function. Blocks keep their order: a block that is split is followed by its
/// continuations, and the fault blocks come last, so numbering is known before any block is
/// built and a terminator only needs its targets renumbered.
struct Expander<'a> {
    f: &'a mut Func,
    checks: bool,
    index_fault: ExtId,
    out: Vec<BlockData>,
    faults: Vec<BlockData>,
    /// The number of the first fault block: after every block built in order.
    fault_base: usize,
    /// The number of the next continuation block of the current block.
    next: usize,
}

impl<'a> Expander<'a> {
    fn new(f: &'a mut Func, checks: bool, index_fault: ExtId) -> Expander<'a> {
        Expander {
            f,
            checks,
            index_fault,
            out: Vec::new(),
            faults: Vec::new(),
            fault_base: 0,
            next: 0,
        }
    }

    fn run(mut self, old: Vec<BlockData>) -> Vec<BlockData> {
        let mut start = Vec::with_capacity(old.len());
        let mut total = 0;
        for b in &old {
            start.push(total);
            total += 1 + b
                .insts
                .iter()
                .map(|i| continuations(i.op, self.checks))
                .sum::<usize>();
        }
        self.fault_base = total;
        self.out.reserve(total);
        for (bi, b) in old.into_iter().enumerate() {
            debug_assert_eq!(self.out.len(), start[bi]);
            self.next = start[bi] + 1;
            let mut cur = BlockData {
                params: b.params,
                insts: Vec::with_capacity(b.insts.len()),
                term: Term::Unreachable,
                term_loc: b.term_loc,
            };
            for inst in b.insts {
                if expands(inst.op) {
                    cur = self.expand(inst, cur);
                } else {
                    cur.insts.push(inst);
                }
            }
            let mut term = b.term;
            renumber(&mut term, &start);
            cur.term = term;
            self.out.push(cur);
        }
        debug_assert_eq!(self.out.len(), total);
        self.out.extend(self.faults);
        self.out
    }

    fn value(&mut self, ty: Ty) -> Value {
        self.f.new_value(ty)
    }

    fn emit(
        &mut self,
        b: &mut BlockData,
        op: Op,
        args: &[Value],
        imm: Imm,
        ty: Ty,
        loc: Loc,
    ) -> Value {
        let res = self.value(ty);
        b.insts.push(Inst {
            op,
            args: args.to_vec(),
            imm,
            res: Some(res),
            loc,
        });
        res
    }

    fn int(&mut self, b: &mut BlockData, n: i64, loc: Loc) -> Value {
        self.emit(b, Op::IConst, &[], Imm::Int(n), Ty::INT, loc)
    }

    /// Ends `cur` with a branch on `ok` to the next block of the chain, or to a new fault block
    /// that holds `fault`, and returns the next block, ready for the rest of the instructions.
    fn guard(&mut self, mut cur: BlockData, ok: Value, fault: BlockData) -> BlockData {
        let to_fault = Block((self.fault_base + self.faults.len()) as u32);
        self.faults.push(fault);
        self.f.cold.insert(to_fault);
        let cont = Block(self.next as u32);
        self.next += 1;
        cur.term = Term::CondBr {
            cond: ok,
            then: Target::to(cont),
            els: Target::to(to_fault),
        };
        self.out.push(cur);
        BlockData::new()
    }

    fn expand(&mut self, inst: Inst, mut cur: BlockData) -> BlockData {
        let loc = inst.loc;
        match inst.op {
            Op::ListPush => self.push(inst, cur),
            Op::OptUnwrap => {
                if self.checks {
                    let some = self.emit(
                        &mut cur,
                        Op::OptIsSome,
                        &inst.args,
                        Imm::None,
                        Ty::BOOL,
                        loc,
                    );
                    let fault = BlockData {
                        params: Vec::new(),
                        insts: Vec::new(),
                        term: Term::Fault(FaultKind::NoneUnwrap),
                        term_loc: loc,
                    };
                    cur = self.guard(cur, some, fault);
                }
                cur.insts.push(inst);
                cur
            }
            op => {
                // A list access: `list.get`, `list.set`, `list.fill` and `list.addr` count a
                // negative index from the end; the `.nn` forms know it is not negative.
                let (l, i) = (inst.args[0], inst.args[1]);
                let wraps = matches!(op, Op::ListGet | Op::ListSet | Op::ListFill | Op::ListAddr);
                let needs_len = self.checks || wraps;
                let len = needs_len
                    .then(|| self.emit(&mut cur, Op::ListLen, &[l], Imm::None, Ty::INT, loc));
                let idx = if wraps {
                    let len = len.expect("length computed");
                    let zero = self.int(&mut cur, 0, loc);
                    let neg = self.emit(
                        &mut cur,
                        Op::ICmp,
                        &[i, zero],
                        Imm::Cc(Cc::Lt),
                        Ty::BOOL,
                        loc,
                    );
                    let wrapped = self.emit(&mut cur, Op::IAdd, &[i, len], Imm::None, Ty::INT, loc);
                    self.emit(
                        &mut cur,
                        Op::Select,
                        &[neg, wrapped, i],
                        Imm::None,
                        Ty::INT,
                        loc,
                    )
                } else {
                    i
                };
                if self.checks {
                    let len = len.expect("length computed");
                    let ok = self.emit(
                        &mut cur,
                        Op::UICmp,
                        &[idx, len],
                        Imm::Cc(Cc::Lt),
                        Ty::BOOL,
                        loc,
                    );
                    let call = self.value(Ty::VOID);
                    let fault = BlockData {
                        params: Vec::new(),
                        insts: vec![Inst {
                            op: Op::CallRt,
                            args: vec![i, len],
                            imm: Imm::Ext(self.index_fault),
                            res: Some(call),
                            loc,
                        }],
                        term: Term::Unreachable,
                        term_loc: loc,
                    };
                    cur = self.guard(cur, ok, fault);
                }
                let unchecked = match op {
                    Op::ListGet | Op::ListGetNn => Op::ListGetU,
                    Op::ListSet | Op::ListSetNn => Op::ListSetU,
                    Op::ListFill => Op::ListFillU,
                    _ => Op::ListAddrU,
                };
                let mut args = inst.args;
                args[1] = idx;
                cur.insts.push(Inst {
                    op: unchecked,
                    args,
                    imm: inst.imm,
                    res: inst.res,
                    loc,
                });
                cur
            }
        }
    }

    /// `list.push l, v`: when the list is full, grow it to 4 elements if it is empty and to
    /// twice its capacity otherwise, then store the element after the last.
    fn push(&mut self, inst: Inst, mut cur: BlockData) -> BlockData {
        let loc = inst.loc;
        let (l, v) = (inst.args[0], inst.args[1]);
        let ty = self.f.ty(l);
        let len = self.emit(&mut cur, Op::ListLen, &[l], Imm::None, Ty::INT, loc);
        let cap = self.emit(&mut cur, Op::ListCap, &[l], Imm::None, Ty::INT, loc);
        let full = self.emit(
            &mut cur,
            Op::ICmp,
            &[len, cap],
            Imm::Cc(Cc::Eq),
            Ty::BOOL,
            loc,
        );
        let (grow, ready) = (Block(self.next as u32), Block(self.next as u32 + 1));
        self.next += 2;
        self.f.cold.insert(grow);
        cur.term = Term::CondBr {
            cond: full,
            then: Target::to(grow),
            els: Target {
                block: ready,
                args: vec![l],
            },
        };
        self.out.push(cur);
        let mut g = BlockData::new();
        g.term_loc = loc;
        let zero = self.int(&mut g, 0, loc);
        let empty = self.emit(
            &mut g,
            Op::ICmp,
            &[cap, zero],
            Imm::Cc(Cc::Eq),
            Ty::BOOL,
            loc,
        );
        let one = self.int(&mut g, 1, loc);
        let doubled = self.emit(&mut g, Op::Shl, &[cap, one], Imm::None, Ty::INT, loc);
        let four = self.int(&mut g, 4, loc);
        let ncap = self.emit(
            &mut g,
            Op::Select,
            &[empty, four, doubled],
            Imm::None,
            Ty::INT,
            loc,
        );
        let grown = self.emit(&mut g, Op::ListGrow, &[l, ncap], Imm::None, ty, loc);
        g.term = Term::Br(Target {
            block: ready,
            args: vec![grown],
        });
        self.out.push(g);
        let list = self.value(ty);
        let mut r = BlockData::new();
        r.params.push(BlockParam {
            value: list,
            mode: Mode::Move,
        });
        r.insts.push(Inst {
            op: Op::ListPushU,
            args: vec![list, v],
            imm: Imm::None,
            res: inst.res,
            loc,
        });
        r
    }
}

/// Points the targets of an original terminator at the new numbers of the blocks they name.
fn renumber(term: &mut Term, start: &[usize]) {
    let one = |t: &mut Target| t.block = Block(start[t.block.index()] as u32);
    match term {
        Term::Br(t) => one(t),
        Term::CondBr { then, els, .. } => {
            one(then);
            one(els);
        }
        Term::Switch { cases, default, .. } => {
            cases.iter_mut().for_each(|(_, t)| one(t));
            one(default);
        }
        Term::Ret(_) | Term::Fault(_) | Term::Unreachable => {}
    }
}
