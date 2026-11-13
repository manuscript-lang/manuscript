//! The MIR data structures: module, functions, blocks, instructions.
//!
//! # Model
//!
//! A function is a CFG of basic blocks in SSA form. Control-flow joins use
//! block parameters instead of phi nodes. Block 0 is the entry; its parameters
//! are the function parameters.
//!
//! Every SSA value has one monomorphic [`Ty`]. MIR follows the value-semantics
//! memory model: types, lists, optionals and the like are *values*, flattened
//! into scalar leaves by the backend (see [`crate::layout`]), not heap objects
//! with identity. A value whose type [needs a drop](Module::needs_drop) (lists,
//! maps, strings, boxed alternatives, types containing them) is
//! either **owned** (it must be consumed exactly once: moved into a consuming
//! position or `drop`ped) or **borrowed** (a read-only view the producer keeps
//! alive). Ownership is determined by the defining instruction (see
//! [`Module::result_modes`]) or by the declared [`Mode`] of a parameter, and is
//! checked by the verifier with a move/maybe-moved dataflow, so conditional
//! moves are expressed with `drop.if` flags the way drop elaboration emits them.
//!
//! Mutation is threaded through SSA: an operation that changes an owned value
//! moving_params it and returns the updated value (`list.push`, `list.set`,
//! `type.set`), and a `var` parameter is copy-in/copy-out: the callee returns
//! its final value after its result.

use crate::types::{
    AltDef, AltId, IfaceDef, IfaceId, Ty, TyKind, TyTable, TypeDef, TypeId, id_type,
};
use std::collections::HashMap;
use std::fmt;

id_type!(
    /// An SSA value within one function.
    Value
);
id_type!(
    /// A basic block within one function.
    Block
);
id_type!(
    /// A function in [`Module::funcs`].
    FuncId
);
id_type!(
    /// A runtime function declaration in [`Module::externs`].
    ExtId
);
id_type!(
    /// A string literal in [`Module::strings`].
    StrId
);
id_type!(
    /// A module-level variable in [`Module::globals`].
    GlobalId
);
id_type!(
    /// An interface implementation table in [`Module::vtables`].
    VtableId
);

/// A source position. `file` indexes [`Module::files`]; lines and columns are 1-based.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct Loc {
    /// Index into [`Module::files`], or `u32::MAX` when unknown.
    pub file: u32,
    /// 1-based line, 0 when unknown.
    pub line: u32,
    /// 1-based column, 0 when unknown.
    pub col: u32,
    /// Inlining scope: 0 when the position belongs to the function itself, else
    /// one plus an index into [`Func::scopes`].
    pub scope: u32,
}

/// A callee body inlined into a function: fault traces and profiles show it as its
/// own frame, called from `call_line` of the enclosing scope.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Scope {
    /// Display name of the inlined function.
    pub name: String,
    /// Index into [`Module::files`] of the inlined function's file, `u32::MAX` when unknown.
    pub file: u32,
    /// Enclosing scope (0 = the function itself).
    pub parent: u32,
    /// Line of the inlined call in the enclosing scope.
    pub call_line: u32,
}

impl Loc {
    /// The unknown location.
    pub const NONE: Loc = Loc {
        file: u32::MAX,
        line: 0,
        col: 0,
        scope: 0,
    };

    /// A known location.
    pub fn new(file: u32, line: u32, col: u32) -> Loc {
        Loc {
            file,
            line,
            col,
            scope: 0,
        }
    }

    /// Whether the location is unknown.
    pub fn is_none(self) -> bool {
        self.file == u32::MAX
    }
}

/// How a parameter or block parameter holds its value.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Mode {
    /// A borrow; the caller keeps ownership.
    Borrow,
    /// Ownership moves in; the callee must move the value on or drop it.
    Move,
    /// A `var` parameter: ownership moves in and the final value is returned
    /// after the function's result (move-in/move-out). Only on function parameters.
    Var,
}

/// A function parameter.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Param {
    /// Parameter type.
    pub ty: Ty,
    /// How the value is passed. `Borrow` and `Own` coincide for types that need no drop.
    pub mode: Mode,
}

/// A block parameter: the SSA value it defines and whether it owns the incoming value.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct BlockParam {
    /// The defined value.
    pub value: Value,
    /// Ownership of the incoming value (`Borrow` or `Own`).
    pub mode: Mode,
}

/// Comparison condition. Integer comparisons are signed; float comparisons are
/// ordered (any comparison with NaN is false except `Ne`).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Cc {
    /// Equal.
    Eq,
    /// Not equal.
    Ne,
    /// Less than.
    Lt,
    /// Less than or equal.
    Le,
    /// Greater than.
    Gt,
    /// Greater than or equal.
    Ge,
}

impl Cc {
    /// The condition with swapped operands.
    pub fn swapped(self) -> Cc {
        match self {
            Cc::Eq => Cc::Eq,
            Cc::Ne => Cc::Ne,
            Cc::Lt => Cc::Gt,
            Cc::Le => Cc::Ge,
            Cc::Gt => Cc::Lt,
            Cc::Ge => Cc::Le,
        }
    }

    /// The logical negation (integers only; not valid for NaN-aware floats).
    pub fn negated(self) -> Cc {
        match self {
            Cc::Eq => Cc::Ne,
            Cc::Ne => Cc::Eq,
            Cc::Lt => Cc::Ge,
            Cc::Le => Cc::Gt,
            Cc::Gt => Cc::Le,
            Cc::Ge => Cc::Lt,
        }
    }

    /// Mnemonic suffix.
    pub fn name(self) -> &'static str {
        match self {
            Cc::Eq => "eq",
            Cc::Ne => "ne",
            Cc::Lt => "lt",
            Cc::Le => "le",
            Cc::Gt => "gt",
            Cc::Ge => "ge",
        }
    }

    /// Parses a mnemonic suffix.
    pub fn from_name(s: &str) -> Option<Cc> {
        Some(match s {
            "eq" => Cc::Eq,
            "ne" => Cc::Ne,
            "lt" => Cc::Lt,
            "le" => Cc::Le,
            "gt" => Cc::Gt,
            "ge" => Cc::Ge,
            _ => return None,
        })
    }

    /// Evaluates the condition on two integers read as unsigned.
    pub fn eval_uint(self, a: i64, b: i64) -> bool {
        self.eval_int((a as u64 ^ (1 << 63)) as i64, (b as u64 ^ (1 << 63)) as i64)
    }

    /// Evaluates the condition on two signed integers.
    pub fn eval_int(self, a: i64, b: i64) -> bool {
        match self {
            Cc::Eq => a == b,
            Cc::Ne => a != b,
            Cc::Lt => a < b,
            Cc::Le => a <= b,
            Cc::Gt => a > b,
            Cc::Ge => a >= b,
        }
    }

    /// Evaluates the condition on two floats with IEEE semantics.
    pub fn eval_float(self, a: f64, b: f64) -> bool {
        match self {
            Cc::Eq => a == b,
            Cc::Ne => a != b,
            Cc::Lt => a < b,
            Cc::Le => a <= b,
            Cc::Gt => a > b,
            Cc::Ge => a >= b,
        }
    }
}

/// The reason a program faults. Checked operations carry an implicit kind.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum FaultKind {
    /// Checked `Int` arithmetic overflowed.
    IntOverflow,
    /// Integer division or remainder by zero.
    DivByZero,
    /// List index out of range.
    IndexOutOfRange,
    /// `Optional` payload read from `none`.
    NoneUnwrap,
    /// Cancellation was requested.
    Cancelled,
    /// The call depth limit was exceeded.
    CallDepth,
    /// Control reached code the checker proved dead.
    Unreachable,
    /// An explicit fault with a message literal.
    Message(StrId),
}

/// An operation code. See [`Op::info`] for the operand and effect table, and
/// the module documentation of [`crate::verify`] for typing rules.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
#[rustfmt::skip]
pub enum Op {
    // Constants.
    IConst, FConst, BConst, UnitConst, StrLit, BytesLit,
    // Integer arithmetic: wrapping, overflow-checked, and unchecked division.
    IAdd, ISub, IMul, INeg, IAddOverflow, IMulOverflow, IntOverflowIf, IAddChk, ISubChk, IMulChk, UAddChk, USubChk, UMulChk, INegChk, SDivChk, SRemChk, SDiv, SRem,
    // Sized integers: fault unless the value fits its type. `Float32`: round to binary32.
    NarrowChk, F32Round,
    // Conversions: `Conv` retypes a number to another type of its kind (rounding to binary32 for `Float32`); `INarrowOpt` yields some(value) when an int fits the smaller type.
    Conv, INarrowOpt,
    // Bit operations and booleans (`And`/`Or`/`Xor` accept Int or Bool).
    And, Or, Xor, Shl, Sshr, Ushr, Rotl, Rotr, Clz, Ctz, Popcnt, Not,
    // Comparisons.
    ICmp, UICmp, FCmp,
    // Float arithmetic and conversions.
    FAdd, FSub, FMul, FDiv, FNeg, FSqrt, FAbs, FFloor, FCeil, FTrunc, I2F, F2IOpt, B2I, Select,
    // Types and alternatives.
    TypeNew, TypeGet, TypeSet, TypeFill, AltNew, AltView, AltPlain, AltOwn, AltTag, AltGet, AltUnbox, AltTake, AltRelease, TypeRelease,
    // Lists.
    ListNew, ListLit, ListConst, ListLen, ListGet, ListGetNn, ListGetU, ListTake, ListSet, ListSetNn, ListSetU, ListFill, ListPush, ListDropLast, ListRelease,
    // Optionals.
    OptSome, OptView, OptNone, OptIsSome, OptGet, OptUnwrap, OptUnbox, OptAddr,
    // Strings.
    StrLen, StrByte, StrAscii, StrAsciiAt,
    // Closures and interface views.
    ClosureNew, ClosureCap, ClosureCapAddr, IfaceNew, IfaceBorrow, IfaceView, IfaceData, IfaceIs,
    // Ownership.
    Clone, Drop, DropIf, MoveOut,
    // Raw memory: stack slots, interior pointers into lists and types.
    Slot, Load, Take, Store, Put, ListAddr, ListAddrU, PtrField, PtrIsNull,
    // Calls.
    Call, CallInd, CallRt, CallMethod,
    // Runtime services.
    TypeDesc, FuncAddr, Poll, DepthEnter, DepthLeave, CleanupPush, CleanupRun, GlobalGet, GlobalSet,
    // Raw-phase scope markers, consumed by `elaborate`.
    ScopeBegin, ScopeOwn, ScopeEnd, ScopeDisown, ScopeMark,
}

/// How an instruction touches machine state; used by optimization passes.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct Effects {
    /// Reads memory.
    pub reads: bool,
    /// Writes memory.
    pub writes: bool,
    /// May fault.
    pub faults: bool,
    /// Drops or clones an owned value (runs destructors, allocates).
    pub ownership: bool,
    /// Allocates.
    pub alloc: bool,
    /// Has an unknown or externally visible effect (calls, cleanup stack, globals, polls).
    pub io: bool,
}

impl Effects {
    /// No effect at all: freely removable, movable and duplicable.
    pub fn is_pure(&self) -> bool {
        *self == Effects::default()
    }

    /// May the instruction be deleted when its result is unused?
    pub fn removable(&self) -> bool {
        !self.writes && !self.faults && !self.io && !self.ownership
    }
}

macro_rules! effects {
    () => { Effects { reads: false, writes: false, faults: false, ownership: false, alloc: false, io: false } };
    ($($f:ident),+) => { Effects { $($f: true,)+ ..effects!() } };
}

/// Immediate operand kinds, used by the text format.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ImmKind {
    /// No immediate.
    None,
    /// `i64`.
    Int,
    /// `f64`.
    Float,
    /// `true` or `false`.
    Bool,
    /// String literal id.
    Str,
    /// Function.
    Func,
    /// Runtime function.
    Ext,
    /// Type.
    Ty,
    /// Type id.
    Type,
    /// Type id and field index.
    Field,
    /// Alternative id and case index.
    Case,
    /// Alternative id, case and field index.
    AltField,
    /// Alternative id, case and the set of payload fields that were moved out.
    AltMask,
    /// Type id and the set of fields that were moved out.
    TypeMask,
    /// Vtable.
    Vtable,
    /// Global.
    Global,
    /// Interface and method index.
    Method,
    /// Comparison condition.
    Cc,
    /// Unsigned index.
    Idx,
    /// A scope marker: the scope, and a second number whose meaning the op sets.
    Scope,
}

/// Static facts about an [`Op`].
#[derive(Clone, Copy, Debug)]
pub struct OpInfo {
    /// Text-format mnemonic.
    pub name: &'static str,
    /// Immediate operand kind.
    pub imm: ImmKind,
    /// Whether the instruction defines a value (calls define one value per
    /// non-unit result plus one per `var` parameter and are checked separately).
    pub has_result: bool,
    /// Effects of the instruction, ignoring the callee for calls.
    pub effects: Effects,
}

/// An immediate operand.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Imm {
    /// None.
    None,
    /// An integer.
    Int(i64),
    /// A float, as raw bits so instructions stay `Eq`.
    Float(u64),
    /// A boolean.
    Bool(bool),
    /// A string literal.
    Str(StrId),
    /// A function.
    Func(FuncId),
    /// A runtime function.
    Ext(ExtId),
    /// A type.
    Ty(Ty),
    /// A type.
    Type(TypeId),
    /// A type field.
    Field(TypeId, u32),
    /// An alternative case.
    Case(AltId, u32),
    /// An alternative case field.
    AltField(AltId, u32, u32),
    /// Alternative id, case and a bit set of payload fields moved out by `alt.take`.
    AltMask(AltId, u32, u32),
    /// Type id and a bit set of fields moved out before `type.release`.
    TypeMask(TypeId, u32),
    /// A vtable.
    Vtable(VtableId),
    /// A global.
    Global(GlobalId),
    /// An interface method.
    Method(IfaceId, u32),
    /// A comparison.
    Cc(Cc),
    /// An index.
    Idx(u32),
    /// A scope marker's two numbers.
    Scope(u32, u32),
}

impl Imm {
    /// The float value of a [`Imm::Float`].
    pub fn float(self) -> f64 {
        match self {
            Imm::Float(b) => f64::from_bits(b),
            _ => 0.0,
        }
    }
}

/// An instruction.
#[derive(Clone, PartialEq, Debug)]
pub struct Inst {
    /// The operation.
    pub op: Op,
    /// Operands.
    pub args: Vec<Value>,
    /// Immediate operand.
    pub imm: Imm,
    /// The defined value, for ops that have a result.
    pub res: Option<Value>,
    /// Source position.
    pub loc: Loc,
}

/// A branch target with the block arguments passed to its parameters.
#[derive(Clone, PartialEq, Debug)]
pub struct Target {
    /// Destination block.
    pub block: Block,
    /// One argument per destination parameter.
    pub args: Vec<Value>,
}

impl Target {
    /// A target without arguments.
    pub fn to(block: Block) -> Target {
        Target {
            block,
            args: Vec::new(),
        }
    }
}

/// A block terminator.
#[derive(Clone, PartialEq, Debug)]
pub enum Term {
    /// Unconditional branch.
    Br(Target),
    /// Branch on a boolean.
    CondBr {
        /// The condition.
        cond: Value,
        /// Taken when true.
        then: Target,
        /// Taken when false.
        els: Target,
    },
    /// Multi-way branch on an integer.
    Switch {
        /// The scrutinee.
        value: Value,
        /// `(constant, target)` pairs.
        cases: Vec<(i64, Target)>,
        /// Taken when no case matches.
        default: Target,
    },
    /// Returns an owned value (or nothing for `Unit` functions).
    Ret(Option<Value>),
    /// Aborts the program with a fault, running scope cleanups first.
    Fault(FaultKind),
    /// Control never reaches here; undefined behavior if it does.
    Unreachable,
}

impl Term {
    /// Visits every successor target.
    pub fn for_each_target(&self, mut f: impl FnMut(&Target)) {
        match self {
            Term::Br(t) => f(t),
            Term::CondBr { then, els, .. } => {
                f(then);
                f(els);
            }
            Term::Switch { cases, default, .. } => {
                cases.iter().for_each(|(_, t)| f(t));
                f(default);
            }
            Term::Ret(_) | Term::Fault(_) | Term::Unreachable => {}
        }
    }

    /// Visits every successor target mutably.
    pub fn for_each_target_mut(&mut self, mut f: impl FnMut(&mut Target)) {
        match self {
            Term::Br(t) => f(t),
            Term::CondBr { then, els, .. } => {
                f(then);
                f(els);
            }
            Term::Switch { cases, default, .. } => {
                cases.iter_mut().for_each(|(_, t)| f(t));
                f(default);
            }
            Term::Ret(_) | Term::Fault(_) | Term::Unreachable => {}
        }
    }

    /// The successor blocks, in order, with duplicates.
    pub fn successors(&self) -> Vec<Block> {
        let mut out = Vec::new();
        self.for_each_target(|t| out.push(t.block));
        out
    }

    /// Visits every value operand (condition, scrutinee, return value, block arguments).
    pub fn for_each_use(&self, mut f: impl FnMut(Value)) {
        match self {
            Term::CondBr { cond, .. } => f(*cond),
            Term::Switch { value, .. } => f(*value),
            Term::Ret(Some(v)) => f(*v),
            _ => {}
        }
        self.for_each_target(|t| t.args.iter().for_each(|a| f(*a)));
    }

    /// Visits every value operand mutably.
    pub fn for_each_use_mut(&mut self, mut f: impl FnMut(&mut Value)) {
        match self {
            Term::CondBr { cond, .. } => f(cond),
            Term::Switch { value, .. } => f(value),
            Term::Ret(Some(v)) => f(v),
            _ => {}
        }
        self.for_each_target_mut(|t| t.args.iter_mut().for_each(&mut f));
    }
}

/// A basic block.
#[derive(Clone, Debug)]
pub struct BlockData {
    /// Parameters defined on entry.
    pub params: Vec<BlockParam>,
    /// Straight-line instructions.
    pub insts: Vec<Inst>,
    /// The terminator.
    pub term: Term,
    /// Source position of the terminator.
    pub term_loc: Loc,
}

impl BlockData {
    /// An empty block ending in `unreachable`.
    pub fn new() -> BlockData {
        BlockData {
            params: Vec::new(),
            insts: Vec::new(),
            term: Term::Unreachable,
            term_loc: Loc::NONE,
        }
    }
}

impl Default for BlockData {
    fn default() -> Self {
        Self::new()
    }
}

/// Symbol visibility of a function.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Linkage {
    /// Visible to the linker (the entry point, exports).
    Export,
    /// Internal to the object.
    Internal,
}

/// An inlining directive.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum InlineHint {
    /// Decided by the optimizer's size heuristic.
    Auto,
    /// Inline whenever possible.
    Always,
    /// Never inline.
    Never,
}

/// What a function is for.
#[derive(Clone, PartialEq, Debug)]
pub enum FuncKind {
    /// An ordinary function with the declared per-parameter modes.
    Normal,
    /// The code of a closure. Parameter 0 is the closure object itself
    /// (type [`Ty::PTR`], borrowed); `captures` are the types of the captured
    /// values stored in the closure, read with `closure.cap`. All parameters
    /// are borrowed.
    Closure {
        /// Types of captured values in closure-object layout order.
        captures: Vec<Ty>,
    },
    /// A method implementation reachable through a vtable. All parameters are
    /// borrowed; parameter 0 is the erased receiver ([`Ty::PTR`]).
    Method,
}

/// Whether a function is a comparator thunk of a runtime sort.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum SortThunk {
    /// An ordinary function.
    #[default]
    None,
    /// `fn(comparator, ptr, ptr) -> int`: calls the user's closure for each comparison.
    Generic,
    /// A generic thunk specialized to one closure by `inline`; parameter 0 is the raw
    /// environment pointer. The sort pass reads its comparison.
    Specialized,
}

/// A function.
#[derive(Clone, Debug)]
pub struct Func {
    /// Symbol and display name.
    pub name: String,
    /// Parameters; `blocks[0].params` define their values.
    pub params: Vec<Param>,
    /// Result type. Results are owned unless `ret_borrowed`.
    pub ret: Ty,
    /// The result is a reference into one or more parameters (a borrow-returning function): the caller
    /// holds it as a borrow for as long as those arguments live and never releases it. The
    /// verifier rejects an owned value returned from such a function.
    pub ret_borrowed: bool,
    /// The result is an owned interface value (or holds one) whose payload is borrowed from the
    /// arguments (a view returner, `iface.borrow`): the caller drops it, which frees only the box,
    /// and holds the arguments for as long as it lives.
    pub ret_view: bool,
    /// Visibility.
    pub linkage: Linkage,
    /// Role of the function.
    pub kind: FuncKind,
    /// Inlining directive.
    pub inline: InlineHint,
    /// Whether the function is a sort comparator thunk.
    pub sort: SortThunk,
    /// Declaration position.
    pub loc: Loc,
    /// Type of every value, indexed by [`Value`].
    pub values: Vec<Ty>,
    /// Blocks, indexed by [`Block`]; block 0 is the entry.
    pub blocks: Vec<BlockData>,
    /// Inlined-callee scopes referenced by [`Loc::scope`].
    pub scopes: Vec<Scope>,
    /// Results of unchecked `iadd`/`isub`/`imul`/`ineg`/`shl` that the range pass proved cannot wrap:
    /// the value is the exact mathematical result, so later analysis treats the operation like its
    /// checked twin instead of as a wrapping one. Values are never reused, so an entry stays true
    /// as the function is rewritten; code copied into another function does not carry it.
    pub exact: std::collections::HashSet<Value>,
    /// Indexes of pointer parameters that no other parameter or memory the function reaches
    /// overlaps while it runs (`var` parameters, which the checker keeps exclusive).
    pub noalias: Vec<u32>,
    /// A closure function whose environment points into its maker's frame (a borrowed capture
    /// or a shared variable): the closure may be called, copied and dropped, but never stored
    /// or returned, and the verifier rejects code that does.
    pub scoped: bool,
    /// A function that starts a promise from the closures it is given: it keeps them past its call, which
    /// is sound because the checker holds what they borrow until the promise is dropped. Closures built
    /// inside such a function carry the flag too, so inlining it keeps them valid in the caller.
    pub keeps_scoped: bool,
    /// A cleanup closer that acts only while a cancellation or fault unwinds a guarded task
    /// (see `unwind`). Registering it is skipped when no guard is open, where it would do nothing.
    pub unwind_only: bool,
    /// A generated sort helper whose lists hold bitwise copies of another list's slots and own
    /// nothing: an unwind frees their buffers and never drops their elements (see `unwind`).
    pub raw_scratch: bool,
    /// A closure function whose environment owns resources: the capture index and the function
    /// that closes it (taking the captured value by borrow), run when the closure is dropped.
    pub capture_closers: Vec<(u32, FuncId)>,
    /// A cleanup thunk that takes the address of a value of this type and closes it in place:
    /// the value is still there after the close, for the unwinding that registered it to drop.
    pub slot_close: Option<Ty>,
    /// On a `slot_close` thunk whose close can fail: the function that runs the same close and
    /// returns its `Result`, for `elaborate` to propagate (consumed there).
    pub slot_result: Option<FuncId>,
    /// On a function with fallible closing owners: how an error from a scope-end close becomes
    /// the function's return value, `(plain, pending)`: `fn(move close error) -> ret` and
    /// `fn(move close error, move pending return) -> ret`, the latter keeping an error the
    /// function was already returning (consumed by `elaborate`).
    pub close_exit: Option<(FuncId, FuncId)>,
}

impl Func {
    /// A function with an entry block whose parameters mirror `params`.
    pub fn new(name: &str, params: Vec<Param>, ret: Ty) -> Func {
        let mut f = Func {
            name: name.to_string(),
            params: params.clone(),
            ret,
            ret_borrowed: false,
            ret_view: false,
            linkage: Linkage::Internal,
            kind: FuncKind::Normal,
            inline: InlineHint::Auto,
            sort: SortThunk::None,
            loc: Loc::NONE,
            values: Vec::new(),
            blocks: vec![BlockData::new()],
            scopes: Vec::new(),
            exact: Default::default(),
            noalias: Vec::new(),
            scoped: false,
            keeps_scoped: false,
            unwind_only: false,
            raw_scratch: false,
            capture_closers: Vec::new(),
            slot_close: None,
            slot_result: None,
            close_exit: None,
        };
        for p in params {
            let v = f.new_value(p.ty);
            f.blocks[0].params.push(BlockParam {
                value: v,
                mode: p.mode,
            });
        }
        f
    }

    /// Allocates a fresh value of type `ty`.
    pub fn new_value(&mut self, ty: Ty) -> Value {
        self.values.push(ty);
        Value(self.values.len() as u32 - 1)
    }

    /// Appends an empty block.
    pub fn new_block(&mut self) -> Block {
        self.blocks.push(BlockData::new());
        Block(self.blocks.len() as u32 - 1)
    }

    /// The type of `v`.
    pub fn ty(&self, v: Value) -> Ty {
        self.values[v.index()]
    }

    /// The entry block's parameter values.
    pub fn param_values(&self) -> Vec<Value> {
        self.blocks[0].params.iter().map(|p| p.value).collect()
    }

    /// Total instruction count (excluding terminators).
    pub fn inst_count(&self) -> usize {
        self.blocks.iter().map(|b| b.insts.len()).sum()
    }

    /// Predecessor lists, indexed by block.
    pub fn predecessors(&self) -> Vec<Vec<Block>> {
        let mut preds = vec![Vec::new(); self.blocks.len()];
        for (i, b) in self.blocks.iter().enumerate() {
            for s in b.term.successors() {
                if !preds[s.index()].contains(&Block(i as u32)) {
                    preds[s.index()].push(Block(i as u32));
                }
            }
        }
        preds
    }

    /// Blocks in reverse post-order from the entry (unreachable blocks omitted).
    pub fn rpo(&self) -> Vec<Block> {
        let n = self.blocks.len();
        let mut seen = vec![false; n];
        let mut post = Vec::with_capacity(n);
        let mut stack: Vec<(usize, Vec<Block>)> = vec![(0, self.blocks[0].term.successors())];
        seen[0] = true;
        while let Some((b, succs)) = stack.last_mut() {
            if let Some(s) = succs.pop() {
                if !seen[s.index()] {
                    seen[s.index()] = true;
                    let next = self.blocks[s.index()].term.successors();
                    stack.push((s.index(), next));
                }
            } else {
                post.push(Block(*b as u32));
                stack.pop();
            }
        }
        post.reverse();
        post
    }

    /// Removes unreachable blocks and renumbers the rest in reverse post-order.
    pub fn compact_blocks(&mut self) {
        let order = self.rpo();
        let mut map = vec![u32::MAX; self.blocks.len()];
        for (new, old) in order.iter().enumerate() {
            map[old.index()] = new as u32;
        }
        let mut old_blocks: Vec<Option<BlockData>> = std::mem::take(&mut self.blocks)
            .into_iter()
            .map(Some)
            .collect();
        for old in &order {
            let mut b = old_blocks[old.index()].take().expect("block visited once");
            b.term
                .for_each_target_mut(|t| t.block = Block(map[t.block.index()]));
            self.blocks.push(b);
        }
    }

    /// Use counts per value over the whole function.
    pub fn use_counts(&self) -> Vec<u32> {
        let mut counts = vec![0u32; self.values.len()];
        for b in &self.blocks {
            for i in &b.insts {
                for a in &i.args {
                    counts[a.index()] += 1;
                }
            }
            b.term.for_each_use(|v| counts[v.index()] += 1);
        }
        counts
    }
}

/// A runtime function the generated code calls.
#[derive(Clone, Debug)]
pub struct ExternDef {
    /// Linker symbol, `msrt_<module>_<name>`.
    pub name: String,
    /// Parameters with their reference-count conventions.
    pub params: Vec<Param>,
    /// Result type; results are owned.
    pub ret: Ty,
    /// Whether the call never returns.
    pub noreturn: bool,
    /// Whether the call has no observable effect and does not fault, so equal calls
    /// can be merged and unused ones removed.
    pub pure_: bool,
    /// Whether the result points into no borrowed argument (it is an owned allocation, an
    /// inline value or a static), so a borrowed argument may be dropped once the call returns.
    pub fresh: bool,
    /// Whether the call never reaches a cancellation point (declared `leaf` on the runtime
    /// function), so a task cannot be cancelled inside it.
    pub leaf: bool,
    /// Whether the call only reads memory, cannot fault and cannot run user code (declared `pure`
    /// on the runtime function), so the backend may assume it does not clobber the caller's memory.
    pub reads: bool,
    /// What the optimizer and code generator know this runtime function by.
    pub role: ExternRole,
}

/// A runtime function that a pass or the code generator treats specially. Lowering sets the
/// role from the runtime ABI declaration; passes read it and never a symbol name.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ExternRole {
    /// No special treatment.
    #[default]
    None,
    /// `strbuilder.append(builder, string)`.
    StrBuilderAppend,
    /// `strbuilder.append_int(builder, int)`.
    StrBuilderAppendInt,
    /// `string.concat(a, b)` (the fixed-arity and `fmt` joins share it).
    StringConcat,
    /// In-place `string.append(s, piece)`.
    StringAppend,
    /// `int.to_string(n)`.
    IntToString,
    /// `list.sorted(list, comparator)`.
    ListSorted,
    /// A bitwise copy of a list's slots that owns nothing: a fault must not drop it.
    RawSlots,
    /// Releases the buffer of a [`ExternRole::RawSlots`] copy without touching its elements.
    RawFree,
    /// Integer-list sort with the natural order.
    ListSortInts,
    /// Sort by a difference comparator.
    ListSortedByDifference,
    /// `list.new()`.
    ListNew,
    /// An empty `Map` or `Set`: all words zero, so code generation needs no call.
    MapNew,
    /// `bytes.values(bytes)`.
    BytesValues,
    /// `string.eq(a, b)`.
    StringEq,
    /// Skips a cleanup registration; handle 0 means none.
    CleanupDiscard,
    /// `bytes.append(bytes, byte)`.
    BytesAppend,
    /// A runtime call whose result borrows its operands (`string_split_view`, `map_keys_view`,
    /// `map_values_view`, `list_slice_view`): passes never move the result into an owning position
    /// or turn a copy of it into a move.
    ViewResult,
    /// A runtime function with a `<name>_take` twin (`// ms: takes_self`); the `bytetake` pass
    /// calls the twin when the first argument is an owned value that dies at the call.
    TakesDying,
    /// Starts a task that can be cancelled.
    SpawnsTask,
}

impl ExternRole {
    /// The attribute spelling in textual MIR; `None` has none.
    pub const NAMES: &'static [(ExternRole, &'static str)] = &[
        (ExternRole::StrBuilderAppend, "strbuilder_append"),
        (ExternRole::StrBuilderAppendInt, "strbuilder_append_int"),
        (ExternRole::StringConcat, "string_concat"),
        (ExternRole::StringAppend, "string_append"),
        (ExternRole::IntToString, "int_to_string"),
        (ExternRole::ListSorted, "list_sorted"),
        (ExternRole::ListSortInts, "list_sort_ints"),
        (
            ExternRole::ListSortedByDifference,
            "list_sorted_by_difference",
        ),
        (ExternRole::ListNew, "list_new"),
        (ExternRole::MapNew, "map_new"),
        (ExternRole::BytesValues, "bytes_values"),
        (ExternRole::StringEq, "string_eq"),
        (ExternRole::CleanupDiscard, "cleanup_discard"),
        (ExternRole::BytesAppend, "bytes_append"),
        (ExternRole::TakesDying, "takes_dying"),
        (ExternRole::ViewResult, "view_result"),
        (ExternRole::SpawnsTask, "spawns_task"),
    ];

    /// The textual attribute of this role.
    pub fn name(self) -> Option<&'static str> {
        Self::NAMES
            .iter()
            .find(|(r, _)| *r == self)
            .map(|(_, n)| *n)
    }

    /// The role with this textual attribute.
    pub fn from_name(name: &str) -> Option<ExternRole> {
        Self::NAMES
            .iter()
            .find(|(_, n)| *n == name)
            .map(|(r, _)| *r)
    }
}

/// A module-level variable.
#[derive(Clone, Debug)]
pub struct GlobalDef {
    /// Name.
    pub name: String,
    /// Type; the initial value is zero/null and must be stored by an init function.
    pub ty: Ty,
}

/// An implementation of an interface for one concrete type.
#[derive(Clone, Debug)]
pub struct VtableDef {
    /// Name, for symbols and the text format.
    pub name: String,
    /// The implemented interface.
    pub iface: IfaceId,
    /// Method implementations in interface order; each is a [`FuncKind::Method`] function.
    pub methods: Vec<FuncId>,
    /// Concrete type of the data, used to release it.
    pub data_ty: Ty,
}

/// A compilation unit: the whole program after monomorphization.
#[derive(Clone, Debug)]
pub struct Module {
    /// Name, used for object and symbol naming.
    pub name: String,
    /// Source file paths indexed by [`Loc::file`].
    pub files: Vec<String>,
    /// Type table.
    pub types: TyTable,
    /// Type declarations.
    pub type_defs: Vec<TypeDef>,
    /// Alternative declarations.
    pub alts: Vec<AltDef>,
    /// Interface declarations.
    pub ifaces: Vec<IfaceDef>,
    /// Interface implementation tables.
    pub vtables: Vec<VtableDef>,
    /// String literals (UTF-8).
    pub strings: Vec<String>,
    /// Element data of constant lists (`list.const`): one entry per list, each element the raw
    /// register value of its type (float bits for floats, 0 or 1 for booleans).
    pub list_consts: Vec<Vec<i64>>,
    /// Raw bytes of constant `Bytes` (`bytes`), placed in read-only data and borrowed.
    pub blobs: Vec<Vec<u8>>,
    /// Index of [`Module::strings`] by content; only [`Module::add_string`] writes both.
    string_ids: HashMap<String, StrId>,
    /// Runtime functions called. Grow it only through [`Module::add_extern`] or
    /// [`Module::push_extern`], which keep [`Module::extern_ids`] in step.
    pub externs: Vec<ExternDef>,
    /// Index of [`Module::externs`] by symbol, so a declaration never scans the list.
    extern_ids: HashMap<String, Vec<ExtId>>,
    /// Module-level variables.
    pub globals: Vec<GlobalDef>,
    /// Functions.
    pub funcs: Vec<Func>,
    /// The program entry (`fn() -> Int`, the process exit code), if any.
    pub entry: Option<FuncId>,
    /// Equality and hash functions (`fn(ptr, ptr) -> bool`, `fn(ptr) -> int`) that the
    /// descriptor of an aggregate type points to.
    pub desc_glue: Vec<(Ty, FuncId, FuncId)>,
    /// Externs that are user `extern fn` shims (`ms_abi.h`): their sized numbers cross as the
    /// same-width C types, extended per the platform ABI, instead of the runtime's 64-bit words.
    pub c_externs: std::collections::BTreeSet<String>,
}

impl fmt::Display for Loc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.is_none() {
            write!(f, "?")
        } else {
            write!(f, "{}:{}:{}", self.file, self.line, self.col)
        }
    }
}

mod module;
pub use module::Boxing;
mod ops;
