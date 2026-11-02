import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right from "@std/math.ms"

let MASK32 = 4294967295
let MOD32 = 4294967296
let HALF32 = 2147483648
let MEM_SIZE = 4096
let OP_NAMES = [
    "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar",
    "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl",
    "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"
]
let REG_NAMES = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]

type Sym:
    kind: Int
    value: Int
    expr: String
    busy: Bool

type Opnd:
    kind: Int
    reg: Int
    text: String
    base: Int
    val: Int

type Ins:
    op: Int
    line: Int
    nops: Int
    a: Opnd
    b: Opnd

type Item:
    line: Int
    addr: Int
    count: Int
    text: String

type Prog:
    ins: List[Ins]
    items: List[Item]
    dsize: Int
    in_data: Bool
    budget: Int

type Ev:
    good: Bool
    val: Int
    reg: Int
    err: String

type StrRes:
    good: Bool
    bytes: List[Int]

type Machine:
    regs: List[Int]
    mem: List[Int]
    z: Bool
    l: Bool
    trap: String
    halted: Bool
    out: List[String]
    last_nl: Bool
    input: List[Int]
    inpos: Int
    chars: List[String]

fn wrap32(x: Int) Int:
    let u = bit_and(x, MASK32)
    if u >= HALF32:
        return u - MOD32

    return u

fn cc(c: String) Int:
    return c.to_bytes().values()[0].to_int()

fn is_digit(k: Int) Bool:
    return k >= 48 and k <= 57

fn is_ident_start(k: Int) Bool:
    return (k >= 65 and k <= 90) or (k >= 97 and k <= 122) or k == 95

fn is_ident_char(k: Int) Bool:
    return is_ident_start(k) or is_digit(k) or k == 46

fn is_ws(k: Int) Bool:
    return k == 32 or k == 9 or k == 13

fn is_ident(s: String) Bool:
    let cs = s.chars()
    let n = cs.length()
    if n == 0:
        return false
    if not is_ident_start(cc(cs[0])):
        return false

    for i in 1..n:
        if not is_ident_char(cc(cs[i])):
            return false
    return true

fn reg_of(s: String) Int:
    let names = REG_NAMES
    for i in 0..names.length():
        if names[i] == s:
            return i
    return -1

fn join_range(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var i = a

    while i < b:
        s = s.concat(cs[i])
        i += 1

    return s

fn lit_len(cs: List[String], i: Int) Int:
    let n = cs.length()
    if cs[i] != "'":
        return 0
    if i + 2 < n and cs[i + 1] != "\\" and cs[i + 1] != "'" and cs[i + 2] == "'":
        return 3
    if i + 3 < n and cs[i + 1] == "\\" and cs[i + 3] == "'":
        return 4

    return 0

fn esc_value(c: String) Int:
    if c == "n":
        return 10
    if c == "t":
        return 9
    if c == "0":
        return 0
    if c == "\\":
        return 92
    if c == "'":
        return 39
    if c == "\"":
        return 34

    return -1

fn strip_comment(cs: List[String]) String:
    let n = cs.length()
    var out = ""
    var i = 0

    while i < n:
        let c = cs[i]
        if c == ";":
            break

        if c == "\"":
            var j = i + 1

            while j < n:
                if cs[j] == "\\" and j + 1 < n:
                    j += 2
                else if cs[j] == "\"":
                    j += 1
                    break
                else:
                    j += 1

            out = out.concat(join_range(cs, i, j))
            i = j
            continue

        let L = lit_len(cs, i)

        if L > 0:
            out = out.concat(join_range(cs, i, i + L))
            i += L
            continue

        out = out.concat(c)
        i += 1

    return out

fn split_operands(s: String) List[String]:
    var res = List[String]()
    if s.trim() == "":
        return res

    let cs = s.chars()
    let n = cs.length()
    var depth = 0
    var cur = ""
    var i = 0

    while i < n:
        let L = lit_len(cs, i)

        if L > 0:
            cur = cur.concat(join_range(cs, i, i + L))
            i += L
            continue

        let c = cs[i]
        if c == "[":
            depth += 1
        if c == "]":
            depth -= 1

        if c == "," and depth == 0:
            res.append(cur.trim())
            cur = ""
        else:
            cur = cur.concat(c)

        i += 1

    res.append(cur.trim())
    return res

# Splits an expression into signed terms, each encoded as sign char + trimmed body.
# Returns an empty list when the text is malformed.
fn split_terms(cs: List[String]) List[String]:
    var res = List[String]()
    let n = cs.length()
    var sign = "+"
    var sign_set = false
    var cur = ""
    var i = 0

    while i < n:
        let L = lit_len(cs, i)

        if L > 0:
            cur = cur.concat(join_range(cs, i, i + L))
            i += L
            continue

        let c = cs[i]

        if c == "+" or c == "-":
            if cur.trim() == "":
                if res.length() > 0 or sign_set:
                    return List[String]()

                sign = c.clone()
                sign_set = true
            else:
                res.append(sign.concat(cur.trim()))
                sign = c.clone()
                cur = ""
        else:
            cur = cur.concat(c)

        i += 1

    if cur.trim() == "":
        return List[String]()

    res.append(sign.concat(cur.trim()))
    return res

fn body_of(t: String) String:
    let cs = t.chars()
    return join_range(cs, 1, cs.length())

fn is_neg(t: String) Bool:
    return t.get(0) == "-"

fn mem_content(t: String) String:
    let cs = t.chars()
    return join_range(cs, 1, cs.length() - 1)

fn check_mem(t: String) Bool:
    let cs = t.chars()
    let n = cs.length()
    if n < 2 or cs[n - 1] != "]":
        return false

    let inner = join_range(cs, 1, n - 1)
    if inner.contains("[") or inner.contains("]"):
        return false

    let terms = split_terms(inner.chars())
    if terms.length() == 0:
        return false

    var regs = 0

    for term in terms:
        if reg_of(body_of(term)) >= 0:
            if is_neg(term):
                return false

            regs += 1

    return regs <= 1

fn parse_string(s: String) StrRes:
    let cs = s.chars()
    let n = cs.length()
    var out = List[Int]()
    if n < 2 or cs[0] != "\"" or cs[n - 1] != "\"":
        return StrRes(good: false, bytes: out)

    var i = 1

    while i < n - 1:
        let c = cs[i]
        if c == "\"":
            return StrRes(good: false, bytes: out)

        if c == "\\":
            if i + 1 >= n - 1:
                return StrRes(good: false, bytes: out)

            let v = esc_value(cs[i + 1])
            if v < 0:
                return StrRes(good: false, bytes: out)

            out.append(v)
            i += 2
        else:
            for b in c.to_bytes().values():
                out.append(b.to_int())
            i += 1

    return StrRes(good: true, bytes: out)

fn parse_budget(s: String) Int:
    let cs = s.chars()
    let n = cs.length()
    if n == 0 or n > 8:
        return -1

    var v = 0

    for c in cs:
        let k = cc(c)
        if not is_digit(k):
            return -1

        v = v * 10 + (k - 48)

    if v < 1 or v > 10000000:
        return -1

    return v

fn ev_ok(v: Int) Ev:
    return Ev(good: true, val: v, reg: -1, err: "")

fn ev_err(e: String) Ev:
    return Ev(good: false, val: 0, reg: -1, err: e)

fn digit_val(k: Int, base: Int) Int:
    if k >= 48 and k <= 57:
        let d = k - 48
        if d < base:
            return d

        return -1

    if base == 16:
        if k >= 97 and k <= 102:
            return k - 87
        if k >= 65 and k <= 70:
            return k - 55

    return -1

fn eval_number(body: String, ctx: String) Ev:
    let cs = body.chars()
    let n = cs.length()
    var base = 10
    var start = 0

    if n > 2 and cs[0] == "0" and cs[1] == "x":
        base = 16
        start = 2
    else if n > 2 and cs[0] == "0" and cs[1] == "b":
        base = 2
        start = 2

    var v = 0
    var i = start

    while i < n:
        let d = digit_val(cc(cs[i]), base)
        if d < 0:
            return ev_err("invalid expression '{ctx}'")

        v = v * base + d
        if v > MASK32:
            v = MASK32 + 1
        i += 1

    if v > MASK32:
        return ev_err("immediate out of range")

    return ev_ok(wrap32(v))

fn eval_term(body: String, ctx: String, var syms: Map[String, Sym]) Ev:
    let cs = body.chars()
    let n = cs.length()
    if n == 0:
        return ev_err("invalid expression '{ctx}'")

    let k = cc(cs[0])
    if is_digit(k):
        return eval_number(body, ctx)

    if cs[0] == "'":
        let L = lit_len(cs, 0)
        if L == 0 or L != n:
            return ev_err("invalid expression '{ctx}'")

        var v = -1
        if L == 3 and cc(cs[1]) < 128:
            v = cc(cs[1])
        if L == 4:
            v = esc_value(cs[2])
        if v < 0:
            return ev_err("invalid expression '{ctx}'")

        return ev_ok(v)

    if is_ident_start(k):
        if not is_ident(body):
            return ev_err("invalid expression '{ctx}'")

        if let s = syms.get(body):
            if s.kind == 2:
                if s.busy:
                    return ev_err("circular definition '{body}'")

                let e = s.expr.clone()
                syms.remove(body.clone())
                syms.add(
                    body.clone(),
                    Sym(
                        kind: 2, value: 0, expr: e.clone(), busy: true
                    )
                )

                let r = eval_expr(e.clone(), var syms)
                syms.remove(body.clone())
                syms.add(body.clone(), Sym(kind: 2, value: 0, expr: e, busy: false))
                return r

            return ev_ok(s.value)

        return ev_err("undefined symbol '{body}'")

    return ev_err("invalid expression '{ctx}'")

fn eval_expr(text: String, var syms: Map[String, Sym]) Ev:
    let t = text.trim()
    let terms = split_terms(t.chars())
    if terms.length() == 0:
        return ev_err("invalid expression '{t}'")

    var acc = 0

    for term in terms:
        let r = eval_term(body_of(term), t, var syms)
        if not r.good:
            return r

        if is_neg(term):
            acc = acc - r.val
        else:
            acc = acc + r.val

    return ev_ok(wrap32(acc))

fn resolve_mem(t: String, var syms: Map[String, Sym]) Ev:
    let terms = split_terms(mem_content(t).chars())
    var base = -1
    var off = 0

    for term in terms:
        let body = body_of(term)
        let rr = reg_of(body)

        if rr >= 0:
            base = rr
        else:
            let r = eval_term(body.clone(), body, var syms)
            if not r.good:
                return r

            if is_neg(term):
                off = off - r.val
            else:
                off = off + r.val

    return Ev(good: true, val: wrap32(off), reg: base, err: "")

fn opcode(w: String) Int:
    let names = OP_NAMES
    for i in 0..names.length():
        if names[i] == w:
            return i
    if w == "jz":
        return 21
    if w == "jnz":
        return 22

    return -1

fn nops(op: Int) Int:
    if op == 28 or op == 32 or op == 33:
        return 0
    if (
        (op >= 13 and op <= 16)
        or op == 18
        or op == 19
        or (op >= 20 and op <= 27)
        or op == 29
        or op == 30
        or op == 31
    ):
        return 1

    return 2

fn valid_classes(op: Int, k0: Int, k1: Int, want: Int) Bool:
    if want == 0:
        return true

    if want == 1:
        if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29:
            return k0 == 1
        if op == 18 or op == 30 or op == 31:
            return k0 == 1 or k0 == 2 or k0 == 3

        return k0 == 2

    if op == 0:
        return (
            (k0 == 1 and (k1 == 1 or k1 == 2 or k1 == 3))
            or (k0 == 3 and (k1 == 1 or k1 == 2))
        )
    if op == 17:
        return k0 == 1 and k1 == 3

    return k0 == 1 and (k1 == 1 or k1 == 2 or k1 == 3)

fn classify(t: String) Int:
    if t.starts_with("["):
        return 3
    if reg_of(t) >= 0:
        return 1

    return 2

fn mk_opnd(t: String, k: Int) Opnd:
    return Opnd(kind: k, reg: reg_of(t), text: t, base: -1, val: 0)

fn empty_opnd() Opnd:
    return Opnd(kind: 0, reg: -1, text: "", base: -1, val: 0)

fn define(var syms: Map[String, Sym], name: String, kind: Int, value: Int, expr: String) String:
    if reg_of(name) >= 0:
        return "reserved name '{name}'"
    if syms.contains(name):
        return "duplicate symbol '{name}'"

    syms.add(name, Sym(kind: kind, value: value, expr: expr, busy: false))
    return ""

fn pass1_ins(var prog: Prog, lineno: Int, word: String, args: String) String:
    if prog.in_data:
        return "instruction in data section"

    let op = opcode(word)
    if op < 0:
        return "unknown mnemonic '{word}'"

    let ops = split_operands(args)

    for t in ops:
        if t == "":
            return "invalid operand ''"
        if t.starts_with("[") and not check_mem(t):
            return "invalid operand '{t}'"

    let want = nops(op)
    if ops.length() != want:
        return "wrong number of operands for '{word}'"

    var k0 = 0
    var k1 = 0
    var a = empty_opnd()
    var b = empty_opnd()

    if want >= 1:
        let t0 = ops[0]
        k0 = classify(t0)
        a = mk_opnd(t0.clone(), k0)

    if want == 2:
        let t1 = ops[1]
        k1 = classify(t1)
        b = mk_opnd(t1.clone(), k1)

    if not valid_classes(op, k0, k1, want):
        return "invalid operands for '{word}'"

    prog.ins.append(Ins(op: op, line: lineno, nops: want, a: a, b: b))
    return ""

fn data_dir(
    var syms: Map[String, Sym], var mem: List[Int], var prog: Prog, lineno: Int,
    word: String, args: String
) String:
    if word == ".word":
        let ops = split_operands(args)
        if ops.length() == 0:
            return "wrong number of operands for '.word'"
        if prog.dsize + ops.length() > MEM_SIZE:
            return "data section too large"

        for t in ops:
            prog.items.append(Item(line: lineno, addr: prog.dsize, count: 1, text: t))
            prog.dsize += 1

        return ""

    if word == ".ascii" or word == ".asciz":
        let sr = parse_string(args)
        if not sr.good:
            return "invalid string"

        var bytes = sr.bytes.clone()
        if word == ".asciz":
            bytes.append(0)
        if prog.dsize + bytes.length() > MEM_SIZE:
            return "data section too large"

        for b in bytes:
            mem[prog.dsize] = b
            prog.dsize += 1

        return ""

    let ops = split_operands(args)
    if ops.length() != 1 and ops.length() != 2:
        return "wrong number of operands for '.space'"

    let count_text = ops[0].clone()
    let r = eval_expr(count_text, var syms)
    if not r.good:
        return r.err
    if r.val < 0:
        return "invalid operand '{count_text}'"
    if prog.dsize + r.val > MEM_SIZE:
        return "data section too large"

    var fill = "0"
    if ops.length() == 2:
        fill = ops[1].clone()
    prog.items.append(Item(line: lineno, addr: prog.dsize, count: r.val, text: fill))
    prog.dsize += r.val
    return ""

fn pass1_dir(
    var syms: Map[String, Sym], var mem: List[Int], var prog: Prog, lineno: Int,
    word: String, args: String
) String:
    if word == ".text":
        if args != "":
            return "invalid operand '{args}'"

        prog.in_data = false
        return ""

    if word == ".data":
        if args != "":
            return "invalid operand '{args}'"

        prog.in_data = true
        return ""

    if word == ".equ":
        let ops = split_operands(args)
        if ops.length() != 2:
            return "wrong number of operands for '.equ'"

        let name = ops[0]
        if not is_ident(name):
            return "invalid operand '{name}'"

        return define(var syms, name.clone(), 2, 0, ops[1].clone())

    if word == ".budget":
        let v = parse_budget(args)
        if v < 0:
            return "invalid operand '{args}'"

        prog.budget = v
        return ""

    if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
        if not prog.in_data:
            return "data directive in text section"

        return data_dir(var syms, var mem, var prog, lineno, word, args)

    return "unknown directive '{word}'"

fn pass1_line(
    var syms: Map[String, Sym], var mem: List[Int], var prog: Prog, lineno: Int,
    line: String
) String:
    let s = strip_comment(line.chars())
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var going = true

    while going:
        going = false
        while i < n and is_ws(cc(cs[i])):
            i += 1

        if i < n and is_ident_start(cc(cs[i])):
            var j = i + 1
            while j < n and is_ident_char(cc(cs[j])):
                j += 1

            if j < n and cs[j] == ":":
                let name = join_range(cs, i, j)
                var e = ""

                if prog.in_data:
                    e = define(var syms, name, 1, prog.dsize, "")
                else:
                    e = define(var syms, name, 0, prog.ins.length(), "")

                if e != "":
                    return e

                i = j + 1
                going = true

    let rest = join_range(cs, i, n).trim()
    if rest == "":
        return ""

    let rcs = rest.chars()
    let rn = rcs.length()
    var w = 0
    while w < rn and not is_ws(cc(rcs[w])):
        w += 1

    let word = join_range(rcs, 0, w)
    let args = join_range(rcs, w, rn).trim()
    if word.starts_with("."):
        return pass1_dir(var syms, var mem, var prog, lineno, word, args)

    return pass1_ins(var prog, lineno, word, args)

fn pass2_item(it: Item, var syms: Map[String, Sym], var mem: List[Int]) String:
    let r = eval_expr(it.text, var syms)
    if not r.good:
        return r.err

    var k = 0

    while k < it.count:
        mem[it.addr + k] = r.val
        k += 1

    return ""

fn resolve_op(o: Opnd, var syms: Map[String, Sym]) Ev:
    if o.kind == 2:
        return eval_expr(o.text, var syms)
    if o.kind == 3:
        return resolve_mem(o.text, var syms)

    return ev_ok(0)

fn pass2_ins(ins: Ins, var syms: Map[String, Sym], n: Int, var code: List[Ins]) String:
    let ra = resolve_op(ins.a, var syms)
    if not ra.good:
        return ra.err

    let rb = resolve_op(ins.b, var syms)
    if not rb.good:
        return rb.err

    let a = Opnd(
        kind: ins.a.kind, reg: ins.a.reg, text: ins.a.text, base: ra.reg, val: ra.val
    )
    let b = Opnd(
        kind: ins.b.kind, reg: ins.b.reg, text: ins.b.text, base: rb.reg, val: rb.val
    )
    if ins.op >= 20 and ins.op <= 27:
        if a.val < 0 or a.val >= n:
            return "invalid jump target"
    code.append(Ins(op: ins.op, line: ins.line, nops: ins.nops, a: a, b: b))
    return ""

fn char_of(code: Int) String:
    let b = "A".to_bytes().with_value(0, code.to_uint8().get(0))
    return b.decode_utf8().get("?")

fn rd(var m: Machine, o: Opnd) Int:
    if o.kind == 1:
        return m.regs[o.reg]
    if o.kind == 2:
        return o.val

    let addr = ea(var m, o)
    if m.trap != "":
        return 0

    return m.mem[addr]

fn ea(var m: Machine, o: Opnd) Int:
    var base = 0
    if o.base >= 0:
        base = m.regs[o.base]

    let addr = wrap32(base + o.val)
    if addr < 0 or addr >= MEM_SIZE:
        m.trap = "memory access out of range: {addr}"
    return addr

fn wr(var m: Machine, o: Opnd, v: Int) Unit:
    if o.kind == 1:
        m.regs[o.reg] = v
        return

    let addr = ea(var m, o)
    if m.trap != "":
        return

    m.mem[addr] = v

fn exec(var m: Machine, ins: Ins, pc: Int) Int:
    let a = ins.a
    let b = ins.b
    let op = ins.op

    if op == 0:
        let v = rd(var m, b)
        if m.trap != "":
            return pc

        wr(var m, a, v)
        return pc + 1

    if op >= 1 and op <= 11:
        let s = rd(var m, b)
        if m.trap != "":
            return pc

        let d = m.regs[a.reg]
        var r = 0

        if op == 1:
            r = wrap32(d + s)
        else if op == 2:
            r = wrap32(d - s)
        else if op == 3:
            r = wrap32(d * s)
        else if op == 4 or op == 5:
            if s == 0:
                m.trap = "division by zero"
                return pc

            if op == 4:
                r = wrap32(d / s)
            else:
                r = wrap32(d % s)
        else if op == 6:
            r = bit_and(d, s)
        else if op == 7:
            r = bit_or(d, s)
        else if op == 8:
            r = bit_xor(d, s)
        else if op == 9:
            r = wrap32(shift_left(d, bit_and(s, 31)))
        else if op == 10:
            r = wrap32(shift_right(bit_and(d, MASK32), bit_and(s, 31)))
        else:
            r = wrap32(shift_right(d, bit_and(s, 31)))

        m.regs[a.reg] = r
        return pc + 1

    if op == 12:
        let x = m.regs[a.reg]
        let y = rd(var m, b)
        if m.trap != "":
            return pc

        m.z = x == y
        m.l = x < y
        return pc + 1

    if op >= 13 and op <= 16:
        let d = m.regs[a.reg]
        var r = 0

        if op == 13:
            r = wrap32(0 - d)
        else if op == 14:
            r = bit_not(d)
        else if op == 15:
            r = wrap32(d + 1)
        else:
            r = wrap32(d - 1)

        m.regs[a.reg] = r
        return pc + 1

    if op == 17:
        var base = 0
        if b.base >= 0:
            base = m.regs[b.base]
        m.regs[a.reg] = wrap32(base + b.val)
        return pc + 1

    if op == 18:
        let v = rd(var m, a)
        if m.trap != "":
            return pc

        let sp = m.regs[8]

        if sp <= 0:
            m.trap = "stack overflow"
            return pc

        let ns = sp - 1
        m.regs[8] = ns

        if ns < 0 or ns >= MEM_SIZE:
            m.trap = "memory access out of range: {ns}"
            return pc

        m.mem[ns] = v
        return pc + 1

    if op == 19:
        let sp = m.regs[8]

        if sp >= MEM_SIZE:
            m.trap = "stack underflow"
            return pc

        if sp < 0:
            m.trap = "memory access out of range: {sp}"
            return pc

        let v = m.mem[sp]
        m.regs[8] = sp + 1
        m.regs[a.reg] = v
        return pc + 1

    if op >= 20 and op <= 27:
        if op == 27:
            let sp = m.regs[8]

            if sp <= 0:
                m.trap = "stack overflow"
                return pc

            let ns = sp - 1
            m.regs[8] = ns

            if ns < 0 or ns >= MEM_SIZE:
                m.trap = "memory access out of range: {ns}"
                return pc

            m.mem[ns] = pc + 1
            return a.val

        var take = false

        if op == 20:
            take = true
        else if op == 21:
            take = m.z
        else if op == 22:
            take = not m.z
        else if op == 23:
            take = m.l
        else if op == 24:
            take = m.l or m.z
        else if op == 25:
            take = (not m.l) and (not m.z)
        else:
            take = not m.l

        if take:
            return a.val

        return pc + 1

    if op == 28:
        let sp = m.regs[8]

        if sp >= MEM_SIZE:
            m.trap = "stack underflow"
            return pc

        if sp < 0:
            m.trap = "memory access out of range: {sp}"
            return pc

        let v = m.mem[sp]
        m.regs[8] = sp + 1
        return v

    if op == 29:
        if m.inpos >= m.input.length():
            m.trap = "input exhausted"
            return pc

        let v = m.input[m.inpos]
        m.inpos += 1
        m.regs[a.reg] = v
        return pc + 1

    if op == 30:
        let v = rd(var m, a)
        if m.trap != "":
            return pc

        m.out.append("{v}\n")
        m.last_nl = true
        return pc + 1

    if op == 31:
        let v = rd(var m, a)
        if m.trap != "":
            return pc

        if v < 0 or v > 127:
            m.trap = "invalid character"
            return pc

        m.out.append(m.chars[v].clone())
        m.last_nl = v == 10
        return pc + 1

    if op == 32:
        m.halted = true
        return pc

    return pc + 1

fn input_value(tok: String) Int:
    let cs = tok.chars()
    let n = cs.length()
    var start = 0
    var neg = false

    if n > 0 and cs[0] == "-":
        neg = true
        start = 1

    if start >= n:
        return 0

    var u = 0
    var i = start

    while i < n:
        let k = cc(cs[i])
        if not is_digit(k):
            return 0

        u = (u * 10 + (k - 48)) % MOD32
        i += 1

    if neg:
        return wrap32(0 - u)

    return wrap32(u)

fn is_valid_token(tok: String) Bool:
    let cs = tok.chars()
    let n = cs.length()
    var start = 0
    if n > 0 and cs[0] == "-":
        start = 1
    if start >= n:
        return false

    var i = start

    while i < n:
        if not is_digit(cc(cs[i])):
            return false

        i += 1

    return true

fn strip_cr(l: String) String:
    let cs = l.chars()
    let n = cs.length()
    if n > 0 and cc(cs[n - 1]) == 13:
        return join_range(cs, 0, n - 1)

    return l

fn parse_input_lines(lines: List[String]) List[Int]:
    var res = List[Int]()

    for l in lines:
        var tok = ""

        for c in l.chars():
            if is_ws(cc(c)):
                if tok != "" and is_valid_token(tok):
                    res.append(input_value(tok))
                tok = ""
            else:
                tok = tok.concat(c)

        if tok != "" and is_valid_token(tok):
            res.append(input_value(tok))

    return res

export fn main() Int:
    let raw = read_lines(stdin()).get()
    var src = List[String]()
    var inp = List[String]()
    var seen_sep = false

    for l in raw:
        let t = strip_cr(l)

        if seen_sep:
            inp.append(t)
        else if t == "====":
            seen_sep = true
        else:
            src.append(t)

    var syms = Map[String, Sym]()
    var mem = List[Int]()
    for i in 0..MEM_SIZE:
        mem.append(0)

    var prog = Prog(
        ins: List[Ins](), items: List[Item](), dsize: 0, in_data: false, budget: 100000
    )
    var ln = 0

    for l in src:
        ln += 1

        let e = pass1_line(var syms, var mem, var prog, ln, l)

        if e != "":
            stdout().write("asm error line {ln}: {e}\n").get()
            return 0

    var code = List[Ins]()
    let n = prog.ins.length()
    var ii = 0
    var di = 0

    while ii < n or di < prog.items.length():
        if (
            di >= prog.items.length()
            or (ii < n and prog.ins[ii].line < prog.items[di].line)
        ):
            let ins = prog.ins[ii].clone()
            let e = pass2_ins(ins.clone(), var syms, n, var code)

            if e != "":
                stdout().write("asm error line {ins.line}: {e}\n").get()
                return 0

            ii += 1
        else:
            let it = prog.items[di].clone()
            let e = pass2_item(it, var syms, var mem)

            if e != "":
                stdout().write("asm error line {it.line}: {e}\n").get()
                return 0

            di += 1

    var entry = 0
    if let s = syms.get("main"):
        if s.kind == 0:
            entry = s.value

    var chars = List[String]()
    for i in 0..128:
        chars.append(char_of(i))

    var regs = List[Int]()
    for i in 0..10:
        regs.append(0)
    regs[8] = MEM_SIZE

    var m = Machine(
        regs: regs, mem: mem, z: false, l: false, trap: "", halted: false,
        out: List[String](), last_nl: false, input: parse_input_lines(inp), inpos: 0,
        chars: chars
    )
    var pc = entry
    var steps = 0
    var is_trap = false
    var trap_msg = ""
    var trap_pc = 0
    var trap_line = "-"
    var done = false

    while not done:
        if pc < 0 or pc >= n:
            is_trap = true
            trap_msg = "pc out of range"
            trap_pc = pc
            trap_line = "-"
            break

        let ins = code[pc]

        if steps == prog.budget:
            is_trap = true
            trap_msg = "budget exceeded"
            trap_pc = pc
            trap_line = "{ins.line}"
            break

        let next = exec(var m, ins, pc)

        if m.trap != "":
            is_trap = true
            trap_msg = m.trap
            trap_pc = pc
            trap_line = "{ins.line}"
            break

        steps += 1
        if m.halted:
            break

        pc = next

    var text = m.out.join("")
    if m.out.length() > 0 and not m.last_nl:
        text = text.concat("\n")

    if is_trap:
        text = text.concat(
            "-- trap: {trap_msg} (pc={trap_pc} line={trap_line}) after {steps} steps\n"
        )
    else:
        text = text.concat("-- halted after {steps} steps\n")

    let names = REG_NAMES
    var line = "regs:"
    for i in 0..10:
        line = line.concat(" {names[i]}={m.regs[i]}")
    text = text.concat(line + "\n")

    var zb = 0
    if m.z:
        zb = 1

    var lb = 0
    if m.l:
        lb = 1
    text = text.concat("flags: Z={zb} L={lb}\n")
    stdout().write(text).get()
    return 0
