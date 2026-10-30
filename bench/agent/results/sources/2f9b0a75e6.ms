import read_all, stdin, stdout from "@std/io.ms"
import Bytes from "@std/bytes.ms"

# Value kinds. A value is a copyable (kind, n) pair; heap objects live in
# the Heap arenas and `n` is an index into the matching arena.
let K_VOID = 0
let K_BOOL = 1
let K_INT = 2
let K_NIL = 3
let K_PAIR = 4
let K_STR = 5
let K_SYM = 6
let K_PRIM = 7
let K_CLO = 8
# Special forms are interned first, so their symbol ids are these constants.
# Ids below NSPECIAL are special form keywords.
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
# Primitive codes, in registration order (see reg_prims).
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
let P_ZERO = 14
let P_EVEN = 15
let P_ODD = 16
let P_NOT = 17
let P_NULL = 18
let P_PAIRP = 19
let P_LISTP = 20
let P_NUMBERP = 21
let P_STRINGP = 22
let P_SYMBOLP = 23
let P_BOOLP = 24
let P_PROCP = 25
let P_EQ = 26
let P_EQUAL = 27
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
let P_SUBSTRING = 54
let P_STRREF = 55
let P_STREQ = 56
let P_STRLT = 57
let P_UPCASE = 58
let P_DOWNCASE = 59
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
# Groups of primitive codes, used to dispatch in prim_apply.
let P_PRED = 17
let P_PAIR = 28
let P_HO = 45
let P_STR = 52
let P_MISC = 69
let MAX_INT = 9223372036854775807
let MIN_INT = -9223372036854775807 - 1
let MAX_DEPTH = 10000
let FRAME_SHIFT = 4294967296
let SPECIAL_NAMES = [
    "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond",
    "and", "or", "when", "unless", "try", "else"
]

type V:
    kind: Int
    n: Int

type Clo:
    formals: V
    body: V
    env: Int
    name: Int

type Fail:
    msg: String
    syntax: Bool

impl Error for Fail:
    fn message() String:
        return self.msg.clone()

type Heap:
    cars: List[V]
    cdrs: List[V]
    strs: List[String]
    syms: List[String]
    symids: Map[String, Int]
    parents: List[Int]
    binds: Map[Int, V]
    clos: List[Clo]
    pnames: List[String]
    pmin: List[Int]
    pmax: List[Int]
    src: Bytes
    n: Int
    pos: Int
    out_any: Bool
    out_nl: Bool

# What a special form leaves behind: either a finished value, or an
# expression to continue evaluating in the loop of eval_expr.
type Step:
    done: Bool
    value: V
    expr: V
    env: Int
    depth: Int
    tail: Bool

fn void_v() V:
    return V(K_VOID, 0)

fn nil_v() V:
    return V(K_NIL, 0)

fn int_val(n: Int) V:
    return V(K_INT, n)

fn vbool(b: Bool) V:
    if b:
        return V(K_BOOL, 1)

    return V(K_BOOL, 0)

fn is_true(v: V) Bool:
    return not (v.kind == K_BOOL and v.n == 0)

fn is_proc(v: V) Bool:
    return v.kind == K_PRIM or v.kind == K_CLO

fn finish(v: V) Step:
    return Step(done: true, value: v, expr: void_v(), env: 0, depth: 0, tail: false)

fn jump(e: V, env: Int, depth: Int, tail: Bool) Step:
    return Step(
        done: false, value: void_v(), expr: e, env: env, depth: depth, tail: tail
    )

fn syn_err(msg: String) Fail:
    return Fail("syntax error: {msg}", true)

fn rt_err(msg: String) Fail:
    return Fail(msg, false)

fn bad_form(h: Heap, sid: Int) Fail:
    return Fail("syntax error: bad form: {h.syms[sid]}", true)

fn key(frame: Int, sym: Int) Int:
    return frame * FRAME_SHIFT + sym

fn intern(var h: Heap, name: String) Int:
    if let id = h.symids.get(name):
        return id

    let id = h.syms.length()
    h.syms.append(name.clone())
    h.symids.add(name.clone(), id)
    return id

fn str_val(var h: Heap, s: String) V:
    h.strs.append(s)
    return V(K_STR, h.strs.length() - 1)

fn cons(var h: Heap, a: V, d: V) V:
    h.cars.append(a)
    h.cdrs.append(d)
    return V(K_PAIR, h.cars.length() - 1)

fn car_of(h: Heap, v: V) V:
    return h.cars[v.n]

fn cdr_of(h: Heap, v: V) V:
    return h.cdrs[v.n]

# Element i of a list (0 is the car of the list itself).
fn nth(h: Heap, v: V, i: Int) V:
    var cur = v
    var k = 0

    while k < i:
        cur = cdr_of(h, cur)
        k += 1

    return car_of(h, cur)

# The list after its first k pairs.
fn drop(h: Heap, v: V, k: Int) V:
    var cur = v
    var i = 0

    while i < k:
        cur = cdr_of(h, cur)
        i += 1

    return cur

# Number of pairs in a proper list, or -1 when the list is not proper.
fn list_len(h: Heap, v: V) Int:
    var n = 0
    var cur = v

    while cur.kind == K_PAIR:
        n += 1
        cur = cdr_of(h, cur)

    if cur.kind != K_NIL:
        return -1

    return n

fn to_vec(h: Heap, v: V) List[V]:
    var out = List[V]()
    var cur = v

    while cur.kind == K_PAIR:
        out.append(car_of(h, cur))
        cur = cdr_of(h, cur)

    return out

# Conses items[0..] in front of tail, keeping their order.
fn prepend_list(var h: Heap, items: List[V], tail: V) V:
    var acc = tail
    var i = items.length() - 1

    while i >= 0:
        acc = cons(var h, items[i], acc)
        i -= 1

    return acc

fn quote_str(s: String) String:
    let a = s.split("\\").join("\\\\")
    let b = a.split("\"").join("\\\"")
    let c = b.split("\n").join("\\n")
    let d = c.split("\t").join("\\t")
    return "\"{d}\""

fn atom_text(h: Heap, v: V, readable: Bool) String:
    if v.kind == K_INT:
        return v.n.to_string_radix(10)

    if v.kind == K_BOOL:
        if v.n == 1:
            return "#t"

        return "#f"

    if v.kind == K_STR:
        if readable:
            return quote_str(h.strs[v.n])

        return h.strs[v.n].clone()

    if v.kind == K_SYM:
        return h.syms[v.n].clone()
    if v.kind == K_NIL:
        return "()"
    if v.kind == K_VOID:
        return "#<void>"
    if v.kind == K_PRIM:
        return "#<builtin {h.pnames[v.n]}>"

    let name = h.clos[v.n].name
    if name < 0:
        return "#<procedure>"

    return "#<procedure {h.syms[name]}>"

fn put(h: Heap, v: V, readable: Bool, var parts: List[String]) Unit:
    if v.kind != K_PAIR:
        parts.append(atom_text(h, v, readable))
    else:
        parts.append("(")

        var cur = v
        var first = true

        while cur.kind == K_PAIR:
            if not first:
                parts.append(" ")
            first = false
            put(h, car_of(h, cur), readable, var parts)
            cur = cdr_of(h, cur)

        if cur.kind != K_NIL:
            parts.append(" . ")
            put(h, cur, readable, var parts)

        parts.append(")")

fn show(h: Heap, v: V, readable: Bool) String:
    var parts = List[String]()
    put(h, v, readable, var parts)
    return parts.join("")

fn emit(var h: Heap, s: String) Unit:
    stdout().write(s).get()

    if s.length() > 0:
        h.out_any = true
        h.out_nl = s.ends_with("\n")

fn report_error(var h: Heap, msg: String) Unit:
    if h.out_any and not h.out_nl:
        emit(var h, "\n")
    emit(var h, "error: {msg}\n")

# ---- Argument checks for primitives ----

fn tyerr(h: Heap, code: Int, kind: String, v: V) Fail:
    return Fail("{h.pnames[code]}: expected {kind}, got {show(h, v, true)}", false)

fn arity_err(h: Heap, code: Int, n: Int) Fail:
    let lo = h.pmin[code]
    let hi = h.pmax[code]
    var expected = "{lo}"

    if hi < 0:
        expected = "at least {lo}"
    else if hi != lo:
        expected = "{lo} to {hi}"

    return Fail(
        "wrong number of arguments to {h.pnames[code]}: expected {expected}, got {n}",
        false
    )

fn want_int(h: Heap, code: Int, v: V) Result[Int, Fail]:
    if v.kind != K_INT:
        return error(tyerr(h, code, "integer", v))

    return ok(v.n)

# Returns the index of the string in h.strs.
fn want_str(h: Heap, code: Int, v: V) Result[Int, Fail]:
    if v.kind != K_STR:
        return error(tyerr(h, code, "string", v))

    return ok(v.n)

fn check_list(h: Heap, code: Int, v: V) Result[Unit, Fail]:
    if list_len(h, v) < 0:
        return error(tyerr(h, code, "list", v))

    return ok(unit)

fn check_proc(h: Heap, code: Int, v: V) Result[Unit, Fail]:
    if not is_proc(v):
        return error(tyerr(h, code, "procedure", v))

    return ok(unit)

# ---- Overflow-checked integer arithmetic ----

fn add_checked(a: Int, b: Int) Result[Int, Fail]:
    if b > 0 and a > MAX_INT - b:
        return error(rt_err("integer overflow"))
    if b < 0 and a < MIN_INT - b:
        return error(rt_err("integer overflow"))

    return ok(a + b)

fn sub_checked(a: Int, b: Int) Result[Int, Fail]:
    if b < 0 and a > MAX_INT + b:
        return error(rt_err("integer overflow"))
    if b > 0 and a < MIN_INT + b:
        return error(rt_err("integer overflow"))

    return ok(a - b)

fn mul_checked(a: Int, b: Int) Result[Int, Fail]:
    if a == 0 or b == 0:
        return ok(0)

    if a == -1:
        if b == MIN_INT:
            return error(rt_err("integer overflow"))

        return ok(-b)

    if b == -1:
        if a == MIN_INT:
            return error(rt_err("integer overflow"))

        return ok(-a)

    if a > 0 and b > 0 and a > MAX_INT / b:
        return error(rt_err("integer overflow"))
    if a > 0 and b < 0 and b < MIN_INT / a:
        return error(rt_err("integer overflow"))
    if a < 0 and b > 0 and a < MIN_INT / b:
        return error(rt_err("integer overflow"))
    if a < 0 and b < 0 and a < MAX_INT / b:
        return error(rt_err("integer overflow"))

    return ok(a * b)

# ---- Equality ----

fn same_v(a: V, b: V) Bool:
    if a.kind != b.kind:
        return false
    if a.kind == K_STR or a.kind == K_PAIR or a.kind == K_CLO or a.kind == K_PRIM:
        return false

    return a.n == b.n

fn equal_v(h: Heap, a: V, b: V) Bool:
    var x = a
    var y = b

    while x.kind == K_PAIR and y.kind == K_PAIR:
        if not equal_v(h, car_of(h, x), car_of(h, y)):
            return false

        x = cdr_of(h, x)
        y = cdr_of(h, y)

    if x.kind != y.kind:
        return false
    if x.kind == K_PAIR:
        return false
    if x.kind == K_STR:
        return h.strs[x.n] == h.strs[y.n]

    return x.n == y.n

# ---- Environments ----

fn lookup(h: Heap, env: Int, sym: Int) Optional[V]:
    var f = env

    while f >= 0:
        if let v = h.binds.get(key(f, sym)):
            return some(v)

        f = h.parents[f]

    return none

# Frame that holds sym, or -1 when no frame does.
fn find_frame(h: Heap, env: Int, sym: Int) Int:
    var f = env

    while f >= 0:
        if h.binds.contains(key(f, sym)):
            return f

        f = h.parents[f]

    return -1

fn new_frame(var h: Heap, parent: Int) Int:
    h.parents.append(parent)
    return h.parents.length() - 1

fn call_depth(depth: Int, tail: Bool) Result[Int, Fail]:
    var nd = depth
    if not tail:
        nd = depth + 1
    if nd > MAX_DEPTH:
        return error(rt_err("recursion limit exceeded"))

    return ok(nd)

# Creates the frame for calling closure ci with args and returns its id.
fn bind_call(var h: Heap, ci: Int, args: List[V]) Result[Int, Fail]:
    let formals = h.clos[ci].formals
    let env = h.clos[ci].env
    var nreq = 0
    var cur = formals

    while cur.kind == K_PAIR:
        nreq += 1
        cur = cdr_of(h, cur)

    let rest = cur.kind == K_SYM
    let nargs = args.length()

    if nargs < nreq or (not rest and nargs > nreq):
        let name = h.clos[ci].name
        var who = "lambda"
        if name >= 0:
            who = h.syms[name].clone()

        var expected = "{nreq}"
        if rest:
            expected = "at least {nreq}"
        return error(
            rt_err(
                "wrong number of arguments to {who}: expected {expected}, got {nargs}"
            )
        )

    let frame = new_frame(var h, env)
    var fcur = formals
    var i = 0

    while fcur.kind == K_PAIR:
        h.binds.add(key(frame, car_of(h, fcur).n), args[i])
        i += 1
        fcur = cdr_of(h, fcur)

    if rest:
        var tailargs = List[V]()
        var j = nreq

        while j < nargs:
            tailargs.append(args[j])
            j += 1

        h.binds.add(key(frame, cur.n), prepend_list(var h, tailargs, nil_v()))

    return ok(frame)

# Validates formals and stores a closure. sid names the form for errors.
fn make_closure(var h: Heap, sid: Int, formals: V, body: V, env: Int, name: Int) Result[
    V, Fail
]:
    var seen = List[Int]()
    var cur = formals

    while cur.kind == K_PAIR:
        let p = car_of(h, cur)
        if p.kind != K_SYM or seen.contains(p.n):
            return error(bad_form(h, sid))

        seen.append(p.n)
        cur = cdr_of(h, cur)

    if cur.kind == K_SYM:
        if seen.contains(cur.n):
            return error(bad_form(h, sid))
    else if cur.kind != K_NIL:
        return error(bad_form(h, sid))

    h.clos.append(Clo(formals, body, env, name))
    return ok(V(K_CLO, h.clos.length() - 1))

fn lambda_form(var h: Heap, x: V, env: Int, name: Int) Result[V, Fail]:
    let params = nth(h, x, 1)
    let body = drop(h, x, 2)
    return make_closure(var h, S_LAMBDA, params, body, env, name)

# Last expression of a non-empty body.
fn body_last(h: Heap, body: V) V:
    var cur = body
    while cdr_of(h, cur).kind == K_PAIR:
        cur = cdr_of(h, cur)
    return car_of(h, cur)

# Evaluates every expression of a body except the last, in non-tail position.
fn run_init(var h: Heap, body: V, env: Int, depth: Int) Result[Unit, Fail]:
    var cur = body

    while cur.kind == K_PAIR and cdr_of(h, cur).kind == K_PAIR:
        let e = car_of(h, cur)
        let _v = try eval_expr(var h, e, env, depth, false)
        cur = cdr_of(h, cur)

    return ok(unit)

# Checks a let-style binding list and returns its (name init) entries.
fn binding_list(h: Heap, sid: Int, bindings: V) Result[List[V], Fail]:
    let items = to_vec(h, bindings)
    if list_len(h, bindings) < 0:
        return error(bad_form(h, sid))

    for b in items:
        if list_len(h, b) != 2 or car_of(h, b).kind != K_SYM:
            return error(bad_form(h, sid))
    return ok(items)

# Evaluates a special form. `x` is a proper list whose head is special.
fn special(var h: Heap, sid: Int, x: V, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    let len = list_len(h, x)

    if sid == S_QUOTE:
        if len != 2:
            return error(bad_form(h, sid))

        return ok(finish(nth(h, x, 1)))

    if sid == S_IF:
        return sf_if(var h, x, len, env, depth, tail)
    if sid == S_DEFINE:
        return sf_define(var h, x, len, env, depth)
    if sid == S_SET:
        return sf_set(var h, x, len, env, depth)

    if sid == S_LAMBDA:
        if len < 3:
            return error(bad_form(h, sid))

        let clo = try lambda_form(var h, x, env, -1)
        return ok(finish(clo))

    if sid == S_BEGIN:
        return sf_begin(var h, x, len, env, depth, tail)

    if sid == S_LET:
        if len < 3:
            return error(bad_form(h, sid))
        if nth(h, x, 1).kind == K_SYM:
            return named_let(var h, x, len, env, depth, tail)

        return plain_let(var h, x, env, depth, tail)

    if sid == S_LETSTAR or sid == S_LETREC:
        return sf_letstar(var h, x, len, env, depth, tail)
    if sid == S_COND:
        return sf_cond(var h, x, env, depth, tail)
    if sid == S_AND or sid == S_OR:
        return sf_and_or(var h, x, len, env, depth, tail)
    if sid == S_WHEN or sid == S_UNLESS:
        return sf_when(var h, x, len, env, depth, tail)

    return sf_try(var h, x, len, env, depth)

fn sf_if(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    if len != 3 and len != 4:
        return error(bad_form(h, S_IF))

    let condition = nth(h, x, 1)
    let t = try eval_expr(var h, condition, env, depth, false)
    if is_true(t):
        return ok(jump(nth(h, x, 2), env, depth, tail))
    if len == 4:
        return ok(jump(nth(h, x, 3), env, depth, tail))

    return ok(finish(void_v()))

fn sf_define(var h: Heap, x: V, len: Int, env: Int, depth: Int) Result[Step, Fail]:
    if len < 3:
        return error(bad_form(h, S_DEFINE))

    let target = nth(h, x, 1)

    if target.kind == K_SYM:
        if len != 3:
            return error(bad_form(h, S_DEFINE))

        let expr = nth(h, x, 2)
        var value = void_v()

        if (
            expr.kind == K_PAIR
            and car_of(h, expr).kind == K_SYM
            and car_of(h, expr).n == S_LAMBDA
        ):
            value = try lambda_form(var h, expr, env, target.n)
        else:
            value = try eval_expr(var h, expr, env, depth, false)

        h.binds.add(key(env, target.n), value)
        return ok(finish(void_v()))

    if target.kind != K_PAIR or car_of(h, target).kind != K_SYM:
        return error(bad_form(h, S_DEFINE))

    let fname = car_of(h, target).n
    let formals = cdr_of(h, target)
    let body = drop(h, x, 2)
    let clo = try make_closure(var h, S_DEFINE, formals, body, env, fname)
    h.binds.add(key(env, fname), clo)
    return ok(finish(void_v()))

fn sf_set(var h: Heap, x: V, len: Int, env: Int, depth: Int) Result[Step, Fail]:
    if len != 3:
        return error(bad_form(h, S_SET))

    let target = nth(h, x, 1)
    if target.kind != K_SYM:
        return error(bad_form(h, S_SET))

    let expr = nth(h, x, 2)
    let v = try eval_expr(var h, expr, env, depth, false)
    let frame = find_frame(h, env, target.n)
    if frame < 0:
        return error(rt_err("unbound variable: {h.syms[target.n]}"))

    h.binds.add(key(frame, target.n), v)
    return ok(finish(void_v()))

fn sf_begin(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    if len == 1:
        return ok(finish(void_v()))

    let body = cdr_of(h, x)
    try run_init(var h, body, env, depth)
    return ok(jump(body_last(h, body), env, depth, tail))

fn sf_letstar(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    if len < 3:
        return error(bad_form(h, S_LETSTAR))

    let items = try binding_list(h, S_LETSTAR, nth(h, x, 1))
    let frame = new_frame(var h, env)

    for b in items:
        let sym = car_of(h, b).n
        let init = nth(h, b, 1)
        let v = try eval_expr(var h, init, frame, depth, false)
        h.binds.add(key(frame, sym), v)

    let body = drop(h, x, 2)
    try run_init(var h, body, frame, depth)
    return ok(jump(body_last(h, body), frame, depth, tail))

fn sf_cond(var h: Heap, x: V, env: Int, depth: Int, tail: Bool) Result[Step, Fail]:
    var cl = cdr_of(h, x)

    while cl.kind == K_PAIR:
        let clause = car_of(h, cl)
        if clause.kind != K_PAIR:
            return error(bad_form(h, S_COND))

        let head = car_of(h, clause)

        if head.kind == K_SYM and head.n == S_ELSE:
            if cdr_of(h, cl).kind != K_NIL:
                return error(bad_form(h, S_COND))

            let body = cdr_of(h, clause)
            if body.kind != K_PAIR:
                return error(bad_form(h, S_COND))

            try run_init(var h, body, env, depth)
            return ok(jump(body_last(h, body), env, depth, tail))

        let t = try eval_expr(var h, head, env, depth, false)

        if is_true(t):
            let body = cdr_of(h, clause)
            if body.kind != K_PAIR:
                return ok(finish(t))

            try run_init(var h, body, env, depth)
            return ok(jump(body_last(h, body), env, depth, tail))

        cl = cdr_of(h, cl)

    return ok(finish(void_v()))

fn sf_and_or(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    let is_and = h.cars[x.n].n == S_AND
    if len == 1:
        return ok(finish(vbool(is_and)))

    var cur = cdr_of(h, x)

    while cdr_of(h, cur).kind == K_PAIR:
        let e = car_of(h, cur)
        let v = try eval_expr(var h, e, env, depth, false)
        if is_and and not is_true(v):
            return ok(finish(v))
        if not is_and and is_true(v):
            return ok(finish(v))

        cur = cdr_of(h, cur)

    return ok(jump(car_of(h, cur), env, depth, tail))

fn sf_when(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    let is_when = h.cars[x.n].n == S_WHEN
    if len < 3:
        return error(bad_form(h, h.cars[x.n].n))

    let condition = nth(h, x, 1)
    let t = try eval_expr(var h, condition, env, depth, false)
    if is_true(t) != is_when:
        return ok(finish(void_v()))

    let body = drop(h, x, 2)
    try run_init(var h, body, env, depth)
    return ok(jump(body_last(h, body), env, depth, tail))

fn sf_try(var h: Heap, x: V, len: Int, env: Int, depth: Int) Result[Step, Fail]:
    if len != 3:
        return error(bad_form(h, S_TRY))

    let body_expr = nth(h, x, 1)
    let r = eval_expr(var h, body_expr, env, depth, false)

    if r.is_error():
        let msg = r.err().msg.clone()
        if r.err().syntax:
            return error(Fail(msg, true))

        let handler = nth(h, x, 2)
        let hv = try eval_expr(var h, handler, env, depth, false)
        var args = List[V]()
        args.append(str_val(var h, msg))

        let res = try apply_proc(var h, hv, args, depth)
        return ok(finish(res))

    let v = try r
    return ok(finish(v))

# (let ((name init) ...) body ...)
fn plain_let(var h: Heap, x: V, env: Int, depth: Int, tail: Bool) Result[Step, Fail]:
    let items = try binding_list(h, S_LET, nth(h, x, 1))
    var vals = List[V]()

    for b in items:
        let init = nth(h, b, 1)
        let v = try eval_expr(var h, init, env, depth, false)
        vals.append(v)

    let frame = new_frame(var h, env)
    var i = 0

    for b in items:
        h.binds.add(key(frame, car_of(h, b).n), vals[i])
        i += 1

    let body = drop(h, x, 2)
    try run_init(var h, body, frame, depth)
    return ok(jump(body_last(h, body), frame, depth, tail))

# (let name ((var init) ...) body ...): name is a procedure over the body.
fn named_let(var h: Heap, x: V, len: Int, env: Int, depth: Int, tail: Bool) Result[
    Step, Fail
]:
    if len < 4:
        return error(bad_form(h, S_LET))

    let name = nth(h, x, 1).n
    let items = try binding_list(h, S_LET, nth(h, x, 2))
    var formal_list = List[V]()
    var vals = List[V]()

    for b in items:
        formal_list.append(V(K_SYM, car_of(h, b).n))

        let init = nth(h, b, 1)
        let v = try eval_expr(var h, init, env, depth, false)
        vals.append(v)

    let formals = prepend_list(var h, formal_list, nil_v())
    let loop_frame = new_frame(var h, env)
    let body = drop(h, x, 3)
    let clo = try make_closure(var h, S_LET, formals, body, loop_frame, name)
    h.binds.add(key(loop_frame, name), clo)

    let nd = try call_depth(depth, tail)
    let frame = try bind_call(var h, clo.n, vals)
    try run_init(var h, body, frame, nd)
    return ok(jump(body_last(h, body), frame, nd, true))

# Applies a procedure to already evaluated arguments, in non-tail position
# of a builtin. Used by higher-order primitives and the try handler.
fn apply_proc(var h: Heap, f: V, args: List[V], depth: Int) Result[V, Fail]:
    if f.kind == K_PRIM:
        return prim_apply(var h, f.n, args, depth)
    if f.kind != K_CLO:
        return error(rt_err("not a procedure: {show(h, f, true)}"))

    let frame = try bind_call(var h, f.n, args)
    let nd = try call_depth(depth, false)
    let body = h.clos[f.n].body
    try run_init(var h, body, frame, nd)

    let last = body_last(h, body)
    return eval_expr(var h, last, frame, nd, true)

# Evaluates expr in env. `depth` counts procedure bodies entered from
# non-tail positions; `tail` says whether expr is in tail position of the
# body that is running. Tail calls loop here instead of recursing.
fn eval_expr(var h: Heap, expr: V, env0: Int, depth0: Int, tail0: Bool) Result[V, Fail]:
    var x = expr
    var env = env0
    var depth = depth0
    var tail = tail0

    while true:
        if x.kind == K_SYM:
            if let v = lookup(h, env, x.n):
                return ok(v)

            return error(rt_err("unbound variable: {h.syms[x.n]}"))

        if x.kind == K_NIL:
            return error(syn_err("empty application"))
        if x.kind != K_PAIR:
            return ok(x)
        if list_len(h, x) < 0:
            return error(syn_err("bad application"))

        let head = car_of(h, x)

        if head.kind == K_SYM and head.n < NSPECIAL:
            let st = try special(var h, head.n, x, env, depth, tail)
            if st.done:
                return ok(st.value)

            x = st.expr
            env = st.env
            depth = st.depth
            tail = st.tail
        else:
            let f = try eval_expr(var h, head, env, depth, false)
            var args = List[V]()
            var cur = cdr_of(h, x)

            while cur.kind == K_PAIR:
                let operand = car_of(h, cur)
                let v = try eval_expr(var h, operand, env, depth, false)
                args.append(v)
                cur = cdr_of(h, cur)

            if f.kind == K_PRIM:
                return prim_apply(var h, f.n, args, depth)
            if f.kind != K_CLO:
                return error(rt_err("not a procedure: {show(h, f, true)}"))

            let frame = try bind_call(var h, f.n, args)
            let nd = try call_depth(depth, tail)
            let body = h.clos[f.n].body
            try run_init(var h, body, frame, nd)
            x = body_last(h, body)
            env = frame
            depth = nd
            tail = true

fn prim_apply(var h: Heap, code: Int, args: List[V], depth: Int) Result[V, Fail]:
    let n = args.length()
    if n < h.pmin[code] or (h.pmax[code] >= 0 and n > h.pmax[code]):
        return error(arity_err(h, code, n))
    if code < P_PRED:
        return num_prim(var h, code, args)
    if code < P_PAIR:
        return pred_prim(var h, code, args)
    if code < P_HO:
        return pair_prim(var h, code, args)
    if code < P_STR:
        return ho_prim(var h, code, args, depth)
    if code < P_MISC:
        return str_prim(var h, code, args)

    return misc_prim(var h, code, args)

# ---- Numbers ----

fn num_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    if code == P_ADD or code == P_MUL:
        var acc = 0
        if code == P_MUL:
            acc = 1

        for a in args:
            let v = try want_int(h, code, a)

            if code == P_ADD:
                acc = try add_checked(acc, v)
            else:
                acc = try mul_checked(acc, v)

        return ok(int_val(acc))

    if code == P_SUB:
        let first = try want_int(h, code, args[0])
        if args.length() == 1:
            return ok(int_val(try sub_checked(0, first)))

        var acc = first

        for i in 1..args.length():
            let v = try want_int(h, code, args[i])
            acc = try sub_checked(acc, v)

        return ok(int_val(acc))

    if code == P_QUOT or code == P_REM or code == P_MOD:
        let a = try want_int(h, code, args[0])
        let b = try want_int(h, code, args[1])
        if b == 0:
            return error(rt_err("division by zero"))

        if b == -1:
            if code == P_QUOT:
                if a == MIN_INT:
                    return error(rt_err("integer overflow"))

                return ok(int_val(-a))

            return ok(int_val(0))

        if code == P_QUOT:
            return ok(int_val(a / b))

        var r = a % b
        if code == P_MOD and r != 0 and (r < 0) != (b < 0):
            r = r + b
        return ok(int_val(r))

    if code == P_ABS:
        let a = try want_int(h, code, args[0])
        if a == MIN_INT:
            return error(rt_err("integer overflow"))
        if a < 0:
            return ok(int_val(-a))

        return ok(int_val(a))

    if code == P_MIN or code == P_MAX:
        var best = try want_int(h, code, args[0])

        for i in 1..args.length():
            let v = try want_int(h, code, args[i])
            if code == P_MIN and v < best:
                best = v
            if code == P_MAX and v > best:
                best = v

        return ok(int_val(best))

    if code >= P_NUMEQ and code <= P_GE:
        var vals = List[Int]()
        for a in args:
            vals.append(try want_int(h, code, a))

        var all = true

        for i in 0..vals.length() - 1:
            let a = vals[i]
            let b = vals[i + 1]
            var good = false

            if code == P_NUMEQ:
                good = a == b
            else if code == P_LT:
                good = a < b
            else if code == P_GT:
                good = a > b
            else if code == P_LE:
                good = a <= b
            else:
                good = a >= b

            if not good:
                all = false

        return ok(vbool(all))

    let a = try want_int(h, code, args[0])
    if code == P_ZERO:
        return ok(vbool(a == 0))
    if code == P_EVEN:
        return ok(vbool(a % 2 == 0))

    return ok(vbool(a % 2 != 0))

# ---- Predicates and equality ----

fn pred_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    let v = args[0]
    if code == P_NOT:
        return ok(vbool(not is_true(v)))
    if code == P_NULL:
        return ok(vbool(v.kind == K_NIL))
    if code == P_PAIRP:
        return ok(vbool(v.kind == K_PAIR))
    if code == P_LISTP:
        return ok(vbool(list_len(h, v) >= 0))
    if code == P_NUMBERP:
        return ok(vbool(v.kind == K_INT))
    if code == P_STRINGP:
        return ok(vbool(v.kind == K_STR))
    if code == P_SYMBOLP:
        return ok(vbool(v.kind == K_SYM))
    if code == P_BOOLP:
        return ok(vbool(v.kind == K_BOOL))
    if code == P_PROCP:
        return ok(vbool(is_proc(v)))
    if code == P_EQ:
        return ok(vbool(same_v(v, args[1])))

    return ok(vbool(equal_v(h, v, args[1])))

# ---- Pairs and lists ----

fn car_checked(h: Heap, code: Int, v: V) Result[V, Fail]:
    if v.kind != K_PAIR:
        return error(tyerr(h, code, "pair", v))

    return ok(car_of(h, v))

fn cdr_checked(h: Heap, code: Int, v: V) Result[V, Fail]:
    if v.kind != K_PAIR:
        return error(tyerr(h, code, "pair", v))

    return ok(cdr_of(h, v))

fn pair_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    if code == P_CONS:
        return ok(cons(var h, args[0], args[1]))
    if code == P_CAR:
        return car_checked(h, code, args[0])
    if code == P_CDR:
        return cdr_checked(h, code, args[0])

    if code == P_CADR:
        let d = try cdr_checked(h, code, args[0])
        return car_checked(h, code, d)

    if code == P_CDDR:
        let d = try cdr_checked(h, code, args[0])
        return cdr_checked(h, code, d)

    if code == P_CADDR:
        let d = try cdr_checked(h, code, args[0])
        let dd = try cdr_checked(h, code, d)
        return car_checked(h, code, dd)

    if code == P_SETCAR or code == P_SETCDR:
        if args[0].kind != K_PAIR:
            return error(tyerr(h, code, "pair", args[0]))

        if code == P_SETCAR:
            h.cars[args[0].n] = args[1]
        else:
            h.cdrs[args[0].n] = args[1]

        return ok(void_v())

    if code == P_LIST:
        return ok(prepend_list(var h, args, nil_v()))

    if code == P_LENGTH:
        let _l = try check_list(h, code, args[0])
        return ok(int_val(list_len(h, args[0])))

    if code == P_APPEND:
        return append_prim(var h, code, args)

    if code == P_REVERSE:
        let _l = try check_list(h, code, args[0])
        var acc = nil_v()
        for x in to_vec(h, args[0]):
            acc = cons(var h, x, acc)
        return ok(acc)

    if code == P_LISTREF:
        let _l = try check_list(h, code, args[0])
        let k = try want_int(h, code, args[1])
        if k < 0:
            return error(rt_err("list-ref: index out of range"))

        let first = args[0]
        var cur = first
        var i = 0

        while i < k and cur.kind == K_PAIR:
            cur = cdr_of(h, cur)
            i += 1

        if cur.kind != K_PAIR:
            return error(rt_err("list-ref: index out of range"))

        return ok(car_of(h, cur))

    if code == P_LISTTAIL:
        let _l = try check_list(h, code, args[0])
        let k = try want_int(h, code, args[1])
        if k < 0 or k > list_len(h, args[0]):
            return error(rt_err("list-tail: index out of range"))

        return ok(drop(h, args[0], k))

    if code == P_RANGE:
        let a = try want_int(h, code, args[0])
        let b = try want_int(h, code, args[1])
        if a >= b:
            return ok(nil_v())

        var acc = nil_v()
        var i = b - 1

        while true:
            acc = cons(var h, int_val(i), acc)
            if i == a:
                break

            i -= 1

        return ok(acc)

    if code == P_ASSOC:
        let _l = try check_list(h, code, args[1])
        let second = args[1]
        var cur = second

        while cur.kind == K_PAIR:
            let e = car_of(h, cur)
            if e.kind != K_PAIR:
                return error(tyerr(h, code, "pair", e))
            if equal_v(h, args[0], car_of(h, e)):
                return ok(e)

            cur = cdr_of(h, cur)

        return ok(vbool(false))

    # member
    let _m = try check_list(h, code, args[1])
    let second = args[1]
    var cur = second

    while cur.kind == K_PAIR:
        if equal_v(h, args[0], car_of(h, cur)):
            return ok(cur)

        cur = cdr_of(h, cur)

    return ok(vbool(false))

fn append_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    let n = args.length()
    if n == 0:
        return ok(nil_v())

    for i in 0..n - 1:
        let _l = try check_list(h, code, args[i])

    let last = args[n - 1]
    var acc = last
    var i = n - 2

    while i >= 0:
        acc = prepend_list(var h, to_vec(h, args[i]), acc)
        i -= 1

    return ok(acc)

# ---- Higher-order primitives ----

# Calls f on the i-th elements of the lists in args[1..], stopping at the shortest.
fn map_lists(var h: Heap, code: Int, args: List[V], depth: Int) Result[List[V], Fail]:
    let f = args[0]
    let _p = try check_proc(h, code, f)
    var columns = List[List[V]]()
    var shortest = -1

    for i in 1..args.length():
        let _l = try check_list(h, code, args[i])
        let col = to_vec(h, args[i])
        if shortest < 0 or col.length() < shortest:
            shortest = col.length()
        columns.append(col)

    var results = List[V]()
    var k = 0

    while k < shortest:
        var cargs = List[V]()
        for col in columns:
            cargs.append(col[k])

        let r = try apply_proc(var h, f, cargs, depth)
        results.append(r)
        k += 1

    return ok(results)

# Stable merge sort; less? is called as (less? later earlier).
fn sort_list(var h: Heap, items: List[V], less: V, depth: Int) Result[List[V], Fail]:
    let n = items.length()
    var out = List[V]()

    if n <= 1:
        for x in items:
            out.append(x)
        return ok(out)

    let mid = n / 2
    var left = List[V]()
    var right = List[V]()

    for i in 0..n:
        if i < mid:
            left.append(items[i])
        else:
            right.append(items[i])

    let ls = try sort_list(var h, left, less, depth)
    let rs = try sort_list(var h, right, less, depth)
    var i = 0
    var j = 0

    while i < ls.length() and j < rs.length():
        var cargs = List[V]()
        cargs.append(rs[j])
        cargs.append(ls[i])

        let r = try apply_proc(var h, less, cargs, depth)

        if is_true(r):
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

fn ho_prim(var h: Heap, code: Int, args: List[V], depth: Int) Result[V, Fail]:
    if code == P_MAP:
        let results = try map_lists(var h, code, args, depth)
        return ok(prepend_list(var h, results, nil_v()))

    if code == P_FOREACH:
        let _r = try map_lists(var h, code, args, depth)
        return ok(void_v())

    if code == P_FILTER:
        return ho_filter(var h, args, depth)
    if code == P_FOLD:
        return ho_fold(var h, args, depth)
    if code == P_FOLDR:
        return ho_foldr(var h, args, depth)
    if code == P_APPLY:
        return ho_apply(var h, args, depth)

    return ho_sort(var h, args, depth)

fn ho_filter(var h: Heap, args: List[V], depth: Int) Result[V, Fail]:
    let _p = try check_proc(h, P_FILTER, args[0])
    let _l = try check_list(h, P_FILTER, args[1])
    var keep = List[V]()

    for x in to_vec(h, args[1]):
        var one = List[V]()
        one.append(x)

        let r = try apply_proc(var h, args[0], one, depth)
        if is_true(r):
            keep.append(x)

    return ok(prepend_list(var h, keep, nil_v()))

fn ho_fold(var h: Heap, args: List[V], depth: Int) Result[V, Fail]:
    let _p = try check_proc(h, P_FOLD, args[0])
    let _l = try check_list(h, P_FOLD, args[2])
    let init = args[1]
    var acc = init

    for x in to_vec(h, args[2]):
        var cargs = List[V]()
        cargs.append(acc)
        cargs.append(x)
        acc = try apply_proc(var h, args[0], cargs, depth)

    return ok(acc)

fn ho_foldr(var h: Heap, args: List[V], depth: Int) Result[V, Fail]:
    let _p = try check_proc(h, P_FOLDR, args[0])
    let _l = try check_list(h, P_FOLDR, args[2])
    let items = to_vec(h, args[2])
    let init = args[1]
    var acc = init
    var i = items.length() - 1

    while i >= 0:
        var cargs = List[V]()
        cargs.append(items[i])
        cargs.append(acc)
        acc = try apply_proc(var h, args[0], cargs, depth)
        i -= 1

    return ok(acc)

fn ho_apply(var h: Heap, args: List[V], depth: Int) Result[V, Fail]:
    let _p = try check_proc(h, P_APPLY, args[0])
    let n = args.length()
    let _l = try check_list(h, P_APPLY, args[n - 1])
    var cargs = List[V]()
    for i in 1..n - 1:
        cargs.append(args[i])
    for x in to_vec(h, args[n - 1]):
        cargs.append(x)
    return apply_proc(var h, args[0], cargs, depth)

# The procedure is checked before the list.
fn ho_sort(var h: Heap, args: List[V], depth: Int) Result[V, Fail]:
    let _p = try check_proc(h, P_SORT, args[1])
    let _l = try check_list(h, P_SORT, args[0])
    let items = to_vec(h, args[0])
    let sorted = try sort_list(var h, items, args[1], depth)
    return ok(prepend_list(var h, sorted, nil_v()))

# ---- Strings ----

fn str_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    if code == P_STRLEN:
        let si = try want_str(h, code, args[0])
        return ok(int_val(h.strs[si].length()))

    if code == P_STRAPPEND:
        var parts = List[String]()

        for a in args:
            let si = try want_str(h, code, a)
            parts.append(h.strs[si].clone())

        return ok(str_val(var h, parts.join("")))

    if code == P_SUBSTRING:
        let si = try want_str(h, code, args[0])
        let a = try want_int(h, code, args[1])
        let b = try want_int(h, code, args[2])
        let s = h.strs[si].clone()
        if let t = s.slice_scalars(a, b):
            return ok(str_val(var h, t))

        return error(rt_err("substring: index out of range"))

    if code == P_STRREF:
        let si = try want_str(h, code, args[0])
        let i = try want_int(h, code, args[1])
        let s = h.strs[si].clone()
        if i < 0 or i >= s.length():
            return error(rt_err("string-ref: index out of range"))
        if let c = s.slice_scalars(i, i + 1):
            return ok(str_val(var h, c))

        return error(rt_err("string-ref: index out of range"))

    if code == P_STREQ or code == P_STRLT:
        let a = try want_str(h, code, args[0])
        let b = try want_str(h, code, args[1])
        let x = h.strs[a].clone()
        let y = h.strs[b].clone()
        if code == P_STREQ:
            return ok(vbool(x == y))

        return ok(vbool(x.compare(y) < 0))

    if code == P_UPCASE or code == P_DOWNCASE:
        let si = try want_str(h, code, args[0])
        var t = h.strs[si].upper()
        if code == P_DOWNCASE:
            t = h.strs[si].lower()
        return ok(str_val(var h, t))

    if code == P_STR2NUM:
        let si = try want_str(h, code, args[0])
        let text = h.strs[si].clone()
        if is_int_text(text):
            if let n = parse_int_text(text):
                return ok(int_val(n))
        return ok(vbool(false))

    if code == P_NUM2STR:
        let n = try want_int(h, code, args[0])
        let t = n.to_string_radix(10)
        return ok(str_val(var h, t))

    if code == P_STR2SYM:
        let si = try want_str(h, code, args[0])
        let name = h.strs[si].clone()
        return ok(V(K_SYM, intern(var h, name)))

    if code == P_SYM2STR:
        if args[0].kind != K_SYM:
            return error(tyerr(h, code, "symbol", args[0]))

        let t = h.syms[args[0].n].clone()
        return ok(str_val(var h, t))

    if code == P_STR2LIST:
        let si = try want_str(h, code, args[0])
        let s = h.strs[si].clone()
        var items = List[V]()
        for i in 0..s.length():
            if let c = s.slice_scalars(i, i + 1):
                items.append(str_val(var h, c))
        return ok(prepend_list(var h, items, nil_v()))

    if code == P_LIST2STR:
        let _l = try check_list(h, code, args[0])
        var parts = List[String]()

        for e in to_vec(h, args[0]):
            let si = try want_str(h, code, e)
            parts.append(h.strs[si].clone())

        return ok(str_val(var h, parts.join("")))

    if code == P_STRJOIN:
        let _l = try check_list(h, code, args[0])
        let sep = try want_str(h, code, args[1])
        let sep_text = h.strs[sep].clone()
        var parts = List[String]()

        for e in to_vec(h, args[0]):
            let si = try want_str(h, code, e)
            parts.append(h.strs[si].clone())

        return ok(str_val(var h, parts.join(sep_text)))

    if code == P_STRSPLIT:
        let si = try want_str(h, code, args[0])
        let sp = try want_str(h, code, args[1])
        let sep = h.strs[sp].clone()
        if sep.length() != 1:
            return error(rt_err("string-split: separator must be one character"))

        let s = h.strs[si].clone()
        var items = List[V]()
        for piece in s.split(sep):
            items.append(str_val(var h, piece.clone()))
        return ok(prepend_list(var h, items, nil_v()))

    # string-contains?
    let si = try want_str(h, code, args[0])
    let sb = try want_str(h, code, args[1])
    let s = h.strs[si].clone()
    let t = h.strs[sb].clone()
    return ok(vbool(s.contains(t)))

# ---- Output and miscellaneous ----

fn misc_prim(var h: Heap, code: Int, args: List[V]) Result[V, Fail]:
    if code == P_DISPLAY or code == P_WRITE:
        let text = show(h, args[0], code == P_WRITE)
        emit(var h, text)
        return ok(void_v())

    if code == P_NEWLINE:
        emit(var h, "\n")
        return ok(void_v())

    if code == P_VOID:
        return ok(void_v())

    # error
    let si = try want_str(h, code, args[0])
    var parts = List[String]()
    parts.append(h.strs[si].clone())

    for i in 1..args.length():
        parts.append(" ")
        parts.append(show(h, args[i], true))

    return error(rt_err(parts.join("")))

# ---- Reader ----

fn peek(h: Heap) Int:
    if h.pos >= h.n:
        return -1

    return h.src.get(h.pos).to_int()

fn byte_at(h: Heap, i: Int) Int:
    if i >= h.n:
        return -1

    return h.src.get(i).to_int()

fn is_delim(c: Int) Bool:
    return (
        c == -1
        or c == 32
        or c == 9
        or c == 10
        or c == 13
        or c == 40
        or c == 41
        or c == 34
        or c == 59
    )

fn skip_ws(var h: Heap) Unit:
    var more = true

    while more:
        let c = peek(h)

        if c == 32 or c == 9 or c == 10 or c == 13:
            h.pos += 1
        else if c == 59:
            while peek(h) != 10 and peek(h) != -1:
                h.pos += 1
        else:
            more = false

fn read_datum(var h: Heap) Result[V, Fail]:
    skip_ws(var h)

    let c = peek(h)
    if c == -1:
        return error(syn_err("unexpected end of input"))

    if c == 40:
        h.pos += 1
        return read_list(var h)

    if c == 41:
        return error(syn_err("unexpected )"))

    if c == 39:
        h.pos += 1

        let d = try read_datum(var h)
        let rest = cons(var h, d, nil_v())
        return ok(cons(var h, V(K_SYM, S_QUOTE), rest))

    if c == 34:
        h.pos += 1
        return read_string(var h)

    return read_atom(var h)

fn read_list(var h: Heap) Result[V, Fail]:
    var items = List[V]()
    var tail = nil_v()

    while true:
        skip_ws(var h)

        let c = peek(h)
        if c == -1:
            return error(syn_err("unexpected end of input"))

        if c == 41:
            h.pos += 1
            break

        if c == 46 and is_delim(byte_at(h, h.pos + 1)):
            if items.length() == 0:
                return error(syn_err("bad dotted list"))

            h.pos += 1
            skip_ws(var h)
            if peek(h) == 41:
                return error(syn_err("bad dotted list"))

            tail = try read_datum(var h)
            skip_ws(var h)

            let after = peek(h)

            if after == 41:
                h.pos += 1
                break

            if after == -1:
                return error(syn_err("unexpected end of input"))

            return error(syn_err("bad dotted list"))

        let item = try read_datum(var h)
        items.append(item)

    return ok(prepend_list(var h, items, tail))

fn text_range(h: Heap, start: Int, end: Int) String:
    if let t = h.src.decode_utf8_range(start, end):
        return t

    return ""

fn read_string(var h: Heap) Result[V, Fail]:
    var parts = List[String]()
    let begin = h.pos
    var run = begin

    while true:
        let c = peek(h)
        if c == -1:
            return error(syn_err("unterminated string"))

        if c == 34:
            parts.append(text_range(h, run, h.pos))
            h.pos += 1
            break

        if c == 92:
            parts.append(text_range(h, run, h.pos))

            let e = byte_at(h, h.pos + 1)
            if e == -1:
                return error(syn_err("unterminated string"))

            if e == 110:
                parts.append("\n")
            else if e == 116:
                parts.append("\t")
            else if e == 92:
                parts.append("\\")
            else if e == 34:
                parts.append("\"")
            else:
                return error(syn_err("bad escape"))

            h.pos += 2
            run = h.pos
        else:
            h.pos += 1

    return ok(str_val(var h, parts.join("")))

fn read_atom(var h: Heap) Result[V, Fail]:
    let start = h.pos
    while not is_delim(peek(h)):
        h.pos += 1
    if let t = h.src.decode_utf8_range(start, h.pos):
        return atom_value(var h, t)

    return error(syn_err("bad token"))

fn atom_value(var h: Heap, t: String) Result[V, Fail]:
    if t == "#t":
        return ok(vbool(true))
    if t == "#f":
        return ok(vbool(false))
    if t.starts_with("#"):
        return error(syn_err("bad token: {t}"))
    if t == ".":
        return error(syn_err("unexpected ."))

    if is_int_text(t):
        if let n = parse_int_text(t):
            return ok(int_val(n))

        return error(syn_err("integer out of range"))

    return ok(V(K_SYM, intern(var h, t)))

# True for an optional '-' followed by one or more digits.
fn is_int_text(text: String) Bool:
    let b = text.to_bytes()
    let n = b.length()
    var i = 0
    if n > 0 and b.get(0).to_int() == 45:
        i = 1
    if i >= n:
        return false

    while i < n:
        let c = b.get(i).to_int()
        if c < 48 or c > 57:
            return false

        i += 1

    return true

# Parses text that passed is_int_text. Accumulates as a negative number so
# that MIN_INT is representable; none when the value is out of range.
fn parse_int_text(text: String) Optional[Int]:
    let b = text.to_bytes()
    let n = b.length()
    var neg = false
    var i = 0

    if b.get(0).to_int() == 45:
        neg = true
        i = 1

    var acc = 0

    while i < n:
        let d = b.get(i).to_int() - 48
        if acc < (MIN_INT + d) / 10:
            return none

        acc = acc * 10 - d
        i += 1

    if neg:
        return some(acc)
    if acc == MIN_INT:
        return none

    return some(-acc)

# ---- Driver ----

fn run_top(var h: Heap) Result[Unit, Fail]:
    while true:
        skip_ws(var h)
        if h.pos >= h.n:
            break

        let form = try read_datum(var h)
        let _v = try eval_expr(var h, form, 0, 0, false)

    return ok(unit)

fn reg(var h: Heap, name: String, lo: Int, hi: Int) Unit:
    let code = h.pnames.length()
    h.pnames.append(name.clone())
    h.pmin.append(lo)
    h.pmax.append(hi)

    let id = intern(var h, name)
    h.binds.add(key(0, id), V(K_PRIM, code))

# Registration order must match the P_* constants.
fn reg_prims(var h: Heap) Unit:
    reg(var h, "+", 0, -1)
    reg(var h, "-", 1, -1)
    reg(var h, "*", 0, -1)
    reg(var h, "quotient", 2, 2)
    reg(var h, "remainder", 2, 2)
    reg(var h, "modulo", 2, 2)
    reg(var h, "abs", 1, 1)
    reg(var h, "min", 1, -1)
    reg(var h, "max", 1, -1)
    reg(var h, "=", 2, -1)
    reg(var h, "<", 2, -1)
    reg(var h, ">", 2, -1)
    reg(var h, "<=", 2, -1)
    reg(var h, ">=", 2, -1)
    reg(var h, "zero?", 1, 1)
    reg(var h, "even?", 1, 1)
    reg(var h, "odd?", 1, 1)
    reg(var h, "not", 1, 1)
    reg(var h, "null?", 1, 1)
    reg(var h, "pair?", 1, 1)
    reg(var h, "list?", 1, 1)
    reg(var h, "number?", 1, 1)
    reg(var h, "string?", 1, 1)
    reg(var h, "symbol?", 1, 1)
    reg(var h, "boolean?", 1, 1)
    reg(var h, "procedure?", 1, 1)
    reg(var h, "eq?", 2, 2)
    reg(var h, "equal?", 2, 2)
    reg(var h, "cons", 2, 2)
    reg(var h, "car", 1, 1)
    reg(var h, "cdr", 1, 1)
    reg(var h, "cadr", 1, 1)
    reg(var h, "cddr", 1, 1)
    reg(var h, "caddr", 1, 1)
    reg(var h, "set-car!", 2, 2)
    reg(var h, "set-cdr!", 2, 2)
    reg(var h, "list", 0, -1)
    reg(var h, "length", 1, 1)
    reg(var h, "append", 0, -1)
    reg(var h, "reverse", 1, 1)
    reg(var h, "list-ref", 2, 2)
    reg(var h, "list-tail", 2, 2)
    reg(var h, "range", 2, 2)
    reg(var h, "assoc", 2, 2)
    reg(var h, "member", 2, 2)
    reg(var h, "map", 2, -1)
    reg(var h, "for-each", 2, -1)
    reg(var h, "filter", 2, 2)
    reg(var h, "fold", 3, 3)
    reg(var h, "foldr", 3, 3)
    reg(var h, "apply", 2, -1)
    reg(var h, "sort", 2, 2)
    reg(var h, "string-length", 1, 1)
    reg(var h, "string-append", 0, -1)
    reg(var h, "substring", 3, 3)
    reg(var h, "string-ref", 2, 2)
    reg(var h, "string=?", 2, 2)
    reg(var h, "string<?", 2, 2)
    reg(var h, "string-upcase", 1, 1)
    reg(var h, "string-downcase", 1, 1)
    reg(var h, "string->number", 1, 1)
    reg(var h, "number->string", 1, 1)
    reg(var h, "string->symbol", 1, 1)
    reg(var h, "symbol->string", 1, 1)
    reg(var h, "string->list", 1, 1)
    reg(var h, "list->string", 1, 1)
    reg(var h, "string-join", 2, 2)
    reg(var h, "string-split", 2, 2)
    reg(var h, "string-contains?", 2, 2)
    reg(var h, "display", 1, 1)
    reg(var h, "write", 1, 1)
    reg(var h, "newline", 0, 0)
    reg(var h, "void", 0, 0)
    reg(var h, "error", 1, -1)

fn new_heap(src: Bytes) Heap:
    let n = src.length()
    var h = Heap(
        cars: List[V](), cdrs: List[V](), strs: List[String](), syms: List[String](),
        symids: Map[String, Int](), parents: List[Int](), binds: Map[Int, V](),
        clos: List[Clo](), pnames: List[String](), pmin: List[Int](), pmax: List[Int](),
        src: src, n: n, pos: 0, out_any: false, out_nl: false
    )
    for name in SPECIAL_NAMES:
        let _id = intern(var h, name)
    h.parents.append(-1)
    reg_prims(var h)
    return h

export fn main() Int:
    let data = read_all(stdin()).get()
    var h = new_heap(data)
    let r = run_top(var h)
    if r.is_error():
        report_error(var h, r.err().msg)
    return 0
