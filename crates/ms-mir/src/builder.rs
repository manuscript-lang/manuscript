//! A convenience builder for functions, with optional SSA variables.
//!
//! The builder infers result types from operands and immediates where the
//! opcode determines them. Mutable source variables can be modelled with
//! [`Var`]s (`declare_var`, `def_var`, `use_var`, `seal_block`), which the
//! builder turns into block parameters (Braun et al., *Simple and Efficient
//! Construction of SSA Form*). The builder never inserts `retain`/`release`:
//! reference counting is the caller's job, and the verifier checks it.

use crate::ir::*;
use crate::types::*;
use std::collections::HashMap;

/// A mutable variable resolved to SSA values by the builder.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Var(pub u32);

impl Var {
    fn index(self) -> usize {
        self.0 as usize
    }
}

struct VarInfo {
    ty: Ty,
    mode: Mode,
    /// Defined exactly once, where every use it has is dominated by the definition: reads need no
    /// search for the reaching definition or block parameters.
    single: Option<Value>,
    is_single: bool,
}

/// Builds one function inside a module.
pub struct FuncBuilder<'m> {
    /// The module being extended (types, strings and declarations are interned here).
    pub m: &'m mut Module,
    f: Func,
    cur: Block,
    loc: Loc,
    vars: Vec<VarInfo>,
    defs: HashMap<(Var, Block), Value>,
    preds: Vec<Vec<Block>>,
    sealed: Vec<bool>,
    incomplete: HashMap<Block, Vec<(Var, Value)>>,
    /// Block parameters found trivial, mapped to the value they were replaced by. Definitions and
    /// edge arguments that still name a removed parameter are resolved through this map when read
    /// and once more when the function is finished.
    forward: HashMap<Value, Value>,
}

impl<'m> FuncBuilder<'m> {
    /// Starts a function; the entry block is current and sealed.
    pub fn new(m: &'m mut Module, name: &str, params: Vec<Param>, ret: Ty) -> Self {
        let f = Func::new(name, params, ret);
        FuncBuilder {
            m,
            f,
            cur: Block(0),
            loc: Loc::NONE,
            vars: Vec::new(),
            defs: HashMap::new(),
            preds: vec![Vec::new()],
            sealed: vec![true],
            incomplete: HashMap::new(),
            forward: HashMap::new(),
        }
    }

    /// Mutable access to the function under construction (linkage, kind, hints).
    pub fn func_mut(&mut self) -> &mut Func {
        &mut self.f
    }

    /// The entry block's parameter values.
    pub fn params(&self) -> Vec<Value> {
        self.f.param_values()
    }

    /// The type of a value.
    pub fn ty(&self, v: Value) -> Ty {
        self.f.ty(v)
    }

    /// The op that defined `v` in the current block, if it was defined there.
    pub fn defining_op(&self, v: Value) -> Option<Op> {
        let insts = &self.f.blocks[self.cur.index()].insts;
        insts.iter().rev().find(|i| i.res == Some(v)).map(|i| i.op)
    }

    /// Whether `v` is a borrow: defined by an operation whose result borrows, or a borrowed
    /// parameter. Searches every block; an undefined value is not.
    pub fn is_borrowed(&self, v: Value) -> bool {
        for b in &self.f.blocks {
            if let Some(p) = b.params.iter().find(|p| p.value == v) {
                return p.mode == crate::ir::Mode::Borrow;
            }
            if let Some(i) = b.insts.iter().find(|i| i.res == Some(v)) {
                return self.m.result_mode(&self.f, i) != Some(crate::ir::Mode::Own);
            }
        }
        false
    }

    /// The first operand of the instruction that defined `v` in the current block.
    pub fn defining_operand(&self, v: Value) -> Option<Value> {
        let insts = &self.f.blocks[self.cur.index()].insts;
        insts
            .iter()
            .rev()
            .find(|i| i.res == Some(v))
            .and_then(|i| i.args.first().copied())
    }

    /// Sets the source location attached to subsequently emitted instructions.
    pub fn set_loc(&mut self, loc: Loc) {
        self.loc = loc;
    }

    /// The source location attached to emitted instructions.
    pub fn loc(&self) -> Loc {
        self.loc
    }

    /// The current block.
    pub fn current(&self) -> Block {
        self.cur
    }

    /// Creates a block. It starts unsealed.
    pub fn new_block(&mut self) -> Block {
        self.preds.push(Vec::new());
        self.sealed.push(false);
        self.f.new_block()
    }

    /// Adds a parameter to `b` and returns its value.
    pub fn add_block_param(&mut self, b: Block, ty: Ty, mode: Mode) -> Value {
        let v = self.f.new_value(ty);
        self.f.blocks[b.index()]
            .params
            .push(BlockParam { value: v, mode });
        v
    }

    /// Makes `b` current. Instructions are appended to it.
    pub fn switch_to(&mut self, b: Block) {
        self.cur = b;
    }

    /// Emits an instruction with an explicit result type.
    pub fn emit(&mut self, op: Op, args: &[Value], imm: Imm, res_ty: Option<Ty>) -> Option<Value> {
        let res = res_ty.map(|t| self.f.new_value(t));
        let inst = Inst {
            op,
            args: args.to_vec(),
            imm,
            res,
            loc: self.loc,
        };
        self.f.blocks[self.cur.index()].insts.push(inst);
        res
    }

    fn val(&mut self, op: Op, args: &[Value], imm: Imm, ty: Ty) -> Value {
        self.emit(op, args, imm, Some(ty)).expect("has result")
    }

    // Constants.

    /// `iconst`.
    pub fn iconst(&mut self, v: i64) -> Value {
        self.val(Op::IConst, &[], Imm::Int(v), Ty::INT)
    }
    /// `iconst` of a sized integer type.
    pub fn iconst_ty(&mut self, v: i64, ty: Ty) -> Value {
        self.val(Op::IConst, &[], Imm::Int(v), ty)
    }
    /// `fconst` of a float type; a `Float32` constant must already be binary32-exact.
    pub fn fconst_ty(&mut self, v: f64, ty: Ty) -> Value {
        self.val(Op::FConst, &[], Imm::Float(v.to_bits()), ty)
    }
    /// `fconst`.
    pub fn fconst(&mut self, v: f64) -> Value {
        self.val(Op::FConst, &[], Imm::Float(v.to_bits()), Ty::FLOAT)
    }
    /// `bconst`.
    pub fn bconst(&mut self, v: bool) -> Value {
        self.val(Op::BConst, &[], Imm::Bool(v), Ty::BOOL)
    }
    /// `unit`.
    pub fn unit(&mut self) -> Value {
        self.val(Op::UnitConst, &[], Imm::None, Ty::UNIT)
    }
    /// A string literal (borrowed static object).
    pub fn str_lit(&mut self, s: &str) -> Value {
        let id = self.m.add_string(s);
        self.val(Op::StrLit, &[], Imm::Str(id), Ty::STR)
    }

    // Arithmetic.

    /// A binary operation on two values of the same type as the first operand.
    pub fn binop(&mut self, op: Op, a: Value, b: Value) -> Value {
        let ty = self.ty(a);
        self.val(op, &[a, b], Imm::None, ty)
    }
    /// A unary operation preserving the operand type.
    pub fn unop(&mut self, op: Op, a: Value) -> Value {
        let ty = self.ty(a);
        self.val(op, &[a], Imm::None, ty)
    }
    /// `narrow.chk`: faults unless a sized integer is within its type's range.
    pub fn narrow_chk(&mut self, a: Value) -> Value {
        self.unop(Op::NarrowChk, a)
    }
    /// `f32.round`: rounds a `Float32` to the nearest binary32 value.
    pub fn f32_round(&mut self, a: Value) -> Value {
        self.unop(Op::F32Round, a)
    }
    /// `conv`: the same number as another type of its kind. A `Float32` target rounds.
    pub fn conv(&mut self, a: Value, to: Ty) -> Value {
        self.val(Op::Conv, &[a], Imm::None, to)
    }
    /// `inarrow.opt`: `some(a)` as `to?` when `a` fits the smaller int type `to`.
    pub fn inarrow_opt(&mut self, a: Value, to: Ty) -> Value {
        let t = self.m.types.opt(to);
        self.val(Op::INarrowOpt, &[a], Imm::None, t)
    }
    /// `icmp.cc`. An ordered comparison of `UInt64` operands, which hold a bit pattern, is
    /// the unsigned `uicmp`.
    pub fn icmp(&mut self, cc: Cc, a: Value, b: Value) -> Value {
        if self.ty(a) == Ty::UINT64 && !matches!(cc, Cc::Eq | Cc::Ne) {
            return self.val(Op::UICmp, &[a, b], Imm::Cc(cc), Ty::BOOL);
        }
        self.val(Op::ICmp, &[a, b], Imm::Cc(cc), Ty::BOOL)
    }
    /// `fcmp.cc`.
    pub fn fcmp(&mut self, cc: Cc, a: Value, b: Value) -> Value {
        self.val(Op::FCmp, &[a, b], Imm::Cc(cc), Ty::BOOL)
    }
    /// `i2f`: converts directly to the target float width, rounding once.
    pub fn i2f(&mut self, a: Value, to: Ty) -> Value {
        self.val(Op::I2F, &[a], Imm::None, to)
    }
    /// `f2i.opt`.
    pub fn f2i_opt(&mut self, a: Value) -> Value {
        let t = self.m.types.opt(Ty::INT);
        self.val(Op::F2IOpt, &[a], Imm::None, t)
    }
    /// `select`.
    pub fn select(&mut self, c: Value, a: Value, b: Value) -> Value {
        let ty = self.ty(a);
        self.val(Op::Select, &[c, a, b], Imm::None, ty)
    }

    // Records and alternatives.

    /// `rec.new`.
    pub fn rec_new(&mut self, r: RecId, fields: &[Value]) -> Value {
        let t = self.m.types.rec(r);
        self.val(Op::RecNew, fields, Imm::Rec(r), t)
    }
    /// `rec.get` by field index.
    pub fn rec_get(&mut self, r: RecId, field: u32, obj: Value) -> Value {
        let ty = self.m.records[r.index()].fields[field as usize].1;
        self.val(Op::RecGet, &[obj], Imm::Field(r, field), ty)
    }
    /// `rec.set` by field index.
    pub fn rec_set(&mut self, r: RecId, field: u32, obj: Value, v: Value) -> Value {
        let t = self.ty(obj);
        self.val(Op::RecSet, &[obj, v], Imm::Field(r, field), t)
    }
    /// `rec.fill`: like `rec.set`, for a field whose old value was moved out with `move.out`.
    pub fn rec_fill(&mut self, r: RecId, field: u32, obj: Value, v: Value) -> Value {
        let t = self.ty(obj);
        self.val(Op::RecFill, &[obj, v], Imm::Field(r, field), t)
    }
    /// `move.out`: takes ownership of a borrowed projection without copying it. The projected
    /// slot must be refilled with `rec.fill` or `list.fill` before anything else reads it.
    pub fn move_out(&mut self, v: Value) -> Value {
        let t = self.ty(v);
        self.val(Op::MoveOut, &[v], Imm::None, t)
    }
    /// `alt.new`.
    pub fn alt_new(&mut self, a: AltId, case: u32, fields: &[Value]) -> Value {
        let t = self.m.types.alt(a);
        self.val(Op::AltNew, fields, Imm::Case(a, case), t)
    }
    /// `alt.view`: an alternative holding the borrowed `fields` themselves, which it neither
    /// retains nor releases.
    pub fn alt_view(&mut self, a: AltId, case: u32, fields: &[Value]) -> Value {
        let t = self.m.types.alt(a);
        self.val(Op::AltView, fields, Imm::Case(a, case), t)
    }
    /// `iface.lend`: an interface value whose box holds a bitwise copy of the borrowed `data`
    /// leaves (vtable word tagged 1): dropping it frees the box and leaves the payload alone.
    pub fn iface_lend(&mut self, vt: VtableId, data: Value, t: Ty) -> Value {
        self.val(Op::IfaceLend, &[data], Imm::Vtable(vt), t)
    }
    /// `iface.view`: the borrowed interface value `x` as an owned value that owns nothing
    /// (vtable word tagged 2): dropping it frees nothing.
    pub fn iface_view(&mut self, x: Value) -> Value {
        let t = self.ty(x);
        self.val(Op::IfaceView, &[x], Imm::None, t)
    }
    /// `alt.tag`.
    pub fn alt_tag(&mut self, obj: Value) -> Value {
        self.val(Op::AltTag, &[obj], Imm::None, Ty::INT)
    }
    /// `alt.get`.
    pub fn alt_get(&mut self, a: AltId, case: u32, field: u32, obj: Value) -> Value {
        let ty = self.m.alts[a.index()].cases[case as usize].fields[field as usize].1;
        self.val(Op::AltGet, &[obj], Imm::AltField(a, case, field), ty)
    }
    /// `alt.take`: moves `field` of the active `case` out of the owned `obj`, which an
    /// `alt.release` naming that field must then free.
    pub fn alt_take(&mut self, a: AltId, case: u32, field: u32, obj: Value) -> Value {
        let ty = self.m.alts[a.index()].cases[case as usize].fields[field as usize].1;
        self.val(Op::AltTake, &[obj], Imm::AltField(a, case, field), ty)
    }
    /// `alt.release`: drops the owned `obj` of `case` except the fields in `mask`, which were
    /// taken out.
    pub fn alt_release(&mut self, a: AltId, case: u32, mask: u32, obj: Value) {
        self.emit(Op::AltRelease, &[obj], Imm::AltMask(a, case, mask), None);
    }

    // Lists.

    /// `list.new` with a capacity.
    pub fn list_new(&mut self, elem: Ty, cap: Value) -> Value {
        let t = self.m.types.list(elem);
        self.val(Op::ListNew, &[cap], Imm::None, t)
    }
    /// `list.lit`.
    pub fn list_lit(&mut self, elem: Ty, items: &[Value]) -> Value {
        let t = self.m.types.list(elem);
        self.val(Op::ListLit, items, Imm::None, t)
    }
    /// `list.len`.
    pub fn list_len(&mut self, l: Value) -> Value {
        self.val(Op::ListLen, &[l], Imm::None, Ty::INT)
    }
    /// `str.len`: the scalar count of a string.
    pub fn str_len(&mut self, s: Value) -> Value {
        self.val(Op::StrLen, &[s], Imm::None, Ty::INT)
    }
    /// `list.get` (negative indexes count from the end).
    pub fn list_get(&mut self, l: Value, i: Value) -> Value {
        let e = self.m.list_elem(self.ty(l)).expect("list operand");
        self.val(Op::ListGet, &[l, i], Imm::None, e)
    }
    /// `list.set`.
    pub fn list_set(&mut self, l: Value, i: Value, v: Value) -> Value {
        let t = self.ty(l);
        self.val(Op::ListSet, &[l, i, v], Imm::None, t)
    }
    /// `list.fill`: like `list.set`, for an element that was moved out with `move.out`.
    pub fn list_fill(&mut self, l: Value, i: Value, v: Value) -> Value {
        let t = self.ty(l);
        self.val(Op::ListFill, &[l, i, v], Imm::None, t)
    }
    /// `list.push`.
    pub fn list_push(&mut self, l: Value, v: Value) -> Value {
        let t = self.ty(l);
        self.val(Op::ListPush, &[l, v], Imm::None, t)
    }

    /// `list.droplast`: the list without its last element, which is dropped. The list must not be empty.
    pub fn list_drop_last(&mut self, l: Value) -> Value {
        let t = self.ty(l);
        self.val(Op::ListDropLast, &[l], Imm::None, t)
    }

    // Optionals.

    /// `opt.some`.
    pub fn opt_some(&mut self, v: Value) -> Value {
        let t = self.m.types.opt(self.ty(v));
        self.val(Op::OptSome, &[v], Imm::None, t)
    }
    /// `opt.view`: an optional holding the borrowed `v` itself, which is neither retained nor released.
    pub fn opt_view(&mut self, v: Value) -> Value {
        let t = self.m.types.opt(self.ty(v));
        self.val(Op::OptView, &[v], Imm::None, t)
    }
    /// `opt.none` of the given optional type.
    pub fn opt_none(&mut self, opt_ty: Ty) -> Value {
        self.val(Op::OptNone, &[], Imm::None, opt_ty)
    }
    /// `opt.is_some`.
    pub fn opt_is_some(&mut self, o: Value) -> Value {
        self.val(Op::OptIsSome, &[o], Imm::None, Ty::BOOL)
    }
    /// `opt.get` (unchecked).
    pub fn opt_get(&mut self, o: Value) -> Value {
        let t = self.m.opt_inner(self.ty(o)).expect("optional operand");
        self.val(Op::OptGet, &[o], Imm::None, t)
    }
    /// `opt.unbox`: moves the payload out of an owned present optional, which it consumes.
    pub fn opt_unbox(&mut self, o: Value) -> Value {
        let t = self.m.opt_inner(self.ty(o)).expect("optional operand");
        self.val(Op::OptUnbox, &[o], Imm::None, t)
    }
    /// `opt.unwrap` (faults on none).
    pub fn opt_unwrap(&mut self, o: Value) -> Value {
        let t = self.m.opt_inner(self.ty(o)).expect("optional operand");
        self.val(Op::OptUnwrap, &[o], Imm::None, t)
    }

    // Calls.

    /// `call` a module function.
    pub fn call(&mut self, f: FuncId, args: &[Value]) -> Value {
        let ret = self.m.funcs[f.index()].ret;
        self.val(Op::Call, args, Imm::Func(f), ret)
    }
    /// `call.rt` a runtime function.
    pub fn call_rt(&mut self, e: ExtId, args: &[Value]) -> Value {
        let ret = self.m.externs[e.index()].ret;
        self.val(Op::CallRt, args, Imm::Ext(e), ret)
    }
    /// `call.ind` through a closure value.
    pub fn call_ind(&mut self, closure: Value, args: &[Value]) -> Value {
        let TyKind::Fn(_, r) = self.m.types.kind(self.ty(closure)).clone() else {
            panic!("call_ind needs a closure")
        };
        let mut all = vec![closure];
        all.extend_from_slice(args);
        self.val(Op::CallInd, &all, Imm::None, r)
    }
    /// `call.method` through an interface value.
    pub fn call_method(
        &mut self,
        iface: IfaceId,
        method: u32,
        recv: Value,
        args: &[Value],
    ) -> Value {
        let ret = self.m.ifaces[iface.index()].methods[method as usize].ret;
        let mut all = vec![recv];
        all.extend_from_slice(args);
        self.val(Op::CallMethod, &all, Imm::Method(iface, method), ret)
    }
    /// `poll`.
    pub fn poll(&mut self) {
        self.emit(Op::Poll, &[], Imm::None, None);
    }

    // Terminators.

    fn set_term(&mut self, t: Term) {
        let b = self.cur;
        let mut succs = Vec::new();
        t.for_each_target(|x| succs.push(x.block));
        for s in succs {
            self.preds[s.index()].push(b);
        }
        let blk = &mut self.f.blocks[b.index()];
        blk.term = t;
        blk.term_loc = self.loc;
    }

    /// `br`.
    pub fn br(&mut self, b: Block, args: &[Value]) {
        self.set_term(Term::Br(Target {
            block: b,
            args: args.to_vec(),
        }));
    }
    /// `br_if`.
    pub fn br_if(
        &mut self,
        cond: Value,
        then: Block,
        then_args: &[Value],
        els: Block,
        els_args: &[Value],
    ) {
        self.set_term(Term::CondBr {
            cond,
            then: Target {
                block: then,
                args: then_args.to_vec(),
            },
            els: Target {
                block: els,
                args: els_args.to_vec(),
            },
        });
    }
    /// `switch`.
    pub fn switch(&mut self, value: Value, cases: &[(i64, Block)], default: Block) {
        self.set_term(Term::Switch {
            value,
            cases: cases.iter().map(|(k, b)| (*k, Target::to(*b))).collect(),
            default: Target::to(default),
        });
    }
    /// `ret`.
    pub fn ret(&mut self, v: Option<Value>) {
        self.set_term(Term::Ret(v));
    }
    /// `fault`.
    pub fn fault(&mut self, k: FaultKind) {
        self.set_term(Term::Fault(k));
    }
    /// `unreachable`.
    pub fn unreachable(&mut self) {
        self.set_term(Term::Unreachable);
    }

    // Variables.

    /// Declares a mutable variable. `mode` is the ownership its block parameters carry.
    pub fn declare_var(&mut self, ty: Ty, mode: Mode) -> Var {
        self.vars.push(VarInfo {
            ty,
            mode,
            single: None,
            is_single: false,
        });
        Var(self.vars.len() as u32 - 1)
    }

    /// Declares a variable that is defined once and only read where that definition dominates
    /// (an immutable `let`). Reading it never creates block parameters; defining it twice panics.
    pub fn declare_single(&mut self, ty: Ty, mode: Mode) -> Var {
        self.vars.push(VarInfo {
            ty,
            mode,
            single: None,
            is_single: true,
        });
        Var(self.vars.len() as u32 - 1)
    }

    /// The type a variable was declared with.
    pub fn var_ty(&self, v: Var) -> Ty {
        self.vars[v.0 as usize].ty
    }

    /// The ownership a variable's block parameters carry.
    pub fn var_mode(&self, v: Var) -> Mode {
        self.vars[v.0 as usize].mode
    }

    /// Defines the variable's value at the end of the current block.
    pub fn def_var(&mut self, v: Var, val: Value) {
        let info = &mut self.vars[v.index()];
        if info.is_single {
            assert!(
                info.single.is_none(),
                "single-definition variable {v:?} defined twice"
            );
            info.single = Some(val);
            return;
        }
        self.defs.insert((v, self.cur), val);
    }

    /// The variable's current value in the current block.
    pub fn use_var(&mut self, v: Var) -> Value {
        let b = self.cur;
        self.read_var(v, b)
    }

    /// Declares that every predecessor of `b` has been emitted.
    pub fn seal_block(&mut self, b: Block) {
        if self.sealed[b.index()] {
            return;
        }
        self.sealed[b.index()] = true;
        for (var, param) in self.incomplete.remove(&b).unwrap_or_default() {
            self.add_phi_operands(var, b, param);
        }
    }

    fn read_var(&mut self, v: Var, b: Block) -> Value {
        if self.vars[v.index()].is_single {
            let x = self.vars[v.index()]
                .single
                .unwrap_or_else(|| panic!("variable {v:?} used before it is defined in b{}", b.0));
            return self.resolve(x);
        }
        if let Some(x) = self.defs.get(&(v, b)).copied() {
            return self.resolve(x);
        }
        let info = &self.vars[v.index()];
        let (ty, mode) = (info.ty, info.mode);
        let val = if !self.sealed[b.index()] {
            let p = self.add_block_param(b, ty, mode);
            self.incomplete.entry(b).or_default().push((v, p));
            p
        } else if self.preds[b.index()].len() == 1 {
            let p = self.preds[b.index()][0];
            self.read_var(v, p)
        } else if self.preds[b.index()].is_empty() {
            panic!(
                "variable {v:?} used before it is defined on every path to b{}",
                b.0
            );
        } else {
            let p = self.add_block_param(b, ty, mode);
            self.defs.insert((v, b), p);
            self.add_phi_operands(v, b, p);
            self.without_trivial_param(v, b, p)
        };
        self.defs.insert((v, b), val);
        val
    }

    /// The value a possibly removed block parameter stands for now.
    fn resolve(&mut self, mut v: Value) -> Value {
        let start = v;
        while let Some(&next) = self.forward.get(&v) {
            v = next;
        }
        if v != start {
            self.forward.insert(start, v);
        }
        v
    }

    /// Removes the block parameter `param` of the sealed block `b` when every predecessor
    /// passes the same value, so that value stays live across the join instead of being
    /// handed through an edge (which would consume it for code that still holds it).
    fn without_trivial_param(&mut self, v: Var, b: Block, param: Value) -> Value {
        let idx = self.f.blocks[b.index()]
            .params
            .iter()
            .position(|p| p.value == param)
            .expect("param exists");
        let mut same: Option<Value> = None;
        let mut edges = 0;
        for p in self.preds[b.index()].clone() {
            let mut ok = true;
            let mut args = Vec::new();
            self.f.blocks[p.index()].term.for_each_target_mut(|t| {
                if t.block == b {
                    args.push(t.args.get(idx).copied());
                }
            });
            for a in args {
                edges += 1;
                let a = a.map(|a| self.resolve(a));
                match (a, same) {
                    // A loop passing the parameter around changes nothing.
                    (Some(a), _) if a == param => {}
                    (Some(a), None) => same = Some(a),
                    (Some(a), Some(s)) if a == s => {}
                    _ => ok = false,
                }
            }
            if !ok {
                return param;
            }
        }
        let Some(x) = same.filter(|_| edges > 0) else {
            return param;
        };
        for p in self.preds[b.index()].clone() {
            self.f.blocks[p.index()].term.for_each_target_mut(|t| {
                if t.block == b && t.args.len() > idx {
                    t.args.remove(idx);
                }
            });
        }
        self.f.blocks[b.index()].params.remove(idx);
        self.defs.insert((v, b), x);
        // Whatever still names the parameter resolves to `x` from here on.
        self.forward.insert(param, x);
        x
    }

    fn add_phi_operands(&mut self, v: Var, b: Block, param: Value) {
        let idx = self.f.blocks[b.index()]
            .params
            .iter()
            .position(|p| p.value == param)
            .expect("param exists");
        let mut preds = self.preds[b.index()].clone();
        preds.dedup();
        let mut seen = Vec::new();
        for p in preds {
            if seen.contains(&p) {
                continue;
            }
            seen.push(p);
            let val = self.read_var(v, p);
            self.f.blocks[p.index()].term.for_each_target_mut(|t| {
                if t.block == b {
                    while t.args.len() < idx {
                        t.args.push(val);
                    }
                    if t.args.len() == idx {
                        t.args.push(val);
                    }
                }
            });
        }
    }

    /// Finishes the function and adds it to the module.
    pub fn finish(self) -> FuncId {
        let (m, f) = self.into_parts();
        m.add_func(f)
    }

    /// Finishes the function without adding it (for functions declared ahead of their bodies).
    pub fn into_func(self) -> Func {
        self.into_parts().1
    }

    /// The module and the finished function, with edge arguments naming removed parameters
    /// replaced.
    fn into_parts(mut self) -> (&'m mut Module, Func) {
        let forward = std::mem::take(&mut self.forward);
        if !forward.is_empty() {
            for block in &mut self.f.blocks {
                block.term.for_each_target_mut(|t| {
                    for a in &mut t.args {
                        while let Some(&next) = forward.get(a) {
                            *a = next;
                        }
                    }
                });
            }
        }
        (self.m, self.f)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A chain of `n` two-predecessor joins: every variable read after it crosses all of them.
    fn chain(n: usize, single: bool) -> usize {
        let mut m = Module::new("t");
        let mut b = FuncBuilder::new(&mut m, "f", Vec::new(), Ty::INT);
        let vars: Vec<Var> = (0..n)
            .map(|k| {
                let v = if single {
                    b.declare_single(Ty::INT, Mode::Borrow)
                } else {
                    b.declare_var(Ty::INT, Mode::Borrow)
                };
                let c = b.iconst(k as i64);
                b.def_var(v, c);
                v
            })
            .collect();
        for _ in 0..n {
            let (then, join) = (b.new_block(), b.new_block());
            let c = b.bconst(true);
            b.br_if(c, then, &[], join, &[]);
            b.seal_block(then);
            b.switch_to(then);
            b.br(join, &[]);
            b.seal_block(join);
            b.switch_to(join);
        }
        for v in vars {
            b.use_var(v);
        }
        b.defs.len()
    }

    #[test]
    fn a_single_definition_variable_is_read_without_visiting_joins() {
        // Each reassignable variable leaves an entry per join; a single-definition one none.
        assert!(chain(20, false) >= 20 * 20);
        assert_eq!(chain(20, true), 0);
    }
}
