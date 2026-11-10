// Backtracking regular-expression engine and command driver (see TASK.md).
//
// A pattern is parsed into a program for a small backtracking VM. Fragments use
// relative jumps, so fragments can be concatenated and wrapped freely.

import (
    stdin from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
    Bytes from "@std/bytes.ms",
)

let OP_CHR = 0
let OP_CLS = 1
let OP_SPLIT = 2
let OP_JMP = 3
let OP_OPEN = 4
let OP_CLOSE = 5
let OP_ASSERT = 6
let OP_BREF = 7
let OP_LOOK = 8
let OP_MATCH = 9
let OP_SETI = 10
let OP_SETPOS = 11
let OP_INC = 12
let OP_JLT = 13
let OP_JGE = 14
let OP_LOOPCHK = 15
let AS_BOL = 0
let AS_BOLM = 1
let AS_EOL = 2
let AS_EOLM = 3
let AS_WORDB = 4
let AS_NWORDB = 5
let INF = -1
let ASCII = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
let HEX = "0123456789abcdef"

type Instr:
    op: Int
    a: Int = 0
    b: Int = 0
    c: Int = 0
    d: Int = 0
    e: Int = 0

type Parser:
    src: List[Int]
    pos: Int = 0
    ci: Bool = false
    ml: Bool = false
    dotall: Bool = false
    ngroups: Int = 0
    nregs: Int = 0
    qmin: Int = 0
    qmax: Int = 0
    err: String = ""
    prog: List[Instr]
    sets: List[List[Bool]]
    group_regs: List[Int]
    group_names: List[String]
    names: Map[String, Int]
    refnames: List[String]

// ---------- byte helpers ----------

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_word(c: Int) Bool:
    return is_digit(c) or is_alpha(c) or c == 95

fn is_space(c: Int) Bool:
    return c == 32 or (c >= 9 and c <= 13)

fn is_alnum(c: Int) Bool:
    return is_digit(c) or is_alpha(c)

fn hexval(c: Int) Int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 65 and c <= 70:
        return c - 55
    if c >= 97 and c <= 102:
        return c - 87

    return -1

fn lower(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn upper(c: Int) Int:
    if c >= 97 and c <= 122:
        return c - 32

    return c

fn byte_at(subj: List[Int], i: Int) Int:
    if i < 0 or i >= subj.length():
        return -1

    return subj[i]

// ---------- character sets ----------

fn empty_set() List[Bool]:
    var s = List[Bool]()
    for i in 0..256:
        s.append(false)
    return s

fn shorthand(letter: Int) List[Bool]:
    var s = empty_set()
    let neg = letter >= 65 and letter <= 90
    let low = lower(letter)

    for c in 0..256:
        var m = is_space(c)

        if low == 100:
            m = is_digit(c)
        else if low == 119:
            m = is_word(c)

        if neg:
            m = not m
        s[c] = m

    return s

fn add_shorthand(var s: List[Bool], letter: Int) Unit:
    let sh = shorthand(letter)
    for c in 0..256:
        if sh[c]:
            s[c] = true

fn add_range(var s: List[Bool], lo: Int, hi: Int) Unit:
    for c in lo..hi + 1:
        s[c] = true

fn fold_case(var s: List[Bool]) Unit:
    for c in 65..91:
        if s[c] or s[c + 32]:
            s[c] = true
            s[c + 32] = true

fn add_set(var p: Parser, s: List[Bool]) Int:
    p.sets.append(s)
    return p.sets.length() - 1

// ---------- parser state helpers ----------

fn set_err(var p: Parser, msg: String) Unit:
    if p.err == "":
        p.err = msg

fn cur(p: Parser) Int:
    if p.pos >= p.src.length():
        return -1

    return p.src[p.pos]

fn ahead(p: Parser, k: Int) Int:
    let i = p.pos + k
    if i >= p.src.length():
        return -1

    return p.src[i]

fn alloc_reg(var p: Parser) Int:
    let r = p.nregs
    p.nregs += 1
    return r

fn name_string(p: Parser, s: Int, e: Int) String:
    var out = ""
    for i in s..e:
        out += ASCII.get(p.src[i] - 32)
    return out

// Index just past an identifier starting at `start`, or `start` if there is none.
fn ident_end(p: Parser, start: Int) Int:
    let n = p.src.length()
    if start >= n:
        return start

    let f = p.src[start]
    if not (is_alpha(f) or f == 95):
        return start

    var i = start + 1
    while i < n and is_word(p.src[i]):
        i += 1
    return i

// Parses the two hex digits after \x (p.pos at the first digit); -1 on error.
fn hex_escape(var p: Parser) Int:
    let h = hexval(ahead(p, 0))
    let l = hexval(ahead(p, 1))

    if h < 0 or l < 0:
        set_err(var p, "bad escape")
        return -1

    p.pos += 2
    return h * 16 + l

fn cat(var out: List[Instr], xs: List[Instr]) Unit:
    for x in xs:
        out.append(x.clone())

fn one(i: Instr) List[Instr]:
    var out = List[Instr]()
    out.append(i)
    return out

fn literal(p: Parser, c: Int) List[Instr]:
    if p.ci and is_alpha(c):
        return one(Instr(op: OP_CHR, a: lower(c), b: upper(c)))

    return one(Instr(op: OP_CHR, a: c, b: c))

// ---------- character classes ----------

// A byte value, or 1000 + letter for a shorthand class; -1 on error.
fn class_atom(var p: Parser) Int:
    let c = cur(p)
    p.pos += 1
    if c != 92:
        return c

    let e = cur(p)

    if e == -1:
        set_err(var p, "bad escape")
        return -1

    p.pos += 1
    if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
        return 1000 + e
    if e == 110:
        return 10
    if e == 116:
        return 9
    if e == 114:
        return 13
    if e == 120:
        return hex_escape(var p)
    if e < 128 and not is_alnum(e):
        return e

    set_err(var p, "bad escape")
    return -1

fn parse_class(var p: Parser) List[Instr]:
    var neg = false

    if cur(p) == 94:
        neg = true
        p.pos += 1

    var s = empty_set()
    var first = true

    while true:
        let c = cur(p)

        if c == -1:
            set_err(var p, "unterminated class")
            return List[Instr]()

        if c == 93 and not first:
            p.pos += 1
            break

        first = false

        let a1 = class_atom(var p)
        if p.err != "":
            return List[Instr]()

        if cur(p) == 45 and ahead(p, 1) != 93 and ahead(p, 1) != -1:
            p.pos += 1

            let a2 = class_atom(var p)
            if p.err != "":
                return List[Instr]()

            if a1 >= 1000 or a2 >= 1000 or a2 < a1:
                set_err(var p, "bad range")
                return List[Instr]()

            add_range(var s, a1, a2)
        else if a1 >= 1000:
            add_shorthand(var s, a1 - 1000)
        else:
            s[a1] = true

    if p.ci:
        fold_case(var s)
    if neg:
        for c in 0..256:
            s[c] = not s[c]

    let idx = add_set(var p, s)
    return one(Instr(op: OP_CLS, a: idx))

fn parse_dot(var p: Parser) List[Instr]:
    var s = empty_set()
    for c in 0..256:
        s[c] = p.dotall or c != 10

    let idx = add_set(var p, s)
    return one(Instr(op: OP_CLS, a: idx))

// ---------- escapes outside classes ----------

fn parse_escape(var p: Parser) List[Instr]:
    let e = cur(p)

    if e == -1:
        set_err(var p, "bad escape")
        return List[Instr]()

    p.pos += 1

    if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
        let idx = add_set(var p, shorthand(e))
        return one(Instr(op: OP_CLS, a: idx))

    if e == 98:
        return one(Instr(op: OP_ASSERT, a: AS_WORDB))
    if e == 66:
        return one(Instr(op: OP_ASSERT, a: AS_NWORDB))
    if e == 110:
        return literal(p, 10)
    if e == 116:
        return literal(p, 9)
    if e == 114:
        return literal(p, 13)

    if e == 120:
        let v = hex_escape(var p)
        if p.err != "":
            return List[Instr]()

        return literal(p, v)

    var ci_flag = 0
    if p.ci:
        ci_flag = 1
    if e >= 49 and e <= 57:
        return one(Instr(op: OP_BREF, a: e - 48, c: ci_flag))

    if e == 107:
        if cur(p) != 60:
            set_err(var p, "bad escape")
            return List[Instr]()

        p.pos += 1

        let stop = ident_end(p, p.pos)

        if stop == p.pos or stop >= p.src.length() or p.src[stop] != 62:
            set_err(var p, "bad escape")
            return List[Instr]()

        let nm = name_string(p, p.pos, stop)
        p.pos = stop + 1
        p.refnames.append(nm)

        // Negative `a` marks a named reference, resolved after parsing.
        return one(Instr(op: OP_BREF, a: -p.refnames.length(), c: ci_flag))

    if is_alnum(e):
        set_err(var p, "bad escape")
        return List[Instr]()

    if e < 128:
        return literal(p, e)

    set_err(var p, "bad escape")
    return List[Instr]()

// ---------- groups ----------

fn expect_close(var p: Parser) Bool:
    if cur(p) != 41:
        set_err(var p, "unmatched (")
        return false

    p.pos += 1
    return true

// Parses a capturing group body (p.pos just past its opening parenthesis).
fn capture(var p: Parser, name: String) List[Instr]:
    p.ngroups += 1

    let g = p.ngroups
    p.group_names.append(name.clone())
    if name != "":
        p.names.add(name, g)

    let r = alloc_reg(var p)
    p.group_regs.append(r)

    let body = parse_alt(var p)
    if p.err != "":
        return List[Instr]()
    if not expect_close(var p):
        return List[Instr]()

    var frag = List[Instr]()
    frag.append(Instr(op: OP_OPEN, a: r))
    cat(var frag, body)
    frag.append(Instr(op: OP_CLOSE, a: g, b: r))
    return frag

fn parse_group(var p: Parser) List[Instr]:
    p.pos += 1
    if cur(p) != 63:
        return capture(var p, "")

    let k = ahead(p, 1)

    if k == 58:
        p.pos += 2

        let body = parse_alt(var p)
        if p.err != "":
            return List[Instr]()
        if not expect_close(var p):
            return List[Instr]()

        return body

    if k == 61 or k == 33:
        p.pos += 2

        let body = parse_alt(var p)
        if p.err != "":
            return List[Instr]()
        if not expect_close(var p):
            return List[Instr]()

        var neg = 0
        if k == 33:
            neg = 1

        var frag = List[Instr]()
        frag.append(Instr(op: OP_LOOK, a: neg, b: body.length() + 2))
        cat(var frag, body)
        frag.append(Instr(op: OP_MATCH))
        return frag

    if k == 60:
        let k2 = ahead(p, 2)

        if k2 == 61 or k2 == 33:
            set_err(var p, "bad group")
            return List[Instr]()

        p.pos += 2

        let stop = ident_end(p, p.pos)

        if stop == p.pos or stop >= p.src.length() or p.src[stop] != 62:
            set_err(var p, "bad group")
            return List[Instr]()

        let nm = name_string(p, p.pos, stop)

        if p.names.contains(nm):
            set_err(var p, "duplicate group name")
            return List[Instr]()

        p.pos = stop + 1
        return capture(var p, nm)

    set_err(var p, "bad group")
    return List[Instr]()

// ---------- quantifiers ----------

// Index just past a valid {n}, {n,} or {n,m} starting at p.pos, or -1.
fn scan_brace(p: Parser) Int:
    let n = p.src.length()
    var i = p.pos + 1
    let s1 = i
    while i < n and is_digit(p.src[i]):
        i += 1
    if i == s1:
        return -1
    if i < n and p.src[i] == 125:
        return i + 1

    if i < n and p.src[i] == 44:
        i += 1
        while i < n and is_digit(p.src[i]):
            i += 1
        if i < n and p.src[i] == 125:
            return i + 1

    return -1

// Reads a validated brace quantifier into p.qmin / p.qmax and moves p.pos to `stop`.
fn read_brace(var p: Parser, stop: Int) Unit:
    var i = p.pos + 1
    var v = 0

    while is_digit(p.src[i]):
        if v < 100000:
            v = v * 10 + p.src[i] - 48
        i += 1

    p.qmin = v

    if p.src[i] == 44:
        i += 1

        if p.src[i] == 125:
            p.qmax = INF
        else:
            v = 0

            while is_digit(p.src[i]):
                if v < 100000:
                    v = v * 10 + p.src[i] - 48
                i += 1

            p.qmax = v
    else:
        p.qmax = p.qmin

    p.pos = stop

fn is_quant_start(p: Parser) Bool:
    let c = cur(p)
    if c == 42 or c == 43 or c == 63:
        return true
    if c == 123 and scan_brace(p) != -1:
        return true

    return false

// Emits a loop with a counter register and an empty-iteration check.
fn loop_wrap(var p: Parser, body: List[Instr], mn: Int, mx: Int, greedy: Bool) List[
    Instr
]:
    let cnt = alloc_reg(var p)
    let mark = alloc_reg(var p)
    let nb = body.length()
    var hl = 1
    if mn > 0:
        hl += 1
    if mx != INF:
        hl += 1

    let exit_idx = 4 + hl + nb
    var out = List[Instr]()
    out.append(Instr(op: OP_SETI, a: cnt, b: 0))

    var idx = 1

    if mn > 0:
        out.append(Instr(op: OP_JLT, a: cnt, b: mn, c: hl))
        idx += 1

    if mx != INF:
        out.append(Instr(op: OP_JGE, a: cnt, b: mx, c: exit_idx - idx))
        idx += 1

    if greedy:
        out.append(Instr(op: OP_SPLIT, a: 1, b: exit_idx - idx))
    else:
        out.append(Instr(op: OP_SPLIT, a: exit_idx - idx, b: 1))

    out.append(Instr(op: OP_SETPOS, a: mark))
    cat(var out, body)
    out.append(Instr(op: OP_INC, a: cnt))
    out.append(
        Instr(
            op: OP_LOOPCHK, a: mark, b: cnt, c: mn, d: 1 - (3 + hl + nb), e: 1
        )
    )
    return out

fn parse_quant(var p: Parser, atom: List[Instr], nr: Bool) List[Instr]:
    let c = cur(p)
    var mn = 0
    var mx = INF

    if c == 42:
        p.pos += 1
    else if c == 43:
        mn = 1
        p.pos += 1
    else if c == 63:
        mx = 1
        p.pos += 1
    else if c == 123 and scan_brace(p) != -1:
        let stop = scan_brace(p)
        read_brace(var p, stop)
        mn = p.qmin
        mx = p.qmax
    else:
        return atom.clone()

    var greedy = true

    if cur(p) == 63:
        greedy = false
        p.pos += 1

    if nr:
        set_err(var p, "nothing to repeat")
        return List[Instr]()

    if mn > 1000 or (mx != INF and (mx > 1000 or mn > mx)):
        set_err(var p, "bad repeat")
        return List[Instr]()

    if is_quant_start(p):
        set_err(var p, "nothing to repeat")
        return List[Instr]()

    return loop_wrap(var p, atom, mn, mx, greedy)

// ---------- atoms, sequences, alternation ----------

fn is_norep_start(p: Parser) Bool:
    let c = cur(p)
    if c == 94 or c == 36:
        return true

    if c == 92:
        let e = ahead(p, 1)
        return e == 98 or e == 66

    if c == 40 and ahead(p, 1) == 63:
        let k = ahead(p, 2)
        return k == 61 or k == 33

    return false

fn parse_atom(var p: Parser) List[Instr]:
    let c = cur(p)
    if c == 40:
        return parse_group(var p)

    if c == 91:
        p.pos += 1
        return parse_class(var p)

    if c == 46:
        p.pos += 1
        return parse_dot(var p)

    if c == 94 or c == 36:
        p.pos += 1

        var k = AS_BOL
        if c == 36:
            k = AS_EOL
        if p.ml:
            k += 1
        return one(Instr(op: OP_ASSERT, a: k))

    if c == 92:
        p.pos += 1
        return parse_escape(var p)

    if c == 42 or c == 43 or c == 63:
        set_err(var p, "nothing to repeat")
        return List[Instr]()

    p.pos += 1
    return literal(p, c)

fn parse_seq(var p: Parser) List[Instr]:
    var out = List[Instr]()

    while true:
        let c = cur(p)
        if c == -1 or c == 124 or c == 41:
            break

        let nr = is_norep_start(p)
        let atom = parse_atom(var p)
        if p.err != "":
            return List[Instr]()

        let q = parse_quant(var p, atom, nr)
        if p.err != "":
            return List[Instr]()

        cat(var out, q)

    return out

fn alt_join(alts: List[List[Instr]], i: Int) List[Instr]:
    if i == alts.length() - 1:
        return alts[i].clone()

    let a = alts[i]
    let rest = alt_join(alts, i + 1)
    var out = List[Instr]()
    out.append(Instr(op: OP_SPLIT, a: 1, b: a.length() + 2))
    cat(var out, a)
    out.append(Instr(op: OP_JMP, a: rest.length() + 1))
    cat(var out, rest)
    return out

fn parse_alt(var p: Parser) List[Instr]:
    var alts = List[List[Instr]]()
    alts.append(parse_seq(var p))
    if p.err != "":
        return List[Instr]()

    while cur(p) == 124:
        p.pos += 1
        alts.append(parse_seq(var p))
        if p.err != "":
            return List[Instr]()

    return alt_join(alts, 0)

// ---------- whole pattern ----------

fn compile_pattern(src: List[Int]) Parser:
    var p = Parser(
        src: src.clone(), prog: List[Instr](), sets: List[List[Bool]](),
        group_regs: [0], group_names: [""], names: Map[String, Int](),
        refnames: List[String]()
    )
    let n = src.length()

    // Leading flags: (?ims...)
    if (
        n >= 3
        and src[0] == 40
        and src[1] == 63
        and (src[2] == 105 or src[2] == 109 or src[2] == 115)
    ):
        var i = 2

        while i < n and (src[i] == 105 or src[i] == 109 or src[i] == 115):
            if src[i] == 105:
                p.ci = true
            if src[i] == 109:
                p.ml = true
            if src[i] == 115:
                p.dotall = true
            i += 1

        if i < n and src[i] == 41:
            p.pos = i + 1
        else:
            set_err(var p, "bad group")
            return p

    var body = parse_alt(var p)
    if p.err == "" and p.pos < n:
        set_err(var p, "unmatched )")
    if p.err != "":
        return p

    body.append(Instr(op: OP_MATCH))

    // Resolve backreferences now that every group is known.
    var i = 0

    while i < body.length() and p.err == "":
        if body[i].op == OP_BREF:
            var g = body[i].a

            if g < 0:
                let nm = p.refnames[-g - 1]
                g = p.names.get_or(nm, -1)
                if g < 0:
                    set_err(var p, "bad backreference")
            else if g > p.ngroups:
                set_err(var p, "bad backreference")

            if p.err == "":
                body[i] = Instr(op: OP_BREF, a: g, b: p.group_regs[g], c: body[i].c)

        i += 1

    p.prog = body
    return p

// ---------- VM ----------

fn push3(var stk: List[Int], kind: Int, a: Int, b: Int) Unit:
    stk.append(kind)
    stk.append(a)
    stk.append(b)

fn restore(var xs: List[Int], src: List[Int]) Unit:
    for i in 0..xs.length():
        xs[i] = src[i]

// Runs the program from start_pc at start_pos. Returns the end position on success or -1.
// caps and regs are restored to their entry values on failure.
fn run(
    prog: List[Instr],
    sets: List[List[Bool]],
    subj: List[Int],
    var caps: List[Int],
    var regs: List[Int],
    start_pc: Int,
    start_pos: Int,
    full: Bool
) Int:
    let n = subj.length()
    var stk = List[Int]()
    var pc = start_pc
    var pos = start_pos

    while true:
        let ins = prog[pc]
        let op = ins.op
        var fail = false

        if op == OP_CHR:
            var ok = false
            if pos < n:
                ok = subj[pos] == ins.a or subj[pos] == ins.b

            if ok:
                pos += 1
                pc += 1
            else:
                fail = true
        else if op == OP_CLS:
            var ok = false
            if pos < n:
                ok = sets[ins.a][subj[pos]]

            if ok:
                pos += 1
                pc += 1
            else:
                fail = true
        else if op == OP_SPLIT:
            push3(var stk, 0, pc + ins.b, pos)
            pc += ins.a
        else if op == OP_JMP:
            pc += ins.a
        else if op == OP_OPEN:
            push3(var stk, 2, ins.a, regs[ins.a])
            regs[ins.a] = pos
            pc += 1
        else if op == OP_CLOSE:
            let g = ins.a
            let r = ins.b
            push3(var stk, 1, 2 * g, caps[2 * g])
            push3(var stk, 1, 2 * g + 1, caps[2 * g + 1])
            push3(var stk, 2, r, regs[r])
            caps[2 * g] = regs[r]
            caps[2 * g + 1] = pos
            regs[r] = -1
            pc += 1
        else if op == OP_ASSERT:
            let k = ins.a
            var ok = false

            if k == AS_BOL:
                ok = pos == 0
            else if k == AS_BOLM:
                ok = pos == 0 or byte_at(subj, pos - 1) == 10
            else if k == AS_EOL:
                ok = pos == n
            else if k == AS_EOLM:
                ok = pos == n or byte_at(subj, pos) == 10
            else:
                let wb = is_word(byte_at(subj, pos - 1)) != is_word(byte_at(subj, pos))

                if k == AS_WORDB:
                    ok = wb
                else:
                    ok = not wb

            if ok:
                pc += 1
            else:
                fail = true
        else if op == OP_BREF:
            let g = ins.a
            var ok = regs[ins.b] == -1
            let s = caps[2 * g]
            let e = caps[2 * g + 1]
            if s < 0 or e < 0:
                ok = false

            if ok:
                let len = e - s

                if pos + len > n:
                    ok = false
                else:
                    var i = 0

                    while i < len and ok:
                        var x = subj[s + i]
                        var y = subj[pos + i]

                        if ins.c == 1:
                            x = lower(x)
                            y = lower(y)

                        if x != y:
                            ok = false
                        i += 1

                if ok:
                    pos += len

            if ok:
                pc += 1
            else:
                fail = true
        else if op == OP_LOOK:
            let snapC = caps.clone()
            let snapR = regs.clone()
            let r = run(prog, sets, subj, var caps, var regs, pc + 1, pos, false)

            if ins.a == 1:
                if r >= 0:
                    restore(var caps, snapC)
                    restore(var regs, snapR)
                    fail = true
                else:
                    pc += ins.b
            else:
                if r >= 0:
                    for i in 0..caps.length():
                        if caps[i] != snapC[i]:
                            push3(var stk, 1, i, snapC[i])
                    for i in 0..regs.length():
                        if regs[i] != snapR[i]:
                            push3(var stk, 2, i, snapR[i])
                    pc += ins.b
                else:
                    fail = true
        else if op == OP_MATCH:
            if full and pos != n:
                fail = true
            else:
                return pos
        else if op == OP_SETI:
            push3(var stk, 2, ins.a, regs[ins.a])
            regs[ins.a] = ins.b
            pc += 1
        else if op == OP_SETPOS:
            push3(var stk, 2, ins.a, regs[ins.a])
            regs[ins.a] = pos
            pc += 1
        else if op == OP_INC:
            push3(var stk, 2, ins.a, regs[ins.a])
            regs[ins.a] = regs[ins.a] + 1
            pc += 1
        else if op == OP_JLT:
            if regs[ins.a] < ins.b:
                pc += ins.c
            else:
                pc += 1
        else if op == OP_JGE:
            if regs[ins.a] >= ins.b:
                pc += ins.c
            else:
                pc += 1
        else if op == OP_LOOPCHK:
            if pos == regs[ins.a] and regs[ins.b] >= ins.c:
                pc += ins.e
            else:
                pc += ins.d

        if fail:
            var resumed = false

            while not resumed:
                if stk.length() == 0:
                    return -1

                let vb = stk.pop().get(0)
                let va = stk.pop().get(0)
                let vk = stk.pop().get(0)

                if vk == 0:
                    pc = va
                    pos = vb
                    resumed = true
                else if vk == 1:
                    caps[va] = vb
                else:
                    regs[va] = vb

// Leftmost match starting at or after `from` (only at `from` when full).
// Returns the capture list (group 0 set) or an empty list when there is no match.
fn search(p: Parser, subj: List[Int], from: Int, full: Bool) List[Int]:
    var caps = List[Int]()
    for i in 0..(2 * p.ngroups + 2):
        caps.append(-1)

    var regs = List[Int]()
    for i in 0..p.nregs:
        regs.append(-1)

    let n = subj.length()
    var s = from

    while s <= n:
        let e = run(p.prog, p.sets, subj, var caps, var regs, 0, s, full)

        if e >= 0:
            caps[0] = s
            caps[1] = e
            return caps

        if full:
            break

        s += 1

    return List[Int]()

// All find-all matches as capture lists.
fn all_matches(p: Parser, subj: List[Int]) List[List[Int]]:
    var out = List[List[Int]]()
    let n = subj.length()
    var from = 0

    while from <= n:
        let c = search(p, subj, from, false)
        if c.length() == 0:
            break

        let e = c[1]

        if e > c[0]:
            from = e
        else:
            from = e + 1

        out.append(c)

    return out

// ---------- output ----------

fn esc_byte(c: Int) String:
    if c == 92:
        return "\\\\"
    if c == 34:
        return "\\\""
    if c == 10:
        return "\\n"
    if c == 9:
        return "\\t"
    if c == 13:
        return "\\r"
    if c < 32 or c > 126:
        return "\\x" + HEX.get(c / 16) + HEX.get(c % 16)

    return ASCII.get(c - 32)

fn quote_range(subj: List[Int], s: Int, e: Int) String:
    var out = "\""
    for i in s..e:
        out += esc_byte(subj[i])
    return out + "\""

fn group_lines(p: Parser, subj: List[Int], c: List[Int]) List[String]:
    var out = List[String]()

    for g in 0..(p.ngroups + 1):
        var label = "{g}"
        if g > 0 and p.group_names[g] != "":
            label = "{g} (" + p.group_names[g] + ")"

        let s = c[2 * g]
        let e = c[2 * g + 1]

        if s >= 0 and e >= 0:
            out.append(label + ": {s}..{e} " + quote_range(subj, s, e))
        else:
            out.append(label + ": unset")

    return out

// ---------- replacement ----------

fn append_group(var out: List[Int], subj: List[Int], c: List[Int], g: Int) Unit:
    let s = c[2 * g]
    let e = c[2 * g + 1]
    if s >= 0 and e >= 0:
        for k in s..e:
            out.append(subj[k])

// Name bytes as a String; anything that is not an identifier byte gives "" (never a group name).
fn name_of(repl: List[Int], s: Int, e: Int) String:
    for i in s..e:
        if not is_word(repl[i]):
            return ""

    var out = ""
    for i in s..e:
        out += ASCII.get(repl[i] - 32)
    return out

// Expands one replacement for match `c`; none when the replacement is malformed.
fn expand(repl: List[Int], p: Parser, subj: List[Int], c: List[Int]) List[Int]?:
    var out = List[Int]()
    let m = repl.length()
    var i = 0

    while i < m:
        let ch = repl[i]

        if ch != 36:
            out.append(ch)
            i += 1
        else if i + 1 >= m:
            out.append(36)
            i += 1
        else:
            let d = repl[i + 1]

            if is_digit(d):
                let g = d - 48
                if g > p.ngroups:
                    return none

                append_group(var out, subj, c, g)
                i += 2
            else if d == 36:
                out.append(36)
                i += 2
            else if d == 123:
                var j = i + 2
                while j < m and repl[j] != 125:
                    j += 1
                if j >= m:
                    return none

                let nm = name_of(repl, i + 2, j)
                let g = p.names.get_or(nm, -1)
                if g < 0:
                    return none

                append_group(var out, subj, c, g)
                i = j + 1
            else:
                out.append(36)
                i += 1

    return out

// ---------- input parsing ----------

fn to_ints(b: Bytes) List[Int]:
    var out = List[Int]()
    for i in 0..b.length():
        out.append(b.get(i).to_int())
    return out

fn split_bytes(all: List[Int], sep: Int) List[List[Int]]:
    var parts = List[List[Int]]()
    var part = List[Int]()

    for c in all:
        if c == sep:
            parts.append(part)
            part = List[Int]()
        else:
            part.append(c)

    parts.append(part)
    return parts

fn eq_str(f: List[Int], s: String) Bool:
    let b = s.as_bytes()
    if b.length() != f.length():
        return false

    for i in 0..f.length():
        if b.get(i).to_int() != f[i]:
            return false
    return true

// Subject / replacement escapes; none on a bad escape.
fn unescape(f: List[Int]) List[Int]?:
    var out = List[Int]()
    let n = f.length()
    var i = 0

    while i < n:
        let c = f[i]

        if c != 92:
            out.append(c)
            i += 1
        else if i + 1 >= n:
            return none
        else:
            let d = f[i + 1]

            if d == 110:
                out.append(10)
                i += 2
            else if d == 116:
                out.append(9)
                i += 2
            else if d == 92:
                out.append(92)
                i += 2
            else if d == 120:
                if i + 3 >= n:
                    return none

                let h = hexval(f[i + 2])
                let l = hexval(f[i + 3])
                if h < 0 or l < 0:
                    return none

                out.append(h * 16 + l)
                i += 4
            else:
                return none

    return out

fn handle(line: List[Int]) List[String]:
    var out = List[String]()
    let fields = split_bytes(line, 9)
    let name = fields[0]
    var is_replace = eq_str(name, "replace")
    var known = (
        is_replace
        or eq_str(name, "test")
        or eq_str(name, "match")
        or eq_str(name, "full")
        or eq_str(name, "find-all")
        or eq_str(name, "split")
    )
    var want = 3
    if is_replace:
        want = 4

    if not known or fields.length() != want:
        out.append("error: bad command")
        return out

    var subj = List[Int]()

    if let s = unescape(fields[2]):
        subj = s
    else:
        out.append("error: bad command")
        return out

    var repl = List[Int]()

    if is_replace:
        if let r = unescape(fields[3]):
            repl = r
        else:
            out.append("error: bad command")
            return out

    let p = compile_pattern(fields[1].clone())

    if p.err != "":
        out.append("error: " + p.err)
        return out

    if eq_str(name, "test"):
        let c = search(p, subj, 0, false)

        if c.length() > 0:
            out.append("true")
        else:
            out.append("false")
    else if eq_str(name, "match") or eq_str(name, "full"):
        let c = search(p, subj, 0, eq_str(name, "full"))

        if c.length() == 0:
            out.append("no match")
        else:
            for l in group_lines(p, subj, c):
                out.append(l)
    else if eq_str(name, "find-all"):
        let ms = all_matches(p, subj)
        for c in ms:
            out.append("{c[0]}..{c[1]} " + quote_range(subj, c[0], c[1]))
        out.append("({ms.length()} matches)")
    else if eq_str(name, "split"):
        let ms = all_matches(p, subj)
        var pieces = List[String]()
        var prev = 0

        for c in ms:
            if c[1] > c[0]:
                pieces.append(quote_range(subj, prev, c[0]))
                prev = c[1]

        pieces.append(quote_range(subj, prev, subj.length()))
        for piece in pieces:
            out.append(piece.clone())
        out.append("({pieces.length()} pieces)")
    else:
        let ms = all_matches(p, subj)
        var res = List[Int]()
        var prev = 0

        for c in ms:
            if let ex = expand(repl, p, subj, c):
                for k in prev..c[0]:
                    res.append(subj[k])
                cat_ints(var res, ex)
            else:
                out.append("error: bad replacement")
                return out

            prev = c[1]

        for k in prev..subj.length():
            res.append(subj[k])
        out.append(quote_range(res, 0, res.length()))

    return out

fn cat_ints(var out: List[Int], xs: List[Int]) Unit:
    for x in xs:
        out.append(x)

export fn main() Int:
    let data = read_all(stdin()).get()
    let all = to_ints(data)

    for line in split_bytes(all, 10):
        if line.length() == 0:
            continue

        for s in handle(line):
            print(s)

    return 0
