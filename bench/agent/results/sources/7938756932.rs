use std::cmp::Ordering;
use std::collections::{BTreeSet, HashMap, HashSet, VecDeque};
use std::io::{self, Read, Write};

// ---------------------------------------------------------------------------
// Basic types
// ---------------------------------------------------------------------------

/// (column 0..=25, row 1..=999)
type Pos = (u8, u16);
/// Normalized rectangle: (top-left, bottom-right)
type Rect = (Pos, Pos);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum E {
    Div0,
    Ref,
    Name,
    Value,
    Num,
    Parse,
    Cycle,
}

impl E {
    fn text(self) -> &'static str {
        match self {
            E::Div0 => "#DIV/0!",
            E::Ref => "#REF!",
            E::Name => "#NAME?",
            E::Value => "#VALUE!",
            E::Num => "#NUM!",
            E::Parse => "#PARSE!",
            E::Cycle => "#CYCLE!",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Val {
    Empty,
    Num(f64),
    Text(String),
    Bool(bool),
    Err(E),
}

type R = Result<Val, E>;

fn col_letter(c: u8) -> char {
    (b'A' + c) as char
}

fn pos_name(p: Pos) -> String {
    format!("{}{}", col_letter(p.0), p.1)
}

fn norm(a: Pos, b: Pos) -> Rect {
    ((a.0.min(b.0), a.1.min(b.1)), (a.0.max(b.0), a.1.max(b.1)))
}

fn in_rect(r: Rect, p: Pos) -> bool {
    p.0 >= r.0 .0 && p.0 <= r.1 .0 && p.1 >= r.0 .1 && p.1 <= r.1 .1
}

fn rect_cells(r: Rect) -> Vec<Pos> {
    let mut v = Vec::new();
    for row in r.0 .1..=r.1 .1 {
        for col in r.0 .0..=r.1 .0 {
            v.push((col, row));
        }
    }
    v
}

fn rect_area(r: Rect) -> usize {
    ((r.1 .0 - r.0 .0) as usize + 1) * ((r.1 .1 - r.0 .1) as usize + 1)
}

// ---------------------------------------------------------------------------
// Numbers and display
// ---------------------------------------------------------------------------

/// Matches the number grammar `[+-]?(digits[.digits]|.digits)([eE][+-]?digits)?`
/// (plus `digits.`) and returns its value (possibly infinite).
fn grammar_value(s: &str) -> Option<f64> {
    let b = s.as_bytes();
    let n = b.len();
    let mut i = 0;
    let mut neg = false;
    if i < n && (b[i] == b'+' || b[i] == b'-') {
        neg = b[i] == b'-';
        i += 1;
    }
    let int_start = i;
    while i < n && b[i].is_ascii_digit() {
        i += 1;
    }
    let int_part = &s[int_start..i];
    let mut frac_part = "";
    if i < n && b[i] == b'.' {
        i += 1;
        let fs = i;
        while i < n && b[i].is_ascii_digit() {
            i += 1;
        }
        frac_part = &s[fs..i];
    }
    if int_part.is_empty() && frac_part.is_empty() {
        return None;
    }
    let mut exp = String::from("0");
    if i < n && (b[i] == b'e' || b[i] == b'E') {
        i += 1;
        let mut eneg = false;
        if i < n && (b[i] == b'+' || b[i] == b'-') {
            eneg = b[i] == b'-';
            i += 1;
        }
        let es = i;
        while i < n && b[i].is_ascii_digit() {
            i += 1;
        }
        if i == es {
            return None;
        }
        exp = format!("{}{}", if eneg { "-" } else { "" }, &s[es..i]);
    }
    if i != n {
        return None;
    }
    let txt = format!(
        "{}{}.{}e{}",
        if neg { "-" } else { "" },
        if int_part.is_empty() { "0" } else { int_part },
        if frac_part.is_empty() { "0" } else { frac_part },
        exp
    );
    txt.parse::<f64>().ok()
}

/// Number grammar and finite.
fn number_literal(s: &str) -> Option<f64> {
    grammar_value(s).filter(|x| x.is_finite())
}

fn disp_num(x: f64) -> String {
    let s = format!("{:.10}", x);
    let s = if s.contains('.') {
        s.trim_end_matches('0').trim_end_matches('.').to_string()
    } else {
        s
    };
    if s == "-0" {
        "0".to_string()
    } else {
        s
    }
}

fn disp(v: &Val) -> String {
    match v {
        Val::Empty => String::new(),
        Val::Num(x) => disp_num(*x),
        Val::Text(s) => s.clone(),
        Val::Bool(b) => {
            if *b {
                "TRUE".to_string()
            } else {
                "FALSE".to_string()
            }
        }
        Val::Err(e) => e.text().to_string(),
    }
}

/// Value of a constant cell from its (trimmed) raw text.
fn const_value(raw: &str) -> Val {
    if let Some(rest) = raw.strip_prefix('\'') {
        return Val::Text(rest.to_string());
    }
    if let Some(x) = number_literal(raw) {
        return Val::Num(x);
    }
    if raw.eq_ignore_ascii_case("TRUE") {
        return Val::Bool(true);
    }
    if raw.eq_ignore_ascii_case("FALSE") {
        return Val::Bool(false);
    }
    Val::Text(raw.to_string())
}

fn fin(x: f64) -> R {
    if x.is_finite() {
        Ok(Val::Num(x))
    } else {
        Err(E::Num)
    }
}

fn to_num(v: &Val) -> Result<f64, E> {
    match v {
        Val::Num(x) => Ok(*x),
        Val::Bool(b) => Ok(if *b { 1.0 } else { 0.0 }),
        Val::Empty => Ok(0.0),
        Val::Text(s) => number_literal(s.trim()).ok_or(E::Value),
        Val::Err(e) => Err(*e),
    }
}

fn to_bool(v: &Val) -> Result<bool, E> {
    match v {
        Val::Bool(b) => Ok(*b),
        Val::Num(x) => Ok(*x != 0.0),
        Val::Empty => Ok(false),
        Val::Text(s) => {
            if s.eq_ignore_ascii_case("TRUE") {
                Ok(true)
            } else if s.eq_ignore_ascii_case("FALSE") {
                Ok(false)
            } else {
                Err(E::Value)
            }
        }
        Val::Err(e) => Err(*e),
    }
}

fn zero_of(v: &Val) -> Val {
    match v {
        Val::Text(_) => Val::Text(String::new()),
        Val::Bool(_) => Val::Bool(false),
        _ => Val::Num(0.0),
    }
}

fn rank(v: &Val) -> u8 {
    match v {
        Val::Num(_) => 0,
        Val::Text(_) => 1,
        Val::Bool(_) => 2,
        _ => 3,
    }
}

/// Comparison rules (errors must already be filtered out).
fn cmp_vals(a: &Val, b: &Val) -> Ordering {
    match (a, b) {
        (Val::Empty, Val::Empty) => Ordering::Equal,
        (Val::Empty, x) => cmp_vals(&zero_of(x), x),
        (x, Val::Empty) => cmp_vals(x, &zero_of(x)),
        (Val::Num(x), Val::Num(y)) => x.partial_cmp(y).unwrap_or(Ordering::Equal),
        (Val::Text(x), Val::Text(y)) => x.as_bytes().cmp(y.as_bytes()),
        (Val::Bool(x), Val::Bool(y)) => x.cmp(y),
        _ => rank(a).cmp(&rank(b)),
    }
}

fn test_op(op: &str, o: Ordering) -> bool {
    match op {
        "=" => o == Ordering::Equal,
        "<>" => o != Ordering::Equal,
        "<" => o == Ordering::Less,
        "<=" => o != Ordering::Greater,
        ">" => o == Ordering::Greater,
        ">=" => o != Ordering::Less,
        _ => false,
    }
}

fn tag(v: &Val) -> u8 {
    match v {
        Val::Empty => 0,
        Val::Num(_) => 1,
        Val::Text(_) => 2,
        Val::Bool(_) => 3,
        Val::Err(_) => 4,
    }
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
enum Tk {
    Num(f64),
    Str(String),
    Ref(String),
    Range(String, String),
    Ident(String),
    ErrRef,
    Op(&'static str),
    LP,
    RP,
    Comma,
}

#[derive(Clone, Debug)]
struct Token {
    tk: Tk,
    start: usize,
    end: usize,
}

/// If a reference word starts at `i`, return the index just after it.
fn ref_word_end(c: &[char], i: usize) -> Option<usize> {
    let n = c.len();
    let mut j = i;
    if j < n && c[j] == '$' {
        j += 1;
    }
    let ls = j;
    while j < n && c[j].is_ascii_alphabetic() {
        j += 1;
    }
    if j == ls {
        return None;
    }
    if j < n && c[j] == '$' {
        j += 1;
    }
    let ds = j;
    while j < n && c[j].is_ascii_digit() {
        j += 1;
    }
    if j == ds {
        return None;
    }
    if j < n {
        let x = c[j];
        if x.is_ascii_alphanumeric() || x == '_' || x == '.' || x == '(' || x == '$' {
            return None;
        }
    }
    Some(j)
}

fn lex(c: &[char]) -> Option<Vec<Token>> {
    let n = c.len();
    let mut out: Vec<Token> = Vec::new();
    let mut i = 0;
    while i < n {
        let ch = c[i];
        if ch == ' ' || ch == '\t' {
            i += 1;
            continue;
        }
        let start = i;
        // numbers
        if ch.is_ascii_digit() || (ch == '.' && i + 1 < n && c[i + 1].is_ascii_digit()) {
            while i < n && c[i].is_ascii_digit() {
                i += 1;
            }
            if i < n && c[i] == '.' {
                i += 1;
                while i < n && c[i].is_ascii_digit() {
                    i += 1;
                }
            }
            if i < n && (c[i] == 'e' || c[i] == 'E') {
                let mut j = i + 1;
                if j < n && (c[j] == '+' || c[j] == '-') {
                    j += 1;
                }
                if j < n && c[j].is_ascii_digit() {
                    while j < n && c[j].is_ascii_digit() {
                        j += 1;
                    }
                    i = j;
                }
            }
            let text: String = c[start..i].iter().collect();
            let v = grammar_value(&text)?;
            out.push(Token { tk: Tk::Num(v), start, end: i });
            continue;
        }
        // strings
        if ch == '"' {
            i += 1;
            let mut s = String::new();
            loop {
                if i >= n {
                    return None;
                }
                if c[i] == '"' {
                    if i + 1 < n && c[i + 1] == '"' {
                        s.push('"');
                        i += 2;
                    } else {
                        i += 1;
                        break;
                    }
                } else {
                    s.push(c[i]);
                    i += 1;
                }
            }
            out.push(Token { tk: Tk::Str(s), start, end: i });
            continue;
        }
        // error constant
        if ch == '#' {
            if i + 5 <= n && c[i + 1..i + 5].iter().collect::<String>().eq_ignore_ascii_case("REF!") {
                i += 5;
                out.push(Token { tk: Tk::ErrRef, start, end: i });
                continue;
            }
            return None;
        }
        // references, ranges, identifiers
        if ch == '$' || ch.is_ascii_alphabetic() {
            if let Some(e1) = ref_word_end(c, i) {
                let w1: String = c[i..e1].iter().collect();
                if e1 < n && c[e1] == ':' {
                    if let Some(e2) = ref_word_end(c, e1 + 1) {
                        let w2: String = c[e1 + 1..e2].iter().collect();
                        out.push(Token { tk: Tk::Range(w1, w2), start, end: e2 });
                        i = e2;
                        continue;
                    }
                }
                out.push(Token { tk: Tk::Ref(w1), start, end: e1 });
                i = e1;
                continue;
            }
            if ch == '$' {
                return None;
            }
        }
        if ch == '_' || ch.is_ascii_alphabetic() {
            let mut j = i;
            while j < n && (c[j].is_ascii_alphanumeric() || c[j] == '_' || c[j] == '.') {
                j += 1;
            }
            let name: String = c[i..j].iter().collect();
            out.push(Token { tk: Tk::Ident(name), start, end: j });
            i = j;
            continue;
        }
        // operators
        if i + 1 < n {
            let two: String = c[i..i + 2].iter().collect();
            let op2 = match two.as_str() {
                "<>" => Some("<>"),
                "<=" => Some("<="),
                ">=" => Some(">="),
                _ => None,
            };
            if let Some(o) = op2 {
                out.push(Token { tk: Tk::Op(o), start, end: i + 2 });
                i += 2;
                continue;
            }
        }
        let tk = match ch {
            '+' => Tk::Op("+"),
            '-' => Tk::Op("-"),
            '*' => Tk::Op("*"),
            '/' => Tk::Op("/"),
            '^' => Tk::Op("^"),
            '&' => Tk::Op("&"),
            '=' => Tk::Op("="),
            '<' => Tk::Op("<"),
            '>' => Tk::Op(">"),
            '(' => Tk::LP,
            ')' => Tk::RP,
            ',' => Tk::Comma,
            _ => return None,
        };
        out.push(Token { tk, start, end: i + 1 });
        i += 1;
    }
    Some(out)
}

// ---------------------------------------------------------------------------
// References
// ---------------------------------------------------------------------------

struct WP<'a> {
    dc: bool,
    letters: &'a str,
    dr: bool,
    digits: &'a str,
}

fn word_parse(w: &str) -> Option<WP<'_>> {
    let b = w.as_bytes();
    let mut i = 0;
    let mut dc = false;
    if i < b.len() && b[i] == b'$' {
        dc = true;
        i += 1;
    }
    let ls = i;
    while i < b.len() && b[i].is_ascii_alphabetic() {
        i += 1;
    }
    let letters = &w[ls..i];
    let mut dr = false;
    if i < b.len() && b[i] == b'$' {
        dr = true;
        i += 1;
    }
    let ds = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    let digits = &w[ds..i];
    if i != b.len() || letters.is_empty() || digits.is_empty() {
        return None;
    }
    Some(WP { dc, letters, dr, digits })
}

fn wp_pos(p: &WP) -> Option<Pos> {
    if p.letters.len() != 1 || p.digits.len() > 3 || p.digits.starts_with('0') {
        return None;
    }
    let row: u16 = p.digits.parse().ok()?;
    if !(1..=999).contains(&row) {
        return None;
    }
    Some((p.letters.as_bytes()[0].to_ascii_uppercase() - b'A', row))
}

fn word_pos(w: &str) -> Option<Pos> {
    word_parse(w).and_then(|p| wp_pos(&p))
}

/// Cell reference argument of a command.
fn parse_cell(s: &str) -> Result<Pos, String> {
    let b = s.as_bytes();
    let ok = b.len() >= 2
        && b.len() <= 4
        && b[0].is_ascii_alphabetic()
        && b[1..].iter().all(|c| c.is_ascii_digit())
        && b[1] != b'0';
    if ok {
        if let Ok(row) = s[1..].parse::<u16>() {
            if (1..=999).contains(&row) {
                return Ok((b[0].to_ascii_uppercase() - b'A', row));
            }
        }
    }
    Err(format!("bad cell reference '{}'", s))
}

/// Range argument of a command.
fn parse_range(s: &str) -> Result<Rect, String> {
    let parts: Vec<&str> = s.split(':').collect();
    let res = match parts.as_slice() {
        [a] => parse_cell(a).ok().map(|p| (p, p)),
        [a, b] => match (parse_cell(a), parse_cell(b)) {
            (Ok(x), Ok(y)) => Some((x, y)),
            _ => None,
        },
        _ => None,
    };
    match res {
        Some((x, y)) => Ok(norm(x, y)),
        None => Err(format!("bad range '{}'", s)),
    }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
enum Ex {
    Num(f64),
    Str(String),
    Bool(bool),
    ErrRef,
    Name,
    /// None: invalid reference (#REF!)
    Ref(Option<Pos>),
    /// Corners as written; None: invalid corner
    Range(Option<(Pos, Pos)>),
    Paren(Box<Ex>),
    Un(char, Box<Ex>),
    Bin(&'static str, Box<Ex>, Box<Ex>),
    Call(String, Vec<Ex>),
}

struct Parser<'a> {
    t: &'a [Token],
    i: usize,
}

impl<'a> Parser<'a> {
    fn at(&self) -> Option<&'a Tk> {
        let t: &'a [Token] = self.t;
        t.get(self.i).map(|x| &x.tk)
    }

    fn op(&self) -> Option<&'static str> {
        match self.at() {
            Some(Tk::Op(o)) => Some(*o),
            _ => None,
        }
    }

    fn cmp(&mut self) -> Option<Ex> {
        let mut l = self.concat()?;
        while let Some(o) = self.op() {
            if matches!(o, "=" | "<>" | "<" | "<=" | ">" | ">=") {
                self.i += 1;
                let r = self.concat()?;
                l = Ex::Bin(o, Box::new(l), Box::new(r));
            } else {
                break;
            }
        }
        Some(l)
    }

    fn concat(&mut self) -> Option<Ex> {
        let mut l = self.add()?;
        while self.op() == Some("&") {
            self.i += 1;
            let r = self.add()?;
            l = Ex::Bin("&", Box::new(l), Box::new(r));
        }
        Some(l)
    }

    fn add(&mut self) -> Option<Ex> {
        let mut l = self.mul()?;
        while let Some(o) = self.op() {
            if o == "+" || o == "-" {
                self.i += 1;
                let r = self.mul()?;
                l = Ex::Bin(o, Box::new(l), Box::new(r));
            } else {
                break;
            }
        }
        Some(l)
    }

    fn mul(&mut self) -> Option<Ex> {
        let mut l = self.unary()?;
        while let Some(o) = self.op() {
            if o == "*" || o == "/" {
                self.i += 1;
                let r = self.unary()?;
                l = Ex::Bin(o, Box::new(l), Box::new(r));
            } else {
                break;
            }
        }
        Some(l)
    }

    fn unary(&mut self) -> Option<Ex> {
        if let Some(o) = self.op() {
            if o == "+" || o == "-" {
                self.i += 1;
                let x = self.unary()?;
                return Some(Ex::Un(o.chars().next().unwrap(), Box::new(x)));
            }
        }
        self.pow()
    }

    fn pow(&mut self) -> Option<Ex> {
        let b = self.primary()?;
        if self.op() == Some("^") {
            self.i += 1;
            let r = self.pow_rhs()?;
            return Some(Ex::Bin("^", Box::new(b), Box::new(r)));
        }
        Some(b)
    }

    fn pow_rhs(&mut self) -> Option<Ex> {
        if let Some(o) = self.op() {
            if o == "+" || o == "-" {
                self.i += 1;
                let x = self.pow_rhs()?;
                return Some(Ex::Un(o.chars().next().unwrap(), Box::new(x)));
            }
        }
        self.pow()
    }

    fn primary(&mut self) -> Option<Ex> {
        let tok: &'a Token = self.t.get(self.i)?;
        self.i += 1;
        match &tok.tk {
            Tk::Num(v) => Some(Ex::Num(*v)),
            Tk::Str(s) => Some(Ex::Str(s.clone())),
            Tk::ErrRef => Some(Ex::ErrRef),
            Tk::Ref(w) => Some(Ex::Ref(word_pos(w))),
            Tk::Range(a, b) => Some(Ex::Range(match (word_pos(a), word_pos(b)) {
                (Some(x), Some(y)) => Some((x, y)),
                _ => None,
            })),
            Tk::LP => {
                let e = self.cmp()?;
                if matches!(self.at(), Some(Tk::RP)) {
                    self.i += 1;
                    Some(Ex::Paren(Box::new(e)))
                } else {
                    None
                }
            }
            Tk::Ident(name) => {
                if matches!(self.at(), Some(Tk::LP)) {
                    self.i += 1;
                    let mut args = Vec::new();
                    if matches!(self.at(), Some(Tk::RP)) {
                        self.i += 1;
                        return Some(Ex::Call(name.to_uppercase(), args));
                    }
                    loop {
                        args.push(self.cmp()?);
                        match self.at() {
                            Some(Tk::Comma) => self.i += 1,
                            Some(Tk::RP) => {
                                self.i += 1;
                                break;
                            }
                            _ => return None,
                        }
                    }
                    return Some(Ex::Call(name.to_uppercase(), args));
                }
                let u = name.to_uppercase();
                if u == "TRUE" {
                    Some(Ex::Bool(true))
                } else if u == "FALSE" {
                    Some(Ex::Bool(false))
                } else {
                    Some(Ex::Name)
                }
            }
            _ => None,
        }
    }
}

fn parse_src(s: &str) -> Option<Ex> {
    let c: Vec<char> = s.chars().collect();
    let t = lex(&c)?;
    if t.is_empty() {
        return None;
    }
    let mut p = Parser { t: &t, i: 0 };
    let e = p.cmp()?;
    if p.i != t.len() {
        return None;
    }
    Some(e)
}

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug)]
enum Dep {
    One(Pos),
    Area(Rect),
}

fn collect_deps(e: &Ex, out: &mut Vec<Dep>) {
    match e {
        Ex::Ref(Some(p)) => out.push(Dep::One(*p)),
        Ex::Range(Some((a, b))) => out.push(Dep::Area(norm(*a, *b))),
        Ex::Paren(x) | Ex::Un(_, x) => collect_deps(x, out),
        Ex::Bin(_, l, r) => {
            collect_deps(l, out);
            collect_deps(r, out);
        }
        Ex::Call(name, args) => {
            if name != "ROW" && name != "COLUMN" {
                for a in args {
                    collect_deps(a, out);
                }
            }
        }
        _ => {}
    }
}

fn dep_cells(d: &Dep) -> Vec<Pos> {
    match d {
        Dep::One(p) => vec![*p],
        Dep::Area(r) => rect_cells(*r),
    }
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

struct Cell {
    raw: String,
    formula: bool,
    expr: Option<Ex>,
    deps: Vec<Dep>,
    value: Val,
}

#[derive(Default)]
struct Sheet {
    cells: HashMap<Pos, Cell>,
    /// single-cell precedent -> formulas depending on it
    rd_one: HashMap<Pos, Vec<Pos>>,
    /// range precedent -> formulas depending on it
    rd_area: Vec<(Rect, Pos)>,
    evals: u64,
}

fn tarjan(n: usize, adj: &[Vec<usize>]) -> Vec<Vec<usize>> {
    const UNV: usize = usize::MAX;
    struct St<'a> {
        adj: &'a [Vec<usize>],
        idx: Vec<usize>,
        low: Vec<usize>,
        on: Vec<bool>,
        stack: Vec<usize>,
        cnt: usize,
        out: Vec<Vec<usize>>,
    }
    fn strong(s: &mut St<'_>, v: usize) {
        s.idx[v] = s.cnt;
        s.low[v] = s.cnt;
        s.cnt += 1;
        s.stack.push(v);
        s.on[v] = true;
        for k in 0..s.adj[v].len() {
            let w = s.adj[v][k];
            if s.idx[w] == UNV {
                strong(s, w);
                s.low[v] = s.low[v].min(s.low[w]);
            } else if s.on[w] {
                s.low[v] = s.low[v].min(s.idx[w]);
            }
        }
        if s.low[v] == s.idx[v] {
            let mut comp = Vec::new();
            loop {
                let w = s.stack.pop().unwrap();
                s.on[w] = false;
                comp.push(w);
                if w == v {
                    break;
                }
            }
            s.out.push(comp);
        }
    }
    let mut st = St {
        adj,
        idx: vec![UNV; n],
        low: vec![0; n],
        on: vec![false; n],
        stack: Vec::new(),
        cnt: 0,
        out: Vec::new(),
    };
    for v in 0..n {
        if st.idx[v] == UNV {
            strong(&mut st, v);
        }
    }
    st.out
}

impl Sheet {
    fn val(&self, p: Pos) -> Val {
        self.cells.get(&p).map(|c| c.value.clone()).unwrap_or(Val::Empty)
    }

    fn items(&self, args: &[Ex]) -> Vec<(R, bool)> {
        let mut v = Vec::new();
        for a in args {
            match a {
                Ex::Range(Some((x, y))) => {
                    for p in rect_cells(norm(*x, *y)) {
                        let item = match self.val(p) {
                            Val::Err(e) => Err(e),
                            other => Ok(other),
                        };
                        v.push((item, true));
                    }
                }
                Ex::Range(None) => v.push((Err(E::Ref), true)),
                _ => v.push((self.eval(a), false)),
            }
        }
        v
    }

    fn numbers(&self, args: &[Ex]) -> Result<Vec<f64>, E> {
        let mut out = Vec::new();
        for (r, is_rng) in self.items(args) {
            let v = r?;
            if is_rng {
                if let Val::Num(x) = v {
                    out.push(x);
                }
            } else {
                out.push(to_num(&v)?);
            }
        }
        Ok(out)
    }

    fn num1(&self, a: &Ex) -> Result<f64, E> {
        to_num(&self.eval(a)?)
    }

    fn eval(&self, e: &Ex) -> R {
        match e {
            Ex::Num(x) => {
                if x.is_finite() {
                    Ok(Val::Num(*x))
                } else {
                    Err(E::Num)
                }
            }
            Ex::Str(s) => Ok(Val::Text(s.clone())),
            Ex::Bool(b) => Ok(Val::Bool(*b)),
            Ex::ErrRef => Err(E::Ref),
            Ex::Name => Err(E::Name),
            Ex::Ref(None) => Err(E::Ref),
            Ex::Ref(Some(p)) => match self.val(*p) {
                Val::Err(e) => Err(e),
                v => Ok(v),
            },
            Ex::Range(None) => Err(E::Ref),
            Ex::Range(Some(_)) => Err(E::Value),
            Ex::Paren(x) => self.eval(x),
            Ex::Un(op, x) => {
                let v = to_num(&self.eval(x)?)?;
                fin(if *op == '-' { -v } else { v })
            }
            Ex::Bin(op, l, r) => self.binary(op, l, r),
            Ex::Call(name, args) => self.call(name, args),
        }
    }

    fn binary(&self, op: &str, l: &Ex, r: &Ex) -> R {
        let a = self.eval(l);
        let b = self.eval(r);
        match op {
            "&" => {
                let a = a?;
                let b = b?;
                Ok(Val::Text(disp(&a) + &disp(&b)))
            }
            "=" | "<>" | "<" | "<=" | ">" | ">=" => {
                let a = a?;
                let b = b?;
                Ok(Val::Bool(test_op(op, cmp_vals(&a, &b))))
            }
            _ => {
                let x = a.and_then(|v| to_num(&v))?;
                let y = b.and_then(|v| to_num(&v))?;
                match op {
                    "+" => fin(x + y),
                    "-" => fin(x - y),
                    "*" => fin(x * y),
                    "/" => {
                        if y == 0.0 {
                            Err(E::Div0)
                        } else {
                            fin(x / y)
                        }
                    }
                    _ => fin(x.powf(y)),
                }
            }
        }
    }

    fn call(&self, name: &str, a: &[Ex]) -> R {
        let n = a.len();
        match name {
            "SUM" | "AVERAGE" | "MIN" | "MAX" | "PRODUCT" | "MEDIAN" => {
                if n == 0 {
                    return Err(E::Value);
                }
                let xs = self.numbers(a)?;
                match name {
                    "SUM" => fin(xs.iter().fold(0.0, |s, x| s + x)),
                    "AVERAGE" => {
                        if xs.is_empty() {
                            Err(E::Div0)
                        } else {
                            fin(xs.iter().fold(0.0, |s, x| s + x) / xs.len() as f64)
                        }
                    }
                    "MIN" => Ok(Val::Num(xs.iter().cloned().reduce(f64::min).unwrap_or(0.0))),
                    "MAX" => Ok(Val::Num(xs.iter().cloned().reduce(f64::max).unwrap_or(0.0))),
                    "PRODUCT" => {
                        if xs.is_empty() {
                            Ok(Val::Num(0.0))
                        } else {
                            fin(xs.iter().fold(1.0, |s, x| s * x))
                        }
                    }
                    _ => {
                        if xs.is_empty() {
                            return Err(E::Num);
                        }
                        let mut v = xs.clone();
                        v.sort_by(|p, q| p.partial_cmp(q).unwrap_or(Ordering::Equal));
                        let m = v.len();
                        let med = if m % 2 == 1 {
                            v[m / 2]
                        } else {
                            (v[m / 2 - 1] + v[m / 2]) / 2.0
                        };
                        fin(med)
                    }
                }
            }
            "COUNT" | "COUNTA" => {
                if n == 0 {
                    return Err(E::Value);
                }
                let mut c = 0usize;
                for (r, _) in self.items(a) {
                    let hit = if name == "COUNT" {
                        matches!(r, Ok(Val::Num(_)))
                    } else {
                        !matches!(r, Ok(Val::Empty))
                    };
                    if hit {
                        c += 1;
                    }
                }
                Ok(Val::Num(c as f64))
            }
            "IF" => {
                if n < 2 || n > 3 {
                    return Err(E::Value);
                }
                let c = to_bool(&self.eval(&a[0])?)?;
                if c {
                    self.eval(&a[1])
                } else if n == 3 {
                    self.eval(&a[2])
                } else {
                    Ok(Val::Bool(false))
                }
            }
            "IFERROR" => {
                if n != 2 {
                    return Err(E::Value);
                }
                match self.eval(&a[0]) {
                    Ok(v) => Ok(v),
                    Err(_) => self.eval(&a[1]),
                }
            }
            "CHOOSE" => {
                if n < 2 {
                    return Err(E::Value);
                }
                let i = self.num1(&a[0])?.floor();
                let cnt = (n - 1) as f64;
                if !(i >= 1.0 && i <= cnt) {
                    return Err(E::Value);
                }
                self.eval(&a[i as usize])
            }
            "AND" | "OR" => {
                if n == 0 {
                    return Err(E::Value);
                }
                let is_and = name == "AND";
                let mut acc = is_and;
                let mut any = false;
                for (r, rng) in self.items(a) {
                    let v = r?;
                    if rng && matches!(v, Val::Text(_) | Val::Empty) {
                        continue;
                    }
                    let b = to_bool(&v)?;
                    any = true;
                    if is_and {
                        acc = acc && b;
                    } else {
                        acc = acc || b;
                    }
                }
                if !any {
                    return Err(E::Value);
                }
                Ok(Val::Bool(acc))
            }
            "NOT" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let b = to_bool(&self.eval(&a[0])?)?;
                Ok(Val::Bool(!b))
            }
            "ABS" => {
                if n != 1 {
                    return Err(E::Value);
                }
                fin(self.num1(&a[0])?.abs())
            }
            "INT" => {
                if n != 1 {
                    return Err(E::Value);
                }
                fin(self.num1(&a[0])?.floor())
            }
            "SQRT" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let x = self.num1(&a[0])?;
                if x < 0.0 {
                    return Err(E::Num);
                }
                fin(x.sqrt())
            }
            "POW" => {
                if n != 2 {
                    return Err(E::Value);
                }
                let x = self.num1(&a[0]);
                let y = self.num1(&a[1]);
                let x = x?;
                let y = y?;
                fin(x.powf(y))
            }
            "MOD" => {
                if n != 2 {
                    return Err(E::Value);
                }
                let x = self.num1(&a[0]);
                let y = self.num1(&a[1]);
                let x = x?;
                let y = y?;
                if y == 0.0 {
                    return Err(E::Div0);
                }
                fin(x - y * (x / y).floor())
            }
            "ROUND" => {
                if n < 1 || n > 2 {
                    return Err(E::Value);
                }
                let x = self.num1(&a[0])?;
                let d = if n == 2 { self.num1(&a[1])?.trunc() } else { 0.0 };
                if d.abs() > 15.0 {
                    return Err(E::Num);
                }
                let p = 10f64.powi(d as i32);
                fin((x * p).round() / p)
            }
            "LEN" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let s = disp(&self.eval(&a[0])?);
                Ok(Val::Num(s.chars().count() as f64))
            }
            "UPPER" | "LOWER" | "TRIM" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let s = disp(&self.eval(&a[0])?);
                let t = match name {
                    "UPPER" => s.to_ascii_uppercase(),
                    "LOWER" => s.to_ascii_lowercase(),
                    _ => s.split_whitespace().collect::<Vec<_>>().join(" "),
                };
                Ok(Val::Text(t))
            }
            "LEFT" | "RIGHT" => {
                if n < 1 || n > 2 {
                    return Err(E::Value);
                }
                let s = disp(&self.eval(&a[0])?);
                let k = if n == 2 { self.num1(&a[1])?.floor() } else { 1.0 };
                if k < 0.0 {
                    return Err(E::Value);
                }
                let chars: Vec<char> = s.chars().collect();
                let take = (k as usize).min(chars.len());
                let out: String = if name == "LEFT" {
                    chars[..take].iter().collect()
                } else {
                    chars[chars.len() - take..].iter().collect()
                };
                Ok(Val::Text(out))
            }
            "MID" => {
                if n != 3 {
                    return Err(E::Value);
                }
                let s = disp(&self.eval(&a[0])?);
                let start = self.num1(&a[1])?.floor();
                let len = self.num1(&a[2])?.floor();
                if start < 1.0 || len < 0.0 {
                    return Err(E::Value);
                }
                let out: String = s
                    .chars()
                    .skip(start as usize - 1)
                    .take(len as usize)
                    .collect();
                Ok(Val::Text(out))
            }
            "CONCAT" => {
                if n == 0 {
                    return Err(E::Value);
                }
                let mut out = String::new();
                for (r, _) in self.items(a) {
                    let v = r?;
                    out.push_str(&disp(&v));
                }
                Ok(Val::Text(out))
            }
            "SUBSTITUTE" => {
                if n != 3 {
                    return Err(E::Value);
                }
                let s = disp(&self.eval(&a[0])?);
                let old = disp(&self.eval(&a[1])?);
                let new = disp(&self.eval(&a[2])?);
                if old.is_empty() {
                    Ok(Val::Text(s))
                } else {
                    Ok(Val::Text(s.replace(&old, &new)))
                }
            }
            "VALUE" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let v = self.eval(&a[0])?;
                Ok(Val::Num(to_num(&v)?))
            }
            "ISERROR" => {
                if n != 1 {
                    return Err(E::Value);
                }
                Ok(Val::Bool(self.eval(&a[0]).is_err()))
            }
            "ISBLANK" => {
                if n != 1 {
                    return Err(E::Value);
                }
                Ok(Val::Bool(matches!(self.eval(&a[0]), Ok(Val::Empty))))
            }
            "ISNUMBER" => {
                if n != 1 {
                    return Err(E::Value);
                }
                Ok(Val::Bool(matches!(self.eval(&a[0]), Ok(Val::Num(_)))))
            }
            "ISTEXT" => {
                if n != 1 {
                    return Err(E::Value);
                }
                Ok(Val::Bool(matches!(self.eval(&a[0]), Ok(Val::Text(_)))))
            }
            "ROW" | "COLUMN" => {
                if n != 1 {
                    return Err(E::Value);
                }
                let p = match &a[0] {
                    Ex::Ref(Some(p)) => *p,
                    Ex::Range(Some((x, _))) => *x,
                    Ex::Ref(None) | Ex::Range(None) => return Err(E::Ref),
                    _ => return Err(E::Value),
                };
                let v = if name == "ROW" { p.1 as f64 } else { (p.0 as f64) + 1.0 };
                Ok(Val::Num(v))
            }
            "INDEX" => {
                if n < 2 || n > 3 {
                    return Err(E::Value);
                }
                let rc = match &a[0] {
                    Ex::Range(Some((x, y))) => norm(*x, *y),
                    Ex::Range(None) => return Err(E::Ref),
                    _ => return Err(E::Value),
                };
                let h = (rc.1 .1 - rc.0 .1 + 1) as f64;
                let w = (rc.1 .0 - rc.0 .0 + 1) as f64;
                let r = self.num1(&a[1])?.floor();
                let (row, col) = if n == 3 {
                    let c = self.num1(&a[2])?.floor();
                    (r, c)
                } else if h == 1.0 {
                    (1.0, r)
                } else {
                    (r, 1.0)
                };
                if row < 1.0 || row > h || col < 1.0 || col > w {
                    return Err(E::Ref);
                }
                let p = (rc.0 .0 + (col - 1.0) as u8, rc.0 .1 + (row - 1.0) as u16);
                match self.val(p) {
                    Val::Err(e) => Err(e),
                    v => Ok(v),
                }
            }
            "COUNTIF" => {
                if n != 2 {
                    return Err(E::Value);
                }
                let rc = match &a[0] {
                    Ex::Range(Some((x, y))) => norm(*x, *y),
                    Ex::Range(None) => return Err(E::Ref),
                    _ => return Err(E::Value),
                };
                let crit = self.eval(&a[1])?;
                let (op, operand): (&str, Val) = match crit {
                    Val::Text(s) => {
                        let mut op: &str = "=";
                        let mut rest: &str = &s;
                        for o in [">=", "<=", "<>", ">", "<", "="] {
                            if let Some(r) = s.strip_prefix(o) {
                                op = o;
                                rest = r;
                                break;
                            }
                        }
                        let operand = match number_literal(rest) {
                            Some(x) => Val::Num(x),
                            None => Val::Text(rest.to_string()),
                        };
                        (op, operand)
                    }
                    other => ("=", other),
                };
                let mut cnt = 0usize;
                for p in rect_cells(rc) {
                    let cell = self.val(p);
                    let hit = if tag(&cell) == tag(&operand) {
                        test_op(op, cmp_vals(&cell, &operand))
                    } else {
                        op == "<>" && !matches!(cell, Val::Empty)
                    };
                    if hit {
                        cnt += 1;
                    }
                }
                Ok(Val::Num(cnt as f64))
            }
            _ => Err(E::Name),
        }
    }

    /// Final value of a formula's expression.
    fn eval_top(&self, e: &Ex) -> Val {
        match self.eval(e) {
            Ok(Val::Empty) => Val::Num(0.0),
            Ok(v) => v,
            Err(e) => Val::Err(e),
        }
    }

    fn eval_cell(&self, p: Pos) -> Val {
        match self.cells.get(&p) {
            Some(Cell { expr: Some(e), .. }) => self.eval_top(e),
            _ => Val::Err(E::Parse),
        }
    }

    fn dependents_of(&self, x: Pos) -> Vec<Pos> {
        let mut v: Vec<Pos> = self.rd_one.get(&x).cloned().unwrap_or_default();
        for (r, f) in &self.rd_area {
            if in_rect(*r, x) {
                v.push(*f);
            }
        }
        v
    }

    fn unindex(&mut self, p: Pos, deps: &[Dep]) {
        for d in deps {
            if let Dep::One(q) = d {
                let empty = match self.rd_one.get_mut(q) {
                    Some(v) => {
                        v.retain(|&x| x != p);
                        v.is_empty()
                    }
                    None => false,
                };
                if empty {
                    self.rd_one.remove(q);
                }
            }
        }
        if deps.iter().any(|d| matches!(d, Dep::Area(_))) {
            self.rd_area.retain(|(_, f)| *f != p);
        }
    }

    /// Replace the content of `p` from its raw text (trimmed VALUE). No recalculation.
    fn store(&mut self, p: Pos, raw: &str) {
        if let Some(old) = self.cells.remove(&p) {
            if old.formula {
                self.unindex(p, &old.deps);
            }
        }
        if raw.is_empty() {
            return;
        }
        if let Some(src) = raw.strip_prefix('=') {
            let expr = parse_src(src);
            let mut deps = Vec::new();
            if let Some(e) = &expr {
                collect_deps(e, &mut deps);
            }
            for d in &deps {
                match d {
                    Dep::One(q) => self.rd_one.entry(*q).or_default().push(p),
                    Dep::Area(r) => self.rd_area.push((*r, p)),
                }
            }
            self.cells.insert(
                p,
                Cell {
                    raw: raw.to_string(),
                    formula: true,
                    expr,
                    deps,
                    value: Val::Empty,
                },
            );
        } else {
            self.cells.insert(
                p,
                Cell {
                    raw: raw.to_string(),
                    formula: false,
                    expr: None,
                    deps: Vec::new(),
                    value: const_value(raw),
                },
            );
        }
    }

    /// Recalculate everything affected by the changed cells. Returns N.
    fn recalc(&mut self, changed: &[Pos]) -> usize {
        let mut seen: HashSet<Pos> = HashSet::new();
        let mut q: VecDeque<Pos> = VecDeque::new();
        for &c in changed {
            if seen.insert(c) {
                q.push_back(c);
            }
        }
        while let Some(x) = q.pop_front() {
            for f in self.dependents_of(x) {
                if seen.insert(f) {
                    q.push_back(f);
                }
            }
        }
        let mut members: Vec<Pos> = seen
            .iter()
            .copied()
            .filter(|p| self.cells.get(p).map_or(false, |c| c.formula))
            .collect();
        members.sort();
        let n = members.len();
        if n == 0 {
            return 0;
        }
        let index: HashMap<Pos, usize> = members.iter().enumerate().map(|(i, p)| (*p, i)).collect();
        let mut adj: Vec<Vec<usize>> = vec![Vec::new(); n];
        for (i, p) in members.iter().enumerate() {
            let cell = &self.cells[p];
            for d in &cell.deps {
                match d {
                    Dep::One(q) => {
                        if let Some(&j) = index.get(q) {
                            adj[i].push(j);
                        }
                    }
                    Dep::Area(r) => {
                        if rect_area(*r) <= n {
                            for q in rect_cells(*r) {
                                if let Some(&j) = index.get(&q) {
                                    adj[i].push(j);
                                }
                            }
                        } else {
                            for (j, q) in members.iter().enumerate() {
                                if in_rect(*r, *q) {
                                    adj[i].push(j);
                                }
                            }
                        }
                    }
                }
            }
        }
        let sccs = tarjan(n, &adj);
        for comp in sccs {
            let cyclic = comp.len() > 1 || adj[comp[0]].contains(&comp[0]);
            if cyclic {
                for &i in &comp {
                    self.set_value(members[i], Val::Err(E::Cycle));
                }
            } else {
                let p = members[comp[0]];
                let v = self.eval_cell(p);
                self.set_value(p, v);
            }
        }
        self.evals += n as u64;
        n
    }

    fn set_value(&mut self, p: Pos, v: Val) {
        if let Some(c) = self.cells.get_mut(&p) {
            c.value = v;
        }
    }

    /// Dependency-expanded precedents of a formula cell.
    fn precedents(&self, p: Pos) -> BTreeSet<(u16, u8)> {
        let mut out = BTreeSet::new();
        if let Some(c) = self.cells.get(&p) {
            for d in &c.deps {
                for q in dep_cells(d) {
                    out.insert((q.1, q.0));
                }
            }
        }
        out
    }

    fn dependents(&self, p: Pos) -> BTreeSet<(u16, u8)> {
        let mut seen: HashSet<Pos> = HashSet::new();
        let mut out = BTreeSet::new();
        let mut q = VecDeque::new();
        q.push_back(p);
        while let Some(x) = q.pop_front() {
            for f in self.dependents_of(x) {
                if seen.insert(f) {
                    out.insert((f.1, f.0));
                    q.push_back(f);
                }
            }
        }
        out
    }
}

// ---------------------------------------------------------------------------
// Copy shifting
// ---------------------------------------------------------------------------

/// Shift one reference word. Returns (text, out_of_grid). Invalid words are unchanged.
fn shift_corner(w: &str, dc: i32, dr: i32) -> (String, bool) {
    match word_parse(w).and_then(|p| wp_pos(&p).map(|pos| (p, pos))) {
        None => (w.to_string(), false),
        Some((p, pos)) => {
            let mut col = pos.0 as i32;
            let mut row = pos.1 as i32;
            if !p.dc {
                col += dc;
            }
            if !p.dr {
                row += dr;
            }
            if !(0..=25).contains(&col) || !(1..=999).contains(&row) {
                return (String::new(), true);
            }
            let mut s = String::new();
            if p.dc {
                s.push('$');
            }
            s.push(col_letter(col as u8));
            if p.dr {
                s.push('$');
            }
            s.push_str(&row.to_string());
            (s, false)
        }
    }
}

fn shift_formula(src: &str, dc: i32, dr: i32) -> String {
    let c: Vec<char> = src.chars().collect();
    let toks = match lex(&c) {
        Some(t) => t,
        None => return src.to_string(),
    };
    let mut out = String::new();
    let mut last = 0;
    for t in &toks {
        match &t.tk {
            Tk::Ref(w) => {
                out.extend(c[last..t.start].iter());
                let (s, oob) = shift_corner(w, dc, dr);
                if oob {
                    out.push_str("#REF!");
                } else {
                    out.push_str(&s);
                }
                last = t.end;
            }
            Tk::Range(a, b) => {
                out.extend(c[last..t.start].iter());
                let (sa, oa) = shift_corner(a, dc, dr);
                let (sb, ob) = shift_corner(b, dc, dr);
                if oa || ob {
                    out.push_str("#REF!");
                } else {
                    out.push_str(&sa);
                    out.push(':');
                    out.push_str(&sb);
                }
                last = t.end;
            }
            _ => {}
        }
    }
    out.extend(c[last..].iter());
    out
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

/// Parse import block lines into non-blank records of fields.
fn csv_records(lines: &[&str]) -> Vec<Vec<String>> {
    let text = lines.join("\n");
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    let mut recs: Vec<Vec<String>> = Vec::new();
    let mut fields: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut in_q = false;
    let mut nonblank = false;
    let mut i = 0;
    while i < n {
        let c = chars[i];
        if in_q {
            if c == '"' {
                if i + 1 < n && chars[i + 1] == '"' {
                    cur.push('"');
                    i += 2;
                    continue;
                }
                in_q = false;
            } else {
                cur.push(c);
            }
        } else {
            match c {
                '"' => {
                    in_q = true;
                    nonblank = true;
                }
                ',' => {
                    fields.push(std::mem::take(&mut cur));
                    nonblank = true;
                }
                '\n' => {
                    fields.push(std::mem::take(&mut cur));
                    if nonblank {
                        recs.push(std::mem::take(&mut fields));
                    } else {
                        fields.clear();
                    }
                    nonblank = false;
                }
                '\r' => {}
                _ => {
                    if !c.is_whitespace() {
                        nonblank = true;
                    }
                    cur.push(c);
                }
            }
        }
        i += 1;
    }
    if nonblank {
        fields.push(cur);
        recs.push(fields);
    }
    recs
}

fn csv_quote(s: &str) -> String {
    if s.contains(|c| c == ',' || c == '"' || c == '\n' || c == '\r')
        || s.starts_with(' ')
        || s.ends_with(' ')
    {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn default_rect(sh: &Sheet) -> Option<Rect> {
    if sh.cells.is_empty() {
        return None;
    }
    let mut mc = 0u8;
    let mut mr = 1u16;
    for p in sh.cells.keys() {
        mc = mc.max(p.0);
        mr = mr.max(p.1);
    }
    Some(((0, 1), (mc, mr)))
}

fn cmd_set(sh: &mut Sheet, rest: &str) -> Result<String, String> {
    let r = rest.trim();
    if r.is_empty() {
        return Err("usage: set CELL VALUE".to_string());
    }
    let (cell_tok, value) = match r.find(char::is_whitespace) {
        Some(k) => (&r[..k], r[k..].trim()),
        None => (r, ""),
    };
    let p = parse_cell(cell_tok)?;
    sh.store(p, value);
    let n = sh.recalc(&[p]);
    Ok(format!("recalc {}\n", n))
}

fn cmd_get(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: get CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    Ok(match sh.cells.get(&p) {
        None => "(empty)\n".to_string(),
        Some(c) => format!("{}\n", disp(&c.value)),
    })
}

fn cmd_show(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: show CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    let name = pos_name(p);
    Ok(match sh.cells.get(&p) {
        None => format!("{}: (empty)\n", name),
        Some(c) if !c.formula => format!("{}: {}\n", name, c.raw),
        Some(c) => format!("{}: {} => {}\n", name, c.raw, disp(&c.value)),
    })
}

fn cmd_clear(sh: &mut Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: clear CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    sh.store(p, "");
    let n = sh.recalc(&[p]);
    Ok(format!("recalc {}\n", n))
}

fn cmd_copy(sh: &mut Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 2 {
        return Err("usage: copy SRC DST".to_string());
    }
    let src = parse_cell(args[0])?;
    let dst = parse_range(args[1])?;
    let src_raw: Option<String> = sh.cells.get(&src).map(|c| c.raw.clone());
    let mut changed = Vec::new();
    for d in rect_cells(dst) {
        let new_raw = match &src_raw {
            None => String::new(),
            Some(raw) => match raw.strip_prefix('=') {
                Some(f) => {
                    let dc = d.0 as i32 - src.0 as i32;
                    let dr = d.1 as i32 - src.1 as i32;
                    format!("={}", shift_formula(f, dc, dr))
                }
                None => raw.clone(),
            },
        };
        sh.store(d, &new_raw);
        changed.push(d);
    }
    let n = sh.recalc(&changed);
    Ok(format!("recalc {}\n", n))
}

fn cmd_import(sh: &mut Sheet, args: &[&str], block: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: import CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    let recs = csv_records(block);
    let r = recs.len();
    let c = recs.iter().map(|x| x.len()).max().unwrap_or(0);
    if r > 0 && (p.1 as usize + r - 1 > 999 || p.0 as usize + c - 1 > 25) {
        return Err("import out of range".to_string());
    }
    let mut changed = Vec::new();
    for (ri, rec) in recs.iter().enumerate() {
        for (ci, f) in rec.iter().enumerate() {
            let pos = (p.0 + ci as u8, p.1 + ri as u16);
            sh.store(pos, f.trim());
            changed.push(pos);
        }
    }
    let n = sh.recalc(&changed);
    Ok(format!("imported {} rows, {} columns; recalc {}\n", r, c, n))
}

fn cmd_print(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    let usage = "usage: print [RANGE]".to_string();
    if args.len() > 1 {
        return Err(usage);
    }
    if let Some(a) = args.first() {
        if *a == "formulas" || *a == "values" {
            return Err(usage);
        }
    }
    let rc = match args.first() {
        Some(a) => parse_range(a)?,
        None => match default_rect(sh) {
            Some(r) => r,
            None => return Ok("(empty sheet)\n".to_string()),
        },
    };
    let mut out = String::new();
    for row in rc.0 .1..=rc.1 .1 {
        let fields: Vec<String> = (rc.0 .0..=rc.1 .0)
            .map(|col| disp(&sh.val((col, row))))
            .collect();
        out.push_str(&fields.join(" | "));
        out.push('\n');
    }
    Ok(out)
}

fn cmd_export(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    let usage = "usage: export [formulas] [RANGE]".to_string();
    let is_kw = |s: &str| s == "formulas" || s == "values";
    let (formulas, rng_arg): (bool, Option<&str>) = match args.len() {
        0 => (false, None),
        1 => {
            if is_kw(args[0]) {
                (args[0] == "formulas", None)
            } else {
                (false, Some(args[0]))
            }
        }
        2 => {
            if is_kw(args[0]) && !is_kw(args[1]) {
                (args[0] == "formulas", Some(args[1]))
            } else {
                return Err(usage);
            }
        }
        _ => return Err(usage),
    };
    let rc = match rng_arg {
        Some(a) => parse_range(a)?,
        None => match default_rect(sh) {
            Some(r) => r,
            None => return Ok("(empty sheet)\n".to_string()),
        },
    };
    let mut out = String::new();
    for row in rc.0 .1..=rc.1 .1 {
        let fields: Vec<String> = (rc.0 .0..=rc.1 .0)
            .map(|col| {
                let p = (col, row);
                let text = if formulas {
                    sh.cells.get(&p).map(|c| c.raw.clone()).unwrap_or_default()
                } else {
                    disp(&sh.val(p))
                };
                csv_quote(&text)
            })
            .collect();
        out.push_str(&fields.join(","));
        out.push('\n');
    }
    Ok(out)
}

fn names_line(set: &BTreeSet<(u16, u8)>) -> String {
    if set.is_empty() {
        return "(none)\n".to_string();
    }
    let names: Vec<String> = set
        .iter()
        .map(|(row, col)| format!("{}{}", col_letter(*col), row))
        .collect();
    format!("{}\n", names.join(" "))
}

fn cmd_precedents(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: precedents CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    Ok(names_line(&sh.precedents(p)))
}

fn cmd_dependents(sh: &Sheet, args: &[&str]) -> Result<String, String> {
    if args.len() != 1 {
        return Err("usage: dependents CELL".to_string());
    }
    let p = parse_cell(args[0])?;
    Ok(names_line(&sh.dependents(p)))
}

fn cmd_stats(sh: &Sheet) -> String {
    let formulas = sh.cells.values().filter(|c| c.formula).count();
    format!(
        "cells {} formulas {} evals {}\n",
        sh.cells.len(),
        formulas,
        sh.evals
    )
}

fn run() {
    let mut buf = Vec::new();
    let _ = io::stdin().read_to_end(&mut buf);
    let text = String::from_utf8_lossy(&buf).into_owned();
    let lines: Vec<&str> = text
        .lines()
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();

    let mut sh = Sheet::default();
    let mut out = String::new();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        i += 1;
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        out.push_str("> ");
        out.push_str(line.trim_end());
        out.push('\n');

        let ls = line.trim_start();
        let word = ls.split_whitespace().next().unwrap_or("");
        let rest = &ls[word.len()..];
        let args: Vec<&str> = rest.split_whitespace().collect();

        let result = match word {
            "set" => cmd_set(&mut sh, rest),
            "get" => cmd_get(&sh, &args),
            "show" => cmd_show(&sh, &args),
            "clear" => cmd_clear(&mut sh, &args),
            "copy" => cmd_copy(&mut sh, &args),
            "import" => {
                let mut block: Vec<&str> = Vec::new();
                while i < lines.len() && lines[i] != "." {
                    block.push(lines[i]);
                    i += 1;
                }
                if i < lines.len() {
                    i += 1; // skip the terminating "."
                }
                cmd_import(&mut sh, &args, &block)
            }
            "print" => cmd_print(&sh, &args),
            "export" => cmd_export(&sh, &args),
            "precedents" => cmd_precedents(&sh, &args),
            "dependents" => cmd_dependents(&sh, &args),
            "stats" => Ok(cmd_stats(&sh)),
            _ => Err(format!("unknown command '{}'", word)),
        };
        match result {
            Ok(s) => out.push_str(&s),
            Err(m) => {
                out.push_str("error: ");
                out.push_str(&m);
                out.push('\n');
            }
        }
    }
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(out.as_bytes());
    let _ = lock.flush();
}

fn main() {
    // Deep recursion is possible in long formula chains; use a large stack.
    let child = std::thread::Builder::new()
        .stack_size(512 * 1024 * 1024)
        .spawn(run)
        .expect("spawn");
    let _ = child.join();
}
