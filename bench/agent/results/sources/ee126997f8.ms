import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import values, Bytes from "@std/bytes.ms"

// ---------- core data ----------

type Fail:
    msg: String
    syntax: Bool

enum Val:
    Num(n: Int)
    Bo(b: Bool)
    Str(s: String)
    Sym(name: String)
    Nil
    Void
    Pair(id: Int)
    Prim(id: Int)
    Clo(id: Int)

type Frame:
    names: List[String]
    vals: List[Val]
    parent: Int

type Lam:
    params: List[String]
    rest: String
    has_rest: Bool
    body: List[Val]
    env: Int
    name: String

type PrimSpec:
    name: String
    lo: Int
    hi: Int

type Step:
    finished: Bool
    result: Val
    next: Val
    nenv: Int

type Binds:
    names: List[String]
    inits: List[Val]

type Heap:
    cars: List[Val]
    cdrs: List[Val]
    frames: List[Frame]
    globals: Map[String, Val]
    lams: List[Lam]
    specs: List[PrimSpec]
    bs: List[UInt8]
    data: Bytes
    pos: Int
    any_out: Bool
    last_nl: Bool

fn rterr(msg: String) Fail:
    return Fail(msg: msg, syntax: false)

fn syn(msg: String) Fail:
    return Fail(msg: msg, syntax: true)

fn bad_form(kw: String) Fail:
    return syn("syntax error: bad form: " + kw)

fn kind_err(name: String, kind: String, h: Heap, v: Val) Fail:
    return rterr(name + ": expected " + kind + ", got " + show(h, v, true))

fn done_step(v: Val) Step:
    return Step(finished: true, result: v, next: Val.Void, nenv: 0)

fn cont_step(e: Val, env: Int) Step:
    return Step(finished: false, result: Val.Void, next: e, nenv: env)

fn is_true(v: Val) Bool:
    match v:
        Bo(b):
            return b
        _:
            return true

fn is_proc(v: Val) Bool:
    match v:
        Clo(_id):
            return true
        Prim(_id):
            return true
        _:
            return false

fn pair_id(v: Val) Int:
    match v:
        Pair(id):
            return id
        _:
            return -1

fn prim_id(v: Val) Int:
    match v:
        Prim(id):
            return id
        _:
            return -1

fn clo_id(v: Val) Int:
    match v:
        Clo(id):
            return id
        _:
            return -1

fn sym_name(v: Val) String:
    match v:
        Sym(name):
            return name.clone()
        _:
            return ""

fn is_nil(v: Val) Bool:
    match v:
        Nil:
            return true
        _:
            return false

fn is_str(v: Val) Bool:
    match v:
        Str(_s):
            return true
        _:
            return false

fn str_of(v: Val) String:
    match v:
        Str(s):
            return s.clone()
        _:
            return ""

fn num_of(v: Val) Int:
    match v:
        Num(n):
            return n
        _:
            return 0

fn is_num(v: Val) Bool:
    match v:
        Num(_n):
            return true
        _:
            return false

fn bool_of(v: Val) Bool:
    match v:
        Bo(b):
            return b
        _:
            return true

fn is_bool(v: Val) Bool:
    match v:
        Bo(_b):
            return true
        _:
            return false

fn cons(var h: Heap, a: Val, b: Val) Val:
    h.cars.append(a.clone())
    h.cdrs.append(b.clone())
    return Val.Pair(id: h.cars.length() - 1)

fn vec_to_list(var h: Heap, items: List[Val]) Val:
    var res = Val.Nil
    var i = items.length() - 1

    while i >= 0:
        res = cons(var h, items[i].clone(), res.clone())
        i -= 1

    return res

fn proper_list(h: Heap, v: Val) Bool:
    var cur = v.clone()

    while true:
        let p = pair_id(cur)
        if p < 0:
            return is_nil(cur)

        cur = h.cdrs[p].clone()

    return false

fn items_of(h: Heap, v: Val) List[Val]:
    var out = List[Val]()
    var p = pair_id(v)

    while p >= 0:
        out.append(h.cars[p].clone())
        p = pair_id(h.cdrs[p])

    return out

fn body_slice(items: List[Val], start: Int) List[Val]:
    var out = List[Val]()
    var i = start

    while i < items.length():
        out.append(items[i].clone())
        i += 1

    return out

fn eq_val(a: Val, b: Val) Bool:
    if is_num(a) and is_num(b):
        return num_of(a) == num_of(b)
    if is_bool(a) and is_bool(b):
        return bool_of(a) == bool_of(b)
    if sym_name(a) != "" and sym_name(b) != "":
        return sym_name(a) == sym_name(b)
    if is_nil(a) and is_nil(b):
        return true

    return false

fn equal_val(h: Heap, a: Val, b: Val) Bool:
    let pa = pair_id(a)
    let pb = pair_id(b)

    if pa >= 0 and pb >= 0:
        if not equal_val(h, h.cars[pa].clone(), h.cars[pb].clone()):
            return false

        return equal_val(h, h.cdrs[pa].clone(), h.cdrs[pb].clone())

    if pa >= 0 or pb >= 0:
        return false
    if is_str(a) and is_str(b):
        return str_of(a) == str_of(b)

    let ca = clo_id(a)
    let cb = clo_id(b)
    if ca >= 0 or cb >= 0:
        return ca == cb

    match a:
        Prim(x):
            return prim_id(b) == x
        _:
            return eq_val(a, b)

fn quote_str(s: String) String:
    var out = "\""
    var i = 0

    while i < s.length():
        let c = s.get(i, "")

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

        i += 1

    return out + "\""

fn show_pair(h: Heap, id: Int, w: Bool) String:
    var out = "("
    var p = id
    var first = true

    while true:
        if not first:
            out = out + " "
        first = false
        out = out + show(h, h.cars[p].clone(), w)

        let q = pair_id(h.cdrs[p])

        if q >= 0:
            p = q
        else:
            let tail = h.cdrs[p].clone()
            if not is_nil(tail):
                out = out + " . " + show(h, tail, w)
            return out + ")"

    return out

fn show(h: Heap, v: Val, w: Bool) String:
    match v:
        Num(n):
            return "{n}"
        Bo(b):
            if b:
                return "#t"

            return "#f"
        Str(s):
            if w:
                return quote_str(s)

            return s.clone()
        Sym(name):
            return name.clone()
        Nil:
            return "()"
        Void:
            return "#<void>"
        Pair(id):
            return show_pair(h, id, w)
        Prim(id):
            return "#<builtin " + h.specs[id].name + ">"
        Clo(id):
            if h.lams[id].name == "":
                return "#<procedure>"

            return "#<procedure " + h.lams[id].name + ">"

// ---------- reader ----------

fn peekc(h: Heap) Int:
    if h.pos >= h.bs.length():
        return -1

    return h.bs[h.pos].to_int()

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
    while true:
        let c = peekc(h)

        if c == 32 or c == 9 or c == 10 or c == 13:
            h.pos += 1
        else if c == 59:
            while peekc(h) != -1 and peekc(h) != 10:
                h.pos += 1
        else:
            return

fn is_lone_dot(h: Heap) Bool:
    if peekc(h) != 46:
        return false

    let p = h.pos + 1
    if p >= h.bs.length():
        return true

    return is_delim(h.bs[p].to_int())

fn chunk(h: Heap, a: Int, b: Int) String:
    if a >= b:
        return ""

    return h.data.decode_utf8_range(a, b).get("")

fn is_int_text(t: String) Bool:
    let n = t.length()
    var i = 0
    if n > 0 and t.get(0, "") == "-":
        i = 1
    if i >= n:
        return false

    while i < n:
        let ch = t.get(i, "")
        if ch < "0" or ch > "9":
            return false

        i += 1

    return true

fn read_atom(var h: Heap) Val!Fail:
    let start = h.pos
    while not is_delim(peekc(h)):
        h.pos += 1

    let tok = chunk(h, start, h.pos)
    if tok == "#t":
        return ok(Val.Bo(b: true))
    if tok == "#f":
        return ok(Val.Bo(b: false))
    if tok.get(0, "") == "#":
        return error(syn("syntax error: bad token: " + tok))
    if tok == ".":
        return error(syn("syntax error: unexpected ."))

    if is_int_text(tok):
        if let n = tok.parse_int():
            return ok(Val.Num(n: n))

        return error(syn("syntax error: integer out of range"))

    return ok(Val.Sym(name: tok))

fn read_string(var h: Heap) Val!Fail:
    h.pos += 1

    var acc = ""
    var start = h.pos

    while true:
        if h.pos >= h.bs.length():
            return error(syn("syntax error: unterminated string"))

        let c = h.bs[h.pos].to_int()

        if c == 34:
            acc = acc + chunk(h, start, h.pos)
            h.pos += 1
            return ok(Val.Str(s: acc))

        if c == 92:
            acc = acc + chunk(h, start, h.pos)
            h.pos += 1
            if h.pos >= h.bs.length():
                return error(syn("syntax error: unterminated string"))

            let e = h.bs[h.pos].to_int()

            if e == 110:
                acc = acc + "\n"
            else if e == 116:
                acc = acc + "\t"
            else if e == 92:
                acc = acc + "\\"
            else if e == 34:
                acc = acc + "\""
            else:
                return error(syn("syntax error: bad escape"))

            h.pos += 1
            start = h.pos
        else:
            h.pos += 1

    return error(syn("syntax error: unterminated string"))

fn read_list(var h: Heap) Val!Fail:
    var items = List[Val]()

    while true:
        skip_ws(var h)

        let c = peekc(h)
        if c == -1:
            return error(syn("syntax error: unexpected end of input"))

        if c == 41:
            h.pos += 1
            return ok(vec_to_list(var h, items))

        if is_lone_dot(h):
            h.pos += 1
            if items.length() == 0:
                return error(syn("syntax error: bad dotted list"))

            skip_ws(var h)

            let c2 = peekc(h)
            if c2 == -1:
                return error(syn("syntax error: unexpected end of input"))
            if c2 == 41:
                return error(syn("syntax error: bad dotted list"))

            let tailv = try read_datum(var h)
            skip_ws(var h)

            let c3 = peekc(h)
            if c3 == -1:
                return error(syn("syntax error: unexpected end of input"))
            if c3 != 41:
                return error(syn("syntax error: bad dotted list"))

            h.pos += 1

            var res = tailv.clone()
            var i = items.length() - 1

            while i >= 0:
                res = cons(var h, items[i].clone(), res.clone())
                i -= 1

            return ok(res)

        let item = try read_datum(var h)
        items.append(item)

    return error(syn("syntax error: unexpected end of input"))

fn read_datum(var h: Heap) Val!Fail:
    skip_ws(var h)

    let c = peekc(h)
    if c == -1:
        return error(syn("syntax error: unexpected end of input"))

    if c == 40:
        h.pos += 1
        return read_list(var h)

    if c == 41:
        return error(syn("syntax error: unexpected )"))

    if c == 39:
        h.pos += 1

        let inner = try read_datum(var h)
        let tailp = cons(var h, inner.clone(), Val.Nil)
        return ok(cons(var h, Val.Sym(name: "quote"), tailp))

    if c == 34:
        return read_string(var h)
    if is_lone_dot(h):
        return error(syn("syntax error: unexpected ."))

    return read_atom(var h)

// ---------- heap helpers ----------

fn new_heap(data: Bytes, bs: List[UInt8]) Heap:
    var h = Heap(
        cars: List[Val](), cdrs: List[Val](), frames: List[Frame](),
        globals: Map[String, Val](), lams: List[Lam](), specs: prim_table(), bs: bs,
        data: data, pos: 0, any_out: false, last_nl: true
    )
    var i = 0

    while i < h.specs.length():
        h.globals[h.specs[i].name.clone()] = Val.Prim(id: i)
        i += 1

    return h

fn spec(name: String, lo: Int, hi: Int) PrimSpec:
    return PrimSpec(name: name, lo: lo, hi: hi)

fn prim_table() List[PrimSpec]:
    var t = List[PrimSpec]()
    t.append(spec("+", 0, -1))
    t.append(spec("-", 1, -1))
    t.append(spec("*", 0, -1))
    t.append(spec("quotient", 2, 2))
    t.append(spec("remainder", 2, 2))
    t.append(spec("modulo", 2, 2))
    t.append(spec("abs", 1, 1))
    t.append(spec("min", 1, -1))
    t.append(spec("max", 1, -1))
    t.append(spec("=", 2, -1))
    t.append(spec("<", 2, -1))
    t.append(spec(">", 2, -1))
    t.append(spec("<=", 2, -1))
    t.append(spec(">=", 2, -1))
    t.append(spec("zero?", 1, 1))
    t.append(spec("even?", 1, 1))
    t.append(spec("odd?", 1, 1))
    t.append(spec("not", 1, 1))
    t.append(spec("null?", 1, 1))
    t.append(spec("pair?", 1, 1))
    t.append(spec("list?", 1, 1))
    t.append(spec("number?", 1, 1))
    t.append(spec("string?", 1, 1))
    t.append(spec("symbol?", 1, 1))
    t.append(spec("boolean?", 1, 1))
    t.append(spec("procedure?", 1, 1))
    t.append(spec("eq?", 2, 2))
    t.append(spec("equal?", 2, 2))
    t.append(spec("cons", 2, 2))
    t.append(spec("car", 1, 1))
    t.append(spec("cdr", 1, 1))
    t.append(spec("cadr", 1, 1))
    t.append(spec("cddr", 1, 1))
    t.append(spec("caddr", 1, 1))
    t.append(spec("set-car!", 2, 2))
    t.append(spec("set-cdr!", 2, 2))
    t.append(spec("list", 0, -1))
    t.append(spec("length", 1, 1))
    t.append(spec("append", 0, -1))
    t.append(spec("reverse", 1, 1))
    t.append(spec("list-ref", 2, 2))
    t.append(spec("list-tail", 2, 2))
    t.append(spec("range", 2, 2))
    t.append(spec("assoc", 2, 2))
    t.append(spec("member", 2, 2))
    t.append(spec("map", 2, -1))
    t.append(spec("for-each", 2, -1))
    t.append(spec("filter", 2, 2))
    t.append(spec("fold", 3, 3))
    t.append(spec("foldr", 3, 3))
    t.append(spec("apply", 2, -1))
    t.append(spec("sort", 2, 2))
    t.append(spec("string-length", 1, 1))
    t.append(spec("string-append", 0, -1))
    t.append(spec("substring", 3, 3))
    t.append(spec("string-ref", 2, 2))
    t.append(spec("string=?", 2, 2))
    t.append(spec("string<?", 2, 2))
    t.append(spec("string-upcase", 1, 1))
    t.append(spec("string-downcase", 1, 1))
    t.append(spec("number->string", 1, 1))
    t.append(spec("string->number", 1, 1))
    t.append(spec("string->symbol", 1, 1))
    t.append(spec("symbol->string", 1, 1))
    t.append(spec("string->list", 1, 1))
    t.append(spec("list->string", 1, 1))
    t.append(spec("string-join", 2, 2))
    t.append(spec("string-split", 2, 2))
    t.append(spec("string-contains?", 2, 2))
    t.append(spec("display", 1, 1))
    t.append(spec("write", 1, 1))
    t.append(spec("newline", 0, 0))
    t.append(spec("void", 0, 0))
    t.append(spec("error", 1, -1))
    return t

fn emit(var h: Heap, s: String) Unit:
    if s.length() == 0:
        return

    stdout().write(s).get()
    h.any_out = true
    h.last_nl = s.get(-1, "") == "\n"

fn report(var h: Heap, msg: String) Unit:
    if h.any_out and not h.last_nl:
        emit(var h, "\n")
    emit(var h, "error: " + msg + "\n")

// index of `name` in frame `fi`, or -1
fn frame_find(h: Heap, fi: Int, name: String) Int:
    var i = 0

    while i < h.frames[fi].names.length():
        if h.frames[fi].names[i] == name:
            return i

        i += 1

    return -1

// define `name` in frame `fi` (-1 is the global frame)
fn frame_put(var h: Heap, fi: Int, name: String, v: Val) Unit:
    if fi < 0:
        h.globals[name.clone()] = v.clone()
        return

    let j = frame_find(h, fi, name)

    if j >= 0:
        h.frames[fi].vals[j] = v.clone()
    else:
        h.frames[fi].names.append(name.clone())
        h.frames[fi].vals.append(v.clone())

fn lookup(h: Heap, env: Int, name: String) Val!Fail:
    var e = env

    while e >= 0:
        let j = frame_find(h, e, name)
        if j >= 0:
            return ok(h.frames[e].vals[j].clone())

        e = h.frames[e].parent

    if let v = h.globals.get(name):
        return ok(v)

    return error(rterr("unbound variable: " + name))

fn set_var(var h: Heap, env: Int, name: String, v: Val) Bool:
    var e = env

    while e >= 0:
        let j = frame_find(h, e, name)

        if j >= 0:
            h.frames[e].vals[j] = v.clone()
            return true

        e = h.frames[e].parent

    if h.globals.get(name).is_some():
        h.globals[name.clone()] = v.clone()
        return true

    return false

// ---------- evaluator ----------

fn make_lam(
    var h: Heap, params: Val, body: List[Val], env: Int, name: String, kw: String
) Val!Fail:
    var ps = List[String]()
    var cur = params.clone()

    while true:
        let pid = pair_id(cur)
        if pid < 0:
            break

        let pn = sym_name(h.cars[pid])
        if pn == "":
            return error(bad_form(kw))
        if ps.contains(pn):
            return error(bad_form(kw))

        ps.append(pn)
        cur = h.cdrs[pid].clone()

    var rest = ""
    var has_rest = false
    let rn = sym_name(cur)

    if rn != "":
        rest = rn
        has_rest = true
    else if not is_nil(cur):
        return error(bad_form(kw))

    if has_rest and ps.contains(rest):
        return error(bad_form(kw))

    h.lams.append(
        Lam(
            params: ps, rest: rest, has_rest: has_rest, body: body, env: env, name: name
        )
    )
    return ok(Val.Clo(id: h.lams.length() - 1))

fn enter(var h: Heap, lid: Int, args: List[Val], d: Int, tail: Bool) Step!Fail:
    let np = h.lams[lid].params.length()
    let has_rest = h.lams[lid].has_rest
    let n = args.length()
    var nm = h.lams[lid].name.clone()
    if nm == "":
        nm = "lambda"

    if has_rest:
        if n < np:
            return error(
                rterr(
                    "wrong number of arguments to "
                    + nm
                    + ": expected at least {np}, got {n}"
                )
            )
    else if n != np:
        return error(
            rterr(
                "wrong number of arguments to " + nm + ": expected {np}, got {n}"
            )
        )

    if not tail and d + 1 > 10000:
        return error(rterr("recursion limit exceeded"))

    var bd = d
    if not tail:
        bd = d + 1

    var names = h.lams[lid].params.clone()
    var vals = List[Val]()
    var i = 0

    while i < np:
        vals.append(args[i].clone())
        i += 1

    if has_rest:
        var extra = List[Val]()
        var j = np

        while j < n:
            extra.append(args[j].clone())
            j += 1

        names.append(h.lams[lid].rest.clone())
        vals.append(vec_to_list(var h, extra))

    h.frames.append(Frame(names: names, vals: vals, parent: h.lams[lid].env))

    let newenv = h.frames.length() - 1
    let body = h.lams[lid].body.clone()
    let st = try run_body(var h, body, 0, newenv, bd)
    if tail:
        return ok(st)

    let v = try eval(var h, st.next.clone(), st.nenv, bd, true)
    return ok(done_step(v.clone()))

fn run_body(var h: Heap, body: List[Val], start: Int, env: Int, d: Int) Step!Fail:
    let n = body.length()
    var i = start

    while i < n - 1:
        let _v = try eval(var h, body[i].clone(), env, d, false)
        i += 1

    return ok(cont_step(body[n - 1].clone(), env))

fn eval(var h: Heap, expr: Val, env: Int, d: Int, tail: Bool) Val!Fail:
    var x = expr.clone()
    var e = env

    while true:
        let st = try eval_step(var h, x.clone(), e, d, tail)
        if st.finished:
            return ok(st.result.clone())

        x = st.next.clone()
        e = st.nenv

    return ok(Val.Void)

fn eval_step(var h: Heap, x: Val, env: Int, d: Int, tail: Bool) Step!Fail:
    match x:
        Sym(name):
            let v = try lookup(h, env, name)
            return ok(done_step(v.clone()))
        Pair(_id):
            return eval_pair(var h, x, env, d, tail)
        Nil:
            return error(syn("syntax error: empty application"))
        _:
            return ok(done_step(x.clone()))

fn is_special(name: String) Bool:
    return (
        name == "quote"
        or name == "if"
        or name == "define"
        or name == "set!"
        or name == "lambda"
        or name == "begin"
        or name == "let"
        or name == "let*"
        or name == "letrec"
        or name == "cond"
        or name == "and"
        or name == "or"
        or name == "when"
        or name == "unless"
        or name == "try"
    )

fn eval_pair(var h: Heap, x: Val, env: Int, d: Int, tail: Bool) Step!Fail:
    if not proper_list(h, x):
        return error(syn("syntax error: bad application"))

    let items = items_of(h, x)
    let hn = sym_name(items[0])
    if hn != "" and is_special(hn):
        return special(var h, hn, items, env, d, tail)

    return apply_form(var h, items, env, d, tail)

fn apply_form(var h: Heap, items: List[Val], env: Int, d: Int, tail: Bool) Step!Fail:
    let fv = try eval(var h, items[0].clone(), env, d, false)
    var args = List[Val]()
    var i = 1

    while i < items.length():
        let a = try eval(var h, items[i].clone(), env, d, false)
        args.append(a)
        i += 1

    match fv:
        Clo(id):
            return enter(var h, id, args, d, tail)
        Prim(id):
            let r = try call_prim(var h, id, args, d)
            return ok(done_step(r))
        _:
            return error(rterr("not a procedure: " + show(h, fv, true)))

fn apply_val(var h: Heap, f: Val, args: List[Val], d: Int) Val!Fail:
    match f:
        Clo(id):
            let st = try enter(var h, id, args, d, false)
            return ok(st.result.clone())
        Prim(id):
            return call_prim(var h, id, args, d)
        _:
            return error(rterr("not a procedure: " + show(h, f, true)))

fn special(var h: Heap, name: String, items: List[Val], env: Int, d: Int, tail: Bool) Step!Fail:
    if name == "quote":
        if items.length() != 2:
            return error(bad_form("quote"))

        return ok(done_step(items[1].clone()))

    if name == "if":
        return sf_if(var h, items, env, d)
    if name == "define":
        return sf_define(var h, items, env, d)
    if name == "set!":
        return sf_set(var h, items, env, d)

    if name == "lambda":
        if items.length() < 3:
            return error(bad_form("lambda"))

        let c = try make_lam(
            var h, items[1].clone(), body_slice(items, 2), env, "", "lambda"
        )
        return ok(done_step(c))

    if name == "begin":
        if items.length() == 1:
            return ok(done_step(Val.Void))

        return run_body(var h, items, 1, env, d)

    if name == "let":
        return sf_let(var h, items, env, d, tail)
    if name == "let*" or name == "letrec":
        return sf_letstar(var h, items, env, d, name)
    if name == "cond":
        return sf_cond(var h, items, env, d)
    if name == "and":
        return sf_andor(var h, items, env, d, true)
    if name == "or":
        return sf_andor(var h, items, env, d, false)
    if name == "when":
        return sf_when(var h, items, env, d, false)
    if name == "unless":
        return sf_when(var h, items, env, d, true)

    return sf_try(var h, items, env, d)

fn sf_if(var h: Heap, items: List[Val], env: Int, d: Int) Step!Fail:
    let n = items.length()
    if n != 3 and n != 4:
        return error(bad_form("if"))

    let t = try eval(var h, items[1].clone(), env, d, false)
    if is_true(t):
        return ok(cont_step(items[2].clone(), env))
    if n == 4:
        return ok(cont_step(items[3].clone(), env))

    return ok(done_step(Val.Void))

fn eval_named(var h: Heap, rhs: Val, name: String, env: Int, d: Int) Val!Fail:
    let items = items_of(h, rhs)

    if proper_list(h, rhs) and items.length() > 0 and sym_name(items[0]) == "lambda":
        if items.length() < 3:
            return error(bad_form("lambda"))

        return make_lam(
            var h, items[1].clone(), body_slice(items, 2), env, name, "lambda"
        )

    return eval(var h, rhs, env, d, false)

fn sf_define(var h: Heap, items: List[Val], env: Int, d: Int) Step!Fail:
    if items.length() < 3:
        return error(bad_form("define"))

    let target = items[1].clone()
    let tn = sym_name(target)

    if tn != "":
        if items.length() != 3:
            return error(bad_form("define"))

        let v = try eval_named(var h, items[2].clone(), tn.clone(), env, d)
        frame_put(var h, env, tn, v)
        return ok(done_step(Val.Void))

    let pid = pair_id(target)
    if pid < 0:
        return error(bad_form("define"))

    let fname = sym_name(h.cars[pid])
    if fname == "":
        return error(bad_form("define"))

    let c = try make_lam(
        var h, h.cdrs[pid].clone(), body_slice(items, 2), env, fname.clone(), "define"
    )
    frame_put(var h, env, fname, c)
    return ok(done_step(Val.Void))

fn sf_set(var h: Heap, items: List[Val], env: Int, d: Int) Step!Fail:
    if items.length() != 3 or sym_name(items[1]) == "":
        return error(bad_form("set!"))

    let name = sym_name(items[1])
    let v = try eval(var h, items[2].clone(), env, d, false)
    if not set_var(var h, env, name, v):
        return error(rterr("unbound variable: " + name))

    return ok(done_step(Val.Void))

fn parse_binds(h: Heap, bindings: Val, kw: String) Binds!Fail:
    if not proper_list(h, bindings):
        return error(bad_form(kw))

    var names = List[String]()
    var inits = List[Val]()
    let bl = items_of(h, bindings)

    for b in bl:
        if not proper_list(h, b):
            return error(bad_form(kw))

        let bi = items_of(h, b)
        if bi.length() != 2 or sym_name(bi[0]) == "":
            return error(bad_form(kw))

        names.append(sym_name(bi[0]))
        inits.append(bi[1].clone())

    return ok(Binds(names: names, inits: inits))

fn sf_let(var h: Heap, items: List[Val], env: Int, d: Int, tail: Bool) Step!Fail:
    if items.length() < 3:
        return error(bad_form("let"))

    let lname = sym_name(items[1])

    if lname != "":
        if items.length() < 4:
            return error(bad_form("let"))

        let bs = try parse_binds(h, items[2].clone(), "let")
        var vals = List[Val]()

        for init in bs.inits:
            let v = try eval(var h, init.clone(), env, d, false)
            vals.append(v)

        var fnames = List[String]()
        fnames.append(lname.clone())

        var fvals = List[Val]()
        fvals.append(Val.Void)
        h.frames.append(Frame(names: fnames, vals: fvals, parent: env))

        let f1 = h.frames.length() - 1
        h.lams.append(
            Lam(
                params: bs.names.clone(), rest: "", has_rest: false,
                body: body_slice(items, 3), env: f1, name: lname.clone()
            )
        )

        let cid = h.lams.length() - 1
        h.frames[f1].vals[0] = Val.Clo(id: cid)
        return enter(var h, cid, vals, d, tail)

    let bs = try parse_binds(h, items[1].clone(), "let")
    var names = List[String]()
    var vals = List[Val]()
    var i = 0

    while i < bs.names.length():
        let v = try eval(var h, bs.inits[i].clone(), env, d, false)
        names.append(bs.names[i].clone())
        vals.append(v)
        i += 1

    h.frames.append(Frame(names: names, vals: vals, parent: env))

    let ne = h.frames.length() - 1
    return run_body(var h, items, 2, ne, d)

fn sf_letstar(var h: Heap, items: List[Val], env: Int, d: Int, kw: String) Step!Fail:
    if items.length() < 3:
        return error(bad_form(kw))

    let bs = try parse_binds(h, items[1].clone(), kw)
    h.frames.append(Frame(names: List[String](), vals: List[Val](), parent: env))

    let ne = h.frames.length() - 1
    var i = 0

    while i < bs.names.length():
        let v = try eval(var h, bs.inits[i].clone(), ne, d, false)
        frame_put(var h, ne, bs.names[i], v)
        i += 1

    return run_body(var h, items, 2, ne, d)

fn sf_cond(var h: Heap, items: List[Val], env: Int, d: Int) Step!Fail:
    let n = items.length()
    var i = 1

    while i < n:
        let clause = items[i].clone()
        if pair_id(clause) < 0 or not proper_list(h, clause):
            return error(bad_form("cond"))

        let ci = items_of(h, clause)

        if sym_name(ci[0]) == "else":
            if i != n - 1 or ci.length() < 2:
                return error(bad_form("cond"))

            return run_body(var h, ci, 1, env, d)

        let t = try eval(var h, ci[0].clone(), env, d, false)

        if is_true(t):
            if ci.length() == 1:
                return ok(done_step(t.clone()))

            return run_body(var h, ci, 1, env, d)

        i += 1

    return ok(done_step(Val.Void))

fn sf_andor(var h: Heap, items: List[Val], env: Int, d: Int, is_and: Bool) Step!Fail:
    let n = items.length()
    if n == 1:
        return ok(done_step(Val.Bo(b: is_and)))

    var i = 1

    while i < n - 1:
        let v = try eval(var h, items[i].clone(), env, d, false)
        if is_and and not is_true(v):
            return ok(done_step(v))
        if not is_and and is_true(v):
            return ok(done_step(v))

        i += 1

    return ok(cont_step(items[n - 1].clone(), env))

fn sf_when(var h: Heap, items: List[Val], env: Int, d: Int, neg: Bool) Step!Fail:
    if items.length() < 3:
        return error(bad_form("when"))

    let t = try eval(var h, items[1].clone(), env, d, false)
    var fires = is_true(t)
    if neg:
        fires = not fires
    if fires:
        return run_body(var h, items, 2, env, d)

    return ok(done_step(Val.Void))

fn sf_try(var h: Heap, items: List[Val], env: Int, d: Int) Step!Fail:
    if items.length() != 3:
        return error(bad_form("try"))

    let r = eval(var h, items[1].clone(), env, d, false)

    if r.is_error():
        let f = r.err()
        if f.syntax:
            return error(f)

        let hv = try eval(var h, items[2].clone(), env, d, false)
        var args = List[Val]()
        args.append(Val.Str(s: f.msg.clone()))

        let res = try apply_val(var h, hv, args, d)
        return ok(done_step(res))

    return ok(done_step(r.get(Val.Void)))

// ---------- builtins ----------

fn want_int(name: String, h: Heap, v: Val) Int!Fail:
    match v:
        Num(n):
            return ok(n)
        _:
            return error(kind_err(name, "integer", h, v))

fn want_str(name: String, h: Heap, v: Val) String!Fail:
    match v:
        Str(s):
            return ok(s)
        _:
            return error(kind_err(name, "string", h, v))

fn want_list(name: String, h: Heap, v: Val) Bool!Fail:
    if proper_list(h, v):
        return ok(true)

    return error(kind_err(name, "list", h, v))

fn ints_of(name: String, h: Heap, args: List[Val]) List[Int]!Fail:
    var out = List[Int]()

    for a in args:
        let n = try want_int(name, h, a)
        out.append(n)

    return ok(out)

fn int_min() Int:
    return -9223372036854775807 - 1

fn int_max() Int:
    return 9223372036854775807

fn add_ok(a: Int, b: Int) Bool:
    if b > 0:
        return a <= int_max() - b

    return a >= int_min() - b

fn sub_ok(a: Int, b: Int) Bool:
    if b < 0:
        return a <= int_max() + b

    return a >= int_min() + b

fn mul_ok(a: Int, b: Int) Bool:
    if a == 0 or b == 0:
        return true
    if a == -1:
        return b != int_min()
    if b == -1:
        return a != int_min()

    if a > 0:
        if b > 0:
            return a <= int_max() / b

        return b >= int_min() / a

    if b > 0:
        return a >= int_min() / b

    return a >= int_max() / b

fn cmp_ok(op: Int, a: Int, b: Int) Bool:
    if op == 0:
        return a == b
    if op == 1:
        return a < b
    if op == 2:
        return a > b
    if op == 3:
        return a <= b

    return a >= b

fn call_prim(var h: Heap, id: Int, args: List[Val], d: Int) Val!Fail:
    let nm = h.specs[id].name.clone()
    let lo = h.specs[id].lo
    let hi = h.specs[id].hi
    let n = args.length()

    if n < lo or (hi >= 0 and n > hi):
        var exp = "{lo}"

        if hi < 0:
            exp = "at least {lo}"
        else if lo != hi:
            exp = "{lo} to {hi}"

        return error(
            rterr(
                "wrong number of arguments to " + nm + ": expected " + exp + ", got {n}"
            )
        )

    if (
        nm == "+"
        or nm == "-"
        or nm == "*"
        or nm == "min"
        or nm == "max"
        or nm == "abs"
        or nm == "="
        or nm == "<"
        or nm == ">"
        or nm == "<="
        or nm == ">="
        or nm == "zero?"
        or nm == "even?"
        or nm == "odd?"
        or nm == "quotient"
        or nm == "remainder"
        or nm == "modulo"
        or nm == "number->string"
    ):
        return prim_num(var h, nm, args)
    if (
        nm == "eq?"
        or nm == "equal?"
        or nm == "not"
        or nm == "null?"
        or nm == "pair?"
        or nm == "list?"
        or nm == "number?"
        or nm == "string?"
        or nm == "symbol?"
        or nm == "boolean?"
        or nm == "procedure?"
        or nm == "cons"
        or nm == "car"
        or nm == "cdr"
        or nm == "cadr"
        or nm == "cddr"
        or nm == "caddr"
        or nm == "set-car!"
        or nm == "set-cdr!"
        or nm == "list"
        or nm == "length"
        or nm == "append"
        or nm == "reverse"
        or nm == "list-ref"
        or nm == "list-tail"
        or nm == "range"
        or nm == "assoc"
        or nm == "member"
    ):
        return prim_data(var h, nm, args)
    if (
        nm == "map"
        or nm == "for-each"
        or nm == "filter"
        or nm == "fold"
        or nm == "foldr"
        or nm == "apply"
        or nm == "sort"
    ):
        return prim_hof(var h, nm, args, d)
    if (
        nm == "display"
        or nm == "write"
        or nm == "newline"
        or nm == "void"
        or nm == "error"
    ):
        return prim_io(var h, nm, args)

    return prim_str(var h, nm, args)

fn prim_num(var h: Heap, nm: String, args: List[Val]) Val!Fail:
    if nm == "+":
        let xs = try ints_of(nm, h, args)
        var acc = 0

        for x in xs:
            if not add_ok(acc, x):
                return error(rterr("integer overflow"))

            acc += x

        return ok(Val.Num(n: acc))

    if nm == "-":
        let xs = try ints_of(nm, h, args)

        if xs.length() == 1:
            if xs[0] == int_min():
                return error(rterr("integer overflow"))

            return ok(Val.Num(n: -xs[0]))

        var acc = xs[0]
        var i = 1

        while i < xs.length():
            if not sub_ok(acc, xs[i]):
                return error(rterr("integer overflow"))

            acc -= xs[i]
            i += 1

        return ok(Val.Num(n: acc))

    if nm == "*":
        let xs = try ints_of(nm, h, args)
        var acc = 1

        for x in xs:
            if not mul_ok(acc, x):
                return error(rterr("integer overflow"))

            acc *= x

        return ok(Val.Num(n: acc))

    if nm == "quotient" or nm == "remainder" or nm == "modulo":
        let a = try want_int(nm, h, args[0])
        let b = try want_int(nm, h, args[1])
        if b == 0:
            return error(rterr("division by zero"))
        if a == int_min() and b == -1:
            return error(rterr("integer overflow"))

        let q = a / b
        let r = a - q * b
        if nm == "quotient":
            return ok(Val.Num(n: q))
        if nm == "remainder":
            return ok(Val.Num(n: r))

        var m = r
        if m != 0 and ((m < 0) != (b < 0)):
            m = m + b
        return ok(Val.Num(n: m))

    if nm == "abs":
        let a = try want_int(nm, h, args[0])
        if a == int_min():
            return error(rterr("integer overflow"))
        if a < 0:
            return ok(Val.Num(n: -a))

        return ok(Val.Num(n: a))

    if nm == "min" or nm == "max":
        let xs = try ints_of(nm, h, args)
        var best = xs[0]

        for x in xs:
            if nm == "min" and x < best:
                best = x
            if nm == "max" and x > best:
                best = x

        return ok(Val.Num(n: best))

    if nm == "zero?":
        let a = try want_int(nm, h, args[0])
        return ok(Val.Bo(b: a == 0))

    if nm == "even?" or nm == "odd?":
        let a = try want_int(nm, h, args[0])
        let even = a - (a / 2) * 2 == 0
        if nm == "even?":
            return ok(Val.Bo(b: even))

        return ok(Val.Bo(b: not even))

    if nm == "number->string":
        let a = try want_int(nm, h, args[0])
        return ok(Val.Str(s: "{a}"))

    // comparisons, chained
    let xs = try ints_of(nm, h, args)
    var op = 0

    if nm == "<":
        op = 1
    else if nm == ">":
        op = 2
    else if nm == "<=":
        op = 3
    else if nm == ">=":
        op = 4

    var i = 0

    while i + 1 < xs.length():
        if not cmp_ok(op, xs[i], xs[i + 1]):
            return ok(Val.Bo(b: false))

        i += 1

    return ok(Val.Bo(b: true))

fn prim_data(var h: Heap, nm: String, args: List[Val]) Val!Fail:
    if nm == "not":
        return ok(Val.Bo(b: not is_true(args[0])))
    if nm == "null?":
        return ok(Val.Bo(b: is_nil(args[0])))
    if nm == "pair?":
        return ok(Val.Bo(b: pair_id(args[0]) >= 0))
    if nm == "list?":
        return ok(Val.Bo(b: proper_list(h, args[0])))
    if nm == "number?":
        return ok(Val.Bo(b: is_num(args[0])))
    if nm == "string?":
        return ok(Val.Bo(b: is_str(args[0])))
    if nm == "symbol?":
        return ok(Val.Bo(b: sym_name(args[0]) != ""))
    if nm == "boolean?":
        return ok(Val.Bo(b: is_bool(args[0])))
    if nm == "procedure?":
        return ok(Val.Bo(b: is_proc(args[0])))
    if nm == "eq?":
        return ok(Val.Bo(b: eq_val(args[0], args[1])))
    if nm == "equal?":
        return ok(Val.Bo(b: equal_val(h, args[0], args[1])))
    if nm == "cons":
        return ok(cons(var h, args[0], args[1]))

    if nm == "car" or nm == "cdr" or nm == "cadr" or nm == "cddr" or nm == "caddr":
        var cur = args[0].clone()

        // walk the c[ad]+r path from the last letter inward
        var k = nm.length() - 2

        while k >= 1:
            let letter = nm.get(k, "")
            let p = pair_id(cur)
            if p < 0:
                return error(kind_err(nm, "pair", h, cur))

            if letter == "a":
                cur = h.cars[p].clone()
            else:
                cur = h.cdrs[p].clone()

            k -= 1

        return ok(cur)

    if nm == "set-car!" or nm == "set-cdr!":
        let p = pair_id(args[0])
        if p < 0:
            return error(kind_err(nm, "pair", h, args[0]))

        if nm == "set-car!":
            h.cars[p] = args[1].clone()
        else:
            h.cdrs[p] = args[1].clone()

        return ok(Val.Void)

    if nm == "list":
        return ok(vec_to_list(var h, args))

    if nm == "length":
        let _ok = try want_list(nm, h, args[0])
        return ok(Val.Num(n: items_of(h, args[0]).length()))

    if nm == "append":
        let n = args.length()
        if n == 0:
            return ok(Val.Nil)

        var i = 0

        while i < n - 1:
            let _ok = try want_list(nm, h, args[i])
            i += 1

        var res = args[n - 1].clone()
        var j = n - 2

        while j >= 0:
            let its = items_of(h, args[j])
            var k = its.length() - 1

            while k >= 0:
                res = cons(var h, its[k].clone(), res.clone())
                k -= 1

            j -= 1

        return ok(res)

    if nm == "reverse":
        let _ok = try want_list(nm, h, args[0])
        let its = items_of(h, args[0])
        var res = Val.Nil
        var i = 0

        while i < its.length():
            res = cons(var h, its[i].clone(), res.clone())
            i += 1

        return ok(res)

    if nm == "list-ref" or nm == "list-tail":
        let _ok = try want_list(nm, h, args[0])
        let k = try want_int(nm, h, args[1])
        let its = items_of(h, args[0])

        if nm == "list-ref":
            if k < 0 or k >= its.length():
                return error(rterr("list-ref: index out of range"))

            return ok(its[k].clone())

        if k < 0 or k > its.length():
            return error(rterr("list-tail: index out of range"))

        var cur = args[0].clone()
        var i = 0

        while i < k:
            cur = h.cdrs[pair_id(cur)].clone()
            i += 1

        return ok(cur)

    if nm == "range":
        let a = try want_int(nm, h, args[0])
        let b = try want_int(nm, h, args[1])
        var res = Val.Nil
        var i = b - 1

        while i >= a:
            res = cons(var h, Val.Num(n: i), res.clone())
            i -= 1

        return ok(res)

    if nm == "assoc" or nm == "member":
        let _ok = try want_list(nm, h, args[1])
        var cur = args[1].clone()

        while true:
            let p = pair_id(cur)
            if p < 0:
                return ok(Val.Bo(b: false))

            let el = h.cars[p].clone()

            if nm == "assoc":
                if pair_id(el) < 0:
                    return error(kind_err(nm, "pair", h, el))
                if equal_val(h, args[0], h.cars[pair_id(el)].clone()):
                    return ok(el)
            else if equal_val(h, args[0], el):
                return ok(cur)

            cur = h.cdrs[p].clone()

    return error(rterr("unknown builtin: " + nm))

fn merge_sort(var h: Heap, items: List[Val], f: Val, d: Int) List[Val]!Fail:
    var src = items.clone()
    let n = src.length()
    var width = 1

    while width < n:
        var dst = List[Val]()
        var lo = 0

        while lo < n:
            var mid = lo + width
            if mid > n:
                mid = n

            var hi = lo + 2 * width
            if hi > n:
                hi = n

            var i = lo
            var j = mid

            while i < mid or j < hi:
                if i >= mid:
                    dst.append(src[j].clone())
                    j += 1
                else if j >= hi:
                    dst.append(src[i].clone())
                    i += 1
                else:
                    let lt = try apply_val(
                        var h, f.clone(), [src[j].clone(), src[i].clone()], d
                    )

                    if is_true(lt):
                        dst.append(src[j].clone())
                        j += 1
                    else:
                        dst.append(src[i].clone())
                        i += 1

            lo = hi

        src = dst
        width = width * 2

    return ok(src)

fn prim_hof(var h: Heap, nm: String, args: List[Val], d: Int) Val!Fail:
    if nm == "map" or nm == "for-each":
        if not is_proc(args[0]):
            return error(kind_err(nm, "procedure", h, args[0]))

        var curs = List[Val]()
        var cnt = -1
        var i = 1

        while i < args.length():
            let _ok = try want_list(nm, h, args[i])
            let its = items_of(h, args[i])
            if cnt < 0 or its.length() < cnt:
                cnt = its.length()
            curs.append(args[i].clone())
            i += 1

        if cnt < 0:
            cnt = 0

        var out = List[Val]()
        var step = 0

        while step < cnt:
            var elems = List[Val]()
            var j = 0

            while j < curs.length():
                let p = pair_id(curs[j])
                elems.append(h.cars[p].clone())
                curs[j] = h.cdrs[p].clone()
                j += 1

            let r = try apply_val(var h, args[0].clone(), elems, d)
            if nm == "map":
                out.append(r)
            step += 1

        if nm == "map":
            return ok(vec_to_list(var h, out))

        return ok(Val.Void)

    if nm == "filter":
        if not is_proc(args[0]):
            return error(kind_err(nm, "procedure", h, args[0]))

        let _ok = try want_list(nm, h, args[1])
        let its = items_of(h, args[1])
        var out = List[Val]()

        for e in its:
            var one = List[Val]()
            one.append(e.clone())

            let t = try apply_val(var h, args[0].clone(), one, d)
            if is_true(t):
                out.append(e.clone())

        return ok(vec_to_list(var h, out))

    if nm == "fold" or nm == "foldr":
        if not is_proc(args[0]):
            return error(kind_err(nm, "procedure", h, args[0]))

        let _ok = try want_list(nm, h, args[2])
        let its = items_of(h, args[2])
        var acc = args[1].clone()

        if nm == "fold":
            for e in its:
                var two = List[Val]()
                two.append(acc.clone())
                two.append(e.clone())
                acc = try apply_val(var h, args[0].clone(), two, d)
        else:
            var i = its.length() - 1

            while i >= 0:
                var two = List[Val]()
                two.append(its[i].clone())
                two.append(acc.clone())
                acc = try apply_val(var h, args[0].clone(), two, d)
                i -= 1

        return ok(acc)

    if nm == "apply":
        if not is_proc(args[0]):
            return error(kind_err(nm, "procedure", h, args[0]))

        let n = args.length()
        let _ok = try want_list(nm, h, args[n - 1])
        var fargs = List[Val]()
        var i = 1

        while i < n - 1:
            fargs.append(args[i].clone())
            i += 1

        let tailitems = items_of(h, args[n - 1])
        for t in tailitems:
            fargs.append(t.clone())
        return apply_val(var h, args[0].clone(), fargs, d)

    // sort
    if not is_proc(args[1]):
        return error(kind_err(nm, "procedure", h, args[1]))

    let _ok = try want_list(nm, h, args[0])
    let its = items_of(h, args[0])
    let sorted = try merge_sort(var h, its, args[1].clone(), d)
    return ok(vec_to_list(var h, sorted))

fn prim_io(var h: Heap, nm: String, args: List[Val]) Val!Fail:
    if nm == "display":
        emit(var h, show(h, args[0], false))
        return ok(Val.Void)

    if nm == "write":
        emit(var h, show(h, args[0], true))
        return ok(Val.Void)

    if nm == "newline":
        emit(var h, "\n")
        return ok(Val.Void)

    if nm == "void":
        return ok(Val.Void)

    // error
    let msg = try want_str(nm, h, args[0])
    var text = msg.clone()
    var i = 1

    while i < args.length():
        text = text + " " + show(h, args[i], true)
        i += 1

    return error(rterr(text))

fn prim_str(var h: Heap, nm: String, args: List[Val]) Val!Fail:
    if nm == "string-length":
        let s = try want_str(nm, h, args[0])
        return ok(Val.Num(n: s.length()))

    if nm == "string-append":
        var out = ""
        var i = 0

        while i < args.length():
            let s = try want_str(nm, h, args[i])
            out = out + s
            i += 1

        return ok(Val.Str(s: out))

    if nm == "substring":
        let s = try want_str(nm, h, args[0])
        let a = try want_int(nm, h, args[1])
        let b = try want_int(nm, h, args[2])
        if a < 0 or a > b or b > s.length():
            return error(rterr("substring: index out of range"))

        return ok(Val.Str(s: s.slice_scalars(a, b).get("")))

    if nm == "string-ref":
        let s = try want_str(nm, h, args[0])
        let k = try want_int(nm, h, args[1])
        if k < 0 or k >= s.length():
            return error(rterr("string-ref: index out of range"))

        return ok(Val.Str(s: s.get(k, "")))

    if nm == "string=?":
        let a = try want_str(nm, h, args[0])
        let b = try want_str(nm, h, args[1])
        return ok(Val.Bo(b: a == b))

    if nm == "string<?":
        let a = try want_str(nm, h, args[0])
        let b = try want_str(nm, h, args[1])
        return ok(Val.Bo(b: a < b))

    if nm == "string-upcase":
        let s = try want_str(nm, h, args[0])
        return ok(Val.Str(s: s.upper()))

    if nm == "string-downcase":
        let s = try want_str(nm, h, args[0])
        return ok(Val.Str(s: s.lower()))

    if nm == "string->number":
        let s = try want_str(nm, h, args[0])
        if is_int_text(s):
            if let n = s.parse_int():
                return ok(Val.Num(n: n))
        return ok(Val.Bo(b: false))

    if nm == "string->symbol":
        let s = try want_str(nm, h, args[0])
        return ok(Val.Sym(name: s.clone()))

    if nm == "symbol->string":
        let s = sym_name(args[0])
        if s == "":
            return error(kind_err(nm, "symbol", h, args[0]))

        return ok(Val.Str(s: s))

    if nm == "string->list":
        let s = try want_str(nm, h, args[0])
        var items = List[Val]()
        var i = 0

        while i < s.length():
            items.append(Val.Str(s: s.get(i, "")))
            i += 1

        return ok(vec_to_list(var h, items))

    if nm == "list->string":
        let _ok = try want_list(nm, h, args[0])
        var out = ""

        for e in items_of(h, args[0]):
            if not is_str(e):
                return error(kind_err(nm, "string", h, e))

            out = out + str_of(e)

        return ok(Val.Str(s: out))

    if nm == "string-join":
        let _ok = try want_list(nm, h, args[0])
        let sep = try want_str(nm, h, args[1])
        var out = ""
        var first = true

        for e in items_of(h, args[0]):
            if not is_str(e):
                return error(kind_err(nm, "string", h, e))

            if not first:
                out = out + sep
            out = out + str_of(e)
            first = false

        return ok(Val.Str(s: out))

    if nm == "string-split":
        let s = try want_str(nm, h, args[0])
        let sep = try want_str(nm, h, args[1])
        if sep.length() != 1:
            return error(rterr("string-split: separator must be one character"))

        var items = List[Val]()
        for part in s.split(sep):
            items.append(Val.Str(s: part.clone()))
        return ok(vec_to_list(var h, items))

    // string-contains?
    let s = try want_str(nm, h, args[0])
    let sub = try want_str(nm, h, args[1])
    return ok(Val.Bo(b: s.contains(sub)))

// ---------- entry ----------

export fn main() Int:
    let data = read_all(stdin()).get()
    let bs = values(data)
    var h = new_heap(data, bs)

    while true:
        skip_ws(var h)
        if peekc(h) == -1:
            return 0

        let rd = read_datum(var h)

        if rd.is_error():
            report(var h, rd.err().msg)
            return 0

        let ev = eval(var h, rd.get(Val.Void), -1, 0, false)

        if ev.is_error():
            report(var h, ev.err().msg)
            return 0

    return 0
