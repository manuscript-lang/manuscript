//! A small typed builder for textual LLVM IR.
//!
//! The direct MIR emitter (`mir_llvm`) writes IR through this instead of formatting strings. Every
//! value carries its type; operations check their operand types; `load`, `store`, `alloca` and
//! `memcpy` take an explicit alignment, so none can be forgotten (LLVM's own builders default to a
//! pessimistic one, which blocks vectorization). Struct types are named and laid out once, with
//! offsets that match `layout::mem_layout`. The output is the text the pinned `opt` and `llc`
//! read, so it joins the rest of the release pipeline unchanged.

#![allow(
    dead_code,
    reason = "stage 2 (records and memory) uses the rest of the builder"
)]

use std::cell::RefCell;
use std::fmt::Write as _;

/// The alias class of a memory access, which LLVM's type-based alias analysis uses to tell that
/// a scalar element store cannot overwrite a list or string header word.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tbaa {
    /// A list element that is one scalar word.
    ScalarElem,
    /// A list element that is a list or string header.
    HeaderElem,
}

/// The values an integer load can take, as `!range`.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Range {
    /// A `Bool` byte: 0 or 1.
    Bool,
    /// A length or count: not negative.
    Len,
}

/// Facts about the memory a load reads or a store writes. Each is a promise about the program,
/// not a hint: a wrong one makes the result poison or the code wrong.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct Meta {
    /// The alias class, `!tbaa`.
    pub tbaa: Option<Tbaa>,
    /// The value range of an integer load, `!range`.
    pub range: Option<Range>,
    /// A loaded pointer is not null, `!nonnull`.
    pub nonnull: bool,
    /// A loaded value is never `undef` or `poison`, `!noundef`.
    pub noundef: bool,
}

impl Meta {
    /// `, !tbaa !N, !range !N, ...` for an access of type `ty`; `load` is whether it reads.
    fn text(&self, ty: &Ty, load: bool) -> String {
        use crate::llvm_ir::{
            EMPTY_NODE, RANGE_BOOL_NODE, RANGE_LEN_NODE, TBAA_HEADER_ELEM_NODE,
            TBAA_SCALAR_ELEM_NODE,
        };
        let mut out = String::new();
        if let Some(t) = self.tbaa {
            let node = match t {
                Tbaa::ScalarElem => TBAA_SCALAR_ELEM_NODE,
                Tbaa::HeaderElem => TBAA_HEADER_ELEM_NODE,
            };
            let _ = write!(out, ", !tbaa !{node}");
        }
        if load {
            if let Some(r) = self.range {
                let (node, want) = match r {
                    Range::Bool => (RANGE_BOOL_NODE, Ty::I8),
                    Range::Len => (RANGE_LEN_NODE, Ty::I64),
                };
                assert_eq!(*ty, want, "a range on a load of another type");
                let _ = write!(out, ", !range !{node}");
            }
            if self.nonnull {
                assert_eq!(*ty, Ty::Ptr, "!nonnull on a load that is not a pointer");
                let _ = write!(out, ", !nonnull !{EMPTY_NODE}");
            }
            if self.noundef {
                let _ = write!(out, ", !noundef !{EMPTY_NODE}");
            }
        }
        out
    }
}

/// An LLVM type.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Ty {
    Void,
    I1,
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    Ptr,
    /// A named struct from [`Types`].
    Struct(usize),
    Array(Box<Ty>, u64),
    /// An anonymous struct `{ a, b }`: the result of a call that returns several leaves.
    Tuple(Vec<Ty>),
}

/// A named struct type: fields laid out in order with natural alignment.
#[derive(Clone, Debug)]
pub struct StructDef {
    pub name: String,
    pub fields: Vec<Ty>,
}

/// The struct types of a module. One value is shared by every function of the module (each
/// function's builder borrows it), so a struct named once is the same type everywhere; the
/// definitions are written once at the end of the module.
#[derive(Default, Debug)]
pub struct Types {
    structs: RefCell<Vec<StructDef>>,
}

impl Types {
    /// Declares a struct and returns its type.
    pub fn add_struct(&self, name: &str, fields: Vec<Ty>) -> Ty {
        let mut structs = self.structs.borrow_mut();
        structs.push(StructDef {
            name: name.to_string(),
            fields,
        });
        Ty::Struct(structs.len() - 1)
    }

    /// The struct called `name` with these `fields`, declared on first use. A name taken by a
    /// struct of other fields gets a numeric suffix, so two records of one name stay distinct.
    pub fn named(&self, name: &str, fields: Vec<Ty>) -> Ty {
        let found = {
            let structs = self.structs.borrow();
            let mut candidate = name.to_string();
            let mut n = 1;
            loop {
                match structs.iter().position(|d| d.name == candidate) {
                    Some(i) if structs[i].fields == fields => break Ok(i),
                    Some(_) => {
                        n += 1;
                        candidate = format!("{name}.{n}");
                    }
                    None => break Err(candidate),
                }
            }
        };
        match found {
            Ok(i) => Ty::Struct(i),
            Err(unused) => self.add_struct(&unused, fields),
        }
    }

    /// `%"name" = type { .. }` lines for every struct.
    pub fn definitions(&self) -> String {
        let mut s = String::new();
        for d in self.structs.borrow().iter() {
            let fields: Vec<String> = d.fields.iter().map(|f| self.text(f)).collect();
            let _ = writeln!(s, "%\"{}\" = type {{ {} }}", d.name, fields.join(", "));
        }
        s
    }

    /// The type as written in IR.
    pub fn text(&self, ty: &Ty) -> String {
        match ty {
            Ty::Void => "void".into(),
            Ty::I1 => "i1".into(),
            Ty::I8 => "i8".into(),
            Ty::I16 => "i16".into(),
            Ty::I32 => "i32".into(),
            Ty::I64 => "i64".into(),
            Ty::F32 => "float".into(),
            Ty::F64 => "double".into(),
            Ty::Ptr => "ptr".into(),
            Ty::Struct(i) => format!("%\"{}\"", self.structs.borrow()[*i].name),
            Ty::Array(e, n) => format!("[{n} x {}]", self.text(e)),
            Ty::Tuple(fs) => {
                let fs: Vec<String> = fs.iter().map(|f| self.text(f)).collect();
                format!("{{ {} }}", fs.join(", "))
            }
        }
    }

    /// Size and alignment in bytes.
    pub fn size_align(&self, ty: &Ty) -> (u64, u64) {
        match ty {
            Ty::Void => (0, 1),
            Ty::I1 | Ty::I8 => (1, 1),
            Ty::I16 => (2, 2),
            Ty::I32 | Ty::F32 => (4, 4),
            Ty::I64 | Ty::F64 | Ty::Ptr => (8, 8),
            Ty::Array(e, n) => {
                let (s, a) = self.size_align(e);
                (s * n, a)
            }
            Ty::Struct(_) | Ty::Tuple(_) => {
                let (mut off, mut align) = (0u64, 1u64);
                for f in &self.fields_of(ty) {
                    let (s, a) = self.size_align(f);
                    off = off.div_ceil(a) * a + s;
                    align = align.max(a);
                }
                (off.div_ceil(align) * align, align)
            }
        }
    }

    fn fields_of(&self, ty: &Ty) -> Vec<Ty> {
        match ty {
            Ty::Struct(i) => self.structs.borrow()[*i].fields.clone(),
            Ty::Tuple(fs) => fs.clone(),
            _ => panic!("fields of a non-struct"),
        }
    }

    /// Byte offset of field `idx` of struct `ty`.
    pub fn field_offset(&self, ty: &Ty, idx: usize) -> u64 {
        let Ty::Struct(i) = ty else {
            panic!("field_offset of a non-struct")
        };
        let mut off = 0u64;
        for (k, f) in self.structs.borrow()[*i].fields.iter().enumerate() {
            let (s, a) = self.size_align(f);
            off = off.div_ceil(a) * a;
            if k == idx {
                return off;
            }
            off += s;
        }
        panic!("field {idx} out of range")
    }

    fn field(&self, ty: &Ty, idx: usize) -> Ty {
        self.fields_of(ty)[idx].clone()
    }
}

/// An operand: its text (`%v3`, `42`, `0x..`, `@"f"`) and its type.
#[derive(Clone, PartialEq, Debug)]
pub struct Val {
    pub text: String,
    pub ty: Ty,
}

impl Val {
    pub fn new(text: impl Into<String>, ty: Ty) -> Val {
        Val {
            text: text.into(),
            ty,
        }
    }

    pub fn int(v: i64) -> Val {
        Val::new(v.to_string(), Ty::I64)
    }

    pub fn double(bits: u64) -> Val {
        Val::new(format!("0x{bits:016X}"), Ty::F64)
    }

    pub fn byte(v: u8) -> Val {
        Val::new(v.to_string(), Ty::I8)
    }
}

/// Integer and float binary operations.
#[derive(Clone, Copy, Debug)]
pub enum Bin {
    Add,
    Sub,
    Mul,
    And,
    Or,
    Xor,
    FAdd,
    FSub,
    FMul,
    FDiv,
    LShr,
    Shl,
}

impl Bin {
    fn name(self) -> &'static str {
        match self {
            Bin::Add => "add",
            Bin::Sub => "sub",
            Bin::Mul => "mul",
            Bin::And => "and",
            Bin::Or => "or",
            Bin::Xor => "xor",
            Bin::FAdd => "fadd",
            Bin::FSub => "fsub",
            Bin::FMul => "fmul",
            Bin::FDiv => "fdiv",
            Bin::LShr => "lshr",
            Bin::Shl => "shl",
        }
    }

    fn float(self) -> bool {
        matches!(self, Bin::FAdd | Bin::FSub | Bin::FMul | Bin::FDiv)
    }
}

/// Builds the body of one function.
pub struct FnBuilder<'t> {
    types: &'t Types,
    out: String,
    next: u32,
    /// Allocas, written at the top of the entry block.
    allocas: String,
    /// `, !dbg !N` appended to every instruction.
    dbg: Option<usize>,
    /// The name the next defined value takes, set by [`FnBuilder::name_next`].
    pending: Option<Val>,
}

impl<'t> FnBuilder<'t> {
    pub fn new(types: &'t Types, dbg: Option<usize>) -> Self {
        FnBuilder {
            types,
            out: String::new(),
            next: 0,
            allocas: String::new(),
            dbg,
            pending: None,
        }
    }

    /// A fresh value name of type `ty`, defined by the caller (a phi, or an instruction that is
    /// written later).
    pub fn reserve(&mut self, ty: Ty) -> Val {
        self.next += 1;
        Val::new(format!("%v{}", self.next), ty)
    }

    fn line(&mut self, text: String) {
        match self.dbg {
            Some(d) => {
                let _ = writeln!(self.out, "  {text}, !dbg !{d}");
            }
            None => {
                let _ = writeln!(self.out, "  {text}");
            }
        }
    }

    fn def(&mut self, ty: Ty, rhs: String) -> Val {
        let v = match self.pending.take() {
            Some(v) => {
                assert_eq!(v.ty, ty, "the reserved name has another type");
                v
            }
            None => self.reserve(ty),
        };
        self.line(format!("{} = {rhs}", v.text));
        v
    }

    fn ty(&self, t: &Ty) -> String {
        self.types.text(t)
    }

    /// Makes the next defined value take the reserved name `v` (a phi may already use it).
    pub fn name_next(&mut self, v: &Val) {
        assert!(self.pending.is_none(), "a reserved name is unused");
        self.pending = Some(v.clone());
    }

    /// Sets the `!dbg` node written on the following instructions.
    pub fn set_dbg(&mut self, dbg: Option<usize>) {
        self.dbg = dbg;
    }

    /// Takes the pending name back, for a caller that defines helper values first.
    pub fn take_name(&mut self) -> Option<Val> {
        self.pending.take()
    }

    /// Puts a name taken with [`FnBuilder::take_name`] back.
    pub fn restore_name(&mut self, v: Option<Val>) {
        self.pending = v;
    }

    /// Starts a block.
    /// The module's struct types.
    pub fn types(&self) -> &'t Types {
        self.types
    }

    pub fn label(&mut self, name: &str) {
        let _ = writeln!(self.out, "{name}:");
    }

    pub fn bin(&mut self, op: Bin, a: &Val, b: &Val) -> Val {
        assert_eq!(a.ty, b.ty, "{} operands differ", op.name());
        assert_eq!(
            op.float(),
            matches!(a.ty, Ty::F32 | Ty::F64),
            "{} on {:?}",
            op.name(),
            a.ty
        );
        self.def(
            a.ty.clone(),
            format!("{} {} {}, {}", op.name(), self.ty(&a.ty), a.text, b.text),
        )
    }

    pub fn fneg(&mut self, a: &Val) -> Val {
        self.def(a.ty.clone(), format!("fneg {} {}", self.ty(&a.ty), a.text))
    }

    /// `icmp`; `cc` is `eq`, `ne`, `slt`, `ult`, ...
    pub fn icmp(&mut self, cc: &str, a: &Val, b: &Val) -> Val {
        assert_eq!(a.ty, b.ty);
        self.def(
            Ty::I1,
            format!("icmp {cc} {} {}, {}", self.ty(&a.ty), a.text, b.text),
        )
    }

    /// `fcmp`; `cc` is `oeq`, `une`, `olt`, ...
    pub fn fcmp(&mut self, cc: &str, a: &Val, b: &Val) -> Val {
        assert_eq!(a.ty, b.ty);
        self.def(
            Ty::I1,
            format!("fcmp {cc} {} {}, {}", self.ty(&a.ty), a.text, b.text),
        )
    }

    pub fn zext(&mut self, v: &Val, to: Ty) -> Val {
        let from = self.ty(&v.ty);
        let rhs = format!("zext {from} {} to {}", v.text, self.ty(&to));
        self.def(to, rhs)
    }

    pub fn sext(&mut self, v: &Val, to: Ty) -> Val {
        let from = self.ty(&v.ty);
        let rhs = format!("sext {from} {} to {}", v.text, self.ty(&to));
        self.def(to, rhs)
    }

    pub fn trunc(&mut self, v: &Val, to: Ty) -> Val {
        let from = self.ty(&v.ty);
        let rhs = format!("trunc {from} {} to {}", v.text, self.ty(&to));
        self.def(to, rhs)
    }

    /// An `i64` address as a `ptr`.
    pub fn inttoptr(&mut self, v: &Val) -> Val {
        assert_eq!(v.ty, Ty::I64);
        self.def(Ty::Ptr, format!("inttoptr i64 {} to ptr", v.text))
    }

    pub fn ptrtoint(&mut self, v: &Val) -> Val {
        assert_eq!(v.ty, Ty::Ptr);
        self.def(Ty::I64, format!("ptrtoint ptr {} to i64", v.text))
    }

    /// `ptr` `off` bytes past `base`.
    pub fn gep_bytes(&mut self, base: &Val, off: u64) -> Val {
        assert_eq!(base.ty, Ty::Ptr);
        if off == 0 {
            return base.clone();
        }
        self.def(
            Ty::Ptr,
            format!("getelementptr inbounds i8, ptr {}, i64 {off}", base.text),
        )
    }

    pub fn select(&mut self, cond: &Val, a: &Val, b: &Val) -> Val {
        assert_eq!(cond.ty, Ty::I1);
        assert_eq!(a.ty, b.ty);
        self.def(
            a.ty.clone(),
            format!(
                "select i1 {}, {} {}, {} {}",
                cond.text,
                self.ty(&a.ty),
                a.text,
                self.ty(&b.ty),
                b.text
            ),
        )
    }

    /// `ptr` to field `idx` of a struct of type `ty` at `base`.
    pub fn field_ptr(&mut self, ty: &Ty, base: &Val, idx: usize) -> Val {
        assert_eq!(base.ty, Ty::Ptr);
        let _ = self.types.field(ty, idx);
        self.def(
            Ty::Ptr,
            format!(
                "getelementptr inbounds {}, ptr {}, i32 0, i32 {idx}",
                self.ty(ty),
                base.text
            ),
        )
    }

    /// `ptr` to element `index` of an array of `elem` at `base`.
    pub fn elem_ptr(&mut self, elem: &Ty, base: &Val, index: &Val) -> Val {
        assert_eq!(base.ty, Ty::Ptr);
        assert_eq!(index.ty, Ty::I64);
        self.def(
            Ty::Ptr,
            format!(
                "getelementptr inbounds {}, ptr {}, i64 {}",
                self.ty(elem),
                base.text,
                index.text
            ),
        )
    }

    /// A load with the alignment of `ty`, or the stricter `align` the caller knows.
    pub fn load(&mut self, ty: &Ty, ptr: &Val, align: u64) -> Val {
        self.load_with(ty, ptr, align, Meta::default())
    }

    /// A load carrying `meta`.
    pub fn load_with(&mut self, ty: &Ty, ptr: &Val, align: u64, meta: Meta) -> Val {
        assert_eq!(ptr.ty, Ty::Ptr);
        assert!(align.is_power_of_two());
        self.def(
            ty.clone(),
            format!(
                "load {}, ptr {}, align {align}{}",
                self.ty(ty),
                ptr.text,
                meta.text(ty, true)
            ),
        )
    }

    pub fn store(&mut self, val: &Val, ptr: &Val, align: u64) {
        self.store_with(val, ptr, align, Meta::default());
    }

    /// A store carrying `meta` (only its alias class applies to a store).
    pub fn store_with(&mut self, val: &Val, ptr: &Val, align: u64, meta: Meta) {
        assert_eq!(ptr.ty, Ty::Ptr);
        assert!(align.is_power_of_two());
        self.line(format!(
            "store {} {}, ptr {}, align {align}{}",
            self.ty(&val.ty),
            val.text,
            ptr.text,
            meta.text(&val.ty, false)
        ));
    }

    /// A stack slot for one `ty`, aligned for it; the `alloca` goes to the top of the entry block.
    pub fn alloca(&mut self, ty: &Ty) -> Val {
        let v = self.reserve(Ty::Ptr);
        self.alloca_as(&v, ty);
        v
    }

    /// Like [`FnBuilder::alloca`], with the slot named by the reserved pointer `v`.
    pub fn alloca_as(&mut self, v: &Val, ty: &Ty) {
        let (_, align) = self.types.size_align(ty);
        let _ = writeln!(
            self.allocas,
            "  {} = alloca {}, align {align}",
            v.text,
            self.ty(ty)
        );
    }

    /// Copies one `ty` from `src` to `dst` (non-overlapping), with its alignment.
    pub fn copy(&mut self, ty: &Ty, dst: &Val, src: &Val) {
        let (size, align) = self.types.size_align(ty);
        assert_eq!((&dst.ty, &src.ty), (&Ty::Ptr, &Ty::Ptr));
        self.line(format!(
            "call void @llvm.memcpy.p0.p0.i64(ptr align {align} {}, ptr align {align} {}, i64 {size}, i1 false)",
            dst.text, src.text
        ));
    }

    /// A call; `ret` is `Ty::Void` for none. `args` carry their parameter attributes in `attrs`
    /// (same length), such as `" zeroext"`. Calls from distinct source sites are never merged,
    /// which would lose the caller's fault frame; use [`FnBuilder::call_pure`] for a callee that
    /// cannot fault.
    pub fn call(
        &mut self,
        ret: &Ty,
        ret_attr: &str,
        callee: &str,
        args: &[(Val, &str)],
    ) -> Option<Val> {
        self.call_with(ret, ret_attr, callee, args, " nomerge")
    }

    /// A call to a callee proven pure (`memory(none)`, so it cannot fault): LLVM may merge,
    /// hoist and delete it like any other expression.
    pub fn call_pure(
        &mut self,
        ret: &Ty,
        ret_attr: &str,
        callee: &str,
        args: &[(Val, &str)],
    ) -> Option<Val> {
        self.call_with(ret, ret_attr, callee, args, "")
    }

    fn call_with(
        &mut self,
        ret: &Ty,
        ret_attr: &str,
        callee: &str,
        args: &[(Val, &str)],
        fn_attrs: &str,
    ) -> Option<Val> {
        let actuals: Vec<String> = args
            .iter()
            .map(|(v, a)| format!("{}{a} {}", self.ty(&v.ty), v.text))
            .collect();
        let head = format!(
            "call {ret_attr}{} @\"{callee}\"({}){fn_attrs}",
            self.ty(ret),
            actuals.join(", ")
        );
        if *ret == Ty::Void {
            self.line(head);
            None
        } else {
            Some(self.def(ret.clone(), head))
        }
    }

    /// Copies `len` bytes from `src` (aligned to `src_align`) to `dst` (aligned to `dst_align`),
    /// non-overlapping.
    pub fn memcpy(&mut self, dst: (&Val, u64), src: (&Val, u64), len: &Val) {
        let ((dst, dst_align), (src, src_align)) = (dst, src);
        assert_eq!((&dst.ty, &src.ty, &len.ty), (&Ty::Ptr, &Ty::Ptr, &Ty::I64));
        self.line(format!(
            "call void @llvm.memcpy.p0.p0.i64(ptr align {dst_align} {}, ptr align {src_align} {}, i64 {}, i1 false)",
            dst.text, src.text, len.text
        ));
    }

    /// A call returning several values as an anonymous struct, split into its parts.
    pub fn call_multi(&mut self, rets: &[Ty], callee: &str, args: &[(Val, &str)]) -> Vec<Val> {
        let actuals: Vec<String> = args
            .iter()
            .map(|(v, a)| format!("{}{a} {}", self.ty(&v.ty), v.text))
            .collect();
        let agg = self.agg(rets);
        let r = self.def(
            Ty::Void,
            format!("call {agg} @\"{callee}\"({})", actuals.join(", ")),
        );
        rets.iter()
            .enumerate()
            .map(|(i, t)| self.def(t.clone(), format!("extractvalue {agg} {}, {i}", r.text)))
            .collect()
    }

    /// Returns several values as an anonymous struct.
    pub fn ret_multi(&mut self, vals: &[Val]) {
        let tys: Vec<Ty> = vals.iter().map(|v| v.ty.clone()).collect();
        let agg = self.agg(&tys);
        let mut cur = "poison".to_string();
        for (i, v) in vals.iter().enumerate() {
            let t = self.reserve(Ty::Void);
            self.line(format!(
                "{} = insertvalue {agg} {cur}, {} {}, {i}",
                t.text,
                self.ty(&v.ty),
                v.text
            ));
            cur = t.text;
        }
        self.line(format!("ret {agg} {cur}"));
    }

    /// The text of the anonymous struct of `tys`.
    pub fn agg(&self, tys: &[Ty]) -> String {
        let parts: Vec<String> = tys.iter().map(|t| self.ty(t)).collect();
        format!("{{ {} }}", parts.join(", "))
    }

    /// Defines the reserved `dst` as a phi of `(value, block)` pairs.
    pub fn phi(&mut self, dst: &Val, incoming: &[(Val, String)]) {
        let edges: Vec<String> = incoming
            .iter()
            .map(|(v, b)| {
                assert_eq!(v.ty, dst.ty, "phi operand type");
                format!("[ {}, %{b} ]", v.text)
            })
            .collect();
        self.line(format!(
            "{} = phi {} {}",
            dst.text,
            self.ty(&dst.ty),
            edges.join(", ")
        ));
    }

    pub fn br(&mut self, block: &str) {
        self.line(format!("br label %{block}"));
    }

    /// A conditional branch whose `then` side is taken far more often than `els` (or the other
    /// way round), so the cold side is laid out away from the hot path.
    pub fn cond_br_likely(&mut self, cond: &Val, then: &str, els: &str, then_hot: bool) {
        assert_eq!(cond.ty, Ty::I1);
        let (a, b) = if then_hot { (2000, 1) } else { (1, 2000) };
        self.line(format!(
            "br i1 {}, label %{then}, label %{els}, !prof !{{!\"branch_weights\", i32 {a}, i32 {b}}}",
            cond.text
        ));
    }

    /// An empty inline asm taking the fault site number `n`: keeps fault sites distinct, so LLVM
    /// neither merges them (which drops the line of a fault in a trace) nor hoists them.
    pub fn fault_site(&mut self, n: u32) {
        self.line(format!("call void asm sideeffect \"\", \"i\"(i32 {n})"));
    }

    /// `inttoptr` of a pointer-sized integer leaf.
    /// `ptr` `offset` bytes past `base`; the instruction is written even for 0, so the result can
    /// take a reserved name.
    pub fn byte_ptr(&mut self, base: &Val, offset: u64) -> Val {
        assert_eq!(base.ty, Ty::Ptr);
        self.def(
            Ty::Ptr,
            format!("getelementptr inbounds i8, ptr {}, i64 {offset}", base.text),
        )
    }

    pub fn ptr_to_int(&mut self, v: &Val) -> Val {
        assert_eq!(v.ty, Ty::Ptr);
        self.def(Ty::I64, format!("ptrtoint ptr {} to i64", v.text))
    }

    /// Copies `size` bytes (non-overlapping) with the alignment both sides are known to have.
    pub fn copy_bytes(&mut self, dst: &Val, src: &Val, size: u64, align: u64) {
        assert_eq!((&dst.ty, &src.ty), (&Ty::Ptr, &Ty::Ptr));
        self.line(format!(
            "call void @llvm.memcpy.p0.p0.i64(ptr align {align} {}, ptr align {align} {}, i64 {size}, i1 false)",
            dst.text, src.text
        ));
    }

    pub fn int_to_ptr(&mut self, v: &Val) -> Val {
        assert_eq!(v.ty, Ty::I64);
        self.def(Ty::Ptr, format!("inttoptr i64 {} to ptr", v.text))
    }

    pub fn cond_br(&mut self, cond: &Val, then: &str, els: &str) {
        assert_eq!(cond.ty, Ty::I1);
        self.line(format!("br i1 {}, label %{then}, label %{els}", cond.text));
    }

    pub fn ret(&mut self, v: Option<&Val>) {
        match v {
            Some(v) => self.line(format!("ret {} {}", self.ty(&v.ty), v.text)),
            None => self.line("ret void".into()),
        }
    }

    pub fn unreachable(&mut self) {
        self.line("unreachable".into());
    }

    /// A tuple of `vals`, for a function that returns several leaves.
    pub fn tuple(&mut self, vals: &[Val]) -> Val {
        let ty = Ty::Tuple(vals.iter().map(|v| v.ty.clone()).collect());
        let mut agg = Val::new("poison", ty.clone());
        for (i, v) in vals.iter().enumerate() {
            let last = i + 1 == vals.len();
            let rhs = format!(
                "insertvalue {} {}, {} {}, {i}",
                self.ty(&ty),
                agg.text,
                self.ty(&v.ty),
                v.text
            );
            agg = if last {
                self.def(ty.clone(), rhs)
            } else {
                let saved = self.pending.take();
                let t = self.def(ty.clone(), rhs);
                self.pending = saved;
                t
            };
        }
        agg
    }

    /// Leaf `idx` of a tuple.
    pub fn extract(&mut self, agg: &Val, idx: usize) -> Val {
        let Ty::Tuple(fs) = &agg.ty else {
            panic!("extract from a non-tuple")
        };
        let ty = fs[idx].clone();
        self.def(
            ty,
            format!("extractvalue {} {}, {idx}", self.ty(&agg.ty), agg.text),
        )
    }

    /// The body: the entry label, the allocas, then everything else, closed with `}`.
    pub fn finish(self) -> String {
        let (first, rest) = self
            .out
            .split_once('\n')
            .expect("a body starts with a label");
        format!("{first}\n{}{rest}}}\n\n", self.allocas)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_and_stores_carry_their_metadata() {
        use crate::llvm_ir::{RANGE_BOOL_NODE, TBAA_SCALAR_ELEM_NODE};
        let types = Types::default();
        let mut b = FnBuilder::new(&types, None);
        let p = b.reserve(Ty::Ptr);
        let meta = Meta {
            tbaa: Some(Tbaa::ScalarElem),
            range: Some(Range::Bool),
            ..Meta::default()
        };
        let v = b.load_with(&Ty::I8, &p, 1, meta);
        b.store_with(&v, &p, 1, meta);
        b.load(&Ty::I8, &p, 1);
        let text = b.finish();
        let tbaa = format!("!tbaa !{TBAA_SCALAR_ELEM_NODE}");
        assert!(
            text.contains(&format!("align 1, {tbaa}, !range !{RANGE_BOOL_NODE}")),
            "{text}"
        );
        // A store takes only the alias class; a plain load takes nothing.
        assert!(text.contains(&format!("align 1, {tbaa}\n")), "{text}");
        assert_eq!(text.matches("!range").count(), 1, "{text}");
    }

    #[test]
    fn struct_layout_matches_natural_alignment() {
        let t = Types::default();
        let r = t.add_struct("R", vec![Ty::I8, Ty::I64, Ty::I32]);
        assert_eq!(t.size_align(&r), (24, 8));
        assert_eq!(t.field_offset(&r, 1), 8);
        assert_eq!(t.field_offset(&r, 2), 16);
        assert_eq!(t.definitions(), "%\"R\" = type { i8, i64, i32 }\n");
    }

    #[test]
    fn a_record_copy_is_one_memcpy_and_accesses_are_aligned() {
        let t = Types::default();
        let r = t.add_struct("R", vec![Ty::I64, Ty::F64, Ty::I64]);
        let mut b = FnBuilder::new(&t, None);
        b.label("b0");
        let slot = b.alloca(&r);
        let src = Val::new("%a0", Ty::Ptr);
        b.copy(&r, &slot, &src);
        let f = b.field_ptr(&r, &slot, 2);
        let x = b.load(&Ty::I64, &f, 8);
        b.ret(Some(&x));
        let text = b.finish();
        assert!(
            text.starts_with("b0:\n  %v1 = alloca %\"R\", align 8\n"),
            "{text}"
        );
        assert!(text.contains(
            "call void @llvm.memcpy.p0.p0.i64(ptr align 8 %v1, ptr align 8 %a0, i64 24, i1 false)"
        ));
        assert!(text.contains("getelementptr inbounds %\"R\", ptr %v1, i32 0, i32 2"));
        assert!(text.contains("load i64, ptr %v2, align 8"));
        assert!(text.ends_with("}\n\n"));
    }

    #[test]
    #[should_panic(expected = "operands differ")]
    fn mixed_operand_types_are_rejected() {
        let t = Types::default();
        let mut b = FnBuilder::new(&t, None);
        b.label("b0");
        b.bin(Bin::Add, &Val::int(1), &Val::byte(1));
    }
}
