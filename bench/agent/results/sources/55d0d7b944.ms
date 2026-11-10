import (
    stdin from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
)

// ---------------------------------------------------------------------------
// Backtracking regex engine: parser -> node arena -> bytecode -> backtracking VM.
// Instructions are stride-6 records: op, a, b, c, d, e.
// ---------------------------------------------------------------------------

let OP_SET = 0  // a = set id: consume one byte that is in the set
let OP_SPLIT = 1  // try a first, backtrack to b
let OP_JMP = 2  // a = target
let OP_OPEN = 3  // slot a = pos (group start, undoable)
let OP_CLOSE = 4  // caps[a], caps[a+1] = slot b, pos
let OP_ASSERT = 5  // a = assertion kind
let OP_BREF = 6  // a = group, b = case-insensitive
let OP_SETPOS = 7  // slot a = pos
let OP_SETVAL = 8  // slot a = b
let OP_LOOPG = 9  // greedy loop head: a = count slot, b = min, c = max (-1 inf), d = exit
let OP_LOOPL = 10  // lazy loop head: same fields
let OP_LOOPTAIL = 11  // a = count slot, b = min, c = pos slot, d = exit, e = head
let OP_LOOK = 12  // a = negative flag, b = continuation pc; body follows
let OP_SUBEND = 13  // end of lookahead body
let OP_MATCH = 14  // end of whole pattern
let N_SET = 0
let N_ASSERT = 1
let N_GROUP = 2
let N_SEQ = 3
let N_ALT = 4
let N_REPEAT = 5
let N_LOOK = 6
let N_BREF = 7
let PRINTABLE = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
let HEXD = "0123456789abcdef"

type Pat:
    pat: List[Int]
    pos: Int
    err: String
    icase: Bool
    multi: Bool
    dotall: Bool
    ngroups: Int
    gnames: List[List[Int]]
    nk: List[Int]
    na: List[Int]
    nb: List[Int]
    nc: List[Int]
    nd: List[Int]
    kids: List[List[Int]]
    bits: List[Bool]
    brefs: List[Int]
    brefnames: List[List[Int]]
    qmin: Int
    qmax: Int
    qgreedy: Bool
    code: List[Int]
    nslots: Int
    tbase: Int

fn new_pat(src: List[Int]) Pat:
    var names = List[List[Int]]()
    names.append(List[Int]())
    return Pat(
        pat: src, pos: 0, err: "", icase: false, multi: false, dotall: false,
        ngroups: 0, gnames: names, nk: List[Int](), na: List[Int](), nb: List[Int](),
        nc: List[Int](), nd: List[Int](), kids: List[List[Int]](), bits: List[Bool](),
        brefs: List[Int](), brefnames: List[List[Int]](), qmin: 0, qmax: 0,
        qgreedy: true, code: List[Int](), nslots: 0, tbase: 0
    )

// ---- character helpers ----------------------------------------------------

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_alnum(c: Int) Bool:
    return is_alpha(c) or is_digit(c)

fn is_word(c: Int) Bool:
    return is_alnum(c) or c == 95

fn lower(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn hexval(c: Int) Int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

fn peek(p: Pat) Int:
    if p.pos < p.pat.length():
        return p.pat[p.pos]

    return -1

fn peek_at(p: Pat, k: Int) Int:
    let i = p.pos + k
    if i < p.pat.length():
        return p.pat[i]

    return -1

fn perr(var p: Pat, msg: String) Int:
    if p.err.length() == 0:
        p.err = msg
    return -1

// ---- nodes and sets -------------------------------------------------------

fn add_node(var p: Pat, kind: Int, a: Int, b: Int, c: Int, d: Int) Int:
    p.nk.append(kind)
    p.na.append(a)
    p.nb.append(b)
    p.nc.append(c)
    p.nd.append(d)
    return p.nk.length() - 1

fn seq_node(var p: Pat, items: List[Int]) Int:
    p.kids.append(items)

    let idx = p.kids.length() - 1
    return add_node(var p, N_SEQ, idx, 0, 0, 0)

fn new_set(var p: Pat) Int:
    let id = p.bits.length() / 256
    for i in 0..256:
        p.bits.append(false)
    return id

fn set_put(var p: Pat, id: Int, c: Int) Unit:
    p.bits[id * 256 + c] = true

fn fold_case(var p: Pat, id: Int) Unit:
    for c in 65..91:
        let up = id * 256 + c
        let lo = up + 32

        if p.bits[up] or p.bits[lo]:
            p.bits[up] = true
            p.bits[lo] = true

fn shorthand_has(k: Int, c: Int) Bool:
    if k == 0:
        return is_digit(c)
    if k == 1:
        return is_word(c)

    return c == 32 or (c >= 9 and c <= 13)

// code: 1000 + j, j: 0 d, 1 D, 2 w, 3 W, 4 s, 5 S
fn add_short(var p: Pat, id: Int, code: Int) Unit:
    let j = code - 1000
    let k = j / 2
    let neg = j % 2 == 1

    for c in 0..256:
        let h = shorthand_has(k, c)
        if (h and not neg) or (neg and not h):
            p.bits[id * 256 + c] = true

fn lit_node(var p: Pat, c: Int) Int:
    let id = new_set(var p)
    set_put(var p, id, c)
    if p.icase:
        fold_case(var p, id)
    return add_node(var p, N_SET, id, 0, 0, 0)

fn bref_node(var p: Pat, g: Int, name: List[Int]) Int:
    let id = add_node(var p, N_BREF, g, 0, 0, 0)
    p.brefs.append(id)
    p.brefnames.append(name)
    return id

// ---- escapes --------------------------------------------------------------

// p.pos is just after the backslash. Returns a byte, a shorthand code (>= 1000), or -1 (error set).
fn escape_char(var p: Pat) Int:
    let c = peek(p)
    if c < 0:
        return perr(var p, "bad escape")

    p.pos += 1
    if c == 100:
        return 1000
    if c == 68:
        return 1001
    if c == 119:
        return 1002
    if c == 87:
        return 1003
    if c == 115:
        return 1004
    if c == 83:
        return 1005
    if c == 110:
        return 10
    if c == 116:
        return 9
    if c == 114:
        return 13

    if c == 120:
        let h1 = hexval(peek(p))
        let h2 = hexval(peek_at(p, 1))
        if h1 < 0 or h2 < 0:
            return perr(var p, "bad escape")

        p.pos += 2
        return h1 * 16 + h2

    if is_alnum(c) or c >= 128:
        return perr(var p, "bad escape")

    return c

// Reads `name>` at p.pos. Returns the name, or an empty list when malformed.
fn parse_name(var p: Pat) List[Int]:
    var name = List[Int]()
    let c0 = peek(p)
    if not (is_alpha(c0) or c0 == 95):
        return name

    while is_word(peek(p)):
        name.append(peek(p))
        p.pos += 1

    if peek(p) != 62:
        return List[Int]()

    p.pos += 1
    return name

fn parse_atom_escape(var p: Pat) Int:
    p.pos += 1

    let c = peek(p)

    if c == 98:
        p.pos += 1
        return add_node(var p, N_ASSERT, 4, 0, 0, 0)

    if c == 66:
        p.pos += 1
        return add_node(var p, N_ASSERT, 5, 0, 0, 0)

    if c >= 49 and c <= 57:
        p.pos += 1
        return bref_node(var p, c - 48, List[Int]())

    if c == 107:
        p.pos += 1
        if peek(p) != 60:
            return perr(var p, "bad escape")

        p.pos += 1

        let name = parse_name(var p)
        if name.length() == 0:
            return perr(var p, "bad escape")

        return bref_node(var p, -1, name)

    let e = escape_char(var p)
    if p.err.length() > 0:
        return -1

    if e >= 1000:
        let id = new_set(var p)
        add_short(var p, id, e)
        return add_node(var p, N_SET, id, 0, 0, 0)

    return lit_node(var p, e)

// ---- character classes ----------------------------------------------------

fn parse_class(var p: Pat) Int:
    p.pos += 1

    var neg = false

    if peek(p) == 94:
        neg = true
        p.pos += 1

    let id = new_set(var p)
    var first = true
    var after_range = false

    while true:
        let c = peek(p)
        if c < 0:
            return perr(var p, "unterminated class")

        if c == 93 and not first:
            p.pos += 1
            break

        first = false

        var lo = -1

        if c == 92:
            p.pos += 1

            let e = escape_char(var p)
            if p.err.length() > 0:
                return -1

            if e >= 1000:
                add_short(var p, id, e)
                if peek(p) == 45 and peek_at(p, 1) >= 0 and peek_at(p, 1) != 93:
                    return perr(var p, "bad range")

                after_range = false
                continue

            lo = e
        else:
            p.pos += 1
            lo = c

        let can_range = not (after_range and c == 45)

        if can_range and peek(p) == 45 and peek_at(p, 1) >= 0 and peek_at(p, 1) != 93:
            p.pos += 1

            var hi = -1

            if peek(p) == 92:
                p.pos += 1
                hi = escape_char(var p)
                if p.err.length() > 0:
                    return -1
                if hi >= 1000:
                    return perr(var p, "bad range")
            else:
                hi = peek(p)
                p.pos += 1

            if hi < lo:
                return perr(var p, "bad range")

            for x in lo..hi + 1:
                set_put(var p, id, x)
            after_range = true
        else:
            set_put(var p, id, lo)
            after_range = false

    if p.icase:
        fold_case(var p, id)

    if neg:
        for x in 0..256:
            let idx = id * 256 + x
            p.bits[idx] = not p.bits[idx]

    return add_node(var p, N_SET, id, 0, 0, 0)

// ---- groups and atoms -----------------------------------------------------

fn close_group(var p: Pat) Bool:
    if peek(p) != 41:
        perr(var p, "unmatched (")
        return false

    p.pos += 1
    return true

fn parse_group(var p: Pat) Int:
    p.pos += 1

    if peek(p) == 63:
        let c2 = peek_at(p, 1)

        if c2 == 58:
            p.pos += 2

            let body = parse_alt(var p)
            if p.err.length() > 0:
                return -1
            if not close_group(var p):
                return -1

            var one = List[Int]()
            one.append(body)
            return seq_node(var p, one)

        if c2 == 61 or c2 == 33:
            p.pos += 2

            let lbody = parse_alt(var p)
            if p.err.length() > 0:
                return -1
            if not close_group(var p):
                return -1

            var neg = 0
            if c2 == 33:
                neg = 1
            return add_node(var p, N_LOOK, lbody, neg, 0, 0)

        if c2 == 60:
            let c3 = peek_at(p, 2)
            if c3 == 61 or c3 == 33:
                return perr(var p, "bad group")

            p.pos += 2

            let name = parse_name(var p)
            if name.length() == 0:
                return perr(var p, "bad group")

            for g in 1..p.gnames.length():
                if same_name(p.gnames[g], name, 0, name.length()):
                    return perr(var p, "duplicate group name")
            p.ngroups += 1

            let gi = p.ngroups
            p.gnames.append(name)

            let nbody = parse_alt(var p)
            if p.err.length() > 0:
                return -1
            if not close_group(var p):
                return -1

            return add_node(var p, N_GROUP, gi, nbody, 0, 0)

        return perr(var p, "bad group")

    p.ngroups += 1

    let g = p.ngroups
    p.gnames.append(List[Int]())

    let body = parse_alt(var p)
    if p.err.length() > 0:
        return -1
    if not close_group(var p):
        return -1

    return add_node(var p, N_GROUP, g, body, 0, 0)

fn dot_node(var p: Pat) Int:
    let id = new_set(var p)
    for c in 0..256:
        if p.dotall or c != 10:
            p.bits[id * 256 + c] = true
    return add_node(var p, N_SET, id, 0, 0, 0)

fn parse_atom(var p: Pat) Int:
    let c = peek(p)
    if c == 40:
        return parse_group(var p)
    if c == 91:
        return parse_class(var p)

    if c == 46:
        p.pos += 1
        return dot_node(var p)

    if c == 94:
        p.pos += 1

        var kind = 0
        if p.multi:
            kind = 1
        return add_node(var p, N_ASSERT, kind, 0, 0, 0)

    if c == 36:
        p.pos += 1

        var kind = 2
        if p.multi:
            kind = 3
        return add_node(var p, N_ASSERT, kind, 0, 0, 0)

    if c == 92:
        return parse_atom_escape(var p)
    if c == 42 or c == 43 or c == 63:
        return perr(var p, "nothing to repeat")

    p.pos += 1
    return lit_node(var p, c)

// ---- quantifiers ----------------------------------------------------------

// If `{` starts a valid quantifier shape, returns the index after `}`; otherwise -1.
fn brace_end(p: Pat) Int:
    let n = p.pat.length()
    var i = p.pos + 1
    var nd = 0

    while i < n and is_digit(p.pat[i]):
        i += 1
        nd += 1

    if nd == 0:
        return -1
    if i < n and p.pat[i] == 125:
        return i + 1

    if i < n and p.pat[i] == 44:
        i += 1
        while i < n and is_digit(p.pat[i]):
            i += 1
        if i < n and p.pat[i] == 125:
            return i + 1

    return -1

fn quant_here(p: Pat) Bool:
    let c = peek(p)
    if c == 42 or c == 43 or c == 63:
        return true
    if c == 123:
        return brace_end(p) >= 0

    return false

fn parse_number(var p: Pat) Int:
    var v = 0

    while is_digit(peek(p)):
        if v <= 100000:
            v = v * 10 + peek(p) - 48
        p.pos += 1

    return v

// Reads one quantifier (and optional lazy `?`) into p.qmin, p.qmax, p.qgreedy.
fn parse_quant(var p: Pat) Bool:
    let c = peek(p)

    if c == 42:
        p.qmin = 0
        p.qmax = -1
        p.pos += 1
    else if c == 43:
        p.qmin = 1
        p.qmax = -1
        p.pos += 1
    else if c == 63:
        p.qmin = 0
        p.qmax = 1
        p.pos += 1
    else:
        p.pos += 1

        let lo = parse_number(var p)
        var hi = lo

        if peek(p) == 44:
            p.pos += 1

            if is_digit(peek(p)):
                hi = parse_number(var p)
            else:
                hi = -1

        p.pos += 1
        p.qmin = lo
        p.qmax = hi

    p.qgreedy = true

    if peek(p) == 63:
        p.qgreedy = false
        p.pos += 1

    if (p.qmax >= 0 and p.qmin > p.qmax) or p.qmin > 1000 or p.qmax > 1000:
        perr(var p, "bad repeat")
        return false

    return true

fn repeatable(p: Pat, node: Int) Bool:
    let k = p.nk[node]
    return not (k == N_ASSERT or k == N_LOOK)

fn parse_seq(var p: Pat) Int:
    var items = List[Int]()

    while true:
        let c = peek(p)
        if c < 0 or c == 124 or c == 41:
            break

        var node = parse_atom(var p)
        if p.err.length() > 0:
            return -1

        if quant_here(p):
            if not repeatable(p, node):
                return perr(var p, "nothing to repeat")
            if not parse_quant(var p):
                return -1

            let mn = p.qmin
            let mx = p.qmax
            var gi = 0
            if p.qgreedy:
                gi = 1
            node = add_node(var p, N_REPEAT, node, mn, mx, gi)
            if quant_here(p):
                return perr(var p, "nothing to repeat")

        items.append(node)

    if items.length() == 1:
        return items[0]

    return seq_node(var p, items)

fn parse_alt(var p: Pat) Int:
    var alts = List[Int]()

    while true:
        let s = parse_seq(var p)
        if p.err.length() > 0:
            return -1

        alts.append(s)

        if peek(p) == 124:
            p.pos += 1
        else:
            break

    if alts.length() == 1:
        return alts[0]

    p.kids.append(alts)

    let idx = p.kids.length() - 1
    return add_node(var p, N_ALT, idx, 0, 0, 0)

// ---- pattern compilation to bytecode -------------------------------------

fn emit(var p: Pat, op: Int, a: Int, b: Int, c: Int, d: Int, e: Int) Int:
    p.code.append(op)
    p.code.append(a)
    p.code.append(b)
    p.code.append(c)
    p.code.append(d)
    p.code.append(e)
    return p.code.length() / 6 - 1

fn here(p: Pat) Int:
    return p.code.length() / 6

// field: 1 = a, 2 = b, 3 = c, 4 = d, 5 = e
fn setf(var p: Pat, pc: Int, field: Int, value: Int) Unit:
    p.code[pc * 6 + field] = value

fn compile_node(var p: Pat, node: Int) Unit:
    let k = p.nk[node]
    let a = p.na[node]
    let b = p.nb[node]
    let c = p.nc[node]
    let d = p.nd[node]

    if k == N_SET:
        emit(var p, OP_SET, a, 0, 0, 0, 0)
    else if k == N_ASSERT:
        emit(var p, OP_ASSERT, a, 0, 0, 0, 0)
    else if k == N_BREF:
        var ic = 0
        if p.icase:
            ic = 1
        emit(var p, OP_BREF, a, ic, 0, 0, 0)
    else if k == N_SEQ:
        let m = p.kids[a].length()

        for i in 0..m:
            let child = p.kids[a][i]
            compile_node(var p, child)
    else if k == N_GROUP:
        let tb = p.tbase + a
        emit(var p, OP_OPEN, tb, 0, 0, 0, 0)
        compile_node(var p, b)
        emit(var p, OP_CLOSE, 2 * a, tb, 0, 0, 0)
    else if k == N_ALT:
        let m = p.kids[a].length()
        var jumps = List[Int]()

        for i in 0..m:
            let child = p.kids[a][i]

            if i < m - 1:
                let hp = here(p)
                let sp = emit(var p, OP_SPLIT, hp + 1, 0, 0, 0, 0)
                compile_node(var p, child)

                let j = emit(var p, OP_JMP, 0, 0, 0, 0, 0)
                jumps.append(j)

                let nx = here(p)
                setf(var p, sp, 2, nx)
            else:
                compile_node(var p, child)

        let endpc = here(p)

        for i in 0..jumps.length():
            let jp = jumps[i]
            setf(var p, jp, 1, endpc)
    else if k == N_LOOK:
        let lk = emit(var p, OP_LOOK, b, 0, 0, 0, 0)
        compile_node(var p, a)
        emit(var p, OP_SUBEND, 0, 0, 0, 0, 0)

        let cont = here(p)
        setf(var p, lk, 2, cont)
    else if k == N_REPEAT:
        let cs = p.nslots
        let es = cs + 1
        p.nslots = cs + 2
        emit(var p, OP_SETVAL, cs, 0, 0, 0, 0)

        var hop = OP_LOOPL
        if d == 1:
            hop = OP_LOOPG

        let h = emit(var p, hop, cs, b, c, 0, 0)
        emit(var p, OP_SETPOS, es, 0, 0, 0, 0)
        compile_node(var p, a)

        let t = emit(var p, OP_LOOPTAIL, cs, b, es, 0, h)
        let ex = here(p)
        setf(var p, h, 4, ex)
        setf(var p, t, 4, ex)

fn same_name(name: List[Int], src: List[Int], from: Int, to: Int) Bool:
    if name.length() != to - from:
        return false

    for k in 0..name.length():
        if name[k] != src[from + k]:
            return false
    return true

fn build_pattern(src: List[Int]) Pat:
    var p = new_pat(src.clone())
    let n = src.length()

    if n >= 3 and src[0] == 40 and src[1] == 63:
        var j = 2

        while j < n and (src[j] == 105 or src[j] == 109 or src[j] == 115):
            if src[j] == 105:
                p.icase = true
            if src[j] == 109:
                p.multi = true
            if src[j] == 115:
                p.dotall = true
            j += 1

        if j > 2 and j < n and src[j] == 41:
            p.pos = j + 1

    let root = parse_alt(var p)
    if p.err.length() == 0 and p.pos < n:
        perr(var p, "unmatched )")
    if p.err.length() > 0:
        return p

    var k = 0

    while k < p.brefs.length():
        let id = p.brefs[k]

        if p.brefnames[k].length() == 0:
            if p.na[id] > p.ngroups:
                perr(var p, "bad backreference")
                return p
        else:
            var found = -1
            for g in 1..p.gnames.length():
                if (
                    found < 0
                    and same_name(
                        p.gnames[g], p.brefnames[k], 0, p.brefnames[k].length()
                    )
                ):
                    found = g

            if found < 0:
                perr(var p, "bad backreference")
                return p

            p.na[id] = found

        k += 1

    p.tbase = 2 * (p.ngroups + 1)
    p.nslots = p.tbase + p.ngroups + 1
    compile_node(var p, root)
    emit(var p, OP_MATCH, 0, 0, 0, 0, 0)
    return p

// ---- backtracking VM ------------------------------------------------------

fn assert_ok(kind: Int, subj: List[Int], pos: Int) Bool:
    let n = subj.length()

    if kind == 1:
        if pos == 0:
            return true

        return subj[pos - 1] == 10

    if kind == 2:
        return pos == n

    if kind == 3:
        if pos == n:
            return true

        return subj[pos] == 10

    if kind == 0:
        return pos == 0

    var before = false
    var after = false
    if pos > 0:
        before = is_word(subj[pos - 1])
    if pos < n:
        after = is_word(subj[pos])
    if kind == 4:
        return not (before == after)

    return before == after

// Runs from start_pc at start_pos. Returns end position, or -1 on failure.
// slots holds captures (2 per group), then group-open temporaries, then loop counters.
fn vm_run(
    prog: List[Int],
    bits: List[Bool],
    subj: List[Int],
    var slots: List[Int],
    start_pc: Int,
    start_pos: Int,
    full: Bool
) Int:
    var sk = List[Int]()
    var sx = List[Int]()
    var sy = List[Int]()
    var pc = start_pc
    var pos = start_pos
    let n = subj.length()

    while true:
        let base = pc * 6
        let op = prog[base]
        let a = prog[base + 1]
        let b = prog[base + 2]
        let c = prog[base + 3]
        let d = prog[base + 4]
        let e = prog[base + 5]
        var ok = true

        if op == OP_SET:
            if pos < n:
                if bits[a * 256 + subj[pos]]:
                    pc += 1
                    pos += 1
                else:
                    ok = false
            else:
                ok = false
        else if op == OP_SPLIT:
            sk.append(0)
            sx.append(b)
            sy.append(pos)
            pc = a
        else if op == OP_JMP:
            pc = a
        else if op == OP_OPEN:
            sk.append(1)
            sx.append(a)
            sy.append(slots[a])
            slots[a] = pos
            pc += 1
        else if op == OP_CLOSE:
            let st = slots[b]
            sk.append(1)
            sx.append(a)
            sy.append(slots[a])
            sk.append(1)
            sx.append(a + 1)
            sy.append(slots[a + 1])
            slots[a] = st
            slots[a + 1] = pos
            pc += 1
        else if op == OP_ASSERT:
            if assert_ok(a, subj, pos):
                pc += 1
            else:
                ok = false
        else if op == OP_BREF:
            let s = slots[2 * a]
            let en = slots[2 * a + 1]

            if s < 0:
                ok = false
            else:
                let ln = en - s

                if pos + ln > n:
                    ok = false
                else:
                    var i = 0

                    while i < ln:
                        var x = subj[s + i]
                        var y = subj[pos + i]

                        if b == 1:
                            x = lower(x)
                            y = lower(y)

                        if x != y:
                            break

                        i += 1

                    if i < ln:
                        ok = false
                    else:
                        pos += ln
                        pc += 1
        else if op == OP_SETPOS:
            sk.append(1)
            sx.append(a)
            sy.append(slots[a])
            slots[a] = pos
            pc += 1
        else if op == OP_SETVAL:
            sk.append(1)
            sx.append(a)
            sy.append(slots[a])
            slots[a] = b
            pc += 1
        else if op == OP_LOOPG or op == OP_LOOPL:
            let cnt = slots[a]

            if cnt < b:
                pc += 1
            else if c >= 0 and cnt >= c:
                pc = d
            else if op == OP_LOOPG:
                sk.append(0)
                sx.append(d)
                sy.append(pos)
                pc += 1
            else:
                sk.append(0)
                sx.append(pc + 1)
                sy.append(pos)
                pc = d
        else if op == OP_LOOPTAIL:
            let cnt = slots[a]

            if cnt >= b and pos == slots[c]:
                pc = d
            else:
                sk.append(1)
                sx.append(a)
                sy.append(cnt)
                slots[a] = cnt + 1
                pc = e
        else if op == OP_LOOK:
            let snap = slots.clone()
            let r = vm_run(prog, bits, subj, var slots, pc + 1, pos, false)

            if r >= 0:
                if a == 1:
                    for i in 0..snap.length():
                        slots[i] = snap[i]
                    ok = false
                else:
                    for i in 0..snap.length():
                        if slots[i] != snap[i]:
                            sk.append(1)
                            sx.append(i)
                            sy.append(snap[i])

                    pc = b
            else:
                if a == 1:
                    pc = b
                else:
                    ok = false
        else if op == OP_SUBEND:
            return pos
        else if op == OP_MATCH:
            if full and pos != n:
                ok = false
            else:
                return pos

        if not ok:
            var resumed = false

            while not resumed:
                let m = sk.length()
                if m == 0:
                    return -1

                let kind = sk[m - 1]
                let x = sx[m - 1]
                let y = sy[m - 1]
                sk.pop()
                sx.pop()
                sy.pop()

                if kind == 1:
                    slots[x] = y
                else:
                    pc = x
                    pos = y
                    resumed = true

fn new_slots(p: Pat) List[Int]:
    var s = List[Int]()
    for i in 0..p.nslots:
        s.append(-1)
    return s

// Leftmost match starting at or after `from`. Returns start or -1; slots 0 and 1 hold the whole match.
fn find_from(p: Pat, subj: List[Int], from: Int, full: Bool, var slots: List[Int]) Int:
    let n = subj.length()
    var st = from

    while st <= n:
        for i in 0..slots.length():
            slots[i] = -1

        let r = vm_run(p.code, p.bits, subj, var slots, 0, st, full)

        if r >= 0:
            slots[0] = st
            slots[1] = r
            return st

        if full:
            return -1

        st += 1

    return -1

// All find-all matches: starts, ends and capture vectors.
fn collect(
    p: Pat,
    subj: List[Int],
    var slots: List[Int],
    var ms: List[Int],
    var me: List[Int],
    var mc: List[List[Int]]
) Unit:
    let n = subj.length()
    var start = 0

    while start <= n:
        let st = find_from(p, subj, start, false, var slots)
        if st < 0:
            break

        let en = slots[1]
        ms.append(st)
        me.append(en)
        mc.append(slots.clone())

        if en > st:
            start = en
        else:
            start = en + 1

// ---- output ---------------------------------------------------------------

fn quote_char(c: Int) String:
    if c == 34:
        return "\\\""
    if c == 92:
        return "\\\\"
    if c == 10:
        return "\\n"
    if c == 9:
        return "\\t"
    if c == 13:
        return "\\r"
    if c < 32 or c > 126:
        return "\\x{HEXD.get(c / 16)}{HEXD.get(c % 16)}"

    return PRINTABLE.get(c - 32)

fn quoted(bytes: List[Int], from: Int, to: Int) String:
    var parts = List[String]()
    parts.append("\"")
    for i in from..to:
        parts.append(quote_char(bytes[i]))
    parts.append("\"")
    return parts.join("")

fn ascii_str(bytes: List[Int]) String:
    var parts = List[String]()
    for i in 0..bytes.length():
        parts.append(PRINTABLE.get(bytes[i] - 32))
    return parts.join("")

// ms: allow_effect std.console.write
fn print_groups(p: Pat, subj: List[Int], slots: List[Int]) Unit:
    for g in 0..p.ngroups + 1:
        var label = "{g}"
        if g > 0 and p.gnames[g].length() > 0:
            label = "{g} ({ascii_str(p.gnames[g])})"

        let s = slots[2 * g]

        if s < 0:
            print("{label}: unset")
        else:
            let en = slots[2 * g + 1]
            print("{label}: {s}..{en} {quoted(subj, s, en)}")

// ---- replacement ----------------------------------------------------------

fn append_group(var res: List[Int], subj: List[Int], slots: List[Int], g: Int) Unit:
    let s = slots[2 * g]

    if s >= 0:
        let en = slots[2 * g + 1]
        for j in s..en:
            res.append(subj[j])

fn find_name(names: List[List[Int]], src: List[Int], from: Int, to: Int) Int:
    for g in 1..names.length():
        if names[g].length() > 0 and same_name(names[g], src, from, to):
            return g
    return -1

fn expand(
    var res: List[Int], repl: List[Int], subj: List[Int], slots: List[Int],
    ngroups: Int, names: List[List[Int]]
) Bool:
    let m = repl.length()
    var i = 0

    while i < m:
        let c = repl[i]

        if c != 36:
            res.append(c)
            i += 1
        else if i + 1 >= m:
            res.append(36)
            i += 1
        else:
            let d = repl[i + 1]

            if is_digit(d):
                let g = d - 48
                if g > ngroups:
                    return false

                append_group(var res, subj, slots, g)
                i += 2
            else if d == 36:
                res.append(36)
                i += 2
            else if d == 123:
                var j = i + 2
                while j < m and repl[j] != 125:
                    j += 1
                if j >= m:
                    return false

                let g = find_name(names, repl, i + 2, j)
                if g < 0:
                    return false

                append_group(var res, subj, slots, g)
                i = j + 1
            else:
                res.append(36)
                i += 1

    return true

// ---- input decoding -------------------------------------------------------

fn bytes_is(b: List[Int], s: String) Bool:
    let sb = s.to_bytes()
    if sb.length() != b.length():
        return false

    for k in 0..b.length():
        if sb.get(k).to_int() != b[k]:
            return false
    return true

fn split_tab(line: List[Int]) List[List[Int]]:
    var out = List[List[Int]]()
    var cur = List[Int]()

    for k in 0..line.length():
        if line[k] == 9:
            out.append(cur)
            cur = List[Int]()
        else:
            cur.append(line[k])

    out.append(cur)
    return out

// Decodes \n \t \\ \xHH. Returns false on a bad sequence.
fn unescape(src: List[Int], var out: List[Int]) Bool:
    let n = src.length()
    var i = 0

    while i < n:
        let c = src[i]

        if c != 92:
            out.append(c)
            i += 1
        else:
            if i + 1 >= n:
                return false

            let d = src[i + 1]

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
                    return false

                let h1 = hexval(src[i + 2])
                let h2 = hexval(src[i + 3])
                if h1 < 0 or h2 < 0:
                    return false

                out.append(h1 * 16 + h2)
                i += 4
            else:
                return false

    return true

// ---- command driver -------------------------------------------------------

// ms: allow_effect std.console.write
fn process_line(line: List[Int]) Unit:
    let fields = split_tab(line)
    let cmd = fields[0]
    var kind = 0

    if bytes_is(cmd, "test"):
        kind = 1
    else if bytes_is(cmd, "match"):
        kind = 2
    else if bytes_is(cmd, "full"):
        kind = 3
    else if bytes_is(cmd, "find-all"):
        kind = 4
    else if bytes_is(cmd, "split"):
        kind = 5
    else if bytes_is(cmd, "replace"):
        kind = 6

    if kind == 0:
        print("error: bad command")
        return

    var want = 3
    if kind == 6:
        want = 4

    if fields.length() != want:
        print("error: bad command")
        return

    var subj = List[Int]()

    if not unescape(fields[2], var subj):
        print("error: bad command")
        return

    var repl = List[Int]()

    if kind == 6:
        if not unescape(fields[3], var repl):
            print("error: bad command")
            return

    let p = build_pattern(fields[1].clone())

    if p.err.length() > 0:
        print("error: {p.err}")
        return

    var slots = new_slots(p)

    if kind == 1:
        let st = find_from(p, subj, 0, false, var slots)

        if st >= 0:
            print("true")
        else:
            print("false")
    else if kind == 2 or kind == 3:
        let st = find_from(p, subj, 0, kind == 3, var slots)

        if st < 0:
            print("no match")
        else:
            print_groups(p, subj, slots)
    else if kind == 4:
        var ms = List[Int]()
        var me = List[Int]()
        var mc = List[List[Int]]()
        collect(p, subj, var slots, var ms, var me, var mc)
        for k in 0..ms.length():
            print("{ms[k]}..{me[k]} {quoted(subj, ms[k], me[k])}")
        print("({ms.length()} matches)")
    else if kind == 5:
        var ms = List[Int]()
        var me = List[Int]()
        var mc = List[List[Int]]()
        collect(p, subj, var slots, var ms, var me, var mc)

        var count = 0
        var prev = 0

        for k in 0..ms.length():
            if me[k] > ms[k]:
                print(quoted(subj, prev, ms[k]))
                count += 1
                prev = me[k]

        print(quoted(subj, prev, subj.length()))
        count += 1
        print("({count} pieces)")
    else:
        var ms = List[Int]()
        var me = List[Int]()
        var mc = List[List[Int]]()
        collect(p, subj, var slots, var ms, var me, var mc)

        var res = List[Int]()
        var prev = 0
        var okr = true

        for k in 0..ms.length():
            if okr:
                for j in prev..ms[k]:
                    res.append(subj[j])
                if not expand(var res, repl, subj, mc[k], p.ngroups, p.gnames):
                    okr = false
                prev = me[k]

        if okr:
            for j in prev..subj.length():
                res.append(subj[j])
            print(quoted(res, 0, res.length()))
        else:
            print("error: bad replacement")

export fn main() Int:
    let data = read_all(stdin()).get()
    var all = List[Int]()
    for i in 0..data.length():
        all.append(data.get(i).to_int())

    let total = all.length()
    var start = 0
    var i = 0

    while i <= total:
        if i == total or all[i] == 10:
            if i > start:
                var line = List[Int]()
                for j in start..i:
                    line.append(all[j])
                process_line(line)

            start = i + 1

        i += 1

    return 0
