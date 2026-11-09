// Backtracking regular-expression engine and command driver (see TASK.md).
//
// Pipeline: parse the pattern into a node arena, compile the nodes to a
// small instruction list, then run a backtracking VM that keeps an explicit
// undo stack for captures and loop registers.

import stdin from "@std/io/io.ms"
import stdout_bytes from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder from "@std/bytes.ms"

// AST node kinds.
let N_CLASS = 0
let N_SEQ = 1
let N_ALT = 2
let N_GROUP = 3
let N_REP = 4
let N_ASSERT = 5
let N_BREF = 6
let N_LOOK = 7
let N_NBREF = 8
// VM opcodes.
let O_CLASS = 0
let O_SPLIT = 1
let O_JMP = 2
let O_LOOPSET = 3
let O_CHK = 4
let O_OPEN = 5
let O_CLOSE = 6
let O_BOL = 7
let O_EOL = 8
let O_WORDB = 9
let O_NWORDB = 10
let O_BREF = 11
let O_LOOK = 12
let O_LOOKEND = 13
let O_MATCH = 14

type Node:
    kind: Int
    a: Int
    b: Int
    c: Int
    kids: List[Int]

type Parser:
    pat: List[Int]
    pos: Int
    ngroups: Int
    gnames: List[List[Int]]
    nodes: List[Node]
    classes: List[List[Bool]]
    icase: Bool
    multi: Bool
    dotall: Bool
    brefs: List[Int]
    nrefs: List[List[Int]]

type Prog:
    ops: List[Int]
    xs: List[Int]
    ys: List[Int]
    classes: List[List[Bool]]
    ngroups: Int
    gnames: List[List[Int]]
    regbase: Int
    nregs: Int
    icase: Bool
    multi: Bool

// ---------- small helpers ----------

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_alnum(c: Int) Bool:
    return is_digit(c) or is_alpha(c)

fn is_word(c: Int) Bool:
    return is_digit(c) or is_alpha(c) or c == 95

fn is_space(c: Int) Bool:
    return c == 32 or (c >= 9 and c <= 13)

fn lower(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn hexval(c: Int) Int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 65 and c <= 70:
        return c - 55
    if c >= 97 and c <= 102:
        return c - 87

    return -1

fn hexdig(v: Int) Int:
    if v < 10:
        return 48 + v

    return 87 + v

// Byte at i, or -1 outside the list.
fn at(ps: Parser, i: Int) Int:
    if i < 0 or i >= ps.pat.length():
        return -1

    return ps.pat[i]

fn to_ints(s: String) List[Int]:
    var r = List[Int]()
    for b in s.to_bytes().values():
        r.append(b.to_int())
    return r

fn same_bytes(a: List[Int], b: List[Int]) Bool:
    if a.length() != b.length():
        return false

    for i in 0..a.length():
        if a[i] != b[i]:
            return false
    return true

fn slice_of(xs: List[Int], from: Int, to: Int) List[Int]:
    var r = List[Int]()
    for i in from..to:
        r.append(xs[i])
    return r

// Index of the group called `nm` (named groups only), or -1.
fn find_group(names: List[List[Int]], ngroups: Int, nm: List[Int]) Int:
    if nm.length() == 0:
        return -1

    for k in 1..(ngroups + 1):
        if names[k].length() > 0 and same_bytes(names[k], nm):
            return k
    return -1

fn empty_set() List[Bool]:
    var s = List[Bool]()
    for i in 0..256:
        s.append(false)
    return s

fn add_node(var ps: Parser, kind: Int, a: Int, b: Int, c: Int, kids: List[Int]) Int:
    ps.nodes.append(Node(kind: kind, a: a, b: b, c: c, kids: kids))
    return ps.nodes.length() - 1

// Turns a byte set into a class node; ASCII letters are folded for `i`.
fn finish_class(var ps: Parser, var cs: List[Bool], neg: Bool) Int:
    if ps.icase:
        for k in 0..26:
            let u = 65 + k
            let l = 97 + k

            if cs[u] or cs[l]:
                cs[u] = true
                cs[l] = true

    if neg:
        for i in 0..256:
            cs[i] = not cs[i]
    ps.classes.append(cs.clone())
    return add_node(var ps, N_CLASS, ps.classes.length() - 1, 0, 0, List[Int]())

fn literal_node(var ps: Parser, c: Int) Int:
    var cs = empty_set()
    cs[c] = true
    return finish_class(var ps, var cs, false)

fn any_node(var ps: Parser) Int:
    var cs = empty_set()
    for i in 0..256:
        cs[i] = ps.dotall or i != 10
    return finish_class(var ps, var cs, false)

// k is the shorthand letter: d D w W s S.
fn short_has(k: Int, c: Int) Bool:
    if k == 100:
        return is_digit(c)
    if k == 68:
        return not is_digit(c)
    if k == 119:
        return is_word(c)
    if k == 87:
        return not is_word(c)
    if k == 115:
        return is_space(c)

    return not is_space(c)

fn short_node(var ps: Parser, k: Int) Int:
    var cs = empty_set()
    for i in 0..256:
        cs[i] = short_has(k, i)
    return finish_class(var ps, var cs, false)

// The shorthand letter if a `\d`-style escape starts at pos, else -1.
fn shorthand_at(ps: Parser) Int:
    if at(ps, ps.pos) == 92:
        let e = at(ps, ps.pos + 1)
        if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
            return e

    return -1

// Decoded value of \n \t \r, or -1.
fn simple_escape(e: Int) Int:
    if e == 110:
        return 10
    if e == 116:
        return 9
    if e == 114:
        return 13

    return -1

// Two hex digits starting at i, or -1.
fn hex2(ps: Parser, i: Int) Int:
    let h1 = hexval(at(ps, i))
    let h2 = hexval(at(ps, i + 1))
    if h1 < 0 or h2 < 0:
        return -1

    return h1 * 16 + h2

// End index of an identifier starting at i, or -1 when it does not start one.
fn name_end(ps: Parser, i: Int) Int:
    let c = at(ps, i)
    if not (is_alpha(c) or c == 95):
        return -1

    var j = i + 1
    while is_word(at(ps, j)):
        j += 1
    return j

// Index after `}` when a `{n}`, `{n,}` or `{n,m}` shape starts at p, else -1.
fn brace_end(ps: Parser, p: Int) Int:
    var i = p + 1
    let s1 = i
    while is_digit(at(ps, i)):
        i += 1
    if i == s1:
        return -1
    if at(ps, i) == 125:
        return i + 1
    if at(ps, i) != 44:
        return -1

    i += 1
    while is_digit(at(ps, i)):
        i += 1
    if at(ps, i) == 125:
        return i + 1

    return -1

// Decimal value of digits in [i, j), capped so huge counts stay small.
fn num_range(ps: Parser, i: Int, j: Int) Int:
    var v = 0

    for k in i..j:
        v = v * 10 + (at(ps, k) - 48)
        if v > 100000:
            v = 100000

    return v

// ---------- parser ----------

// One character inside a class, consuming it (handles escapes).
fn class_char(var ps: Parser) Int!String:
    let c = at(ps, ps.pos)

    if c != 92:
        ps.pos += 1
        return ok(c)

    let e = at(ps, ps.pos + 1)
    if e < 0:
        return error("bad escape")

    let sv = simple_escape(e)

    if sv >= 0:
        ps.pos += 2
        return ok(sv)

    if e == 120:
        let v = hex2(ps, ps.pos + 2)
        if v < 0:
            return error("bad escape")

        ps.pos += 4
        return ok(v)

    if is_alnum(e) or e >= 128:
        return error("bad escape")

    ps.pos += 2
    return ok(e)

// Parses a class body; ps.pos is just after `[`.
fn parse_class(var ps: Parser) Int!String:
    var cs = empty_set()
    var neg = false

    if at(ps, ps.pos) == 94:
        neg = true
        ps.pos += 1

    var item = 0
    var prev_range = false

    while true:
        let c = at(ps, ps.pos)
        if c < 0:
            return error("unterminated class")

        if c == 93 and item > 0:
            ps.pos += 1
            break

        let sh = shorthand_at(ps)

        if sh >= 0:
            ps.pos += 2
            for i in 0..256:
                if short_has(sh, i):
                    cs[i] = true
            if (
                at(ps, ps.pos) == 45
                and at(ps, ps.pos + 1) >= 0
                and at(ps, ps.pos + 1) != 93
            ):
                return error("bad range")

            prev_range = false
        else:
            let lo = try class_char(var ps)
            var is_range = false
            if (
                at(ps, ps.pos) == 45
                and at(ps, ps.pos + 1) >= 0
                and at(ps, ps.pos + 1) != 93
            ):
                is_range = not (lo == 45 and (item == 0 or prev_range))

            if is_range:
                ps.pos += 1
                if shorthand_at(ps) >= 0:
                    return error("bad range")

                let hi = try class_char(var ps)
                if hi < lo:
                    return error("bad range")

                for i in lo..(hi + 1):
                    cs[i] = true
                prev_range = true
            else:
                cs[lo] = true
                prev_range = false

        item += 1

    return ok(finish_class(var ps, var cs, neg))

// Escape outside a class; ps.pos is at the backslash.
fn parse_escape(var ps: Parser) Int!String:
    let e = at(ps, ps.pos + 1)
    if e < 0:
        return error("bad escape")

    let sh = shorthand_at(ps)

    if sh >= 0:
        ps.pos += 2
        return ok(short_node(var ps, sh))

    if e == 98:
        ps.pos += 2
        return ok(add_node(var ps, N_ASSERT, O_WORDB, 0, 0, List[Int]()))

    if e == 66:
        ps.pos += 2
        return ok(add_node(var ps, N_ASSERT, O_NWORDB, 0, 0, List[Int]()))

    if e >= 49 and e <= 57:
        ps.pos += 2
        ps.brefs.append(e - 48)
        return ok(add_node(var ps, N_BREF, e - 48, 0, 0, List[Int]()))

    if e == 107:
        if at(ps, ps.pos + 2) != 60:
            return error("bad escape")

        let ne = name_end(ps, ps.pos + 3)
        if ne < 0 or at(ps, ne) != 62:
            return error("bad escape")

        let name = slice_of(ps.pat, ps.pos + 3, ne)
        ps.pos = ne + 1
        ps.nrefs.append(name)
        return ok(add_node(var ps, N_NBREF, ps.nrefs.length() - 1, 0, 0, List[Int]()))

    let sv = simple_escape(e)

    if sv >= 0:
        ps.pos += 2
        return ok(literal_node(var ps, sv))

    if e == 120:
        let v = hex2(ps, ps.pos + 2)
        if v < 0:
            return error("bad escape")

        ps.pos += 4
        return ok(literal_node(var ps, v))

    if is_alnum(e) or e >= 128:
        return error("bad escape")

    ps.pos += 2
    return ok(literal_node(var ps, e))

// Parses `(...)`, `(?:...)`, `(?=...)`, `(?!...)` or `(?<name>...)`.
fn parse_group(var ps: Parser) Int!String:
    ps.pos += 1

    var cap = -1
    var kind = N_GROUP
    var look_neg = 0

    if at(ps, ps.pos) == 63:
        let d = at(ps, ps.pos + 1)

        if d == 58:
            ps.pos += 2
        else if d == 61 or d == 33:
            ps.pos += 2
            kind = N_LOOK
            if d == 33:
                look_neg = 1
        else if d == 60:
            let e1 = at(ps, ps.pos + 2)
            if e1 == 61 or e1 == 33:
                return error("bad group")

            let ne = name_end(ps, ps.pos + 2)
            if ne < 0 or at(ps, ne) != 62:
                return error("bad group")

            let name = slice_of(ps.pat, ps.pos + 2, ne)
            for g in 1..(ps.ngroups + 1):
                if same_bytes(ps.gnames[g], name):
                    return error("duplicate group name")
            ps.pos = ne + 1
            ps.ngroups += 1
            ps.gnames.append(name)
            cap = ps.ngroups
        else:
            return error("bad group")
    else:
        ps.ngroups += 1
        ps.gnames.append(List[Int]())
        cap = ps.ngroups

    let body = try parse_alt(var ps)
    if at(ps, ps.pos) != 41:
        return error("unmatched (")

    ps.pos += 1
    if kind == N_LOOK:
        return ok(add_node(var ps, N_LOOK, look_neg, 0, 0, [body]))

    return ok(add_node(var ps, N_GROUP, cap, 0, 0, [body]))

fn parse_atom(var ps: Parser) Int!String:
    let c = at(ps, ps.pos)
    if c == 40:
        return parse_group(var ps)

    if c == 91:
        ps.pos += 1
        return parse_class(var ps)

    if c == 46:
        ps.pos += 1
        return ok(any_node(var ps))

    if c == 94:
        ps.pos += 1
        return ok(add_node(var ps, N_ASSERT, O_BOL, 0, 0, List[Int]()))

    if c == 36:
        ps.pos += 1
        return ok(add_node(var ps, N_ASSERT, O_EOL, 0, 0, List[Int]()))

    if c == 92:
        return parse_escape(var ps)
    if c == 42 or c == 43 or c == 63:
        return error("nothing to repeat")

    // `{` here is always a literal, as are `}` and `]`.
    ps.pos += 1
    return ok(literal_node(var ps, c))

// Applies a quantifier after `atom` if one starts at ps.pos.
fn parse_quant(var ps: Parser, atom: Int) Int!String:
    let c = at(ps, ps.pos)
    var mn = 0
    var mx = 0
    var greedy = 1

    if c == 42:
        mn = 0
        mx = -1
        ps.pos += 1
    else if c == 43:
        mn = 1
        mx = -1
        ps.pos += 1
    else if c == 63:
        mn = 0
        mx = 1
        ps.pos += 1
    else if c == 123:
        let e = brace_end(ps, ps.pos)
        if e < 0:
            return ok(atom)

        let i1 = ps.pos + 1
        var i = i1
        while is_digit(at(ps, i)):
            i += 1
        mn = num_range(ps, i1, i)

        if at(ps, i) == 125:
            mx = mn
        else:
            i += 1

            let s2 = i
            while is_digit(at(ps, i)):
                i += 1

            if s2 == i:
                mx = -1
            else:
                mx = num_range(ps, s2, i)

        ps.pos = e
    else:
        return ok(atom)

    let kind = ps.nodes[atom].kind
    if kind == N_ASSERT or kind == N_LOOK:
        return error("nothing to repeat")
    if mx >= 0 and mn > mx:
        return error("bad repeat")
    if mn > 1000 or mx > 1000:
        return error("bad repeat")

    if at(ps, ps.pos) == 63:
        greedy = 0
        ps.pos += 1

    let nc = at(ps, ps.pos)
    if nc == 42 or nc == 43 or nc == 63:
        return error("nothing to repeat")
    if nc == 123 and brace_end(ps, ps.pos) >= 0:
        return error("nothing to repeat")

    return ok(add_node(var ps, N_REP, mn, mx, greedy, [atom]))

fn parse_seq(var ps: Parser) Int!String:
    var kids = List[Int]()
    let n = ps.pat.length()

    while ps.pos < n:
        let c = ps.pat[ps.pos]
        if c == 124 or c == 41:
            break

        let atom = try parse_atom(var ps)
        let q = try parse_quant(var ps, atom)
        kids.append(q)

    return ok(add_node(var ps, N_SEQ, 0, 0, 0, kids))

fn parse_alt(var ps: Parser) Int!String:
    var alts = List[Int]()
    let n = ps.pat.length()
    alts.append(try parse_seq(var ps))

    while ps.pos < n and ps.pat[ps.pos] == 124:
        ps.pos += 1
        alts.append(try parse_seq(var ps))

    if alts.length() == 1:
        return ok(alts[0])

    return ok(add_node(var ps, N_ALT, 0, 0, 0, alts))

// ---------- compiler ----------

fn emit(var p: Prog, op: Int, x: Int, y: Int) Int:
    p.ops.append(op)
    p.xs.append(x)
    p.ys.append(y)
    return p.ops.length() - 1

fn new_reg(var p: Prog) Int:
    let r = p.regbase + p.nregs
    p.nregs += 1
    return r

fn compile(var p: Prog, nodes: List[Node], id: Int) Unit:
    let kind = nodes[id].kind

    if kind == N_CLASS:
        let _e = emit(var p, O_CLASS, nodes[id].a, 0)
    else if kind == N_SEQ:
        for k in nodes[id].kids:
            compile(var p, nodes, k)
    else if kind == N_ALT:
        let kids = nodes[id].kids
        let k = kids.length()
        var jmps = List[Int]()

        for i in 0..k:
            if i < k - 1:
                let sp = emit(var p, O_SPLIT, 0, 0)
                compile(var p, nodes, kids[i])
                jmps.append(emit(var p, O_JMP, 0, 0))
                p.xs[sp] = sp + 1
                p.ys[sp] = p.ops.length()
            else:
                compile(var p, nodes, kids[i])

        let end = p.ops.length()
        for j in jmps:
            p.xs[j] = end
    else if kind == N_GROUP:
        let g = nodes[id].a
        let body = nodes[id].kids[0]

        if g >= 0:
            let r = new_reg(var p)
            let _o = emit(var p, O_OPEN, g, r)
            compile(var p, nodes, body)

            let _c = emit(var p, O_CLOSE, g, r)
        else:
            compile(var p, nodes, body)
    else if kind == N_REP:
        let mn = nodes[id].a
        let mx = nodes[id].b
        let greedy = nodes[id].c == 1
        let body = nodes[id].kids[0]
        var splits = List[Int]()
        var chks = List[Int]()

        // Mandatory iterations. The last one may not consume nothing and
        // still continue the loop, so it gets an empty-iteration check.
        for i in 0..mn:
            if mx != mn and i == mn - 1:
                let r = new_reg(var p)
                let _l = emit(var p, O_LOOPSET, r, 0)
                compile(var p, nodes, body)
                chks.append(emit(var p, O_CHK, r, 0))
            else:
                compile(var p, nodes, body)

        if mx == -1:
            let top = emit(var p, O_SPLIT, 0, 0)
            splits.append(top)

            let r = new_reg(var p)
            let _l = emit(var p, O_LOOPSET, r, 0)
            compile(var p, nodes, body)
            chks.append(emit(var p, O_CHK, r, 0))

            let _j = emit(var p, O_JMP, top, 0)
        else:
            for i in 0..(mx - mn):
                splits.append(emit(var p, O_SPLIT, 0, 0))

                let r = new_reg(var p)
                let _l = emit(var p, O_LOOPSET, r, 0)
                compile(var p, nodes, body)
                chks.append(emit(var p, O_CHK, r, 0))

        let exit = p.ops.length()

        for sp in splits:
            if greedy:
                p.xs[sp] = sp + 1
                p.ys[sp] = exit
            else:
                p.xs[sp] = exit
                p.ys[sp] = sp + 1

        for ck in chks:
            p.ys[ck] = exit
    else if kind == N_ASSERT:
        let _a = emit(var p, nodes[id].a, 0, 0)
    else if kind == N_BREF:
        let _b = emit(var p, O_BREF, nodes[id].a, 0)
    else if kind == N_LOOK:
        let lk = emit(var p, O_LOOK, nodes[id].a, 0)
        compile(var p, nodes, nodes[id].kids[0])

        let _e = emit(var p, O_LOOKEND, 0, 0)
        p.ys[lk] = p.ops.length()

// Parses and compiles a pattern. Errors carry the message from TASK.md.
fn parse_pattern(pat: List[Int]) Prog!String:
    var ps = Parser(
        pat: pat.clone(), pos: 0, ngroups: 0, gnames: [List[Int]()],
        nodes: List[Node](), classes: List[List[Bool]](), icase: false, multi: false,
        dotall: false, brefs: List[Int](), nrefs: List[List[Int]]()
    )
    let n = pat.length()

    // Leading flags: (?imsx...) at the very start only.
    if at(ps, 0) == 40 and at(ps, 1) == 63:
        var j = 2
        while at(ps, j) == 105 or at(ps, j) == 109 or at(ps, j) == 115:
            j += 1

        if j > 2 and at(ps, j) == 41:
            for k in 2..j:
                let f = pat[k]

                if f == 105:
                    ps.icase = true
                else if f == 109:
                    ps.multi = true
                else:
                    ps.dotall = true

            ps.pos = j + 1

    let root = try parse_alt(var ps)
    if ps.pos < n:
        return error("unmatched )")

    for b in ps.brefs:
        if b > ps.ngroups:
            return error("bad backreference")

    for i in 0..ps.nodes.length():
        if ps.nodes[i].kind == N_NBREF:
            let g = find_group(ps.gnames, ps.ngroups, ps.nrefs[ps.nodes[i].a])
            if g < 0:
                return error("bad backreference")

            ps.nodes[i] = Node(kind: N_BREF, a: g, b: 0, c: 0, kids: List[Int]())

    var p = Prog(
        ops: List[Int](), xs: List[Int](), ys: List[Int](), classes: ps.classes,
        ngroups: ps.ngroups, gnames: ps.gnames, regbase: 2 * (ps.ngroups + 1), nregs: 0,
        icase: ps.icase, multi: ps.multi
    )
    compile(var p, ps.nodes, root)

    let _m = emit(var p, O_MATCH, 0, 0)
    return ok(p)

// ---------- matcher ----------

// Writes st[slot] with an undo record on the stack.
fn set_slot(var st: List[Int], var stk: List[Int], slot: Int, value: Int) Unit:
    stk.append(1)
    stk.append(slot)
    stk.append(st[slot])
    st[slot] = value

// Pops everything above height h, applying undo records.
fn undo_to(var st: List[Int], var stk: List[Int], h: Int) Unit:
    while stk.length() > h:
        let b = stk.pop().get(0)
        let a = stk.pop().get(0)
        let k = stk.pop().get(0)
        if k == 1:
            st[a] = b

// Drops choice points above h but keeps undo records (used after an atomic lookahead succeeds).
fn drop_choices(var st: List[Int], var stk: List[Int], h: Int) Unit:
    var keep = List[Int]()
    var i = h
    let n = stk.length()

    while i < n:
        if stk[i] == 1:
            keep.append(1)
            keep.append(stk[i + 1])
            keep.append(stk[i + 2])

        i += 3

    while stk.length() > h:
        let _x = stk.pop()
    for v in keep:
        stk.append(v)

// Runs the program from pc0 at pos0. Returns the end position, or -1.
// need_end demands the match end at the subject end (for `full`).
fn run(
    p: Prog,
    s: List[Int],
    var st: List[Int],
    var stk: List[Int],
    pc0: Int,
    pos0: Int,
    need_end: Bool
) Int:
    var pc = pc0
    var pos = pos0
    let base = stk.length()
    let n = s.length()

    while true:
        let op = p.ops[pc]
        let x = p.xs[pc]
        let y = p.ys[pc]
        var fail = false

        if op == O_CLASS:
            if pos < n and p.classes[x][s[pos]]:
                pos += 1
                pc += 1
            else:
                fail = true
        else if op == O_SPLIT:
            stk.append(0)
            stk.append(y)
            stk.append(pos)
            pc = x
        else if op == O_JMP:
            pc = x
        else if op == O_LOOPSET:
            set_slot(var st, var stk, x, pos)
            pc += 1
        else if op == O_CHK:
            if pos == st[x]:
                pc = y
            else:
                pc += 1
        else if op == O_OPEN:
            set_slot(var st, var stk, y, pos)
            set_slot(var st, var stk, 2 * x, -1)
            set_slot(var st, var stk, 2 * x + 1, -1)
            pc += 1
        else if op == O_CLOSE:
            set_slot(var st, var stk, 2 * x, st[y])
            set_slot(var st, var stk, 2 * x + 1, pos)
            pc += 1
        else if op == O_BOL:
            if pos == 0 or (p.multi and s[pos - 1] == 10):
                pc += 1
            else:
                fail = true
        else if op == O_EOL:
            if pos == n or (p.multi and s[pos] == 10):
                pc += 1
            else:
                fail = true
        else if op == O_WORDB or op == O_NWORDB:
            var before = false
            var after = false
            if pos > 0:
                before = is_word(s[pos - 1])
            if pos < n:
                after = is_word(s[pos])

            let boundary = before != after

            if boundary == (op == O_WORDB):
                pc += 1
            else:
                fail = true
        else if op == O_BREF:
            let gs = st[2 * x]
            let ge = st[2 * x + 1]

            if gs < 0 or ge < 0:
                fail = true
            else:
                let len = ge - gs

                if pos + len > n:
                    fail = true
                else:
                    var same = true

                    for j in 0..len:
                        var a = s[gs + j]
                        var b = s[pos + j]

                        if p.icase:
                            a = lower(a)
                            b = lower(b)

                        if a != b:
                            same = false

                    if same:
                        pos += len
                        pc += 1
                    else:
                        fail = true
        else if op == O_LOOK:
            let h = stk.length()
            let r = run(p, s, var st, var stk, pc + 1, pos, false)

            if x == 0:
                if r < 0:
                    fail = true
                else:
                    drop_choices(var st, var stk, h)
                    pc = y
            else:
                if r >= 0:
                    undo_to(var st, var stk, h)
                    fail = true
                else:
                    pc = y
        else if op == O_LOOKEND:
            return pos
        else if op == O_MATCH:
            if need_end and pos != n:
                fail = true
            else:
                return pos

        if fail:
            var resumed = false

            while not resumed:
                if stk.length() == base:
                    return -1

                let b = stk.pop().get(0)
                let a = stk.pop().get(0)
                let k = stk.pop().get(0)

                if k == 1:
                    st[a] = b
                else:
                    pc = a
                    pos = b
                    resumed = true

// Leftmost match starting at or after `from` (only at `from` when anchored).
// Returns the start, or -1. On success st[0], st[1] hold the span and
// st[2g], st[2g+1] the groups.
fn search(
    p: Prog,
    s: List[Int],
    from: Int,
    anchored: Bool,
    need_end: Bool,
    var st: List[Int]
) Int:
    let n = s.length()
    var last = n
    if anchored:
        last = from

    var start = from

    while start <= last:
        for i in 0..st.length():
            st[i] = -1

        var stk = List[Int]()
        let e = run(p, s, var st, var stk, 0, start, need_end)

        if e >= 0:
            st[0] = start
            st[1] = e
            return start

        start += 1

    return -1

fn new_state(p: Prog) List[Int]:
    var st = List[Int]()
    for i in 0..(p.regbase + p.nregs):
        st.append(-1)
    return st

// All successive matches as capture snapshots (see find-all rules in TASK.md).
fn find_all(p: Prog, s: List[Int]) List[List[Int]]:
    var res = List[List[Int]]()
    let n = s.length()
    var st = new_state(p)
    var start = 0

    while start <= n:
        let sp = search(p, s, start, false, false, var st)
        if sp < 0:
            break

        let e = st[1]
        res.append(st.clone())

        if e == sp:
            start = e + 1
        else:
            start = e

    return res

// ---------- output ----------

fn put_str(var out: List[Int], s: String) Unit:
    for b in s.to_bytes().values():
        out.append(b.to_int())

fn put_quoted(var out: List[Int], s: List[Int], from: Int, to: Int) Unit:
    out.append(34)

    for i in from..to:
        let c = s[i]

        if c == 92:
            out.append(92)
            out.append(92)
        else if c == 34:
            out.append(92)
            out.append(34)
        else if c == 10:
            out.append(92)
            out.append(110)
        else if c == 9:
            out.append(92)
            out.append(116)
        else if c == 13:
            out.append(92)
            out.append(114)
        else if c < 32 or c > 126:
            out.append(92)
            out.append(120)
            out.append(hexdig(c / 16))
            out.append(hexdig(c % 16))
        else:
            out.append(c)

    out.append(34)

fn put_span(var out: List[Int], s: List[Int], st: List[Int], g: Int) Unit:
    put_str(var out, "{st[2 * g]}..{st[2 * g + 1]} ")
    put_quoted(var out, s, st[2 * g], st[2 * g + 1])

fn put_groups(var out: List[Int], p: Prog, s: List[Int], st: List[Int]) Unit:
    for g in 0..(p.ngroups + 1):
        put_str(var out, "{g}")

        if g > 0 and p.gnames[g].length() > 0:
            put_str(var out, " (")
            for b in p.gnames[g]:
                out.append(b)
            put_str(var out, ")")

        put_str(var out, ": ")

        if st[2 * g] >= 0 and st[2 * g + 1] >= 0:
            put_span(var out, s, st, g)
        else:
            put_str(var out, "unset")

        out.append(10)

// ---------- replacement ----------

// Expands a replacement for one match; none when it names a bad group.
fn expand(p: Prog, s: List[Int], st: List[Int], repl: List[Int]) List[Int]?:
    var buf = List[Int]()
    let m = repl.length()
    var i = 0

    while i < m:
        let c = repl[i]

        if c != 36:
            buf.append(c)
            i += 1
        else if i + 1 >= m:
            buf.append(36)
            i += 1
        else:
            let d = repl[i + 1]

            if d == 36:
                buf.append(36)
                i += 2
            else if is_digit(d):
                let g = d - 48
                if g > p.ngroups:
                    return none

                if st[2 * g] >= 0 and st[2 * g + 1] >= 0:
                    for k in st[2 * g]..st[2 * g + 1]:
                        buf.append(s[k])
                i += 2
            else if d == 123:
                var j = i + 2
                while j < m and repl[j] != 125:
                    j += 1
                if j >= m:
                    return none

                let g = find_group(p.gnames, p.ngroups, slice_of(repl, i + 2, j))
                if g < 0:
                    return none

                if st[2 * g] >= 0 and st[2 * g + 1] >= 0:
                    for k in st[2 * g]..st[2 * g + 1]:
                        buf.append(s[k])
                i = j + 1
            else:
                buf.append(36)
                i += 1

    return buf

// ---------- command line handling ----------

// Unescapes subject/replacement text. False on a bad escape.
fn unescape(raw: List[Int], var buf: List[Int]) Bool:
    let n = raw.length()
    var i = 0

    while i < n:
        let c = raw[i]

        if c != 92:
            buf.append(c)
            i += 1
        else:
            if i + 1 >= n:
                return false

            let e = raw[i + 1]
            let sv = simple_escape(e)

            if sv >= 0:
                buf.append(sv)
                i += 2
            else if e == 92:
                buf.append(92)
                i += 2
            else if e == 120:
                if i + 3 >= n:
                    return false

                let h1 = hexval(raw[i + 2])
                let h2 = hexval(raw[i + 3])
                if h1 < 0 or h2 < 0:
                    return false

                buf.append(h1 * 16 + h2)
                i += 4
            else:
                return false

    return true

fn command_code(name: List[Int]) Int:
    if same_bytes(name, to_ints("test")):
        return 0
    if same_bytes(name, to_ints("match")):
        return 1
    if same_bytes(name, to_ints("full")):
        return 2
    if same_bytes(name, to_ints("find-all")):
        return 3
    if same_bytes(name, to_ints("split")):
        return 4
    if same_bytes(name, to_ints("replace")):
        return 5

    return -1

fn put_error(var out: List[Int], msg: String) Unit:
    put_str(var out, "error: ")
    put_str(var out, msg)
    out.append(10)

fn put_bad_command(var out: List[Int]) Unit:
    put_error(var out, "bad command")

fn process(var out: List[Int], line: List[Int]) Unit:
    var fields = List[List[Int]]()
    var cur = List[Int]()

    for c in line:
        if c == 9:
            fields.append(cur)
            cur = List[Int]()
        else:
            cur.append(c)

    fields.append(cur)

    let nf = fields.length()
    let code = command_code(fields[0])

    if code < 0:
        put_bad_command(var out)
        return

    let want = if code == 5: 4 else: 3

    if nf != want:
        put_bad_command(var out)
        return

    var subject = List[Int]()

    if not unescape(fields[2], var subject):
        put_bad_command(var out)
        return

    var repl = List[Int]()

    if code == 5 and not unescape(fields[3], var repl):
        put_bad_command(var out)
        return

    let compiled = parse_pattern(fields[1].clone())

    if compiled.is_error():
        put_error(var out, compiled.err())
        return

    let p = compiled.get(
        Prog(
            ops: List[Int](), xs: List[Int](), ys: List[Int](),
            classes: List[List[Bool]](), ngroups: 0, gnames: List[List[Int]](),
            regbase: 0, nregs: 0, icase: false, multi: false
        )
    )
    var st = new_state(p)
    let n = subject.length()

    if code == 0:
        let sp = search(p, subject, 0, false, false, var st)

        if sp >= 0:
            put_str(var out, "true\n")
        else:
            put_str(var out, "false\n")
    else if code == 1:
        let sp = search(p, subject, 0, false, false, var st)

        if sp < 0:
            put_str(var out, "no match\n")
        else:
            put_groups(var out, p, subject, st)
    else if code == 2:
        let sp = search(p, subject, 0, true, true, var st)

        if sp < 0:
            put_str(var out, "no match\n")
        else:
            put_groups(var out, p, subject, st)
    else if code == 3:
        let ms = find_all(p, subject)

        for snap in ms:
            put_span(var out, subject, snap, 0)
            out.append(10)

        put_str(var out, "({ms.length()} matches)\n")
    else if code == 4:
        let ms = find_all(p, subject)
        var prev = 0
        var pieces = 0

        for snap in ms:
            if snap[0] != snap[1]:
                put_quoted(var out, subject, prev, snap[0])
                out.append(10)
                prev = snap[1]
                pieces += 1

        put_quoted(var out, subject, prev, n)
        out.append(10)
        pieces += 1
        put_str(var out, "({pieces} pieces)\n")
    else:
        let ms = find_all(p, subject)
        var buf = List[Int]()
        var prev = 0
        var bad = false

        for snap in ms:
            if not bad:
                for k in prev..snap[0]:
                    buf.append(subject[k])

                if let piece = expand(p, subject, snap, repl):
                    for v in piece:
                        buf.append(v)
                else:
                    bad = true

                prev = snap[1]

        if bad:
            put_error(var out, "bad replacement")
        else:
            for k in prev..n:
                buf.append(subject[k])
            put_quoted(var out, buf, 0, buf.length())
            out.append(10)

export fn main() Int:
    let data = read_all(stdin()).get()
    var input = List[Int]()
    for b in data.values():
        input.append(b.to_int())

    var out = List[Int]()
    var line = List[Int]()

    for c in input:
        if c == 10:
            if line.length() > 0:
                process(var out, line)
            line = List[Int]()
        else:
            line.append(c)

    if line.length() > 0:
        process(var out, line)

    var bb = BytesBuilder()
    for v in out:
        bb.append(v.to_uint8().get(0))

    let _w = stdout_bytes().write(bb.build()).get()
    return 0
