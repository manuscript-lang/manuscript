//! A reference interpreter for MIR: the semantic oracle for the optimizer and
//! the native backend.
//!
//! The interpreter has its own value model ([`Val`]) and does not depend on
//! the runtime crate. Aggregates are reference counted with copy-on-write, so
//! borrowing an operand is cheap and consuming ops mutate in place when the
//! operand is uniquely held, which matches the ownership rules the verifier
//! checks.
//!
//! # Semantics decided here
//!
//! * `rec.set`, `list.set*` and `list.push` consume their collection operand
//!   and yield the updated value. Negative indices of `list.get` and
//!   `list.set` count from the end; the `.nn` forms fault on negative indices.
//!   The `.u` forms are unchecked in the backend; here they fault like the
//!   checked ones so that bugs surface.
//! * `f2i.opt` yields `none` for NaN, infinities and values outside the `Int`
//!   range, otherwise the value truncated toward zero.
//! * `sdiv.chk` faults on zero (`DivByZero`) and on `MIN / -1`
//!   (`IntOverflow`); `srem.chk` faults on zero and yields 0 for `MIN % -1`.
//!   Unchecked `sdiv`/`srem` wrap and still fault on zero.
//! * `shl`/`sshr` use only the low six bits of the shift amount.
//! * `cleanup.push` records `(closer, value)` and yields a handle;
//!   `cleanup.run` pops and runs the innermost action. A fault runs the
//!   remaining actions LIFO; faults inside them are collected in
//!   [`Fault::cleanup_faults`].
//! * `Mode::Var` parameters cannot be represented by the IR yet (a call has a
//!   single result), so the interpreter treats them as owned parameters
//!   without copy-out.
//! * `call.rt` looks the symbol up in the host registry (see
//!   [`Interp::register`]); built-ins are `msrt_fault`, `msrt_print_int`,
//!   `msrt_print_float`, `msrt_print_bool` and `msrt_print_str`.

use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

/// Maximum nesting enforced by `depth.enter`.
pub const MAX_CALL_DEPTH: i64 = 200_000;
/// 2^63 as a float: `Int` values are the floats in `[-2^63, 2^63)`.
const I64_RANGE: f64 = 9_223_372_036_854_775_808.0;
/// Hard cap on live interpreter frames (independent of `depth.enter`).
const MAX_FRAMES: usize = 2_000_000;

/// An interpreter value.
#[derive(Clone, Debug, Default)]
pub enum Val {
    /// The unit value (also the state of a moved-out or undefined register).
    #[default]
    Unit,
    /// A boolean.
    Bool(bool),
    /// A signed 64-bit integer.
    Int(i64),
    /// A float.
    Float(f64),
    /// An immutable string.
    Str(Rc<str>),
    /// A raw word: type descriptor (the type id) or stack slot address.
    Ptr(u64),
    /// A record: fields in declaration order.
    Rec(Rc<Vec<Val>>),
    /// An alternative: case index and payload fields.
    Alt(u32, Rc<Vec<Val>>),
    /// A list.
    List(Rc<Vec<Val>>),
    /// An optional.
    Opt(Option<Rc<Val>>),
    /// A closure: code and captured values.
    Closure(FuncId, Rc<Vec<Val>>),
    /// An interface value: implementation table and erased data.
    Iface(VtableId, Rc<Val>),
    /// `Shared[T]`.
    Shared(Rc<Val>),
    /// A runtime object (maps, sets...) the interpreter does not model.
    Obj(Rc<str>, Rc<Vec<Val>>),
}

impl Val {
    /// A string value.
    pub fn str(s: &str) -> Val {
        Val::Str(Rc::from(s))
    }

    /// The integer inside, if any.
    pub fn as_int(&self) -> Option<i64> {
        match self {
            Val::Int(i) => Some(*i),
            _ => None,
        }
    }
}

impl PartialEq for Val {
    fn eq(&self, o: &Val) -> bool {
        match (self, o) {
            (Val::Unit, Val::Unit) => true,
            (Val::Bool(a), Val::Bool(b)) => a == b,
            (Val::Int(a), Val::Int(b)) => a == b,
            (Val::Float(a), Val::Float(b)) => a == b,
            (Val::Str(a), Val::Str(b)) => a == b,
            (Val::Ptr(a), Val::Ptr(b)) => a == b,
            (Val::Rec(a), Val::Rec(b)) | (Val::List(a), Val::List(b)) => a == b,
            (Val::Alt(t, a), Val::Alt(u, b)) => t == u && a == b,
            (Val::Opt(a), Val::Opt(b)) => a == b,
            (Val::Shared(a), Val::Shared(b)) => Rc::ptr_eq(a, b) || a == b,
            _ => false,
        }
    }
}

/// A program fault: the interpreter's analogue of the native fault protocol.
#[derive(Clone, Debug)]
pub struct Fault {
    /// What went wrong.
    pub kind: FaultKind,
    /// Human-readable message.
    pub message: String,
    /// Frames, innermost first, as `function (file:line)`.
    pub stack: Vec<String>,
    /// Messages of faults raised by cleanup actions while unwinding.
    pub cleanup_faults: Vec<String>,
    /// Whether the fault is the instruction budget running out.
    pub fuel_exhausted: bool,
}

impl std::fmt::Display for Fault {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)?;
        for s in &self.stack {
            write!(f, "\n  at {s}")?;
        }
        for c in &self.cleanup_faults {
            write!(f, "\ncleanup fault: {c}")?;
        }
        Ok(())
    }
}

impl std::error::Error for Fault {}

/// A host implementation of a runtime function: receives the captured
/// standard output and the arguments; `Err` raises a fault with that message.
pub type HostFn = Rc<dyn Fn(&mut String, &[Val]) -> Result<Val, String>>;

struct Raw {
    kind: FaultKind,
    message: String,
    fuel: bool,
}

impl Raw {
    fn new(kind: FaultKind, message: impl Into<String>) -> Raw {
        Raw {
            kind,
            message: message.into(),
            fuel: false,
        }
    }
    fn internal(message: impl Into<String>) -> Raw {
        Raw::new(
            FaultKind::Unreachable,
            format!("interpreter: {}", message.into()),
        )
    }
}

type R<T> = Result<T, Raw>;

struct Frame {
    func: FuncId,
    regs: Vec<Val>,
    block: usize,
    ip: usize,
    ret_dst: Option<Value>,
}

enum Flow {
    Next,
    Call { callee: FuncId, args: Vec<Val> },
}

/// The interpreter.
pub struct Interp<'m> {
    m: &'m Module,
    strings: Vec<Rc<str>>,
    globals: Vec<Val>,
    mem: Vec<Val>,
    cleanup: Vec<(FuncId, Val)>,
    depth: i64,
    steps: u64,
    fuel: Option<u64>,
    drops: u64,
    stdout: String,
    hosts: HashMap<String, HostFn>,
    cancel: Arc<AtomicBool>,
    unwinding: bool,
}

impl<'m> Interp<'m> {
    /// An interpreter for `m` with the built-in runtime functions registered.
    pub fn new(m: &'m Module) -> Interp<'m> {
        let mut it = Interp {
            m,
            strings: m.strings.iter().map(|s| Rc::from(s.as_str())).collect(),
            globals: Vec::new(),
            mem: Vec::new(),
            cleanup: Vec::new(),
            depth: 0,
            steps: 0,
            fuel: None,
            drops: 0,
            stdout: String::new(),
            hosts: HashMap::new(),
            cancel: Arc::new(AtomicBool::new(false)),
            unwinding: false,
        };
        it.globals = m.globals.iter().map(|g| it.default_val(g.ty)).collect();
        it.register("msrt_fault", |_, a| {
            Err(a.first().map(show).unwrap_or_default())
        });
        it.register("msrt_print_int", print);
        it.register("msrt_print_float", print);
        it.register("msrt_print_bool", print);
        it.register("msrt_print_str", print);
        it
    }

    /// Registers (or replaces) a host implementation of a runtime function.
    pub fn register(
        &mut self,
        name: &str,
        f: impl Fn(&mut String, &[Val]) -> Result<Val, String> + 'static,
    ) {
        self.hosts.insert(name.to_string(), Rc::new(f));
    }

    /// Limits the number of executed instructions and terminators.
    pub fn set_fuel(&mut self, fuel: Option<u64>) {
        self.fuel = fuel;
    }

    /// The flag `poll` checks; setting it makes the next poll fault.
    pub fn cancel_flag(&self) -> Arc<AtomicBool> {
        self.cancel.clone()
    }

    /// Everything the program printed.
    pub fn stdout(&self) -> &str {
        &self.stdout
    }

    /// Number of `drop` instructions executed with an effect.
    pub fn drops(&self) -> u64 {
        self.drops
    }

    /// Instructions executed so far.
    pub fn steps(&self) -> u64 {
        self.steps
    }

    /// Runs the module entry and returns its exit code.
    pub fn run_entry(&mut self) -> Result<i64, Fault> {
        let Some(e) = self.m.entry else {
            return Err(self.plain_fault("module has no entry"));
        };
        match self.call(e, Vec::new())? {
            Val::Int(i) => Ok(i),
            v => Err(self.plain_fault(&format!("entry returned {v:?}"))),
        }
    }

    /// Calls a function with already-built arguments.
    pub fn call(&mut self, f: FuncId, args: Vec<Val>) -> Result<Val, Fault> {
        self.unwinding = false;
        self.exec(f, args)
    }

    fn plain_fault(&self, msg: &str) -> Fault {
        Fault {
            kind: FaultKind::Unreachable,
            message: msg.into(),
            stack: Vec::new(),
            cleanup_faults: Vec::new(),
            fuel_exhausted: false,
        }
    }

    /// The zero value of a type (used for globals and stack slots).
    pub fn default_val(&self, t: Ty) -> Val {
        match self.m.types.kind(t) {
            TyKind::Bool => Val::Bool(false),
            TyKind::Int
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::UInt8
            | TyKind::UInt16
            | TyKind::UInt32
            | TyKind::UInt64 => Val::Int(0),
            TyKind::Float | TyKind::Float32 => Val::Float(0.0),
            TyKind::Str => Val::str(""),
            TyKind::Ptr => Val::Ptr(0),
            TyKind::List(_) => Val::List(Rc::new(Vec::new())),
            TyKind::Opt(_) => Val::Opt(None),
            TyKind::Rec(r) => Val::Rec(Rc::new(
                self.m.records[r.index()]
                    .fields
                    .iter()
                    .map(|f| self.default_val(f.1))
                    .collect(),
            )),
            _ => Val::Unit,
        }
    }

    fn enter(&self, func: FuncId, args: Vec<Val>, ret_dst: Option<Value>) -> R<Frame> {
        let f = &self.m.funcs[func.index()];
        if args.len() != f.params.len() {
            return Err(Raw::internal(format!(
                "{} takes {} arguments, found {}",
                f.name,
                f.params.len(),
                args.len()
            )));
        }
        let mut regs = vec![Val::Unit; f.values.len()];
        for (bp, a) in f.blocks[0].params.iter().zip(args) {
            regs[bp.value.index()] = a;
        }
        Ok(Frame {
            func,
            regs,
            block: 0,
            ip: 0,
            ret_dst,
        })
    }

    fn exec(&mut self, entry: FuncId, args: Vec<Val>) -> Result<Val, Fault> {
        let mut frames: Vec<Frame> = Vec::new();
        match self.enter(entry, args, None) {
            Ok(fr) => frames.push(fr),
            Err(raw) => return Err(self.finish(raw, &frames)),
        }
        let m = self.m;
        loop {
            if self.fuel.is_some_and(|fuel| self.steps >= fuel) {
                let mut raw = Raw::new(FaultKind::Cancelled, "instruction budget exhausted");
                raw.fuel = true;
                return Err(self.finish(raw, &frames));
            }
            self.steps += 1;
            let top = frames.len() - 1;
            let (func, block, ip) = (frames[top].func, frames[top].block, frames[top].ip);
            let f = &m.funcs[func.index()];
            let blk = &f.blocks[block];
            if ip < blk.insts.len() {
                frames[top].ip += 1;
                let flow = self.step(f, &mut frames[top].regs, &blk.insts[ip]);
                match flow {
                    Ok(Flow::Next) => {}
                    Ok(Flow::Call { callee, args }) => {
                        if frames.len() >= MAX_FRAMES {
                            let raw = Raw::new(FaultKind::CallDepth, depth_msg());
                            return Err(self.finish(raw, &frames));
                        }
                        let dst = blk.insts[ip].res;
                        match self.enter(callee, args, dst) {
                            Ok(fr) => frames.push(fr),
                            Err(raw) => return Err(self.finish(raw, &frames)),
                        }
                    }
                    Err(raw) => return Err(self.finish(raw, &frames)),
                }
                continue;
            }
            // Terminator.
            match &blk.term {
                Term::Ret(v) => {
                    let val = match v {
                        Some(v) => std::mem::take(&mut frames[top].regs[v.index()]),
                        None => Val::Unit,
                    };
                    let done = frames.pop().expect("frame");
                    match frames.last_mut() {
                        None => return Ok(val),
                        Some(caller) => {
                            if let Some(d) = done.ret_dst {
                                caller.regs[d.index()] = val;
                            }
                        }
                    }
                }
                Term::Fault(k) => {
                    let msg = fault_message(m, *k);
                    return Err(self.finish(Raw::new(*k, msg), &frames));
                }
                Term::Unreachable => {
                    let raw = Raw::new(FaultKind::Unreachable, "unreachable code reached");
                    return Err(self.finish(raw, &frames));
                }
                Term::Br(t) => jump(m, f, &mut frames[top], t),
                Term::CondBr { cond, then, els } => {
                    let c = matches!(frames[top].regs[cond.index()], Val::Bool(true));
                    jump(m, f, &mut frames[top], if c { then } else { els });
                }
                Term::Switch {
                    value,
                    cases,
                    default,
                } => {
                    let v = frames[top].regs[value.index()].as_int();
                    let t = cases
                        .iter()
                        .find(|(k, _)| Some(*k) == v)
                        .map(|(_, t)| t)
                        .unwrap_or(default);
                    jump(m, f, &mut frames[top], t);
                }
            }
        }
    }

    /// Builds the final fault, running pending cleanup actions.
    fn finish(&mut self, raw: Raw, frames: &[Frame]) -> Fault {
        let m = self.m;
        let stack: Vec<String> = frames
            .iter()
            .rev()
            .map(|fr| {
                let f = &m.funcs[fr.func.index()];
                let blk = &f.blocks[fr.block];
                let loc = if fr.ip > 0 && fr.ip <= blk.insts.len() {
                    blk.insts[fr.ip - 1].loc
                } else {
                    blk.term_loc
                };
                if loc.is_none() {
                    f.name.clone()
                } else {
                    let file = m
                        .files
                        .get(loc.file as usize)
                        .map(String::as_str)
                        .unwrap_or("?");
                    format!("{} ({}:{})", f.name, file, loc.line)
                }
            })
            .collect();
        let mut cleanup_faults = Vec::new();
        if !self.unwinding {
            self.unwinding = true;
            while let Some((closer, v)) = self.cleanup.pop() {
                if let Err(e) = self.exec(closer, vec![v]) {
                    cleanup_faults.push(e.message);
                }
            }
            self.unwinding = false;
        }
        self.depth = 0;
        Fault {
            kind: raw.kind,
            message: raw.message,
            stack,
            cleanup_faults,
            fuel_exhausted: raw.fuel,
        }
    }

    #[allow(clippy::too_many_lines)]
    fn step(&mut self, f: &Func, regs: &mut [Val], inst: &Inst) -> R<Flow> {
        let m = self.m;
        let a = &inst.args;
        macro_rules! int {
            ($i:expr) => {
                match &regs[a[$i].index()] {
                    Val::Int(x) => *x,
                    v => {
                        return Err(Raw::internal(format!(
                            "{}: expected int, found {v:?}",
                            inst.op.info().name
                        )))
                    }
                }
            };
        }
        macro_rules! flt {
            ($i:expr) => {
                match &regs[a[$i].index()] {
                    Val::Float(x) => *x,
                    v => {
                        return Err(Raw::internal(format!(
                            "{}: expected float, found {v:?}",
                            inst.op.info().name
                        )))
                    }
                }
            };
        }
        macro_rules! boolean {
            ($i:expr) => {
                match &regs[a[$i].index()] {
                    Val::Bool(x) => *x,
                    v => {
                        return Err(Raw::internal(format!(
                            "{}: expected bool, found {v:?}",
                            inst.op.info().name
                        )))
                    }
                }
            };
        }
        macro_rules! set {
            ($v:expr) => {{
                let v = $v;
                if let Some(r) = inst.res {
                    regs[r.index()] = v;
                }
            }};
        }
        let overflow = || Raw::new(FaultKind::IntOverflow, "integer overflow");
        let div0 = || Raw::new(FaultKind::DivByZero, "division by zero");
        match inst.op {
            Op::IConst => set!(Val::Int(imm_int(inst.imm))),
            Op::FConst => set!(Val::Float(inst.imm.float())),
            Op::BConst => set!(Val::Bool(matches!(inst.imm, Imm::Bool(true)))),
            Op::UnitConst => set!(Val::Unit),
            Op::StrLit => {
                let Imm::Str(s) = inst.imm else {
                    return Err(Raw::internal("str without literal"));
                };
                set!(Val::Str(self.strings[s.index()].clone()));
            }
            Op::IAdd => set!(Val::Int(int!(0).wrapping_add(int!(1)))),
            Op::ISub => set!(Val::Int(int!(0).wrapping_sub(int!(1)))),
            Op::IMul => set!(Val::Int(int!(0).wrapping_mul(int!(1)))),
            Op::INeg => set!(Val::Int(int!(0).wrapping_neg())),
            Op::IAddOverflow => set!(Val::Bool(int!(0).overflowing_add(int!(1)).1)),
            Op::IMulOverflow => set!(Val::Bool(int!(0).overflowing_mul(int!(1)).1)),
            Op::IntOverflowIf => {
                if boolean!(0) {
                    return Err(overflow());
                }
            }
            Op::NarrowChk => {
                let (lo, hi) = m
                    .types
                    .int_range(f.values[a[0].index()])
                    .unwrap_or((i64::MIN.into(), i64::MAX.into()));
                let v = int!(0);
                if !(lo..=hi).contains(&i128::from(v)) {
                    return Err(overflow());
                }
                set!(Val::Int(v));
            }
            Op::Conv => {
                let to32 = inst.res.is_some_and(|r| f.values[r.index()] == Ty::FLOAT32);
                match &regs[a[0].index()] {
                    Val::Float(x) if to32 => set!(Val::Float(*x as f32 as f64)),
                    v => set!(v.clone()),
                }
            }
            Op::INarrowOpt => {
                let v = int!(0);
                let inner = inst.res.and_then(|r| m.opt_inner(f.values[r.index()]));
                let (lo, hi) = inner.map_or((i64::MIN, i64::MAX), |i| {
                    m.types.narrow_range(f.values[a[0].index()], i)
                });
                let fits = (lo..=hi).contains(&v);
                set!(Val::Opt(fits.then(|| Rc::new(Val::Int(v)))));
            }
            Op::F32Round => set!(Val::Float(flt!(0) as f32 as f64)),
            Op::IAddChk => set!(Val::Int(int!(0).checked_add(int!(1)).ok_or_else(overflow)?)),
            Op::ISubChk => set!(Val::Int(int!(0).checked_sub(int!(1)).ok_or_else(overflow)?)),
            Op::IMulChk => set!(Val::Int(int!(0).checked_mul(int!(1)).ok_or_else(overflow)?)),
            Op::UAddChk | Op::USubChk | Op::UMulChk => {
                let (x, y) = (int!(0) as u64, int!(1) as u64);
                let r = match inst.op {
                    Op::UAddChk => x.checked_add(y),
                    Op::USubChk => x.checked_sub(y),
                    _ => x.checked_mul(y),
                };
                set!(Val::Int(r.ok_or_else(overflow)? as i64))
            }
            Op::INegChk => set!(Val::Int(int!(0).checked_neg().ok_or_else(overflow)?)),
            Op::SDivChk => {
                let (x, y) = (int!(0), int!(1));
                if y == 0 {
                    return Err(div0());
                }
                set!(Val::Int(x.checked_div(y).ok_or_else(overflow)?));
            }
            Op::SRemChk => {
                let (x, y) = (int!(0), int!(1));
                if y == 0 {
                    return Err(div0());
                }
                set!(Val::Int(x.wrapping_rem(y)));
            }
            Op::SDiv | Op::SRem => {
                let (x, y) = (int!(0), int!(1));
                if y == 0 {
                    return Err(div0());
                }
                set!(Val::Int(if inst.op == Op::SDiv {
                    x.wrapping_div(y)
                } else {
                    x.wrapping_rem(y)
                }));
            }
            Op::And | Op::Or | Op::Xor => {
                let r = match (&regs[a[0].index()], &regs[a[1].index()]) {
                    (Val::Int(x), Val::Int(y)) => Val::Int(match inst.op {
                        Op::And => x & y,
                        Op::Or => x | y,
                        _ => x ^ y,
                    }),
                    (Val::Bool(x), Val::Bool(y)) => Val::Bool(match inst.op {
                        Op::And => x & y,
                        Op::Or => x | y,
                        _ => x ^ y,
                    }),
                    _ => {
                        return Err(Raw::internal(
                            "bitwise operands must be both int or both bool",
                        ));
                    }
                };
                set!(r);
            }
            Op::Shl => set!(Val::Int(int!(0).wrapping_shl(int!(1) as u32))),
            Op::Sshr => set!(Val::Int(int!(0).wrapping_shr(int!(1) as u32))),
            Op::Not => set!(Val::Bool(!boolean!(0))),
            Op::UICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("uicmp without condition"));
                };
                set!(Val::Bool(cc.eval_uint(int!(0), int!(1))));
            }
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("icmp without condition"));
                };
                let word = |v: &Val| match v {
                    Val::Int(i) => Some(*i),
                    Val::Bool(b) => Some(*b as i64),
                    _ => None,
                };
                let (Some(x), Some(y)) = (word(&regs[a[0].index()]), word(&regs[a[1].index()]))
                else {
                    return Err(Raw::internal("icmp operands must be int or bool"));
                };
                set!(Val::Bool(cc.eval_int(x, y)));
            }
            Op::FCmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("fcmp without condition"));
                };
                set!(Val::Bool(cc.eval_float(flt!(0), flt!(1))));
            }
            Op::FAdd => set!(Val::Float(flt!(0) + flt!(1))),
            Op::FSub => set!(Val::Float(flt!(0) - flt!(1))),
            Op::FMul => set!(Val::Float(flt!(0) * flt!(1))),
            Op::FDiv => set!(Val::Float(flt!(0) / flt!(1))),
            Op::FNeg => set!(Val::Float(-flt!(0))),
            Op::FSqrt => set!(Val::Float(flt!(0).sqrt())),
            Op::FFloor => set!(Val::Float(flt!(0).floor())),
            Op::FCeil => set!(Val::Float(flt!(0).ceil())),
            Op::FTrunc => set!(Val::Float(flt!(0).trunc())),
            Op::FAbs => set!(Val::Float(flt!(0).abs())),
            Op::I2F => {
                let x = int!(0);
                let value = if inst.res.is_some_and(|r| f.ty(r) == Ty::FLOAT32) {
                    (x as f32) as f64
                } else {
                    x as f64
                };
                set!(Val::Float(value));
            }
            Op::F2IOpt => {
                let x = flt!(0);
                let ok = x.is_finite() && (-I64_RANGE..I64_RANGE).contains(&x);
                set!(Val::Opt(ok.then(|| Rc::new(Val::Int(x as i64)))));
            }
            Op::B2I => set!(Val::Int(boolean!(0) as i64)),
            Op::Select => {
                let pick = if boolean!(0) { 1 } else { 2 };
                set!(regs[a[pick].index()].clone());
            }
            Op::RecNew => set!(Val::Rec(Rc::new(self.take_args(f, regs, a)))),
            Op::RecGet => {
                let Imm::Field(_, i) = inst.imm else {
                    return Err(Raw::internal("rec.get without field"));
                };
                let Val::Rec(r) = &regs[a[0].index()] else {
                    return Err(Raw::internal("rec.get on a non-record"));
                };
                set!(r[i as usize].clone());
            }
            Op::RecSet | Op::RecFill => {
                let Imm::Field(_, i) = inst.imm else {
                    return Err(Raw::internal("rec.set without field"));
                };
                let v = arg(f, regs, a[1], true, m);
                let Val::Rec(mut r) = arg(f, regs, a[0], true, m) else {
                    return Err(Raw::internal("rec.set on a non-record"));
                };
                Rc::make_mut(&mut r)[i as usize] = v;
                set!(Val::Rec(r));
            }
            Op::AltNew => {
                let Imm::Case(_, c) = inst.imm else {
                    return Err(Raw::internal("alt.new without case"));
                };
                set!(Val::Alt(c, Rc::new(self.take_args(f, regs, a))));
            }
            Op::AltTag => {
                let Val::Alt(t, _) = &regs[a[0].index()] else {
                    return Err(Raw::internal("alt.tag on a non-alternative"));
                };
                set!(Val::Int(*t as i64));
            }
            Op::AltGet => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.get without field"));
                };
                let Val::Alt(t, p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("alt.get on a non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.get of case {c} on case {t}")));
                }
                set!(p[i as usize].clone());
            }
            Op::AltTake => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.take without field"));
                };
                let Val::Alt(t, p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("alt.take on a non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.take of case {c} on case {t}")));
                }
                set!(p[i as usize].clone());
            }
            Op::AltRelease => {
                arg(f, regs, a[0], true, m);
            }
            Op::AltUnbox => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.unbox without field"));
                };
                let Val::Alt(t, p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("alt.unbox on a non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.unbox of case {c} on case {t}")));
                }
                let field = p[i as usize].clone();
                arg(f, regs, a[0], true, m);
                set!(field);
            }
            Op::ListNew => {
                let cap = int!(0).clamp(0, 1 << 16) as usize;
                set!(Val::List(Rc::new(Vec::with_capacity(cap))));
            }
            Op::ListLit => set!(Val::List(Rc::new(self.take_args(f, regs, a)))),
            Op::ListLen => {
                let Val::List(l) = &regs[a[0].index()] else {
                    return Err(Raw::internal("list.len on a non-list"));
                };
                set!(Val::Int(l.len() as i64));
            }
            Op::ListGet | Op::ListGetNn | Op::ListGetU => {
                let i = int!(1);
                let Val::List(l) = &regs[a[0].index()] else {
                    return Err(Raw::internal("list.get on a non-list"));
                };
                let k = list_index(l.len(), i, inst.op == Op::ListGet)?;
                set!(l[k].clone());
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                let i = int!(1);
                let v = arg(f, regs, a[2], true, m);
                let Val::List(mut l) = arg(f, regs, a[0], true, m) else {
                    return Err(Raw::internal("list.set on a non-list"));
                };
                let k = list_index(l.len(), i, matches!(inst.op, Op::ListSet | Op::ListFill))?;
                Rc::make_mut(&mut l)[k] = v;
                set!(Val::List(l));
            }
            Op::ListPush => {
                let v = arg(f, regs, a[1], true, m);
                let Val::List(mut l) = arg(f, regs, a[0], true, m) else {
                    return Err(Raw::internal("list.push on a non-list"));
                };
                Rc::make_mut(&mut l).push(v);
                set!(Val::List(l));
            }
            Op::ListDropLast => {
                let Val::List(mut l) = arg(f, regs, a[0], true, m) else {
                    return Err(Raw::internal("list.droplast on a non-list"));
                };
                Rc::make_mut(&mut l).pop();
                set!(Val::List(l));
            }
            Op::OptSome => set!(Val::Opt(Some(Rc::new(arg(f, regs, a[0], true, m))))),
            Op::OptView => set!(Val::Opt(Some(Rc::new(arg(f, regs, a[0], false, m))))),
            Op::RefNew | Op::RefGet => set!(arg(f, regs, a[0], false, m)),
            Op::OptNone => set!(Val::Opt(None)),
            Op::OptIsSome => {
                let Val::Opt(o) = &regs[a[0].index()] else {
                    return Err(Raw::internal("opt.is_some on a non-optional"));
                };
                set!(Val::Bool(o.is_some()));
            }
            Op::OptGet | Op::OptUnwrap => {
                let Val::Opt(o) = &regs[a[0].index()] else {
                    return Err(Raw::internal("opt.get on a non-optional"));
                };
                match o {
                    Some(v) => set!((**v).clone()),
                    None if inst.op == Op::OptUnwrap => {
                        return Err(Raw::new(FaultKind::NoneUnwrap, "unwrap of none"));
                    }
                    None => return Err(Raw::internal("opt.get on none")),
                }
            }
            Op::OptUnbox => {
                let Val::Opt(Some(v)) = &regs[a[0].index()] else {
                    return Err(Raw::internal("opt.unbox of none"));
                };
                let payload = (**v).clone();
                arg(f, regs, a[0], true, m);
                set!(payload);
            }
            Op::StrLen => {
                let Val::Str(s) = &regs[a[0].index()] else {
                    return Err(Raw::internal("str.len on a non-string"));
                };
                set!(Val::Int(s.chars().count() as i64));
            }
            Op::StrByte => {
                let (Val::Str(s), Val::Int(i)) = (&regs[a[0].index()], &regs[a[1].index()]) else {
                    return Err(Raw::internal("str.byte on a non-string"));
                };
                set!(Val::Int(i64::from(s.as_bytes()[*i as usize])));
            }
            Op::StrAscii => {
                let Val::Int(b) = &regs[a[0].index()] else {
                    return Err(Raw::internal("str.ascii on a non-int"));
                };
                set!(Val::Str(((*b as u8) as char).to_string().into()));
            }
            Op::SharedNew => set!(Val::Shared(Rc::new(arg(f, regs, a[0], true, m)))),
            Op::SharedGet => {
                let Val::Shared(s) = &regs[a[0].index()] else {
                    return Err(Raw::internal("shared.get on a non-shared"));
                };
                set!((**s).clone());
            }
            Op::ClosureNew => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("closure.new without function"));
                };
                set!(Val::Closure(g, Rc::new(self.take_args(f, regs, a))));
            }
            Op::ClosureCap => {
                let Imm::Idx(i) = inst.imm else {
                    return Err(Raw::internal("closure.cap without index"));
                };
                let Val::Closure(_, c) = &regs[a[0].index()] else {
                    return Err(Raw::internal("closure.cap on a non-closure"));
                };
                set!(c[i as usize].clone());
            }
            Op::IfaceNew => {
                let Imm::Vtable(v) = inst.imm else {
                    return Err(Raw::internal("iface.new without vtable"));
                };
                set!(Val::Iface(v, Rc::new(arg(f, regs, a[0], true, m))));
            }
            Op::IfaceIs => {
                let (Imm::Vtable(want), Val::Iface(have, _)) = (inst.imm, &regs[a[0].index()])
                else {
                    return Err(Raw::internal("iface.is on a non-interface"));
                };
                set!(Val::Bool(*have == want));
            }
            Op::IfaceData => {
                let Val::Iface(_, d) = &regs[a[0].index()] else {
                    return Err(Raw::internal("iface.data on a non-interface"));
                };
                set!((**d).clone());
            }
            Op::Copy | Op::MoveOut => set!(regs[a[0].index()].clone()),
            Op::Drop => {
                self.drops += 1;
                arg(f, regs, a[0], true, m);
            }
            Op::DropIf => {
                if boolean!(0) {
                    self.drops += 1;
                    arg(f, regs, a[1], true, m);
                }
            }
            Op::Slot => {
                let Imm::Ty(t) = inst.imm else {
                    return Err(Raw::internal("slot without type"));
                };
                self.mem.push(self.default_val(t));
                set!(Val::Ptr(self.mem.len() as u64));
            }
            Op::PtrIsNull => {
                let Val::Ptr(p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("ptr.is_null of a non-pointer"));
                };
                set!(Val::Bool(*p == 0));
            }
            Op::ListAddr | Op::ListAddrU | Op::PtrField | Op::SharedAddr => {
                return Err(Raw::internal(
                    "interior pointers are not supported by the interpreter",
                ));
            }
            Op::Load | Op::Take => {
                let Val::Ptr(p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("load through a non-pointer"));
                };
                let cell = self
                    .mem
                    .get((*p as usize).wrapping_sub(1))
                    .ok_or_else(|| Raw::internal("load from an invalid address"))?;
                set!(cell.clone());
            }
            Op::Store | Op::Put => {
                let Val::Ptr(p) = &regs[a[0].index()] else {
                    return Err(Raw::internal("store through a non-pointer"));
                };
                let k = (*p as usize).wrapping_sub(1);
                let v = regs[a[1].index()].clone();
                *self
                    .mem
                    .get_mut(k)
                    .ok_or_else(|| Raw::internal("store to an invalid address"))? = v;
            }
            Op::Call => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("call without callee"));
                };
                let params = &m.funcs[g.index()].params;
                let args = a
                    .iter()
                    .zip(params)
                    .map(|(v, p)| arg(f, regs, *v, p.mode != Mode::Borrow, m))
                    .collect();
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallInd => {
                let Val::Closure(g, _) = regs[a[0].index()].clone() else {
                    return Err(Raw::internal("call.ind on a non-closure"));
                };
                let mut args = vec![regs[a[0].index()].clone()];
                args.extend(a[1..].iter().map(|v| arg(f, regs, *v, false, m)));
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallMethod => {
                let Imm::Method(_, k) = inst.imm else {
                    return Err(Raw::internal("call.method without method"));
                };
                let Val::Iface(vt, data) = regs[a[0].index()].clone() else {
                    return Err(Raw::internal("call.method on a non-interface"));
                };
                let g = m.vtables[vt.index()].methods[k as usize];
                let mut args = vec![(*data).clone()];
                args.extend(a[1..].iter().map(|v| arg(f, regs, *v, false, m)));
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallRt => {
                let Imm::Ext(e) = inst.imm else {
                    return Err(Raw::internal("call.rt without extern"));
                };
                let ext = &m.externs[e.index()];
                let args: Vec<Val> = a
                    .iter()
                    .zip(&ext.params)
                    .map(|(v, p)| arg(f, regs, *v, p.mode != Mode::Borrow, m))
                    .collect();
                let host = self.hosts.get(&ext.name).cloned().ok_or_else(|| {
                    Raw::internal(format!("unregistered runtime function {}", ext.name))
                })?;
                let r = host(&mut self.stdout, &args)
                    .map_err(|msg| Raw::new(FaultKind::Unreachable, msg))?;
                set!(r);
            }
            Op::FuncAddr => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("func.addr without function"));
                };
                set!(Val::Ptr(g.0 as u64));
            }
            Op::TypeDesc => {
                let Imm::Ty(t) = inst.imm else {
                    return Err(Raw::internal("typedesc without type"));
                };
                set!(Val::Ptr(t.0 as u64));
            }
            Op::Poll => {
                if self.cancel.load(Ordering::Relaxed) {
                    return Err(Raw::new(FaultKind::Cancelled, "cancelled"));
                }
            }
            Op::DepthEnter => {
                self.depth += 1;
                if self.depth > MAX_CALL_DEPTH {
                    return Err(Raw::new(FaultKind::CallDepth, depth_msg()));
                }
            }
            Op::DepthLeave => self.depth -= 1,
            Op::CleanupPush => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("cleanup.push without closer"));
                };
                self.cleanup.push((g, regs[a[0].index()].clone()));
                set!(Val::Int(self.cleanup.len() as i64));
            }
            Op::CleanupRun => {
                let Val::Int(h) = regs[a[0].index()].clone() else {
                    return Err(Raw::internal("cleanup.run needs a handle"));
                };
                while self.cleanup.len() as i64 >= h && h > 0 {
                    let Some((closer, v)) = self.cleanup.pop() else {
                        break;
                    };
                    self.exec(closer, vec![v])
                        .map_err(|e| Raw::new(e.kind, e.message))?;
                }
            }
            Op::GlobalGet => {
                let Imm::Global(g) = inst.imm else {
                    return Err(Raw::internal("global.get without global"));
                };
                set!(self.globals[g.index()].clone());
            }
            Op::GlobalSet => {
                let Imm::Global(g) = inst.imm else {
                    return Err(Raw::internal("global.set without global"));
                };
                self.globals[g.index()] = arg(f, regs, a[0], true, m);
            }
        }
        Ok(Flow::Next)
    }

    /// Reads operands for an op that consumes all of them.
    fn take_args(&self, f: &Func, regs: &mut [Val], args: &[Value]) -> Vec<Val> {
        args.iter()
            .map(|v| arg(f, regs, *v, true, self.m))
            .collect()
    }
}

/// Moves `v` out of its register.
fn take(regs: &mut [Val], v: Value) -> Val {
    std::mem::take(&mut regs[v.index()])
}

/// Reads an operand: moves it out when the position consumes a droppable
/// value, so that unique owners keep mutating in place; clones otherwise.
fn arg(f: &Func, regs: &mut [Val], v: Value, own: bool, m: &Module) -> Val {
    if own && m.needs_drop(f.ty(v)) {
        take(regs, v)
    } else {
        regs[v.index()].clone()
    }
}

fn jump(m: &Module, f: &Func, fr: &mut Frame, t: &Target) {
    let dest = &f.blocks[t.block.index()];
    let vals: Vec<Val> = t
        .args
        .iter()
        .zip(&dest.params)
        .map(|(a, p)| arg(f, &mut fr.regs, *a, p.mode == Mode::Own, m))
        .collect();
    for (p, v) in dest.params.iter().zip(vals) {
        fr.regs[p.value.index()] = v;
    }
    fr.block = t.block.index();
    fr.ip = 0;
}

fn imm_int(i: Imm) -> i64 {
    match i {
        Imm::Int(v) => v,
        _ => 0,
    }
}

fn list_index(len: usize, i: i64, from_end: bool) -> R<usize> {
    let k = if i < 0 && from_end { i + len as i64 } else { i };
    if k < 0 || k as usize >= len {
        return Err(Raw::new(
            FaultKind::IndexOutOfRange,
            format!("index {i} out of range for length {len}"),
        ));
    }
    Ok(k as usize)
}

fn depth_msg() -> String {
    format!(
        "call depth limit exceeded ({MAX_CALL_DEPTH} nested calls); check the recursion for a missing base case, or iterate instead"
    )
}

fn fault_message(m: &Module, k: FaultKind) -> String {
    match k {
        FaultKind::IntOverflow => "integer overflow".into(),
        FaultKind::DivByZero => "division by zero".into(),
        FaultKind::IndexOutOfRange => "index out of range".into(),
        FaultKind::NoneUnwrap => "unwrap of none".into(),
        FaultKind::Cancelled => "cancelled".into(),
        FaultKind::CallDepth => depth_msg(),
        FaultKind::Unreachable => "unreachable code reached".into(),
        FaultKind::Message(s) => m.strings[s.index()].clone(),
    }
}

fn show(v: &Val) -> String {
    match v {
        Val::Unit => "()".into(),
        Val::Bool(b) => b.to_string(),
        Val::Int(i) => i.to_string(),
        Val::Float(x) => format!("{x}"),
        Val::Str(s) => s.to_string(),
        other => format!("{other:?}"),
    }
}

fn print(out: &mut String, a: &[Val]) -> Result<Val, String> {
    out.push_str(&a.first().map(show).unwrap_or_default());
    out.push('\n');
    Ok(Val::Unit)
}
