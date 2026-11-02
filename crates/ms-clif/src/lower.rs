//! Lowering of one MIR function (or glue function) to Cranelift IR.

use crate::cg::{CLOSURE_CAPTURES, CLOSURE_CODE, Gen, Glue, SHARED_VALUE, leaf_type, mem_type};
use crate::layout::{AltRepr, Leaf, mem_layout};
use cranelift_codegen::ir::condcodes::{CondCode, FloatCC, IntCC};
use cranelift_codegen::ir::{
    self, BlockArg, FuncRef, GlobalValue, InstBuilder, InstructionData, MemFlagsData, Opcode,
    StackSlotData, StackSlotKind, TrapCode, Value, ValueDef, types,
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_module::{DataId, FuncId, Module as _};
use ms_mir::ir::{Cc, FaultKind, Func, Imm, Inst, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::symbols::{ISOLATE_HDR_CANCEL, ISOLATE_HDR_GUARDED, STACK_SLOT};
use ms_rt_abi::{
    ASCII_CHAR_STRIDE, STR_INLINE, STR_INLINE_LEN_SHIFT, STR_LEN_MASK, STR_LEN_OFFSET,
    STR_PTR_OFFSET, STR_STATIC, VEC_CAP_OFFSET, VEC_LEN_OFFSET, VEC_PTR_OFFSET,
};
use std::collections::HashMap;

type Vs = Vec<Value>;

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
    /// MIR block being lowered.
    cur: usize,
    /// Result paired with the preceding overflow flag. Reuse only on the very
    /// next instruction, so the defining instruction always dominates the use.
    overflow_result: Option<(Op, Value, Value, Value)>,
    /// Snapshot of the last slot written in this block; mutations still reach memory.
    slot_value: Option<(ms_mir::ir::Value, Ty, Vs)>,
    blocks: Vec<Option<ir::Block>>,
    /// First unsupported construct met, reported by the driver.
    pub unsupported: Option<String>,
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
            slot_blk: HashMap::new(),
            used: Vec::new(),
            str_lits: HashMap::new(),
            pslots: HashMap::new(),
            lazy: Vec::new(),
            cur: 0,
            overflow_result: None,
            slot_value: None,
            blocks: Vec::new(),
            unsupported: None,
        }
    }

    pub fn finish(mut self) {
        self.b.seal_all_blocks();
        let config = self.g.module.target_config();
        self.b.finalize(config);
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
        let os = self.g.module.isa().triple().operating_system;
        if os == target_lexicon::OperatingSystem::Windows {
            return self.rt_call("msrt_isolate_hdr", &[])[0];
        }
        let sp = self.b.ins().get_stack_pointer(types::I64);
        self.b.ins().band_imm_s(sp, !(STACK_SLOT - 1))
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
        let v = self.b.ins().load(mem_type(l), flags(), ptr, off);
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
        self.b.ins().store(flags(), v, ptr, off);
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

    fn alloc(&mut self, size: i64) -> Value {
        let n = self.iconst(size.max(1));
        self.rt_call("msrt_alloc", &[n])[0]
    }

    fn free(&mut self, p: Value) {
        self.rt_call("msrt_free", &[p]);
    }

    // ---- ownership -------------------------------------------------------

    /// `rc -= 1; if rc == 0 { drop_slow }` on a non-null object pointer.
    fn release(&mut self, p: Value) {
        let rc = self.b.ins().load(types::I64, flags(), p, 0);
        let n = self.b.ins().iadd_imm_s(rc, -1);
        self.b.ins().store(flags(), n, p, 0);
        let zero = self.b.ins().icmp_imm_s(IntCC::Equal, n, 0);
        self.if_then(zero, |s| {
            s.rt_call("msrt_drop_slow", &[p]);
        });
    }

    /// With `MS_COUNT_STR` set at compile time, reports each executed string drop (`kind` 0) or copy
    /// (1) with its capacity word to the counting runtime (`ms-rt` feature `stats`), which prints
    /// the dynamic totals at exit. `bench/tools/copy_report.ms` counts the static sites.
    fn count_str(&mut self, kind: i64, cap: Value) {
        if !self.g.count_str {
            return;
        }
        let kind = self.b.ins().iconst(types::I64, kind);
        self.rt_call("msrt_str_count", &[kind, cap]);
    }

    fn retain(&mut self, p: Value) {
        let rc = self.b.ins().load(types::I64, flags(), p, 0);
        let n = self.b.ins().iadd_imm_s(rc, 1);
        self.b.ins().store(flags(), n, p, 0);
    }

    /// Whether dropping a value of `ty` is a call to glue (rather than inline or nothing).
    fn drop_value(&mut self, ty: Ty, vs: &[Value]) {
        let m = self.g.m;
        if !m.needs_drop(ty) {
            return;
        }
        match m.types.kind(ty) {
            _ if self.g.lay.is_str_like(ty) => {
                self.count_str(0, vs[1]);
                // Only an owned string (tag `00`) frees anything.
                let owned =
                    self.b
                        .ins()
                        .icmp_imm_s(IntCC::UnsignedLessThan, vs[1], STR_INLINE as i64);
                self.if_then(owned, |s| {
                    s.rt_call("msrt_str_free", &[vs[0]]);
                });
            }
            TyKind::Fn(..) => self.release(vs[0]),
            TyKind::Obj(n, _) if n != "Map" && n != "Set" => self.release(vs[0]),
            TyKind::Opt(inner)
                if self.g.lay.opt_is_nullable(*inner) && !self.g.lay.opt_is_boxed(*inner) =>
            {
                let p = vs[0];
                let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, p, 0);
                self.if_then(nn, |s| s.release(p));
            }
            _ => {
                let id = self.g.glue(Glue::Drop, ty);
                self.call_id(id, vs);
            }
        }
    }

    fn copy_value(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        if !m.needs_drop(ty) {
            return vs.to_vec();
        }
        match m.types.kind(ty) {
            _ if self.g.lay.is_str_like(ty) => {
                self.count_str(1, vs[1]);
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
                let slot = self.b.create_sized_stack_slot(StackSlotData::new(
                    StackSlotKind::ExplicitSlot,
                    16,
                    3,
                ));
                let out = self.b.ins().stack_addr(types::I64, slot, 0);
                self.rt_call("msrt_str_copy", &[vs[0], vs[1], out]);
                let c = self.load_leaves(out, 0, &[Leaf::I64; 2]);
                self.b.ins().jump(join, &bargs(&c));
                self.b.switch_to_block(join);
                self.b.block_params(join).to_vec()
            }
            TyKind::Fn(..) => {
                self.retain(vs[0]);
                vs.to_vec()
            }
            TyKind::Obj(n, _) if n != "Map" && n != "Set" => {
                self.retain(vs[0]);
                vs.to_vec()
            }
            _ => {
                let id = self.g.glue(Glue::Copy, ty);
                self.call_id(id, vs)
            }
        }
    }

    // ---- glue ------------------------------------------------------------

    pub fn lower_glue(&mut self, kind: Glue, ty: Ty) {
        let entry = self.b.create_block();
        self.b.append_block_params_for_function_params(entry);
        self.b.switch_to_block(entry);
        let params = self.b.block_params(entry).to_vec();
        match kind {
            Glue::Drop => {
                self.glue_drop(ty, &params);
                self.b.ins().return_(&[]);
            }
            Glue::Copy => {
                let out = self.glue_copy(ty, &params);
                self.b.ins().return_(&out);
            }
            Glue::ClosureDrop(f) => {
                // Drops the captures then frees the object.
                let obj = params[0];
                let caps = match &self.g.m.funcs[f as usize].kind {
                    ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
                    _ => Vec::new(),
                };
                let closers = self.g.m.funcs[f as usize].capture_closers.clone();
                let mut off = CLOSURE_CAPTURES as i64;
                for (k, c) in caps.into_iter().enumerate() {
                    let leaves = self.g.lay.leaves(c);
                    let lay = mem_layout(&leaves);
                    off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
                    if let Some((_, close)) = closers.iter().find(|(i, _)| *i as usize == k) {
                        // A resource the environment owns is closed before it is released.
                        let vs = self.load_leaves(obj, off, &leaves);
                        let fid = self.g.funcs[close.index()];
                        self.call_id(fid, &vs);
                    }
                    if self.g.m.needs_drop(c) {
                        let vs = self.load_leaves(obj, off, &leaves);
                        self.drop_value(c, &vs);
                    }
                    off += lay.size as i64;
                }
                self.free(obj);
                self.b.ins().return_(&[]);
            }
            Glue::BlockDrop => {
                // Interface payload block holding a `ty` value.
                let blk = params[0];
                if self.g.m.needs_drop(ty) {
                    let leaves = self.g.lay.leaves(ty);
                    let vs = self.load_leaves(blk, 0, &leaves);
                    self.drop_value(ty, &vs);
                }
                self.free(blk);
                self.b.ins().return_(&[]);
            }
            Glue::BlockCopy => {
                // Interface payload block holding a `ty` value.
                let leaves = self.g.lay.leaves(ty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                let copied = self.copy_value(ty, &vs);
                let blk = self.alloc(mem_layout(&leaves).size as i64);
                self.store_leaves(blk, 0, &leaves, &copied);
                self.b.ins().return_(&[blk]);
            }
            Glue::SharedDrop => {
                let obj = params[0];
                if let Some(&(_, close)) = self.g.m.shared_close.iter().find(|(t, _)| *t == ty) {
                    // The last holder is gone: close the payload before it is dropped.
                    let at = self.add_imm(obj, SHARED_VALUE);
                    let id = self.g.funcs[close.index()];
                    self.call_id(id, &[at]);
                }
                if self.g.m.needs_drop(ty) {
                    let leaves = self.g.lay.leaves(ty);
                    let vs = self.load_leaves(obj, SHARED_VALUE, &leaves);
                    if self.is_shared_box(ty) {
                        // `take` moved the payload out and left its bits behind; the new owner
                        // drops it, so a box dropped while taken must not drop it again.
                        let (_, at, _) = *self.fields_of(ty).last().expect("taken flag");
                        let off = self.g.lay.mem(ty).offsets.get(at).copied().unwrap_or(0);
                        let taken = self.b.ins().load(
                            types::I8,
                            flags(),
                            obj,
                            (SHARED_VALUE + off as i64) as i32,
                        );
                        let held = self.b.ins().icmp_imm_s(IntCC::Equal, taken, 0);
                        self.if_then(held, |s| s.drop_value(ty, &vs));
                    } else {
                        self.drop_value(ty, &vs);
                    }
                }
                self.free(obj);
                self.b.ins().return_(&[]);
            }
            Glue::SlotDrop => {
                if self.g.m.needs_drop(ty) {
                    let leaves = self.g.lay.leaves(ty);
                    let vs = self.load_leaves(params[0], 0, &leaves);
                    self.drop_value(ty, &vs);
                }
                self.b.ins().return_(&[]);
            }
            Glue::SlotCopy => {
                let leaves = self.g.lay.leaves(ty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                let out = self.copy_value(ty, &vs);
                self.store_leaves(params[1], 0, &leaves, &out);
                self.b.ins().return_(&[]);
            }
            Glue::CleanupThunk(f) => {
                // `arg` points at a stack copy of the registered value.
                let fid = self.g.funcs[f as usize];
                let pty = self.g.m.funcs[f as usize].params[0].ty;
                let leaves = self.g.lay.leaves(pty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                self.call_id(fid, &vs);
                self.b.ins().return_(&[]);
            }
        }
    }

    /// Splits `vs` into per-field slices for a record type.
    /// For a `SharedGuard` (fields `box`, `value`, `held`): the `held` flag and the leaf index of
    /// `value`. A closed guard handed its payload back to the box without a copy, so its stale
    /// `value` is neither dropped nor copied.
    fn guard_held(&self, ty: Ty, vs: &[Value]) -> Option<(Value, usize)> {
        let m = self.g.m;
        let TyKind::Rec(r) = m.types.kind(ty) else {
            return None;
        };
        let (held, value) = m.shared_guard_fields(*r)?;
        let fields = self.fields_of(ty);
        Some((vs[fields[held].1], fields[value].1))
    }

    /// `copy_value` of `vs` when `flag` is set; otherwise `vs` as they are (a payload nobody reads).
    fn copy_if(&mut self, flag: Value, ty: Ty, vs: &[Value]) -> Vs {
        let leaves = self.g.lay.leaves(ty);
        let join = self.b.create_block();
        for l in &leaves {
            self.b.append_block_param(join, leaf_type(*l));
        }
        let yes = self.b.create_block();
        self.b.ins().brif(flag, yes, &[], join, &bargs(vs));
        self.b.switch_to_block(yes);
        let c = self.copy_value(ty, vs);
        self.b.ins().jump(join, &bargs(&c));
        self.b.switch_to_block(join);
        self.b.block_params(join).to_vec()
    }

    fn fields_of(&self, ty: Ty) -> Vec<(Ty, usize, usize)> {
        let m = self.g.m;
        let TyKind::Rec(r) = m.types.kind(ty) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        let mut at = 0;
        for f in &m.records[r.index()].fields {
            let w = self.g.lay.width(f.1);
            out.push((f.1, at, w));
            at += w;
        }
        out
    }

    /// Per-case, per-field `(type, leaf indices into the alt's leaf/block list)`.
    fn alt_fields(&self, a: ms_mir::types::AltId) -> std::rc::Rc<crate::layout::AltFields> {
        self.g.lay.alt_fields(a)
    }

    fn glue_drop(&mut self, ty: Ty, vs: &[Value]) {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => {
                let elem = m.list_elem(ty);
                let (ptr, len) = (vs[0], vs[1]);
                if let Some(e) = elem.filter(|e| m.needs_drop(*e)) {
                    let leaves = self.g.lay.leaves(e);
                    let size = mem_layout(&leaves).size as i64;
                    let head = self.b.create_block();
                    let body = self.b.create_block();
                    let done = self.b.create_block();
                    self.b.append_block_param(head, types::I64);
                    let zero = self.iconst(0);
                    self.b.ins().jump(head, &[BlockArg::Value(zero)]);
                    self.b.switch_to_block(head);
                    let i = self.b.block_params(head)[0];
                    let more = self.b.ins().icmp(IntCC::SignedLessThan, i, len);
                    self.b.ins().brif(more, body, &[], done, &[]);
                    self.b.switch_to_block(body);
                    let off = self.b.ins().imul_imm_s(i, size);
                    let at = self.b.ins().iadd(ptr, off);
                    let ev = self.load_leaves(at, 0, &leaves);
                    self.drop_value(e, &ev);
                    let next = self.b.ins().iadd_imm_s(i, 1);
                    self.b.ins().jump(head, &[BlockArg::Value(next)]);
                    self.b.switch_to_block(done);
                }
                let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, ptr, 0);
                self.if_then(nn, |s| s.free(ptr));
            }
            TyKind::Obj(..) => {
                // Map and Set are owned `MapVal`s the runtime knows how to drop.
                let leaves = self.g.lay.leaves(ty);
                let slot = self.spill(vs, &leaves);
                let d = self.typedesc_addr(ty);
                self.rt_call("msrt_slot_drop", &[d, slot]);
            }
            TyKind::Rec(_) => {
                let held = self.guard_held(ty, vs);
                for (fty, at, w) in self.fields_of(ty) {
                    if !m.needs_drop(fty) {
                        continue;
                    }
                    match held {
                        Some((flag, value_at)) if at == value_at => {
                            let part = vs[at..at + w].to_vec();
                            self.if_then(flag, |s| s.drop_value(fty, &part));
                        }
                        _ => self.drop_value(fty, &vs[at..at + w]),
                    }
                }
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                // Payload lives in a heap block behind a nullable pointer.
                let p = vs[0];
                let leaves = self.g.lay.leaves(inner);
                let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, p, 0);
                self.if_then(nn, |s| {
                    if m.needs_drop(inner) {
                        let payload = s.load_leaves(p, 0, &leaves);
                        s.drop_value(inner, &payload);
                    }
                    s.free(p);
                });
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.drop_value(ty, vs),
            TyKind::Opt(inner) => {
                // Non-nullable optional: [present, payload...].
                let present = vs[0];
                let payload = vs[1..].to_vec();
                self.if_then(present, |s| s.drop_value(inner, &payload));
            }
            TyKind::Alt(a) => self.glue_drop_alt(ty, a, vs),
            TyKind::Iface(_) => {
                // The vtable word's low bits say what the value owns: 0 the box and its payload
                // (vtable[0] is the payload destructor), 1 only the box (`iface.lend`), 2
                // nothing (`iface.view`).
                let (data, vt) = (vs[0], vs[1]);
                let tag = self.b.ins().band_imm_s(vt, 3);
                let owned = self.b.ins().icmp_imm_s(IntCC::Equal, tag, 0);
                self.if_then(owned, |s| {
                    let f = s.b.ins().load(types::I64, flags(), vt, 0);
                    let mut sig = s.g.module.make_signature();
                    sig.params.push(ir::AbiParam::new(types::I64));
                    let sr = s.b.import_signature(sig);
                    s.b.ins().call_indirect(sr, f, &[data]);
                });
                let lent = self.b.ins().icmp_imm_s(IntCC::Equal, tag, 1);
                self.if_then(lent, |s| s.free(data));
            }
            _ => {}
        }
    }

    /// For a boxed alternative with payloadless cases: whether `tag` names one (such values are the
    /// shared block, see [`Gen::unit_block`]) and that block's address. `None` when every case
    /// carries a payload.
    fn unit_case(&mut self, a: ms_mir::types::AltId, tag: Value) -> Option<(Value, Value)> {
        let ty = self
            .g
            .m
            .types
            .find(&TyKind::Alt(a))
            .expect("alt type interned");
        let shape = self.g.lay.shape(ty);
        let Some(AltRepr::Boxed { block, .. }) = &shape.alt else {
            return None;
        };
        let size = mem_layout(block).size;
        let units: Vec<usize> = self.g.m.alts[a.index()]
            .cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
            .map(|(i, _)| i)
            .collect();
        let mut acc: Option<(Value, Value)> = None;
        for c in units {
            let id = self.g.unit_block(a, c, size as usize);
            let addr = self.data_addr(id);
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            acc = Some(match acc {
                None => (is, addr),
                Some((u, prev)) => (self.b.ins().bor(u, is), self.b.ins().select(is, addr, prev)),
            });
        }
        acc
    }

    /// Frees the block of a boxed alternative unless its tag names a payloadless (shared) case.
    fn free_boxed(&mut self, a: ms_mir::types::AltId, tag: Value, p: Value) {
        match self.unit_case(a, tag) {
            None => self.free(p),
            Some((unit, _)) => {
                let free = self.b.create_block();
                let cont = self.b.create_block();
                self.b.ins().brif(unit, cont, &[], free, &[]);
                self.b.switch_to_block(free);
                self.free(p);
                self.b.ins().jump(cont, &[]);
                self.b.switch_to_block(cont);
            }
        }
    }

    fn glue_drop_alt(&mut self, ty: Ty, a: ms_mir::types::AltId, vs: &[Value]) {
        let fields = self.alt_fields(a);
        let boxed = matches!(self.g.lay.shape(ty).alt, Some(AltRepr::Boxed { .. }));
        if boxed && self.has_tail(ty, &fields) {
            self.drop_boxed_iter(ty, &fields, vs[0]);
            return;
        }
        let (leaves, base) = match &self.g.lay.shape(ty).alt {
            Some(AltRepr::Boxed { block, .. }) => (block.clone(), Some(vs[0])),
            _ => (self.g.lay.leaves(ty), None),
        };
        let tag = match base {
            Some(p) => self.b.ins().load(types::I64, flags(), p, 0),
            None => vs[0],
        };
        let done = self.b.create_block();
        for (c, case) in fields.iter().enumerate() {
            if !case.iter().any(|(t, _)| self.g.m.needs_drop(*t)) {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            for (fty, idx) in case {
                if !self.g.m.needs_drop(*fty) {
                    continue;
                }
                let fv: Vs = match base {
                    Some(p) => {
                        let lay = mem_layout(&leaves);
                        idx.iter()
                            .map(|i| {
                                self.b.ins().load(
                                    leaf_type(leaves[*i]),
                                    flags(),
                                    p,
                                    lay.offsets[*i] as i32,
                                )
                            })
                            .collect()
                    }
                    None => idx.iter().map(|i| vs[*i]).collect(),
                };
                self.drop_value(*fty, &fv);
            }
            self.b.ins().jump(done, &[]);
            self.b.switch_to_block(next);
        }
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(done);
        if boxed {
            self.free_boxed(a, tag, vs[0]);
        }
    }

    /// The field of `case` that holds the same boxed alternative again (the "tail" of a chain
    /// such as `Cons(head, tail)`), as `(field index, leaf indices, optional)`. Drop and copy of a
    /// boxed alternative loop over this field instead of recursing, so a long chain does not
    /// overflow the stack. Other recursive fields (the left child of a tree) still recurse.
    fn tail_field(&self, ty: Ty, case: &[(Ty, Vec<usize>)]) -> Option<(usize, Vec<usize>, bool)> {
        let m = self.g.m;
        case.iter().enumerate().rev().find_map(|(i, (fty, idx))| {
            if *fty == ty && idx.len() == 1 {
                return Some((i, idx.clone(), false));
            }
            match m.types.kind(*fty) {
                TyKind::Opt(inner) if *inner == ty && idx.len() == 2 => {
                    Some((i, idx.clone(), true))
                }
                _ => None,
            }
        })
    }

    fn has_tail(&self, ty: Ty, fields: &[Vec<(Ty, Vec<usize>)>]) -> bool {
        fields.iter().any(|c| self.tail_field(ty, c).is_some())
    }

    /// Frees a chain of boxed blocks: each iteration drops the non-tail fields of the block,
    /// reads its tail pointer, frees it and moves on to the tail.
    fn drop_boxed_iter(&mut self, ty: Ty, fields: &[Vec<(Ty, Vec<usize>)>], first: Value) {
        let shape = self.g.lay.shape(ty);
        let Some(AltRepr::Boxed { block, .. }) = &shape.alt else {
            return;
        };
        let lay = mem_layout(block);
        let head = self.b.create_block();
        let exit = self.b.create_block();
        self.b.append_block_param(head, types::I64);
        self.b.ins().jump(head, &[BlockArg::Value(first)]);
        self.b.switch_to_block(head);
        let cur = self.b.block_params(head)[0];
        let tag = self.b.ins().load(types::I64, flags(), cur, 0);
        for (c, case) in fields.iter().enumerate() {
            let tail = self.tail_field(ty, case);
            let droppable = case.iter().any(|(t, _)| self.g.m.needs_drop(*t));
            if !droppable {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            for (i, (fty, idx)) in case.iter().enumerate() {
                if !self.g.m.needs_drop(*fty) || tail.as_ref().is_some_and(|t| t.0 == i) {
                    continue;
                }
                let fv: Vs = idx
                    .iter()
                    .map(|k| {
                        self.b.ins().load(
                            leaf_type(block[*k]),
                            flags(),
                            cur,
                            lay.offsets[*k] as i32,
                        )
                    })
                    .collect();
                self.drop_value(*fty, &fv);
            }
            match tail {
                Some((_, idx, optional)) => {
                    let k = *idx.last().expect("tail leaf");
                    let child = self
                        .b
                        .ins()
                        .load(types::I64, flags(), cur, lay.offsets[k] as i32);
                    let present = if optional {
                        Some(self.b.ins().load(
                            leaf_type(block[idx[0]]),
                            flags(),
                            cur,
                            lay.offsets[idx[0]] as i32,
                        ))
                    } else {
                        None
                    };
                    self.free(cur);
                    match present {
                        Some(p) => self
                            .b
                            .ins()
                            .brif(p, head, &[BlockArg::Value(child)], exit, &[]),
                        None => self.b.ins().jump(head, &[BlockArg::Value(child)]),
                    };
                }
                None => {
                    self.free(cur);
                    self.b.ins().jump(exit, &[]);
                }
            }
            self.b.switch_to_block(next);
        }
        // A case with nothing to drop: only the block is freed.
        let TyKind::Alt(a) = self.g.m.types.kind(ty).clone() else {
            unreachable!("boxed alternative")
        };
        self.free_boxed(a, tag, cur);
        self.b.ins().jump(exit, &[]);
        self.b.switch_to_block(exit);
    }

    /// Copies a chain of boxed blocks front to back: each iteration allocates the new block,
    /// stores its address where the previous block's tail pointer lives, copies the non-tail
    /// fields, and continues with the source's tail.
    fn copy_boxed_iter(&mut self, ty: Ty, fields: &[Vec<(Ty, Vec<usize>)>], first: Value) -> Value {
        let shape = self.g.lay.shape(ty);
        let Some(AltRepr::Boxed { block, .. }) = &shape.alt else {
            return first;
        };
        let lay = mem_layout(block);
        let result =
            self.b
                .create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8, 3));
        let result_addr = self.b.ins().stack_addr(types::I64, result, 0);
        let head = self.b.create_block();
        let exit = self.b.create_block();
        self.b.append_block_param(head, types::I64);
        self.b.append_block_param(head, types::I64);
        self.b.ins().jump(
            head,
            &[BlockArg::Value(first), BlockArg::Value(result_addr)],
        );
        self.b.switch_to_block(head);
        let (src, dst) = {
            let ps = self.b.block_params(head);
            (ps[0], ps[1])
        };
        let sv = self.load_leaves(src, 0, block);
        let tag = sv[0];
        let TyKind::Alt(a) = self.g.m.types.kind(ty).clone() else {
            unreachable!("boxed alternative")
        };
        if let Some((unit, addr)) = self.unit_case(a, tag) {
            // A payloadless case is the shared block: link it and stop.
            let shared = self.b.create_block();
            let fresh = self.b.create_block();
            self.b.ins().brif(unit, shared, &[], fresh, &[]);
            self.b.switch_to_block(shared);
            self.b.ins().store(flags(), addr, dst, 0);
            self.b.ins().jump(exit, &[]);
            self.b.switch_to_block(fresh);
        }
        let blk = self.alloc(lay.size as i64);
        self.b.ins().store(flags(), blk, dst, 0);
        for (c, case) in fields.iter().enumerate() {
            let tail = self.tail_field(ty, case);
            let droppable = case.iter().any(|(t, _)| self.g.m.needs_drop(*t));
            if !droppable {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            let mut out = sv.clone();
            for (i, (fty, idx)) in case.iter().enumerate() {
                if !self.g.m.needs_drop(*fty) || tail.as_ref().is_some_and(|t| t.0 == i) {
                    continue;
                }
                let fv: Vs = idx.iter().map(|k| sv[*k]).collect();
                let cv = self.copy_value(*fty, &fv);
                for (k, v) in idx.iter().zip(cv) {
                    out[*k] = v;
                }
            }
            self.store_leaves(blk, 0, block, &out);
            match tail {
                Some((_, idx, optional)) => {
                    let k = *idx.last().expect("tail leaf");
                    let next_dst = self.b.ins().iadd_imm_s(blk, lay.offsets[k] as i64);
                    let args = [BlockArg::Value(sv[k]), BlockArg::Value(next_dst)];
                    if optional {
                        self.b.ins().brif(sv[idx[0]], head, &args, exit, &[]);
                    } else {
                        self.b.ins().jump(head, &args);
                    }
                }
                None => {
                    self.b.ins().jump(exit, &[]);
                }
            }
            self.b.switch_to_block(next);
        }
        self.store_leaves(blk, 0, block, &sv);
        self.b.ins().jump(exit, &[]);
        self.b.switch_to_block(exit);
        self.b.ins().load(types::I64, flags(), result_addr, 0)
    }

    fn glue_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => self.list_copy(ty, vs),
            TyKind::Rec(_) => {
                let held = self.guard_held(ty, vs);
                let mut out = Vec::new();
                for (fty, at, w) in self.fields_of(ty) {
                    let part = &vs[at..at + w];
                    match held {
                        Some((flag, value_at)) if at == value_at && m.needs_drop(fty) => {
                            out.extend(self.copy_if(flag, fty, part));
                        }
                        _ => out.extend(self.copy_value(fty, part)),
                    }
                }
                out
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                // Null stays null; otherwise copy the payload into a fresh block.
                let p = vs[0];
                let leaves = self.g.lay.leaves(inner);
                let size = mem_layout(&leaves).size as i64;
                let join = self.b.create_block();
                self.b.append_block_param(join, types::I64);
                let yes = self.b.create_block();
                self.b.ins().brif(p, yes, &[], join, &[BlockArg::Value(p)]);
                self.b.switch_to_block(yes);
                let payload = self.load_leaves(p, 0, &leaves);
                let c = self.copy_value(inner, &payload);
                let q = self.alloc(size);
                self.store_leaves(q, 0, &leaves, &c);
                self.b.ins().jump(join, &[BlockArg::Value(q)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.copy_value(ty, vs),
            TyKind::Opt(inner) => {
                if self.g.lay.opt_is_nullable(inner) {
                    // Retain through copy_value on a non-null pointer.
                    let p = vs[0];
                    let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, p, 0);
                    self.if_then(nn, |s| s.retain(p));
                    vs.to_vec()
                } else {
                    // Copy the payload only when present; otherwise the zero payload is returned.
                    let present = vs[0];
                    let payload = vs[1..].to_vec();
                    let leaves = self.g.lay.leaves(inner);
                    let join = self.b.create_block();
                    for l in &leaves {
                        self.b.append_block_param(join, leaf_type(*l));
                    }
                    let yes = self.b.create_block();
                    self.b.ins().brif(present, yes, &[], join, &bargs(&payload));
                    self.b.switch_to_block(yes);
                    let c = self.copy_value(inner, &payload);
                    self.b.ins().jump(join, &bargs(&c));
                    self.b.switch_to_block(join);
                    let mut out = vec![present];
                    out.extend(self.b.block_params(join).to_vec());
                    out
                }
            }
            TyKind::Alt(_) => self.alt_copy(ty, vs),
            TyKind::Obj(..) => {
                let leaves = self.g.lay.leaves(ty);
                let src = self.spill(vs, &leaves);
                let dst = self.spill(vs, &leaves);
                let d = self.typedesc_addr(ty);
                self.rt_call("msrt_slot_copy", &[d, src, dst]);
                self.load_leaves(dst, 0, &leaves)
            }
            TyKind::Iface(i) => {
                // The payload copier sits after the methods in the vtable. The copy owns its
                // payload whatever the source owned, so the tag bits come off.
                let (data, vt) = (vs[0], self.b.ins().band_imm_s(vs[1], !3));
                let slot = 8 * (1 + self.g.m.ifaces[i.index()].methods.len()) as i32;
                let f = self.b.ins().load(types::I64, flags(), vt, slot);
                let mut sig = self.g.module.make_signature();
                sig.params.push(ir::AbiParam::new(types::I64));
                sig.returns.push(ir::AbiParam::new(types::I64));
                let sr = self.b.import_signature(sig);
                let c = self.b.ins().call_indirect(sr, f, &[data]);
                vec![self.b.inst_results(c)[0], vt]
            }
            _ => vs.to_vec(),
        }
    }

    fn list_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        let elem = m.list_elem(ty);
        let (ptr, len) = (vs[0], vs[1]);
        let size = elem.map_or(1, |e| mem_layout(&self.g.lay.leaves(e)).size.max(1) as i64);
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I64);
        let some = self.b.create_block();
        let empty_ptr = self.iconst(0);
        let nonempty = self.b.ins().icmp_imm_s(IntCC::NotEqual, len, 0);
        self.b
            .ins()
            .brif(nonempty, some, &[], join, &[BlockArg::Value(empty_ptr)]);
        self.b.switch_to_block(some);
        let bytes = self.b.ins().imul_imm_s(len, size);
        let np = self.rt_call("msrt_alloc", &[bytes])[0];
        match elem.filter(|e| m.needs_drop(*e)) {
            None => {
                self.b
                    .call_memcpy(self.g.module.target_config(), np, ptr, bytes);
            }
            Some(e) => {
                let leaves = self.g.lay.leaves(e);
                let head = self.b.create_block();
                let body = self.b.create_block();
                let done = self.b.create_block();
                self.b.append_block_param(head, types::I64);
                let zero = self.iconst(0);
                self.b.ins().jump(head, &[BlockArg::Value(zero)]);
                self.b.switch_to_block(head);
                let i = self.b.block_params(head)[0];
                let more = self.b.ins().icmp(IntCC::SignedLessThan, i, len);
                self.b.ins().brif(more, body, &[], done, &[]);
                self.b.switch_to_block(body);
                let off = self.b.ins().imul_imm_s(i, size);
                let src = self.b.ins().iadd(ptr, off);
                let dst = self.b.ins().iadd(np, off);
                let ev = self.load_leaves(src, 0, &leaves);
                let cv = self.copy_value(e, &ev);
                self.store_leaves(dst, 0, &leaves, &cv);
                let next = self.b.ins().iadd_imm_s(i, 1);
                self.b.ins().jump(head, &[BlockArg::Value(next)]);
                self.b.switch_to_block(done);
            }
        }
        self.b.ins().jump(join, &[BlockArg::Value(np)]);
        self.b.switch_to_block(join);
        let p = self.b.block_params(join)[0];
        vec![p, len, len]
    }

    fn alt_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let TyKind::Alt(a) = self.g.m.types.kind(ty).clone() else {
            return vs.to_vec();
        };
        let fields = self.alt_fields(a);
        let shape = self.g.lay.shape(ty);
        let boxed = matches!(shape.alt, Some(AltRepr::Boxed { .. }));
        if boxed && self.has_tail(ty, &fields) {
            return vec![self.copy_boxed_iter(ty, &fields, vs[0])];
        }
        let leaves = match &shape.alt {
            Some(AltRepr::Boxed { block, .. }) => block.clone(),
            _ => shape.leaves.clone(),
        };
        // Source leaves: boxed values are loaded from the block.
        let src: Vs = if boxed {
            self.load_leaves(vs[0], 0, &leaves)
        } else {
            vs.to_vec()
        };
        let join = self.b.create_block();
        for l in &leaves {
            self.b.append_block_param(join, leaf_type(*l));
        }
        let tag = src[0];
        for (c, case) in fields.iter().enumerate() {
            if !case.iter().any(|(t, _)| self.g.m.needs_drop(*t)) {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            let mut out = src.clone();
            for (fty, idx) in case {
                if !self.g.m.needs_drop(*fty) {
                    continue;
                }
                let fv: Vs = idx.iter().map(|i| src[*i]).collect();
                let cv = self.copy_value(*fty, &fv);
                for (i, v) in idx.iter().zip(cv) {
                    out[*i] = v;
                }
            }
            self.b.ins().jump(join, &bargs(&out));
            self.b.switch_to_block(next);
        }
        self.b.ins().jump(join, &bargs(&src));
        self.b.switch_to_block(join);
        let out = self.b.block_params(join).to_vec();
        if boxed {
            let size = mem_layout(&leaves).size as i64;
            let Some((unit, addr)) = self.unit_case(a, out[0]) else {
                let blk = self.alloc(size);
                self.store_leaves(blk, 0, &leaves, &out);
                return vec![blk];
            };
            let fin = self.b.create_block();
            self.b.append_block_param(fin, types::I64);
            let fresh = self.b.create_block();
            self.b
                .ins()
                .brif(unit, fin, &[BlockArg::Value(addr)], fresh, &[]);
            self.b.switch_to_block(fresh);
            let blk = self.alloc(size);
            self.store_leaves(blk, 0, &leaves, &out);
            self.b.ins().jump(fin, &[BlockArg::Value(blk)]);
            self.b.switch_to_block(fin);
            vec![self.b.block_params(fin)[0]]
        } else {
            out
        }
    }

    /// The address of the static descriptor for slots of type `ty`.
    fn typedesc_addr(&mut self, ty: Ty) -> Value {
        let d = self.g.typedesc(ty);
        self.data_addr(d)
    }

    /// Spills `vs` into a fresh stack slot laid out per `leaves` and returns its address.
    fn spill(&mut self, vs: &[Value], leaves: &[Leaf]) -> Value {
        let lay = mem_layout(leaves);
        let slot = self.b.create_sized_stack_slot(StackSlotData::new(
            StackSlotKind::ExplicitSlot,
            lay.size.max(8),
            3,
        ));
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

    /// Whether `ty` is the `{value, taken}` record of a user-facing `Shared[T]` (a builder's
    /// `{items, sealed}` keeps owning its items once sealed).
    fn is_shared_box(&self, ty: Ty) -> bool {
        let m = self.g.m;
        matches!(m.types.kind(ty), TyKind::Rec(r) if m.records[r.index()].name.starts_with("Shared#"))
    }

    fn is_wide(&self, ty: Ty) -> bool {
        matches!(self.g.m.types.kind(ty), TyKind::Str)
            || matches!(self.g.m.types.kind(ty), TyKind::Obj(n, _) if n == "Map" || n == "Set")
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

    pub fn lower_func(&mut self, f: &Func) {
        let rpo = f.rpo();
        self.g.scope_base = self.g.scopes.len() as u32;
        let base = self.g.scope_base;
        for sc in &f.scopes {
            let mut sc = sc.clone();
            if sc.parent != 0 {
                sc.parent += base;
            }
            self.g.scopes.push(sc);
        }
        self.blocks = vec![None; f.blocks.len()];
        self.vals = vec![Vec::new(); f.values.len()];
        self.homes = vec![None; f.values.len()];
        self.used = vec![false; f.values.len()];
        self.lazy = vec![false; f.values.len()];
        self.slot_of.clear();
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
            self.slot_value = None;
            let insts = &f.blocks[b.index()].insts;
            for (ii, inst) in insts.iter().enumerate() {
                self.set_loc(inst.loc);
                self.refresh(f, inst.args.iter().copied());
                if !self.preserves_slot_value(f, inst) {
                    self.slot_value = None;
                }
                let stored_field = ii
                    .checked_sub(2)
                    .is_some_and(|start| self.store_changed_field(f, &insts[start..=ii]));
                if !stored_field {
                    self.lower_inst(f, inst);
                }
                if inst.op == Op::Put {
                    let value = self.a(inst, 1);
                    self.slot_value = Some((inst.args[0], f.ty(inst.args[1]), value));
                }
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

    /// No drop, or a buffer free with no descriptor or user callbacks.
    fn drop_cannot_call_user(&self, ty: Ty) -> bool {
        match self.g.m.types.kind(ty) {
            TyKind::Str | TyKind::Bytes => true,
            TyKind::List(element) => !self.g.m.needs_drop(*element),
            _ => !self.g.m.needs_drop(ty),
        }
    }

    fn preserves_slot_value(&self, f: &Func, inst: &Inst) -> bool {
        match inst.op {
            Op::Load | Op::Take => true,
            Op::Drop => self.drop_cannot_call_user(f.ty(inst.args[0])),
            Op::RecSet => {
                let Imm::Field(record, field) = inst.imm else {
                    return false;
                };
                self.drop_cannot_call_user(
                    self.g.m.records[record.index()].fields[field as usize].1,
                )
            }
            _ => {
                let effects = inst.op.info().effects;
                !effects.writes && !effects.rc && !effects.alloc && !effects.io
            }
        }
    }

    /// `take p; rec.set r.field, value; put p, r` changes only that field in `p`.
    /// Keep the record update's drop where it is, then store only the changed leaves.
    /// Adjacency excludes intervening operations; buffer frees cannot call back and
    /// change another field while the record update drops the old field.
    fn store_changed_field(&mut self, f: &Func, window: &[Inst]) -> bool {
        let [take, set, put] = window else {
            return false;
        };
        if take.op != Op::Take || set.op != Op::RecSet || put.op != Op::Put {
            return false;
        }
        let (Some(old), Some(new)) = (take.res, set.res) else {
            return false;
        };
        if set.args[0] != old || put.args != [take.args[0], new] {
            return false;
        }
        let Imm::Field(_, field) = set.imm else {
            return false;
        };
        let ty = f.ty(old);
        let (field_ty, at, width) = self.fields_of(ty)[field as usize];
        if !self.drop_cannot_call_user(field_ty) {
            return false;
        }
        // Nested fields share the parent's flattened leaf layout. Their standalone
        // padding can differ, so use each leaf's actual parent offset.
        let layout = self.g.lay.mem(ty);
        let leaves = self.g.lay.leaves(ty);
        let pointer = self.a(put, 0)[0];
        let value = self.a(put, 1);
        for i in at..at + width {
            self.store_leaf(leaves[i], value[i], pointer, layout.offsets[i] as i32);
        }
        true
    }

    pub fn lower_main(&mut self, entry: usize) {
        let blk = self.b.create_block();
        self.b.append_block_params_for_function_params(blk);
        self.b.switch_to_block(blk);
        let p = self.b.block_params(blk).to_vec();
        let (argc, argv) = (self.b.ins().sextend(types::I64, p[0]), p[1]);
        let fid = self.g.funcs[entry];
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
                    self.b.ins().brif(c, tb, &ta, eb, &ea);
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

    fn lower_inst(&mut self, f: &Func, inst: &Inst) {
        let checks = self.g.opts.checks;
        let previous_overflow = self.overflow_result.take();
        let m = self.g.m;
        let res_ty = inst.res.map(|r| f.ty(r));
        let out: Vs = match inst.op {
            Op::IConst => {
                let Imm::Int(v) = inst.imm else {
                    unreachable!()
                };
                vec![self.iconst(v)]
            }
            Op::FConst if res_ty == Some(Ty::FLOAT32) => {
                vec![self.b.ins().f32const(inst.imm.float() as f32)]
            }
            Op::FConst => vec![self.b.ins().f64const(inst.imm.float())],
            Op::BConst => {
                let Imm::Bool(v) = inst.imm else {
                    unreachable!()
                };
                vec![self.b.ins().iconst(types::I8, v as i64)]
            }
            Op::UnitConst => vec![],
            Op::StrLit => {
                let Imm::Str(s) = inst.imm else {
                    unreachable!()
                };
                let d = self.g.str_lit(s.0);
                if let Some(r) = inst.res {
                    self.str_lits.insert(r.index(), s.0);
                }
                let base = self.data_addr(d);
                let ptr = base;
                let len = self.g.m.strings[s.0 as usize].len() as i64;
                let tagged = self.iconst(len | STR_STATIC as i64);
                vec![ptr, tagged]
            }
            Op::IAdd => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if let Some((Op::IAdd, _, _, v)) =
                    previous_overflow.filter(|p| p.1 == x && p.2 == y)
                {
                    v
                } else {
                    self.b.ins().iadd(x, y)
                }
            }],
            Op::ISub => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().isub(x, y)
            }],
            Op::IMul => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if let Some((Op::IMul, _, _, v)) =
                    previous_overflow.filter(|p| p.1 == x && p.2 == y)
                {
                    v
                } else {
                    self.mul(x, y)
                }
            }],
            Op::INeg => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().ineg(x)
            }],
            Op::IAddOverflow | Op::IMulOverflow => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                let (v, of) = if inst.op == Op::IAddOverflow {
                    self.b.ins().sadd_overflow(x, y)
                } else {
                    self.mul_overflow(x, y)
                };
                self.overflow_result = Some((
                    if inst.op == Op::IAddOverflow {
                        Op::IAdd
                    } else {
                        Op::IMul
                    },
                    x,
                    y,
                    v,
                ));
                vec![of]
            }
            Op::IntOverflowIf => {
                if checks {
                    self.fault_if(self.a(inst, 0)[0], "msrt_fault_int_overflow", vec![]);
                }
                vec![]
            }
            Op::NarrowChk => {
                let x = self.a(inst, 0)[0];
                let (lo, hi) = self
                    .g
                    .lay
                    .m
                    .types
                    .int_range(f.ty(inst.args[0]))
                    .unwrap_or((i64::MIN.into(), i64::MAX.into()));
                if checks {
                    let (lo_k, hi_k) = (
                        self.b.ins().iconst(types::I64, lo as i64),
                        self.b.ins().iconst(types::I64, hi as i64),
                    );
                    let lo = self.b.ins().icmp(IntCC::SignedLessThan, x, lo_k);
                    let hi = self.b.ins().icmp(IntCC::SignedGreaterThan, x, hi_k);
                    let bad = self.b.ins().bor(lo, hi);
                    self.fault_if(bad, "msrt_fault_int_range", vec![]);
                }
                vec![x]
            }
            Op::Conv => {
                let x = self.a(inst, 0)[0];
                let to = if res_ty == Some(Ty::FLOAT32) {
                    types::F32
                } else {
                    types::F64
                };
                vec![self.float_as(x, to)]
            }
            Op::INarrowOpt => {
                let x = self.a(inst, 0)[0];
                let inner = res_ty.and_then(|r| self.g.lay.m.opt_inner(r));
                let from = f.ty(inst.args[0]);
                let (lo, hi) = inner.map_or((i64::MIN, i64::MAX), |i| {
                    self.g.lay.m.types.narrow_range(from, i)
                });
                let (lo_k, hi_k) = (
                    self.b.ins().iconst(types::I64, lo),
                    self.b.ins().iconst(types::I64, hi),
                );
                let ge = self.b.ins().icmp(IntCC::SignedGreaterThanOrEqual, x, lo_k);
                let le = self.b.ins().icmp(IntCC::SignedLessThanOrEqual, x, hi_k);
                let ok = self.b.ins().band(ge, le);
                vec![ok, x]
            }
            Op::F32Round => vec![{
                let x = self.a(inst, 0)[0];
                self.float_as(x, types::F32)
            }],
            Op::IAddChk | Op::ISubChk | Op::IMulChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if !checks {
                    vec![match inst.op {
                        Op::IAddChk => self.b.ins().iadd(x, y),
                        Op::ISubChk => self.b.ins().isub(x, y),
                        _ => self.mul(x, y),
                    }]
                } else {
                    let (v, of) = match inst.op {
                        Op::IAddChk => self.b.ins().sadd_overflow(x, y),
                        Op::ISubChk => self.b.ins().ssub_overflow(x, y),
                        _ => self.mul_overflow(x, y),
                    };
                    self.fault_if(of, "msrt_fault_int_overflow", vec![]);
                    vec![v]
                }
            }
            Op::UAddChk | Op::USubChk | Op::UMulChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if !checks {
                    vec![match inst.op {
                        Op::UAddChk => self.b.ins().iadd(x, y),
                        Op::USubChk => self.b.ins().isub(x, y),
                        _ => self.mul(x, y),
                    }]
                } else {
                    let (v, of) = match inst.op {
                        Op::UAddChk => self.b.ins().uadd_overflow(x, y),
                        Op::USubChk => self.b.ins().usub_overflow(x, y),
                        _ => self.b.ins().umul_overflow(x, y),
                    };
                    self.fault_if(of, "msrt_fault_int_range", vec![]);
                    vec![v]
                }
            }
            Op::INegChk => {
                let x = self.a(inst, 0)[0];
                if checks {
                    let z = self.iconst(0);
                    let (v, of) = self.b.ins().ssub_overflow(z, x);
                    self.fault_if(of, "msrt_fault_int_overflow", vec![]);
                    vec![v]
                } else {
                    vec![self.b.ins().ineg(x)]
                }
            }
            Op::SDivChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if checks {
                    let z = self.b.ins().icmp_imm_s(IntCC::Equal, y, 0);
                    self.fault_if(z, "msrt_fault_div_zero", vec![]);
                    let m1 = self.b.ins().icmp_imm_s(IntCC::Equal, y, -1);
                    let mn = self.b.ins().icmp_imm_s(IntCC::Equal, x, i64::MIN);
                    let both = self.b.ins().band(m1, mn);
                    self.fault_if(both, "msrt_fault_div_overflow", vec![x, y]);
                }
                vec![self.b.ins().sdiv(x, y)]
            }
            Op::SRemChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if checks {
                    let z = self.b.ins().icmp_imm_s(IntCC::Equal, y, 0);
                    self.fault_if(z, "msrt_fault_rem_zero", vec![]);
                }
                let m1 = self.b.ins().icmp_imm_s(IntCC::Equal, y, -1);
                let one = self.iconst(1);
                let safe = self.b.ins().select(m1, one, y);
                let r = self.b.ins().srem(x, safe);
                let zero = self.iconst(0);
                vec![self.b.ins().select(m1, zero, r)]
            }
            Op::SDiv => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().sdiv(x, y)
            }],
            Op::SRem => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().srem(x, y)
            }],
            Op::And => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().band(x, y)
            }],
            Op::Or => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().bor(x, y)
            }],
            Op::Xor => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().bxor(x, y)
            }],
            Op::Shl => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().ishl(x, y)
            }],
            Op::Sshr => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().sshr(x, y)
            }],
            Op::Not => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().bxor_imm_s(x, 1)
            }],
            Op::UICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                let cc = match cc {
                    Cc::Eq => IntCC::Equal,
                    Cc::Ne => IntCC::NotEqual,
                    Cc::Lt => IntCC::UnsignedLessThan,
                    Cc::Le => IntCC::UnsignedLessThanOrEqual,
                    Cc::Gt => IntCC::UnsignedGreaterThan,
                    Cc::Ge => IntCC::UnsignedGreaterThanOrEqual,
                };
                vec![self.b.ins().icmp(cc, x, y)]
            }
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                vec![self.b.ins().icmp(Self::icc(cc), x, y)]
            }
            Op::FCmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                vec![self.b.ins().fcmp(Self::fcc(cc), x, y)]
            }
            Op::FAdd => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fadd(x, y)
            }],
            Op::FSub => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fsub(x, y)
            }],
            Op::FMul => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fmul(x, y)
            }],
            Op::FDiv => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fdiv(x, y)
            }],
            Op::FNeg => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().fneg(x)
            }],
            Op::FSqrt => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().sqrt(x)
            }],
            Op::FFloor => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().floor(x)
            }],
            Op::FCeil => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().ceil(x)
            }],
            Op::FTrunc => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().trunc(x)
            }],
            Op::FAbs => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().fabs(x)
            }],
            Op::I2F => vec![{
                let x = self.a(inst, 0)[0];
                if res_ty == Some(Ty::FLOAT32) {
                    self.b.ins().fcvt_from_sint(types::F32, x)
                } else {
                    self.b.ins().fcvt_from_sint(types::F64, x)
                }
            }],
            Op::F2IOpt => {
                let v = self.a(inst, 0)[0];
                let v = self.float_as(v, types::F64);
                let lo = self.b.ins().f64const(-9223372036854775808.0);
                let hi = self.b.ins().f64const(9223372036854775808.0);
                let ge = self.b.ins().fcmp(FloatCC::GreaterThanOrEqual, v, lo);
                let lt = self.b.ins().fcmp(FloatCC::LessThan, v, hi);
                let ok = self.b.ins().band(ge, lt);
                vec![ok, self.b.ins().fcvt_to_sint_sat(types::I64, v)]
            }
            Op::B2I => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().uextend(types::I64, x)
            }],
            Op::Select => {
                let c = self.a(inst, 0)[0];
                let (t, e) = (self.a(inst, 1), self.a(inst, 2));
                t.iter()
                    .zip(&e)
                    .map(|(x, y)| self.b.ins().select(c, *x, *y))
                    .collect()
            }
            Op::RecNew => (0..inst.args.len()).flat_map(|i| self.a(inst, i)).collect(),
            Op::RecGet => {
                let Imm::Field(_, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (_, at, w) = self.fields_of(ty)[i as usize];
                self.a(inst, 0)[at..at + w].to_vec()
            }
            Op::RecSet | Op::RecFill => {
                let Imm::Field(_, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (fty, at, w) = self.fields_of(ty)[i as usize];
                let mut obj = self.a(inst, 0);
                if inst.op == Op::RecSet && m.needs_drop(fty) {
                    let old = obj[at..at + w].to_vec();
                    self.drop_value(fty, &old);
                }
                let new = self.a(inst, 1);
                obj.splice(at..at + w, new);
                obj
            }
            Op::AltNew | Op::AltView => self.alt_new(inst, res_ty.expect("alt.new result")),
            Op::AltTag => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { .. }) => {
                        vec![self.b.ins().load(types::I64, flags(), v[0], 0)]
                    }
                    _ => vec![v[0]],
                }
            }
            Op::AltGet | Op::AltTake => {
                let Imm::AltField(a, c, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (_, idx) = self.alt_fields(a)[c as usize][i as usize].clone();
                let v = self.a(inst, 0);
                match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => {
                        let lay = mem_layout(block);
                        idx.iter()
                            .map(|k| {
                                self.b.ins().load(
                                    leaf_type(block[*k]),
                                    flags(),
                                    v[0],
                                    lay.offsets[*k] as i32,
                                )
                            })
                            .collect()
                    }
                    _ => idx.iter().map(|k| v[*k]).collect(),
                }
            }
            Op::RecRelease => {
                let Imm::RecMask(_, mask) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                // Drop the fields that were not moved out; a record owns no block of its own.
                for (k, (fty, at, w)) in self.fields_of(ty).into_iter().enumerate() {
                    if mask >> k & 1 == 0 {
                        self.drop_value(fty, &v[at..at + w]);
                    }
                }
                vec![]
            }
            Op::AltRelease => {
                let Imm::AltMask(a, c, mask) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let case = self.alt_fields(a)[c as usize].clone();
                let v = self.a(inst, 0);
                let boxed = match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => Some(block.clone()),
                    _ => None,
                };
                // Drop the payload fields that were not moved out, then free the block.
                for (k, (fty, idx)) in case.iter().enumerate() {
                    if mask >> k & 1 == 1 || !m.needs_drop(*fty) {
                        continue;
                    }
                    let fv: Vs = match &boxed {
                        Some(block) => {
                            let lay = mem_layout(block);
                            idx.iter()
                                .map(|j| {
                                    self.b.ins().load(
                                        leaf_type(block[*j]),
                                        flags(),
                                        v[0],
                                        lay.offsets[*j] as i32,
                                    )
                                })
                                .collect()
                        }
                        None => idx.iter().map(|j| v[*j]).collect(),
                    };
                    self.drop_value(*fty, &fv);
                }
                if boxed.is_some() {
                    self.free(v[0]);
                }
                vec![]
            }
            Op::AltUnbox => {
                let Imm::AltField(a, c, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let case = self.alt_fields(a)[c as usize].clone();
                let v = self.a(inst, 0);
                let boxed = match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => Some(block.clone()),
                    _ => None,
                };
                // Read every payload leaf of the case, drop all fields but `i`, free the block.
                let fields: Vec<Vs> = case
                    .iter()
                    .map(|(_, idx)| match &boxed {
                        Some(block) => {
                            let lay = mem_layout(block);
                            idx.iter()
                                .map(|k| {
                                    self.b.ins().load(
                                        leaf_type(block[*k]),
                                        flags(),
                                        v[0],
                                        lay.offsets[*k] as i32,
                                    )
                                })
                                .collect()
                        }
                        None => idx.iter().map(|k| v[*k]).collect(),
                    })
                    .collect();
                for (k, ((fty, _), fv)) in case.iter().zip(&fields).enumerate() {
                    if k != i as usize {
                        self.drop_value(*fty, fv);
                    }
                }
                if boxed.is_some() {
                    self.free(v[0]);
                }
                fields[i as usize].clone()
            }
            Op::ListNew
            | Op::ListLit
            | Op::ListLen
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::ListSet
            | Op::ListSetNn
            | Op::ListSetU
            | Op::ListFill
            | Op::ListPush
            | Op::ListDropLast => self.lower_list(f, inst),
            Op::OptSome | Op::OptView => {
                let ty = res_ty.expect("opt.some result");
                let v = self.a(inst, 0);
                if self.opt_boxed(ty) {
                    assert!(
                        inst.op == Op::OptSome,
                        "a borrowed optional cannot have a boxed layout"
                    );
                    let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                        unreachable!()
                    };
                    let leaves = self.g.lay.leaves(inner);
                    let p = self.alloc(mem_layout(&leaves).size as i64);
                    self.store_leaves(p, 0, &leaves, &v);
                    vec![p]
                } else if self.opt_niche(ty) {
                    v
                } else {
                    let one = self.b.ins().iconst(types::I8, 1);
                    let mut out = vec![one];
                    out.extend(v);
                    out
                }
            }
            Op::OptNone => {
                let ty = res_ty.expect("opt.none result");
                self.zeros(ty)
            }
            Op::OptIsSome => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                if self.opt_niche(ty) {
                    vec![self.opt_present(ty, &v)]
                } else {
                    vec![v[0]]
                }
            }
            Op::OptGet | Op::OptUnwrap => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                let nullable = self.opt_niche(ty);
                if inst.op == Op::OptUnwrap && checks {
                    // Every layout keeps the presence word (null pointer or tag) first; an
                    // optional string also needs its tag.
                    let none = if self.g.lay.is_str_like(ty) {
                        let some = self.opt_present(ty, &v);
                        self.b.ins().icmp_imm_s(IntCC::Equal, some, 0)
                    } else {
                        self.b.ins().icmp_imm_s(IntCC::Equal, v[0], 0)
                    };
                    self.fault_if(none, "msrt_fault_unwrap_none", vec![]);
                }
                let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                    unreachable!()
                };
                let payload = if self.opt_boxed(ty) {
                    let leaves = self.g.lay.leaves(inner);
                    self.load_leaves(v[0], 0, &leaves)
                } else if nullable {
                    v
                } else {
                    v[1..].to_vec()
                };
                // `unwrap` returns an owned value; `get` borrows.
                if inst.op == Op::OptUnwrap {
                    self.copy_value(inner, &payload)
                } else {
                    payload
                }
            }
            Op::OptUnbox => {
                // Moves the payload out of a some: the box (if any) is freed, the payload lives on.
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                    unreachable!()
                };
                if self.opt_boxed(ty) {
                    let leaves = self.g.lay.leaves(inner);
                    let payload = self.load_leaves(v[0], 0, &leaves);
                    self.free(v[0]);
                    payload
                } else if self.opt_niche(ty) {
                    v
                } else {
                    v[1..].to_vec()
                }
            }
            Op::StrByte => {
                // An inline string's bytes are its two words, little-endian.
                let (s, i) = (self.a(inst, 0), self.a(inst, 1)[0]);
                let inline = self.str_is_inline(s[1]);
                let (word, mem, join) = (
                    self.b.create_block(),
                    self.b.create_block(),
                    self.b.create_block(),
                );
                self.b.append_block_param(join, types::I64);
                self.b.ins().brif(inline, word, &[], mem, &[]);
                self.b.switch_to_block(word);
                let high = self
                    .b
                    .ins()
                    .icmp_imm_s(IntCC::SignedGreaterThanOrEqual, i, 8);
                let w = self.b.ins().select(high, s[1], s[0]);
                let shift = self.b.ins().band_imm_s(i, 7);
                let shift = self.b.ins().ishl_imm_u(shift, 3);
                let w = self.b.ins().ushr(w, shift);
                let w = self.b.ins().band_imm_s(w, 0xff);
                self.b.ins().jump(join, &[BlockArg::Value(w)]);
                self.b.switch_to_block(mem);
                let at = self.b.ins().iadd(s[0], i);
                let byte = self.b.ins().load(types::I8, flags(), at, 0);
                let byte = self.b.ins().uextend(types::I64, byte);
                self.b.ins().jump(join, &[BlockArg::Value(byte)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            Op::StrAscii => {
                let b = self.a(inst, 0)[0];
                let d = self.g.rt_data("msrt_ascii_chars");
                let base = self.data_addr(d);
                let off = self.b.ins().imul_imm_s(b, ASCII_CHAR_STRIDE as i64);
                let ptr = self.b.ins().iadd(base, off);
                let tagged = self.iconst(1 | STR_STATIC as i64);
                vec![ptr, tagged]
            }
            Op::StrLen => {
                // Scalar count: computed by the runtime (long strings are remembered there).
                let s = self.a(inst, 0);
                let at = match self.home_of(inst.args[0]) {
                    Some(h) => h.addr,
                    None => self.spill(&s, &[Leaf::I64; 2]),
                };
                vec![self.rt_call("msrt_string_length", &[at])[0]]
            }
            Op::SharedNew => {
                let t = self.g.m.types.kind(res_ty.expect("result")).clone();
                let TyKind::Obj(_, args) = t else {
                    unreachable!()
                };
                let leaves = self.g.lay.leaves(args[0]);
                let size = SHARED_VALUE + mem_layout(&leaves).size as i64;
                let obj = self.alloc(size);
                let one = self.iconst(1);
                self.b.ins().store(flags(), one, obj, 0);
                let drop = self.g.glue(Glue::SharedDrop, args[0]);
                let dr = self.fref(drop);
                let da = self.b.ins().func_addr(types::I64, dr);
                self.b.ins().store(flags(), da, obj, 8);
                let v = self.a(inst, 0);
                self.store_leaves(obj, SHARED_VALUE, &leaves, &v);
                vec![obj]
            }
            Op::SharedGet => {
                let obj = self.a(inst, 0)[0];
                let leaves = self.g.lay.leaves(res_ty.expect("result"));
                self.load_leaves(obj, SHARED_VALUE, &leaves)
            }
            Op::SharedAddr => {
                let obj = self.a(inst, 0)[0];
                vec![self.add_imm(obj, SHARED_VALUE)]
            }
            Op::ClosureNew => self.closure_new(inst),
            Op::ClosureCap => {
                let Imm::Idx(i) = inst.imm else {
                    unreachable!()
                };
                let ms_mir::ir::FuncKind::Closure { captures } = &f.kind else {
                    unreachable!()
                };
                let mut off = CLOSURE_CAPTURES as i64;
                let mut found = (0, Vec::new());
                for (k, c) in captures.iter().enumerate() {
                    let leaves = self.g.lay.leaves(*c);
                    let lay = mem_layout(&leaves);
                    off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
                    if k == i as usize {
                        found = (off, leaves);
                    }
                    off += lay.size as i64;
                }
                let env = self.a(inst, 0)[0];
                self.load_leaves(env, found.0, &found.1)
            }
            Op::IfaceNew => {
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let size = mem_layout(&leaves).size as i64;
                let blk = self.alloc(size);
                let v = self.a(inst, 0);
                self.store_leaves(blk, 0, &leaves, &v);
                let id = self.g.vtables[vt.index()];
                let addr = self.data_addr(id);
                vec![blk, addr]
            }
            Op::IfaceLend => {
                // A box holding the borrowed leaves as they are; the tag says only the box is
                // freed.
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let size = mem_layout(&leaves).size as i64;
                let blk = self.alloc(size);
                let v = self.a(inst, 0);
                self.store_leaves(blk, 0, &leaves, &v);
                let id = self.g.vtables[vt.index()];
                let addr = self.data_addr(id);
                vec![blk, self.b.ins().bor_imm_s(addr, 1)]
            }
            Op::IfaceView => {
                let v = self.a(inst, 0);
                let vt = self.b.ins().band_imm_s(v[1], !3);
                vec![v[0], self.b.ins().bor_imm_s(vt, 2)]
            }
            Op::IfaceData => vec![self.a(inst, 0)[0]],
            Op::IfaceIs => {
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let have = self.a(inst, 0)[1];
                let have = self.b.ins().band_imm_s(have, !3);
                let id = self.g.vtables[vt.index()];
                let want = self.data_addr(id);
                vec![self.b.ins().icmp(IntCC::Equal, have, want)]
            }
            Op::MoveOut => self.a(inst, 0),
            Op::Copy => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                self.copy_value(ty, &v)
            }
            Op::Drop => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                self.drop_value(ty, &v);
                vec![]
            }
            Op::DropIf => {
                let ty = f.ty(inst.args[1]);
                let flag = self.a(inst, 0)[0];
                let v = self.a(inst, 1);
                self.if_then(flag, |s| s.drop_value(ty, &v));
                vec![]
            }
            Op::Slot => {
                let Imm::Ty(ty) = inst.imm else {
                    unreachable!()
                };
                let lay = self.g.lay.mem(ty);
                let slot = self.b.create_sized_stack_slot(StackSlotData::new(
                    StackSlotKind::ExplicitSlot,
                    lay.size.max(8),
                    3,
                ));
                if let Some(r) = inst.res {
                    self.slot_of.insert(r.index(), slot);
                    self.slot_blk.insert(r.index(), self.cur);
                }
                vec![self.b.ins().stack_addr(types::I64, slot, 0)]
            }
            Op::ListAddr | Op::ListAddrU => {
                let lt = f.ty(inst.args[0]);
                let (_, _, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let mode = if inst.op == Op::ListAddr {
                    Op::ListGet
                } else {
                    Op::ListGetU
                };
                vec![self.elem_addr(l[0], l[1], i, size, mode)]
            }
            Op::PtrIsNull => {
                let p = self.a(inst, 0)[0];
                vec![self.b.ins().icmp_imm_s(IntCC::Equal, p, 0)]
            }
            Op::PtrField => {
                let Imm::Field(r, i) = inst.imm else {
                    unreachable!()
                };
                let rty = m.types.find(&TyKind::Rec(r)).expect("record type interned");
                let (_, at, _) = self.fields_of(rty)[i as usize];
                let lay = self.g.lay.mem(rty);
                let off = lay.offsets.get(at).copied().unwrap_or(0) as i64;
                // The result is read and written with the field's own layout, so each of its
                // leaves must sit at the same distance from the field's address as in the field.
                debug_assert!(
                    {
                        let fty = m.records[r.index()].fields[i as usize].1;
                        let own = mem_layout(&self.g.lay.leaves(fty));
                        own.offsets
                            .iter()
                            .enumerate()
                            .all(|(k, o)| lay.offsets[at + k] - lay.offsets[at] == *o)
                    },
                    "field {i} of record {r:?} is laid out differently inside the record"
                );
                let p = self.a(inst, 0)[0];
                vec![self.add_imm(p, off)]
            }
            Op::Load | Op::Take => {
                let Imm::Ty(ty) = inst.imm else {
                    unreachable!()
                };
                let leaves = self.g.lay.leaves(ty);
                let p = self.a(inst, 0)[0];
                let out = match &self.slot_value {
                    Some((slot, held_ty, value)) if *slot == inst.args[0] && *held_ty == ty => {
                        value.clone()
                    }
                    _ => self.load_leaves(p, 0, &leaves),
                };
                if inst.op == Op::Take
                    && self.is_wide(ty)
                    && let Some(r) = inst.res
                {
                    self.homes[r.index()] = Some(Home {
                        addr: p,
                        slot: self.slot_of.get(&inst.args[0].index()).copied(),
                        blk: Some(self.cur),
                    });
                }
                out
            }
            Op::Store | Op::Put => {
                let ty = f.ty(inst.args[1]);
                let (dst, src) = (inst.args[0].index(), inst.args[1]);
                // A wide value moving into a fresh slot just adopts the memory it already lives in.
                if inst.op == Op::Put
                    && self.is_wide(ty)
                    && !self.used[dst]
                    && self.slot_blk.get(&dst) == Some(&self.cur)
                    && let Some(h) = self.home_of(src)
                {
                    self.vals[dst] = vec![h.addr];
                    match h.slot {
                        Some(s) => self.slot_of.insert(dst, s),
                        None => self.slot_of.remove(&dst),
                    };
                    return;
                }
                let leaves = self.g.lay.leaves(ty);
                let (p, v) = (self.a(inst, 0)[0], self.a(inst, 1));
                self.store_leaves(p, 0, &leaves, &v);
                vec![]
            }
            Op::Call => {
                let Imm::Func(c) = inst.imm else {
                    unreachable!()
                };
                let args: Vs = (0..inst.args.len()).flat_map(|i| self.a(inst, i)).collect();
                let id = self.g.funcs[c.index()];
                self.call_id(id, &args)
            }
            Op::CallInd => self.call_closure(f, inst),
            Op::CallMethod => self.call_method(inst),
            Op::CallRt => self.call_extern(f, inst),
            Op::FuncAddr => {
                let Imm::Func(g) = inst.imm else {
                    unreachable!()
                };
                let r = self.fref(self.g.funcs[g.index()]);
                vec![self.b.ins().func_addr(types::I64, r)]
            }
            Op::TypeDesc => {
                let Imm::Ty(t) = inst.imm else { unreachable!() };
                vec![self.typedesc_addr(t)]
            }
            Op::Poll => {
                if self.g.opts.poll {
                    let hdr = self.task_hdr();
                    let addr = self.add_imm(hdr, ISOLATE_HDR_CANCEL);
                    let v = self.b.ins().atomic_load(types::I8, flags(), addr);
                    self.fault_if(v, "msrt_cancelled", vec![]);
                }
                vec![]
            }
            Op::DepthEnter => {
                let hdr = self.task_hdr();
                let limit = self.b.ins().load(types::I64, flags(), hdr, 0);
                let sp = self.b.ins().get_stack_pointer(types::I64);
                let over = self.b.ins().icmp(IntCC::UnsignedLessThan, sp, limit);
                self.fault_if(over, "msrt_fault_depth", vec![]);
                vec![]
            }
            Op::DepthLeave => vec![],
            Op::CleanupPush => {
                let Imm::Func(c) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let v = self.a(inst, 0);
                let thunk = self.g.glue(Glue::CleanupThunk(c.0), Ty::UNIT);
                if !self.g.m.funcs[c.index()].unwind_only {
                    let slot = self.spill(&v, &leaves);
                    let r = self.fref(thunk);
                    let fa = self.b.ins().func_addr(types::I64, r);
                    self.rt_call("msrt_cleanup_push", &[fa, slot])
                } else {
                    // A closer that only acts while a guarded task unwinds: with no guard open the
                    // registration is skipped, and its handle 0 makes the discard a no-op.
                    let hdr = self.task_hdr();
                    let guarded =
                        self.b
                            .ins()
                            .load(types::I8, flags(), hdr, ISOLATE_HDR_GUARDED as i32);
                    let none = self.iconst(0);
                    let push = self.b.create_block();
                    let join = self.b.create_block();
                    self.b.append_block_param(join, types::I64);
                    self.b.ins().brif(guarded, push, &[], join, &[none.into()]);
                    self.b.switch_to_block(push);
                    let slot = self.spill(&v, &leaves);
                    let r = self.fref(thunk);
                    let fa = self.b.ins().func_addr(types::I64, r);
                    let h = self.rt_call("msrt_cleanup_push", &[fa, slot])[0];
                    self.b.ins().jump(join, &[h.into()]);
                    self.b.switch_to_block(join);
                    self.b.block_params(join).to_vec()
                }
            }
            Op::CleanupRun => {
                let h = self.a(inst, 0)[0];
                self.rt_call("msrt_cleanup_run", &[h]);
                vec![]
            }
            Op::GlobalGet | Op::GlobalSet => {
                let Imm::Global(gi) = inst.imm else {
                    unreachable!()
                };
                let ty = m.globals[gi.index()].ty;
                let leaves = self.g.lay.leaves(ty);
                let addr = self.data_addr(self.g.globals[gi.index()]);
                if inst.op == Op::GlobalGet {
                    self.load_leaves(addr, 0, &leaves)
                } else {
                    if m.needs_drop(ty) {
                        let old = self.load_leaves(addr, 0, &leaves);
                        self.drop_value(ty, &old);
                    }
                    let v = self.a(inst, 0);
                    self.store_leaves(addr, 0, &leaves, &v);
                    vec![]
                }
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

    fn elem_info(&self, list_ty: Ty) -> (Ty, Vec<Leaf>, i64) {
        let e = self.g.m.list_elem(list_ty).unwrap_or(Ty::INT);
        let leaves = self.g.lay.leaves(e);
        let size = mem_layout(&leaves).size as i64;
        (e, leaves, size)
    }

    /// Normalizes `i` (negative counts from the end) and bounds-checks it; returns the element address.
    fn elem_addr(&mut self, ptr: Value, len: Value, i: Value, size: i64, mode: Op) -> Value {
        let idx = match mode {
            Op::ListGet | Op::ListSet | Op::ListFill => {
                let neg = self.b.ins().icmp_imm_s(IntCC::SignedLessThan, i, 0);
                let wrapped = self.b.ins().iadd(i, len);
                self.b.ins().select(neg, wrapped, i)
            }
            _ => i,
        };
        if self.g.opts.checks && !matches!(mode, Op::ListGetU | Op::ListSetU) {
            let oob = self
                .b
                .ins()
                .icmp(IntCC::UnsignedGreaterThanOrEqual, idx, len);
            self.fault_if(oob, "msrt_index_fault", vec![i, len]);
        }
        let off = self.b.ins().imul_imm_s(idx, size);
        self.b.ins().iadd(ptr, off)
    }

    fn lower_list(&mut self, f: &Func, inst: &Inst) -> Vs {
        let res_ty = inst.res.map(|r| f.ty(r)).expect("list op result");
        match inst.op {
            Op::ListNew => {
                let (_, _, size) = self.elem_info(res_ty);
                let cap = self.a(inst, 0)[0];
                let join = self.b.create_block();
                self.b.append_block_param(join, types::I64);
                let some = self.b.create_block();
                let null = self.iconst(0);
                self.b
                    .ins()
                    .brif(cap, some, &[], join, &[BlockArg::Value(null)]);
                self.b.switch_to_block(some);
                let bytes = self.b.ins().imul_imm_s(cap, size.max(1));
                let p = self.rt_call("msrt_alloc", &[bytes])[0];
                self.b.ins().jump(join, &[BlockArg::Value(p)]);
                self.b.switch_to_block(join);
                let p = self.b.block_params(join)[0];
                let zero = self.iconst(0);
                vec![p, zero, cap]
            }
            Op::ListLit => {
                let (_, leaves, size) = self.elem_info(res_ty);
                let n = inst.args.len() as i64;
                if n == 0 {
                    let z = self.iconst(0);
                    return vec![z, z, z];
                }
                let p = self.alloc(n * size);
                for i in 0..inst.args.len() {
                    let v = self.a(inst, i);
                    self.store_leaves(p, i as i64 * size, &leaves, &v);
                }
                let nn = self.iconst(n);
                vec![p, nn, nn]
            }
            Op::ListLen => vec![self.a(inst, 0)[1]],
            Op::ListGet | Op::ListGetNn | Op::ListGetU => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let at = self.elem_addr(l[0], l[1], i, size, inst.op);
                self.load_leaves(at, 0, &leaves)
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                let lt = f.ty(inst.args[0]);
                let (e, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let v = self.a(inst, 2);
                let at = self.elem_addr(l[0], l[1], i, size, inst.op);
                if inst.op != Op::ListFill && self.g.m.needs_drop(e) {
                    let old = self.load_leaves(at, 0, &leaves);
                    self.drop_value(e, &old);
                }
                self.store_leaves(at, 0, &leaves, &v);
                l
            }
            Op::ListDropLast => {
                let lt = f.ty(inst.args[0]);
                let (e, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let nl = self.b.ins().iadd_imm_s(l[1], -1);
                if self.g.m.needs_drop(e) {
                    let off = self.b.ins().imul_imm_s(nl, size);
                    let at = self.b.ins().iadd(l[0], off);
                    let old = self.load_leaves(at, 0, &leaves);
                    self.drop_value(e, &old);
                }
                vec![l[0], nl, l[2]]
            }
            Op::ListPush => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let v = self.a(inst, 1);
                let (ptr, len, cap) = (l[0], l[1], l[2]);
                let full = self.b.ins().icmp(IntCC::Equal, len, cap);
                let ready = self.b.create_block();
                self.b.append_block_param(ready, types::I64);
                self.b.append_block_param(ready, types::I64);
                let grow = self.b.create_block();
                self.b.set_cold_block(grow);
                self.b.ins().brif(
                    full,
                    grow,
                    &[],
                    ready,
                    &[BlockArg::Value(ptr), BlockArg::Value(cap)],
                );
                self.b.switch_to_block(grow);
                let empty = self.b.ins().icmp_imm_s(IntCC::Equal, cap, 0);
                let four = self.iconst(4);
                let doubled = self.b.ins().ishl_imm_s(cap, 1);
                let ncap = self.b.ins().select(empty, four, doubled);
                let bytes = self.b.ins().imul_imm_s(ncap, size.max(1));
                let first = self.b.create_block();
                let again = self.b.create_block();
                let joined = self.b.create_block();
                self.b.append_block_param(joined, types::I64);
                self.b.ins().brif(empty, first, &[], again, &[]);
                self.b.switch_to_block(first);
                let np = self.rt_call("msrt_alloc", &[bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(np)]);
                self.b.switch_to_block(again);
                let rp = self.rt_call("msrt_realloc", &[ptr, bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(rp)]);
                self.b.switch_to_block(joined);
                let np = self.b.block_params(joined)[0];
                self.b
                    .ins()
                    .jump(ready, &[BlockArg::Value(np), BlockArg::Value(ncap)]);
                self.b.switch_to_block(ready);
                let (p, c) = (self.b.block_params(ready)[0], self.b.block_params(ready)[1]);
                let off = self.b.ins().imul_imm_s(len, size);
                let at = self.b.ins().iadd(p, off);
                self.store_leaves(at, 0, &leaves, &v);
                let nl = self.b.ins().iadd_imm_s(len, 1);
                vec![p, nl, c]
            }
            _ => unreachable!(),
        }
    }

    fn closure_new(&mut self, inst: &Inst) -> Vs {
        let Imm::Func(c) = inst.imm else {
            unreachable!()
        };
        let caps = match &self.g.m.funcs[c.index()].kind {
            ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
            _ => Vec::new(),
        };
        let mut layouts = Vec::new();
        let mut off = CLOSURE_CAPTURES as i64;
        for cty in &caps {
            let leaves = self.g.lay.leaves(*cty);
            let lay = mem_layout(&leaves);
            off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
            layouts.push((off, leaves));
            off += lay.size as i64;
        }
        let total = (off + 7) / 8 * 8;
        let obj = self.alloc(total);
        let one = self.iconst(1);
        self.b.ins().store(flags(), one, obj, 0);
        let drop = self.g.glue(Glue::ClosureDrop(c.0), Ty::UNIT);
        let dr = self.fref(drop);
        let da = self.b.ins().func_addr(types::I64, dr);
        self.b.ins().store(flags(), da, obj, 8);
        let code = self.g.funcs[c.index()];
        let cr = self.fref(code);
        let ca = self.b.ins().func_addr(types::I64, cr);
        self.b.ins().store(flags(), ca, obj, CLOSURE_CODE);
        for (i, (off, leaves)) in layouts.iter().enumerate() {
            let v = self.a(inst, i);
            self.store_leaves(obj, *off, leaves, &v);
        }
        vec![obj]
    }

    fn call_closure(&mut self, f: &Func, inst: &Inst) -> Vs {
        let clo = self.a(inst, 0)[0];
        let TyKind::Fn(ps, r) = self.g.m.types.kind(f.ty(inst.args[0])).clone() else {
            unreachable!()
        };
        let mut params = vec![Leaf::I64];
        for p in &ps {
            params.extend(self.g.lay.leaves(*p));
        }
        let rets = self.g.lay.leaves(r);
        let sig = self.g.sig(&params, &rets);
        let sr = self.b.import_signature(sig);
        let code = self.b.ins().load(types::I64, flags(), clo, CLOSURE_CODE);
        let mut args = vec![clo];
        for i in 1..inst.args.len() {
            args.extend(self.a(inst, i));
        }
        let c = self.b.ins().call_indirect(sr, code, &args);
        self.b.inst_results(c).to_vec()
    }

    fn call_method(&mut self, inst: &Inst) -> Vs {
        let Imm::Method(iface, k) = inst.imm else {
            unreachable!()
        };
        let recv = self.a(inst, 0);
        let sig = self.g.m.ifaces[iface.index()].methods[k as usize].clone();
        let mut params = vec![Leaf::I64];
        for p in &sig.params {
            params.extend(self.g.lay.leaves(*p));
        }
        let rets = self.g.lay.leaves(sig.ret);
        let csig = self.g.sig(&params, &rets);
        let sr = self.b.import_signature(csig);
        let vt = self.b.ins().band_imm_s(recv[1], !3);
        let code = self
            .b
            .ins()
            .load(types::I64, flags(), vt, 8 * (1 + k as i32));
        let mut args = vec![recv[0]];
        for i in 1..inst.args.len() {
            args.extend(self.a(inst, i));
        }
        let c = self.b.ins().call_indirect(sr, code, &args);
        self.b.inst_results(c).to_vec()
    }

    /// Calls a runtime function with the ABI mapping of `ms-rt`: aggregates by pointer
    /// to a spilled copy, aggregate results through a trailing out pointer.
    /// `s == "lit"` for a literal of one to eight bytes without a NUL, compared inline: the
    /// length word, then the bytes in power-of-two chunks (read only once the length matches,
    /// so no load passes the object's NUL terminator).
    fn string_eq_literal(&mut self, inst: &Inst) -> Option<Vs> {
        let (lit, other) = match (
            self.str_lits.get(&inst.args[0].index()),
            self.str_lits.get(&inst.args[1].index()),
        ) {
            (_, Some(l)) => (*l, self.a(inst, 0)),
            (Some(l), None) => (*l, self.a(inst, 1)),
            (None, None) => return None,
        };
        let bytes = self.g.m.strings[lit as usize].as_bytes().to_vec();
        if bytes.is_empty() || bytes.len() > 8 || bytes.contains(&0) {
            return None;
        }
        let unaligned = MemFlagsData::new().with_notrap();
        // The literal as an inline string: equal words. Another kind of string compares its
        // masked length (never the literal's for an inline string) and then its bytes.
        let mut word = [0u8; 8];
        word[..bytes.len()].copy_from_slice(&bytes);
        let inline_tag = (STR_INLINE | (bytes.len() << STR_INLINE_LEN_SHIFT)) as i64;
        let same_tag = self.b.ins().icmp_imm_s(IntCC::Equal, other[1], inline_tag);
        let same_word = self
            .b
            .ins()
            .icmp_imm_s(IntCC::Equal, other[0], i64::from_le_bytes(word));
        let inline_eq = self.b.ins().band(same_tag, same_word);
        let len = self.b.ins().band_imm_s(other[1], STR_LEN_MASK as i64);
        let same_len = self
            .b
            .ins()
            .icmp_imm_s(IntCC::Equal, len, bytes.len() as i64);
        let check = self.b.create_block();
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I8);
        let no = self.b.ins().iconst(types::I8, 0);
        self.b
            .ins()
            .brif(same_len, check, &[], join, &[BlockArg::Value(inline_eq)]);
        let _ = no;
        self.b.switch_to_block(check);
        let mut all = None;
        let mut at = 0;
        while at < bytes.len() {
            let n = [8, 4, 2, 1]
                .into_iter()
                .find(|n| bytes.len() - at >= *n)
                .unwrap();
            let ty = match n {
                8 => types::I64,
                4 => types::I32,
                2 => types::I16,
                _ => types::I8,
            };
            let mut word = [0u8; 8];
            word[..n].copy_from_slice(&bytes[at..at + n]);
            let shift = 64 - 8 * n as u32;
            let want = (i64::from_le_bytes(word) << shift) >> shift;
            let got = self.b.ins().load(ty, unaligned, other[0], at as i32);
            let eq = self.b.ins().icmp_imm_s(IntCC::Equal, got, want);
            all = Some(match all {
                Some(a) => self.b.ins().band(a, eq),
                None => eq,
            });
            at += n;
        }
        self.b
            .ins()
            .jump(join, &[BlockArg::Value(all.expect("non-empty literal"))]);
        self.b.switch_to_block(join);
        Some(vec![self.b.block_params(join)[0]])
    }

    /// `a == b` for two strings: differing lengths are unequal and identical pointers equal without
    /// a call; only same-length distinct blocks reach the runtime.
    fn string_eq_inline(&mut self, f: &Func, inst: &Inst) -> Vs {
        let (a, b) = (self.a(inst, 0), self.a(inst, 1));
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I8);
        let no = self.b.ins().iconst(types::I8, 0);
        let (same_hi, other_kind, slow) = (
            self.b.create_block(),
            self.b.create_block(),
            self.b.create_block(),
        );
        // `x = a.tagged ^ b.tagged`. With `0 < x < 1 << 62` both have one kind and the low bits
        // differ: different lengths, or for inline strings different bytes. Either way unequal.
        let x = self.b.ins().bxor(a[1], b[1]);
        let below = self.b.ins().iadd_imm_s(x, -1);
        let differ =
            self.b
                .ins()
                .icmp_imm_u(IntCC::UnsignedLessThan, below, (STR_INLINE - 1) as i64);
        let undecided = self.b.create_block();
        self.b
            .ins()
            .brif(differ, join, &[BlockArg::Value(no)], undecided, &[]);
        self.b.switch_to_block(undecided);
        let is_same = self.b.ins().icmp_imm_s(IntCC::Equal, x, 0);
        self.b.ins().brif(is_same, same_hi, &[], other_kind, &[]);
        // Same second word: the same first word is the same string. Otherwise inline strings
        // differ, and other kinds of one length compare their bytes.
        self.b.switch_to_block(same_hi);
        let same_ptr = self.b.ins().icmp(IntCC::Equal, a[0], b[0]);
        let inline = self.str_is_inline(a[1]);
        let known = self.b.ins().bor(same_ptr, inline);
        self.b
            .ins()
            .brif(known, join, &[BlockArg::Value(same_ptr)], slow, &[]);
        // Different kinds are equal only with the same byte length; the runtime compares bytes.
        self.b.switch_to_block(other_kind);
        let (la, lb) = (self.str_byte_len(a[1]), self.str_byte_len(b[1]));
        let same_len = self.b.ins().icmp(IntCC::Equal, la, lb);
        self.b
            .ins()
            .brif(same_len, slow, &[], join, &[BlockArg::Value(no)]);
        self.b.switch_to_block(slow);
        let r = self.call_extern_plain(f, inst);
        self.b.ins().jump(join, &[BlockArg::Value(r[0])]);
        self.b.switch_to_block(join);
        vec![self.b.block_params(join)[0]]
    }

    fn call_extern(&mut self, f: &Func, inst: &Inst) -> Vs {
        let Imm::Ext(e) = inst.imm else {
            unreachable!()
        };
        if self.g.m.externs[e.index()].name == "msrt_string_eq" {
            if let Some(r) = self.string_eq_literal(inst) {
                return r;
            }
            return self.string_eq_inline(f, inst);
        }
        if self.g.m.externs[e.index()].name == "msrt_cleanup_discard" {
            // Handle 0 is a registration skipped for lack of a guard.
            let h = self.a(inst, 0)[0];
            self.if_then(h, |s| {
                s.call_extern_plain(f, inst);
            });
            return vec![];
        }
        self.call_extern_plain(f, inst)
    }

    fn call_extern_plain(&mut self, f: &Func, inst: &Inst) -> Vs {
        let Imm::Ext(e) = inst.imm else {
            unreachable!()
        };
        let def = self.g.m.externs[e.index()].clone();
        let id = match self.g.ext.get(&e) {
            Some(id) => *id,
            None => {
                let direct =
                    |lay: &crate::layout::Layouts, t: Ty| -> bool { Self::passes_directly(lay, t) };
                let mut params: Vec<Leaf> = Vec::new();
                for p in &def.params {
                    if direct(&self.g.lay, p.ty) {
                        params.extend(self.g.lay.leaves(p.ty));
                    } else {
                        params.push(Leaf::I64);
                    }
                }
                let rets: Vec<Leaf> = if direct(&self.g.lay, def.ret) {
                    self.g.lay.leaves(def.ret)
                } else {
                    params.push(Leaf::I64);
                    Vec::new()
                };
                // Native code takes and returns a `Float32` as `f64`.
                let wide = |ls: &mut Vec<Leaf>| {
                    for l in ls.iter_mut().filter(|l| **l == Leaf::F32) {
                        *l = Leaf::F64;
                    }
                };
                wide(&mut params);
                let mut rets = rets;
                wide(&mut rets);
                let sig = self.g.sig(&params, &rets);
                let id = self
                    .g
                    .module
                    .declare_function(&def.name, cranelift_module::Linkage::Import, &sig)
                    .expect("declare extern");
                self.g.ext.insert(e, id);
                id
            }
        };
        let mut args: Vs = Vec::new();
        for (i, p) in def.params.iter().enumerate() {
            let v = self.a(inst, i);
            if Self::passes_directly(&self.g.lay, p.ty) {
                args.extend(v);
            } else if let Some(h) = self.home_of(inst.args[i]) {
                args.push(h.addr);
            } else {
                let leaves = self.g.lay.leaves(p.ty);
                args.push(self.spill(&v, &leaves));
            }
        }
        let ret_ty = def.ret;
        let _ = f;
        if def.name == "msrt_strbuilder_append"
            && args.len() == 2
            && self.g.lay.leaves(ret_ty).is_empty()
        {
            if let Some(&lit) = self.str_lits.get(&inst.args[1].index()) {
                let bytes = self.g.m.strings[lit as usize].as_bytes().to_vec();
                if (1..=16).contains(&bytes.len()) {
                    return self.strbuilder_append_literal(id, args[0], args[1], &bytes);
                }
            }
            return self.strbuilder_append(id, args[0], args[1]);
        }
        if def.name == "msrt_bytes_append"
            && args.len() == 2
            && self.g.lay.leaves(ret_ty).is_empty()
        {
            return self.bytes_append(id, args[0], args[1]);
        }
        if Self::passes_directly(&self.g.lay, ret_ty) {
            self.call_id(id, &args)
        } else {
            let leaves = self.g.lay.leaves(ret_ty);
            let lay = mem_layout(&leaves);
            let slot = self.b.create_sized_stack_slot(StackSlotData::new(
                StackSlotKind::ExplicitSlot,
                lay.size.max(8),
                3,
            ));
            let out = self.b.ins().stack_addr(types::I64, slot, 0);
            args.push(out);
            self.call_id(id, &args);
            if self.is_wide(ret_ty)
                && let Some(r) = inst.res
            {
                self.homes[r.index()] = Some(Home {
                    addr: out,
                    slot: Some(slot),
                    blk: Some(self.cur),
                });
            }
            self.load_leaves(out, 0, &leaves)
        }
    }

    /// `StringBuilder.append` of a literal of 1 to 16 bytes with room to spare is a few constant
    /// stores and a length bump. The bytes are known here, so no length decode or copy loop
    /// remains; a full buffer calls the runtime.
    fn strbuilder_append_literal(
        &mut self,
        id: FuncId,
        builder: Value,
        text: Value,
        bytes: &[u8],
    ) -> Vs {
        let n = bytes.len();
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let next = self.b.ins().iadd_imm_s(len, n as i64);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThanOrEqual, next, cap);
        let store = self.b.create_block();
        let slow = self.b.create_block();
        self.b.set_cold_block(slow);
        let join = self.b.create_block();
        self.b.ins().brif(room, store, &[], slow, &[]);
        self.b.switch_to_block(store);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        // Overlapping stores of the widest width that fits cover every length without a loop.
        let unaligned = MemFlagsData::new().with_notrap();
        let word = |from: usize, w: usize| {
            let mut x = 0u64;
            for (i, b) in bytes[from..from + w].iter().enumerate() {
                x |= (*b as u64) << (8 * i);
            }
            x as i64
        };
        let (w, ty) = match n {
            8..=16 => (8, types::I64),
            4..=7 => (4, types::I32),
            2..=3 => (2, types::I16),
            _ => (1, types::I8),
        };
        let first = self.b.ins().iconst(ty, word(0, w));
        self.b.ins().store(unaligned, first, at, 0);
        if n > w {
            let last = self.b.ins().iconst(ty, word(n - w, w));
            self.b.ins().store(unaligned, last, at, (n - w) as i32);
        }
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(slow);
        self.call_id(id, &[builder, text]);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(join);
        Vec::new()
    }

    /// `StringBuilder.append` of a string with room to spare is a capacity check, a copy and a
    /// length bump: a one-byte string is a store, anything longer one `memcpy`. An inline string
    /// (whose length sits in different bits) and a full buffer call the runtime, which makes the
    /// same tests first.
    fn strbuilder_append(&mut self, id: FuncId, builder: Value, text: Value) -> Vs {
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let tagged = self
            .b
            .ins()
            .load(types::I64, flags(), text, STR_LEN_OFFSET as i32);
        let size = self.b.ins().band_imm_s(tagged, STR_LEN_MASK as i64);
        let tag = self.b.ins().ushr_imm_u(tagged, 62);
        let flat = self.b.ins().icmp_imm_s(IntCC::NotEqual, tag, 1);
        let next = self.b.ins().iadd(len, size);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThanOrEqual, next, cap);
        let fast = self.b.ins().band(flat, room);
        let store = self.b.create_block();
        let slow = self.b.create_block();
        self.b.set_cold_block(slow);
        let join = self.b.create_block();
        self.b.ins().brif(fast, store, &[], slow, &[]);
        self.b.switch_to_block(store);
        let bytes = self
            .b
            .ins()
            .load(types::I64, flags(), text, STR_PTR_OFFSET as i32);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        let single = self.b.ins().icmp_imm_s(IntCC::Equal, size, 1);
        let one = self.b.create_block();
        let many = self.b.create_block();
        let done = self.b.create_block();
        self.b.ins().brif(single, one, &[], many, &[]);
        self.b.switch_to_block(one);
        let byte = self.b.ins().load(types::I8, flags(), bytes, 0);
        self.b.ins().store(flags(), byte, at, 0);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(many);
        self.b
            .call_memcpy(self.g.module.target_config(), at, bytes, size);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(done);
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(slow);
        self.call_id(id, &[builder, text]);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(join);
        Vec::new()
    }

    /// `BytesBuilder.append` of a byte value with room to spare is a store and a length bump;
    /// an out-of-range value (which faults) or a full buffer calls the runtime.
    fn bytes_append(&mut self, id: FuncId, builder: Value, value: Value) -> Vs {
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let byte = self
            .b
            .ins()
            .icmp_imm_s(IntCC::UnsignedLessThanOrEqual, value, 255);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThan, len, cap);
        let fast = self.b.ins().band(byte, room);
        let store = self.b.create_block();
        let slow = self.b.create_block();
        self.b.set_cold_block(slow);
        let join = self.b.create_block();
        self.b.ins().brif(fast, store, &[], slow, &[]);
        self.b.switch_to_block(store);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        let narrow = self.b.ins().ireduce(types::I8, value);
        self.b.ins().store(flags(), narrow, at, 0);
        let next = self.b.ins().iadd_imm_s(len, 1);
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(slow);
        self.call_id(id, &[builder, value]);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(join);
        Vec::new()
    }

    fn passes_directly(lay: &crate::layout::Layouts, t: Ty) -> bool {
        match lay.m.types.kind(t) {
            TyKind::Unit
            | TyKind::Bool
            | TyKind::Int
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::UInt8
            | TyKind::UInt16
            | TyKind::UInt32
            | TyKind::UInt64
            | TyKind::Float
            | TyKind::Float32
            | TyKind::Ptr
            | TyKind::Fn(..)
            | TyKind::Iface(_) => true,
            TyKind::Obj(n, _) => n != "Map" && n != "Set",
            TyKind::Opt(inner) => lay.opt_is_nullable(*inner) || lay.m.types.is_scalar(*inner),
            _ => false,
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
