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

/// A location as `file:line:col`, with `:scope` when it belongs to an inlined callee.
fn loc_str(l: Loc) -> String {
    if l.scope == 0 {
        l.to_string()
    } else {
        format!("{l}:{}", l.scope)
    }
}

/// Renders a type.
pub fn ty_str(m: &Module, t: Ty) -> String {
    let mut s = String::new();
    write_ty(m, t.unscoped(), &mut s);
    if t.scope() != 0 {
        s.push_str(&format!("@{}", t.scope()));
    }
    s
}

fn write_ty(m: &Module, t: Ty, out: &mut String) {
    match m.types.kind(t) {
        TyKind::Void => out.push_str("void"),
        TyKind::Bool => out.push_str("bool"),
        TyKind::Int => out.push_str("int"),
        TyKind::Float => out.push_str("float"),
        TyKind::Int8 => out.push_str("int8"),
        TyKind::Int16 => out.push_str("int16"),
        TyKind::Int32 => out.push_str("int32"),
        TyKind::Float32 => out.push_str("float32"),
        TyKind::UInt8 => out.push_str("uint8"),
        TyKind::UInt16 => out.push_str("uint16"),
        TyKind::UInt32 => out.push_str("uint32"),
        TyKind::UInt64 => out.push_str("uint64"),
        TyKind::Str => out.push_str("str"),
        TyKind::Bytes => out.push_str("bytes"),
        TyKind::Ptr => out.push_str("ptr"),
        TyKind::Type(r) => out.push_str(&type_label(m, r.index())),
        TyKind::Alt(a) => out.push_str(&alt_label(m, a.index())),
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
                out.push_str(n.name());
            } else {
                out.push_str(n.name());
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
        TyKind::Fn(ps, r, owned) => {
            out.push_str("fn(");
            for (i, a) in ps.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                if crate::types::owns(*owned, i) {
                    out.push_str("move ");
                }
                write_ty(m, *a, out);
            }
            out.push_str(") -> ");
            write_ty(m, *r, out);
        }
        TyKind::Iface(i) => {
            out.push_str("dyn ");
            out.push_str(&iface_label(m, i.index()));
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

/// `move ` where a parameter takes its value owned, whatever the type: the verifier compares the mode
/// with the one a function type or interface method declares, a scalar's included.
fn mode_prefix(_m: &Module, _ty: Ty, mode: Mode) -> &'static str {
    if mode == Mode::Move { "move " } else { "" }
}

thread_local! {
    /// The printed names of functions whose own name another function already has (a program's
    /// `main` and the exported entry wrapper `main`): the later one gets `.1`, `.2`, ... so every
    /// reference in the text names one function and the text parses back. Empty almost always.
    static RENAMED: std::cell::RefCell<HashMap<usize, String>> = std::cell::RefCell::new(HashMap::new());
}

/// A function name the text can hold: the generated names (`<function adapter>`, `<to_string>`)
/// have characters a name token cannot.
fn sanitized(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '$') {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn find_renamed(m: &Module) -> HashMap<usize, String> {
    let printed: Vec<String> = m.funcs.iter().map(|f| sanitized(&f.name)).collect();
    let mut seen: HashMap<&str, usize> = HashMap::new();
    let taken: std::collections::HashSet<&str> = printed.iter().map(String::as_str).collect();
    let mut renamed = HashMap::new();
    // A function with a source position keeps its name; the generated entry wrapper that shares
    // it (`main`) is the one renamed, so a trace names the user's function.
    let mut order: Vec<usize> = (0..printed.len()).collect();
    order.sort_by_key(|&i| m.funcs[i].loc.line == 0);
    for i in order {
        let base = &printed[i];
        let count = seen.entry(base.as_str()).or_insert(0);
        *count += 1;
        if *count > 1 {
            let mut k = *count - 1;
            let mut name = format!("{base}.{k}");
            while taken.contains(name.as_str()) {
                k += 1;
                name = format!("{base}.{k}");
            }
            renamed.insert(i, name);
        } else if *base != m.funcs[i].name {
            renamed.insert(i, base.clone());
        }
    }
    renamed
}

thread_local! {
    /// As [`RENAMED`] for the type, alternative and interface declarations, whose names two
    /// generic instances can share (`ListCursor` of strings and of bytes): the later ones get
    /// `$1`, `$2`, ... (`.` is the field separator in a name, so it cannot be the suffix).
    static RENAMED_DECLS: std::cell::RefCell<[HashMap<usize, String>; 3]> =
        std::cell::RefCell::new([HashMap::new(), HashMap::new(), HashMap::new()]);
}

fn find_renamed_decls<'a>(names: impl Iterator<Item = &'a str>) -> HashMap<usize, String> {
    let all: Vec<&str> = names.collect();
    let taken: std::collections::HashSet<&str> = all.iter().copied().collect();
    let mut seen: HashMap<&str, usize> = HashMap::new();
    let mut renamed = HashMap::new();
    for (i, name) in all.iter().enumerate() {
        let count = seen.entry(name).or_insert(0);
        *count += 1;
        if *count > 1 {
            let mut k = *count - 1;
            let mut label = format!("{name}${k}");
            while taken.contains(label.as_str()) {
                k += 1;
                label = format!("{name}${k}");
            }
            renamed.insert(i, label);
        }
    }
    renamed
}

fn decl_label(kind: usize, index: usize, name: &str) -> String {
    RENAMED_DECLS.with(|r| match r.borrow()[kind].get(&index) {
        Some(label) => label.clone(),
        None => name.to_string(),
    })
}

fn type_label(m: &Module, index: usize) -> String {
    decl_label(0, index, &m.type_defs[index].name)
}

fn alt_label(m: &Module, index: usize) -> String {
    decl_label(1, index, &m.alts[index].name)
}

fn iface_label(m: &Module, index: usize) -> String {
    decl_label(2, index, &m.ifaces[index].name)
}

/// The name function `index` is printed under.
fn func_label(m: &Module, index: usize) -> String {
    RENAMED.with(|r| match r.borrow().get(&index) {
        Some(name) => name.clone(),
        None => m.funcs[index].name.clone(),
    })
}

/// The names a trace shows for functions whose printed name differs from their own (a name with
/// spaces, such as a test's, is sanitized; a duplicate gets `.N`): one `printed<TAB>name` line each,
/// in the order [`print_module_unique`] prints them.
pub fn display_names(m: &Module) -> String {
    let renamed = find_renamed(m);
    let mut o = String::new();
    for (i, f) in m.funcs.iter().enumerate() {
        let printed = renamed.get(&i).cloned().unwrap_or_else(|| f.name.clone());
        if printed != f.name {
            let _ = writeln!(o, "{printed}\t{}", f.name);
        }
    }
    o
}

/// Renders a module as canonical text.
pub fn print_module(m: &Module) -> String {
    print_module_with(m, false)
}

/// As [`print_module`], for text that is read back: two types, alternatives or interfaces that
/// share a name (instances of one generic declaration) are printed under distinct names, so each
/// reference names one declaration.
pub fn print_module_unique(m: &Module) -> String {
    print_module_with(m, true)
}

/// As [`print_module`] with every function under its own name, even when two share one: the
/// pass oracles compare the text of what a pass built against the C pass's, which keeps names
/// as they are.
pub fn print_module_raw(m: &Module) -> String {
    print_module_text(m)
}

fn print_module_with(m: &Module, unique_decls: bool) -> String {
    RENAMED.with(|r| *r.borrow_mut() = find_renamed(m));
    if unique_decls {
        RENAMED_DECLS.with(|r| {
            *r.borrow_mut() = [
                find_renamed_decls(m.type_defs.iter().map(|t| t.name.as_str())),
                find_renamed_decls(m.alts.iter().map(|t| t.name.as_str())),
                find_renamed_decls(m.ifaces.iter().map(|t| t.name.as_str())),
            ];
        });
    }
    let text = print_module_text(m);
    RENAMED.with(|r| r.borrow_mut().clear());
    RENAMED_DECLS.with(|r| r.borrow_mut().iter_mut().for_each(HashMap::clear));
    text
}

fn print_module_text(m: &Module) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "module {}", quote(&m.name));
    for (i, f) in m.files.iter().enumerate() {
        let _ = writeln!(o, "file {i} {}", quote(f));
    }
    for (i, b) in m.blobs.iter().enumerate() {
        let hex: String = b.iter().map(|x| format!("{x:02x}")).collect();
        let _ = writeln!(o, "blob {i} \"{hex}\"");
    }
    for (i, l) in m.list_consts.iter().enumerate() {
        let items: Vec<String> = l.iter().map(|x| x.to_string()).collect();
        let _ = writeln!(o, "consts {i} [{}]", items.join(", "));
    }
    for (ri, r) in m.type_defs.iter().enumerate() {
        let fields: Vec<String> = r
            .fields
            .iter()
            .map(|(n, t)| format!("{n}: {}", ty_str(m, *t)))
            .collect();
        let indirect = if r.indirect { " indirect" } else { "" };
        let _ = writeln!(
            o,
            "type {}{indirect} {{ {} }}",
            type_label(m, ri),
            fields.join(", ")
        );
    }
    for (ai, a) in m.alts.iter().enumerate() {
        let cases: Vec<String> = a
            .cases
            .iter()
            .map(|c| {
                if c.fields.is_empty() {
                    c.name.clone()
                } else {
                    let fs: Vec<String> = c
                        .fields
                        .iter()
                        .map(|(n, t)| format!("{n}: {}", ty_str(m, *t)))
                        .collect();
                    format!("{}({})", c.name, fs.join(", "))
                }
            })
            .collect();
        let attr = a.std.name().map(|n| format!(" {n}")).unwrap_or_default();
        // The cases a borrowing variant holds as borrows (a bit per case).
        let borrowed = if a.borrowed == 0 {
            String::new()
        } else {
            format!(" borrowed {}", a.borrowed)
        };
        let _ = writeln!(
            o,
            "alt {}{borrowed} {{ {} }}{attr}",
            alt_label(m, ai),
            cases.join(", ")
        );
    }
    for (ii, i) in m.ifaces.iter().enumerate() {
        let ms: Vec<String> = i
            .methods
            .iter()
            .map(|s| {
                let ps: Vec<String> = s
                    .params
                    .iter()
                    .enumerate()
                    .map(|(k, t)| {
                        let own = if crate::types::owns(s.owned, k) {
                            "move "
                        } else {
                            ""
                        };
                        format!("{own}{}", ty_str(m, *t))
                    })
                    .collect();
                format!("{}({}) -> {}", s.name, ps.join(", "), ty_str(m, s.ret))
            })
            .collect();
        let attr = i.std.name().map(|n| format!(" {n}")).unwrap_or_default();
        let _ = writeln!(
            o,
            "iface {} {{ {} }}{attr}",
            iface_label(m, ii),
            ms.join(", ")
        );
    }
    for e in &m.externs {
        let ps: Vec<String> = e
            .params
            .iter()
            .map(|p| format!("{}{}", mode_prefix(m, p.ty, p.mode), ty_str(m, p.ty)))
            .collect();
        let mut line = format!(
            "extern @{}({}) -> {}",
            e.name,
            ps.join(", "),
            ty_str(m, e.ret)
        );
        if e.pure_ {
            line.push_str(" pure");
        }
        if e.noreturn {
            line.push_str(" noreturn");
        }
        if e.fresh {
            line.push_str(" fresh");
        }
        if e.leaf {
            line.push_str(" leaf");
        }
        if e.reads {
            line.push_str(" reads");
        }
        if e.retains {
            line.push_str(" retains");
        }
        if let Some(role) = e.role.name() {
            line.push(' ');
            line.push_str(role);
        }
        o.push_str(&line);
        o.push('\n');
    }
    for g in &m.globals {
        let _ = writeln!(o, "global @{}: {}", g.name, ty_str(m, g.ty));
    }
    for v in &m.vtables {
        let ms: Vec<String> = v
            .methods
            .iter()
            .map(|f| format!("@{}", func_label(m, f.index())))
            .collect();
        let _ = writeln!(
            o,
            "vtable @{}: {} for {} {{ {} }}",
            sanitized(&v.name),
            iface_label(m, v.iface.index()),
            ty_str(m, v.data_ty),
            ms.join(", ")
        );
    }
    for &(ty, eq, hash) in &m.desc_glue {
        let _ = writeln!(
            o,
            "desc_glue {} @{} @{}",
            ty_str(m, ty),
            func_label(m, eq.index()),
            func_label(m, hash.index())
        );
    }
    if let Some(e) = m.entry {
        let _ = writeln!(o, "entry @{}", func_label(m, e.index()));
    }
    if let Some(c) = m.close {
        let _ = writeln!(o, "close @{}", func_label(m, c.index()));
    }
    for f in &m.funcs {
        o.push('\n');
        o.push_str(&print_func(m, f));
    }
    o
}

/// The printed name of `f`, which is a function of `m`.
fn func_label_of(m: &Module, f: &Func) -> String {
    let renamed = RENAMED.with(|r| !r.borrow().is_empty());
    if renamed && let Some(i) = m.funcs.iter().position(|g| std::ptr::eq(g, f)) {
        return func_label(m, i);
    }
    f.name.clone()
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
        .map(|(bp, p)| {
            format!(
                "{}: {}{}",
                n(bp.value),
                mode_prefix(m, p.ty, p.mode),
                ty_str(m, p.ty)
            )
        })
        .collect();
    let _ = write!(
        o,
        "fn @{}({}) -> {}",
        func_label_of(m, f),
        ps.join(", "),
        ty_str(m, f.ret)
    );
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
    match f.sort {
        SortThunk::None => {}
        SortThunk::Generic => o.push_str(" sort_cmp"),
        SortThunk::Specialized => o.push_str(" sort_cmp_for"),
    }
    if f.explicit_cancel {
        o.push_str(" explicit_cancel");
    }
    if !f.noalias.is_empty() {
        let ns: Vec<String> = f.noalias.iter().map(u32::to_string).collect();
        let _ = write!(o, " noalias({})", ns.join(", "));
    }
    if let Some(s) = f.slot_result {
        let _ = write!(o, " slot_result(@{})", func_label(m, s.0 as usize));
    }
    if let Some((a, b)) = f.close_exit {
        let _ = write!(
            o,
            " close_exit(@{}, @{})",
            func_label(m, a.0 as usize),
            func_label(m, b.0 as usize)
        );
    }
    for (set, word) in [
        (f.ret_borrowed, "ret_borrowed"),
        (f.ret_view, "ret_view"),
        (f.scoped, "scoped"),
        (f.keeps_scoped, "keeps_scoped"),
        (f.unwind_only, "unwind_only"),
        (f.raw_scratch, "raw_scratch"),
    ] {
        if set {
            o.push(' ');
            o.push_str(word);
        }
    }
    if let Some(t) = f.slot_close {
        let _ = write!(o, " slot_close({})", ty_str(m, t));
    }
    if !f.capture_closers.is_empty() {
        let cs: Vec<String> = f
            .capture_closers
            .iter()
            .map(|(i, g)| format!("{i} @{}", func_label(m, g.0 as usize)))
            .collect();
        let _ = write!(o, " capture_closers({})", cs.join(", "));
    }
    if !f.loc.is_none() {
        let _ = write!(o, " !{}", loc_str(f.loc));
    }
    o.push_str(" {\n");
    for (bi, b) in f.blocks.iter().enumerate() {
        if bi == 0 {
            o.push_str("b0:\n");
        } else {
            let ps: Vec<String> = b
                .params
                .iter()
                .map(|p| {
                    format!(
                        "{}: {}{}",
                        n(p.value),
                        mode_prefix(m, f.ty(p.value), p.mode),
                        ty_str(m, f.ty(p.value))
                    )
                })
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
                let _ = write!(o, " !{}", loc_str(i.loc));
            }
            o.push('\n');
        }
        o.push_str("  ");
        o.push_str(&print_term(m, &b.term, &n));
        if !b.term_loc.is_none() {
            let _ = write!(o, " !{}", loc_str(b.term_loc));
        }
        o.push('\n');
    }
    // Debugger and range facts, only when a function has them: the inlined scopes, the named
    // values and the results proved exact, in that order.
    for sc in &f.scopes {
        let _ = writeln!(
            o,
            "  scope {} {} {} {}",
            quote(&sc.name),
            sc.file,
            sc.parent,
            sc.call_line
        );
    }
    for nv in &f.names {
        if let Some(&i) = names.get(&nv.value) {
            let _ = writeln!(
                o,
                "  name %{i} {} {} {}",
                quote(&nv.name),
                if nv.param { "param" } else { "local" },
                nv.scope
            );
        }
    }
    let mut exact: Vec<usize> = f
        .exact
        .iter()
        .filter_map(|v| names.get(v).copied())
        .collect();
    exact.sort_unstable();
    for i in exact {
        let _ = writeln!(o, "  exact %{i}");
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
            if v.is_finite() {
                format!("{v:?}")
            } else {
                format!("0x{b:016x}")
            }
        }
        Imm::Bool(b) => b.to_string(),
        Imm::Str(id) => quote(&m.strings[id.index()]),
        Imm::Func(f) => format!("@{}", func_label(m, f.index())),
        Imm::Ext(e) => format!("@{}", m.externs[e.index()].name),
        Imm::Ty(t) => ty_str(m, t),
        Imm::Type(r) => type_label(m, r.index()),
        Imm::Field(r, f) => format!(
            "{}.{}",
            type_label(m, r.index()),
            m.type_defs[r.index()].fields[f as usize].0
        ),
        Imm::Case(a, c) => format!(
            "{}.{}",
            alt_label(m, a.index()),
            m.alts[a.index()].cases[c as usize].name
        ),
        Imm::AltField(a, c, f) => {
            let case = &m.alts[a.index()].cases[c as usize];
            format!(
                "{}.{}.{}",
                alt_label(m, a.index()),
                case.name,
                case.fields[f as usize].0
            )
        }
        Imm::AltMask(a, c, mask) => {
            let case = &m.alts[a.index()].cases[c as usize];
            let mut s = format!("{}.{}", alt_label(m, a.index()), case.name);
            for (i, (name, _)) in case.fields.iter().enumerate() {
                if mask >> i & 1 == 1 {
                    s.push('.');
                    s.push_str(name);
                }
            }
            s
        }
        Imm::TypeMask(r, mask) => {
            let mut s = type_label(m, r.index());
            for (i, (name, _)) in m.type_defs[r.index()].fields.iter().enumerate() {
                if mask >> i & 1 == 1 {
                    s.push('.');
                    s.push_str(name);
                }
            }
            s
        }
        Imm::Vtable(v) => format!("@{}", sanitized(&m.vtables[v.index()].name)),
        Imm::Global(g) => format!("@{}", m.globals[g.index()].name),
        Imm::Method(ifc, k) => format!(
            "{}.{}",
            iface_label(m, ifc.index()),
            m.ifaces[ifc.index()].methods[k as usize].name
        ),
        Imm::Cc(cc) => {
            s.push('.');
            s.push_str(cc.name());
            String::new()
        }
        Imm::Idx(k) => k.to_string(),
        Imm::Scope(a, b) => format!("{a} {b}"),
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
        Term::CondBr { cond, then, els } => format!(
            "br_if {}, {}, {}",
            n(*cond),
            target_str(then, n),
            target_str(els, n)
        ),
        Term::Switch {
            value,
            cases,
            default,
        } => {
            let cs: Vec<String> = cases
                .iter()
                .map(|(k, t)| format!("{k}: {}", target_str(t, n)))
                .collect();
            format!(
                "switch {} [{}] default {}",
                n(*value),
                cs.join(", "),
                target_str(default, n)
            )
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
