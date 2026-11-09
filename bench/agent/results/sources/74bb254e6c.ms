import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"
import from_scalars from "@std/string.ms"

// Errors raised by the interpreter. `syntax` errors are never caught by `try`.
type Fail:
    msg: String
    syntax: Bool

// Every Scheme value is an Int: value = index * 16 + tag.
// Integers, strings, symbols, pairs and procedures keep their payload in arenas.
let TNIL = 0
let TVOID = 1
let TBOOL = 2
let TINT = 3
let TSTR = 4
let TSYM = 5
let TPAIR = 6
let TLAM = 7
let TPRIM = 8
let NILV = 0
let VOIDV = 1
let FALSEV = 2
let TRUEV = 18
// Special-form keywords are interned first, so their symbol ids are fixed.
let NSPECIAL = 15
let S_QUOTE = 0
let S_IF = 1
let S_DEFINE = 2
let S_SET = 3
let S_LAMBDA = 4
let S_BEGIN = 5
let S_LET = 6
let S_LETSTAR = 7
let S_LETREC = 8
let S_COND = 9
let S_AND = 10
let S_OR = 11
let S_WHEN = 12
let S_UNLESS = 13
let S_TRY = 14
let S_ELSE = 15
let INT_MAX = 9223372036854775807
let INT_MIN = -9223372036854775807 - 1
let MAX_DEPTH = 10000
let BUILTIN_COST = 3

fn symv(id: Int) Int:
    return id * 16 + TSYM

fn bv(b: Bool) Int:
    if b:
        return TRUEV

    return FALSEV

fn one(x: Int) List[Int]:
    var r: List[Int] = []
    r.append(x)
    return r

fn two(x: Int, y: Int) List[Int]:
    var r: List[Int] = []
    r.append(x)
    r.append(y)
    return r

fn has(xs: List[Int], v: Int) Bool:
    for x in xs:
        if x == v:
            return true
    return false

fn add_ck(a: Int, b: Int) Int!Fail:
    if b > 0:
        if a > INT_MAX - b:
            return error(Fail(msg: "integer overflow", syntax: false))
    if b < 0:
        if a < INT_MIN - b:
            return error(Fail(msg: "integer overflow", syntax: false))
    return ok(a + b)

fn sub_ck(a: Int, b: Int) Int!Fail:
    if b < 0:
        if a > INT_MAX + b:
            return error(Fail(msg: "integer overflow", syntax: false))
    if b > 0:
        if a < INT_MIN + b:
            return error(Fail(msg: "integer overflow", syntax: false))
    return ok(a - b)

fn mul_ck(a: Int, b: Int) Int!Fail:
    if a == 0 or b == 0:
        return ok(0)

    var bad = false
    if a > 0 and b > 0:
        bad = a > INT_MAX / b
    if a > 0 and b < 0:
        bad = b < INT_MIN / a
    if a < 0 and b > 0:
        bad = a < INT_MIN / b
    if a < 0 and b < 0:
        bad = a < INT_MAX / b
    if bad:
        return error(Fail(msg: "integer overflow", syntax: false))

    return ok(a * b)

// Reader helpers on code points.
fn is_delim(c: Int) Bool:
    if c == -1 or c == 32 or c == 9 or c == 10 or c == 13:
        return true
    if c == 40 or c == 41 or c == 34 or c == 59:
        return true

    return false

fn is_int_text(cs: List[Int]) Bool:
    let n = cs.length()
    var i = 0
    if n > 0:
        if cs[0] == 45:
            i = 1
    if i >= n:
        return false

    while i < n:
        if cs[i] < 48 or cs[i] > 57:
            return false

        i += 1

    return true

// Parses text already known to match -?[0-9]+; none when it does not fit int64.
fn parse_num(cs: List[Int]) Int?:
    let n = cs.length()
    var i = 0
    var neg = false

    if cs[0] == 45:
        neg = true
        i = 1

    let limit = 922337203685477580
    var acc = 0

    while i < n:
        let d = cs[i] - 48

        if neg:
            if acc < -limit:
                return none
            if acc == -limit and d > 8:
                return none

            acc = acc * 10 - d
        else:
            if acc > limit:
                return none
            if acc == limit and d > 7:
                return none

            acc = acc * 10 + d

        i += 1

    return acc

fn serr(msg: String) Int!Fail:
    return error(Fail(msg: msg, syntax: true))

fn rterr(msg: String) Int!Fail:
    return error(Fail(msg: msg, syntax: false))

type M:
    src: List[Int]
    pos: Int
    ints: List[Int]
    strs: List[String]
    syms: List[String]
    symmap: Map[String, Int]
    gslot: List[Int]
    pcar: List[Int]
    pcdr: List[Int]
    lparams: List[Int]
    lbody: List[Int]
    lenv: List[Int]
    lname: List[Int]
    pnames: List[String]
    pmin: List[Int]
    pmax: List[Int]
    pgrp: List[Int]
    fparent: List[Int]
    fhead: List[Int]
    bsym: List[Int]
    bval: List[Int]
    bnext: List[Int]
    out: List[String]
    need_nl: Bool

impl M:
    // ---- arenas -------------------------------------------------------

    var fn mkint(n: Int) Int:
        self.ints.append(n)
        return (self.ints.length() - 1) * 16 + TINT

    fn ival(v: Int) Int:
        return self.ints[v / 16]

    var fn mkstr(s: String) Int:
        self.strs.append(s)
        return (self.strs.length() - 1) * 16 + TSTR

    fn sval(v: Int) String:
        return self.strs[v / 16].clone()

    fn symname(v: Int) String:
        return self.syms[v / 16].clone()

    var fn intern(name: String) Int:
        if let found = self.symmap.get(name):
            return found

        let nid = self.syms.length()
        self.syms.append(name.clone())
        self.gslot.append(-1)
        self.symmap.add(name, nid)
        return nid

    var fn cons(a: Int, d: Int) Int:
        self.pcar.append(a)
        self.pcdr.append(d)
        return (self.pcar.length() - 1) * 16 + TPAIR

    fn car(p: Int) Int:
        return self.pcar[p / 16]

    fn cdr(p: Int) Int:
        return self.pcdr[p / 16]

    var fn mklist(items: List[Int]) Int:
        var r = NILV
        var i = items.length() - 1

        while i >= 0:
            r = self.cons(items[i], r)
            i -= 1

        return r

    fn llen(v: Int) Int:
        var n = 0
        var cur = v

        while cur % 16 == TPAIR:
            n += 1
            cur = self.cdr(cur)

        if cur == NILV:
            return n

        return -1

    fn nth(v: Int, i: Int) Int:
        var cur = v
        for _k in 0..i:
            cur = self.cdr(cur)
        return self.car(cur)

    fn nthcdr(v: Int, i: Int) Int:
        var cur = v
        for _k in 0..i:
            cur = self.cdr(cur)
        return cur

    fn lastcell(v: Int) Int:
        var cur = v
        while self.cdr(cur) % 16 == TPAIR:
            cur = self.cdr(cur)
        return cur

    // ---- environments -------------------------------------------------
    // Frame 0 is the global frame; its bindings are reached through gslot.

    var fn newframe(parent: Int) Int:
        self.fparent.append(parent)
        self.fhead.append(-1)
        return self.fparent.length() - 1

    var fn addbind(sym: Int, v: Int, next: Int) Int:
        self.bsym.append(sym)
        self.bval.append(v)
        self.bnext.append(next)
        return self.bsym.length() - 1

    var fn bind(frame: Int, sym: Int, v: Int) Unit:
        if frame == 0:
            let g = self.gslot[sym]

            if g >= 0:
                self.bval[g] = v
                return

            let gb = self.addbind(sym, v, -1)
            self.gslot[sym] = gb
            return

        var b = self.fhead[frame]

        while b >= 0:
            if self.bsym[b] == sym:
                self.bval[b] = v
                return

            b = self.bnext[b]

        let nb = self.addbind(sym, v, self.fhead[frame])
        self.fhead[frame] = nb

    fn find(env: Int, sym: Int) Int:
        var f = env

        while f > 0:
            var b = self.fhead[f]

            while b >= 0:
                if self.bsym[b] == sym:
                    return b

                b = self.bnext[b]

            f = self.fparent[f]

        return self.gslot[sym]

    // ---- printing -----------------------------------------------------

    fn quote_str(s: String) String:
        var parts: List[String] = []
        parts.append("\"")

        for c in s.chars():
            if c == "\"":
                parts.append("\\\"")
            else if c == "\\":
                parts.append("\\\\")
            else if c == "\n":
                parts.append("\\n")
            else if c == "\t":
                parts.append("\\t")
            else:
                parts.append(c)

        parts.append("\"")
        return parts.join("")

    fn show(v: Int, wr: Bool) String:
        let t = v % 16
        if t == TNIL:
            return "()"
        if t == TVOID:
            return "#<void>"

        if t == TBOOL:
            if v == TRUEV:
                return "#t"

            return "#f"

        if t == TINT:
            let n = self.ival(v)
            return "{n}"

        if t == TSTR:
            let s = self.sval(v)
            if wr:
                return self.quote_str(s)

            return s

        if t == TSYM:
            return self.symname(v)

        if t == TLAM:
            let nm = self.lname[v / 16]
            if nm < 0:
                return "#<procedure>"

            let pn = self.symname(nm * 16 + TSYM)
            return "#<procedure {pn}>"

        if t == TPRIM:
            let bn = self.pnames[v / 16]
            return "#<builtin {bn}>"

        var parts: List[String] = []
        var cur = v

        while cur % 16 == TPAIR:
            parts.append(self.show(self.car(cur), wr))
            cur = self.cdr(cur)

        let body = parts.join(" ")
        if cur == NILV:
            return "({body})"

        let tailtxt = self.show(cur, wr)
        return "({body} . {tailtxt})"

    fn wrongf(name: String, kind: String, v: Int) Fail:
        let shown = self.show(v, true)
        return Fail(msg: "{name}: expected {kind}, got {shown}", syntax: false)

    fn want_int(name: String, v: Int) Int!Fail:
        if v % 16 != TINT:
            return error(self.wrongf(name, "integer", v))

        return ok(self.ival(v))

    fn want_str(name: String, v: Int) String!Fail:
        if v % 16 != TSTR:
            return error(self.wrongf(name, "string", v))

        return ok(self.sval(v))

    fn eqv(a: Int, b: Int) Bool:
        let ta = a % 16
        if ta != b % 16:
            return false
        if ta == TINT:
            return self.ival(a) == self.ival(b)
        if ta == TSTR or ta == TPAIR or ta == TLAM or ta == TPRIM:
            return false

        return a == b

    fn equal(a: Int, b: Int) Bool:
        var x = a
        var y = b

        while x % 16 == TPAIR and y % 16 == TPAIR:
            if not self.equal(self.car(x), self.car(y)):
                return false

            x = self.cdr(x)
            y = self.cdr(y)

        let tx = x % 16
        if tx != y % 16:
            return false
        if tx == TINT:
            return self.ival(x) == self.ival(y)
        if tx == TSTR:
            return self.sval(x) == self.sval(y)

        return x == y

    // ---- reader -------------------------------------------------------

    fn peekc() Int:
        if self.pos < self.src.length():
            return self.src[self.pos]

        return -1

    fn charat(i: Int) Int:
        if i < self.src.length():
            return self.src[i]

        return -1

    var fn skipws() Unit:
        while true:
            let c = self.peekc()

            if c == 32 or c == 9 or c == 10 or c == 13:
                self.pos += 1
            else if c == 59:
                while self.peekc() != -1 and self.peekc() != 10:
                    self.pos += 1
            else:
                return

    var fn read_datum() Int!Fail:
        self.skipws()

        let c = self.peekc()
        if c == -1:
            return serr("syntax error: unexpected end of input")

        if c == 40:
            self.pos += 1
            return self.read_list()

        if c == 41:
            return serr("syntax error: unexpected )")

        if c == 39:
            self.pos += 1

            let d = try self.read_datum()
            return ok(self.cons(symv(S_QUOTE), self.cons(d, NILV)))

        if c == 34:
            self.pos += 1
            return self.read_string()

        return self.read_atom()

    var fn read_list() Int!Fail:
        var head = NILV
        var last = NILV

        while true:
            self.skipws()

            let c = self.peekc()
            if c == -1:
                return serr("syntax error: unexpected end of input")

            if c == 41:
                self.pos += 1
                return ok(head)

            if c == 46 and is_delim(self.charat(self.pos + 1)):
                if head == NILV:
                    return serr("syntax error: bad dotted list")

                self.pos += 1
                self.skipws()

                let c2 = self.peekc()
                if c2 == -1:
                    return serr("syntax error: unexpected end of input")
                if c2 == 41:
                    return serr("syntax error: bad dotted list")

                let dd = try self.read_datum()
                self.skipws()

                let c3 = self.peekc()
                if c3 == -1:
                    return serr("syntax error: unexpected end of input")
                if c3 != 41:
                    return serr("syntax error: bad dotted list")

                self.pos += 1
                self.pcdr[last / 16] = dd
                return ok(head)

            let d = try self.read_datum()
            let cell = self.cons(d, NILV)

            if head == NILV:
                head = cell
            else:
                self.pcdr[last / 16] = cell

            last = cell

    var fn read_string() Int!Fail:
        var buf: List[Int] = []

        while true:
            let c = self.peekc()
            if c == -1:
                return serr("syntax error: unterminated string")

            if c == 34:
                self.pos += 1

                let text = from_scalars(buf).get("")
                return ok(self.mkstr(text))

            if c == 92:
                let esc = self.charat(self.pos + 1)
                if esc == -1:
                    return serr("syntax error: unterminated string")

                if esc == 110:
                    buf.append(10)
                else if esc == 116:
                    buf.append(9)
                else if esc == 92:
                    buf.append(92)
                else if esc == 34:
                    buf.append(34)
                else:
                    return serr("syntax error: bad escape")

                self.pos += 2
            else:
                buf.append(c)
                self.pos += 1

    var fn read_atom() Int!Fail:
        var atom: List[Int] = []

        while not is_delim(self.peekc()):
            atom.append(self.peekc())
            self.pos += 1

        let text = from_scalars(atom).get("")

        if atom[0] == 35:
            if text == "#t":
                return ok(TRUEV)
            if text == "#f":
                return ok(FALSEV)

            return serr("syntax error: bad token: {text}")

        if atom.length() == 1 and atom[0] == 46:
            return serr("syntax error: unexpected .")

        if is_int_text(atom):
            if let nv = parse_num(atom):
                return ok(self.mkint(nv))

            return serr("syntax error: integer out of range")

        let sid = self.intern(text)
        return ok(symv(sid))

    // ---- evaluation helpers ------------------------------------------

    var fn badform(sym: Int) Int!Fail:
        let nm = self.symname(sym * 16 + TSYM)
        return serr("syntax error: bad form: {nm}")

    // Validates a parameter list and creates a closure.
    var fn mklambda(params: Int, body: Int, env: Int, name: Int, form: Int) Int!Fail:
        var seen: List[Int] = []
        var p = params

        while p % 16 == TPAIR:
            let s = self.car(p)
            if s % 16 != TSYM:
                return self.badform(form)
            if has(seen, s):
                return self.badform(form)

            seen.append(s)
            p = self.cdr(p)

        if p != NILV:
            if p % 16 != TSYM:
                return self.badform(form)
            if has(seen, p):
                return self.badform(form)

        self.lparams.append(params)
        self.lbody.append(body)
        self.lenv.append(env)
        self.lname.append(name)
        return ok((self.lbody.length() - 1) * 16 + TLAM)

    // Creates the call frame for closure f applied to args; evaluates all but the last body expression.
    var fn enter(f: Int, args: List[Int], nd: Int) Int!Fail:
        let li = f / 16
        let nm = self.lname[li]
        var np = 0
        var p = self.lparams[li]

        while p % 16 == TPAIR:
            np += 1
            p = self.cdr(p)

        let rest = p != NILV
        let got = args.length()

        if got < np or (not rest and got > np):
            var expect = "{np}"
            if rest:
                expect = "at least {np}"

            var shownm = "lambda"
            if nm >= 0:
                shownm = self.symname(nm * 16 + TSYM).clone()
            return rterr(
                "wrong number of arguments to {shownm}: expected {expect}, got {got}"
            )

        let fr = self.newframe(self.lenv[li])
        var pp = self.lparams[li]
        var k = 0

        while pp % 16 == TPAIR:
            self.bind(fr, self.car(pp) / 16, args[k])
            k += 1
            pp = self.cdr(pp)

        if pp != NILV:
            var restl: List[Int] = []
            var j = k

            while j < got:
                restl.append(args[j])
                j += 1

            let rl = self.mklist(restl)
            self.bind(fr, pp / 16, rl)

        let _lc = try self.prefix(self.lbody[li], fr, nd)
        return ok(fr)

    // Evaluates every element of lst except the last (non-tail); returns the last cell.
    var fn prefix(lst: Int, en: Int, dep: Int) Int!Fail:
        var cur = lst

        while self.cdr(cur) % 16 == TPAIR:
            let _v = try self.evalx(self.car(cur), en, dep, false)
            cur = self.cdr(cur)

        return ok(cur)

    // Calls a procedure from a builtin or handler: callee depth is one more than dep.
    var fn call_proc(f: Int, args: List[Int], dep: Int) Int!Fail:
        if f % 16 == TLAM:
            // Builtin-mediated calls cost extra depth: each one uses several native frames, so
            // this keeps runaway builtin recursion within the native stack budget.
            let nd = dep + 1 + BUILTIN_COST
            if nd > MAX_DEPTH:
                return rterr("recursion limit exceeded")

            let fr = try self.enter(f, args, nd)
            let body = self.lbody[f / 16]
            return self.evalx(self.car(self.lastcell(body)), fr, nd, true)

        if f % 16 == TPRIM:
            return self.prim(f / 16, args, dep)

        let shown = self.show(f, true)
        return rterr("not a procedure: {shown}")

    // ---- the evaluator ------------------------------------------------
    // tail: whether x is in tail position of the current body. Depth `dep` is the number of
    // non-tail procedure entries so far; a call in non-tail position enters at dep + 1.

    var fn evalx(x: Int, env: Int, d: Int, tail: Bool) Int!Fail:
        var e = x
        var en = env
        var dep = d
        var tl = tail

        while true:
            let t = e % 16

            if t == TSYM:
                let b = self.find(en, e / 16)

                if b < 0:
                    let nm = self.symname(e)
                    return rterr("unbound variable: {nm}")

                return ok(self.bval[b])

            if t != TPAIR:
                if e == NILV:
                    return serr("syntax error: empty application")

                return ok(e)

            let head = self.car(e)
            var ready = false
            var fv = NILV
            var argl: List[Int] = []

            if head % 16 == TSYM and head / 16 < NSPECIAL:
                let s = head / 16

                if s == S_QUOTE:
                    if self.llen(e) != 2:
                        return self.badform(s)

                    return ok(self.nth(e, 1))

                if s == S_IF:
                    let n = self.llen(e)
                    if n != 3 and n != 4:
                        return self.badform(s)

                    let tv = try self.evalx(self.nth(e, 1), en, dep, false)

                    if tv != FALSEV:
                        e = self.nth(e, 2)
                        continue

                    if n == 4:
                        e = self.nth(e, 3)
                        continue

                    return ok(VOIDV)

                if s == S_DEFINE:
                    let n = self.llen(e)
                    if n < 3:
                        return self.badform(s)

                    let target = self.nth(e, 1)

                    if target % 16 == TPAIR:
                        let fsym = self.car(target)
                        if fsym % 16 != TSYM:
                            return self.badform(s)

                        let lam = try self.mklambda(
                            self.cdr(target), self.nthcdr(e, 2), en, fsym / 16, s
                        )
                        self.bind(en, fsym / 16, lam)
                        return ok(VOIDV)

                    if target % 16 != TSYM or n != 3:
                        return self.badform(s)

                    let ex = self.nth(e, 2)
                    let v = try self.evalx(ex, en, dep, false)
                    if ex % 16 == TPAIR and self.car(ex) == symv(S_LAMBDA):
                        self.lname[v / 16] = target / 16
                    self.bind(en, target / 16, v)
                    return ok(VOIDV)

                if s == S_SET:
                    if self.llen(e) != 3:
                        return self.badform(s)

                    let target = self.nth(e, 1)
                    if target % 16 != TSYM:
                        return self.badform(s)

                    let v = try self.evalx(self.nth(e, 2), en, dep, false)
                    let b = self.find(en, target / 16)

                    if b < 0:
                        let nm = self.symname(target)
                        return rterr("unbound variable: {nm}")

                    self.bval[b] = v
                    return ok(VOIDV)

                if s == S_LAMBDA:
                    if self.llen(e) < 3:
                        return self.badform(s)

                    let lam = try self.mklambda(
                        self.nth(e, 1), self.nthcdr(e, 2), en, -1, s
                    )
                    return ok(lam)

                if s == S_BEGIN:
                    if self.llen(e) < 0:
                        return self.badform(s)
                    if self.cdr(e) == NILV:
                        return ok(VOIDV)

                    let lc = try self.prefix(self.cdr(e), en, dep)
                    e = self.car(lc)
                    continue

                if s == S_LET:
                    let n = self.llen(e)
                    if n < 3:
                        return self.badform(s)

                    let second = self.nth(e, 1)

                    if second % 16 == TSYM:
                        // named let: the loop procedure lives in its own frame
                        if n < 4:
                            return self.badform(s)

                        let bnds = self.nth(e, 2)
                        if self.llen(bnds) < 0:
                            return self.badform(s)

                        var vars: List[Int] = []
                        var cur = bnds

                        while cur != NILV:
                            let b = self.car(cur)
                            if self.llen(b) != 2 or self.car(b) % 16 != TSYM:
                                return self.badform(s)

                            vars.append(self.car(b))

                            let iv = try self.evalx(self.nth(b, 1), en, dep, false)
                            argl.append(iv)
                            cur = self.cdr(cur)

                        let pl = self.mklist(vars)
                        let f1 = self.newframe(en)
                        let lam = try self.mklambda(
                            pl, self.nthcdr(e, 3), f1, second / 16, s
                        )
                        self.bind(f1, second / 16, lam)
                        fv = lam
                        ready = true
                    else:
                        if self.llen(second) < 0:
                            return self.badform(s)

                        let f2 = self.newframe(en)
                        var syms: List[Int] = []
                        var vals: List[Int] = []
                        var cur = second

                        while cur != NILV:
                            let b = self.car(cur)
                            if self.llen(b) != 2 or self.car(b) % 16 != TSYM:
                                return self.badform(s)

                            syms.append(self.car(b) / 16)

                            let iv = try self.evalx(self.nth(b, 1), en, dep, false)
                            vals.append(iv)
                            cur = self.cdr(cur)

                        var k = 0

                        while k < syms.length():
                            self.bind(f2, syms[k], vals[k])
                            k += 1

                        let lc = try self.prefix(self.nthcdr(e, 2), f2, dep)
                        e = self.car(lc)
                        en = f2
                        continue

                if s == S_LETSTAR or s == S_LETREC:
                    if self.llen(e) < 3:
                        return self.badform(s)

                    let bl = self.nth(e, 1)
                    if self.llen(bl) < 0:
                        return self.badform(s)

                    let f3 = self.newframe(en)
                    var cur = bl

                    while cur != NILV:
                        let b = self.car(cur)
                        if self.llen(b) != 2 or self.car(b) % 16 != TSYM:
                            return self.badform(s)

                        let iv = try self.evalx(self.nth(b, 1), f3, dep, false)
                        self.bind(f3, self.car(b) / 16, iv)
                        cur = self.cdr(cur)

                    let lc = try self.prefix(self.nthcdr(e, 2), f3, dep)
                    e = self.car(lc)
                    en = f3
                    continue

                if s == S_COND:
                    if self.llen(e) < 0:
                        return self.badform(s)
                    if self.cdr(e) == NILV:
                        return ok(VOIDV)

                    let clause = self.car(self.cdr(e))
                    let restcl = self.cdr(self.cdr(e))
                    if clause % 16 != TPAIR or self.llen(clause) < 1:
                        return self.badform(s)

                    let tst = self.car(clause)

                    if tst == symv(S_ELSE):
                        if restcl != NILV or self.llen(clause) < 2:
                            return self.badform(s)

                        let elc = try self.prefix(self.cdr(clause), en, dep)
                        e = self.car(elc)
                        continue

                    let tv = try self.evalx(tst, en, dep, false)

                    if tv != FALSEV:
                        if self.llen(clause) == 1:
                            return ok(tv)

                        let blc = try self.prefix(self.cdr(clause), en, dep)
                        e = self.car(blc)
                        continue

                    e = self.cons(symv(S_COND), restcl)
                    continue

                if s == S_AND:
                    if self.llen(e) < 0:
                        return self.badform(s)
                    if self.cdr(e) == NILV:
                        return ok(TRUEV)

                    var cur = self.cdr(e)

                    while self.cdr(cur) != NILV:
                        let av = try self.evalx(self.car(cur), en, dep, false)
                        if av == FALSEV:
                            return ok(FALSEV)

                        cur = self.cdr(cur)

                    e = self.car(cur)
                    continue

                if s == S_OR:
                    if self.llen(e) < 0:
                        return self.badform(s)
                    if self.cdr(e) == NILV:
                        return ok(FALSEV)

                    var cur = self.cdr(e)

                    while self.cdr(cur) != NILV:
                        let ov = try self.evalx(self.car(cur), en, dep, false)
                        if ov != FALSEV:
                            return ok(ov)

                        cur = self.cdr(cur)

                    e = self.car(cur)
                    continue

                if s == S_WHEN or s == S_UNLESS:
                    if self.llen(e) < 3:
                        return self.badform(s)

                    let wv = try self.evalx(self.nth(e, 1), en, dep, false)
                    var go = wv != FALSEV
                    if s == S_UNLESS:
                        go = wv == FALSEV
                    if not go:
                        return ok(VOIDV)

                    let wlc = try self.prefix(self.nthcdr(e, 2), en, dep)
                    e = self.car(wlc)
                    continue

                if s == S_TRY:
                    if self.llen(e) != 3:
                        return self.badform(s)

                    let r = self.evalx(self.nth(e, 1), en, dep, false)

                    if r.is_error():
                        let ferr = r.err()
                        if ferr.syntax:
                            return error(ferr)

                        let hv = try self.evalx(self.nth(e, 2), en, dep, false)
                        let mv = self.mkstr(ferr.msg)
                        return self.call_proc(hv, one(mv), dep)

                    return r

            // ordinary application
            if not ready:
                if self.llen(e) < 0:
                    return serr("syntax error: bad application")

                fv = try self.evalx(head, en, dep, false)

                var cur = self.cdr(e)

                while cur != NILV:
                    let av = try self.evalx(self.car(cur), en, dep, false)
                    argl.append(av)
                    cur = self.cdr(cur)

            if fv % 16 == TLAM:
                var nd = dep + 1
                if tl:
                    nd = dep
                if nd > MAX_DEPTH:
                    return rterr("recursion limit exceeded")

                let fr = try self.enter(fv, argl, nd)
                e = self.car(self.lastcell(self.lbody[fv / 16]))
                en = fr
                dep = nd
                tl = true
                continue

            if fv % 16 == TPRIM:
                return self.prim(fv / 16, argl, dep)

            let shown = self.show(fv, true)
            return rterr("not a procedure: {shown}")

    // ---- builtins -----------------------------------------------------

    var fn emit(s: String) Unit:
        if s.length() > 0:
            self.need_nl = s.get(-1) != "\n"
            self.out.append(s)

    // Map/for-each core: collect true builds a list of results, false returns void.
    var fn map_core(name: String, args: List[Int], dep: Int, collect: Bool) Int!Fail:
        let f = args[0]
        if f % 16 != TLAM and f % 16 != TPRIM:
            return error(self.wrongf(name, "procedure", f))

        var curs: List[Int] = []
        var k = 1

        while k < args.length():
            if self.llen(args[k]) < 0:
                return error(self.wrongf(name, "list", args[k]))

            curs.append(args[k])
            k += 1

        var results: List[Int] = []

        while true:
            var stop = false
            for j in 0..curs.length():
                if curs[j] == NILV:
                    stop = true
            if stop:
                break

            var cargs: List[Int] = []

            for j in 0..curs.length():
                cargs.append(self.car(curs[j]))
                curs[j] = self.cdr(curs[j])

            let rv = try self.call_proc(f, cargs, dep)
            if collect:
                results.append(rv)

        if collect:
            return ok(self.mklist(results))

        return ok(VOIDV)

    var fn msort(items: List[Int], less: Int, dep: Int) List[Int]!Fail:
        let n = items.length()
        if n <= 1:
            return ok(items.clone())

        let half = n / 2
        var left: List[Int] = []
        var right: List[Int] = []
        for i in 0..half:
            left.append(items[i])
        for i in half..n:
            right.append(items[i])

        let ls = try self.msort(left, less, dep)
        let rs = try self.msort(right, less, dep)
        var out: List[Int] = []
        var i = 0
        var j = 0

        while i < ls.length() and j < rs.length():
            let pick = try self.call_proc(less, two(rs[j], ls[i]), dep)

            if pick != FALSEV:
                out.append(rs[j])
                j += 1
            else:
                out.append(ls[i])
                i += 1

        while i < ls.length():
            out.append(ls[i])
            i += 1

        while j < rs.length():
            out.append(rs[j])
            j += 1

        return ok(out)

    var fn prim(id: Int, args: List[Int], dep: Int) Int!Fail:
        let name = self.pnames[id].clone()
        let n = args.length()
        let lo = self.pmin[id]
        let hi = self.pmax[id]

        if n < lo or (hi >= 0 and n > hi):
            var expect = "{lo}"

            if hi < 0:
                expect = "at least {lo}"
            else if lo != hi:
                expect = "{lo} to {hi}"

            return rterr(
                "wrong number of arguments to {name}: expected {expect}, got {n}"
            )

        let grp = self.pgrp[id]
        if grp == 0:
            return self.prim_num(name, args, dep)
        if grp == 1:
            return self.prim_lst(name, args, dep)
        if grp == 2:
            return self.prim_hof(name, args, dep)
        if grp == 3:
            return self.prim_str(name, args, dep)

        return self.prim_misc(name, args, dep)

    var fn prim_num(name: String, args: List[Int], dep: Int) Int!Fail:
        let n = args.length()

        if name == "+":
            var acc = 0

            for i in 0..n:
                let a = try self.want_int(name, args[i])
                acc = try add_ck(acc, a)

            return ok(self.mkint(acc))

        if name == "-":
            if n == 1:
                let a = try self.want_int(name, args[0])
                if a == INT_MIN:
                    return rterr("integer overflow")

                return ok(self.mkint(-a))

            var acc = try self.want_int(name, args[0])

            for i in 1..n:
                let a = try self.want_int(name, args[i])
                acc = try sub_ck(acc, a)

            return ok(self.mkint(acc))

        if name == "*":
            var acc = 1

            for i in 0..n:
                let a = try self.want_int(name, args[i])
                acc = try mul_ck(acc, a)

            return ok(self.mkint(acc))

        if name == "quotient" or name == "remainder" or name == "modulo":
            let a = try self.want_int(name, args[0])
            let b = try self.want_int(name, args[1])
            if b == 0:
                return rterr("division by zero")

            if name == "quotient":
                if b == -1 and a == INT_MIN:
                    return rterr("integer overflow")

                return ok(self.mkint(a / b))

            if b == -1:
                return ok(self.mkint(0))

            var r = a % b
            if name == "modulo":
                if r != 0 and ((r < 0) != (b < 0)):
                    r = r + b
            return ok(self.mkint(r))

        if name == "abs":
            let a = try self.want_int(name, args[0])
            if a == INT_MIN:
                return rterr("integer overflow")
            if a < 0:
                return ok(self.mkint(-a))

            return ok(self.mkint(a))

        if name == "min" or name == "max":
            var vals: List[Int] = []

            for i in 0..n:
                let a = try self.want_int(name, args[i])
                vals.append(a)

            var best = vals[0]

            for i in 1..n:
                if name == "min" and vals[i] < best:
                    best = vals[i]
                if name == "max" and vals[i] > best:
                    best = vals[i]

            return ok(self.mkint(best))

        if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
            var vals: List[Int] = []

            for i in 0..n:
                let a = try self.want_int(name, args[i])
                vals.append(a)

            var all = true

            for i in 0..n - 1:
                let a = vals[i]
                let b = vals[i + 1]
                var good = false
                if name == "=":
                    good = a == b
                if name == "<":
                    good = a < b
                if name == ">":
                    good = a > b
                if name == "<=":
                    good = a <= b
                if name == ">=":
                    good = a >= b
                if not good:
                    all = false

            return ok(bv(all))

        if name == "zero?":
            let a = try self.want_int(name, args[0])
            return ok(bv(a == 0))

        if name == "even?":
            let a = try self.want_int(name, args[0])
            return ok(bv(a % 2 == 0))

        if name == "odd?":
            let a = try self.want_int(name, args[0])
            return ok(bv(a % 2 != 0))

        return rterr("unknown builtin: {name}")

    var fn prim_lst(name: String, args: List[Int], dep: Int) Int!Fail:
        let n = args.length()
        let a0 = args.get(0, NILV)
        if name == "not":
            return ok(bv(a0 == FALSEV))
        if name == "null?":
            return ok(bv(a0 == NILV))
        if name == "pair?":
            return ok(bv(a0 % 16 == TPAIR))
        if name == "list?":
            return ok(bv(self.llen(a0) >= 0))
        if name == "number?":
            return ok(bv(a0 % 16 == TINT))
        if name == "string?":
            return ok(bv(a0 % 16 == TSTR))
        if name == "symbol?":
            return ok(bv(a0 % 16 == TSYM))
        if name == "boolean?":
            return ok(bv(a0 % 16 == TBOOL))
        if name == "procedure?":
            return ok(bv(a0 % 16 == TLAM or a0 % 16 == TPRIM))
        if name == "eq?":
            return ok(bv(self.eqv(a0, args[1])))
        if name == "equal?":
            return ok(bv(self.equal(a0, args[1])))

        // pairs and lists
        if name == "cons":
            return ok(self.cons(a0, args[1]))

        if name == "car" or name == "cdr":
            if a0 % 16 != TPAIR:
                return error(self.wrongf(name, "pair", a0))
            if name == "car":
                return ok(self.car(a0))

            return ok(self.cdr(a0))

        if name == "cadr" or name == "cddr" or name == "caddr":
            var cur = a0
            var idx = name.length() - 2

            while idx >= 1:
                let op = name.get(idx)
                if cur % 16 != TPAIR:
                    return error(self.wrongf(name, "pair", cur))

                if op == "a":
                    cur = self.car(cur)
                else:
                    cur = self.cdr(cur)

                idx -= 1

            return ok(cur)

        if name == "set-car!":
            if a0 % 16 != TPAIR:
                return error(self.wrongf(name, "pair", a0))

            self.pcar[a0 / 16] = args[1]
            return ok(VOIDV)

        if name == "set-cdr!":
            if a0 % 16 != TPAIR:
                return error(self.wrongf(name, "pair", a0))

            self.pcdr[a0 / 16] = args[1]
            return ok(VOIDV)

        if name == "list":
            return ok(self.mklist(args))

        if name == "length":
            let ln = self.llen(a0)
            if ln < 0:
                return error(self.wrongf(name, "list", a0))

            return ok(self.mkint(ln))

        if name == "append":
            if n == 0:
                return ok(NILV)

            var items: List[Int] = []
            var i = 0

            while i < n - 1:
                let lst = args[i]
                if self.llen(lst) < 0:
                    return error(self.wrongf(name, "list", lst))

                var cur = lst

                while cur != NILV:
                    items.append(self.car(cur))
                    cur = self.cdr(cur)

                i += 1

            var r = args[n - 1]
            var j = items.length() - 1

            while j >= 0:
                r = self.cons(items[j], r)
                j -= 1

            return ok(r)

        if name == "reverse":
            if self.llen(a0) < 0:
                return error(self.wrongf(name, "list", a0))

            var r = NILV
            var cur = a0

            while cur != NILV:
                r = self.cons(self.car(cur), r)
                cur = self.cdr(cur)

            return ok(r)

        if name == "list-ref":
            let k = try self.want_int(name, args[1])
            if k < 0:
                return rterr("list-ref: index out of range")

            var cur = a0
            var i = 0

            while i < k:
                if cur % 16 != TPAIR:
                    return rterr("list-ref: index out of range")

                cur = self.cdr(cur)
                i += 1

            if cur % 16 != TPAIR:
                return rterr("list-ref: index out of range")

            return ok(self.car(cur))

        if name == "list-tail":
            let k = try self.want_int(name, args[1])
            if k < 0:
                return rterr("list-tail: index out of range")

            var cur = a0
            var i = 0

            while i < k:
                if cur % 16 != TPAIR:
                    return rterr("list-tail: index out of range")

                cur = self.cdr(cur)
                i += 1

            return ok(cur)

        if name == "range":
            let lo2 = try self.want_int(name, args[0])
            let hi2 = try self.want_int(name, args[1])
            var r = NILV
            var i = hi2 - 1

            while i >= lo2:
                r = self.cons(self.mkint(i), r)
                i -= 1

            return ok(r)

        if name == "assoc":
            var cur = args[1]

            while cur != NILV:
                if cur % 16 != TPAIR:
                    return error(self.wrongf(name, "list", args[1]))

                let elem = self.car(cur)
                if elem % 16 != TPAIR:
                    return error(self.wrongf(name, "pair", elem))
                if self.equal(a0, self.car(elem)):
                    return ok(elem)

                cur = self.cdr(cur)

            return ok(FALSEV)

        if name == "member":
            var cur = args[1]

            while cur != NILV:
                if cur % 16 != TPAIR:
                    return error(self.wrongf(name, "list", args[1]))
                if self.equal(a0, self.car(cur)):
                    return ok(cur)

                cur = self.cdr(cur)

            return ok(FALSEV)

        return rterr("unknown builtin: {name}")

    var fn prim_hof(name: String, args: List[Int], dep: Int) Int!Fail:
        let n = args.length()
        let a0 = args.get(0, NILV)
        if name == "map":
            return self.map_core(name, args, dep, true)
        if name == "for-each":
            return self.map_core(name, args, dep, false)

        if name == "filter":
            if a0 % 16 != TLAM and a0 % 16 != TPRIM:
                return error(self.wrongf(name, "procedure", a0))
            if self.llen(args[1]) < 0:
                return error(self.wrongf(name, "list", args[1]))

            var out: List[Int] = []
            var cur = args[1]

            while cur != NILV:
                let x = self.car(cur)
                let keep = try self.call_proc(a0, one(x), dep)
                if keep != FALSEV:
                    out.append(x)
                cur = self.cdr(cur)

            return ok(self.mklist(out))

        if name == "fold":
            if a0 % 16 != TLAM and a0 % 16 != TPRIM:
                return error(self.wrongf(name, "procedure", a0))
            if self.llen(args[2]) < 0:
                return error(self.wrongf(name, "list", args[2]))

            var acc = args[1]
            var cur = args[2]

            while cur != NILV:
                acc = try self.call_proc(a0, two(acc, self.car(cur)), dep)
                cur = self.cdr(cur)

            return ok(acc)

        if name == "foldr":
            if a0 % 16 != TLAM and a0 % 16 != TPRIM:
                return error(self.wrongf(name, "procedure", a0))
            if self.llen(args[2]) < 0:
                return error(self.wrongf(name, "list", args[2]))

            var items: List[Int] = []
            var cur = args[2]

            while cur != NILV:
                items.append(self.car(cur))
                cur = self.cdr(cur)

            var acc = args[1]
            var i = items.length() - 1

            while i >= 0:
                acc = try self.call_proc(a0, two(items[i], acc), dep)
                i -= 1

            return ok(acc)

        if name == "apply":
            if a0 % 16 != TLAM and a0 % 16 != TPRIM:
                return error(self.wrongf(name, "procedure", a0))

            let lastarg = args[n - 1]
            if self.llen(lastarg) < 0:
                return error(self.wrongf(name, "list", lastarg))

            var cargs: List[Int] = []
            var i = 1

            while i < n - 1:
                cargs.append(args[i])
                i += 1

            var cur = lastarg

            while cur != NILV:
                cargs.append(self.car(cur))
                cur = self.cdr(cur)

            return self.call_proc(a0, cargs, dep)

        if name == "sort":
            if args[1] % 16 != TLAM and args[1] % 16 != TPRIM:
                return error(self.wrongf(name, "procedure", args[1]))
            if self.llen(a0) < 0:
                return error(self.wrongf(name, "list", a0))

            var items: List[Int] = []
            var cur = a0

            while cur != NILV:
                items.append(self.car(cur))
                cur = self.cdr(cur)

            let sorted = try self.msort(items, args[1], dep)
            return ok(self.mklist(sorted))

        return rterr("unknown builtin: {name}")

    var fn prim_str(name: String, args: List[Int], dep: Int) Int!Fail:
        let n = args.length()
        let a0 = args.get(0, NILV)

        if name == "string-length":
            let s = try self.want_str(name, a0)
            return ok(self.mkint(s.length()))

        if name == "string-append":
            var parts: List[String] = []

            for i in 0..n:
                let s = try self.want_str(name, args[i])
                parts.append(s)

            return ok(self.mkstr(parts.join("")))

        if name == "substring":
            let s = try self.want_str(name, a0)
            let st = try self.want_int(name, args[1])
            let en2 = try self.want_int(name, args[2])
            if st < 0 or st > en2 or en2 > s.length():
                return rterr("substring: index out of range")

            let piece = s.slice(st, en2).get("")
            return ok(self.mkstr(piece))

        if name == "string-ref":
            let s = try self.want_str(name, a0)
            let k = try self.want_int(name, args[1])
            if k < 0 or k >= s.length():
                return rterr("string-ref: index out of range")

            return ok(self.mkstr(s.get(k)))

        if name == "string=?" or name == "string<?":
            let s = try self.want_str(name, a0)
            let t = try self.want_str(name, args[1])
            if name == "string=?":
                return ok(bv(s == t))

            return ok(bv(s.compare(t) < 0))

        if name == "string-upcase" or name == "string-downcase":
            let s = try self.want_str(name, a0)
            var parts: List[String] = []

            for c in s.chars():
                let code = c.scalar_at(0)
                var outc = c
                if name == "string-upcase" and code >= 97 and code <= 122:
                    outc = from_scalars(one(code - 32)).get("")
                if name == "string-downcase" and code >= 65 and code <= 90:
                    outc = from_scalars(one(code + 32)).get("")
                parts.append(outc)

            return ok(self.mkstr(parts.join("")))

        if name == "string->number":
            let s = try self.want_str(name, a0)
            let cs = s.scalar_values()
            if is_int_text(cs):
                if let nv = parse_num(cs):
                    return ok(self.mkint(nv))
            return ok(FALSEV)

        if name == "number->string":
            let a = try self.want_int(name, a0)
            return ok(self.mkstr("{a}"))

        if name == "string->symbol":
            let s = try self.want_str(name, a0)
            return ok(symv(self.intern(s)))

        if name == "symbol->string":
            if a0 % 16 != TSYM:
                return error(self.wrongf(name, "symbol", a0))

            return ok(self.mkstr(self.symname(a0)))

        if name == "string->list":
            let s = try self.want_str(name, a0)
            var items: List[Int] = []
            for c in s.chars():
                items.append(self.mkstr(c))
            return ok(self.mklist(items))

        if name == "list->string":
            if self.llen(a0) < 0:
                return error(self.wrongf(name, "list", a0))

            var parts: List[String] = []
            var cur = a0

            while cur != NILV:
                let s = try self.want_str(name, self.car(cur))
                parts.append(s)
                cur = self.cdr(cur)

            return ok(self.mkstr(parts.join("")))

        if name == "string-join":
            if self.llen(a0) < 0:
                return error(self.wrongf(name, "list", a0))

            let sep = try self.want_str(name, args[1])
            var parts: List[String] = []
            var cur = a0

            while cur != NILV:
                let s = try self.want_str(name, self.car(cur))
                parts.append(s)
                cur = self.cdr(cur)

            return ok(self.mkstr(parts.join(sep)))

        if name == "string-split":
            let s = try self.want_str(name, a0)
            let sep = try self.want_str(name, args[1])
            if sep.length() != 1:
                return rterr("string-split: separator must be one character")

            var items: List[Int] = []
            var cur: List[String] = []

            for c in s.chars():
                if c == sep:
                    items.append(self.mkstr(cur.join("")))
                    cur = []
                else:
                    cur.append(c)

            items.append(self.mkstr(cur.join("")))
            return ok(self.mklist(items))

        if name == "string-contains?":
            let s = try self.want_str(name, a0)
            let sub = try self.want_str(name, args[1])
            return ok(bv(s.contains(sub)))

        return rterr("unknown builtin: {name}")

    var fn prim_misc(name: String, args: List[Int], dep: Int) Int!Fail:
        let n = args.length()
        let a0 = args.get(0, NILV)

        if name == "display":
            let shown = self.show(a0, false)
            self.emit(shown)
            return ok(VOIDV)

        if name == "write":
            let shown = self.show(a0, true)
            self.emit(shown)
            return ok(VOIDV)

        if name == "newline":
            self.emit("\n")
            return ok(VOIDV)

        if name == "void":
            return ok(VOIDV)

        if name == "error":
            if a0 % 16 != TSTR:
                return error(self.wrongf(name, "string", a0))

            var msg = self.sval(a0)
            var i = 1

            while i < n:
                let shown = self.show(args[i], true)
                msg = "{msg} {shown}"
                i += 1

            return rterr(msg)

        return rterr("unknown builtin: {name}")

    var fn defp(name: String, lo: Int, hi: Int, grp: Int) Unit:
        let pid = self.pnames.length()
        self.pgrp.append(grp)
        self.pnames.append(name.clone())
        self.pmin.append(lo)
        self.pmax.append(hi)

        let sid = self.intern(name)
        self.bind(0, sid, pid * 16 + TPRIM)

    var fn setup() Unit:
        let _root = self.newframe(-1)
        let specials: List[String] = [
            "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec",
            "cond", "and", "or", "when", "unless", "try", "else"
        ]
        for nm in specials:
            let _sid = self.intern(nm)
        self.defp("+", 0, -1, 0)
        self.defp("-", 1, -1, 0)
        self.defp("*", 0, -1, 0)
        self.defp("quotient", 2, 2, 0)
        self.defp("remainder", 2, 2, 0)
        self.defp("modulo", 2, 2, 0)
        self.defp("abs", 1, 1, 0)
        self.defp("min", 1, -1, 0)
        self.defp("max", 1, -1, 0)
        self.defp("=", 2, -1, 0)
        self.defp("<", 2, -1, 0)
        self.defp(">", 2, -1, 0)
        self.defp("<=", 2, -1, 0)
        self.defp(">=", 2, -1, 0)
        self.defp("zero?", 1, 1, 0)
        self.defp("even?", 1, 1, 0)
        self.defp("odd?", 1, 1, 0)
        self.defp("not", 1, 1, 1)
        self.defp("null?", 1, 1, 1)
        self.defp("pair?", 1, 1, 1)
        self.defp("list?", 1, 1, 1)
        self.defp("number?", 1, 1, 1)
        self.defp("string?", 1, 1, 1)
        self.defp("symbol?", 1, 1, 1)
        self.defp("boolean?", 1, 1, 1)
        self.defp("procedure?", 1, 1, 1)
        self.defp("eq?", 2, 2, 1)
        self.defp("equal?", 2, 2, 1)
        self.defp("cons", 2, 2, 1)
        self.defp("car", 1, 1, 1)
        self.defp("cdr", 1, 1, 1)
        self.defp("cadr", 1, 1, 1)
        self.defp("cddr", 1, 1, 1)
        self.defp("caddr", 1, 1, 1)
        self.defp("set-car!", 2, 2, 1)
        self.defp("set-cdr!", 2, 2, 1)
        self.defp("list", 0, -1, 1)
        self.defp("length", 1, 1, 1)
        self.defp("append", 0, -1, 1)
        self.defp("reverse", 1, 1, 1)
        self.defp("list-ref", 2, 2, 1)
        self.defp("list-tail", 2, 2, 1)
        self.defp("range", 2, 2, 1)
        self.defp("assoc", 2, 2, 1)
        self.defp("member", 2, 2, 1)
        self.defp("map", 2, -1, 2)
        self.defp("for-each", 2, -1, 2)
        self.defp("filter", 2, 2, 2)
        self.defp("fold", 3, 3, 2)
        self.defp("foldr", 3, 3, 2)
        self.defp("apply", 2, -1, 2)
        self.defp("sort", 2, 2, 2)
        self.defp("string-length", 1, 1, 3)
        self.defp("string-append", 0, -1, 3)
        self.defp("substring", 3, 3, 3)
        self.defp("string-ref", 2, 2, 3)
        self.defp("string=?", 2, 2, 3)
        self.defp("string<?", 2, 2, 3)
        self.defp("string-upcase", 1, 1, 3)
        self.defp("string-downcase", 1, 1, 3)
        self.defp("string->number", 1, 1, 3)
        self.defp("number->string", 1, 1, 3)
        self.defp("string->symbol", 1, 1, 3)
        self.defp("symbol->string", 1, 1, 3)
        self.defp("string->list", 1, 1, 3)
        self.defp("list->string", 1, 1, 3)
        self.defp("string-join", 2, 2, 3)
        self.defp("string-split", 2, 2, 3)
        self.defp("string-contains?", 2, 2, 3)
        self.defp("display", 1, 1, 4)
        self.defp("write", 1, 1, 4)
        self.defp("newline", 0, 0, 4)
        self.defp("void", 0, 0, 4)
        self.defp("error", 1, -1, 4)

    // Runs every top-level form; returns the uncaught error message, or "" on success.
    var fn run() String:
        while true:
            self.skipws()
            if self.pos >= self.src.length():
                return ""

            let rd = self.read_datum()
            if rd.is_error():
                return rd.err().msg

            let form = rd.get(NILV)
            let rv = self.evalx(form, 0, 0, false)
            if rv.is_error():
                return rv.err().msg

export fn main() Int:
    let data = read_all(stdin())
    var text = ""
    if let bs = data:
        text = bs.decode_utf8().get("")

    var m = M(
        src: text.scalar_values(), pos: 0, ints: [], strs: [], syms: [],
        symmap: Map[String, Int](), gslot: [], pcar: [], pcdr: [], lparams: [],
        lbody: [], lenv: [], lname: [], pnames: [], pmin: [], pmax: [], pgrp: [],
        fparent: [], fhead: [], bsym: [], bval: [], bnext: [], out: [], need_nl: false
    )
    m.setup()

    let msg = m.run()

    if msg != "":
        if m.need_nl:
            m.emit("\n")
        m.emit("error: {msg}\n")

    stdout().write(m.out.join("")).get()
    return 0
