//! Lowers `depth.enter`, the stack-depth check of a recursive function, to ordinary operations.
//!
//! The check runs first in the function: when the stack pointer is below the task's limit
//! (`stack.low`), the function runs again on a new stack segment. Its entry parameters are stored
//! in a heap block, `task.grow` calls the function's grow shim there with the block, and the
//! function returns what that run left in the block. The shim is a small function of its own that
//! loads the parameters, calls the function and stores the result. Both backends see only
//! `stack.low`, memory operations and calls, so neither has to know the protocol.
//!
//! Runs last, after `unwind`: the check must stay the first instruction of the entry block while
//! the other passes look for it.

use crate::ir::{
    ExternDef, ExternRole, Func, FuncId, Imm, Inst, Loc, Mode, Module, Op, Param, Target, Term,
};
use crate::layout::Layouts;
use crate::types::Ty;

/// Replaces every `depth.enter` in `m`; whether there was one.
pub fn lower(m: &mut Module) -> bool {
    let todo: Vec<usize> = (0..m.funcs.len())
        .filter(|&i| {
            m.funcs[i]
                .blocks
                .first()
                .and_then(|b| b.insts.first())
                .is_some_and(|i| i.op == Op::DepthEnter)
        })
        .collect();
    if todo.is_empty() {
        return false;
    }
    let ext = |m: &mut Module, name: &str, params: &[Ty], ret: Ty, role, fresh| {
        m.push_extern(ExternDef {
            name: name.to_string(),
            params: params
                .iter()
                .map(|&ty| Param {
                    ty,
                    mode: Mode::Borrow,
                })
                .collect(),
            ret,
            noreturn: false,
            pure_: false,
            fresh,
            leaf: false,
            reads: false,
            role,
        })
    };
    let rt = Runtime {
        alloc: ext(m, "msrt_alloc", &[Ty::INT], Ty::PTR, ExternRole::None, true),
        free: ext(
            m,
            "msrt_free",
            &[Ty::PTR],
            Ty::VOID,
            ExternRole::None,
            false,
        ),
        grow: ext(
            m,
            "msrt_task_grow",
            &[Ty::PTR, Ty::PTR],
            Ty::VOID,
            ExternRole::GrowStack,
            false,
        ),
    };
    for i in todo {
        expand(m, i, &rt);
    }
    true
}

struct Runtime {
    alloc: crate::ir::ExtId,
    free: crate::ir::ExtId,
    grow: crate::ir::ExtId,
}

/// Where each entry parameter and the result sit in the block, and the block's size.
struct Cells {
    params: Vec<i64>,
    result: i64,
    size: i64,
}

fn cells(lay: &Layouts, f: &Func) -> Cells {
    let mut off = 0i64;
    let mut place = |ty: Ty| {
        let mem = lay.mem(ty);
        let align = i64::from(mem.align);
        off = (off + align - 1) / align * align;
        let at = off;
        off += i64::from(mem.size);
        at
    };
    let params = f.params.iter().map(|p| place(p.ty)).collect();
    let result = place(f.ret);
    Cells {
        params,
        result,
        size: (off + 7) / 8 * 8,
    }
}

/// Appends instructions to a block of `f`.
struct Emit<'a> {
    f: &'a mut Func,
    block: usize,
    loc: Loc,
}

impl Emit<'_> {
    fn op(
        &mut self,
        op: Op,
        args: &[crate::ir::Value],
        imm: Imm,
        ty: Option<Ty>,
    ) -> crate::ir::Value {
        let res = ty.map(|t| self.f.new_value(t));
        self.f.blocks[self.block].insts.push(Inst {
            op,
            args: args.to_vec(),
            imm,
            res,
            loc: self.loc,
        });
        res.unwrap_or(crate::ir::Value(0))
    }

    fn int(&mut self, n: i64) -> crate::ir::Value {
        self.op(Op::IConst, &[], Imm::Int(n), Some(Ty::INT))
    }

    /// The address `off` bytes into `base`.
    fn at(&mut self, base: crate::ir::Value, off: i64) -> crate::ir::Value {
        if off == 0 {
            return base;
        }
        let n = self.int(off);
        self.op(Op::PtrAdd, &[base, n], Imm::None, Some(Ty::PTR))
    }

    fn call(
        &mut self,
        e: crate::ir::ExtId,
        args: &[crate::ir::Value],
        ret: Ty,
    ) -> crate::ir::Value {
        self.op(Op::CallRt, args, Imm::Ext(e), Some(ret))
    }
}

fn expand(m: &mut Module, fi: usize, rt: &Runtime) {
    // The new instructions carry no location: the check is not source code, and a position on its
    // call would add a frame to the stack trace of an overflow.
    let loc = Loc::NONE;
    let (cells, params, ret, name, floc) = {
        let lay = Layouts::new(m);
        let f = &m.funcs[fi];
        (
            cells(&lay, f),
            f.params.clone(),
            f.ret,
            f.name.clone(),
            f.loc,
        )
    };
    // The shim: `fn(block)` loads the parameters, runs the function and stores its result.
    let mut shim = Func::new(
        &format!("{name}.grow"),
        vec![Param {
            ty: Ty::PTR,
            mode: Mode::Borrow,
        }],
        Ty::VOID,
    );
    shim.loc = floc;
    let block = shim.blocks[0].params[0].value;
    let mut e = Emit {
        f: &mut shim,
        block: 0,
        loc,
    };
    let args: Vec<_> = params
        .iter()
        .zip(&cells.params)
        .map(|(p, &off)| {
            let at = e.at(block, off);
            let op = if p.mode == Mode::Borrow {
                Op::Load
            } else {
                Op::Take
            };
            e.op(op, &[at], Imm::Ty(p.ty), Some(p.ty))
        })
        .collect();
    let result = e.op(Op::Call, &args, Imm::Func(FuncId(fi as u32)), Some(ret));
    if ret != Ty::VOID {
        let at = e.at(block, cells.result);
        e.op(Op::Put, &[at, result], Imm::None, None);
    }
    let done = e.op(Op::VoidConst, &[], Imm::None, Some(Ty::VOID));
    shim.blocks[0].term = Term::Ret(Some(done));
    shim.blocks[0].term_loc = loc;
    let shim_id = m.add_func(shim);

    // The check, then the grow path out of line.
    let f = &mut m.funcs[fi];
    let entry = std::mem::take(&mut f.blocks[0]);
    let entry_params = entry.params.clone();
    let mut rest = entry.insts;
    rest.remove(0);
    let grow = f.blocks.len();
    let cont = grow + 1;
    f.blocks.push(crate::ir::BlockData::new());
    f.blocks.push(crate::ir::BlockData {
        params: Vec::new(),
        insts: rest,
        term: entry.term,
        term_loc: entry.term_loc,
    });
    f.blocks[0].params = entry_params.clone();
    let mut e = Emit { f, block: 0, loc };
    let low = e.op(Op::StackLow, &[], Imm::None, Some(Ty::BOOL));
    e.f.blocks[0].term = Term::CondBr {
        cond: low,
        then: Target::to(crate::ir::Block(grow as u32)),
        els: Target::to(crate::ir::Block(cont as u32)),
    };
    e.f.blocks[0].term_loc = loc;
    e.block = grow;
    let size = e.int(cells.size.max(8));
    let blk = e.call(rt.alloc, &[size], Ty::PTR);
    for ((p, bp), &off) in params.iter().zip(&entry_params).zip(&cells.params) {
        let at = e.at(blk, off);
        let op = if p.mode == Mode::Borrow {
            Op::Store
        } else {
            Op::Put
        };
        e.op(op, &[at, bp.value], Imm::None, None);
    }
    let shim_addr = e.op(Op::FuncAddr, &[], Imm::Func(shim_id), Some(Ty::PTR));
    e.call(rt.grow, &[shim_addr, blk], Ty::VOID);
    let out = if ret == Ty::VOID {
        e.op(Op::VoidConst, &[], Imm::None, Some(Ty::VOID))
    } else {
        let at = e.at(blk, cells.result);
        e.op(Op::Take, &[at], Imm::Ty(ret), Some(ret))
    };
    e.call(rt.free, &[blk], Ty::VOID);
    e.f.blocks[grow].term = Term::Ret(Some(out));
    e.f.blocks[grow].term_loc = loc;
}
