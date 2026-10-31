import read_lines from "@std/streams.ms"
import stdin, stdout from "@std/io.ms"

# Special-form symbol ids (interned first, so the ids are fixed).
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
let NSPECIAL = 15
let MAXI = 9223372036854775807
let MINI = -9223372036854775807 - 1
let DEPTH_LIMIT = 10000

type Fail:
    msg: String
    syntax: Bool

impl Error for Fail:
    fn message() String:
        return self.msg.clone()

type Value:
    case VNum(n: Int)
    case VBool(b: Bool)
    case VStr(id: Int)
    case VSym(id: Int)
    case VPair(id: Int)
    case VNil
    case VVoid
    case VPrim(id: Int)
    case VClos(id: Int)

type Step:
    done: Bool
    value: Value
    expr: Value
    env: Int

fn done(v: Value) Step:
    return Step(done: true, value: v, expr: VVoid, env: 0)

fn next(x: Value, e: Int) Step:
    return Step(done: false, value: VVoid, expr: x, env: e)

fn is_true(v: Value) Bool:
    match v:
        VBool(b):
            return b
        _:
            return true

fn is_delim(c: String) Bool:
    return c == " " or c == "\n" or c == "\t" or c == "\r" or c == "(" or c == ")" or c == "\"" or c == ";"

fn digit_of(c: String) Int:
    let code = c.scalar_at(0, -1)
    if code >= 48 and code <= 57:
        return code - 48
    return -1

fn int_shape(tok: String) Bool:
    let cs = tok.chars()
    var i = 0
    if cs.length() > 0 and cs[0] == "-":
        i = 1
    if i >= cs.length():
        return false
    while i < cs.length():
        if digit_of(cs[i]) < 0:
            return false
        i += 1
    return true

# Parses an integer literal (optional leading '-'); none when it does not fit in int64.
fn parse_int_checked(s: String) Int?:
    let cs = s.chars()
    var i = 0
    var neg = false
    if cs.length() > 0 and cs[0] == "-":
        neg = true
        i = 1
    if i >= cs.length():
        return none
    var acc = 0
    while i < cs.length():
        let d = digit_of(cs[i])
        if d < 0:
            return none
        if acc < (MINI + d) / 10:
            return none
        acc = acc * 10 - d
        i += 1
    if neg:
        return acc
    if acc == MINI:
        return none
    return -acc

fn add_over(a: Int, b: Int) Bool:
    if b > 0:
        return a > MAXI - b
    return a < MINI - b

fn sub_over(a: Int, b: Int) Bool:
    if b < 0:
        return a > MAXI + b
    return a < MINI + b

fn mul_over(a: Int, b: Int) Bool:
    if a == 0 or b == 0:
        return false
    if b == -1:
        return a == MINI
    if a == -1:
        return b == MINI
    if b > 0:
        return a > MAXI / b or a < MINI / b
    return a < MAXI / b or a > MINI / b

fn same_atom(a: Value, b: Value) Bool:
    match a:
        VNum(x):
            match b:
                VNum(y):
                    return x == y
                _:
                    return false
        VBool(x):
            match b:
                VBool(y):
                    return x == y
                _:
                    return false
        VSym(x):
            match b:
                VSym(y):
                    return x == y
                _:
                    return false
        VNil:
            match b:
                VNil:
                    return true
                _:
                    return false
        VVoid:
            match b:
                VVoid:
                    return true
                _:
                    return false
        VPrim(x):
            match b:
                VPrim(y):
                    return x == y
                _:
                    return false
        VClos(x):
            match b:
                VClos(y):
                    return x == y
                _:
                    return false
        _:
            return false

fn is_delim_at(src: List[String], i: Int) Bool:
    if i >= src.length():
        return true
    return is_delim(src[i])

fn group_of(name: String) Int:
    if name == "+":
        return 0
    if name == "*":
        return 0
    if name == "-":
        return 0
    if name == "quotient":
        return 0
    if name == "remainder":
        return 0
    if name == "abs":
        return 0
    if name == "min":
        return 0
    if name == "=":
        return 0
    if name == "<":
        return 0
    if name == ">":
        return 0
    if name == "<=":
        return 0
    if name == "zero?":
        return 0
    if name == "even?":
        return 0
    if name == "odd?":
        return 0
    if name == "modulo":
        return 0
    if name == "max":
        return 0
    if name == ">=":
        return 0
    if name == "not":
        return 1
    if name == "null?":
        return 1
    if name == "pair?":
        return 1
    if name == "list?":
        return 1
    if name == "number?":
        return 1
    if name == "string?":
        return 1
    if name == "symbol?":
        return 1
    if name == "boolean?":
        return 1
    if name == "procedure?":
        return 1
    if name == "eq?":
        return 1
    if name == "equal?":
        return 1
    if name == "cons":
        return 2
    if name == "car":
        return 2
    if name == "cdr":
        return 2
    if name == "cadr":
        return 2
    if name == "cddr":
        return 2
    if name == "caddr":
        return 2
    if name == "set-car!":
        return 2
    if name == "set-cdr!":
        return 2
    if name == "list":
        return 2
    if name == "length":
        return 2
    if name == "append":
        return 2
    if name == "reverse":
        return 2
    if name == "list-ref":
        return 2
    if name == "list-tail":
        return 2
    if name == "range":
        return 2
    if name == "assoc":
        return 2
    if name == "member":
        return 2
    if name == "map":
        return 3
    if name == "for-each":
        return 3
    if name == "filter":
        return 3
    if name == "fold":
        return 3
    if name == "apply":
        return 3
    if name == "sort":
        return 3
    if name == "foldr":
        return 3
    if name == "string-length":
        return 4
    if name == "string-append":
        return 4
    if name == "substring":
        return 4
    if name == "string-ref":
        return 4
    if name == "string=?":
        return 4
    if name == "string<?":
        return 4
    if name == "string-upcase":
        return 4
    if name == "string-downcase":
        return 4
    if name == "string->number":
        return 4
    if name == "number->string":
        return 4
    if name == "string->symbol":
        return 4
    if name == "symbol->string":
        return 4
    if name == "string->list":
        return 4
    if name == "list->string":
        return 4
    if name == "string-join":
        return 4
    if name == "string-split":
        return 4
    if name == "string-contains?":
        return 4
    if name == "display":
        return 5
    if name == "write":
        return 5
    if name == "newline":
        return 5
    if name == "void":
        return 5
    if name == "error":
        return 5
    return 5

type Interp:
    src: List[String]
    pos: Int
    pcar: List[Value]
    pcdr: List[Value]
    strs: List[String]
    syms: List[String]
    symmap: Map[String, Int]
    bsym: List[Int]
    bval: List[Value]
    bnext: List[Int]
    gidx: List[Int]
    fparent: List[Int]
    fhead: List[Int]
    cparams: List[Value]
    cbody: List[List[Value]]
    cenv: List[Int]
    cname: List[Int]
    cnreq: List[Int]
    crest: List[Bool]
    pname: List[String]
    pmin: List[Int]
    pmax: List[Int]
    pgroup: List[Int]
    depth: Int
    printed: Bool
    at_bol: Bool

impl Interp:
    fn err(msg: String) Fail:
        return Fail(msg: msg, syntax: false)

    fn serr(msg: String) Fail:
        return Fail(msg: "syntax error: " + msg, syntax: true)

    fn bad_form(name: String) Fail:
        return self.serr("bad form: " + name)

    fn type_err(name: String, kind: String, v: Value) Fail:
        return self.err(name + ": expected " + kind + ", got " + self.show(v, true))

    fn arity_err(name: String, lo: Int, hi: Int, n: Int) Fail:
        var expected = ""
        if hi < 0:
            expected = "at least " + "{lo}"
        else if lo == hi:
            expected = "{lo}"
        else:
            expected = "{lo} to {hi}"
        return self.err("wrong number of arguments to " + name + ": expected " + expected + ", got {n}")

    var fn intern(name: String) Int:
        if self.symmap.contains(name):
            return self.symmap.get(name).get(0)
        let id = self.syms.length()
        self.syms.append(name.clone())
        self.symmap.add(name.clone(), id)
        return id

    fn sym_id(v: Value) Int:
        match v:
            VSym(s):
                return s
            _:
                return -1

    var fn new_str(s: String) Value:
        let id = self.strs.length()
        self.strs.append(s)
        return VStr(id)

    var fn cons(a: Value, d: Value) Value:
        let id = self.pcar.length()
        self.pcar.append(a)
        self.pcdr.append(d)
        return VPair(id)

    var fn make_list(xs: List[Value]) Value:
        var r = VNil
        var i = xs.length() - 1
        while i >= 0:
            r = self.cons(xs[i].clone(), r)
            i -= 1
        return r

    var fn make_list_from(xs: List[Value], from: Int) Value:
        var r = VNil
        var i = xs.length() - 1
        while i >= from:
            r = self.cons(xs[i].clone(), r)
            i -= 1
        return r

    # Converts a proper list to a List; none when the list is improper.
    fn items(v: Value) List[Value]?:
        var out = List[Value]()
        var cur = v.clone()
        while true:
            match cur:
                VPair(p):
                    out.append(self.pcar[p].clone())
                    cur = self.pcdr[p].clone()
                VNil:
                    return out
                _:
                    return none

    var fn new_frame(parent: Int) Int:
        self.fparent.append(parent)
        self.fhead.append(-1)
        return self.fparent.length() - 1

    var fn add_binding(f: Int, sym: Int, v: Value) Unit:
        self.bsym.append(sym)
        self.bval.append(v)
        self.bnext.append(self.fhead[f])
        self.fhead[f] = self.bsym.length() - 1
        if f == 0:
            while self.gidx.length() <= sym:
                self.gidx.append(-1)
            self.gidx[sym] = self.bsym.length() - 1

    var fn find_in_frame(f: Int, sym: Int) Int:
        if f == 0:
            if sym < self.gidx.length():
                return self.gidx[sym]
            return -1
        let head = self.fhead[f]
        var b = head
        while b >= 0:
            if self.bsym[b] == sym:
                return b
            b = self.bnext[b]
        return -1

    var fn find(sym: Int, env: Int) Int:
        var f = env
        while f >= 0:
            let b = self.find_in_frame(f, sym)
            if b >= 0:
                return b
            f = self.fparent[f]
        return -1

    var fn define_in(env: Int, sym: Int, v: Value) Unit:
        let b = self.find_in_frame(env, sym)
        if b >= 0:
            self.bval[b] = v
        else:
            self.add_binding(env, sym, v)

    var fn defprim(name: String, lo: Int, hi: Int) Unit:
        let id = self.pname.length()
        self.pname.append(name.clone())
        self.pgroup.append(group_of(name))
        self.pmin.append(lo)
        self.pmax.append(hi)
        self.define_in(0, self.intern(name), VPrim(id))

    fn is_lambda_form(v: Value) Bool:
        match v:
            VPair(p):
                match self.pcar[p]:
                    VSym(s):
                        return s == S_LAMBDA
                    _:
                        return false
            _:
                return false

    # Checks a parameter spec; returns the number of required parameters.
    fn check_params(spec: Value, who: String) Int!Fail:
        var cur = spec.clone()
        var req = 0
        var seen = List[Int]()
        while true:
            let cv = cur.clone()
            match cv:
                VPair(p):
                    let s = self.sym_id(self.pcar[p].clone())
                    if s < 0:
                        return error(self.bad_form(who))
                    var i = 0
                    while i < seen.length():
                        if seen[i] == s:
                            return error(self.bad_form(who))
                        i += 1
                    seen.append(s)
                    req += 1
                    cur = self.pcdr[p].clone()
                VSym(s):
                    var i = 0
                    while i < seen.length():
                        if seen[i] == s:
                            return error(self.bad_form(who))
                        i += 1
                    return ok(req)
                VNil:
                    return ok(req)
                _:
                    return error(self.bad_form(who))

    fn spec_rest(spec: Value) Bool:
        var cur = spec.clone()
        while true:
            let cv = cur.clone()
            match cv:
                VPair(p):
                    cur = self.pcdr[p].clone()
                VSym(_s):
                    return true
                _:
                    return false

    var fn make_closure(spec: Value, body: List[Value], env: Int, name: Int, who: String) Value!Fail:
        let req = try self.check_params(spec, who)
        let rest = self.spec_rest(spec)
        self.cparams.append(spec.clone())
        self.cbody.append(body)
        self.cenv.append(env)
        self.cname.append(name)
        self.cnreq.append(req)
        self.crest.append(rest)
        return ok(VClos(self.cparams.length() - 1))

    var fn bind(c: Int, args: List[Value]) Int!Fail:
        let n = args.length()
        let req = self.cnreq[c]
        let rest = self.crest[c]
        if n < req or (not rest and n > req):
            var nm = "lambda"
            if self.cname[c] >= 0:
                nm = self.syms[self.cname[c]].clone()
            var hi = req
            if rest:
                hi = -1
            return error(self.arity_err(nm, req, hi, n))
        let nf = self.new_frame(self.cenv[c])
        var spec = self.cparams[c].clone()
        var i = 0
        while true:
            let cv = spec.clone()
            match cv:
                VPair(sp):
                    let sym = self.sym_id(self.pcar[sp].clone())
                    self.add_binding(nf, sym, args[i].clone())
                    i += 1
                    spec = self.pcdr[sp].clone()
                VSym(rs):
                    self.add_binding(nf, rs, self.make_list_from(args, i))
                    return ok(nf)
                _:
                    return ok(nf)

    # Non-tail procedure call (used by builtins and non-tail applications).
    var fn apply_val(f: Value, args: List[Value]) Value!Fail:
        match f:
            VPrim(id):
                return self.call_prim(id, args)
            VClos(c):
                let nf = try self.bind(c, args)
                if self.depth >= DEPTH_LIMIT:
                    return error(self.err("recursion limit exceeded"))
                self.depth += 1
                let forms = self.cbody[c].length()
                var k = 0
                while k < forms - 1:
                    let _x = self.eval(self.cbody[c][k].clone(), nf, false)
                    if _x.is_error():
                        self.depth -= 1
                        return _x
                    k += 1
                let r = self.eval(self.cbody[c][forms - 1].clone(), nf, true)
                self.depth -= 1
                return r
            _:
                return error(self.err("not a procedure: " + self.show(f, true)))

    var fn apply_step(f: Value, args: List[Value], tail: Bool) Step!Fail:
        match f:
            VPrim(id):
                let v = try self.call_prim(id, args)
                return ok(done(v))
            VClos(c):
                if not tail:
                    let v = try self.apply_val(f, args)
                    return ok(done(v))
                let nf = try self.bind(c, args)
                let forms = self.cbody[c].length()
                var k = 0
                while k < forms - 1:
                    let _x = try self.eval(self.cbody[c][k].clone(), nf, false)
                    k += 1
                return ok(next(self.cbody[c][forms - 1].clone(), nf))
            _:
                return error(self.err("not a procedure: " + self.show(f, true)))

    fn tail_items(its: List[Value], from: Int) List[Value]:
        var out = List[Value]()
        var k = from
        while k < its.length():
            out.append(its[k].clone())
            k += 1
        return out

    # Evaluates forms from..end in env; the last one is in tail position.
    var fn body_step(its: List[Value], from: Int, env: Int) Step!Fail:
        let n = its.length()
        var k = from
        while k < n - 1:
            let _x = try self.eval(its[k].clone(), env, false)
            k += 1
        return ok(next(its[n - 1].clone(), env))

    var fn special(hid: Int, its: List[Value], e: Int, tail: Bool) Step!Fail:
        let n = its.length()
        if hid == S_QUOTE:
            if n != 2:
                return error(self.bad_form("quote"))
            return ok(done(its[1].clone()))

        if hid == S_IF:
            if n != 3 and n != 4:
                return error(self.bad_form("if"))
            let t = try self.eval(its[1].clone(), e, false)
            if is_true(t):
                return ok(next(its[2].clone(), e))
            if n == 4:
                return ok(next(its[3].clone(), e))
            return ok(done(VVoid))

        if hid == S_DEFINE:
            if n < 2:
                return error(self.bad_form("define"))
            let target = its[1].clone()
            match target:
                VSym(sid):
                    if n != 3:
                        return error(self.bad_form("define"))
                    let val = try self.eval(its[2].clone(), e, false)
                    if self.is_lambda_form(its[2].clone()):
                        match val:
                            VClos(c):
                                self.cname[c] = sid
                            _:
                                let _y = 0
                    self.define_in(e, sid, val)
                    return ok(done(VVoid))
                VPair(tp):
                    if n < 3:
                        return error(self.bad_form("define"))
                    let sid = self.sym_id(self.pcar[tp].clone())
                    if sid < 0:
                        return error(self.bad_form("define"))
                    let spec = self.pcdr[tp].clone()
                    let clo = try self.make_closure(spec, self.tail_items(its, 2), e, sid, "define")
                    self.define_in(e, sid, clo)
                    return ok(done(VVoid))
                _:
                    return error(self.bad_form("define"))

        if hid == S_SET:
            if n != 3:
                return error(self.bad_form("set!"))
            let sid = self.sym_id(its[1].clone())
            if sid < 0:
                return error(self.bad_form("set!"))
            let v = try self.eval(its[2].clone(), e, false)
            let b = self.find(sid, e)
            if b < 0:
                return error(self.err("unbound variable: " + self.syms[sid]))
            self.bval[b] = v
            return ok(done(VVoid))

        if hid == S_LAMBDA:
            if n < 3:
                return error(self.bad_form("lambda"))
            let clo = try self.make_closure(its[1].clone(), self.tail_items(its, 2), e, -1, "lambda")
            return ok(done(clo))

        if hid == S_BEGIN:
            if n == 1:
                return ok(done(VVoid))
            var k = 1
            while k < n - 1:
                let _x = try self.eval(its[k].clone(), e, false)
                k += 1
            return ok(next(its[n - 1].clone(), e))

        if hid == S_LET:
            if n < 3:
                return error(self.bad_form("let"))
            if self.sym_id(its[1].clone()) >= 0:
                # named let
                if n < 4:
                    return error(self.bad_form("let"))
                let lname = self.sym_id(its[1].clone())
                let binds = self.items(its[2].clone())
                if binds.is_none():
                    return error(self.bad_form("let"))
                var names = List[Value]()
                var args = List[Value]()
                for b in binds.get(List[Value]()):
                    let bi = self.items(b.clone())
                    if bi.is_none():
                        return error(self.bad_form("let"))
                    let bl = bi.get(List[Value]())
                    if bl.length() != 2 or self.sym_id(bl[0].clone()) < 0:
                        return error(self.bad_form("let"))
                    names.append(bl[0].clone())
                    args.append(try self.eval(bl[1].clone(), e, false))
                let spec = self.make_list(names)
                let nf1 = self.new_frame(e)
                let clo = try self.make_closure(spec, self.tail_items(its, 3), nf1, lname, "let")
                self.add_binding(nf1, lname, clo.clone())
                let st = try self.apply_step(clo, args, tail)
                return ok(st)

            let binds = self.items(its[1].clone())
            if binds.is_none():
                return error(self.bad_form("let"))
            var names = List[Int]()
            var vals = List[Value]()
            for b in binds.get(List[Value]()):
                let bi = self.items(b.clone())
                if bi.is_none():
                    return error(self.bad_form("let"))
                let bl = bi.get(List[Value]())
                if bl.length() != 2 or self.sym_id(bl[0].clone()) < 0:
                    return error(self.bad_form("let"))
                names.append(self.sym_id(bl[0].clone()))
                vals.append(try self.eval(bl[1].clone(), e, false))
            let nf = self.new_frame(e)
            var i = 0
            while i < names.length():
                self.define_in(nf, names[i], vals[i].clone())
                i += 1
            return ok(try self.body_step(its, 2, nf))

        if hid == S_LETSTAR or hid == S_LETREC:
            if n < 3:
                return error(self.bad_form("let"))
            let binds = self.items(its[1].clone())
            if binds.is_none():
                return error(self.bad_form("let"))
            let nf = self.new_frame(e)
            for b in binds.get(List[Value]()):
                let bi = self.items(b.clone())
                if bi.is_none():
                    return error(self.bad_form("let"))
                let bl = bi.get(List[Value]())
                if bl.length() != 2 or self.sym_id(bl[0].clone()) < 0:
                    return error(self.bad_form("let"))
                let v = try self.eval(bl[1].clone(), nf, false)
                self.define_in(nf, self.sym_id(bl[0].clone()), v)
            return ok(try self.body_step(its, 2, nf))

        if hid == S_COND:
            var i = 1
            while i < n:
                let cl = self.items(its[i].clone())
                if cl.is_none():
                    return error(self.bad_form("cond"))
                let cll = cl.get(List[Value]())
                if cll.length() == 0:
                    return error(self.bad_form("cond"))
                if self.sym_id(cll[0].clone()) == S_ELSE:
                    if i != n - 1 or cll.length() < 2:
                        return error(self.bad_form("cond"))
                    return ok(try self.body_step(cll, 1, e))
                let t = try self.eval(cll[0].clone(), e, false)
                if is_true(t):
                    if cll.length() == 1:
                        return ok(done(t))
                    return ok(try self.body_step(cll, 1, e))
                i += 1
            return ok(done(VVoid))

        if hid == S_AND:
            if n == 1:
                return ok(done(VBool(true)))
            var k = 1
            while k < n - 1:
                let v = try self.eval(its[k].clone(), e, false)
                if not is_true(v):
                    return ok(done(v))
                k += 1
            return ok(next(its[n - 1].clone(), e))

        if hid == S_OR:
            if n == 1:
                return ok(done(VBool(false)))
            var k = 1
            while k < n - 1:
                let v = try self.eval(its[k].clone(), e, false)
                if is_true(v):
                    return ok(done(v))
                k += 1
            return ok(next(its[n - 1].clone(), e))

        if hid == S_WHEN or hid == S_UNLESS:
            if n < 3:
                return error(self.bad_form("when"))
            let t = try self.eval(its[1].clone(), e, false)
            var fire = is_true(t)
            if hid == S_UNLESS:
                fire = not fire
            if not fire:
                return ok(done(VVoid))
            return ok(try self.body_step(its, 2, e))

        if hid == S_TRY:
            if n != 3:
                return error(self.bad_form("try"))
            let d0 = self.depth
            let r = self.eval(its[1].clone(), e, false)
            if let v = r:
                return ok(done(v))
            let fe = r.err()
            if fe.syntax:
                return error(fe)
            self.depth = d0
            let h = try self.eval(its[2].clone(), e, false)
            var args = List[Value]()
            args.append(self.new_str(fe.msg))
            let v2 = try self.apply_val(h, args)
            return ok(done(v2))

        return error(self.err("internal: unknown special form"))

    var fn eval(expr: Value, env: Int, tail: Bool) Value!Fail:
        var x = expr.clone()
        var e = env
        while true:
            match x:
                VSym(id):
                    let b = self.find(id, e)
                    if b < 0:
                        return error(self.err("unbound variable: " + self.syms[id]))
                    return ok(self.bval[b].clone())
                VPair(p):
                    let head = self.pcar[p].clone()
                    let hs = self.sym_id(head.clone())
                    let its_opt = self.items(x)
                    if its_opt.is_none():
                        if hs >= 0 and hs < NSPECIAL:
                            return error(self.bad_form(self.syms[hs]))
                        return error(self.serr("bad application"))
                    let its = its_opt.get(List[Value]())
                    if hs >= 0 and hs < NSPECIAL:
                        let st = try self.special(hs, its, e, tail)
                        if st.done:
                            return ok(st.value.clone())
                        x = st.expr.clone()
                        e = st.env
                        continue
                    let f = try self.eval(head.clone(), e, false)
                    var args = List[Value]()
                    var k = 1
                    while k < its.length():
                        let av = try self.eval(its[k].clone(), e, false)
                        args.append(av)
                        k += 1
                    let st2 = try self.apply_step(f, args, tail)
                    if st2.done:
                        return ok(st2.value.clone())
                    x = st2.expr.clone()
                    e = st2.env
                    continue
                VNil:
                    return error(self.serr("empty application"))
                _:
                    return ok(x.clone())

    # ---- printing -------------------------------------------------------

    fn escape(s: String) String:
        var out = "\""
        for c in s.chars():
            if c == "\\":
                out = out + "\\\\"
            else if c == "\"":
                out = out + "\\\""
            else if c == "\n":
                out = out + "\\n"
            else if c == "\t":
                out = out + "\\t"
            else:
                out = out + c
        return out + "\""

    fn show(v: Value, wr: Bool) String:
        match v:
            VNum(n):
                return "{n}"
            VBool(b):
                if b:
                    return "#t"
                return "#f"
            VStr(id):
                if wr:
                    return self.escape(self.strs[id])
                return self.strs[id].clone()
            VSym(id):
                return self.syms[id].clone()
            VPair(p):
                var s = "("
                s = s + self.show(self.pcar[p].clone(), wr)
                var cur = self.pcdr[p].clone()
                while true:
                    let cv = cur.clone()
                    match cv:
                        VPair(q):
                            s = s + " " + self.show(self.pcar[q].clone(), wr)
                            cur = self.pcdr[q].clone()
                        VNil:
                            return s + ")"
                        _:
                            return s + " . " + self.show(cv, wr) + ")"
            VNil:
                return "()"
            VVoid:
                return "#<void>"
            VPrim(id):
                return "#<builtin " + self.pname[id] + ">"
            VClos(c):
                if self.cname[c] >= 0:
                    return "#<procedure " + self.syms[self.cname[c]] + ">"
                return "#<procedure>"

    var fn emit(s: String) Unit:
        if s.length() > 0:
            let _w = stdout().write(s).get()
            self.printed = true
            self.at_bol = s.ends_with("\n")

    var fn report(e: Fail) Unit:
        if self.printed and not self.at_bol:
            self.emit("\n")
        self.emit("error: " + e.msg + "\n")

    # ---- reader ---------------------------------------------------------

    var fn skip_ws() Unit:
        let n = self.src.length()
        while self.pos < n:
            let c = self.src[self.pos].clone()
            if c == " " or c == "\n" or c == "\t" or c == "\r":
                self.pos += 1
            else if c == ";":
                while self.pos < n and self.src[self.pos] != "\n":
                    self.pos += 1
            else:
                return

    var fn read_token() String:
        var tok = ""
        while self.pos < self.src.length():
            let c = self.src[self.pos].clone()
            if is_delim(c):
                break
            tok = tok + c
            self.pos += 1
        return tok

    var fn build(elems: List[Value], tailv: Value) Value:
        var r = tailv
        var i = elems.length() - 1
        while i >= 0:
            r = self.cons(elems[i].clone(), r)
            i -= 1
        return r

    var fn read_string() Value!Fail:
        var s = ""
        let n = self.src.length()
        while true:
            if self.pos >= n:
                return error(self.serr("unterminated string"))
            let c = self.src[self.pos].clone()
            self.pos += 1
            if c == "\"":
                return ok(self.new_str(s))
            if c == "\\":
                if self.pos >= n:
                    return error(self.serr("unterminated string"))
                let ec = self.src[self.pos].clone()
                self.pos += 1
                if ec == "n":
                    s = s + "\n"
                else if ec == "t":
                    s = s + "\t"
                else if ec == "\\":
                    s = s + "\\"
                else if ec == "\"":
                    s = s + "\""
                else:
                    return error(self.serr("bad escape"))
            else:
                s = s + c

    var fn atom(tok: String) Value!Fail:
        if tok == ".":
            return error(self.serr("unexpected ."))
        if tok == "#t":
            return ok(VBool(true))
        if tok == "#f":
            return ok(VBool(false))
        if tok.starts_with("#"):
            return error(self.serr("bad token: " + tok))
        if int_shape(tok):
            let v = parse_int_checked(tok)
            if v.is_none():
                return error(self.serr("integer out of range"))
            return ok(VNum(v.get(0)))
        return ok(VSym(self.intern(tok)))

    var fn read_list() Value!Fail:
        var elems = List[Value]()
        let n = self.src.length()
        while true:
            self.skip_ws()
            if self.pos >= n:
                return error(self.serr("unexpected end of input"))
            let c = self.src[self.pos].clone()
            if c == ")":
                self.pos += 1
                return ok(self.build(elems, VNil))
            if c == "." and is_delim_at(self.src, self.pos + 1):
                if elems.length() == 0:
                    return error(self.serr("bad dotted list"))
                self.pos += 1
                self.skip_ws()
                if self.pos < n and self.src[self.pos] == ")":
                    return error(self.serr("bad dotted list"))
                let tailv = try self.read_datum()
                self.skip_ws()
                if self.pos >= n:
                    return error(self.serr("unexpected end of input"))
                if self.src[self.pos] != ")":
                    return error(self.serr("bad dotted list"))
                self.pos += 1
                return ok(self.build(elems, tailv))
            let d = try self.read_datum()
            elems.append(d)

    var fn read_datum() Value!Fail:
        self.skip_ws()
        if self.pos >= self.src.length():
            return error(self.serr("unexpected end of input"))
        let c = self.src[self.pos].clone()
        if c == "(":
            self.pos += 1
            return self.read_list()
        if c == ")":
            return error(self.serr("unexpected )"))
        if c == "'":
            self.pos += 1
            let d = try self.read_datum()
            return ok(self.cons(VSym(S_QUOTE), self.cons(d, VNil)))
        if c == "\"":
            self.pos += 1
            return self.read_string()
        let tok = self.read_token()
        return self.atom(tok)

    # ---- builtins helpers -----------------------------------------------

    fn int_arg(name: String, v: Value) Int!Fail:
        match v:
            VNum(n):
                return ok(n)
            _:
                return error(self.type_err(name, "integer", v))

    fn str_arg(name: String, v: Value) String!Fail:
        match v:
            VStr(id):
                return ok(self.strs[id].clone())
            _:
                return error(self.type_err(name, "string", v))

    fn list_arg(name: String, v: Value) List[Value]!Fail:
        let r = self.items(v.clone())
        if r.is_none():
            return error(self.type_err(name, "list", v))
        return ok(r.get(List[Value]()))

    fn proc_arg(name: String, v: Value) Value!Fail:
        match v:
            VPrim(_id):
                return ok(v.clone())
            VClos(_c):
                return ok(v.clone())
            _:
                return error(self.type_err(name, "procedure", v))

    var fn truthy_call(f: Value, args: List[Value]) Bool!Fail:
        let r = try self.apply_val(f, args)
        return ok(is_true(r))

    var fn equal_v(a0: Value, b0: Value) Bool:
        var a = a0.clone()
        var b = b0.clone()
        while true:
            let av = a.clone()
            let bv = b.clone()
            match av:
                VPair(pa):
                    match bv:
                        VPair(pb):
                            if not self.equal_v(self.pcar[pa].clone(), self.pcar[pb].clone()):
                                return false
                            a = self.pcdr[pa].clone()
                            b = self.pcdr[pb].clone()
                        _:
                            return false
                VStr(sa):
                    match bv:
                        VStr(sb):
                            return self.strs[sa] == self.strs[sb]
                        _:
                            return false
                _:
                    return same_atom(av, bv)

    var fn cxr(name: String, v: Value, ops: String) Value!Fail:
        var cur = v.clone()
        var i = ops.length() - 1
        while i >= 0:
            let cv = cur.clone()
            match cv:
                VPair(p):
                    if ops.get(i) == "a":
                        cur = self.pcar[p].clone()
                    else:
                        cur = self.pcdr[p].clone()
                _:
                    return error(self.type_err(name, "pair", cv))
            i -= 1
        return ok(cur)

    var fn msort(xs: List[Value], less: Value) List[Value]!Fail:
        let n = xs.length()
        if n <= 1:
            return ok(xs)
        let mid = n / 2
        var left = List[Value]()
        var right = List[Value]()
        var i = 0
        while i < n:
            if i < mid:
                left.append(xs[i].clone())
            else:
                right.append(xs[i].clone())
            i += 1
        let ls = try self.msort(left, less.clone())
        let rs = try self.msort(right, less.clone())
        var out = List[Value]()
        var a = 0
        var b = 0
        while a < ls.length() or b < rs.length():
            if a >= ls.length():
                out.append(rs[b].clone())
                b += 1
            else if b >= rs.length():
                out.append(ls[a].clone())
                a += 1
            else:
                var args = List[Value]()
                args.append(rs[b].clone())
                args.append(ls[a].clone())
                if try self.truthy_call(less.clone(), args):
                    out.append(rs[b].clone())
                    b += 1
                else:
                    out.append(ls[a].clone())
                    a += 1
        return ok(out)

    # ---- primitives -----------------------------------------------------

    var fn call_prim(id: Int, args: List[Value]) Value!Fail:
        let name = self.pname[id].clone()
        let n = args.length()
        let lo = self.pmin[id]
        let hi = self.pmax[id]
        if n < lo or (hi >= 0 and n > hi):
            return error(self.arity_err(name, lo, hi, n))
        let g = self.pgroup[id]
        if g == 0:
            return self.dispatch_num(name, args)
        if g == 1:
            return self.dispatch_pred(name, args)
        if g == 2:
            return self.dispatch_pairs(name, args)
        if g == 3:
            return self.dispatch_hof(name, args)
        if g == 4:
            return self.dispatch_str(name, args)
        return self.dispatch_out(name, args)

    var fn dispatch_num(name: String, args: List[Value]) Value!Fail:
        let n = args.length()
        if name == "+":
            var acc = 0
            var i = 0
            while i < n:
                let v = try self.int_arg("+", args[i].clone())
                if add_over(acc, v):
                    return error(self.err("integer overflow"))
                acc = acc + v
                i += 1
            return ok(VNum(acc))
        if name == "*":
            var acc = 1
            var i = 0
            while i < n:
                let v = try self.int_arg("*", args[i].clone())
                if mul_over(acc, v):
                    return error(self.err("integer overflow"))
                acc = acc * v
                i += 1
            return ok(VNum(acc))
        if name == "-":
            let first = try self.int_arg("-", args[0].clone())
            if n == 1:
                if sub_over(0, first):
                    return error(self.err("integer overflow"))
                return ok(VNum(-first))
            var acc = first
            var i = 1
            while i < n:
                let v = try self.int_arg("-", args[i].clone())
                if sub_over(acc, v):
                    return error(self.err("integer overflow"))
                acc = acc - v
                i += 1
            return ok(VNum(acc))
        if name == "quotient" or name == "remainder" or name == "modulo":
            let a = try self.int_arg(name, args[0].clone())
            let b = try self.int_arg(name, args[1].clone())
            if b == 0:
                return error(self.err("division by zero"))
            if name == "quotient":
                if a == MINI and b == -1:
                    return error(self.err("integer overflow"))
                return ok(VNum(a / b))
            if b == -1:
                return ok(VNum(0))
            var r = a % b
            if name == "remainder":
                return ok(VNum(r))
            if r != 0 and ((r < 0) != (b < 0)):
                r = r + b
            return ok(VNum(r))
        if name == "abs":
            let a = try self.int_arg("abs", args[0].clone())
            if a < 0:
                if sub_over(0, a):
                    return error(self.err("integer overflow"))
                return ok(VNum(-a))
            return ok(VNum(a))
        if name == "min" or name == "max":
            var best = try self.int_arg(name, args[0].clone())
            var i = 1
            while i < n:
                let v = try self.int_arg(name, args[i].clone())
                if name == "min":
                    if v < best:
                        best = v
                else:
                    if v > best:
                        best = v
                i += 1
            return ok(VNum(best))
        if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
            var vals = List[Int]()
            var i = 0
            while i < n:
                vals.append(try self.int_arg(name, args[i].clone()))
                i += 1
            var k = 0
            while k + 1 < n:
                let a = vals[k]
                let b = vals[k + 1]
                var okc = false
                if name == "=":
                    okc = a == b
                else if name == "<":
                    okc = a < b
                else if name == ">":
                    okc = a > b
                else if name == "<=":
                    okc = a <= b
                else:
                    okc = a >= b
                if not okc:
                    return ok(VBool(false))
                k += 1
            return ok(VBool(true))
        if name == "zero?":
            let a = try self.int_arg(name, args[0].clone())
            return ok(VBool(a == 0))
        if name == "even?":
            let a = try self.int_arg(name, args[0].clone())
            return ok(VBool(a % 2 == 0))
        if name == "odd?":
            let a = try self.int_arg(name, args[0].clone())
            return ok(VBool(a % 2 != 0))
        return error(self.err("internal: unknown primitive " + name))

    var fn dispatch_pred(name: String, args: List[Value]) Value!Fail:
        let a0 = args.get(0, VVoid)
        if name == "not":
            match a0:
                VBool(b):
                    return ok(VBool(not b))
                _:
                    return ok(VBool(false))
        if name == "null?":
            match a0:
                VNil:
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "pair?":
            match a0:
                VPair(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "list?":
            return ok(VBool(self.items(a0.clone()).is_some()))
        if name == "number?":
            match a0:
                VNum(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "string?":
            match a0:
                VStr(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "symbol?":
            match a0:
                VSym(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "boolean?":
            match a0:
                VBool(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "procedure?":
            match a0:
                VPrim(_p):
                    return ok(VBool(true))
                VClos(_p):
                    return ok(VBool(true))
                _:
                    return ok(VBool(false))
        if name == "eq?":
            let b0 = args[1].clone()
            match a0:
                VStr(_p):
                    return ok(VBool(false))
                VPair(_p):
                    return ok(VBool(false))
                VClos(_p):
                    return ok(VBool(false))
                VPrim(_p):
                    return ok(VBool(false))
                _:
                    return ok(VBool(same_atom(a0, b0)))
        if name == "equal?":
            return ok(VBool(self.equal_v(a0, args[1].clone())))
        return error(self.err("internal: unknown primitive " + name))

    var fn dispatch_pairs(name: String, args: List[Value]) Value!Fail:
        let n = args.length()
        let a0 = args.get(0, VVoid)
        if name == "cons":
            return ok(self.cons(a0, args[1].clone()))
        if name == "car":
            return self.cxr("car", a0, "a")
        if name == "cdr":
            return self.cxr("cdr", a0, "d")
        if name == "cadr":
            return self.cxr("cadr", a0, "ad")
        if name == "cddr":
            return self.cxr("cddr", a0, "dd")
        if name == "caddr":
            return self.cxr("caddr", a0, "add")
        if name == "set-car!":
            match a0:
                VPair(p):
                    self.pcar[p] = args[1].clone()
                    return ok(VVoid)
                _:
                    return error(self.type_err("set-car!", "pair", a0))
        if name == "set-cdr!":
            match a0:
                VPair(p):
                    self.pcdr[p] = args[1].clone()
                    return ok(VVoid)
                _:
                    return error(self.type_err("set-cdr!", "pair", a0))
        if name == "list":
            return ok(self.make_list(args))
        if name == "length":
            let xs = try self.list_arg("length", a0)
            return ok(VNum(xs.length()))
        if name == "append":
            if n == 0:
                return ok(VNil)
            var r = args[n - 1].clone()
            var i = n - 2
            while i >= 0:
                let xs = try self.list_arg("append", args[i].clone())
                var j = xs.length() - 1
                while j >= 0:
                    r = self.cons(xs[j].clone(), r)
                    j -= 1
                i -= 1
            return ok(r)
        if name == "reverse":
            let xs = try self.list_arg("reverse", a0)
            var r = VNil
            for x in xs:
                r = self.cons(x.clone(), r)
            return ok(r)
        if name == "list-ref":
            let k = try self.int_arg("list-ref", args[1].clone())
            match a0:
                VPair(_p):
                    let _y = 0
                VNil:
                    let _z = 0
                _:
                    return error(self.type_err("list-ref", "list", a0))
            if k < 0:
                return error(self.err("list-ref: index out of range"))
            var cur = a0.clone()
            var i = 0
            while true:
                let cv = cur.clone()
                match cv:
                    VPair(p):
                        if i == k:
                            return ok(self.pcar[p].clone())
                        cur = self.pcdr[p].clone()
                        i += 1
                    _:
                        return error(self.err("list-ref: index out of range"))
        if name == "list-tail":
            let k = try self.int_arg("list-tail", args[1].clone())
            if k < 0:
                return error(self.err("list-tail: index out of range"))
            var cur = a0.clone()
            var i = 0
            while i < k:
                let cv = cur.clone()
                match cv:
                    VPair(p):
                        cur = self.pcdr[p].clone()
                        i += 1
                    _:
                        return error(self.err("list-tail: index out of range"))
            return ok(cur)
        if name == "range":
            let a = try self.int_arg("range", a0.clone())
            let b = try self.int_arg("range", args[1].clone())
            var r = VNil
            var i = b - 1
            while i >= a:
                r = self.cons(VNum(i), r)
                i -= 1
            return ok(r)
        if name == "assoc":
            var cur = args[1].clone()
            while true:
                let cv = cur.clone()
                match cv:
                    VPair(p):
                        let entry = self.pcar[p].clone()
                        match entry:
                            VPair(q):
                                if self.equal_v(a0.clone(), self.pcar[q].clone()):
                                    return ok(entry)
                            _:
                                return error(self.type_err("assoc", "pair", entry))
                        cur = self.pcdr[p].clone()
                    VNil:
                        return ok(VBool(false))
                    _:
                        return error(self.type_err("assoc", "list", args[1]))
        if name == "member":
            var cur = args[1].clone()
            while true:
                let cv = cur.clone()
                match cv:
                    VPair(p):
                        if self.equal_v(a0.clone(), self.pcar[p].clone()):
                            return ok(cv)
                        cur = self.pcdr[p].clone()
                    VNil:
                        return ok(VBool(false))
                    _:
                        return error(self.type_err("member", "list", args[1]))
        return error(self.err("internal: unknown primitive " + name))

    var fn dispatch_hof(name: String, args: List[Value]) Value!Fail:
        let n = args.length()
        let a0 = args.get(0, VVoid)
        if name == "map" or name == "for-each":
            let f = try self.proc_arg(name, a0.clone())
            var lists = List[List[Value]]()
            var i = 1
            while i < n:
                lists.append(try self.list_arg(name, args[i].clone()))
                i += 1
            var len = lists[0].length()
            for l in lists:
                if l.length() < len:
                    len = l.length()
            var out = List[Value]()
            var k = 0
            while k < len:
                var cargs = List[Value]()
                for l in lists:
                    cargs.append(l[k].clone())
                let r = try self.apply_val(f.clone(), cargs)
                out.append(r)
                k += 1
            if name == "for-each":
                return ok(VVoid)
            return ok(self.make_list(out))
        if name == "filter":
            let f = try self.proc_arg(name, a0.clone())
            let xs = try self.list_arg(name, args[1].clone())
            var out = List[Value]()
            for x in xs:
                var cargs = List[Value]()
                cargs.append(x.clone())
                if try self.truthy_call(f.clone(), cargs):
                    out.append(x.clone())
            return ok(self.make_list(out))
        if name == "fold" or name == "foldr":
            let f = try self.proc_arg(name, a0.clone())
            var acc = args[1].clone()
            let xs = try self.list_arg(name, args[2].clone())
            if name == "fold":
                for x in xs:
                    var cargs = List[Value]()
                    cargs.append(acc.clone())
                    cargs.append(x.clone())
                    acc = try self.apply_val(f.clone(), cargs)
            else:
                var i = xs.length() - 1
                while i >= 0:
                    var cargs = List[Value]()
                    cargs.append(xs[i].clone())
                    cargs.append(acc.clone())
                    acc = try self.apply_val(f.clone(), cargs)
                    i -= 1
            return ok(acc)
        if name == "apply":
            let f = try self.proc_arg(name, a0.clone())
            var cargs = List[Value]()
            var i = 1
            while i < n - 1:
                cargs.append(args[i].clone())
                i += 1
            let last = try self.list_arg(name, args[n - 1].clone())
            for x in last:
                cargs.append(x.clone())
            return self.apply_val(f, cargs)
        if name == "sort":
            let less = try self.proc_arg(name, args[1].clone())
            let xs = try self.list_arg(name, a0.clone())
            let sorted = try self.msort(xs, less)
            return ok(self.make_list(sorted))
        return error(self.err("internal: unknown primitive " + name))

    var fn dispatch_str(name: String, args: List[Value]) Value!Fail:
        let n = args.length()
        let a0 = args.get(0, VVoid)
        if name == "string-length":
            let s = try self.str_arg(name, a0.clone())
            return ok(VNum(s.length()))
        if name == "string-append":
            var s = ""
            var i = 0
            while i < n:
                s = s + (try self.str_arg(name, args[i].clone()))
                i += 1
            return ok(self.new_str(s))
        if name == "substring":
            let s = try self.str_arg(name, a0.clone())
            let a = try self.int_arg(name, args[1].clone())
            let b = try self.int_arg(name, args[2].clone())
            if a < 0 or a > b or b > s.length():
                return error(self.err("substring: index out of range"))
            let t = s.slice(a, b)
            if let u = t:
                return ok(self.new_str(u))
            return error(self.err("substring: index out of range"))
        if name == "string-ref":
            let s = try self.str_arg(name, a0.clone())
            let i = try self.int_arg(name, args[1].clone())
            if i < 0 or i >= s.length():
                return error(self.err("string-ref: index out of range"))
            return ok(self.new_str(s.get(i)))
        if name == "string=?":
            let a = try self.str_arg(name, a0.clone())
            let b = try self.str_arg(name, args[1].clone())
            return ok(VBool(a == b))
        if name == "string<?":
            let a = try self.str_arg(name, a0.clone())
            let b = try self.str_arg(name, args[1].clone())
            return ok(VBool(a < b))
        if name == "string-upcase":
            let s = try self.str_arg(name, a0.clone())
            return ok(self.new_str(s.upper()))
        if name == "string-downcase":
            let s = try self.str_arg(name, a0.clone())
            return ok(self.new_str(s.lower()))
        if name == "string->number":
            let s = try self.str_arg(name, a0.clone())
            if not int_shape(s):
                return ok(VBool(false))
            let v = parse_int_checked(s)
            if v.is_none():
                return ok(VBool(false))
            return ok(VNum(v.get(0)))
        if name == "number->string":
            let v = try self.int_arg(name, a0.clone())
            return ok(self.new_str("{v}"))
        if name == "string->symbol":
            let s = try self.str_arg(name, a0.clone())
            return ok(VSym(self.intern(s)))
        if name == "symbol->string":
            match a0:
                VSym(id):
                    return ok(self.new_str(self.syms[id].clone()))
                _:
                    return error(self.type_err(name, "symbol", a0))
        if name == "string->list":
            let s = try self.str_arg(name, a0.clone())
            var out = List[Value]()
            for c in s.chars():
                out.append(self.new_str(c))
            return ok(self.make_list(out))
        if name == "list->string":
            let xs = try self.list_arg(name, a0.clone())
            var s = ""
            for x in xs:
                s = s + (try self.str_arg(name, x.clone()))
            return ok(self.new_str(s))
        if name == "string-join":
            let xs = try self.list_arg(name, a0.clone())
            let sep = try self.str_arg(name, args[1].clone())
            var s = ""
            var i = 0
            while i < xs.length():
                if i > 0:
                    s = s + sep
                s = s + (try self.str_arg(name, xs[i].clone()))
                i += 1
            return ok(self.new_str(s))
        if name == "string-split":
            let s = try self.str_arg(name, a0.clone())
            let sep = try self.str_arg(name, args[1].clone())
            if sep.length() != 1:
                return error(self.err("string-split: separator must be one character"))
            var out = List[Value]()
            var cur = ""
            for c in s.chars():
                if c == sep:
                    out.append(self.new_str(cur))
                    cur = ""
                else:
                    cur = cur + c
            out.append(self.new_str(cur))
            return ok(self.make_list(out))
        if name == "string-contains?":
            let s = try self.str_arg(name, a0.clone())
            let sub = try self.str_arg(name, args[1].clone())
            return ok(VBool(s.contains(sub)))
        return error(self.err("internal: unknown primitive " + name))

    var fn dispatch_out(name: String, args: List[Value]) Value!Fail:
        let n = args.length()
        let a0 = args.get(0, VVoid)
        if name == "display":
            self.emit(self.show(a0, false))
            return ok(VVoid)
        if name == "write":
            self.emit(self.show(a0, true))
            return ok(VVoid)
        if name == "newline":
            self.emit("\n")
            return ok(VVoid)
        if name == "void":
            return ok(VVoid)
        if name == "error":
            let msg = try self.str_arg("error", a0.clone())
            var s = msg
            var i = 1
            while i < n:
                s = s + " " + self.show(args[i].clone(), true)
                i += 1
            return error(self.err(s))

        return error(self.err("internal: unknown primitive " + name))
        return error(self.err("internal: unknown primitive " + name))

    var fn init_builtins() Unit:
        let _g = self.new_frame(-1)
        self.defprim("+", 0, -1)
        self.defprim("-", 1, -1)
        self.defprim("*", 0, -1)
        self.defprim("quotient", 2, 2)
        self.defprim("remainder", 2, 2)
        self.defprim("modulo", 2, 2)
        self.defprim("abs", 1, 1)
        self.defprim("min", 1, -1)
        self.defprim("max", 1, -1)
        self.defprim("=", 2, -1)
        self.defprim("<", 2, -1)
        self.defprim(">", 2, -1)
        self.defprim("<=", 2, -1)
        self.defprim(">=", 2, -1)
        self.defprim("zero?", 1, 1)
        self.defprim("even?", 1, 1)
        self.defprim("odd?", 1, 1)
        self.defprim("not", 1, 1)
        self.defprim("null?", 1, 1)
        self.defprim("pair?", 1, 1)
        self.defprim("list?", 1, 1)
        self.defprim("number?", 1, 1)
        self.defprim("string?", 1, 1)
        self.defprim("symbol?", 1, 1)
        self.defprim("boolean?", 1, 1)
        self.defprim("procedure?", 1, 1)
        self.defprim("eq?", 2, 2)
        self.defprim("equal?", 2, 2)
        self.defprim("cons", 2, 2)
        self.defprim("car", 1, 1)
        self.defprim("cdr", 1, 1)
        self.defprim("cadr", 1, 1)
        self.defprim("cddr", 1, 1)
        self.defprim("caddr", 1, 1)
        self.defprim("set-car!", 2, 2)
        self.defprim("set-cdr!", 2, 2)
        self.defprim("list", 0, -1)
        self.defprim("length", 1, 1)
        self.defprim("append", 0, -1)
        self.defprim("reverse", 1, 1)
        self.defprim("list-ref", 2, 2)
        self.defprim("list-tail", 2, 2)
        self.defprim("range", 2, 2)
        self.defprim("assoc", 2, 2)
        self.defprim("member", 2, 2)
        self.defprim("map", 2, -1)
        self.defprim("for-each", 2, -1)
        self.defprim("filter", 2, 2)
        self.defprim("fold", 3, 3)
        self.defprim("foldr", 3, 3)
        self.defprim("apply", 2, -1)
        self.defprim("sort", 2, 2)
        self.defprim("string-length", 1, 1)
        self.defprim("string-append", 0, -1)
        self.defprim("substring", 3, 3)
        self.defprim("string-ref", 2, 2)
        self.defprim("string=?", 2, 2)
        self.defprim("string<?", 2, 2)
        self.defprim("string-upcase", 1, 1)
        self.defprim("string-downcase", 1, 1)
        self.defprim("string->number", 1, 1)
        self.defprim("number->string", 1, 1)
        self.defprim("string->symbol", 1, 1)
        self.defprim("symbol->string", 1, 1)
        self.defprim("string->list", 1, 1)
        self.defprim("list->string", 1, 1)
        self.defprim("string-join", 2, 2)
        self.defprim("string-split", 2, 2)
        self.defprim("string-contains?", 2, 2)
        self.defprim("display", 1, 1)
        self.defprim("write", 1, 1)
        self.defprim("newline", 0, 0)
        self.defprim("void", 0, 0)
        self.defprim("error", 1, -1)

    var fn run() Unit:
        while true:
            self.skip_ws()
            if self.pos >= self.src.length():
                return
            let rr = self.read_datum()
            if rr.is_error():
                self.report(rr.err())
                return
            let form = rr.get(VVoid)
            let ev = self.eval(form, 0, false)
            if ev.is_error():
                self.report(ev.err())
                return

fn new_interp(src: List[String]) Interp:
    return Interp(
        src: src,
        pos: 0,
        pcar: List[Value](),
        pcdr: List[Value](),
        strs: List[String](),
        syms: List[String](),
        symmap: Map[String, Int](),
        bsym: List[Int](),
        bval: List[Value](),
        bnext: List[Int](),
        gidx: List[Int](),
        fparent: List[Int](),
        fhead: List[Int](),
        cparams: List[Value](),
        cbody: List[List[Value]](),
        cenv: List[Int](),
        cname: List[Int](),
        cnreq: List[Int](),
        crest: List[Bool](),
        pname: List[String](),
        pmin: List[Int](),
        pmax: List[Int](),
        pgroup: List[Int](),
        depth: 0,
        printed: false,
        at_bol: true,
    )

export fn main() Int:
    let lines = read_lines(stdin()).get(List[String]())
    var src = List[String]()
    for line in lines:
        for c in line.chars():
            src.append(c)
        src.append("\n")
    var it = new_interp(src)
    # Intern the special-form names first so their ids match the S_* constants.
    let names = ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try", "else"]
    for nm in names:
        let _id = it.intern(nm)
    it.init_builtins()
    it.run()
    return 0
