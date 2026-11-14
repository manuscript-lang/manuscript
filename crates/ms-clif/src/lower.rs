//! Lowering of one MIR function (or glue function) to Cranelift IR.

use crate::cg::{CLOSURE_CAPTURES, CLOSURE_CODE, Gen, Glue, leaf_type, mem_type};
use crate::layout::{AltRepr, Leaf, mem_layout};
use cranelift_codegen::ir::condcodes::{CondCode, FloatCC, IntCC};
use cranelift_codegen::ir::{
    self, BlockArg, FuncRef, GlobalValue, InstBuilder, InstructionData, MemFlagsData, Opcode,
    StackSlotData, StackSlotKind, TrapCode, Value, ValueDef, types,
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_module::{DataId, FuncId, Module as _};
use ms_mir::ir::{Cc, ExternRole, FaultKind, Func, Imm, Inst, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::symbols::{ISOLATE_HDR_CANCEL, ISOLATE_HDR_GUARDED, STACK_LIMIT_CELL, STACK_REGION};
use ms_rt_abi::{
    ASCII_CHAR_STRIDE, STR_ASCII, STR_INLINE, STR_INLINE_LEN_SHIFT, STR_INLINE_MAX, STR_LEN_MASK,
    STR_LEN_OFFSET, STR_PTR_OFFSET, STR_STATIC, VEC_CAP_OFFSET, VEC_LEN_OFFSET, VEC_PTR_OFFSET,
};
use std::collections::{HashMap, HashSet};

type Vs = Vec<Value>;

mod call;
mod closure;
mod data;
mod glue;
mod list;
mod memory;
mod runtime;
mod scalar;
mod string;

fn flags() -> MemFlagsData {
    MemFlagsData::trusted()
}

/// Where a wide value (`Map`, `Set`: seven words) also lives in memory, so calls take its
/// address instead of spilling a copy. A home on a block parameter holds for the rest of the
/// function; any other holds only within the block that created it (`blk`).
#[derive(Clone, Copy)]
struct Home {
    addr: Value,
    slot: Option<ir::StackSlot>,
    blk: Option<usize>,
}

pub struct Lower<'a, 'm> {
    g: &'a mut Gen<'m>,
    b: FunctionBuilder<'a>,
    frefs: HashMap<FuncId, FuncRef>,
    grefs: HashMap<DataId, GlobalValue>,
    vals: Vec<Vs>,
    /// Memory copies of `Map`/`Set` values (see [`Home`]), by MIR value index.
    homes: Vec<Option<Home>>,
    /// Stack slot behind each MIR value that holds a slot address.
    slot_of: HashMap<usize, ir::StackSlot>,
    /// `iface.borrow` results that only reach calls and drops: their leaves live in a stack slot.
    framed_ifaces: HashSet<usize>,
    /// `closure.new` results that only calls borrow and drops release: their objects live in a stack slot.
    framed_closures: HashSet<usize>,
    /// Block that defined each MIR `slot` value.
    slot_blk: HashMap<usize, usize>,
    /// MIR values that an already lowered instruction used.
    used: Vec<bool>,
    /// String literal index behind each MIR value defined by `str`.
    str_lits: HashMap<usize, u32>,
    /// Home slot of each wide block parameter, by `(block, parameter)`.
    pslots: HashMap<(usize, usize), ir::StackSlot>,
    /// Wide block parameters whose leaves are loaded from their home at each use.
    lazy: Vec<bool>,
    /// Quotients of the signed divisions lowered so far in this block, by operands, so a
    /// remainder of the same operands reuses the divide.
    quotients: HashMap<(Value, Value), Value>,
    /// The same for remainders: the quotient by the divisor with -1 replaced by 1.
    safe_quotients: HashMap<(Value, Value), Value>,
    /// MIR block being lowered.
    cur: usize,
    /// MIR function being lowered (the key of its grow shim).
    fid: u32,
    /// Result paired with the preceding overflow flag. Reuse only on the very
    /// next instruction, so the defining instruction always dominates the use.
    overflow_result: Option<(Op, Value, Value, Value)>,
    blocks: Vec<Option<ir::Block>>,
    /// First unsupported construct met, reported by the driver.
    pub unsupported: Option<String>,
    /// Slots of statement-scoped temporaries, merged between blocks by `slotshare`.
    temps: Vec<ir::StackSlot>,
}

fn bargs(vs: &[Value]) -> Vec<BlockArg> {
    vs.iter().map(|v| BlockArg::Value(*v)).collect()
}

impl<'a, 'm> Lower<'a, 'm> {
    pub fn new(
        g: &'a mut Gen<'m>,
        func: &'a mut ir::Function,
        fctx: &'a mut FunctionBuilderContext,
    ) -> Self {
        Lower {
            g,
            b: FunctionBuilder::new(func, fctx),
            frefs: HashMap::new(),
            grefs: HashMap::new(),
            vals: Vec::new(),
            homes: Vec::new(),
            slot_of: HashMap::new(),
            framed_ifaces: HashSet::new(),
            framed_closures: HashSet::new(),
            slot_blk: HashMap::new(),
            used: Vec::new(),
            str_lits: HashMap::new(),
            pslots: HashMap::new(),
            lazy: Vec::new(),
            quotients: HashMap::new(),
            safe_quotients: HashMap::new(),
            cur: 0,
            fid: 0,
            overflow_result: None,
            blocks: Vec::new(),
            unsupported: None,
            temps: Vec::new(),
        }
    }

    /// Finishes the function and returns the slots of its temporaries for `slotshare::share`.
    pub fn finish(mut self) -> Vec<ir::StackSlot> {
        self.b.seal_all_blocks();
        let config = self.g.module.target_config();
        let temps = std::mem::take(&mut self.temps);
        self.b.finalize(config);
        temps
    }

    /// A new slot for a temporary that lives within one statement.
    fn temp_slot(&mut self, size: u32) -> ir::StackSlot {
        let slot = self.new_slot(size);
        self.temps.push(slot);
        slot
    }

    // ---- small helpers ---------------------------------------------------

    fn set_loc(&mut self, loc: ms_mir::ir::Loc) {
        let bits = self.g.loc_bits(loc);
        self.b.set_srcloc(ir::SourceLoc::new(bits));
    }

    fn unsupported(&mut self, what: &str) {
        if self.unsupported.is_none() {
            self.unsupported = Some(what.to_string());
        }
    }

    fn iconst(&mut self, v: i64) -> Value {
        self.b.ins().iconst(types::I64, v)
    }

    fn const_of(&self, v: Value) -> Option<i64> {
        let dfg = &self.b.func.dfg;
        let ValueDef::Result(i, _) = dfg.value_def(v) else {
            return None;
        };
        match dfg.insts[i] {
            InstructionData::UnaryImm {
                opcode: Opcode::Iconst,
                imm,
            } => Some(imm.bits()),
            _ => None,
        }
    }

    /// The constant operand of a multiplication and the other operand.
    fn mul_const(&self, x: Value, y: Value) -> Option<(Value, i64)> {
        match (self.const_of(x), self.const_of(y)) {
            (_, Some(c)) => Some((x, c)),
            (Some(c), _) => Some((y, c)),
            _ => None,
        }
    }

    /// `x * y`, using shifts and adds (which fold into `lea`) for small constants.
    fn mul(&mut self, x: Value, y: Value) -> Value {
        if let Some((x, c)) = self.mul_const(x, y) {
            match c {
                1 => return x,
                c if c > 1 && (c as u64).is_power_of_two() => {
                    return self.b.ins().ishl_imm_u(x, c.trailing_zeros() as i64);
                }
                3 | 5 | 9 => {
                    let t = self.b.ins().ishl_imm_u(x, (c - 1).trailing_zeros() as i64);
                    return self.b.ins().iadd(x, t);
                }
                _ => {}
            }
        }
        self.b.ins().imul(x, y)
    }

    /// `x * y` and its signed-overflow flag; a constant factor is a range check.
    fn mul_overflow(&mut self, x: Value, y: Value) -> (Value, Value) {
        if let Some((x, c)) = self.mul_const(x, y)
            && c >= 2
        {
            let (lo, hi) = (i64::MIN / c, i64::MAX / c);
            let off = self.b.ins().iadd_imm_s(x, lo.wrapping_neg());
            let of = self
                .b
                .ins()
                .icmp_imm_u(IntCC::UnsignedGreaterThan, off, hi.wrapping_sub(lo));
            let k = self.iconst(c);
            return (self.mul(x, k), of);
        }
        self.b.ins().smul_overflow(x, y)
    }

    fn zero(&mut self, l: Leaf) -> Value {
        match l {
            Leaf::I64 => self.b.ins().iconst(types::I64, 0),
            Leaf::I8 => self.b.ins().iconst(types::I8, 0),
            Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                self.b.ins().iconst(types::I64, 0)
            }
            Leaf::F64 => self.b.ins().f64const(0.0),
            Leaf::F32 => self.b.ins().f32const(0.0),
        }
    }

    fn zeros(&mut self, ty: Ty) -> Vs {
        if self.g.lay.is_str_like(ty) && !matches!(self.g.m.types.kind(ty), TyKind::Str) {
            // An absent `String?`: static, so dropping and copying it do nothing.
            return vec![self.iconst(0), self.iconst(STR_STATIC as i64)];
        }
        self.g
            .lay
            .leaves(ty)
            .into_iter()
            .map(|l| self.zero(l))
            .collect()
    }

    fn fref(&mut self, id: FuncId) -> FuncRef {
        if let Some(r) = self.frefs.get(&id) {
            return *r;
        }
        let r = self.g.module.declare_func_in_func(id, self.b.func);
        self.frefs.insert(id, r);
        r
    }

    /// `v` as the float type `to`: runtime and native signatures carry `Float32` as `f64`, and
    /// the binary32 value converts exactly both ways.
    fn float_as(&mut self, v: Value, to: ir::Type) -> Value {
        let from = self.b.func.dfg.value_type(v);
        if from == to || !from.is_float() || !to.is_float() {
            v
        } else if to == types::F64 {
            self.b.ins().fpromote(types::F64, v)
        } else {
            self.b.ins().fdemote(types::F32, v)
        }
    }

    /// A call of a user shim: 64-bit registers narrow to the C parameter types, and narrow C
    /// results widen back. A result that does not pass directly goes through the trailing
    /// `out` the lowering added, so the call returns at most one scalar.
    fn call_c_extern(&mut self, id: FuncId, args: &[Value], ret: Ty) -> Vs {
        let r = self.fref(id);
        let sig = self.b.func.dfg.ext_funcs[r].signature;
        let want = self.b.func.dfg.signatures[sig].params.clone();
        let rets = self.b.func.dfg.signatures[sig].returns.clone();
        let args: Vec<Value> = args
            .iter()
            .zip(&want)
            .map(|(a, p)| {
                let from = self.b.func.dfg.value_type(*a);
                if from == types::I64 && p.value_type.is_int() && p.value_type.bits() < 64 {
                    self.b.ins().ireduce(p.value_type, *a)
                } else {
                    self.float_as(*a, p.value_type)
                }
            })
            .collect();
        let i = self.b.ins().call(r, &args);
        let out = self.b.inst_results(i).to_vec();
        let leaves = if Self::passes_directly(&self.g.lay, ret) {
            self.g.lay.leaves(ret)
        } else {
            Vec::new()
        };
        out.iter()
            .zip(&rets)
            .zip(leaves)
            .map(|((v, p), l)| {
                let want = leaf_type(l);
                if want == p.value_type {
                    return *v;
                }
                match c_param(l).extension {
                    ir::ArgumentExtension::Sext => self.b.ins().sextend(want, *v),
                    _ => self.b.ins().uextend(want, *v),
                }
            })
            .collect()
    }

    fn call_id(&mut self, id: FuncId, args: &[Value]) -> Vs {
        let r = self.fref(id);
        let sig = self.b.func.dfg.ext_funcs[r].signature;
        let want: Vec<ir::Type> = self.b.func.dfg.signatures[sig]
            .params
            .iter()
            .map(|p| p.value_type)
            .collect();
        let args: Vec<Value> = args
            .iter()
            .enumerate()
            .map(|(k, a)| match want.get(k) {
                Some(t) => self.float_as(*a, *t),
                None => *a,
            })
            .collect();
        let i = self.b.ins().call(r, &args);
        self.b.inst_results(i).to_vec()
    }

    fn rt_call(&mut self, name: &'static str, args: &[Value]) -> Vs {
        let id = self.g.rt(name);
        self.call_id(id, args)
    }

    fn data_addr(&mut self, id: DataId) -> Value {
        let gv = match self.grefs.get(&id) {
            Some(gv) => *gv,
            None => {
                let gv = self.g.module.declare_data_in_func(id, self.b.func);
                self.grefs.insert(id, gv);
                gv
            }
        };
        self.b.ins().symbol_value(types::I64, gv)
    }

    /// The running task's header block (see `ms_rt_abi::symbols::ISOLATE_HDR`).
    fn task_hdr(&mut self) -> Value {
        // The last 16 bytes of the stack's region point at the running task's block.
        let sp = self.b.ins().get_stack_pointer(types::I64);
        let base = self.b.ins().band_imm_s(sp, !(STACK_REGION - 1));
        let cell = self.b.ins().iadd_imm_s(base, STACK_REGION - 16);
        self.b.ins().load(types::I64, flags(), cell, 0)
    }

    fn add_imm(&mut self, p: Value, off: i64) -> Value {
        if off == 0 {
            p
        } else {
            self.b.ins().iadd_imm_s(p, off)
        }
    }

    fn load_leaves(&mut self, ptr: Value, base: i64, leaves: &[Leaf]) -> Vs {
        let lay = mem_layout(leaves);
        leaves
            .iter()
            .zip(&lay.offsets)
            .map(|(l, o)| self.load_leaf(*l, ptr, (base + *o as i64) as i32))
            .collect()
    }

    /// Reads a leaf from memory into its register type, widening a packed number.
    fn load_leaf(&mut self, l: Leaf, ptr: Value, off: i32) -> Value {
        let flags = self.mem_flags();
        let v = self.b.ins().load(mem_type(l), flags, ptr, off);
        match l {
            Leaf::N8 | Leaf::N16 | Leaf::N32 => self.b.ins().sextend(types::I64, v),
            Leaf::U8 | Leaf::U16 | Leaf::U32 => self.b.ins().uextend(types::I64, v),
            _ => v,
        }
    }

    /// Writes a leaf's register value to memory, narrowing a packed number.
    fn store_leaf(&mut self, l: Leaf, v: Value, ptr: Value, off: i32) {
        let v = match l {
            Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                self.b.ins().ireduce(mem_type(l), v)
            }
            _ => v,
        };
        let flags = self.mem_flags();
        self.b.ins().store(flags, v, ptr, off);
    }

    /// Flags of a leaf access, with the alias region of the list element being accessed.
    fn mem_flags(&self) -> MemFlagsData {
        flags()
    }

    fn store_leaves(&mut self, ptr: Value, base: i64, leaves: &[Leaf], vs: &[Value]) {
        let lay = mem_layout(leaves);
        for ((l, v), o) in leaves.iter().zip(vs).zip(&lay.offsets) {
            self.store_leaf(*l, *v, ptr, (base + *o as i64) as i32);
        }
    }

    /// Runs `body` when `cond` holds; `body` must fall through to the join.
    fn if_then(&mut self, cond: Value, body: impl FnOnce(&mut Self)) {
        let then = self.b.create_block();
        let cont = self.b.create_block();
        self.b.ins().brif(cond, then, &[], cont, &[]);
        self.b.switch_to_block(then);
        body(self);
        self.b.ins().jump(cont, &[]);
        self.b.switch_to_block(cont);
    }

    /// Calls the never-returning runtime function `name` when `cond` holds.
    fn fault_if(&mut self, cond: Value, name: &'static str, args: Vec<Value>) {
        let fault = self.b.create_block();
        let cont = self.b.create_block();
        self.b.set_cold_block(fault);
        // Cranelift lays out the second successor first. The fault goes second so that the code
        // after the check follows the branch: a fault block placed after the rest of the function
        // keeps every value it reads live across it, and allocation is quadratic in a long function.
        let ok = self.negate(cond);
        self.b.ins().brif(ok, cont, &[], fault, &[]);
        self.b.switch_to_block(fault);
        self.rt_call(name, &args);
        self.b.ins().trap(TrapCode::unwrap_user(1));
        self.b.switch_to_block(cont);
    }

    /// The recursion check of a cyclic function: when the stack pointer is below the task's
    /// limit, the function runs again on a new stack segment (`msrt_task_grow` calls the
    /// function's grow shim there with the entry parameters, stored in a block on this frame)
    /// and returns that run's results. The check is the first thing the function does, so the
    /// parameters are still the caller's values (`ms_mir::verify`).
    fn depth_enter(&mut self) {
        // The limit sits in the region beside the block's address: one load from the masked
        // stack pointer.
        let sp = self.b.ins().get_stack_pointer(types::I64);
        let base = self.b.ins().band_imm_s(sp, !(STACK_REGION - 1));
        let limit = self.b.ins().load(
            types::I64,
            flags(),
            base,
            (STACK_REGION - STACK_LIMIT_CELL) as i32,
        );
        let over = self.b.ins().icmp(IntCC::UnsignedLessThan, sp, limit);
        let grow = self.b.create_block();
        let cont = self.b.create_block();
        self.b.set_cold_block(grow);
        let ok = self.negate(over);
        self.b.ins().brif(ok, cont, &[], grow, &[]);
        self.b.switch_to_block(grow);
        let entry = self.blocks[0].expect("entry block");
        let params = self.b.block_params(entry).to_vec();
        let returns: Vec<ir::Type> = self
            .b
            .func
            .signature
            .returns
            .iter()
            .map(|p| p.value_type)
            .collect();
        // The block is a heap allocation, not a frame slot: a slot would widen the frame of
        // every recursive function for a path taken once per segment.
        let block = self.alloc(((params.len() + returns.len()) * 8) as i64);
        for (i, p) in params.iter().enumerate() {
            self.b.ins().store(flags(), *p, block, (i * 8) as i32);
        }
        let shim = self.g.glue(Glue::GrowShim(self.fid), Ty::UNIT);
        let r = self.fref(shim);
        let fa = self.b.ins().func_addr(types::I64, r);
        self.rt_call("msrt_task_grow", &[fa, block]);
        let results: Vec<Value> = returns
            .iter()
            .enumerate()
            .map(|(j, t)| {
                self.b
                    .ins()
                    .load(*t, flags(), block, ((params.len() + j) * 8) as i32)
            })
            .collect();
        self.free(block);
        self.b.ins().return_(&results);
        self.b.switch_to_block(cont);
    }

    fn alloc(&mut self, size: i64) -> Value {
        let n = self.iconst(size.max(1));
        self.rt_call("msrt_alloc", &[n])[0]
    }

    fn free(&mut self, p: Value) {
        self.rt_call("msrt_free", &[p]);
    }

    // ---- ownership -------------------------------------------------------

    /// Drops the object `p` through its header's drop entry (the runtime ignores null).
    fn drop_obj(&mut self, p: Value) {
        self.rt_call("msrt_obj_drop", &[p]);
    }

    /// An independent copy of the object `p` through its header's clone entry (null stays null;
    /// a value with one owner faults).
    fn clone_obj(&mut self, p: Value) -> Value {
        self.rt_call("msrt_obj_clone", &[p])[0]
    }

    /// Whether dropping a value of `ty` is a call to glue (rather than inline or nothing).
    fn drop_value(&mut self, ty: Ty, vs: &[Value]) {
        let m = self.g.m;
        if !m.needs_drop(ty) {
            return;
        }
        match m.types.kind(ty) {
            _ if self.g.lay.is_str_like(ty) => {
                // A literal's capacity word is a known constant: nothing to free.
                if self
                    .const_of(vs[1])
                    .is_some_and(|cap| cap as u64 >= STR_INLINE as u64)
                {
                    return;
                }
                // Only an owned string (tag `00`) frees anything.
                let owned =
                    self.b
                        .ins()
                        .icmp_imm_s(IntCC::UnsignedLessThan, vs[1], STR_INLINE as i64);
                self.if_then(owned, |s| {
                    s.rt_call("msrt_str_free", &[vs[0]]);
                });
            }
            TyKind::Fn(..) => self.drop_obj(vs[0]),
            TyKind::Obj(n, _) if !n.is_map_or_set() => self.drop_obj(vs[0]),
            TyKind::Opt(inner)
                if self.g.lay.opt_is_nullable(*inner) && !self.g.lay.opt_is_boxed(*inner) =>
            {
                self.drop_obj(vs[0]);
            }
            _ => {
                let id = self.g.glue(Glue::Drop, ty);
                self.call_id(id, vs);
            }
        }
    }

    fn clone_value(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        if !m.needs_drop(ty) {
            return vs.to_vec();
        }
        match m.types.kind(ty) {
            _ if self.g.lay.is_str_like(ty) => {
                // A literal's capacity word is a known constant, so its tag is too.
                if let Some(cap) = self.const_of(vs[1])
                    && (cap as u64 >> 62).wrapping_sub(1) < 2
                {
                    return vs.to_vec();
                }
                // A static (`10`) or inline (`01`) string copies bitwise; an owned one or a
                // view is duplicated, inline when it is short.
                let tag = self.b.ins().ushr_imm_u(vs[1], 62);
                let tag = self.b.ins().iadd_imm_s(tag, -1);
                let shared = self.b.ins().icmp_imm_s(IntCC::UnsignedLessThan, tag, 2);
                let (dup, join) = (self.b.create_block(), self.b.create_block());
                for _ in 0..2 {
                    self.b.append_block_param(join, types::I64);
                }
                let same = [vs[0], vs[1]].map(BlockArg::Value);
                self.b.ins().brif(shared, join, &same, dup, &[]);
                self.b.switch_to_block(dup);
                let slot = self.temp_slot(16);
                let out = self.b.ins().stack_addr(types::I64, slot, 0);
                self.rt_call("msrt_str_copy", &[vs[0], vs[1], out]);
                let c = self.load_leaves(out, 0, &[Leaf::I64; 2]);
                self.b.ins().jump(join, &bargs(&c));
                self.b.switch_to_block(join);
                self.b.block_params(join).to_vec()
            }
            TyKind::Fn(..) => vec![self.clone_obj(vs[0])],
            TyKind::Obj(n, _) if !n.is_map_or_set() => vec![self.clone_obj(vs[0])],
            _ => {
                let id = self.g.glue(Glue::Clone, ty);
                self.call_id(id, vs)
            }
        }
    }

    // ---- glue ------------------------------------------------------------

    /// The address of the static descriptor for slots of type `ty`.
    fn typedesc_addr(&mut self, ty: Ty) -> Value {
        let d = self.g.typedesc(ty);
        self.data_addr(d)
    }

    /// Spills `vs` into a fresh stack slot laid out per `leaves` and returns its address. The slot
    /// stays valid for the whole function: use it where the runtime keeps the address (a cleanup
    /// entry).
    fn spill(&mut self, vs: &[Value], leaves: &[Leaf]) -> Value {
        self.spill_in(vs, leaves, false)
    }

    /// Like [`Self::spill`] for a value only read during one call; the slot may be shared with
    /// the temporaries of other blocks.
    fn spill_temp(&mut self, vs: &[Value], leaves: &[Leaf]) -> Value {
        self.spill_in(vs, leaves, true)
    }

    fn spill_in(&mut self, vs: &[Value], leaves: &[Leaf], temp: bool) -> Value {
        let lay = mem_layout(leaves);
        let slot = if temp {
            self.temp_slot(lay.size)
        } else {
            self.new_slot(lay.size)
        };
        let addr = self.b.ins().stack_addr(types::I64, slot, 0);
        self.store_leaves(addr, 0, leaves, vs);
        addr
    }

    /// Loads the leaves of lazy wide parameters among `vs` from their home slots.
    fn refresh(&mut self, f: &Func, vs: impl Iterator<Item = ms_mir::ir::Value>) {
        for v in vs {
            if self.lazy[v.index()] {
                let h = self.homes[v.index()].expect("lazy value has a home");
                let leaves = self.g.lay.leaves(f.ty(v));
                self.vals[v.index()] = self.load_leaves(h.addr, 0, &leaves);
            }
        }
    }

    fn is_wide(&self, ty: Ty) -> bool {
        matches!(self.g.m.types.kind(ty), TyKind::Str)
            || matches!(self.g.m.types.kind(ty), TyKind::Obj(n, _) if n.is_map_or_set())
    }

    fn new_slot(&mut self, size: u32) -> ir::StackSlot {
        self.b.create_sized_stack_slot(StackSlotData::new(
            StackSlotKind::ExplicitSlot,
            size.max(8),
            3,
        ))
    }

    /// The memory copy of MIR value `v`, when it has one that is valid here.
    fn home_of(&self, v: ms_mir::ir::Value) -> Option<Home> {
        self.homes[v.index()].filter(|h| h.blk.is_none_or(|b| b == self.cur))
    }

    /// Stores the wide arguments of an edge into the home slots of the target's parameters,
    /// except those that already live there.
    fn edge_stores(&self, t: &Target) -> Vec<(ir::StackSlot, Vs, Vec<Leaf>)> {
        let mut out = Vec::new();
        for (j, a) in t.args.iter().enumerate() {
            let Some(slot) = self.pslots.get(&(t.block.index(), j)) else {
                continue;
            };
            if self.home_of(*a).is_some_and(|h| h.slot == Some(*slot)) {
                continue;
            }
            let leaves = (0..self.vals[a.index()].len()).map(|_| Leaf::I64).collect();
            out.push((*slot, self.vals[a.index()].clone(), leaves));
        }
        out
    }

    fn emit_stores(&mut self, stores: Vec<(ir::StackSlot, Vs, Vec<Leaf>)>) {
        for (slot, vs, leaves) in stores {
            let addr = self.b.ins().stack_addr(types::I64, slot, 0);
            self.store_leaves(addr, 0, &leaves, &vs);
        }
    }
}

// ---- functions -------------------------------------------------------------

impl<'a, 'm> Lower<'a, 'm> {
    fn a(&self, inst: &Inst, i: usize) -> Vs {
        self.vals[inst.args[i].index()].clone()
    }

    fn set(&mut self, inst: &Inst, vs: Vs) {
        if let Some(r) = inst.res {
            self.vals[r.index()] = vs;
        }
    }

    fn target(&mut self, t: &Target) -> (ir::Block, Vec<BlockArg>) {
        let args: Vs = t
            .args
            .iter()
            .enumerate()
            .filter(|(j, _)| !self.pslots.contains_key(&(t.block.index(), *j)))
            .flat_map(|(_, a)| self.vals[a.index()].clone())
            .collect();
        (
            self.blocks[t.block.index()].expect("reachable block"),
            bargs(&args),
        )
    }

    fn framed_iface_borrows(&self, f: &Func) -> HashSet<usize> {
        ms_mir::frames::framed_iface_borrows(self.g.m, f)
    }

    fn framed_closure_objects(&self, f: &Func) -> HashSet<usize> {
        ms_mir::frames::framed_closure_objects(self.g.m, f)
    }

    pub fn lower_func(&mut self, fi: usize, f: &Func) {
        self.fid = fi as u32;
        let rpo = f.rpo();
        self.g.add_scopes(f);
        self.blocks = vec![None; f.blocks.len()];
        self.vals = vec![Vec::new(); f.values.len()];
        self.homes = vec![None; f.values.len()];
        self.used = vec![false; f.values.len()];
        self.lazy = vec![false; f.values.len()];
        self.slot_of.clear();
        self.framed_ifaces = self.framed_iface_borrows(f);
        self.framed_closures = self.framed_closure_objects(f);
        self.slot_blk.clear();
        self.pslots.clear();
        for b in &rpo {
            let cb = self.b.create_block();
            self.blocks[b.index()] = Some(cb);
            if b.index() == 0 {
                self.b.append_block_params_for_function_params(cb);
            } else {
                for (j, p) in f.blocks[b.index()].params.iter().enumerate() {
                    if self.is_wide(f.ty(p.value)) {
                        let size = self.g.lay.mem(f.ty(p.value)).size;
                        let slot = self.new_slot(size);
                        self.pslots.insert((b.index(), j), slot);
                        continue;
                    }
                    for l in self.g.lay.leaves(f.ty(p.value)) {
                        self.b.append_block_param(cb, leaf_type(l));
                    }
                }
            }
        }
        for b in &rpo {
            let cb = self.blocks[b.index()].expect("created");
            self.b.switch_to_block(cb);
            // Bind block parameters.
            self.cur = b.index();
            self.quotients.clear();
            self.safe_quotients.clear();
            let params = self.b.block_params(cb).to_vec();
            let mut at = 0;
            for (j, p) in f.blocks[b.index()].params.iter().enumerate() {
                let ty = f.ty(p.value);
                if let Some(slot) = self.pslots.get(&(b.index(), j)).copied() {
                    let addr = self.b.ins().stack_addr(types::I64, slot, 0);
                    self.lazy[p.value.index()] = true;
                    self.homes[p.value.index()] = Some(Home {
                        addr,
                        slot: Some(slot),
                        blk: None,
                    });
                    continue;
                }
                let w = self.g.lay.width(ty);
                self.vals[p.value.index()] = params[at..at + w].to_vec();
                at += w;
                if b.index() == 0 && self.is_wide(ty) {
                    let leaves = self.g.lay.leaves(ty);
                    let size = self.g.lay.mem(ty).size;
                    let slot = self.new_slot(size);
                    let addr = self.b.ins().stack_addr(types::I64, slot, 0);
                    let vs = self.vals[p.value.index()].clone();
                    self.store_leaves(addr, 0, &leaves, &vs);
                    self.homes[p.value.index()] = Some(Home {
                        addr,
                        slot: Some(slot),
                        blk: None,
                    });
                }
            }
            self.overflow_result = None;
            for inst in &f.blocks[b.index()].insts {
                self.set_loc(inst.loc);
                self.refresh(f, inst.args.iter().copied());
                self.lower_inst(f, inst);
                for a in &inst.args {
                    self.used[a.index()] = true;
                }
            }
            self.set_loc(f.blocks[b.index()].term_loc);
            let mut uses = Vec::new();
            f.blocks[b.index()].term.for_each_use(|v| uses.push(v));
            self.refresh(f, uses.into_iter());
            self.lower_term(f, &f.blocks[b.index()].term);
        }
    }

    pub fn lower_main(&mut self, fid: FuncId) {
        let blk = self.b.create_block();
        self.b.append_block_params_for_function_params(blk);
        self.b.switch_to_block(blk);
        let p = self.b.block_params(blk).to_vec();
        let (argc, argv) = (self.b.ins().sextend(types::I64, p[0]), p[1]);
        let fref = self.fref(fid);
        let faddr = self.b.ins().func_addr(types::I64, fref);
        let tables = match self.g.tables {
            Some(id) => {
                let gv = self.g.module.declare_data_in_func(id, self.b.func);
                self.b.ins().symbol_value(types::I64, gv)
            }
            None => self.iconst(0),
        };
        let r = self.rt_call("msrt_start", &[faddr, tables, argc, argv])[0];
        let r32 = self.b.ins().ireduce(types::I32, r);
        self.b.ins().return_(&[r32]);
    }

    /// The negation of the boolean `c`, folding into the comparison that produced it.
    fn negate(&mut self, c: Value) -> Value {
        if let ValueDef::Result(i, _) = self.b.func.dfg.value_def(c)
            && let InstructionData::IntCompare {
                opcode: Opcode::Icmp,
                args: [x, y],
                cond,
            } = self.b.func.dfg.insts[i]
        {
            return self.b.ins().icmp(cond.complement(), x, y);
        }
        self.b.ins().icmp_imm_s(IntCC::Equal, c, 0)
    }

    /// The arguments of a join block reached by both edges of a branch on `c`: the common value,
    /// or a `select` between the two.
    fn select_args(
        &mut self,
        c: Value,
        then: &[BlockArg],
        els: &[BlockArg],
    ) -> Option<Vec<BlockArg>> {
        let mut out = Vec::with_capacity(then.len());
        for (t, e) in then.iter().zip(els) {
            let (BlockArg::Value(t), BlockArg::Value(e)) = (t, e) else {
                return None;
            };
            let v = if t == e {
                *t
            } else {
                self.b.ins().select(c, *t, *e)
            };
            out.push(BlockArg::Value(v));
        }
        Some(out)
    }

    fn lower_term(&mut self, f: &Func, t: &Term) {
        match t {
            Term::Br(tg) => {
                let (b, args) = self.target(tg);
                let stores = self.edge_stores(tg);
                self.emit_stores(stores);
                self.b.ins().jump(b, &args);
            }
            Term::CondBr { cond, then, els } => {
                let mut c = self.vals[cond.index()][0];
                // Cranelift lays out the second successor first, so a loop test puts the
                // exit there only if the body is the second one: swap to keep the body
                // as the fall-through and the loop to one taken branch per iteration.
                let swap = continues_loop(f, self.cur, then.block.index(), els.block.index());
                let (then, els) = if swap {
                    c = self.negate(c);
                    (els, then)
                } else {
                    (then, els)
                };
                let (tb, ta) = self.target(then);
                let (eb, ea) = self.target(els);
                let (ts, es) = (self.edge_stores(then), self.edge_stores(els));
                if ts.is_empty() && es.is_empty() {
                    if tb == eb
                        && self.g.opts.opt_level != "none"
                        && let Some(args) = self.select_args(c, &ta, &ea)
                    {
                        // Both edges reach one block: pick each argument with a conditional move
                        // instead of branching on data that is often unpredictable (`min`, `max`).
                        self.b.ins().jump(tb, &args);
                    } else {
                        self.b.ins().brif(c, tb, &ta, eb, &ea);
                    }
                } else {
                    let (tt, te) = (self.b.create_block(), self.b.create_block());
                    self.b.ins().brif(c, tt, &[], te, &[]);
                    self.b.switch_to_block(tt);
                    self.emit_stores(ts);
                    self.b.ins().jump(tb, &ta);
                    self.b.switch_to_block(te);
                    self.emit_stores(es);
                    self.b.ins().jump(eb, &ea);
                }
            }
            Term::Switch {
                value,
                cases,
                default,
            } => {
                let v = self.vals[value.index()][0];
                let mut sw = Switch::new();
                // Targets that pass arguments go through a trampoline block, filled after the switch.
                let mut trampolines = Vec::new();
                for (k, tg) in cases {
                    let (blk, args) = self.target(tg);
                    let stores = self.edge_stores(tg);
                    let entry = if args.is_empty() && stores.is_empty() {
                        blk
                    } else {
                        let tramp = self.b.create_block();
                        trampolines.push((tramp, blk, args, stores));
                        tramp
                    };
                    sw.set_entry(*k as u64 as u128, entry);
                }
                let (db, da) = self.target(default);
                let dstores = self.edge_stores(default);
                let dblock = if da.is_empty() && dstores.is_empty() {
                    db
                } else {
                    let tramp = self.b.create_block();
                    trampolines.push((tramp, db, da, dstores));
                    tramp
                };
                sw.emit(&mut self.b, v, dblock);
                for (tramp, blk, args, stores) in trampolines {
                    self.b.switch_to_block(tramp);
                    self.emit_stores(stores);
                    self.b.ins().jump(blk, &args);
                }
            }
            Term::Ret(v) => {
                let vs = v.map(|v| self.vals[v.index()].clone()).unwrap_or_default();
                debug_assert_eq!(vs.len(), self.g.lay.width(f.ret));
                self.b.ins().return_(&vs);
            }
            Term::Fault(k) => {
                self.fault_term(*k);
            }
            Term::Unreachable => {
                self.b.ins().trap(TrapCode::unwrap_user(2));
            }
        }
    }

    fn fault_term(&mut self, k: FaultKind) {
        match k {
            FaultKind::IntOverflow => {
                self.rt_call("msrt_fault_int_overflow", &[]);
            }
            FaultKind::DivByZero => {
                self.rt_call("msrt_fault_div_zero", &[]);
            }
            FaultKind::IndexOutOfRange => {
                let z = self.iconst(0);
                self.rt_call("msrt_index_fault", &[z, z]);
            }
            FaultKind::NoneUnwrap => {
                self.rt_call("msrt_fault_unwrap_none", &[]);
            }
            FaultKind::Cancelled => {
                self.rt_call("msrt_cancelled", &[]);
            }
            FaultKind::CallDepth => {
                self.rt_call("msrt_fault_depth", &[]);
            }
            FaultKind::Unreachable => {
                self.unsupported("fault unreachable_code message");
            }
            FaultKind::Message(s) => {
                let d = self.g.str_lit(s.0);
                let base = self.data_addr(d);
                let p = base;
                let n = self.iconst(self.g.m.strings[s.index()].len() as i64);
                self.rt_call("msrt_fault", &[p, n]);
            }
        }
        self.b.ins().trap(TrapCode::unwrap_user(1));
    }

    fn icc(cc: Cc) -> IntCC {
        match cc {
            Cc::Eq => IntCC::Equal,
            Cc::Ne => IntCC::NotEqual,
            Cc::Lt => IntCC::SignedLessThan,
            Cc::Le => IntCC::SignedLessThanOrEqual,
            Cc::Gt => IntCC::SignedGreaterThan,
            Cc::Ge => IntCC::SignedGreaterThanOrEqual,
        }
    }

    fn fcc(cc: Cc) -> FloatCC {
        match cc {
            Cc::Eq => FloatCC::Equal,
            Cc::Ne => FloatCC::NotEqual,
            Cc::Lt => FloatCC::LessThan,
            Cc::Le => FloatCC::LessThanOrEqual,
            Cc::Gt => FloatCC::GreaterThan,
            Cc::Ge => FloatCC::GreaterThanOrEqual,
        }
    }

    /// Lowers one instruction by routing it to the function for its op family, then
    /// normalizes the result leaves to the machine types of the result type.
    fn lower_inst(&mut self, f: &Func, inst: &Inst) {
        let previous_overflow = self.overflow_result.take();
        let res_ty = inst.res.map(|r| f.ty(r));
        let out: Vs = match inst.op {
            Op::IConst | Op::FConst | Op::BConst | Op::UnitConst | Op::StrLit | Op::BytesLit => {
                self.constants(f, inst)
            }
            Op::IAdd | Op::ISub | Op::IMul | Op::INeg | Op::F32Round | Op::SDiv | Op::SRem => {
                self.integer_ops(inst, previous_overflow)
            }
            Op::IAddOverflow
            | Op::IMulOverflow
            | Op::IntOverflowIf
            | Op::NarrowChk
            | Op::Conv
            | Op::INarrowOpt
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::INegChk
            | Op::SDivChk
            | Op::SRemChk => {
                let vs = self.checked_integer_ops(f, inst);
                self.range_check_sized(f, inst, vs)
            }
            Op::And
            | Op::Or
            | Op::Xor
            | Op::Shl
            | Op::Sshr
            | Op::Ushr
            | Op::Rotl
            | Op::Rotr
            | Op::Clz
            | Op::Ctz
            | Op::Popcnt
            | Op::Not => self.bit_ops(inst),
            Op::UICmp | Op::ICmp | Op::FCmp | Op::Select => self.comparisons(inst),
            Op::FAdd
            | Op::FSub
            | Op::FMul
            | Op::FDiv
            | Op::FNeg
            | Op::FSqrt
            | Op::FFloor
            | Op::FCeil
            | Op::FTrunc
            | Op::FAbs
            | Op::I2F
            | Op::F2IOpt
            | Op::B2I => self.float_ops(f, inst),
            Op::TypeNew | Op::TypeGet | Op::TypeSet | Op::TypeFill => self.type_op(f, inst),
            Op::AltNew
            | Op::AltView
            | Op::AltPlain
            | Op::AltOwn
            | Op::AltTag
            | Op::AltGet
            | Op::AltTake
            | Op::TypeRelease
            | Op::AltRelease
            | Op::AltUnbox => self.alternatives(f, inst),
            Op::ListNew
            | Op::ListLit
            | Op::ListConst
            | Op::ListLen
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::ListSet
            | Op::ListSetNn
            | Op::ListSetU
            | Op::ListFill
            | Op::ListPush
            | Op::ListDropLast
            | Op::ListTake
            | Op::ListRelease => self.lists(f, inst),
            Op::OptSome
            | Op::OptView
            | Op::OptNone
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptUnwrap
            | Op::OptUnbox
            | Op::OptAddr => self.optionals(f, inst),
            Op::StrByte
            | Op::StrAscii
            | Op::StrAsciiAt
            | Op::StrAsciiLen
            | Op::StrEqFast
            | Op::StrEqLit
            | Op::StrLen => self.strings(inst),
            Op::BytesPush => self.bytes_push(inst),
            Op::ClosureNew
            | Op::ClosureCap
            | Op::ClosureCapAddr
            | Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceData
            | Op::IfaceIs => self.closures_and_interfaces(f, inst),
            Op::Call | Op::CallInd | Op::CallMethod | Op::CallRt => self.calls(f, inst),
            Op::MoveOut | Op::Clone | Op::Drop | Op::DropIf => self.ownership(f, inst),
            Op::Slot
            | Op::ListAddr
            | Op::ListAddrU
            | Op::PtrIsNull
            | Op::PtrField
            | Op::Load
            | Op::Take
            | Op::Store
            | Op::Put => self.memory(f, inst),
            Op::FuncAddr
            | Op::TypeDesc
            | Op::Poll
            | Op::DepthEnter
            | Op::DepthLeave
            | Op::CleanupPush
            | Op::CleanupRun
            | Op::GlobalGet
            | Op::GlobalSet => self.runtime_services(f, inst),
            Op::ScopeBegin | Op::ScopeOwn | Op::ScopeEnd | Op::ScopeDisown | Op::ScopeMark => {
                unreachable!("scope markers are removed by elaborate before codegen")
            }
        };
        let out = match res_ty {
            Some(t) => {
                let leaves = self.g.lay.leaves(t);
                if leaves.len() == out.len() {
                    out.into_iter()
                        .zip(leaves)
                        .map(|(v, l)| self.float_as(v, leaf_type(l)))
                        .collect()
                } else {
                    out
                }
            }
            None => out,
        };
        self.set(inst, out);
    }

    fn opt_boxed(&self, opt: Ty) -> bool {
        match self.g.m.types.kind(opt) {
            TyKind::Opt(inner) => self.g.lay.opt_is_boxed(*inner),
            _ => false,
        }
    }

    /// Whether a niche optional holds a value. None of an optional string is a null pointer with
    /// the static tag; an inline string may have a zero first word, but never that tag.
    fn opt_present(&mut self, ty: Ty, v: &[Value]) -> Value {
        if !self.g.lay.is_str_like(ty) {
            return self.b.ins().icmp_imm_s(IntCC::NotEqual, v[0], 0);
        }
        let t = self.b.ins().bxor_imm_s(v[1], STR_STATIC as i64);
        let any = self.b.ins().bor(v[0], t);
        self.b.ins().icmp_imm_s(IntCC::NotEqual, any, 0)
    }

    /// Whether the second word of a string has the inline tag.
    /// The byte length of a string from its `tagged` word.
    fn str_byte_len(&mut self, tagged: Value) -> Value {
        let inline = self.str_is_inline(tagged);
        let short = self.b.ins().ushr_imm_u(tagged, STR_INLINE_LEN_SHIFT as i64);
        let short = self.b.ins().band_imm_s(short, 15);
        let long = self.b.ins().band_imm_s(tagged, STR_LEN_MASK as i64);
        self.b.ins().select(inline, short, long)
    }

    fn str_is_inline(&mut self, tagged: Value) -> Value {
        let tag = self.b.ins().ushr_imm_u(tagged, 62);
        self.b.ins().icmp_imm_s(IntCC::Equal, tag, 1)
    }

    /// Whether the optional is its payload's leaves, with a null first leaf for none.
    fn opt_niche(&self, opt: Ty) -> bool {
        self.opt_nullable(opt) || self.g.lay.is_str_like(opt)
    }

    fn opt_nullable(&self, opt: Ty) -> bool {
        match self.g.m.types.kind(opt) {
            TyKind::Opt(inner) => self.g.lay.opt_is_nullable(*inner),
            _ => false,
        }
    }
}

// ---- aggregates, lists, calls ---------------------------------------------

impl<'a, 'm> Lower<'a, 'm> {
    fn alt_new(&mut self, inst: &Inst, ty: Ty) -> Vs {
        let Imm::Case(a, c) = inst.imm else {
            unreachable!()
        };
        let shape = self.g.lay.shape(ty);
        let fields = self.alt_fields(a);
        let (leaves, boxed) = match &shape.alt {
            Some(AltRepr::Boxed { block, .. }) => (block.clone(), true),
            _ => (shape.leaves.clone(), false),
        };
        let mut out: Vs = leaves.iter().map(|l| self.zero(*l)).collect();
        out[0] = self.iconst(c as i64);
        for (i, (_, idx)) in fields[c as usize].iter().enumerate() {
            let v = self.vals[inst.args[i].index()].clone();
            for (k, x) in idx.iter().zip(v) {
                out[*k] = x;
            }
        }
        if boxed {
            let size = mem_layout(&leaves).size;
            if fields[c as usize].is_empty() {
                let id = self.g.unit_block(a, c as usize, size as usize);
                return vec![self.data_addr(id)];
            }
            let blk = self.alloc(size as i64);
            self.store_leaves(blk, 0, &leaves, &out);
            vec![blk]
        } else {
            out
        }
    }
}

/// Whether `head` ends in a loop test whose `then` edge stays in the loop and whose `els`
/// edge leaves it (`head` is reachable from `then` but not from `els`).
fn continues_loop(f: &Func, head: usize, then: usize, els: usize) -> bool {
    let has_back_edge = f.blocks.iter().enumerate().skip(head).any(|(_, b)| {
        let mut hit = false;
        b.term.for_each_target(|t| hit |= t.block.index() == head);
        hit
    });
    has_back_edge && reaches(f, then, head) && !reaches(f, els, head)
}

fn reaches(f: &Func, from: usize, to: usize) -> bool {
    let mut seen = vec![false; f.blocks.len()];
    let mut stack = vec![from];
    while let Some(b) = stack.pop() {
        if b == to {
            return true;
        }
        if std::mem::replace(&mut seen[b], true) {
            continue;
        }
        f.blocks[b]
            .term
            .for_each_target(|t| stack.push(t.block.index()));
    }
    false
}

/// The C parameter of a leaf crossing to a user shim: sized integers at their own width,
/// sign- or zero-extended as the platform ABI expects, `Bool` as a zero-extended byte.
fn c_param(l: Leaf) -> ir::AbiParam {
    let (ty, ext) = match l {
        Leaf::N8 => (types::I8, ir::ArgumentExtension::Sext),
        Leaf::N16 => (types::I16, ir::ArgumentExtension::Sext),
        Leaf::N32 => (types::I32, ir::ArgumentExtension::Sext),
        Leaf::U8 | Leaf::I8 => (types::I8, ir::ArgumentExtension::Uext),
        Leaf::U16 => (types::I16, ir::ArgumentExtension::Uext),
        Leaf::U32 => (types::I32, ir::ArgumentExtension::Uext),
        _ => (leaf_type(l), ir::ArgumentExtension::None),
    };
    let p = ir::AbiParam::new(ty);
    match ext {
        ir::ArgumentExtension::Sext => p.sext(),
        ir::ArgumentExtension::Uext => p.uext(),
        ir::ArgumentExtension::None => p,
    }
}
