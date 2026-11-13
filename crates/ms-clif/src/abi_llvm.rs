//! The calling convention of directly emitted LLVM functions.
//!
//! One design for types, lists, glue and closures. A value of at most [`SCALAR_BYTES`] bytes
//! (by `mem_layout`, so layout, runtime and the Cranelift object agree) is passed as scalars, so
//! a `String` is two parameters. Anything larger is indirect: a pointer to the caller's slot.
//!
//! - Borrow, indirect: `ptr nonnull readonly nocapture align A dereferenceable(N)`. No `noalias`
//!   until the borrow rules are proven for `scoped` closures.
//! - Move, indirect: a pointer to a temporary the caller owns and no longer uses,
//!   `ptr nonnull nocapture noalias align A dereferenceable(N)`. No `byval`: a clone is always an
//!   explicit call, never a copy the move would hide.
//! - Var, scalar or indirect: the same pointer to the variable's slot, updated in place. The
//!   final value MIR returns after the result becomes a store at each `ret`.
//! - Result: scalars up to the threshold, else a hidden first parameter
//!   `ptr sret(%T) noalias nocapture nonnull align A dereferenceable(N)`.
//!
//! Boundary: a function whose address escapes, which the runtime calls, or which a translated
//! function calls, keeps a thunk with the leaf signature that forwards to the internal native
//! body `@"f.n"`; direct calls name `@"f.n"`. The runtime's `msrt_*` entry points keep the C leaf
//! ABI.

#![allow(
    dead_code,
    reason = "the direct emitter adopts this in the types and glue follow-ups; remove then"
)]

use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::Types;
use ms_mir::ir::{Mode, Param};
use ms_mir::types::{Ty, TyKind};

/// Values up to this many bytes travel as scalars. A start; change it only by measurement.
pub const SCALAR_BYTES: u32 = 16;

/// An LLVM scalar a leaf is passed as.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Reg {
    /// `i64`: integers, sized integers widened to registers, pointers.
    I64,
    /// `double`.
    F64,
    /// `i8`: booleans and presence flags.
    I8,
    /// `ptr`: a leaf that is an address (see `Layouts::pointer_leaves`).
    Ptr,
}

impl Reg {
    /// The register a leaf is held in.
    pub fn of(leaf: Leaf) -> Reg {
        match leaf {
            Leaf::F64 | Leaf::F32 => Reg::F64,
            Leaf::I8 => Reg::I8,
            _ => Reg::I64,
        }
    }

    /// The LLVM type name.
    pub fn llvm(self) -> &'static str {
        match self {
            Reg::I64 => "i64",
            Reg::F64 => "double",
            Reg::I8 => "i8",
            Reg::Ptr => "ptr",
        }
    }
}

/// Size and alignment of an indirect value.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Mem {
    /// Size in bytes.
    pub size: u32,
    /// Alignment in bytes.
    pub align: u32,
}

/// How one parameter is passed.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Pass {
    /// One parameter per register; empty for `Unit`.
    Scalars(Vec<Reg>),
    /// A pointer to the value's slot, with the access the callee has to it.
    Indirect(Mode, Mem),
}

/// How a result comes back.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Ret {
    /// `void` for no registers, the type for one, an anonymous struct for more.
    Scalars(Vec<Reg>),
    /// Written through a hidden first parameter.
    Sret(Mem),
}

/// The size and alignment of the registers spilled to memory: a literal struct of `i64`,
/// `double`, `i8` and `ptr` fields, which is also what a type in memory is.
fn mem_of(regs: &[Reg]) -> Mem {
    let leaves: Vec<Leaf> = regs
        .iter()
        .map(|r| match r {
            Reg::I8 => Leaf::I8,
            Reg::F64 => Leaf::F64,
            Reg::I64 | Reg::Ptr => Leaf::I64,
        })
        .collect();
    let m = mem_layout(&leaves);
    Mem {
        size: m.size,
        align: m.align,
    }
}

fn regs(leaves: &[Leaf]) -> Vec<Reg> {
    leaves.iter().copied().map(Reg::of).collect()
}

/// The registers of a value of type `ty`: its leaves, with the pointer ones as `ptr`.
pub fn regs_of(lay: &Layouts, ty: Ty) -> Vec<Reg> {
    let mut r = regs(&lay.leaves(ty));
    for (reg, ptr) in r.iter_mut().zip(lay.pointer_leaves(ty)) {
        if ptr {
            *reg = Reg::Ptr;
        }
    }
    r
}

fn pass_regs(regs: Vec<Reg>, mode: Mode) -> Pass {
    let mem = mem_of(&regs);
    if mode == Mode::Var || mem.size > SCALAR_BYTES {
        Pass::Indirect(mode, mem)
    } else {
        Pass::Scalars(regs)
    }
}

fn ret_regs(regs: Vec<Reg>) -> Ret {
    let mem = mem_of(&regs);
    if mem.size > SCALAR_BYTES {
        Ret::Sret(mem)
    } else {
        Ret::Scalars(regs)
    }
}

/// How a parameter with these leaves is passed.
pub fn classify_leaves(leaves: &[Leaf], mode: Mode) -> Pass {
    pass_regs(regs(leaves), mode)
}

/// How a result with these leaves comes back.
pub fn ret_leaves(leaves: &[Leaf]) -> Ret {
    ret_regs(regs(leaves))
}

/// How a parameter of type `ty` is passed in `mode`.
pub fn classify(lay: &Layouts, ty: Ty, mode: Mode) -> Pass {
    pass_regs(regs_of(lay, ty), mode)
}

/// How a result of type `ty` comes back.
pub fn ret(lay: &Layouts, ty: Ty) -> Ret {
    ret_regs(regs_of(lay, ty))
}

impl Mem {
    fn access(self) -> String {
        format!("align {} dereferenceable({})", self.align, self.size)
    }
}

/// The attributes of an indirect parameter, after its `ptr` type.
pub fn param_attrs(mode: Mode, mem: Mem) -> String {
    let head = match mode {
        Mode::Borrow => "nonnull readonly nocapture",
        Mode::Move | Mode::Var => "nonnull nocapture noalias",
    };
    format!("{head} {}", mem.access())
}

/// The attributes of the hidden result pointer, after its `ptr` type; `ty` is the struct type.
pub fn sret_attrs(ty: &str, mem: Mem) -> String {
    format!("sret({ty}) noalias nocapture nonnull {}", mem.access())
}

/// One parameter of a function as it is written: its type with attributes, and its name.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Formal {
    /// `i64`, `double`, `i8 zeroext` or `ptr nonnull readonly nocapture align 8 dereferenceable(24)`.
    pub ty: String,
    /// The local name inside the function: `%a{i}_{j}` for a scalar, `%a{i}` for a pointer,
    /// `%sret` for the hidden result pointer.
    pub name: String,
}

/// The signature of a function in the native convention. Built once, it prints the `define`
/// pieces and every `declare`, so the two cannot drift apart.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Signature {
    /// The result, as written after `define`/`declare`: `void`, `i64`, `zeroext i8`, `{ i64, i64 }`.
    pub ret: String,
    /// The hidden result pointer first, then each parameter's pieces in order.
    pub params: Vec<Formal>,
    /// How each MIR parameter is passed, in order.
    pub passes: Vec<Pass>,
    /// How the result comes back.
    pub result: Ret,
}

fn reg_formal(r: Reg, name: String) -> Formal {
    let ty = match r {
        Reg::I8 => "i8 zeroext".to_string(),
        r => r.llvm().to_string(),
    };
    Formal { ty, name }
}

/// A fact about register `j` of a value of type `ty`, beyond its width: `Bool` is 0 or 1 and a
/// list's or bytes' length is not negative, an enum's case index is below its case count (the range wraps: it is `[0, 2^63)`).
fn range_attr(lay: &Layouts, ty: Ty, j: usize) -> &'static str {
    match (lay.m.types.kind(ty), j) {
        (TyKind::Bool, 0) => " range(i8 0, 2)",
        (TyKind::Bytes | TyKind::List(_), 1) => " range(i64 0, -9223372036854775808)",
        // An inline enum starts with its case index.
        (TyKind::Alt(a), 0) if !lay.is_boxed(*a) => {
            crate::mir_llvm::tag_attr(lay.m.alts[a.index()].cases.len())
        }
        _ => "",
    }
}

impl Signature {
    /// The signature of a function with these MIR parameters and result. `exclusive` lists the
    /// pointer parameters nothing else the function reaches overlaps (`Func::noalias`).
    pub fn of(
        types: &Types,
        lay: &Layouts,
        params: &[Param],
        exclusive: &[u32],
        ret_ty: Ty,
    ) -> Signature {
        let result = ret(lay, ret_ty);
        let mut formals = Vec::new();
        let ret = match &result {
            Ret::Sret(mem) => {
                let st = types.text(&crate::mir_llvm::aggregate(types, lay, ret_ty));
                formals.push(Formal {
                    ty: format!("ptr {}", sret_attrs(&st, *mem)),
                    name: "%sret".to_string(),
                });
                "void".to_string()
            }
            Ret::Scalars(r) => match r.as_slice() {
                [] => "void".to_string(),
                [Reg::I8] => format!("zeroext{} i8", range_attr(lay, ret_ty, 0)),
                [one] => one.llvm().to_string(),
                many => {
                    let tys: Vec<&str> = many.iter().map(|r| r.llvm()).collect();
                    format!("{{ {} }}", tys.join(", "))
                }
            },
        };
        let mut passes = Vec::new();
        for (i, p) in params.iter().enumerate() {
            let pass = classify(lay, p.ty, p.mode);
            match &pass {
                Pass::Scalars(regs) => {
                    for (j, r) in regs.iter().enumerate() {
                        let mut f = reg_formal(*r, format!("%a{i}_{j}"));
                        f.ty.push_str(range_attr(lay, p.ty, j));
                        if *r == Reg::Ptr && exclusive.contains(&(i as u32)) {
                            f.ty.push_str(" noalias");
                        }
                        formals.push(f);
                    }
                }
                Pass::Indirect(mode, mem) => formals.push(Formal {
                    ty: format!("ptr {}", param_attrs(*mode, *mem)),
                    name: format!("%a{i}"),
                }),
            }
            passes.push(pass);
        }
        Signature {
            ret,
            params: formals,
            passes,
            result,
        }
    }

    /// The parameter list of a `define`.
    pub fn define_params(&self) -> String {
        let parts: Vec<String> = self
            .params
            .iter()
            .map(|f| format!("{} {}", f.ty, f.name))
            .collect();
        parts.join(", ")
    }

    /// `declare <ret> @"sym"(<types>)` followed by `attrs`.
    pub fn declare(&self, sym: &str, attrs: &str) -> String {
        let tys: Vec<&str> = self.params.iter().map(|f| f.ty.as_str()).collect();
        format!("declare {} @\"{sym}\"({}){attrs}", self.ret, tys.join(", "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STRING: [Leaf; 2] = [Leaf::I64, Leaf::I64];
    const LIST: [Leaf; 3] = [Leaf::I64, Leaf::I64, Leaf::I64];

    #[test]
    fn a_string_is_two_scalars() {
        assert_eq!(
            classify_leaves(&STRING, Mode::Borrow),
            Pass::Scalars(vec![Reg::I64, Reg::I64])
        );
        assert_eq!(ret_leaves(&STRING), Ret::Scalars(vec![Reg::I64, Reg::I64]));
    }

    #[test]
    fn a_list_is_indirect() {
        let mem = Mem { size: 24, align: 8 };
        assert_eq!(
            classify_leaves(&LIST, Mode::Move),
            Pass::Indirect(Mode::Move, mem)
        );
        assert_eq!(ret_leaves(&LIST), Ret::Sret(mem));
    }

    #[test]
    fn the_threshold_counts_padding() {
        // 8 + 1 rounds up to 16: still scalars. 8 + 8 + 1 rounds up to 24.
        let two = [Leaf::I64, Leaf::I8];
        let three = [Leaf::I64, Leaf::I64, Leaf::I8];
        assert!(matches!(
            classify_leaves(&two, Mode::Borrow),
            Pass::Scalars(_)
        ));
        assert!(matches!(
            classify_leaves(&three, Mode::Borrow),
            Pass::Indirect(..)
        ));
    }

    #[test]
    fn a_var_is_always_a_pointer() {
        let mem = Mem { size: 8, align: 8 };
        assert_eq!(
            classify_leaves(&[Leaf::I64], Mode::Var),
            Pass::Indirect(Mode::Var, mem)
        );
    }

    #[test]
    fn unit_is_no_parameters() {
        assert_eq!(classify_leaves(&[], Mode::Borrow), Pass::Scalars(vec![]));
        assert_eq!(ret_leaves(&[]), Ret::Scalars(vec![]));
    }

    #[test]
    fn sized_integers_and_floats_ride_registers() {
        assert_eq!(Reg::of(Leaf::U8), Reg::I64);
        assert_eq!(Reg::of(Leaf::F32), Reg::F64);
        assert_eq!(Reg::of(Leaf::I8), Reg::I8);
    }

    #[test]
    fn a_register_formal_widens_a_bool() {
        assert_eq!(reg_formal(Reg::I8, "%a0_0".into()).ty, "i8 zeroext");
        assert_eq!(reg_formal(Reg::F64, "%a0_1".into()).ty, "double");
    }

    #[test]
    fn attributes_match_the_convention() {
        let mem = Mem { size: 24, align: 8 };
        assert_eq!(
            param_attrs(Mode::Borrow, mem),
            "nonnull readonly nocapture align 8 dereferenceable(24)"
        );
        assert_eq!(
            param_attrs(Mode::Move, mem),
            "nonnull nocapture noalias align 8 dereferenceable(24)"
        );
        assert_eq!(param_attrs(Mode::Var, mem), param_attrs(Mode::Move, mem));
        assert_eq!(
            sret_attrs("%List", mem),
            "sret(%List) noalias nocapture nonnull align 8 dereferenceable(24)"
        );
    }
}
