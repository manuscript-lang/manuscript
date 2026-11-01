// A small Scheme-like interpreter. Reads a program from stdin, writes to stdout.
// Standard library only.

use std::cell::RefCell;
use std::collections::HashMap;
use std::io::{self, Read, Write};
use std::rc::Rc;

const MAX_DEPTH: usize = 10_000;
const STACK_SIZE: usize = 1 << 30;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

#[derive(Clone)]
enum Value {
    Int(i64),
    Bool(bool),
    Str(Rc<Vec<u8>>),
    Sym(Rc<str>),
    Pair(Rc<Pair>),
    Nil,
    Void,
    Closure(Rc<Closure>),
    Builtin(usize),
}

struct Pair {
    car: RefCell<Value>,
    cdr: RefCell<Value>,
}

impl Pair {
    fn car(&self) -> Value {
        self.car.borrow().clone()
    }
    fn cdr(&self) -> Value {
        self.cdr.borrow().clone()
    }
}

struct Closure {
    name: Option<Rc<str>>,
    params: Vec<Rc<str>>,
    rest: Option<Rc<str>>,
    body: Rc<Vec<Value>>,
    env: Rc<Env>,
}

/// A frame of local bindings. The frame with `parent == None` is the global
/// environment; its bindings live in `Interp::globals`.
struct Env {
    vars: RefCell<Vec<(Rc<str>, Value)>>,
    parent: Option<Rc<Env>>,
}

struct Fail {
    msg: String,
    syntax: bool,
}

type R<T> = Result<T, Fail>;

fn rt<T>(msg: impl Into<String>) -> R<T> {
    Err(Fail { msg: msg.into(), syntax: false })
}

fn syn<T>(msg: impl Into<String>) -> R<T> {
    Err(Fail { msg: msg.into(), syntax: true })
}

fn bad<T>(form: &str) -> R<T> {
    syn(format!("bad form: {}", form))
}

fn ovf() -> Fail {
    Fail { msg: "integer overflow".to_string(), syntax: false }
}

fn tyerr<T>(name: &str, kind: &str, v: &Value) -> R<T> {
    rt(format!("{}: expected {}, got {}", name, kind, show(v, false)))
}

fn cons(a: Value, b: Value) -> Value {
    Value::Pair(Rc::new(Pair { car: RefCell::new(a), cdr: RefCell::new(b) }))
}

fn from_vec(items: Vec<Value>, tail: Value) -> Value {
    let mut r = tail;
    for x in items.into_iter().rev() {
        r = cons(x, r);
    }
    r
}

/// Elements of a proper list, or None.
fn list_vec(v: &Value) -> Option<Vec<Value>> {
    let mut out = Vec::new();
    let mut cur = v.clone();
    loop {
        match cur {
            Value::Nil => return Some(out),
            Value::Pair(p) => {
                out.push(p.car());
                cur = p.cdr();
            }
            _ => return None,
        }
    }
}

fn is_proper(v: &Value) -> bool {
    let mut cur = v.clone();
    loop {
        match cur {
            Value::Nil => return true,
            Value::Pair(p) => cur = p.cdr(),
            _ => return false,
        }
    }
}

fn truthy(v: &Value) -> bool {
    !matches!(v, Value::Bool(false))
}

fn render(v: &Value, disp: bool, out: &mut Vec<u8>) {
    match v {
        Value::Int(n) => out.extend_from_slice(n.to_string().as_bytes()),
        Value::Bool(b) => out.extend_from_slice(if *b { &b"#t"[..] } else { &b"#f"[..] }),
        Value::Str(s) => {
            if disp {
                out.extend_from_slice(s.as_slice());
            } else {
                out.push(b'"');
                for &c in s.iter() {
                    match c {
                        b'\\' => out.extend_from_slice(b"\\\\"),
                        b'"' => out.extend_from_slice(b"\\\""),
                        b'\n' => out.extend_from_slice(b"\\n"),
                        b'\t' => out.extend_from_slice(b"\\t"),
                        _ => out.push(c),
                    }
                }
                out.push(b'"');
            }
        }
        Value::Sym(s) => out.extend_from_slice(s.as_bytes()),
        Value::Pair(p) => {
            out.push(b'(');
            render(&p.car(), disp, out);
            let mut cur = p.cdr();
            loop {
                match cur {
                    Value::Pair(q) => {
                        out.push(b' ');
                        render(&q.car(), disp, out);
                        cur = q.cdr();
                    }
                    Value::Nil => break,
                    other => {
                        out.extend_from_slice(b" . ");
                        render(&other, disp, out);
                        break;
                    }
                }
            }
            out.push(b')');
        }
        Value::Nil => out.extend_from_slice(b"()"),
        Value::Void => out.extend_from_slice(b"#<void>"),
        Value::Closure(c) => match &c.name {
            Some(n) => out.extend_from_slice(format!("#<procedure {}>", n).as_bytes()),
            None => out.extend_from_slice(b"#<procedure>"),
        },
        Value::Builtin(i) => {
            out.extend_from_slice(format!("#<builtin {}>", BUILTINS[*i].name).as_bytes())
        }
    }
}

fn show(v: &Value, disp: bool) -> String {
    let mut b = Vec::new();
    render(v, disp, &mut b);
    String::from_utf8_lossy(&b).into_owned()
}

fn eqp(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Int(x), Value::Int(y)) => x == y,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Sym(x), Value::Sym(y)) => x == y,
        (Value::Nil, Value::Nil) => true,
        (Value::Void, Value::Void) => true,
        _ => false,
    }
}

fn equalp(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Pair(_), Value::Pair(_)) => {
            let mut x = a.clone();
            let mut y = b.clone();
            loop {
                let next = match (&x, &y) {
                    (Value::Pair(p), Value::Pair(q)) => {
                        if !equalp(&p.car(), &q.car()) {
                            return false;
                        }
                        Some((p.cdr(), q.cdr()))
                    }
                    _ => None,
                };
                match next {
                    Some((nx, ny)) => {
                        x = nx;
                        y = ny;
                    }
                    None => return equalp(&x, &y),
                }
            }
        }
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Closure(x), Value::Closure(y)) => Rc::ptr_eq(x, y),
        (Value::Builtin(x), Value::Builtin(y)) => x == y,
        _ => eqp(a, b),
    }
}

fn is_int_token(tok: &[u8]) -> bool {
    let d = if tok.first() == Some(&b'-') { &tok[1..] } else { tok };
    !d.is_empty() && d.iter().all(|c| c.is_ascii_digit())
}

// ---------------------------------------------------------------------------
// Reader
// ---------------------------------------------------------------------------

struct Reader<'a> {
    src: &'a [u8],
    pos: usize,
}

fn is_delim(c: Option<u8>) -> bool {
    matches!(
        c,
        None | Some(b' ')
            | Some(b'\t')
            | Some(b'\n')
            | Some(b'\r')
            | Some(b'(')
            | Some(b')')
            | Some(b'"')
            | Some(b';')
    )
}

impl<'a> Reader<'a> {
    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn at_eof(&self) -> bool {
        self.pos >= self.src.len()
    }

    fn skip_ws(&mut self) {
        loop {
            match self.peek() {
                Some(b' ') | Some(b'\t') | Some(b'\n') | Some(b'\r') => self.pos += 1,
                Some(b';') => {
                    while let Some(c) = self.peek() {
                        if c == b'\n' {
                            break;
                        }
                        self.pos += 1;
                    }
                }
                _ => break,
            }
        }
    }

    /// Reads one datum. Caller must have checked that input is not exhausted
    /// at top level; inside a datum, running out is an error.
    fn read(&mut self) -> R<Value> {
        self.skip_ws();
        match self.peek() {
            None => syn("unexpected end of input"),
            Some(b'(') => {
                self.pos += 1;
                self.read_list()
            }
            Some(b')') => syn("unexpected )"),
            Some(b'\'') => {
                self.pos += 1;
                let d = self.read()?;
                Ok(from_vec(vec![Value::Sym(Rc::from("quote")), d], Value::Nil))
            }
            Some(b'"') => {
                self.pos += 1;
                self.read_string()
            }
            Some(_) => self.read_atom(),
        }
    }

    fn read_list(&mut self) -> R<Value> {
        let mut items = Vec::new();
        loop {
            self.skip_ws();
            match self.peek() {
                None => return syn("unexpected end of input"),
                Some(b')') => {
                    self.pos += 1;
                    return Ok(from_vec(items, Value::Nil));
                }
                Some(b'.') if is_delim(self.src.get(self.pos + 1).copied()) => {
                    if items.is_empty() {
                        return syn("bad dotted list");
                    }
                    self.pos += 1;
                    self.skip_ws();
                    match self.peek() {
                        None => return syn("unexpected end of input"),
                        Some(b')') => return syn("bad dotted list"),
                        _ => {}
                    }
                    let tail = self.read()?;
                    self.skip_ws();
                    match self.peek() {
                        None => return syn("unexpected end of input"),
                        Some(b')') => {
                            self.pos += 1;
                            return Ok(from_vec(items, tail));
                        }
                        _ => return syn("bad dotted list"),
                    }
                }
                _ => items.push(self.read()?),
            }
        }
    }

    fn read_string(&mut self) -> R<Value> {
        let mut buf = Vec::new();
        loop {
            match self.peek() {
                None => return syn("unterminated string"),
                Some(b'"') => {
                    self.pos += 1;
                    break;
                }
                Some(b'\\') => {
                    self.pos += 1;
                    let c = match self.peek() {
                        None => return syn("unterminated string"),
                        Some(c) => c,
                    };
                    let r = match c {
                        b'n' => b'\n',
                        b't' => b'\t',
                        b'\\' => b'\\',
                        b'"' => b'"',
                        _ => return syn("bad escape"),
                    };
                    buf.push(r);
                    self.pos += 1;
                }
                Some(c) => {
                    buf.push(c);
                    self.pos += 1;
                }
            }
        }
        Ok(Value::Str(Rc::new(buf)))
    }

    fn read_atom(&mut self) -> R<Value> {
        let start = self.pos;
        while !is_delim(self.peek()) {
            self.pos += 1;
        }
        let tok = &self.src[start..self.pos];
        if tok == &b"#t"[..] {
            return Ok(Value::Bool(true));
        }
        if tok == &b"#f"[..] {
            return Ok(Value::Bool(false));
        }
        if tok[0] == b'#' {
            return syn(format!("bad token: {}", String::from_utf8_lossy(tok)));
        }
        if tok == &b"."[..] {
            return syn("unexpected .");
        }
        if is_int_token(tok) {
            return match std::str::from_utf8(tok).ok().and_then(|s| s.parse::<i64>().ok()) {
                Some(n) => Ok(Value::Int(n)),
                None => syn("integer out of range"),
            };
        }
        Ok(Value::Sym(Rc::from(String::from_utf8_lossy(tok).as_ref())))
    }
}

// ---------------------------------------------------------------------------
// Builtins table
// ---------------------------------------------------------------------------

type BuiltinFn = fn(&mut Interp, Vec<Value>) -> R<Value>;

struct Builtin {
    name: &'static str,
    min: usize,
    max: Option<usize>,
    f: BuiltinFn,
}

static BUILTINS: &[Builtin] = &[
    Builtin { name: "+", min: 0, max: None, f: bi_add },
    Builtin { name: "-", min: 1, max: None, f: bi_sub },
    Builtin { name: "*", min: 0, max: None, f: bi_mul },
    Builtin { name: "quotient", min: 2, max: Some(2), f: bi_quotient },
    Builtin { name: "remainder", min: 2, max: Some(2), f: bi_remainder },
    Builtin { name: "modulo", min: 2, max: Some(2), f: bi_modulo },
    Builtin { name: "abs", min: 1, max: Some(1), f: bi_abs },
    Builtin { name: "min", min: 1, max: None, f: bi_min },
    Builtin { name: "max", min: 1, max: None, f: bi_max },
    Builtin { name: "=", min: 2, max: None, f: bi_num_eq },
    Builtin { name: "<", min: 2, max: None, f: bi_lt },
    Builtin { name: ">", min: 2, max: None, f: bi_gt },
    Builtin { name: "<=", min: 2, max: None, f: bi_le },
    Builtin { name: ">=", min: 2, max: None, f: bi_ge },
    Builtin { name: "zero?", min: 1, max: Some(1), f: bi_zerop },
    Builtin { name: "even?", min: 1, max: Some(1), f: bi_evenp },
    Builtin { name: "odd?", min: 1, max: Some(1), f: bi_oddp },
    Builtin { name: "not", min: 1, max: Some(1), f: bi_not },
    Builtin { name: "null?", min: 1, max: Some(1), f: bi_nullp },
    Builtin { name: "pair?", min: 1, max: Some(1), f: bi_pairp },
    Builtin { name: "list?", min: 1, max: Some(1), f: bi_listp },
    Builtin { name: "number?", min: 1, max: Some(1), f: bi_numberp },
    Builtin { name: "string?", min: 1, max: Some(1), f: bi_stringp },
    Builtin { name: "symbol?", min: 1, max: Some(1), f: bi_symbolp },
    Builtin { name: "boolean?", min: 1, max: Some(1), f: bi_booleanp },
    Builtin { name: "procedure?", min: 1, max: Some(1), f: bi_procedurep },
    Builtin { name: "eq?", min: 2, max: Some(2), f: bi_eqp },
    Builtin { name: "equal?", min: 2, max: Some(2), f: bi_equalp },
    Builtin { name: "cons", min: 2, max: Some(2), f: bi_cons },
    Builtin { name: "car", min: 1, max: Some(1), f: bi_car },
    Builtin { name: "cdr", min: 1, max: Some(1), f: bi_cdr },
    Builtin { name: "cadr", min: 1, max: Some(1), f: bi_cadr },
    Builtin { name: "cddr", min: 1, max: Some(1), f: bi_cddr },
    Builtin { name: "caddr", min: 1, max: Some(1), f: bi_caddr },
    Builtin { name: "set-car!", min: 2, max: Some(2), f: bi_set_car },
    Builtin { name: "set-cdr!", min: 2, max: Some(2), f: bi_set_cdr },
    Builtin { name: "list", min: 0, max: None, f: bi_list },
    Builtin { name: "length", min: 1, max: Some(1), f: bi_length },
    Builtin { name: "append", min: 0, max: None, f: bi_append },
    Builtin { name: "reverse", min: 1, max: Some(1), f: bi_reverse },
    Builtin { name: "list-ref", min: 2, max: Some(2), f: bi_list_ref },
    Builtin { name: "list-tail", min: 2, max: Some(2), f: bi_list_tail },
    Builtin { name: "range", min: 2, max: Some(2), f: bi_range },
    Builtin { name: "assoc", min: 2, max: Some(2), f: bi_assoc },
    Builtin { name: "member", min: 2, max: Some(2), f: bi_member },
    Builtin { name: "map", min: 2, max: None, f: bi_map },
    Builtin { name: "for-each", min: 2, max: None, f: bi_for_each },
    Builtin { name: "filter", min: 2, max: Some(2), f: bi_filter },
    Builtin { name: "fold", min: 3, max: Some(3), f: bi_fold },
    Builtin { name: "foldr", min: 3, max: Some(3), f: bi_foldr },
    Builtin { name: "apply", min: 2, max: None, f: bi_apply },
    Builtin { name: "sort", min: 2, max: Some(2), f: bi_sort },
    Builtin { name: "string-length", min: 1, max: Some(1), f: bi_string_length },
    Builtin { name: "string-append", min: 0, max: None, f: bi_string_append },
    Builtin { name: "substring", min: 3, max: Some(3), f: bi_substring },
    Builtin { name: "string-ref", min: 2, max: Some(2), f: bi_string_ref },
    Builtin { name: "string=?", min: 2, max: Some(2), f: bi_string_eq },
    Builtin { name: "string<?", min: 2, max: Some(2), f: bi_string_lt },
    Builtin { name: "string-upcase", min: 1, max: Some(1), f: bi_string_upcase },
    Builtin { name: "string-downcase", min: 1, max: Some(1), f: bi_string_downcase },
    Builtin { name: "string->number", min: 1, max: Some(1), f: bi_string_to_number },
    Builtin { name: "number->string", min: 1, max: Some(1), f: bi_number_to_string },
    Builtin { name: "string->symbol", min: 1, max: Some(1), f: bi_string_to_symbol },
    Builtin { name: "symbol->string", min: 1, max: Some(1), f: bi_symbol_to_string },
    Builtin { name: "string->list", min: 1, max: Some(1), f: bi_string_to_list },
    Builtin { name: "list->string", min: 1, max: Some(1), f: bi_list_to_string },
    Builtin { name: "string-join", min: 2, max: Some(2), f: bi_string_join },
    Builtin { name: "string-split", min: 2, max: Some(2), f: bi_string_split },
    Builtin { name: "string-contains?", min: 2, max: Some(2), f: bi_string_contains },
    Builtin { name: "display", min: 1, max: Some(1), f: bi_display },
    Builtin { name: "write", min: 1, max: Some(1), f: bi_write },
    Builtin { name: "newline", min: 0, max: Some(0), f: bi_newline },
    Builtin { name: "void", min: 0, max: Some(0), f: bi_void },
    Builtin { name: "error", min: 1, max: None, f: bi_error },
];

// ---------------------------------------------------------------------------
// Interpreter
// ---------------------------------------------------------------------------

/// What a step of evaluation produces next.
enum Next {
    /// Finished with a value.
    Val(Value),
    /// Evaluate an expression in an environment (a tail position).
    Expr(Value, Rc<Env>),
    /// Apply a procedure to evaluated arguments (a tail position).
    Call(Value, Vec<Value>),
}

struct Interp {
    globals: HashMap<Rc<str>, Value>,
    global_env: Rc<Env>,
    depth: usize,
    out: Vec<u8>,
    last: Option<u8>,
}

fn is_special(s: &str) -> bool {
    matches!(
        s,
        "quote"
            | "if"
            | "define"
            | "set!"
            | "lambda"
            | "begin"
            | "let"
            | "let*"
            | "letrec"
            | "cond"
            | "and"
            | "or"
            | "when"
            | "unless"
            | "try"
    )
}

fn parse_params(v: &Value) -> Option<(Vec<Rc<str>>, Option<Rc<str>>)> {
    let mut params: Vec<Rc<str>> = Vec::new();
    let mut cur = v.clone();
    loop {
        match cur {
            Value::Nil => return Some((params, None)),
            Value::Sym(s) => {
                if params.iter().any(|p| *p == s) {
                    return None;
                }
                return Some((params, Some(s)));
            }
            Value::Pair(p) => {
                match p.car() {
                    Value::Sym(s) => {
                        if params.iter().any(|q| *q == s) {
                            return None;
                        }
                        params.push(s);
                    }
                    _ => return None,
                }
                cur = p.cdr();
            }
            _ => return None,
        }
    }
}

fn make_closure(
    form: &str,
    name: Option<Rc<str>>,
    params: &Value,
    body: &[Value],
    env: &Rc<Env>,
) -> R<Value> {
    let (params, rest) = match parse_params(params) {
        Some(x) => x,
        None => return bad(form),
    };
    Ok(Value::Closure(Rc::new(Closure {
        name,
        params,
        rest,
        body: Rc::new(body.to_vec()),
        env: env.clone(),
    })))
}

fn is_lambda_form(v: &Value) -> bool {
    match v {
        Value::Pair(p) => matches!(&p.car(), Value::Sym(s) if &**s == "lambda"),
        _ => false,
    }
}

/// Parses `((name init) ...)`; `form` names the special form for errors.
fn bindings(v: &Value, form: &str) -> R<Vec<(Rc<str>, Value)>> {
    let list = match list_vec(v) {
        Some(l) => l,
        None => return bad(form),
    };
    let mut out = Vec::with_capacity(list.len());
    for b in list {
        match list_vec(&b) {
            Some(bl) if bl.len() == 2 => match &bl[0] {
                Value::Sym(s) => out.push((s.clone(), bl[1].clone())),
                _ => return bad(form),
            },
            _ => return bad(form),
        }
    }
    Ok(out)
}

fn frame_set(env: &Env, name: Rc<str>, v: Value) {
    let mut vars = env.vars.borrow_mut();
    match vars.iter().position(|e| e.0 == name) {
        Some(i) => vars[i].1 = v,
        None => vars.push((name, v)),
    }
}

impl Interp {
    fn new() -> Interp {
        let mut globals = HashMap::new();
        for (i, b) in BUILTINS.iter().enumerate() {
            globals.insert(Rc::from(b.name), Value::Builtin(i));
        }
        Interp {
            globals,
            global_env: Rc::new(Env { vars: RefCell::new(Vec::new()), parent: None }),
            depth: 0,
            out: Vec::new(),
            last: None,
        }
    }

    fn emit(&mut self, b: &[u8]) {
        if b.is_empty() {
            return;
        }
        self.out.extend_from_slice(b);
        self.last = b.last().copied();
        if self.out.len() > (1 << 16) {
            self.flush();
        }
    }

    fn flush(&mut self) {
        let stdout = io::stdout();
        let mut lock = stdout.lock();
        let _ = lock.write_all(&self.out);
        let _ = lock.flush();
        self.out.clear();
    }

    fn report(&mut self, f: &Fail) {
        if let Some(last) = self.last {
            if last != b'\n' {
                self.emit(b"\n");
            }
        }
        let line = format!("error: {}\n", f.msg);
        self.emit(line.as_bytes());
    }

    fn lookup(&self, name: &Rc<str>, env: &Rc<Env>) -> R<Value> {
        let mut cur: &Env = env;
        loop {
            {
                let vars = cur.vars.borrow();
                for (k, v) in vars.iter() {
                    if k == name {
                        return Ok(v.clone());
                    }
                }
            }
            match &cur.parent {
                Some(p) => cur = p.as_ref(),
                None => break,
            }
        }
        match self.globals.get(name.as_ref()) {
            Some(v) => Ok(v.clone()),
            None => rt(format!("unbound variable: {}", name)),
        }
    }

    fn set_var(&mut self, name: &Rc<str>, env: &Rc<Env>, v: Value) -> R<()> {
        let mut cur: &Env = env;
        loop {
            {
                let mut vars = cur.vars.borrow_mut();
                if let Some(i) = vars.iter().position(|e| e.0 == *name) {
                    vars[i].1 = v;
                    return Ok(());
                }
            }
            match &cur.parent {
                Some(p) => cur = p.as_ref(),
                None => break,
            }
        }
        if self.globals.contains_key(name.as_ref()) {
            self.globals.insert(name.clone(), v);
            return Ok(());
        }
        rt(format!("unbound variable: {}", name))
    }

    fn define(&mut self, env: &Rc<Env>, name: Rc<str>, v: Value) {
        if env.parent.is_none() {
            self.globals.insert(name, v);
        } else {
            frame_set(env, name, v);
        }
    }

    /// Evaluates an expression (non-tail context).
    fn eval(&mut self, e: Value, env: Rc<Env>) -> R<Value> {
        self.run(Next::Expr(e, env))
    }

    /// Applies a procedure (non-tail context).
    fn apply(&mut self, f: Value, args: Vec<Value>) -> R<Value> {
        self.run(Next::Call(f, args))
    }

    /// Runs steps until a value is produced. `counted` tracks whether this
    /// invocation has already added one to the call depth; tail calls within
    /// the invocation replace the running frame and do not add to it.
    fn run(&mut self, start: Next) -> R<Value> {
        let mut counted = false;
        let r = self.run_loop(start, &mut counted);
        if counted {
            self.depth -= 1;
        }
        r
    }

    fn run_loop(&mut self, mut next: Next, counted: &mut bool) -> R<Value> {
        loop {
            next = match next {
                Next::Val(v) => return Ok(v),
                Next::Expr(e, env) => match &e {
                    Value::Sym(s) => return self.lookup(s, &env),
                    Value::Pair(_) => self.pair_next(&e, &env)?,
                    Value::Nil => return syn("empty application"),
                    _ => return Ok(e),
                },
                Next::Call(f, args) => match f {
                    Value::Builtin(i) => return self.call_builtin(i, args),
                    Value::Closure(c) => {
                        let env = self.bind_args(&c, args)?;
                        if !*counted {
                            if self.depth >= MAX_DEPTH {
                                return rt("recursion limit exceeded");
                            }
                            self.depth += 1;
                            *counted = true;
                        }
                        let body = c.body.clone();
                        let (last, init) = body.split_last().expect("lambda body is non-empty");
                        for x in init {
                            self.eval(x.clone(), env.clone())?;
                        }
                        Next::Expr(last.clone(), env)
                    }
                    other => return rt(format!("not a procedure: {}", show(&other, false))),
                },
            }
        }
    }

    fn bind_args(&self, c: &Rc<Closure>, args: Vec<Value>) -> R<Rc<Env>> {
        let n = c.params.len();
        let got = args.len();
        let ok = if c.rest.is_some() { got >= n } else { got == n };
        if !ok {
            let name = c.name.as_deref().unwrap_or("lambda");
            let exp = if c.rest.is_some() { format!("at least {}", n) } else { n.to_string() };
            return rt(format!(
                "wrong number of arguments to {}: expected {}, got {}",
                name, exp, got
            ));
        }
        let mut vars = Vec::with_capacity(n + 1);
        let mut it = args.into_iter();
        for p in &c.params {
            vars.push((p.clone(), it.next().expect("arity checked")));
        }
        if let Some(r) = &c.rest {
            let remaining: Vec<Value> = it.collect();
            vars.push((r.clone(), from_vec(remaining, Value::Nil)));
        }
        Ok(Rc::new(Env { vars: RefCell::new(vars), parent: Some(c.env.clone()) }))
    }

    fn call_builtin(&mut self, i: usize, args: Vec<Value>) -> R<Value> {
        let b = &BUILTINS[i];
        let n = args.len();
        let too_many = b.max.map_or(false, |m| n > m);
        if n < b.min || too_many {
            let exp = match b.max {
                None => format!("at least {}", b.min),
                Some(m) if m == b.min => b.min.to_string(),
                Some(m) => format!("{} to {}", b.min, m),
            };
            return rt(format!(
                "wrong number of arguments to {}: expected {}, got {}",
                b.name, exp, n
            ));
        }
        (b.f)(self, args)
    }

    /// Evaluates a sequence; the last expression is returned as a tail step.
    fn seq(&mut self, body: &[Value], env: &Rc<Env>) -> R<Next> {
        if body.is_empty() {
            return Ok(Next::Val(Value::Void));
        }
        let (last, init) = body.split_last().expect("non-empty");
        for x in init {
            self.eval(x.clone(), env.clone())?;
        }
        Ok(Next::Expr(last.clone(), env.clone()))
    }

    fn pair_next(&mut self, e: &Value, env: &Rc<Env>) -> R<Next> {
        let head = match e {
            Value::Pair(p) => p.car(),
            _ => unreachable!("pair_next called on a non-pair"),
        };
        if let Value::Sym(s) = &head {
            if is_special(s) {
                return self.special(s, e, env);
            }
        }
        let items = match list_vec(e) {
            Some(v) => v,
            None => return syn("bad application"),
        };
        let f = self.eval(items[0].clone(), env.clone())?;
        let mut args = Vec::with_capacity(items.len() - 1);
        for x in &items[1..] {
            args.push(self.eval(x.clone(), env.clone())?);
        }
        Ok(Next::Call(f, args))
    }

    fn special(&mut self, s: &str, e: &Value, env: &Rc<Env>) -> R<Next> {
        let items = match list_vec(e) {
            Some(v) => v,
            None => return bad(s),
        };
        let n = items.len();
        match s {
            "quote" => {
                if n != 2 {
                    return bad(s);
                }
                Ok(Next::Val(items[1].clone()))
            }
            "if" => {
                if n != 3 && n != 4 {
                    return bad(s);
                }
                let t = self.eval(items[1].clone(), env.clone())?;
                if truthy(&t) {
                    Ok(Next::Expr(items[2].clone(), env.clone()))
                } else if n == 4 {
                    Ok(Next::Expr(items[3].clone(), env.clone()))
                } else {
                    Ok(Next::Val(Value::Void))
                }
            }
            "define" => {
                if n < 3 {
                    return bad(s);
                }
                match &items[1] {
                    Value::Sym(name) => {
                        if n != 3 {
                            return bad(s);
                        }
                        let v = if is_lambda_form(&items[2]) {
                            let lam = match list_vec(&items[2]) {
                                Some(l) if l.len() >= 3 => l,
                                _ => return bad("lambda"),
                            };
                            make_closure("lambda", Some(name.clone()), &lam[1], &lam[2..], env)?
                        } else {
                            self.eval(items[2].clone(), env.clone())?
                        };
                        self.define(env, name.clone(), v);
                        Ok(Next::Val(Value::Void))
                    }
                    Value::Pair(p) => {
                        let name = match p.car() {
                            Value::Sym(s) => s,
                            _ => return bad(s),
                        };
                        let clo = make_closure("define", Some(name.clone()), &p.cdr(), &items[2..], env)?;
                        self.define(env, name, clo);
                        Ok(Next::Val(Value::Void))
                    }
                    _ => bad(s),
                }
            }
            "set!" => {
                if n != 3 {
                    return bad(s);
                }
                let name = match &items[1] {
                    Value::Sym(x) => x.clone(),
                    _ => return bad(s),
                };
                let v = self.eval(items[2].clone(), env.clone())?;
                self.set_var(&name, env, v)?;
                Ok(Next::Val(Value::Void))
            }
            "lambda" => {
                if n < 3 {
                    return bad(s);
                }
                Ok(Next::Val(make_closure("lambda", None, &items[1], &items[2..], env)?))
            }
            "begin" => {
                if n == 1 {
                    return Ok(Next::Val(Value::Void));
                }
                self.seq(&items[1..], env)
            }
            "let" => {
                if n < 3 {
                    return bad(s);
                }
                if let Value::Sym(name) = &items[1] {
                    // Named let.
                    if n < 4 {
                        return bad(s);
                    }
                    let binds = bindings(&items[2], s)?;
                    let mut vals = Vec::with_capacity(binds.len());
                    for (_, init) in &binds {
                        vals.push(self.eval(init.clone(), env.clone())?);
                    }
                    let frame = Rc::new(Env { vars: RefCell::new(Vec::new()), parent: Some(env.clone()) });
                    let params: Vec<Rc<str>> = binds.iter().map(|b| b.0.clone()).collect();
                    let clo = Rc::new(Closure {
                        name: Some(name.clone()),
                        params,
                        rest: None,
                        body: Rc::new(items[3..].to_vec()),
                        env: frame.clone(),
                    });
                    frame.vars.borrow_mut().push((name.clone(), Value::Closure(clo.clone())));
                    return Ok(Next::Call(Value::Closure(clo), vals));
                }
                let binds = bindings(&items[1], s)?;
                let mut vals = Vec::with_capacity(binds.len());
                for (_, init) in &binds {
                    vals.push(self.eval(init.clone(), env.clone())?);
                }
                let frame = Rc::new(Env { vars: RefCell::new(Vec::new()), parent: Some(env.clone()) });
                for ((name, _), v) in binds.into_iter().zip(vals) {
                    frame_set(&frame, name, v);
                }
                self.seq(&items[2..], &frame)
            }
            "let*" | "letrec" => {
                if n < 3 {
                    return bad(s);
                }
                let binds = bindings(&items[1], s)?;
                let frame = Rc::new(Env { vars: RefCell::new(Vec::new()), parent: Some(env.clone()) });
                for (name, init) in binds {
                    let v = self.eval(init, frame.clone())?;
                    frame_set(&frame, name, v);
                }
                self.seq(&items[2..], &frame)
            }
            "cond" => {
                for i in 1..n {
                    let cl = match list_vec(&items[i]) {
                        Some(c) if !c.is_empty() => c,
                        _ => return bad(s),
                    };
                    let is_else = matches!(&cl[0], Value::Sym(x) if &**x == "else");
                    if is_else {
                        if i != n - 1 || cl.len() < 2 {
                            return bad(s);
                        }
                        return self.seq(&cl[1..], env);
                    }
                    let t = self.eval(cl[0].clone(), env.clone())?;
                    if truthy(&t) {
                        if cl.len() == 1 {
                            return Ok(Next::Val(t));
                        }
                        return self.seq(&cl[1..], env);
                    }
                }
                Ok(Next::Val(Value::Void))
            }
            "and" => {
                if n == 1 {
                    return Ok(Next::Val(Value::Bool(true)));
                }
                for x in &items[1..n - 1] {
                    let v = self.eval(x.clone(), env.clone())?;
                    if !truthy(&v) {
                        return Ok(Next::Val(v));
                    }
                }
                Ok(Next::Expr(items[n - 1].clone(), env.clone()))
            }
            "or" => {
                if n == 1 {
                    return Ok(Next::Val(Value::Bool(false)));
                }
                for x in &items[1..n - 1] {
                    let v = self.eval(x.clone(), env.clone())?;
                    if truthy(&v) {
                        return Ok(Next::Val(v));
                    }
                }
                Ok(Next::Expr(items[n - 1].clone(), env.clone()))
            }
            "when" | "unless" => {
                if n < 3 {
                    return bad(s);
                }
                let t = self.eval(items[1].clone(), env.clone())?;
                let fire = truthy(&t) == (s == "when");
                if fire {
                    self.seq(&items[2..], env)
                } else {
                    Ok(Next::Val(Value::Void))
                }
            }
            "try" => {
                if n != 3 {
                    return bad(s);
                }
                match self.eval(items[1].clone(), env.clone()) {
                    Ok(v) => Ok(Next::Val(v)),
                    Err(f) if !f.syntax => {
                        let h = self.eval(items[2].clone(), env.clone())?;
                        let msg = Value::Str(Rc::new(f.msg.into_bytes()));
                        let r = self.apply(h, vec![msg])?;
                        Ok(Next::Val(r))
                    }
                    Err(f) => Err(f),
                }
            }
            _ => bad(s),
        }
    }
}

// ---------------------------------------------------------------------------
// Builtin helpers
// ---------------------------------------------------------------------------

fn int_of(name: &str, v: &Value) -> R<i64> {
    match v {
        Value::Int(n) => Ok(*n),
        _ => tyerr(name, "integer", v),
    }
}

fn str_of(name: &str, v: &Value) -> R<Rc<Vec<u8>>> {
    match v {
        Value::Str(s) => Ok(s.clone()),
        _ => tyerr(name, "string", v),
    }
}

fn sym_of(name: &str, v: &Value) -> R<Rc<str>> {
    match v {
        Value::Sym(s) => Ok(s.clone()),
        _ => tyerr(name, "symbol", v),
    }
}

fn pair_of(name: &str, v: &Value) -> R<Rc<Pair>> {
    match v {
        Value::Pair(p) => Ok(p.clone()),
        _ => tyerr(name, "pair", v),
    }
}

fn list_of(name: &str, v: &Value) -> R<Vec<Value>> {
    match list_vec(v) {
        Some(l) => Ok(l),
        None => tyerr(name, "list", v),
    }
}

fn proc_of(name: &str, v: &Value) -> R<Value> {
    match v {
        Value::Closure(_) | Value::Builtin(_) => Ok(v.clone()),
        _ => tyerr(name, "procedure", v),
    }
}

fn ints(name: &str, a: &[Value]) -> R<Vec<i64>> {
    a.iter().map(|v| int_of(name, v)).collect()
}

fn strs_joined_ok(name: &str, a: &[Value]) -> R<Vec<Rc<Vec<u8>>>> {
    a.iter().map(|v| str_of(name, v)).collect()
}

fn bool_v(b: bool) -> R<Value> {
    Ok(Value::Bool(b))
}

fn str_v(b: Vec<u8>) -> Value {
    Value::Str(Rc::new(b))
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

fn bi_add(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let ns = ints("+", &a)?;
    let mut acc: i64 = 0;
    for n in ns {
        acc = acc.checked_add(n).ok_or_else(ovf)?;
    }
    Ok(Value::Int(acc))
}

fn bi_sub(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let ns = ints("-", &a)?;
    if ns.len() == 1 {
        return Ok(Value::Int(ns[0].checked_neg().ok_or_else(ovf)?));
    }
    let mut acc = ns[0];
    for &n in &ns[1..] {
        acc = acc.checked_sub(n).ok_or_else(ovf)?;
    }
    Ok(Value::Int(acc))
}

fn bi_mul(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let ns = ints("*", &a)?;
    let mut acc: i64 = 1;
    for n in ns {
        acc = acc.checked_mul(n).ok_or_else(ovf)?;
    }
    Ok(Value::Int(acc))
}

fn two_ints(name: &str, a: &[Value]) -> R<(i64, i64)> {
    let x = int_of(name, &a[0])?;
    let y = int_of(name, &a[1])?;
    Ok((x, y))
}

fn bi_quotient(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let (x, y) = two_ints("quotient", &a)?;
    if y == 0 {
        return rt("division by zero");
    }
    Ok(Value::Int(x.checked_div(y).ok_or_else(ovf)?))
}

fn bi_remainder(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let (x, y) = two_ints("remainder", &a)?;
    if y == 0 {
        return rt("division by zero");
    }
    Ok(Value::Int(x.wrapping_rem(y)))
}

fn bi_modulo(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let (x, y) = two_ints("modulo", &a)?;
    if y == 0 {
        return rt("division by zero");
    }
    let mut r = x.wrapping_rem(y);
    if r != 0 && ((r < 0) != (y < 0)) {
        r += y;
    }
    Ok(Value::Int(r))
}

fn bi_abs(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let x = int_of("abs", &a[0])?;
    Ok(Value::Int(x.checked_abs().ok_or_else(ovf)?))
}

fn bi_min(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let ns = ints("min", &a)?;
    Ok(Value::Int(*ns.iter().min().expect("non-empty")))
}

fn bi_max(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let ns = ints("max", &a)?;
    Ok(Value::Int(*ns.iter().max().expect("non-empty")))
}

fn cmp_chain(name: &str, a: &[Value], f: fn(&i64, &i64) -> bool) -> R<Value> {
    let ns = ints(name, a)?;
    Ok(Value::Bool(ns.windows(2).all(|w| f(&w[0], &w[1]))))
}

fn bi_num_eq(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cmp_chain("=", &a, |x, y| x == y)
}
fn bi_lt(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cmp_chain("<", &a, |x, y| x < y)
}
fn bi_gt(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cmp_chain(">", &a, |x, y| x > y)
}
fn bi_le(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cmp_chain("<=", &a, |x, y| x <= y)
}
fn bi_ge(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cmp_chain(">=", &a, |x, y| x >= y)
}

fn bi_zerop(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(int_of("zero?", &a[0])? == 0))
}

fn bi_evenp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(int_of("even?", &a[0])?.wrapping_rem(2) == 0))
}

fn bi_oddp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(int_of("odd?", &a[0])?.wrapping_rem(2) != 0))
}

// ---------------------------------------------------------------------------
// Predicates and equality
// ---------------------------------------------------------------------------

fn bi_not(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(!truthy(&a[0])))
}
fn bi_nullp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Nil)))
}
fn bi_pairp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Pair(_))))
}
fn bi_listp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(is_proper(&a[0])))
}
fn bi_numberp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Int(_))))
}
fn bi_stringp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Str(_))))
}
fn bi_symbolp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Sym(_))))
}
fn bi_booleanp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Bool(_))))
}
fn bi_procedurep(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(matches!(a[0], Value::Closure(_) | Value::Builtin(_))))
}
fn bi_eqp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    // Strings, pairs and procedures are never eq?, as specified.
    let never = matches!(
        (&a[0], &a[1]),
        (Value::Str(_), _) | (Value::Pair(_), _) | (Value::Closure(_), _) | (Value::Builtin(_), _)
    );
    Ok(Value::Bool(!never && eqp(&a[0], &a[1])))
}
fn bi_equalp(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Bool(equalp(&a[0], &a[1])))
}

// ---------------------------------------------------------------------------
// Pairs and lists
// ---------------------------------------------------------------------------

fn bi_cons(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let mut it = a.into_iter();
    let x = it.next().expect("arity");
    let y = it.next().expect("arity");
    Ok(cons(x, y))
}

fn bi_car(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(pair_of("car", &a[0])?.car())
}

fn bi_cdr(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(pair_of("cdr", &a[0])?.cdr())
}

/// `ops` lists the steps between `c` and `r` in the name, e.g. "ad" for cadr.
fn cxr(name: &str, v: &Value, ops: &str) -> R<Value> {
    let mut cur = v.clone();
    for ch in ops.chars().rev() {
        let p = pair_of(name, &cur)?;
        cur = if ch == 'a' { p.car() } else { p.cdr() };
    }
    Ok(cur)
}

fn bi_cadr(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cxr("cadr", &a[0], "ad")
}
fn bi_cddr(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cxr("cddr", &a[0], "dd")
}
fn bi_caddr(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    cxr("caddr", &a[0], "add")
}

fn bi_set_car(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let p = pair_of("set-car!", &a[0])?;
    *p.car.borrow_mut() = a[1].clone();
    Ok(Value::Void)
}

fn bi_set_cdr(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let p = pair_of("set-cdr!", &a[0])?;
    *p.cdr.borrow_mut() = a[1].clone();
    Ok(Value::Void)
}

fn bi_list(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(from_vec(a, Value::Nil))
}

fn bi_length(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Int(list_of("length", &a[0])?.len() as i64))
}

fn bi_append(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let n = a.len();
    if n == 0 {
        return Ok(Value::Nil);
    }
    let mut parts = Vec::with_capacity(n - 1);
    for v in &a[..n - 1] {
        parts.push(list_of("append", v)?);
    }
    let mut tail = a[n - 1].clone();
    for part in parts.into_iter().rev() {
        tail = from_vec(part, tail);
    }
    Ok(tail)
}

fn bi_reverse(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let mut l = list_of("reverse", &a[0])?;
    l.reverse();
    Ok(from_vec(l, Value::Nil))
}

fn bi_list_ref(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let l = list_of("list-ref", &a[0])?;
    let i = int_of("list-ref", &a[1])?;
    if i < 0 || i as usize >= l.len() {
        return rt("list-ref: index out of range");
    }
    Ok(l[i as usize].clone())
}

fn bi_list_tail(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let l = list_of("list-tail", &a[0])?;
    let i = int_of("list-tail", &a[1])?;
    if i < 0 || i as usize > l.len() {
        return rt("list-tail: index out of range");
    }
    let mut cur = a[0].clone();
    for _ in 0..(i as usize) {
        let next = match &cur {
            Value::Pair(p) => p.cdr(),
            _ => Value::Nil,
        };
        cur = next;
    }
    Ok(cur)
}

fn bi_range(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let x = int_of("range", &a[0])?;
    let y = int_of("range", &a[1])?;
    if x >= y {
        return Ok(Value::Nil);
    }
    Ok(from_vec((x..y).map(Value::Int).collect(), Value::Nil))
}

fn bi_assoc(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let key = &a[0];
    let mut cur = a[1].clone();
    loop {
        let node = cur.clone();
        match node {
            Value::Nil => return bool_v(false),
            Value::Pair(p) => {
                let entry = p.car();
                match &entry {
                    Value::Pair(ep) => {
                        if equalp(key, &ep.car()) {
                            return Ok(entry.clone());
                        }
                    }
                    _ => return tyerr("assoc", "pair", &entry),
                }
                cur = p.cdr();
            }
            _ => return tyerr("assoc", "list", &a[1]),
        }
    }
}

fn bi_member(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let key = &a[0];
    let mut cur = a[1].clone();
    loop {
        let node = cur.clone();
        match node {
            Value::Nil => return bool_v(false),
            Value::Pair(p) => {
                if equalp(key, &p.car()) {
                    return Ok(cur);
                }
                cur = p.cdr();
            }
            _ => return tyerr("member", "list", &a[1]),
        }
    }
}

// ---------------------------------------------------------------------------
// Higher-order builtins
// ---------------------------------------------------------------------------

fn bi_map(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("map", &a[0])?;
    let lists: Vec<Vec<Value>> = a[1..].iter().map(|v| list_of("map", v)).collect::<R<_>>()?;
    let n = lists.iter().map(|l| l.len()).min().unwrap_or(0);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let args: Vec<Value> = lists.iter().map(|l| l[i].clone()).collect();
        out.push(it.apply(f.clone(), args)?);
    }
    Ok(from_vec(out, Value::Nil))
}

fn bi_for_each(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("for-each", &a[0])?;
    let lists: Vec<Vec<Value>> = a[1..].iter().map(|v| list_of("for-each", v)).collect::<R<_>>()?;
    let n = lists.iter().map(|l| l.len()).min().unwrap_or(0);
    for i in 0..n {
        let args: Vec<Value> = lists.iter().map(|l| l[i].clone()).collect();
        it.apply(f.clone(), args)?;
    }
    Ok(Value::Void)
}

fn bi_filter(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("filter", &a[0])?;
    let l = list_of("filter", &a[1])?;
    let mut out = Vec::new();
    for x in l {
        let r = it.apply(f.clone(), vec![x.clone()])?;
        if truthy(&r) {
            out.push(x);
        }
    }
    Ok(from_vec(out, Value::Nil))
}

fn bi_fold(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("fold", &a[0])?;
    let l = list_of("fold", &a[2])?;
    let mut acc = a[1].clone();
    for x in l {
        acc = it.apply(f.clone(), vec![acc, x])?;
    }
    Ok(acc)
}

fn bi_foldr(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("foldr", &a[0])?;
    let l = list_of("foldr", &a[2])?;
    let mut acc = a[1].clone();
    for x in l.into_iter().rev() {
        acc = it.apply(f.clone(), vec![x, acc])?;
    }
    Ok(acc)
}

fn bi_apply(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let f = proc_of("apply", &a[0])?;
    let n = a.len();
    let last = list_of("apply", &a[n - 1])?;
    let mut args: Vec<Value> = a[1..n - 1].to_vec();
    args.extend(last);
    it.apply(f, args)
}

/// Stable merge sort; `less` is called as (less later earlier).
fn msort(it: &mut Interp, v: &[Value], less: &Value) -> R<Vec<Value>> {
    if v.len() <= 1 {
        return Ok(v.to_vec());
    }
    let mid = v.len() / 2;
    let l = msort(it, &v[..mid], less)?;
    let r = msort(it, &v[mid..], less)?;
    let mut out = Vec::with_capacity(v.len());
    let (mut i, mut j) = (0, 0);
    while i < l.len() && j < r.len() {
        let t = it.apply(less.clone(), vec![r[j].clone(), l[i].clone()])?;
        if truthy(&t) {
            out.push(r[j].clone());
            j += 1;
        } else {
            out.push(l[i].clone());
            i += 1;
        }
    }
    out.extend_from_slice(&l[i..]);
    out.extend_from_slice(&r[j..]);
    Ok(out)
}

fn bi_sort(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let less = proc_of("sort", &a[1])?;
    let l = list_of("sort", &a[0])?;
    let sorted = msort(it, &l, &less)?;
    Ok(from_vec(sorted, Value::Nil))
}

// ---------------------------------------------------------------------------
// Strings and symbols
// ---------------------------------------------------------------------------

fn bi_string_length(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(Value::Int(str_of("string-length", &a[0])?.len() as i64))
}

fn bi_string_append(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let parts = strs_joined_ok("string-append", &a)?;
    let mut out = Vec::new();
    for p in parts {
        out.extend_from_slice(p.as_slice());
    }
    Ok(str_v(out))
}

fn bi_substring(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("substring", &a[0])?;
    let st = int_of("substring", &a[1])?;
    let en = int_of("substring", &a[2])?;
    if st < 0 || en < st || en as usize > s.len() {
        return rt("substring: index out of range");
    }
    Ok(str_v(s[st as usize..en as usize].to_vec()))
}

fn bi_string_ref(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string-ref", &a[0])?;
    let i = int_of("string-ref", &a[1])?;
    if i < 0 || i as usize >= s.len() {
        return rt("string-ref: index out of range");
    }
    Ok(str_v(vec![s[i as usize]]))
}

fn bi_string_eq(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let x = str_of("string=?", &a[0])?;
    let y = str_of("string=?", &a[1])?;
    bool_v(x == y)
}

fn bi_string_lt(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let x = str_of("string<?", &a[0])?;
    let y = str_of("string<?", &a[1])?;
    bool_v(x < y)
}

fn bi_string_upcase(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(str_v(str_of("string-upcase", &a[0])?.to_ascii_uppercase()))
}

fn bi_string_downcase(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    Ok(str_v(str_of("string-downcase", &a[0])?.to_ascii_lowercase()))
}

fn bi_string_to_number(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string->number", &a[0])?;
    if !is_int_token(&s) {
        return bool_v(false);
    }
    match std::str::from_utf8(&s).ok().and_then(|t| t.parse::<i64>().ok()) {
        Some(n) => Ok(Value::Int(n)),
        None => bool_v(false),
    }
}

fn bi_number_to_string(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let n = int_of("number->string", &a[0])?;
    Ok(str_v(n.to_string().into_bytes()))
}

fn bi_string_to_symbol(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string->symbol", &a[0])?;
    Ok(Value::Sym(Rc::from(String::from_utf8_lossy(&s).as_ref())))
}

fn bi_symbol_to_string(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = sym_of("symbol->string", &a[0])?;
    Ok(str_v(s.as_bytes().to_vec()))
}

fn bi_string_to_list(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string->list", &a[0])?;
    let items: Vec<Value> = s.iter().map(|&c| str_v(vec![c])).collect();
    Ok(from_vec(items, Value::Nil))
}

fn bi_list_to_string(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let items = list_of("list->string", &a[0])?;
    let mut out = Vec::new();
    for x in &items {
        out.extend_from_slice(str_of("list->string", x)?.as_slice());
    }
    Ok(str_v(out))
}

fn bi_string_join(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let items = list_of("string-join", &a[0])?;
    let sep = str_of("string-join", &a[1])?;
    let mut out = Vec::new();
    for (i, x) in items.iter().enumerate() {
        if i > 0 {
            out.extend_from_slice(sep.as_slice());
        }
        out.extend_from_slice(str_of("string-join", x)?.as_slice());
    }
    Ok(str_v(out))
}

fn bi_string_split(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string-split", &a[0])?;
    let sep = str_of("string-split", &a[1])?;
    if sep.len() != 1 {
        return rt("string-split: separator must be one character");
    }
    let c = sep[0];
    let parts: Vec<Value> = s.split(|b| *b == c).map(|p| str_v(p.to_vec())).collect();
    Ok(from_vec(parts, Value::Nil))
}

fn bi_string_contains(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let s = str_of("string-contains?", &a[0])?;
    let sub = str_of("string-contains?", &a[1])?;
    if sub.is_empty() {
        return bool_v(true);
    }
    bool_v(s.windows(sub.len()).any(|w| w == sub.as_slice()))
}

// ---------------------------------------------------------------------------
// Output and misc
// ---------------------------------------------------------------------------

fn bi_display(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let mut b = Vec::new();
    render(&a[0], true, &mut b);
    it.emit(&b);
    Ok(Value::Void)
}

fn bi_write(it: &mut Interp, a: Vec<Value>) -> R<Value> {
    let mut b = Vec::new();
    render(&a[0], false, &mut b);
    it.emit(&b);
    Ok(Value::Void)
}

fn bi_newline(it: &mut Interp, _: Vec<Value>) -> R<Value> {
    it.emit(b"\n");
    Ok(Value::Void)
}

fn bi_void(_: &mut Interp, _: Vec<Value>) -> R<Value> {
    Ok(Value::Void)
}

fn bi_error(_: &mut Interp, a: Vec<Value>) -> R<Value> {
    let msg = match &a[0] {
        Value::Str(s) => String::from_utf8_lossy(s).into_owned(),
        v => return tyerr("error", "string", v),
    };
    let mut m = msg;
    for v in &a[1..] {
        m.push(' ');
        m.push_str(&show(v, false));
    }
    rt(m)
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

fn run_program(src: Vec<u8>) {
    let mut it = Interp::new();
    let mut rd = Reader { src: &src, pos: 0 };
    loop {
        rd.skip_ws();
        if rd.at_eof() {
            break;
        }
        let result = rd.read().and_then(|datum| {
            let env = it.global_env.clone();
            it.eval(datum, env).map(|_| ())
        });
        if let Err(f) = result {
            it.report(&f);
            break;
        }
    }
    it.flush();
}

fn main() {
    let mut src = Vec::new();
    let _ = io::stdin().read_to_end(&mut src);
    let child = std::thread::Builder::new()
        .stack_size(STACK_SIZE)
        .spawn(move || run_program(src))
        .expect("spawn interpreter thread");
    let _ = child.join();
}
