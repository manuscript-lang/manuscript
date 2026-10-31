import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import floor, pow, sqrt from "@std/math.ms"

# ---------------------------------------------------------------- constants

let ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let DIGS = "0123456789"
let E_DIV = "#DIV/0!"
let E_REF = "#REF!"
let E_NAME = "#NAME?"
let E_VALUE = "#VALUE!"
let E_NUM = "#NUM!"
let E_PARSE = "#PARSE!"
let E_CYCLE = "#CYCLE!"
let TWO53 = 9007199254740992.0
let NARROW = 256

# ---------------------------------------------------------------- types

# Cell keys are r * 100 + c (c in 0..25, r in 1..999), so ordering by key is row-major.
type Value:
    case VEmpty
    case VNum(n: Float)
    case VText(s: String)
    case VBool(b: Bool)
    case VErr(e: String)

type Node:
    case NLit(v: Value)
    case NRef(c: Int, r: Int, ok: Bool)
    case NRng(c1: Int, r1: Int, c2: Int, r2: Int, ok: Bool)
    case NName(name: String)
    case NCall(name: String, args: List[Node])
    case NUn(op: String, x: Node)
    case NBin(op: String, l: Node, r: Node)
    case NParen(x: Node)
    case NBad

# kind: 0 number, 1 text, 2 identifier, 3 reference, 4 range, 5 operator,
# 6 '(', 7 ')', 8 ',', 9 #REF! constant, 10 end, 11 bad character
type Tok:
    kind: Int = 10
    text: String = ""
    num: Float = 0.0
    s0: Int = 0
    s1: Int = 0

type RefP:
    ok: Bool = false
    shape: Bool = false
    c: Int = 0
    r: Int = 0
    cabs: Bool = false
    rabs: Bool = false

type Rect:
    c1: Int = 0
    r1: Int = 0
    c2: Int = 0
    r2: Int = 0

type Item:
    v: Value
    rng: Bool

type RI:
    kind: Int
    ok: Bool
    c1: Int
    r1: Int
    c2: Int
    r2: Int

type Crit:
    op: String
    opnd: Value

type Cut:
    head: String
    rest: String

type Ps:
    toks: List[Tok]
    pos: Int = 0
    bad: Bool = false

type Scc:
    succ: List[List[Int]]
    idx: List[Int]
    low: List[Int]
    onst: List[Bool]
    stk: List[Int]
    counter: Int
    order: List[List[Int]]

type Sheet:
    rawm: Map[Int, String]
    valm: Map[Int, Value]
    formm: Map[Int, Node]
    depm: Map[Int, List[Rect]]
    evals: Int
    out: List[String]

# ---------------------------------------------------------------- small helpers

fn is_ws(ch: String) Bool:
    return ch == " " or ch == "\t" or ch == "\r" or ch == "\n"

fn is_digit(ch: String) Bool:
    return ch >= "0" and ch <= "9"

fn is_letter(ch: String) Bool:
    return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")

fn is_wordch(ch: String) Bool:
    return is_letter(ch) or is_digit(ch) or ch == "_" or ch == "." or ch == "$"

fn sub(cs: List[String], a: Int, b: Int) String:
    var out = List[String]()
    var i = a
    while i < b:
        out.append(cs[i].clone())
        i += 1
    return out.join("")

fn imin(a: Int, b: Int) Int:
    if a < b:
        return a
    return b

fn imax(a: Int, b: Int) Int:
    if a > b:
        return a
    return b

fn key(c: Int, r: Int) Int:
    return r * 100 + c

fn cname(k: Int) String:
    let c = k % 100
    let r = k / 100
    return ALPHA.drop(c).take(1) + r.to_string()

fn norm_rect(c1: Int, r1: Int, c2: Int, r2: Int) Rect:
    return Rect(c1: imin(c1, c2), r1: imin(r1, r2), c2: imax(c1, c2), r2: imax(r1, r2))

fn in_rect(rc: Rect, k: Int) Bool:
    let kc = k % 100
    let kr = k / 100
    return kc >= rc.c1 and kc <= rc.c2 and kr >= rc.r1 and kr <= rc.r2

fn covers(rs: List[Rect], k: Int) Bool:
    for rc in rs:
        if in_rect(rc, k):
            return true
    return false

fn ident_shape(w: String) Bool:
    let cs = w.chars()
    if cs.length() == 0:
        return false
    if not (is_letter(cs[0]) or cs[0] == "_"):
        return false
    for ch in cs:
        if not (is_letter(ch) or is_digit(ch) or ch == "_" or ch == "."):
            return false
    return true

# Reference shape: optional $, letters, optional $, digits. ok = valid cell reference.
fn ref_parts(s: String) RefP:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var cabs = false
    var rabs = false
    var nl = 0
    var col = -1
    if i < n and cs[i] == "$":
        cabs = true
        i += 1
    while i < n and is_letter(cs[i]):
        if nl == 0:
            col = ALPHA.index_of(cs[i].upper()).get(0)
        nl += 1
        i += 1
    if i < n and cs[i] == "$":
        rabs = true
        i += 1
    let ds = i
    while i < n and is_digit(cs[i]):
        i += 1
    let nd = i - ds
    if nl == 0 or nd == 0 or i != n:
        return RefP(ok: false, shape: false, c: 0, r: 0, cabs: cabs, rabs: rabs)
    var row = 0
    var k = ds
    while k < n:
        row = row * 10 + DIGS.index_of(cs[k]).get(0)
        k += 1
    let ok = nl == 1 and nd <= 3 and cs[ds] != "0" and row >= 1 and row <= 999
    return RefP(ok: ok, shape: true, c: col, r: row, cabs: cabs, rabs: rabs)

fn ref_shape(w: String) Bool:
    return ref_parts(w).shape

# ---------------------------------------------------------------- number text

fn numgram(s: String) Bool:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    if i < n and (cs[i] == "+" or cs[i] == "-"):
        i += 1
    var nd = 0
    while i < n and is_digit(cs[i]):
        i += 1
        nd += 1
    if i < n and cs[i] == ".":
        i += 1
        while i < n and is_digit(cs[i]):
            i += 1
            nd += 1
    if nd == 0:
        return false
    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1
        if i < n and (cs[i] == "+" or cs[i] == "-"):
            i += 1
        var ne = 0
        while i < n and is_digit(cs[i]):
            i += 1
            ne += 1
        if ne == 0:
            return false
    return i == n

# Value of text that satisfies numgram (may be infinite for huge exponents).
fn numval(s: String) Float:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var neg = false
    if i < n and (cs[i] == "+" or cs[i] == "-"):
        neg = cs[i] == "-"
        i += 1
    let is0 = i
    while i < n and is_digit(cs[i]):
        i += 1
    let ints = sub(cs, is0, i)
    var frac = ""
    if i < n and cs[i] == ".":
        i += 1
        let fs = i
        while i < n and is_digit(cs[i]):
            i += 1
        frac = sub(cs, fs, i)
    var eneg = false
    var edig = ""
    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1
        if i < n and (cs[i] == "+" or cs[i] == "-"):
            eneg = cs[i] == "-"
            i += 1
        let es = i
        while i < n and is_digit(cs[i]):
            i += 1
        edig = sub(cs, es, i)
    let mant = ints + frac
    var mz = true
    for ch in mant.chars():
        if ch != "0":
            mz = false
    let ec = edig.chars()
    var z = 0
    while z < ec.length() and ec[z] == "0":
        z += 1
    var ed = sub(ec, z, ec.length())
    if ed.length() > 6:
        ed = "999999"
    if ed == "":
        ed = "0"
    var ip = ints.clone()
    if ip == "":
        ip = "0"
    var fp = frac.clone()
    if fp == "":
        fp = "0"
    var sgn = ""
    if eneg:
        sgn = "-"
    let canon = ip + "." + fp + "e" + sgn + ed
    if let p = canon.parse_float():
        if neg:
            return -p
        return p
    if mz or eneg:
        return 0.0
    let inf = 1.0e200 * 1.0e200
    if neg:
        return -inf
    return inf

fn strip_fixed(s: String) String:
    var neg = false
    var body = s.clone()
    if s.starts_with("-"):
        neg = true
        body = s.drop(1)
    let dot = body.index_of(".").get(0)
    let ip = body.take(dot)
    let cs = body.drop(dot + 1).chars()
    var e = cs.length()
    while e > 0:
        if cs[e - 1] != "0":
            break
        e -= 1
    var res = ip.clone()
    if e > 0:
        res = ip + "." + sub(cs, 0, e)
    if res == "0":
        return res
    if neg:
        return "-" + res
    return res

# Exact decimal expansion of a large integer-valued double.
fn fmt_big(x: Float) String:
    let neg = x < 0.0
    var y = x.abs()
    var e = 0
    while y >= TWO53:
        y = y / 2.0
        e += 1
    let m = y.truncate_to_int().get(0)
    var digs = List[Int]()
    let mcs = m.to_string().chars()
    var q = mcs.length() - 1
    while q >= 0:
        digs.append(DIGS.index_of(mcs[q]).get(0))
        q -= 1
    var step = 0
    while step < e:
        var carry = 0
        var t = 0
        while t < digs.length():
            let v = digs[t] * 2 + carry
            digs[t] = v % 10
            carry = v / 10
            t += 1
        while carry > 0:
            digs.append(carry % 10)
            carry = carry / 10
        step += 1
    var out = ""
    var p = digs.length() - 1
    while p >= 0:
        out = out + DIGS.drop(digs[p]).take(1)
        p -= 1
    if neg:
        return "-" + out
    return out

fn fmt_num(x: Float) String:
    if x.abs() >= 1.0e21:
        return fmt_big(x)
    return strip_fixed(x.to_fixed(10))

# ---------------------------------------------------------------- values

fn kind_of(v: Value) Int:
    match v:
        VEmpty:
            return 0
        VNum(_n):
            return 1
        VText(_s):
            return 2
        VBool(_b):
            return 3
        VErr(_e):
            return 4

fn is_err(v: Value) Bool:
    return kind_of(v) == 4

fn is_num(v: Value) Bool:
    return kind_of(v) == 1

fn numof(v: Value) Float:
    match v:
        VNum(x):
            return x
        _:
            return 0.0

fn getbool(v: Value) Bool:
    match v:
        VBool(bb):
            return bb
        _:
            return false

fn numres(x: Float) Value:
    if x.is_finite():
        return VNum(n: x)
    return VErr(e: E_NUM)

# String form (display text) of a non-error value.
fn sf(v: Value) String:
    match v:
        VEmpty:
            return ""
        VNum(x):
            return fmt_num(x)
        VText(s):
            return s.clone()
        VBool(bb):
            if bb:
                return "TRUE"
            return "FALSE"
        VErr(e):
            return e.clone()

fn coerce(v: Value) Value:
    match v:
        VEmpty:
            return VNum(n: 0.0)
        VNum(x):
            return VNum(n: x)
        VBool(bb):
            if bb:
                return VNum(n: 1.0)
            return VNum(n: 0.0)
        VText(s):
            let t = s.trim()
            if numgram(t):
                return VNum(n: numval(t))
            return VErr(e: E_VALUE)
        VErr(e):
            return VErr(e: e.clone())

fn boolco(v: Value) Value:
    match v:
        VBool(bb):
            return VBool(b: bb)
        VNum(x):
            return VBool(b: x != 0.0)
        VText(s):
            let up = s.upper()
            if up == "TRUE":
                return VBool(b: true)
            if up == "FALSE":
                return VBool(b: false)
            return VErr(e: E_VALUE)
        VEmpty:
            return VBool(b: false)
        VErr(e):
            return VErr(e: e.clone())

fn zero_of(v: Value) Value:
    let k = kind_of(v)
    if k == 1:
        return VNum(n: 0.0)
    if k == 2:
        return VText(s: "")
    return VBool(b: false)

# Three-way comparison with the empty-cell and type-order rules. No errors expected.
fn cmp3(a0: Value, b0: Value) Int:
    var a = a0.clone()
    var b = b0.clone()
    let ka0 = kind_of(a)
    let kb0 = kind_of(b)
    if ka0 == 0 and kb0 == 0:
        return 0
    if ka0 == 0:
        a = zero_of(b)
    if kb0 == 0:
        b = zero_of(a)
    let ka = kind_of(a)
    let kb = kind_of(b)
    if ka != kb:
        if ka < kb:
            return -1
        return 1
    if ka == 1:
        let x = numof(a)
        let y = numof(b)
        if x < y:
            return -1
        if x > y:
            return 1
        return 0
    if ka == 2:
        let s = sf(a)
        let t = sf(b)
        if s < t:
            return -1
        if s > t:
            return 1
        return 0
    let p = getbool(a)
    let q = getbool(b)
    if p == q:
        return 0
    if q:
        return -1
    return 1

fn opholds(op: String, c: Int) Bool:
    if op == "=":
        return c == 0
    if op == "<>":
        return c != 0
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0
    return c >= 0

fn floor_int(x: Float) Int:
    let f = floor(x)
    if f > 1.0e12:
        return 1000000000000
    if f < -1.0e12:
        return -1000000000000
    if let i = f.truncate_to_int():
        return i
    return 0

fn round_half(y: Float) Float:
    let a = y.abs()
    let t = floor(a)
    var r = t
    if a - t >= 0.5:
        r = t + 1.0
    if y < 0.0:
        return -r
    return r

fn trunc_f(d: Float) Float:
    if d >= 0.0:
        return floor(d)
    return -floor(-d)

fn ascii_upper(s: String) String:
    var out = List[String]()
    for ch in s.chars():
        if ch.byte_length() == 1:
            out.append(ch.upper())
        else:
            out.append(ch)
    return out.join("")

fn ascii_lower(s: String) String:
    var out = List[String]()
    for ch in s.chars():
        if ch.byte_length() == 1:
            out.append(ch.lower())
        else:
            out.append(ch)
    return out.join("")

fn collapse(s: String) String:
    var out = ""
    var pending = false
    for ch in s.chars():
        if is_ws(ch):
            pending = true
        else:
            if pending and out.length() > 0:
                out = out + " "
            pending = false
            out = out + ch
    return out

fn textop(s: String) Value:
    return VText(s: s.clone())

# ---------------------------------------------------------------- lexer

fn tk(kind: Int, text: String, s0: Int, s1: Int) Tok:
    return Tok(kind: kind, text: text, num: 0.0, s0: s0, s1: s1)

fn lex(cs: List[String]) List[Tok]:
    var out = List[Tok]()
    let n = cs.length()
    var i = 0
    while i < n:
        let ch = cs[i].clone()
        if is_ws(ch):
            i += 1
        else if is_digit(ch) or (ch == "." and i + 1 < n and is_digit(cs[i + 1])):
            var j = i
            while j < n and is_digit(cs[j]):
                j += 1
            if j < n and cs[j] == ".":
                j += 1
                while j < n and is_digit(cs[j]):
                    j += 1
            if j < n and (cs[j] == "e" or cs[j] == "E"):
                var q = j + 1
                if q < n and (cs[q] == "+" or cs[q] == "-"):
                    q += 1
                if q < n and is_digit(cs[q]):
                    while q < n and is_digit(cs[q]):
                        q += 1
                    j = q
            let t = sub(cs, i, j)
            let nv = numval(t)
            out.append(Tok(kind: 0, text: t.clone(), num: nv, s0: i, s1: j))
            i = j
        else if ch == "\"":
            var j = i + 1
            var sb = List[String]()
            var closed = false
            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        sb.append("\"")
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    sb.append(cs[j].clone())
                    j += 1
            if closed:
                out.append(tk(1, sb.join(""), i, j))
            else:
                out.append(tk(11, ch, i, j))
            i = j
        else if is_letter(ch) or ch == "_" or ch == "$":
            var j = i
            while j < n and is_wordch(cs[j]):
                j += 1
            let w = sub(cs, i, j)
            let paren = j < n and cs[j] == "("
            if paren and ident_shape(w):
                out.append(tk(2, w, i, j))
                i = j
            else if ref_shape(w):
                var handled = false
                if j < n and cs[j] == ":":
                    var m = j + 1
                    while m < n and is_wordch(cs[m]):
                        m += 1
                    let w2 = sub(cs, j + 1, m)
                    if ref_shape(w2):
                        out.append(tk(4, w + ":" + w2, i, m))
                        i = m
                        handled = true
                if not handled:
                    out.append(tk(3, w, i, j))
                    i = j
            else if ident_shape(w):
                out.append(tk(2, w, i, j))
                i = j
            else:
                out.append(tk(11, w, i, j))
                i = j
        else if ch == "(":
            out.append(tk(6, ch, i, i + 1))
            i += 1
        else if ch == ")":
            out.append(tk(7, ch, i, i + 1))
            i += 1
        else if ch == ",":
            out.append(tk(8, ch, i, i + 1))
            i += 1
        else if ch == "+" or ch == "-" or ch == "*" or ch == "/" or ch == "^" or ch == "&" or ch == "=":
            out.append(tk(5, ch, i, i + 1))
            i += 1
        else if ch == "<" or ch == ">":
            let j = i + 1
            if j < n and (cs[j] == "=" or (ch == "<" and cs[j] == ">")):
                out.append(tk(5, ch + cs[j], i, j + 1))
                i = j + 1
            else:
                out.append(tk(5, ch, i, i + 1))
                i += 1
        else if ch == "#" and i + 5 <= n and sub(cs, i, i + 5).upper() == "#REF!":
            out.append(tk(9, "#REF!", i, i + 5))
            i += 5
        else:
            out.append(tk(11, ch, i, i + 1))
            i += 1
    out.append(Tok(kind: 10, text: "", num: 0.0, s0: n, s1: n))
    return out

# ---------------------------------------------------------------- parser

impl Ps:
    fn cur() Tok:
        if self.pos < self.toks.length():
            return self.toks[self.pos].clone()
        return Tok(kind: 10)

    fn kind() Int:
        return self.cur().kind

    fn is_op(s: String) Bool:
        let t = self.cur()
        return t.kind == 5 and t.text == s

    fn is_cmp() Bool:
        let t = self.cur()
        if t.kind != 5:
            return false
        return t.text == "=" or t.text == "<>" or t.text == "<" or t.text == "<=" or t.text == ">" or t.text == ">="

    var fn bump() Unit:
        self.pos += 1

    var fn failp() Unit:
        self.bad = true
        self.pos = self.toks.length()

    var fn expr() Node:
        return self.cmpx()

    var fn cmpx() Node:
        var left = self.catx()
        while self.is_cmp():
            let op = self.cur().text
            self.bump()
            let right = self.catx()
            left = NBin(op: op, l: left, r: right)
        return left

    var fn catx() Node:
        var left = self.addx()
        while self.is_op("&"):
            self.bump()
            let right = self.addx()
            left = NBin(op: "&", l: left, r: right)
        return left

    var fn addx() Node:
        var left = self.mulx()
        while self.is_op("+") or self.is_op("-"):
            let op = self.cur().text
            self.bump()
            let right = self.mulx()
            left = NBin(op: op, l: left, r: right)
        return left

    var fn mulx() Node:
        var left = self.unx()
        while self.is_op("*") or self.is_op("/"):
            let op = self.cur().text
            self.bump()
            let right = self.unx()
            left = NBin(op: op, l: left, r: right)
        return left

    var fn unx() Node:
        if self.is_op("+") or self.is_op("-"):
            let op = self.cur().text
            self.bump()
            let x = self.unx()
            return NUn(op: op, x: x)
        return self.powx()

    var fn powx() Node:
        let base = self.primary()
        if self.is_op("^"):
            self.bump()
            let ex = self.powrhs()
            return NBin(op: "^", l: base, r: ex)
        return base

    var fn powrhs() Node:
        if self.is_op("+") or self.is_op("-"):
            let op = self.cur().text
            self.bump()
            let x = self.powrhs()
            return NUn(op: op, x: x)
        return self.powx()

    var fn callx(name: String) Node:
        self.bump()
        var args = List[Node]()
        if self.kind() == 7:
            self.bump()
            return NCall(name: name, args: args)
        var done = false
        while not done:
            let a = self.expr()
            if self.bad:
                return NBad
            args.append(a)
            if self.kind() == 8:
                self.bump()
            else if self.kind() == 7:
                self.bump()
                done = true
            else:
                self.failp()
                return NBad
        return NCall(name: name, args: args)

    var fn primary() Node:
        let t = self.cur()
        if t.kind == 0:
            self.bump()
            if not t.num.is_finite():
                return NLit(v: VErr(e: E_NUM))
            return NLit(v: VNum(n: t.num))
        if t.kind == 1:
            self.bump()
            return NLit(v: VText(s: t.text))
        if t.kind == 2:
            self.bump()
            if self.kind() == 6:
                return self.callx(t.text.upper())
            let up = t.text.upper()
            if up == "TRUE":
                return NLit(v: VBool(b: true))
            if up == "FALSE":
                return NLit(v: VBool(b: false))
            return NName(name: up)
        if t.kind == 3:
            self.bump()
            let p = ref_parts(t.text)
            return NRef(c: p.c, r: p.r, ok: p.ok)
        if t.kind == 4:
            self.bump()
            let parts = t.text.split(":")
            let a = ref_parts(parts[0])
            let b = ref_parts(parts[1])
            return NRng(c1: a.c, r1: a.r, c2: b.c, r2: b.r, ok: a.ok and b.ok)
        if t.kind == 9:
            self.bump()
            return NLit(v: VErr(e: E_REF))
        if t.kind == 6:
            self.bump()
            let e = self.expr()
            if self.bad:
                return NBad
            if self.kind() == 7:
                self.bump()
                return NParen(x: e)
            self.failp()
            return NBad
        self.failp()
        return NBad

fn parse_formula(src: String) Node:
    let toks = lex(src.chars())
    var p = Ps(toks: toks, pos: 0, bad: false)
    let e = p.expr()
    if p.bad or p.kind() != 10:
        return NBad
    return e

# Collects precedent rectangles (valid references and ranges), skipping ROW/COLUMN arguments.
fn collect(n: Node, var out: List[Rect]) Unit:
    match n:
        NRef(c, r, ok):
            if ok:
                out.append(Rect(c1: c, r1: r, c2: c, r2: r))
        NRng(c1, r1, c2, r2, ok):
            if ok:
                out.append(norm_rect(c1, r1, c2, r2))
        NCall(name, args):
            if name != "ROW" and name != "COLUMN":
                for a in args:
                    collect(a, var out)
        NUn(_op, x):
            collect(x, var out)
        NBin(_op, l, r):
            collect(l, var out)
            collect(r, var out)
        NParen(x):
            collect(x, var out)
        _:
            return

fn rinfo(n: Node) RI:
    match n:
        NRng(c1, r1, c2, r2, ok):
            return RI(kind: 2, ok: ok, c1: c1, r1: r1, c2: c2, r2: r2)
        NRef(c, r, ok):
            return RI(kind: 1, ok: ok, c1: c, r1: r, c2: c, r2: r)
        _:
            return RI(kind: 0, ok: false, c1: 0, r1: 0, c2: 0, r2: 0)

# ---------------------------------------------------------------- formula-copy shifting

fn shift_p(p: RefP, dc: Int, dr: Int) RefP:
    let pc = p.c
    let pr = p.r
    var nc = 0
    var nr = 0
    nc = pc + dc
    nr = pr + dr
    if p.cabs:
        nc = pc
    if p.rabs:
        nr = pr
    let inside = nc >= 0 and nc <= 25 and nr >= 1 and nr <= 999
    return RefP(ok: inside, shape: true, c: nc, r: nr, cabs: p.cabs, rabs: p.rabs)

fn refstr(p: RefP) String:
    var s = ""
    if p.cabs:
        s = "$"
    s = s + ALPHA.drop(p.c).take(1)
    if p.rabs:
        s = s + "$"
    return s + p.r.to_string()

fn shift_ref_tok(text: String, dc: Int, dr: Int) String:
    let parts = text.split(":")
    if parts.length() == 1:
        let p = ref_parts(text)
        if not p.ok:
            return text.clone()
        let q = shift_p(p, dc, dr)
        if not q.ok:
            return "#REF!"
        return refstr(q)
    let a = ref_parts(parts[0])
    let b = ref_parts(parts[1])
    if not a.ok or not b.ok:
        return text.clone()
    let qa = shift_p(a, dc, dr)
    let qb = shift_p(b, dc, dr)
    if not qa.ok or not qb.ok:
        return "#REF!"
    return refstr(qa) + ":" + refstr(qb)

# raw is a formula text starting with "=".
fn shift_formula(raw: String, dc: Int, dr: Int) String:
    let cs = raw.drop(1).chars()
    let toks = lex(cs)
    for t in toks:
        if t.kind == 11:
            return raw.clone()
    var out = List[String]()
    var pos = 0
    for t in toks:
        if t.kind == 3 or t.kind == 4:
            out.append(sub(cs, pos, t.s0))
            out.append(shift_ref_tok(t.text, dc, dr))
            pos = t.s1
    out.append(sub(cs, pos, cs.length()))
    return "=" + out.join("")

# ---------------------------------------------------------------- SCC (Tarjan)

impl Scc:
    var fn visit(v: Int) Unit:
        self.idx[v] = self.counter
        self.low[v] = self.counter
        self.counter += 1
        self.stk.append(v)
        self.onst[v] = true
        var j = 0
        while j < self.succ[v].length():
            let w = self.succ[v][j]
            j += 1
            if self.idx[w] < 0:
                self.visit(w)
                if self.low[w] < self.low[v]:
                    self.low[v] = self.low[w]
            else if self.onst[w]:
                if self.idx[w] < self.low[v]:
                    self.low[v] = self.idx[w]
        if self.low[v] == self.idx[v]:
            var comp = List[Int]()
            var done = false
            while not done:
                let w = self.stk.pop().get(0)
                self.onst[w] = false
                comp.append(w)
                if w == v:
                    done = true
            self.order.append(comp)

    fn selfloop(v: Int) Bool:
        for w in self.succ[v]:
            if w == v:
                return true
        return false

# ---------------------------------------------------------------- CSV

# Records of a block; blank (whitespace-only, unquoted) records are skipped.
fn csv_parse(block: List[String]) List[List[String]]:
    let joined = block.join("\n")
    let cs = joined.chars()
    let n = cs.length()
    var recs = List[List[String]]()
    var fields = List[String]()
    var cur = List[String]()
    var inq = false
    var content = false
    var i = 0
    while i < n:
        let ch = cs[i].clone()
        if inq:
            if ch == "\"":
                if i + 1 < n and cs[i + 1] == "\"":
                    cur.append("\"")
                    i += 2
                else:
                    inq = false
                    i += 1
            else:
                cur.append(ch)
                i += 1
        else if ch == "\"":
            inq = true
            content = true
            i += 1
        else if ch == ",":
            fields.append(cur.join(""))
            cur = List[String]()
            content = true
            i += 1
        else if ch == "\n":
            fields.append(cur.join(""))
            if content:
                recs.append(fields)
            fields = List[String]()
            cur = List[String]()
            content = false
            i += 1
        else if ch == "\r":
            i += 1
        else if ch == " " or ch == "\t":
            cur.append(ch)
            i += 1
        else:
            cur.append(ch)
            content = true
            i += 1
    if content:
        fields.append(cur.join(""))
        recs.append(fields)
    return recs

fn words(s: String) List[String]:
    var out = List[String]()
    for p in s.replace("\t", " ").split(" "):
        if p != "":
            out.append(p.clone())
    return out

# First whitespace-separated word, and the rest of the line (trimmed).
fn cut(s: String) Cut:
    let t = s.trim_start()
    let cs = t.chars()
    var i = 0
    while i < cs.length() and not is_ws(cs[i]):
        i += 1
    return Cut(head: t.take(i), rest: t.drop(i).trim())

fn cell_of(s: String) Int:
    if s.contains("$"):
        return -1
    let p = ref_parts(s)
    if not p.ok:
        return -1
    return key(p.c, p.r)

fn range_of(s: String) Rect:
    let bad = Rect(c1: -1, r1: 0, c2: 0, r2: 0)
    let parts = s.split(":")
    if parts.length() == 1:
        let k = cell_of(s)
        if k < 0:
            return bad
        return Rect(c1: k % 100, r1: k / 100, c2: k % 100, r2: k / 100)
    if parts.length() == 2:
        let a = cell_of(parts[0])
        let b = cell_of(parts[1])
        if a < 0 or b < 0:
            return bad
        return norm_rect(a % 100, a / 100, b % 100, b / 100)
    return bad

fn csvq(s: String) String:
    let need = s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r") or s.starts_with(" ") or s.ends_with(" ")
    if need:
        return "\"" + s.replace("\"", "\"\"") + "\""
    return s.clone()

# ---------------------------------------------------------------- aggregate helpers

fn agg(name: String, its: List[Item]) Value:
    for it in its:
        if is_err(it.v):
            return it.v.clone()
    var nums = List[Float]()
    for it in its:
        if it.rng:
            if is_num(it.v):
                nums.append(numof(it.v))
        else:
            let c = coerce(it.v)
            if is_err(c):
                return c
            nums.append(numof(c))
    if name == "SUM":
        var s = 0.0
        for x in nums:
            s += x
        return numres(s)
    if name == "AVERAGE":
        if nums.length() == 0:
            return VErr(e: E_DIV)
        var s = 0.0
        for x in nums:
            s += x
        return numres(s / nums.length().to_float())
    if name == "PRODUCT":
        if nums.length() == 0:
            return VNum(n: 0.0)
        var p = 1.0
        for x in nums:
            p = p * x
        return numres(p)
    if name == "MIN" or name == "MAX":
        if nums.length() == 0:
            return VNum(n: 0.0)
        var m = 0.0
        m = nums[0]
        for x in nums:
            if name == "MIN" and x < m:
                m = x
            if name == "MAX" and x > m:
                m = x
        return VNum(n: m)
    # MEDIAN
    if nums.length() == 0:
        return VErr(e: E_NUM)
    nums.sort()
    let h = nums.length() / 2
    if nums.length() % 2 == 1:
        return numres(nums[h])
    return numres((nums[h - 1] + nums[h]) / 2.0)

fn countf(isnum: Bool, its: List[Item]) Value:
    var cnt = 0
    for it in its:
        if isnum:
            if is_num(it.v):
                cnt += 1
        else:
            if kind_of(it.v) != 0:
                cnt += 1
    return VNum(n: cnt.to_float())

fn logic(isand: Bool, its: List[Item]) Value:
    var any = false
    var res = isand
    for it in its:
        if is_err(it.v):
            return it.v.clone()
        if it.rng:
            let kd = kind_of(it.v)
            if kd == 0 or kd == 2:
                continue
        let b = boolco(it.v)
        if is_err(b):
            return b
        any = true
        if isand:
            res = res and getbool(b)
        else:
            res = res or getbool(b)
    if not any:
        return VErr(e: E_VALUE)
    return VBool(b: res)

fn arith(op: String, a: Value, b: Value) Value:
    let ca = coerce(a)
    if is_err(ca):
        return ca
    let cb = coerce(b)
    if is_err(cb):
        return cb
    let x = numof(ca)
    let y = numof(cb)
    if op == "+":
        return numres(x + y)
    if op == "-":
        return numres(x - y)
    if op == "*":
        return numres(x * y)
    if op == "/":
        if y == 0.0:
            return VErr(e: E_DIV)
        return numres(x / y)
    return numres(pow(x, y))

fn crit(v: Value) Crit:
    match v:
        VText(s):
            let ops = [">=", "<=", "<>", ">", "<", "="]
            for op in ops:
                if s.starts_with(op):
                    let rest = s.drop(op.length())
                    return Crit(op: op.clone(), opnd: opnd_text(rest))
            return Crit(op: "=", opnd: opnd_text(s.clone()))
        _:
            return Crit(op: "=", opnd: v.clone())

fn opnd_text(s: String) Value:
    if numgram(s):
        return VNum(n: numval(s))
    return VText(s: s.clone())

fn valuef(v: Value) Value:
    let c = coerce(v)
    if is_num(c):
        return numres(numof(c))
    return c

# ---------------------------------------------------------------- sheet evaluation

impl Sheet:
    fn val(k: Int) Value:
        if let v = self.valm.get(k):
            return v
        return VEmpty

    fn depends(fk: Int, x: Int) Bool:
        if let rs = self.depm.get(fk):
            return covers(rs, x)
        return false

    fn items(args: List[Node]) List[Item]:
        var out = List[Item]()
        for a in args:
            match a:
                NRng(c1, r1, c2, r2, ok):
                    if not ok:
                        out.append(Item(v: VErr(e: E_REF), rng: false))
                    else:
                        let rc = norm_rect(c1, r1, c2, r2)
                        var r = 0
                        r = rc.r1
                        while r <= rc.r2:
                            var c = 0
                            c = rc.c1
                            while c <= rc.c2:
                                out.append(Item(v: self.val(key(c, r)), rng: true))
                                c += 1
                            r += 1
                _:
                    out.append(Item(v: self.ev(a), rng: false))
        return out

    fn ev(n: Node) Value:
        match n:
            NLit(v):
                return v.clone()
            NRef(c, r, ok):
                if not ok:
                    return VErr(e: E_REF)
                return self.val(key(c, r))
            NRng(_c1, _r1, _c2, _r2, ok):
                if not ok:
                    return VErr(e: E_REF)
                return VErr(e: E_VALUE)
            NName(_nm):
                return VErr(e: E_NAME)
            NCall(name, args):
                return self.callf(name, args)
            NUn(op, x):
                return self.unary(op, x)
            NBin(op, l, r):
                return self.binop(op, l, r)
            NParen(x):
                return self.ev(x)
            NBad:
                return VErr(e: E_PARSE)

    fn unary(op: String, x: Node) Value:
        let c = coerce(self.ev(x))
        if is_err(c):
            return c
        if op == "-":
            return numres(-numof(c))
        return c

    fn binop(op: String, l: Node, r: Node) Value:
        let a = self.ev(l)
        let b = self.ev(r)
        if op == "&":
            if is_err(a):
                return a
            if is_err(b):
                return b
            return VText(s: sf(a) + sf(b))
        if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
            if is_err(a):
                return a
            if is_err(b):
                return b
            return VBool(b: opholds(op, cmp3(a, b)))
        return arith(op, a, b)

    fn callf(name: String, args: List[Node]) Value:
        let na = args.length()
        if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN":
            if na == 0:
                return VErr(e: E_VALUE)
            return agg(name, self.items(args))
        if name == "COUNT" or name == "COUNTA":
            if na == 0:
                return VErr(e: E_VALUE)
            return countf(name == "COUNT", self.items(args))
        if name == "AND" or name == "OR":
            if na == 0:
                return VErr(e: E_VALUE)
            return logic(name == "AND", self.items(args))
        if name == "CONCAT":
            if na == 0:
                return VErr(e: E_VALUE)
            var s = ""
            for it in self.items(args):
                if is_err(it.v):
                    return it.v.clone()
                s = s + sf(it.v)
            return VText(s: s)
        if name == "IF":
            if na < 2 or na > 3:
                return VErr(e: E_VALUE)
            let c = boolco(self.ev(args[0]))
            if is_err(c):
                return c
            if getbool(c):
                return self.ev(args[1])
            if na == 3:
                return self.ev(args[2])
            return VBool(b: false)
        if name == "IFERROR":
            if na != 2:
                return VErr(e: E_VALUE)
            let a = self.ev(args[0])
            if is_err(a):
                return self.ev(args[1])
            return a
        if name == "CHOOSE":
            if na < 2:
                return VErr(e: E_VALUE)
            let c = coerce(self.ev(args[0]))
            if is_err(c):
                return c
            let f = floor_int(numof(c))
            if f < 1 or f >= na:
                return VErr(e: E_VALUE)
            return self.ev(args[f])
        if name == "NOT":
            if na != 1:
                return VErr(e: E_VALUE)
            let b = boolco(self.ev(args[0]))
            if is_err(b):
                return b
            return VBool(b: not getbool(b))
        if name == "ABS" or name == "INT" or name == "SQRT":
            if na != 1:
                return VErr(e: E_VALUE)
            let c = coerce(self.ev(args[0]))
            if is_err(c):
                return c
            let x = numof(c)
            if name == "ABS":
                return numres(x.abs())
            if name == "INT":
                return numres(floor(x))
            if x < 0.0:
                return VErr(e: E_NUM)
            return numres(sqrt(x))
        if name == "POW":
            if na != 2:
                return VErr(e: E_VALUE)
            return arith("^", self.ev(args[0]), self.ev(args[1]))
        if name == "MOD":
            if na != 2:
                return VErr(e: E_VALUE)
            let ca = coerce(self.ev(args[0]))
            if is_err(ca):
                return ca
            let cb = coerce(self.ev(args[1]))
            if is_err(cb):
                return cb
            let x = numof(ca)
            let y = numof(cb)
            if y == 0.0:
                return VErr(e: E_DIV)
            return numres(x - y * floor(x / y))
        if name == "ROUND":
            return self.roundf(args)
        if name == "LEN" or name == "UPPER" or name == "LOWER" or name == "TRIM":
            if na != 1:
                return VErr(e: E_VALUE)
            let v = self.ev(args[0])
            if is_err(v):
                return v
            let s = sf(v)
            if name == "LEN":
                return numres(s.scalar_length().to_float())
            if name == "UPPER":
                return VText(s: ascii_upper(s))
            if name == "LOWER":
                return VText(s: ascii_lower(s))
            return VText(s: collapse(s))
        if name == "LEFT" or name == "RIGHT":
            return self.leftright(name == "LEFT", args)
        if name == "MID":
            if na != 3:
                return VErr(e: E_VALUE)
            let sv = self.ev(args[0])
            if is_err(sv):
                return sv
            let c1 = coerce(self.ev(args[1]))
            if is_err(c1):
                return c1
            let c2 = coerce(self.ev(args[2]))
            if is_err(c2):
                return c2
            let start = floor_int(numof(c1))
            let len = floor_int(numof(c2))
            if start < 1 or len < 0:
                return VErr(e: E_VALUE)
            return VText(s: sf(sv).drop(start - 1).take(len))
        if name == "SUBSTITUTE":
            if na != 3:
                return VErr(e: E_VALUE)
            let v1 = self.ev(args[0])
            if is_err(v1):
                return v1
            let v2 = self.ev(args[1])
            if is_err(v2):
                return v2
            let v3 = self.ev(args[2])
            if is_err(v3):
                return v3
            let s = sf(v1)
            let old = sf(v2)
            let nw = sf(v3)
            if old == "":
                return VText(s: s)
            return VText(s: s.replace(old, nw))
        if name == "VALUE":
            if na != 1:
                return VErr(e: E_VALUE)
            return valuef(self.ev(args[0]))
        if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
            if na != 1:
                return VErr(e: E_VALUE)
            let v = self.ev(args[0])
            if name == "ISERROR":
                return VBool(b: is_err(v))
            if name == "ISBLANK":
                return VBool(b: kind_of(v) == 0)
            if name == "ISNUMBER":
                return VBool(b: is_num(v))
            return VBool(b: kind_of(v) == 2)
        if name == "ROW" or name == "COLUMN":
            if na != 1:
                return VErr(e: E_VALUE)
            let ri = rinfo(args[0])
            if ri.kind == 0:
                return VErr(e: E_VALUE)
            if not ri.ok:
                return VErr(e: E_REF)
            if name == "ROW":
                return VNum(n: ri.r1.to_float())
            return VNum(n: (ri.c1 + 1).to_float())
        if name == "INDEX":
            return self.indexf(args)
        if name == "COUNTIF":
            return self.countif(args)
        return VErr(e: E_NAME)

    fn roundf(args: List[Node]) Value:
        let na = args.length()
        if na < 1 or na > 2:
            return VErr(e: E_VALUE)
        let x = coerce(self.ev(args[0]))
        if is_err(x):
            return x
        var d = 0.0
        if na == 2:
            let dc = coerce(self.ev(args[1]))
            if is_err(dc):
                return dc
            d = numof(dc)
        let dt = trunc_f(d)
        if dt.abs() > 15.0:
            return VErr(e: E_NUM)
        let p = pow(10.0, dt)
        let y = numof(x) * p
        if not y.is_finite():
            return VErr(e: E_NUM)
        return numres(round_half(y) / p)

    fn leftright(isleft: Bool, args: List[Node]) Value:
        let na = args.length()
        if na < 1 or na > 2:
            return VErr(e: E_VALUE)
        let sv = self.ev(args[0])
        if is_err(sv):
            return sv
        var n = 1
        if na == 2:
            let c = coerce(self.ev(args[1]))
            if is_err(c):
                return c
            n = floor_int(numof(c))
        if n < 0:
            return VErr(e: E_VALUE)
        let s = sf(sv)
        if isleft:
            return VText(s: s.take(n))
        return VText(s: s.drop(imax(0, s.scalar_length() - n)))

    fn indexf(args: List[Node]) Value:
        let na = args.length()
        if na < 2 or na > 3:
            return VErr(e: E_VALUE)
        let ri = rinfo(args[0])
        if ri.kind != 2:
            return VErr(e: E_VALUE)
        if not ri.ok:
            return VErr(e: E_REF)
        let top = imin(ri.r1, ri.r2)
        let bottom = imax(ri.r1, ri.r2)
        let left = imin(ri.c1, ri.c2)
        let right = imax(ri.c1, ri.c2)
        let rows = bottom - top + 1
        let cols = right - left + 1
        let rv = coerce(self.ev(args[1]))
        if is_err(rv):
            return rv
        let rr = floor_int(numof(rv))
        var rowi = rr
        var coli = 1
        if na == 2:
            if rows == 1:
                rowi = 1
                coli = rr
        else:
            let cv = coerce(self.ev(args[2]))
            if is_err(cv):
                return cv
            coli = floor_int(numof(cv))
        if rowi < 1 or rowi > rows or coli < 1 or coli > cols:
            return VErr(e: E_REF)
        return self.val(key(left + coli - 1, top + rowi - 1))

    fn countif(args: List[Node]) Value:
        if args.length() != 2:
            return VErr(e: E_VALUE)
        let ri = rinfo(args[0])
        if ri.kind != 2:
            return VErr(e: E_VALUE)
        if not ri.ok:
            return VErr(e: E_REF)
        let cv = self.ev(args[1])
        if is_err(cv):
            return cv
        let cr = crit(cv)
        let rc = norm_rect(ri.c1, ri.r1, ri.c2, ri.r2)
        var cnt = 0
        var r = 0
        r = rc.r1
        while r <= rc.r2:
            var c = 0
            c = rc.c1
            while c <= rc.c2:
                let v = self.val(key(c, r))
                if kind_of(v) == kind_of(cr.opnd):
                    if opholds(cr.op, cmp3(v, cr.opnd)):
                        cnt += 1
                else if cr.op == "<>" and kind_of(v) != 0:
                    cnt += 1
                c += 1
            r += 1
        return VNum(n: cnt.to_float())

    # Value of a formula cell: empty result becomes 0; non-finite numbers are #NUM!.
    fn topv(ast: Node) Value:
        let v = self.ev(ast)
        if kind_of(v) == 0:
            return VNum(n: 0.0)
        if is_num(v):
            if not numof(v).is_finite():
                return VErr(e: E_NUM)
        return v

    # ------------------------------------------------------------ mutation

    var fn emit(s: String) Unit:
        self.out.append(s)

    # Stores raw (already trimmed VALUE) into cell k, classifying it.
    var fn assign(k: Int, text: String) Unit:
        if text == "":
            self.rawm.remove(k)
            self.valm.remove(k)
            self.formm.remove(k)
            self.depm.remove(k)
            return
        if text.starts_with("="):
            let ast = parse_formula(text.drop(1))
            var rs = List[Rect]()
            collect(ast, var rs)
            self.rawm[k] = text.clone()
            self.formm[k] = ast
            self.depm[k] = rs
            self.valm.remove(k)
            return
        self.formm.remove(k)
        self.depm.remove(k)
        self.rawm[k] = text.clone()
        if text.starts_with("'"):
            self.valm[k] = VText(s: text.drop(1))
            return
        if numgram(text):
            let x = numval(text)
            if x.is_finite():
                self.valm[k] = VNum(n: x)
                return
        let up = text.upper()
        if up == "TRUE":
            self.valm[k] = VBool(b: true)
            return
        if up == "FALSE":
            self.valm[k] = VBool(b: false)
            return
        self.valm[k] = VText(s: text.clone())

    # Recalculates the affected formula cells after the given cells changed.
    # Returns the number of affected formula cells.
    var fn recalc(changed: List[Int]) Int:
        # Index of formula cells by the cells of their precedent rectangles.
        # Narrow rectangles are expanded into a linked list per cell; wide ones are checked directly.
        var fl = List[Int]()
        var fr = List[List[Rect]]()
        var wide = List[Int]()
        var head = Map[Int, Int]()
        var nxt = List[Int]()
        var ent = List[Int]()
        for fk in self.depm.keys():
            if let rs = self.depm.get(fk):
                let fi = fl.length()
                fl.append(fk)
                for rc in rs:
                    let area = (rc.c2 - rc.c1 + 1) * (rc.r2 - rc.r1 + 1)
                    if area > NARROW:
                        wide.append(fi)
                    else:
                        var r = 0
                        r = rc.r1
                        while r <= rc.r2:
                            var c = 0
                            c = rc.c1
                            while c <= rc.c2:
                                let k = key(c, r)
                                var h = -1
                                if let hh = head.get(k):
                                    h = hh
                                ent.append(fi)
                                nxt.append(h)
                                head[k] = ent.length() - 1
                                c += 1
                            r += 1
                fr.append(rs)

        var affected = List[Int]()
        var inA = Set[Int]()
        var queue = List[Int]()
        for k in changed:
            if self.formm.contains(k) and not inA.contains(k):
                inA.add(k)
                affected.append(k)
            queue.append(k)
        var qi = 0
        while qi < queue.length():
            let x = queue[qi]
            qi += 1
            var cand = List[Int]()
            var e = -1
            if let hh = head.get(x):
                e = hh
            while e >= 0:
                cand.append(ent[e])
                e = nxt[e]
            for fi in wide:
                if covers(fr[fi], x):
                    cand.append(fi)
            for fi in cand:
                let fk = fl[fi]
                if not inA.contains(fk):
                    inA.add(fk)
                    affected.append(fk)
                    queue.append(fk)

        let n = affected.length()
        var apos = Map[Int, Int]()
        for i in 0..n:
            apos[affected[i]] = i
        # Edges: node i depends on node j when some precedent rectangle of i contains affected[j].
        var succ = List[List[Int]]()
        var i = 0
        while i < n:
            var lst = List[Int]()
            if let rs = self.depm.get(affected[i]):
                for rc in rs:
                    let area = (rc.c2 - rc.c1 + 1) * (rc.r2 - rc.r1 + 1)
                    if area <= n:
                        var r = 0
                        r = rc.r1
                        while r <= rc.r2:
                            var c = 0
                            c = rc.c1
                            while c <= rc.c2:
                                if let p = apos.get(key(c, r)):
                                    lst.append(p)
                                c += 1
                            r += 1
                    else:
                        var j = 0
                        while j < n:
                            if in_rect(rc, affected[j]):
                                lst.append(j)
                            j += 1
            succ.append(lst)
            i += 1

        var idx = List[Int]()
        var low = List[Int]()
        var onst = List[Bool]()
        for _i in 0..n:
            idx.append(-1)
            low.append(0)
            onst.append(false)
        var st = Scc(succ: succ, idx: idx, low: low, onst: onst, stk: List[Int](), counter: 0, order: List[List[Int]]())
        for v in 0..n:
            if st.idx[v] < 0:
                st.visit(v)
        for comp in st.order:
            if comp.length() == 1 and not st.selfloop(comp[0]):
                let k = affected[comp[0]]
                if let f = self.formm.get(k):
                    let res = self.topv(f)
                    self.valm[k] = res
            else:
                for v in comp:
                    self.valm[affected[v]] = VErr(e: E_CYCLE)
        self.evals += n
        return n

    var fn setcmd(rest: String) Unit:
        if rest == "":
            self.emit("error: usage: set CELL VALUE")
            return
        let c2 = cut(rest)
        let k = cell_of(c2.head)
        if k < 0:
            self.emit("error: bad cell reference '" + c2.head + "'")
            return
        self.assign(k, c2.rest)
        let n = self.recalc([k])
        self.emit("recalc " + n.to_string())

    var fn copyf(sk: Int, dr: Rect) Unit:
        var srctext = ""
        if let s = self.rawm.get(sk):
            srctext = s
        let sc = sk % 100
        let sr = sk / 100
        var changed = List[Int]()
        var r = 0
        r = dr.r1
        while r <= dr.r2:
            var c = 0
            c = dr.c1
            while c <= dr.c2:
                let k = key(c, r)
                if srctext.starts_with("="):
                    self.assign(k, shift_formula(srctext, c - sc, r - sr))
                else:
                    self.assign(k, srctext)
                changed.append(k)
                c += 1
            r += 1
        let n = self.recalc(changed)
        self.emit("recalc " + n.to_string())

    var fn do_import(argline: String, block: List[String]) Unit:
        let recs = csv_parse(block)
        let args = words(argline)
        if args.length() != 1:
            self.emit("error: usage: import CELL")
            return
        let k = cell_of(args[0])
        if k < 0:
            self.emit("error: bad cell reference '" + args[0] + "'")
            return
        let r0 = k / 100
        let c0 = k % 100
        var ncol = 0
        for rec in recs:
            ncol = imax(ncol, rec.length())
        let nrec = recs.length()
        if c0 + ncol - 1 > 25 or r0 + nrec - 1 > 999:
            self.emit("error: import out of range")
            return
        var changed = List[Int]()
        var r = 0
        for rec in recs:
            var c = 0
            for f in rec:
                let kk = key(c0 + c, r0 + r)
                self.assign(kk, f.trim())
                changed.append(kk)
                c += 1
            r += 1
        let n = self.recalc(changed)
        self.emit("imported " + nrec.to_string() + " rows, " + ncol.to_string() + " columns; recalc " + n.to_string())

    # ------------------------------------------------------------ reporting

    fn disp(k: Int) String:
        return sf(self.val(k))

    fn show(k: Int) String:
        let nm = cname(k)
        if let raw = self.rawm.get(k):
            if self.formm.contains(k):
                return nm + ": " + raw + " => " + self.disp(k)
            return nm + ": " + raw
        return nm + ": (empty)"

    fn names_of(st: Set[Int]) String:
        var ks = st.values()
        ks.sort()
        var parts = List[String]()
        for k in ks:
            parts.append(cname(k))
        if parts.length() == 0:
            return "(none)"
        return parts.join(" ")

    fn precs(k: Int) String:
        if not self.formm.contains(k):
            return "(none)"
        var st = Set[Int]()
        if let rs = self.depm.get(k):
            for rc in rs:
                var r = 0
                r = rc.r1
                while r <= rc.r2:
                    var c = 0
                    c = rc.c1
                    while c <= rc.c2:
                        st.add(key(c, r))
                        c += 1
                    r += 1
        return self.names_of(st)

    fn dependents(k: Int) String:
        var seen = Set[Int]()
        var queue = List[Int]()
        queue.append(k)
        var qi = 0
        while qi < queue.length():
            let x = queue[qi]
            qi += 1
            for fk in self.depm.keys():
                if not seen.contains(fk) and self.depends(fk, x):
                    seen.add(fk)
                    queue.append(fk)
        return self.names_of(seen)

    # Default range: A1 to the largest column and row among non-empty cells.
    fn default_range() Rect:
        var maxc = 0
        var maxr = 1
        for k in self.rawm.keys():
            maxc = imax(maxc, k % 100)
            maxr = imax(maxr, k / 100)
        return Rect(c1: 0, r1: 1, c2: maxc, r2: maxr)

    var fn printr(rc: Rect) Unit:
        var r = 0
        r = rc.r1
        while r <= rc.r2:
            var parts = List[String]()
            var c = 0
            c = rc.c1
            while c <= rc.c2:
                parts.append(self.disp(key(c, r)))
                c += 1
            self.emit(parts.join(" | "))
            r += 1

    var fn exportr(rc: Rect, formulas: Bool) Unit:
        var r = 0
        r = rc.r1
        while r <= rc.r2:
            var parts = List[String]()
            var c = 0
            c = rc.c1
            while c <= rc.c2:
                let k = key(c, r)
                var field = ""
                if formulas:
                    if let s = self.rawm.get(k):
                        field = csvq(s)
                else:
                    field = csvq(self.disp(k))
                parts.append(field)
                c += 1
            self.emit(parts.join(","))
            r += 1

    var fn stats() Unit:
        self.emit("cells " + self.rawm.length().to_string() + " formulas " + self.formm.length().to_string() + " evals " + self.evals.to_string())

    # ------------------------------------------------------------ dispatch

    var fn exec(line: String) Unit:
        let c = cut(line)
        let cmd = c.head
        let rest = c.rest
        let args = words(rest)
        if cmd == "set":
            self.setcmd(rest)
            return
        if cmd == "get" or cmd == "show" or cmd == "clear" or cmd == "precedents" or cmd == "dependents":
            if args.length() != 1:
                self.emit("error: usage: " + cmd + " CELL")
                return
            let k = cell_of(args[0])
            if k < 0:
                self.emit("error: bad cell reference '" + args[0] + "'")
                return
            if cmd == "get":
                if self.rawm.contains(k):
                    self.emit(self.disp(k))
                else:
                    self.emit("(empty)")
            else if cmd == "show":
                self.emit(self.show(k))
            else if cmd == "clear":
                self.assign(k, "")
                let n = self.recalc([k])
                self.emit("recalc " + n.to_string())
            else if cmd == "precedents":
                self.emit(self.precs(k))
            else:
                self.emit(self.dependents(k))
            return
        if cmd == "copy":
            if args.length() != 2:
                self.emit("error: usage: copy SRC DST")
                return
            let sk = cell_of(args[0])
            if sk < 0:
                self.emit("error: bad cell reference '" + args[0] + "'")
                return
            let dr = range_of(args[1])
            if dr.c1 < 0:
                self.emit("error: bad range '" + args[1] + "'")
                return
            self.copyf(sk, dr)
            return
        if cmd == "print":
            if args.length() > 1 or (args.length() == 1 and args[0] == "formulas"):
                self.emit("error: usage: print [RANGE]")
                return
            if args.length() == 0:
                if self.rawm.length() == 0:
                    self.emit("(empty sheet)")
                    return
                self.printr(self.default_range())
                return
            let rc = range_of(args[0])
            if rc.c1 < 0:
                self.emit("error: bad range '" + args[0] + "'")
                return
            self.printr(rc)
            return
        if cmd == "export":
            var formulas = false
            var modes = 0
            var nr = 0
            var rng = ""
            for a in args:
                if a == "formulas":
                    formulas = true
                    modes += 1
                else if a == "values":
                    formulas = false
                    modes += 1
                else:
                    rng = a.clone()
                    nr += 1
            if modes > 1 or nr > 1:
                self.emit("error: usage: export [formulas] [RANGE]")
                return
            var rc = Rect(c1: 0, r1: 1, c2: 0, r2: 1)
            if nr == 0:
                if self.rawm.length() == 0:
                    self.emit("(empty sheet)")
                    return
                rc = self.default_range()
            else:
                rc = range_of(rng)
                if rc.c1 < 0:
                    self.emit("error: bad range '" + rng + "'")
                    return
            self.exportr(rc, formulas)
            return
        if cmd == "stats":
            self.stats()
            return
        self.emit("error: unknown command '" + cmd + "'")

    var fn do_line(line: String) Unit:
        self.exec(line)

# ---------------------------------------------------------------- main

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var sh = Sheet(rawm: Map[Int, String](), valm: Map[Int, Value](), formm: Map[Int, Node](), depm: Map[Int, List[Rect]](), evals: 0, out: List[String]())
    var i = 0
    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1
        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue
        sh.emit("> " + line)
        let c = cut(line)
        if c.head == "import":
            var block = List[String]()
            var done = false
            while not done:
                if i >= lines.length():
                    done = true
                else if lines[i] == ".":
                    i += 1
                    done = true
                else:
                    block.append(lines[i].clone())
                    i += 1
            sh.do_import(c.rest, block)
        else:
            sh.do_line(line)
    if sh.out.length() > 0:
        stdout().write(sh.out.join("\n") + "\n").get()
    return 0
