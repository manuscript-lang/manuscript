import (
    bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right from "@std/math/math.ms",
    from_scalars from "@std/string.ms",
    read_all from "@std/io/streams.ms",
    stdin, stdout from "@std/io/io.ms",
)

let TWO32 = 4294967296
let TWO31 = 2147483648
let MAXU32 = 4294967295
let MEMSIZE = 4096
let WS = " \t\r"
let DIGITS = "0123456789"
let ALNUM = "_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
let IDSTART = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
let IDCHARS = "._0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

type Sym:
    is_text: Bool
    is_equ: Bool
    value: Int
    expr: String

type Stmt:
    line: Int
    kind: Int
    mnem: String
    ops: List[String]
    addr: Int
    vals: List[Int]
    count: Int
    fill: String

type Term:
    neg: Bool
    kind: Int
    val: Int
    name: String

type Ev:
    err: String
    val: Int

type TermsRes:
    err: String
    terms: List[Term]

type MemRes:
    err: String
    base: Int
    terms: List[String]

type StrRes:
    err: String
    vals: List[Int]

type OpInfo:
    id: Int
    nargs: Int
    c1: String
    c2: String

type Opv:
    err: String
    k: Int
    r: Int
    v: Int

type Asm:
    text: Bool
    tc: Int
    dc: Int
    budget: Int
    syms: Map[String, Sym]
    stmts: List[Stmt]

type Vm:
    ops: List[Int]
    k1: List[Int]
    r1: List[Int]
    v1: List[Int]
    k2: List[Int]
    r2: List[Int]
    v2: List[Int]
    lines: List[Int]
    regs: List[Int]
    mem: List[Int]
    input: List[Int]
    inpos: Int
    zf: Bool
    lf: Bool
    steps: Int
    budget: Int
    pc: Int
    done: Bool
    trapped: Bool
    trapmsg: String
    out: List[String]
    chartab: List[String]
    last_nl: Bool
    has_out: Bool
    aerr: String
    aline: Int

// ---------- small helpers ----------

fn wrap32(x: Int) Int:
    var r = x % TWO32
    if r < 0:
        r += TWO32
    if r >= TWO31:
        r -= TWO32
    return r

fn sub(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var i = a

    while i < b:
        s += cs[i]
        i += 1

    return s

fn reg_index(name: String) Int:
    let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    for i in 0..10:
        if names[i] == name: return i
    return -1

fn is_ident(s: String) Bool:
    let cs = s.chars()
    let n = cs.length()
    if n == 0: return false
    if not IDSTART.contains(cs[0]): return false

    for i in 1..n:
        if not IDCHARS.contains(cs[i]): return false
    return true

fn all_digits(s: String) Bool:
    let cs = s.chars()
    if cs.length() == 0: return false

    for c in cs:
        if not DIGITS.contains(c): return false
    return true

// Index just past a run of non-whitespace from `from`.
fn skip_ws(cs: List[String], from: Int) Int:
    var i = from

    while i < cs.length():
        if not WS.contains(cs[i]): break

        i += 1

    return i

// Length of a character literal starting at i (0 when there is none).
fn char_lit_len(cs: List[String], i: Int) Int:
    let n = cs.length()
    if i + 1 >= n: return 0

    if cs[i + 1] == "\\":
        if i + 3 < n:
            if cs[i + 3] == "'": return 4
        return 0

    if cs[i + 1] == "'": return 0

    if i + 2 < n:
        if cs[i + 2] == "'": return 3
    return 0

fn escape_code(c: String) Int:
    if c == "n": return 10
    if c == "t": return 9
    if c == "0": return 0
    if c == "\\": return 92
    if c == "'": return 39
    if c == "\"": return 34

    return -1

// Value of a character literal of length L at i, or -1 when invalid.
fn char_value(cs: List[String], i: Int, len: Int) Int:
    if len == 3:
        let code = cs[i + 1].scalar_at(0)
        if code > 127: return -1

        return code

    return escape_code(cs[i + 2])

fn digit_value(c: String) Int:
    let code = c.scalar_at(0)
    if code >= 48 and code <= 57: return code - 48
    if code >= 97 and code <= 102: return code - 87
    if code >= 65 and code <= 70: return code - 55

    return -1

// Number token value; -1 invalid, -2 out of range.
fn parse_num(tok: String) Int:
    let cs = tok.chars()
    let n = cs.length()
    var base = 10
    var start = 0

    if n > 2 and cs[0] == "0":
        if cs[1] == "x":
            base = 16
            start = 2
        else if cs[1] == "b":
            base = 2
            start = 2

    if start >= n: return -1

    var v = 0
    var i = start

    while i < n:
        let d = digit_value(cs[i])
        if d < 0 or d >= base: return -1

        v = v * base + d
        if v > MAXU32:
            v = TWO32
        i += 1

    if v > MAXU32: return -2

    return v

// Splits at commas outside brackets and character literals; parts are trimmed.
fn split_top(s: String) List[String]:
    let cs = s.chars()
    let n = cs.length()
    var out = List[String]()
    var depth = 0
    var start = 0
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "'":
            let L = char_lit_len(cs, i)

            if L > 0:
                i += L
                continue

        if c == "[":
            depth += 1
        else if c == "]":
            if depth > 0:
                depth -= 1
        else if c == "," and depth == 0:
            out.append(sub(cs, start, i).trim_chars(WS))
            start = i + 1

        i += 1

    out.append(sub(cs, start, n).trim_chars(WS))
    return out

// Splits memory-operand contents at top-level + and -. Each piece keeps its sign as the first char.
fn split_terms(s: String) List[String]:
    let cs = s.chars()
    let n = cs.length()
    var out = List[String]()
    var sign = "+"
    var start = 0

    if n > 0:
        if cs[0] == "+" or cs[0] == "-":
            sign = cs[0].clone()
            start = 1

    var i = start

    while i < n:
        let c = cs[i]

        if c == "'":
            let L = char_lit_len(cs, i)

            if L > 0:
                i += L
                continue

        if c == "+" or c == "-":
            out.append(sign + sub(cs, start, i))
            sign = c.clone()
            start = i + 1

        i += 1

    out.append(sign + sub(cs, start, n))
    return out

// Validates a memory operand; the base register (or -1) and the expression terms.
fn parse_mem(op: String) MemRes:
    let cs = op.chars()
    let n = cs.length()
    let bad = "invalid operand '" + op + "'"
    var terms = List[String]()
    if n < 2 or cs[n - 1] != "]": return MemRes(err: bad, base: -1, terms: terms)

    let pieces = split_terms(sub(cs, 1, n - 1))
    var base = -1

    for p in pieces:
        let pc = p.chars()
        let sign = pc[0]
        let text = sub(pc, 1, pc.length()).trim_chars(WS)
        if text == "": return MemRes(err: bad, base: -1, terms: terms)

        let r = reg_index(text)

        if r >= 0:
            if sign == "-" or base >= 0: return MemRes(err: bad, base: -1, terms: terms)

            base = r
        else:
            terms.append(p.clone())

    return MemRes(err: "", base: base, terms: terms)

fn parse_string(s: String) StrRes:
    let cs = s.chars()
    let n = cs.length()
    var vals = List[Int]()
    let bad = "invalid string"
    if n < 2 or cs[0] != "\"": return StrRes(err: bad, vals: vals)

    var i = 1

    while true:
        if i >= n: return StrRes(err: bad, vals: vals)

        let c = cs[i]

        if c == "\"":
            if i != n - 1: return StrRes(err: bad, vals: vals)

            break

        if c == "\\":
            if i + 1 >= n: return StrRes(err: bad, vals: vals)

            let e = escape_code(cs[i + 1])
            if e < 0: return StrRes(err: bad, vals: vals)

            vals.append(e)
            i += 2
            continue

        // Ordinary scalar: append its UTF-8 bytes.
        let code = c.scalar_at(0)

        if code < 128:
            vals.append(code)
        else if code < 2048:
            vals.append(192 + code / 64)
            vals.append(128 + code % 64)
        else if code < 65536:
            vals.append(224 + code / 4096)
            vals.append(128 + (code / 64) % 64)
            vals.append(128 + code % 64)
        else:
            vals.append(240 + code / 262144)
            vals.append(128 + (code / 4096) % 64)
            vals.append(128 + (code / 64) % 64)
            vals.append(128 + code % 64)

        i += 1

    return StrRes(err: "", vals: vals)

// ---------- expressions ----------

fn scan_terms(t: String) TermsRes:
    let cs = t.chars()
    let n = cs.length()
    let bad = "invalid expression '" + t + "'"
    var terms = List[Term]()
    if n == 0: return TermsRes(err: bad, terms: terms)

    var neg = false
    var i = 0

    if cs[0] == "+":
        i = 1
    else if cs[0] == "-":
        neg = true
        i = 1

    while true:
        i = skip_ws(cs, i)
        if i >= n: return TermsRes(err: bad, terms: terms)

        let c = cs[i]

        if DIGITS.contains(c):
            var j = i

            while j < n:
                if not ALNUM.contains(cs[j]): break

                j += 1

            let v = parse_num(sub(cs, i, j))
            if v == -1: return TermsRes(err: bad, terms: terms)
            if v == -2: return TermsRes(err: "immediate out of range", terms: terms)

            terms.append(Term(neg: neg, kind: 0, val: v, name: ""))
            i = j
        else if c == "'":
            let L = char_lit_len(cs, i)
            if L == 0: return TermsRes(err: bad, terms: terms)

            let v = char_value(cs, i, L)
            if v < 0: return TermsRes(err: bad, terms: terms)

            terms.append(Term(neg: neg, kind: 0, val: v, name: ""))
            i += L
        else if IDSTART.contains(c):
            var j = i

            while j < n:
                if not IDCHARS.contains(cs[j]): break

                j += 1

            terms.append(Term(neg: neg, kind: 1, val: 0, name: sub(cs, i, j)))
            i = j
        else:
            return TermsRes(err: bad, terms: terms)

        i = skip_ws(cs, i)
        if i >= n: break

        let op = cs[i]

        if op == "+":
            neg = false
        else if op == "-":
            neg = true
        else:
            return TermsRes(err: bad, terms: terms)

        i += 1

    return TermsRes(err: "", terms: terms)

// Evaluates an expression. `stack` holds the .equ names being evaluated (for cycle detection).
fn eval(text: String, syms: Map[String, Sym], stack: String) Ev:
    let t = text.trim_chars(WS)
    let sr = scan_terms(t)
    if sr.err != "": return Ev(err: sr.err, val: 0)

    var total = 0

    for term in sr.terms:
        var v = term.val

        if term.kind == 1:
            if not syms.contains(term.name):
                return Ev(err: "undefined symbol '" + term.name + "'", val: 0)

            let s = syms.get(
                term.name
            ).get(Sym(is_text: false, is_equ: false, value: 0, expr: ""))

            if s.is_equ:
                let key = "|" + term.name + "|"
                if stack.contains(key):
                    return Ev(err: "circular definition of '" + term.name + "'", val: 0)

                let inner = eval(s.expr, syms, stack + key)
                if inner.err != "": return Ev(err: inner.err, val: 0)

                v = inner.val
            else:
                v = s.value

        if term.neg:
            total -= v
        else:
            total += v

        total = wrap32(total)

    return Ev(err: "", val: total)

// ---------- instruction table ----------

fn op_info(mn: String) OpInfo:
    if mn == "mov": return OpInfo(id: 0, nargs: 2, c1: "RM", c2: "RIM")
    if mn == "add": return OpInfo(id: 1, nargs: 2, c1: "R", c2: "RIM")
    if mn == "sub": return OpInfo(id: 2, nargs: 2, c1: "R", c2: "RIM")
    if mn == "mul": return OpInfo(id: 3, nargs: 2, c1: "R", c2: "RIM")
    if mn == "div": return OpInfo(id: 4, nargs: 2, c1: "R", c2: "RIM")
    if mn == "mod": return OpInfo(id: 5, nargs: 2, c1: "R", c2: "RIM")
    if mn == "and": return OpInfo(id: 6, nargs: 2, c1: "R", c2: "RIM")
    if mn == "or": return OpInfo(id: 7, nargs: 2, c1: "R", c2: "RIM")
    if mn == "xor": return OpInfo(id: 8, nargs: 2, c1: "R", c2: "RIM")
    if mn == "shl": return OpInfo(id: 9, nargs: 2, c1: "R", c2: "RIM")
    if mn == "shr": return OpInfo(id: 10, nargs: 2, c1: "R", c2: "RIM")
    if mn == "sar": return OpInfo(id: 11, nargs: 2, c1: "R", c2: "RIM")
    if mn == "cmp": return OpInfo(id: 12, nargs: 2, c1: "R", c2: "RIM")
    if mn == "neg": return OpInfo(id: 13, nargs: 1, c1: "R", c2: "")
    if mn == "not": return OpInfo(id: 14, nargs: 1, c1: "R", c2: "")
    if mn == "inc": return OpInfo(id: 15, nargs: 1, c1: "R", c2: "")
    if mn == "dec": return OpInfo(id: 16, nargs: 1, c1: "R", c2: "")
    if mn == "lea": return OpInfo(id: 17, nargs: 2, c1: "R", c2: "M")
    if mn == "push": return OpInfo(id: 18, nargs: 1, c1: "RIM", c2: "")
    if mn == "pop": return OpInfo(id: 19, nargs: 1, c1: "R", c2: "")
    if mn == "jmp": return OpInfo(id: 20, nargs: 1, c1: "I", c2: "")
    if mn == "je" or mn == "jz": return OpInfo(id: 21, nargs: 1, c1: "I", c2: "")
    if mn == "jne" or mn == "jnz": return OpInfo(id: 22, nargs: 1, c1: "I", c2: "")
    if mn == "jl": return OpInfo(id: 23, nargs: 1, c1: "I", c2: "")
    if mn == "jle": return OpInfo(id: 24, nargs: 1, c1: "I", c2: "")
    if mn == "jg": return OpInfo(id: 25, nargs: 1, c1: "I", c2: "")
    if mn == "jge": return OpInfo(id: 26, nargs: 1, c1: "I", c2: "")
    if mn == "call": return OpInfo(id: 27, nargs: 1, c1: "I", c2: "")
    if mn == "ret": return OpInfo(id: 28, nargs: 0, c1: "", c2: "")
    if mn == "in": return OpInfo(id: 29, nargs: 1, c1: "R", c2: "")
    if mn == "out": return OpInfo(id: 30, nargs: 1, c1: "RIM", c2: "")
    if mn == "outc": return OpInfo(id: 31, nargs: 1, c1: "RIM", c2: "")
    if mn == "halt": return OpInfo(id: 32, nargs: 0, c1: "", c2: "")
    if mn == "nop": return OpInfo(id: 33, nargs: 0, c1: "", c2: "")

    return OpInfo(id: -1, nargs: 0, c1: "", c2: "")

// "R", "I" or "M" for an operand already known to be syntactically valid.
fn kind_letter(op: String) String:
    if reg_index(op) >= 0: return "R"
    if op.starts_with("["): return "M"

    return "I"

// Pass-1 syntax check of one operand: "" when valid.
fn operand_syntax(op: String) String:
    if op == "": return "invalid operand ''"
    if op.starts_with("["): return parse_mem(op).err

    return ""

// Pass-2 encoding of one operand.
fn encode_operand(op: String, syms: Map[String, Sym]) Opv:
    let r = reg_index(op)
    if r >= 0: return Opv(err: "", k: 0, r: r, v: 0)

    if op.starts_with("["):
        let m = parse_mem(op)
        if m.err != "": return Opv(err: m.err, k: 2, r: -1, v: 0)

        var total = 0

        for t in m.terms:
            let tcs = t.chars()
            let text = sub(tcs, 1, tcs.length())
            let e = eval(text, syms, "")
            if e.err != "": return Opv(err: e.err, k: 2, r: -1, v: 0)

            if tcs[0] == "-":
                total -= e.val
            else:
                total += e.val

            total = wrap32(total)

        return Opv(err: "", k: 2, r: m.base, v: total)

    let e = eval(op, syms, "")
    if e.err != "": return Opv(err: e.err, k: 1, r: -1, v: 0)

    return Opv(err: "", k: 1, r: -1, v: e.val)

// Input token: optional '-', decimal digits, wrapped to 32 bits. none when invalid.
fn parse_input(tok: String) Int?:
    let cs = tok.chars()
    var i = 0
    var neg = false

    if cs.length() > 0 and cs[0] == "-":
        neg = true
        i = 1

    let digits = sub(cs, i, cs.length())
    if not all_digits(digits): return none

    var v = 0
    for c in digits.chars():
        v = (v * 10 + c.scalar_at(0) - 48) % TWO32
    if neg:
        v = (TWO32 - v) % TWO32
    return wrap32(v)

// ---------- pass 1 ----------

impl Asm:
    var fn define(name: String, num: Int) String:
        if reg_index(name) >= 0: return "reserved name '" + name + "'"
        if self.syms.contains(name): return "duplicate symbol '" + name + "'"

        return ""

    var fn directive(num: Int, word: String, rest: String) String:
        if word == ".text" or word == ".data":
            if rest != "": return "invalid operand '" + rest + "'"

            self.text = (word == ".text")
            return ""

        if word == ".budget":
            if not all_digits(rest): return "invalid operand '" + rest + "'"

            var v = 0

            for c in rest.chars():
                v = v * 10 + c.scalar_at(0) - 48
                if v > 10000001:
                    v = 10000001

            if v < 1 or v > 10000000: return "invalid operand '" + rest + "'"

            self.budget = v
            return ""

        if word == ".equ":
            let ops = split_top(rest)
            if rest == "" or ops.length() != 2:
                return "wrong number of operands for '.equ'"

            let name = ops[0].clone()
            if not is_ident(name): return "invalid operand '" + name + "'"

            let e = self.define(name, num)
            if e != "": return e

            self.syms[name.clone()] = Sym(
                is_text: false, is_equ: true, value: 0, expr: ops[1].clone()
            )
            return ""

        if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
            if self.text: return "data directive in text section"

        if word == ".word":
            if rest == "": return "wrong number of operands for '.word'"

            let ops = split_top(rest)
            if self.dc + ops.length() > MEMSIZE: return "data section too large"

            self.stmts.append(
                Stmt(
                    line: num, kind: 1, mnem: "", ops: ops.clone(), addr: self.dc,
                    vals: List[Int](), count: 0, fill: ""
                )
            )
            self.dc += ops.length()
            return ""

        if word == ".ascii" or word == ".asciz":
            let sr = parse_string(rest)
            if sr.err != "": return sr.err

            var vals = sr.vals.clone()
            if word == ".asciz":
                vals.append(0)
            if self.dc + vals.length() > MEMSIZE: return "data section too large"

            let cnt = vals.length()
            self.stmts.append(
                Stmt(
                    line: num, kind: 2, mnem: "", ops: List[String](), addr: self.dc,
                    vals: vals, count: 0, fill: ""
                )
            )
            self.dc += cnt
            return ""

        if word == ".space":
            let ops = split_top(rest)
            if rest == "" or ops.length() > 2:
                return "wrong number of operands for '.space'"

            let nt = ops[0].clone()
            let ev = eval(nt, self.syms, "")
            if ev.err != "": return ev.err
            if ev.val < 0: return "invalid operand '" + nt + "'"
            if self.dc + ev.val > MEMSIZE: return "data section too large"

            var fill = "0"
            if ops.length() == 2:
                fill = ops[1].clone()
            self.stmts.append(
                Stmt(
                    line: num, kind: 3, mnem: "", ops: List[String](), addr: self.dc,
                    vals: List[Int](), count: ev.val, fill: fill
                )
            )
            self.dc += ev.val
            return ""

        return "unknown directive '" + word + "'"

    var fn instr(num: Int, word: String, rest: String) String:
        if not self.text: return "instruction in data section"

        let info = op_info(word)
        if info.id < 0: return "unknown mnemonic '" + word + "'"

        var ops = List[String]()
        if rest != "":
            ops = split_top(rest)

        for op in ops:
            let e = operand_syntax(op)
            if e != "": return e

        if ops.length() != info.nargs:
            return "wrong number of operands for '" + word + "'"

        if info.nargs >= 1:
            if not info.c1.contains(kind_letter(ops[0])):
                return "invalid operands for '" + word + "'"

        if info.nargs == 2:
            let l1 = kind_letter(ops[0])
            let l2 = kind_letter(ops[1])
            if not info.c2.contains(l2): return "invalid operands for '" + word + "'"
            if l1 == "M" and l2 == "M": return "invalid operands for '" + word + "'"

        self.stmts.append(
            Stmt(
                line: num, kind: 0, mnem: word.clone(), ops: ops, addr: 0,
                vals: List[Int](), count: 0, fill: ""
            )
        )
        self.tc += 1
        return ""

    var fn line1(num: Int, raw: String) String:
        var s = strip_comment(raw).trim_chars(WS)

        // Leading labels.
        while true:
            let cs = s.chars()
            let n = cs.length()
            if n == 0: break
            if not IDSTART.contains(cs[0]): break

            var j = 1

            while j < n:
                if not IDCHARS.contains(cs[j]): break

                j += 1

            if j >= n: break
            if cs[j] != ":": break

            let name = sub(cs, 0, j)
            let e = self.define(name, num)
            if e != "": return e

            if self.text:
                self.syms[name.clone()] = Sym(
                    is_text: true, is_equ: false, value: self.tc, expr: ""
                )
            else:
                self.syms[name.clone()] = Sym(
                    is_text: false, is_equ: false, value: self.dc, expr: ""
                )

            s = sub(cs, j + 1, n).trim_chars(WS)

        if s == "": return ""

        let cs = s.chars()
        let n = cs.length()
        var we = 0

        while we < n:
            if WS.contains(cs[we]): break

            we += 1

        let word = sub(cs, 0, we)
        let rest = sub(cs, we, n).trim_chars(WS)
        if word.starts_with("."): return self.directive(num, word, rest)

        return self.instr(num, word, rest)

// Removes a `;` comment that is outside string and character literals.
fn strip_comment(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var i = 0

    while i < n:
        let c = cs[i]
        if c == ";": return sub(cs, 0, i)

        if c == "\"":
            i += 1

            while i < n:
                if cs[i] == "\"": break

                if cs[i] == "\\":
                    i += 1
                i += 1

            i += 1
            continue

        if c == "'":
            let L = char_lit_len(cs, i)

            if L > 0:
                i += L
                continue

        i += 1

    return s.clone()

// ---------- pass 2: build the VM image ----------

fn build(asm: Asm, inputs: List[Int], chartab: List[String]) Vm:
    var mem = List[Int]()
    for i in 0..MEMSIZE:
        mem.append(0)

    var ops = List[Int]()
    var k1 = List[Int]()
    var r1 = List[Int]()
    var v1 = List[Int]()
    var k2 = List[Int]()
    var r2 = List[Int]()
    var v2 = List[Int]()
    var lines = List[Int]()
    var aerr = ""
    var aline = 0
    let ntext = asm.tc

    for s in asm.stmts:
        if s.kind == 0:
            let info = op_info(s.mnem)
            var o1 = Opv(err: "", k: -1, r: -1, v: 0)
            var o2 = Opv(err: "", k: -1, r: -1, v: 0)

            if info.nargs >= 1:
                o1 = encode_operand(s.ops[0], asm.syms)

                if o1.err != "":
                    aerr = o1.err
                    aline = s.line
                    break

            if info.nargs == 2:
                o2 = encode_operand(s.ops[1], asm.syms)

                if o2.err != "":
                    aerr = o2.err
                    aline = s.line
                    break

            if info.id >= 20 and info.id <= 27:
                if o1.v < 0 or o1.v >= ntext:
                    aerr = "invalid jump target"
                    aline = s.line
                    break

            ops.append(info.id)
            k1.append(o1.k)
            r1.append(o1.r)
            v1.append(o1.v)
            k2.append(o2.k)
            r2.append(o2.r)
            v2.append(o2.v)
            lines.append(s.line)
        else if s.kind == 1:
            var i = 0

            for op in s.ops:
                let e = eval(op, asm.syms, "")

                if e.err != "":
                    aerr = e.err
                    aline = s.line
                    break

                mem[s.addr + i] = e.val
                i += 1

            if aerr != "": break
        else if s.kind == 2:
            var i = 0

            for b in s.vals:
                mem[s.addr + i] = b
                i += 1
        else if s.kind == 3:
            let e = eval(s.fill, asm.syms, "")

            if e.err != "":
                aerr = e.err
                aline = s.line
                break

            for i in 0..s.count:
                mem[s.addr + i] = e.val

    var entry = 0

    if asm.syms.contains("main"):
        let m = asm.syms.get(
            "main"
        ).get(Sym(is_text: false, is_equ: false, value: 0, expr: ""))
        if m.is_text and not m.is_equ:
            entry = m.value

    var regs = List[Int]()
    for i in 0..10:
        regs.append(0)
    regs[8] = MEMSIZE
    return Vm(
        ops: ops, k1: k1, r1: r1, v1: v1, k2: k2, r2: r2, v2: v2, lines: lines,
        regs: regs, mem: mem, input: inputs, inpos: 0, zf: false, lf: false, steps: 0,
        budget: asm.budget, pc: entry, done: false, trapped: false, trapmsg: "",
        out: List[String](), chartab: chartab, last_nl: false, has_out: false,
        aerr: aerr, aline: aline
    )

// ---------- the machine ----------

impl Vm:
    var fn fail(msg: String) Unit:
        self.done = true
        self.trapped = true

        var ln = "-"
        if self.pc >= 0 and self.pc < self.lines.length():
            ln = self.lines[self.pc].to_string()
        self.trapmsg = msg + " (pc=" + self.pc.to_string() + " line=" + ln + ")"

    fn ea(r: Int, v: Int) Int:
        var base = 0
        if r >= 0:
            base = self.regs[r]
        return wrap32(base + v)

    var fn mem_get(a: Int) Int:
        if a < 0 or a >= MEMSIZE:
            self.fail("memory access out of range: " + a.to_string())
            return 0

        return self.mem[a]

    var fn mem_set(a: Int, val: Int) Unit:
        if a < 0 or a >= MEMSIZE:
            self.fail("memory access out of range: " + a.to_string())
            return

        self.mem[a] = val

    var fn read(k: Int, r: Int, v: Int) Int:
        if k == 0: return self.regs[r]
        if k == 1: return v

        return self.mem_get(self.ea(r, v))

    var fn write(k: Int, r: Int, v: Int, val: Int) Unit:
        if k == 0:
            self.regs[r] = val
            return

        self.mem_set(self.ea(r, v), val)

    var fn exec() Unit:
        let pc = self.pc
        let op = self.ops[pc]
        let k1 = self.k1[pc]
        let r1 = self.r1[pc]
        let v1 = self.v1[pc]
        let k2 = self.k2[pc]
        let r2 = self.r2[pc]
        let v2 = self.v2[pc]
        var nextpc = pc + 1

        if op == 0:
            let s = self.read(k2, r2, v2)
            if self.done: return

            self.write(k1, r1, v1, s)
            if self.done: return
        else if op >= 1 and op <= 11:
            let s = self.read(k2, r2, v2)
            if self.done: return

            let d = self.regs[r1]
            var res = 0

            if op == 1:
                res = d + s
            else if op == 2:
                res = d - s
            else if op == 3:
                res = d * s
            else if op == 4 or op == 5:
                if s == 0:
                    self.fail("division by zero")
                    return

                if op == 4:
                    res = d / s
                else:
                    res = d % s
            else if op == 6:
                res = bit_and(d, s)
            else if op == 7:
                res = bit_or(d, s)
            else if op == 8:
                res = bit_xor(d, s)
            else if op == 9:
                res = shift_left(d, bit_and(s, 31))
            else if op == 10:
                var u = d
                if u < 0:
                    u += TWO32
                res = shift_right(u, bit_and(s, 31))
            else:
                res = shift_right(d, bit_and(s, 31))

            self.regs[r1] = wrap32(res)
        else if op == 12:
            let s = self.read(k2, r2, v2)
            if self.done: return

            let d = self.regs[r1]
            self.zf = (d == s)
            self.lf = (d < s)
        else if op >= 13 and op <= 16:
            let d = self.regs[r1]
            var res = d

            if op == 13:
                res = -d
            else if op == 14:
                res = bit_not(d)
            else if op == 15:
                res = d + 1
            else:
                res = d - 1

            self.regs[r1] = wrap32(res)
        else if op == 17:
            self.regs[r1] = self.ea(r2, v2)
        else if op == 18:
            let s = self.read(k1, r1, v1)
            if self.done: return

            if self.regs[8] <= 0:
                self.fail("stack overflow")
                return

            self.regs[8] = self.regs[8] - 1
            self.mem_set(self.regs[8], s)
            if self.done: return
        else if op == 19:
            if self.regs[8] >= MEMSIZE:
                self.fail("stack underflow")
                return

            let v = self.mem_get(self.regs[8])
            if self.done: return

            self.regs[8] = self.regs[8] + 1
            self.regs[r1] = v
        else if op >= 20 and op <= 26:
            var take = false

            if op == 20:
                take = true
            else if op == 21:
                take = self.zf
            else if op == 22:
                take = not self.zf
            else if op == 23:
                take = self.lf
            else if op == 24:
                take = self.lf or self.zf
            else if op == 25:
                take = (not self.lf) and (not self.zf)
            else:
                take = not self.lf

            if take:
                nextpc = v1
        else if op == 27:
            if self.regs[8] <= 0:
                self.fail("stack overflow")
                return

            self.regs[8] = self.regs[8] - 1
            self.mem_set(self.regs[8], pc + 1)
            if self.done: return

            nextpc = v1
        else if op == 28:
            if self.regs[8] >= MEMSIZE:
                self.fail("stack underflow")
                return

            let v = self.mem_get(self.regs[8])
            if self.done: return

            self.regs[8] = self.regs[8] + 1
            nextpc = v
        else if op == 29:
            if self.inpos >= self.input.length():
                self.fail("input exhausted")
                return

            self.regs[r1] = self.input[self.inpos]
            self.inpos += 1
        else if op == 30:
            let s = self.read(k1, r1, v1)
            if self.done: return

            self.out.append(s.to_string() + "\n")
            self.last_nl = true
            self.has_out = true
        else if op == 31:
            let s = self.read(k1, r1, v1)
            if self.done: return

            if s < 0 or s > 127:
                self.fail("invalid character")
                return

            self.out.append(self.chartab[s].clone())
            self.last_nl = (s == 10)
            self.has_out = true
        else if op == 32:
            self.steps += 1
            self.done = true
            self.trapped = false
            return

        // op 33 (nop) does nothing.
        self.steps += 1
        self.pc = nextpc

    var fn run() Unit:
        while not self.done:
            if self.steps == self.budget:
                self.fail("budget exceeded")
                break

            if self.pc < 0 or self.pc >= self.ops.length():
                self.fail("pc out of range")
                break

            self.exec()

// ---------- driver ----------

export fn main() Int:
    let raw = read_all(stdin()).get()
    var text = ""

    if let decoded = raw.decode_utf8():
        text = decoded
    else:
        // Not valid UTF-8: keep every byte as one scalar (Latin-1) so the source still assembles.
        var codes = List[Int]()
        for i in 0..raw.length():
            codes.append(raw.get(i).to_int())
        text = from_scalars(codes).get()

    var src = List[String]()
    var inputs_text = ""
    var in_input = false

    for p in text.split("\n"):
        if in_input:
            inputs_text += p + "\n"
        else if p.trim_end_chars("\r") == "====":
            in_input = true
        else:
            src.append(p.clone())

    var toks = List[String]()
    var cur = ""

    for c in inputs_text.chars():
        if WS.contains(c) or c == "\n":
            if cur != "":
                toks.append(cur.clone())
            cur = ""
        else:
            cur += c

    if cur != "":
        toks.append(cur.clone())

    var inputs = List[Int]()
    for t in toks:
        if let v = parse_input(t):
            inputs.append(v)

    var chartab = List[String]()
    for c in 0..128:
        chartab.append(from_scalars([c]).get())

    var asm = Asm(
        text: true, tc: 0, dc: 0, budget: 100000, syms: Map[String, Sym](),
        stmts: List[Stmt]()
    )
    var aerr = ""
    var aline = 0

    for i in 0..src.length():
        let e = asm.line1(i + 1, src[i])

        if e != "":
            aerr = e
            aline = i + 1
            break

    if aerr == "":
        var vm = build(asm, inputs, chartab)

        if vm.aerr != "":
            aerr = vm.aerr
            aline = vm.aline
        else:
            vm.run()

            var outtext = vm.out.join("")
            if vm.has_out and not vm.last_nl:
                outtext += "\n"

            if vm.trapped:
                outtext += (
                    "-- trap: "
                    + vm.trapmsg
                    + " after "
                    + vm.steps.to_string()
                    + " steps\n"
                )
            else:
                outtext += "-- halted after " + vm.steps.to_string() + " steps\n"

            let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
            var rl = "regs:"
            for i in 0..10:
                rl += " " + names[i] + "=" + vm.regs[i].to_string()
            outtext += rl + "\n"

            var zz = 0
            var ll = 0
            if vm.zf:
                zz = 1
            if vm.lf:
                ll = 1
            outtext += "flags: Z=" + zz.to_string() + " L=" + ll.to_string() + "\n"
            stdout().write(outtext).get()
            return 0

    stdout().write("asm error line " + aline.to_string() + ": " + aerr + "\n").get()
    return 0
