use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::io::{self, Read, Write};

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
enum V {
    Null,
    Int(i64),
    Text(Vec<u8>),
    Bool(bool),
}

type Res<T> = Result<T, String>;

fn syn<T>() -> Res<T> {
    Err("syntax error".to_string())
}

fn type_err<T>() -> Res<T> {
    Err("type error".to_string())
}

fn wrong_args<T>(name: &str) -> Res<T> {
    Err(format!("wrong number of arguments to {}", name))
}

fn show(v: &V) -> Vec<u8> {
    match v {
        V::Null => b"NULL".to_vec(),
        V::Int(i) => i.to_string().into_bytes(),
        V::Text(s) => s.clone(),
        V::Bool(b) => {
            if *b {
                b"true".to_vec()
            } else {
                b"false".to_vec()
            }
        }
    }
}

// Encodes a tuple of values into a hashable, self-delimiting key.
fn keyb(vs: &[V]) -> Vec<u8> {
    let mut k = Vec::new();
    for v in vs {
        match v {
            V::Null => k.push(0),
            V::Bool(b) => {
                k.push(1);
                k.push(*b as u8);
            }
            V::Int(i) => {
                k.push(2);
                k.extend_from_slice(&i.to_be_bytes());
            }
            V::Text(s) => {
                k.push(3);
                k.extend_from_slice(&(s.len() as u64).to_be_bytes());
                k.extend_from_slice(s);
            }
        }
    }
    k
}

fn rank(v: &V) -> u8 {
    match v {
        V::Null => 0,
        V::Bool(_) => 1,
        V::Int(_) => 2,
        V::Text(_) => 3,
    }
}

// Total order used by ORDER BY: NULL < BOOL < INT < TEXT.
fn ordcmp(a: &V, b: &V) -> Ordering {
    match (a, b) {
        (V::Int(x), V::Int(y)) => x.cmp(y),
        (V::Text(x), V::Text(y)) => x.cmp(y),
        (V::Bool(x), V::Bool(y)) => x.cmp(y),
        _ => rank(a).cmp(&rank(b)),
    }
}

// Comparison with SQL semantics: None means NULL.
fn cmp_vals(a: &V, b: &V) -> Res<Option<Ordering>> {
    match (a, b) {
        (V::Null, _) | (_, V::Null) => Ok(None),
        (V::Int(x), V::Int(y)) => Ok(Some(x.cmp(y))),
        (V::Text(x), V::Text(y)) => Ok(Some(x.cmp(y))),
        _ => type_err(),
    }
}

fn to_logic(v: &V) -> Res<Option<bool>> {
    match v {
        V::Bool(b) => Ok(Some(*b)),
        V::Null => Ok(None),
        _ => type_err(),
    }
}

fn and3(l: Option<bool>, r: Option<bool>) -> Option<bool> {
    if r == Some(false) {
        Some(false)
    } else if l == Some(true) && r == Some(true) {
        Some(true)
    } else {
        None
    }
}

fn or3(l: Option<bool>, r: Option<bool>) -> Option<bool> {
    if r == Some(true) {
        Some(true)
    } else if l == Some(false) && r == Some(false) {
        Some(false)
    } else {
        None
    }
}

fn from3(o: Option<bool>) -> V {
    match o {
        Some(b) => V::Bool(b),
        None => V::Null,
    }
}

// WHERE / HAVING / ON: only TRUE keeps a row; NULL and FALSE drop it.
fn truthy(v: &V) -> Res<bool> {
    Ok(to_logic(v)? == Some(true))
}

fn like(s: &[u8], p: &[u8]) -> bool {
    let (mut i, mut j) = (0usize, 0usize);
    let (mut star, mut mark) = (usize::MAX, 0usize);
    while i < s.len() {
        if j < p.len() && p[j] != b'%' && (p[j] == b'_' || p[j] == s[i]) {
            i += 1;
            j += 1;
        } else if j < p.len() && p[j] == b'%' {
            star = j;
            mark = i;
            j += 1;
        } else if star != usize::MAX {
            j = star + 1;
            mark += 1;
            i = mark;
        } else {
            return false;
        }
    }
    while j < p.len() && p[j] == b'%' {
        j += 1;
    }
    j == p.len()
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

const KEYWORDS: &[&str] = &[
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT",
    "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO",
    "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT",
    "ASC", "DESC",
];

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Id(String),
    Kw(&'static str),
    Int(i64),
    Str(Vec<u8>),
    Op(&'static str),
}

// Splits the script at `;` that are outside string literals and comments.
fn split_statements(s: &[u8]) -> Vec<&[u8]> {
    let mut out = Vec::new();
    let n = s.len();
    let mut i = 0;
    let mut st = 0;
    let mut in_str = false;
    while i < n {
        let c = s[i];
        if in_str {
            if c == b'\'' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        match c {
            b'\'' => {
                in_str = true;
                i += 1;
            }
            b'-' if i + 1 < n && s[i + 1] == b'-' => {
                while i < n && s[i] != b'\n' {
                    i += 1;
                }
            }
            b';' => {
                out.push(&s[st..i]);
                i += 1;
                st = i;
            }
            _ => i += 1,
        }
    }
    out.push(&s[st..]);
    out
}

fn lex(s: &[u8]) -> Res<Vec<Tok>> {
    let mut out = Vec::new();
    let n = s.len();
    let mut i = 0;
    while i < n {
        let c = s[i];
        match c {
            b' ' | b'\t' | b'\r' | b'\n' => i += 1,
            b'-' if i + 1 < n && s[i + 1] == b'-' => {
                while i < n && s[i] != b'\n' {
                    i += 1;
                }
            }
            b'a'..=b'z' | b'A'..=b'Z' | b'_' => {
                let st = i;
                while i < n && (s[i].is_ascii_alphanumeric() || s[i] == b'_') {
                    i += 1;
                }
                let w = String::from_utf8_lossy(&s[st..i]).to_string();
                let up = w.to_ascii_uppercase();
                match KEYWORDS.iter().find(|k| **k == up) {
                    Some(k) => out.push(Tok::Kw(*k)),
                    None => out.push(Tok::Id(w)),
                }
            }
            b'0'..=b'9' => {
                let st = i;
                while i < n && s[i].is_ascii_digit() {
                    i += 1;
                }
                let t = String::from_utf8_lossy(&s[st..i]).to_string();
                match t.parse::<i64>() {
                    Ok(v) => out.push(Tok::Int(v)),
                    Err(_) => return syn(),
                }
            }
            b'\'' => {
                i += 1;
                let mut v = Vec::new();
                loop {
                    if i >= n {
                        return syn();
                    }
                    if s[i] == b'\'' {
                        if i + 1 < n && s[i + 1] == b'\'' {
                            v.push(b'\'');
                            i += 2;
                        } else {
                            i += 1;
                            break;
                        }
                    } else {
                        v.push(s[i]);
                        i += 1;
                    }
                }
                out.push(Tok::Str(v));
            }
            _ => {
                let two: &[u8] = if i + 1 < n { &s[i..i + 2] } else { &[] };
                let (op, len): (&'static str, usize) = match two {
                    b"<>" => ("<>", 2),
                    b"!=" => ("<>", 2),
                    b"<=" => ("<=", 2),
                    b">=" => (">=", 2),
                    b"||" => ("||", 2),
                    _ => match c {
                        b'=' => ("=", 1),
                        b'<' => ("<", 1),
                        b'>' => (">", 1),
                        b'+' => ("+", 1),
                        b'-' => ("-", 1),
                        b'*' => ("*", 1),
                        b'/' => ("/", 1),
                        b'%' => ("%", 1),
                        b'(' => ("(", 1),
                        b')' => (")", 1),
                        b',' => (",", 1),
                        b'.' => (".", 1),
                        _ => return syn(),
                    },
                };
                out.push(Tok::Op(op));
                i += len;
            }
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Debug)]
enum B {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Cat,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

enum Ast {
    Lit(V),
    Col(Option<String>, String),
    Neg(Box<Ast>),
    Not(Box<Ast>),
    Bin(B, Box<Ast>, Box<Ast>),
    And(Box<Ast>, Box<Ast>),
    Or(Box<Ast>, Box<Ast>),
    IsNull(Box<Ast>, bool),
    Like(Box<Ast>, Box<Ast>, bool),
    In(Box<Ast>, Vec<Ast>, bool),
    Between(Box<Ast>, Box<Ast>, Box<Ast>, bool),
    Call {
        name: String,
        distinct: bool,
        star: bool,
        args: Vec<Ast>,
    },
}

#[derive(Clone)]
struct ColDef {
    name: String,
    is_int: bool,
    not_null: bool,
    pk: bool,
}

struct TRef {
    table: String,
    alias: String,
}

struct Join {
    left: bool,
    tref: TRef,
    on: Ast,
}

enum Item {
    Star,
    TStar(String),
    Expr(Ast, Option<String>),
}

struct Select {
    distinct: bool,
    items: Vec<Item>,
    from: Option<TRef>,
    joins: Vec<Join>,
    wh: Option<Ast>,
    group: Vec<(Option<String>, String)>,
    having: Option<Ast>,
    order: Vec<(Ast, bool)>,
    limit: Option<(i64, i64)>,
}

enum Stmt {
    Create { name: String, cols: Vec<ColDef> },
    Drop(String),
    Insert { table: String, cols: Option<Vec<String>>, rows: Vec<Vec<Ast>> },
    Update { table: String, sets: Vec<(String, Ast)>, wh: Option<Ast> },
    Delete { table: String, wh: Option<Ast> },
    Select(Select),
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

struct P {
    t: Vec<Tok>,
    p: usize,
}

impl P {
    fn peek(&self) -> Option<&Tok> {
        self.t.get(self.p)
    }

    fn peek_at(&self, k: usize) -> Option<&Tok> {
        self.t.get(self.p + k)
    }

    fn peek_clone(&self) -> Option<Tok> {
        self.t.get(self.p).cloned()
    }

    fn is_kw(&self, k: &str) -> bool {
        matches!(self.peek(), Some(Tok::Kw(x)) if *x == k)
    }

    fn eat_kw(&mut self, k: &str) -> bool {
        if self.is_kw(k) {
            self.p += 1;
            true
        } else {
            false
        }
    }

    fn expect_kw(&mut self, k: &str) -> Res<()> {
        if self.eat_kw(k) {
            Ok(())
        } else {
            syn()
        }
    }

    fn is_op(&self, o: &str) -> bool {
        matches!(self.peek(), Some(Tok::Op(x)) if *x == o)
    }

    fn eat_op(&mut self, o: &str) -> bool {
        if self.is_op(o) {
            self.p += 1;
            true
        } else {
            false
        }
    }

    fn expect_op(&mut self, o: &str) -> Res<()> {
        if self.eat_op(o) {
            Ok(())
        } else {
            syn()
        }
    }

    fn ident(&mut self) -> Res<String> {
        match self.peek_clone() {
            Some(Tok::Id(s)) => {
                self.p += 1;
                Ok(s)
            }
            _ => syn(),
        }
    }

    fn int_lit(&mut self) -> Res<i64> {
        match self.peek_clone() {
            Some(Tok::Int(n)) => {
                self.p += 1;
                Ok(n)
            }
            _ => syn(),
        }
    }

    fn create(&mut self) -> Res<Stmt> {
        self.expect_kw("TABLE")?;
        let name = self.ident()?;
        self.expect_op("(")?;
        let mut cols = Vec::new();
        loop {
            let cname = self.ident()?;
            let ty = match self.peek_clone() {
                Some(Tok::Id(t)) => t.to_ascii_uppercase(),
                _ => return syn(),
            };
            self.p += 1;
            let is_int = match ty.as_str() {
                "INT" => true,
                "TEXT" => false,
                _ => return syn(),
            };
            let mut pk = false;
            let mut nn = false;
            loop {
                if self.eat_kw("PRIMARY") {
                    self.expect_kw("KEY")?;
                    pk = true;
                    nn = true;
                } else if self.eat_kw("NOT") {
                    self.expect_kw("NULL")?;
                    nn = true;
                } else {
                    break;
                }
            }
            cols.push(ColDef {
                name: cname,
                is_int,
                not_null: nn,
                pk,
            });
            if !self.eat_op(",") {
                break;
            }
        }
        self.expect_op(")")?;
        Ok(Stmt::Create { name, cols })
    }

    fn insert(&mut self) -> Res<Stmt> {
        self.expect_kw("INTO")?;
        let table = self.ident()?;
        let mut cols = None;
        if self.eat_op("(") {
            let mut v = vec![self.ident()?];
            while self.eat_op(",") {
                v.push(self.ident()?);
            }
            self.expect_op(")")?;
            cols = Some(v);
        }
        self.expect_kw("VALUES")?;
        let mut rows = Vec::new();
        loop {
            self.expect_op("(")?;
            let mut r = vec![self.expr()?];
            while self.eat_op(",") {
                r.push(self.expr()?);
            }
            self.expect_op(")")?;
            rows.push(r);
            if !self.eat_op(",") {
                break;
            }
        }
        Ok(Stmt::Insert { table, cols, rows })
    }

    fn update(&mut self) -> Res<Stmt> {
        let table = self.ident()?;
        self.expect_kw("SET")?;
        let mut sets = Vec::new();
        loop {
            let c = self.ident()?;
            self.expect_op("=")?;
            let e = self.expr()?;
            sets.push((c, e));
            if !self.eat_op(",") {
                break;
            }
        }
        let wh = if self.eat_kw("WHERE") {
            Some(self.expr()?)
        } else {
            None
        };
        Ok(Stmt::Update { table, sets, wh })
    }

    fn delete(&mut self) -> Res<Stmt> {
        self.expect_kw("FROM")?;
        let table = self.ident()?;
        let wh = if self.eat_kw("WHERE") {
            Some(self.expr()?)
        } else {
            None
        };
        Ok(Stmt::Delete { table, wh })
    }

    fn colref(&mut self) -> Res<(Option<String>, String)> {
        let a = self.ident()?;
        if self.eat_op(".") {
            let b = self.ident()?;
            Ok((Some(a), b))
        } else {
            Ok((None, a))
        }
    }

    fn tref(&mut self) -> Res<TRef> {
        let table = self.ident()?;
        let alias = if self.eat_kw("AS") {
            self.ident()?
        } else if let Some(Tok::Id(a)) = self.peek_clone() {
            self.p += 1;
            a
        } else {
            table.clone()
        };
        Ok(TRef { table, alias })
    }

    fn item(&mut self) -> Res<Item> {
        if self.eat_op("*") {
            return Ok(Item::Star);
        }
        let tstar = match (self.peek_at(0), self.peek_at(1), self.peek_at(2)) {
            (Some(Tok::Id(a)), Some(Tok::Op(".")), Some(Tok::Op("*"))) => Some(a.clone()),
            _ => None,
        };
        if let Some(a) = tstar {
            self.p += 3;
            return Ok(Item::TStar(a));
        }
        let e = self.expr()?;
        let alias = if self.eat_kw("AS") {
            Some(self.ident()?)
        } else {
            None
        };
        Ok(Item::Expr(e, alias))
    }

    fn select(&mut self) -> Res<Select> {
        self.expect_kw("SELECT")?;
        let distinct = self.eat_kw("DISTINCT");
        let mut items = vec![self.item()?];
        while self.eat_op(",") {
            items.push(self.item()?);
        }
        let mut from = None;
        let mut joins = Vec::new();
        if self.eat_kw("FROM") {
            from = Some(self.tref()?);
            loop {
                let left = if self.eat_kw("LEFT") {
                    self.expect_kw("JOIN")?;
                    true
                } else if self.eat_kw("INNER") {
                    self.expect_kw("JOIN")?;
                    false
                } else if self.eat_kw("JOIN") {
                    false
                } else {
                    break;
                };
                let tref = self.tref()?;
                self.expect_kw("ON")?;
                let on = self.expr()?;
                joins.push(Join { left, tref, on });
            }
        }
        let wh = if self.eat_kw("WHERE") {
            Some(self.expr()?)
        } else {
            None
        };
        let mut group = Vec::new();
        if self.eat_kw("GROUP") {
            self.expect_kw("BY")?;
            group.push(self.colref()?);
            while self.eat_op(",") {
                group.push(self.colref()?);
            }
        }
        let having = if self.eat_kw("HAVING") {
            Some(self.expr()?)
        } else {
            None
        };
        let mut order = Vec::new();
        if self.eat_kw("ORDER") {
            self.expect_kw("BY")?;
            loop {
                let e = self.expr()?;
                let desc = self.eat_kw("DESC");
                if !desc {
                    self.eat_kw("ASC");
                }
                order.push((e, desc));
                if !self.eat_op(",") {
                    break;
                }
            }
        }
        let mut limit = None;
        if self.eat_kw("LIMIT") {
            let n = self.int_lit()?;
            let mut off = 0;
            if self.eat_kw("OFFSET") {
                off = self.int_lit()?;
            }
            limit = Some((n, off));
        }
        Ok(Select {
            distinct,
            items,
            from,
            joins,
            wh,
            group,
            having,
            order,
            limit,
        })
    }

    fn expr(&mut self) -> Res<Ast> {
        let mut l = self.and_()?;
        while self.eat_kw("OR") {
            let r = self.and_()?;
            l = Ast::Or(Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn and_(&mut self) -> Res<Ast> {
        let mut l = self.not_()?;
        while self.eat_kw("AND") {
            let r = self.not_()?;
            l = Ast::And(Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn not_(&mut self) -> Res<Ast> {
        if self.eat_kw("NOT") {
            Ok(Ast::Not(Box::new(self.not_()?)))
        } else {
            self.cmp()
        }
    }

    fn cmp(&mut self) -> Res<Ast> {
        let l = self.add()?;
        let op = match self.peek() {
            Some(Tok::Op(o)) => match *o {
                "=" => Some(B::Eq),
                "<>" => Some(B::Ne),
                "<" => Some(B::Lt),
                "<=" => Some(B::Le),
                ">" => Some(B::Gt),
                ">=" => Some(B::Ge),
                _ => None,
            },
            _ => None,
        };
        if let Some(op) = op {
            self.p += 1;
            let r = self.add()?;
            return Ok(Ast::Bin(op, Box::new(l), Box::new(r)));
        }
        if self.eat_kw("IS") {
            let neg = self.eat_kw("NOT");
            self.expect_kw("NULL")?;
            return Ok(Ast::IsNull(Box::new(l), neg));
        }
        let save = self.p;
        let neg = self.eat_kw("NOT");
        if self.eat_kw("LIKE") {
            let r = self.add()?;
            return Ok(Ast::Like(Box::new(l), Box::new(r), neg));
        }
        if self.eat_kw("IN") {
            self.expect_op("(")?;
            let mut list = vec![self.expr()?];
            while self.eat_op(",") {
                list.push(self.expr()?);
            }
            self.expect_op(")")?;
            return Ok(Ast::In(Box::new(l), list, neg));
        }
        if self.eat_kw("BETWEEN") {
            let lo = self.add()?;
            self.expect_kw("AND")?;
            let hi = self.add()?;
            return Ok(Ast::Between(Box::new(l), Box::new(lo), Box::new(hi), neg));
        }
        self.p = save;
        Ok(l)
    }

    fn add(&mut self) -> Res<Ast> {
        let mut l = self.mul()?;
        loop {
            let op = match self.peek() {
                Some(Tok::Op("+")) => B::Add,
                Some(Tok::Op("-")) => B::Sub,
                Some(Tok::Op("||")) => B::Cat,
                _ => break,
            };
            self.p += 1;
            let r = self.mul()?;
            l = Ast::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn mul(&mut self) -> Res<Ast> {
        let mut l = self.unary()?;
        loop {
            let op = match self.peek() {
                Some(Tok::Op("*")) => B::Mul,
                Some(Tok::Op("/")) => B::Div,
                Some(Tok::Op("%")) => B::Mod,
                _ => break,
            };
            self.p += 1;
            let r = self.unary()?;
            l = Ast::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn unary(&mut self) -> Res<Ast> {
        if self.eat_op("-") {
            Ok(Ast::Neg(Box::new(self.unary()?)))
        } else {
            self.primary()
        }
    }

    fn primary(&mut self) -> Res<Ast> {
        match self.peek_clone() {
            Some(Tok::Int(n)) => {
                self.p += 1;
                Ok(Ast::Lit(V::Int(n)))
            }
            Some(Tok::Str(s)) => {
                self.p += 1;
                Ok(Ast::Lit(V::Text(s)))
            }
            Some(Tok::Kw("NULL")) => {
                self.p += 1;
                Ok(Ast::Lit(V::Null))
            }
            Some(Tok::Op("(")) => {
                self.p += 1;
                let e = self.expr()?;
                self.expect_op(")")?;
                Ok(e)
            }
            Some(Tok::Id(name)) => {
                self.p += 1;
                if self.eat_op("(") {
                    self.call(name)
                } else if self.eat_op(".") {
                    let c = self.ident()?;
                    Ok(Ast::Col(Some(name), c))
                } else {
                    Ok(Ast::Col(None, name))
                }
            }
            _ => syn(),
        }
    }

    fn call(&mut self, name: String) -> Res<Ast> {
        let name = name.to_ascii_uppercase();
        let distinct = self.eat_kw("DISTINCT");
        let mut star = false;
        let mut args = Vec::new();
        if self.eat_op("*") {
            star = true;
        } else if !self.is_op(")") {
            args.push(self.expr()?);
            while self.eat_op(",") {
                args.push(self.expr()?);
            }
        }
        self.expect_op(")")?;
        Ok(Ast::Call {
            name,
            distinct,
            star,
            args,
        })
    }
}

fn parse_statement(toks: Vec<Tok>) -> Res<Stmt> {
    let mut p = P { t: toks, p: 0 };
    let st = if p.eat_kw("CREATE") {
        p.create()?
    } else if p.eat_kw("DROP") {
        p.expect_kw("TABLE")?;
        Stmt::Drop(p.ident()?)
    } else if p.eat_kw("INSERT") {
        p.insert()?
    } else if p.eat_kw("UPDATE") {
        p.update()?
    } else if p.eat_kw("DELETE") {
        p.delete()?
    } else if p.is_kw("SELECT") {
        Stmt::Select(p.select()?)
    } else {
        return syn();
    };
    if p.p != p.t.len() {
        return syn();
    }
    Ok(st)
}

// ---------------------------------------------------------------------------
// Compiled expressions (column references resolved to indices)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Sf {
    Upper,
    Lower,
    Length,
    Abs,
    Substr,
    Coalesce,
}

#[derive(Clone, Copy, PartialEq)]
enum Ag {
    Count,
    Sum,
    Min,
    Max,
}

enum R {
    Lit(V),
    Col(usize),
    Neg(Box<R>),
    Not(Box<R>),
    Bin(B, Box<R>, Box<R>),
    And(Box<R>, Box<R>),
    Or(Box<R>, Box<R>),
    IsNull(Box<R>, bool),
    Like(Box<R>, Box<R>, bool),
    In(Box<R>, Vec<R>, bool),
    Between(Box<R>, Box<R>, Box<R>, bool),
    Func(Sf, Vec<R>),
    Agg(Ag, bool, Option<Box<R>>),
}

struct Src {
    alias: String,
    cols: Vec<String>,
    off: usize,
}

#[derive(Clone, Copy)]
struct Cx<'a> {
    srcs: &'a [Src],
    aggs: bool,
    agg_query: bool,
    group: &'a [usize],
    in_agg: bool,
}

fn plain(srcs: &[Src]) -> Cx<'_> {
    Cx {
        srcs,
        aggs: false,
        agg_query: false,
        group: &[],
        in_agg: false,
    }
}

fn resolve(srcs: &[Src], q: Option<&str>, n: &str) -> Res<usize> {
    match q {
        Some(q) => {
            for s in srcs {
                if s.alias == q {
                    if let Some(p) = s.cols.iter().position(|c| c == n) {
                        return Ok(s.off + p);
                    }
                    break;
                }
            }
            Err(format!("no such column: {}.{}", q, n))
        }
        None => {
            let mut found = None;
            let mut cnt = 0;
            for s in srcs {
                for (p, c) in s.cols.iter().enumerate() {
                    if c == n {
                        cnt += 1;
                        if found.is_none() {
                            found = Some(s.off + p);
                        }
                    }
                }
            }
            match cnt {
                0 => Err(format!("no such column: {}", n)),
                1 => Ok(found.unwrap()),
                _ => Err(format!("ambiguous column: {}", n)),
            }
        }
    }
}

fn check_group(cx: &Cx, i: usize, name: &str) -> Res<()> {
    if cx.agg_query && !cx.in_agg && !cx.group.contains(&i) {
        Err(format!("column {} must appear in GROUP BY", name))
    } else {
        Ok(())
    }
}

fn contains_agg(a: &Ast) -> bool {
    match a {
        Ast::Lit(_) | Ast::Col(..) => false,
        Ast::Neg(x) | Ast::Not(x) | Ast::IsNull(x, _) => contains_agg(x),
        Ast::Bin(_, l, r) | Ast::And(l, r) | Ast::Or(l, r) | Ast::Like(l, r, _) => {
            contains_agg(l) || contains_agg(r)
        }
        Ast::In(x, list, _) => contains_agg(x) || list.iter().any(contains_agg),
        Ast::Between(x, l, h, _) => contains_agg(x) || contains_agg(l) || contains_agg(h),
        Ast::Call { name, args, .. } => {
            matches!(name.as_str(), "COUNT" | "SUM" | "MIN" | "MAX") || args.iter().any(contains_agg)
        }
    }
}

fn compile(a: &Ast, cx: Cx) -> Res<R> {
    Ok(match a {
        Ast::Lit(v) => R::Lit(v.clone()),
        Ast::Col(q, n) => {
            let i = resolve(cx.srcs, q.as_deref(), n)?;
            let shown = match q {
                Some(q) => format!("{}.{}", q, n),
                None => n.clone(),
            };
            check_group(&cx, i, &shown)?;
            R::Col(i)
        }
        Ast::Neg(x) => R::Neg(Box::new(compile(x, cx)?)),
        Ast::Not(x) => R::Not(Box::new(compile(x, cx)?)),
        Ast::Bin(op, l, r) => {
            let l = compile(l, cx)?;
            let r = compile(r, cx)?;
            R::Bin(*op, Box::new(l), Box::new(r))
        }
        Ast::And(l, r) => {
            let l = compile(l, cx)?;
            let r = compile(r, cx)?;
            R::And(Box::new(l), Box::new(r))
        }
        Ast::Or(l, r) => {
            let l = compile(l, cx)?;
            let r = compile(r, cx)?;
            R::Or(Box::new(l), Box::new(r))
        }
        Ast::IsNull(x, n) => R::IsNull(Box::new(compile(x, cx)?), *n),
        Ast::Like(x, p, n) => {
            let x = compile(x, cx)?;
            let p = compile(p, cx)?;
            R::Like(Box::new(x), Box::new(p), *n)
        }
        Ast::In(x, list, n) => {
            let x = compile(x, cx)?;
            let mut rl = Vec::new();
            for e in list {
                rl.push(compile(e, cx)?);
            }
            R::In(Box::new(x), rl, *n)
        }
        Ast::Between(x, lo, hi, n) => {
            let x = compile(x, cx)?;
            let lo = compile(lo, cx)?;
            let hi = compile(hi, cx)?;
            R::Between(Box::new(x), Box::new(lo), Box::new(hi), *n)
        }
        Ast::Call {
            name,
            distinct,
            star,
            args,
        } => compile_call(name, *distinct, *star, args, cx)?,
    })
}

fn compile_call(name: &str, distinct: bool, star: bool, args: &[Ast], cx: Cx) -> Res<R> {
    let ag = match name {
        "COUNT" => Some(Ag::Count),
        "SUM" => Some(Ag::Sum),
        "MIN" => Some(Ag::Min),
        "MAX" => Some(Ag::Max),
        _ => None,
    };
    if let Some(ag) = ag {
        if !cx.aggs || cx.in_agg {
            return Err("misuse of aggregate".to_string());
        }
        if star {
            if ag == Ag::Count && !distinct {
                return Ok(R::Agg(Ag::Count, false, None));
            }
            return wrong_args(name);
        }
        if args.len() != 1 {
            return wrong_args(name);
        }
        let inner = Cx {
            in_agg: true,
            ..cx
        };
        let a = compile(&args[0], inner)?;
        return Ok(R::Agg(ag, distinct, Some(Box::new(a))));
    }
    let (f, arity) = match name {
        "UPPER" => (Sf::Upper, 1),
        "LOWER" => (Sf::Lower, 1),
        "LENGTH" => (Sf::Length, 1),
        "ABS" => (Sf::Abs, 1),
        "SUBSTR" => (Sf::Substr, 3),
        "COALESCE" => (Sf::Coalesce, 0),
        _ => return Err(format!("no such function: {}", name)),
    };
    let count_ok = if f == Sf::Coalesce {
        !args.is_empty()
    } else {
        args.len() == arity
    };
    if star || !count_ok || (distinct && args.len() != 1) {
        return wrong_args(name);
    }
    let mut ra = Vec::new();
    for a in args {
        ra.push(compile(a, cx)?);
    }
    Ok(R::Func(f, ra))
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

fn bin(op: B, a: V, b: V) -> Res<V> {
    match op {
        B::Add | B::Sub | B::Mul | B::Div | B::Mod => {
            if matches!(a, V::Null) || matches!(b, V::Null) {
                return Ok(V::Null);
            }
            let (x, y) = match (a, b) {
                (V::Int(x), V::Int(y)) => (x, y),
                _ => return type_err(),
            };
            Ok(V::Int(match op {
                B::Add => x.wrapping_add(y),
                B::Sub => x.wrapping_sub(y),
                B::Mul => x.wrapping_mul(y),
                B::Div => {
                    if y == 0 {
                        return Err("division by zero".to_string());
                    }
                    x.wrapping_div(y)
                }
                _ => {
                    if y == 0 {
                        return Err("division by zero".to_string());
                    }
                    x.wrapping_rem(y)
                }
            }))
        }
        B::Cat => match (a, b) {
            (V::Null, _) | (_, V::Null) => Ok(V::Null),
            (V::Text(x), V::Text(y)) => {
                let mut z = x;
                z.extend_from_slice(&y);
                Ok(V::Text(z))
            }
            _ => type_err(),
        },
        _ => match cmp_vals(&a, &b)? {
            None => Ok(V::Null),
            Some(o) => Ok(V::Bool(match op {
                B::Eq => o == Ordering::Equal,
                B::Ne => o != Ordering::Equal,
                B::Lt => o == Ordering::Less,
                B::Le => o != Ordering::Greater,
                B::Gt => o == Ordering::Greater,
                _ => o != Ordering::Less,
            })),
        },
    }
}

fn scalar(f: Sf, v: &[V]) -> Res<V> {
    match f {
        Sf::Coalesce => Ok(v
            .iter()
            .find(|x| !matches!(x, V::Null))
            .cloned()
            .unwrap_or(V::Null)),
        Sf::Upper => match &v[0] {
            V::Text(s) => Ok(V::Text(s.to_ascii_uppercase())),
            _ => type_err(),
        },
        Sf::Lower => match &v[0] {
            V::Text(s) => Ok(V::Text(s.to_ascii_lowercase())),
            _ => type_err(),
        },
        Sf::Length => match &v[0] {
            V::Text(s) => Ok(V::Int(s.len() as i64)),
            _ => type_err(),
        },
        Sf::Abs => match &v[0] {
            V::Int(i) => Ok(V::Int(i.wrapping_abs())),
            _ => type_err(),
        },
        Sf::Substr => match (&v[0], &v[1], &v[2]) {
            (V::Text(s), V::Int(st), V::Int(ln)) => {
                let st = *st as i128;
                let ln = *ln as i128;
                let n = s.len() as i128;
                if ln <= 0 {
                    return Ok(V::Text(Vec::new()));
                }
                let lo = st.max(1);
                let hi = (st + ln - 1).min(n);
                if lo > hi {
                    Ok(V::Text(Vec::new()))
                } else {
                    Ok(V::Text(s[(lo - 1) as usize..hi as usize].to_vec()))
                }
            }
            _ => type_err(),
        },
    }
}

fn agg(kind: Ag, distinct: bool, arg: Option<&R>, grp: &[&[V]]) -> Res<V> {
    let a = match arg {
        None => return Ok(V::Int(grp.len() as i64)),
        Some(a) => a,
    };
    let mut vals: Vec<V> = Vec::new();
    for r in grp {
        let v = eval(a, r, &[])?;
        if !matches!(v, V::Null) {
            vals.push(v);
        }
    }
    if distinct {
        let mut seen: HashSet<Vec<u8>> = HashSet::new();
        vals.retain(|v| seen.insert(keyb(std::slice::from_ref(v))));
    }
    Ok(match kind {
        Ag::Count => V::Int(vals.len() as i64),
        Ag::Sum => {
            if vals.is_empty() {
                V::Null
            } else {
                let mut s: i64 = 0;
                for v in &vals {
                    match v {
                        V::Int(i) => s = s.wrapping_add(*i),
                        _ => return type_err(),
                    }
                }
                V::Int(s)
            }
        }
        Ag::Min | Ag::Max => {
            let mut best: Option<V> = None;
            for v in vals {
                let replace = match &best {
                    None => {
                        if !matches!(v, V::Int(_) | V::Text(_)) {
                            return type_err();
                        }
                        true
                    }
                    Some(b) => {
                        let o = cmp_vals(b, &v)?.unwrap_or(Ordering::Equal);
                        if kind == Ag::Min {
                            o == Ordering::Greater
                        } else {
                            o == Ordering::Less
                        }
                    }
                };
                if replace {
                    best = Some(v);
                }
            }
            best.unwrap_or(V::Null)
        }
    })
}

fn eval(r: &R, row: &[V], grp: &[&[V]]) -> Res<V> {
    Ok(match r {
        R::Lit(v) => v.clone(),
        R::Col(i) => row[*i].clone(),
        R::Neg(x) => match eval(x, row, grp)? {
            V::Null => V::Null,
            V::Int(i) => V::Int(i.wrapping_neg()),
            _ => return type_err(),
        },
        R::Not(x) => from3(to_logic(&eval(x, row, grp)?)?.map(|b| !b)),
        R::Bin(op, a, b) => {
            let va = eval(a, row, grp)?;
            let vb = eval(b, row, grp)?;
            bin(*op, va, vb)?
        }
        R::And(a, b) => {
            let l = to_logic(&eval(a, row, grp)?)?;
            if l == Some(false) {
                V::Bool(false)
            } else {
                let rr = to_logic(&eval(b, row, grp)?)?;
                from3(and3(l, rr))
            }
        }
        R::Or(a, b) => {
            let l = to_logic(&eval(a, row, grp)?)?;
            if l == Some(true) {
                V::Bool(true)
            } else {
                let rr = to_logic(&eval(b, row, grp)?)?;
                from3(or3(l, rr))
            }
        }
        R::IsNull(x, neg) => {
            let n = matches!(eval(x, row, grp)?, V::Null);
            V::Bool(n != *neg)
        }
        R::Like(x, p, neg) => {
            let s = eval(x, row, grp)?;
            let pt = eval(p, row, grp)?;
            match (s, pt) {
                (V::Null, _) | (_, V::Null) => V::Null,
                (V::Text(s), V::Text(p)) => V::Bool(like(&s, &p) != *neg),
                _ => return type_err(),
            }
        }
        R::In(x, list, neg) => {
            let vx = eval(x, row, grp)?;
            let mut found = false;
            let mut sawnull = false;
            for e in list {
                let v = eval(e, row, grp)?;
                if matches!(vx, V::Null) {
                    continue;
                }
                if matches!(v, V::Null) {
                    sawnull = true;
                    continue;
                }
                if cmp_vals(&vx, &v)? == Some(Ordering::Equal) {
                    found = true;
                }
            }
            let res = if matches!(vx, V::Null) {
                None
            } else if found {
                Some(true)
            } else if sawnull {
                None
            } else {
                Some(false)
            };
            match res {
                None => V::Null,
                Some(b) => V::Bool(b != *neg),
            }
        }
        R::Between(x, lo, hi, neg) => {
            let vx = eval(x, row, grp)?;
            let vl = eval(lo, row, grp)?;
            let vh = eval(hi, row, grp)?;
            let ge = cmp_vals(&vx, &vl)?.map(|o| o != Ordering::Less);
            let res = if ge == Some(false) {
                Some(false)
            } else {
                let le = cmp_vals(&vx, &vh)?.map(|o| o != Ordering::Greater);
                and3(ge, le)
            };
            match res {
                None => V::Null,
                Some(b) => V::Bool(b != *neg),
            }
        }
        R::Func(f, args) => {
            let mut vals = Vec::with_capacity(args.len());
            for a in args {
                vals.push(eval(a, row, grp)?);
            }
            if *f == Sf::Coalesce {
                scalar(*f, &vals)?
            } else if vals.iter().any(|v| matches!(v, V::Null)) {
                V::Null
            } else {
                scalar(*f, &vals)?
            }
        }
        R::Agg(kind, distinct, arg) => agg(*kind, *distinct, arg.as_deref(), grp)?,
    })
}

// ---------------------------------------------------------------------------
// Database and statements
// ---------------------------------------------------------------------------

struct Table {
    name: String,
    cols: Vec<ColDef>,
    rows: Vec<Vec<V>>,
}

struct Db {
    tables: Vec<Table>,
}

impl Db {
    fn pos(&self, n: &str) -> Option<usize> {
        self.tables.iter().position(|t| t.name == n)
    }
}

// Per-row constraints shared by INSERT and UPDATE.
fn check_row(t: &Table, row: &[V]) -> Res<()> {
    for (c, v) in t.cols.iter().zip(row) {
        if matches!(v, V::Null) {
            if c.not_null || c.pk {
                return Err(format!("NOT NULL constraint failed: {}", c.name));
            }
        } else {
            let ok = match v {
                V::Int(_) => c.is_int,
                V::Text(_) => !c.is_int,
                _ => false,
            };
            if !ok {
                return Err(format!("type mismatch in column {}", c.name));
            }
        }
    }
    Ok(())
}

fn check_pk(t: &Table, rows: &[Vec<V>]) -> Res<()> {
    if let Some(pi) = t.cols.iter().position(|c| c.pk) {
        let mut seen: HashSet<Vec<u8>> = HashSet::new();
        for r in rows {
            if !seen.insert(keyb(std::slice::from_ref(&r[pi]))) {
                return Err(format!(
                    "duplicate primary key: {}",
                    String::from_utf8_lossy(&show(&r[pi]))
                ));
            }
        }
    }
    Ok(())
}

fn table_src(t: &Table) -> Vec<Src> {
    vec![Src {
        alias: t.name.clone(),
        cols: t.cols.iter().map(|c| c.name.clone()).collect(),
        off: 0,
    }]
}

fn exec_insert(db: &mut Db, table: String, cols: Option<Vec<String>>, rows: Vec<Vec<Ast>>) -> Res<String> {
    let ti = db.pos(&table).ok_or_else(|| format!("no such table: {}", table))?;
    let t = &db.tables[ti];
    let targets: Vec<usize> = match cols {
        Some(names) => {
            let mut v: Vec<usize> = Vec::new();
            for n in names {
                let i = t
                    .cols
                    .iter()
                    .position(|c| c.name == n)
                    .ok_or_else(|| format!("no such column: {}", n))?;
                if v.contains(&i) {
                    return Err(format!("duplicate column: {}", n));
                }
                v.push(i);
            }
            v
        }
        None => (0..t.cols.len()).collect(),
    };
    let mut new_rows: Vec<Vec<V>> = Vec::new();
    for row in &rows {
        if row.len() != targets.len() {
            return Err("wrong number of values".to_string());
        }
        let mut vals = vec![V::Null; t.cols.len()];
        for (k, e) in row.iter().enumerate() {
            let r = compile(e, plain(&[]))?;
            vals[targets[k]] = eval(&r, &[], &[])?;
        }
        check_row(t, &vals)?;
        new_rows.push(vals);
    }
    let mut all = t.rows.clone();
    all.extend(new_rows.iter().cloned());
    check_pk(t, &all)?;
    let n = new_rows.len();
    db.tables[ti].rows.extend(new_rows);
    Ok(format!("inserted {}", n))
}

fn exec_update(db: &mut Db, table: String, sets: Vec<(String, Ast)>, wh: Option<Ast>) -> Res<String> {
    let ti = db.pos(&table).ok_or_else(|| format!("no such table: {}", table))?;
    let t = &db.tables[ti];
    let mut sidx = Vec::new();
    for (n, _) in &sets {
        let i = t
            .cols
            .iter()
            .position(|c| c.name == *n)
            .ok_or_else(|| format!("no such column: {}", n))?;
        sidx.push(i);
    }
    let srcs = table_src(t);
    let mut srs = Vec::new();
    for (_, e) in &sets {
        srs.push(compile(e, plain(&srcs))?);
    }
    let wr = match &wh {
        Some(w) => Some(compile(w, plain(&srcs))?),
        None => None,
    };
    let mut new_rows = t.rows.clone();
    let mut cnt = 0usize;
    for (ri, row) in t.rows.iter().enumerate() {
        let m = match &wr {
            Some(w) => truthy(&eval(w, row, &[])?)?,
            None => true,
        };
        if !m {
            continue;
        }
        cnt += 1;
        let mut nr = row.clone();
        for (k, r) in srs.iter().enumerate() {
            nr[sidx[k]] = eval(r, row, &[])?;
        }
        check_row(t, &nr)?;
        new_rows[ri] = nr;
    }
    check_pk(t, &new_rows)?;
    db.tables[ti].rows = new_rows;
    Ok(format!("updated {}", cnt))
}

fn exec_delete(db: &mut Db, table: String, wh: Option<Ast>) -> Res<String> {
    let ti = db.pos(&table).ok_or_else(|| format!("no such table: {}", table))?;
    let t = &db.tables[ti];
    let srcs = table_src(t);
    let wr = match &wh {
        Some(w) => Some(compile(w, plain(&srcs))?),
        None => None,
    };
    let mut keep = Vec::new();
    let mut cnt = 0usize;
    for row in &t.rows {
        let m = match &wr {
            Some(w) => truthy(&eval(w, row, &[])?)?,
            None => true,
        };
        if m {
            cnt += 1;
        } else {
            keep.push(row.clone());
        }
    }
    db.tables[ti].rows = keep;
    Ok(format!("deleted {}", cnt))
}

struct OutCol {
    name: String,
    r: R,
}

enum OKey {
    Out(usize),
    Expr(R),
}

fn run_select(db: &Db, s: &Select) -> Res<String> {
    // Step 1: tables and aliases.
    let mut trefs: Vec<&TRef> = Vec::new();
    if let Some(f) = &s.from {
        trefs.push(f);
    }
    for j in &s.joins {
        trefs.push(&j.tref);
    }
    let mut srcs: Vec<Src> = Vec::new();
    let mut tabs: Vec<&Table> = Vec::new();
    let mut width = 0usize;
    for t in &trefs {
        let tab = db
            .pos(&t.table)
            .map(|i| &db.tables[i])
            .ok_or_else(|| format!("no such table: {}", t.table))?;
        if srcs.iter().any(|x| x.alias == t.alias) {
            return Err(format!("duplicate alias: {}", t.alias));
        }
        let cols: Vec<String> = tab.cols.iter().map(|c| c.name.clone()).collect();
        let w = cols.len();
        srcs.push(Src {
            alias: t.alias.clone(),
            cols,
            off: width,
        });
        width += w;
        tabs.push(tab);
    }

    // Step 2: JOIN conditions, each against the sources visible so far.
    let mut on_r: Vec<R> = Vec::new();
    for (k, j) in s.joins.iter().enumerate() {
        on_r.push(compile(&j.on, plain(&srcs[..k + 2]))?);
    }

    // Step 3: stars.
    for it in &s.items {
        if let Item::TStar(a) = it {
            if !srcs.iter().any(|x| &x.alias == a) {
                return Err(format!("no such table: {}", a));
            }
        }
    }

    let agg_query = !s.group.is_empty()
        || s.having.is_some()
        || s.items.iter().any(|it| matches!(it, Item::Expr(e, _) if contains_agg(e)))
        || s.order.iter().any(|(e, _)| contains_agg(e));

    // Step 4: GROUP BY columns.
    let mut group: Vec<usize> = Vec::new();
    for (q, n) in &s.group {
        group.push(resolve(&srcs, q.as_deref(), n)?);
    }

    // Step 5: WHERE.
    let wh_r = match &s.wh {
        Some(w) => Some(compile(w, plain(&srcs))?),
        None => None,
    };

    let cx_sel = Cx {
        srcs: &srcs,
        aggs: true,
        agg_query,
        group: &group,
        in_agg: false,
    };

    // Step 6: select items.
    let mut outs: Vec<OutCol> = Vec::new();
    for it in &s.items {
        match it {
            Item::Star => {
                for src in &srcs {
                    for (p, c) in src.cols.iter().enumerate() {
                        check_group(&cx_sel, src.off + p, c)?;
                        outs.push(OutCol {
                            name: c.clone(),
                            r: R::Col(src.off + p),
                        });
                    }
                }
            }
            Item::TStar(a) => {
                let src = srcs.iter().find(|x| &x.alias == a).unwrap();
                for (p, c) in src.cols.iter().enumerate() {
                    check_group(&cx_sel, src.off + p, c)?;
                    outs.push(OutCol {
                        name: c.clone(),
                        r: R::Col(src.off + p),
                    });
                }
            }
            Item::Expr(e, alias) => {
                let r = compile(e, cx_sel)?;
                let name = match (alias, e) {
                    (Some(a), _) => a.clone(),
                    (None, Ast::Col(_, n)) => n.clone(),
                    _ => "?column?".to_string(),
                };
                outs.push(OutCol { name, r });
            }
        }
    }

    // Step 7: HAVING.
    let having_r = match &s.having {
        Some(h) => Some(compile(h, cx_sel)?),
        None => None,
    };

    // Step 8: ORDER BY.
    let mut okeys: Vec<(OKey, bool)> = Vec::new();
    for (e, desc) in &s.order {
        let k = match e {
            Ast::Lit(V::Int(n)) => {
                if *n >= 1 && *n <= outs.len() as i64 {
                    OKey::Out((*n - 1) as usize)
                } else {
                    return Err("bad ORDER BY position".to_string());
                }
            }
            Ast::Col(None, n) => match outs.iter().position(|o| o.name == *n) {
                Some(i) => OKey::Out(i),
                None => OKey::Expr(compile(e, cx_sel)?),
            },
            _ => OKey::Expr(compile(e, cx_sel)?),
        };
        okeys.push((k, *desc));
    }

    // ---- Execution ----
    let nulls: Vec<V> = vec![V::Null; width];

    let mut rows: Vec<Vec<V>> = if s.from.is_some() {
        tabs[0].rows.clone()
    } else {
        vec![vec![]]
    };

    for (k, j) in s.joins.iter().enumerate() {
        let inner = tabs[k + 1];
        let iw = inner.cols.len();
        let mut nr: Vec<Vec<V>> = Vec::new();
        for o in &rows {
            let mut matched = false;
            for ir in &inner.rows {
                let mut comb = o.clone();
                comb.extend(ir.iter().cloned());
                if truthy(&eval(&on_r[k], &comb, &[])?)? {
                    matched = true;
                    nr.push(comb);
                }
            }
            if !matched && j.left {
                let mut comb = o.clone();
                comb.extend(std::iter::repeat(V::Null).take(iw));
                nr.push(comb);
            }
        }
        rows = nr;
    }

    if let Some(w) = &wh_r {
        let mut nr: Vec<Vec<V>> = Vec::new();
        for r in rows {
            if truthy(&eval(w, &r, &[])?)? {
                nr.push(r);
            }
        }
        rows = nr;
    }

    // Groups (non-aggregated queries: each row is its own group).
    let groups: Vec<Vec<usize>> = if agg_query {
        if group.is_empty() {
            vec![(0..rows.len()).collect()]
        } else {
            let mut map: HashMap<Vec<u8>, usize> = HashMap::new();
            let mut gs: Vec<Vec<usize>> = Vec::new();
            for (i, r) in rows.iter().enumerate() {
                let kv: Vec<V> = group.iter().map(|&g| r[g].clone()).collect();
                let key = keyb(&kv);
                if let Some(&gi) = map.get(&key) {
                    gs[gi].push(i);
                } else {
                    map.insert(key, gs.len());
                    gs.push(vec![i]);
                }
            }
            gs
        }
    } else {
        (0..rows.len()).map(|i| vec![i]).collect()
    };

    let mut out: Vec<(Vec<V>, usize)> = Vec::new();
    for (gi, idx) in groups.iter().enumerate() {
        let grows: Vec<&[V]> = idx.iter().map(|&i| rows[i].as_slice()).collect();
        let rep: &[V] = if idx.is_empty() {
            nulls.as_slice()
        } else {
            rows[idx[0]].as_slice()
        };
        if let Some(h) = &having_r {
            if !truthy(&eval(h, rep, &grows)?)? {
                continue;
            }
        }
        let mut vals = Vec::with_capacity(outs.len());
        for o in &outs {
            vals.push(eval(&o.r, rep, &grows)?);
        }
        out.push((vals, gi));
    }

    if s.distinct {
        let mut seen: HashSet<Vec<u8>> = HashSet::new();
        out.retain(|(vals, _)| seen.insert(keyb(vals)));
    }

    let final_vals: Vec<Vec<V>> = if okeys.is_empty() {
        out.into_iter().map(|(v, _)| v).collect()
    } else {
        let mut tagged: Vec<(Vec<V>, Vec<V>)> = Vec::with_capacity(out.len());
        for (vals, gi) in out {
            let idx = &groups[gi];
            let grows: Vec<&[V]> = idx.iter().map(|&i| rows[i].as_slice()).collect();
            let rep: &[V] = if idx.is_empty() {
                nulls.as_slice()
            } else {
                rows[idx[0]].as_slice()
            };
            let mut ks = Vec::with_capacity(okeys.len());
            for (k, _) in &okeys {
                ks.push(match k {
                    OKey::Out(i) => vals[*i].clone(),
                    OKey::Expr(r) => eval(r, rep, &grows)?,
                });
            }
            tagged.push((ks, vals));
        }
        tagged.sort_by(|a, b| {
            for (j, (_, desc)) in okeys.iter().enumerate() {
                let o = ordcmp(&a.0[j], &b.0[j]);
                let o = if *desc { o.reverse() } else { o };
                if o != Ordering::Equal {
                    return o;
                }
            }
            Ordering::Equal
        });
        tagged.into_iter().map(|(_, v)| v).collect()
    };

    let (lim, off) = s.limit.unwrap_or((i64::MAX, 0));
    let final_rows: Vec<Vec<V>> = final_vals
        .into_iter()
        .skip(off as usize)
        .take(lim as usize)
        .collect();

    let mut text: Vec<u8> = Vec::new();
    let names: Vec<&str> = outs.iter().map(|o| o.name.as_str()).collect();
    text.extend_from_slice(names.join("|").as_bytes());
    for row in &final_rows {
        text.push(b'\n');
        let parts: Vec<Vec<u8>> = row.iter().map(show).collect();
        text.extend_from_slice(&parts.join(&b'|'));
    }
    text.push(b'\n');
    text.extend_from_slice(format!("({} rows)", final_rows.len()).as_bytes());
    Ok(String::from_utf8_lossy(&text).into_owned())
}

fn exec(db: &mut Db, st: Stmt) -> Res<String> {
    match st {
        Stmt::Create { name, cols } => {
            if db.pos(&name).is_some() {
                return Err(format!("table {} already exists", name));
            }
            let mut seen: HashSet<&str> = HashSet::new();
            for c in &cols {
                if !seen.insert(c.name.as_str()) {
                    return Err(format!("duplicate column: {}", c.name));
                }
            }
            if cols.iter().filter(|c| c.pk).count() > 1 {
                return Err("multiple primary keys".to_string());
            }
            db.tables.push(Table {
                name,
                cols,
                rows: Vec::new(),
            });
            Ok("ok".to_string())
        }
        Stmt::Drop(name) => {
            let i = db
                .pos(&name)
                .ok_or_else(|| format!("no such table: {}", name))?;
            db.tables.remove(i);
            Ok("ok".to_string())
        }
        Stmt::Insert { table, cols, rows } => exec_insert(db, table, cols, rows),
        Stmt::Update { table, sets, wh } => exec_update(db, table, sets, wh),
        Stmt::Delete { table, wh } => exec_delete(db, table, wh),
        Stmt::Select(s) => run_select(db, &s),
    }
}

fn main() {
    let mut input = Vec::new();
    let _ = io::stdin().read_to_end(&mut input);
    let mut db = Db { tables: Vec::new() };
    let mut out: Vec<u8> = Vec::new();
    for chunk in split_statements(&input) {
        let res: Res<String> = match lex(chunk) {
            Err(e) => Err(e),
            Ok(toks) => {
                if toks.is_empty() {
                    continue;
                }
                match parse_statement(toks) {
                    Err(e) => Err(e),
                    Ok(st) => exec(&mut db, st),
                }
            }
        };
        match res {
            Ok(s) => {
                out.extend_from_slice(s.as_bytes());
                out.push(b'\n');
            }
            Err(e) => {
                out.extend_from_slice(format!("error: {}\n", e).as_bytes());
            }
        }
    }
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(&out);
    let _ = lock.flush();
}
