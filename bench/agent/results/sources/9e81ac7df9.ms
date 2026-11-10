import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"
import StringBuilder from "@std/string.ms"

// ---------------------------------------------------------------------------
// Value representation: every Scheme value is an Int id into the heap tables.
// Heap tables: tags/nums/cars/cdrs describe values; the rest are side tables.
// ---------------------------------------------------------------------------

T_VOID := 0
T_BOOL := 1
T_INT := 2
T_SYM := 3
T_STR := 4
T_PAIR := 5
T_PRIM := 6
T_CLOS := 7
T_NIL := 8
V_VOID := 0
V_FALSE := 1
V_TRUE := 2
V_NIL := 3
NO_ID := -1
DEPTH_LIMIT := 10000
MAXI := 9223372036854775807
MINI := -9223372036854775807 - 1
// Special-form symbols are interned first, in this order, so their ids are fixed.
S_QUOTE := 0
S_IF := 1
S_DEFINE := 2
S_SET := 3
S_LAMBDA := 4
S_BEGIN := 5
S_LET := 6
S_LETSTAR := 7
S_LETREC := 8
S_COND := 9
S_AND := 10
S_OR := 11
S_WHEN := 12
S_UNLESS := 13
S_TRY := 14
S_ELSE := 15
NSPECIAL := 15

type Heap:
    tags: List[Int]
    nums: List[Int]
    cars: List[Int]
    cdrs: List[Int]
    strs: List[String]
    syms: Map[String, Int]
    symnames: List[String]
    gval: List[Int]
    cl_params: List[Int]
    cl_body: List[Int]
    cl_env: List[Int]
    cl_name: List[Int]
    fparent: List[Int]
    fhead: List[Int]
    bsym: List[Int]
    bval: List[Int]
    bnext: List[Int]
    pname: List[String]
    plo: List[Int]
    phi: List[Int]
    pgroup: List[Int]
    depth: Int
    out: StringBuilder
    nonempty: Bool
    lastnl: Bool
    chars: List[String]
    pos: Int
    v_begin: Int
    tx: Int
    tenv: Int
    tproc: Int
    targs: List[Int]

type Fail:
    msg: String
    syntax: Bool

fn rt(msg: String) Fail:
    return Fail(msg: msg, syntax: false)

fn syn(msg: String) Fail:
    return Fail(msg: "syntax error: " + msg, syntax: true)

fn bad(h: Heap, sf: Int) Fail:
    return syn("bad form: " + h.symnames[sf])

fn type_err(h: Heap, name: String, kind: String, v: Int) Fail:
    return rt(name + ": expected " + kind + ", got " + show(h, v, true))

fn arity_msg(name: String, lo: Int, hi: Int, m: Int) String:
    var e = "{lo}"

    if hi < 0:
        e = "at least {lo}"
    else if hi != lo:
        e = "{lo} to {hi}"

    return "wrong number of arguments to " + name + ": expected " + e + ", got {m}"

// ---------------------------------------------------------------------------
// Allocation
// ---------------------------------------------------------------------------

fn alloc(var h: Heap, t: Int, n: Int, a: Int, d: Int) Int:
    h.tags.append(t)
    h.nums.append(n)
    h.cars.append(a)
    h.cdrs.append(d)
    return h.tags.length() - 1

fn cons(var h: Heap, a: Int, d: Int) Int:
    return alloc(var h, T_PAIR, 0, a, d)

fn mk_int(var h: Heap, n: Int) Int:
    return alloc(var h, T_INT, n, 0, 0)

fn mk_str(var h: Heap, s: String) Int:
    h.strs.append(s)

    idx := h.strs.length() - 1
    return alloc(var h, T_STR, idx, 0, 0)

fn mk_sym(var h: Heap, sid: Int) Int:
    return alloc(var h, T_SYM, sid, 0, 0)

fn bool_val(b: Bool) Int:
    if b:
        return V_TRUE

    return V_FALSE

fn intern(var h: Heap, name: String) Int:
    found := h.syms.get(name)
    if known := found:
        return known

    sid := h.symnames.length()
    h.symnames.append(name.clone())
    h.gval.append(NO_ID)
    h.syms[name] = sid
    return sid

fn build_onto(var h: Heap, items: List[Int], tail: Int) Int:
    var res = tail
    var i = items.length() - 1

    while i >= 0:
        it := items[i]
        res = cons(var h, it, res)
        i -= 1

    return res

fn build_list(var h: Heap, items: List[Int]) Int:
    return build_onto(var h, items, V_NIL)

fn seq_of(var h: Heap, body: Int) Int:
    bv := h.v_begin
    return cons(var h, bv, body)

// ---------------------------------------------------------------------------
// List helpers
// ---------------------------------------------------------------------------

fn list_len(h: Heap, lst: Int) Int:
    var n = 0
    var p = lst

    while h.tags[p] == T_PAIR:
        n += 1
        p = h.cdrs[p]

    if p == V_NIL:
        return n

    return -1

fn nth(h: Heap, lst: Int, i: Int) Int:
    p := cdr_n(h, lst, i)
    return h.cars[p]

fn cdr_n(h: Heap, lst: Int, k: Int) Int:
    var p = lst
    var i = 0

    while i < k:
        p = h.cdrs[p]
        i += 1

    return p

fn elements(h: Heap, lst: Int) List[Int]:
    var res = List[Int]()
    var p = lst

    while h.tags[p] == T_PAIR:
        res.append(h.cars[p])
        p = h.cdrs[p]

    return res

fn arg(args: List[Int], i: Int) Int:
    if i < args.length():
        return args[i]

    return V_VOID

fn is_proc(h: Heap, v: Int) Bool:
    return h.tags[v] == T_PRIM or h.tags[v] == T_CLOS

fn in_list(xs: List[Int], v: Int) Bool:
    var i = 0

    while i < xs.length():
        if xs[i] == v:
            return true

        i += 1

    return false

// ---------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------

fn quote_str(s: String) String:
    var sb = StringBuilder()
    sb.append("\"")

    for c in s.chars():
        if c == "\"":
            sb.append("\\\"")
        else if c == "\\":
            sb.append("\\\\")
        else if c == "\n":
            sb.append("\\n")
        else if c == "\t":
            sb.append("\\t")
        else:
            sb.append(c)

    sb.append("\"")
    return sb.build()

fn show(h: Heap, v: Int, w: Bool) String:
    t := h.tags[v]
    if t == T_VOID:
        return "#<void>"

    if t == T_BOOL:
        if v == V_TRUE:
            return "#t"

        return "#f"

    if t == T_NIL:
        return "()"
    if t == T_INT:
        return "{h.nums[v]}"
    if t == T_SYM:
        return h.symnames[h.nums[v]].clone()

    if t == T_STR:
        s := h.strs[h.nums[v]].clone()
        if not w:
            return s

        return quote_str(s)

    if t == T_PRIM:
        return "#<builtin " + h.pname[h.nums[v]] + ">"

    if t == T_CLOS:
        nm := h.cl_name[h.nums[v]]
        if nm == NO_ID:
            return "#<procedure>"

        return "#<procedure " + h.symnames[nm] + ">"

    var sb = StringBuilder()
    sb.append("(")

    var cur = v

    while true:
        sb.append(show(h, h.cars[cur], w))

        d := h.cdrs[cur]

        if h.tags[d] == T_PAIR:
            sb.append(" ")
            cur = d
        else if d == V_NIL:
            break
        else:
            sb.append(" . ")
            sb.append(show(h, d, w))
            break

    sb.append(")")
    return sb.build()

fn emit(var h: Heap, s: String) Unit:
    if s == "":
        return

    h.out.append(s)
    h.nonempty = true
    h.lastnl = s.ends_with("\n")

fn flush(var h: Heap) Unit:
    s := h.out.drain()
    if s != "":
        stdout().write(s).get()

// ---------------------------------------------------------------------------
// Equality
// ---------------------------------------------------------------------------

fn is_eqv(h: Heap, a: Int, b: Int) Bool:
    ta := h.tags[a]
    if ta != h.tags[b]:
        return false
    if ta == T_INT or ta == T_SYM:
        return h.nums[a] == h.nums[b]
    if ta == T_BOOL:
        return a == b
    if ta == T_NIL:
        return true

    return false

fn is_equal(h: Heap, a0: Int, b0: Int) Bool:
    var a = a0
    var b = b0

    while true:
        ta := h.tags[a]
        if ta != h.tags[b]:
            return false

        if ta == T_PAIR:
            if not is_equal(h, h.cars[a], h.cars[b]):
                return false

            a = h.cdrs[a]
            b = h.cdrs[b]
        else if ta == T_STR:
            return h.strs[h.nums[a]] == h.strs[h.nums[b]]
        else if ta == T_INT or ta == T_SYM:
            return h.nums[a] == h.nums[b]
        else:
            return a == b

// ---------------------------------------------------------------------------
// Integers
// ---------------------------------------------------------------------------

fn add_int(a: Int, b: Int) Int!Fail:
    if (b > 0 and a > MAXI - b) or (b < 0 and a < MINI - b):
        return error(rt("integer overflow"))

    return ok(a + b)

fn sub_int(a: Int, b: Int) Int!Fail:
    if (b < 0 and a > MAXI + b) or (b > 0 and a < MINI + b):
        return error(rt("integer overflow"))

    return ok(a - b)

fn mul_int(a: Int, b: Int) Int!Fail:
    if a == 0 or b == 0:
        return ok(0)

    if a == -1:
        if b == MINI:
            return error(rt("integer overflow"))

        return ok(-b)

    if b == -1:
        if a == MINI:
            return error(rt("integer overflow"))

        return ok(-a)

    if a > 0 and b > 0 and a > MAXI / b:
        return error(rt("integer overflow"))
    if a > 0 and b < 0 and b < MINI / a:
        return error(rt("integer overflow"))
    if a < 0 and b > 0 and a < MINI / b:
        return error(rt("integer overflow"))
    if a < 0 and b < 0 and a < MAXI / b:
        return error(rt("integer overflow"))

    return ok(a * b)

fn digit_val(c: String) Int:
    ds := "0123456789".chars()
    var k = 0

    while k < 10:
        if ds[k] == c:
            return k

        k += 1

    return -1

// Parses -?[0-9]+ . Error 1 = not an integer literal, error 2 = out of int64 range.
fn text_int(s: String) Int!Int:
    cs := s.chars()
    n := cs.length()
    if n == 0:
        return error(1)

    var i = 0
    var neg = false

    if cs[0] == "-":
        neg = true
        i = 1

    if i >= n:
        return error(1)

    var k = i

    while k < n:
        if digit_val(cs[k]) < 0:
            return error(1)

        k += 1

    var acc = 0
    k = i

    while k < n:
        d := digit_val(cs[k])

        if neg:
            if acc < -922337203685477580:
                return error(2)
            if acc == -922337203685477580 and d > 8:
                return error(2)

            acc = acc * 10 - d
        else:
            if acc > 922337203685477580:
                return error(2)
            if acc == 922337203685477580 and d > 7:
                return error(2)

            acc = acc * 10 + d

        k += 1

    return ok(acc)

fn cmp_ok(name: String, a: Int, b: Int) Bool:
    if name == "=":
        return a == b
    if name == "<":
        return a < b
    if name == ">":
        return a > b
    if name == "<=":
        return a <= b

    return a >= b

fn ints_of(h: Heap, name: String, args: List[Int]) List[Int]!Fail:
    var res = List[Int]()

    for i in 0..args.length():
        v := args[i]
        if h.tags[v] != T_INT:
            return error(type_err(h, name, "integer", v))

        res.append(h.nums[v])

    return ok(res)

fn int_val(h: Heap, name: String, v: Int) Int!Fail:
    if h.tags[v] != T_INT:
        return error(type_err(h, name, "integer", v))

    return ok(h.nums[v])

fn str_of(h: Heap, name: String, v: Int) String!Fail:
    if h.tags[v] != T_STR:
        return error(type_err(h, name, "string", v))

    return ok(h.strs[h.nums[v]].clone())

// ---------------------------------------------------------------------------
// Reader. Works on the input as a list of one-scalar strings.
// ---------------------------------------------------------------------------

fn at_end(h: Heap) Bool:
    return h.pos >= h.chars.length()

fn is_delim(c: String) Bool:
    return (
        c == " "
        or c == "\n"
        or c == "\t"
        or c == "\r"
        or c == "("
        or c == ")"
        or c == "\""
        or c == ";"
    )

fn skip_ws(var h: Heap) Unit:
    while not at_end(h):
        c := h.chars[h.pos].clone()

        if c == " " or c == "\n" or c == "\t" or c == "\r":
            h.pos += 1
        else if c == ";":
            while not at_end(h):
                d := h.chars[h.pos].clone()
                if d == "\n":
                    break

                h.pos += 1
        else:
            return

fn read_token(var h: Heap) String:
    var sb = StringBuilder()

    while not at_end(h):
        c := h.chars[h.pos].clone()
        if is_delim(c):
            break

        sb.append(c)
        h.pos += 1

    return sb.build()

fn read_string(var h: Heap) Int!Fail:
    h.pos += 1

    var sb = StringBuilder()

    while true:
        if at_end(h):
            return error(syn("unterminated string"))

        c := h.chars[h.pos].clone()

        if c == "\"":
            h.pos += 1
            break

        if c == "\\":
            if h.pos + 1 >= h.chars.length():
                return error(syn("unterminated string"))

            e := h.chars[h.pos + 1].clone()

            if e == "n":
                sb.append("\n")
            else if e == "t":
                sb.append("\t")
            else if e == "\\":
                sb.append("\\")
            else if e == "\"":
                sb.append("\"")
            else:
                return error(syn("bad escape"))

            h.pos += 2
        else:
            sb.append(c)
            h.pos += 1

    s := sb.build()
    return ok(mk_str(var h, s))

fn dot_is_token(h: Heap) Bool:
    nxt := h.pos + 1
    if nxt >= h.chars.length():
        return true

    return is_delim(h.chars[nxt])

fn read_list(var h: Heap) Int!Fail:
    var items = List[Int]()
    var tail = V_NIL

    while true:
        skip_ws(var h)
        if at_end(h):
            return error(syn("unexpected end of input"))

        c := h.chars[h.pos].clone()

        if c == ")":
            h.pos += 1
            break

        if c == "." and dot_is_token(h):
            if items.length() == 0:
                return error(syn("bad dotted list"))

            h.pos += 1
            skip_ws(var h)
            if at_end(h):
                return error(syn("unexpected end of input"))
            if h.chars[h.pos] == ")":
                return error(syn("bad dotted list"))

            tail = try read_datum(var h)
            skip_ws(var h)
            if at_end(h):
                return error(syn("unexpected end of input"))
            if h.chars[h.pos] != ")":
                return error(syn("bad dotted list"))

            h.pos += 1
            break

        d := try read_datum(var h)
        items.append(d)

    return ok(build_onto(var h, items, tail))

fn read_datum(var h: Heap) Int!Fail:
    skip_ws(var h)
    if at_end(h):
        return error(syn("unexpected end of input"))

    c := h.chars[h.pos].clone()

    if c == "(":
        h.pos += 1
        return read_list(var h)

    if c == ")":
        return error(syn("unexpected )"))

    if c == "'":
        h.pos += 1

        d := try read_datum(var h)
        qs := mk_sym(var h, S_QUOTE)
        tl := cons(var h, d, V_NIL)
        return ok(cons(var h, qs, tl))

    if c == "\"":
        return read_string(var h)

    tok := read_token(var h)
    if tok == "#t":
        return ok(V_TRUE)
    if tok == "#f":
        return ok(V_FALSE)
    if tok == ".":
        return error(syn("unexpected ."))
    if tok.starts_with("#"):
        return error(syn("bad token: " + tok))

    r := text_int(tok)

    if r.is_error():
        if r.err() == 2:
            return error(syn("integer out of range"))

        sid := intern(var h, tok)
        return ok(mk_sym(var h, sid))

    n := r.get(0)
    return ok(mk_int(var h, n))

// ---------------------------------------------------------------------------
// Environments
// ---------------------------------------------------------------------------

fn new_frame(var h: Heap, parent: Int) Int:
    h.fparent.append(parent)
    h.fhead.append(NO_ID)
    return h.fparent.length() - 1

fn frame_bind(var h: Heap, f: Int, sid: Int, v: Int) Unit:
    var b = h.fhead[f]

    while b != NO_ID:
        if h.bsym[b] == sid:
            h.bval[b] = v
            return

        b = h.bnext[b]

    h.bsym.append(sid)
    h.bval.append(v)

    head := h.fhead[f]
    h.bnext.append(head)
    h.fhead[f] = h.bsym.length() - 1

fn define_in(var h: Heap, env: Int, sid: Int, v: Int) Unit:
    if env == 0:
        h.gval[sid] = v
    else:
        frame_bind(var h, env, sid, v)

fn lookup(h: Heap, sid: Int, env: Int) Int!Fail:
    var e = env

    while e != 0:
        var b = h.fhead[e]

        while b != NO_ID:
            if h.bsym[b] == sid:
                return ok(h.bval[b])

            b = h.bnext[b]

        e = h.fparent[e]

    g := h.gval[sid]
    if g == NO_ID:
        return error(rt("unbound variable: " + h.symnames[sid]))

    return ok(g)

fn assign(var h: Heap, env: Int, sid: Int, v: Int) Bool:
    var e = env

    while e != 0:
        var b = h.fhead[e]

        while b != NO_ID:
            if h.bsym[b] == sid:
                h.bval[b] = v
                return true

            b = h.bnext[b]

        e = h.fparent[e]

    if h.gval[sid] == NO_ID:
        return false

    h.gval[sid] = v
    return true

// ---------------------------------------------------------------------------
// Closures
// ---------------------------------------------------------------------------

// params: a proper list, a dotted list, or a single symbol; all symbols, no repeats.
fn params_ok(h: Heap, params: Int) Bool:
    var seen = List[Int]()
    var p = params

    while h.tags[p] == T_PAIR:
        s := h.cars[p]
        if h.tags[s] != T_SYM:
            return false

        sid := h.nums[s]
        if in_list(seen, sid):
            return false

        seen.append(sid)
        p = h.cdrs[p]

    if p == V_NIL:
        return true
    if h.tags[p] == T_SYM:
        return not in_list(seen, h.nums[p])

    return false

fn make_closure(var h: Heap, params: Int, body: Int, env: Int, name: Int) Int:
    var b2 = body

    if h.tags[body] == T_PAIR and h.cdrs[body] == V_NIL:
        b2 = h.cars[body]
    else:
        b2 = seq_of(var h, body)

    h.cl_params.append(params)
    h.cl_body.append(b2)
    h.cl_env.append(env)
    h.cl_name.append(name)

    idx := h.cl_params.length() - 1
    return alloc(var h, T_CLOS, idx, 0, 0)

// Creates the frame for a call of closure idx, checking the arity.
fn bind_args(var h: Heap, idx: Int, args: List[Int]) Int!Fail:
    params := h.cl_params[idx]
    cenv := h.cl_env[idx]
    var n = 0
    var p = params

    while h.tags[p] == T_PAIR:
        n += 1
        p = h.cdrs[p]

    rest := (h.tags[p] == T_SYM)
    m := args.length()

    if (rest and m < n) or ((not rest) and m != n):
        var nm = "lambda"
        if h.cl_name[idx] != NO_ID:
            nm = h.symnames[h.cl_name[idx]].clone()

        var e = "{n}"
        if rest:
            e = "at least {n}"
        return error(
            rt(
                "wrong number of arguments to " + nm + ": expected " + e + ", got {m}"
            )
        )

    f := new_frame(var h, cenv)
    p = params

    var i = 0

    while h.tags[p] == T_PAIR:
        sid := h.nums[h.cars[p]]
        frame_bind(var h, f, sid, args[i])
        i += 1
        p = h.cdrs[p]

    if h.tags[p] == T_SYM:
        var lst = V_NIL
        var j = m - 1

        while j >= i:
            lst = cons(var h, args[j], lst)
            j -= 1

        rsid := h.nums[p]
        frame_bind(var h, f, rsid, lst)

    return ok(f)

// ---------------------------------------------------------------------------
// Evaluator
// ---------------------------------------------------------------------------

// Calls f with args from a non-tail position: the body runs in body mode.
fn apply_proc(var h: Heap, f: Int, args: List[Int]) Int!Fail:
    if h.tags[f] == T_PRIM:
        return call_prim(var h, f, args)
    if h.tags[f] != T_CLOS:
        return error(rt("not a procedure: " + show(h, f, true)))

    idx := h.nums[f]
    nenv := try bind_args(var h, idx, args)
    if h.depth >= DEPTH_LIMIT:
        return error(rt("recursion limit exceeded"))

    h.depth += 1

    body := h.cl_body[idx]
    r := eval(var h, body, nenv, true)
    h.depth -= 1
    return r

// Sentinel results of `special`: a tail position (h.tx in h.tenv) or a pending call (h.tproc applied to h.targs).
TAILX := -2
TAILAPP := -3

// in_body: this evaluation is the tail chain of a procedure body that was
// entered already, so tail calls reuse this loop instead of nesting.
fn eval(var h: Heap, x0: Int, env0: Int, in_body: Bool) Int!Fail:
    var x = x0
    var env = env0
    var pending = false
    var proc = V_VOID
    var args = List[Int]()

    while true:
        if pending:
            pending = false
            if not in_body:
                return apply_proc(var h, proc, args)
            if h.tags[proc] == T_PRIM:
                return call_prim(var h, proc, args)
            if h.tags[proc] != T_CLOS:
                return error(rt("not a procedure: " + show(h, proc, true)))

            env = try bind_args(var h, h.nums[proc], args)
            x = h.cl_body[h.nums[proc]]
            continue

        t := h.tags[x]
        if t == T_SYM:
            return lookup(h, h.nums[x], env)
        if x == V_NIL:
            return error(syn("empty application"))
        if t != T_PAIR:
            return ok(x)

        head := h.cars[x]

        if h.tags[head] == T_SYM and h.nums[head] < NSPECIAL:
            r := try special(var h, x, env, h.nums[head])

            if r == TAILX:
                x = h.tx
                env = h.tenv
                continue

            if r == TAILAPP:
                proc = h.tproc
                args = h.targs.clone()
                pending = true
                continue

            return ok(r)

        // ordinary application: operator, then operands left to right
        if list_len(h, x) < 0:
            return error(syn("bad application"))

        proc = try eval(var h, head, env, false)

        var vals = List[Int]()
        var c = h.cdrs[x]

        while c != V_NIL:
            a := h.cars[c]
            v := try eval(var h, a, env, false)
            vals.append(v)
            c = h.cdrs[c]

        args = vals
        pending = true
        continue

fn tail_to(var h: Heap, y: Int, env: Int) Int!Fail:
    h.tx = y
    h.tenv = env
    return ok(TAILX)

fn special(var h: Heap, x: Int, env: Int, sf: Int) Int!Fail:
    if sf == S_QUOTE:
        return sp_quote(h, x)
    if sf == S_IF:
        return sp_if(var h, x, env)
    if sf == S_DEFINE:
        return sp_define(var h, x, env)
    if sf == S_SET:
        return sp_set(var h, x, env)
    if sf == S_LAMBDA:
        return sp_lambda(var h, x, env)
    if sf == S_BEGIN:
        return sp_begin(var h, x, env)
    if sf == S_LET:
        return sp_let(var h, x, env)
    if sf == S_LETSTAR or sf == S_LETREC:
        return sp_letstar(var h, x, env, sf)
    if sf == S_COND:
        return sp_cond(var h, x, env)
    if sf == S_AND or sf == S_OR:
        return sp_andor(var h, x, env, sf)
    if sf == S_WHEN or sf == S_UNLESS:
        return sp_when(var h, x, env, sf)
    if sf == S_TRY:
        return sp_try(var h, x, env)

    return error(bad(h, sf))

fn sp_quote(h: Heap, x: Int) Int!Fail:
    if list_len(h, x) != 2:
        return error(bad(h, S_QUOTE))

    return ok(nth(h, x, 1))

fn sp_if(var h: Heap, x: Int, env: Int) Int!Fail:
    n := list_len(h, x)
    if n != 3 and n != 4:
        return error(bad(h, S_IF))

    tst := nth(h, x, 1)
    tv := try eval(var h, tst, env, false)

    if tv != V_FALSE:
        br := nth(h, x, 2)
        return tail_to(var h, br, env)

    if n == 4:
        alt := nth(h, x, 3)
        return tail_to(var h, alt, env)

    return ok(V_VOID)

fn sp_define(var h: Heap, x: Int, env: Int) Int!Fail:
    n := list_len(h, x)
    if n < 2:
        return error(bad(h, S_DEFINE))

    target := nth(h, x, 1)

    if h.tags[target] == T_PAIR:
        if n < 3:
            return error(bad(h, S_DEFINE))

        nm := h.cars[target]
        if h.tags[nm] != T_SYM:
            return error(bad(h, S_DEFINE))

        sid := h.nums[nm]
        params := h.cdrs[target]
        if not params_ok(h, params):
            return error(bad(h, S_DEFINE))

        body := cdr_n(h, x, 2)
        clo := make_closure(var h, params, body, env, sid)
        define_in(var h, env, sid, clo)
        return ok(V_VOID)

    if h.tags[target] == T_SYM:
        if n != 3:
            return error(bad(h, S_DEFINE))

        sid := h.nums[target]
        vexpr := nth(h, x, 2)
        v := try eval(var h, vexpr, env, false)
        if (
            h.tags[vexpr] == T_PAIR
            and h.tags[h.cars[vexpr]] == T_SYM
            and h.nums[h.cars[vexpr]] == S_LAMBDA
            and h.tags[v] == T_CLOS
        ):
            h.cl_name[h.nums[v]] = sid
        define_in(var h, env, sid, v)
        return ok(V_VOID)

    return error(bad(h, S_DEFINE))

fn sp_set(var h: Heap, x: Int, env: Int) Int!Fail:
    if list_len(h, x) != 3:
        return error(bad(h, S_SET))

    target := nth(h, x, 1)
    if h.tags[target] != T_SYM:
        return error(bad(h, S_SET))

    sid := h.nums[target]
    vexpr := nth(h, x, 2)
    v := try eval(var h, vexpr, env, false)
    if not assign(var h, env, sid, v):
        return error(rt("unbound variable: " + h.symnames[sid]))

    return ok(V_VOID)

fn sp_lambda(var h: Heap, x: Int, env: Int) Int!Fail:
    if list_len(h, x) < 3:
        return error(bad(h, S_LAMBDA))

    params := nth(h, x, 1)
    if not params_ok(h, params):
        return error(bad(h, S_LAMBDA))

    body := cdr_n(h, x, 2)
    return ok(make_closure(var h, params, body, env, NO_ID))

fn sp_begin(var h: Heap, x: Int, env: Int) Int!Fail:
    var b = h.cdrs[x]
    if b == V_NIL:
        return ok(V_VOID)

    while true:
        nxt := h.cdrs[b]
        if nxt == V_NIL:
            break

        e := h.cars[b]
        _r := try eval(var h, e, env, false)
        b = nxt

    last := h.cars[b]
    return tail_to(var h, last, env)

fn sp_let(var h: Heap, x: Int, env: Int) Int!Fail:
    n := list_len(h, x)
    if n < 3:
        return error(bad(h, S_LET))
    if h.tags[nth(h, x, 1)] == T_SYM:
        return sp_namedlet(var h, x, env)

    return sp_plainlet(var h, x, env)

fn sp_namedlet(var h: Heap, x: Int, env: Int) Int!Fail:
    // named let: a call of a loop procedure bound in a frame around the body
    if list_len(h, x) < 4:
        return error(bad(h, S_LET))

    loop_sid := h.nums[nth(h, x, 1)]
    var names = List[Int]()
    var exprs = List[Int]()
    bindings := nth(h, x, 2)
    if not parse_bindings(h, bindings, var names, var exprs):
        return error(bad(h, S_LET))

    body := cdr_n(h, x, 3)
    vals := try eval_all(var h, exprs, env)
    f1 := new_frame(var h, env)
    names_list := build_list(var h, names)
    clo := make_closure(var h, names_list, body, f1, loop_sid)
    frame_bind(var h, f1, loop_sid, clo)
    h.tproc = clo
    h.targs = vals
    return ok(TAILAPP)

fn sp_plainlet(var h: Heap, x: Int, env: Int) Int!Fail:
    var names2 = List[Int]()
    var exprs2 = List[Int]()
    bindings := nth(h, x, 1)
    if not parse_bindings(h, bindings, var names2, var exprs2):
        return error(bad(h, S_LET))

    vals2 := try eval_all(var h, exprs2, env)
    f2 := new_frame(var h, env)
    bind_names(var h, f2, names2, vals2)

    body2 := cdr_n(h, x, 2)
    seq2 := seq_of(var h, body2)
    return tail_to(var h, seq2, f2)

// Evaluates each expression in env, left to right.
fn eval_all(var h: Heap, exprs: List[Int], env: Int) List[Int]!Fail:
    var vals = List[Int]()

    for k in 0..exprs.length():
        ev := try eval(var h, exprs[k], env, false)
        vals.append(ev)

    return ok(vals)

// Binds names[k] to vals[k] in frame f.
fn bind_names(var h: Heap, f: Int, names: List[Int], vals: List[Int]) Unit:
    for k in 0..names.length():
        bsid := h.nums[names[k]]
        frame_bind(var h, f, bsid, vals[k])

fn sp_letstar(var h: Heap, x: Int, env: Int, sf: Int) Int!Fail:
    if list_len(h, x) < 3:
        return error(bad(h, sf))

    var names3 = List[Int]()
    var exprs3 = List[Int]()
    bindings := nth(h, x, 1)
    if not parse_bindings(h, bindings, var names3, var exprs3):
        return error(bad(h, sf))

    f3 := new_frame(var h, env)

    for k in 0..names3.length():
        ev := try eval(var h, exprs3[k], f3, false)
        bsid := h.nums[names3[k]]
        frame_bind(var h, f3, bsid, ev)

    body3 := cdr_n(h, x, 2)
    seq3 := seq_of(var h, body3)
    return tail_to(var h, seq3, f3)

fn sp_cond(var h: Heap, x: Int, env: Int) Int!Fail:
    var c = h.cdrs[x]

    while c != V_NIL:
        clause := h.cars[c]
        if h.tags[clause] != T_PAIR:
            return error(bad(h, S_COND))

        cl_n := list_len(h, clause)
        if cl_n < 1:
            return error(bad(h, S_COND))

        rest_c := h.cdrs[c]
        hd := h.cars[clause]
        cbody := h.cdrs[clause]

        if h.tags[hd] == T_SYM and h.nums[hd] == S_ELSE:
            if rest_c != V_NIL or cl_n < 2:
                return error(bad(h, S_COND))

            seq_e := seq_of(var h, cbody)
            return tail_to(var h, seq_e, env)

        tv := try eval(var h, hd, env, false)

        if tv != V_FALSE:
            if cl_n == 1:
                return ok(tv)

            seq_t := seq_of(var h, cbody)
            return tail_to(var h, seq_t, env)

        c = rest_c

    return ok(V_VOID)

fn sp_andor(var h: Heap, x: Int, env: Int, sf: Int) Int!Fail:
    n := list_len(h, x)
    if n < 1:
        return error(bad(h, sf))

    if n == 1:
        if sf == S_AND:
            return ok(V_TRUE)

        return ok(V_FALSE)

    var c = h.cdrs[x]

    while true:
        nxt := h.cdrs[c]
        if nxt == V_NIL:
            break

        e := h.cars[c]
        v := try eval(var h, e, env, false)
        if sf == S_AND and v == V_FALSE:
            return ok(v)
        if sf == S_OR and v != V_FALSE:
            return ok(v)

        c = nxt

    last := h.cars[c]
    return tail_to(var h, last, env)

fn sp_when(var h: Heap, x: Int, env: Int, sf: Int) Int!Fail:
    if list_len(h, x) < 3:
        return error(bad(h, sf))

    tst := nth(h, x, 1)
    tv := try eval(var h, tst, env, false)
    var fire = (tv != V_FALSE)
    if sf == S_UNLESS:
        fire = not fire

    if fire:
        body := cdr_n(h, x, 2)
        seq := seq_of(var h, body)
        return tail_to(var h, seq, env)

    return ok(V_VOID)

fn sp_try(var h: Heap, x: Int, env: Int) Int!Fail:
    if list_len(h, x) != 3:
        return error(bad(h, S_TRY))

    body := nth(h, x, 1)
    handler := nth(h, x, 2)
    r := eval(var h, body, env, false)
    if not r.is_error():
        return r

    fl := r.err()
    if fl.syntax:
        return error(fl)

    hv := try eval(var h, handler, env, false)
    msg := mk_str(var h, fl.msg)
    return apply_proc(var h, hv, [msg])

// Collects (name init) pairs into parallel lists of symbol values and expressions.
fn parse_bindings(
    h: Heap,
    bindings: Int,
    var names: List[Int],
    var exprs: List[Int]
) Bool:
    if list_len(h, bindings) < 0:
        return false

    var c = bindings

    while h.tags[c] == T_PAIR:
        b := h.cars[c]
        if list_len(h, b) != 2:
            return false

        nm := h.cars[b]
        if h.tags[nm] != T_SYM:
            return false

        names.append(nm)
        exprs.append(nth(h, b, 1))
        c = h.cdrs[c]

    return true

// ---------------------------------------------------------------------------
// Builtins
// ---------------------------------------------------------------------------

fn call_prim(var h: Heap, f: Int, args: List[Int]) Int!Fail:
    pi := h.nums[f]
    m := args.length()
    if m < h.plo[pi] or (h.phi[pi] >= 0 and m > h.phi[pi]):
        return prim_arity_error(var h, pi, m)

    g := h.pgroup[pi]
    if g == 1:
        return prim_num(var h, h.pname[pi].clone(), args)
    if g == 2:
        return prim_list(var h, h.pname[pi].clone(), args)
    if g == 3:
        return prim_hof(var h, h.pname[pi].clone(), args)
    if g == 4:
        return prim_str(var h, h.pname[pi].clone(), args)

    return prim_misc(var h, h.pname[pi].clone(), args)

fn prim_arity_error(var h: Heap, pi: Int, m: Int) Int!Fail:
    return error(rt(arity_msg(h.pname[pi].clone(), h.plo[pi], h.phi[pi], m)))

fn prim_num(var h: Heap, name: String, args: List[Int]) Int!Fail:
    if name == "+":
        ns := try ints_of(h, name, args)
        var acc = 0

        for i in 0..ns.length():
            s := try add_int(acc, ns[i])
            acc = s

        return ok(mk_int(var h, acc))

    if name == "-":
        ns := try ints_of(h, name, args)

        if ns.length() == 1:
            if ns[0] == MINI:
                return error(rt("integer overflow"))

            return ok(mk_int(var h, -ns[0]))

        var acc = ns[0]

        for i in 1..ns.length():
            s := try sub_int(acc, ns[i])
            acc = s

        return ok(mk_int(var h, acc))

    if name == "*":
        ns := try ints_of(h, name, args)
        var acc = 1

        for i in 0..ns.length():
            s := try mul_int(acc, ns[i])
            acc = s

        return ok(mk_int(var h, acc))

    if name == "quotient" or name == "remainder" or name == "modulo":
        ns := try ints_of(h, name, args)
        a := ns[0]
        b := ns[1]
        if b == 0:
            return error(rt("division by zero"))

        if name == "quotient":
            if b == -1:
                if a == MINI:
                    return error(rt("integer overflow"))

                return ok(mk_int(var h, -a))

            return ok(mk_int(var h, a / b))

        var r = 0
        if b != -1:
            r = a % b
        if name == "modulo":
            if r != 0 and ((r < 0) != (b < 0)):
                r = r + b
        return ok(mk_int(var h, r))

    if name == "abs":
        ns := try ints_of(h, name, args)
        a := ns[0]
        if a == MINI:
            return error(rt("integer overflow"))
        if a < 0:
            return ok(mk_int(var h, -a))

        return ok(mk_int(var h, a))

    if name == "min" or name == "max":
        ns := try ints_of(h, name, args)
        var best = ns[0]

        for i in 1..ns.length():
            v := ns[i]
            if name == "min" and v < best:
                best = v
            if name == "max" and v > best:
                best = v

        return ok(mk_int(var h, best))

    if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
        ns := try ints_of(h, name, args)
        var all_ok = true
        for i in 0..ns.length() - 1:
            if not cmp_ok(name, ns[i], ns[i + 1]):
                all_ok = false
        return ok(bool_val(all_ok))

    if name == "zero?":
        ns := try ints_of(h, name, args)
        return ok(bool_val(ns[0] == 0))

    if name == "even?":
        ns := try ints_of(h, name, args)
        return ok(bool_val(ns[0] % 2 == 0))

    if name == "odd?":
        ns := try ints_of(h, name, args)
        return ok(bool_val(ns[0] % 2 != 0))

    return error(rt("internal: unknown builtin " + name))

fn prim_list(var h: Heap, name: String, args: List[Int]) Int!Fail:
    a0 := arg(args, 0)
    a1 := arg(args, 1)
    if name == "not":
        return ok(bool_val(a0 == V_FALSE))
    if name == "null?":
        return ok(bool_val(a0 == V_NIL))
    if name == "pair?":
        return ok(bool_val(h.tags[a0] == T_PAIR))
    if name == "list?":
        return ok(bool_val(list_len(h, a0) >= 0))
    if name == "number?":
        return ok(bool_val(h.tags[a0] == T_INT))
    if name == "string?":
        return ok(bool_val(h.tags[a0] == T_STR))
    if name == "symbol?":
        return ok(bool_val(h.tags[a0] == T_SYM))
    if name == "boolean?":
        return ok(bool_val(h.tags[a0] == T_BOOL))
    if name == "procedure?":
        return ok(bool_val(is_proc(h, a0)))
    if name == "eq?":
        return ok(bool_val(is_eqv(h, a0, a1)))
    if name == "equal?":
        return ok(bool_val(is_equal(h, a0, a1)))
    if name == "cons":
        return ok(cons(var h, a0, a1))

    if name == "car" or name == "cdr":
        if h.tags[a0] != T_PAIR:
            return error(type_err(h, name, "pair", a0))
        if name == "car":
            return ok(h.cars[a0])

        return ok(h.cdrs[a0])

    if name == "cadr":
        return cxr(h, name, a0, "ad")
    if name == "cddr":
        return cxr(h, name, a0, "dd")
    if name == "caddr":
        return cxr(h, name, a0, "add")

    if name == "set-car!" or name == "set-cdr!":
        if h.tags[a0] != T_PAIR:
            return error(type_err(h, name, "pair", a0))

        if name == "set-car!":
            h.cars[a0] = a1
        else:
            h.cdrs[a0] = a1

        return ok(V_VOID)

    if name == "list":
        return ok(build_list(var h, args))

    if name == "length":
        n := list_len(h, a0)
        if n < 0:
            return error(type_err(h, name, "list", a0))

        return ok(mk_int(var h, n))

    if name == "append":
        m := args.length()
        if m == 0:
            return ok(V_NIL)

        var i = 0

        while i < m - 1:
            if list_len(h, args[i]) < 0:
                return error(type_err(h, name, "list", args[i]))

            i += 1

        var res = args[m - 1]
        var j = m - 2

        while j >= 0:
            elts := elements(h, args[j])
            res = build_onto(var h, elts, res)
            j -= 1

        return ok(res)

    if name == "reverse":
        if list_len(h, a0) < 0:
            return error(type_err(h, name, "list", a0))

        elts := elements(h, a0)
        var res = V_NIL

        for i in 0..elts.length():
            e := elts[i]
            res = cons(var h, e, res)

        return ok(res)

    if name == "list-ref" or name == "list-tail":
        if h.tags[a0] != T_PAIR and a0 != V_NIL:
            return error(type_err(h, name, "list", a0))

        k := try int_val(h, name, a1)
        if k < 0:
            return error(rt(name + ": index out of range"))

        var p = a0
        var i = 0

        while i < k:
            if h.tags[p] != T_PAIR:
                return error(rt(name + ": index out of range"))

            p = h.cdrs[p]
            i += 1

        if name == "list-tail":
            return ok(p)
        if h.tags[p] != T_PAIR:
            return error(rt(name + ": index out of range"))

        return ok(h.cars[p])

    if name == "range":
        a := try int_val(h, name, a0)
        b := try int_val(h, name, a1)
        if a >= b:
            return ok(V_NIL)

        var res = V_NIL
        var i = b - 1

        while i >= a:
            iv := mk_int(var h, i)
            res = cons(var h, iv, res)
            i -= 1

        return ok(res)

    if name == "assoc" or name == "member":
        if h.tags[a1] != T_PAIR and a1 != V_NIL:
            return error(type_err(h, name, "list", a1))

        var p = a1

        while h.tags[p] == T_PAIR:
            e := h.cars[p]

            if name == "member":
                if is_equal(h, a0, e):
                    return ok(p)
            else:
                if h.tags[e] != T_PAIR:
                    return error(type_err(h, name, "pair", e))
                if is_equal(h, a0, h.cars[e]):
                    return ok(e)

            p = h.cdrs[p]

        if p != V_NIL:
            return error(type_err(h, name, "list", a1))

        return ok(V_FALSE)

    return error(rt("internal: unknown builtin " + name))

fn cxr(h: Heap, name: String, v: Int, path: String) Int!Fail:
    var cur = v
    var i = path.length() - 1

    while i >= 0:
        if h.tags[cur] != T_PAIR:
            return error(type_err(h, name, "pair", cur))

        step := path.get(i)

        if step == "a":
            cur = h.cars[cur]
        else:
            cur = h.cdrs[cur]

        i -= 1

    return ok(cur)

fn prim_hof(var h: Heap, name: String, args: List[Int]) Int!Fail:
    if (name == "map" or name == "for-each") and args.length() == 2:
        return hof_map1(var h, name, args)
    if name == "map" or name == "for-each":
        return hof_map(var h, name, args)
    if name == "filter":
        return hof_filter(var h, args)
    if name == "fold" or name == "foldr":
        return hof_fold(var h, name, args)
    if name == "apply":
        return hof_apply(var h, args)
    if name == "sort":
        return hof_sort(var h, args)

    return error(rt("internal: unknown builtin " + name))

// map / for-each over one list: a small frame, since recursion through it is common.
fn hof_map1(var h: Heap, name: String, args: List[Int]) Int!Fail:
    f := arg(args, 0)
    if not is_proc(h, f):
        return error(type_err(h, name, "procedure", f))

    lst := arg(args, 1)
    if list_len(h, lst) < 0:
        return error(type_err(h, name, "list", lst))

    var res = List[Int]()
    var p = lst

    while h.tags[p] == T_PAIR:
        ca := h.cars[p]
        r := try apply_proc(var h, f, [ca])
        res.append(r)
        p = h.cdrs[p]

    if name == "for-each":
        return ok(V_VOID)

    return ok(build_list(var h, res))

fn hof_map(var h: Heap, name: String, args: List[Int]) Int!Fail:
    f := arg(args, 0)
    if not is_proc(h, f):
        return error(type_err(h, name, "procedure", f))

    var curs = List[Int]()
    var i = 1

    while i < args.length():
        if list_len(h, args[i]) < 0:
            return error(type_err(h, name, "list", args[i]))

        curs.append(args[i])
        i += 1

    var res = List[Int]()
    var stop = false

    while not stop:
        var cargs = List[Int]()
        var k = 0

        while k < curs.length():
            p := curs[k]

            if h.tags[p] != T_PAIR:
                stop = true
            else:
                cargs.append(h.cars[p])
                curs[k] = h.cdrs[p]

            k += 1

        if stop:
            break

        r := try apply_proc(var h, f, cargs)
        res.append(r)

    if name == "for-each":
        return ok(V_VOID)

    return ok(build_list(var h, res))

fn hof_filter(var h: Heap, args: List[Int]) Int!Fail:
    f := arg(args, 0)
    if not is_proc(h, f):
        return error(type_err(h, "filter", "procedure", f))

    lst := arg(args, 1)
    if list_len(h, lst) < 0:
        return error(type_err(h, "filter", "list", lst))

    elts := elements(h, lst)
    var res = List[Int]()

    for i in 0..elts.length():
        keep := try apply_proc(var h, f, [elts[i]])
        if keep != V_FALSE:
            res.append(elts[i])

    return ok(build_list(var h, res))

fn hof_fold(var h: Heap, name: String, args: List[Int]) Int!Fail:
    f := arg(args, 0)
    if not is_proc(h, f):
        return error(type_err(h, name, "procedure", f))

    lst := arg(args, 2)
    if list_len(h, lst) < 0:
        return error(type_err(h, name, "list", lst))

    elts := elements(h, lst)
    var acc = arg(args, 1)

    if name == "fold":
        for i in 0..elts.length():
            na := try apply_proc(var h, f, [acc, elts[i]])
            acc = na
    else:
        var i = elts.length() - 1

        while i >= 0:
            na := try apply_proc(var h, f, [elts[i], acc])
            acc = na
            i -= 1

    return ok(acc)

fn hof_apply(var h: Heap, args: List[Int]) Int!Fail:
    f := arg(args, 0)
    if not is_proc(h, f):
        return error(type_err(h, "apply", "procedure", f))

    m := args.length()
    last := args[m - 1]
    if list_len(h, last) < 0:
        return error(type_err(h, "apply", "list", last))

    var cargs = List[Int]()
    var i = 1

    while i < m - 1:
        cargs.append(args[i])
        i += 1

    tl := elements(h, last)
    for j in 0..tl.length():
        cargs.append(tl[j])
    return apply_proc(var h, f, cargs)

fn hof_sort(var h: Heap, args: List[Int]) Int!Fail:
    less := arg(args, 1)
    if not is_proc(h, less):
        return error(type_err(h, "sort", "procedure", less))

    src := arg(args, 0)
    if list_len(h, src) < 0:
        return error(type_err(h, "sort", "list", src))

    var a = elements(h, src)
    n := a.length()
    var width = 1

    while width < n:
        var b = List[Int]()
        var lo = 0

        while lo < n:
            mid := if lo + width < n: lo + width else: n
            hi := if lo + 2 * width < n: lo + 2 * width else: n
            var p = lo
            var q = mid

            while p < mid and q < hi:
                r := try apply_proc(var h, less, [a[q], a[p]])

                if r != V_FALSE:
                    b.append(a[q])
                    q += 1
                else:
                    b.append(a[p])
                    p += 1

            while p < mid:
                b.append(a[p])
                p += 1

            while q < hi:
                b.append(a[q])
                q += 1

            lo = lo + 2 * width

        a = b
        width = width * 2

    return ok(build_list(var h, a))

fn prim_str(var h: Heap, name: String, args: List[Int]) Int!Fail:
    a0 := arg(args, 0)
    a1 := arg(args, 1)

    if name == "string-length":
        s := try str_of(h, name, a0)
        return ok(mk_int(var h, s.length()))

    if name == "string-append":
        var sb = StringBuilder()

        for i in 0..args.length():
            s := try str_of(h, name, args[i])
            sb.append(s)

        return ok(mk_str(var h, sb.build()))

    if name == "substring":
        s := try str_of(h, name, a0)
        st := try int_val(h, name, a1)
        en := try int_val(h, name, arg(args, 2))
        n := s.length()
        if st < 0 or en < st or en > n:
            return error(rt("substring: index out of range"))

        sub := s.slice(st, en).get("")
        return ok(mk_str(var h, sub))

    if name == "string-ref":
        s := try str_of(h, name, a0)
        k := try int_val(h, name, a1)
        if k < 0 or k >= s.length():
            return error(rt("string-ref: index out of range"))

        ch := s.get(k)
        return ok(mk_str(var h, ch))

    if name == "string=?" or name == "string<?":
        a := try str_of(h, name, a0)
        b := try str_of(h, name, a1)
        if name == "string=?":
            return ok(bool_val(a == b))

        return ok(bool_val(a < b))

    if name == "string-upcase" or name == "string-downcase":
        s := try str_of(h, name, a0)
        if name == "string-upcase":
            return ok(mk_str(var h, s.upper()))

        return ok(mk_str(var h, s.lower()))

    if name == "string->number":
        s := try str_of(h, name, a0)
        r := text_int(s)
        if r.is_error():
            return ok(V_FALSE)

        n := r.get(0)
        return ok(mk_int(var h, n))

    if name == "number->string":
        n := try int_val(h, name, a0)
        txt := "{n}"
        return ok(mk_str(var h, txt))

    if name == "string->symbol":
        s := try str_of(h, name, a0)
        sid := intern(var h, s)
        return ok(mk_sym(var h, sid))

    if name == "symbol->string":
        if h.tags[a0] != T_SYM:
            return error(type_err(h, name, "symbol", a0))

        nm := h.symnames[h.nums[a0]].clone()
        return ok(mk_str(var h, nm))

    if name == "string->list":
        s := try str_of(h, name, a0)
        cs := s.chars()
        var items = List[Int]()

        for i in 0..cs.length():
            sv := mk_str(var h, cs[i].clone())
            items.append(sv)

        return ok(build_list(var h, items))

    if name == "list->string":
        if list_len(h, a0) < 0:
            return error(type_err(h, name, "list", a0))

        elts := elements(h, a0)
        var sb = StringBuilder()

        for i in 0..elts.length():
            s := try str_of(h, name, elts[i])
            sb.append(s)

        return ok(mk_str(var h, sb.build()))

    if name == "string-join":
        if list_len(h, a0) < 0:
            return error(type_err(h, name, "list", a0))

        sep := try str_of(h, name, a1)
        elts := elements(h, a0)
        var sb = StringBuilder()

        for i in 0..elts.length():
            if i > 0:
                sb.append(sep)

            s := try str_of(h, name, elts[i])
            sb.append(s)

        return ok(mk_str(var h, sb.build()))

    if name == "string-split":
        s := try str_of(h, name, a0)
        sep := try str_of(h, name, a1)
        if sep.length() != 1:
            return error(rt("string-split: separator must be one character"))

        parts := s.split(sep)
        var items = List[Int]()

        for i in 0..parts.length():
            pv := mk_str(var h, parts[i].clone())
            items.append(pv)

        return ok(build_list(var h, items))

    if name == "string-contains?":
        s := try str_of(h, name, a0)
        sub := try str_of(h, name, a1)
        return ok(bool_val(s.contains(sub)))

    return error(rt("internal: unknown builtin " + name))

fn prim_misc(var h: Heap, name: String, args: List[Int]) Int!Fail:
    a0 := arg(args, 0)

    if name == "display":
        txt := show(h, a0, false)
        emit(var h, txt)
        return ok(V_VOID)

    if name == "write":
        txt := show(h, a0, true)
        emit(var h, txt)
        return ok(V_VOID)

    if name == "newline":
        emit(var h, "\n")
        return ok(V_VOID)

    if name == "void":
        return ok(V_VOID)

    if name == "error":
        if h.tags[a0] != T_STR:
            return error(type_err(h, name, "string", a0))

        var sb = StringBuilder()
        sb.append(h.strs[h.nums[a0]])

        for i in 1..args.length():
            sb.append(" ")
            sb.append(show(h, args[i], true))

        return error(rt(sb.build()))

    return error(rt("internal: unknown builtin " + name))

fn reg(var h: Heap, name: String, lo: Int, hi: Int, group: Int) Unit:
    sid := intern(var h, name.clone())
    pi := h.pname.length()
    h.pname.append(name)
    h.plo.append(lo)
    h.phi.append(hi)
    h.pgroup.append(group)

    pv := alloc(var h, T_PRIM, pi, 0, 0)
    h.gval[sid] = pv

fn new_heap() Heap:
    var h = Heap(
        tags: [], nums: [], cars: [], cdrs: [], strs: [], syms: Map[String, Int](),
        symnames: [], gval: [], cl_params: [], cl_body: [], cl_env: [], cl_name: [],
        fparent: [], fhead: [], bsym: [], bval: [], bnext: [], pname: [], plo: [],
        phi: [], pgroup: [], depth: 0, out: StringBuilder(), nonempty: false,
        lastnl: false, chars: [], pos: 0, v_begin: 0, tx: 0, tenv: 0, tproc: 0,
        targs: []
    )
    _v0 := alloc(var h, T_VOID, 0, 0, 0)
    _v1 := alloc(var h, T_BOOL, 0, 0, 0)
    _v2 := alloc(var h, T_BOOL, 1, 0, 0)
    _v3 := alloc(var h, T_NIL, 0, 0, 0)
    h.fparent.append(-1)
    h.fhead.append(NO_ID)

    specials := [
        "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec",
        "cond", "and", "or", "when", "unless", "try", "else"
    ]
    for i in 0..specials.length():
        _s := intern(var h, specials[i].clone())

    bv := mk_sym(var h, S_BEGIN)
    h.v_begin = bv
    reg(var h, "+", 0, -1, 1)
    reg(var h, "-", 1, -1, 1)
    reg(var h, "*", 0, -1, 1)
    reg(var h, "quotient", 2, 2, 1)
    reg(var h, "remainder", 2, 2, 1)
    reg(var h, "modulo", 2, 2, 1)
    reg(var h, "abs", 1, 1, 1)
    reg(var h, "min", 1, -1, 1)
    reg(var h, "max", 1, -1, 1)
    reg(var h, "=", 2, -1, 1)
    reg(var h, "<", 2, -1, 1)
    reg(var h, ">", 2, -1, 1)
    reg(var h, "<=", 2, -1, 1)
    reg(var h, ">=", 2, -1, 1)
    reg(var h, "zero?", 1, 1, 1)
    reg(var h, "even?", 1, 1, 1)
    reg(var h, "odd?", 1, 1, 1)
    reg(var h, "not", 1, 1, 2)
    reg(var h, "null?", 1, 1, 2)
    reg(var h, "pair?", 1, 1, 2)
    reg(var h, "list?", 1, 1, 2)
    reg(var h, "number?", 1, 1, 2)
    reg(var h, "string?", 1, 1, 2)
    reg(var h, "symbol?", 1, 1, 2)
    reg(var h, "boolean?", 1, 1, 2)
    reg(var h, "procedure?", 1, 1, 2)
    reg(var h, "eq?", 2, 2, 2)
    reg(var h, "equal?", 2, 2, 2)
    reg(var h, "cons", 2, 2, 2)
    reg(var h, "car", 1, 1, 2)
    reg(var h, "cdr", 1, 1, 2)
    reg(var h, "cadr", 1, 1, 2)
    reg(var h, "cddr", 1, 1, 2)
    reg(var h, "caddr", 1, 1, 2)
    reg(var h, "set-car!", 2, 2, 2)
    reg(var h, "set-cdr!", 2, 2, 2)
    reg(var h, "list", 0, -1, 2)
    reg(var h, "length", 1, 1, 2)
    reg(var h, "append", 0, -1, 2)
    reg(var h, "reverse", 1, 1, 2)
    reg(var h, "list-ref", 2, 2, 2)
    reg(var h, "list-tail", 2, 2, 2)
    reg(var h, "range", 2, 2, 2)
    reg(var h, "assoc", 2, 2, 2)
    reg(var h, "member", 2, 2, 2)
    reg(var h, "map", 2, -1, 3)
    reg(var h, "for-each", 2, -1, 3)
    reg(var h, "filter", 2, 2, 3)
    reg(var h, "fold", 3, 3, 3)
    reg(var h, "foldr", 3, 3, 3)
    reg(var h, "apply", 2, -1, 3)
    reg(var h, "sort", 2, 2, 3)
    reg(var h, "string-length", 1, 1, 4)
    reg(var h, "string-append", 0, -1, 4)
    reg(var h, "substring", 3, 3, 4)
    reg(var h, "string-ref", 2, 2, 4)
    reg(var h, "string=?", 2, 2, 4)
    reg(var h, "string<?", 2, 2, 4)
    reg(var h, "string-upcase", 1, 1, 4)
    reg(var h, "string-downcase", 1, 1, 4)
    reg(var h, "string->number", 1, 1, 4)
    reg(var h, "number->string", 1, 1, 4)
    reg(var h, "string->symbol", 1, 1, 4)
    reg(var h, "symbol->string", 1, 1, 4)
    reg(var h, "string->list", 1, 1, 4)
    reg(var h, "list->string", 1, 1, 4)
    reg(var h, "string-join", 2, 2, 4)
    reg(var h, "string-split", 2, 2, 4)
    reg(var h, "string-contains?", 2, 2, 4)
    reg(var h, "display", 1, 1, 5)
    reg(var h, "write", 1, 1, 5)
    reg(var h, "newline", 0, 0, 5)
    reg(var h, "void", 0, 0, 5)
    reg(var h, "error", 1, -1, 5)
    return h

fn report(var h: Heap, f: Fail) Unit:
    if h.nonempty and not h.lastnl:
        emit(var h, "\n")
    emit(var h, "error: " + f.msg + "\n")

fn main_loop(var h: Heap) Unit:
    while true:
        skip_ws(var h)
        if at_end(h):
            return

        rd := read_datum(var h)

        if rd.is_error():
            report(var h, rd.err())
            return

        d := rd.get(V_VOID)
        ev := eval(var h, d, 0, false)

        if ev.is_error():
            report(var h, ev.err())
            return

        flush(var h)

export fn main() Int:
    var h = new_heap()
    raw := read_all(stdin()).get()
    text := raw.decode_utf8().get("")
    h.chars = text.chars()
    h.pos = 0
    main_loop(var h)
    flush(var h)
    return 0
