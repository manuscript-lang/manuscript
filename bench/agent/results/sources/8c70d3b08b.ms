from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/math.ms" import BigInt, from_int, floor, sqrt, pow

# ---------- Values, expressions and cells ----------

type Value:
    case Empty
    case Number(n: Float)
    case Text(s: String)
    case Boolean(b: Bool)
    case Fault(code: String)

# Rows are 1..999 and columns 0..25; an invalid reference has row -1.
type Expr:
    case Lit(v: Value)
    case Ref(r: Int, c: Int)
    case Span(r1: Int, c1: Int, r2: Int, c2: Int)
    case Unary(op: String, operand: Expr)
    case Binary(op: String, left: Expr, right: Expr)
    case Call(name: String, args: List[Expr])

type Tok:
    kind: String
    text: String

type RefParts:
    valid: Bool
    col: Int
    row: Int
    abs_col: Bool
    abs_row: Bool

type Sheet:
    kind: List[Int]
    raw: List[String]
    vals: List[Value]
    exprs: List[Expr]
    precs: List[List[Int]]
    deps: Map[Int, Set[Int]]
    mark: List[Int]
    tidx: List[Int]
    tlow: List[Int]
    tseen: List[Int]
    ton: List[Bool]
    epoch: Int
    evals: Int

type Acc:
    total: Float
    prod: Float
    lo: Float
    hi: Float
    count: Int
    want_list: Bool
    xs: List[Float]

type Item:
    v: Value
    ranged: Bool

type Parser:
    toks: List[Tok]
    pos: Int
    bad: Bool

type Tarjan:
    stack: List[Int]
    counter: Int
    ep: Int

# ---------- Small helpers ----------

def is_ws(c: String) -> Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

def is_digit(c: String) -> Bool:
    return c >= "0" and c <= "9"

def is_letter(c: String) -> Bool:
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

def ident_char(c: String) -> Bool:
    return is_letter(c) or is_digit(c) or c == "_" or c == "."

def span(cs: List[String], i: Int, j: Int) -> String:
    var out = ""
    for k in i..j:
        out += cs[k]
    return out

def rtrim(s: String) -> String:
    let cs = s.chars()
    var j = cs.length()
    while j > 0 and is_ws(cs[j - 1]):
        j -= 1
    return span(cs, 0, j)

def letter(c: Int) -> String:
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".slice(c, c + 1).get()

def key_name(key: Int) -> String:
    let r = key / 26
    return letter(key - r * 26) + r.to_string()

def least(a: Int, b: Int) -> Int:
    if a < b:
        return a
    return b

def greatest(a: Int, b: Int) -> Int:
    if a > b:
        return a
    return b

def has_char(s: String, ch: String) -> Bool:
    for c in s.chars():
        if c == ch:
            return True
    return False

def is_fault(v: Value) -> Bool:
    match v:
        case Fault(_code):
            return True
        case _:
            return False
    return False

def is_empty_v(v: Value) -> Bool:
    match v:
        case Empty:
            return True
        case _:
            return False
    return False

def is_number(v: Value) -> Bool:
    match v:
        case Number(_n):
            return True
        case _:
            return False
    return False

def is_text(v: Value) -> Bool:
    match v:
        case Text(_s):
            return True
        case _:
            return False
    return False

def fnum(v: Value) -> Float:
    match v:
        case Number(n):
            return n
        case _:
            return 0.0
    return 0.0

def text_of(v: Value) -> String:
    match v:
        case Text(s):
            return s
        case _:
            return ""
    return ""

def truth(v: Value) -> Bool:
    match v:
        case Boolean(b):
            return b
        case _:
            return False
    return False

def finite(x: Float) -> Value:
    if x.is_finite():
        return Number(x)
    return Fault("#NUM!")

def type_tag(v: Value) -> Int:
    match v:
        case Empty:
            return 0
        case Number(_n):
            return 1
        case Text(_s):
            return 2
        case Boolean(_b):
            return 3
        case _:
            return 4
    return 4

# ---------- Numbers: grammar, parsing and display ----------

# Returns the number grammar text normalized for parse_float, or "" when the text is not a number.
def normalize_number(s: String) -> String:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var sign = ""
    if i < n and (cs[i] == "+" or cs[i] == "-"):
        if cs[i] == "-":
            sign = "-"
        i += 1
    var ip = ""
    while i < n and is_digit(cs[i]):
        ip += cs[i]
        i += 1
    var fp = ""
    if i < n and cs[i] == ".":
        i += 1
        while i < n and is_digit(cs[i]):
            fp += cs[i]
            i += 1
    if ip == "" and fp == "":
        return ""
    var ex = ""
    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1
        var esign = ""
        if i < n and (cs[i] == "+" or cs[i] == "-"):
            if cs[i] == "-":
                esign = "-"
            i += 1
        var ed = ""
        while i < n and is_digit(cs[i]):
            ed += cs[i]
            i += 1
        if ed == "":
            return ""
        ex = "e" + esign + ed
    if i != n:
        return ""
    var ipart = ip
    if ipart == "":
        ipart = "0"
    var fpart = fp
    if fpart == "":
        fpart = "0"
    return sign + ipart + "." + fpart + ex

# The finite number a text denotes under the number grammar, or none.
def number_text(s: String) -> Optional[Float]:
    let norm = normalize_number(s)
    if norm == "":
        return none
    if let x = norm.parse_float():
        if x.is_finite():
            return some(x)
    return none

def last_char(s: String) -> String:
    return s.slice(s.length() - 1, s.length()).get()

# Display text of a finite number: 10 fractional digits, rounded half away from zero, trailing zeros dropped.
def fmt_num(x: Float) -> String:
    if x == 0.0:
        return "0"
    let neg = x < 0.0
    var m = x.abs()
    var k = 0
    while m >= 9007199254740992.0:
        m = m / 2.0
        k += 1
    while m < 4503599627370496.0:
        m = m * 2.0
        k -= 1
    # x is exactly mant * 2^k with mant an integer in [2^52, 2^53).
    let mant = m.truncate_to_int().get(0)
    let scaled = from_int(mant) * from_int(10000000000)
    var scaled_n = scaled
    if k >= 0:
        scaled_n = scaled * from_int(2).pow(k).get()
    else:
        let d = from_int(2).pow(0 - k).get()
        var q = scaled / d
        let r = scaled % d
        if r * from_int(2) >= d:
            q = q + from_int(1)
        scaled_n = q
    var s = scaled_n.to_string_radix(10)
    while s.length() < 11:
        s = "0" + s
    let split = s.length() - 10
    let ip = s.slice(0, split).get()
    var fp = s.slice(split, s.length()).get()
    while fp.length() > 0 and last_char(fp) == "0":
        fp = fp.slice(0, fp.length() - 1).get()
    var out = ip.clone()
    if fp != "":
        out = ip + "." + fp
    if neg and out != "0":
        out = "-" + out
    return out

# Display text of any value (empty is the empty string, errors are their codes).
def show(v: Value) -> String:
    match v:
        case Empty:
            return ""
        case Number(n):
            return fmt_num(n)
        case Text(s):
            return s
        case Boolean(b):
            if b:
                return "TRUE"
            return "FALSE"
        case Fault(code):
            return code
    return ""

# Number coercion for arithmetic and numeric arguments.
def to_num(v: Value) -> Value:
    match v:
        case Number(_n):
            return v
        case Empty:
            return Number(0.0)
        case Boolean(b):
            if b:
                return Number(1.0)
            return Number(0.0)
        case Text(s):
            let t = s.trim()
            if normalize_number(t) == "":
                return Fault("#VALUE!")
            if let x = number_text(t):
                return Number(x)
            return Fault("#NUM!")
        case Fault(code):
            return Fault(code.clone())
    return v

def to_bool(v: Value) -> Value:
    match v:
        case Empty:
            return Boolean(False)
        case Number(n):
            return Boolean(n != 0.0)
        case Boolean(_b):
            return v
        case Text(s):
            let up = s.upper()
            if up == "TRUE":
                return Boolean(True)
            if up == "FALSE":
                return Boolean(False)
            return Fault("#VALUE!")
        case Fault(code):
            return Fault(code.clone())
    return v

# ---------- Formula lexer and parser ----------

def ref_end(cs: List[String], start: Int) -> Int:
    let n = cs.length()
    var i = start
    if i < n and cs[i] == "$":
        i += 1
    let letters = i
    while i < n and is_letter(cs[i]):
        i += 1
    if i == letters:
        return -1
    if i < n and cs[i] == "$":
        i += 1
    let digits = i
    while i < n and is_digit(cs[i]):
        i += 1
    if i == digits:
        return -1
    return i

# A reference word ending at `end` must not run on into more identifier text, a call or a `$`.
def ref_ok(cs: List[String], end: Int) -> Bool:
    if end >= cs.length():
        return True
    let c = cs[end]
    return not (ident_char(c) or c == "(" or c == "$")

def is_symbol(s: String) -> Bool:
    return s == "+" or s == "-" or s == "*" or s == "/" or s == "^" or s == "&" or s == "=" or s == "<" or s == ">" or s == "<>" or s == "<=" or s == ">=" or s == "(" or s == ")" or s == ","

def lex(src: String) -> Optional[List[Tok]]:
    let cs = src.chars()
    let n = cs.length()
    var toks = List[Tok]()
    var i = 0
    while i < n:
        let c = cs[i]
        if is_ws(c):
            var j = i
            while j < n and is_ws(cs[j]):
                j += 1
            toks.append(Tok(kind: "space", text: span(cs, i, j)))
            i = j
        elif c == "\"":
            var j = i + 1
            var closed = False
            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        j += 2
                    else:
                        closed = True
                else:
                    j += 1
            if not closed:
                return none
            toks.append(Tok(kind: "str", text: span(cs, i, j + 1)))
            i = j + 1
        elif is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
            var j = i
            while j < n and is_digit(cs[j]):
                j += 1
            if j < n and cs[j] == ".":
                j += 1
                while j < n and is_digit(cs[j]):
                    j += 1
            if j < n and (cs[j] == "e" or cs[j] == "E"):
                var k = j + 1
                if k < n and (cs[k] == "+" or cs[k] == "-"):
                    k += 1
                if k < n and is_digit(cs[k]):
                    while k < n and is_digit(cs[k]):
                        k += 1
                    j = k
            toks.append(Tok(kind: "num", text: span(cs, i, j)))
            i = j
        elif is_letter(c) or c == "_" or c == "$":
            let e = ref_end(cs, i)
            let is_ref = e >= 0 and ref_ok(cs, e)
            if is_ref and e < n and cs[e] == ":":
                let e2 = ref_end(cs, e + 1)
                if e2 < 0 or not ref_ok(cs, e2):
                    return none
                toks.append(Tok(kind: "range", text: span(cs, i, e2)))
                i = e2
            elif is_ref:
                toks.append(Tok(kind: "ref", text: span(cs, i, e)))
                i = e
            elif c == "$":
                return none
            else:
                var j = i
                while j < n and ident_char(cs[j]):
                    j += 1
                toks.append(Tok(kind: "word", text: span(cs, i, j)))
                i = j
        elif c == "#":
            if i + 5 <= n and span(cs, i, i + 5) == "#REF!":
                toks.append(Tok(kind: "err", text: "#REF!"))
                i += 5
            else:
                return none
        else:
            var sym = c.clone()
            if i + 1 < n:
                let two = c + cs[i + 1]
                if two == "<>" or two == "<=" or two == ">=":
                    sym = two
            if not is_symbol(sym):
                return none
            toks.append(Tok(kind: "sym", text: sym.clone()))
            i += sym.length()
    return some(toks)

def ref_parts(text: String) -> RefParts:
    let cs = text.chars()
    let n = cs.length()
    var i = 0
    var ac = False
    var ar = False
    if i < n and cs[i] == "$":
        ac = True
        i += 1
    let ls = i
    while i < n and is_letter(cs[i]):
        i += 1
    let nl = i - ls
    if i < n and cs[i] == "$":
        ar = True
        i += 1
    let ds = i
    while i < n and is_digit(cs[i]):
        i += 1
    let nd = i - ds
    if i != n or nl != 1 or nd < 1 or nd > 3:
        return RefParts(valid: False, col: -1, row: -1, abs_col: ac, abs_row: ar)
    if cs[ds] == "0":
        return RefParts(valid: False, col: -1, row: -1, abs_col: ac, abs_row: ar)
    let code = cs[ls].scalar_at(0)
    let col = code - 65
    var c = col
    if code >= 97:
        c = code - 97
    let row = span(cs, ds, n).parse_int().get(0)
    if row < 1 or row > 999:
        return RefParts(valid: False, col: -1, row: -1, abs_col: ac, abs_row: ar)
    return RefParts(valid: True, col: c, row: row, abs_col: ac, abs_row: ar)

impl Parser:
    def peek_kind() -> String:
        if self.pos < self.toks.length():
            return self.toks[self.pos].kind.clone()
        return "end"

    def peek_text() -> String:
        if self.pos < self.toks.length():
            return self.toks[self.pos].text.clone()
        return ""

    def is_sym(s: String) -> Bool:
        return self.peek_kind() == "sym" and self.peek_text() == s

    def is_cmp() -> Bool:
        let t = self.peek_text()
        return self.peek_kind() == "sym" and (t == "=" or t == "<>" or t == "<" or t == "<=" or t == ">" or t == ">=")

    var def expr() -> Expr:
        var left = self.concat()
        while self.is_cmp():
            let op = self.peek_text()
            self.pos += 1
            left = Binary(op.clone(), left, self.concat())
        return left

    var def concat() -> Expr:
        var left = self.additive()
        while self.is_sym("&"):
            self.pos += 1
            left = Binary("&", left, self.additive())
        return left

    var def additive() -> Expr:
        var left = self.term()
        while self.is_sym("+") or self.is_sym("-"):
            let op = self.peek_text()
            self.pos += 1
            left = Binary(op.clone(), left, self.term())
        return left

    var def term() -> Expr:
        var left = self.unary()
        while self.is_sym("*") or self.is_sym("/"):
            let op = self.peek_text()
            self.pos += 1
            left = Binary(op.clone(), left, self.unary())
        return left

    var def unary() -> Expr:
        if self.is_sym("+") or self.is_sym("-"):
            let op = self.peek_text()
            self.pos += 1
            return Unary(op.clone(), self.unary())
        return self.power()

    var def power() -> Expr:
        let base = self.primary()
        if self.is_sym("^"):
            self.pos += 1
            return Binary("^", base, self.power_operand())
        return base

    var def power_operand() -> Expr:
        if self.is_sym("+") or self.is_sym("-"):
            let op = self.peek_text()
            self.pos += 1
            return Unary(op.clone(), self.power_operand())
        return self.power()

    var def primary() -> Expr:
        let k = self.peek_kind()
        let t = self.peek_text()
        if k == "num":
            self.pos += 1
            if let x = number_text(t):
                return Lit(Number(x))
            return Lit(Fault("#NUM!"))
        if k == "str":
            self.pos += 1
            return Lit(Text(t.slice(1, t.length() - 1).get().replace("\"\"", "\"")))
        if k == "err":
            self.pos += 1
            return Lit(Fault("#REF!"))
        if k == "ref":
            self.pos += 1
            let p = ref_parts(t)
            if p.valid:
                return Ref(p.row, p.col)
            return Ref(-1, -1)
        if k == "range":
            self.pos += 1
            let parts = t.split(":")
            let a = ref_parts(parts[0])
            let b = ref_parts(parts[1])
            if a.valid and b.valid:
                return Span(a.row, a.col, b.row, b.col)
            return Span(-1, -1, -1, -1)
        if k == "word":
            self.pos += 1
            if self.is_sym("("):
                self.pos += 1
                var args = List[Expr]()
                if self.is_sym(")"):
                    self.pos += 1
                    return Call(t.upper(), args)
                var more = True
                while more:
                    args.append(self.expr())
                    if self.is_sym(","):
                        self.pos += 1
                    elif self.is_sym(")"):
                        self.pos += 1
                        more = False
                    else:
                        self.bad = True
                        more = False
                return Call(t.upper(), args)
            let up = t.upper()
            if up == "TRUE":
                return Lit(Boolean(True))
            if up == "FALSE":
                return Lit(Boolean(False))
            return Lit(Fault("#NAME?"))
        if self.is_sym("("):
            self.pos += 1
            let e = self.expr()
            if self.is_sym(")"):
                self.pos += 1
            else:
                self.bad = True
            return e
        self.bad = True
        return Lit(Empty)

def parse_formula(src: String) -> Optional[Expr]:
    if let toks = lex(src):
        var sig = List[Tok]()
        for t in toks:
            if t.kind != "space":
                sig.append(t)
        var p = Parser(toks: sig.clone(), pos: 0, bad: False)
        let e = p.expr()
        if p.bad or p.pos != sig.length():
            return none
        return some(e)
    return none

# ---------- Ranges and reference collection ----------

def rect_keys(r1: Int, c1: Int, r2: Int, c2: Int) -> List[Int]:
    var out = List[Int]()
    let lr = least(r1, r2)
    let hr = greatest(r1, r2)
    let lc = least(c1, c2)
    let hc = greatest(c1, c2)
    for r in lr..hr + 1:
        for c in lc..hc + 1:
            out.append(r * 26 + c)
    return out

def is_span(e: Expr) -> Bool:
    match e:
        case Span(_r1, _c1, _r2, _c2):
            return True
        case _:
            return False
    return False

def corners(e: Expr) -> List[Int]:
    match e:
        case Span(r1, c1, r2, c2):
            return [r1, c1, r2, c2]
        case _:
            return []
    return []

def collect_refs(e: Expr, var out: Set[Int]) -> Unit:
    match e:
        case Ref(r, c):
            if c >= 0:
                out.add(r * 26 + c)
        case Span(r1, c1, r2, c2):
            if c1 >= 0 and c2 >= 0:
                for key in rect_keys(r1, c1, r2, c2):
                    out.add(key)
        case Unary(_op, x):
            collect_refs(x, var out)
        case Binary(_op, l, r):
            collect_refs(l, var out)
            collect_refs(r, var out)
        case Call(name, args):
            if name != "ROW" and name != "COLUMN":
                for a in args:
                    collect_refs(a, var out)
        case _:
            return

def precedents_of(e: Expr) -> List[Int]:
    var s = Set[Int]()
    collect_refs(e, var s)
    return s.values().sorted()

# ---------- Cell access ----------

def key_count() -> Int:
    return 26000

def new_sheet() -> Sheet:
    var kind = List[Int]()
    var raw = List[String]()
    var vals = List[Value]()
    var exprs = List[Expr]()
    var precs = List[List[Int]]()
    var mark = List[Int]()
    var tidx = List[Int]()
    var tlow = List[Int]()
    var tseen = List[Int]()
    var ton = List[Bool]()
    for i in 0..key_count():
        kind.append(0)
        raw.append("")
        vals.append(Empty)
        exprs.append(Lit(Empty))
        precs.append(List[Int]())
        mark.append(0)
        tidx.append(0)
        tlow.append(0)
        tseen.append(0)
        ton.append(False)
    return Sheet(kind: kind, raw: raw, vals: vals, exprs: exprs, precs: precs, deps: Map[Int, Set[Int]](), mark: mark, tidx: tidx, tlow: tlow, tseen: tseen, ton: ton, epoch: 0, evals: 0)

def value_at(sh: Sheet, key: Int) -> Value:
    return sh.vals[key].clone()

def precs_of(sh: Sheet, key: Int) -> List[Int]:
    return sh.precs[key].clone()

def is_formula(sh: Sheet, key: Int) -> Bool:
    return sh.kind[key] >= 2



def add_dep(var sh: Sheet, p: Int, f: Int) -> Unit:
    if var s = sh.deps.get(p):
        s.add(f)
    else:
        var s2 = Set[Int]()
        s2.add(f)
        sh.deps[p] = s2

def remove_dep(var sh: Sheet, p: Int, f: Int) -> Unit:
    if var s = sh.deps.get(p):
        s.remove(f)

def dependents_direct(sh: Sheet, key: Int) -> List[Int]:
    if let s = sh.deps.get(key):
        return s.values()
    return []

# ---------- Evaluation ----------

def binary(sh: Sheet, op: String, l: Expr, r: Expr) -> Value:
    let a = ev(sh, l)
    let b = ev(sh, r)
    if op == "&":
        if is_fault(a):
            return a
        if is_fault(b):
            return b
        return Text(show(a) + show(b))
    if is_cmp_op(op):
        return compare(op, a, b)
    let x = to_num(a)
    if is_fault(x):
        return x
    let y = to_num(b)
    if is_fault(y):
        return y
    let p = fnum(x)
    let q = fnum(y)
    if op == "+":
        return finite(p + q)
    if op == "-":
        return finite(p - q)
    if op == "*":
        return finite(p * q)
    if op == "/":
        if q == 0.0:
            return Fault("#DIV/0!")
        return finite(p / q)
    return finite(pow(p, q))

def is_cmp_op(op: String) -> Bool:
    return op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">="

def zero_like(v: Value) -> Value:
    match v:
        case Text(_s):
            return Text("")
        case Boolean(_b):
            return Boolean(False)
        case _:
            return Number(0.0)
    return Number(0.0)

def rank(v: Value) -> Int:
    match v:
        case Number(_n):
            return 0
        case Text(_s):
            return 1
        case Boolean(_b):
            return 2
        case _:
            return 0
    return 0

def compare(op: String, a0: Value, b0: Value) -> Value:
    if is_fault(a0):
        return a0
    if is_fault(b0):
        return b0
    var a = a0
    var b = b0
    if is_empty_v(a):
        a = zero_like(b)
    if is_empty_v(b):
        b = zero_like(a)
    var c = 0
    if rank(a) != rank(b):
        if rank(a) < rank(b):
            c = -1
        else:
            c = 1
    else:
        match a:
            case Number(x):
                let y = fnum(b)
                if x < y:
                    c = -1
                elif x > y:
                    c = 1
            case Text(s):
                c = s.compare(text_of(b))
            case Boolean(p):
                var pi = 0
                if p:
                    pi = 1
                var qi = 0
                if truth(b):
                    qi = 1
                c = pi - qi
            case _:
                c = 0
    if op == "=":
        return Boolean(c == 0)
    if op == "<>":
        return Boolean(c != 0)
    if op == "<":
        return Boolean(c < 0)
    if op == "<=":
        return Boolean(c <= 0)
    if op == ">":
        return Boolean(c > 0)
    return Boolean(c >= 0)

def ev(sh: Sheet, e: Expr) -> Value:
    match e:
        case Lit(v):
            return v
        case Ref(r, c):
            if c < 0:
                return Fault("#REF!")
            return value_at(sh, r * 26 + c)
        case Span(_r1, _c1, _r2, _c2):
            return Fault("#VALUE!")
        case Unary(op, x):
            let a = to_num(ev(sh, x))
            if is_fault(a):
                return a
            if op == "-":
                return Number(0.0 - fnum(a))
            return a
        case Binary(op, l, r):
            return binary(sh, op, l, r)
        case Call(name, args):
            return call(sh, name, args)
    return Fault("#VALUE!")

def collect(sh: Sheet, args: List[Expr]) -> List[Item]:
    var items = List[Item]()
    for a in args:
        match a:
            case Span(r1, c1, r2, c2):
                if c1 < 0 or c2 < 0:
                    items.append(Item(v: Fault("#REF!"), ranged: False))
                else:
                    for key in rect_keys(r1, c1, r2, c2):
                        items.append(Item(v: value_at(sh, key), ranged: True))
            case _:
                items.append(Item(v: ev(sh, a), ranged: False))
    return items

# The first error among the items, in item order; a direct item that cannot be a number is #VALUE!.
def scan_fault(items: List[Item]) -> Value:
    for it in items:
        if it.ranged:
            if is_fault(it.v):
                return it.v.clone()
        else:
            let t = to_num(it.v.clone())
            if is_fault(t):
                return t.clone()
    return Empty

def contributes(it: Item) -> Bool:
    if it.ranged:
        return is_number(it.v)
    return True

def nums(items: List[Item]) -> List[Float]:
    var out = List[Float]()
    for it in items:
        if contributes(it):
            out.append(fnum(to_num(it.v.clone())))
    return out

def total(xs: List[Float]) -> Float:
    var s = 0.0
    for x in xs:
        s += x
    return s

def product(xs: List[Float]) -> Float:
    var s = 1.0
    for x in xs:
        s = s * x
    return s

def agg_item(var acc: Acc, v: Value, ranged: Bool) -> Value:
    if is_fault(v):
        return v
    if ranged and not is_number(v):
        return Empty
    let t = to_num(v)
    if is_fault(t):
        return t
    let x = fnum(t)
    if acc.count == 0 or x < acc.lo:
        acc.lo = x
    if acc.count == 0 or x > acc.hi:
        acc.hi = x
    acc.count += 1
    acc.total += x
    acc.prod = acc.prod * x
    if acc.want_list:
        acc.xs.append(x)
    return Empty

def counts_item(v: Value, counta: Bool) -> Bool:
    if counta:
        return not is_empty_v(v)
    return is_number(v)

def count_items(sh: Sheet, counta: Bool, args: List[Expr]) -> Value:
    var k = 0
    for a in args:
        if is_span(a):
            let rc = corners(a)
            if rc[1] < 0 or rc[3] < 0:
                if counta:
                    k += 1
            else:
                let r1 = least(rc[0], rc[2])
                let r2 = greatest(rc[0], rc[2])
                let c1 = least(rc[1], rc[3])
                let c2 = greatest(rc[1], rc[3])
                for r in r1..r2 + 1:
                    for c in c1..c2 + 1:
                        if counts_item(sh.vals[r * 26 + c], counta):
                            k += 1
        elif counts_item(ev(sh, a), counta):
            k += 1
    return Number(k.to_float())

def aggregate(sh: Sheet, name: String, args: List[Expr]) -> Value:
    if args.length() == 0:
        return Fault("#VALUE!")
    if name == "COUNT" or name == "COUNTA":
        return count_items(sh, name == "COUNTA", args)
    var acc = Acc(total: 0.0, prod: 1.0, lo: 0.0, hi: 0.0, count: 0, want_list: name == "MEDIAN", xs: List[Float]())
    for a in args:
        if is_span(a):
            let rc = corners(a)
            if rc[1] < 0 or rc[3] < 0:
                return Fault("#REF!")
            let r1 = least(rc[0], rc[2])
            let r2 = greatest(rc[0], rc[2])
            let c1 = least(rc[1], rc[3])
            let c2 = greatest(rc[1], rc[3])
            for r in r1..r2 + 1:
                for c in c1..c2 + 1:
                    let f = agg_item(var acc, sh.vals[r * 26 + c].clone(), True)
                    if is_fault(f):
                        return f
        else:
            let f = agg_item(var acc, ev(sh, a), False)
            if is_fault(f):
                return f
    if name == "SUM":
        return finite(acc.total)
    if name == "AVERAGE":
        if acc.count == 0:
            return Fault("#DIV/0!")
        return finite(acc.total / acc.count.to_float())
    if name == "PRODUCT":
        if acc.count == 0:
            return Number(0.0)
        return finite(acc.prod)
    if name == "MIN":
        if acc.count == 0:
            return Number(0.0)
        return Number(acc.lo)
    if name == "MAX":
        if acc.count == 0:
            return Number(0.0)
        return Number(acc.hi)
    # MEDIAN
    if acc.count == 0:
        return Fault("#NUM!")
    let sorted = acc.xs.sorted()
    let m = sorted.length() / 2
    if sorted.length() % 2 == 1:
        return Number(sorted[m])
    return finite((sorted[m - 1] + sorted[m]) / 2.0)

def logic(sh: Sheet, args: List[Expr], is_and: Bool) -> Value:
    if args.length() == 0:
        return Fault("#VALUE!")
    let items = collect(sh, args)
    var count = 0
    var acc = is_and
    for it in items:
        if is_fault(it.v):
            return it.v.clone()
        let skipped = it.ranged and (is_empty_v(it.v) or is_text(it.v))
        if not skipped:
            let b = to_bool(it.v.clone())
            if is_fault(b):
                return b
            count += 1
            if is_and:
                acc = acc and truth(b)
            else:
                acc = acc or truth(b)
    if count == 0:
        return Fault("#VALUE!")
    return Boolean(acc)

def round_half_away(y: Float) -> Float:
    let a = y.abs()
    let t = floor(a)
    var r = t
    if a - t >= 0.5:
        r = t + 1.0
    if y < 0.0:
        return 0.0 - r
    return r

def index_of(x: Float) -> Int:
    return floor(x).truncate_to_int().get(-1)

def crit_prefix(s: String) -> String:
    for p in [">=", "<=", "<>", ">", "<", "="]:
        if s.starts_with(p):
            return p
    return ""

def text_or_number(s: String) -> Value:
    if let x = number_text(s):
        return Number(x)
    return Text(s)

def countif(sh: Sheet, args: List[Expr]) -> Value:
    if args.length() != 2 or not is_span(args[0]):
        return Fault("#VALUE!")
    let rc = corners(args[0])
    if rc[1] < 0 or rc[3] < 0:
        return Fault("#REF!")
    let cv = ev(sh, args[1].clone())
    if is_fault(cv.clone()):
        return cv
    var op = "="
    var operand = cv.clone()
    if is_text(cv):
        let s = text_of(cv)
        let p = crit_prefix(s)
        if p != "":
            op = p.clone()
        operand = text_or_number(s.slice(p.clone().length(), s.length()).get())
    var count = 0
    let r1 = least(rc[0], rc[2])
    let r2 = greatest(rc[0], rc[2])
    let c1 = least(rc[1], rc[3])
    let c2 = greatest(rc[1], rc[3])
    for r in r1..r2 + 1:
        for c in c1..c2 + 1:
            let v = sh.vals[r * 26 + c].clone()
            if type_tag(v.clone()) == type_tag(operand.clone()):
                if truth(compare(op, v, operand.clone())):
                    count += 1
            elif op == "<>" and not is_empty_v(v):
                count += 1
    return Number(count.to_float())

def index_fn(sh: Sheet, args: List[Expr]) -> Value:
    let n = args.length()
    if n < 2 or n > 3 or not is_span(args[0].clone()):
        return Fault("#VALUE!")
    let rc = corners(args[0].clone())
    if rc[1] < 0 or rc[3] < 0:
        return Fault("#REF!")
    let top = least(rc[0], rc[2])
    let left = least(rc[1], rc[3])
    let rows = greatest(rc[0], rc[2]) - top + 1
    let cols = greatest(rc[1], rc[3]) - left + 1
    let rv = to_num(ev(sh, args[1].clone()))
    if is_fault(rv):
        return rv
    var ri = 1
    var ci = 1
    if n == 3:
        let cv = to_num(ev(sh, args[2].clone()))
        if is_fault(cv):
            return cv
        ri = index_of(fnum(rv))
        ci = index_of(fnum(cv))
    elif rows == 1:
        ci = index_of(fnum(rv))
    else:
        ri = index_of(fnum(rv))
    if ri < 1 or ri > rows or ci < 1 or ci > cols:
        return Fault("#REF!")
    return value_at(sh, (top + ri - 1) * 26 + (left + ci - 1))

def row_or_col(args: List[Expr], want_row: Bool) -> Value:
    if args.length() != 1:
        return Fault("#VALUE!")
    match args[0].clone():
        case Ref(r, c):
            if c < 0:
                return Fault("#REF!")
            if want_row:
                return Number(r.to_float())
            return Number((c + 1).to_float())
        case Span(r1, c1, r2, c2):
            if c1 < 0 or c2 < 0:
                return Fault("#REF!")
            if want_row:
                return Number(least(r1, r2).to_float())
            return Number((least(c1, c2) + 1).to_float())
        case _:
            return Fault("#VALUE!")
    return Fault("#VALUE!")

def text_arg(sh: Sheet, args: List[Expr], i: Int) -> Value:
    return ev(sh, args[i].clone())

def call(sh: Sheet, name: String, args: List[Expr]) -> Value:
    let n = args.length()
    if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN" or name == "COUNT" or name == "COUNTA":
        return aggregate(sh, name, args)
    if name == "AND" or name == "OR":
        return logic(sh, args, name == "AND")
    if name == "IF":
        if n < 2 or n > 3:
            return Fault("#VALUE!")
        let c = ev(sh, args[0].clone())
        if is_fault(c):
            return c
        let b = to_bool(c)
        if is_fault(b):
            return b
        if truth(b):
            return ev(sh, args[1].clone())
        if n == 3:
            return ev(sh, args[2].clone())
        return Boolean(False)
    if name == "IFERROR":
        if n != 2:
            return Fault("#VALUE!")
        let a = ev(sh, args[0].clone())
        if is_fault(a):
            return ev(sh, args[1].clone())
        return a
    if name == "CHOOSE":
        if n < 2:
            return Fault("#VALUE!")
        let iv = to_num(ev(sh, args[0].clone()))
        if is_fault(iv):
            return iv
        let idx = index_of(fnum(iv))
        if idx < 1 or idx > n - 1:
            return Fault("#VALUE!")
        return ev(sh, args[idx].clone())
    if name == "NOT":
        if n != 1:
            return Fault("#VALUE!")
        let b = to_bool(ev(sh, args[0].clone()))
        if is_fault(b):
            return b
        return Boolean(not truth(b))
    if name == "ABS" or name == "INT" or name == "SQRT":
        if n != 1:
            return Fault("#VALUE!")
        let x = to_num(ev(sh, args[0].clone()))
        if is_fault(x):
            return x
        let v = fnum(x)
        if name == "ABS":
            return finite(v.abs())
        if name == "INT":
            return finite(floor(v))
        if v < 0.0:
            return Fault("#NUM!")
        return finite(sqrt(v))
    if name == "POW" or name == "MOD":
        if n != 2:
            return Fault("#VALUE!")
        let a = to_num(ev(sh, args[0].clone()))
        if is_fault(a):
            return a
        let b = to_num(ev(sh, args[1].clone()))
        if is_fault(b):
            return b
        let x = fnum(a)
        let y = fnum(b)
        if name == "POW":
            return finite(pow(x, y))
        if y == 0.0:
            return Fault("#DIV/0!")
        return finite(x - y * floor(x / y))
    if name == "ROUND":
        if n < 1 or n > 2:
            return Fault("#VALUE!")
        let x = to_num(ev(sh, args[0].clone()))
        if is_fault(x):
            return x
        var d = 0
        if n == 2:
            let dv = to_num(ev(sh, args[1].clone()))
            if is_fault(dv):
                return dv
            d = fnum(dv).truncate_to_int().get(100)
        if d > 15 or d < -15:
            return Fault("#NUM!")
        let p = pow(10.0, d.to_float())
        return finite(round_half_away(fnum(x) * p) / p)
    if name == "LEN" or name == "UPPER" or name == "LOWER" or name == "TRIM":
        if n != 1:
            return Fault("#VALUE!")
        let v = ev(sh, args[0].clone())
        if is_fault(v):
            return v
        let s = show(v)
        if name == "LEN":
            return Number(s.length().to_float())
        if name == "UPPER" or name == "LOWER":
            var out = ""
            for c in s.chars():
                if name == "UPPER" and c >= "a" and c <= "z":
                    out += c.upper()
                elif name == "LOWER" and c >= "A" and c <= "Z":
                    out += c.lower()
                else:
                    out += c
            return Text(out)
        var out = ""
        var pending = False
        for c in s.chars():
            if is_ws(c):
                pending = True
            else:
                if pending and out != "":
                    out += " "
                pending = False
                out += c
        return Text(out)
    if name == "LEFT" or name == "RIGHT":
        if n < 1 or n > 2:
            return Fault("#VALUE!")
        let sv = ev(sh, args[0].clone())
        if is_fault(sv):
            return sv
        let s = show(sv)
        let len = s.length()
        var kf = 1.0
        if n == 2:
            let nv = to_num(ev(sh, args[1].clone()))
            if is_fault(nv):
                return nv
            kf = floor(fnum(nv))
            if kf < 0.0:
                return Fault("#VALUE!")
        var k = len
        if kf < len.to_float():
            k = kf.truncate_to_int().get(0)
        if name == "LEFT":
            return Text(s.slice(0, k).get())
        return Text(s.slice(len - k, len).get())
    if name == "MID":
        if n != 3:
            return Fault("#VALUE!")
        let sv = ev(sh, args[0].clone())
        if is_fault(sv):
            return sv
        let stv = to_num(ev(sh, args[1].clone()))
        if is_fault(stv):
            return stv
        let lnv = to_num(ev(sh, args[2].clone()))
        if is_fault(lnv):
            return lnv
        let sf = floor(fnum(stv))
        let lf = floor(fnum(lnv))
        if sf < 1.0 or lf < 0.0:
            return Fault("#VALUE!")
        let s = show(sv)
        let len = s.length()
        if sf - 1.0 >= len.to_float():
            return Text("")
        let si = (sf - 1.0).truncate_to_int().get(0)
        var k = len - si
        if lf < k.to_float():
            k = lf.truncate_to_int().get(0)
        return Text(s.slice(si, si + k).get())
    if name == "CONCAT":
        if n == 0:
            return Fault("#VALUE!")
        var out = ""
        for it in collect(sh, args):
            if is_fault(it.v):
                return it.v.clone()
            out += show(it.v.clone())
        return Text(out)
    if name == "SUBSTITUTE":
        if n != 3:
            return Fault("#VALUE!")
        let sv = ev(sh, args[0].clone())
        if is_fault(sv):
            return sv
        let ov = ev(sh, args[1].clone())
        if is_fault(ov):
            return ov
        let nv = ev(sh, args[2].clone())
        if is_fault(nv):
            return nv
        let old = show(ov)
        if old == "":
            return sv
        return Text(show(sv).replace(old, show(nv)))
    if name == "VALUE":
        if n != 1:
            return Fault("#VALUE!")
        return to_num(ev(sh, args[0].clone()))
    if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
        if n != 1:
            return Fault("#VALUE!")
        let v = ev(sh, args[0].clone())
        if name == "ISERROR":
            return Boolean(is_fault(v))
        if name == "ISBLANK":
            return Boolean(is_empty_v(v))
        if name == "ISNUMBER":
            return Boolean(is_number(v))
        return Boolean(is_text(v))
    if name == "ROW":
        return row_or_col(args, True)
    if name == "COLUMN":
        return row_or_col(args, False)
    if name == "INDEX":
        return index_fn(sh, args)
    if name == "COUNTIF":
        return countif(sh, args)
    return Fault("#NAME?")

# Value of a formula cell after evaluation: an empty result counts as 0.
def eval_top(sh: Sheet, e: Expr) -> Value:
    let v = ev(sh, e)
    if is_empty_v(v):
        return Number(0.0)
    return v

# ---------- Assignment and recalculation ----------

# Classifies the trimmed VALUE of a set/import/copy into a constant value.
def classify(raw: String) -> Value:
    if raw.starts_with("'"):
        return Text(raw.slice(1, raw.length()).get())
    if let x = number_text(raw):
        return Number(x)
    let up = raw.upper()
    if up == "TRUE":
        return Boolean(True)
    if up == "FALSE":
        return Boolean(False)
    return Text(raw)

def set_cell(var sh: Sheet, key: Int, raw: String) -> Unit:
    let old = sh.precs[key].clone()
    for p in old:
        remove_dep(var sh, p, key)
    sh.precs[key] = List[Int]()
    sh.raw[key] = raw.clone()
    if raw == "":
        sh.kind[key] = 0
        sh.vals[key] = Empty
        return
    if raw.starts_with("="):
        if let e = parse_formula(raw.slice(1, raw.length()).get()):
            let precs = precedents_of(e.clone())
            for p in precs:
                add_dep(var sh, p, key)
            sh.precs[key] = precs
            sh.exprs[key] = e
            sh.kind[key] = 2
            sh.vals[key] = Empty
        else:
            sh.kind[key] = 3
            sh.vals[key] = Fault("#PARSE!")
        return
    sh.kind[key] = 1
    sh.vals[key] = classify(raw)

def visit(var sh: Sheet, var st: Tarjan, v: Int) -> Unit:
    sh.tseen[v] = st.ep
    sh.tidx[v] = st.counter
    sh.tlow[v] = st.counter
    st.counter += 1
    st.stack.append(v)
    sh.ton[v] = True
    let ps = sh.precs[v].clone()
    for p in ps:
        if sh.mark[p] == st.ep:
            if sh.tseen[p] != st.ep:
                visit(var sh, var st, p)
                sh.tlow[v] = least(sh.tlow[v], sh.tlow[p])
            elif sh.ton[p]:
                sh.tlow[v] = least(sh.tlow[v], sh.tidx[p])
    if sh.tlow[v] == sh.tidx[v]:
        var members = List[Int]()
        var done = False
        while not done:
            let m = st.stack.pop().get(0)
            sh.ton[m] = False
            members.append(m)
            if m == v:
                done = True
        var self_loop = False
        for p in ps:
            if p == v:
                self_loop = True
        if members.length() == 1 and not self_loop:
            if sh.kind[v] == 3:
                sh.vals[v] = Fault("#PARSE!")
            else:
                sh.vals[v] = eval_top(sh, sh.exprs[v].clone())
        else:
            for m in members:
                sh.vals[m] = Fault("#CYCLE!")

def recalc(var sh: Sheet, changed: List[Int]) -> Int:
    sh.epoch += 1
    let ep = sh.epoch
    var aff = List[Int]()
    var queue = List[Int]()
    for k in changed:
        queue.append(k)
        if sh.kind[k] >= 2 and sh.mark[k] != ep:
            sh.mark[k] = ep
            aff.append(k)
    var qi = 0
    while qi < queue.length():
        let n = queue[qi]
        qi += 1
        for d in dependents_direct(sh, n):
            if sh.mark[d] != ep:
                sh.mark[d] = ep
                aff.append(d)
                queue.append(d)
    var st = Tarjan(stack: List[Int](), counter: 0, ep: ep)
    for k in aff:
        if sh.tseen[k] != ep:
            visit(var sh, var st, k)
    sh.evals += aff.length()
    return aff.length()

# ---------- Commands ----------

def say(s: String) -> Unit:
    stdout().write(s + "\n").get()

# Splits a line into whitespace-separated fields; the last one (when `limit` is reached) keeps the rest of the line.
def fields(line: String, limit: Int) -> List[String]:
    let cs = line.chars()
    let n = cs.length()
    var out = List[String]()
    var i = 0
    while i < n:
        while i < n and is_ws(cs[i]):
            i += 1
        if i >= n:
            break
        if out.length() == limit - 1:
            out.append(span(cs, i, n).trim())
            break
        var j = i
        while j < n and not is_ws(cs[j]):
            j += 1
        out.append(span(cs, i, j))
        i = j
    return out

# Cell key of a bare cell reference (no $), or -1.
def cell_key(t: String) -> Int:
    if has_char(t, "$"):
        return -1
    let p = ref_parts(t)
    if not p.valid:
        return -1
    return p.row * 26 + p.col

# [r1, c1, r2, c2] of a cell or range argument, or [] when it is not one.
def rect_of(t: String) -> List[Int]:
    let parts = t.split(":")
    if parts.length() == 1:
        let k = cell_key(parts[0])
        if k < 0:
            return []
        return [k / 26, k - (k / 26) * 26, k / 26, k - (k / 26) * 26]
    if parts.length() == 2:
        let a = cell_key(parts[0])
        let b = cell_key(parts[1])
        if a < 0 or b < 0:
            return []
        let ra = a / 26
        let ca = a - ra * 26
        let rb = b / 26
        let cb = b - rb * 26
        return [least(ra, rb), least(ca, cb), greatest(ra, rb), greatest(ca, cb)]
    return []

def csv_field(s: String) -> String:
    var needs = s.starts_with(" ") or s.ends_with(" ")
    if has_char(s, ",") or has_char(s, "\"") or has_char(s, "\n") or has_char(s, "\r"):
        needs = True
    if not needs:
        return s
    var out = "\""
    for c in s.chars():
        if c == "\"":
            out += "\"\""
        else:
            out += c
    return out + "\""

# Bounding rectangle of the non-empty cells, or [] for an empty sheet.
def used_rect(sh: Sheet) -> List[Int]:
    var found = False
    var maxr = 1
    var maxc = 0
    for key in 0..key_count():
        if sh.kind[key] != 0:
            let r = key / 26
            let c = key - r * 26
            found = True
            maxr = greatest(maxr, r)
            maxc = greatest(maxc, c)
    if not found:
        return []
    return [1, 0, maxr, maxc]

def csv_parse(lines: List[String]) -> List[List[String]]:
    var text = ""
    var first = True
    for line in lines:
        if not first:
            text += "\n"
        text += line
        first = False
    let cs = text.chars()
    let n = cs.length()
    var recs = List[List[String]]()
    var rec = List[String]()
    var field = ""
    var inq = False
    var rawn = 0
    var i = 0
    while i < n:
        let c = cs[i]
        if inq and c == "\"" and i + 1 < n and cs[i + 1] == "\"":
            field += "\""
            rawn += 2
            i += 2
        elif c == "\r" and not inq:
            i += 1
        elif c == "\"":
            inq = not inq
            rawn += 1
            i += 1
        elif c == "," and not inq:
            rec.append(field)
            field = ""
            rawn += 1
            i += 1
        elif c == "\n" and not inq:
            rec.append(field)
            if rawn > 0:
                recs.append(rec)
            rec = List[String]()
            field = ""
            rawn = 0
            i += 1
        else:
            field += c
            rawn += 1
            i += 1
    if rawn > 0:
        rec.append(field)
        recs.append(rec)
    return recs

def shift_ref(text: String, dc: Int, dr: Int) -> Optional[String]:
    let p = ref_parts(text)
    if not p.valid:
        return some(text)
    let nc = p.col + (0 if p.abs_col else dc)
    let nr = p.row + (0 if p.abs_row else dr)
    if nc < 0 or nc > 25 or nr < 1 or nr > 999:
        return none
    var out = ""
    if p.abs_col:
        out += "$"
    out += letter(nc)
    if p.abs_row:
        out += "$"
    return some(out + nr.to_string())

def shift_formula(raw: String, dc: Int, dr: Int) -> String:
    if let toks = lex(raw):
        var out = ""
        for t in toks:
            if t.kind == "ref":
                if let s = shift_ref(t.text.clone(), dc, dr):
                    out += s
                else:
                    out += "#REF!"
            elif t.kind == "range":
                let parts = t.text.split(":")
                let a = shift_ref(parts[0].clone(), dc, dr)
                let b = shift_ref(parts[1].clone(), dc, dr)
                if a.is_none() or b.is_none():
                    out += "#REF!"
                else:
                    out += a.get("") + ":" + b.get("")
            else:
                out += t.text
        return out
    return raw

def dependents_of(sh: Sheet, start: Int) -> List[Int]:
    var seen = Set[Int]()
    var queue = List[Int]()
    queue.append(start)
    var qi = 0
    while qi < queue.length():
        let n = queue[qi]
        qi += 1
        for d in dependents_direct(sh, n):
            if not seen.contains(d):
                seen.add(d)
                queue.append(d)
    return seen.values().sorted()

def names_of(keys: List[Int]) -> String:
    var parts = List[String]()
    for k in keys:
        parts.append(key_name(k))
    return parts.join(" ")

def print_rect(sh: Sheet, rect: List[Int]) -> Unit:
    for r in rect[0]..rect[2] + 1:
        var parts = List[String]()
        for c in rect[1]..rect[3] + 1:
            parts.append(show(value_at(sh, r * 26 + c)))
        say(parts.join(" | "))

def export_rect(sh: Sheet, rect: List[Int], formulas: Bool) -> Unit:
    for r in rect[0]..rect[2] + 1:
        var parts = List[String]()
        for c in rect[1]..rect[3] + 1:
            let key = r * 26 + c
            if formulas:
                parts.append(csv_field(sh.raw[key].clone()))
            else:
                parts.append(csv_field(show(value_at(sh, key))))
        say(parts.join(","))

def do_import(var sh: Sheet, cell: String, block: List[String]) -> Unit:
    let key = cell_key(cell)
    if key < 0:
        say("error: bad cell reference '" + cell + "'")
        return
    let recs = csv_parse(block)
    var width = 0
    for rec in recs:
        width = greatest(width, rec.length())
    let rows = recs.length()
    let base_r = key / 26
    let base_c = key - base_r * 26
    if rows > 0 and (base_r + rows - 1 > 999 or base_c + width - 1 > 25):
        say("error: import out of range")
        return
    var changed = List[Int]()
    for i in 0..rows:
        let rec = recs[i]
        for j in 0..rec.length():
            let k = (base_r + i) * 26 + base_c + j
            set_cell(var sh, k, rec[j].trim().clone())
            changed.append(k)
    let n = recalc(var sh, changed)
    say("imported " + rows.to_string() + " rows, " + width.to_string() + " columns; recalc " + n.to_string())

def run(var sh: Sheet, line: String, lines: List[String], at: Int) -> Int:
    var next = at + 1
    let f = fields(line, 1000)
    let cmd = f[0]
    let argc = f.length() - 1
    if cmd == "set":
        let sf = fields(line, 3)
        if sf.length() < 2:
            say("error: usage: set CELL VALUE")
            return next
        let key = cell_key(sf[1])
        if key < 0:
            say("error: bad cell reference '" + sf[1] + "'")
            return next
        var raw = ""
        if sf.length() == 3:
            raw = sf[2].trim().clone()
        set_cell(var sh, key, raw)
        let n = recalc(var sh, [key])
        say("recalc " + n.to_string())
    elif cmd == "clear":
        if argc != 1:
            say("error: usage: clear CELL")
            return next
        let key = cell_key(f[1])
        if key < 0:
            say("error: bad cell reference '" + f[1] + "'")
            return next
        set_cell(var sh, key, "")
        let n = recalc(var sh, [key])
        say("recalc " + n.to_string())
    elif cmd == "get":
        if argc != 1:
            say("error: usage: get CELL")
            return next
        let key = cell_key(f[1])
        if key < 0:
            say("error: bad cell reference '" + f[1] + "'")
            return next
        if sh.kind[key] == 0:
            say("(empty)")
        else:
            say(show(value_at(sh, key)))
    elif cmd == "show":
        if argc != 1:
            say("error: usage: show CELL")
            return next
        let key = cell_key(f[1])
        if key < 0:
            say("error: bad cell reference '" + f[1] + "'")
            return next
        let name = key_name(key)
        let k = sh.kind[key]
        if k == 0:
            say(name + ": (empty)")
        elif k == 1:
            say(name + ": " + sh.raw[key])
        else:
            say(name + ": " + sh.raw[key] + " => " + show(value_at(sh, key)))
    elif cmd == "stats":
        var cells = 0
        var formulas = 0
        for k in 0..key_count():
            if sh.kind[k] != 0:
                cells += 1
            if sh.kind[k] >= 2:
                formulas += 1
        say("cells " + cells.to_string() + " formulas " + formulas.to_string() + " evals " + sh.evals.to_string())
    elif cmd == "precedents" or cmd == "dependents":
        if argc != 1:
            say("error: usage: " + cmd + " CELL")
            return next
        let key = cell_key(f[1])
        if key < 0:
            say("error: bad cell reference '" + f[1] + "'")
            return next
        var keys = List[Int]()
        if cmd == "precedents":
            keys = precs_of(sh, key)
            keys = keys.sorted()
        else:
            keys = dependents_of(sh, key)
        if keys.length() == 0:
            say("(none)")
        else:
            say(names_of(keys))
    elif cmd == "print":
        if argc > 1:
            say("error: usage: print [RANGE]")
            return next
        var rect = used_rect(sh)
        if argc == 1:
            if f[1] == "formulas":
                say("error: usage: print [RANGE]")
                return next
            rect = rect_of(f[1])
            if rect.length() == 0:
                say("error: bad range '" + f[1] + "'")
                return next
        if rect.length() == 0:
            say("(empty sheet)")
            return next
        print_rect(sh, rect)
    elif cmd == "export":
        var formulas = False
        var rest = 0
        if argc > 2:
            say("error: usage: export [formulas] [RANGE]")
            return next
        if argc >= 1 and (f[1] == "formulas" or f[1] == "values"):
            formulas = f[1] == "formulas"
            rest = 1
        if argc - rest > 1 or (argc == 2 and rest == 0):
            say("error: usage: export [formulas] [RANGE]")
            return next
        var rect = used_rect(sh)
        if argc - rest == 1:
            rect = rect_of(f[1 + rest])
            if rect.length() == 0:
                say("error: bad range '" + f[1 + rest] + "'")
                return next
        if rect.length() == 0:
            say("(empty sheet)")
            return next
        export_rect(sh, rect, formulas)
    elif cmd == "copy":
        if argc != 2:
            say("error: usage: copy SRC DST")
            return next
        let src = cell_key(f[1])
        if src < 0:
            say("error: bad cell reference '" + f[1] + "'")
            return next
        let dst = rect_of(f[2])
        if dst.length() == 0:
            say("error: bad range '" + f[2] + "'")
            return next
        let src_raw = sh.raw[src].clone()
        let sr = src / 26
        let sc = src - sr * 26
        var changed = List[Int]()
        for r in dst[0]..dst[2] + 1:
            for c in dst[1]..dst[3] + 1:
                let k = r * 26 + c
                var raw = src_raw.clone()
                if raw.starts_with("="):
                    raw = shift_formula(raw, c - sc, r - sr)
                set_cell(var sh, k, raw)
                changed.append(k)
        let n = recalc(var sh, changed)
        say("recalc " + n.to_string())
    elif cmd == "import":
        var j = at + 1
        var block = List[String]()
        while j < lines.length() and lines[j] != ".":
            block.append(lines[j].clone())
            j += 1
        next = j
        if j < lines.length():
            next = j + 1
        if argc != 1:
            say("error: usage: import CELL")
        else:
            do_import(var sh, f[1], block)
    else:
        say("error: unknown command '" + cmd + "'")
    return next

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    var sh = new_sheet()
    var i = 0
    while i < lines.length():
        let line = lines[i]
        i += 1
        let f = fields(line, 1000)
        if f.length() > 0 and not f[0].starts_with("#"):
            say("> " + rtrim(line))
            i = run(var sh, line, lines, i - 1)

    return 0
