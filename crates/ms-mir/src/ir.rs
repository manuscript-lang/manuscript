//! The MIR data structures: module, functions, blocks, instructions.
//!
//! # Model
//!
//! A function is a CFG of basic blocks in SSA form. Control-flow joins use
//! block parameters instead of phi nodes. Block 0 is the entry; its parameters
//! are the function parameters.
//!
//! Every SSA value has one monomorphic [`Ty`]. MIR follows the value-semantics
//! memory model: records, lists, optionals and the like are *values*, flattened
//! into scalar leaves by the backend (see [`crate::layout`]), not heap objects
//! with identity. A value whose type [needs a drop](Module::needs_drop) (lists,
//! maps, strings, boxed alternatives, `Shared[T]`, records containing them) is
//! either **owned** (it must be consumed exactly once: moved into a consuming
//! position or `drop`ped) or **borrowed** (a read-only view the producer keeps
//! alive). Ownership is determined by the defining instruction (see
//! [`Module::result_modes`]) or by the declared [`Mode`] of a parameter, and is
//! checked by the verifier with a move/maybe-moved dataflow, so conditional
//! moves are expressed with `drop.if` flags the way drop elaboration emits them.
//!
//! Mutation is threaded through SSA: an operation that changes an owned value
//! consumes it and returns the updated value (`list.push`, `list.set`,
//! `rec.set`), and a `var` parameter is copy-in/copy-out: the callee returns
//! its final value after its result.

use crate::types::{
    AltDef, AltId, IfaceDef, IfaceId, RecId, RecordDef, Ty, TyKind, TyTable, id_type,
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
    /// A read-only view; the caller keeps ownership.
    Borrow,
    /// Ownership moves in; the callee must consume the value.
    Own,
    /// A `var` parameter: ownership moves in and the final value is returned
    /// after the function's result (copy-in/copy-out). Only on function parameters.
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

    /// Evaluates the condition on two integers.
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
    IConst, FConst, BConst, UnitConst, StrLit,
    // Integer arithmetic: wrapping, overflow-checked, and unchecked division.
    IAdd, ISub, IMul, INeg, IAddOverflow, IMulOverflow, IntOverflowIf, IAddChk, ISubChk, IMulChk, INegChk, SDivChk, SRemChk, SDiv, SRem,
    // Sized integers: fault unless the value fits its type. `Float32`: round to binary32.
    NarrowChk, F32Round,
    // Conversions: `Conv` retypes a number to another type of its kind (rounding to binary32 for `Float32`); `INarrowOpt` yields some(value) when an int fits the smaller type.
    Conv, INarrowOpt,
    // Bit operations and booleans (`And`/`Or`/`Xor` accept Int or Bool).
    And, Or, Xor, Shl, Sshr, Not,
    // Comparisons.
    ICmp, FCmp,
    // Float arithmetic and conversions.
    FAdd, FSub, FMul, FDiv, FNeg, FSqrt, FAbs, FFloor, FCeil, FTrunc, I2F, F2IOpt, B2I, Select,
    // Records and alternatives.
    RecNew, RecGet, RecSet, RecFill, AltNew, AltTag, AltGet, AltUnbox,
    // Lists.
    ListNew, ListLit, ListLen, ListGet, ListGetNn, ListGetU, ListSet, ListSetNn, ListSetU, ListFill, ListPush, ListDropLast,
    // Optionals.
    OptSome, OptView, OptNone, OptIsSome, OptGet, OptUnwrap, OptUnbox,
    // Strings.
    StrLen, StrByte, StrAscii,
    // Shared[T].
    SharedNew, SharedGet, SharedAddr,
    // Closures and interface views.
    ClosureNew, ClosureCap, IfaceNew, IfaceData, IfaceIs,
    // Ownership.
    Copy, Drop, DropIf, MoveOut,
    // Raw memory: stack slots, interior pointers into lists and records.
    Slot, Load, Take, Store, Put, ListAddr, ListAddrU, PtrField, PtrIsNull,
    // Calls.
    Call, CallInd, CallRt, CallMethod,
    // Runtime services.
    TypeDesc, FuncAddr, Poll, DepthEnter, DepthLeave, CleanupPush, CleanupRun, GlobalGet, GlobalSet,
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
    /// Drops or deep-copies a value (runs destructors, adjusts counts).
    pub rc: bool,
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
        !self.writes && !self.faults && !self.io && !self.rc
    }
}

macro_rules! effects {
    () => { Effects { reads: false, writes: false, faults: false, rc: false, alloc: false, io: false } };
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
    /// Record id.
    Rec,
    /// Record id and field index.
    Field,
    /// Alternative id and case index.
    Case,
    /// Alternative id, case and field index.
    AltField,
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

impl Op {
    /// Every opcode, for tables and the text parser.
    #[rustfmt::skip]
    pub const ALL: &'static [Op] = &[
        Op::IConst, Op::FConst, Op::BConst, Op::UnitConst, Op::StrLit,
        Op::IAdd, Op::ISub, Op::IMul, Op::INeg, Op::IAddOverflow, Op::IMulOverflow, Op::IntOverflowIf, Op::IAddChk, Op::ISubChk, Op::IMulChk, Op::INegChk,
        Op::SDivChk, Op::SRemChk, Op::SDiv, Op::SRem, Op::NarrowChk, Op::F32Round, Op::Conv, Op::INarrowOpt,
        Op::And, Op::Or, Op::Xor, Op::Shl, Op::Sshr, Op::Not,
        Op::ICmp, Op::FCmp,
        Op::FAdd, Op::FSub, Op::FMul, Op::FDiv, Op::FNeg, Op::FSqrt, Op::FAbs, Op::FFloor, Op::FCeil, Op::FTrunc, Op::I2F, Op::F2IOpt, Op::B2I, Op::Select,
        Op::RecNew, Op::RecGet, Op::RecSet, Op::RecFill, Op::AltNew, Op::AltTag, Op::AltGet, Op::AltUnbox,
        Op::ListNew, Op::ListLit, Op::ListLen, Op::ListGet, Op::ListGetNn, Op::ListGetU,
        Op::ListSet, Op::ListSetNn, Op::ListSetU, Op::ListFill, Op::ListPush, Op::ListDropLast,
        Op::OptSome, Op::OptView, Op::OptNone, Op::OptIsSome, Op::OptGet, Op::OptUnwrap, Op::OptUnbox,
        Op::StrLen, Op::StrByte, Op::StrAscii, Op::SharedNew, Op::SharedGet, Op::SharedAddr,
        Op::ClosureNew, Op::ClosureCap, Op::IfaceNew, Op::IfaceData, Op::IfaceIs,
        Op::Copy, Op::Drop, Op::DropIf, Op::MoveOut, Op::Slot, Op::Load, Op::Take, Op::Store, Op::Put, Op::ListAddr, Op::ListAddrU, Op::PtrField, Op::PtrIsNull,
        Op::Call, Op::CallInd, Op::CallRt, Op::CallMethod,
        Op::TypeDesc, Op::FuncAddr, Op::Poll, Op::DepthEnter, Op::DepthLeave, Op::CleanupPush, Op::CleanupRun,
        Op::GlobalGet, Op::GlobalSet,
    ];

    /// The static description of this opcode.
    #[rustfmt::skip]
    #[allow(clippy::needless_update)]
    pub fn info(self) -> OpInfo {
        use ImmKind as K;
        let (name, imm, has_result, effects) = match self {
            Op::IConst => ("iconst", K::Int, true, effects!()),
            Op::FConst => ("fconst", K::Float, true, effects!()),
            Op::BConst => ("bconst", K::Bool, true, effects!()),
            Op::UnitConst => ("unit", K::None, true, effects!()),
            Op::StrLit => ("str", K::Str, true, effects!()),
            Op::IAdd => ("iadd", K::None, true, effects!()),
            Op::ISub => ("isub", K::None, true, effects!()),
            Op::IMul => ("imul", K::None, true, effects!()),
            Op::INeg => ("ineg", K::None, true, effects!()),
            Op::IAddOverflow => ("iadd.overflow", K::None, true, effects!()),
            Op::IMulOverflow => ("imul.overflow", K::None, true, effects!()),
            Op::IntOverflowIf => ("int_overflow.if", K::None, false, effects!(faults)),
            Op::NarrowChk => ("narrow.chk", K::None, true, effects!(faults)),
            Op::F32Round => ("f32.round", K::None, true, effects!()),
            Op::Conv => ("conv", K::None, true, effects!()),
            Op::INarrowOpt => ("inarrow.opt", K::None, true, effects!()),
            Op::IAddChk => ("iadd.chk", K::None, true, effects!(faults)),
            Op::ISubChk => ("isub.chk", K::None, true, effects!(faults)),
            Op::IMulChk => ("imul.chk", K::None, true, effects!(faults)),
            Op::INegChk => ("ineg.chk", K::None, true, effects!(faults)),
            Op::SDivChk => ("sdiv.chk", K::None, true, effects!(faults)),
            Op::SRemChk => ("srem.chk", K::None, true, effects!(faults)),
            Op::SDiv => ("sdiv", K::None, true, effects!()),
            Op::SRem => ("srem", K::None, true, effects!()),
            Op::And => ("and", K::None, true, effects!()),
            Op::Or => ("or", K::None, true, effects!()),
            Op::Xor => ("xor", K::None, true, effects!()),
            Op::Shl => ("shl", K::None, true, effects!()),
            Op::Sshr => ("sshr", K::None, true, effects!()),
            Op::Not => ("not", K::None, true, effects!()),
            Op::ICmp => ("icmp", K::Cc, true, effects!()),
            Op::FCmp => ("fcmp", K::Cc, true, effects!()),
            Op::FAdd => ("fadd", K::None, true, effects!()),
            Op::FSub => ("fsub", K::None, true, effects!()),
            Op::FMul => ("fmul", K::None, true, effects!()),
            Op::FDiv => ("fdiv", K::None, true, effects!()),
            Op::FNeg => ("fneg", K::None, true, effects!()),
            Op::FSqrt => ("fsqrt", K::None, true, effects!()),
            Op::FFloor => ("ffloor", K::None, true, effects!()),
            Op::FCeil => ("fceil", K::None, true, effects!()),
            Op::FTrunc => ("ftrunc", K::None, true, effects!()),
            Op::FAbs => ("fabs", K::None, true, effects!()),
            Op::I2F => ("i2f", K::None, true, effects!()),
            Op::F2IOpt => ("f2i.opt", K::None, true, effects!()),
            Op::B2I => ("b2i", K::None, true, effects!()),
            Op::Select => ("select", K::None, true, effects!()),
            Op::RecNew => ("rec.new", K::Rec, true, effects!()),
            Op::RecGet => ("rec.get", K::Field, true, effects!()),
            Op::RecSet => ("rec.set", K::Field, true, effects!(rc)),
            Op::RecFill => ("rec.fill", K::Field, true, effects!()),
            Op::AltNew => ("alt.new", K::Case, true, effects!(alloc)),
            Op::AltTag => ("alt.tag", K::None, true, effects!(reads)),
            Op::AltGet => ("alt.get", K::AltField, true, effects!(reads)),
            Op::AltUnbox => ("alt.unbox", K::AltField, true, effects!(writes, rc)),
            Op::ListNew => ("list.new", K::None, true, effects!(alloc)),
            Op::ListLit => ("list.lit", K::None, true, effects!(alloc)),
            Op::ListLen => ("list.len", K::None, true, effects!()),
            Op::ListGet => ("list.get", K::None, true, effects!(reads, faults)),
            Op::ListGetNn => ("list.get.nn", K::None, true, effects!(reads, faults)),
            Op::ListGetU => ("list.get.u", K::None, true, effects!(reads)),
            Op::ListSet => ("list.set", K::None, true, effects!(reads, writes, faults, rc)),
            Op::ListSetNn => ("list.set.nn", K::None, true, effects!(reads, writes, faults, rc)),
            Op::ListSetU => ("list.set.u", K::None, true, effects!(reads, writes, rc)),
            Op::ListFill => ("list.fill", K::None, true, effects!(reads, writes, faults)),
            Op::ListPush => ("list.push", K::None, true, effects!(reads, writes, alloc, faults)),
            Op::ListDropLast => ("list.droplast", K::None, true, effects!(reads, writes, rc)),
            Op::OptSome => ("opt.some", K::None, true, effects!()),
            Op::OptView => ("opt.view", K::None, true, effects!()),
            Op::OptNone => ("opt.none", K::None, true, effects!()),
            Op::OptIsSome => ("opt.is_some", K::None, true, effects!()),
            Op::OptGet => ("opt.get", K::None, true, effects!()),
            Op::OptUnwrap => ("opt.unwrap", K::None, true, effects!(faults)),
            Op::OptUnbox => ("opt.unbox", K::None, true, effects!(writes, rc)),
            Op::StrLen => ("str.len", K::None, true, effects!(reads, writes)),
            Op::StrByte => ("str.byte", K::None, true, effects!(reads)),
            Op::StrAscii => ("str.ascii", K::None, true, effects!()),
            Op::SharedNew => ("shared.new", K::None, true, effects!(alloc)),
            Op::SharedGet => ("shared.get", K::None, true, effects!(reads)),
            Op::SharedAddr => ("shared.addr", K::None, true, effects!(reads)),
            Op::ClosureNew => ("closure.new", K::Func, true, effects!(alloc)),
            Op::ClosureCap => ("closure.cap", K::Idx, true, effects!(reads)),
            Op::IfaceNew => ("iface.new", K::Vtable, true, effects!()),
            Op::IfaceData => ("iface.data", K::None, true, effects!()),
            Op::IfaceIs => ("iface.is", K::Vtable, true, effects!()),
            Op::Copy => ("copy", K::None, true, effects!(reads, alloc, rc)),
            Op::Drop => ("drop", K::None, false, effects!(writes, rc)),
            Op::MoveOut => ("move.out", K::None, true, effects!(writes)),
            Op::DropIf => ("drop.if", K::None, false, effects!(writes, rc)),
            Op::Slot => ("slot", K::Ty, true, effects!()),
            Op::Load => ("load", K::Ty, true, effects!(reads)),
            Op::Take => ("take", K::Ty, true, effects!(reads, writes)),
            Op::Store => ("store", K::None, false, effects!(writes)),
            Op::Put => ("put", K::None, false, effects!(writes)),
            Op::ListAddr => ("list.addr", K::None, true, effects!(faults)),
            Op::ListAddrU => ("list.addr.u", K::None, true, effects!()),
            Op::PtrField => ("ptr.field", K::Field, true, effects!()),
            Op::PtrIsNull => ("ptr.is_null", K::None, true, effects!()),
            Op::Call => ("call", K::Func, true, effects!(reads, writes, faults, rc, alloc, io)),
            Op::CallInd => ("call.ind", K::None, true, effects!(reads, writes, faults, rc, alloc, io)),
            Op::CallRt => ("call.rt", K::Ext, true, effects!(reads, writes, faults, rc, alloc, io)),
            Op::CallMethod => ("call.method", K::Method, true, effects!(reads, writes, faults, rc, alloc, io)),
            Op::TypeDesc => ("typedesc", K::Ty, true, effects!()),
            Op::FuncAddr => ("func.addr", K::Func, true, effects!()),
            Op::Poll => ("poll", K::None, false, effects!(faults, io)),
            Op::DepthEnter => ("depth.enter", K::None, false, effects!(faults, io)),
            Op::DepthLeave => ("depth.leave", K::None, false, effects!(io)),
            Op::CleanupPush => ("cleanup.push", K::Func, true, effects!(io)),
            Op::CleanupRun => ("cleanup.run", K::None, false, effects!(io)),
            Op::GlobalGet => ("global.get", K::Global, true, effects!(reads)),
            Op::GlobalSet => ("global.set", K::Global, false, effects!(writes, rc)),
        };
        OpInfo { name, imm, has_result, effects }
    }

    /// Looks an opcode up by mnemonic.
    pub fn from_name(name: &str) -> Option<Op> {
        Op::ALL.iter().copied().find(|op| op.info().name == name)
    }

    /// Whether the instruction is a call of any kind.
    pub fn is_call(self) -> bool {
        matches!(self, Op::Call | Op::CallInd | Op::CallRt | Op::CallMethod)
    }

    /// Whether two instructions with this opcode, operands and immediate always
    /// produce equal results and can be merged (value numbering).
    pub fn is_numberable(self) -> bool {
        let e = self.info().effects;
        e.is_pure() && self.info().has_result && !matches!(self, Op::Slot | Op::Copy)
    }

    /// Whether the instruction is a call of any kind.
    pub fn is_call_kind(self) -> bool {
        self.is_call()
    }
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
    /// A record.
    Rec(RecId),
    /// A record field.
    Field(RecId, u32),
    /// An alternative case.
    Case(AltId, u32),
    /// An alternative case field.
    AltField(AltId, u32, u32),
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
    /// Aborts the program with a fault, running `with` cleanups first.
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

/// A function.
#[derive(Clone, Debug)]
pub struct Func {
    /// Symbol and display name.
    pub name: String,
    /// Parameters; `blocks[0].params` define their values.
    pub params: Vec<Param>,
    /// Result type; results are owned unless `ret_borrowed` says the function lends one.
    pub ret: Ty,
    /// The result is a borrow of an argument that the caller keeps alive: returned without a
    /// retain, and not released by the caller.
    pub ret_borrowed: bool,
    /// Visibility.
    pub linkage: Linkage,
    /// Role of the function.
    pub kind: FuncKind,
    /// Inlining directive.
    pub inline: InlineHint,
    /// Declaration position.
    pub loc: Loc,
    /// Type of every value, indexed by [`Value`].
    pub values: Vec<Ty>,
    /// Blocks, indexed by [`Block`]; block 0 is the entry.
    pub blocks: Vec<BlockData>,
    /// Inlined-callee scopes referenced by [`Loc::scope`].
    pub scopes: Vec<Scope>,
    /// Indexes of pointer parameters that no other parameter or memory the function reaches
    /// overlaps while it runs (`var` parameters, which the checker keeps exclusive).
    pub noalias: Vec<u32>,
    /// A closure function whose environment points into its maker's frame (a borrowed capture
    /// or a shared variable): the closure may be called, copied and dropped, but never stored
    /// or returned, and the verifier rejects code that does.
    pub scoped: bool,
}

impl Func {
    /// A function with an entry block whose parameters mirror `params`.
    pub fn new(name: &str, params: Vec<Param>, ret: Ty) -> Func {
        let mut f = Func {
            name: name.to_string(),
            params: params.clone(),
            ret,
            ret_borrowed: false,
            linkage: Linkage::Internal,
            kind: FuncKind::Normal,
            inline: InlineHint::Auto,
            loc: Loc::NONE,
            values: Vec::new(),
            blocks: vec![BlockData::new()],
            scopes: Vec::new(),
            noalias: Vec::new(),
            scoped: false,
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

    /// Replaces every use of `from` by `to` (instruction operands and terminators).
    pub fn replace_uses(&mut self, from: Value, to: Value) {
        for b in &mut self.blocks {
            for i in &mut b.insts {
                for a in &mut i.args {
                    if *a == from {
                        *a = to;
                    }
                }
            }
            b.term.for_each_use_mut(|v| {
                if *v == from {
                    *v = to;
                }
            });
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
    /// Record declarations.
    pub records: Vec<RecordDef>,
    /// Alternative declarations.
    pub alts: Vec<AltDef>,
    /// Interface declarations.
    pub ifaces: Vec<IfaceDef>,
    /// Interface implementation tables.
    pub vtables: Vec<VtableDef>,
    /// String literals (UTF-8).
    pub strings: Vec<String>,
    /// Index of [`Module::strings`] by content; only [`Module::add_string`] writes both.
    string_ids: HashMap<String, StrId>,
    /// Runtime functions called.
    pub externs: Vec<ExternDef>,
    /// Module-level variables.
    pub globals: Vec<GlobalDef>,
    /// Functions.
    pub funcs: Vec<Func>,
    /// The program entry (`fn() -> Int`, the process exit code), if any.
    pub entry: Option<FuncId>,
    /// Equality and hash functions (`fn(ptr, ptr) -> bool`, `fn(ptr) -> int`) that the
    /// descriptor of an aggregate type points to.
    pub desc_glue: Vec<(Ty, FuncId, FuncId)>,
}

impl Default for Module {
    fn default() -> Self {
        Self::new("module")
    }
}

impl Module {
    /// An empty module.
    pub fn new(name: &str) -> Module {
        Module {
            name: name.to_string(),
            files: Vec::new(),
            types: TyTable::new(),
            records: Vec::new(),
            alts: Vec::new(),
            ifaces: Vec::new(),
            vtables: Vec::new(),
            strings: Vec::new(),
            string_ids: HashMap::new(),
            externs: Vec::new(),
            globals: Vec::new(),
            funcs: Vec::new(),
            entry: None,
            desc_glue: Vec::new(),
        }
    }

    /// Interns a string literal.
    pub fn add_string(&mut self, s: &str) -> StrId {
        if let Some(&id) = self.string_ids.get(s) {
            return id;
        }
        let id = StrId(self.strings.len() as u32);
        self.strings.push(s.to_string());
        self.string_ids.insert(s.to_string(), id);
        id
    }

    /// Registers a source file and returns its index for [`Loc`].
    pub fn add_file(&mut self, path: &str) -> u32 {
        if let Some(i) = self.files.iter().position(|x| x == path) {
            return i as u32;
        }
        self.files.push(path.to_string());
        self.files.len() as u32 - 1
    }

    /// Declares a record and returns its id and type.
    pub fn add_record(&mut self, name: &str, fields: Vec<(String, Ty)>) -> (RecId, Ty) {
        self.records.push(RecordDef {
            name: name.to_string(),
            fields,
        });
        let id = RecId(self.records.len() as u32 - 1);
        (id, self.types.rec(id))
    }

    /// Declares an alternative and returns its id and type.
    pub fn add_alt(&mut self, name: &str, cases: Vec<crate::types::CaseDef>) -> (AltId, Ty) {
        self.alts.push(AltDef {
            name: name.to_string(),
            cases,
        });
        let id = AltId(self.alts.len() as u32 - 1);
        (id, self.types.alt(id))
    }

    /// Declares a runtime function (or returns the existing one with this symbol and signature).
    pub fn add_extern(&mut self, def: ExternDef) -> ExtId {
        let same = |e: &ExternDef| {
            e.name == def.name
                && e.ret == def.ret
                && e.params.len() == def.params.len()
                && e.params.iter().zip(&def.params).all(|(a, b)| a.ty == b.ty)
        };
        if let Some(i) = self.externs.iter().position(same) {
            return ExtId(i as u32);
        }
        self.externs.push(def);
        ExtId(self.externs.len() as u32 - 1)
    }

    /// Adds a function.
    pub fn add_func(&mut self, f: Func) -> FuncId {
        self.funcs.push(f);
        FuncId(self.funcs.len() as u32 - 1)
    }

    /// Finds a function by name.
    pub fn func_by_name(&self, name: &str) -> Option<FuncId> {
        self.funcs
            .iter()
            .position(|f| f.name == name)
            .map(|i| FuncId(i as u32))
    }

    /// Finds a record by name.
    pub fn record_by_name(&self, name: &str) -> Option<RecId> {
        self.records
            .iter()
            .position(|r| r.name == name)
            .map(|i| RecId(i as u32))
    }

    /// Finds an alternative by name.
    pub fn alt_by_name(&self, name: &str) -> Option<AltId> {
        self.alts
            .iter()
            .position(|r| r.name == name)
            .map(|i| AltId(i as u32))
    }

    /// The element type of a list type.
    pub fn list_elem(&self, ty: Ty) -> Option<Ty> {
        match self.types.kind(ty) {
            TyKind::List(e) => Some(*e),
            _ => None,
        }
    }

    /// The payload type of an optional type.
    pub fn opt_inner(&self, ty: Ty) -> Option<Ty> {
        match self.types.kind(ty) {
            TyKind::Opt(e) => Some(*e),
            _ => None,
        }
    }

    /// The field types of a record or alternative case, for `rec.new`/`alt.new`.
    pub fn field_types(&self, imm: Imm) -> Option<Vec<Ty>> {
        match imm {
            Imm::Rec(r) => Some(
                self.records
                    .get(r.index())?
                    .fields
                    .iter()
                    .map(|f| f.1)
                    .collect(),
            ),
            Imm::Case(a, c) => Some(
                self.alts
                    .get(a.index())?
                    .cases
                    .get(c as usize)?
                    .fields
                    .iter()
                    .map(|f| f.1)
                    .collect(),
            ),
            _ => None,
        }
    }

    /// Whether `Optional[inner]` contains itself by value (`type Node: next: Optional[Node]`)
    /// and therefore holds its payload in a heap block behind a nullable pointer. Backends
    /// share this rule through [`Boxing`], which memoizes it.
    pub fn opt_is_boxed(&self, inner: Ty) -> bool {
        Boxing::default().opt(self, inner)
    }

    /// Whether values of `ty` own resources that must be dropped (strings, lists,
    /// maps, closures, interfaces, boxed or recursive alternatives, and records,
    /// alternatives and optionals containing them). Plain data is copied freely.
    pub fn needs_drop(&self, ty: Ty) -> bool {
        self.needs_drop_in(ty, &mut Vec::new())
    }

    fn needs_drop_in(&self, ty: Ty, seen: &mut Vec<Ty>) -> bool {
        match self.types.kind(ty) {
            TyKind::Unit
            | TyKind::Bool
            | TyKind::Int
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::Float
            | TyKind::Float32
            | TyKind::Ptr => false,
            TyKind::Opt(inner) => self.needs_drop_in(*inner, seen),
            TyKind::Rec(r) => {
                if seen.contains(&ty) {
                    return true;
                }
                seen.push(ty);
                let out = self.records[r.index()]
                    .fields
                    .iter()
                    .any(|f| self.needs_drop_in(f.1, seen));
                seen.pop();
                out
            }
            TyKind::Alt(a) => {
                if seen.contains(&ty) {
                    return true;
                }
                seen.push(ty);
                let out = self.alts[a.index()]
                    .cases
                    .iter()
                    .any(|c| c.fields.iter().any(|f| self.needs_drop_in(f.1, seen)));
                seen.pop();
                out
            }
            _ => true,
        }
    }

    /// The ownership mode of the result of `inst` in `f`, if it is reference counted.
    pub fn result_mode(&self, f: &Func, inst: &Inst) -> Option<Mode> {
        let res = inst.res?;
        if !self.needs_drop(f.ty(res)) {
            return None;
        }
        if let (Op::Call, Imm::Func(g)) = (inst.op, inst.imm)
            && self.funcs[g.index()].ret_borrowed
        {
            return Some(Mode::Borrow);
        }
        if let (Op::CallMethod, Imm::Method(i, k)) = (inst.op, inst.imm)
            && self.ifaces[i.index()].methods[k as usize].ret_borrowed
        {
            return Some(Mode::Borrow);
        }
        Some(match inst.op {
            Op::RecGet
            | Op::AltGet
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::OptGet
            | Op::ClosureCap
            | Op::GlobalGet
            | Op::Load
            | Op::StrLit
            | Op::StrAscii
            | Op::OptView
            | Op::OptNone => Mode::Borrow,
            _ => Mode::Own,
        })
    }
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

/// The recursive-layout decisions of a module: an alternative or an optional that contains
/// itself by value lives behind a pointer. One `Boxing` memoizes the answers for a module.
#[derive(Default)]
pub struct Boxing {
    alts: HashMap<AltId, bool>,
    opts: HashMap<Ty, bool>,
}

impl Boxing {
    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn alt(&mut self, m: &Module, a: AltId) -> bool {
        if let Some(b) = self.alts.get(&a) {
            return *b;
        }
        // Provisional answer for cycles through other alternatives.
        self.alts.insert(a, false);
        let target = m.types.find(&TyKind::Alt(a));
        let b = target.is_some_and(|t| self.reaches_by_value(m, t, t, &mut Vec::new()));
        self.alts.insert(a, b);
        b
    }

    /// Whether `Optional[inner]` contains itself by value.
    pub fn opt(&mut self, m: &Module, inner: Ty) -> bool {
        if let Some(b) = self.opts.get(&inner) {
            return *b;
        }
        self.opts.insert(inner, false);
        let target = m.types.find(&TyKind::Opt(inner));
        let b = target.is_some_and(|t| self.reaches_by_value(m, t, t, &mut Vec::new()));
        self.opts.insert(inner, b);
        b
    }

    fn reaches_by_value(&mut self, m: &Module, from: Ty, target: Ty, seen: &mut Vec<Ty>) -> bool {
        let children: Vec<Ty> = match m.types.kind(from) {
            TyKind::Rec(r) => m.records[r.index()].fields.iter().map(|f| f.1).collect(),
            TyKind::Alt(a) => m.alts[a.index()]
                .cases
                .iter()
                .flat_map(|c| c.fields.iter().map(|f| f.1))
                .collect(),
            TyKind::Opt(t) => vec![*t],
            _ => return false,
        };
        for c in children {
            if c == target {
                return true;
            }
            if seen.contains(&c) {
                continue;
            }
            seen.push(c);
            // Stop at other boxed alternatives and optionals: they are one pointer.
            if let TyKind::Alt(a) = m.types.kind(c)
                && self.alt(m, *a)
            {
                continue;
            }
            if let TyKind::Opt(i) = m.types.kind(c)
                && self.opt(m, *i)
            {
                continue;
            }
            if self.reaches_by_value(m, c, target, seen) {
                return true;
            }
        }
        false
    }
}
