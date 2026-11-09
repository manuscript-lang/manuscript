// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
import floor, pow, sqrt from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

// ---------- constants ----------

let V_EMPTY = 0
let V_NUM = 1
let V_TEXT = 2
let V_BOOL = 3
let V_ERR = 4
let K_NUM = 0
let K_STR = 1
let K_BOOL = 2
let K_REF = 3
let K_RANGE = 4
let K_ERR = 5
let K_NAME = 6
let K_CALL = 7
let K_BIN = 8
let K_NEG = 9
let K_POS = 10
let K_IDENT = 11
let K_OP = 12
let K_LP = 13
let K_RP = 14
let K_COMMA = 15
let K_BAD = 16
let LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let TWO53 = 9007199254740992.0

// ---------- records ----------

type SVal:
    kind: Int
    num: Float = 0.0
    text: String = ""

type SNode:
    kind: Int
    num: Float = 0.0
    text: String = ""
    ok: Bool = true
    c1: Int = 0
    r1: Int = 0
    c2: Int = 0
    r2: Int = 0
    dc1: Bool = false
    dr1: Bool = false
    dc2: Bool = false
    dr2: Bool = false
    pos: Int = 0
    endp: Int = 0
    kids: List[SNode] = []

type SRect:
    c1: Int
    r1: Int
    c2: Int
    r2: Int

type SCell:
    raw: String
    mode: Int
    ast: SNode
    precs: List[SRect]

type SSheet:
    cells: Map[Int, SCell]
    vals: Map[Int, SVal]
    evals: Int

type SLex:
    toks: List[SNode]
    bad: Bool

type SParser:
    toks: List[SNode]
    pos: Int
    bad: Bool

type SItem:
    v: SVal
    rng: Bool

type SNums:
    err: SVal
    failed: Bool
    vals: List[Float]

type SShift:
    text: String
    off: Bool
    endp: Int

type SView:
    usage: Bool
    bad: String
    fml: Bool
    has_range: Bool
    rect: SRect

type STarjan:
    adj: List[List[Int]]
    index: List[Int]
    low: List[Int]
    onst: List[Bool]
    stk: List[Int]
    comps: List[List[Int]]
    counter: Int

// ---------- small helpers ----------

fn svnum(x: Float) SVal:
    return SVal(kind: V_NUM, num: x)

fn svtext(s: String) SVal:
    return SVal(kind: V_TEXT, text: s)

fn svbool(b: Bool) SVal:
    if b:
        return SVal(kind: V_BOOL, num: 1.0)

    return SVal(kind: V_BOOL, num: 0.0)

fn sverr(e: String) SVal:
    return SVal(kind: V_ERR, text: e)

fn svempty() SVal:
    return SVal(kind: V_EMPTY)

fn finite_or_num(x: Float) SVal:
    if x.is_finite():
        return svnum(x)

    return sverr("#NUM!")

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn is_upper(c: String) Bool:
    return c >= "A" and c <= "Z"

fn is_lower(c: String) Bool:
    return c >= "a" and c <= "z"

fn is_alpha(c: String) Bool:
    return is_upper(c) or is_lower(c)

fn is_alnum(c: String) Bool:
    return is_alpha(c) or is_digit(c)

fn is_space(c: String) Bool:
    return c == " " or c == "\t"

fn sub(cs: List[String], a: Int, b: Int) String:
    var s = ""
    for i in a..b:
        s += cs[i]
    return s

fn letter_idx(c: String) Int:
    return c.upper().scalar_at(0) - 65

fn digit_val(c: String) Int:
    return c.scalar_at(0) - 48

fn mkkey(col: Int, row: Int) Int:
    return row * 100 + col

fn keycol(k: Int) Int:
    return k % 100

fn keyrow(k: Int) Int:
    return k / 100

fn name_of(k: Int) String:
    let c = keycol(k)
    return LETTERS.slice_scalars(c, c + 1).get("") + keyrow(k).to_string()

fn imin(a: Int, b: Int) Int:
    if a < b:
        return a

    return b

fn imax(a: Int, b: Int) Int:
    if a > b:
        return a

    return b

fn norm_rect(ca: Int, ra: Int, cb: Int, rb: Int) SRect:
    return SRect(c1: imin(ca, cb), r1: imin(ra, rb), c2: imax(ca, cb), r2: imax(ra, rb))

fn rect_has(r: SRect, k: Int) Bool:
    let c = keycol(k)
    let rw = keyrow(k)
    return c >= r.c1 and c <= r.c2 and rw >= r.r1 and rw <= r.r2

fn node_rect(a: SNode) SRect:
    return norm_rect(a.c1, a.r1, a.c2, a.r2)

// ---------- number grammar and formatting ----------

fn parse_number(s: String) Float?:
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

    let ip = sub(cs, is0, i)
    var fp = ""

    if i < n and cs[i] == ".":
        i += 1

        let fs = i
        while i < n and is_digit(cs[i]):
            i += 1
        fp = sub(cs, fs, i)

    if ip == "" and fp == "":
        return none

    var ex = ""

    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1

        var exneg = false

        if i < n and (cs[i] == "+" or cs[i] == "-"):
            exneg = cs[i] == "-"
            i += 1

        let es = i
        while i < n and is_digit(cs[i]):
            i += 1
        if i == es:
            return none

        ex = "e"
        if exneg:
            ex = "e-"
        ex += sub(cs, es, i)

    if i != n:
        return none

    var ipart = ip
    if ipart == "":
        ipart = "0"

    var fpart = fp
    if fpart == "":
        fpart = "0"

    let parsed = (ipart + "." + fpart + ex).parse_float()

    if let x = parsed:
        if not x.is_finite():
            return none
        if neg:
            return -x

        return x

    return none

fn big_int_string(x: Float) String:
    var y = x.abs()
    var halvings = 0

    while y >= TWO53:
        y = y / 2.0
        halvings += 1

    let m = y.truncate_to_int().get(0)
    let mchars = m.to_string().chars()
    var digs = List[Int]()
    var di = mchars.length() - 1

    while di >= 0:
        digs.append(digit_val(mchars[di]))
        di -= 1

    for _s in 0..halvings:
        var carry = 0
        var k = 0

        while k < digs.length():
            let v = digs[k] * 2 + carry
            digs[k] = v % 10
            carry = v / 10
            k += 1

        if carry > 0:
            digs.append(carry)

    var out = ""
    var k = digs.length() - 1

    while k >= 0:
        out += digs[k].to_string()
        k -= 1

    if x < 0.0:
        return "-" + out

    return out

fn fmt_num(x: Float) String:
    if x == 0.0:
        return "0"

    var s = ""

    if x.abs() >= 1e21:
        s = big_int_string(x)
    else:
        s = x.to_fixed(10)
        if s.contains("."):
            s = s.trim_end_chars("0").trim_end_chars(".")

    if s == "-0":
        return "0"

    return s

fn strform(v: SVal) String:
    if v.kind == V_NUM:
        return fmt_num(v.num)

    if v.kind == V_BOOL:
        if v.num != 0.0:
            return "TRUE"

        return "FALSE"

    if v.kind == V_TEXT or v.kind == V_ERR:
        return v.text.clone()

    return ""

// ---------- tokenizer ----------

fn scan_ref(cs: List[String], i: Int) SNode:
    let n = cs.length()
    var p = i
    var dc = false
    var dr = false

    if cs[p] == "$":
        dc = true
        p += 1

    let ls = p
    while p < n and is_alpha(cs[p]):
        p += 1

    let nl = p - ls
    if nl == 0:
        return SNode(kind: K_REF, endp: -1)

    if p < n and cs[p] == "$":
        dr = true
        p += 1

    let ds = p
    while p < n and is_digit(cs[p]):
        p += 1

    let nd = p - ds
    if nd == 0:
        return SNode(kind: K_REF, endp: -1)

    if p < n:
        let c = cs[p]
        if is_alnum(c) or c == "_" or c == "." or c == "(" or c == "$":
            return SNode(kind: K_REF, endp: -1)

    var ok = nl == 1 and nd <= 3 and cs[ds] != "0"
    var col = 0
    var row = 0

    if ok:
        col = letter_idx(cs[ls])
        row = sub(cs, ds, p).parse_int().get(0)
        ok = row >= 1 and row <= 999

    return SNode(
        kind: K_REF, ok: ok, c1: col, r1: row, dc1: dc, dr1: dr, pos: i, endp: p
    )

fn tokenize(cs: List[String]) SLex:
    var toks = List[SNode]()
    var bad = false
    let n = cs.length()
    var i = 0

    while i < n and not bad:
        let c = cs[i]

        if is_space(c):
            i += 1
        else if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
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

            let text = sub(cs, i, j)

            if let x = parse_number(text):
                toks.append(SNode(kind: K_NUM, num: x, pos: i, endp: j))
            else:
                toks.append(SNode(kind: K_ERR, text: "#NUM!", pos: i, endp: j))

            i = j
        else if c == "\"":
            var j = i + 1
            var s = ""
            var closed = false

            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        s += "\""
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    s += cs[j]
                    j += 1

            if closed:
                toks.append(SNode(kind: K_STR, text: s, pos: i, endp: j))
                i = j
            else:
                bad = true
        else if is_alpha(c) or c == "_" or c == "$":
            let r = scan_ref(cs, i)

            if r.endp >= 0:
                if r.endp < n and cs[r.endp] == ":":
                    var r2 = SNode(kind: K_REF, endp: -1)
                    if r.endp + 1 < n:
                        r2 = scan_ref(cs, r.endp + 1)

                    if r2.endp < 0:
                        bad = true
                    else:
                        toks.append(
                            SNode(
                                kind: K_RANGE, ok: r.ok and r2.ok, c1: r.c1, r1: r.r1,
                                dc1: r.dc1, dr1: r.dr1, c2: r2.c1, r2: r2.r1,
                                dc2: r2.dc1, dr2: r2.dr1, pos: i, endp: r2.endp
                            )
                        )
                        i = r2.endp
                else:
                    toks.append(
                        SNode(
                            kind: K_REF, ok: r.ok, c1: r.c1, r1: r.r1, dc1: r.dc1,
                            dr1: r.dr1, pos: i, endp: r.endp
                        )
                    )
                    i = r.endp
            else if c == "$":
                bad = true
            else:
                var j = i
                while j < n and (is_alnum(cs[j]) or cs[j] == "_" or cs[j] == "."):
                    j += 1
                toks.append(SNode(kind: K_IDENT, text: sub(cs, i, j), pos: i, endp: j))
                i = j
        else if c == "#":
            if i + 5 <= n and sub(cs, i, i + 5).upper() == "#REF!":
                toks.append(SNode(kind: K_ERR, text: "#REF!", pos: i, endp: i + 5))
                i += 5
            else:
                bad = true
        else if c == "(":
            toks.append(SNode(kind: K_LP, pos: i, endp: i + 1))
            i += 1
        else if c == ")":
            toks.append(SNode(kind: K_RP, pos: i, endp: i + 1))
            i += 1
        else if c == ",":
            toks.append(SNode(kind: K_COMMA, pos: i, endp: i + 1))
            i += 1
        else:
            var op = ""

            if (
                i + 1 < n
                and (
                    (
                        c == "<"
                        and (
                            cs[i + 1] == "="
                            or cs[i + 1] == ">"
                        )
                    )
                    or (c == ">" and cs[i + 1] == "=")
                )
            ):
                op = c + cs[i + 1]
            else if (
                c == "+"
                or c == "-"
                or c == "*"
                or c == "/"
                or c == "^"
                or c == "&"
                or c == "="
                or c == "<"
                or c == ">"
            ):
                op = c.clone()

            if op == "":
                bad = true
            else:
                toks.append(
                    SNode(
                        kind: K_OP, text: op.clone(), pos: i, endp: i + op.length()
                    )
                )
                i += op.length()

    return SLex(toks: toks, bad: bad)

// ---------- parser ----------

fn cur_kind(p: SParser) Int:
    if p.pos < p.toks.length():
        return p.toks[p.pos].kind

    return K_BAD

fn cur_text(p: SParser) String:
    if p.pos < p.toks.length():
        return p.toks[p.pos].text.clone()

    return ""

fn is_op(p: SParser, a: String) Bool:
    return cur_kind(p) == K_OP and cur_text(p) == a

fn parse_cmp(var p: SParser) SNode:
    var l = parse_cat(var p)

    while (
        not p.bad
        and cur_kind(p) == K_OP
        and (
            is_op(p, "=")
            or is_op(p, "<>")
            or is_op(p, "<")
            or is_op(p, "<=")
            or is_op(p, ">")
            or is_op(p, ">=")
        )
    ):
        let op = cur_text(p)
        p.pos += 1

        let r = parse_cat(var p)
        l = SNode(kind: K_BIN, text: op, kids: [l, r])

    return l

fn parse_cat(var p: SParser) SNode:
    var l = parse_add(var p)

    while not p.bad and is_op(p, "&"):
        p.pos += 1

        let r = parse_add(var p)
        l = SNode(kind: K_BIN, text: "&", kids: [l, r])

    return l

fn parse_add(var p: SParser) SNode:
    var l = parse_mul(var p)

    while not p.bad and (is_op(p, "+") or is_op(p, "-")):
        let op = cur_text(p)
        p.pos += 1

        let r = parse_mul(var p)
        l = SNode(kind: K_BIN, text: op, kids: [l, r])

    return l

fn parse_mul(var p: SParser) SNode:
    var l = parse_unary(var p)

    while not p.bad and (is_op(p, "*") or is_op(p, "/")):
        let op = cur_text(p)
        p.pos += 1

        let r = parse_unary(var p)
        l = SNode(kind: K_BIN, text: op, kids: [l, r])

    return l

fn parse_unary(var p: SParser) SNode:
    if not p.bad and (is_op(p, "+") or is_op(p, "-")):
        let neg = is_op(p, "-")
        p.pos += 1

        let k = parse_unary(var p)
        if neg:
            return SNode(kind: K_NEG, kids: [k])

        return SNode(kind: K_POS, kids: [k])

    return parse_power(var p)

fn parse_power(var p: SParser) SNode:
    let b = parse_primary(var p)

    if not p.bad and is_op(p, "^"):
        p.pos += 1

        let e = parse_pow_operand(var p)
        return SNode(kind: K_BIN, text: "^", kids: [b, e])

    return b.clone()

fn parse_pow_operand(var p: SParser) SNode:
    if not p.bad and (is_op(p, "+") or is_op(p, "-")):
        let neg = is_op(p, "-")
        p.pos += 1

        let k = parse_pow_operand(var p)
        if neg:
            return SNode(kind: K_NEG, kids: [k])

        return SNode(kind: K_POS, kids: [k])

    return parse_power(var p)

fn parse_primary(var p: SParser) SNode:
    if p.bad:
        return SNode(kind: K_NUM)

    let k = cur_kind(p)

    if k == K_NUM or k == K_STR or k == K_REF or k == K_RANGE or k == K_ERR:
        let t = p.toks[p.pos].clone()
        p.pos += 1
        return t

    if k == K_LP:
        p.pos += 1

        let e = parse_cmp(var p)

        if not p.bad and cur_kind(p) == K_RP:
            p.pos += 1
            return e.clone()

        p.bad = true
        return e.clone()

    if k == K_IDENT:
        let name = cur_text(p)
        p.pos += 1

        if cur_kind(p) == K_LP:
            p.pos += 1

            var args = List[SNode]()

            if cur_kind(p) == K_RP:
                p.pos += 1
            else:
                var done = false

                while not done and not p.bad:
                    let a = parse_cmp(var p)
                    args.append(a)

                    if cur_kind(p) == K_COMMA:
                        p.pos += 1
                    else if cur_kind(p) == K_RP:
                        p.pos += 1
                        done = true
                    else:
                        p.bad = true

            return SNode(kind: K_CALL, text: name.upper(), kids: args)

        let u = name.upper()
        if u == "TRUE":
            return SNode(kind: K_BOOL, num: 1.0)
        if u == "FALSE":
            return SNode(kind: K_BOOL, num: 0.0)

        return SNode(kind: K_NAME, text: name)

    p.bad = true
    return SNode(kind: K_NUM)

fn parse_src(src: String) SNode?:
    let lx = tokenize(src.chars())
    if lx.bad:
        return none

    var p = SParser(toks: lx.toks, pos: 0, bad: false)
    let e = parse_cmp(var p)
    if p.bad or p.pos != p.toks.length():
        return none

    return e.clone()

fn collect_precs(n: SNode, var out: List[SRect]) Unit:
    if n.kind == K_REF:
        if n.ok:
            out.append(SRect(c1: n.c1, r1: n.r1, c2: n.c1, r2: n.r1))
        return

    if n.kind == K_RANGE:
        if n.ok:
            out.append(node_rect(n))
        return

    if n.kind == K_CALL and (n.text == "ROW" or n.text == "COLUMN"):
        return

    for k in n.kids:
        collect_precs(k, var out)

fn const_value(raw: String) SVal:
    if raw.starts_with("'"):
        return svtext(raw.slice_scalars(1, raw.scalar_length()).get(""))
    if let x = parse_number(raw):
        return svnum(x)

    let u = raw.upper()
    if u == "TRUE":
        return svbool(true)
    if u == "FALSE":
        return svbool(false)

    return svtext(raw)

fn make_cell(raw: String) SCell:
    if raw.starts_with("="):
        let src = raw.slice_scalars(1, raw.scalar_length()).get("")

        if let e = parse_src(src):
            var precs = List[SRect]()
            collect_precs(e, var precs)
            return SCell(raw: raw, mode: 1, ast: e, precs: precs)

        return SCell(raw: raw, mode: 2, ast: SNode(kind: K_NUM), precs: List[SRect]())

    return SCell(raw: raw, mode: 0, ast: SNode(kind: K_NUM), precs: List[SRect]())

// ---------- evaluation ----------

fn value_at(sh: SSheet, k: Int) SVal:
    if let v = sh.vals.get(k):
        return v.clone()

    return svempty()

fn to_num(v: SVal) SVal:
    if v.kind == V_NUM:
        return v.clone()
    if v.kind == V_BOOL:
        return svnum(v.num)
    if v.kind == V_EMPTY:
        return svnum(0.0)

    if v.kind == V_TEXT:
        if let x = parse_number(v.text.trim()):
            return svnum(x)

        return sverr("#VALUE!")

    return v.clone()

fn to_bool(v: SVal) SVal:
    if v.kind == V_NUM or v.kind == V_BOOL:
        return svbool(v.num != 0.0)
    if v.kind == V_EMPTY:
        return svbool(false)

    if v.kind == V_TEXT:
        let u = v.text.upper()
        if u == "TRUE":
            return svbool(true)
        if u == "FALSE":
            return svbool(false)

        return sverr("#VALUE!")

    return v.clone()

fn rank(k: Int) Int:
    if k == V_NUM:
        return 0
    if k == V_TEXT:
        return 1

    return 2

fn cmp_vals(x: SVal, y: SVal) Int:
    if x.kind != y.kind:
        if rank(x.kind) < rank(y.kind):
            return -1

        return 1

    if x.kind == V_NUM or x.kind == V_BOOL:
        if x.num < y.num:
            return -1
        if x.num > y.num:
            return 1

        return 0

    if x.kind == V_TEXT:
        if x.text < y.text:
            return -1
        if x.text > y.text:
            return 1

        return 0

    return 0

fn zero_like(k: Int) SVal:
    if k == V_TEXT:
        return svtext("")
    if k == V_BOOL:
        return svbool(false)

    return svnum(0.0)

fn op_holds(op: String, c: Int) Bool:
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

fn compare_op(a: SVal, b: SVal, op: String) SVal:
    if a.kind == V_ERR:
        return a.clone()
    if b.kind == V_ERR:
        return b.clone()

    var c = 0

    if a.kind == V_EMPTY and b.kind == V_EMPTY:
        c = 0
    else if a.kind == V_EMPTY:
        c = cmp_vals(zero_like(b.kind), b)
    else if b.kind == V_EMPTY:
        c = cmp_vals(a, zero_like(a.kind))
    else:
        c = cmp_vals(a, b)

    return svbool(op_holds(op, c))

fn arith(op: String, a: SVal, b: SVal) SVal:
    let ca = to_num(a)
    if ca.kind == V_ERR:
        return ca

    let cb = to_num(b)
    if cb.kind == V_ERR:
        return cb

    let x = ca.num
    let y = cb.num
    var r = 0.0

    if op == "+":
        r = x + y
    else if op == "-":
        r = x - y
    else if op == "*":
        r = x * y
    else if op == "/":
        if y == 0.0:
            return sverr("#DIV/0!")

        r = x / y
    else:
        r = pow(x, y)

    return finite_or_num(r)

fn concat2(a: SVal, b: SVal) SVal:
    if a.kind == V_ERR:
        return a.clone()
    if b.kind == V_ERR:
        return b.clone()

    return svtext(strform(a) + strform(b))

fn ev(sh: SSheet, n: SNode) SVal:
    let k = n.kind
    if k == K_NUM:
        return svnum(n.num)
    if k == K_STR:
        return svtext(n.text)
    if k == K_BOOL:
        return svbool(n.num != 0.0)

    if k == K_REF:
        if not n.ok:
            return sverr("#REF!")

        return value_at(sh, mkkey(n.c1, n.r1))

    if k == K_RANGE:
        if not n.ok:
            return sverr("#REF!")

        return sverr("#VALUE!")

    if k == K_ERR:
        return sverr(n.text)
    if k == K_NAME:
        return sverr("#NAME?")

    if k == K_NEG or k == K_POS:
        let v = to_num(ev(sh, n.kids[0].clone()))
        if v.kind == V_ERR:
            return v.clone()
        if k == K_NEG:
            return svnum(-v.num)

        return v.clone()

    if k == K_BIN:
        let a = ev(sh, n.kids[0].clone())
        let b = ev(sh, n.kids[1].clone())
        if n.text == "&":
            return concat2(a, b)
        if (
            n.text == "="
            or n.text == "<>"
            or n.text == "<"
            or n.text == "<="
            or n.text == ">"
            or n.text == ">="
        ):
            return compare_op(a, b, n.text)

        return arith(n.text, a, b)

    if k == K_CALL:
        return callf(sh, n)

    return sverr("#PARSE!")

fn ev_top(sh: SSheet, n: SNode) SVal:
    let v = ev(sh, n)
    if v.kind == V_EMPTY:
        return svnum(0.0)

    return v.clone()

fn items_of(sh: SSheet, args: List[SNode]) List[SItem]:
    var out = List[SItem]()

    for a in args:
        if a.kind == K_RANGE:
            if not a.ok:
                out.append(SItem(v: sverr("#REF!"), rng: true))
            else:
                let rc = node_rect(a)
                let rend = rc.r2 + 1
                let cend = rc.c2 + 1
                for r in rc.r1..rend:
                    for c in rc.c1..cend:
                        out.append(SItem(v: value_at(sh, mkkey(c, r)), rng: true))
        else:
            out.append(SItem(v: ev(sh, a), rng: false))

    return out

fn nums_of(sh: SSheet, args: List[SNode]) SNums:
    let items = items_of(sh, args)
    var vals = List[Float]()

    for it in items:
        if it.v.kind == V_ERR:
            return SNums(err: it.v.clone(), failed: true, vals: vals)

        if it.rng:
            if it.v.kind == V_NUM:
                vals.append(it.v.num)
        else:
            let c = to_num(it.v)
            if c.kind == V_ERR:
                return SNums(err: c, failed: true, vals: vals)

            vals.append(c.num)

    return SNums(err: svempty(), failed: false, vals: vals)

fn agg_sum(sh: SSheet, args: List[SNode]) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let r = nums_of(sh, args)
    if r.failed:
        return r.err

    var s = 0.0
    for x in r.vals:
        s += x
    return finite_or_num(s)

fn agg_average(sh: SSheet, args: List[SNode]) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let r = nums_of(sh, args)
    if r.failed:
        return r.err
    if r.vals.length() == 0:
        return sverr("#DIV/0!")

    var s = 0.0
    for x in r.vals:
        s += x
    return finite_or_num(s / r.vals.length().to_float())

fn agg_minmax(sh: SSheet, args: List[SNode], want_max: Bool) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let r = nums_of(sh, args)
    if r.failed:
        return r.err
    if r.vals.length() == 0:
        return svnum(0.0)

    var m = r.vals[0]

    for x in r.vals:
        if want_max and x > m:
            m = x
        if (not want_max) and x < m:
            m = x

    return svnum(m)

fn agg_product(sh: SSheet, args: List[SNode]) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let r = nums_of(sh, args)
    if r.failed:
        return r.err
    if r.vals.length() == 0:
        return svnum(0.0)

    var p = 1.0
    for x in r.vals:
        p *= x
    return finite_or_num(p)

fn agg_median(sh: SSheet, args: List[SNode]) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let r = nums_of(sh, args)
    if r.failed:
        return r.err

    let cnt = r.vals.length()
    if cnt == 0:
        return sverr("#NUM!")

    var xs = List[Float]()
    for x in r.vals:
        xs.append(x)
    xs.sort()

    let h = cnt / 2
    if cnt % 2 == 1:
        return svnum(xs[h])

    return finite_or_num((xs[h - 1] + xs[h]) / 2.0)

fn agg_count(sh: SSheet, args: List[SNode], nonempty: Bool) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let items = items_of(sh, args)
    var cnt = 0

    for it in items:
        if nonempty:
            if it.v.kind != V_EMPTY:
                cnt += 1
        else if it.v.kind == V_NUM:
            cnt += 1

    return svnum(cnt.to_float())

fn fn_if(sh: SSheet, args: List[SNode]) SVal:
    if args.length() < 2 or args.length() > 3:
        return sverr("#VALUE!")

    let c = to_bool(ev(sh, args[0].clone()))
    if c.kind == V_ERR:
        return c.clone()
    if c.num != 0.0:
        return ev(sh, args[1].clone())
    if args.length() == 3:
        return ev(sh, args[2].clone())

    return svbool(false)

fn fn_iferror(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 2:
        return sverr("#VALUE!")

    let a = ev(sh, args[0].clone())
    if a.kind == V_ERR:
        return ev(sh, args[1].clone())

    return a.clone()

fn fn_choose(sh: SSheet, args: List[SNode]) SVal:
    if args.length() < 2:
        return sverr("#VALUE!")

    let iv = to_num(ev(sh, args[0].clone()))
    if iv.kind == V_ERR:
        return iv

    let f = floor(iv.num)
    let cnt = args.length() - 1
    if f < 1.0 or f > cnt.to_float():
        return sverr("#VALUE!")

    let idx = f.truncate_to_int().get(0)
    return ev(sh, args[idx].clone())

fn fn_andor(sh: SSheet, args: List[SNode], is_and: Bool) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let items = items_of(sh, args)
    var result = is_and
    var took = false

    for it in items:
        if it.v.kind == V_ERR:
            return it.v.clone()
        if it.rng and (it.v.kind == V_TEXT or it.v.kind == V_EMPTY):
            continue

        let b = to_bool(it.v)
        if b.kind == V_ERR:
            return b.clone()

        took = true

        if is_and:
            result = result and b.num != 0.0
        else:
            result = result or b.num != 0.0

    if not took:
        return sverr("#VALUE!")

    return svbool(result)

fn fn_not(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let b = to_bool(ev(sh, args[0].clone()))
    if b.kind == V_ERR:
        return b.clone()

    return svbool(b.num == 0.0)

fn round_half(y: Float) Float:
    let a = y.abs()
    let f = floor(a)
    var r = f
    if a - f >= 0.5:
        r = f + 1.0
    if y < 0.0:
        return -r

    return r

fn fn_num1(sh: SSheet, args: List[SNode], which: Int) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let c = to_num(ev(sh, args[0].clone()))
    if c.kind == V_ERR:
        return c.clone()

    let x = c.num
    if which == 0:
        return svnum(x.abs())
    if which == 1:
        return finite_or_num(floor(x))
    if x < 0.0:
        return sverr("#NUM!")

    return finite_or_num(sqrt(x))

fn fn_pow(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 2:
        return sverr("#VALUE!")

    let a = ev(sh, args[0].clone())
    let b = ev(sh, args[1].clone())
    return arith("^", a, b)

fn fn_mod(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 2:
        return sverr("#VALUE!")

    let a = to_num(ev(sh, args[0].clone()))
    if a.kind == V_ERR:
        return a.clone()

    let b = to_num(ev(sh, args[1].clone()))
    if b.kind == V_ERR:
        return b.clone()
    if b.num == 0.0:
        return sverr("#DIV/0!")

    return finite_or_num(a.num - b.num * floor(a.num / b.num))

fn fn_round(sh: SSheet, args: List[SNode]) SVal:
    if args.length() < 1 or args.length() > 2:
        return sverr("#VALUE!")

    let x = to_num(ev(sh, args[0].clone()))
    if x.kind == V_ERR:
        return x.clone()

    var d = 0.0

    if args.length() == 2:
        let dv = to_num(ev(sh, args[1].clone()))
        if dv.kind == V_ERR:
            return dv

        d = dv.num

    if d.abs() > 1000000.0:
        return sverr("#NUM!")

    let dt = d.truncate_to_int().get(0)
    if dt > 15 or dt < -15:
        return sverr("#NUM!")

    let p = pow(10.0, dt.to_float())
    let r = round_half(x.num * p) / p
    return finite_or_num(r)

fn fn_len(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let v = ev(sh, args[0].clone())
    if v.kind == V_ERR:
        return v.clone()

    return svnum(strform(v).scalar_length().to_float())

fn ascii_case(s: String, to_upper: Bool) String:
    var out = ""

    for ch in s.chars():
        if to_upper and is_lower(ch):
            out += ch.upper()
        else if (not to_upper) and is_upper(ch):
            out += ch.lower()
        else:
            out += ch

    return out

fn fn_text1(sh: SSheet, args: List[SNode], which: Int) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let v = ev(sh, args[0].clone())
    if v.kind == V_ERR:
        return v.clone()

    let s = strform(v)
    if which == 0:
        return svtext(ascii_case(s, true))
    if which == 1:
        return svtext(ascii_case(s, false))

    return svtext(s.fields().join(" "))

fn fn_leftright(sh: SSheet, args: List[SNode], left: Bool) SVal:
    if args.length() < 1 or args.length() > 2:
        return sverr("#VALUE!")

    let sv = ev(sh, args[0].clone())
    if sv.kind == V_ERR:
        return sv.clone()

    var k = 1.0

    if args.length() == 2:
        let kv = to_num(ev(sh, args[1].clone()))
        if kv.kind == V_ERR:
            return kv

        k = floor(kv.num)

    if k < 0.0:
        return sverr("#VALUE!")

    let s = strform(sv)
    let len = s.scalar_length()
    var kk = len
    if k < len.to_float():
        kk = k.truncate_to_int().get(0)
    if left:
        return svtext(s.slice_scalars(0, kk).get(""))

    return svtext(s.slice_scalars(len - kk, len).get(""))

fn fn_mid(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 3:
        return sverr("#VALUE!")

    let sv = ev(sh, args[0].clone())
    if sv.kind == V_ERR:
        return sv.clone()

    let stv = to_num(ev(sh, args[1].clone()))
    if stv.kind == V_ERR:
        return stv

    let lv = to_num(ev(sh, args[2].clone()))
    if lv.kind == V_ERR:
        return lv

    let st = floor(stv.num)
    let ln = floor(lv.num)
    if st < 1.0 or ln < 0.0:
        return sverr("#VALUE!")

    let s = strform(sv)
    let len = s.scalar_length()
    let si = st - 1.0
    if si >= len.to_float():
        return svtext("")

    let sidx = si.truncate_to_int().get(0)
    let remain = len - sidx
    var cnt = remain
    if ln < remain.to_float():
        cnt = ln.truncate_to_int().get(0)
    return svtext(s.slice_scalars(sidx, sidx + cnt).get(""))

fn fn_concat(sh: SSheet, args: List[SNode]) SVal:
    if args.length() == 0:
        return sverr("#VALUE!")

    let items = items_of(sh, args)
    var out = ""

    for it in items:
        if it.v.kind == V_ERR:
            return it.v.clone()

        out += strform(it.v)

    return svtext(out)

fn fn_substitute(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 3:
        return sverr("#VALUE!")

    let sv = ev(sh, args[0].clone())
    if sv.kind == V_ERR:
        return sv.clone()

    let ov = ev(sh, args[1].clone())
    if ov.kind == V_ERR:
        return ov

    let nv = ev(sh, args[2].clone())
    if nv.kind == V_ERR:
        return nv

    let old = strform(ov)
    let s = strform(sv)
    if old == "":
        return svtext(s)

    return svtext(s.replace(old, strform(nv)))

fn fn_value(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    return to_num(ev(sh, args[0].clone()))

fn fn_is(sh: SSheet, args: List[SNode], which: Int) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let v = ev(sh, args[0].clone())
    if which == 0:
        return svbool(v.kind == V_ERR)
    if which == 1:
        return svbool(v.kind == V_EMPTY)
    if which == 2:
        return svbool(v.kind == V_NUM)

    return svbool(v.kind == V_TEXT)

fn fn_rowcol(args: List[SNode], is_row: Bool) SVal:
    if args.length() != 1:
        return sverr("#VALUE!")

    let a = args[0]

    if a.kind == K_REF:
        if not a.ok:
            return sverr("#REF!")
        if is_row:
            return svnum(a.r1.to_float())

        return svnum((a.c1 + 1).to_float())

    if a.kind == K_RANGE:
        if not a.ok:
            return sverr("#REF!")

        let rc = node_rect(a)
        if is_row:
            return svnum(rc.r1.to_float())

        return svnum((rc.c1 + 1).to_float())

    return sverr("#VALUE!")

fn fn_index(sh: SSheet, args: List[SNode]) SVal:
    if args.length() < 2 or args.length() > 3:
        return sverr("#VALUE!")

    let a = args[0]
    if a.kind != K_RANGE:
        return sverr("#VALUE!")
    if not a.ok:
        return sverr("#REF!")

    let rc = node_rect(a)
    let rows = rc.r2 - rc.r1 + 1
    let cols = rc.c2 - rc.c1 + 1
    let rv = to_num(ev(sh, args[1].clone()))
    if rv.kind == V_ERR:
        return rv

    var row = 1.0
    var col = 1.0

    if args.length() == 3:
        let cv = to_num(ev(sh, args[2].clone()))
        if cv.kind == V_ERR:
            return cv

        row = rv.num
        col = cv.num
    else if rows == 1:
        col = rv.num
    else:
        row = rv.num

    let ri = floor(row)
    let ci = floor(col)
    if ri < 1.0 or ri > rows.to_float() or ci < 1.0 or ci > cols.to_float():
        return sverr("#REF!")

    let rr = rc.r1 + ri.truncate_to_int().get(0) - 1
    let cc = rc.c1 + ci.truncate_to_int().get(0) - 1
    return value_at(sh, mkkey(cc, rr))

fn fn_countif(sh: SSheet, args: List[SNode]) SVal:
    if args.length() != 2:
        return sverr("#VALUE!")

    let a = args[0]
    if a.kind != K_RANGE:
        return sverr("#VALUE!")

    let cv = ev(sh, args[1].clone())
    if cv.kind == V_ERR:
        return cv
    if not a.ok:
        return sverr("#REF!")

    var op = "="
    var opnd = cv.clone()

    if cv.kind == V_TEXT:
        let s = cv.text
        let len = s.scalar_length()
        var rest = s.clone()

        if s.starts_with(">="):
            op = ">="
            rest = s.slice_scalars(2, len).get("")
        else if s.starts_with("<="):
            op = "<="
            rest = s.slice_scalars(2, len).get("")
        else if s.starts_with("<>"):
            op = "<>"
            rest = s.slice_scalars(2, len).get("")
        else if s.starts_with(">"):
            op = ">"
            rest = s.slice_scalars(1, len).get("")
        else if s.starts_with("<"):
            op = "<"
            rest = s.slice_scalars(1, len).get("")
        else if s.starts_with("="):
            op = "="
            rest = s.slice_scalars(1, len).get("")

        if let x = parse_number(rest):
            opnd = svnum(x)
        else:
            opnd = svtext(rest)

    let rc = node_rect(a)
    let rend = rc.r2 + 1
    let cend = rc.c2 + 1
    var cnt = 0

    for r in rc.r1..rend:
        for c in rc.c1..cend:
            let v = value_at(sh, mkkey(c, r))

            if v.kind == opnd.kind:
                if op_holds(op, cmp_vals(v, opnd)):
                    cnt += 1
            else if op == "<>" and v.kind != V_EMPTY:
                cnt += 1

    return svnum(cnt.to_float())

fn callf(sh: SSheet, n: SNode) SVal:
    let nm = n.text
    let args = n.kids
    if nm == "SUM":
        return agg_sum(sh, args.clone())
    if nm == "AVERAGE":
        return agg_average(sh, args.clone())
    if nm == "MIN":
        return agg_minmax(sh, args.clone(), false)
    if nm == "MAX":
        return agg_minmax(sh, args.clone(), true)
    if nm == "PRODUCT":
        return agg_product(sh, args.clone())
    if nm == "MEDIAN":
        return agg_median(sh, args.clone())
    if nm == "COUNT":
        return agg_count(sh, args.clone(), false)
    if nm == "COUNTA":
        return agg_count(sh, args.clone(), true)
    if nm == "IF":
        return fn_if(sh, args.clone())
    if nm == "IFERROR":
        return fn_iferror(sh, args.clone())
    if nm == "CHOOSE":
        return fn_choose(sh, args.clone())
    if nm == "AND":
        return fn_andor(sh, args.clone(), true)
    if nm == "OR":
        return fn_andor(sh, args.clone(), false)
    if nm == "NOT":
        return fn_not(sh, args.clone())
    if nm == "ABS":
        return fn_num1(sh, args.clone(), 0)
    if nm == "INT":
        return fn_num1(sh, args.clone(), 1)
    if nm == "SQRT":
        return fn_num1(sh, args.clone(), 2)
    if nm == "POW":
        return fn_pow(sh, args.clone())
    if nm == "MOD":
        return fn_mod(sh, args.clone())
    if nm == "ROUND":
        return fn_round(sh, args.clone())
    if nm == "LEN":
        return fn_len(sh, args.clone())
    if nm == "UPPER":
        return fn_text1(sh, args.clone(), 0)
    if nm == "LOWER":
        return fn_text1(sh, args.clone(), 1)
    if nm == "TRIM":
        return fn_text1(sh, args.clone(), 2)
    if nm == "LEFT":
        return fn_leftright(sh, args.clone(), true)
    if nm == "RIGHT":
        return fn_leftright(sh, args.clone(), false)
    if nm == "MID":
        return fn_mid(sh, args.clone())
    if nm == "CONCAT":
        return fn_concat(sh, args.clone())
    if nm == "SUBSTITUTE":
        return fn_substitute(sh, args.clone())
    if nm == "VALUE":
        return fn_value(sh, args.clone())
    if nm == "ISERROR":
        return fn_is(sh, args.clone(), 0)
    if nm == "ISBLANK":
        return fn_is(sh, args.clone(), 1)
    if nm == "ISNUMBER":
        return fn_is(sh, args.clone(), 2)
    if nm == "ISTEXT":
        return fn_is(sh, args.clone(), 3)
    if nm == "ROW":
        return fn_rowcol(args, true)
    if nm == "COLUMN":
        return fn_rowcol(args, false)
    if nm == "INDEX":
        return fn_index(sh, args.clone())
    if nm == "COUNTIF":
        return fn_countif(sh, args.clone())

    return sverr("#NAME?")

// ---------- dependencies and recalculation ----------

fn is_formula(sh: SSheet, k: Int) Bool:
    if let c = sh.cells.get(k):
        return c.mode != 0

    return false

fn depends_on(sh: SSheet, f: Int, x: Int) Bool:
    if let c = sh.cells.get(f):
        for r in c.precs:
            if rect_has(r, x):
                return true
    return false

fn cell_depends(c: SCell, x: Int) Bool:
    for r in c.precs:
        if rect_has(r, x):
            return true
    return false

fn ast_of(sh: SSheet, k: Int) SNode:
    if let c = sh.cells.get(k):
        return c.ast.clone()

    return SNode(kind: K_NUM)

fn mode_of(sh: SSheet, k: Int) Int:
    if let c = sh.cells.get(k):
        return c.mode

    return 0

fn strong(var t: STarjan, v: Int) Unit:
    t.index[v] = t.counter
    t.low[v] = t.counter
    t.counter += 1
    t.stk.append(v)
    t.onst[v] = true

    var e = 0

    while e < t.adj[v].length():
        let w = t.adj[v][e]
        e += 1

        if t.index[w] < 0:
            strong(var t, w)
            if t.low[w] < t.low[v]:
                t.low[v] = t.low[w]
        else if t.onst[w]:
            if t.index[w] < t.low[v]:
                t.low[v] = t.index[w]

    if t.low[v] == t.index[v]:
        var comp = List[Int]()
        var going = true

        while going:
            let x = t.stk.pop().get(0)
            t.onst[x] = false
            comp.append(x)
            if x == v:
                going = false

        t.comps.append(comp)

fn self_loop(adj: List[Int], v: Int) Bool:
    for w in adj:
        if w == v:
            return true
    return false

fn recalc(var sh: SSheet, changed: List[Int]) Int:
    var seen = Set[Int]()
    var queue = List[Int]()
    var aff = List[Int]()

    for k in changed:
        if not seen.contains(k):
            seen.add(k)
            queue.append(k)
            if is_formula(sh, k):
                aff.append(k)

    var head = 0

    while head < queue.length():
        let x = queue[head]
        head += 1

        for e in sh.cells.entries():
            let f = e.key

            if not seen.contains(f) and cell_depends(e.value, x):
                seen.add(f)
                queue.append(f)
                aff.append(f)

    let m = aff.length()
    var adj = List[List[Int]]()
    var index = List[Int]()
    var low = List[Int]()
    var onst = List[Bool]()

    for i in 0..m:
        var lst = List[Int]()
        for j in 0..m:
            if depends_on(sh, aff[i], aff[j]):
                lst.append(j)
        adj.append(lst)
        index.append(-1)
        low.append(0)
        onst.append(false)

    var t = STarjan(
        adj: adj, index: index, low: low, onst: onst, stk: List[Int](),
        comps: List[List[Int]](), counter: 0
    )
    for v in 0..m:
        if t.index[v] < 0:
            strong(var t, v)

    for comp in t.comps:
        if comp.length() == 1 and not self_loop(t.adj[comp[0]], comp[0]):
            let k = aff[comp[0]]

            if mode_of(sh, k) == 2:
                sh.vals[k] = sverr("#PARSE!")
            else:
                let ast = ast_of(sh, k)
                let v = ev_top(sh, ast)
                sh.vals[k] = v
        else:
            for x in comp:
                sh.vals[aff[x]] = sverr("#CYCLE!")

    sh.evals += m
    return m

fn assign(var sh: SSheet, k: Int, raw: String) Unit:
    if raw == "":
        sh.cells.remove(k)
        sh.vals.remove(k)
        return

    let c = make_cell(raw.clone())

    if c.mode == 0:
        sh.vals[k] = const_value(raw)
    else:
        sh.vals.remove(k)

    sh.cells[k] = c

fn dependents_of(sh: SSheet, x0: Int) List[Int]:
    var seen = Set[Int]()
    var queue = List[Int]()
    var out = List[Int]()
    queue.append(x0)

    var head = 0

    while head < queue.length():
        let x = queue[head]
        head += 1

        for e in sh.cells.entries():
            let f = e.key

            if not seen.contains(f) and cell_depends(e.value, x):
                seen.add(f)
                queue.append(f)
                out.append(f)

    out.sort()
    return out

fn precedents_of(sh: SSheet, k: Int) List[Int]:
    var seen = Set[Int]()
    var out = List[Int]()

    if let c = sh.cells.get(k):
        for r in c.precs:
            let rend = r.r2 + 1
            let cend = r.c2 + 1

            for rr in r.r1..rend:
                for cc in r.c1..cend:
                    let key = mkkey(cc, rr)

                    if not seen.contains(key):
                        seen.add(key)
                        out.append(key)

    out.sort()
    return out

// ---------- cell references in commands ----------

fn cell_key(s: String) Int:
    let cs = s.chars()
    let n = cs.length()
    if n < 2 or n > 4:
        return -1
    if not is_alpha(cs[0]):
        return -1

    var i = 1

    while i < n:
        if not is_digit(cs[i]):
            return -1

        i += 1

    if cs[1] == "0":
        return -1

    let row = sub(cs, 1, n).parse_int().get(0)
    if row < 1 or row > 999:
        return -1

    return mkkey(letter_idx(cs[0]), row)

fn parse_range(s: String) SRect?:
    let parts = s.split(":")

    if parts.length() == 1:
        let k = cell_key(parts[0])
        if k < 0:
            return none

        return SRect(c1: keycol(k), r1: keyrow(k), c2: keycol(k), r2: keyrow(k))

    if parts.length() == 2:
        let a = cell_key(parts[0])
        let b = cell_key(parts[1])
        if a < 0 or b < 0:
            return none

        return norm_rect(keycol(a), keyrow(a), keycol(b), keyrow(b))

    return none

fn rest_after(line: String, skip: Int) String:
    let cs = line.chars()
    let n = cs.length()
    var i = 0
    var k = 0

    while k < skip:
        while i < n and is_space(cs[i]):
            i += 1
        while i < n and not is_space(cs[i]):
            i += 1
        k += 1

    return sub(cs, i, n).trim()

// ---------- formula copy (reference shifting) ----------

fn shift_corner(cs: List[String], pos: Int, dr: Int, dc: Int) SShift:
    let r = scan_ref(cs, pos)
    if r.endp < 0:
        return SShift(text: "", off: false, endp: pos)
    if not r.ok:
        return SShift(text: sub(cs, pos, r.endp), off: false, endp: r.endp)

    var nc = r.c1
    var nr = r.r1
    if not r.dc1:
        nc = r.c1 + dc
    if not r.dr1:
        nr = r.r1 + dr
    if nc < 0 or nc > 25 or nr < 1 or nr > 999:
        return SShift(text: "#REF!", off: true, endp: r.endp)

    var s = ""
    if r.dc1:
        s += "$"
    s += LETTERS.slice_scalars(nc, nc + 1).get("")
    if r.dr1:
        s += "$"
    s += nr.to_string()
    return SShift(text: s, off: false, endp: r.endp)

fn shift_formula(src: String, dr: Int, dc: Int) String:
    let cs = src.chars()
    let lx = tokenize(cs)
    if lx.bad:
        return src.clone()

    var out = ""
    var cur = 0

    for t in lx.toks:
        if t.kind == K_REF:
            let a = shift_corner(cs, t.pos, dr, dc)
            out += sub(cs, cur, t.pos)
            out += a.text
            cur = t.endp
        else if t.kind == K_RANGE:
            let a = shift_corner(cs, t.pos, dr, dc)
            let b = shift_corner(cs, a.endp + 1, dr, dc)
            out += sub(cs, cur, t.pos)

            if a.off or b.off:
                out += "#REF!"
            else:
                out += a.text + ":" + b.text

            cur = t.endp

    out += sub(cs, cur, cs.length())
    return out

// ---------- CSV ----------

fn parse_block(block: List[String]) List[List[String]]:
    var text = ""

    for i in 0..block.length():
        if i > 0:
            text += "\n"
        text += block[i]

    let cs = text.chars()
    let n = cs.length()
    var recs = List[List[String]]()
    var fields = List[String]()
    var field = ""
    var inq = false
    var has = false
    var i = 0

    while i < n:
        let c = cs[i]

        if inq:
            if c == "\"":
                if i + 1 < n and cs[i + 1] == "\"":
                    field += "\""
                    i += 2
                else:
                    inq = false
                    i += 1
            else:
                field += c
                i += 1
        else if c == "\r":
            i += 1
        else if c == "\n":
            if has:
                fields.append(field)
                recs.append(fields)

            fields = List[String]()
            field = ""
            has = false
            i += 1
        else:
            has = true

            if c == "\"":
                inq = true
            else if c == ",":
                fields.append(field)
                field = ""
            else:
                field += c

            i += 1

    if has:
        fields.append(field)
        recs.append(fields)

    return recs

fn csv_quote(s: String) String:
    var need = false
    if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
        need = true
    if s.starts_with(" ") or s.ends_with(" "):
        need = true
    if not need:
        return s.clone()

    return "\"" + s.replace("\"", "\"\"") + "\""

// ---------- command implementations ----------

fn cell_text(sh: SSheet, k: Int, fml: Bool) String:
    if fml:
        if let c = sh.cells.get(k):
            return c.raw.clone()

        return ""

    return strform(value_at(sh, k))

fn default_rect(sh: SSheet) SRect?:
    var any = false
    var maxc = 0
    var maxr = 0

    for e in sh.cells.entries():
        let c = keycol(e.key)
        let r = keyrow(e.key)

        if not any:
            any = true
            maxc = c
            maxr = r
        else:
            maxc = imax(maxc, c)
            maxr = imax(maxr, r)

    if not any:
        return none

    return SRect(c1: 0, r1: 1, c2: maxc, r2: maxr)

fn view_args(words: List[String], is_export: Bool) SView:
    var nwords = 0
    var nrange = 0
    var fml = false
    var rtext = ""
    var i = 1

    while i < words.length():
        let a = words[i]

        if a == "formulas" or a == "values":
            nwords += 1
            if a == "formulas":
                fml = true
        else:
            nrange += 1
            rtext = a.clone()

        i += 1

    let empty_rect = SRect(c1: 0, r1: 1, c2: 0, r2: 1)
    if nwords > 1 or nrange > 1:
        return SView(
            usage: true, bad: "", fml: false, has_range: false, rect: empty_rect
        )
    if fml and not is_export:
        return SView(
            usage: true, bad: "", fml: false, has_range: false, rect: empty_rect
        )
    if nrange == 0:
        return SView(
            usage: false, bad: "", fml: fml, has_range: false, rect: empty_rect
        )
    if let rc = parse_range(rtext):
        return SView(usage: false, bad: "", fml: fml, has_range: true, rect: rc)

    return SView(usage: false, bad: rtext, fml: fml, has_range: false, rect: empty_rect)

fn run_view(sh: SSheet, words: List[String], is_export: Bool) Unit:
    var v = view_args(words, is_export)

    if v.usage:
        if is_export:
            print("error: usage: export [formulas] [RANGE]")
        else:
            print("error: usage: print [RANGE]")

        return

    if v.bad != "":
        print("error: bad range '" + v.bad + "'")
        return

    var rc = v.rect.clone()

    if not v.has_range:
        if let d = default_rect(sh):
            rc = d
        else:
            print("(empty sheet)")
            return

    let rend = rc.r2 + 1
    let cend = rc.c2 + 1

    for r in rc.r1..rend:
        var parts = List[String]()

        for c in rc.c1..cend:
            let txt = cell_text(sh, mkkey(c, r), v.fml)

            if is_export:
                parts.append(csv_quote(txt))
            else:
                parts.append(txt)

        if is_export:
            print(parts.join(","))
        else:
            print(parts.join(" | "))

fn run_import(var sh: SSheet, words: List[String], block: List[String]) Unit:
    if words.length() != 2:
        print("error: usage: import CELL")
        return

    let k0 = cell_key(words[1])

    if k0 < 0:
        print("error: bad cell reference '" + words[1] + "'")
        return

    let recs = parse_block(block)
    let nrec = recs.length()
    var ncol = 0
    for rec in recs:
        ncol = imax(ncol, rec.length())

    let r0 = keyrow(k0)
    let c0 = keycol(k0)

    if nrec > 0 and r0 + nrec - 1 > 999:
        print("error: import out of range")
        return

    if ncol > 0 and c0 + ncol - 1 > 25:
        print("error: import out of range")
        return

    var changed = List[Int]()

    for i in 0..nrec:
        let rec = recs[i]

        for j in 0..rec.length():
            let k = mkkey(c0 + j, r0 + i)
            assign(var sh, k, rec[j].trim())
            changed.append(k)

    let n = recalc(var sh, changed)
    print(
        "imported "
        + nrec.to_string()
        + " rows, "
        + ncol.to_string()
        + " columns; recalc "
        + n.to_string()
    )

fn run_cmd(var sh: SSheet, words: List[String], t: String) Unit:
    let cmd = words[0]
    let na = words.length() - 1

    if cmd == "set":
        if na < 1:
            print("error: usage: set CELL VALUE")
            return

        let k = cell_key(words[1])

        if k < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        assign(var sh, k, rest_after(t, 2))

        let n = recalc(var sh, [k])
        print("recalc " + n.to_string())
    else if cmd == "clear":
        if na != 1:
            print("error: usage: clear CELL")
            return

        let k = cell_key(words[1])

        if k < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        assign(var sh, k, "")

        let n = recalc(var sh, [k])
        print("recalc " + n.to_string())
    else if cmd == "get":
        if na != 1:
            print("error: usage: get CELL")
            return

        let k = cell_key(words[1])

        if k < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        if let v = sh.vals.get(k):
            if v.kind != V_EMPTY:
                print(strform(v))
                return

        print("(empty)")
    else if cmd == "show":
        if na != 1:
            print("error: usage: show CELL")
            return

        let k = cell_key(words[1])

        if k < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        let name = name_of(k)

        if let c = sh.cells.get(k):
            if c.mode == 0:
                print(name + ": " + c.raw)
            else:
                print(name + ": " + c.raw + " => " + strform(value_at(sh, k)))
        else:
            print(name + ": (empty)")
    else if cmd == "copy":
        if na != 2:
            print("error: usage: copy SRC DST")
            return

        let sk = cell_key(words[1])

        if sk < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        if let dst = parse_range(words[2]):
            var raw_src = ""
            var fml = false

            if let c = sh.cells.get(sk):
                raw_src = c.raw.clone()
                fml = c.mode != 0

            let srow = keyrow(sk)
            let scol = keycol(sk)
            var changed = List[Int]()
            let rend = dst.r2 + 1
            let cend = dst.c2 + 1

            for r in dst.r1..rend:
                for c in dst.c1..cend:
                    let k = mkkey(c, r)
                    changed.append(k)

                    if raw_src == "":
                        assign(var sh, k, "")
                    else if fml:
                        let body = raw_src.slice_scalars(
                            1, raw_src.scalar_length()
                        ).get("")
                        assign(var sh, k, "=" + shift_formula(body, r - srow, c - scol))
                    else:
                        assign(var sh, k, raw_src.clone())

            let n = recalc(var sh, changed)
            print("recalc " + n.to_string())
        else:
            print("error: bad range '" + words[2] + "'")
    else if cmd == "precedents" or cmd == "dependents":
        if na != 1:
            print("error: usage: " + cmd + " CELL")
            return

        let k = cell_key(words[1])

        if k < 0:
            print("error: bad cell reference '" + words[1] + "'")
            return

        var ks = List[Int]()

        if cmd == "precedents":
            ks = precedents_of(sh, k)
        else:
            ks = dependents_of(sh, k)

        if ks.length() == 0:
            print("(none)")
        else:
            var names = List[String]()
            for x in ks:
                names.append(name_of(x))
            print(names.join(" "))
    else if cmd == "print":
        run_view(sh, words, false)
    else if cmd == "export":
        run_view(sh, words, true)
    else if cmd == "stats":
        var nf = 0
        for e in sh.cells.entries():
            if e.value.mode != 0:
                nf += 1
        print(
            "cells "
            + sh.cells.length().to_string()
            + " formulas "
            + nf.to_string()
            + " evals "
            + sh.evals.to_string()
        )
    else:
        print("error: unknown command '" + cmd + "'")

// ---------- input and main ----------

fn collect_lines() List[String]!:
    var out = List[String]()
    for line in stdin() | lines(max_bytes: none):
        out.append(line)
    return ok(out)

export fn main() Int:
    let all = collect_lines().get([])
    let n = all.length()
    var sh = SSheet(cells: Map[Int, SCell](), vals: Map[Int, SVal](), evals: 0)
    var i = 0

    while i < n:
        let raw_line = all[i]
        i += 1

        let t = raw_line.trim()
        if t == "" or t.starts_with("#"):
            continue

        print("> " + raw_line.trim_end())

        let words = t.fields()

        if words[0] == "import":
            var block = List[String]()

            while i < n and all[i] != ".":
                block.append(all[i].clone())
                i += 1

            if i < n:
                i += 1
            run_import(var sh, words, block)
        else:
            run_cmd(var sh, words, t)

    return 0
