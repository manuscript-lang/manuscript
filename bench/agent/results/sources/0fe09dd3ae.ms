import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"
import from_scalars from "@std/string.ms"
import (
    bit_and,
    bit_or,
    bit_xor,
    shift_left,
    shift_right,
    shift_right_unsigned
) from "@std/math/math.ms"

// ---------- records ----------

type Term:
    neg: Bool
    reg: Int
    text: List[Int]

type Opnd:
    kind: Int
    reg: Int
    terms: List[Term]

type DItem:
    line: Int
    addr: Int
    count: Int
    fixed: Bool
    lit: Int
    text: List[Int]

type Ev:
    ok: Bool
    val: Int
    msg: String

type ETerm:
    neg: Bool
    is_num: Bool
    num: Int
    name: String

type EParse:
    ok: Bool
    terms: List[ETerm]

type Ck:
    ok: Bool
    val: Int
    next: Int

type Str:
    ok: Bool
    bytes: List[Int]

type St:
    err: String
    err_line: Int
    in_data: Bool
    dc: Int
    ic: Int
    budget: Int
    start: Int
    labels: Map[String, Int]
    equs: Map[String, List[Int]]
    seen: Map[String, Bool]
    ops: List[Int]
    ilines: List[Int]
    opa: List[Opnd]
    opb: List[Opnd]
    dl: List[DItem]
    tasks: List[Int]
    ak: List[Int]
    ar: List[Int]
    av: List[Int]
    bk: List[Int]
    br: List[Int]
    bv: List[Int]
    mem: List[Int]
    regs: List[Int]
    z: Bool
    l: Bool
    pc: Int
    steps: Int
    inputs: List[Int]
    ip: Int
    outs: List[String]
    hasout: Bool
    endnl: Bool
    msg: String
    halted: Bool
    tpc: Int
    tline: Int
    chars: List[String]

// ---------- small helpers ----------

fn wrap32(x: Int) Int:
    return bit_and(x + 2147483648, 4294967295) - 2147483648

fn zeros(n: Int) List[Int]:
    var r = List[Int]()
    var i = 0

    while i < n:
        r.append(0)
        i += 1

    return r

fn slice_cs(cs: List[Int], a: Int, b: Int) List[Int]:
    var r = List[Int]()
    var i = a

    while i < b:
        r.append(cs[i])
        i += 1

    return r

fn txt(cs: List[Int]) String:
    return from_scalars(cs).get("")

fn is_ws(c: Int) Bool:
    return c == 32 or c == 9 or c == 13 or c == 11 or c == 12

fn is_space(c: Int) Bool:
    return is_ws(c) or c == 10

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_ident_char(c: Int) Bool:
    return is_ident_start(c) or is_digit(c) or c == 46

fn is_word_char(c: Int) Bool:
    return is_ident_start(c) or is_digit(c)

fn trim_cs(cs: List[Int]) List[Int]:
    let n = cs.length()
    var a = 0

    while a < n:
        if not is_ws(cs[a]):
            break

        a += 1

    var b = n

    while b > a:
        if not is_ws(cs[b - 1]):
            break

        b -= 1

    return slice_cs(cs, a, b)

fn skip_ws(cs: List[Int], pos: Int) Int:
    var i = pos

    while i < cs.length():
        if not is_ws(cs[i]):
            break

        i += 1

    return i

fn word_end(cs: List[Int], pos: Int) Int:
    var i = pos

    while i < cs.length():
        if is_ws(cs[i]):
            break

        i += 1

    return i

fn ident_end(cs: List[Int], pos: Int) Int:
    let n = cs.length()
    var j = pos + 1

    while j < n:
        if not is_ident_char(cs[j]):
            break

        j += 1

    return j

fn is_identifier(t: List[Int]) Bool:
    let n = t.length()
    if n == 0:
        return false
    if not is_ident_start(t[0]):
        return false

    var i = 1

    while i < n:
        if not is_ident_char(t[i]):
            return false

        i += 1

    return true

// index just past a quoted literal starting at i (quote char q); n if unterminated
fn skip_quoted(cs: List[Int], i: Int, q: Int) Int:
    let n = cs.length()
    var j = i + 1

    while j < n:
        if cs[j] == 92:
            j += 2
        else if cs[j] == q:
            return j + 1
        else:
            j += 1

    return n

fn strip_comment(cs: List[Int]) List[Int]:
    let n = cs.length()
    var i = 0

    while i < n:
        let c = cs[i]
        if c == 59:
            return slice_cs(cs, 0, i)

        if c == 34:
            i = skip_quoted(cs, i, 34)
        else if c == 39:
            i = skip_quoted(cs, i, 39)
        else:
            i += 1

    return slice_cs(cs, 0, n)

// position after any leading `name:` labels (no definitions made)
fn after_labels(c: List[Int]) Int:
    let n = c.length()
    var pos = skip_ws(c, 0)

    while pos < n:
        if not is_ident_start(c[pos]):
            break

        let e = ident_end(c, pos)
        if e >= n:
            break
        if c[e] != 58:
            break

        pos = skip_ws(c, e + 1)

    return pos

// split at commas that are outside [] and character literals
fn split_commas(cs: List[Int]) List[List[Int]]:
    var parts = List[List[Int]]()
    let n = cs.length()
    var depth = 0
    var start = 0
    var i = 0

    while i < n:
        let c = cs[i]

        if c == 39:
            i = skip_quoted(cs, i, 39)
        else if c == 91:
            depth += 1
            i += 1
        else if c == 93:
            depth -= 1
            i += 1
        else if c == 44 and depth == 0:
            parts.append(slice_cs(cs, start, i))
            start = i + 1
            i += 1
        else:
            i += 1

    parts.append(slice_cs(cs, start, n))
    return parts

fn reg_index(t: List[Int]) Int:
    if t.length() != 2:
        return -1

    let a = t[0]
    let b = t[1]
    if a == 114 and b >= 48 and b <= 55:
        return b - 48
    if a == 115 and b == 112:
        return 8
    if a == 98 and b == 112:
        return 9

    return -1

fn esc_char(c: Int) Int:
    if c == 110:
        return 10
    if c == 116:
        return 9
    if c == 48:
        return 0
    if c == 92 or c == 39 or c == 34:
        return c

    return -1

fn utf8_bytes(c: Int) List[Int]:
    var r = List[Int]()

    if c < 128:
        r.append(c)
    else if c < 2048:
        r.append(192 + c / 64)
        r.append(128 + c % 64)
    else if c < 65536:
        r.append(224 + c / 4096)
        r.append(128 + (c / 64) % 64)
        r.append(128 + c % 64)
    else:
        r.append(240 + c / 262144)
        r.append(128 + (c / 4096) % 64)
        r.append(128 + (c / 64) % 64)
        r.append(128 + c % 64)

    return r

// t is a trimmed operand: "..." with escapes
fn parse_string(t: List[Int]) Str:
    let n = t.length()
    let bad = Str(ok: false, bytes: List[Int]())
    if n < 2:
        return bad
    if t[0] != 34:
        return bad
    if t[n - 1] != 34:
        return bad

    var out = List[Int]()
    var i = 1

    while i < n - 1:
        let c = t[i]
        if c == 34:
            return bad

        if c == 92:
            if i + 1 >= n - 1:
                return bad

            let e = esc_char(t[i + 1])
            if e < 0:
                return bad

            for b in utf8_bytes(e):
                out.append(b)
            i += 2
        else:
            for b in utf8_bytes(c):
                out.append(b)
            i += 1

    return Str(ok: true, bytes: out)

fn digit_val(c: Int, base: Int) Int:
    var d = -1

    if c >= 48 and c <= 57:
        d = c - 48
    else if c >= 97 and c <= 102:
        d = c - 87
    else if c >= 65 and c <= 70:
        d = c - 55

    if d < 0 or d >= base:
        return -1

    return d

// decimal, 0x hex or 0b binary literal; value capped just above the 32-bit unsigned range
fn number_value(tok: List[Int]) Ck:
    let n = tok.length()
    let bad = Ck(ok: false, val: 0, next: 0)
    var start = 0
    var base = 10

    if n >= 2:
        if tok[0] == 48 and tok[1] == 120:
            base = 16
            start = 2
        else if tok[0] == 48 and tok[1] == 98:
            base = 2
            start = 2

    if start >= n:
        return bad

    var v = 0
    var i = start

    while i < n:
        let d = digit_val(tok[i], base)
        if d < 0:
            return bad

        v = v * base + d
        if v > 4294967296:
            v = 4294967296
        i += 1

    return Ck(ok: true, val: v, next: 0)

// character literal starting at t[pos] == '
fn char_value(t: List[Int], pos: Int) Ck:
    let n = t.length()
    let bad = Ck(ok: false, val: 0, next: 0)
    var j = pos + 1
    if j >= n:
        return bad

    var v = 0

    if t[j] == 92:
        if j + 1 >= n:
            return bad

        let e = esc_char(t[j + 1])
        if e < 0:
            return bad

        v = e
        j += 2
    else:
        let c = t[j]
        if c == 39 or c >= 128:
            return bad

        v = c
        j += 1

    if j >= n:
        return bad
    if t[j] != 39:
        return bad

    return Ck(ok: true, val: v, next: j + 1)

fn parse_expr(t: List[Int]) EParse:
    let n = t.length()
    let bad = EParse(ok: false, terms: List[ETerm]())
    if n == 0:
        return bad

    var terms = List[ETerm]()
    var pos = 0
    var neg = false

    if t[0] == 43 or t[0] == 45:
        neg = t[0] == 45
        pos = 1

    while true:
        pos = skip_ws(t, pos)
        if pos >= n:
            return bad

        let c = t[pos]

        if is_digit(c):
            var e = pos

            while e < n:
                if not is_word_char(t[e]):
                    break

                e += 1

            let nr = number_value(slice_cs(t, pos, e))
            if not nr.ok:
                return bad

            terms.append(ETerm(neg: neg, is_num: true, num: nr.val, name: ""))
            pos = e
        else if c == 39:
            let cr = char_value(t, pos)
            if not cr.ok:
                return bad

            terms.append(ETerm(neg: neg, is_num: true, num: cr.val, name: ""))
            pos = cr.next
        else if is_ident_start(c):
            let e = ident_end(t, pos)
            terms.append(
                ETerm(
                    neg: neg, is_num: false, num: 0, name: txt(slice_cs(t, pos, e))
                )
            )
            pos = e
        else:
            return bad

        pos = skip_ws(t, pos)
        if pos >= n:
            break

        if t[pos] == 43 or t[pos] == 45:
            neg = t[pos] == 45
            pos += 1
        else:
            return bad

    return EParse(ok: true, terms: terms)

fn list_has(xs: List[String], s: String) Bool:
    for x in xs:
        if x == s:
            return true
    return false

fn evaluate(
    cs: List[Int],
    labels: Map[String, Int],
    equs: Map[String, List[Int]],
    stack: List[String]
) Ev:
    let t = trim_cs(cs)
    let pr = parse_expr(t)
    if not pr.ok:
        return Ev(ok: false, val: 0, msg: "invalid expression '{txt(t)}'")

    var acc = 0
    var k = 0

    while k < pr.terms.length():
        let tm = pr.terms[k]
        var v = 0

        if tm.is_num:
            if tm.num > 4294967295:
                return Ev(ok: false, val: 0, msg: "immediate out of range")

            v = wrap32(tm.num)
        else:
            if let lv = labels.get(tm.name):
                v = lv
            else:
                if let e = equs.get(tm.name):
                    if list_has(stack, tm.name):
                        return Ev(
                            ok: false, val: 0, msg: "circular definition of '{tm.name}'"
                        )

                    var ns = List[String]()
                    for s in stack:
                        ns.append(s.clone())
                    ns.append(tm.name.clone())

                    let r = evaluate(e, labels, equs, ns)
                    if not r.ok:
                        return r

                    v = r.val
                else:
                    return Ev(ok: false, val: 0, msg: "undefined symbol '{tm.name}'")

        if tm.neg:
            acc = wrap32(acc - v)
        else:
            acc = wrap32(acc + v)

        k += 1

    return Ev(ok: true, val: acc, msg: "")

// ---------- operands ----------

fn none_opnd() Opnd:
    return Opnd(kind: -1, reg: -1, terms: List[Term]())

// t is a trimmed operand that starts with '['
fn mem_operand(t: List[Int]) Opnd:
    let n = t.length()
    let bad = Opnd(kind: -2, reg: -1, terms: List[Term]())
    if n < 2:
        return bad
    if t[n - 1] != 93:
        return bad

    let inner = trim_cs(slice_cs(t, 1, n - 1))
    let m = inner.length()
    if m == 0:
        return bad

    var terms = List[Term]()
    var reg = -1
    var nregs = 0
    var neg = false
    var pos = 0

    if inner[0] == 43 or inner[0] == 45:
        neg = inner[0] == 45
        pos = 1

    while true:
        var j = pos

        while j < m:
            if inner[j] == 39:
                j = skip_quoted(inner, j, 39)
            else if inner[j] == 43 or inner[j] == 45:
                break
            else:
                j += 1

        let term = trim_cs(slice_cs(inner, pos, j))
        if term.length() == 0:
            return bad

        let r = reg_index(term)

        if r >= 0:
            if neg:
                return bad

            nregs += 1
            if nregs > 1:
                return bad

            reg = r
            terms.append(Term(neg: false, reg: r, text: List[Int]()))
        else:
            terms.append(Term(neg: neg, reg: -1, text: term))

        if j >= m:
            break

        neg = inner[j] == 45
        pos = j + 1

    return Opnd(kind: 2, reg: reg, terms: terms)

fn classify(t: List[Int]) Opnd:
    if t.length() == 0:
        return Opnd(kind: -2, reg: -1, terms: List[Term]())
    if t[0] == 91:
        return mem_operand(t)

    let r = reg_index(t)
    if r >= 0:
        return Opnd(kind: 0, reg: r, terms: List[Term]())

    var terms = List[Term]()
    terms.append(Term(neg: false, reg: -1, text: slice_cs(t, 0, t.length())))
    return Opnd(kind: 1, reg: -1, terms: terms)

// ---------- opcodes ----------
// 0 mov, 1 add, 2 sub, 3 mul, 4 div, 5 mod, 6 and, 7 or, 8 xor, 9 shl, 10 shr, 11 sar,
// 12 cmp, 13 neg, 14 not, 15 inc, 16 dec, 17 lea, 18 push, 19 pop, 20 jmp, 21 je, 22 jne,
// 23 jl, 24 jle, 25 jg, 26 jge, 27 call, 28 ret, 29 in, 30 out, 31 outc, 32 halt, 33 nop

fn opcode(name: String) Int:
    let names = [
        "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr",
        "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je",
        "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt",
        "nop"
    ]
    if name == "jz":
        return 21
    if name == "jnz":
        return 22

    var i = 0

    while i < names.length():
        if names[i] == name:
            return i

        i += 1

    return -1

fn opcount(op: Int) Int:
    if op == 0 or (op >= 1 and op <= 12) or op == 17:
        return 2
    if op == 28 or op >= 32:
        return 0

    return 1

fn mask_a(op: Int) Int:
    if op == 0:
        return 5
    if op >= 1 and op <= 16:
        return 1
    if op == 17 or op == 19 or op == 29:
        return 1
    if op == 18 or op == 30 or op == 31:
        return 7
    if op >= 20 and op <= 27:
        return 2

    return 0

fn mask_b(op: Int) Int:
    if op == 0 or (op >= 1 and op <= 12):
        return 7
    if op == 17:
        return 4

    return 0

fn kbit(k: Int) Int:
    if k == 0:
        return 1
    if k == 1:
        return 2

    return 4

fn char_table() List[String]:
    var r = List[String]()
    var c = 0

    while c < 128:
        var one = List[Int]()
        one.append(c)
        r.append(txt(one))
        c += 1

    return r

fn new_state() St:
    var regs = zeros(10)
    regs[8] = 4096
    return St(
        err: "", err_line: 0, in_data: false, dc: 0, ic: 0, budget: 100000, start: 0,
        labels: Map[String, Int](), equs: Map[String, List[Int]](),
        seen: Map[String, Bool](), ops: List[Int](), ilines: List[Int](),
        opa: List[Opnd](), opb: List[Opnd](), dl: List[DItem](), tasks: List[Int](),
        ak: List[Int](), ar: List[Int](), av: List[Int](), bk: List[Int](),
        br: List[Int](), bv: List[Int](), mem: zeros(4096), regs: regs, z: false,
        l: false, pc: 0, steps: 0, inputs: List[Int](), ip: 0, outs: List[String](),
        hasout: false, endnl: false, msg: "", halted: false, tpc: 0, tline: 0,
        chars: char_table()
    )

// ---------- assembler ----------

impl St:
    var fn err_at(line: Int, msg: String) Unit:
        if self.err == "":
            self.err = msg
            self.err_line = line

    var fn add_item(
        line: Int,
        addr: Int,
        count: Int,
        fixed: Bool,
        lit: Int,
        text: List[Int]
    ) Unit:
        self.dl.append(
            DItem(
                line: line, addr: addr, count: count, fixed: fixed, lit: lit, text: text
            )
        )
        self.tasks.append(-self.dl.length())

    var fn define(name: List[Int], line: Int) Unit:
        let nm = txt(name)

        if reg_index(name) >= 0:
            self.err_at(line, "reserved name '{nm}'")
            return

        if self.seen.contains(nm):
            self.err_at(line, "duplicate symbol '{nm}'")
            return

        self.seen[nm.clone()] = true

        if self.in_data:
            self.labels[nm.clone()] = self.dc
        else:
            self.labels[nm.clone()] = self.ic
            if nm == "main":
                self.start = self.ic

    var fn directive(w: String, rest: List[Int], line: Int) Unit:
        if w == ".text" or w == ".data":
            if rest.length() > 0:
                self.err_at(line, "invalid operand '{txt(rest)}'")
                return

            self.in_data = w == ".data"
            return

        if w == ".equ":
            let parts = split_commas(rest)

            if parts.length() != 2:
                self.err_at(line, "wrong number of operands for '.equ'")
                return

            let name = trim_cs(parts[0])

            if not is_identifier(name):
                self.err_at(line, "invalid operand '{txt(name)}'")
                return

            let nm = txt(name)

            if reg_index(name) >= 0:
                self.err_at(line, "reserved name '{nm}'")
                return

            if self.seen.contains(nm):
                self.err_at(line, "duplicate symbol '{nm}'")
                return

            self.seen[nm] = true
            return

        if w == ".budget":
            var ok = rest.length() > 0
            var v = 0

            for c in rest:
                if not is_digit(c):
                    ok = false
                else:
                    v = v * 10 + (c - 48)
                    if v > 100000000:
                        v = 100000000

            if not ok or v < 1 or v > 10000000:
                self.err_at(line, "invalid operand '{txt(rest)}'")
                return

            self.budget = v
            return

        if w == ".word" or w == ".ascii" or w == ".asciz" or w == ".space":
            if not self.in_data:
                self.err_at(line, "data directive in text section")
                return

        if w == ".word":
            if rest.length() == 0:
                self.err_at(line, "wrong number of operands for '.word'")
                return

            let parts = split_commas(rest)
            let base = self.dc

            if base + parts.length() > 4096:
                self.err_at(line, "data section too large")
                return

            var k = 0

            while k < parts.length():
                self.add_item(line, base + k, 1, false, 0, trim_cs(parts[k]))
                k += 1

            self.dc = base + parts.length()
            return

        if w == ".ascii" or w == ".asciz":
            var s = parse_string(trim_cs(rest))

            if not s.ok:
                self.err_at(line, "invalid string")
                return

            if w == ".asciz":
                s.bytes.append(0)

            let base = self.dc

            if base + s.bytes.length() > 4096:
                self.err_at(line, "data section too large")
                return

            var k = 0

            while k < s.bytes.length():
                self.add_item(line, base + k, 1, true, s.bytes[k], List[Int]())
                k += 1

            self.dc = base + s.bytes.length()
            return

        if w == ".space":
            if rest.length() == 0:
                self.err_at(line, "wrong number of operands for '.space'")
                return

            let parts = split_commas(rest)

            if parts.length() > 2:
                self.err_at(line, "wrong number of operands for '.space'")
                return

            let ntext = trim_cs(parts[0])
            let ev = evaluate(ntext, self.labels, self.equs, List[String]())

            if not ev.ok:
                self.err_at(line, ev.msg)
                return

            let cnt = ev.val

            if cnt < 0:
                self.err_at(line, "invalid operand '{txt(ntext)}'")
                return

            if self.dc + cnt > 4096:
                self.err_at(line, "data section too large")
                return

            if parts.length() == 2:
                self.add_item(line, self.dc, cnt, false, 0, trim_cs(parts[1]))
            self.dc += cnt
            return

        self.err_at(line, "unknown directive '{w}'")

    var fn instruction(word: List[Int], rest: List[Int], line: Int) Unit:
        if self.in_data:
            self.err_at(line, "instruction in data section")
            return

        let name = txt(word)
        let op = opcode(name)

        if op < 0:
            self.err_at(line, "unknown mnemonic '{name}'")
            return

        var parts = List[List[Int]]()
        if rest.length() > 0:
            parts = split_commas(rest)

        var a = none_opnd()
        var b = none_opnd()
        var k = 0

        while k < parts.length():
            let t = trim_cs(parts[k])
            let o = classify(t)

            if o.kind == -2:
                self.err_at(line, "invalid operand '{txt(t)}'")
                return

            if k == 0:
                a = o
            else:
                b = o

            k += 1

        let want = opcount(op)

        if parts.length() != want:
            self.err_at(line, "wrong number of operands for '{name}'")
            return

        if want >= 1:
            if bit_and(mask_a(op), kbit(a.kind)) == 0:
                self.err_at(line, "invalid operands for '{name}'")
                return

        if want == 2:
            if bit_and(mask_b(op), kbit(b.kind)) == 0:
                self.err_at(line, "invalid operands for '{name}'")
                return

            if op == 0 and a.kind == 2 and b.kind == 2:
                self.err_at(line, "invalid operands for '{name}'")
                return

        self.ops.append(op)
        self.ilines.append(line)
        self.opa.append(a)
        self.opb.append(b)
        self.tasks.append(self.ic)
        self.ic += 1

    var fn do_line(cs: List[Int], line: Int) Unit:
        let c = strip_comment(cs)
        let n = c.length()
        var pos = skip_ws(c, 0)

        while pos < n:
            if not is_ident_start(c[pos]):
                break

            let e = ident_end(c, pos)
            if e >= n:
                break
            if c[e] != 58:
                break

            self.define(slice_cs(c, pos, e), line)
            if self.err != "":
                return

            pos = skip_ws(c, e + 1)

        if pos >= n:
            return

        let we = word_end(c, pos)
        let word = slice_cs(c, pos, we)
        let rest = trim_cs(slice_cs(c, we, n))

        if word[0] == 46:
            self.directive(txt(word), rest, line)
        else:
            self.instruction(word, rest, line)

    // collect .equ definitions so that .space counts can refer to constants defined later
    var fn collect_equs(lines: List[List[Int]]) Unit:
        var i = 0

        while i < lines.length():
            let c = strip_comment(lines[i])
            let n = c.length()
            let pos = after_labels(c)
            let we = word_end(c, pos)

            if pos < n and txt(slice_cs(c, pos, we)) == ".equ":
                let parts = split_commas(trim_cs(slice_cs(c, we, n)))

                if parts.length() == 2:
                    let name = trim_cs(parts[0])

                    if is_identifier(name) and reg_index(name) < 0:
                        let nm = txt(name)
                        if not self.equs.contains(nm):
                            self.equs[nm] = trim_cs(parts[1])

            i += 1

    var fn pass1(lines: List[List[Int]]) Unit:
        var i = 0

        while i < lines.length():
            if self.err != "":
                return

            self.do_line(lines[i], i + 1)
            i += 1

    var fn do_data(idx: Int) Unit:
        let line = self.dl[idx].line
        let addr = self.dl[idx].addr
        let cnt = self.dl[idx].count
        var v = self.dl[idx].lit

        if not self.dl[idx].fixed:
            let ev = evaluate(self.dl[idx].text, self.labels, self.equs, List[String]())

            if not ev.ok:
                self.err_at(line, ev.msg)
                return

            v = ev.val

        var k = 0

        while k < cnt:
            self.mem[addr + k] = v
            k += 1

    var fn do_instr(i: Int) Unit:
        let op = self.ops[i]
        let line = self.ilines[i]
        let ra = resolve(self.opa[i], self.labels, self.equs)

        if not ra.ok:
            self.err_at(line, ra.msg)
            return

        var rb = Ev(ok: true, val: 0, msg: "")

        if self.opb[i].kind != -1:
            rb = resolve(self.opb[i], self.labels, self.equs)

            if not rb.ok:
                self.err_at(line, rb.msg)
                return

        if op >= 20 and op <= 27:
            if ra.val < 0 or ra.val >= self.ic:
                self.err_at(line, "invalid jump target")
                return

        self.ak.append(self.opa[i].kind)
        self.ar.append(self.opa[i].reg)
        self.av.append(ra.val)
        self.bk.append(self.opb[i].kind)
        self.br.append(self.opb[i].reg)
        self.bv.append(rb.val)

    var fn pass2() Unit:
        var k = 0

        while k < self.tasks.length():
            if self.err != "":
                return

            let t = self.tasks[k]

            if t >= 0:
                self.do_instr(t)
            else:
                self.do_data(-t - 1)

            k += 1

    // ----- machine -----

    var fn trap(msg: String) Unit:
        if self.msg == "":
            self.msg = msg
            self.tpc = self.pc
            self.tline = self.ilines[self.pc]

    fn ea(reg: Int, off: Int) Int:
        var base = 0
        if reg >= 0:
            base = self.regs[reg]
        return wrap32(base + off)

    var fn mread(addr: Int) Int:
        if addr < 0 or addr >= 4096:
            self.trap("memory access out of range: {addr}")
            return 0

        return self.mem[addr]

    var fn mwrite(addr: Int, v: Int) Unit:
        if addr < 0 or addr >= 4096:
            self.trap("memory access out of range: {addr}")
            return

        self.mem[addr] = v

    var fn rd(k: Int, r: Int, v: Int) Int:
        if k == 0:
            return self.regs[r]
        if k == 1:
            return v

        return self.mread(self.ea(r, v))

    var fn wr(k: Int, r: Int, v: Int, val: Int) Unit:
        if k == 0:
            self.regs[r] = val
            return

        self.mwrite(self.ea(r, v), val)

    var fn alu(op: Int, d: Int, s: Int) Int:
        if op == 1:
            return wrap32(d + s)
        if op == 2:
            return wrap32(d - s)
        if op == 3:
            return wrap32(d * s)

        if op == 4 or op == 5:
            if s == 0:
                self.trap("division by zero")
                return 0

            if op == 4:
                return wrap32(d / s)

            return wrap32(d % s)

        if op == 6:
            return bit_and(d, s)
        if op == 7:
            return bit_or(d, s)
        if op == 8:
            return bit_xor(d, s)

        let c = bit_and(s, 31)
        if op == 9:
            return wrap32(shift_left(d, c))
        if op == 10:
            return wrap32(shift_right_unsigned(bit_and(d, 4294967295), c))

        return shift_right(d, c)

    fn cond(op: Int) Bool:
        if op == 20:
            return true
        if op == 21:
            return self.z
        if op == 22:
            return not self.z
        if op == 23:
            return self.l
        if op == 24:
            return self.l or self.z
        if op == 25:
            return (not self.l) and (not self.z)

        return not self.l

    var fn exec() Unit:
        let p = self.pc
        let op = self.ops[p]
        let ak = self.ak[p]
        let ar = self.ar[p]
        let av = self.av[p]
        let bk = self.bk[p]
        let br = self.br[p]
        let bv = self.bv[p]
        var next = p + 1

        if op == 0:
            let s = self.rd(bk, br, bv)
            if self.msg != "":
                return

            self.wr(ak, ar, av, s)
            if self.msg != "":
                return
        else if op >= 1 and op <= 11:
            let d = self.regs[ar]
            let s = self.rd(bk, br, bv)
            if self.msg != "":
                return

            let r = self.alu(op, d, s)
            if self.msg != "":
                return

            self.regs[ar] = r
        else if op == 12:
            let d = self.rd(ak, ar, av)
            let s = self.rd(bk, br, bv)
            if self.msg != "":
                return

            self.z = d == s
            self.l = d < s
        else if op == 13:
            self.regs[ar] = wrap32(0 - self.regs[ar])
        else if op == 14:
            self.regs[ar] = wrap32(-self.regs[ar] - 1)
        else if op == 15:
            self.regs[ar] = wrap32(self.regs[ar] + 1)
        else if op == 16:
            self.regs[ar] = wrap32(self.regs[ar] - 1)
        else if op == 17:
            self.regs[ar] = self.ea(br, bv)
        else if op == 18:
            let v = self.rd(ak, ar, av)
            if self.msg != "":
                return

            let sp = self.regs[8]

            if sp <= 0:
                self.trap("stack overflow")
                return

            self.regs[8] = sp - 1
            self.mwrite(sp - 1, v)
            if self.msg != "":
                return
        else if op == 19:
            let sp = self.regs[8]

            if sp >= 4096:
                self.trap("stack underflow")
                return

            let v = self.mread(sp)
            if self.msg != "":
                return

            self.regs[8] = sp + 1
            self.regs[ar] = v
        else if op >= 20 and op <= 26:
            if self.cond(op):
                next = av
        else if op == 27:
            let sp = self.regs[8]

            if sp <= 0:
                self.trap("stack overflow")
                return

            self.regs[8] = sp - 1
            self.mwrite(sp - 1, p + 1)
            if self.msg != "":
                return

            next = av
        else if op == 28:
            let sp = self.regs[8]

            if sp >= 4096:
                self.trap("stack underflow")
                return

            let v = self.mread(sp)
            if self.msg != "":
                return

            self.regs[8] = sp + 1
            next = v
        else if op == 29:
            if self.ip >= self.inputs.length():
                self.trap("input exhausted")
                return

            self.regs[ar] = self.inputs[self.ip]
            self.ip += 1
        else if op == 30:
            let v = self.rd(ak, ar, av)
            if self.msg != "":
                return

            self.outs.append("{v}\n")
            self.hasout = true
            self.endnl = true
        else if op == 31:
            let v = self.rd(ak, ar, av)
            if self.msg != "":
                return

            if v < 0 or v > 127:
                self.trap("invalid character")
                return

            self.outs.append(self.chars[v].clone())
            self.hasout = true
            self.endnl = v == 10
        else if op == 32:
            self.halted = true

        self.steps += 1
        self.pc = next

    var fn run() Unit:
        self.pc = self.start

        while true:
            if self.pc < 0 or self.pc >= self.ops.length():
                self.msg = "pc out of range"
                self.tpc = self.pc
                self.tline = -1
                return

            if self.steps == self.budget:
                self.trap("budget exceeded")
                return

            self.exec()
            if self.msg != "" or self.halted:
                return

// evaluate one operand for pass 2: registers give 0, memory/immediate sum their expression terms
fn resolve(o: Opnd, labels: Map[String, Int], equs: Map[String, List[Int]]) Ev:
    if o.kind == 0:
        return Ev(ok: true, val: 0, msg: "")

    var acc = 0
    var k = 0

    while k < o.terms.length():
        let tm = o.terms[k]

        if tm.reg < 0:
            let ev = evaluate(tm.text, labels, equs, List[String]())
            if not ev.ok:
                return ev

            if tm.neg:
                acc = wrap32(acc - ev.val)
            else:
                acc = wrap32(acc + ev.val)

        k += 1

    return Ev(ok: true, val: acc, msg: "")

fn parse_inputs(all: List[Int], from: Int) List[Int]:
    var res = List[Int]()
    let n = all.length()
    var i = from

    while i < n:
        if is_space(all[i]):
            i += 1
        else:
            var e = i

            while e < n:
                if is_space(all[e]):
                    break

                e += 1

            let tok = slice_cs(all, i, e)
            let tn = tok.length()
            var start = 0
            var neg = false

            if tok[0] == 45:
                neg = true
                start = 1

            var ok = start < tn
            var v = 0
            var j = start

            while j < tn:
                if not is_digit(tok[j]):
                    ok = false
                else:
                    v = wrap32(v * 10 + (tok[j] - 48))

                j += 1

            if ok:
                if neg:
                    v = wrap32(-v)
                res.append(v)

            i = e

    return res

fn is_sep(all: List[Int], a: Int, b: Int) Bool:
    if b - a != 4:
        return false

    var i = a

    while i < b:
        if all[i] != 61:
            return false

        i += 1

    return true

fn render(st: St) String:
    var o = st.outs.join("")
    if st.hasout and not st.endnl:
        o = "{o}\n"

    var tail = ""

    if st.msg == "":
        tail = "-- halted after {st.steps} steps\n"
    else:
        var lt = "-"
        if st.tline >= 0:
            lt = "{st.tline}"
        tail = "-- trap: {st.msg} (pc={st.tpc} line={lt}) after {st.steps} steps\n"

    var rl = "regs:"
    var i = 0

    while i < 10:
        var nm = "sp"

        if i < 8:
            nm = "r{i}"
        else if i == 9:
            nm = "bp"

        let v = st.regs[i]
        rl = "{rl} {nm}={v}"
        i += 1

    var zi = 0
    if st.z:
        zi = 1

    var li = 0
    if st.l:
        li = 1
    return "{o}{tail}{rl}\nflags: Z={zi} L={li}\n"

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    let all = text.scalar_values()
    let n = all.length()
    var src = List[List[Int]]()
    var pos = 0
    var inpos = n

    while pos <= n:
        var e = pos

        while e < n:
            if all[e] == 10:
                break

            e += 1

        var le = e
        if le > pos:
            if all[le - 1] == 13:
                le -= 1

        if is_sep(all, pos, le):
            inpos = e + 1
            if inpos > n:
                inpos = n
            break

        src.append(slice_cs(all, pos, le))
        if e >= n:
            break

        pos = e + 1

    var st = new_state()
    st.inputs = parse_inputs(all, inpos)
    st.collect_equs(src)
    st.pass1(src)
    if st.err == "":
        st.pass2()

    if st.err != "":
        stdout().write("asm error line {st.err_line}: {st.err}\n").get()
        return 0

    st.run()
    stdout().write(render(st)).get()
    return 0
