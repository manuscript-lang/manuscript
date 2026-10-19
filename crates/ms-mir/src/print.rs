//! Deterministic text format: the printer.
//!
//! Values are renumbered densely in definition order and blocks are labelled
//! by index, so printing a parsed module reproduces the canonical text.
//!
//! ```text
//! fn @sum(%0: list<int>) -> int export {
//! b0:
//!   %1: int = iconst 0 !0:3:5
//!   br b1(%1, %1)
//! b1(%2: int, %3: int):
//!   ...
//! }
//! ```

use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::HashMap;
use std::fmt::Write;

/// Renders a type.
pub fn ty_str(m: &Module, t: Ty) -> String {
    let mut s = String::new();
    write_ty(m, t, &mut s);
    s
}

fn write_ty(m: &Module, t: Ty, out: &mut String) {
    match m.types.kind(t) {
        TyKind::Unit => out.push_str("unit"),
        TyKind::Bool => out.push_str("bool"),
        TyKind::Int => out.push_str("int"),
        TyKind::Float => out.push_str("float"),
        TyKind::Str => out.push_str("str"),
        TyKind::Bytes => out.push_str("bytes"),
        TyKind::Ptr => out.push_str("ptr"),
        TyKind::Rec(r) => out.push_str(&m.records[r.index()].name),
        TyKind::Alt(a) => out.push_str(&m.alts[a.index()].name),
        TyKind::List(e) => {
            out.push_str("list<");
            write_ty(m, *e, out);
            out.push('>');
        }
        TyKind::Opt(e) => {
            out.push_str("opt<");
            write_ty(m, *e, out);
            out.push('>');
        }
        TyKind::Obj(n, args) => {
            if args.is_empty() {
                out.push_str("obj ");
                out.push_str(n);
            } else {
                out.push_str(n);
                out.push('<');
                for (i, a) in args.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    write_ty(m, *a, out);
                }
                out.push('>');
            }
        }
        TyKind::Fn(ps, r) => {
            out.push_str("fn(");
            for (i, a) in ps.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                write_ty(m, *a, out);
            }
            out.push_str(") -> ");
            write_ty(m, *r, out);
        }
        TyKind::Iface(i) => {
            out.push_str("dyn ");
            out.push_str(&m.ifaces[i.index()].name);
        }
    }
}

/// Renders a string literal with escapes.
pub fn quote(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\t' => o.push_str("\\t"),
            '\r' => o.push_str("\\r"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                let _ = write!(o, "\\x{:02x}", c as u32);
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn mode_prefix(m: &Module, ty: Ty, mode: Mode) -> &'static str {
    if mode == Mode::Own && m.needs_drop(ty) { "own " } else { "" }
}

/// Renders a module as canonical text.
pub fn print_module(m: &Module) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "module {}", quote(&m.name));
    for (i, f) in m.files.iter().enumerate() {
        let _ = writeln!(o, "file {i} {}", quote(f));
    }
    for r in &m.records {
        let fields: Vec<String> = r.fields.iter().map(|(n, t)| format!("{n}: {}", ty_str(m, *t))).collect();
        let _ = writeln!(o, "record {} {{ {} }}", r.name, fields.join(", "));
    }
    for a in &m.alts {
        let cases: Vec<String> = a
            .cases
            .iter()
            .map(|c| {
                if c.fields.is_empty() {
                    c.name.clone()
                } else {
                    let fs: Vec<String> = c.fields.iter().map(|(n, t)| format!("{n}: {}", ty_str(m, *t))).collect();
                    format!("{}({})", c.name, fs.join(", "))
                }
            })
            .collect();
        let _ = writeln!(o, "alt {} {{ {} }}", a.name, cases.join(", "));
    }
    for i in &m.ifaces {
        let ms: Vec<String> = i
            .methods
            .iter()
            .map(|s| {
                let ps: Vec<String> = s.params.iter().map(|t| ty_str(m, *t)).collect();
                format!("{}({}) -> {}", s.name, ps.join(", "), ty_str(m, s.ret))
            })
            .collect();
        let _ = writeln!(o, "iface {} {{ {} }}", i.name, ms.join(", "));
    }
    for e in &m.externs {
        let ps: Vec<String> = e.params.iter().map(|p| format!("{}{}", mode_prefix(m, p.ty, p.mode), ty_str(m, p.ty))).collect();
        let mut line = format!("extern @{}({}) -> {}", e.name, ps.join(", "), ty_str(m, e.ret));
        if e.pure_ {
            line.push_str(" pure");
        }
        if e.noreturn {
            line.push_str(" noreturn");
        }
        o.push_str(&line);
        o.push('\n');
    }
    for g in &m.globals {
        let _ = writeln!(o, "global @{}: {}", g.name, ty_str(m, g.ty));
    }
    for v in &m.vtables {
        let ms: Vec<String> = v.methods.iter().map(|f| format!("@{}", m.funcs[f.index()].name)).collect();
        let _ = writeln!(o, "vtable @{}: {} for {} {{ {} }}", v.name, m.ifaces[v.iface.index()].name, ty_str(m, v.data_ty), ms.join(", "));
    }
    if let Some(e) = m.entry {
        let _ = writeln!(o, "entry @{}", m.funcs[e.index()].name);
    }
    for f in &m.funcs {
        o.push('\n');
        o.push_str(&print_func(m, f));
    }
    o
}

/// Renders one function.
pub fn print_func(m: &Module, f: &Func) -> String {
    let mut names: HashMap<Value, usize> = HashMap::new();
    let mut next = 0usize;
    let mut def = |v: Value| {
        names.entry(v).or_insert_with(|| {
            next += 1;
            next - 1
        });
    };
    for b in &f.blocks {
        for p in &b.params {
            def(p.value);
        }
        for i in &b.insts {
            if let Some(r) = i.res {
                def(r);
            }
        }
    }
    let n = |v: Value| format!("%{}", names.get(&v).copied().unwrap_or(usize::MAX));
    let mut o = String::new();
    let ps: Vec<String> = f.blocks[0]
        .params
        .iter()
        .zip(&f.params)
        .map(|(bp, p)| format!("{}: {}{}", n(bp.value), mode_prefix(m, p.ty, p.mode), ty_str(m, p.ty)))
        .collect();
    let _ = write!(o, "fn @{}({}) -> {}", f.name, ps.join(", "), ty_str(m, f.ret));
    if f.linkage == Linkage::Export {
        o.push_str(" export");
    }
    match f.inline {
        InlineHint::Auto => {}
        InlineHint::Always => o.push_str(" inline(always)"),
        InlineHint::Never => o.push_str(" inline(never)"),
    }
    match &f.kind {
        FuncKind::Normal => {}
        FuncKind::Method => o.push_str(" method"),
        FuncKind::Closure { captures } => {
            let cs: Vec<String> = captures.iter().map(|t| ty_str(m, *t)).collect();
            let _ = write!(o, " closure({})", cs.join(", "));
        }
    }
    if !f.loc.is_none() {
        let _ = write!(o, " !{}", f.loc);
    }
    o.push_str(" {\n");
    for (bi, b) in f.blocks.iter().enumerate() {
        if bi == 0 {
            o.push_str("b0:\n");
        } else {
            let ps: Vec<String> = b
                .params
                .iter()
                .map(|p| format!("{}: {}{}", n(p.value), mode_prefix(m, f.ty(p.value), p.mode), ty_str(m, f.ty(p.value))))
                .collect();
            let _ = writeln!(o, "b{bi}({}):", ps.join(", "));
        }
        for i in &b.insts {
            o.push_str("  ");
            if let Some(r) = i.res {
                let _ = write!(o, "{}: {} = ", n(r), ty_str(m, f.ty(r)));
            }
            o.push_str(&print_inst(m, i, &n));
            if !i.loc.is_none() {
                let _ = write!(o, " !{}", i.loc);
            }
            o.push('\n');
        }
        o.push_str("  ");
        o.push_str(&print_term(m, &b.term, &n));
        if !b.term_loc.is_none() {
            let _ = write!(o, " !{}", b.term_loc);
        }
        o.push('\n');
    }
    o.push_str("}\n");
    o
}

fn print_inst(m: &Module, i: &Inst, n: &dyn Fn(Value) -> String) -> String {
    let info = i.op.info();
    let mut s = String::from(info.name);
    let imm = match i.imm {
        Imm::None => String::new(),
        Imm::Int(v) => v.to_string(),
        Imm::Float(b) => {
            let v = f64::from_bits(b);
            if v.is_finite() { format!("{v:?}") } else { format!("0x{b:016x}") }
        }
        Imm::Bool(b) => b.to_string(),
        Imm::Str(id) => quote(&m.strings[id.index()]),
        Imm::Func(f) => format!("@{}", m.funcs[f.index()].name),
        Imm::Ext(e) => format!("@{}", m.externs[e.index()].name),
        Imm::Ty(t) => ty_str(m, t),
        Imm::Rec(r) => m.records[r.index()].name.clone(),
        Imm::Field(r, f) => format!("{}.{}", m.records[r.index()].name, m.records[r.index()].fields[f as usize].0),
        Imm::Case(a, c) => format!("{}.{}", m.alts[a.index()].name, m.alts[a.index()].cases[c as usize].name),
        Imm::AltField(a, c, f) => {
            let case = &m.alts[a.index()].cases[c as usize];
            format!("{}.{}.{}", m.alts[a.index()].name, case.name, case.fields[f as usize].0)
        }
        Imm::Vtable(v) => format!("@{}", m.vtables[v.index()].name),
        Imm::Global(g) => format!("@{}", m.globals[g.index()].name),
        Imm::Method(ifc, k) => format!("{}.{}", m.ifaces[ifc.index()].name, m.ifaces[ifc.index()].methods[k as usize].name),
        Imm::Cc(cc) => {
            s.push('.');
            s.push_str(cc.name());
            String::new()
        }
        Imm::Idx(k) => k.to_string(),
    };
    if !imm.is_empty() {
        s.push(' ');
        s.push_str(&imm);
    }
    let args: Vec<String> = i.args.iter().map(|a| n(*a)).collect();
    if i.op.is_call() {
        let _ = write!(s, " ({})", args.join(", "));
    } else if !args.is_empty() {
        s.push(' ');
        s.push_str(&args.join(", "));
    }
    s
}

fn target_str(t: &Target, n: &dyn Fn(Value) -> String) -> String {
    let args: Vec<String> = t.args.iter().map(|a| n(*a)).collect();
    format!("b{}({})", t.block.0, args.join(", "))
}

fn print_term(m: &Module, t: &Term, n: &dyn Fn(Value) -> String) -> String {
    match t {
        Term::Br(t) => format!("br {}", target_str(t, n)),
        Term::CondBr { cond, then, els } => format!("br_if {}, {}, {}", n(*cond), target_str(then, n), target_str(els, n)),
        Term::Switch { value, cases, default } => {
            let cs: Vec<String> = cases.iter().map(|(k, t)| format!("{k}: {}", target_str(t, n))).collect();
            format!("switch {} [{}] default {}", n(*value), cs.join(", "), target_str(default, n))
        }
        Term::Ret(None) => "ret".to_string(),
        Term::Ret(Some(v)) => format!("ret {}", n(*v)),
        Term::Fault(k) => format!("fault {}", fault_str(m, *k)),
        Term::Unreachable => "unreachable".to_string(),
    }
}

/// Text form of a fault kind.
pub fn fault_str(m: &Module, k: FaultKind) -> String {
    match k {
        FaultKind::IntOverflow => "int_overflow".into(),
        FaultKind::DivByZero => "div_by_zero".into(),
        FaultKind::IndexOutOfRange => "index_out_of_range".into(),
        FaultKind::NoneUnwrap => "none_unwrap".into(),
        FaultKind::Cancelled => "cancelled".into(),
        FaultKind::CallDepth => "call_depth".into(),
        FaultKind::Unreachable => "unreachable_code".into(),
        FaultKind::Message(s) => quote(&m.strings[s.index()]),
    }
}
