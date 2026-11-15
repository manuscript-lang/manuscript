use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Val {
    Null,
    Int(i64),
    Text(Vec<u8>),
    Bool(bool),
}

type Res<T> = Result<T, String>;
fn syn<T>() -> Res<T> {
    Err("syntax error".to_string())
}

const RESERVED: &[&str] = &[
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON",
    "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
    "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC",
];

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Int(i64),
    Str(Vec<u8>),
    Word(String, String),
    Op(&'static str),
}

fn lex(s: &[u8]) -> Res<Vec<Tok>> {
    let mut t = vec![];
    let mut i = 0;
    while i < s.len() {
        let c = s[i];
        if c == b' ' || c == b'\t' || c == b'\r' || c == b'\n' {
            i += 1;
        } else if c == b'-' && i + 1 < s.len() && s[i + 1] == b'-' {
            while i < s.len() && s[i] != b'\n' {
                i += 1;
            }
        } else if c.is_ascii_digit() {
            let st = i;
            while i < s.len() && s[i].is_ascii_digit() {
                i += 1;
            }
            match std::str::from_utf8(&s[st..i]).unwrap().parse::<i64>() {
                Ok(v) => t.push(Tok::Int(v)),
                Err(_) => return syn(),
            }
        } else if c.is_ascii_alphabetic() || c == b'_' {
            let st = i;
            while i < s.len() && (s[i].is_ascii_alphanumeric() || s[i] == b'_') {
                i += 1;
            }
            let w = String::from_utf8_lossy(&s[st..i]).to_string();
            let u = w.to_ascii_uppercase();
            t.push(Tok::Word(w, u));
        } else if c == b'\'' {
            i += 1;
            let mut v = vec![];
            loop {
                if i >= s.len() {
                    return syn();
                }
                if s[i] == b'\'' {
                    if i + 1 < s.len() && s[i + 1] == b'\'' {
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
            t.push(Tok::Str(v));
        } else {
            let two = if i + 1 < s.len() { &s[i..i + 2] } else { &s[i..i + 1] };
            let op: &'static str = match two {
                b"<>" => "<>",
                b"!=" => "<>",
                b"<=" => "<=",
                b">=" => ">=",
                b"||" => "||",
                _ => "",
            };
            if !op.is_empty() {
                t.push(Tok::Op(op));
                i += 2;
                continue;
            }
            let op: &'static str = match c {
                b'=' => "=",
                b'<' => "<",
                b'>' => ">",
                b'+' => "+",
                b'-' => "-",
                b'*' => "*",
                b'/' => "/",
                b'%' => "%",
                b'(' => "(",
                b')' => ")",
                b',' => ",",
                b'.' => ".",
                _ => return syn(),
            };
            t.push(Tok::Op(op));
            i += 1;
        }
    }
    Ok(t)
}

#[derive(Debug)]
enum Expr {
    Lit(Val),
    Col(Option<String>, String),
    Neg(Box<Expr>),
    Not(Box<Expr>),
    Bin(&'static str, Box<Expr>, Box<Expr>),
    Cmp(&'static str, Box<Expr>, Box<Expr>),
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
    IsNull(Box<Expr>, bool),
    Like(Box<Expr>, Box<Expr>, bool),
    In(Box<Expr>, Vec<Expr>, bool),
    Between(Box<Expr>, Box<Expr>, Box<Expr>, bool),
    Call { name: String, distinct: bool, args: Vec<Expr>, star: bool },
}

struct TRef {
    name: String,
    alias: String,
}
struct Join {
    left: bool,
    t: TRef,
    on: Expr,
}
enum Item {
    Star,
    TStar(String),
    E(Expr, Option<String>),
}
struct Select {
    distinct: bool,
    items: Vec<Item>,
    from: Option<(TRef, Vec<Join>)>,
    where_: Option<Expr>,
    group: Vec<(Option<String>, String)>,
    having: Option<Expr>,
    order: Vec<(Expr, bool)>,
    limit: Option<i64>,
    offset: Option<i64>,
}
struct ColDef {
    name: String,
    int: bool,
    notnull: bool,
    pk: bool,
}
enum Stmt {
    Create(String, Vec<ColDef>),
    Drop(String),
    Insert(String, Option<Vec<String>>, Vec<Vec<Expr>>),
    Update(String, Vec<(String, Expr)>, Option<Expr>),
    Delete(String, Option<Expr>),
    Select(Select),
}

struct P {
    t: Vec<Tok>,
    p: usize,
}

impl P {
    fn peek(&self) -> Option<&Tok> {
        self.t.get(self.p)
    }
    fn peek_at(&self, n: usize) -> Option<&Tok> {
        self.t.get(self.p + n)
    }
    fn is_kw(&self, k: &str) -> bool {
        matches!(self.peek(), Some(Tok::Word(_, u)) if u == k)
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
        if let Some(Tok::Word(w, u)) = self.peek() {
            if !RESERVED.contains(&u.as_str()) {
                let w = w.clone();
                self.p += 1;
                return Ok(w);
            }
        }
        syn()
    }
    fn is_ident(&self) -> bool {
        matches!(self.peek(), Some(Tok::Word(_, u)) if !RESERVED.contains(&u.as_str()))
    }
    fn end(&self) -> Res<()> {
        if self.p == self.t.len() {
            Ok(())
        } else {
            syn()
        }
    }

    fn stmt(&mut self) -> Res<Stmt> {
        let s = if self.eat_kw("CREATE") {
            self.expect_kw("TABLE")?;
            let name = self.ident()?;
            self.expect_op("(")?;
            let mut cols = vec![];
            loop {
                let cn = self.ident()?;
                let ty = self.ident()?.to_ascii_uppercase();
                let int = match ty.as_str() {
                    "INT" => true,
                    "TEXT" => false,
                    _ => return syn(),
                };
                let (mut pk, mut nn) = (false, false);
                loop {
                    if self.eat_kw("PRIMARY") {
                        self.expect_kw("KEY")?;
                        pk = true;
                    } else if self.eat_kw("NOT") {
                        self.expect_kw("NULL")?;
                        nn = true;
                    } else {
                        break;
                    }
                }
                cols.push(ColDef { name: cn, int, notnull: nn || pk, pk });
                if !self.eat_op(",") {
                    break;
                }
            }
            self.expect_op(")")?;
            Stmt::Create(name, cols)
        } else if self.eat_kw("DROP") {
            self.expect_kw("TABLE")?;
            Stmt::Drop(self.ident()?)
        } else if self.eat_kw("INSERT") {
            self.expect_kw("INTO")?;
            let name = self.ident()?;
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
            let mut rows = vec![];
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
            Stmt::Insert(name, cols, rows)
        } else if self.eat_kw("UPDATE") {
            let name = self.ident()?;
            self.expect_kw("SET")?;
            let mut sets = vec![];
            loop {
                let c = self.ident()?;
                self.expect_op("=")?;
                let e = self.expr()?;
                sets.push((c, e));
                if !self.eat_op(",") {
                    break;
                }
            }
            let w = if self.eat_kw("WHERE") { Some(self.expr()?) } else { None };
            Stmt::Update(name, sets, w)
        } else if self.eat_kw("DELETE") {
            self.expect_kw("FROM")?;
            let name = self.ident()?;
            let w = if self.eat_kw("WHERE") { Some(self.expr()?) } else { None };
            Stmt::Delete(name, w)
        } else if self.eat_kw("SELECT") {
            Stmt::Select(self.select()?)
        } else {
            return syn();
        };
        self.end()?;
        Ok(s)
    }

    fn tref(&mut self) -> Res<TRef> {
        let name = self.ident()?;
        let alias = if self.eat_kw("AS") {
            self.ident()?
        } else if self.is_ident() {
            self.ident()?
        } else {
            name.clone()
        };
        Ok(TRef { name, alias })
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

    fn intlit(&mut self) -> Res<i64> {
        if let Some(Tok::Int(v)) = self.peek() {
            let v = *v;
            self.p += 1;
            Ok(v)
        } else {
            syn()
        }
    }

    fn select(&mut self) -> Res<Select> {
        let distinct = self.eat_kw("DISTINCT");
        let mut items = vec![];
        loop {
            if self.eat_op("*") {
                items.push(Item::Star);
            } else if self.is_ident()
                && matches!(self.peek_at(1), Some(Tok::Op(".")))
                && matches!(self.peek_at(2), Some(Tok::Op("*")))
            {
                let n = self.ident()?;
                self.p += 2;
                items.push(Item::TStar(n));
            } else {
                let e = self.expr()?;
                let a = if self.eat_kw("AS") { Some(self.ident()?) } else { None };
                items.push(Item::E(e, a));
            }
            if !self.eat_op(",") {
                break;
            }
        }
        let mut from = None;
        if self.eat_kw("FROM") {
            let t = self.tref()?;
            let mut joins = vec![];
            loop {
                let left;
                if self.eat_kw("LEFT") {
                    left = true;
                    self.expect_kw("JOIN")?;
                } else if self.eat_kw("INNER") {
                    left = false;
                    self.expect_kw("JOIN")?;
                } else if self.eat_kw("JOIN") {
                    left = false;
                } else {
                    break;
                }
                let t = self.tref()?;
                self.expect_kw("ON")?;
                let on = self.expr()?;
                joins.push(Join { left, t, on });
            }
            from = Some((t, joins));
        }
        let where_ = if self.eat_kw("WHERE") { Some(self.expr()?) } else { None };
        let mut group = vec![];
        if self.eat_kw("GROUP") {
            self.expect_kw("BY")?;
            loop {
                group.push(self.colref()?);
                if !self.eat_op(",") {
                    break;
                }
            }
        }
        let having = if self.eat_kw("HAVING") { Some(self.expr()?) } else { None };
        let mut order = vec![];
        if self.eat_kw("ORDER") {
            self.expect_kw("BY")?;
            loop {
                let e = self.expr()?;
                let desc = if self.eat_kw("DESC") {
                    true
                } else {
                    self.eat_kw("ASC");
                    false
                };
                order.push((e, desc));
                if !self.eat_op(",") {
                    break;
                }
            }
        }
        let (mut limit, mut offset) = (None, None);
        if self.eat_kw("LIMIT") {
            limit = Some(self.intlit()?);
            if self.eat_kw("OFFSET") {
                offset = Some(self.intlit()?);
            }
        }
        Ok(Select { distinct, items, from, where_, group, having, order, limit, offset })
    }

    fn expr(&mut self) -> Res<Expr> {
        let mut l = self.and()?;
        while self.eat_kw("OR") {
            let r = self.and()?;
            l = Expr::Or(Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn and(&mut self) -> Res<Expr> {
        let mut l = self.not()?;
        while self.eat_kw("AND") {
            let r = self.not()?;
            l = Expr::And(Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn not(&mut self) -> Res<Expr> {
        if self.eat_kw("NOT") {
            let e = self.not()?;
            return Ok(Expr::Not(Box::new(e)));
        }
        self.cmp()
    }
    fn cmp(&mut self) -> Res<Expr> {
        let l = self.add()?;
        for op in ["=", "<>", "<=", ">=", "<", ">"] {
            if self.eat_op(op) {
                let r = self.add()?;
                return Ok(Expr::Cmp(op, Box::new(l), Box::new(r)));
            }
        }
        if self.eat_kw("IS") {
            let neg = self.eat_kw("NOT");
            self.expect_kw("NULL")?;
            return Ok(Expr::IsNull(Box::new(l), neg));
        }
        let neg = if self.is_kw("NOT") {
            match self.peek_at(1) {
                Some(Tok::Word(_, u)) if u == "LIKE" || u == "IN" || u == "BETWEEN" => {
                    self.p += 1;
                    true
                }
                _ => return syn(),
            }
        } else {
            false
        };
        if self.eat_kw("LIKE") {
            let r = self.add()?;
            return Ok(Expr::Like(Box::new(l), Box::new(r), neg));
        }
        if self.eat_kw("IN") {
            self.expect_op("(")?;
            let mut v = vec![self.expr()?];
            while self.eat_op(",") {
                v.push(self.expr()?);
            }
            self.expect_op(")")?;
            return Ok(Expr::In(Box::new(l), v, neg));
        }
        if self.eat_kw("BETWEEN") {
            let lo = self.add()?;
            self.expect_kw("AND")?;
            let hi = self.add()?;
            return Ok(Expr::Between(Box::new(l), Box::new(lo), Box::new(hi), neg));
        }
        Ok(l)
    }
    fn add(&mut self) -> Res<Expr> {
        let mut l = self.mul()?;
        loop {
            let op = if self.is_op("+") {
                "+"
            } else if self.is_op("-") {
                "-"
            } else if self.is_op("||") {
                "||"
            } else {
                break;
            };
            self.p += 1;
            let r = self.mul()?;
            l = Expr::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn mul(&mut self) -> Res<Expr> {
        let mut l = self.unary()?;
        loop {
            let op = if self.is_op("*") {
                "*"
            } else if self.is_op("/") {
                "/"
            } else if self.is_op("%") {
                "%"
            } else {
                break;
            };
            self.p += 1;
            let r = self.unary()?;
            l = Expr::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn unary(&mut self) -> Res<Expr> {
        if self.eat_op("-") {
            let e = self.unary()?;
            return Ok(Expr::Neg(Box::new(e)));
        }
        self.primary()
    }
    fn primary(&mut self) -> Res<Expr> {
        match self.peek().cloned() {
            Some(Tok::Int(v)) => {
                self.p += 1;
                Ok(Expr::Lit(Val::Int(v)))
            }
            Some(Tok::Str(s)) => {
                self.p += 1;
                Ok(Expr::Lit(Val::Text(s)))
            }
            Some(Tok::Op("(")) => {
                self.p += 1;
                let e = self.expr()?;
                self.expect_op(")")?;
                Ok(e)
            }
            Some(Tok::Word(_, u)) if u == "NULL" => {
                self.p += 1;
                Ok(Expr::Lit(Val::Null))
            }
            Some(Tok::Word(_, _)) if self.is_ident() => {
                if matches!(self.peek_at(1), Some(Tok::Op("("))) {
                    let name = self.ident()?.to_ascii_uppercase();
                    self.p += 1;
                    let distinct = self.eat_kw("DISTINCT");
                    let mut args = vec![];
                    let mut star = false;
                    if self.eat_op("*") {
                        if name != "COUNT" {
                            return syn();
                        }
                        star = true;
                    } else if !self.is_op(")") {
                        args.push(self.expr()?);
                        while self.eat_op(",") {
                            args.push(self.expr()?);
                        }
                    }
                    self.expect_op(")")?;
                    Ok(Expr::Call { name, distinct, args, star })
                } else {
                    let (q, n) = self.colref()?;
                    Ok(Expr::Col(q, n))
                }
            }
            _ => syn(),
        }
    }
}

// ---------- resolved expressions ----------
enum R {
    Lit(Val),
    Col(usize),
    Neg(Box<R>),
    Not(Box<R>),
    Bin(&'static str, Box<R>, Box<R>),
    Cmp(&'static str, Box<R>, Box<R>),
    And(Box<R>, Box<R>),
    Or(Box<R>, Box<R>),
    IsNull(Box<R>, bool),
    Like(Box<R>, Box<R>, bool),
    In(Box<R>, Vec<R>, bool),
    Between(Box<R>, Box<R>, Box<R>, bool),
    Func(String, Vec<R>),
    Agg(String, bool, bool, Box<R>),
}

struct Cx<'a> {
    scope: &'a [(String, String)],
    group: Option<&'a [usize]>,
    allow_agg: bool,
}

fn is_agg(n: &str) -> bool {
    matches!(n, "COUNT" | "SUM" | "MIN" | "MAX")
}

fn has_agg(e: &Expr) -> bool {
    match e {
        Expr::Lit(_) | Expr::Col(..) => false,
        Expr::Neg(a) | Expr::Not(a) | Expr::IsNull(a, _) => has_agg(a),
        Expr::Bin(_, a, b) | Expr::Cmp(_, a, b) | Expr::And(a, b) | Expr::Or(a, b) | Expr::Like(a, b, _) => {
            has_agg(a) || has_agg(b)
        }
        Expr::In(a, v, _) => has_agg(a) || v.iter().any(has_agg),
        Expr::Between(a, b, c, _) => has_agg(a) || has_agg(b) || has_agg(c),
        Expr::Call { name, args, .. } => is_agg(name) || args.iter().any(has_agg),
    }
}

fn col_idx(scope: &[(String, String)], q: &Option<String>, n: &str) -> Res<usize> {
    match q {
        Some(q) => {
            for (i, (a, c)) in scope.iter().enumerate() {
                if a == q && c == n {
                    return Ok(i);
                }
            }
            Err(format!("no such column: {}.{}", q, n))
        }
        None => {
            let m: Vec<usize> = scope.iter().enumerate().filter(|(_, (_, c))| c == n).map(|(i, _)| i).collect();
            match m.len() {
                0 => Err(format!("no such column: {}", n)),
                1 => Ok(m[0]),
                _ => Err(format!("ambiguous column: {}", n)),
            }
        }
    }
}

fn resolve(e: &Expr, cx: &Cx, in_agg: bool) -> Res<R> {
    let b = |x: &Expr| -> Res<Box<R>> { Ok(Box::new(resolve(x, cx, in_agg)?)) };
    Ok(match e {
        Expr::Lit(v) => R::Lit(v.clone()),
        Expr::Col(q, n) => {
            let i = col_idx(cx.scope, q, n)?;
            if let Some(g) = cx.group {
                if !in_agg && !g.contains(&i) {
                    let nm = match q {
                        Some(q) => format!("{}.{}", q, n),
                        None => n.clone(),
                    };
                    return Err(format!("column {} must appear in GROUP BY", nm));
                }
            }
            R::Col(i)
        }
        Expr::Neg(a) => R::Neg(b(a)?),
        Expr::Not(a) => R::Not(b(a)?),
        Expr::Bin(o, x, y) => R::Bin(o, b(x)?, b(y)?),
        Expr::Cmp(o, x, y) => R::Cmp(o, b(x)?, b(y)?),
        Expr::And(x, y) => R::And(b(x)?, b(y)?),
        Expr::Or(x, y) => R::Or(b(x)?, b(y)?),
        Expr::IsNull(x, n) => R::IsNull(b(x)?, *n),
        Expr::Like(x, y, n) => R::Like(b(x)?, b(y)?, *n),
        Expr::In(x, v, n) => {
            let x = b(x)?;
            let mut rv = vec![];
            for i in v {
                rv.push(resolve(i, cx, in_agg)?);
            }
            R::In(x, rv, *n)
        }
        Expr::Between(x, l, h, n) => R::Between(b(x)?, b(l)?, b(h)?, *n),
        Expr::Call { name, distinct, args, star } => {
            if is_agg(name) {
                if !cx.allow_agg || in_agg {
                    return Err("misuse of aggregate".into());
                }
                if *star {
                    if *distinct {
                        return Err(format!("wrong number of arguments to {}", name));
                    }
                    return Ok(R::Agg(name.clone(), false, true, Box::new(R::Lit(Val::Null))));
                }
                if args.len() != 1 {
                    return Err(format!("wrong number of arguments to {}", name));
                }
                let a = resolve(&args[0], cx, true)?;
                R::Agg(name.clone(), *distinct, false, Box::new(a))
            } else {
                let ok = match name.as_str() {
                    "UPPER" | "LOWER" | "LENGTH" | "ABS" => {
                        if args.len() != 1 || *star || *distinct && false {
                            return Err(format!("wrong number of arguments to {}", name));
                        }
                        true
                    }
                    "SUBSTR" => {
                        if args.len() != 3 || *distinct {
                            return Err(format!("wrong number of arguments to {}", name));
                        }
                        true
                    }
                    "COALESCE" => {
                        if args.is_empty() || *distinct {
                            return Err(format!("wrong number of arguments to {}", name));
                        }
                        true
                    }
                    _ => false,
                };
                if !ok {
                    return Err(format!("no such function: {}", name));
                }
                if *distinct && args.len() != 1 {
                    return Err(format!("wrong number of arguments to {}", name));
                }
                let mut rv = vec![];
                for a in args {
                    rv.push(resolve(a, cx, in_agg)?);
                }
                R::Func(name.clone(), rv)
            }
        }
    })
}

// ---------- evaluation ----------
fn te<T>() -> Res<T> {
    Err("type error".into())
}

fn cmp_vals(a: &Val, b: &Val) -> Res<Option<Ordering>> {
    match (a, b) {
        (Val::Null, _) | (_, Val::Null) => Ok(None),
        (Val::Int(x), Val::Int(y)) => Ok(Some(x.cmp(y))),
        (Val::Text(x), Val::Text(y)) => Ok(Some(x.cmp(y))),
        _ => te(),
    }
}

fn tri(v: &Val) -> Res<Option<bool>> {
    match v {
        Val::Null => Ok(None),
        Val::Bool(b) => Ok(Some(*b)),
        _ => te(),
    }
}
fn tv(o: Option<bool>) -> Val {
    match o {
        Some(b) => Val::Bool(b),
        None => Val::Null,
    }
}
fn truthy(v: &Val) -> Res<bool> {
    Ok(tri(v)? == Some(true))
}

fn like(s: &[u8], p: &[u8]) -> bool {
    let (mut i, mut j) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while i < s.len() {
        if j < p.len() && p[j] == b'%' {
            star = Some((j, i));
            j += 1;
        } else if j < p.len() && (p[j] == b'_' || p[j] == s[i]) {
            i += 1;
            j += 1;
        } else if let Some((sj, si)) = star {
            j = sj + 1;
            i = si + 1;
            star = Some((sj, si + 1));
        } else {
            return false;
        }
    }
    while j < p.len() && p[j] == b'%' {
        j += 1;
    }
    j == p.len()
}

fn eval(r: &R, row: &[Val], grp: &[&Vec<Val>]) -> Res<Val> {
    match r {
        R::Lit(v) => Ok(v.clone()),
        R::Col(i) => {
            if let Some(v) = row.get(*i) {
                Ok(v.clone())
            } else if let Some(f) = grp.first() {
                Ok(f[*i].clone())
            } else {
                Ok(Val::Null)
            }
        }
        R::Neg(a) => match eval(a, row, grp)? {
            Val::Null => Ok(Val::Null),
            Val::Int(x) => Ok(Val::Int(x.wrapping_neg())),
            _ => te(),
        },
        R::Not(a) => Ok(tv(tri(&eval(a, row, grp)?)?.map(|b| !b))),
        R::Bin(op, a, b) => {
            let x = eval(a, row, grp)?;
            let y = eval(b, row, grp)?;
            if x == Val::Null || y == Val::Null {
                return Ok(Val::Null);
            }
            if *op == "||" {
                return match (x, y) {
                    (Val::Text(mut p), Val::Text(q)) => {
                        p.extend(q);
                        Ok(Val::Text(p))
                    }
                    _ => te(),
                };
            }
            match (x, y) {
                (Val::Int(p), Val::Int(q)) => Ok(Val::Int(match *op {
                    "+" => p.wrapping_add(q),
                    "-" => p.wrapping_sub(q),
                    "*" => p.wrapping_mul(q),
                    "/" => {
                        if q == 0 {
                            return Err("division by zero".into());
                        }
                        p.wrapping_div(q)
                    }
                    _ => {
                        if q == 0 {
                            return Err("division by zero".into());
                        }
                        p.wrapping_rem(q)
                    }
                })),
                _ => te(),
            }
        }
        R::Cmp(op, a, b) => {
            let x = eval(a, row, grp)?;
            let y = eval(b, row, grp)?;
            Ok(match cmp_vals(&x, &y)? {
                None => Val::Null,
                Some(o) => Val::Bool(match *op {
                    "=" => o == Ordering::Equal,
                    "<>" => o != Ordering::Equal,
                    "<" => o == Ordering::Less,
                    "<=" => o != Ordering::Greater,
                    ">" => o == Ordering::Greater,
                    _ => o != Ordering::Less,
                }),
            })
        }
        R::And(a, b) => {
            let l = tri(&eval(a, row, grp)?)?;
            if l == Some(false) {
                return Ok(Val::Bool(false));
            }
            let r = tri(&eval(b, row, grp)?)?;
            Ok(tv(match (l, r) {
                (_, Some(false)) => Some(false),
                (Some(true), Some(true)) => Some(true),
                _ => None,
            }))
        }
        R::Or(a, b) => {
            let l = tri(&eval(a, row, grp)?)?;
            if l == Some(true) {
                return Ok(Val::Bool(true));
            }
            let r = tri(&eval(b, row, grp)?)?;
            Ok(tv(match (l, r) {
                (_, Some(true)) => Some(true),
                (Some(false), Some(false)) => Some(false),
                _ => None,
            }))
        }
        R::IsNull(a, n) => {
            let v = eval(a, row, grp)?;
            Ok(Val::Bool((v == Val::Null) != *n))
        }
        R::Like(a, b, n) => {
            let x = eval(a, row, grp)?;
            let y = eval(b, row, grp)?;
            if x == Val::Null || y == Val::Null {
                return Ok(Val::Null);
            }
            match (x, y) {
                (Val::Text(s), Val::Text(p)) => Ok(Val::Bool(like(&s, &p) != *n)),
                _ => te(),
            }
        }
        R::In(a, list, n) => {
            let x = eval(a, row, grp)?;
            if x == Val::Null {
                return Ok(Val::Null);
            }
            let mut sawnull = false;
            for e in list {
                let v = eval(e, row, grp)?;
                match cmp_vals(&x, &v)? {
                    None => sawnull = true,
                    Some(Ordering::Equal) => return Ok(Val::Bool(!*n)),
                    _ => {}
                }
            }
            if sawnull {
                Ok(Val::Null)
            } else {
                Ok(Val::Bool(*n))
            }
        }
        R::Between(a, l, h, n) => {
            let x = eval(a, row, grp)?;
            let lo = eval(l, row, grp)?;
            let hi = eval(h, row, grp)?;
            let ge = cmp_vals(&x, &lo)?.map(|o| o != Ordering::Less);
            let le = cmp_vals(&x, &hi)?.map(|o| o != Ordering::Greater);
            let r = match (ge, le) {
                (Some(false), _) | (_, Some(false)) => Some(false),
                (Some(true), Some(true)) => Some(true),
                _ => None,
            };
            Ok(tv(r.map(|b| b != *n)))
        }
        R::Func(name, args) => {
            let mut vals = vec![];
            for a in args {
                vals.push(eval(a, row, grp)?);
            }
            if name == "COALESCE" {
                for v in vals {
                    if v != Val::Null {
                        return Ok(v);
                    }
                }
                return Ok(Val::Null);
            }
            if vals.iter().any(|v| *v == Val::Null) {
                return Ok(Val::Null);
            }
            match (name.as_str(), &vals[..]) {
                ("UPPER", [Val::Text(t)]) => Ok(Val::Text(t.to_ascii_uppercase())),
                ("LOWER", [Val::Text(t)]) => Ok(Val::Text(t.to_ascii_lowercase())),
                ("LENGTH", [Val::Text(t)]) => Ok(Val::Int(t.len() as i64)),
                ("ABS", [Val::Int(i)]) => Ok(Val::Int(i.wrapping_abs())),
                ("SUBSTR", [Val::Text(t), Val::Int(s), Val::Int(l)]) => {
                    if *l <= 0 {
                        return Ok(Val::Text(vec![]));
                    }
                    let end = *s as i128 + *l as i128 - 1;
                    let from = (*s as i128).max(1);
                    let to = end.min(t.len() as i128);
                    if from > to {
                        return Ok(Val::Text(vec![]));
                    }
                    Ok(Val::Text(t[(from - 1) as usize..to as usize].to_vec()))
                }
                _ => te(),
            }
        }
        R::Agg(kind, distinct, star, arg) => {
            if *star {
                return Ok(Val::Int(grp.len() as i64));
            }
            let mut vals = vec![];
            for r in grp {
                let v = eval(arg, r, &[])?;
                if v != Val::Null {
                    vals.push(v);
                }
            }
            if *distinct {
                let mut seen = HashSet::new();
                vals.retain(|v| seen.insert(v.clone()));
            }
            match kind.as_str() {
                "COUNT" => Ok(Val::Int(vals.len() as i64)),
                "SUM" => {
                    if vals.is_empty() {
                        return Ok(Val::Null);
                    }
                    let mut s = 0i64;
                    for v in &vals {
                        match v {
                            Val::Int(i) => s = s.wrapping_add(*i),
                            _ => return te(),
                        }
                    }
                    Ok(Val::Int(s))
                }
                _ => {
                    if vals.is_empty() {
                        return Ok(Val::Null);
                    }
                    let mut best = vals[0].clone();
                    for v in &vals {
                        let o = match cmp_vals(&best, v)? {
                            Some(o) => o,
                            None => Ordering::Equal,
                        };
                        if matches!(v, Val::Bool(_)) {
                            return te();
                        }
                        if (kind == "MIN" && o == Ordering::Greater) || (kind == "MAX" && o == Ordering::Less) {
                            best = v.clone();
                        }
                    }
                    if matches!(best, Val::Bool(_)) {
                        return te();
                    }
                    Ok(best)
                }
            }
        }
    }
}

// ---------- database ----------
struct Table {
    name: String,
    cols: Vec<ColDef>,
    rows: Vec<Vec<Val>>,
}
struct Db {
    tables: Vec<Table>,
}

fn fmt_val(v: &Val) -> Vec<u8> {
    match v {
        Val::Null => b"NULL".to_vec(),
        Val::Int(i) => i.to_string().into_bytes(),
        Val::Text(t) => t.clone(),
        Val::Bool(b) => if *b { b"true".to_vec() } else { b"false".to_vec() },
    }
}

fn rank(v: &Val) -> u8 {
    match v {
        Val::Null => 0,
        Val::Bool(_) => 1,
        Val::Int(_) => 2,
        Val::Text(_) => 3,
    }
}
fn ord_vals(a: &Val, b: &Val) -> Ordering {
    match (a, b) {
        (Val::Int(x), Val::Int(y)) => x.cmp(y),
        (Val::Text(x), Val::Text(y)) => x.cmp(y),
        (Val::Bool(x), Val::Bool(y)) => x.cmp(y),
        _ => rank(a).cmp(&rank(b)),
    }
}

fn check_row(t: &Table, row: &[Val]) -> Res<()> {
    for (i, c) in t.cols.iter().enumerate() {
        match &row[i] {
            Val::Null => {
                if c.notnull {
                    return Err(format!("NOT NULL constraint failed: {}", c.name));
                }
            }
            Val::Int(_) if c.int => {}
            Val::Text(_) if !c.int => {}
            _ => return Err(format!("type mismatch in column {}", c.name)),
        }
    }
    Ok(())
}

fn dup_check(t: &Table, rows: &[&Vec<Val>]) -> Res<()> {
    if let Some(pk) = t.cols.iter().position(|c| c.pk) {
        let mut seen = HashSet::new();
        for r in rows {
            if !seen.insert(r[pk].clone()) {
                return Err(format!("duplicate primary key: {}", String::from_utf8_lossy(&fmt_val(&r[pk]))));
            }
        }
    }
    Ok(())
}

fn find(db: &Db, n: &str) -> Res<usize> {
    db.tables.iter().position(|t| t.name == n).ok_or_else(|| format!("no such table: {}", n))
}

fn table_scope(t: &Table, alias: &str) -> Vec<(String, String)> {
    t.cols.iter().map(|c| (alias.to_string(), c.name.clone())).collect()
}

fn exec(db: &mut Db, s: Stmt) -> Res<Vec<u8>> {
    match s {
        Stmt::Create(name, cols) => {
            if db.tables.iter().any(|t| t.name == name) {
                return Err(format!("table {} already exists", name));
            }
            let mut seen = HashSet::new();
            for c in &cols {
                if !seen.insert(c.name.clone()) {
                    return Err(format!("duplicate column: {}", c.name));
                }
            }
            if cols.iter().filter(|c| c.pk).count() > 1 {
                return Err("multiple primary keys".into());
            }
            db.tables.push(Table { name, cols, rows: vec![] });
            Ok(b"ok\n".to_vec())
        }
        Stmt::Drop(n) => {
            let i = find(db, &n)?;
            db.tables.remove(i);
            Ok(b"ok\n".to_vec())
        }
        Stmt::Insert(name, cols, rows) => {
            let ti = find(db, &name)?;
            let t = &db.tables[ti];
            let n = t.cols.len();
            let idxs: Vec<usize> = match &cols {
                Some(l) => {
                    let mut v = vec![];
                    for c in l {
                        match t.cols.iter().position(|d| &d.name == c) {
                            Some(i) => {
                                if v.contains(&i) {
                                    return Err(format!("duplicate column: {}", c));
                                }
                                v.push(i)
                            }
                            None => return Err(format!("no such column: {}", c)),
                        }
                    }
                    v
                }
                None => (0..n).collect(),
            };
            let cx = Cx { scope: &[], group: None, allow_agg: false };
            let mut newrows: Vec<Vec<Val>> = vec![];
            for row in &rows {
                if row.len() != idxs.len() {
                    return Err("wrong number of values".into());
                }
                let mut vals = vec![];
                for e in row {
                    let r = resolve(e, &cx, false)?;
                    vals.push(eval(&r, &[], &[])?);
                }
                let mut full = vec![Val::Null; n];
                for (k, v) in vals.into_iter().enumerate() {
                    full[idxs[k]] = v;
                }
                check_row(t, &full)?;
                newrows.push(full);
            }
            let all: Vec<&Vec<Val>> = t.rows.iter().chain(newrows.iter()).collect();
            dup_check(t, &all)?;
            let cnt = newrows.len();
            db.tables[ti].rows.extend(newrows);
            Ok(format!("inserted {}\n", cnt).into_bytes())
        }
        Stmt::Update(name, sets, w) => {
            let ti = find(db, &name)?;
            let t = &db.tables[ti];
            let mut idxs = vec![];
            for (c, _) in &sets {
                match t.cols.iter().position(|d| &d.name == c) {
                    Some(i) => idxs.push(i),
                    None => return Err(format!("no such column: {}", c)),
                }
            }
            let scope = table_scope(t, &name);
            let cx = Cx { scope: &scope, group: None, allow_agg: false };
            let mut rs = vec![];
            for (_, e) in &sets {
                rs.push(resolve(e, &cx, false)?);
            }
            let rw = match &w {
                Some(e) => Some(resolve(e, &cx, false)?),
                None => None,
            };
            let mut newrows = t.rows.clone();
            let mut cnt = 0;
            for row in newrows.iter_mut() {
                if let Some(rw) = &rw {
                    if !truthy(&eval(rw, row, &[])?)? {
                        continue;
                    }
                }
                let mut vals = vec![];
                for r in &rs {
                    vals.push(eval(r, row, &[])?);
                }
                let mut nr = row.clone();
                for (k, v) in vals.into_iter().enumerate() {
                    nr[idxs[k]] = v;
                }
                check_row(t, &nr)?;
                *row = nr;
                cnt += 1;
            }
            let all: Vec<&Vec<Val>> = newrows.iter().collect();
            dup_check(t, &all)?;
            db.tables[ti].rows = newrows;
            Ok(format!("updated {}\n", cnt).into_bytes())
        }
        Stmt::Delete(name, w) => {
            let ti = find(db, &name)?;
            let t = &db.tables[ti];
            let scope = table_scope(t, &name);
            let cx = Cx { scope: &scope, group: None, allow_agg: false };
            let rw = match &w {
                Some(e) => Some(resolve(e, &cx, false)?),
                None => None,
            };
            let mut keep = vec![];
            let mut cnt = 0;
            for row in &t.rows {
                let del = match &rw {
                    Some(rw) => truthy(&eval(rw, row, &[])?)?,
                    None => true,
                };
                if del {
                    cnt += 1;
                } else {
                    keep.push(row.clone());
                }
            }
            db.tables[ti].rows = keep;
            Ok(format!("deleted {}\n", cnt).into_bytes())
        }
        Stmt::Select(s) => select(db, s),
    }
}

enum Key {
    Out(usize),
    E(R),
}

fn select(db: &Db, s: Select) -> Res<Vec<u8>> {
    // tables
    let mut scope: Vec<(String, String)> = vec![];
    let mut aliases: Vec<String> = vec![];
    let mut prefix_lens = vec![];
    let mut trefs: Vec<(&Table, bool)> = vec![];
    if let Some((t0, joins)) = &s.from {
        let mut list: Vec<(&TRef, bool)> = vec![(t0, false)];
        for j in joins {
            list.push((&j.t, j.left));
        }
        for (t, left) in list {
            let ti = find(db, &t.name)?;
            if aliases.contains(&t.alias) {
                return Err(format!("duplicate alias: {}", t.alias));
            }
            aliases.push(t.alias.clone());
            scope.extend(table_scope(&db.tables[ti], &t.alias));
            prefix_lens.push(scope.len());
            trefs.push((&db.tables[ti], left));
        }
    }
    // joins
    let mut join_r = vec![];
    if let Some((_, joins)) = &s.from {
        for (k, j) in joins.iter().enumerate() {
            let cx = Cx { scope: &scope[..prefix_lens[k + 1]], group: None, allow_agg: false };
            join_r.push(resolve(&j.on, &cx, false)?);
        }
    }
    // stars
    for it in &s.items {
        if let Item::TStar(t) = it {
            if !aliases.contains(t) {
                return Err(format!("no such table: {}", t));
            }
        }
    }
    let nocx = Cx { scope: &scope, group: None, allow_agg: false };
    let mut gidx = vec![];
    for (q, n) in &s.group {
        gidx.push(col_idx(&scope, q, n)?);
    }
    let rwhere = match &s.where_ {
        Some(e) => Some(resolve(e, &nocx, false)?),
        None => None,
    };
    let aggregated = !s.group.is_empty()
        || s.having.is_some()
        || s.items.iter().any(|i| matches!(i, Item::E(e, _) if has_agg(e)))
        || s.order.iter().any(|(e, _)| has_agg(e));
    let cx = Cx { scope: &scope, group: if aggregated { Some(&gidx) } else { None }, allow_agg: true };
    let mut names: Vec<String> = vec![];
    let mut sel: Vec<R> = vec![];
    for it in &s.items {
        match it {
            Item::Star | Item::TStar(_) => {
                let mut off = 0;
                for (k, a) in aliases.iter().enumerate() {
                    let end = prefix_lens[k];
                    let want = match it {
                        Item::TStar(t) => t == a,
                        _ => true,
                    };
                    if want {
                        for i in off..end {
                            let e = Expr::Col(Some(scope[i].0.clone()), scope[i].1.clone());
                            sel.push(resolve(&e, &cx, false)?);
                            names.push(scope[i].1.clone());
                        }
                    }
                    off = end;
                }
            }
            Item::E(e, a) => {
                sel.push(resolve(e, &cx, false)?);
                names.push(match (a, e) {
                    (Some(a), _) => a.clone(),
                    (None, Expr::Col(_, n)) => n.clone(),
                    _ => "?column?".to_string(),
                });
            }
        }
    }
    let rhaving = match &s.having {
        Some(e) => Some(resolve(e, &cx, false)?),
        None => None,
    };
    let mut keys: Vec<(Key, bool)> = vec![];
    for (e, desc) in &s.order {
        if let Expr::Lit(Val::Int(n)) = e {
            if *n < 1 || *n as usize > names.len() {
                return Err("bad ORDER BY position".into());
            }
            keys.push((Key::Out(*n as usize - 1), *desc));
            continue;
        }
        if let Expr::Col(None, n) = e {
            if let Some(p) = names.iter().position(|x| x == n) {
                keys.push((Key::Out(p), *desc));
                continue;
            }
        }
        keys.push((Key::E(resolve(e, &cx, false)?), *desc));
    }

    // rows
    let mut rows: Vec<Vec<Val>> = vec![vec![]];
    if let Some((_, joins)) = &s.from {
        rows = trefs[0].0.rows.clone();
        for (k, _) in joins.iter().enumerate() {
            let (t, left) = trefs[k + 1];
            let width = t.cols.len();
            let mut out = vec![];
            for o in &rows {
                let mut matched = false;
                for inn in &t.rows {
                    let mut c = o.clone();
                    c.extend(inn.iter().cloned());
                    if truthy(&eval(&join_r[k], &c, &[])?)? {
                        matched = true;
                        out.push(c);
                    }
                }
                if left && !matched {
                    let mut c = o.clone();
                    c.extend(std::iter::repeat(Val::Null).take(width));
                    out.push(c);
                }
            }
            rows = out;
        }
    }
    if let Some(w) = &rwhere {
        let mut out = vec![];
        for r in rows {
            if truthy(&eval(w, &r, &[])?)? {
                out.push(r);
            }
        }
        rows = out;
    }
    let mut outs: Vec<(Vec<Val>, Vec<Val>)> = vec![];
    let mut emit = |row: &[Val], grp: &[&Vec<Val>]| -> Res<()> {
        let mut o = vec![];
        for r in &sel {
            o.push(eval(r, row, grp)?);
        }
        let mut ks = vec![];
        for (k, _) in &keys {
            ks.push(match k {
                Key::Out(i) => o[*i].clone(),
                Key::E(r) => eval(r, row, grp)?,
            });
        }
        outs.push((o, ks));
        Ok(())
    };
    if aggregated {
        let mut groups: Vec<Vec<&Vec<Val>>> = vec![];
        if gidx.is_empty() {
            groups.push(rows.iter().collect());
        } else {
            let mut map: HashMap<Vec<Val>, usize> = HashMap::new();
            for r in &rows {
                let k: Vec<Val> = gidx.iter().map(|&i| r[i].clone()).collect();
                let n = groups.len();
                let id = *map.entry(k).or_insert(n);
                if id == n {
                    groups.push(vec![]);
                }
                groups[id].push(r);
            }
        }
        for g in &groups {
            let first: &[Val] = match g.first() {
                Some(f) => f,
                None => &[],
            };
            if let Some(h) = &rhaving {
                if !truthy(&eval(h, first, g)?)? {
                    continue;
                }
            }
            emit(first, g)?;
        }
    } else {
        for r in &rows {
            emit(r, &[])?;
        }
    }
    if s.distinct {
        let mut seen = HashSet::new();
        outs.retain(|(o, _)| seen.insert(o.clone()));
    }
    if !keys.is_empty() {
        outs.sort_by(|a, b| {
            for (i, (_, desc)) in keys.iter().enumerate() {
                let mut o = ord_vals(&a.1[i], &b.1[i]);
                if *desc {
                    o = o.reverse();
                }
                if o != Ordering::Equal {
                    return o;
                }
            }
            Ordering::Equal
        });
    }
    let off = s.offset.unwrap_or(0) as usize;
    let lim = s.limit.map(|l| l as usize).unwrap_or(usize::MAX);
    let mut out = names.join("|").into_bytes();
    out.push(b'\n');
    let mut cnt = 0;
    for (o, _) in outs.iter().skip(off).take(lim) {
        for (i, v) in o.iter().enumerate() {
            if i > 0 {
                out.push(b'|');
            }
            out.extend(fmt_val(v));
        }
        out.push(b'\n');
        cnt += 1;
    }
    out.extend(format!("({} rows)\n", cnt).into_bytes());
    Ok(out)
}

fn split(s: &[u8]) -> Vec<&[u8]> {
    let mut v = vec![];
    let mut st = 0;
    let mut i = 0;
    let mut in_str = false;
    while i < s.len() {
        let c = s[i];
        if in_str {
            if c == b'\'' {
                in_str = false;
            }
        } else if c == b'\'' {
            in_str = true;
        } else if c == b'-' && i + 1 < s.len() && s[i + 1] == b'-' {
            while i < s.len() && s[i] != b'\n' {
                i += 1;
            }
            continue;
        } else if c == b';' {
            v.push(&s[st..i]);
            st = i + 1;
        }
        i += 1;
    }
    v.push(&s[st..]);
    v
}

fn main() {
    let mut inp = vec![];
    std::io::stdin().read_to_end(&mut inp).unwrap();
    let mut db = Db { tables: vec![] };
    let mut out: Vec<u8> = vec![];
    for part in split(&inp) {
        let r = lex(part).and_then(|t| {
            if t.is_empty() {
                return Ok(None);
            }
            let mut p = P { t, p: 0 };
            p.stmt().map(Some)
        });
        match r {
            Ok(None) => {}
            Ok(Some(s)) => match exec(&mut db, s) {
                Ok(o) => out.extend(o),
                Err(e) => out.extend(format!("error: {}\n", e).into_bytes()),
            },
            Err(e) => out.extend(format!("error: {}\n", e).into_bytes()),
        }
    }
    std::io::stdout().write_all(&out).unwrap();
}
