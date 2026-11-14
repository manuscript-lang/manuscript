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
//! * `type.set`, `list.set*` and `list.push` consume their collection operand
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
//! * `cleanup.push` types `(closer, value)` and yields a handle;
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

mod control;
mod data;
mod scalar;

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
    /// A type: fields in declaration order.
    Type(Rc<Vec<Val>>),
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
            (Val::Type(a), Val::Type(b)) | (Val::List(a), Val::List(b)) => a == b,
            (Val::Alt(t, a), Val::Alt(u, b)) => t == u && a == b,
            (Val::Opt(a), Val::Opt(b)) => a == b,
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

/// The operands and result register of the instruction being executed.
struct Operands<'a> {
    regs: &'a mut [Val],
    inst: &'a Inst,
}

impl Operands<'_> {
    fn int(&self, i: usize) -> R<i64> {
        match &self.regs[self.inst.args[i].index()] {
            Val::Int(x) => Ok(*x),
            v => Err(self.wrong_type("int", v)),
        }
    }

    fn float(&self, i: usize) -> R<f64> {
        match &self.regs[self.inst.args[i].index()] {
            Val::Float(x) => Ok(*x),
            v => Err(self.wrong_type("float", v)),
        }
    }

    fn boolean(&self, i: usize) -> R<bool> {
        match &self.regs[self.inst.args[i].index()] {
            Val::Bool(x) => Ok(*x),
            v => Err(self.wrong_type("bool", v)),
        }
    }

    fn wrong_type(&self, expected: &str, found: &Val) -> Raw {
        Raw::internal(format!(
            "{}: expected {expected}, found {found:?}",
            self.inst.op.info().name
        ))
    }

    /// Stores the instruction's result, if it has one.
    fn set(&mut self, v: Val) {
        if let Some(r) = self.inst.res {
            self.regs[r.index()] = v;
        }
    }
}

fn overflow() -> Raw {
    Raw::new(FaultKind::IntOverflow, "integer overflow")
}

fn div0() -> Raw {
    Raw::new(FaultKind::DivByZero, "division by zero")
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
        // The oracle frees at exit, so a leak shows as a drop count that differs.
        it.register("msrt_exit_frees", |_, _| Ok(Val::Bool(true)));
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
            TyKind::Type(r) => Val::Type(Rc::new(
                self.m.type_defs[r.index()]
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

    /// Executes one instruction by routing it to the function for its op family.
    fn step(&mut self, f: &Func, regs: &mut [Val], inst: &Inst) -> R<Flow> {
        match inst.op {
            Op::IConst
            | Op::FConst
            | Op::BConst
            | Op::UnitConst
            | Op::StrLit
            | Op::BytesLit
            | Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::INeg
            | Op::IAddOverflow
            | Op::IMulOverflow
            | Op::IntOverflowIf
            | Op::NarrowChk
            | Op::Conv
            | Op::INarrowOpt
            | Op::F32Round
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::INegChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::SDiv
            | Op::SRem
            | Op::And
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
            | Op::Not => self.constants_and_integers(f, regs, inst),
            Op::UICmp
            | Op::ICmp
            | Op::FCmp
            | Op::FAdd
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
            | Op::B2I
            | Op::Select => self.comparisons_and_floats(f, regs, inst),
            Op::TypeNew
            | Op::TypeGet
            | Op::TypeSet
            | Op::TypeFill
            | Op::AltNew
            | Op::AltView
            | Op::AltOwn
            | Op::AltPlain
            | Op::AltTag
            | Op::AltGet
            | Op::AltTake
            | Op::TypeRelease
            | Op::AltRelease
            | Op::AltUnbox => self.types_and_alternatives(f, regs, inst),
            Op::ListNew
            | Op::ListLit
            | Op::ListConst
            | Op::ListLen
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::ListTake
            | Op::ListRelease
            | Op::ListSet
            | Op::ListSetNn
            | Op::ListSetU
            | Op::ListFill
            | Op::ListPush
            | Op::ListDropLast => self.lists(f, regs, inst),
            Op::OptSome
            | Op::OptView
            | Op::OptNone
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptUnwrap
            | Op::OptUnbox
            | Op::OptAddr
            | Op::StrLen
            | Op::StrByte
            | Op::StrAsciiAt
            | Op::StrAsciiLen
            | Op::StrEqFast
            | Op::StrEqLit
            | Op::StrAscii
            | Op::BytesPush => self.optionals_and_strings(f, regs, inst),
            Op::ClosureNew
            | Op::ClosureCap
            | Op::ClosureCapAddr
            | Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceIs
            | Op::IfaceData => self.closures_and_interfaces(f, regs, inst),
            Op::Clone
            | Op::MoveOut
            | Op::Drop
            | Op::DropIf
            | Op::Slot
            | Op::PtrIsNull
            | Op::ListAddr
            | Op::ListAddrU
            | Op::PtrField
            | Op::Load
            | Op::Take
            | Op::Store
            | Op::Put => self.ownership_and_memory(f, regs, inst),
            Op::Call
            | Op::CallInd
            | Op::CallMethod
            | Op::CallRt
            | Op::FuncAddr
            | Op::TypeDesc
            | Op::Poll
            | Op::DepthEnter
            | Op::DepthLeave
            | Op::CleanupPush
            | Op::CleanupRun
            | Op::GlobalGet
            | Op::GlobalSet => self.calls_and_runtime(f, regs, inst),
            // Raw-phase markers do nothing at run time; `elaborate` replaces them with the cleanup.
            Op::ScopeBegin | Op::ScopeOwn | Op::ScopeEnd | Op::ScopeDisown | Op::ScopeMark => {
                Ok(Flow::Next)
            }
        }
    }

    /// Reads operands for an op that moving_params all of them.
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

/// Reads an operand: moves it out when the position moving_params a droppable
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
        .map(|(a, p)| arg(f, &mut fr.regs, *a, p.mode == Mode::Move, m))
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
