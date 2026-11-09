import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import big_float_of_float from "@std/math/big.ms"
import pow, floor, truncate, sqrt from "@std/math/math.ms"

let UPPER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let LOWER_LETTERS = "abcdefghijklmnopqrstuvwxyz"
let DIGITS = "0123456789"
let CMP_OPS = ["=", "<>", "<", "<=", ">", ">="]

enum Value:
    VE
    VNum(n: Float)
    VText(s: String)
    VBool(b: Bool)
    VErr(e: String)

enum Node:
    NNum(v: Float)
    NStr(s: String)
    NBool(b: Bool)
    NErrK(e: String)
    NRef(c: Int, r: Int, good: Bool)
    NRng(c1: Int, r1: Int, c2: Int, r2: Int, good: Bool)
    NName
    NCall(name: String, args: List[Node])
    NUn(op: String, xs: List[Node])
    NBin(op: String, xs: List[Node])

type Tok:
    kind: String
    text: String
    num: Float
    c1: Int
    r1: Int
    c2: Int
    r2: Int
    good: Bool

type PS:
    toks: List[Tok]
    pos: Int
    bad: Bool

type Form:
    ast: Node
    perr: Bool
    precs: List[Int]

type Sheet:
    raws: Map[Int, String]
    vals: Map[Int, Value]
    forms: Map[Int, Form]
    deps: Map[Int, Set[Int]]
    evals: Int

type Item:
    v: Value
    rng: Bool

type NumsR:
    bad: Bool
    err: Value
    nums: List[Float]

type RS:
    stop: Int
    c: Int
    r: Int
    good: Bool
    dc: Bool
    dr: Bool

type CellR:
    good: Bool
    c: Int
    r: Int

type RangeR:
    good: Bool
    c1: Int
    r1: Int
    c2: Int
    r2: Int

type OpR:
    op: String
    rest: String

type TJ:
    idx: Map[Int, Int]
    low: Map[Int, Int]
    on: Set[Int]
    stk: List[Int]
    cnt: Int
    comps: List[List[Int]]

// ---------- character and text helpers ----------

fn is_letter(c: String) Bool:
    if c == "":
        return false
    return UPPER_LETTERS.contains(c) or LOWER_LETTERS.contains(c)

fn is_digit(c: String) Bool:
    if c == "":
        return false
    return DIGITS.contains(c)

fn is_ident(c: String) Bool:
    return is_letter(c) or is_digit(c) or c == "_" or c == "."

fn is_ws(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn digit_val(c: String) Int:
    return DIGITS.index_of(c).get(0)

fn upper(s: String) String:
    var out = ""
    for c in s.chars():
        let k = LOWER_LETTERS.index_of(c).get(-1)
        if k >= 0:
            out += UPPER_LETTERS.get(k, c)
        else:
            out += c
    return out

fn colnum(c: String) Int:
    return UPPER_LETTERS.index_of(upper(c)).get(-1) + 1

fn colname(c: Int) String:
    return UPPER_LETTERS.get(c - 1, "?")

fn join_cs(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var i = a
    while i < b:
        out += cs[i]
        i += 1
    return out

fn collapse(s: String) String:
    var out = ""
    var pend = false
    for c in s.chars():
        if is_ws(c):
            pend = true
        else:
            if pend and out != "":
                out += " "
            pend = false
            out += c
    return out

fn split_words(t: String) List[String]:
    var out = List[String]()
    var cur = ""
    for c in t.chars():
        if is_ws(c):
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur += c
    if cur != "":
        out.append(cur)
    return out

// Text after skipping `skip` whitespace-separated words of an already-trimmed line.
fn rest_after(t: String, skip: Int) String:
    let cs = t.chars()
    let n = cs.length()
    var i = 0
    var k = 0
    while k < skip:
        while i < n and is_ws(cs[i]):
            i += 1
        while i < n and not is_ws(cs[i]):
            i += 1
        k += 1
    return join_cs(cs, i, n).trim()

fn key_of(c: Int, r: Int) Int:
    return r * 100 + c

fn key_row(k: Int) Int:
    return k / 100

fn key_col(k: Int) Int:
    return k % 100

fn cell_name(k: Int) String:
    return "{colname(key_col(k))}{key_row(k)}"

fn imin(a: Int, b: Int) Int:
    if a < b:
        return a
    return b

fn imax(a: Int, b: Int) Int:
    if a > b:
        return a
    return b

// ---------- numbers ----------

// Scans an unsigned numeric literal at i; returns the exclusive end or -1.
fn scan_num(cs: List[String], i: Int) Int:
    let n = cs.length()
    var j = i
    var nd = 0
    while j < n and is_digit(cs[j]):
        j += 1
        nd += 1
    if j < n and cs[j] == ".":
        var k = j + 1
        var nf = 0
        while k < n and is_digit(cs[k]):
            k += 1
            nf += 1
        if nd == 0 and nf == 0:
            return -1
        j = k
    else if nd == 0:
        return -1
    if j < n and (cs[j] == "e" or cs[j] == "E"):
        var k = j + 1
        if k < n and (cs[k] == "+" or cs[k] == "-"):
            k += 1
        var ne = 0
        while k < n and is_digit(cs[k]):
            k += 1
            ne += 1
        if ne > 0:
            j = k
    return j

// Whole text matches [+-]? number grammar.
fn full_num(cs: List[String]) Bool:
    let n = cs.length()
    var i = 0
    if n > 0 and (cs[0] == "+" or cs[0] == "-"):
        i = 1
    if i >= n:
        return false
    return scan_num(cs, i) == n

// Parses number text (grammar already checked), allowing forms like "5." and ".5".
fn num_from_chars(cs: List[String]) Float?:
    var out = ""
    let n = cs.length()
    for i in 0..n:
        let c = cs[i]
        if c == ".":
            if i == 0:
                out += "0"
            else if not is_digit(cs[i - 1]):
                out += "0"
            out += "."
            if i + 1 >= n:
                out += "0"
            else if not is_digit(cs[i + 1]):
                out += "0"
        else:
            out += c
    return out.parse_float()

fn fmt_num(x: Float) String:
    if x == 0.0:
        return "0"
    if not x.is_finite():
        return "#NUM!"
    var t = big_float_of_float(x, 53).get().to_fixed(10).get()
    if t.contains("."):
        t = t.trim_end_chars("0")
        t = t.trim_end_chars(".")
    if t == "-0":
        return "0"
    return t

fn finite(x: Float) Value:
    if x.is_finite():
        return Value.VNum(x)
    return Value.VErr("#NUM!")

fn is_err(v: Value) Bool:
    match v:
        VErr(_):
            return true
        _:
            return false

fn is_empty(v: Value) Bool:
    match v:
        VE:
            return true
        _:
            return false

fn is_num(v: Value) Bool:
    match v:
        VNum(_):
            return true
        _:
            return false

fn is_text(v: Value) Bool:
    match v:
        VText(_):
            return true
        _:
            return false

fn fv(v: Value) Float:
    match v:
        VNum(x):
            return x
        _:
            return 0.0

fn bv(v: Value) Bool:
    match v:
        VBool(b):
            return b
        _:
            return false

fn str_of(v: Value) String:
    match v:
        VE:
            return ""
        VNum(x):
            return fmt_num(x)
        VText(s):
            return s.clone()
        VBool(b):
            if b:
                return "TRUE"
            return "FALSE"
        VErr(e):
            return e.clone()

// Number coercion: VNum or VErr.
fn text_num(s: String) Value:
    let cs = s.trim().chars()
    if not full_num(cs):
        return Value.VErr("#VALUE!")
    if let x = num_from_chars(cs):
        return finite(x)
    return Value.VErr("#NUM!")

fn num_of(v: Value) Value:
    match v:
        VNum(x):
            return Value.VNum(x)
        VE:
            return Value.VNum(0.0)
        VBool(b):
            if b:
                return Value.VNum(1.0)
            return Value.VNum(0.0)
        VText(s):
            return text_num(s)
        VErr(e):
            return Value.VErr(e)

// Boolean coercion: VBool or VErr.
fn bool_of(v: Value) Value:
    match v:
        VBool(b):
            return Value.VBool(b)
        VNum(x):
            return Value.VBool(x != 0.0)
        VE:
            return Value.VBool(false)
        VText(s):
            let u = upper(s)
            if u == "TRUE":
                return Value.VBool(true)
            if u == "FALSE":
                return Value.VBool(false)
            return Value.VErr("#VALUE!")
        VErr(e):
            return Value.VErr(e)

fn zero_like(v: Value) Value:
    match v:
        VNum(_):
            return Value.VNum(0.0)
        VText(_):
            return Value.VText("")
        VBool(_):
            return Value.VBool(false)
        _:
            return Value.VE

fn rank(v: Value) Int:
    match v:
        VNum(_):
            return 0
        VText(_):
            return 1
        VBool(_):
            return 2
        _:
            return -1

fn cmp_same(a: Value, b: Value) Int:
    match a:
        VNum(x):
            let y = fv(b)
            if x < y:
                return -1
            if x > y:
                return 1
            return 0
        VText(s):
            let t = str_of(b)
            if s < t:
                return -1
            if s > t:
                return 1
            return 0
        VBool(p):
            let q = bv(b)
            if p == q:
                return 0
            if q:
                return -1
            return 1
        _:
            return 0

fn cmp_vals(a0: Value, b0: Value) Int:
    if is_empty(a0) and is_empty(b0):
        return 0
    var a = a0
    var b = b0
    if is_empty(a):
        a = zero_like(b)
    if is_empty(b):
        b = zero_like(a)
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb:
        if ra < rb:
            return -1
        return 1
    return cmp_same(a, b)

fn holds(op: String, c: Int) Bool:
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

fn type_code(v: Value) Int:
    match v:
        VE:
            return 0
        VNum(_):
            return 1
        VText(_):
            return 2
        VBool(_):
            return 3
        VErr(_):
            return 4

// ---------- lexer ----------

// Scans a cell reference at i (optional $, letters, optional $, digits).
fn scan_ref(cs: List[String], i: Int) RS:
    let n = cs.length()
    var p = i
    var dc = false
    var dr = false
    if p < n and cs[p] == "$":
        dc = true
        p += 1
    let ls = p
    while p < n and is_letter(cs[p]):
        p += 1
    let nl = p - ls
    if nl == 0:
        return RS(stop: -1, c: 0, r: 0, good: false, dc: false, dr: false)
    if p < n and cs[p] == "$":
        dr = true
        p += 1
    let ds = p
    while p < n and is_digit(cs[p]):
        p += 1
    let nd = p - ds
    if nd == 0:
        return RS(stop: -1, c: 0, r: 0, good: false, dc: false, dr: false)
    if p < n and (is_ident(cs[p]) or cs[p] == "(" or cs[p] == "$"):
        return RS(stop: -1, c: 0, r: 0, good: false, dc: false, dr: false)
    var r = 0
    if nd <= 3:
        for k in ds..p:
            r = r * 10 + digit_val(cs[k])
    let good = nl == 1 and nd <= 3 and cs[ds] != "0" and r >= 1 and r <= 999
    return RS(stop: p, c: colnum(cs[ls]), r: r, good: good, dc: dc, dr: dr)

fn ref_tok(cs: List[String], i: Int, rs: RS) Tok:
    var t = Tok(kind: "ref", text: join_cs(cs, i, rs.stop), num: 0.0, c1: rs.c, r1: rs.r, c2: 0, r2: 0, good: rs.good)
    return t

fn lex(src: String) List[Tok]:
    let cs = src.chars()
    let n = cs.length()
    var out = List[Tok]()
    var i = 0
    while i < n:
        let c = cs[i].clone()
        if c == " " or c == "\t":
            i += 1
        else if c == "\"":
            var buf = ""
            var j = i + 1
            var closed = false
            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        buf += "\""
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    buf += cs[j]
                    j += 1
            if closed:
                out.append(Tok(kind: "str", text: buf, num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
            else:
                out.append(Tok(kind: "bad", text: "\"", num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: false))
            i = j
        else if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
            let e = scan_num(cs, i)
            let txt = join_cs(cs, i, e)
            if let v = num_from_chars(txt.chars()):
                out.append(Tok(kind: "num", text: txt, num: v, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
            else:
                out.append(Tok(kind: "bad", text: txt, num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: false))
            i = e
        else if c == "<" or c == ">" or c == "=" or c == "+" or c == "-" or c == "*" or c == "/" or c == "^" or c == "&":
            var op = c.clone()
            if i + 1 < n:
                let d = cs[i + 1]
                if (c == "<" and d == "=") or (c == ">" and d == "=") or (c == "<" and d == ">"):
                    op = "{c}{d}"
            out.append(Tok(kind: "op", text: op.clone(), num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
            i += op.scalar_length()
        else if c == "(" or c == ")" or c == ",":
            out.append(Tok(kind: c.clone(), text: c.clone(), num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
            i += 1
        else if c == "#":
            let b = imin(i + 5, n)
            if join_cs(cs, i, b) == "#REF!":
                out.append(Tok(kind: "err", text: "#REF!", num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
                i = b
            else:
                out.append(Tok(kind: "bad", text: "#", num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: false))
                i += 1
        else if c == "$" or is_letter(c) or c == "_":
            let rs = scan_ref(cs, i)
            if rs.stop >= 0:
                var handled = false
                if rs.stop < n and cs[rs.stop] == ":":
                    let rs2 = scan_ref(cs, rs.stop + 1)
                    if rs2.stop >= 0:
                        out.append(Tok(kind: "rng", text: join_cs(cs, i, rs2.stop), num: 0.0, c1: rs.c, r1: rs.r, c2: rs2.c, r2: rs2.r, good: rs.good and rs2.good))
                        i = rs2.stop
                        handled = true
                if not handled:
                    out.append(ref_tok(cs, i, rs))
                    i = rs.stop
            else if c == "$":
                out.append(Tok(kind: "bad", text: "$", num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: false))
                i += 1
            else:
                var j = i
                while j < n and is_ident(cs[j]):
                    j += 1
                let name = join_cs(cs, i, j)
                if j < n and cs[j] == "(":
                    out.append(Tok(kind: "fn", text: name, num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
                else:
                    out.append(Tok(kind: "id", text: name, num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
                i = j
        else:
            out.append(Tok(kind: "bad", text: c.clone(), num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: false))
            i += 1
    out.append(Tok(kind: "end", text: "", num: 0.0, c1: 0, r1: 0, c2: 0, r2: 0, good: true))
    return out

// ---------- parser ----------

fn peek(p: PS) Tok:
    return p.toks[p.pos].clone()

fn is_op(t: Tok, s: String) Bool:
    return t.kind == "op" and t.text == s

fn parse_expr(var p: PS) Node:
    return parse_cmp(var p)

fn parse_cmp(var p: PS) Node:
    var left = parse_concat(var p)
    while not p.bad and peek(p).kind == "op" and CMP_OPS.contains(peek(p).text):
        let op = peek(p).text.clone()
        p.pos += 1
        let right = parse_concat(var p)
        left = Node.NBin(op.clone(), [left, right])
    return left

fn parse_concat(var p: PS) Node:
    var left = parse_add(var p)
    while not p.bad and is_op(peek(p), "&"):
        p.pos += 1
        let right = parse_add(var p)
        left = Node.NBin("&", [left, right])
    return left

fn parse_add(var p: PS) Node:
    var left = parse_mul(var p)
    while not p.bad and (is_op(peek(p), "+") or is_op(peek(p), "-")):
        let op = peek(p).text.clone()
        p.pos += 1
        let right = parse_mul(var p)
        left = Node.NBin(op.clone(), [left, right])
    return left

fn parse_mul(var p: PS) Node:
    var left = parse_unary(var p)
    while not p.bad and (is_op(peek(p), "*") or is_op(peek(p), "/")):
        let op = peek(p).text.clone()
        p.pos += 1
        let right = parse_unary(var p)
        left = Node.NBin(op.clone(), [left, right])
    return left

fn parse_unary(var p: PS) Node:
    if not p.bad and (is_op(peek(p), "+") or is_op(peek(p), "-")):
        let op = peek(p).text.clone()
        p.pos += 1
        let x = parse_unary(var p)
        return Node.NUn(op.clone(), [x])
    return parse_pow(var p)

fn parse_pow(var p: PS) Node:
    let base = parse_prim(var p)
    if not p.bad and is_op(peek(p), "^"):
        p.pos += 1
        let rhs = parse_pow_rhs(var p)
        return Node.NBin("^", [base, rhs])
    return base

fn parse_pow_rhs(var p: PS) Node:
    if not p.bad and (is_op(peek(p), "+") or is_op(peek(p), "-")):
        let op = peek(p).text.clone()
        p.pos += 1
        let x = parse_pow_rhs(var p)
        return Node.NUn(op.clone(), [x])
    return parse_pow(var p)

fn parse_prim(var p: PS) Node:
    if p.bad:
        return Node.NNum(0.0)
    let t = peek(p)
    if t.kind == "num":
        p.pos += 1
        return Node.NNum(t.num)
    if t.kind == "str":
        p.pos += 1
        return Node.NStr(t.text.clone())
    if t.kind == "ref":
        p.pos += 1
        return Node.NRef(t.c1, t.r1, t.good)
    if t.kind == "rng":
        p.pos += 1
        return Node.NRng(t.c1, t.r1, t.c2, t.r2, t.good)
    if t.kind == "err":
        p.pos += 1
        return Node.NErrK("#REF!")
    if t.kind == "id":
        p.pos += 1
        let u = upper(t.text)
        if u == "TRUE":
            return Node.NBool(true)
        if u == "FALSE":
            return Node.NBool(false)
        return Node.NName
    if t.kind == "fn":
        p.pos += 2
        var args = List[Node]()
        if peek(p).kind == ")":
            p.pos += 1
            return Node.NCall(upper(t.text), args)
        var more = true
        while more and not p.bad:
            let x = parse_expr(var p)
            args.append(x)
            if peek(p).kind == ",":
                p.pos += 1
            else if peek(p).kind == ")":
                p.pos += 1
                more = false
            else:
                p.bad = true
        if p.bad:
            return Node.NNum(0.0)
        return Node.NCall(upper(t.text), args)
    if t.kind == "(":
        p.pos += 1
        let e = parse_expr(var p)
        if peek(p).kind == ")":
            p.pos += 1
        else:
            p.bad = true
        return e
    p.bad = true
    return Node.NNum(0.0)

// Collects precedent keys; ROW and COLUMN arguments are not dependencies.
fn collect(n: Node, var acc: Set[Int]) Unit:
    match n:
        NRef(c, r, good):
            if good:
                acc.add(key_of(c, r))
            return
        NRng(c1, r1, c2, r2, good):
            if good:
                let lo_c = imin(c1, c2)
                let hi_c = imax(c1, c2)
                let lo_r = imin(r1, r2)
                let hi_r = imax(r1, r2)
                for rr in lo_r..hi_r + 1:
                    for cc in lo_c..hi_c + 1:
                        acc.add(key_of(cc, rr))
            return
        NCall(name, args):
            let u = upper(name)
            if u == "ROW" or u == "COLUMN":
                return
            for a in args:
                collect(a.clone(), var acc)
            return
        NUn(_, xs):
            for x in xs:
                collect(x.clone(), var acc)
            return
        NBin(_, xs):
            for x in xs:
                collect(x.clone(), var acc)
            return
        _:
            return

fn compile_src(src: String) Form:
    var p = PS(toks: lex(src), pos: 0, bad: false)
    let node = parse_expr(var p)
    if p.bad or peek(p).kind != "end":
        return Form(ast: Node.NNum(0.0), perr: true, precs: List[Int]())
    var acc = Set[Int]()
    collect(node.clone(), var acc)
    return Form(ast: node, perr: false, precs: acc.values())

// ---------- evaluation ----------

fn cell_val(sh: Sheet, key: Int) Value:
    if let v = sh.vals.get(key):
        return v.clone()
    return Value.VE

fn ev(sh: Sheet, n: Node) Value:
    match n:
        NNum(x):
            return Value.VNum(x)
        NStr(s):
            return Value.VText(s)
        NBool(b):
            return Value.VBool(b)
        NErrK(e):
            return Value.VErr(e)
        NRef(c, r, good):
            if not good:
                return Value.VErr("#REF!")
            return cell_val(sh, key_of(c, r))
        NRng(_, _, _, _, _):
            return Value.VErr("#VALUE!")
        NName:
            return Value.VErr("#NAME?")
        NCall(name, args):
            return call_fn(sh, name, args)
        NUn(op, xs):
            return unop(sh, op, xs)
        NBin(op, xs):
            return binop(sh, op, xs)

fn unop(sh: Sheet, op: String, xs: List[Node]) Value:
    let x = num_of(ev(sh, xs[0].clone()))
    if is_err(x):
        return x
    if op == "-":
        return finite(-fv(x))
    return finite(fv(x))

fn binop(sh: Sheet, op: String, xs: List[Node]) Value:
    let a = ev(sh, xs[0].clone())
    let b = ev(sh, xs[1].clone())
    if op == "&":
        if is_err(a):
            return a
        if is_err(b):
            return b
        return Value.VText(str_of(a) + str_of(b))
    if CMP_OPS.contains(op):
        if is_err(a):
            return a
        if is_err(b):
            return b
        return Value.VBool(holds(op, cmp_vals(a, b)))
    let x = num_of(a)
    if is_err(x):
        return x
    let y = num_of(b)
    if is_err(y):
        return y
    let p = fv(x)
    let q = fv(y)
    if op == "+":
        return finite(p + q)
    if op == "-":
        return finite(p - q)
    if op == "*":
        return finite(p * q)
    if op == "/":
        if q == 0.0:
            return Value.VErr("#DIV/0!")
        return finite(p / q)
    return finite(pow(p, q))

// Items of the arguments; range arguments contribute each cell row-major.
fn items_of(sh: Sheet, args: List[Node]) List[Item]:
    var out = List[Item]()
    for a in args:
        match a:
            NRng(c1, r1, c2, r2, good):
                if good:
                    let lo_c = imin(c1, c2)
                    let hi_c = imax(c1, c2)
                    let lo_r = imin(r1, r2)
                    let hi_r = imax(r1, r2)
                    for rr in lo_r..hi_r + 1:
                        for cc in lo_c..hi_c + 1:
                            out.append(Item(v: cell_val(sh, key_of(cc, rr)), rng: true))
                else:
                    out.append(Item(v: Value.VErr("#REF!"), rng: false))
            _:
                out.append(Item(v: ev(sh, a.clone()), rng: false))
    return out

fn collect_nums(items: List[Item]) NumsR:
    var nums = List[Float]()
    for it in items:
        let v = it.v
        if is_err(v):
            return NumsR(bad: true, err: v.clone(), nums: nums)
        if it.rng:
            if is_num(v):
                nums.append(fv(v))
        else:
            let x = num_of(v.clone())
            if is_err(x):
                return NumsR(bad: true, err: x, nums: nums)
            nums.append(fv(x))
    return NumsR(bad: false, err: Value.VE, nums: nums)

fn agg_num(sh: Sheet, u: String, args: List[Node]) Value:
    if args.length() == 0:
        return Value.VErr("#VALUE!")
    let r = collect_nums(items_of(sh, args))
    if r.bad:
        return r.err
    let nums = r.nums
    let cnt = nums.length()
    if u == "SUM":
        var t = 0.0
        for x in nums:
            t += x
        return finite(t)
    if u == "AVERAGE":
        if cnt == 0:
            return Value.VErr("#DIV/0!")
        var t = 0.0
        for x in nums:
            t += x
        return finite(t / cnt.to_float())
    if u == "PRODUCT":
        if cnt == 0:
            return Value.VNum(0.0)
        var t = 1.0
        for x in nums:
            t *= x
        return finite(t)
    if u == "MIN" or u == "MAX":
        if cnt == 0:
            return Value.VNum(0.0)
        var best = nums[0]
        for x in nums:
            if u == "MIN" and x < best:
                best = x
            if u == "MAX" and x > best:
                best = x
        return Value.VNum(best)
    // MEDIAN
    if cnt == 0:
        return Value.VErr("#NUM!")
    var sorted_nums = nums.sorted()
    let half = cnt / 2
    if cnt % 2 == 1:
        return Value.VNum(sorted_nums[half])
    return finite((sorted_nums[half - 1] + sorted_nums[half]) / 2.0)

fn scalar1(sh: Sheet, args: List[Node]) Value:
    return ev(sh, args[0].clone())

// Shared helper for one-argument numeric functions: VNum or error.
fn num_arg(sh: Sheet, n: Node) Value:
    return num_of(ev(sh, n))

fn toi(f: Float) Int:
    return f.truncate_to_int().get(0)

fn join_range_keys(keys: List[Int]) String:
    var out = ""
    var first = true
    for k in keys:
        if not first:
            out += " "
        out += cell_name(k)
        first = false
    return out

fn op_split(s: String) OpR:
    let cs = s.chars()
    let n = cs.length()
    for cand in [">=", "<=", "<>", ">", "<", "="]:
        let w = cand.scalar_length()
        if s.starts_with(cand):
            return OpR(op: cand, rest: join_cs(cs, w, n))
    return OpR(op: "=", rest: s)

fn call_fn(sh: Sheet, name: String, args: List[Node]) Value:
    let u = upper(name)
    let k = args.length()
    if u == "SUM" or u == "AVERAGE" or u == "MIN" or u == "MAX" or u == "PRODUCT" or u == "MEDIAN":
        return agg_num(sh, u, args)
    if u == "COUNT" or u == "COUNTA":
        if k == 0:
            return Value.VErr("#VALUE!")
        var cnt = 0
        for it in items_of(sh, args):
            if u == "COUNT":
                if is_num(it.v):
                    cnt += 1
            else:
                if not is_empty(it.v):
                    cnt += 1
        return Value.VNum(cnt.to_float())
    if u == "IF":
        if k < 2 or k > 3:
            return Value.VErr("#VALUE!")
        let c = bool_of(ev(sh, args[0].clone()))
        if is_err(c):
            return c
        if bv(c):
            return ev(sh, args[1].clone())
        if k == 3:
            return ev(sh, args[2].clone())
        return Value.VBool(false)
    if u == "IFERROR":
        if k != 2:
            return Value.VErr("#VALUE!")
        let a = ev(sh, args[0].clone())
        if is_err(a):
            return ev(sh, args[1].clone())
        return a
    if u == "CHOOSE":
        if k < 2:
            return Value.VErr("#VALUE!")
        let iv = num_arg(sh, args[0].clone())
        if is_err(iv):
            return iv
        let f = floor(fv(iv))
        if f < 1.0 or f > (k - 1).to_float():
            return Value.VErr("#VALUE!")
        return ev(sh, args[toi(f)].clone())
    if u == "AND" or u == "OR":
        if k == 0:
            return Value.VErr("#VALUE!")
        var cnt = 0
        var acc = u == "AND"
        for it in items_of(sh, args):
            let v = it.v.clone()
            if is_err(v):
                return v.clone()
            if it.rng and (is_text(v) or is_empty(v)):
                continue
            let b = bool_of(v.clone())
            if is_err(b):
                return b
            cnt += 1
            if u == "AND" and not bv(b):
                acc = false
            if u == "OR" and bv(b):
                acc = true
        if cnt == 0:
            return Value.VErr("#VALUE!")
        return Value.VBool(acc)
    if u == "NOT":
        if k != 1:
            return Value.VErr("#VALUE!")
        let b = bool_of(ev(sh, args[0].clone()))
        if is_err(b):
            return b
        return Value.VBool(not bv(b))
    if u == "ABS" or u == "INT" or u == "SQRT":
        if k != 1:
            return Value.VErr("#VALUE!")
        let x = num_arg(sh, args[0].clone())
        if is_err(x):
            return x
        let p = fv(x)
        if u == "ABS":
            return finite(p.abs())
        if u == "INT":
            return finite(floor(p))
        if p < 0.0:
            return Value.VErr("#NUM!")
        return finite(sqrt(p))
    if u == "POW" or u == "MOD":
        if k != 2:
            return Value.VErr("#VALUE!")
        let x = num_arg(sh, args[0].clone())
        if is_err(x):
            return x
        let y = num_arg(sh, args[1].clone())
        if is_err(y):
            return y
        let p = fv(x)
        let q = fv(y)
        if u == "POW":
            return finite(pow(p, q))
        if q == 0.0:
            return Value.VErr("#DIV/0!")
        return finite(p - q * floor(p / q))
    if u == "ROUND":
        if k < 1 or k > 2:
            return Value.VErr("#VALUE!")
        let x = num_arg(sh, args[0].clone())
        if is_err(x):
            return x
        var d = 0.0
        if k == 2:
            let dv = num_arg(sh, args[1].clone())
            if is_err(dv):
                return dv
            d = truncate(fv(dv))
        if d.abs() > 15.0:
            return Value.VErr("#NUM!")
        let scale = pow(10.0, d)
        let y = fv(x) * scale
        let a = y.abs()
        let fl = floor(a)
        var r = fl
        if a - fl >= 0.5:
            r = fl + 1.0
        if y < 0.0:
            r = -r
        return finite(r / scale)
    if u == "LEN":
        if k != 1:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        if is_err(v):
            return v
        return Value.VNum(str_of(v).scalar_length().to_float())
    if u == "UPPER" or u == "LOWER" or u == "TRIM":
        if k != 1:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        if is_err(v):
            return v
        let s = str_of(v)
        if u == "UPPER":
            return Value.VText(upper(s))
        if u == "TRIM":
            return Value.VText(collapse(s))
        return Value.VText(lower(s))
    if u == "LEFT" or u == "RIGHT":
        if k < 1 or k > 2:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        if is_err(v):
            return v
        var nf = 1.0
        if k == 2:
            let nv = num_arg(sh, args[1].clone())
            if is_err(nv):
                return nv
            nf = floor(fv(nv))
        if nf < 0.0:
            return Value.VErr("#VALUE!")
        let cs = str_of(v).chars()
        let L = cs.length()
        var cnt = L
        if nf < L.to_float():
            cnt = toi(nf)
        if u == "LEFT":
            return Value.VText(join_cs(cs, 0, cnt))
        return Value.VText(join_cs(cs, L - cnt, L))
    if u == "MID":
        if k != 3:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        if is_err(v):
            return v
        let sv = num_arg(sh, args[1].clone())
        if is_err(sv):
            return sv
        let lv = num_arg(sh, args[2].clone())
        if is_err(lv):
            return lv
        let sf = floor(fv(sv))
        let lf = floor(fv(lv))
        if sf < 1.0 or lf < 0.0:
            return Value.VErr("#VALUE!")
        let cs = str_of(v).chars()
        let L = cs.length()
        if sf > L.to_float():
            return Value.VText("")
        let start = toi(sf) - 1
        var cnt = L
        if lf < L.to_float():
            cnt = toi(lf)
        let stop = imin(start + cnt, L)
        return Value.VText(join_cs(cs, start, stop))
    if u == "CONCAT":
        if k == 0:
            return Value.VErr("#VALUE!")
        var out = ""
        for it in items_of(sh, args):
            if is_err(it.v):
                return it.v
            out += str_of(it.v)
        return Value.VText(out)
    if u == "SUBSTITUTE":
        if k != 3:
            return Value.VErr("#VALUE!")
        let a = ev(sh, args[0].clone())
        if is_err(a):
            return a
        let b = ev(sh, args[1].clone())
        if is_err(b):
            return b
        let c = ev(sh, args[2].clone())
        if is_err(c):
            return c
        let s = str_of(a)
        let old = str_of(b)
        if old == "":
            return Value.VText(s)
        return Value.VText(s.replace(old, str_of(c)))
    if u == "VALUE":
        if k != 1:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        match v:
            VText(s):
                return text_num(s)
            VBool(b):
                if b:
                    return Value.VNum(1.0)
                return Value.VNum(0.0)
            VE:
                return Value.VNum(0.0)
            VNum(x):
                return Value.VNum(x)
            VErr(e):
                return Value.VErr(e)
    if u == "ISERROR" or u == "ISBLANK" or u == "ISNUMBER" or u == "ISTEXT":
        if k != 1:
            return Value.VErr("#VALUE!")
        let v = scalar1(sh, args)
        if u == "ISERROR":
            return Value.VBool(is_err(v))
        if u == "ISBLANK":
            return Value.VBool(is_empty(v))
        if u == "ISNUMBER":
            return Value.VBool(is_num(v))
        return Value.VBool(is_text(v))
    if u == "ROW" or u == "COLUMN":
        if k != 1:
            return Value.VErr("#VALUE!")
        match args[0]:
            NRef(c, r, good):
                if not good:
                    return Value.VErr("#REF!")
                if u == "ROW":
                    return Value.VNum(r.to_float())
                return Value.VNum(c.to_float())
            NRng(c1, r1, _, _, good):
                if not good:
                    return Value.VErr("#REF!")
                if u == "ROW":
                    return Value.VNum(r1.to_float())
                return Value.VNum(c1.to_float())
            _:
                return Value.VErr("#VALUE!")
    if u == "INDEX":
        if k < 2 or k > 3:
            return Value.VErr("#VALUE!")
        match args[0]:
            NRng(c1, r1, c2, r2, good):
                if not good:
                    return Value.VErr("#REF!")
                let rlo = imin(r1, r2)
                let rows = imax(r1, r2) - rlo + 1
                let clo = imin(c1, c2)
                let cols = imax(c1, c2) - clo + 1
                let rv = num_arg(sh, args[1].clone())
                if is_err(rv):
                    return rv
                let rf = floor(fv(rv))
                var row = 0
                var col = 0
                if k == 2:
                    if rows == 1:
                        if rf < 1.0 or rf > cols.to_float():
                            return Value.VErr("#REF!")
                        row = rlo
                        col = clo + toi(rf) - 1
                    else:
                        if rf < 1.0 or rf > rows.to_float():
                            return Value.VErr("#REF!")
                        row = rlo + toi(rf) - 1
                        col = clo
                else:
                    let cv = num_arg(sh, args[2].clone())
                    if is_err(cv):
                        return cv
                    let cf = floor(fv(cv))
                    if rf < 1.0 or rf > rows.to_float() or cf < 1.0 or cf > cols.to_float():
                        return Value.VErr("#REF!")
                    row = rlo + toi(rf) - 1
                    col = clo + toi(cf) - 1
                return cell_val(sh, key_of(col, row))
            _:
                return Value.VErr("#VALUE!")
    if u == "COUNTIF":
        if k != 2:
            return Value.VErr("#VALUE!")
        var lo_c = 0
        var lo_r = 0
        var hi_c = 0
        var hi_r = 0
        match args[0]:
            NRng(c1, r1, c2, r2, good):
                if not good:
                    return Value.VErr("#REF!")
                lo_c = imin(c1, c2)
                hi_c = imax(c1, c2)
                lo_r = imin(r1, r2)
                hi_r = imax(r1, r2)
            _:
                return Value.VErr("#VALUE!")
        let crit = ev(sh, args[1].clone())
        if is_err(crit):
            return crit
        var op = "="
        var opnd = crit.clone()
        if is_text(crit):
            let parts = op_split(str_of(crit))
            op = parts.op
            let rcs = parts.rest.chars()
            if full_num(rcs):
                opnd = text_num(parts.rest)
            else:
                opnd = Value.VText(parts.rest)
        var cnt = 0
        for rr in lo_r..hi_r + 1:
            for cc in lo_c..hi_c + 1:
                let cv = cell_val(sh, key_of(cc, rr))
                if type_code(cv) == type_code(opnd):
                    if holds(op, cmp_vals(cv, opnd.clone())):
                        cnt += 1
                else if op == "<>" and not is_empty(cv):
                    cnt += 1
        return Value.VNum(cnt.to_float())
    return Value.VErr("#NAME?")

fn lower(s: String) String:
    var out = ""
    for c in s.chars():
        let k = UPPER_LETTERS.index_of(c).get(-1)
        if k >= 0:
            out += LOWER_LETTERS.get(k, c)
        else:
            out += c
    return out

// ---------- formulas and recalculation ----------

fn eval_form(sh: Sheet, k: Int) Value:
    if let f = sh.forms.get(k):
        if f.perr:
            return Value.VErr("#PARSE!")
        let v = ev(sh, f.ast.clone())
        if is_empty(v):
            return Value.VNum(0.0)
        return v
    return Value.VNum(0.0)

fn tarjan(var t: TJ, sh: Sheet, aff: Set[Int], v: Int) Unit:
    t.idx[v] = t.cnt
    t.low[v] = t.cnt
    t.cnt += 1
    t.stk.append(v)
    t.on.add(v)
    if let f = sh.forms.get(v):
        for p in f.precs:
            if aff.contains(p):
                if not t.idx.contains(p):
                    tarjan(var t, sh, aff, p)
                    t.low[v] = imin(t.low[v], t.low[p])
                else if t.on.contains(p):
                    t.low[v] = imin(t.low[v], t.idx[p])
    if t.low[v] == t.idx[v]:
        var comp = List[Int]()
        var going = true
        while going:
            let w = t.stk.pop().get(v)
            t.on.remove(w)
            comp.append(w)
            if w == v:
                going = false
        t.comps.append(comp)
    return

// Recalculates every changed cell and its transitive dependents; returns the count of formula cells evaluated.
fn recalc(var sh: Sheet, changed: List[Int]) Int:
    var seen = Set[Int]()
    var queue = List[Int]()
    for k in changed:
        if not seen.contains(k):
            seen.add(k)
            queue.append(k)
    var qi = 0
    while qi < queue.length():
        let k = queue[qi]
        qi += 1
        if let ds = sh.deps.get(k):
            for d in ds.values():
                if not seen.contains(d):
                    seen.add(d)
                    queue.append(d)
    var aff = Set[Int]()
    var order = List[Int]()
    for k in queue:
        if sh.forms.contains(k):
            aff.add(k)
            order.append(k)
    var t = TJ(idx: Map[Int, Int](), low: Map[Int, Int](), on: Set[Int](), stk: List[Int](), cnt: 0, comps: List[List[Int]]())
    for k in order:
        if not t.idx.contains(k):
            tarjan(var t, sh, aff, k)
    for comp in t.comps:
        var cyc = comp.length() > 1
        if not cyc:
            let k0 = comp[0]
            if let f = sh.forms.get(k0):
                for p in f.precs:
                    if p == k0:
                        cyc = true
        for k in comp:
            if cyc:
                sh.vals[k] = Value.VErr("#CYCLE!")
            else:
                sh.vals[k] = eval_form(sh, k)
    let n = order.length()
    sh.evals += n
    return n

fn deps_remove(var sh: Sheet, key: Int, precs: List[Int]) Unit:
    for p in precs:
        if let s = sh.deps.get(p):
            var t = s.clone()
            t.remove(key)
            sh.deps[p] = t
    return

fn deps_add(var sh: Sheet, key: Int, precs: List[Int]) Unit:
    for p in precs:
        var t = Set[Int]()
        if let s = sh.deps.get(p):
            t = s.clone()
        t.add(key)
        sh.deps[p] = t
    return

fn drop_form(var sh: Sheet, key: Int) Unit:
    if let f = sh.forms.get(key):
        let old = f.precs.clone()
        deps_remove(var sh, key, old)
        sh.forms.remove(key)
    return

fn const_value(t: String) Value:
    if t.starts_with("'"):
        let cs = t.chars()
        return Value.VText(join_cs(cs, 1, cs.length()))
    let cs = t.chars()
    if full_num(cs):
        if let x = num_from_chars(cs):
            if x.is_finite():
                return Value.VNum(x)
    let u = upper(t)
    if u == "TRUE":
        return Value.VBool(true)
    if u == "FALSE":
        return Value.VBool(false)
    return Value.VText(t)

// Stores a cell from its trimmed VALUE text ("" clears it).
fn assign(var sh: Sheet, key: Int, text: String) Unit:
    drop_form(var sh, key)
    if text == "":
        sh.raws.remove(key)
        sh.vals.remove(key)
        return
    sh.raws[key] = text.clone()
    if text.starts_with("="):
        let cs = text.chars()
        let form = compile_src(join_cs(cs, 1, cs.length()))
        deps_add(var sh, key, form.precs)
        sh.forms[key] = form
        sh.vals.remove(key)
        return
    sh.vals[key] = const_value(text)
    return

// ---------- copy support ----------

fn shifted_corner(rs: RS, dcol: Int, drow: Int) String:
    var nc = rs.c
    var nr = rs.r
    if not rs.dc:
        nc = rs.c + dcol
    if not rs.dr:
        nr = rs.r + drow
    if nc < 1 or nc > 26 or nr < 1 or nr > 999:
        return ""
    var s = ""
    if rs.dc:
        s += "$"
    s += colname(nc)
    if rs.dr:
        s += "$"
    s += nr.to_string()
    return s

fn shift_src(src: String, dcol: Int, drow: Int) String:
    let cs = src.chars()
    let n = cs.length()
    var out = ""
    var i = 0
    while i < n:
        let c = cs[i]
        if c == "\"":
            var j = i + 1
            var closed = false
            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    j += 1
            out += join_cs(cs, i, j)
            i = j
        else if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
            let e = scan_num(cs, i)
            out += join_cs(cs, i, e)
            i = e
        else if c == "$" or is_letter(c) or c == "_":
            let rs = scan_ref(cs, i)
            if rs.stop >= 0:
                var handled = false
                if rs.stop < n and cs[rs.stop] == ":":
                    let rs2 = scan_ref(cs, rs.stop + 1)
                    if rs2.stop >= 0:
                        handled = true
                        var a = join_cs(cs, i, rs.stop)
                        var b = join_cs(cs, rs.stop + 1, rs2.stop)
                        var bad = false
                        if rs.good:
                            a = shifted_corner(rs, dcol, drow)
                            if a == "":
                                bad = true
                        if rs2.good:
                            b = shifted_corner(rs2, dcol, drow)
                            if b == "":
                                bad = true
                        if bad:
                            out += "#REF!"
                        else:
                            out += "{a}:{b}"
                        i = rs2.stop
                if not handled:
                    if rs.good:
                        let s = shifted_corner(rs, dcol, drow)
                        if s == "":
                            out += "#REF!"
                        else:
                            out += s
                    else:
                        out += join_cs(cs, i, rs.stop)
                    i = rs.stop
            else if c == "$":
                out += "$"
                i += 1
            else:
                var j = i
                while j < n and is_ident(cs[j]):
                    j += 1
                out += join_cs(cs, i, j)
                i = j
        else:
            out += c
            i += 1
    return out

// ---------- CSV ----------

fn csv_parse(block: List[String]) List[List[String]]:
    var text = ""
    var first = true
    for ln in block:
        if not first:
            text += "\n"
        text += ln
        first = false
    let cs = text.chars()
    let n = cs.length()
    var recs = List[List[String]]()
    var fields = List[String]()
    var buf = ""
    var inq = false
    var rlen = 0
    var i = 0
    while i < n:
        let c = cs[i]
        if inq and c == "\"" and i + 1 < n and cs[i + 1] == "\"":
            buf += "\""
            rlen += 2
            i += 2
        else if c == "\"":
            inq = not inq
            rlen += 1
            i += 1
        else if inq:
            buf += c
            rlen += 1
            i += 1
        else if c == ",":
            fields.append(buf)
            buf = ""
            rlen += 1
            i += 1
        else if c == "\n":
            fields.append(buf)
            buf = ""
            if rlen > 0:
                recs.append(fields)
            fields = List[String]()
            rlen = 0
            i += 1
        else if c == "\r":
            i += 1
        else:
            buf += c
            rlen += 1
            i += 1
    fields.append(buf)
    if rlen > 0:
        recs.append(fields)
    return recs

// ---------- commands ----------

fn read_input() Result[List[String], Error]:
    var out = List[String]()
    for l in stdin() | lines:
        out.append(l)
    return ok(out)

fn parse_cell(s: String) CellR:
    let cs = s.chars()
    let n = cs.length()
    if n < 2 or n > 4 or not is_letter(cs[0]):
        return CellR(good: false, c: 0, r: 0)
    var r = 0
    for k in 1..n:
        if not is_digit(cs[k]):
            return CellR(good: false, c: 0, r: 0)
        r = r * 10 + digit_val(cs[k])
    if cs[1] == "0" or r < 1 or r > 999:
        return CellR(good: false, c: 0, r: 0)
    return CellR(good: true, c: colnum(cs[0]), r: r)

fn parse_range(s: String) RangeR:
    let cs = s.chars()
    let n = cs.length()
    var colon = -1
    var colons = 0
    for k in 0..n:
        if cs[k] == ":":
            colon = k
            colons += 1
    if colons == 0:
        let a = parse_cell(s)
        return RangeR(good: a.good, c1: a.c, r1: a.r, c2: a.c, r2: a.r)
    if colons > 1:
        return RangeR(good: false, c1: 0, r1: 0, c2: 0, r2: 0)
    let a = parse_cell(join_cs(cs, 0, colon))
    let b = parse_cell(join_cs(cs, colon + 1, n))
    return RangeR(good: a.good and b.good, c1: a.c, r1: a.r, c2: b.c, r2: b.r)

fn data_range(sh: Sheet) RangeR:
    var found = false
    var mc = 1
    var mr = 1
    for k in sh.raws.keys():
        found = true
        mc = imax(mc, key_col(k))
        mr = imax(mr, key_row(k))
    if not found:
        return RangeR(good: false, c1: 0, r1: 0, c2: 0, r2: 0)
    return RangeR(good: true, c1: 1, r1: 1, c2: mc, r2: mr)

fn cmd_set(var sh: Sheet, words: List[String], t: String) Unit:
    if words.length() < 2:
        print("error: usage: set CELL VALUE")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let key = key_of(cr.c, cr.r)
    assign(var sh, key, rest_after(t, 2))
    let n = recalc(var sh, [key])
    print("recalc {n}")
    return

fn cmd_clear(var sh: Sheet, words: List[String]) Unit:
    if words.length() != 2:
        print("error: usage: clear CELL")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let key = key_of(cr.c, cr.r)
    assign(var sh, key, "")
    let n = recalc(var sh, [key])
    print("recalc {n}")
    return

fn cmd_get(sh: Sheet, words: List[String]) Unit:
    if words.length() != 2:
        print("error: usage: get CELL")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let key = key_of(cr.c, cr.r)
    if sh.raws.contains(key):
        print(str_of(cell_val(sh, key)))
    else:
        print("(empty)")
    return

fn cmd_show(sh: Sheet, words: List[String]) Unit:
    if words.length() != 2:
        print("error: usage: show CELL")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let key = key_of(cr.c, cr.r)
    let name = cell_name(key)
    if not sh.raws.contains(key):
        print("{name}: (empty)")
        return
    let raw = sh.raws.get(key).get("")
    if sh.forms.contains(key):
        print("{name}: {raw} => {str_of(cell_val(sh, key))}")
    else:
        print("{name}: {raw}")
    return

fn cmd_copy(var sh: Sheet, words: List[String]) Unit:
    if words.length() != 3:
        print("error: usage: copy SRC DST")
        return
    let sc = parse_cell(words[1])
    if not sc.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let dr = parse_range(words[2])
    if not dr.good:
        print("error: bad range '" + words[2] + "'")
        return
    let src_key = key_of(sc.c, sc.r)
    let src_raw = sh.raws.get(src_key).get("")
    let src_is_form = sh.forms.contains(src_key)
    var changed = List[Int]()
    for rr in imin(dr.r1, dr.r2)..imax(dr.r1, dr.r2) + 1:
        for cc in imin(dr.c1, dr.c2)..imax(dr.c1, dr.c2) + 1:
            let key = key_of(cc, rr)
            var text = src_raw.clone()
            if src_is_form:
                let cs = src_raw.chars()
                text = "=" + shift_src(join_cs(cs, 1, cs.length()), cc - sc.c, rr - sc.r)
            assign(var sh, key, text)
            changed.append(key)
    let n = recalc(var sh, changed)
    print("recalc {n}")
    return

fn cmd_print(sh: Sheet, words: List[String]) Unit:
    var rg = RangeR(good: false, c1: 0, r1: 0, c2: 0, r2: 0)
    if words.length() == 1:
        rg = data_range(sh)
        if not rg.good:
            print("(empty sheet)")
            return
    else if words.length() == 2:
        if words[1] == "formulas":
            print("error: usage: print [RANGE]")
            return
        rg = parse_range(words[1])
        if not rg.good:
            print("error: bad range '" + words[1] + "'")
            return
    else:
        print("error: usage: print [RANGE]")
        return
    for rr in imin(rg.r1, rg.r2)..imax(rg.r1, rg.r2) + 1:
        var line = ""
        var first = true
        for cc in imin(rg.c1, rg.c2)..imax(rg.c1, rg.c2) + 1:
            if not first:
                line += " | "
            first = false
            line += str_of(cell_val(sh, key_of(cc, rr)))
        print(line)
    return

fn csv_field(s: String) String:
    var special = s.starts_with(" ") or s.ends_with(" ")
    for c in s.chars():
        if c == "," or c == "\"" or c == "\n" or c == "\r":
            special = true
    if not special:
        return s.clone()
    return "\"" + s.replace("\"", "\"\"") + "\""

fn cmd_export(sh: Sheet, words: List[String]) Unit:
    var formulas = false
    var mode_set = false
    var range_seen = false
    var rg = RangeR(good: false, c1: 0, r1: 0, c2: 0, r2: 0)
    var idx = 1
    while idx < words.length():
        let w = words[idx]
        if w == "formulas" or w == "values":
            if mode_set:
                print("error: usage: export [formulas] [RANGE]")
                return
            mode_set = true
            formulas = w == "formulas"
        else:
            if range_seen:
                print("error: usage: export [formulas] [RANGE]")
                return
            range_seen = true
            rg = parse_range(w)
            if not rg.good:
                print("error: bad range '" + w + "'")
                return
        idx += 1
    if not range_seen:
        rg = data_range(sh)
        if not rg.good:
            print("(empty sheet)")
            return
    for rr in imin(rg.r1, rg.r2)..imax(rg.r1, rg.r2) + 1:
        var line = ""
        var first = true
        for cc in imin(rg.c1, rg.c2)..imax(rg.c1, rg.c2) + 1:
            if not first:
                line += ","
            first = false
            let key = key_of(cc, rr)
            if formulas:
                line += csv_field(sh.raws.get(key).get(""))
            else:
                line += csv_field(str_of(cell_val(sh, key)))
        print(line)
    return

fn dependents_of(sh: Sheet, key: Int) List[Int]:
    var seen = Set[Int]()
    var queue = List[Int]()
    if let ds = sh.deps.get(key):
        for d in ds.values():
            if not seen.contains(d):
                seen.add(d)
                queue.append(d)
    var qi = 0
    while qi < queue.length():
        let k = queue[qi]
        qi += 1
        if let more = sh.deps.get(k):
            for d in more.values():
                if not seen.contains(d):
                    seen.add(d)
                    queue.append(d)
    var out = seen.values()
    out.sort()
    return out

fn cmd_deps(sh: Sheet, words: List[String], is_prec: Bool) Unit:
    let cmd = words[0]
    if words.length() != 2:
        print("error: usage: " + cmd + " CELL")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let key = key_of(cr.c, cr.r)
    if is_prec:
        if let f = sh.forms.get(key):
            var ps = f.precs.clone()
            ps.sort()
            if ps.length() > 0:
                print(join_range_keys(ps))
                return
        print("(none)")
        return
    let ds = dependents_of(sh, key)
    if ds.length() == 0:
        print("(none)")
    else:
        print(join_range_keys(ds))
    return

fn cmd_import(var sh: Sheet, words: List[String], block: List[String]) Unit:
    if words.length() != 2:
        print("error: usage: import CELL")
        return
    let cr = parse_cell(words[1])
    if not cr.good:
        print("error: bad cell reference '" + words[1] + "'")
        return
    let recs = csv_parse(block)
    let nrows = recs.length()
    var ncols = 0
    for rec in recs:
        ncols = imax(ncols, rec.length())
    if nrows == 0:
        print("imported 0 rows, 0 columns; recalc 0")
        return
    if cr.r + nrows - 1 > 999 or cr.c + ncols - 1 > 26:
        print("error: import out of range")
        return
    var changed = List[Int]()
    var ri = 0
    for rec in recs:
        var ci = 0
        for f in rec:
            let key = key_of(cr.c + ci, cr.r + ri)
            assign(var sh, key, f.trim())
            changed.append(key)
            ci += 1
        ri += 1
    let n = recalc(var sh, changed)
    print("imported {nrows} rows, {ncols} columns; recalc {n}")
    return

fn cmd_stats(sh: Sheet) Unit:
    print("cells {sh.raws.length()} formulas {sh.forms.length()} evals {sh.evals}")
    return

export fn main() Int:
    let input_lines = read_input().get()
    var sh = Sheet(raws: Map[Int, String](), vals: Map[Int, Value](), forms: Map[Int, Form](), deps: Map[Int, Set[Int]](), evals: 0)
    let total = input_lines.length()
    var i = 0
    while i < total:
        let line = input_lines[i]
        i += 1
        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue
        print("> " + line.trim_end())
        let words = split_words(t)
        let cmd = words[0]
        if cmd == "import":
            var block = List[String]()
            while i < total and input_lines[i] != ".":
                block.append(input_lines[i].clone())
                i += 1
            if i < total:
                i += 1
            cmd_import(var sh, words, block)
        else if cmd == "set":
            cmd_set(var sh, words, t)
        else if cmd == "clear":
            cmd_clear(var sh, words)
        else if cmd == "get":
            cmd_get(sh, words)
        else if cmd == "show":
            cmd_show(sh, words)
        else if cmd == "copy":
            cmd_copy(var sh, words)
        else if cmd == "print":
            cmd_print(sh, words)
        else if cmd == "export":
            cmd_export(sh, words)
        else if cmd == "precedents":
            cmd_deps(sh, words, true)
        else if cmd == "dependents":
            cmd_deps(sh, words, false)
        else if cmd == "stats":
            cmd_stats(sh)
        else:
            print("error: unknown command '" + cmd + "'")
    return 0
