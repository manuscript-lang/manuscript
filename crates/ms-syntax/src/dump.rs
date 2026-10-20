//! Canonical text dump of a [`Module`] for snapshot tests: two trees are equal
//! exactly when they agree node for node, position for position.

use crate::ast::*;
use crate::pos::Pos;
use std::fmt::Write;

/// Quotes `s` in the dump's string syntax (printable ASCII, other bytes as `\xNN`).
pub fn quote(s: &str) -> String {
    let mut out = String::new();
    q(&mut out, s);
    out
}

fn q(out: &mut String, s: &str) {
    out.push('"');
    for &c in s.as_bytes() {
        if (0x20..0x7f).contains(&c) && c != b'"' && c != b'\\' {
            out.push(c as char);
        } else {
            let _ = write!(out, "\\x{c:02x}");
        }
    }
    out.push('"');
}

fn pos(out: &mut String, p: Pos) {
    let _ = write!(out, "{}:{}:{}", p.line, p.column, p.offset);
}

struct D {
    b: String,
}

impl D {
    fn w(&mut self, s: &str) {
        self.b.push_str(s);
    }
    fn p(&mut self, p: Pos) {
        pos(&mut self.b, p);
    }
    fn q(&mut self, s: &str) {
        q(&mut self.b, s);
    }

    fn typ(&mut self, t: Option<&TypeRef>) {
        let Some(t) = t else {
            self.w("nil");
            return;
        };
        self.w("(type ");
        self.p(t.pos);
        self.w(" ");
        match &t.kind {
            TypeKind::Named { name, args } => {
                self.q(name.as_str());
                self.w(" ");
                self.types(args);
                self.w(" ");
                self.params(&[]);
                self.w(" nil)");
            }
            TypeKind::Fn { params, result } => {
                self.q("fn");
                self.w(" ");
                self.types(&[]);
                self.w(" ");
                self.params(params);
                self.w(" ");
                self.typ(Some(result));
                self.w(")");
            }
        }
    }
    fn types(&mut self, ts: &[TypeRef]) {
        self.w("[");
        for t in ts {
            self.typ(Some(t));
            self.w(" ");
        }
        self.w("]");
    }
    fn params(&mut self, ps: &[Param]) {
        self.w("[");
        for pm in ps {
            self.w("(param ");
            self.p(pm.pos);
            self.w(" ");
            self.q(pm.name.as_str());
            self.w(" ");
            self.typ(pm.ty.as_ref());
            self.w(" ");
            self.expr(pm.default.as_ref());
            self.w(") ");
        }
        self.w("]");
    }

    #[allow(clippy::too_many_arguments)]
    fn expr_fields(
        &mut self,
        e: &Expr,
        kind: &str,
        text: &str,
        left: Option<&Expr>,
        right: Option<&Expr>,
        args: &[Argument],
        types: &[TypeRef],
        elements: &[&Expr],
        parts: &[TextPart],
        params: &[Param],
        result: Option<&TypeRef>,
        body: &[Stmt],
        arms: &[Arm],
    ) {
        self.w("(expr ");
        self.p(e.pos);
        self.w(" ");
        self.w(kind);
        self.w(" ");
        self.q(text);
        self.w(" ");
        self.expr(left);
        self.w(" ");
        self.expr(right);
        self.w(" [");
        for a in args {
            self.w("(arg ");
            self.p(a.pos);
            self.w(" ");
            self.q(a.name.map(|n| n.as_str()).unwrap_or(""));
            self.w(" ");
            self.expr(Some(&a.value));
            self.w(") ");
        }
        self.w("] ");
        self.types(types);
        self.w(" [");
        for x in elements {
            self.expr(Some(x));
            self.w(" ");
        }
        self.w("] [");
        for part in parts {
            self.w("(part ");
            match part {
                TextPart::Lit(t) => {
                    self.q(t);
                    self.w(" nil");
                }
                TextPart::Interp(x) => {
                    self.q("");
                    self.w(" ");
                    self.expr(Some(x));
                }
            }
            self.w(") ");
        }
        self.w("] ");
        self.params(params);
        self.w(" ");
        self.typ(result);
        self.w(" ");
        self.body(body);
        self.w(" [");
        for a in arms {
            self.w("(arm ");
            self.p(a.pos);
            self.w(" ");
            self.expr(Some(&a.path));
            self.w(" [");
            for b in &a.bindings {
                self.w("(");
                self.q(b.name.as_str());
                self.w(" ");
                self.p(b.pos);
                self.w(") ");
            }
            self.w("] ");
            self.body(&a.body);
            self.w(" ");
            self.expr(a.value.as_ref());
            self.w(") ");
        }
        self.w("])");
    }

    fn expr(&mut self, e: Option<&Expr>) {
        let Some(e) = e else {
            self.w("nil");
            return;
        };
        let n = |s: &str| s.to_string();
        match &e.kind {
            ExprKind::Number(s) => self.expr_fields(
                e,
                "number",
                s.as_str(),
                None,
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Bool(b) => self.expr_fields(
                e,
                "bool",
                if *b { "true" } else { "false" },
                None,
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Unit => self.expr_fields(
                e,
                "unit",
                "unit",
                None,
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Text(parts) => self.expr_fields(
                e,
                "text",
                "",
                None,
                None,
                &[],
                &[],
                &[],
                parts,
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Name(s) => self.expr_fields(
                e,
                "name",
                s.as_str(),
                None,
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Member { left, name } => self.expr_fields(
                e,
                "member",
                name.as_str(),
                Some(left),
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Apply { left, types, value } => self.expr_fields(
                e,
                "apply",
                "",
                Some(left),
                value.as_deref(),
                &[],
                types,
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Index { left, index } => self.expr_fields(
                e,
                "index",
                "",
                Some(left),
                Some(index),
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::List(items) => {
                let els: Vec<&Expr> = items.iter().collect();
                self.expr_fields(
                    e,
                    "list",
                    &n("["),
                    None,
                    None,
                    &[],
                    &[],
                    &els,
                    &[],
                    &[],
                    None,
                    &[],
                    &[],
                )
            }
            ExprKind::Map(entries) => {
                let els: Vec<&Expr> = entries.iter().flat_map(|en| [&en.key, &en.value]).collect();
                self.expr_fields(
                    e,
                    "map",
                    &n("{"),
                    None,
                    None,
                    &[],
                    &[],
                    &els,
                    &[],
                    &[],
                    None,
                    &[],
                    &[],
                )
            }
            ExprKind::Unary { op, operand } => self.expr_fields(
                e,
                "unary",
                op.as_str(),
                None,
                Some(operand),
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Binary { op, left, right } => self.expr_fields(
                e,
                "binary",
                op.as_str(),
                Some(left),
                Some(right),
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Lambda(l) => self.expr_fields(
                e,
                "lambda",
                "",
                None,
                None,
                &[],
                &[],
                &[],
                &[],
                &l.params,
                l.result.as_deref(),
                &l.body,
                &[],
            ),
            ExprKind::Call { callee, args } => self.expr_fields(
                e,
                "call",
                "",
                Some(callee),
                None,
                args,
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                &[],
            ),
            ExprKind::Match { scrutinee, arms } => self.expr_fields(
                e,
                "match",
                "match",
                Some(scrutinee),
                None,
                &[],
                &[],
                &[],
                &[],
                &[],
                None,
                &[],
                arms,
            ),
        }
    }

    fn pattern(&mut self, p: Option<&Pattern>) {
        let Some(p) = p else {
            self.w("nil");
            return;
        };
        self.w("(pattern ");
        self.p(p.pos);
        self.w(" ");
        match &p.kind {
            PatternKind::Name(n) => {
                self.w("name ");
                self.q(n.as_str());
                self.w(" [] []");
            }
            PatternKind::List(els) => {
                self.w("list ");
                self.q("");
                self.w(" [");
                for e in els {
                    self.pattern(Some(e));
                    self.w(" ");
                }
                self.w("] []");
            }
            PatternKind::Record(fields) => {
                self.w("record ");
                self.q("");
                self.w(" [] [");
                for f in fields {
                    self.w("(pf ");
                    self.p(f.pos);
                    self.w(" ");
                    self.q(f.name.as_str());
                    self.w(" ");
                    self.pattern(Some(&f.pattern));
                    self.w(") ");
                }
                self.w("]");
            }
        }
        self.w(")");
    }

    fn body(&mut self, b: &[Stmt]) {
        self.w("[");
        for s in b {
            self.stmt(s);
            self.w(" ");
        }
        self.w("]");
    }

    #[allow(clippy::too_many_arguments)]
    fn stmt_fields(
        &mut self,
        s_pos: Pos,
        kind: &str,
        name: &str,
        compound: &str,
        mutable: bool,
        group: Option<Pos>,
        pattern: Option<&Pattern>,
        ty: Option<&TypeRef>,
        target: Option<&Expr>,
        value: Option<&Expr>,
        body: &[Stmt],
        else_body: &[Stmt],
    ) {
        self.w("(stmt ");
        self.p(s_pos);
        self.w(" ");
        self.w(kind);
        self.w(" ");
        self.q(name);
        self.w(" ");
        self.q(compound);
        let _ = write!(self.b, " {mutable} ");
        self.p(group.unwrap_or_default());
        self.w(" ");
        self.pattern(pattern);
        self.w(" ");
        self.typ(ty);
        self.w(" ");
        self.expr(target);
        self.w(" ");
        self.expr(value);
        self.w(" ");
        self.body(body);
        self.w(" ");
        self.body(else_body);
        self.w(")");
    }

    fn stmt(&mut self, s: &Stmt) {
        let sp = s.pos;
        match &s.kind {
            StmtKind::Bind {
                mutable,
                pattern,
                ty,
                value,
                group,
            } => self.stmt_fields(
                sp,
                "bind",
                "",
                "",
                *mutable,
                *group,
                Some(pattern),
                ty.as_ref(),
                None,
                Some(value),
                &[],
                &[],
            ),
            StmtKind::Assign {
                target,
                compound,
                value,
            } => {
                let c = compound.map(|o| o.as_str()).unwrap_or("");
                match target {
                    AssignTarget::Name(n) => self.stmt_fields(
                        sp,
                        "assign",
                        n.as_str(),
                        c,
                        false,
                        None,
                        None,
                        None,
                        None,
                        Some(value),
                        &[],
                        &[],
                    ),
                    AssignTarget::Member(t) => self.stmt_fields(
                        sp,
                        "assign",
                        "",
                        c,
                        false,
                        None,
                        None,
                        None,
                        Some(t),
                        Some(value),
                        &[],
                        &[],
                    ),
                }
            }
            StmtKind::Call(e) => self.stmt_fields(
                sp,
                "call",
                "",
                "",
                false,
                None,
                None,
                None,
                None,
                Some(e),
                &[],
                &[],
            ),
            StmtKind::Return(e) => self.stmt_fields(
                sp,
                "return",
                "",
                "",
                false,
                None,
                None,
                None,
                None,
                e.as_ref(),
                &[],
                &[],
            ),
            StmtKind::Break => self.stmt_fields(
                sp,
                "break",
                "",
                "",
                false,
                None,
                None,
                None,
                None,
                None,
                &[],
                &[],
            ),
            StmtKind::Continue => self.stmt_fields(
                sp,
                "continue",
                "",
                "",
                false,
                None,
                None,
                None,
                None,
                None,
                &[],
                &[],
            ),
            StmtKind::If {
                binding,
                mutable,
                cond,
                body,
                else_body,
            } => self.stmt_fields(
                sp,
                "if",
                "",
                "",
                *mutable,
                None,
                binding.as_ref(),
                None,
                None,
                Some(cond),
                body,
                else_body,
            ),
            StmtKind::While { cond, body } => self.stmt_fields(
                sp,
                "while",
                "",
                "",
                false,
                None,
                None,
                None,
                None,
                Some(cond),
                body,
                &[],
            ),
            StmtKind::For { name, iter, body } => self.stmt_fields(
                sp,
                "for",
                name.as_str(),
                "",
                false,
                None,
                None,
                None,
                None,
                Some(iter),
                body,
                &[],
            ),
            StmtKind::With { name, value, body } => self.stmt_fields(
                sp,
                "with",
                name.as_str(),
                "",
                false,
                None,
                None,
                None,
                None,
                Some(value),
                body,
                &[],
            ),
        }
    }

    fn type_params(&mut self, tps: &[TypeParam]) {
        self.w("[");
        for tp in tps {
            self.w("(tp ");
            self.p(tp.pos);
            self.w(" ");
            self.q(tp.name.as_str());
            self.w(" ");
            self.types(&tp.bounds);
            self.w(" ");
            self.typ(tp.default.as_ref());
            self.w(") ");
        }
        self.w("]");
    }

    #[allow(clippy::too_many_arguments)]
    fn decl_fields(
        &mut self,
        dpos: Pos,
        kind: &str,
        name: &str,
        export: bool,
        constant: bool,
        group: Option<Pos>,
        synthetic: bool,
        tparams: &[TypeParam],
        fields: &[Param],
        cases: &[Case],
        methods: &[Method],
        params: &[Param],
        result: Option<&TypeRef>,
        contract: Option<&TypeRef>,
        receiver: Option<&TypeRef>,
        body: &[Stmt],
    ) {
        self.w("(decl ");
        self.p(dpos);
        self.w(" ");
        self.w(kind);
        self.w(" ");
        self.q(name);
        let _ = write!(self.b, " {export} {constant} ");
        self.p(group.unwrap_or_default());
        let _ = write!(self.b, " {synthetic} ");
        self.type_params(tparams);
        self.w(" ");
        self.params(fields);
        self.w(" [");
        for c in cases {
            self.w("(case ");
            self.p(c.pos);
            self.w(" ");
            self.q(c.name.as_str());
            self.w(" ");
            self.params(&c.fields);
            self.w(") ");
        }
        self.w("] [");
        for m in methods {
            self.method(m);
            self.w(" ");
        }
        self.w("] ");
        self.params(params);
        self.w(" ");
        self.typ(result);
        self.w(" ");
        self.typ(contract);
        self.w(" ");
        self.typ(receiver);
        self.w(" ");
        self.body(body);
        self.w(")");
    }

    fn method(&mut self, m: &Method) {
        let f = &m.func;
        self.decl_fields(
            m.pos,
            "fn",
            f.name.as_str(),
            false,
            false,
            None,
            false,
            &f.type_params,
            &[],
            &[],
            &[],
            &f.params,
            Some(&f.result),
            None,
            None,
            &f.body,
        );
    }

    fn decl(&mut self, d: &Decl) {
        let e = d.export;
        let sy = d.synthetic;
        match &d.kind {
            DeclKind::Fn(f) => self.decl_fields(
                d.pos,
                "fn",
                f.name.as_str(),
                e,
                false,
                None,
                sy,
                &f.type_params,
                &[],
                &[],
                &[],
                &f.params,
                Some(&f.result),
                None,
                None,
                &f.body,
            ),
            DeclKind::Const(c) => {
                let placeholder = TypeRef {
                    id: NodeId(0),
                    pos: c.value.pos,
                    kind: TypeKind::Named {
                        name: crate::Symbol::intern(""),
                        args: Vec::new(),
                    },
                };
                let result = c.ty.as_ref().unwrap_or(&placeholder);
                let ret = Stmt {
                    id: NodeId(0),
                    pos: c.init_pos,
                    kind: StmtKind::Return(Some(c.value.clone())),
                };
                self.decl_fields(
                    d.pos,
                    "fn",
                    c.name.as_str(),
                    e,
                    true,
                    c.group,
                    sy,
                    &[],
                    &[],
                    &[],
                    &[],
                    &[],
                    Some(result),
                    None,
                    None,
                    std::slice::from_ref(&ret),
                );
            }
            DeclKind::Record(r) => self.decl_fields(
                d.pos,
                "record",
                r.name.as_str(),
                e,
                false,
                None,
                sy,
                &r.type_params,
                &r.fields,
                &[],
                &[],
                &[],
                None,
                None,
                None,
                &[],
            ),
            DeclKind::Alternative(a) => self.decl_fields(
                d.pos,
                "alternative",
                a.name.as_str(),
                e,
                false,
                None,
                sy,
                &a.type_params,
                &[],
                &a.cases,
                &[],
                &[],
                None,
                None,
                None,
                &[],
            ),
            DeclKind::Interface(i) => self.decl_fields(
                d.pos,
                "interface",
                i.name.as_str(),
                e,
                false,
                None,
                sy,
                &i.type_params,
                &[],
                &[],
                &i.methods,
                &[],
                None,
                None,
                None,
                &[],
            ),
            DeclKind::Impl(i) => self.decl_fields(
                d.pos,
                "impl",
                "",
                e,
                false,
                None,
                sy,
                &[],
                &[],
                &[],
                &i.methods,
                &[],
                None,
                i.contract.as_ref(),
                Some(&i.receiver),
                &[],
            ),
            DeclKind::Test(t) => {
                let unit = TypeRef {
                    id: NodeId(0),
                    pos: d.pos,
                    kind: TypeKind::Named {
                        name: crate::Symbol::intern("Unit"),
                        args: Vec::new(),
                    },
                };
                self.decl_fields(
                    d.pos,
                    "test",
                    &t.name,
                    e,
                    false,
                    None,
                    sy,
                    &[],
                    &[],
                    &[],
                    &[],
                    &[],
                    Some(&unit),
                    None,
                    None,
                    &t.body,
                )
            }
        }
    }
}

/// Dumps a module (imports, declarations, omitted names, recovered spans).
pub fn dump_module(m: &Module) -> String {
    let mut d = D { b: String::new() };
    for i in &m.imports {
        d.w("import ");
        d.p(i.pos);
        d.w(" ");
        d.p(i.name_pos);
        d.w(" ");
        d.q(i.name.as_str());
        d.w(" ");
        d.q(&i.path);
        d.w("\n");
    }
    for x in &m.decls {
        d.decl(x);
        d.w("\n");
    }
    d.w("omitted [");
    for o in &m.omitted {
        d.q(o);
        d.w(" ");
    }
    d.w("]\nrecovered [");
    for r in &m.recovered {
        let _ = write!(d.b, "{}-{} ", r.start, r.end);
    }
    d.w("]\n");
    d.b
}
