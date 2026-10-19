//! Lexer and parser for the spike's Manuscript subset: records, alternatives,
//! functions, `let`/`mut`, `while`, `if`/`else`, `match`, `return`, calls,
//! methods, fields, and indexing, with layout-based blocks.

use std::fmt;

#[derive(Debug, Clone)]
pub struct Error {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

pub fn error<T>(line: usize, message: impl Into<String>) -> Result<T, Error> {
    Err(Error { line, message: message.into() })
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Ident(String),
    Int(i64),
    Float(f64),
    Str(String),
    Punct(&'static str),
    Newline,
    Indent,
    Dedent,
    Eof,
}

const PUNCTS: [&str; 24] = [
    "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "(", ")", "[", "]", ",", ":", ".", "+", "-",
    "*", "/", "%", "<", ">", "=", "!",
];

fn lex(src: &str) -> Result<Vec<(Tok, usize)>, Error> {
    let mut out = Vec::new();
    let mut indents = vec![0usize];
    let mut depth = 0usize;
    for (n, raw) in src.lines().enumerate() {
        let line = n + 1;
        let text = raw.trim_end();
        let body = text.trim_start();
        if body.is_empty() || body.starts_with('#') {
            continue;
        }
        if depth == 0 {
            let width = text.len() - body.len();
            if width > *indents.last().unwrap() {
                indents.push(width);
                out.push((Tok::Indent, line));
            }
            while width < *indents.last().unwrap() {
                indents.pop();
                out.push((Tok::Dedent, line));
            }
            if width != *indents.last().unwrap() {
                return error(line, "inconsistent indentation");
            }
        }
        let bytes = body.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            let c = bytes[i] as char;
            if c == ' ' {
                i += 1;
            } else if c == '#' {
                break;
            } else if c.is_ascii_alphabetic() || c == '_' {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                out.push((Tok::Ident(body[start..i].to_string()), line));
            } else if c.is_ascii_digit() {
                let start = i;
                while i < bytes.len() && bytes[i].is_ascii_digit() {
                    i += 1;
                }
                let float = i + 1 < bytes.len() && bytes[i] == b'.' && bytes[i + 1].is_ascii_digit();
                if float {
                    i += 1;
                    while i < bytes.len() && bytes[i].is_ascii_digit() {
                        i += 1;
                    }
                    out.push((Tok::Float(body[start..i].parse().unwrap()), line));
                } else {
                    match body[start..i].parse() {
                        Ok(v) => out.push((Tok::Int(v), line)),
                        Err(_) => return error(line, "integer literal out of range"),
                    }
                }
            } else if c == '"' {
                let start = i + 1;
                i = start;
                while i < bytes.len() && bytes[i] != b'"' {
                    i += 1;
                }
                if i == bytes.len() {
                    return error(line, "unterminated string");
                }
                out.push((Tok::Str(body[start..i].to_string()), line));
                i += 1;
            } else {
                let Some(p) = PUNCTS.iter().find(|p| body[i..].starts_with(**p)) else {
                    return error(line, format!("unexpected character `{c}`"));
                };
                match *p {
                    "(" | "[" => depth += 1,
                    ")" | "]" => depth = depth.saturating_sub(1),
                    _ => {}
                }
                out.push((Tok::Punct(p), line));
                i += p.len();
            }
        }
        if depth == 0 {
            out.push((Tok::Newline, line));
        }
    }
    let last = src.lines().count();
    while indents.len() > 1 {
        indents.pop();
        out.push((Tok::Dedent, last));
    }
    out.push((Tok::Eof, last));
    Ok(out)
}

#[derive(Debug, Clone, PartialEq)]
pub struct TypeExpr {
    pub name: String,
    pub args: Vec<TypeExpr>,
    pub line: usize,
}

#[derive(Debug)]
pub struct FieldDecl {
    pub name: String,
    pub ty: TypeExpr,
}

#[derive(Debug)]
pub struct CaseDecl {
    pub name: String,
    pub fields: Vec<FieldDecl>,
}

#[derive(Debug)]
pub enum TypeDecl {
    Record { name: String, fields: Vec<FieldDecl> },
    Alternatives { name: String, cases: Vec<CaseDecl> },
}

#[derive(Debug)]
pub struct Param {
    pub name: String,
    pub ty: TypeExpr,
    pub mutable: bool,
}

#[derive(Debug)]
pub struct FnDecl {
    pub name: String,
    pub params: Vec<Param>,
    pub ret: TypeExpr,
    pub body: Block,
    pub line: usize,
}

pub type Block = Vec<Stmt>;

#[derive(Debug)]
pub struct Stmt {
    pub kind: StmtKind,
    pub line: usize,
}

#[derive(Debug)]
pub struct Arm {
    pub case: String,
    pub binds: Vec<String>,
    pub body: Block,
    pub line: usize,
}

#[derive(Debug)]
pub enum StmtKind {
    Let { name: String, mutable: bool, ty: Option<TypeExpr>, init: Expr },
    Assign { target: Expr, op: Option<BinOp>, value: Expr },
    While { cond: Expr, body: Block },
    If { cond: Expr, then: Block, els: Option<Block> },
    Return(Expr),
    Match { scrutinee: Expr, arms: Vec<Arm> },
    Expr(Expr),
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    Or,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UnOp {
    Neg,
    Not,
}

#[derive(Debug)]
pub struct Arg {
    pub mutable: bool,
    pub expr: Expr,
}

#[derive(Debug)]
pub struct Expr {
    pub id: usize,
    pub kind: ExprKind,
    pub line: usize,
}

#[derive(Debug)]
pub enum ExprKind {
    Int(i64),
    Float(f64),
    Bool(bool),
    Str(String),
    Name(String),
    Unary(UnOp, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    Call { callee: String, args: Vec<Arg> },
    Method { recv: Box<Expr>, name: String, args: Vec<Expr> },
    Field(Box<Expr>, String),
    Index(Box<Expr>, Box<Expr>),
    New(TypeExpr),
}

pub struct Program {
    pub types: Vec<TypeDecl>,
    pub fns: Vec<FnDecl>,
    pub expr_count: usize,
}

struct Parser {
    toks: Vec<(Tok, usize)>,
    pos: usize,
    next_id: usize,
}

pub fn parse(src: &str) -> Result<Program, Error> {
    let mut p = Parser { toks: lex(src)?, pos: 0, next_id: 0 };
    let mut types = Vec::new();
    let mut fns = Vec::new();
    loop {
        match p.peek().clone() {
            Tok::Eof => break,
            Tok::Newline => p.pos += 1,
            Tok::Ident(k) if k == "type" => types.push(p.type_decl()?),
            Tok::Ident(k) if k == "fn" || k == "export" => fns.push(p.fn_decl()?),
            _ => return error(p.line(), "expected `type` or `fn`"),
        }
    }
    Ok(Program { types, fns, expr_count: p.next_id })
}

impl Parser {
    fn peek(&self) -> &Tok {
        &self.toks[self.pos].0
    }

    fn line(&self) -> usize {
        self.toks[self.pos].1
    }

    fn is_punct(&self, p: &str) -> bool {
        matches!(self.peek(), Tok::Punct(q) if *q == p)
    }

    fn is_keyword(&self, k: &str) -> bool {
        matches!(self.peek(), Tok::Ident(w) if w == k)
    }

    fn eat_punct(&mut self, p: &str) -> bool {
        let found = self.is_punct(p);
        if found {
            self.pos += 1;
        }
        found
    }

    fn eat_keyword(&mut self, k: &str) -> bool {
        let found = self.is_keyword(k);
        if found {
            self.pos += 1;
        }
        found
    }

    fn expect_punct(&mut self, p: &str) -> Result<(), Error> {
        if self.eat_punct(p) {
            return Ok(());
        }
        error(self.line(), format!("expected `{p}`, found {:?}", self.peek()))
    }

    fn expect(&mut self, t: Tok) -> Result<(), Error> {
        if *self.peek() == t {
            self.pos += 1;
            return Ok(());
        }
        error(self.line(), format!("expected {t:?}, found {:?}", self.peek()))
    }

    fn ident(&mut self) -> Result<String, Error> {
        if let Tok::Ident(name) = self.peek().clone() {
            self.pos += 1;
            return Ok(name);
        }
        error(self.line(), format!("expected a name, found {:?}", self.peek()))
    }

    fn type_expr(&mut self) -> Result<TypeExpr, Error> {
        let line = self.line();
        let name = self.ident()?;
        let mut args = Vec::new();
        if self.eat_punct("[") {
            loop {
                args.push(self.type_expr()?);
                if !self.eat_punct(",") {
                    break;
                }
            }
            self.expect_punct("]")?;
        }
        Ok(TypeExpr { name, args, line })
    }

    fn fields(&mut self) -> Result<Vec<FieldDecl>, Error> {
        let mut fields = Vec::new();
        if self.eat_punct("(") {
            while !self.eat_punct(")") {
                let name = self.ident()?;
                self.expect_punct(":")?;
                fields.push(FieldDecl { name, ty: self.type_expr()? });
                self.eat_punct(",");
            }
        }
        Ok(fields)
    }

    fn type_decl(&mut self) -> Result<TypeDecl, Error> {
        self.pos += 1;
        let name = self.ident()?;
        self.expect_punct(":")?;
        self.expect(Tok::Newline)?;
        self.expect(Tok::Indent)?;
        let mut fields = Vec::new();
        let mut cases = Vec::new();
        while !matches!(self.peek(), Tok::Dedent | Tok::Eof) {
            if self.eat_keyword("case") {
                let case = self.ident()?;
                cases.push(CaseDecl { name: case, fields: self.fields()? });
            } else {
                let field = self.ident()?;
                self.expect_punct(":")?;
                fields.push(FieldDecl { name: field, ty: self.type_expr()? });
            }
            self.expect(Tok::Newline)?;
        }
        self.expect(Tok::Dedent)?;
        if !cases.is_empty() && !fields.is_empty() {
            return error(self.line(), format!("`{name}` mixes fields and cases"));
        }
        if cases.is_empty() {
            return Ok(TypeDecl::Record { name, fields });
        }
        Ok(TypeDecl::Alternatives { name, cases })
    }

    fn fn_decl(&mut self) -> Result<FnDecl, Error> {
        self.eat_keyword("export");
        let line = self.line();
        if !self.eat_keyword("fn") {
            return error(line, "expected `fn`");
        }
        let name = self.ident()?;
        self.expect_punct("(")?;
        let mut params = Vec::new();
        while !self.eat_punct(")") {
            let mutable = self.eat_keyword("mut");
            let pname = self.ident()?;
            self.expect_punct(":")?;
            params.push(Param { name: pname, ty: self.type_expr()?, mutable });
            self.eat_punct(",");
        }
        let ret = self.type_expr()?;
        self.expect_punct(":")?;
        let body = self.block()?;
        Ok(FnDecl { name, params, ret, body, line })
    }

    fn block(&mut self) -> Result<Block, Error> {
        self.expect(Tok::Newline)?;
        self.expect(Tok::Indent)?;
        let mut stmts = Vec::new();
        while !matches!(self.peek(), Tok::Dedent | Tok::Eof) {
            stmts.push(self.stmt()?);
        }
        self.expect(Tok::Dedent)?;
        Ok(stmts)
    }

    fn stmt(&mut self) -> Result<Stmt, Error> {
        let line = self.line();
        let kind = if self.is_keyword("let") || self.is_keyword("mut") {
            let mutable = self.is_keyword("mut");
            self.pos += 1;
            let name = self.ident()?;
            let ty = if self.eat_punct(":") { Some(self.type_expr()?) } else { None };
            self.expect_punct("=")?;
            let init = self.expr()?;
            self.expect(Tok::Newline)?;
            StmtKind::Let { name, mutable, ty, init }
        } else if self.eat_keyword("while") {
            let cond = self.expr()?;
            self.expect_punct(":")?;
            StmtKind::While { cond, body: self.block()? }
        } else if self.eat_keyword("if") {
            return self.if_stmt(line);
        } else if self.eat_keyword("return") {
            let value = self.expr()?;
            self.expect(Tok::Newline)?;
            StmtKind::Return(value)
        } else if self.eat_keyword("match") {
            let scrutinee = self.expr()?;
            self.expect_punct(":")?;
            self.expect(Tok::Newline)?;
            self.expect(Tok::Indent)?;
            let mut arms = Vec::new();
            while !matches!(self.peek(), Tok::Dedent | Tok::Eof) {
                let arm_line = self.line();
                let case = self.ident()?;
                let mut binds = Vec::new();
                if self.eat_punct("(") {
                    while !self.eat_punct(")") {
                        binds.push(self.ident()?);
                        self.eat_punct(",");
                    }
                }
                self.expect_punct(":")?;
                arms.push(Arm { case, binds, body: self.block()?, line: arm_line });
            }
            self.expect(Tok::Dedent)?;
            StmtKind::Match { scrutinee, arms }
        } else {
            let target = self.expr()?;
            let op = match self.peek() {
                Tok::Punct("=") => Some(None),
                Tok::Punct("+=") => Some(Some(BinOp::Add)),
                Tok::Punct("-=") => Some(Some(BinOp::Sub)),
                Tok::Punct("*=") => Some(Some(BinOp::Mul)),
                Tok::Punct("/=") => Some(Some(BinOp::Div)),
                _ => None,
            };
            let kind = match op {
                Some(op) => {
                    self.pos += 1;
                    StmtKind::Assign { target, op, value: self.expr()? }
                }
                None => StmtKind::Expr(target),
            };
            self.expect(Tok::Newline)?;
            kind
        };
        Ok(Stmt { kind, line })
    }

    fn if_stmt(&mut self, line: usize) -> Result<Stmt, Error> {
        let cond = self.expr()?;
        self.expect_punct(":")?;
        let then = self.block()?;
        let mut els = None;
        if self.eat_keyword("else") {
            if self.eat_keyword("if") {
                let nested_line = self.line();
                els = Some(vec![self.if_stmt(nested_line)?]);
            } else {
                self.expect_punct(":")?;
                els = Some(self.block()?);
            }
        }
        Ok(Stmt { kind: StmtKind::If { cond, then, els }, line })
    }

    fn mk(&mut self, kind: ExprKind, line: usize) -> Expr {
        self.next_id += 1;
        Expr { id: self.next_id - 1, kind, line }
    }

    pub fn expr(&mut self) -> Result<Expr, Error> {
        self.binary(0)
    }

    fn binary(&mut self, level: usize) -> Result<Expr, Error> {
        const LEVELS: [&[(&str, BinOp)]; 5] = [
            &[("or", BinOp::Or)],
            &[("and", BinOp::And)],
            &[
                ("==", BinOp::Eq),
                ("!=", BinOp::Ne),
                ("<=", BinOp::Le),
                (">=", BinOp::Ge),
                ("<", BinOp::Lt),
                (">", BinOp::Gt),
            ],
            &[("+", BinOp::Add), ("-", BinOp::Sub)],
            &[("*", BinOp::Mul), ("/", BinOp::Div), ("%", BinOp::Mod)],
        ];
        if level == LEVELS.len() {
            return self.unary();
        }
        let mut lhs = self.binary(level + 1)?;
        loop {
            let line = self.line();
            let op = LEVELS[level].iter().find(|(s, _)| match self.peek() {
                Tok::Punct(p) => p == s,
                Tok::Ident(w) => w == s,
                _ => false,
            });
            let Some(&(_, op)) = op else { return Ok(lhs) };
            self.pos += 1;
            let rhs = self.binary(level + 1)?;
            lhs = self.mk(ExprKind::Binary(op, Box::new(lhs), Box::new(rhs)), line);
        }
    }

    fn unary(&mut self) -> Result<Expr, Error> {
        let line = self.line();
        if self.eat_keyword("not") {
            let e = self.unary()?;
            return Ok(self.mk(ExprKind::Unary(UnOp::Not, Box::new(e)), line));
        }
        if self.eat_punct("-") {
            let e = self.unary()?;
            if let ExprKind::Int(v) = e.kind {
                return Ok(self.mk(ExprKind::Int(-v), line));
            }
            if let ExprKind::Float(v) = e.kind {
                return Ok(self.mk(ExprKind::Float(-v), line));
            }
            return Ok(self.mk(ExprKind::Unary(UnOp::Neg, Box::new(e)), line));
        }
        self.postfix()
    }

    fn postfix(&mut self) -> Result<Expr, Error> {
        let mut e = self.primary()?;
        loop {
            let line = self.line();
            if self.eat_punct(".") {
                let name = self.ident()?;
                if self.eat_punct("(") {
                    let mut args = Vec::new();
                    while !self.eat_punct(")") {
                        args.push(self.expr()?);
                        self.eat_punct(",");
                    }
                    e = self.mk(ExprKind::Method { recv: Box::new(e), name, args }, line);
                } else {
                    e = self.mk(ExprKind::Field(Box::new(e), name), line);
                }
            } else if self.eat_punct("[") {
                let index = self.expr()?;
                self.expect_punct("]")?;
                e = self.mk(ExprKind::Index(Box::new(e), Box::new(index)), line);
            } else {
                return Ok(e);
            }
        }
    }

    fn primary(&mut self) -> Result<Expr, Error> {
        let line = self.line();
        let tok = self.peek().clone();
        self.pos += 1;
        let kind = match tok {
            Tok::Int(v) => ExprKind::Int(v),
            Tok::Float(v) => ExprKind::Float(v),
            Tok::Str(s) => ExprKind::Str(s),
            Tok::Punct("(") => {
                let e = self.expr()?;
                self.expect_punct(")")?;
                return Ok(e);
            }
            Tok::Ident(w) if w == "true" || w == "false" => ExprKind::Bool(w == "true"),
            Tok::Ident(name) if (name == "List" || name == "Map") && self.is_punct("[") => {
                self.pos -= 1;
                let ty = self.type_expr()?;
                self.expect_punct("(")?;
                self.expect_punct(")")?;
                ExprKind::New(ty)
            }
            Tok::Ident(name) => {
                if self.eat_punct("(") {
                    let mut args = Vec::new();
                    while !self.eat_punct(")") {
                        let mutable = self.eat_keyword("mut");
                        args.push(Arg { mutable, expr: self.expr()? });
                        self.eat_punct(",");
                    }
                    ExprKind::Call { callee: name, args }
                } else {
                    ExprKind::Name(name)
                }
            }
            t => return error(line, format!("expected an expression, found {t:?}")),
        };
        Ok(self.mk(kind, line))
    }
}
