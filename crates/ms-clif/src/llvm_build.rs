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

use std::fmt::Write as _;

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
}

/// A named struct type: fields laid out in order with natural alignment.
#[derive(Clone, Debug)]
pub struct StructDef {
    pub name: String,
    pub fields: Vec<Ty>,
}

/// The struct types of a module.
#[derive(Default, Debug)]
pub struct Types {
    structs: Vec<StructDef>,
}

impl Types {
    /// Declares a struct and returns its type.
    pub fn add_struct(&mut self, name: &str, fields: Vec<Ty>) -> Ty {
        self.structs.push(StructDef {
            name: name.to_string(),
            fields,
        });
        Ty::Struct(self.structs.len() - 1)
    }

    /// `%"name" = type { .. }` lines for every struct.
    pub fn definitions(&self) -> String {
        let mut s = String::new();
        for d in &self.structs {
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
            Ty::Struct(i) => format!("%\"{}\"", self.structs[*i].name),
            Ty::Array(e, n) => format!("[{n} x {}]", self.text(e)),
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
            Ty::Struct(i) => {
                let (mut off, mut align) = (0u64, 1u64);
                for f in &self.structs[*i].fields {
                    let (s, a) = self.size_align(f);
                    off = off.div_ceil(a) * a + s;
                    align = align.max(a);
                }
                (off.div_ceil(align) * align, align)
            }
        }
    }

    /// Byte offset of field `idx` of struct `ty`.
    pub fn field_offset(&self, ty: &Ty, idx: usize) -> u64 {
        let Ty::Struct(i) = ty else {
            panic!("field_offset of a non-struct")
        };
        let mut off = 0u64;
        for (k, f) in self.structs[*i].fields.iter().enumerate() {
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
        let Ty::Struct(i) = ty else {
            panic!("field of a non-struct")
        };
        self.structs[*i].fields[idx].clone()
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
}

impl<'t> FnBuilder<'t> {
    pub fn new(types: &'t Types, dbg: Option<usize>) -> Self {
        FnBuilder {
            types,
            out: String::new(),
            next: 0,
            allocas: String::new(),
            dbg,
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
        let v = self.reserve(ty);
        self.line(format!("{} = {rhs}", v.text));
        v
    }

    fn ty(&self, t: &Ty) -> String {
        self.types.text(t)
    }

    /// Starts a block.
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
        assert_eq!(ptr.ty, Ty::Ptr);
        assert!(align.is_power_of_two());
        self.def(
            ty.clone(),
            format!("load {}, ptr {}, align {align}", self.ty(ty), ptr.text),
        )
    }

    pub fn store(&mut self, val: &Val, ptr: &Val, align: u64) {
        assert_eq!(ptr.ty, Ty::Ptr);
        assert!(align.is_power_of_two());
        self.line(format!(
            "store {} {}, ptr {}, align {align}",
            self.ty(&val.ty),
            val.text,
            ptr.text
        ));
    }

    /// A stack slot for one `ty`, aligned for it; the `alloca` goes to the top of the entry block.
    pub fn alloca(&mut self, ty: &Ty) -> Val {
        let (_, align) = self.types.size_align(ty);
        let v = self.reserve(Ty::Ptr);
        let _ = writeln!(
            self.allocas,
            "  {} = alloca {}, align {align}",
            v.text,
            self.ty(ty)
        );
        v
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
    /// (same length), such as `" zeroext"`.
    pub fn call(
        &mut self,
        ret: &Ty,
        ret_attr: &str,
        callee: &str,
        args: &[(Val, &str)],
    ) -> Option<Val> {
        let actuals: Vec<String> = args
            .iter()
            .map(|(v, a)| format!("{}{a} {}", self.ty(&v.ty), v.text))
            .collect();
        let head = format!(
            "call {ret_attr}{} @\"{callee}\"({})",
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

    /// Renames the result of the last instruction, `from`, to the reserved name `to`.
    pub fn alias(&mut self, to: &Val, from: &Val) {
        if to.text == from.text {
            return;
        }
        assert_eq!(to.ty, from.ty);
        let line_start = self.out[..self.out.len() - 1]
            .rfind('\n')
            .map_or(0, |i| i + 1);
        let last = &self.out[line_start..];
        let prefix = format!("  {} = ", from.text);
        assert!(
            last.starts_with(&prefix),
            "the last line does not define {}",
            from.text
        );
        let renamed = format!("  {} = {}", to.text, &last[prefix.len()..]);
        self.out.truncate(line_start);
        self.out.push_str(&renamed);
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
    fn struct_layout_matches_natural_alignment() {
        let mut t = Types::default();
        let r = t.add_struct("R", vec![Ty::I8, Ty::I64, Ty::I32]);
        assert_eq!(t.size_align(&r), (24, 8));
        assert_eq!(t.field_offset(&r, 1), 8);
        assert_eq!(t.field_offset(&r, 2), 16);
        assert_eq!(t.definitions(), "%\"R\" = type { i8, i64, i32 }\n");
    }

    #[test]
    fn a_record_copy_is_one_memcpy_and_accesses_are_aligned() {
        let mut t = Types::default();
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
