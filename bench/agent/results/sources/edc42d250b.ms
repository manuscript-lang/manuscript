import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"
import bit_and, bit_or, bit_xor from "@std/math/math.ms"
import from_scalars from "@std/string.ms"

type Val:
    v: Int
    err: String

type Term:
    sign: Int
    text: String

type EquDef:
    line: Int
    expr: String

type MemV:
    base: Int
    c: Int
    err: String

type Opv:
    kind: Int
    v: Int
    base: Int
    err: String

type Pl:
    num: Int
    labels: List[String]
    rest: String
    lerr: String

type Wr:
    w: String
    r: String

type Stmt:
    line: Int
    sec: Int
    kind: Int
    op: Int
    name: String
    args: List[String]
    count: Int

type P1:
    err: String
    line: Int
    ninstr: Int
    daddr: Int
    budget: Int
    entry: Int

type P2:
    err: String
    line: Int

type Ins:
    op: Int
    ak: Int
    av: Int
    ab: Int
    bk: Int
    bv: Int
    bb: Int
    line: Int

type SL:
    err: String
    vals: List[Int]

fn w32(x: Int) Int:
    return ((x + 2147483648) % 4294967296 + 4294967296) % 4294967296 - 2147483648

fn letters() String:
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"

fn digits() String:
    return "0123456789"

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn is_id_start(c: String) Bool:
    return c.length() == 1 and letters().contains(c)

fn is_id_char(c: String) Bool:
    return (
        c.length() == 1
        and (letters().contains(c) or digits().contains(c) or c == ".")
    )

fn ident_len(cs: List[String]) Int:
    n := cs.length()
    if n == 0 or not is_id_start(cs[0]):
        return 0

    var i = 1
    while i < n and is_id_char(cs[i]):
        i += 1
    return i

fn is_ident(s: String) Bool:
    cs := s.chars()
    return cs.length() > 0 and ident_len(cs) == cs.length()

fn reg_of(s: String) Int:
    names := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    var i = 0

    for n in names:
        if n == s:
            return i

        i += 1

    return -1

fn dval(c: String) Int:
    alph := "0123456789abcdefABCDEF"
    var i = 0

    for ch in alph.chars():
        if ch == c:
            if i >= 16:
                return i - 6

            return i

        i += 1

    return -1

fn join_range(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var i = a

    while i < b:
        out = out + cs[i]
        i += 1

    return out

// Returns the index just past the literal that starts at cs[start] (a quote).
fn lit_end(cs: List[String], start: Int) Int:
    q := cs[start]
    var i = start + 1

    while i < cs.length():
        if cs[i] == "\\":
            i += 2
        else if cs[i] == q:
            return i + 1
        else:
            i += 1

    return cs.length()

fn strip_comment(s: String) String:
    cs := s.chars()
    n := cs.length()
    var out = ""
    var i = 0

    while i < n:
        c := cs[i]

        if c == "\"" or c == "'":
            e := lit_end(cs, i)
            out = out + join_range(cs, i, e)
            i = e
        else if c == ";":
            break
        else:
            out = out + c
            i += 1

    return out

// Splits operands at commas outside brackets and literals; each piece trimmed.
fn split_args(s: String) List[String]:
    cs := s.chars()
    n := cs.length()
    var out = List[String]()
    var cur = ""
    var depth = 0
    var i = 0

    while i < n:
        c := cs[i]

        if c == "\"" or c == "'":
            e := lit_end(cs, i)
            cur = cur + join_range(cs, i, e)
            i = e
        else:
            if c == "[":
                depth += 1
            if c == "]":
                depth -= 1

            if c == "," and depth == 0:
                out.append(cur.trim())
                cur = ""
            else:
                cur = cur + c

            i += 1

    out.append(cur.trim())
    return out

// Splits an expression into signed terms (leading sign included in the first term).
fn split_terms(s: String) List[Term]:
    cs := s.trim().chars()
    n := cs.length()
    var out = List[Term]()
    var sign = 1
    var i = 0

    if n > 0 and cs[0] == "-":
        sign = -1
        i = 1
    else if n > 0 and cs[0] == "+":
        i = 1

    var cur = ""

    while i < n:
        c := cs[i]

        if c == "\"" or c == "'":
            e := lit_end(cs, i)
            cur = cur + join_range(cs, i, e)
            i = e
        else if c == "+" or c == "-":
            out.append(Term(sign: sign, text: cur))
            cur = ""

            if c == "+":
                sign = 1
            else:
                sign = -1

            i += 1
        else:
            cur = cur + c
            i += 1

    out.append(Term(sign: sign, text: cur))
    return out

fn split_word(s: String) Wr:
    cs := s.chars()
    var i = 0
    while i < cs.length() and not is_space(cs[i]):
        i += 1
    return Wr(w: join_range(cs, 0, i), r: join_range(cs, i, cs.length()).trim())

fn parse_line(num: Int, raw: String) Pl:
    var rest = strip_comment(raw).trim()
    var labels = List[String]()
    var lerr = ""
    var go = true

    while go:
        rc := rest.chars()
        k := ident_len(rc)

        if k > 0 and k < rc.length() and rc[k] == ":":
            name := join_range(rc, 0, k)
            if reg_of(name) >= 0 and lerr == "":
                lerr = "reserved name '{name}'"
            labels.append(name)
            rest = join_range(rc, k + 1, rc.length()).trim()
        else:
            go = false

    return Pl(num: num, labels: labels, rest: rest, lerr: lerr)

fn collect_equs(lines: List[Pl]) Map[String, EquDef]:
    var m = Map[String, EquDef]()

    for pl in lines:
        wr := split_word(pl.rest)

        if wr.w == ".equ":
            a := split_args(wr.r)

            if a.length() == 2 and is_ident(a[0]) and reg_of(a[0]) < 0:
                var seen = false
                if _d := m.get(a[0]):
                    seen = true

                if not seen:
                    nm := a[0]
                    m[nm.clone()] = EquDef(line: pl.num, expr: a[1].clone())

    return m

fn escape_val(c: String) Int:
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

fn str_lit(s: String) SL:
    cs := s.chars()
    n := cs.length()
    var vals = List[Int]()
    if n < 2 or cs[0] != "\"" or cs[n - 1] != "\"":
        return SL(err: "invalid string", vals: vals)

    var i = 1

    while i < n - 1:
        c := cs[i]

        if c == "\\":
            if i + 1 >= n - 1:
                return SL(err: "invalid string", vals: vals)

            e := escape_val(cs[i + 1])
            if e < 0:
                return SL(err: "invalid string", vals: vals)

            vals.append(e)
            i += 2
        else if c == "\"":
            return SL(err: "invalid string", vals: vals)
        else:
            bs := c.as_bytes()
            var k = 0

            while k < bs.length():
                vals.append(bs.get(k).to_int())
                k += 1

            i += 1

    return SL(err: "", vals: vals)

// Value of a non-negative decimal integer, capped; -1 if not all digits.
fn decimal_value(s: String) Int:
    cs := s.chars()
    if cs.length() == 0:
        return -1

    var acc = 0

    for c in cs:
        if not digits().contains(c):
            return -1

        acc = acc * 10 + dval(c)
        if acc > 1000000000000:
            acc = 1000000000000

    return acc

fn eval_term(
    x: String,
    labels: Map[String, Int],
    equs: Map[String, EquDef],
    stack: String
) Val:
    cs := x.trim().chars()
    n := cs.length()
    if n == 0:
        return Val(v: 0, err: "INVALID")

    c0 := cs[0]

    if digits().contains(c0):
        var base = 10
        var start = 0

        if n >= 2 and cs[0] == "0" and cs[1] == "x":
            base = 16
            start = 2
        else if n >= 2 and cs[0] == "0" and cs[1] == "b":
            base = 2
            start = 2

        if start >= n:
            return Val(v: 0, err: "INVALID")

        var acc = 0
        var k = start

        while k < n:
            d := dval(cs[k])
            if d < 0 or d >= base:
                return Val(v: 0, err: "INVALID")

            acc = acc * base + d
            if acc > 4294967295:
                acc = 4294967296
            k += 1

        if acc > 4294967295:
            return Val(v: 0, err: "immediate out of range")

        return Val(v: acc, err: "")

    if c0 == "'":
        if n == 3 and cs[2] == "'" and cs[1] != "\\" and cs[1] != "'":
            bs := cs[1].as_bytes()
            if bs.length() == 1:
                return Val(v: bs.get(0).to_int(), err: "")

            return Val(v: 0, err: "INVALID")

        if n == 4 and cs[1] == "\\" and cs[3] == "'":
            e := escape_val(cs[2])
            if e >= 0:
                return Val(v: e, err: "")

        return Val(v: 0, err: "INVALID")

    if is_id_start(c0) and ident_len(cs) == n:
        name := join_range(cs, 0, n)
        if v := labels.get(name):
            return Val(v: v, err: "")

        if d := equs.get(name):
            if stack.contains("|{name}|"):
                return Val(v: 0, err: "circular definition of '{name}'")

            return eval_expr(d.expr, labels, equs, "{stack}|{name}|")

        return Val(v: 0, err: "undefined symbol '{name}'")

    return Val(v: 0, err: "INVALID")

fn eval_expr(
    text: String,
    labels: Map[String, Int],
    equs: Map[String, EquDef],
    stack: String
) Val:
    t := text.trim()
    var acc = 0

    for tm in split_terms(t):
        r := eval_term(tm.text, labels, equs, stack)
        if r.err == "INVALID":
            return Val(v: 0, err: "invalid expression '{t}'")
        if r.err != "":
            return r

        acc = w32(acc + tm.sign * r.v)

    return Val(v: acc, err: "")

fn bracket_inner(o: String) String:
    cs := o.chars()
    return join_range(cs, 1, cs.length() - 1)

// Structural check of an operand (pass 1); returns an error message or "".
fn check_operand(o: String) String:
    if o == "":
        return "invalid operand ''"
    if reg_of(o) >= 0:
        return ""
    if o.get(0) != "[":
        return ""

    bad := "invalid operand '{o}'"
    cs := o.chars()
    if cs.length() < 2 or cs[cs.length() - 1] != "]":
        return bad

    inner := bracket_inner(o)
    if inner.trim() == "":
        return bad

    var nregs = 0

    for tm in split_terms(inner):
        x := tm.text.trim()
        if x == "":
            return bad

        if reg_of(x) >= 0:
            if tm.sign < 0:
                return bad

            nregs += 1
            if nregs > 1:
                return bad

    return ""

fn opclass(o: String) Int:
    if reg_of(o) >= 0:
        return 1
    if o.get(0) == "[":
        return 3

    return 2

fn eval_mem(o: String, labels: Map[String, Int], equs: Map[String, EquDef]) MemV:
    var base = -1
    var c = 0

    for tm in split_terms(bracket_inner(o)):
        x := tm.text.trim()
        r := reg_of(x)

        if r >= 0:
            base = r
        else:
            v := eval_expr(x, labels, equs, "")
            if v.err != "":
                return MemV(base: -1, c: 0, err: v.err)

            c = w32(c + tm.sign * v.v)

    return MemV(base: base, c: c, err: "")

fn evalop(o: String, labels: Map[String, Int], equs: Map[String, EquDef]) Opv:
    r := reg_of(o)
    if r >= 0:
        return Opv(kind: 1, v: r, base: -1, err: "")

    if o.get(0) == "[":
        m := eval_mem(o, labels, equs)
        return Opv(kind: 3, v: m.c, base: m.base, err: m.err)

    e := eval_expr(o, labels, equs, "")
    return Opv(kind: 2, v: e.v, base: -1, err: e.err)

fn opcode_of(s: String) Int:
    names := [
        "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr",
        "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je",
        "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt",
        "nop"
    ]
    var i = 0

    for n in names:
        if n == s:
            return i

        i += 1

    if s == "jz":
        return 21
    if s == "jnz":
        return 22

    return -1

fn arity(op: Int) Int:
    if op == 28 or op == 32 or op == 33:
        return 0
    if op <= 12 or op == 17:
        return 2

    return 1

fn valid_classes(op: Int, cls: List[Int]) Bool:
    var c0 = 0
    var c1 = 0
    if cls.length() > 0:
        c0 = cls[0]
    if cls.length() > 1:
        c1 = cls[1]
    if op == 0:
        return (c0 == 1 and c1 >= 1 and c1 <= 3) or (c0 == 3 and (c1 == 1 or c1 == 2))
    if op >= 1 and op <= 12:
        return c0 == 1 and c1 >= 1 and c1 <= 3
    if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29:
        return c0 == 1
    if op == 17:
        return c0 == 1 and c1 == 3
    if op == 18 or op == 30 or op == 31:
        return c0 >= 1 and c0 <= 3
    if op >= 20 and op <= 27:
        return c0 == 2

    return true

fn perr(msg: String, num: Int) P1:
    return P1(err: msg, line: num, ninstr: 0, daddr: 0, budget: 0, entry: 0)

fn pass1(
    lines: List[Pl],
    equs: Map[String, EquDef],
    var labels: Map[String, Int],
    var stmts: List[Stmt]
) P1:
    var sec = 0
    var ninstr = 0
    var daddr = 0
    var budget = 100000
    var entry = 0

    for pl in lines:
        num := pl.num
        if pl.lerr != "":
            return perr(pl.lerr.clone(), num)

        for lab in pl.labels:
            if _p := labels.get(lab):
                return perr("duplicate symbol '{lab}'", num)

            if d := equs.get(lab):
                if d.line < num:
                    return perr("duplicate symbol '{lab}'", num)

            var val = daddr
            if sec == 0:
                val = ninstr
            labels[lab.clone()] = val
            if sec == 0 and lab == "main":
                entry = ninstr

        if pl.rest == "":
            continue

        wr := split_word(pl.rest)
        word := wr.w
        argtext := wr.r

        if word.get(0) == ".":
            if word == ".text" or word == ".data":
                if argtext != "":
                    return perr("invalid operand '{argtext}'", num)

                if word == ".text":
                    sec = 0
                else:
                    sec = 1
            else if word == ".budget":
                bv := decimal_value(argtext)
                if bv < 1 or bv > 10000000:
                    return perr("invalid operand '{argtext}'", num)

                budget = bv
            else if word == ".equ":
                a := split_args(argtext)
                if a.length() != 2:
                    return perr("wrong number of operands for '.equ'", num)

                name := a[0]
                if not is_ident(name):
                    return perr("invalid operand '{name}'", num)
                if reg_of(name) >= 0:
                    return perr("reserved name '{name}'", num)
                if _q := labels.get(name):
                    return perr("duplicate symbol '{name}'", num)

                if d := equs.get(name):
                    if d.line < num:
                        return perr("duplicate symbol '{name}'", num)
            else if (
                word == ".word"
                or word == ".ascii"
                or word == ".asciz"
                or word == ".space"
            ):
                if sec == 0:
                    return perr("data directive in text section", num)

                if word == ".word":
                    if argtext == "":
                        return perr("wrong number of operands for '.word'", num)

                    a := split_args(argtext)
                    cnt := a.length()
                    if daddr + cnt > 4096:
                        return perr("data section too large", num)

                    daddr += cnt
                    stmts.append(
                        Stmt(
                            line: num, sec: 1, kind: 1, op: 0, name: word.clone(),
                            args: a, count: cnt
                        )
                    )
                else if word == ".space":
                    if argtext == "":
                        return perr("wrong number of operands for '.space'", num)

                    a := split_args(argtext)
                    if a.length() > 2:
                        return perr("wrong number of operands for '.space'", num)

                    nv := eval_expr(a[0], labels, equs, "")
                    if nv.err != "":
                        return perr(nv.err, num)
                    if nv.v < 0:
                        return perr("invalid operand '{a[0]}'", num)
                    if daddr + nv.v > 4096:
                        return perr("data section too large", num)

                    daddr += nv.v
                    stmts.append(
                        Stmt(
                            line: num, sec: 1, kind: 3, op: 0, name: word.clone(),
                            args: a, count: nv.v
                        )
                    )
                else:
                    sl := str_lit(argtext)
                    if sl.err != "":
                        return perr(sl.err, num)

                    var cnt = sl.vals.length()
                    if word == ".asciz":
                        cnt += 1
                    if daddr + cnt > 4096:
                        return perr("data section too large", num)

                    daddr += cnt

                    var one = List[String]()
                    one.append(argtext.clone())
                    stmts.append(
                        Stmt(
                            line: num, sec: 1, kind: 2, op: 0, name: word.clone(),
                            args: one, count: cnt
                        )
                    )
            else:
                return perr("unknown directive '{word}'", num)
        else:
            if sec == 1:
                return perr("instruction in data section", num)

            op := opcode_of(word)
            if op < 0:
                return perr("unknown mnemonic '{word}'", num)

            var args = List[String]()
            if argtext != "":
                args = split_args(argtext)

            var cls = List[Int]()

            for a in args:
                e := check_operand(a)
                if e != "":
                    return perr(e, num)

                cls.append(opclass(a))

            if args.length() != arity(op):
                return perr("wrong number of operands for '{word}'", num)
            if not valid_classes(op, cls):
                return perr("invalid operands for '{word}'", num)

            stmts.append(
                Stmt(
                    line: num, sec: 0, kind: 0, op: op, name: word.clone(), args: args,
                    count: 0
                )
            )
            ninstr += 1

    return P1(
        err: "", line: 0, ninstr: ninstr, daddr: daddr, budget: budget, entry: entry
    )

fn pass2(
    stmts: List[Stmt],
    labels: Map[String, Int],
    equs: Map[String, EquDef],
    ninstr: Int,
    var code: List[Ins],
    var data: List[Int]
) P2:
    for st in stmts:
        if st.kind == 0:
            var ak = 0
            var av = 0
            var ab = -1
            var bk = 0
            var bv = 0
            var bb = -1

            if st.args.length() >= 1:
                o := evalop(st.args[0], labels, equs)
                if o.err != "":
                    return P2(err: o.err, line: st.line)

                ak = o.kind
                av = o.v
                ab = o.base

            if st.args.length() >= 2:
                o := evalop(st.args[1], labels, equs)
                if o.err != "":
                    return P2(err: o.err, line: st.line)

                bk = o.kind
                bv = o.v
                bb = o.base

            if st.op >= 20 and st.op <= 27:
                if av < 0 or av >= ninstr:
                    return P2(err: "invalid jump target", line: st.line)
            code.append(
                Ins(
                    op: st.op, ak: ak, av: av, ab: ab, bk: bk, bv: bv, bb: bb,
                    line: st.line
                )
            )
        else if st.kind == 1:
            for a in st.args:
                e := eval_expr(a, labels, equs, "")
                if e.err != "":
                    return P2(err: e.err, line: st.line)

                data.append(e.v)
        else if st.kind == 2:
            sl := str_lit(st.args[0])
            for x in sl.vals:
                data.append(x)
            if st.name == ".asciz":
                data.append(0)
        else:
            var fill = 0

            if st.args.length() == 2:
                f := eval_expr(st.args[1], labels, equs, "")
                if f.err != "":
                    return P2(err: f.err, line: st.line)

                fill = f.v

            var k = 0

            while k < st.count:
                data.append(fill)
                k += 1

    return P2(err: "", line: 0)

fn input_value(tok: String) Val:
    cs := tok.chars()
    var i = 0
    var neg = false

    if cs.length() > 0 and cs[0] == "-":
        neg = true
        i = 1

    if i >= cs.length():
        return Val(v: 0, err: "skip")

    var acc = 0

    while i < cs.length():
        if not digits().contains(cs[i]):
            return Val(v: 0, err: "skip")

        acc = (acc * 10 + dval(cs[i])) % 4294967296
        i += 1

    if neg:
        acc = -acc
    return Val(v: w32(acc), err: "")

fn tokens(s: String) List[String]:
    var out = List[String]()
    var cur = ""

    for c in s.chars():
        if is_space(c):
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur = cur + c

    if cur != "":
        out.append(cur)
    return out

fn ea(base: Int, c: Int, regs: List[Int]) Int:
    if base < 0:
        return c

    return w32(regs[base] + c)

fn pow2(c: Int) Int:
    var p = 1
    var i = 0

    while i < c:
        p = p * 2
        i += 1

    return p

fn run(
    code: List[Ins],
    data: List[Int],
    input: List[Int],
    budget: Int,
    entry: Int,
    chtab: List[String]
) String:
    var mem = List[Int]()
    var i0 = 0

    while i0 < 4096:
        mem.append(0)
        i0 += 1

    var di = 0

    while di < data.length():
        mem[di] = data[di]
        di += 1

    var regs = List[Int]()
    var i1 = 0

    while i1 < 10:
        regs.append(0)
        i1 += 1

    regs[8] = 4096

    var z = false
    var l = false
    var pc = entry
    var steps = 0
    var inpos = 0
    var outs = List[String]()
    var last_nl = true
    var trap = ""
    var halted = false
    n := code.length()

    while true:
        if steps >= budget:
            trap = "budget exceeded"
            break

        if pc < 0 or pc >= n:
            trap = "pc out of range"
            break

        ins := code[pc]
        op := ins.op
        var nxt = pc + 1
        var sv = 0

        if op <= 12 or op == 18 or op == 30 or op == 31:
            var sk = ins.bk
            var sval = ins.bv
            var sbase = ins.bb

            if op == 18 or op == 30 or op == 31:
                sk = ins.ak
                sval = ins.av
                sbase = ins.ab

            if sk == 1:
                sv = regs[sval]
            else if sk == 2:
                sv = sval
            else:
                a := ea(sbase, sval, regs)

                if a < 0 or a >= 4096:
                    trap = "memory access out of range: {a}"
                    break

                sv = mem[a]

        if op == 0:
            if ins.ak == 3:
                a := ea(ins.ab, ins.av, regs)

                if a < 0 or a >= 4096:
                    trap = "memory access out of range: {a}"
                    break

                mem[a] = sv
            else:
                regs[ins.av] = sv
        else if op >= 1 and op <= 11:
            d := regs[ins.av]
            var r = 0

            if op == 1:
                r = d + sv
            else if op == 2:
                r = d - sv
            else if op == 3:
                r = d * sv
            else if op == 4 or op == 5:
                if sv == 0:
                    trap = "division by zero"
                    break

                if op == 4:
                    r = d / sv
                else:
                    r = d % sv
            else if op == 6:
                r = bit_and(d, sv)
            else if op == 7:
                r = bit_or(d, sv)
            else if op == 8:
                r = bit_xor(d, sv)
            else:
                var cnt = sv % 32
                if cnt < 0:
                    cnt = cnt + 32

                p := pow2(cnt)
                u := (d % 4294967296 + 4294967296) % 4294967296

                if op == 9:
                    r = u * p
                else if op == 10:
                    r = u / p
                else:
                    var q = d / p
                    if d < 0 and q * p != d:
                        q = q - 1
                    r = q

            regs[ins.av] = w32(r)
        else if op == 12:
            d := regs[ins.av]
            z = d == sv
            l = d < sv
        else if op == 13:
            regs[ins.av] = w32(-regs[ins.av])
        else if op == 14:
            regs[ins.av] = w32(-regs[ins.av] - 1)
        else if op == 15:
            regs[ins.av] = w32(regs[ins.av] + 1)
        else if op == 16:
            regs[ins.av] = w32(regs[ins.av] - 1)
        else if op == 17:
            regs[ins.av] = ea(ins.bb, ins.bv, regs)
        else if op == 18:
            if regs[8] <= 0:
                trap = "stack overflow"
                break

            regs[8] = regs[8] - 1

            a := regs[8]

            if a < 0 or a >= 4096:
                trap = "memory access out of range: {a}"
                break

            mem[a] = sv
        else if op == 19:
            if regs[8] >= 4096:
                trap = "stack underflow"
                break

            a := regs[8]

            if a < 0 or a >= 4096:
                trap = "memory access out of range: {a}"
                break

            v := mem[a]
            regs[8] = regs[8] + 1
            regs[ins.av] = v
        else if op >= 20 and op <= 26:
            var take = false

            if op == 20:
                take = true
            else if op == 21:
                take = z
            else if op == 22:
                take = not z
            else if op == 23:
                take = l
            else if op == 24:
                take = l or z
            else if op == 25:
                take = (not l) and (not z)
            else:
                take = not l

            if take:
                nxt = ins.av
        else if op == 27:
            if regs[8] <= 0:
                trap = "stack overflow"
                break

            regs[8] = regs[8] - 1

            a := regs[8]

            if a < 0 or a >= 4096:
                trap = "memory access out of range: {a}"
                break

            mem[a] = pc + 1
            nxt = ins.av
        else if op == 28:
            if regs[8] >= 4096:
                trap = "stack underflow"
                break

            a := regs[8]

            if a < 0 or a >= 4096:
                trap = "memory access out of range: {a}"
                break

            v := mem[a]
            regs[8] = regs[8] + 1
            nxt = v
        else if op == 29:
            if inpos >= input.length():
                trap = "input exhausted"
                break

            regs[ins.av] = input[inpos]
            inpos += 1
        else if op == 30:
            outs.append("{sv}\n")
            last_nl = true
        else if op == 31:
            if sv < 0 or sv > 127:
                trap = "invalid character"
                break

            outs.append(chtab[sv].clone())
            last_nl = sv == 10
        else if op == 32:
            steps += 1
            halted = true
            break

        steps += 1
        pc = nxt

    var result = outs.join("")
    if outs.length() > 0 and not last_nl:
        result = result + "\n"

    if halted:
        result = result + "-- halted after {steps} steps\n"
    else:
        var where = "-"
        if pc >= 0 and pc < n:
            where = "{code[pc].line}"
        result = result + "-- trap: {trap} (pc={pc} line={where}) after {steps} steps\n"

    result = (
        result
        + "regs: r0={regs[0]} r1={regs[1]} r2={regs[2]} r3={regs[3]} r4={regs[4]} r5={regs[5]} r6={regs[6]} r7={regs[7]} sp={regs[8]} bp={regs[9]}\n"
    )

    var zb = 0
    var lb = 0
    if z:
        zb = 1
    if l:
        lb = 1
    result = result + "flags: Z={zb} L={lb}\n"
    return result

export fn main() Int:
    raw := read_all(stdin()).get()
    text := raw.decode_utf8().get("")
    var src_lines = List[String]()
    var inp = List[String]()
    var in_input = false

    for ln in text.split("\n"):
        l := ln.trim_end_chars("\r")

        if not in_input and l == "====":
            in_input = true
        else if in_input:
            inp.append(l)
        else:
            src_lines.append(l)

    var lines = List[Pl]()
    var k = 0

    for sl in src_lines:
        k += 1
        lines.append(parse_line(k, sl))

    equs := collect_equs(lines)
    var labels = Map[String, Int]()
    var stmts = List[Stmt]()
    p1 := pass1(lines, equs, var labels, var stmts)

    if p1.err != "":
        stdout().write("asm error line {p1.line}: {p1.err}\n").get()
        return 0

    var code = List[Ins]()
    var data = List[Int]()
    p2 := pass2(stmts, labels, equs, p1.ninstr, var code, var data)

    if p2.err != "":
        stdout().write("asm error line {p2.line}: {p2.err}\n").get()
        return 0

    var input = List[Int]()

    for tok in tokens(inp.join(" ")):
        iv := input_value(tok)
        if iv.err == "":
            input.append(iv.v)

    var chtab = List[String]()
    var cv = 0

    while cv < 128:
        chtab.append(from_scalars([cv]).get())
        cv += 1

    out := run(code, data, input, p1.budget, p1.entry, chtab)
    stdout().write(out).get()
    return 0
