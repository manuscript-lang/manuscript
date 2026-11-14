//! Operand and result type rules of each MIR instruction.
//!
//! [`Verifier::check_types`] routes an instruction to the function for its op family; each
//! function states the operand count and types its ops require.

use super::{Verifier, r_id};
use crate::ir::*;
use crate::types::{Ty, TyKind};

impl Verifier<'_> {
    /// Checks the operand count and the operand and result types of one instruction.
    pub(super) fn check_types(&self, inst: &Inst) -> Result<(), String> {
        let check = InstCheck {
            v: self,
            inst,
            m: self.m,
            f: self.f,
            n: inst.args.len(),
            res: inst.res.map(|r| self.f.ty(r)),
        };
        check.run()
    }
}

/// One instruction under check, with the views every family needs.
struct InstCheck<'a, 'b> {
    v: &'a Verifier<'b>,
    inst: &'a Inst,
    m: &'a Module,
    f: &'a Func,
    /// Operand count.
    n: usize,
    /// Type of the result, when the instruction has one.
    res: Option<Ty>,
}

impl InstCheck<'_, '_> {
    /// Type of operand `i`.
    fn t(&self, i: usize) -> Ty {
        self.f.ty(self.inst.args[i])
    }

    fn want(&self, cond: bool, msg: &str) -> Result<(), String> {
        if cond { Ok(()) } else { Err(msg.to_string()) }
    }

    fn arity(&self, k: usize) -> Result<(), String> {
        if self.n == k {
            Ok(())
        } else {
            Err(format!("expected {k} operands, found {}", self.n))
        }
    }

    fn mismatch(&self, what: &str, got: Ty, exp: Ty) -> String {
        format!(
            "{what} has type {} but {} is expected",
            self.v.tn(got),
            self.v.tn(exp)
        )
    }

    fn run(&self) -> Result<(), String> {
        match self.inst.op {
            Op::IConst | Op::FConst | Op::BConst | Op::UnitConst | Op::StrLit | Op::BytesLit => {
                self.constants()
            }
            Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::SDiv
            | Op::SRem
            | Op::Shl
            | Op::Sshr
            | Op::Ushr
            | Op::Rotl
            | Op::Rotr
            | Op::IAddOverflow
            | Op::IMulOverflow
            | Op::IntOverflowIf
            | Op::NarrowChk
            | Op::Conv
            | Op::INarrowOpt
            | Op::F32Round
            | Op::INeg
            | Op::INegChk
            | Op::And
            | Op::Or
            | Op::Xor
            | Op::Clz
            | Op::Ctz
            | Op::Popcnt
            | Op::Not => self.integer_ops(),
            Op::UICmp | Op::ICmp | Op::FCmp | Op::Select => self.comparisons(),
            Op::FAdd
            | Op::FSub
            | Op::FMul
            | Op::FDiv
            | Op::FNeg
            | Op::FSqrt
            | Op::FAbs
            | Op::FFloor
            | Op::FCeil
            | Op::FTrunc
            | Op::I2F
            | Op::F2IOpt
            | Op::B2I => self.float_ops(),
            Op::TypeNew | Op::TypeGet | Op::TypeSet | Op::TypeFill | Op::TypeRelease => {
                self.type_ops()
            }
            Op::AltNew
            | Op::AltView
            | Op::AltPlain
            | Op::AltTag
            | Op::AltRelease
            | Op::AltGet
            | Op::AltUnbox
            | Op::AltTake => self.alternatives(),
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
            | Op::ListDropLast => self.lists(),
            Op::OptSome
            | Op::OptView
            | Op::OptNone
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptUnwrap
            | Op::OptUnbox
            | Op::OptAddr => self.optionals(),
            Op::StrLen | Op::StrByte | Op::StrAscii | Op::StrAsciiAt | Op::StrAsciiLen => {
                self.strings()
            }
            Op::ClosureNew
            | Op::ClosureCap
            | Op::ClosureCapAddr
            | Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceIs
            | Op::IfaceData => self.closures_and_interfaces(),
            Op::Call | Op::CallInd | Op::CallRt | Op::CallMethod => self.calls(),
            Op::Clone | Op::AltOwn | Op::MoveOut | Op::Drop | Op::DropIf => self.ownership(),
            Op::Slot
            | Op::ListAddr
            | Op::ListAddrU
            | Op::PtrIsNull
            | Op::PtrField
            | Op::Load
            | Op::Take
            | Op::Put
            | Op::Store
            | Op::FuncAddr
            | Op::TypeDesc => self.memory(),
            Op::Poll
            | Op::DepthEnter
            | Op::DepthLeave
            | Op::CleanupRun
            | Op::CleanupPush
            | Op::GlobalGet
            | Op::GlobalSet => self.runtime_services(),
            Op::ScopeBegin | Op::ScopeOwn | Op::ScopeEnd => self.scope_markers(),
            Op::ScopeDisown => {
                self.arity(1)?;
                self.want(self.res.is_none(), "scope.disown has no result")
            }
            Op::ScopeMark => {
                self.arity(1)?;
                self.want(self.res.is_none(), "scope.mark has no result")
            }
        }
    }

    /// Constants: literal operands and their result type.
    fn constants(&self) -> Result<(), String> {
        match self.inst.op {
            Op::IConst => {
                self.arity(0)?;
                self.want(
                    matches!(self.inst.imm, Imm::Int(_))
                        && self.res.is_some_and(|r| self.m.types.is_int(r)),
                    "iconst yields an int type",
                )
            }
            Op::FConst => {
                self.arity(0)?;
                self.want(
                    matches!(self.inst.imm, Imm::Float(_))
                        && self.res.is_some_and(|r| self.m.types.is_float(r)),
                    "fconst yields a float type",
                )
            }
            Op::BConst => {
                self.arity(0)?;
                self.want(
                    matches!(self.inst.imm, Imm::Bool(_)) && self.res == Some(Ty::BOOL),
                    "bconst yields bool",
                )
            }
            Op::UnitConst => {
                self.arity(0)?;
                self.want(self.res == Some(Ty::UNIT), "unit yields unit")
            }
            Op::StrLit => {
                self.arity(0)?;
                match self.inst.imm {
                    Imm::Str(s) if s.index() < self.m.strings.len() => {
                        self.want(self.res == Some(Ty::STR), "str yields string")
                    }
                    _ => Err("bad string literal".into()),
                }
            }
            Op::BytesLit => {
                self.arity(0)?;
                match self.inst.imm {
                    Imm::Int(i) if (i as usize) < self.m.blobs.len() => {
                        self.want(self.res == Some(Ty::BYTES), "bytes yields Bytes")
                    }
                    _ => Err("bad bytes literal".into()),
                }
            }
            _ => unreachable!("constants is only called for its own ops"),
        }
    }

    /// Integer and bit arithmetic.
    fn integer_ops(&self) -> Result<(), String> {
        match self.inst.op {
            Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::SDiv
            | Op::SRem
            | Op::Shl
            | Op::Sshr
            | Op::Ushr
            | Op::Rotl
            | Op::Rotr => {
                self.arity(2)?;
                self.want(
                    self.m.types.is_int(self.t(0))
                        && self.t(1) == self.t(0)
                        && self.res == Some(self.t(0)),
                    "operands and result must be one int type",
                )
            }
            Op::IAddOverflow | Op::IMulOverflow => {
                self.arity(2)?;
                self.want(
                    self.t(0) == Ty::INT && self.t(1) == Ty::INT && self.res == Some(Ty::BOOL),
                    "overflow flag takes two ints and yields bool",
                )
            }
            Op::IntOverflowIf => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::BOOL && self.res.is_none(),
                    "overflow guard takes bool and has no result",
                )
            }
            Op::NarrowChk => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::INT
                        && self
                            .res
                            .is_some_and(|r| matches!(self.m.types.int_bits(r), Some(b) if b < 64)),
                    "narrow.chk takes an Int and yields a sized int",
                )
            }
            Op::Conv => {
                self.arity(1)?;
                let to = self.res;
                self.want(
                    to.is_some_and(|r| {
                        (self.m.types.is_int(self.t(0)) && self.m.types.is_int(r))
                            || (self.m.types.is_float(self.t(0)) && self.m.types.is_float(r))
                    }),
                    "conv takes an int or float and yields another type of the same kind",
                )
            }
            Op::INarrowOpt => {
                self.arity(1)?;
                let inner = self.res.and_then(|r| self.m.opt_inner(r));
                self.want(
                    self.m.types.is_int(self.t(0)) && inner.is_some_and(|i| self.m.types.is_int(i)),
                    "inarrow.opt takes an int and yields an optional int",
                )
            }
            Op::F32Round => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::FLOAT32 && self.res == Some(Ty::FLOAT32),
                    "operand and result must be float32",
                )
            }
            Op::INeg | Op::INegChk => {
                self.arity(1)?;
                self.want(
                    self.m.types.is_int(self.t(0)) && self.res == Some(self.t(0)),
                    "operand and result must be one int type",
                )
            }
            Op::And | Op::Or | Op::Xor => {
                self.arity(2)?;
                self.want(
                    (self.m.types.is_int(self.t(0)) || self.t(0) == Ty::BOOL)
                        && self.t(0) == self.t(1)
                        && self.res == Some(self.t(0)),
                    "operands and result must be both int or both bool",
                )
            }
            Op::Clz | Op::Ctz | Op::Popcnt => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::INT && self.res == Some(Ty::INT),
                    "operand and result must be int",
                )
            }
            Op::Not => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::BOOL && self.res == Some(Ty::BOOL),
                    "operand and result must be bool",
                )
            }
            _ => unreachable!("integer_ops is only called for its own ops"),
        }
    }

    /// Comparisons and `select`.
    fn comparisons(&self) -> Result<(), String> {
        match self.inst.op {
            Op::UICmp => {
                self.arity(2)?;
                self.want(
                    matches!(self.inst.imm, Imm::Cc(_))
                        && self.t(0) == self.t(1)
                        && self.m.types.is_int(self.t(0))
                        && self.res == Some(Ty::BOOL),
                    "uicmp compares two ints and yields bool",
                )
            }
            Op::ICmp => {
                self.arity(2)?;
                let Imm::Cc(cc) = self.inst.imm else {
                    return Err("missing condition".into());
                };
                let ok = self.t(0) == self.t(1)
                    && (self.m.types.is_int(self.t(0))
                        || (self.t(0) == Ty::BOOL && matches!(cc, Cc::Eq | Cc::Ne)));
                self.want(
                    ok && self.res == Some(Ty::BOOL),
                    "icmp compares two ints (or bools for eq/ne) and yields bool",
                )
            }
            Op::FCmp => {
                self.arity(2)?;
                self.want(
                    matches!(self.inst.imm, Imm::Cc(_))
                        && self.m.types.is_float(self.t(0))
                        && self.t(1) == self.t(0)
                        && self.res == Some(Ty::BOOL),
                    "fcmp compares two floats and yields bool",
                )
            }
            Op::Select => {
                self.arity(3)?;
                self.want(
                    self.t(0) == Ty::BOOL
                        && self.t(1) == self.t(2)
                        && self.res == Some(self.t(1))
                        && !self.v.needs_drop(self.t(1)),
                    "select takes bool, two equal non-reference values",
                )
            }
            _ => unreachable!("comparisons is only called for its own ops"),
        }
    }

    /// Float arithmetic and numeric conversions.
    fn float_ops(&self) -> Result<(), String> {
        match self.inst.op {
            Op::FAdd | Op::FSub | Op::FMul | Op::FDiv => {
                self.arity(2)?;
                self.want(
                    self.m.types.is_float(self.t(0))
                        && self.t(1) == self.t(0)
                        && self.res == Some(self.t(0)),
                    "operands and result must be one float type",
                )
            }
            Op::FNeg | Op::FSqrt | Op::FAbs | Op::FFloor | Op::FCeil | Op::FTrunc => {
                self.arity(1)?;
                self.want(
                    self.m.types.is_float(self.t(0)) && self.res == Some(self.t(0)),
                    "operand and result must be one float type",
                )
            }
            Op::I2F => {
                self.arity(1)?;
                self.want(
                    self.m.types.is_int(self.t(0))
                        && self.res.is_some_and(|r| self.m.types.is_float(r)),
                    "i2f converts an int type to a float type",
                )
            }
            Op::F2IOpt => {
                self.arity(1)?;
                let opt = self.res.and_then(|r| self.m.opt_inner(r));
                self.want(
                    self.m.types.is_float(self.t(0)) && opt == Some(Ty::INT),
                    "f2i.opt converts float to opt<int>",
                )
            }
            Op::B2I => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::BOOL && self.res == Some(Ty::INT),
                    "b2i converts bool to int",
                )
            }
            _ => unreachable!("float_ops is only called for its own ops"),
        }
    }

    /// Type operations.
    fn type_ops(&self) -> Result<(), String> {
        match self.inst.op {
            Op::TypeNew => {
                let Imm::Type(r) = self.inst.imm else {
                    return Err("missing type".into());
                };
                let fields = self.m.field_types(self.inst.imm).ok_or("bad type")?;
                if self.n != fields.len() {
                    return Err(format!(
                        "type {} has {} fields, found {} operands",
                        self.m.type_defs[r.index()].name,
                        fields.len(),
                        self.n
                    ));
                }
                for (i, ft) in fields.iter().enumerate() {
                    if self.t(i) != *ft {
                        return Err(self.mismatch(
                            &format!("field {}", self.m.type_defs[r.index()].fields[i].0),
                            self.t(i),
                            *ft,
                        ));
                    }
                }
                self.want(
                    self.res
                        .map(|r| matches!(self.m.types.kind(r), TyKind::Type(x) if *x == r_id(self.inst)))
                        .unwrap_or(false),
                    "type.new yields the type",
                )
            }
            Op::TypeGet | Op::TypeSet | Op::TypeFill => {
                let Imm::Field(r, i) = self.inst.imm else {
                    return Err("missing field".into());
                };
                let tval = self.m.type_defs.get(r.index()).ok_or("bad type")?;
                let fty = tval.fields.get(i as usize).ok_or("bad field index")?.1;
                if !matches!(self.m.types.kind(self.t(0)), TyKind::Type(x) if *x == r) {
                    return Err(format!("operand 0 must be type {}", tval.name));
                }
                if self.inst.op == Op::TypeGet {
                    self.arity(1)?;
                    self.want(self.res == Some(fty), "type.get yields the field type")
                } else {
                    self.arity(2)?;
                    self.want(
                        self.t(1) == fty && self.res == Some(self.t(0)),
                        "stored value must have the field type; yields the updated type",
                    )
                }
            }
            Op::TypeRelease => {
                self.arity(1)?;
                let Imm::TypeMask(r, _) = self.inst.imm else {
                    return Err("missing field mask".into());
                };
                self.want(
                    r.index() < self.m.type_defs.len()
                        && self.m.type_defs[r.index()].fields.len() <= 32
                        && self.m.types.kind(self.t(0)) == &TyKind::Type(r)
                        && self.res.is_none(),
                    "type.release takes a type with at most 32 fields",
                )
            }
            _ => unreachable!("types is only called for its own ops"),
        }
    }

    /// Alternatives.
    fn alternatives(&self) -> Result<(), String> {
        match self.inst.op {
            Op::AltNew | Op::AltView => {
                let Imm::Case(a, c) = self.inst.imm else {
                    return Err("missing case".into());
                };
                let fields = self.m.field_types(self.inst.imm).ok_or("bad case")?;
                if self.n != fields.len() {
                    return Err(format!(
                        "case {} has {} fields, found {} operands",
                        self.m.alts[a.index()].cases[c as usize].name,
                        fields.len(),
                        self.n
                    ));
                }
                for (i, ft) in fields.iter().enumerate() {
                    if self.t(i) != *ft {
                        return Err(self.mismatch(&format!("field {i}"), self.t(i), *ft));
                    }
                }
                self.want(
                    self.res
                        .map(|r| matches!(self.m.types.kind(r), TyKind::Alt(x) if *x == a))
                        .unwrap_or(false),
                    "alt.new yields the alternative type",
                )?;
                // A borrowing variant lends exactly its borrowed cases: `alt.view` fills one, `alt.new` the others.
                let borrowed = self.m.alts[a.index()].borrowed;
                if borrowed != 0 {
                    self.want(
                    self.m.alts[a.index()].borrows(c as usize) == (self.inst.op == Op::AltView),
                    "a borrowing variant is filled by alt.view in its borrowed cases and alt.new in the others",
                )?;
                }
                // A boxed alternative holds its payload in a heap block, which a borrow cannot own.
                self.want(
                    self.inst.op == Op::AltNew || !Boxing::default().alt(self.m, a),
                    "alt.view cannot borrow a boxed alternative",
                )
            }
            Op::AltPlain => {
                self.arity(1)?;
                let (TyKind::Alt(x), Some(r)) = (self.m.types.kind(self.t(0)), self.res) else {
                    return Err("alt.plain takes a borrowing variant".into());
                };
                let TyKind::Alt(y) = self.m.types.kind(r) else {
                    return Err("alt.plain yields an alternative".into());
                };
                let (dx, dy) = (&self.m.alts[x.index()], &self.m.alts[y.index()]);
                self.want(
                    dx.borrowed != 0
                        && dy.borrowed == 0
                        && dx.name == dy.name
                        && dx.cases == dy.cases,
                    "alt.plain reads a borrowing variant as its ordinary alternative",
                )
            }
            Op::AltTag => {
                self.arity(1)?;
                self.want(
                    matches!(self.m.types.kind(self.t(0)), TyKind::Alt(_))
                        && self.res == Some(Ty::INT),
                    "alt.tag takes an alternative and yields int",
                )
            }
            Op::AltRelease => {
                self.arity(1)?;
                let Imm::AltMask(a, c, _) = self.inst.imm else {
                    return Err("missing case mask".into());
                };
                let case = self
                    .m
                    .alts
                    .get(a.index())
                    .and_then(|x| x.cases.get(c as usize))
                    .ok_or("bad case")?;
                self.want(
                    !self.m.alts[a.index()].borrows(c as usize),
                    "alt.release of a borrowed case would free a payload another value owns",
                )?;
                self.want(
                    case.fields.len() <= 32
                        && matches!(self.m.types.kind(self.t(0)), TyKind::Alt(x) if *x == a)
                        && self.res.is_none(),
                    "alt.release takes an alternative with at most 32 payload fields",
                )
            }
            Op::AltGet | Op::AltUnbox | Op::AltTake => {
                self.arity(1)?;
                let Imm::AltField(a, c, i) = self.inst.imm else {
                    return Err("missing case field".into());
                };
                let case = self
                    .m
                    .alts
                    .get(a.index())
                    .and_then(|x| x.cases.get(c as usize))
                    .ok_or("bad case")?;
                let fty = case.fields.get(i as usize).ok_or("bad field index")?.1;
                self.want(
                    self.inst.op != Op::AltTake && self.inst.op != Op::AltUnbox
                        || !self.m.alts[a.index()].borrows(c as usize),
                    "a borrowed case cannot be taken: its payload belongs to another value",
                )?;
                self.want(
                    matches!(self.m.types.kind(self.t(0)), TyKind::Alt(x) if *x == a)
                        && self.res == Some(fty),
                    "alt.get yields the payload field type",
                )
            }
            _ => unreachable!("alternatives is only called for its own ops"),
        }
    }

    /// Lists.
    fn lists(&self) -> Result<(), String> {
        match self.inst.op {
            Op::ListNew => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::INT && self.res.and_then(|r| self.m.list_elem(r)).is_some(),
                    "list.new takes a capacity and yields a list",
                )
            }
            Op::ListLit => {
                let elem = self
                    .res
                    .and_then(|r| self.m.list_elem(r))
                    .ok_or("list.lit yields a list")?;
                for i in 0..self.n {
                    if self.t(i) != elem {
                        return Err(self.mismatch("element", self.t(i), elem));
                    }
                }
                Ok(())
            }
            Op::ListConst => {
                self.arity(0)?;
                let elem = self
                    .res
                    .and_then(|r| self.m.list_elem(r))
                    .ok_or("list.const yields a list")?;
                let scalar = matches!(
                    self.m.types.kind(elem),
                    TyKind::Bool
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
                );
                match self.inst.imm {
                    Imm::Int(i) if scalar && (i as usize) < self.m.list_consts.len() => Ok(()),
                    _ => Err("list.const names constant data of a scalar element type".into()),
                }
            }
            Op::ListLen => {
                self.arity(1)?;
                self.want(
                    (self.m.list_elem(self.t(0)).is_some() || self.t(0) == Ty::BYTES)
                        && self.res == Some(Ty::INT),
                    "list.len takes a list (or bytes) and yields int",
                )
            }
            Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake => {
                self.arity(2)?;
                let elem = self
                    .m
                    .seq_elem(self.t(0))
                    .ok_or("operand 0 must be a list")?;
                self.want(
                    self.t(1) == Ty::INT && self.res == Some(elem),
                    "index must be int; result is the element type",
                )
            }
            Op::ListRelease => {
                self.arity(2)?;
                self.m
                    .list_elem(self.t(0))
                    .ok_or("operand 0 must be a list")?;
                self.want(
                    self.t(1) == Ty::INT && self.res.is_none(),
                    "the first kept index must be int; no result",
                )
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                self.arity(3)?;
                let elem = self
                    .m
                    .list_elem(self.t(0))
                    .ok_or("operand 0 must be a list")?;
                self.want(
                    self.t(1) == Ty::INT && self.t(2) == elem && self.res == Some(self.t(0)),
                    "index must be int; value must be the element type; yields the updated list",
                )
            }
            Op::ListPush => {
                self.arity(2)?;
                let elem = self
                    .m
                    .list_elem(self.t(0))
                    .ok_or("operand 0 must be a list")?;
                self.want(
                    self.t(1) == elem && self.res == Some(self.t(0)),
                    "value must be the element type; yields the updated list",
                )
            }
            Op::ListDropLast => {
                self.arity(1)?;
                self.m
                    .list_elem(self.t(0))
                    .ok_or("operand 0 must be a list")?;
                self.want(self.res == Some(self.t(0)), "yields the shortened list")
            }
            _ => unreachable!("lists is only called for its own ops"),
        }
    }

    /// Optionals.
    fn optionals(&self) -> Result<(), String> {
        match self.inst.op {
            Op::OptSome | Op::OptView => {
                self.arity(1)?;
                self.want(
                    self.res.and_then(|r| self.m.opt_inner(r)) == Some(self.t(0)),
                    "optional constructors wrap their operand",
                )?;
                // A boxed optional holds its payload in a heap block, which a borrow cannot own.
                self.want(
                    self.inst.op == Op::OptSome || !self.m.opt_is_boxed(self.t(0)),
                    "opt.view cannot borrow a boxed optional",
                )
            }
            Op::OptNone => {
                self.arity(0)?;
                self.want(
                    self.res.and_then(|r| self.m.opt_inner(r)).is_some(),
                    "opt.none yields an optional",
                )
            }
            Op::OptIsSome => {
                self.arity(1)?;
                self.want(
                    self.m.opt_inner(self.t(0)).is_some() && self.res == Some(Ty::BOOL),
                    "opt.is_some takes an optional and yields bool",
                )
            }
            Op::OptGet | Op::OptUnwrap | Op::OptUnbox => {
                self.arity(1)?;
                self.want(
                    self.m.opt_inner(self.t(0)).is_some()
                        && self.res == self.m.opt_inner(self.t(0)),
                    "yields the payload type",
                )
            }
            Op::OptAddr => {
                self.arity(1)?;
                self.want(
                    self.m.opt_inner(self.t(0)).is_some() && self.res == Some(Ty::PTR),
                    "opt.addr takes a present optional and yields a ptr to its payload",
                )
            }
            _ => unreachable!("optionals is only called for its own ops"),
        }
    }

    /// Strings.
    fn strings(&self) -> Result<(), String> {
        match self.inst.op {
            Op::StrLen => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::STR && self.res == Some(Ty::INT),
                    "str.len takes a string and yields int",
                )
            }
            Op::StrByte => {
                self.arity(2)?;
                self.want(
                    self.t(0) == Ty::STR && self.t(1) == Ty::INT && self.res == Some(Ty::INT),
                    "str.byte takes a string and a byte offset and yields int",
                )
            }
            Op::StrAsciiAt => {
                self.arity(2)?;
                self.want(
                    self.t(0) == Ty::STR && self.t(1) == Ty::INT && self.res == Some(Ty::INT),
                    "str.ascii_at takes a string and a scalar index and yields int",
                )
            }
            Op::StrAsciiLen => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::STR && self.res == Some(Ty::INT),
                    "str.ascii_len takes a string and yields int",
                )
            }
            Op::StrAscii => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::INT && self.res == Some(Ty::STR),
                    "str.ascii takes an ASCII byte and yields the shared one-character string",
                )
            }
            _ => unreachable!("strings is only called for its own ops"),
        }
    }

    /// Closures and interface views.
    fn closures_and_interfaces(&self) -> Result<(), String> {
        match self.inst.op {
            Op::ClosureNew => {
                let Imm::Func(g) = self.inst.imm else {
                    return Err("missing function".into());
                };
                let callee = self.m.funcs.get(g.index()).ok_or("bad function")?;
                let FuncKind::Closure { captures } = &callee.kind else {
                    return Err(format!("{} is not a closure function", callee.name));
                };
                if self.n != captures.len() {
                    return Err(format!(
                        "{} captures {} values, found {}",
                        callee.name,
                        captures.len(),
                        self.n
                    ));
                }
                for (i, c) in captures.iter().enumerate() {
                    if self.t(i) != *c {
                        return Err(self.mismatch("capture", self.t(i), *c));
                    }
                }
                let ps: Vec<Ty> = callee.params[1..].iter().map(|p| p.ty).collect();
                match self.res.map(|r| self.m.types.kind(r)) {
                    Some(TyKind::Fn(fp, fr)) if *fp == ps && *fr == callee.ret => Ok(()),
                    _ => Err("closure.new yields a function type matching the closure code".into()),
                }
            }
            Op::ClosureCap => {
                self.arity(1)?;
                let Imm::Idx(i) = self.inst.imm else {
                    return Err("missing index".into());
                };
                let FuncKind::Closure { captures } = &self.f.kind else {
                    return Err("closure.cap outside a closure function".into());
                };
                let c = captures
                    .get(i as usize)
                    .ok_or("capture index out of range")?;
                self.want(
                    self.t(0) == Ty::PTR && self.res == Some(*c),
                    "closure.cap reads the environment (ptr) and yields the capture type",
                )
            }
            Op::ClosureCapAddr => {
                self.arity(1)?;
                let Imm::Idx(i) = self.inst.imm else {
                    return Err("missing index".into());
                };
                let FuncKind::Closure { captures } = &self.f.kind else {
                    return Err("closure.cap_addr outside a closure function".into());
                };
                self.want(
                    self.t(0) == Ty::PTR
                        && self.res == Some(Ty::PTR)
                        && (i as usize) < captures.len(),
                    "closure.cap_addr takes the environment (ptr) and yields the capture's address",
                )
            }
            Op::IfaceNew | Op::IfaceBorrow => {
                self.arity(1)?;
                let Imm::Vtable(v) = self.inst.imm else {
                    return Err("missing vtable".into());
                };
                let vt = self.m.vtables.get(v.index()).ok_or("bad vtable")?;
                self.want(
                self.t(0) == vt.data_ty
                    && self.res
                        .map(|r| matches!(self.m.types.kind(r), TyKind::Iface(i) if *i == vt.iface))
                        .unwrap_or(false),
                "iface.new and iface.borrow wrap the vtable's data type",
            )
            }
            Op::IfaceView => {
                self.arity(1)?;
                self.want(
                    matches!(self.m.types.kind(self.t(0)), TyKind::Iface(_))
                        && self.res == Some(self.t(0)),
                    "iface.view takes an interface value and yields the same type",
                )
            }
            Op::IfaceIs => {
                self.arity(1)?;
                let Imm::Vtable(v) = self.inst.imm else {
                    return Err("missing vtable".into());
                };
                let vt = self.m.vtables.get(v.index()).ok_or("bad vtable")?;
                self.want(
                    matches!(self.m.types.kind(self.t(0)), TyKind::Iface(i) if *i == vt.iface)
                        && self.res == Some(Ty::BOOL),
                    "iface.is tests an interface value of the vtable's interface and yields bool",
                )
            }
            Op::IfaceData => {
                self.arity(1)?;
                self.want(
                    matches!(self.m.types.kind(self.t(0)), TyKind::Iface(_))
                        && self.res == Some(Ty::PTR),
                    "iface.data takes an interface and yields ptr",
                )
            }
            _ => unreachable!("closures_and_interfaces is only called for its own ops"),
        }
    }

    /// Calls.
    fn calls(&self) -> Result<(), String> {
        match self.inst.op {
            Op::Call => {
                let Imm::Func(g) = self.inst.imm else {
                    return Err("missing callee".into());
                };
                let callee = self.m.funcs.get(g.index()).ok_or("bad callee")?;
                if self.n != callee.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {}",
                        callee.name,
                        callee.params.len(),
                        self.n
                    ));
                }
                for (i, p) in callee.params.iter().enumerate() {
                    if self.t(i) != p.ty {
                        return Err(self.mismatch(&format!("argument {i}"), self.t(i), p.ty));
                    }
                }
                self.want(
                    self.res == Some(callee.ret),
                    "call yields the callee's result type",
                )
            }
            Op::CallInd => {
                if self.n == 0 {
                    return Err("call.ind needs a closure".into());
                }
                let TyKind::Fn(ps, r) = self.m.types.kind(self.t(0)) else {
                    return Err("operand 0 must be a closure".into());
                };
                if self.n - 1 != ps.len() {
                    return Err(format!(
                        "closure takes {} arguments, found {}",
                        ps.len(),
                        self.n - 1
                    ));
                }
                for (i, p) in ps.iter().enumerate() {
                    if self.t(i + 1) != *p {
                        return Err(self.mismatch(&format!("argument {i}"), self.t(i + 1), *p));
                    }
                }
                self.want(
                    self.res == Some(*r),
                    "call.ind yields the closure's result type",
                )
            }
            Op::CallRt => {
                let Imm::Ext(e) = self.inst.imm else {
                    return Err("missing runtime function".into());
                };
                let ext = self
                    .m
                    .externs
                    .get(e.index())
                    .ok_or("bad runtime function")?;
                if self.n != ext.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {}",
                        ext.name,
                        ext.params.len(),
                        self.n
                    ));
                }
                for (i, p) in ext.params.iter().enumerate() {
                    if self.t(i) != p.ty {
                        return Err(self.mismatch(&format!("argument {i}"), self.t(i), p.ty));
                    }
                }
                self.want(
                    self.res == Some(ext.ret),
                    "call.rt yields the declared result type",
                )
            }
            Op::CallMethod => {
                let Imm::Method(i, k) = self.inst.imm else {
                    return Err("missing method".into());
                };
                let sig = self
                    .m
                    .ifaces
                    .get(i.index())
                    .and_then(|x| x.methods.get(k as usize))
                    .ok_or("bad method")?;
                if self.n == 0
                    || !matches!(self.m.types.kind(self.t(0)), TyKind::Iface(x) if *x == i)
                {
                    return Err("operand 0 must be the interface value".into());
                }
                if self.n - 1 != sig.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {}",
                        sig.name,
                        sig.params.len(),
                        self.n - 1
                    ));
                }
                for (j, p) in sig.params.iter().enumerate() {
                    if self.t(j + 1) != *p {
                        return Err(self.mismatch(&format!("argument {j}"), self.t(j + 1), *p));
                    }
                }
                self.want(
                    self.res == Some(sig.ret),
                    "call.method yields the method's result type",
                )
            }
            _ => unreachable!("calls is only called for its own ops"),
        }
    }

    /// Ownership: clone, drop, move.
    fn ownership(&self) -> Result<(), String> {
        match self.inst.op {
            Op::Clone => {
                self.arity(1)?;
                // Copying a borrowing variant into itself would own what it must not drop: use alt.own.
                self.want(
                self.res == Some(self.t(0))
                    && self.v.needs_drop(self.t(0))
                    && !matches!(self.m.types.kind(self.t(0)), TyKind::Alt(a) if self.m.alts[a.index()].borrowed != 0),
                "copy duplicates a droppable value",
            )
            }
            Op::AltOwn => {
                self.arity(1)?;
                let (TyKind::Alt(x), Some(r)) = (self.m.types.kind(self.t(0)), self.res) else {
                    return Err("alt.own takes a borrowing variant".into());
                };
                let TyKind::Alt(y) = self.m.types.kind(r) else {
                    return Err("alt.own yields an alternative".into());
                };
                let (dx, dy) = (&self.m.alts[x.index()], &self.m.alts[y.index()]);
                self.want(
                    dx.borrowed != 0
                        && dy.borrowed == 0
                        && dx.name == dy.name
                        && dx.cases == dy.cases
                        && self.v.needs_drop(r),
                    "alt.own copies a borrowing variant into its ordinary alternative",
                )
            }
            Op::MoveOut => {
                self.arity(1)?;
                self.want(
                    self.res == Some(self.t(0)) && self.v.needs_drop(self.t(0)),
                    "move.out takes ownership of a droppable value",
                )
            }
            Op::Drop => {
                self.arity(1)?;
                self.want(self.v.needs_drop(self.t(0)), "drop takes a droppable value")
            }
            Op::DropIf => {
                self.arity(2)?;
                self.want(
                    self.t(0) == Ty::BOOL && self.v.needs_drop(self.t(1)),
                    "drop.if takes a flag and a droppable value",
                )
            }
            _ => unreachable!("ownership is only called for its own ops"),
        }
    }

    /// Raw memory: stack slots, pointers, loads and stores.
    fn memory(&self) -> Result<(), String> {
        match self.inst.op {
            Op::Slot => {
                self.arity(0)?;
                self.want(
                    matches!(self.inst.imm, Imm::Ty(_)) && self.res == Some(Ty::PTR),
                    "slot yields ptr",
                )
            }
            Op::ListAddr | Op::ListAddrU => {
                self.arity(2)?;
                self.want(
                    self.m.list_elem(self.t(0)).is_some()
                        && self.t(1) == Ty::INT
                        && self.res == Some(Ty::PTR),
                    "list.addr takes a list and an index and yields a ptr to the element",
                )
            }
            Op::PtrIsNull => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::PTR && self.res == Some(Ty::BOOL),
                    "ptr.is_null tests a ptr and yields bool",
                )
            }
            Op::PtrField => {
                self.arity(1)?;
                let Imm::Field(r, i) = self.inst.imm else {
                    return Err("missing field".into());
                };
                let tval = self.m.type_defs.get(r.index()).ok_or("bad type")?;
                if tval.fields.get(i as usize).is_none() {
                    return Err("bad field index".into());
                }
                self.want(
                    self.t(0) == Ty::PTR && self.res == Some(Ty::PTR),
                    "ptr.field takes a ptr and yields a ptr",
                )
            }
            Op::Load => {
                self.arity(1)?;
                let Imm::Ty(ty) = self.inst.imm else {
                    return Err("missing type".into());
                };
                self.want(
                    self.t(0) == Ty::PTR && self.res == Some(ty),
                    "load reads a value through a ptr; a droppable result is a borrow",
                )
            }
            Op::Take => {
                self.arity(1)?;
                let Imm::Ty(ty) = self.inst.imm else {
                    return Err("missing type".into());
                };
                self.want(
                    self.t(0) == Ty::PTR && self.res == Some(ty),
                    "take moves a value out of memory through a ptr; the result is owned",
                )
            }
            Op::Put => {
                self.arity(2)?;
                self.want(
                    self.t(0) == Ty::PTR,
                    "put moves an owned value into memory through a ptr",
                )
            }
            Op::Store => {
                self.arity(2)?;
                self.want(
                self.t(0) == Ty::PTR,
                "store writes a value through a ptr; the memory does not own a droppable value, it holds a borrow",
            )
            }
            Op::FuncAddr => {
                self.arity(0)?;
                let Imm::Func(g) = self.inst.imm else {
                    return Err("missing function".into());
                };
                self.want(
                    g.index() < self.m.funcs.len() && self.res == Some(Ty::PTR),
                    "func.addr yields the ptr of a function",
                )
            }
            Op::TypeDesc => {
                self.arity(0)?;
                self.want(
                    matches!(self.inst.imm, Imm::Ty(_)) && self.res == Some(Ty::PTR),
                    "typedesc yields ptr",
                )
            }
            _ => unreachable!("memory is only called for its own ops"),
        }
    }

    /// Runtime services: polling, cleanup stack, globals.
    /// Scope markers: `begin S P` (P is the parent scope plus one, 0 for none), `own v S K`
    /// (K 0 drops, 1 closes), `end S`.
    fn scope_markers(&self) -> Result<(), String> {
        let Imm::Scope(..) = self.inst.imm else {
            return Err("a scope marker takes scope numbers".into());
        };
        self.want(self.res.is_none(), "a scope marker has no result")?;
        match self.inst.op {
            Op::ScopeOwn => {
                self.arity(1)?;
                self.want(
                    self.v.needs_drop(self.t(0)),
                    "scope.own takes a value that needs a drop",
                )
            }
            _ => self.arity(0),
        }
    }

    fn runtime_services(&self) -> Result<(), String> {
        match self.inst.op {
            Op::Poll | Op::DepthEnter | Op::DepthLeave => self.arity(0),
            Op::CleanupRun => {
                self.arity(1)?;
                self.want(
                    self.t(0) == Ty::INT,
                    "cleanup.run takes the handle returned by cleanup.push",
                )
            }
            Op::CleanupPush => {
                self.arity(1)?;
                let Imm::Func(g) = self.inst.imm else {
                    return Err("missing closer".into());
                };
                let callee = self.m.funcs.get(g.index()).ok_or("bad closer")?;
                self.want(
                    callee.params.len() == 1
                        && callee.params[0].ty == self.t(0)
                        && self.res == Some(Ty::INT),
                    "closer takes the registered value; cleanup.push yields an int handle",
                )
            }
            Op::GlobalGet | Op::GlobalSet => {
                let Imm::Global(g) = self.inst.imm else {
                    return Err("missing global".into());
                };
                let gd = self.m.globals.get(g.index()).ok_or("bad global")?;
                if self.inst.op == Op::GlobalGet {
                    self.arity(0)?;
                    self.want(
                        self.res == Some(gd.ty),
                        "global.get yields the global's type",
                    )
                } else {
                    self.arity(1)?;
                    self.want(
                        self.t(0) == gd.ty,
                        "stored value must have the global's type",
                    )
                }
            }
            _ => unreachable!("runtime_services is only called for its own ops"),
        }
    }
}
