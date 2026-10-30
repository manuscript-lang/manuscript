import read_all, stdin, stdout from "@std/io.ms"
import from_scalars from "@std/string.ms"
import Bytes from "@std/bytes.ms"

# Value tags.
let TAG_NUM = 0
let TAG_BOOL = 1
let TAG_STR = 2
let TAG_SYM = 3
let TAG_PAIR = 4
let TAG_NIL = 5
let TAG_VOID = 6
let TAG_PRIM = 7
let TAG_CLO = 8
let TAG_UNBOUND = 9
let MAX_INT = 9223372036854775807
let MIN_INT = -9223372036854775807 - 1
let MAX_DEPTH = 10000
# Symbols with ids below SPECIAL_COUNT name special forms; they are interned first, in this order.
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
let SPECIAL_COUNT = 15
let S_ELSE = 15
# Builtin opcodes; the index is the position in `PRIMS`, which install_prims registers in this order.
let P_ADD = 0
let P_SUB = 1
let P_MUL = 2
let P_QUOT = 3
let P_REM = 4
let P_MOD = 5
let P_ABS = 6
let P_MIN = 7
let P_MAX = 8
let P_EQ = 9
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
let P_EQP = 26
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

# A Scheme value. `num` holds integers, booleans (0 or 1), symbol ids, pair/closure
# indexes and builtin opcodes; `text` holds string contents and is "" otherwise.
type Value:
    tag: Int
    num: Int
    text: String

type Closure:
    name: String
    params: List[Int]
    rest: Bool
    body: Value
    env: Int

# Interpreter state.
# - Pairs live in `cars`/`cdrs`; closures in `clos`.
# - Symbols are interned: `syms` maps id to name. `globals` holds each symbol's global value.
# - Frame 0 is the global frame. Other frames are chains of binding nodes (`node_*`) that
#   start at `frame_head`; `frame_parent` links frames to their enclosing frame.
type Machine:
    syms: List[String]
    sym_ids: Map[String, Int]
    globals: List[Value]
    cars: List[Value]
    cdrs: List[Value]
    clos: List[Closure]
    frame_parent: List[Int]
    frame_head: List[Int]
    node_sym: List[Int]
    node_val: List[Value]
    node_next: List[Int]
    prim_names: List[String]
    prim_min: List[Int]
    prim_max: List[Int]
    line_start: Bool

type Fail:
    msg: String
    syntax: Bool

impl Error for Fail:
    fn message() String:
        return self.msg

# What `special_form` tells the evaluation loop to do next.
type Step:
    done: Bool
    value: Value
    env: Int
    call: Bool

type Reader:
    src: Bytes
    pos: Int

type Params:
    names: List[Int]
    rest: Bool

type Bindings:
    names: List[Int]
    inits: List[Value]

fn mk(tag: Int, num: Int, text: String) Value:
    return Value(tag: tag, num: num, text: text)

fn num_v(n: Int) Value:
    return mk(TAG_NUM, n, "")

fn bool_v(b: Bool) Value:
    if b:
        return mk(TAG_BOOL, 1, "")

    return mk(TAG_BOOL, 0, "")

fn str_v(s: String) Value:
    return mk(TAG_STR, 0, s)

fn sym_v(id: Int) Value:
    return mk(TAG_SYM, id, "")

fn nil_v() Value:
    return mk(TAG_NIL, 0, "")

fn void_v() Value:
    return mk(TAG_VOID, 0, "")

fn truthy(v: Value) Bool:
    return not (v.tag == TAG_BOOL and v.num == 0)

fn rt(msg: String) Fail:
    return Fail(msg: msg, syntax: false)

fn syn(msg: String) Fail:
    return Fail(msg: msg, syntax: true)

fn bad_form(name: String) Fail:
    return syn("syntax error: bad form: {name}")

fn type_fail(m: Machine, name: String, kind: String, v: Value) Fail:
    return rt("{name}: expected {kind}, got {show(m, v, true)}")

fn done_step(v: Value) Step:
    return Step(done: true, value: v, env: 0, call: false)

fn next_step(x: Value, env: Int) Step:
    return Step(done: false, value: x, env: env, call: false)

fn call_step(x: Value, env: Int) Step:
    return Step(done: false, value: x, env: env, call: true)

# ---------------------------------------------------------------- symbols and environments
fn intern(var m: Machine, name: String) Int:
    if let id = m.sym_ids.get(name):
        return id

    m.syms.append(name)
    m.globals.append(mk(TAG_UNBOUND, 0, ""))

    let id = m.syms.length() - 1
    m.sym_ids.add(name, id)
    return id

fn new_frame(var m: Machine, parent: Int) Int:
    m.frame_parent.append(parent)
    m.frame_head.append(-1)
    return m.frame_parent.length() - 1

fn add_binding(var m: Machine, f: Int, sym: Int, v: Value) Unit:
    if f == 0:
        m.globals.set(sym, v)
        return

    m.node_sym.append(sym)
    m.node_val.append(v)
    m.node_next.append(m.frame_head.get(f))
    m.frame_head.set(f, m.node_sym.length() - 1)

# The value bound to `sym`, or an UNBOUND value when there is none.
fn lookup(m: Machine, env: Int, sym: Int) Value:
    var f = env

    while f > 0:
        var n = m.frame_head.get(f)

        while n >= 0:
            if m.node_sym.get(n) == sym:
                return m.node_val.get(n)

            n = m.node_next.get(n)

        f = m.frame_parent.get(f)

    return m.globals.get(sym)

# Assigns an existing binding; false when the symbol is unbound.
fn assign(var m: Machine, env: Int, sym: Int, v: Value) Bool:
    var f = env

    while f > 0:
        var n = m.frame_head.get(f)

        while n >= 0:
            if m.node_sym.get(n) == sym:
                m.node_val.set(n, v)
                return true

            n = m.node_next.get(n)

        f = m.frame_parent.get(f)

    if m.globals.get(sym).tag == TAG_UNBOUND:
        return false

    m.globals.set(sym, v)
    return true

# ---------------------------------------------------------------- pairs and lists
fn cons(var m: Machine, a: Value, d: Value) Value:
    m.cars.append(a)
    m.cdrs.append(d)
    return mk(TAG_PAIR, m.cars.length() - 1, "")

fn car(m: Machine, p: Value) Value:
    return m.cars.get(p.num)

fn cdr(m: Machine, p: Value) Value:
    return m.cdrs.get(p.num)

# The elements of a proper list, or none when the chain ends in a non-empty tail.
fn list_items(m: Machine, v: Value) Optional[List[Value]]:
    var out = List[Value]()
    var cur = v

    while cur.tag == TAG_PAIR:
        out.append(car(m, cur))
        cur = cdr(m, cur)

    if cur.tag != TAG_NIL:
        return none

    return some(out)

fn require_list(m: Machine, name: String, v: Value) Result[List[Value], Fail]:
    if let items = list_items(m, v):
        return ok(items)

    return error(type_fail(m, name, "list", v))

# Builds a list from items[start..] ending in `tail`.
fn build_list(var m: Machine, items: List[Value], start: Int, tail: Value) Value:
    var result = tail
    var i = items.length() - 1

    while i >= start:
        result = cons(var m, items.get(i), result)
        i -= 1

    return result

# (begin forms...) built from items[start..], used as a body in tail position.
fn body_form(var m: Machine, items: List[Value], start: Int) Value:
    let forms = build_list(var m, items, start, nil_v())
    return cons(var m, sym_v(S_BEGIN), forms)

# ---------------------------------------------------------------- printing and equality
fn quote_str(s: String) String:
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

fn show(m: Machine, v: Value, readable: Bool) String:
    if v.tag == TAG_NUM:
        return "{v.num}"

    if v.tag == TAG_BOOL:
        if v.num == 1:
            return "#t"

        return "#f"

    if v.tag == TAG_STR:
        if readable:
            return quote_str(v.text)

        return v.text

    if v.tag == TAG_SYM:
        return m.syms.get(v.num)
    if v.tag == TAG_NIL:
        return "()"
    if v.tag == TAG_VOID:
        return "#<void>"
    if v.tag == TAG_PRIM:
        return "#<builtin {m.prim_names.get(v.num)}>"

    if v.tag == TAG_CLO:
        let name = m.clos.get(v.num).name
        if name == "":
            return "#<procedure>"

        return "#<procedure {name}>"

    var out = "("
    var cur = v
    var first = true

    while cur.tag == TAG_PAIR:
        if not first:
            out = out + " "
        first = false
        out = out + show(m, car(m, cur), readable)
        cur = cdr(m, cur)

    if cur.tag != TAG_NIL:
        out = out + " . " + show(m, cur, readable)
    return out + ")"

fn eqv(a: Value, b: Value) Bool:
    if a.tag != b.tag:
        return false
    if a.tag == TAG_NUM or a.tag == TAG_BOOL or a.tag == TAG_SYM:
        return a.num == b.num
    if a.tag == TAG_NIL:
        return true

    return false

fn equal_values(m: Machine, a: Value, b: Value) Bool:
    var x = a
    var y = b

    while x.tag == TAG_PAIR and y.tag == TAG_PAIR:
        if not equal_values(m, car(m, x), car(m, y)):
            return false

        x = cdr(m, x)
        y = cdr(m, y)

    if x.tag == TAG_PAIR or y.tag == TAG_PAIR:
        return false
    if x.tag != y.tag:
        return false
    if x.tag == TAG_STR:
        return x.text == y.text
    if (
        x.tag == TAG_NUM
        or x.tag == TAG_BOOL
        or x.tag == TAG_SYM
        or x.tag == TAG_PRIM
        or x.tag == TAG_CLO
    ):
        return x.num == y.num

    return true

fn emit(var m: Machine, s: String) Unit:
    if s.length() > 0:
        m.line_start = s.ends_with("\n")
    stdout().write(s).get()

# ---------------------------------------------------------------- reader
fn is_ws(c: Int) Bool:
    return c == 32 or c == 9 or c == 10 or c == 13

fn is_delim(c: Int) Bool:
    return c == -1 or is_ws(c) or c == 40 or c == 41 or c == 34 or c == 59

fn peek(r: Reader) Int:
    return r.src.get(r.pos, -1)

fn skip_space(var r: Reader) Unit:
    while true:
        let c = peek(r)

        if c == 59:
            while peek(r) != 10 and peek(r) != -1:
                r.pos += 1
        else if is_ws(c):
            r.pos += 1
        else:
            return

fn codes_to_string(codes: List[Int]) String:
    return from_scalars(codes).get()

fn int_shape(codes: List[Int]) Bool:
    var i = 0
    if codes.length() > 0 and codes.get(0) == 45:
        i = 1
    if i >= codes.length():
        return false

    while i < codes.length():
        let c = codes.get(i)
        if c < 48 or c > 57:
            return false

        i += 1

    return true

# Parses a token that has int_shape; none when the value does not fit in int64.
fn parse_int(codes: List[Int]) Optional[Int]:
    var i = 0
    var neg = false

    if codes.length() > 0 and codes.get(0) == 45:
        neg = true
        i = 1

    if i >= codes.length():
        return none

    var n = 0

    while i < codes.length():
        let d = codes.get(i) - 48
        if d < 0 or d > 9:
            return none

        if neg:
            if n < (MIN_INT + d) / 10:
                return none

            n = n * 10 - d
        else:
            if n > (MAX_INT - d) / 10:
                return none

            n = n * 10 + d

        i += 1

    return some(n)

fn read_atom(var m: Machine, var r: Reader) Result[Value, Fail]:
    var codes = List[Int]()

    while not is_delim(peek(r)):
        codes.append(peek(r))
        r.pos += 1

    let text = codes_to_string(codes)
    if text == "#t":
        return ok(bool_v(true))
    if text == "#f":
        return ok(bool_v(false))
    if codes.get(0) == 35:
        return error(syn("syntax error: bad token: {text}"))
    if text == ".":
        return error(syn("syntax error: unexpected ."))

    if int_shape(codes):
        if let n = parse_int(codes):
            return ok(num_v(n))

        return error(syn("syntax error: integer out of range"))

    return ok(sym_v(intern(var m, text)))

fn read_string(var r: Reader) Result[Value, Fail]:
    r.pos += 1

    var codes = List[Int]()

    while true:
        let c = peek(r)
        if c == -1:
            return error(syn("syntax error: unterminated string"))

        r.pos += 1
        if c == 34:
            break

        if c == 92:
            let e = peek(r)
            if e == -1:
                return error(syn("syntax error: unterminated string"))

            r.pos += 1

            if e == 110:
                codes.append(10)
            else if e == 116:
                codes.append(9)
            else if e == 92:
                codes.append(92)
            else if e == 34:
                codes.append(34)
            else:
                return error(syn("syntax error: bad escape"))
        else:
            codes.append(c)

    return ok(str_v(codes_to_string(codes)))

fn read_list(var m: Machine, var r: Reader) Result[Value, Fail]:
    var items = List[Value]()

    while true:
        skip_space(var r)

        let c = peek(r)
        if c == -1:
            return error(syn("syntax error: unexpected end of input"))

        if c == 41:
            r.pos += 1
            return ok(build_list(var m, items, 0, nil_v()))

        if c == 46 and is_delim(r.src.get(r.pos + 1, -1)):
            if items.length() == 0:
                return error(syn("syntax error: bad dotted list"))

            r.pos += 1
            skip_space(var r)
            if peek(r) == -1:
                return error(syn("syntax error: unexpected end of input"))
            if peek(r) == 41:
                return error(syn("syntax error: bad dotted list"))

            let tail = try read_datum(var m, var r)
            skip_space(var r)
            if peek(r) == -1:
                return error(syn("syntax error: unexpected end of input"))
            if peek(r) != 41:
                return error(syn("syntax error: bad dotted list"))

            r.pos += 1
            return ok(build_list(var m, items, 0, tail))

        let item = try read_datum(var m, var r)
        items.append(item)

fn read_datum(var m: Machine, var r: Reader) Result[Value, Fail]:
    skip_space(var r)

    let c = peek(r)
    if c == -1:
        return error(syn("syntax error: unexpected end of input"))

    if c == 40:
        r.pos += 1
        return read_list(var m, var r)

    if c == 41:
        return error(syn("syntax error: unexpected )"))

    if c == 39:
        r.pos += 1

        let d = try read_datum(var m, var r)
        let tail = cons(var m, d, nil_v())
        return ok(cons(var m, sym_v(S_QUOTE), tail))

    if c == 34:
        return read_string(var r)

    return read_atom(var m, var r)

# ---------------------------------------------------------------- evaluator
fn is_proper(m: Machine, x: Value) Bool:
    var cur = x
    while cur.tag == TAG_PAIR:
        cur = cdr(m, cur)
    return cur.tag == TAG_NIL

fn names_contains(names: List[Int], sym: Int) Bool:
    for n in names:
        if n == sym:
            return true
    return false

fn parse_params(m: Machine, spec: Value, form: String) Result[Params, Fail]:
    var names = List[Int]()
    var cur = spec

    if cur.tag == TAG_SYM:
        names.append(cur.num)
        return ok(Params(names: names, rest: true))

    while cur.tag == TAG_PAIR:
        let p = car(m, cur)
        if p.tag != TAG_SYM or names_contains(names.clone(), p.num):
            return error(bad_form(form))

        names.append(p.num)
        cur = cdr(m, cur)

    var rest = false

    if cur.tag == TAG_SYM:
        if names_contains(names.clone(), cur.num):
            return error(bad_form(form))

        names.append(cur.num)
        rest = true
    else if cur.tag != TAG_NIL:
        return error(bad_form(form))

    return ok(Params(names: names, rest: rest))

fn make_closure(var m: Machine, name: String, p: Params, body: Value, env: Int) Value:
    m.clos.append(
        Closure(
            name: name, params: p.names.clone(), rest: p.rest, body: body, env: env
        )
    )
    return mk(TAG_CLO, m.clos.length() - 1, "")

# Parses (closure params body...) given the form's items.
fn make_lambda(var m: Machine, items: List[Value], env: Int, name: String) Result[
    Value, Fail
]:
    if items.length() < 3:
        return error(bad_form("closure"))

    let p = try parse_params(m, items.get(1), "closure")
    let body = body_form(var m, items, 2)
    return ok(make_closure(var m, name, p, body, env))

# Creates a frame for a call to closure `id`, binding its parameters.
fn bind_args(var m: Machine, id: Int, args: List[Value]) Result[Int, Fail]:
    let params = m.clos.get(id).params.clone()
    let rest = m.clos.get(id).rest
    let env = m.clos.get(id).env
    var nparams = params.length()
    if rest:
        nparams -= 1

    let n = args.length()

    if n < nparams or (not rest and n > nparams):
        var name = m.clos.get(id).name
        if name == "":
            name = "closure"

        var expected = "{nparams}"
        if rest:
            expected = "at least {nparams}"
        return error(
            rt(
                "wrong number of arguments to {name}: expected {expected}, got {n}"
            )
        )

    let fid = new_frame(var m, env)
    var i = 0

    while i < nparams:
        add_binding(var m, fid, params.get(i), args.get(i))
        i += 1

    if rest:
        let rest_list = build_list(var m, args, nparams, nil_v())
        add_binding(var m, fid, params.get(nparams), rest_list)

    return ok(fid)

# Calls any procedure from a non-tail position.
# Calls any procedure from a non-tail position; `d` is the current call depth.
fn apply_proc(var m: Machine, f: Value, args: List[Value], d: Int) Result[Value, Fail]:
    if f.tag == TAG_PRIM:
        return call_prim(var m, f.num, args, d)
    if f.tag != TAG_CLO:
        return error(rt("not a procedure: {show(m, f, true)}"))

    let fid = try bind_args(var m, f.num, args)
    if d >= MAX_DEPTH:
        return error(rt("recursion limit exceeded"))

    let body = m.clos.get(f.num).body
    return eval(var m, body, fid, d + 1, true)

# Evaluates x in env. `d0` is the call depth of the caller; `entered0` says the body
# being run was already counted as a call, so tail calls here do not count again.
fn eval(var m: Machine, start_x: Value, start_env: Int, d0: Int, entered0: Bool) Result[
    Value, Fail
]:
    var x = start_x
    var env = start_env
    var depth = d0
    var entered = entered0

    while true:
        if x.tag == TAG_SYM:
            let v = lookup(m, env, x.num)
            if v.tag != TAG_UNBOUND:
                return ok(v)

            return error(rt("unbound variable: {m.syms.get(x.num)}"))

        if x.tag != TAG_PAIR:
            if x.tag == TAG_NIL:
                return error(syn("syntax error: empty application"))

            return ok(x)

        let head = car(m, x)

        if head.tag == TAG_SYM and head.num < SPECIAL_COUNT:
            let proper = list_items(m, x)
            if proper.is_none():
                return error(bad_form(m.syms.get(head.num)))

            let st = try special_form(var m, head.num, proper.get(), env, depth)
            if st.done:
                return ok(st.value)

            x = st.value
            env = st.env

            if st.call and not entered:
                if depth >= MAX_DEPTH:
                    return error(rt("recursion limit exceeded"))

                depth += 1
                entered = true
        else:
            if not is_proper(m, x):
                return error(syn("syntax error: bad application"))

            let f = try eval(var m, head, env, depth, false)
            var args = List[Value]()
            var cur = cdr(m, x)

            while cur.tag == TAG_PAIR:
                let arg = car(m, cur)
                let v = try eval(var m, arg, env, depth, false)
                args.append(v)
                cur = cdr(m, cur)

            if f.tag == TAG_PRIM:
                return call_prim(var m, f.num, args, depth)
            if f.tag != TAG_CLO:
                return error(rt("not a procedure: {show(m, f, true)}"))

            let fid = try bind_args(var m, f.num, args)
            x = m.clos.get(f.num).body
            env = fid

            if not entered:
                if depth >= MAX_DEPTH:
                    return error(rt("recursion limit exceeded"))

                depth += 1
                entered = true

fn special_form(var m: Machine, sid: Int, items: List[Value], env: Int, d: Int) Result[
    Step, Fail
]:
    if sid == S_IF:
        return sf_if(var m, items, env, d)
    if sid == S_BEGIN:
        return sf_begin(var m, items, env, d)
    if sid == S_DEFINE:
        return sf_define(var m, items, env, d)
    if sid == S_LET:
        return sf_let(var m, items, env, d)
    if sid == S_SET:
        return sf_set(var m, items, env, d)

    if sid == S_LAMBDA:
        if items.length() < 3:
            return error(bad_form("closure"))

        let f = try make_lambda(var m, items, env, "")
        return ok(done_step(f))

    if sid == S_QUOTE:
        if items.length() != 2:
            return error(bad_form("quote"))

        return ok(done_step(items.get(1)))

    if sid == S_LETSTAR:
        return sf_letstar(var m, items, env, "let*", d)
    if sid == S_LETREC:
        return sf_letstar(var m, items, env, "letrec", d)
    if sid == S_COND:
        return sf_cond(var m, items, env, d)
    if sid == S_AND:
        return sf_and(var m, items, env, d)
    if sid == S_OR:
        return sf_or(var m, items, env, d)
    if sid == S_WHEN:
        return sf_when(var m, items, env, false, d)
    if sid == S_UNLESS:
        return sf_when(var m, items, env, true, d)

    return sf_try(var m, items, env, d)

fn sf_if(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() != 3 and items.length() != 4:
        return error(bad_form("if"))

    let t = try eval(var m, items.get(1), env, d, false)
    if truthy(t):
        return ok(next_step(items.get(2), env))
    if items.length() == 4:
        return ok(next_step(items.get(3), env))

    return ok(done_step(void_v()))

fn sf_define(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() < 3:
        return error(bad_form("define"))

    let target = items.get(1)

    if target.tag == TAG_SYM:
        if items.length() != 3:
            return error(bad_form("define"))

        let expr = items.get(2)
        var value = void_v()

        if (
            expr.tag == TAG_PAIR
            and car(m, expr).tag == TAG_SYM
            and car(m, expr).num == S_LAMBDA
        ):
            let lambda_items = list_items(m, expr)
            if lambda_items.is_none():
                return error(bad_form("closure"))

            let lambda_name = m.syms.get(target.num)
            value = try make_lambda(var m, lambda_items.get(), env, lambda_name)
        else:
            value = try eval(var m, expr, env, d, false)

        add_binding(var m, env, target.num, value)
        return ok(done_step(void_v()))

    if target.tag == TAG_PAIR:
        let head = car(m, target)
        if head.tag != TAG_SYM:
            return error(bad_form("define"))

        let p = try parse_params(m, cdr(m, target), "define")
        let body = body_form(var m, items, 2)
        let name = m.syms.get(head.num)
        let clo = make_closure(var m, name, p, body, env)
        add_binding(var m, env, head.num, clo)
        return ok(done_step(void_v()))

    return error(bad_form("define"))

fn sf_set(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() != 3 or items.get(1).tag != TAG_SYM:
        return error(bad_form("set!"))

    let sym = items.get(1).num
    let v = try eval(var m, items.get(2), env, d, false)
    if not assign(var m, env, sym, v):
        return error(rt("unbound variable: {m.syms.get(sym)}"))

    return ok(done_step(void_v()))

fn sf_begin(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() == 1:
        return ok(done_step(void_v()))

    var i = 1

    while i < items.length() - 1:
        let v = try eval(var m, items.get(i), env, d, false)
        i += 1

    return ok(next_step(items.get(items.length() - 1), env))

fn parse_bindings(m: Machine, spec: Value, form: String) Result[Bindings, Fail]:
    let pairs = list_items(m, spec)
    if pairs.is_none():
        return error(bad_form(form))

    var names = List[Int]()
    var inits = List[Value]()

    for b in pairs.get():
        let parts = list_items(m, b)
        if parts.is_none():
            return error(bad_form(form))

        let p = parts.get()
        if p.length() != 2 or p.get(0).tag != TAG_SYM:
            return error(bad_form(form))

        names.append(p.get(0).num)
        inits.append(p.get(1))

    return ok(Bindings(names: names, inits: inits))

fn sf_let(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() < 3:
        return error(bad_form("let"))
    if items.get(1).tag == TAG_SYM:
        return sf_named_let(var m, items, env, d)

    let b = try parse_bindings(m, items.get(1), "let")
    var vals = List[Value]()
    for init in b.inits:
        vals.append(try eval(var m, init, env, d, false))

    let fid = new_frame(var m, env)
    var i = 0

    while i < vals.length():
        add_binding(var m, fid, b.names.get(i), vals.get(i))
        i += 1

    return ok(next_step(body_form(var m, items, 2), fid))

fn sf_named_let(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() < 4:
        return error(bad_form("let"))

    let sym = items.get(1).num
    let b = try parse_bindings(m, items.get(2), "let")
    var vals = List[Value]()
    for init in b.inits:
        vals.append(try eval(var m, init, env, d, false))

    let loop_env = new_frame(var m, env)
    let body = body_form(var m, items, 3)
    let loop_name = m.syms.get(sym)
    let clo = make_closure(
        var m, loop_name, Params(names: b.names.clone(), rest: false), body, loop_env
    )
    add_binding(var m, loop_env, sym, clo)

    let fid = try bind_args(var m, clo.num, vals)
    return ok(call_step(m.clos.get(clo.num).body, fid))

fn sf_letstar(var m: Machine, items: List[Value], env: Int, form: String, d: Int) Result[
    Step, Fail
]:
    if items.length() < 3:
        return error(bad_form(form))

    let b = try parse_bindings(m, items.get(1), form)
    let fid = new_frame(var m, env)
    var i = 0

    while i < b.names.length():
        let v = try eval(var m, b.inits.get(i), fid, d, false)
        add_binding(var m, fid, b.names.get(i), v)
        i += 1

    return ok(next_step(body_form(var m, items, 2), fid))

fn sf_cond(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    var i = 1

    while i < items.length():
        let parts = list_items(m, items.get(i))
        if parts.is_none():
            return error(bad_form("cond"))

        let p = parts.get()
        if p.length() == 0:
            return error(bad_form("cond"))

        let head = p.get(0)

        if head.tag == TAG_SYM and head.num == S_ELSE:
            if i != items.length() - 1 or p.length() < 2:
                return error(bad_form("cond"))

            return ok(next_step(body_form(var m, p, 1), env))

        let t = try eval(var m, head, env, d, false)

        if truthy(t):
            if p.length() == 1:
                return ok(done_step(t))

            return ok(next_step(body_form(var m, p, 1), env))

        i += 1

    return ok(done_step(void_v()))

fn sf_and(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() == 1:
        return ok(done_step(bool_v(true)))

    var i = 1

    while i < items.length() - 1:
        let v = try eval(var m, items.get(i), env, d, false)
        if not truthy(v):
            return ok(done_step(v))

        i += 1

    return ok(next_step(items.get(items.length() - 1), env))

fn sf_or(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() == 1:
        return ok(done_step(bool_v(false)))

    var i = 1

    while i < items.length() - 1:
        let v = try eval(var m, items.get(i), env, d, false)
        if truthy(v):
            return ok(done_step(v))

        i += 1

    return ok(next_step(items.get(items.length() - 1), env))

fn sf_when(var m: Machine, items: List[Value], env: Int, negate: Bool, d: Int) Result[
    Step, Fail
]:
    if items.length() < 3:
        var form = "when"
        if negate:
            form = "unless"
        return error(bad_form(form))

    let t = try eval(var m, items.get(1), env, d, false)
    var fires = truthy(t)
    if negate:
        fires = not fires
    if not fires:
        return ok(done_step(void_v()))

    return ok(next_step(body_form(var m, items, 2), env))

fn sf_try(var m: Machine, items: List[Value], env: Int, d: Int) Result[Step, Fail]:
    if items.length() != 3:
        return error(bad_form("try"))

    let r = eval(var m, items.get(1), env, d, false)
    if r.is_ok():
        return ok(done_step(r.get()))

    let failure = r.err()
    if failure.syntax:
        return error(failure)

    let handler = try eval(var m, items.get(2), env, d, false)
    var args = List[Value]()
    args.append(str_v(failure.msg))

    let v = try apply_proc(var m, handler, args, d)
    return ok(done_step(v))

# ---------------------------------------------------------------- builtins
fn define_prim(var m: Machine, name: String, lo: Int, hi: Int) Unit:
    m.prim_names.append(name)
    m.prim_min.append(lo)
    m.prim_max.append(hi)

    let sym = intern(var m, name)
    m.globals.set(sym, mk(TAG_PRIM, m.prim_names.length() - 1, ""))

fn install_prims(var m: Machine) Unit:
    define_prim(var m, "+", 0, -1)
    define_prim(var m, "-", 1, -1)
    define_prim(var m, "*", 0, -1)
    define_prim(var m, "quotient", 2, 2)
    define_prim(var m, "remainder", 2, 2)
    define_prim(var m, "modulo", 2, 2)
    define_prim(var m, "abs", 1, 1)
    define_prim(var m, "min", 1, -1)
    define_prim(var m, "max", 1, -1)
    define_prim(var m, "=", 2, -1)
    define_prim(var m, "<", 2, -1)
    define_prim(var m, ">", 2, -1)
    define_prim(var m, "<=", 2, -1)
    define_prim(var m, ">=", 2, -1)
    define_prim(var m, "zero?", 1, 1)
    define_prim(var m, "even?", 1, 1)
    define_prim(var m, "odd?", 1, 1)
    define_prim(var m, "not", 1, 1)
    define_prim(var m, "null?", 1, 1)
    define_prim(var m, "pair?", 1, 1)
    define_prim(var m, "list?", 1, 1)
    define_prim(var m, "number?", 1, 1)
    define_prim(var m, "string?", 1, 1)
    define_prim(var m, "symbol?", 1, 1)
    define_prim(var m, "boolean?", 1, 1)
    define_prim(var m, "procedure?", 1, 1)
    define_prim(var m, "eq?", 2, 2)
    define_prim(var m, "equal?", 2, 2)
    define_prim(var m, "cons", 2, 2)
    define_prim(var m, "car", 1, 1)
    define_prim(var m, "cdr", 1, 1)
    define_prim(var m, "cadr", 1, 1)
    define_prim(var m, "cddr", 1, 1)
    define_prim(var m, "caddr", 1, 1)
    define_prim(var m, "set-car!", 2, 2)
    define_prim(var m, "set-cdr!", 2, 2)
    define_prim(var m, "list", 0, -1)
    define_prim(var m, "length", 1, 1)
    define_prim(var m, "append", 0, -1)
    define_prim(var m, "reverse", 1, 1)
    define_prim(var m, "list-ref", 2, 2)
    define_prim(var m, "list-tail", 2, 2)
    define_prim(var m, "range", 2, 2)
    define_prim(var m, "assoc", 2, 2)
    define_prim(var m, "member", 2, 2)
    define_prim(var m, "map", 2, -1)
    define_prim(var m, "for-each", 2, -1)
    define_prim(var m, "filter", 2, 2)
    define_prim(var m, "fold", 3, 3)
    define_prim(var m, "foldr", 3, 3)
    define_prim(var m, "apply", 2, -1)
    define_prim(var m, "sort", 2, 2)
    define_prim(var m, "string-length", 1, 1)
    define_prim(var m, "string-append", 0, -1)
    define_prim(var m, "substring", 3, 3)
    define_prim(var m, "string-ref", 2, 2)
    define_prim(var m, "string=?", 2, 2)
    define_prim(var m, "string<?", 2, 2)
    define_prim(var m, "string-upcase", 1, 1)
    define_prim(var m, "string-downcase", 1, 1)
    define_prim(var m, "string->number", 1, 1)
    define_prim(var m, "number->string", 1, 1)
    define_prim(var m, "string->symbol", 1, 1)
    define_prim(var m, "symbol->string", 1, 1)
    define_prim(var m, "string->list", 1, 1)
    define_prim(var m, "list->string", 1, 1)
    define_prim(var m, "string-join", 2, 2)
    define_prim(var m, "string-split", 2, 2)
    define_prim(var m, "string-contains?", 2, 2)
    define_prim(var m, "display", 1, 1)
    define_prim(var m, "write", 1, 1)
    define_prim(var m, "newline", 0, 0)
    define_prim(var m, "void", 0, 0)
    define_prim(var m, "error", 1, -1)

fn call_prim(var m: Machine, op: Int, args: List[Value], d: Int) Result[Value, Fail]:
    let name = m.prim_names.get(op)
    let n = args.length()
    let lo = m.prim_min.get(op)
    let hi = m.prim_max.get(op)

    if n < lo or (hi >= 0 and n > hi):
        var expected = "{lo}"

        if hi < 0:
            expected = "at least {lo}"
        else if lo != hi:
            expected = "{lo} to {hi}"

        return error(
            rt(
                "wrong number of arguments to {name}: expected {expected}, got {n}"
            )
        )

    if op >= P_MAP and op <= P_SORT:
        return higher_order(var m, op, name, args, d)

    return prim_dispatch(var m, op, name, args)

fn int_arg(m: Machine, name: String, v: Value) Result[Int, Fail]:
    if v.tag != TAG_NUM:
        return error(type_fail(m, name, "integer", v))

    return ok(v.num)

fn str_arg(m: Machine, name: String, v: Value) Result[String, Fail]:
    if v.tag != TAG_STR:
        return error(type_fail(m, name, "string", v))

    return ok(v.text)

fn proc_arg(m: Machine, name: String, v: Value) Result[Value, Fail]:
    if v.tag != TAG_PRIM and v.tag != TAG_CLO:
        return error(type_fail(m, name, "procedure", v))

    return ok(v)

fn checked_add(a: Int, b: Int) Result[Int, Fail]:
    if b > 0 and a > MAX_INT - b:
        return error(rt("integer overflow"))
    if b < 0 and a < MIN_INT - b:
        return error(rt("integer overflow"))

    return ok(a + b)

fn checked_sub(a: Int, b: Int) Result[Int, Fail]:
    if b < 0 and a > MAX_INT + b:
        return error(rt("integer overflow"))
    if b > 0 and a < MIN_INT + b:
        return error(rt("integer overflow"))

    return ok(a - b)

fn checked_mul(a: Int, b: Int) Result[Int, Fail]:
    if a == 0 or b == 0:
        return ok(0)

    var overflow = false

    if a > 0 and b > 0:
        overflow = a > MAX_INT / b
    else if a > 0 and b < 0:
        overflow = b < MIN_INT / a
    else if a < 0 and b > 0:
        overflow = a < MIN_INT / b
    else:
        overflow = a < MAX_INT / b

    if overflow:
        return error(rt("integer overflow"))

    return ok(a * b)

fn int_divide(op: Int, a: Int, b: Int) Result[Int, Fail]:
    if b == 0:
        return error(rt("division by zero"))

    if b == -1:
        if op == P_QUOT:
            if a == MIN_INT:
                return error(rt("integer overflow"))

            return ok(-a)

        return ok(0)

    if op == P_QUOT:
        return ok(a / b)

    var r = a % b
    if op == P_REM:
        return ok(r)

    if r != 0 and ((r < 0) != (b < 0)):
        r = r + b
    return ok(r)

fn prim_dispatch(var m: Machine, op: Int, name: String, args: List[Value]) Result[
    Value, Fail
]:
    if op <= P_MAX:
        if op == P_ADD or op == P_SUB or op == P_MUL:
            return arith(var m, op, name, args)

        if op == P_QUOT or op == P_REM or op == P_MOD:
            let a = try int_arg(m, name, args.get(0))
            let b = try int_arg(m, name, args.get(1))
            let q = try int_divide(op, a, b)
            return ok(num_v(q))

        if op == P_ABS:
            let a = try int_arg(m, name, args.get(0))
            if a == MIN_INT:
                return error(rt("integer overflow"))
            if a < 0:
                return ok(num_v(-a))

            return ok(num_v(a))

        if op == P_MIN or op == P_MAX:
            var best = try int_arg(m, name, args.get(0))
            var i = 1

            while i < args.length():
                let v = try int_arg(m, name, args.get(i))
                if op == P_MIN and v < best:
                    best = v
                if op == P_MAX and v > best:
                    best = v
                i += 1

            return ok(num_v(best))

    if op >= P_EQ and op <= P_GE:
        return compare(var m, op, name, args)

    if op == P_ZERO or op == P_EVEN or op == P_ODD:
        let a = try int_arg(m, name, args.get(0))
        if op == P_ZERO:
            return ok(bool_v(a == 0))
        if op == P_EVEN:
            return ok(bool_v(a % 2 == 0))

        return ok(bool_v(a % 2 != 0))

    return predicates_and_lists(var m, op, name, args)

fn arith(var m: Machine, op: Int, name: String, args: List[Value]) Result[Value, Fail]:
    if op == P_ADD:
        var acc = 0
        var i = 0

        while i < args.length():
            let n = try int_arg(m, name, args.get(i))
            acc = try checked_add(acc, n)
            i += 1

        return ok(num_v(acc))

    if op == P_MUL:
        var acc = 1
        var i = 0

        while i < args.length():
            let n = try int_arg(m, name, args.get(i))
            acc = try checked_mul(acc, n)
            i += 1

        return ok(num_v(acc))

    let first = try int_arg(m, name, args.get(0))

    if args.length() == 1:
        if first == MIN_INT:
            return error(rt("integer overflow"))

        return ok(num_v(-first))

    var acc = first
    var i = 1

    while i < args.length():
        let n = try int_arg(m, name, args.get(i))
        acc = try checked_sub(acc, n)
        i += 1

    return ok(num_v(acc))

fn compare(var m: Machine, op: Int, name: String, args: List[Value]) Result[Value, Fail]:
    var nums = List[Int]()
    for v in args:
        nums.append(try int_arg(m, name, v))

    var result = true
    var i = 0

    while i + 1 < nums.length():
        let a = nums.get(i)
        let b = nums.get(i + 1)
        if op == P_EQ and a != b:
            result = false
        if op == P_LT and not (a < b):
            result = false
        if op == P_GT and not (a > b):
            result = false
        if op == P_LE and not (a <= b):
            result = false
        if op == P_GE and not (a >= b):
            result = false
        i += 1

    return ok(bool_v(result))

fn predicates_and_lists(var m: Machine, op: Int, name: String, args: List[Value]) Result[
    Value, Fail
]:
    let a = args.get(0, void_v())
    if op == P_NOT:
        return ok(bool_v(not truthy(a)))
    if op == P_NULL:
        return ok(bool_v(a.tag == TAG_NIL))
    if op == P_PAIRP:
        return ok(bool_v(a.tag == TAG_PAIR))
    if op == P_LISTP:
        return ok(bool_v(list_items(m, a).is_some()))
    if op == P_NUMBERP:
        return ok(bool_v(a.tag == TAG_NUM))
    if op == P_STRINGP:
        return ok(bool_v(a.tag == TAG_STR))
    if op == P_SYMBOLP:
        return ok(bool_v(a.tag == TAG_SYM))
    if op == P_BOOLP:
        return ok(bool_v(a.tag == TAG_BOOL))
    if op == P_PROCP:
        return ok(bool_v(a.tag == TAG_PRIM or a.tag == TAG_CLO))
    if op == P_EQP:
        return ok(bool_v(eqv(a, args.get(1))))
    if op == P_EQUAL:
        return ok(bool_v(equal_values(m, a, args.get(1))))
    if op == P_CONS:
        return ok(cons(var m, a, args.get(1)))

    if op == P_CAR or op == P_CDR:
        if a.tag != TAG_PAIR:
            return error(type_fail(m, name, "pair", a))
        if op == P_CAR:
            return ok(car(m, a))

        return ok(cdr(m, a))

    if op == P_CADR or op == P_CDDR or op == P_CADDR:
        if a.tag != TAG_PAIR:
            return error(type_fail(m, name, "pair", a))

        let d1 = cdr(m, a)
        if d1.tag != TAG_PAIR:
            return error(type_fail(m, name, "pair", d1))
        if op == P_CADR:
            return ok(car(m, d1))
        if op == P_CDDR:
            return ok(cdr(m, d1))

        let d2 = cdr(m, d1)
        if d2.tag != TAG_PAIR:
            return error(type_fail(m, name, "pair", d2))

        return ok(car(m, d2))

    if op == P_SETCAR or op == P_SETCDR:
        if a.tag != TAG_PAIR:
            return error(type_fail(m, name, "pair", a))

        if op == P_SETCAR:
            m.cars.set(a.num, args.get(1))
        else:
            m.cdrs.set(a.num, args.get(1))

        return ok(void_v())

    return list_prims(var m, op, name, args)

fn list_prims(var m: Machine, op: Int, name: String, args: List[Value]) Result[
    Value, Fail
]:
    if op == P_LIST:
        return ok(build_list(var m, args, 0, nil_v()))

    if op == P_LENGTH:
        let items = try require_list(m, name, args.get(0))
        return ok(num_v(items.length()))

    if op == P_APPEND:
        if args.length() == 0:
            return ok(nil_v())

        var out = List[Value]()
        var i = 0

        while i < args.length() - 1:
            let items = try require_list(m, name, args.get(i))
            for v in items:
                out.append(v)
            i += 1

        return ok(build_list(var m, out, 0, args.get(args.length() - 1)))

    if op == P_REVERSE:
        let items = try require_list(m, name, args.get(0))
        var result = nil_v()
        for v in items:
            result = cons(var m, v, result)
        return ok(result)

    if op == P_LISTREF:
        let items = try require_list(m, name, args.get(0))
        let k = try int_arg(m, name, args.get(1))
        if k < 0 or k >= items.length():
            return error(rt("list-ref: index out of range"))

        return ok(items.get(k))

    if op == P_LISTTAIL:
        let items = try require_list(m, name, args.get(0))
        let k = try int_arg(m, name, args.get(1))
        if k < 0 or k > items.length():
            return error(rt("list-tail: index out of range"))

        var cur = args.get(0)
        var i = 0

        while i < k:
            cur = cdr(m, cur)
            i += 1

        return ok(cur)

    if op == P_RANGE:
        let a = try int_arg(m, name, args.get(0))
        let b = try int_arg(m, name, args.get(1))
        var result = nil_v()
        var i = b - 1

        while i >= a:
            result = cons(var m, num_v(i), result)
            i -= 1

        return ok(result)

    if op == P_ASSOC or op == P_MEMBER:
        let items = try require_list(m, name, args.get(1))
        let target = args.get(0)
        var cur = args.get(1)

        for e in items:
            if op == P_ASSOC:
                if e.tag != TAG_PAIR:
                    return error(type_fail(m, name, "pair", e))
                if equal_values(m, car(m, e), target):
                    return ok(e)
            else if equal_values(m, e, target):
                return ok(cur)

            cur = cdr(m, cur)

        return ok(bool_v(false))

    return string_prims(var m, op, name, args)

fn all_pairs(m: Machine, cursors: List[Value]) Bool:
    for c in cursors:
        if c.tag != TAG_PAIR:
            return false
    return true

fn higher_order(var m: Machine, op: Int, name: String, args: List[Value], d: Int) Result[
    Value, Fail
]:
    if op == P_MAP or op == P_FOREACH:
        let f = try proc_arg(m, name, args.get(0))
        var cursors = List[Value]()
        var i = 1

        while i < args.length():
            let items = try require_list(m, name, args.get(i))
            cursors.append(args.get(i))
            i += 1

        var out = List[Value]()

        while all_pairs(m, cursors.clone()):
            var call_args = List[Value]()
            var k = 0

            while k < cursors.length():
                call_args.append(car(m, cursors.get(k)))
                cursors.set(k, cdr(m, cursors.get(k)))
                k += 1

            let v = try apply_proc(var m, f, call_args, d)
            out.append(v)

        if op == P_FOREACH:
            return ok(void_v())

        return ok(build_list(var m, out, 0, nil_v()))

    if op == P_FILTER:
        let f = try proc_arg(m, name, args.get(0))
        let items = try require_list(m, name, args.get(1))
        var out = List[Value]()

        for v in items:
            var call_args = List[Value]()
            call_args.append(v)

            let keep = try apply_proc(var m, f, call_args, d)
            if truthy(keep):
                out.append(v)

        return ok(build_list(var m, out, 0, nil_v()))

    if op == P_FOLD or op == P_FOLDR:
        let f = try proc_arg(m, name, args.get(0))
        let items = try require_list(m, name, args.get(2))
        var acc = args.get(1)

        if op == P_FOLD:
            for v in items:
                var call_args = List[Value]()
                call_args.append(acc)
                call_args.append(v)
                acc = try apply_proc(var m, f, call_args, d)
        else:
            var i = items.length() - 1

            while i >= 0:
                var call_args = List[Value]()
                call_args.append(items.get(i))
                call_args.append(acc)
                acc = try apply_proc(var m, f, call_args, d)
                i -= 1

        return ok(acc)

    if op == P_APPLY:
        let f = try proc_arg(m, name, args.get(0))
        let last = try require_list(m, name, args.get(args.length() - 1))
        var call_args = List[Value]()
        var i = 1

        while i < args.length() - 1:
            call_args.append(args.get(i))
            i += 1

        for v in last:
            call_args.append(v)
        return apply_proc(var m, f, call_args, d)

    if op == P_SORT:
        let items = try require_list(m, name, args.get(0))
        let less = try proc_arg(m, name, args.get(1))
        let sorted = try sort_values(var m, items, less, d)
        return ok(build_list(var m, sorted, 0, nil_v()))

    return string_prims(var m, op, name, args)

# Stable merge sort; `less` is called as (less later earlier).
fn sort_values(var m: Machine, items: List[Value], less: Value, d: Int) Result[
    List[Value], Fail
]:
    let n = items.length()
    if n <= 1:
        return ok(items)

    let mid = n / 2
    var left = List[Value]()
    var right = List[Value]()
    var i = 0

    while i < n:
        if i < mid:
            left.append(items.get(i))
        else:
            right.append(items.get(i))

        i += 1

    let sl = try sort_values(var m, left, less, d)
    let sr = try sort_values(var m, right, less, d)
    var out = List[Value]()
    var a = 0
    var b = 0

    while a < sl.length() and b < sr.length():
        var call_args = List[Value]()
        call_args.append(sr.get(b))
        call_args.append(sl.get(a))

        let take_right = try apply_proc(var m, less, call_args, d)

        if truthy(take_right):
            out.append(sr.get(b))
            b += 1
        else:
            out.append(sl.get(a))
            a += 1

    while a < sl.length():
        out.append(sl.get(a))
        a += 1

    while b < sr.length():
        out.append(sr.get(b))
        b += 1

    return ok(out)

fn string_prims(var m: Machine, op: Int, name: String, args: List[Value]) Result[
    Value, Fail
]:
    if op == P_STRLEN:
        let s = try str_arg(m, name, args.get(0))
        return ok(num_v(s.length()))

    if op == P_STRAPPEND:
        var out = ""
        var i = 0

        while i < args.length():
            let s = try str_arg(m, name, args.get(i))
            out = out + s
            i += 1

        return ok(str_v(out))

    if op == P_SUBSTRING:
        let s = try str_arg(m, name, args.get(0))
        let start = try int_arg(m, name, args.get(1))
        let end = try int_arg(m, name, args.get(2))
        if start < 0 or start > end or end > s.length():
            return error(rt("substring: index out of range"))

        return ok(str_v(s.slice_scalars(start, end).get()))

    if op == P_STRREF:
        let s = try str_arg(m, name, args.get(0))
        let k = try int_arg(m, name, args.get(1))
        if k < 0 or k >= s.length():
            return error(rt("string-ref: index out of range"))

        return ok(str_v(s.slice_scalars(k, k + 1).get()))

    if op == P_STREQ or op == P_STRLT:
        let a = try str_arg(m, name, args.get(0))
        let b = try str_arg(m, name, args.get(1))
        if op == P_STREQ:
            return ok(bool_v(a == b))

        return ok(bool_v(a < b))

    if op == P_UPCASE or op == P_DOWNCASE:
        let s = try str_arg(m, name, args.get(0))
        if op == P_UPCASE:
            return ok(str_v(s.upper()))

        return ok(str_v(s.lower()))

    if op == P_STR2NUM:
        let s = try str_arg(m, name, args.get(0))
        let codes = s.to_bytes().values()
        if int_shape(codes):
            if let n = parse_int(codes):
                return ok(num_v(n))
        return ok(bool_v(false))

    if op == P_NUM2STR:
        let n = try int_arg(m, name, args.get(0))
        return ok(str_v("{n}"))

    if op == P_STR2SYM:
        let s = try str_arg(m, name, args.get(0))
        return ok(sym_v(intern(var m, s)))

    if op == P_SYM2STR:
        let a = args.get(0)
        if a.tag != TAG_SYM:
            return error(type_fail(m, name, "symbol", a))

        return ok(str_v(m.syms.get(a.num)))

    return text_prims(var m, op, name, args)

fn text_prims(var m: Machine, op: Int, name: String, args: List[Value]) Result[
    Value, Fail
]:
    if op == P_STR2LIST:
        let s = try str_arg(m, name, args.get(0))
        var out = List[Value]()
        for c in s.chars():
            out.append(str_v(c))
        return ok(build_list(var m, out, 0, nil_v()))

    if op == P_LIST2STR:
        let items = try require_list(m, name, args.get(0))
        var out = ""

        for v in items:
            if v.tag != TAG_STR:
                return error(type_fail(m, name, "string", v))

            out = out + v.text

        return ok(str_v(out))

    if op == P_STRJOIN:
        let items = try require_list(m, name, args.get(0))
        let sep = try str_arg(m, name, args.get(1))
        var parts = List[String]()

        for v in items:
            if v.tag != TAG_STR:
                return error(type_fail(m, name, "string", v))

            parts.append(v.text)

        return ok(str_v(parts.join(sep)))

    if op == P_STRSPLIT:
        let s = try str_arg(m, name, args.get(0))
        let sep = try str_arg(m, name, args.get(1))
        if sep.length() != 1:
            return error(rt("string-split: separator must be one character"))

        var out = List[Value]()
        for part in s.split(sep):
            out.append(str_v(part))
        return ok(build_list(var m, out, 0, nil_v()))

    if op == P_STRCONTAINS:
        let s = try str_arg(m, name, args.get(0))
        let sub = try str_arg(m, name, args.get(1))
        return ok(bool_v(s.contains(sub)))

    if op == P_DISPLAY or op == P_WRITE:
        emit(var m, show(m, args.get(0), op == P_WRITE))
        return ok(void_v())

    if op == P_NEWLINE:
        emit(var m, "\n")
        return ok(void_v())

    if op == P_VOID:
        return ok(void_v())

    # error
    let first = args.get(0)
    if first.tag != TAG_STR:
        return error(type_fail(m, "error", "string", first))

    var msg = first.text
    var i = 1

    while i < args.length():
        msg = msg + " " + show(m, args.get(i), true)
        i += 1

    return error(rt(msg))

# ---------------------------------------------------------------- driver
fn new_machine() Machine:
    var m = Machine(
        syms: List[String](), sym_ids: Map[String, Int](), globals: List[Value](),
        cars: List[Value](), cdrs: List[Value](), clos: List[Closure](),
        frame_parent: List[Int](), frame_head: List[Int](), node_sym: List[Int](),
        node_val: List[Value](), node_next: List[Int](), prim_names: List[String](),
        prim_min: List[Int](), prim_max: List[Int](), line_start: true
    )
    for name in [
        "quote", "if", "define", "set!", "closure", "begin", "let", "let*", "letrec",
        "cond", "and", "or", "when", "unless", "try", "else"
    ]:
        intern(var m, name)
    m.frame_parent.append(-1)
    m.frame_head.append(-1)
    install_prims(var m)
    return m

fn report(var m: Machine, failure: Fail) Unit:
    if not m.line_start:
        emit(var m, "\n")
    emit(var m, "error: {failure.msg}\n")

export fn main() Int:
    var m = new_machine()
    let data = read_all(stdin()).get()
    var r = Reader(src: data, pos: 0)

    while true:
        skip_space(var r)
        if peek(r) == -1:
            break

        let form = read_datum(var m, var r)

        if form.is_error():
            report(var m, form.err())
            break

        let res = eval(var m, form.get(), 0, 0, false)

        if res.is_error():
            report(var m, res.err())
            break

    stdout().flush().get()
    return 0
