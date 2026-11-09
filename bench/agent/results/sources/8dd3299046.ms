// Scheme-like interpreter. Reads a program from stdin and runs its top-level forms in order.
//
// Values are integer handles into parallel arrays (kind, payload, car, cdr), so every value
// has a stable identity and pairs can be mutated without ownership trouble. Strings live in
// `strs`, symbols in `symn`. Environments are frames (`fr_*`) holding linked bindings (`b_*`);
// the global frame is frame -1 with values in `gval` indexed by symbol id.

import read_all from "@std/io/streams.ms"
import stdin, stdout, WriteStream from "@std/io/io.ms"

// Primitive ids, in the order they are registered in `setup`.
let P_ADD = 0
let P_SUB = 1
let P_MUL = 2
let P_QUOT = 3
let P_REM = 4
let P_MOD = 5
let P_ABS = 6
let P_MIN = 7
let P_MAX = 8
let P_NUMEQ = 9
let P_LT = 10
let P_GT = 11
let P_LE = 12
let P_GE = 13
let P_ZEROP = 14
let P_EVENP = 15
let P_ODDP = 16
let P_NOT = 17
let P_NULLP = 18
let P_PAIRP = 19
let P_LISTP = 20
let P_NUMBERP = 21
let P_STRINGP = 22
let P_SYMBOLP = 23
let P_BOOLEANP = 24
let P_PROCP = 25
let P_EQP = 26
let P_EQUALP = 27
let P_CONS = 28
let P_CAR = 29
let P_CDR = 30
let P_CADR = 31
let P_CDDR = 32
let P_CADDR = 33
let P_SETCAR = 34
let P_SETCDR = 35
let P_LIST = 36
let P_LENGTH = 37
let P_APPEND = 38
let P_REVERSE = 39
let P_LISTREF = 40
let P_LISTTAIL = 41
let P_RANGE = 42
let P_ASSOC = 43
let P_MEMBER = 44
let P_MAP = 45
let P_FOREACH = 46
let P_FILTER = 47
let P_FOLD = 48
let P_FOLDR = 49
let P_APPLY = 50
let P_SORT = 51
let P_STRLEN = 52
let P_STRAPPEND = 53
let P_SUBSTR = 54
let P_STRREF = 55
let P_STREQ = 56
let P_STRLT = 57
let P_STRUP = 58
let P_STRDOWN = 59
let P_STR2NUM = 60
let P_NUM2STR = 61
let P_STR2SYM = 62
let P_SYM2STR = 63
let P_STR2LIST = 64
let P_LIST2STR = 65
let P_STRJOIN = 66
let P_STRSPLIT = 67
let P_STRCONTAINS = 68
let P_DISPLAY = 69
let P_WRITE = 70
let P_NEWLINE = 71
let P_VOID = 72
let P_ERROR = 73

let INT_MAX = 9223372036854775807
let INT_MIN = -9223372036854775807 - 1

// Handles of the fixed values.
let NIL = 0
let VOID = 1
let FALSE = 2
let TRUE = 3

// Value kinds.
let K_NIL = 0
let K_VOID = 1
let K_BOOL = 2
let K_INT = 3
let K_STR = 4
let K_SYM = 5
let K_PAIR = 6
let K_PRIM = 7
let K_CLOS = 8

let MAX_DEPTH = 10000
// Limit for calls nested through builtins such as map; keeps the native stack from overflowing.
let MAX_BDEPTH = 5000

// Symbols with ids below NSPECIAL are special-form keywords (interned first, in this order).
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
let NSPECIAL = 15
let S_ELSE = 15

// A failure. `syntax` failures are never caught by `try`.
type Fail:
    msg: String
    syntax: Bool

// Result of one evaluation step: either a finished value, or an expression to continue with.
type Step:
    done: Bool = false
    value: Int = 0
    expr: Int = 0
    env: Int = -1
    tail: Bool = false
    added: Int = 0

fn rt(msg: String) Fail:
    return Fail(msg: msg, syntax: false)

fn synerr(msg: String) Fail:
    return Fail(msg: msg, syntax: true)

fn has(xs: List[Int], v: Int) Bool:
    for x in xs:
        if x == v:
            return true
    return false

fn is_delim(c: String) Bool:
    return c == " " or c == "\n" or c == "\t" or c == "\r" or c == "(" or c == ")" or c == "\"" or c == ";"

fn is_int_text(t: String) Bool:
    let cs = t.chars()
    if cs.length() == 0:
        return false
    var i = 0
    if cs[0] == "-":
        i = 1
    if i >= cs.length():
        return false
    while i < cs.length():
        if not "0123456789".contains(cs[i]):
            return false
        i += 1
    return true

fn add_ok(a: Int, b: Int) Bool:
    if b > 0:
        return a <= INT_MAX - b
    if b < 0:
        return a >= INT_MIN - b
    return true

fn sub_ok(a: Int, b: Int) Bool:
    if b > 0:
        return a >= INT_MIN + b
    if b < 0:
        return a <= INT_MAX + b
    return true

fn mul_ok(a: Int, b: Int) Bool:
    if a == 0 or b == 0:
        return true
    if a == INT_MIN or b == INT_MIN:
        return a == 1 or b == 1
    var ua = a
    if ua < 0:
        ua = -ua
    var ub = b
    if ub < 0:
        ub = -ub
    if ua <= INT_MAX / ub:
        return true
    if (a < 0) == (b < 0):
        return false
    return ub % 2 == 0 and ua == 4611686018427387904 / (ub / 2)

fn cmp_holds(pid: Int, a: Int, b: Int) Bool:
    if pid == P_NUMEQ:
        return a == b
    if pid == P_LT:
        return a < b
    if pid == P_GT:
        return a > b
    if pid == P_LE:
        return a <= b
    return a >= b

type Interp:
    out: WriteStream[String]
    // Value heap: kind, payload, car and cdr per handle.
    hk: List[Int] = [0, 1, 2, 2]
    hp: List[Int] = [0, 0, 0, 1]
    hca: List[Int] = [0, 0, 0, 0]
    hcd: List[Int] = [0, 0, 0, 0]
    strs: List[String] = []
    symn: List[String] = []
    symmap: Map[String, Int] = Map[String, Int]()
    gval: List[Int] = []
    // Frames and bindings.
    fr_parent: List[Int] = []
    fr_head: List[Int] = []
    b_sym: List[Int] = []
    b_val: List[Int] = []
    b_next: List[Int] = []
    // Closures: parameter list (may be a bare symbol or dotted), body list, defining frame, name id (-1 anonymous).
    cl_params: List[Int] = []
    cl_body: List[Int] = []
    cl_env: List[Int] = []
    cl_name: List[Int] = []
    // Builtins: name, minimum and maximum arity (-1 means no maximum).
    prim_name: List[String] = []
    prim_min: List[Int] = []
    prim_max: List[Int] = []
    // Current nesting of non-tail procedure calls.
    depth: Int = 0
    // Nesting of closure calls made from builtins (each one uses much more native stack).
    bdepth: Int = 0
    // Reader state.
    src: List[String] = []
    pos: Int = 0
    // Output state.
    at_bol: Bool = true
    pbuf: List[String] = []

impl Interp:
    // ---------- output ----------

    var fn emit(s: String) Unit:
        if s.length() == 0:
            return
        self.out.write(s).get()
        self.at_bol = s.ends_with("\n")

    var fn report(msg: String) Unit:
        if not self.at_bol:
            self.emit("\n")
        self.emit("error: " + msg + "\n")

    // ---------- heap ----------

    var fn mk(k: Int, p: Int) Int:
        self.hk.append(k)
        self.hp.append(p)
        self.hca.append(0)
        self.hcd.append(0)
        return self.hk.length() - 1

    var fn mkint(n: Int) Int:
        return self.mk(K_INT, n)

    var fn mkbool(b: Bool) Int:
        if b:
            return TRUE
        return FALSE

    var fn mkstr(s: String) Int:
        self.strs.append(s)
        return self.mk(K_STR, self.strs.length() - 1)

    var fn mksym(id: Int) Int:
        return self.mk(K_SYM, id)

    var fn cons(a: Int, d: Int) Int:
        let h = self.mk(K_PAIR, 0)
        self.hca[h] = a
        self.hcd[h] = d
        return h

    var fn build(items: List[Int], tail: Int) Int:
        var r = tail
        var i = items.length() - 1
        while i >= 0:
            r = self.cons(items[i], r)
            i -= 1
        return r

    var fn list_from(items: List[Int]) Int:
        return self.build(items, NIL)

    // Elements of a list; the caller has checked that it is proper.
    fn to_list(h: Int) List[Int]:
        var out: List[Int] = []
        var p = h
        while self.hk[p] == K_PAIR:
            out.append(self.hca[p])
            p = self.hcd[p]
        return out

    // Number of pairs in a proper list, or -1 when the list is improper.
    fn proper_len(h: Int) Int:
        var n = 0
        var p = h
        while self.hk[p] == K_PAIR:
            n += 1
            p = self.hcd[p]
        if self.hk[p] == K_NIL:
            return n
        return -1

    fn is_proper(h: Int) Bool:
        return self.proper_len(h) >= 0

    fn is_proc(h: Int) Bool:
        return self.hk[h] == K_PRIM or self.hk[h] == K_CLOS

    var fn intern(name: String) Int:
        if let id = self.symmap.get(name):
            return id
        let id = self.symn.length()
        self.symn.append(name.clone())
        self.symmap[name.clone()] = id
        self.gval.append(-1)
        return id

    fn sym_name(id: Int) String:
        return self.symn[id].clone()

    // eq?: true only for same integer, boolean, symbol, or empty list.
    fn eqv(a: Int, b: Int) Bool:
        let ka = self.hk[a]
        if ka == K_STR or ka == K_PAIR or ka == K_PRIM or ka == K_CLOS or ka == K_VOID:
            return false
        if ka != self.hk[b]:
            return false
        return self.hp[a] == self.hp[b]

    // equal?: structural on pairs and strings.
    fn equal_v(a0: Int, b0: Int) Bool:
        var a = a0
        var b = b0
        while true:
            let ka = self.hk[a]
            if ka == K_PAIR and self.hk[b] == K_PAIR:
                if not self.equal_v(self.hca[a], self.hca[b]):
                    return false
                a = self.hcd[a]
                b = self.hcd[b]
            else if ka == K_STR:
                return self.hk[b] == K_STR and self.strs[self.hp[a]] == self.strs[self.hp[b]]
            else if ka == K_PRIM or ka == K_CLOS:
                return self.hk[b] == ka and self.hp[b] == self.hp[a]
            else:
                return self.eqv(a, b)
        return false

    // ---------- printing ----------

    var fn pr(h: Int, wr: Bool) Unit:
        let k = self.hk[h]
        if k == K_NIL:
            self.pbuf.append("()")
        else if k == K_VOID:
            self.pbuf.append("#<void>")
        else if k == K_BOOL:
            if h == TRUE:
                self.pbuf.append("#t")
            else:
                self.pbuf.append("#f")
        else if k == K_INT:
            self.pbuf.append(self.hp[h].to_string())
        else if k == K_STR:
            if wr:
                let body = self.strs[self.hp[h]].replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")
                self.pbuf.append("\"" + body + "\"")
            else:
                self.pbuf.append(self.strs[self.hp[h]].clone())
        else if k == K_SYM:
            self.pbuf.append(self.sym_name(self.hp[h]))
        else if k == K_PAIR:
            self.pbuf.append("(")
            self.pr(self.hca[h], wr)
            var p = self.hcd[h]
            while self.hk[p] == K_PAIR:
                self.pbuf.append(" ")
                self.pr(self.hca[p], wr)
                p = self.hcd[p]
            if self.hk[p] != K_NIL:
                self.pbuf.append(" . ")
                self.pr(p, wr)
            self.pbuf.append(")")
        else if k == K_PRIM:
            self.pbuf.append("#<builtin " + self.prim_name[self.hp[h]].clone() + ">")
        else:
            let cid = self.hp[h]
            if self.cl_name[cid] == -1:
                self.pbuf.append("#<procedure>")
            else:
                self.pbuf.append("#<procedure " + self.sym_name(self.cl_name[cid]) + ">")

    var fn to_text(h: Int, wr: Bool) String:
        self.pbuf = []
        self.pr(h, wr)
        return self.pbuf.join("")

    // ---------- reader ----------

    fn at_dot() Bool:
        if self.pos >= self.src.length():
            return false
        if self.src[self.pos] != ".":
            return false
        if self.pos + 1 >= self.src.length():
            return true
        return is_delim(self.src[self.pos + 1])

    var fn skip_ws() Unit:
        while self.pos < self.src.length():
            let c = self.src[self.pos].clone()
            if c == ";":
                while self.pos < self.src.length() and self.src[self.pos] != "\n":
                    self.pos += 1
            else if c == " " or c == "\n" or c == "\t" or c == "\r":
                self.pos += 1
            else:
                break

    var fn read_datum() Int!Fail:
        self.skip_ws()
        if self.pos >= self.src.length():
            return error(synerr("syntax error: unexpected end of input"))
        let c = self.src[self.pos].clone()
        if c == "(":
            self.pos += 1
            return self.read_list()
        if c == ")":
            return error(synerr("syntax error: unexpected )"))
        if c == "'":
            self.pos += 1
            let d = try self.read_datum()
            return ok(self.cons(self.mksym(S_QUOTE), self.cons(d, NIL)))
        if c == "\"":
            self.pos += 1
            return self.read_string()
        var tok = ""
        while self.pos < self.src.length() and not is_delim(self.src[self.pos]):
            tok = tok + self.src[self.pos]
            self.pos += 1
        return self.atom(tok)

    var fn read_list() Int!Fail:
        var items: List[Int] = []
        while true:
            self.skip_ws()
            if self.pos >= self.src.length():
                return error(synerr("syntax error: unexpected end of input"))
            if self.src[self.pos] == ")":
                self.pos += 1
                return ok(self.build(items, NIL))
            if self.at_dot():
                if items.length() == 0:
                    return error(synerr("syntax error: bad dotted list"))
                self.pos += 1
                self.skip_ws()
                if self.pos >= self.src.length():
                    return error(synerr("syntax error: unexpected end of input"))
                if self.src[self.pos] == ")":
                    return error(synerr("syntax error: bad dotted list"))
                let tail = try self.read_datum()
                self.skip_ws()
                if self.pos >= self.src.length():
                    return error(synerr("syntax error: unexpected end of input"))
                if self.src[self.pos] != ")":
                    return error(synerr("syntax error: bad dotted list"))
                self.pos += 1
                return ok(self.build(items, tail))
            let d = try self.read_datum()
            items.append(d)
        return ok(NIL)

    var fn read_string() Int!Fail:
        var s = ""
        while self.pos < self.src.length():
            let c = self.src[self.pos].clone()
            self.pos += 1
            if c == "\"":
                return ok(self.mkstr(s))
            if c == "\\":
                if self.pos >= self.src.length():
                    break
                let e = self.src[self.pos].clone()
                self.pos += 1
                if e == "n":
                    s = s + "\n"
                else if e == "t":
                    s = s + "\t"
                else if e == "\\":
                    s = s + "\\"
                else if e == "\"":
                    s = s + "\""
                else:
                    return error(synerr("syntax error: bad escape"))
            else:
                s = s + c
        return error(synerr("syntax error: unterminated string"))

    var fn atom(tok: String) Int!Fail:
        if tok == "#t":
            return ok(TRUE)
        if tok == "#f":
            return ok(FALSE)
        if tok.starts_with("#"):
            return error(synerr("syntax error: bad token: " + tok))
        if tok == ".":
            return error(synerr("syntax error: unexpected ."))
        if is_int_text(tok):
            if let n = tok.parse_int():
                return ok(self.mkint(n))
            return error(synerr("syntax error: integer out of range"))
        return ok(self.mksym(self.intern(tok)))

    // ---------- environments ----------

    var fn new_frame(parent: Int) Int:
        self.fr_parent.append(parent)
        self.fr_head.append(-1)
        return self.fr_parent.length() - 1

    var fn bind_new(f: Int, sym: Int, val: Int) Unit:
        self.b_sym.append(sym)
        self.b_val.append(val)
        self.b_next.append(self.fr_head[f])
        self.fr_head[f] = self.b_sym.length() - 1

    // define: binds in frame f (or the global table for -1), rebinding an existing name in that frame.
    var fn define_in(f: Int, sym: Int, val: Int) Unit:
        if f == -1:
            self.gval[sym] = val
            return
        var b = self.fr_head[f]
        while b != -1:
            if self.b_sym[b] == sym:
                self.b_val[b] = val
                return
            b = self.b_next[b]
        self.bind_new(f, sym, val)

    fn lookup(env: Int, sym: Int) Int!Fail:
        var f = env
        while f != -1:
            var b = self.fr_head[f]
            while b != -1:
                if self.b_sym[b] == sym:
                    return ok(self.b_val[b])
                b = self.b_next[b]
            f = self.fr_parent[f]
        let g = self.gval[sym]
        if g == -1:
            return error(rt("unbound variable: " + self.sym_name(sym)))
        return ok(g)

    var fn set_var(env: Int, sym: Int, val: Int) Bool:
        var f = env
        while f != -1:
            var b = self.fr_head[f]
            while b != -1:
                if self.b_sym[b] == sym:
                    self.b_val[b] = val
                    return true
                b = self.b_next[b]
            f = self.fr_parent[f]
        if self.gval[sym] == -1:
            return false
        self.gval[sym] = val
        return true

    // ---------- closures ----------

    var fn make_closure(params: Int, body: Int, env: Int, name: Int) Int:
        self.cl_params.append(params)
        self.cl_body.append(body)
        self.cl_env.append(env)
        self.cl_name.append(name)
        return self.mk(K_CLOS, self.cl_params.length() - 1)

    fn params_ok(p: Int) Bool:
        var seen: List[Int] = []
        var t = p
        while self.hk[t] == K_PAIR:
            let a = self.hca[t]
            if self.hk[a] != K_SYM:
                return false
            if has(seen, self.hp[a]):
                return false
            seen.append(self.hp[a])
            t = self.hcd[t]
        if self.hk[t] == K_NIL:
            return true
        if self.hk[t] != K_SYM:
            return false
        return not has(seen, self.hp[t])

    var fn make_lambda(x: Int, env: Int, name: Int) Int!Fail:
        if self.proper_len(x) < 3:
            return error(synerr("syntax error: bad form: lambda"))
        let params = self.hca[self.hcd[x]]
        if not self.params_ok(params):
            return error(synerr("syntax error: bad form: lambda"))
        return ok(self.make_closure(params, self.hcd[self.hcd[x]], env, name))

    fn clo_name(cid: Int) String:
        if self.cl_name[cid] == -1:
            return "lambda"
        return self.sym_name(self.cl_name[cid])

    // Builds the frame for a call of closure cid, checking the argument count.
    var fn bind_args(cid: Int, args: List[Int]) Int!Fail:
        var fixed = 0
        var t = self.cl_params[cid]
        while self.hk[t] == K_PAIR:
            fixed += 1
            t = self.hcd[t]
        let has_rest = self.hk[t] == K_SYM
        let n = args.length()
        if n < fixed or (n > fixed and not has_rest):
            var ex = fixed.to_string()
            if has_rest:
                ex = "at least " + fixed.to_string()
            return error(rt("wrong number of arguments to " + self.clo_name(cid) + ": expected " + ex + ", got " + n.to_string()))
        let env = self.new_frame(self.cl_env[cid])
        var p = self.cl_params[cid]
        var i = 0
        while self.hk[p] == K_PAIR:
            self.bind_new(env, self.hp[self.hca[p]], args[i])
            i += 1
            p = self.hcd[p]
        if has_rest:
            var rest = NIL
            var j = n - 1
            while j >= fixed:
                rest = self.cons(args[j], rest)
                j -= 1
            self.bind_new(env, self.hp[t], rest)
        return ok(env)

    // Evaluates all body expressions but the last; returns the last one unevaluated.
    var fn eval_prefix(body: Int, env: Int) Int!Fail:
        var b = body
        while self.hcd[b] != NIL:
            let _v = try self.ev(self.hca[b], env, false)
            b = self.hcd[b]
        return ok(self.hca[b])

    // Applies f to args as a call in the given position. Closures in tail position replace the
    // current evaluation (no depth change); others enter a new non-tail call.
    var fn apply_step(f: Int, args: List[Int], tail: Bool, added: Int) Step!Fail:
        let k = self.hk[f]
        if k == K_PRIM:
            let v = try self.call_prim(self.hp[f], args)
            return ok(Step(done: true, value: v, added: added))
        if k == K_CLOS:
            let cid = self.hp[f]
            let env2 = try self.bind_args(cid, args)
            var t2 = tail
            var add2 = added
            if not tail:
                if self.depth + 1 > MAX_DEPTH:
                    return error(rt("recursion limit exceeded"))
                self.depth += 1
                add2 += 1
                t2 = true
            let last = try self.eval_prefix(self.cl_body[cid], env2)
            return ok(Step(done: false, expr: last, env: env2, tail: t2, added: add2))
        return error(rt("not a procedure: " + self.to_text(f, true)))

    // Applies f to args from builtin code (always a non-tail call).
    var fn apply_value(f: Int, args: List[Int]) Int!Fail:
        let k = self.hk[f]
        if k == K_PRIM:
            return self.call_prim(self.hp[f], args)
        if k == K_CLOS:
            let cid = self.hp[f]
            if self.depth + 1 > MAX_DEPTH or self.bdepth >= MAX_BDEPTH:
                return error(rt("recursion limit exceeded"))
            self.depth += 1
            self.bdepth += 1
            let env2 = try self.bind_args(cid, args)
            let last = try self.eval_prefix(self.cl_body[cid], env2)
            let v = try self.ev(last, env2, true)
            self.depth -= 1
            self.bdepth -= 1
            return ok(v)
        return error(rt("not a procedure: " + self.to_text(f, true)))

    fn bindings_ok(bl: Int) Bool:
        if not self.is_proper(bl):
            return false
        var b = bl
        while self.hk[b] == K_PAIR:
            let bind = self.hca[b]
            if self.proper_len(bind) != 2:
                return false
            if self.hk[self.hca[bind]] != K_SYM:
                return false
            b = self.hcd[b]
        return true

    // ---------- evaluator ----------

    fn fin(v: Int, added: Int) Step:
        return Step(done: true, value: v, added: added)

    fn go(x: Int, env: Int, tail: Bool, added: Int) Step:
        return Step(done: false, expr: x, env: env, tail: tail, added: added)

    // Evaluates x in env. `tail` says whether x is in tail position of a closure body that is
    // already running, so that a closure call here does not add to the call depth.
    var fn ev(x0: Int, env0: Int, tail0: Bool) Int!Fail:
        var x = x0
        var env = env0
        var tail = tail0
        var added = 0
        while true:
            let k = self.hk[x]
            if k == K_SYM:
                let v = try self.lookup(env, self.hp[x])
                self.depth -= added
                return ok(v)
            if k == K_NIL:
                return error(synerr("syntax error: empty application"))
            if k != K_PAIR:
                self.depth -= added
                return ok(x)
            var st = Step()
            if self.hk[self.hca[x]] == K_SYM and self.hp[self.hca[x]] < NSPECIAL:
                st = try self.special(x, env, tail, added)
            else:
                st = try self.application(x, env, tail, added)
            if st.done:
                self.depth -= st.added
                return ok(st.value)
            x = st.expr
            env = st.env
            tail = st.tail
            added = st.added
        return error(rt("internal error"))

    // A call (f arg...): operator, then operands left to right, then apply.
    var fn application(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        if self.proper_len(x) < 0:
            return error(synerr("syntax error: bad application"))
        let f = try self.ev(self.hca[x], env, false)
        var args: List[Int] = []
        var a = self.hcd[x]
        while self.hk[a] == K_PAIR:
            let v = try self.ev(self.hca[a], env, false)
            args.append(v)
            a = self.hcd[a]
        if self.hk[f] == K_PRIM:
            let pv = try self.call_prim(self.hp[f], args)
            return ok(self.fin(pv, added))
        return self.apply_step(f, args, tail, added)

    var fn special(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        let sid = self.hp[self.hca[x]]
        if self.proper_len(x) < 0:
            return error(synerr("syntax error: bad form: " + self.sym_name(sid)))
        if sid == S_QUOTE:
            return self.sf_quote(x, added)
        if sid == S_IF:
            return self.sf_if(x, env, tail, added)
        if sid == S_DEFINE:
            return self.sf_define(x, env, added)
        if sid == S_SET:
            return self.sf_set(x, env, added)
        if sid == S_LAMBDA:
            return self.sf_lambda(x, env, added)
        if sid == S_BEGIN:
            return self.sf_begin(x, env, tail, added)
        if sid == S_LET:
            return self.sf_let(x, env, tail, added)
        if sid == S_LETSTAR or sid == S_LETREC:
            return self.sf_letstar(x, env, tail, added, sid)
        if sid == S_COND:
            return self.sf_cond(x, env, tail, added)
        if sid == S_AND:
            return self.sf_and(x, env, tail, added)
        if sid == S_OR:
            return self.sf_or(x, env, tail, added)
        if sid == S_WHEN or sid == S_UNLESS:
            return self.sf_when(x, env, tail, added, sid)
        if sid == S_TRY:
            return self.sf_try(x, env, added)
        return error(synerr("syntax error: bad form"))

    var fn sf_quote(x: Int, added: Int) Step!Fail:
        if self.proper_len(x) != 2:
            return error(synerr("syntax error: bad form: quote"))
        return ok(self.fin(self.hca[self.hcd[x]], added))

    var fn sf_if(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        let n = self.proper_len(x)
        if n != 3 and n != 4:
            return error(synerr("syntax error: bad form: if"))
        let tv = try self.ev(self.hca[self.hcd[x]], env, false)
        let rest = self.hcd[self.hcd[x]]
        if tv != FALSE:
            return ok(self.go(self.hca[rest], env, tail, added))
        if self.hcd[rest] != NIL:
            return ok(self.go(self.hca[self.hcd[rest]], env, tail, added))
        return ok(self.fin(VOID, added))

    var fn sf_define(x: Int, env: Int, added: Int) Step!Fail:
        let n = self.proper_len(x)
        if n < 3:
            return error(synerr("syntax error: bad form: define"))
        let target = self.hca[self.hcd[x]]
        if self.hk[target] == K_PAIR:
            let nm = self.hca[target]
            if self.hk[nm] != K_SYM or not self.params_ok(self.hcd[target]):
                return error(synerr("syntax error: bad form: define"))
            let clo = self.make_closure(self.hcd[target], self.hcd[self.hcd[x]], env, self.hp[nm])
            self.define_in(env, self.hp[nm], clo)
            return ok(self.fin(VOID, added))
        if self.hk[target] != K_SYM or n != 3:
            return error(synerr("syntax error: bad form: define"))
        let vexpr = self.hca[self.hcd[self.hcd[x]]]
        var v = 0
        if self.hk[vexpr] == K_PAIR and self.hk[self.hca[vexpr]] == K_SYM and self.hp[self.hca[vexpr]] == S_LAMBDA:
            v = try self.make_lambda(vexpr, env, self.hp[target])
        else:
            v = try self.ev(vexpr, env, false)
        self.define_in(env, self.hp[target], v)
        return ok(self.fin(VOID, added))

    var fn sf_set(x: Int, env: Int, added: Int) Step!Fail:
        if self.proper_len(x) != 3 or self.hk[self.hca[self.hcd[x]]] != K_SYM:
            return error(synerr("syntax error: bad form: set!"))
        let sym = self.hp[self.hca[self.hcd[x]]]
        let v = try self.ev(self.hca[self.hcd[self.hcd[x]]], env, false)
        if not self.set_var(env, sym, v):
            return error(rt("unbound variable: " + self.sym_name(sym)))
        return ok(self.fin(VOID, added))

    var fn sf_lambda(x: Int, env: Int, added: Int) Step!Fail:
        let clo = try self.make_lambda(x, env, -1)
        return ok(self.fin(clo, added))

    var fn sf_begin(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        if self.hcd[x] == NIL:
            return ok(self.fin(VOID, added))
        let last = try self.eval_prefix(self.hcd[x], env)
        return ok(self.go(last, env, tail, added))

    var fn sf_let(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        let n = self.proper_len(x)
        if n < 3:
            return error(synerr("syntax error: bad form: let"))
        let second = self.hca[self.hcd[x]]
        if self.hk[second] == K_SYM:
            // Named let: the loop procedure lives in a frame of its own.
            if n < 4 or not self.bindings_ok(self.hca[self.hcd[self.hcd[x]]]):
                return error(synerr("syntax error: bad form: let"))
            let bl = self.hca[self.hcd[self.hcd[x]]]
            let body = self.hcd[self.hcd[self.hcd[x]]]
            var vars: List[Int] = []
            var vals: List[Int] = []
            var b = bl
            while self.hk[b] == K_PAIR:
                let bind = self.hca[b]
                vars.append(self.hca[bind])
                let iv = try self.ev(self.hca[self.hcd[bind]], env, false)
                vals.append(iv)
                b = self.hcd[b]
            let loopenv = self.new_frame(env)
            let clo = self.make_closure(self.list_from(vars), body, loopenv, self.hp[second])
            self.define_in(loopenv, self.hp[second], clo)
            return self.apply_step(clo, vals, tail, added)
        if not self.bindings_ok(second):
            return error(synerr("syntax error: bad form: let"))
        let newf = self.new_frame(env)
        var b = second
        while self.hk[b] == K_PAIR:
            let bind = self.hca[b]
            let iv = try self.ev(self.hca[self.hcd[bind]], env, false)
            self.bind_new(newf, self.hp[self.hca[bind]], iv)
            b = self.hcd[b]
        let last = try self.eval_prefix(self.hcd[self.hcd[x]], newf)
        return ok(self.go(last, newf, tail, added))

    var fn sf_letstar(x: Int, env: Int, tail: Bool, added: Int, sid: Int) Step!Fail:
        let n = self.proper_len(x)
        if n < 3 or not self.bindings_ok(self.hca[self.hcd[x]]):
            return error(synerr("syntax error: bad form: " + self.sym_name(sid)))
        let newf = self.new_frame(env)
        var b = self.hca[self.hcd[x]]
        while self.hk[b] == K_PAIR:
            let bind = self.hca[b]
            let iv = try self.ev(self.hca[self.hcd[bind]], newf, false)
            self.define_in(newf, self.hp[self.hca[bind]], iv)
            b = self.hcd[b]
        let last = try self.eval_prefix(self.hcd[self.hcd[x]], newf)
        return ok(self.go(last, newf, tail, added))

    var fn sf_cond(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        var cl = self.hcd[x]
        var body = NIL
        var found = false
        while self.hk[cl] == K_PAIR:
            let clause = self.hca[cl]
            if self.hk[clause] != K_PAIR:
                return error(synerr("syntax error: bad form: cond"))
            if self.hk[self.hca[clause]] == K_SYM and self.hp[self.hca[clause]] == S_ELSE:
                if self.hcd[cl] != NIL or self.hcd[clause] == NIL:
                    return error(synerr("syntax error: bad form: cond"))
                body = self.hcd[clause]
                found = true
                break
            let v = try self.ev(self.hca[clause], env, false)
            if v != FALSE:
                if self.hcd[clause] == NIL:
                    return ok(self.fin(v, added))
                body = self.hcd[clause]
                found = true
                break
            cl = self.hcd[cl]
        if not found:
            return ok(self.fin(VOID, added))
        let last = try self.eval_prefix(body, env)
        return ok(self.go(last, env, tail, added))

    var fn sf_and(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        if self.hcd[x] == NIL:
            return ok(self.fin(TRUE, added))
        var a = self.hcd[x]
        while self.hk[self.hcd[a]] == K_PAIR:
            let v = try self.ev(self.hca[a], env, false)
            if v == FALSE:
                return ok(self.fin(v, added))
            a = self.hcd[a]
        return ok(self.go(self.hca[a], env, tail, added))

    var fn sf_or(x: Int, env: Int, tail: Bool, added: Int) Step!Fail:
        if self.hcd[x] == NIL:
            return ok(self.fin(FALSE, added))
        var o = self.hcd[x]
        while self.hk[self.hcd[o]] == K_PAIR:
            let v = try self.ev(self.hca[o], env, false)
            if v != FALSE:
                return ok(self.fin(v, added))
            o = self.hcd[o]
        return ok(self.go(self.hca[o], env, tail, added))

    var fn sf_when(x: Int, env: Int, tail: Bool, added: Int, sid: Int) Step!Fail:
        if self.proper_len(x) < 3:
            return error(synerr("syntax error: bad form: " + self.sym_name(sid)))
        let c = try self.ev(self.hca[self.hcd[x]], env, false)
        var fires = c != FALSE
        if sid == S_UNLESS:
            fires = c == FALSE
        if not fires:
            return ok(self.fin(VOID, added))
        let last = try self.eval_prefix(self.hcd[self.hcd[x]], env)
        return ok(self.go(last, env, tail, added))

    var fn sf_try(x: Int, env: Int, added: Int) Step!Fail:
        if self.proper_len(x) != 3:
            return error(synerr("syntax error: bad form: try"))
        let saved = self.depth
        let saved_b = self.bdepth
        let r = self.ev(self.hca[self.hcd[x]], env, false)
        if r.is_ok():
            return ok(self.fin(r.get(0), added))
        let e = r.err()
        if e.syntax:
            return error(e)
        self.depth = saved
        self.bdepth = saved_b
        let h = try self.ev(self.hca[self.hcd[self.hcd[x]]], env, false)
        var argv: List[Int] = []
        argv.append(self.mkstr(e.msg))
        let v = try self.apply_value(h, argv)
        return ok(self.fin(v, added))

    // ---------- builtin helpers ----------

    var fn kind_err(name: String, kind: String, h: Int) Fail:
        return rt(name + ": expected " + kind + ", got " + self.to_text(h, true))

    var fn ints_of(name: String, args: List[Int]) List[Int]!Fail:
        var out: List[Int] = []
        for a in args:
            if self.hk[a] != K_INT:
                return error(self.kind_err(name, "integer", a))
            out.append(self.hp[a])
        return ok(out)

    var fn int1(name: String, h: Int) Int!Fail:
        if self.hk[h] != K_INT:
            return error(self.kind_err(name, "integer", h))
        return ok(self.hp[h])

    var fn str_of(name: String, h: Int) String!Fail:
        if self.hk[h] != K_STR:
            return error(self.kind_err(name, "string", h))
        return ok(self.strs[self.hp[h]].clone())

    var fn list_of(name: String, h: Int) List[Int]!Fail:
        if not self.is_proper(h):
            return error(self.kind_err(name, "list", h))
        return ok(self.to_list(h))

    var fn proc_of(name: String, h: Int) Int!Fail:
        if not self.is_proc(h):
            return error(self.kind_err(name, "procedure", h))
        return ok(h)

    var fn cxr(name: String, path: String, h: Int) Int!Fail:
        var v = h
        var i = path.length() - 1
        while i >= 0:
            if self.hk[v] != K_PAIR:
                return error(self.kind_err(name, "pair", v))
            if path.drop(i).take(1) == "a":
                v = self.hca[v]
            else:
                v = self.hcd[v]
            i -= 1
        return ok(v)

    var fn all_pairs(cur: List[Int]) Bool:
        for c in cur:
            if self.hk[c] != K_PAIR:
                return false
        return true

    var fn msort(xs: List[Int], less: Int) List[Int]!Fail:
        let n = xs.length()
        if n <= 1:
            return ok(xs)
        var left: List[Int] = []
        var right: List[Int] = []
        let mid = n / 2
        for i in 0..mid:
            left.append(xs[i])
        for i in mid..n:
            right.append(xs[i])
        let ls = try self.msort(left, less)
        let rs = try self.msort(right, less)
        var out: List[Int] = []
        var i = 0
        var j = 0
        while i < ls.length() and j < rs.length():
            var pa: List[Int] = []
            pa.append(rs[j])
            pa.append(ls[i])
            let t = try self.apply_value(less, pa)
            if t != FALSE:
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

    var fn defprim(name: String, mn: Int, mx: Int) Unit:
        let pid = self.prim_name.length()
        self.prim_name.append(name.clone())
        self.prim_min.append(mn)
        self.prim_max.append(mx)
        let sym = self.intern(name.clone())
        let pv = self.mk(K_PRIM, pid)
        self.gval[sym] = pv

    // ---------- builtins ----------

    var fn call_prim(pid: Int, args: List[Int]) Int!Fail:
        let n = args.length()
        let mn = self.prim_min[pid]
        let mx = self.prim_max[pid]
        if n < mn or (mx != -1 and n > mx):
            return error(self.arity_err(pid, n))
        if pid <= P_MAX:
            return self.prim_arith(pid, args)
        if pid <= P_ODDP:
            return self.prim_cmp(pid, args)
        if pid <= P_EQUALP:
            return self.prim_pred(pid, args)
        if pid <= P_MEMBER:
            return self.prim_list(pid, args)
        if pid <= P_SORT:
            return self.prim_hof(pid, args)
        if pid <= P_STRCONTAINS:
            return self.prim_str(pid, args)
        return self.prim_io(pid, args)

    var fn arity_err(pid: Int, n: Int) Fail:
        let mn = self.prim_min[pid]
        let mx = self.prim_max[pid]
        var ex = ""
        if mx == -1:
            ex = "at least " + mn.to_string()
        else if mn == mx:
            ex = mn.to_string()
        else:
            ex = mn.to_string() + " to " + mx.to_string()
        return rt("wrong number of arguments to " + self.prim_name[pid].clone() + ": expected " + ex + ", got " + n.to_string())

    var fn prim_arith(pid: Int, args: List[Int]) Int!Fail:
        // Arithmetic.
        if pid == P_ADD:
            let xs = try self.ints_of("+", args)
            var acc = 0
            for v in xs:
                if not add_ok(acc, v):
                    return error(rt("integer overflow"))
                acc += v
            return ok(self.mkint(acc))

        if pid == P_SUB:
            let xs = try self.ints_of("-", args)
            if xs.length() == 1:
                if xs[0] == INT_MIN:
                    return error(rt("integer overflow"))
                return ok(self.mkint(-xs[0]))
            var acc = xs[0]
            var i = 1
            while i < xs.length():
                if not sub_ok(acc, xs[i]):
                    return error(rt("integer overflow"))
                acc -= xs[i]
                i += 1
            return ok(self.mkint(acc))

        if pid == P_MUL:
            let xs = try self.ints_of("*", args)
            var acc = 1
            for v in xs:
                if not mul_ok(acc, v):
                    return error(rt("integer overflow"))
                acc = acc * v
            return ok(self.mkint(acc))

        if pid == P_QUOT or pid == P_REM or pid == P_MOD:
            let xs = try self.ints_of(self.prim_name[pid].clone(), args)
            let a = xs[0]
            let b = xs[1]
            if b == 0:
                return error(rt("division by zero"))
            if pid == P_QUOT:
                if a == INT_MIN and b == -1:
                    return error(rt("integer overflow"))
                return ok(self.mkint(a / b))
            if b == -1:
                return ok(self.mkint(0))
            var m = a % b
            if pid == P_MOD and m != 0 and ((m < 0) != (b < 0)):
                m = m + b
            return ok(self.mkint(m))

        if pid == P_ABS:
            let xs = try self.ints_of("abs", args)
            if xs[0] == INT_MIN:
                return error(rt("integer overflow"))
            if xs[0] < 0:
                return ok(self.mkint(-xs[0]))
            return ok(self.mkint(xs[0]))

        if pid == P_MIN or pid == P_MAX:
            let xs = try self.ints_of(self.prim_name[pid].clone(), args)
            var best = xs[0]
            for v in xs:
                if pid == P_MIN and v < best:
                    best = v
                if pid == P_MAX and v > best:
                    best = v
            return ok(self.mkint(best))

        return error(rt("internal error: unknown builtin"))

    var fn prim_cmp(pid: Int, args: List[Int]) Int!Fail:
        if pid == P_NUMEQ or pid == P_LT or pid == P_GT or pid == P_LE or pid == P_GE:
            let xs = try self.ints_of(self.prim_name[pid].clone(), args)
            var i = 0
            var holds = true
            while i + 1 < xs.length():
                if not cmp_holds(pid, xs[i], xs[i + 1]):
                    holds = false
                i += 1
            return ok(self.mkbool(holds))

        if pid == P_ZEROP or pid == P_EVENP or pid == P_ODDP:
            let xs = try self.ints_of(self.prim_name[pid].clone(), args)
            let v = xs[0]
            if pid == P_ZEROP:
                return ok(self.mkbool(v == 0))
            if pid == P_EVENP:
                return ok(self.mkbool(v % 2 == 0))
            return ok(self.mkbool(v % 2 != 0))

        return error(rt("internal error: unknown builtin"))

    var fn prim_pred(pid: Int, args: List[Int]) Int!Fail:
        // Predicates and equality.
        if pid == P_NOT:
            return ok(self.mkbool(args[0] == FALSE))
        if pid == P_NULLP:
            return ok(self.mkbool(self.hk[args[0]] == K_NIL))
        if pid == P_PAIRP:
            return ok(self.mkbool(self.hk[args[0]] == K_PAIR))
        if pid == P_LISTP:
            return ok(self.mkbool(self.is_proper(args[0])))
        if pid == P_NUMBERP:
            return ok(self.mkbool(self.hk[args[0]] == K_INT))
        if pid == P_STRINGP:
            return ok(self.mkbool(self.hk[args[0]] == K_STR))
        if pid == P_SYMBOLP:
            return ok(self.mkbool(self.hk[args[0]] == K_SYM))
        if pid == P_BOOLEANP:
            return ok(self.mkbool(self.hk[args[0]] == K_BOOL))
        if pid == P_PROCP:
            return ok(self.mkbool(self.is_proc(args[0])))
        if pid == P_EQP:
            return ok(self.mkbool(self.eqv(args[0], args[1])))
        if pid == P_EQUALP:
            return ok(self.mkbool(self.equal_v(args[0], args[1])))

        return error(rt("internal error: unknown builtin"))

    var fn prim_list(pid: Int, args: List[Int]) Int!Fail:
        let n = args.length()
        // Pairs and lists.
        if pid == P_CONS:
            return ok(self.cons(args[0], args[1]))
        if pid == P_CAR:
            return self.cxr("car", "a", args[0])
        if pid == P_CDR:
            return self.cxr("cdr", "d", args[0])
        if pid == P_CADR:
            return self.cxr("cadr", "ad", args[0])
        if pid == P_CDDR:
            return self.cxr("cddr", "dd", args[0])
        if pid == P_CADDR:
            return self.cxr("caddr", "add", args[0])
        if pid == P_SETCAR:
            if self.hk[args[0]] != K_PAIR:
                return error(self.kind_err("set-car!", "pair", args[0]))
            self.hca[args[0]] = args[1]
            return ok(VOID)
        if pid == P_SETCDR:
            if self.hk[args[0]] != K_PAIR:
                return error(self.kind_err("set-cdr!", "pair", args[0]))
            self.hcd[args[0]] = args[1]
            return ok(VOID)
        if pid == P_LIST:
            return ok(self.list_from(args))
        if pid == P_LENGTH:
            let items = try self.list_of("length", args[0])
            return ok(self.mkint(items.length()))
        if pid == P_APPEND:
            if n == 0:
                return ok(NIL)
            var result = args[n - 1]
            var i = n - 2
            while i >= 0:
                let items = try self.list_of("append", args[i])
                result = self.build(items, result)
                i -= 1
            return ok(result)
        if pid == P_REVERSE:
            let items = try self.list_of("reverse", args[0])
            var r = NIL
            for v in items:
                r = self.cons(v, r)
            return ok(r)
        if pid == P_LISTREF:
            let items = try self.list_of("list-ref", args[0])
            let k = try self.int1("list-ref", args[1])
            if k < 0 or k >= items.length():
                return error(rt("list-ref: index out of range"))
            return ok(items[k])
        if pid == P_LISTTAIL:
            if not self.is_proper(args[0]):
                return error(self.kind_err("list-tail", "list", args[0]))
            let k = try self.int1("list-tail", args[1])
            if k < 0:
                return error(rt("list-tail: index out of range"))
            var p = args[0]
            var i = 0
            while i < k:
                if self.hk[p] != K_PAIR:
                    return error(rt("list-tail: index out of range"))
                p = self.hcd[p]
                i += 1
            return ok(p)
        if pid == P_RANGE:
            let xs = try self.ints_of("range", args)
            var r = NIL
            var i = xs[1] - 1
            while i >= xs[0]:
                r = self.cons(self.mkint(i), r)
                i -= 1
            return ok(r)
        if pid == P_ASSOC:
            var p = args[1]
            while self.hk[p] == K_PAIR:
                let e = self.hca[p]
                if self.hk[e] != K_PAIR:
                    return error(self.kind_err("assoc", "pair", e))
                if self.equal_v(args[0], self.hca[e]):
                    return ok(e)
                p = self.hcd[p]
            if self.hk[p] != K_NIL:
                return error(self.kind_err("assoc", "list", args[1]))
            return ok(FALSE)
        if pid == P_MEMBER:
            if not self.is_proper(args[1]):
                return error(self.kind_err("member", "list", args[1]))
            var p = args[1]
            while self.hk[p] == K_PAIR:
                if self.equal_v(args[0], self.hca[p]):
                    return ok(p)
                p = self.hcd[p]
            return ok(FALSE)

        return error(rt("internal error: unknown builtin"))

    var fn prim_map(pid: Int, args: List[Int]) Int!Fail:
        let n = args.length()
        let nm = self.prim_name[pid].clone()
        let f = try self.proc_of(nm, args[0])
        var cur: List[Int] = []
        var i = 1
        while i < n:
            if not self.is_proper(args[i]):
                return error(self.kind_err(nm, "list", args[i]))
            cur.append(args[i])
            i += 1
        var results: List[Int] = []
        while self.all_pairs(cur):
            var argv: List[Int] = []
            for j in 0..cur.length():
                argv.append(self.hca[cur[j]])
                cur[j] = self.hcd[cur[j]]
            let v = try self.apply_value(f, argv)
            if pid == P_MAP:
                results.append(v)
        if pid == P_FOREACH:
            return ok(VOID)
        return ok(self.list_from(results))


    var fn prim_hof(pid: Int, args: List[Int]) Int!Fail:
        let n = args.length()
        if pid == P_MAP or pid == P_FOREACH:
            return self.prim_map(pid, args)
        if pid == P_FILTER:
            let f = try self.proc_of("filter", args[0])
            let items = try self.list_of("filter", args[1])
            var keep: List[Int] = []
            for v in items:
                var argv: List[Int] = []
                argv.append(v)
                let t = try self.apply_value(f, argv)
                if t != FALSE:
                    keep.append(v)
            return ok(self.list_from(keep))

        if pid == P_FOLD:
            let f = try self.proc_of("fold", args[0])
            let items = try self.list_of("fold", args[2])
            var acc = args[1]
            for v in items:
                var argv: List[Int] = []
                argv.append(acc)
                argv.append(v)
                acc = try self.apply_value(f, argv)
            return ok(acc)

        if pid == P_FOLDR:
            let f = try self.proc_of("foldr", args[0])
            let items = try self.list_of("foldr", args[2])
            var acc = args[1]
            var i = items.length() - 1
            while i >= 0:
                var argv: List[Int] = []
                argv.append(items[i])
                argv.append(acc)
                acc = try self.apply_value(f, argv)
                i -= 1
            return ok(acc)

        if pid == P_APPLY:
            let f = try self.proc_of("apply", args[0])
            let tail_items = try self.list_of("apply", args[n - 1])
            var argv: List[Int] = []
            var i = 1
            while i < n - 1:
                argv.append(args[i])
                i += 1
            for v in tail_items:
                argv.append(v)
            return self.apply_value(f, argv)

        if pid == P_SORT:
            let less = try self.proc_of("sort", args[1])
            let items = try self.list_of("sort", args[0])
            let sorted = try self.msort(items, less)
            return ok(self.list_from(sorted))

        return error(rt("internal error: unknown builtin"))

    var fn prim_str(pid: Int, args: List[Int]) Int!Fail:
        // Strings and symbols.
        if pid == P_STRLEN:
            let s = try self.str_of("string-length", args[0])
            return ok(self.mkint(s.length()))
        if pid == P_STRAPPEND:
            var acc = ""
            for a in args:
                let s = try self.str_of("string-append", a)
                acc = acc + s
            return ok(self.mkstr(acc))
        if pid == P_SUBSTR:
            let s = try self.str_of("substring", args[0])
            let st = try self.int1("substring", args[1])
            let en = try self.int1("substring", args[2])
            if st < 0 or st > en or en > s.length():
                return error(rt("substring: index out of range"))
            return ok(self.mkstr(s.drop(st).take(en - st)))
        if pid == P_STRREF:
            let s = try self.str_of("string-ref", args[0])
            let i = try self.int1("string-ref", args[1])
            if i < 0 or i >= s.length():
                return error(rt("string-ref: index out of range"))
            return ok(self.mkstr(s.drop(i).take(1)))
        if pid == P_STREQ:
            let a = try self.str_of("string=?", args[0])
            let b = try self.str_of("string=?", args[1])
            return ok(self.mkbool(a == b))
        if pid == P_STRLT:
            let a = try self.str_of("string<?", args[0])
            let b = try self.str_of("string<?", args[1])
            return ok(self.mkbool(a.compare(b) < 0))
        if pid == P_STRUP:
            let s = try self.str_of("string-upcase", args[0])
            return ok(self.mkstr(s.upper()))
        if pid == P_STRDOWN:
            let s = try self.str_of("string-downcase", args[0])
            return ok(self.mkstr(s.lower()))
        if pid == P_STR2NUM:
            let s = try self.str_of("string->number", args[0])
            if is_int_text(s):
                if let v = s.parse_int():
                    return ok(self.mkint(v))
            return ok(FALSE)
        if pid == P_NUM2STR:
            let v = try self.int1("number->string", args[0])
            return ok(self.mkstr(v.to_string()))
        if pid == P_STR2SYM:
            let s = try self.str_of("string->symbol", args[0])
            return ok(self.mksym(self.intern(s)))
        if pid == P_SYM2STR:
            if self.hk[args[0]] != K_SYM:
                return error(self.kind_err("symbol->string", "symbol", args[0]))
            return ok(self.mkstr(self.sym_name(self.hp[args[0]])))
        if pid == P_STR2LIST:
            let s = try self.str_of("string->list", args[0])
            var items: List[Int] = []
            for ch in s.chars():
                items.append(self.mkstr(ch.clone()))
            return ok(self.list_from(items))
        if pid == P_LIST2STR:
            let items = try self.list_of("list->string", args[0])
            var acc = ""
            for v in items:
                if self.hk[v] != K_STR:
                    return error(self.kind_err("list->string", "string", v))
                acc = acc + self.strs[self.hp[v]]
            return ok(self.mkstr(acc))
        if pid == P_STRJOIN:
            let items = try self.list_of("string-join", args[0])
            let sep = try self.str_of("string-join", args[1])
            var parts: List[String] = []
            for v in items:
                if self.hk[v] != K_STR:
                    return error(self.kind_err("string-join", "string", v))
                parts.append(self.strs[self.hp[v]].clone())
            return ok(self.mkstr(parts.join(sep)))
        if pid == P_STRSPLIT:
            let s = try self.str_of("string-split", args[0])
            let sep = try self.str_of("string-split", args[1])
            if sep.length() != 1:
                return error(rt("string-split: separator must be one character"))
            var items: List[Int] = []
            if s.length() == 0:
                items.append(self.mkstr(""))
            else:
                for part in s.split(sep, none):
                    items.append(self.mkstr(part.clone()))
            return ok(self.list_from(items))
        if pid == P_STRCONTAINS:
            let s = try self.str_of("string-contains?", args[0])
            let sub = try self.str_of("string-contains?", args[1])
            return ok(self.mkbool(s.contains(sub)))

        return error(rt("internal error: unknown builtin"))

    var fn prim_io(pid: Int, args: List[Int]) Int!Fail:
        let n = args.length()
        // Output and misc.
        if pid == P_DISPLAY:
            self.emit(self.to_text(args[0], false))
            return ok(VOID)
        if pid == P_WRITE:
            self.emit(self.to_text(args[0], true))
            return ok(VOID)
        if pid == P_NEWLINE:
            self.emit("\n")
            return ok(VOID)
        if pid == P_VOID:
            return ok(VOID)
        if pid == P_ERROR:
            var msg = try self.str_of("error", args[0])
            var i = 1
            while i < n:
                msg = msg + " " + self.to_text(args[i], true)
                i += 1
            return error(rt(msg))

        return error(rt("internal error: unknown builtin"))


    var fn setup() Unit:
        let specials = ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try", "else"]
        for nm in specials:
            let _s = self.intern(nm)
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

    // ---------- reader driver ----------

    var fn run_form(form: Int) Bool:
        self.depth = 0
        self.bdepth = 0
        let r = self.ev(form, -1, false)
        if r.is_error():
            self.report(r.err().msg)
            return false
        return true

export fn main() Int:
    let data = read_all(stdin(), none).get()
    let text = data.decode_utf8().get()
    var it = Interp(out: stdout(), src: text.chars())
    it.setup()
    while true:
        it.skip_ws()
        if it.pos >= it.src.length():
            break
        let r = it.read_datum()
        if r.is_error():
            it.report(r.err().msg)
            break
        if not it.run_form(r.get(NIL)):
            break
    it.out.flush().get()
    return 0
