//! Deterministic text format: the parser. See [`crate::print`] for the grammar by example.
//!
//! Top-level items are one per line (`module`, `file`, `record`, `alt`,
//! `iface`, `extern`, `global`, `vtable`, `entry`) except `fn`, whose body
//! extends to a line holding only `}`. Items may reference each other in any
//! order. Inside functions, blocks and values may be referenced before they
//! are defined; names are arbitrary identifiers (`%x`, `loop`) and are
//! renumbered when printed.

use crate::ir::*;
use crate::types::*;
use std::collections::HashMap;
use std::fmt;

/// A syntax or resolution error with its 1-based line.
#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    /// 1-based line number.
    pub line: usize,
    /// Description.
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

impl std::error::Error for ParseError {}

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Ident(String),
    Val(String),
    At(String),
    Num(String),
    Str(String),
    Loc(Loc),
    Arrow,
    P(char),
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '$'
}

fn tokenize(line: &str, lineno: usize) -> Result<Vec<Tok>, ParseError> {
    let err = |m: &str| ParseError {
        line: lineno,
        message: m.to_string(),
    };
    let cs: Vec<char> = line.chars().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < cs.len() {
        let c = cs[i];
        if c.is_whitespace() {
            i += 1;
        } else if c == ';' {
            break;
        } else if c == '"' {
            i += 1;
            let mut s = String::new();
            loop {
                let Some(&c) = cs.get(i) else {
                    return Err(err("unterminated string"));
                };
                i += 1;
                match c {
                    '"' => break,
                    '\\' => {
                        let Some(&e) = cs.get(i) else {
                            return Err(err("bad escape"));
                        };
                        i += 1;
                        match e {
                            'n' => s.push('\n'),
                            't' => s.push('\t'),
                            'r' => s.push('\r'),
                            '"' => s.push('"'),
                            '\\' => s.push('\\'),
                            'x' => {
                                let h: String = cs
                                    .get(i..i + 2)
                                    .ok_or_else(|| err("bad \\x escape"))?
                                    .iter()
                                    .collect();
                                i += 2;
                                s.push(
                                    u8::from_str_radix(&h, 16).map_err(|_| err("bad \\x escape"))?
                                        as char,
                                );
                            }
                            _ => return Err(err("unknown escape")),
                        }
                    }
                    c => s.push(c),
                }
            }
            out.push(Tok::Str(s));
        } else if c == '%' || c == '@' {
            let start = i + 1;
            i += 1;
            while i < cs.len() && is_ident_char(cs[i]) {
                i += 1;
            }
            let name: String = cs[start..i].iter().collect();
            if name.is_empty() {
                return Err(err("empty name"));
            }
            out.push(if c == '%' {
                Tok::Val(name)
            } else {
                Tok::At(name)
            });
        } else if c == '!' {
            i += 1;
            let start = i;
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == ':') {
                i += 1;
            }
            let t: String = cs[start..i].iter().collect();
            let p: Vec<&str> = t.split(':').collect();
            if p.len() != 3 {
                return Err(err("location must be !file:line:col"));
            }
            let n = |s: &str| s.parse::<u32>().map_err(|_| err("bad location"));
            out.push(Tok::Loc(Loc {
                file: n(p[0])?,
                line: n(p[1])?,
                col: n(p[2])?,
                scope: 0,
            }));
        } else if c == '-' && cs.get(i + 1) == Some(&'>') {
            out.push(Tok::Arrow);
            i += 2;
        } else if c.is_ascii_digit()
            || (c == '-' && cs.get(i + 1).is_some_and(|d| d.is_ascii_digit()))
        {
            let start = i;
            i += 1;
            if c == '0' && cs.get(i) == Some(&'x') {
                i += 1;
                while i < cs.len() && cs[i].is_ascii_hexdigit() {
                    i += 1;
                }
            } else {
                while i < cs.len() {
                    let d = cs[i];
                    let exp_sign = (d == '+' || d == '-') && matches!(cs[i - 1], 'e' | 'E');
                    if d.is_ascii_digit() || d == '.' || d == 'e' || d == 'E' || exp_sign {
                        i += 1;
                    } else {
                        break;
                    }
                }
            }
            out.push(Tok::Num(cs[start..i].iter().collect()));
        } else if c.is_ascii_alphabetic() || c == '_' {
            let start = i;
            while i < cs.len() && is_ident_char(cs[i]) {
                i += 1;
            }
            out.push(Tok::Ident(cs[start..i].iter().collect()));
        } else if "(){}<>[],:=".contains(c) {
            out.push(Tok::P(c));
            i += 1;
        } else {
            return Err(err(&format!("unexpected character {c:?}")));
        }
    }
    Ok(out)
}

struct Cur<'a> {
    toks: &'a [Tok],
    pos: usize,
    line: usize,
}

impl Cur<'_> {
    fn err<T>(&self, msg: impl Into<String>) -> Result<T, ParseError> {
        Err(ParseError {
            line: self.line,
            message: msg.into(),
        })
    }
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }
    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.pos).cloned();
        self.pos += 1;
        t
    }
    fn eat_p(&mut self, c: char) -> bool {
        if self.peek() == Some(&Tok::P(c)) {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn expect_p(&mut self, c: char) -> Result<(), ParseError> {
        if self.eat_p(c) {
            Ok(())
        } else {
            self.err(format!("expected '{c}', found {:?}", self.peek()))
        }
    }
    fn ident(&mut self) -> Result<String, ParseError> {
        match self.next() {
            Some(Tok::Ident(s)) => Ok(s),
            t => self.err(format!("expected identifier, found {t:?}")),
        }
    }
    fn eat_ident(&mut self, s: &str) -> bool {
        if matches!(self.peek(), Some(Tok::Ident(x)) if x == s) {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn at(&mut self) -> Result<String, ParseError> {
        match self.next() {
            Some(Tok::At(s)) => Ok(s),
            t => self.err(format!("expected @name, found {t:?}")),
        }
    }
    fn val(&mut self) -> Result<String, ParseError> {
        match self.next() {
            Some(Tok::Val(s)) => Ok(s),
            t => self.err(format!("expected %value, found {t:?}")),
        }
    }
    fn num(&mut self) -> Result<String, ParseError> {
        match self.next() {
            Some(Tok::Num(s)) => Ok(s),
            t => self.err(format!("expected a number, found {t:?}")),
        }
    }
    fn string(&mut self) -> Result<String, ParseError> {
        match self.next() {
            Some(Tok::Str(s)) => Ok(s),
            t => self.err(format!("expected a string, found {t:?}")),
        }
    }
    fn done(&self) -> bool {
        self.pos >= self.toks.len()
    }
}

struct FnHeader {
    names: Vec<String>,
    body: Vec<(usize, String)>,
}

/// Parses the text format into a module.
pub fn parse_module(src: &str) -> Result<Module, ParseError> {
    let mut m = Module::new("module");
    // Group lines into items.
    let mut items: Vec<(usize, String)> = Vec::new();
    #[allow(clippy::type_complexity)]
    let mut fns: Vec<(usize, String, Vec<(usize, String)>)> = Vec::new();
    let mut lines = src.lines().enumerate();
    while let Some((n, raw)) = lines.next() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with(';') {
            continue;
        }
        if line.starts_with("fn ") {
            let mut body = Vec::new();
            let mut closed = false;
            for (bn, braw) in lines.by_ref() {
                if braw.trim() == "}" {
                    closed = true;
                    break;
                }
                body.push((bn + 1, braw.to_string()));
            }
            if !closed {
                return Err(ParseError {
                    line: n + 1,
                    message: "function body is not closed with '}'".into(),
                });
            }
            fns.push((n + 1, line.to_string(), body));
        } else {
            items.push((n + 1, line.to_string()));
        }
    }
    let toks: Vec<(usize, Vec<Tok>)> = items
        .iter()
        .map(|(n, l)| tokenize(l, *n).map(|t| (*n, t)))
        .collect::<Result<_, _>>()?;
    // Pass A: names of records, alternatives and interfaces.
    for (n, t) in &toks {
        let mut c = Cur {
            toks: t,
            pos: 0,
            line: *n,
        };
        match c.ident()?.as_str() {
            "record" => {
                let name = c.ident()?;
                m.records.push(RecordDef {
                    name,
                    fields: Vec::new(),
                });
            }
            "alt" => {
                let name = c.ident()?;
                m.alts.push(AltDef {
                    name,
                    cases: Vec::new(),
                });
            }
            "iface" => {
                let name = c.ident()?;
                m.ifaces.push(IfaceDef {
                    name,
                    methods: Vec::new(),
                });
            }
            _ => {}
        }
    }
    // Pass B: bodies of type declarations.
    for (n, t) in &toks {
        let mut c = Cur {
            toks: t,
            pos: 0,
            line: *n,
        };
        let kw = c.ident()?;
        match kw.as_str() {
            "record" => {
                let name = c.ident()?;
                let id = m.record_by_name(&name).expect("registered");
                c.expect_p('{')?;
                let mut fields = Vec::new();
                while !c.eat_p('}') {
                    let fname = c.ident()?;
                    c.expect_p(':')?;
                    let ty = parse_ty(&mut c, &mut m)?;
                    fields.push((fname, ty));
                    c.eat_p(',');
                }
                m.records[id.index()].fields = fields;
            }
            "alt" => {
                let name = c.ident()?;
                let id = m.alt_by_name(&name).expect("registered");
                c.expect_p('{')?;
                let mut cases = Vec::new();
                while !c.eat_p('}') {
                    let cname = c.ident()?;
                    let mut fields = Vec::new();
                    if c.eat_p('(') {
                        while !c.eat_p(')') {
                            let fname = c.ident()?;
                            c.expect_p(':')?;
                            let ty = parse_ty(&mut c, &mut m)?;
                            fields.push((fname, ty));
                            c.eat_p(',');
                        }
                    }
                    cases.push(CaseDef {
                        name: cname,
                        fields,
                    });
                    c.eat_p(',');
                }
                m.alts[id.index()].cases = cases;
            }
            "iface" => {
                let name = c.ident()?;
                let id = m
                    .ifaces
                    .iter()
                    .position(|i| i.name == name)
                    .expect("registered");
                c.expect_p('{')?;
                let mut methods = Vec::new();
                while !c.eat_p('}') {
                    let mname = c.ident()?;
                    c.expect_p('(')?;
                    let mut params = Vec::new();
                    while !c.eat_p(')') {
                        params.push(parse_ty(&mut c, &mut m)?);
                        c.eat_p(',');
                    }
                    let mut ret_borrowed = false;
                    let ret = if c.peek() == Some(&Tok::Arrow) {
                        c.next();
                        ret_borrowed = c.eat_ident("ref");
                        parse_ty(&mut c, &mut m)?
                    } else {
                        Ty::UNIT
                    };
                    methods.push(MethodSig {
                        name: mname,
                        params,
                        ret,
                        ret_borrowed,
                        self_params: Vec::new(),
                    });
                    c.eat_p(',');
                }
                m.ifaces[id].methods = methods;
            }
            _ => {}
        }
    }
    // Pass C: module, files, externs, globals, function headers.
    let mut entry_name = None;
    let mut vtable_items = Vec::new();
    for (n, t) in &toks {
        let mut c = Cur {
            toks: t,
            pos: 0,
            line: *n,
        };
        let kw = c.ident()?;
        match kw.as_str() {
            "module" => {
                m.name = match c.next() {
                    Some(Tok::Str(s)) | Some(Tok::Ident(s)) => s,
                    t => return c.err(format!("expected module name, found {t:?}")),
                };
            }
            "file" => {
                let idx: usize = c.num()?.parse().map_err(|_| ParseError {
                    line: *n,
                    message: "bad file index".into(),
                })?;
                let path = c.string()?;
                if idx != m.files.len() {
                    return c.err("files must be numbered consecutively from 0");
                }
                m.files.push(path);
            }
            "extern" => {
                let name = c.at()?;
                c.expect_p('(')?;
                let mut params = Vec::new();
                while !c.eat_p(')') {
                    let own = c.eat_ident("own");
                    let ty = parse_ty(&mut c, &mut m)?;
                    params.push(Param {
                        ty,
                        mode: if own { Mode::Own } else { Mode::Borrow },
                    });
                    c.eat_p(',');
                }
                let ret = if c.peek() == Some(&Tok::Arrow) {
                    c.next();
                    parse_ty(&mut c, &mut m)?
                } else {
                    Ty::UNIT
                };
                let (mut noreturn, mut pure_, mut fresh) = (false, false, false);
                while !c.done() {
                    match c.ident()?.as_str() {
                        "noreturn" => noreturn = true,
                        "pure" => pure_ = true,
                        "fresh" => fresh = true,
                        o => return c.err(format!("unknown extern attribute {o}")),
                    }
                }
                m.externs.push(ExternDef {
                    name,
                    params,
                    ret,
                    noreturn,
                    pure_,
                    fresh,
                });
            }
            "global" => {
                let name = c.at()?;
                c.expect_p(':')?;
                let ty = parse_ty(&mut c, &mut m)?;
                m.globals.push(GlobalDef { name, ty });
            }
            "entry" => entry_name = Some((c.at()?, *n)),
            "vtable" => vtable_items.push((*n, t.clone())),
            "record" | "alt" | "iface" => {}
            o => return c.err(format!("unknown item '{o}'")),
        }
    }
    let mut headers = Vec::new();
    for (n, line, body) in &fns {
        let toks = tokenize(line, *n)?;
        let mut c = Cur {
            toks: &toks,
            pos: 0,
            line: *n,
        };
        c.ident()?; // fn
        let name = c.at()?;
        c.expect_p('(')?;
        let mut params = Vec::new();
        let mut names = Vec::new();
        while !c.eat_p(')') {
            names.push(c.val()?);
            c.expect_p(':')?;
            let own = c.eat_ident("own");
            let ty = parse_ty(&mut c, &mut m)?;
            params.push(Param {
                ty,
                mode: if own { Mode::Own } else { Mode::Borrow },
            });
            c.eat_p(',');
        }
        let ret = if c.peek() == Some(&Tok::Arrow) {
            c.next();
            parse_ty(&mut c, &mut m)?
        } else {
            Ty::UNIT
        };
        let mut f = Func::new(&name, params, ret);
        loop {
            match c.peek() {
                Some(Tok::P('{')) => {
                    c.next();
                    break;
                }
                Some(Tok::Loc(l)) => {
                    f.loc = *l;
                    c.next();
                }
                _ => {}
            }
            if c.peek().is_none() {
                return c.err("expected '{'");
            }
            if matches!(c.peek(), Some(Tok::Ident(_))) {
                match c.ident()?.as_str() {
                    "export" => f.linkage = Linkage::Export,
                    "method" => f.kind = FuncKind::Method,
                    "inline" => {
                        c.expect_p('(')?;
                        f.inline = match c.ident()?.as_str() {
                            "always" => InlineHint::Always,
                            "never" => InlineHint::Never,
                            o => return c.err(format!("unknown inline hint {o}")),
                        };
                        c.expect_p(')')?;
                    }
                    "closure" => {
                        c.expect_p('(')?;
                        let mut caps = Vec::new();
                        while !c.eat_p(')') {
                            caps.push(parse_ty(&mut c, &mut m)?);
                            c.eat_p(',');
                        }
                        f.kind = FuncKind::Closure { captures: caps };
                    }
                    o => return c.err(format!("unknown function attribute {o}")),
                }
            }
        }
        if m.func_by_name(&name).is_some() {
            return c.err(format!("function @{name} defined twice"));
        }
        m.add_func(f);
        headers.push(FnHeader {
            names,
            body: body.clone(),
        });
    }
    // Vtables and entry need function ids.
    for (n, t) in vtable_items {
        let mut c = Cur {
            toks: &t,
            pos: 0,
            line: n,
        };
        c.ident()?;
        let name = c.at()?;
        c.expect_p(':')?;
        let iname = c.ident()?;
        let iface = m
            .ifaces
            .iter()
            .position(|i| i.name == iname)
            .ok_or_else(|| ParseError {
                line: n,
                message: format!("unknown interface {iname}"),
            })?;
        if !c.eat_ident("for") {
            return c.err("expected 'for'");
        }
        let data_ty = parse_ty(&mut c, &mut m)?;
        c.expect_p('{')?;
        let mut methods = Vec::new();
        while !c.eat_p('}') {
            let f = c.at()?;
            methods.push(m.func_by_name(&f).ok_or_else(|| ParseError {
                line: n,
                message: format!("unknown function @{f}"),
            })?);
            c.eat_p(',');
        }
        m.vtables.push(VtableDef {
            name,
            iface: IfaceId(iface as u32),
            methods,
            data_ty,
        });
    }
    if let Some((e, n)) = entry_name {
        m.entry = Some(m.func_by_name(&e).ok_or_else(|| ParseError {
            line: n,
            message: format!("unknown entry function @{e}"),
        })?);
    }
    // Pass E: bodies.
    for (i, h) in headers.iter().enumerate() {
        parse_body(&mut m, FuncId(i as u32), h)?;
    }
    Ok(m)
}

fn parse_ty(c: &mut Cur, m: &mut Module) -> Result<Ty, ParseError> {
    let name = c.ident()?;
    Ok(match name.as_str() {
        "unit" => Ty::UNIT,
        "bool" => Ty::BOOL,
        "int" => Ty::INT,
        "float" => Ty::FLOAT,
        "int8" => Ty::INT8,
        "int16" => Ty::INT16,
        "int32" => Ty::INT32,
        "float32" => Ty::FLOAT32,
        "uint8" => Ty::UINT8,
        "uint16" => Ty::UINT16,
        "uint32" => Ty::UINT32,
        "uint64" => Ty::UINT64,
        "str" => Ty::STR,
        "bytes" => Ty::BYTES,
        "ptr" => Ty::PTR,
        "list" | "opt" | "ref" => {
            c.expect_p('<')?;
            let inner = parse_ty(c, m)?;
            c.expect_p('>')?;
            match name.as_str() {
                "list" => m.types.list(inner),
                "opt" => m.types.opt(inner),
                _ => m.types.view(inner),
            }
        }
        "fn" => {
            c.expect_p('(')?;
            let mut ps = Vec::new();
            while !c.eat_p(')') {
                ps.push(parse_ty(c, m)?);
                c.eat_p(',');
            }
            if c.peek() != Some(&Tok::Arrow) {
                return c.err("expected '->' in function type");
            }
            c.next();
            let r = parse_ty(c, m)?;
            m.types.func(ps, r)
        }
        "dyn" => {
            let n = c.ident()?;
            let id = m
                .ifaces
                .iter()
                .position(|i| i.name == n)
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown interface {n}"),
                })?;
            m.types.iface(IfaceId(id as u32))
        }
        "obj" => {
            let n = c.ident()?;
            m.types.obj(&n, Vec::new())
        }
        _ => {
            if c.eat_p('<') {
                let mut args = Vec::new();
                while !c.eat_p('>') {
                    args.push(parse_ty(c, m)?);
                    c.eat_p(',');
                }
                m.types.obj(&name, args)
            } else if let Some(r) = m.record_by_name(&name) {
                m.types.rec(r)
            } else if let Some(a) = m.alt_by_name(&name) {
                m.types.alt(a)
            } else {
                return c.err(format!("unknown type '{name}'"));
            }
        }
    })
}

struct BodyCx {
    vals: HashMap<String, Value>,
    defined: Vec<bool>,
    blocks: HashMap<String, Block>,
    terminated: Vec<bool>,
}

fn value(cx: &mut BodyCx, f: &mut Func, name: &str) -> Value {
    if let Some(v) = cx.vals.get(name) {
        return *v;
    }
    let v = f.new_value(Ty::UNIT);
    cx.vals.insert(name.to_string(), v);
    v
}

fn define(cx: &mut BodyCx, f: &mut Func, c: &Cur, name: &str, ty: Ty) -> Result<Value, ParseError> {
    let v = value(cx, f, name);
    if cx.defined.len() < f.values.len() {
        cx.defined.resize(f.values.len(), false);
    }
    if cx.defined[v.index()] {
        return c.err(format!("%{name} defined twice"));
    }
    cx.defined[v.index()] = true;
    f.values[v.index()] = ty;
    Ok(v)
}

fn parse_body(m: &mut Module, id: FuncId, h: &FnHeader) -> Result<(), ParseError> {
    // The placeholder keeps the signature so a function can call itself.
    let sig = &m.funcs[id.index()];
    let mut placeholder = Func::new(&sig.name, sig.params.clone(), sig.ret);
    placeholder.kind = sig.kind.clone();
    placeholder.linkage = sig.linkage;
    let mut f = std::mem::replace(&mut m.funcs[id.index()], placeholder);
    let mut cx = BodyCx {
        vals: HashMap::new(),
        defined: Vec::new(),
        blocks: HashMap::new(),
        terminated: Vec::new(),
    };
    cx.defined.resize(f.values.len(), false);
    let line0 = h.body.first().map(|b| b.0).unwrap_or(0);
    for (i, name) in h.names.iter().enumerate() {
        let v = f.blocks[0].params[i].value;
        if cx.vals.insert(name.clone(), v).is_some() {
            return Err(ParseError {
                line: line0,
                message: format!("parameter %{name} defined twice"),
            });
        }
        cx.defined[v.index()] = true;
    }
    // Tokenize and find labels.
    let mut lines: Vec<(usize, Vec<Tok>)> = Vec::new();
    for (n, l) in &h.body {
        let t = tokenize(l, *n)?;
        if !t.is_empty() {
            lines.push((*n, t));
        }
    }
    let is_label = |t: &[Tok]| {
        matches!(t.first(), Some(Tok::Ident(_)))
            && t.last() == Some(&Tok::P(':'))
            && !matches!(t.first(), Some(Tok::Ident(s)) if s == "switch")
    };
    let mut first = true;
    for (n, t) in &lines {
        if is_label(t) {
            let Tok::Ident(name) = &t[0] else {
                unreachable!()
            };
            if first {
                cx.blocks.insert(name.clone(), Block(0));
                first = false;
            } else {
                if cx.blocks.contains_key(name) {
                    return Err(ParseError {
                        line: *n,
                        message: format!("block {name} defined twice"),
                    });
                }
                let b = f.new_block();
                cx.blocks.insert(name.clone(), b);
            }
        } else if first {
            return Err(ParseError {
                line: *n,
                message: "function body must start with a block label".into(),
            });
        }
    }
    cx.terminated = vec![false; f.blocks.len()];
    let mut cur: Option<Block> = None;
    for (n, t) in &lines {
        let mut c = Cur {
            toks: t,
            pos: 0,
            line: *n,
        };
        if is_label(t) {
            let name = c.ident()?;
            let b = cx.blocks[&name];
            if b.index() != 0 && c.eat_p('(') {
                while !c.eat_p(')') {
                    let vn = c.val()?;
                    c.expect_p(':')?;
                    let own = c.eat_ident("own");
                    let ty = parse_ty(&mut c, m)?;
                    let v = define(&mut cx, &mut f, &c, &vn, ty)?;
                    f.blocks[b.index()].params.push(BlockParam {
                        value: v,
                        mode: if own { Mode::Own } else { Mode::Borrow },
                    });
                    c.eat_p(',');
                }
            } else if b.index() == 0 && c.eat_p('(') {
                return c.err("the entry block takes the function parameters");
            }
            cur = Some(b);
            continue;
        }
        let b = cur.expect("label checked above");
        if cx.terminated[b.index()] {
            return c.err("instruction after the block terminator");
        }
        parse_line(m, &mut f, &mut cx, &mut c, b)?;
    }
    if let Some(i) = cx.terminated.iter().position(|t| !t) {
        return Err(ParseError {
            line: line0,
            message: format!("block b{i} of @{} has no terminator", f.name),
        });
    }
    // Every referenced value must be defined.
    for (name, v) in &cx.vals {
        if !cx.defined.get(v.index()).copied().unwrap_or(false) {
            return Err(ParseError {
                line: line0,
                message: format!("%{name} is used but never defined in @{}", f.name),
            });
        }
    }
    m.funcs[id.index()] = f;
    Ok(())
}

fn parse_target(c: &mut Cur, f: &mut Func, cx: &mut BodyCx) -> Result<Target, ParseError> {
    let name = c.ident()?;
    let Some(&block) = cx.blocks.get(&name) else {
        return c.err(format!("unknown block {name}"));
    };
    let mut args = Vec::new();
    c.expect_p('(')?;
    while !c.eat_p(')') {
        let v = c.val()?;
        args.push(value(cx, f, &v));
        c.eat_p(',');
    }
    Ok(Target { block, args })
}

fn parse_line(
    m: &mut Module,
    f: &mut Func,
    cx: &mut BodyCx,
    c: &mut Cur,
    b: Block,
) -> Result<(), ParseError> {
    let mut res_name = None;
    let mut res_ty = None;
    if matches!(c.peek(), Some(Tok::Val(_))) {
        let n = c.val()?;
        c.expect_p(':')?;
        res_ty = Some(parse_ty(c, m)?);
        c.expect_p('=')?;
        res_name = Some(n);
    }
    let mn = c.ident()?;
    // Terminators.
    let term = match mn.as_str() {
        "br" => Some(Term::Br(parse_target(c, f, cx)?)),
        "br_if" => {
            let cn = c.val()?;
            let cond = value(cx, f, &cn);
            c.expect_p(',')?;
            let then = parse_target(c, f, cx)?;
            c.expect_p(',')?;
            let els = parse_target(c, f, cx)?;
            Some(Term::CondBr { cond, then, els })
        }
        "switch" => {
            let vn = c.val()?;
            let value_ = value(cx, f, &vn);
            c.expect_p('[')?;
            let mut cases = Vec::new();
            while !c.eat_p(']') {
                let k: i64 = c.num()?.parse().map_err(|_| ParseError {
                    line: c.line,
                    message: "bad switch constant".into(),
                })?;
                c.expect_p(':')?;
                cases.push((k, parse_target(c, f, cx)?));
                c.eat_p(',');
            }
            if !c.eat_ident("default") {
                return c.err("expected 'default'");
            }
            let default = parse_target(c, f, cx)?;
            Some(Term::Switch {
                value: value_,
                cases,
                default,
            })
        }
        "ret" => {
            if let Some(Tok::Val(_)) = c.peek() {
                let vn = c.val()?;
                Some(Term::Ret(Some(value(cx, f, &vn))))
            } else {
                Some(Term::Ret(None))
            }
        }
        "unreachable" => Some(Term::Unreachable),
        "fault" => {
            let kind = match c.next() {
                Some(Tok::Str(s)) => FaultKind::Message(m.add_string(&s)),
                Some(Tok::Ident(s)) => match s.as_str() {
                    "int_overflow" => FaultKind::IntOverflow,
                    "div_by_zero" => FaultKind::DivByZero,
                    "index_out_of_range" => FaultKind::IndexOutOfRange,
                    "none_unwrap" => FaultKind::NoneUnwrap,
                    "cancelled" => FaultKind::Cancelled,
                    "call_depth" => FaultKind::CallDepth,
                    "unreachable_code" => FaultKind::Unreachable,
                    o => return c.err(format!("unknown fault kind {o}")),
                },
                t => return c.err(format!("expected fault kind, found {t:?}")),
            };
            Some(Term::Fault(kind))
        }
        _ => None,
    };
    if let Some(t) = term {
        if res_name.is_some() {
            return c.err("terminators have no result");
        }
        let loc = if let Some(Tok::Loc(l)) = c.peek() {
            *l
        } else {
            Loc::NONE
        };
        if matches!(c.peek(), Some(Tok::Loc(_))) {
            c.next();
        }
        if !c.done() {
            return c.err("unexpected tokens after terminator");
        }
        let blk = &mut f.blocks[b.index()];
        blk.term = t;
        blk.term_loc = loc;
        cx.terminated[b.index()] = true;
        return Ok(());
    }
    // Instructions.
    let (op, cc) = if let Some(op) = Op::from_name(&mn) {
        (op, None)
    } else if let Some((head, tail)) = mn.rsplit_once('.') {
        match (Op::from_name(head), Cc::from_name(tail)) {
            (Some(op @ (Op::ICmp | Op::UICmp | Op::FCmp)), Some(cc)) => (op, Some(cc)),
            _ => return c.err(format!("unknown instruction '{mn}'")),
        }
    } else {
        return c.err(format!("unknown instruction '{mn}'"));
    };
    let info = op.info();
    if info.has_result != res_name.is_some() {
        return c.err(if info.has_result {
            format!("{mn} needs a result: %v: type = {mn} ...")
        } else {
            format!("{mn} has no result")
        });
    }
    let imm = match info.imm {
        ImmKind::None => Imm::None,
        ImmKind::Cc => match cc {
            Some(cc) => Imm::Cc(cc),
            None => return c.err(format!("{mn} needs a condition such as {mn}.eq")),
        },
        ImmKind::Int => {
            let s = c.num()?;
            Imm::Int(s.parse().map_err(|_| ParseError {
                line: c.line,
                message: format!("bad integer {s}"),
            })?)
        }
        ImmKind::Float => {
            let s = c.num()?;
            if let Some(h) = s.strip_prefix("0x") {
                Imm::Float(u64::from_str_radix(h, 16).map_err(|_| ParseError {
                    line: c.line,
                    message: format!("bad float bits {s}"),
                })?)
            } else {
                Imm::Float(
                    s.parse::<f64>()
                        .map_err(|_| ParseError {
                            line: c.line,
                            message: format!("bad float {s}"),
                        })?
                        .to_bits(),
                )
            }
        }
        ImmKind::Bool => match c.ident()?.as_str() {
            "true" => Imm::Bool(true),
            "false" => Imm::Bool(false),
            o => return c.err(format!("expected true or false, found {o}")),
        },
        ImmKind::Str => {
            let s = c.string()?;
            Imm::Str(m.add_string(&s))
        }
        ImmKind::Func => {
            let n = c.at()?;
            Imm::Func(m.func_by_name(&n).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown function @{n}"),
            })?)
        }
        ImmKind::Ext => {
            let n = c.at()?;
            Imm::Ext(ExtId(
                m.externs
                    .iter()
                    .position(|e| e.name == n)
                    .ok_or_else(|| ParseError {
                        line: c.line,
                        message: format!("unknown extern @{n}"),
                    })? as u32,
            ))
        }
        ImmKind::Vtable => {
            let n = c.at()?;
            Imm::Vtable(VtableId(
                m.vtables
                    .iter()
                    .position(|e| e.name == n)
                    .ok_or_else(|| ParseError {
                        line: c.line,
                        message: format!("unknown vtable @{n}"),
                    })? as u32,
            ))
        }
        ImmKind::Global => {
            let n = c.at()?;
            Imm::Global(GlobalId(
                m.globals
                    .iter()
                    .position(|e| e.name == n)
                    .ok_or_else(|| ParseError {
                        line: c.line,
                        message: format!("unknown global @{n}"),
                    })? as u32,
            ))
        }
        ImmKind::Ty => Imm::Ty(parse_ty(c, m)?),
        ImmKind::Idx => Imm::Idx(c.num()?.parse().map_err(|_| ParseError {
            line: c.line,
            message: "bad index".into(),
        })?),
        ImmKind::Rec => {
            let n = c.ident()?;
            Imm::Rec(m.record_by_name(&n).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown record {n}"),
            })?)
        }
        ImmKind::Field => {
            let n = c.ident()?;
            let (r, fld) = n.split_once('.').ok_or_else(|| ParseError {
                line: c.line,
                message: "expected Record.field".into(),
            })?;
            let rid = m.record_by_name(r).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown record {r}"),
            })?;
            let fi = m.records[rid.index()]
                .fields
                .iter()
                .position(|x| x.0 == fld)
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown field {n}"),
                })?;
            Imm::Field(rid, fi as u32)
        }
        ImmKind::Case => {
            let n = c.ident()?;
            let (a, cs) = n.split_once('.').ok_or_else(|| ParseError {
                line: c.line,
                message: "expected Alt.Case".into(),
            })?;
            let aid = m.alt_by_name(a).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown alternative {a}"),
            })?;
            let ci = m.alts[aid.index()]
                .cases
                .iter()
                .position(|x| x.name == cs)
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown case {n}"),
                })?;
            Imm::Case(aid, ci as u32)
        }
        ImmKind::AltField => {
            let n = c.ident()?;
            let parts: Vec<&str> = n.split('.').collect();
            if parts.len() != 3 {
                return c.err("expected Alt.Case.field");
            }
            let aid = m.alt_by_name(parts[0]).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown alternative {}", parts[0]),
            })?;
            let ci = m.alts[aid.index()]
                .cases
                .iter()
                .position(|x| x.name == parts[1])
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown case {n}"),
                })?;
            let fi = m.alts[aid.index()].cases[ci]
                .fields
                .iter()
                .position(|x| x.0 == parts[2])
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown field {n}"),
                })?;
            Imm::AltField(aid, ci as u32, fi as u32)
        }
        ImmKind::AltMask => {
            let n = c.ident()?;
            let parts: Vec<&str> = n.split('.').collect();
            if parts.len() < 2 {
                return c.err("expected Alt.Case.field...");
            }
            let aid = m.alt_by_name(parts[0]).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown alternative {}", parts[0]),
            })?;
            let ci = m.alts[aid.index()]
                .cases
                .iter()
                .position(|x| x.name == parts[1])
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown case {n}"),
                })?;
            let mut mask = 0u32;
            for name in &parts[2..] {
                let fi = m.alts[aid.index()].cases[ci]
                    .fields
                    .iter()
                    .position(|x| x.0 == *name)
                    .ok_or_else(|| ParseError {
                        line: c.line,
                        message: format!("unknown field {n}"),
                    })?;
                mask |= 1 << fi;
            }
            Imm::AltMask(aid, ci as u32, mask)
        }
        ImmKind::RecMask => {
            let n = c.ident()?;
            let parts: Vec<&str> = n.split('.').collect();
            let rid = m.record_by_name(parts[0]).ok_or_else(|| ParseError {
                line: c.line,
                message: format!("unknown record {}", parts[0]),
            })?;
            let mut mask = 0u32;
            for name in &parts[1..] {
                let fi = m.records[rid.index()]
                    .fields
                    .iter()
                    .position(|x| x.0 == *name)
                    .ok_or_else(|| ParseError {
                        line: c.line,
                        message: format!("unknown field {n}"),
                    })?;
                mask |= 1 << fi;
            }
            Imm::RecMask(rid, mask)
        }
        ImmKind::Method => {
            let n = c.ident()?;
            let (i, mt) = n.split_once('.').ok_or_else(|| ParseError {
                line: c.line,
                message: "expected Interface.method".into(),
            })?;
            let iid = m
                .ifaces
                .iter()
                .position(|x| x.name == i)
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown interface {i}"),
                })?;
            let mi = m.ifaces[iid]
                .methods
                .iter()
                .position(|x| x.name == mt)
                .ok_or_else(|| ParseError {
                    line: c.line,
                    message: format!("unknown method {n}"),
                })?;
            Imm::Method(IfaceId(iid as u32), mi as u32)
        }
    };
    let mut args = Vec::new();
    let parens = op.is_call();
    if parens {
        c.expect_p('(')?;
    }
    while let Some(Tok::Val(_)) = c.peek() {
        let vn = c.val()?;
        args.push(value(cx, f, &vn));
        if !c.eat_p(',') {
            break;
        }
    }
    if parens {
        c.expect_p(')')?;
    }
    let mut loc = Loc::NONE;
    if let Some(Tok::Loc(l)) = c.peek() {
        loc = *l;
        c.next();
    }
    if !c.done() {
        return c.err(format!("unexpected {:?} after instruction", c.peek()));
    }
    let res = match (res_name, res_ty) {
        (Some(n), Some(t)) => Some(define(cx, f, c, &n, t)?),
        _ => None,
    };
    f.blocks[b.index()].insts.push(Inst {
        op,
        args,
        imm,
        res,
        loc,
    });
    Ok(())
}
