import read_all, stdin, stdout from "@std/io.ms"

let MAX_INT = 9223372036854775807
let MIN_INT = -9223372036854775807 - 1
let MAX_DEPTH = 10000
let DIGITS = "0123456789"
let T_NUMBER = 1
let T_BOOLEAN = 2
let T_TEXT = 3
let T_SYMBOL = 4
let T_PAIR = 5
let T_NIL = 6
let T_VOID = 7
let T_BUILTIN = 8
let T_CLOSURE = 9

type Fault:
    text: String
    syntax: Bool

impl Error for Fault:
    fn message() String:
        return self.text.clone()

type Value:
    case Number(n: Int)
    case Boolean(on: Bool)
    case Text(s: String)
    case Symbol(name: String)
    case PairRef(id: Int)
    case Nil
    case Void
    case Builtin(name: String, low: Int, high: Int)
    case Closure(id: Int)

type Frame:
    vars: Map[String, Value]
    parent: Int

type Procedure:
    name: String
    params: List[String]
    rest: Bool
    body: List[Value]
    env: Int

type Machine:
    input: List[String]
    pos: Int
    cars: List[Value]
    cdrs: List[Value]
    frames: List[Frame]
    procs: List[Procedure]
    clean: Bool
    escape: Int

type Step:
    case Done(value: Value)
    case Tail(expr: Value, env: Int)

type Params:
    names: List[String]
    rest: Bool

type Bindings:
    names: List[String]
    inits: List[Value]

type Token:
    case Open
    case Close
    case Quote
    case Dot
    case End
    case Atom(text: String)
    case Str(text: String)

# ---------- errors and small helpers ----------

fn rt_fault(text: String) Fault:
    return Fault(text: text, syntax: false)

fn syntax_fault(text: String) Fault:
    return Fault(text: "syntax error: " + text, syntax: true)

fn bad_form(name: String) Fault:
    return syntax_fault("bad form: " + name)

fn wrong_kind(m: Machine, name: String, kind: String, v: Value) Fault:
    return rt_fault(name + ": expected " + kind + ", got " + show(m, v, true))

fn check_arity(name: String, low: Int, high: Int, got: Int) Result[Unit, Fault]:
    if got >= low and (high < 0 or got <= high):
        return ok(unit)

    var expected = "at least " + "{low}"

    if high == low:
        expected = "{low}"
    else if high >= 0:
        expected = "{low} to {high}"

    return error(
        rt_fault(
            "wrong number of arguments to {name}: expected {expected}, got {got}"
        )
    )

fn tag(v: Value) Int:
    match v:
        Number(_): return T_NUMBER
        Boolean(_): return T_BOOLEAN
        Text(_): return T_TEXT
        Symbol(_): return T_SYMBOL
        PairRef(_): return T_PAIR
        Nil: return T_NIL
        Void: return T_VOID
        Builtin(_, _, _): return T_BUILTIN
        Closure(_): return T_CLOSURE

fn pair_id_of(v: Value) Int:
    match v:
        PairRef(id): return id
        _: return -1

fn closure_id_of(v: Value) Int:
    match v:
        Closure(id): return id
        _: return -1

fn symbol_name(v: Value) String:
    match v:
        Symbol(name): return name.clone()
        _: return ""

fn text_of(v: Value) String:
    match v:
        Text(s): return s.clone()
        _: return ""

fn builtin_name(v: Value) String:
    match v:
        Builtin(name, _, _): return name.clone()
        _: return ""

fn truthy(v: Value) Bool:
    match v:
        Boolean(on): return on
        _: return true

fn is_nil(v: Value) Bool:
    return tag(v) == T_NIL

fn is_procedure(v: Value) Bool:
    return tag(v) == T_BUILTIN or tag(v) == T_CLOSURE

# Text of atoms that have no payload to quote: numbers, booleans, symbols, ().
fn atom_text(v: Value) String:
    match v:
        Number(n): return "{n}"
        Boolean(on):
            if on:
                return "#t"

            return "#f"
        Symbol(name): return name.clone()
        Nil: return "()"
        _: return ""

fn quote_text(s: String) String:
    let body = s.replace("\\", "\\\\").replace("\"", "\\\"").replace(
        "\n", "\\n"
    ).replace("\t", "\\t")
    return "\"" + body + "\""

fn show(m: Machine, v: Value, quoted: Bool) String:
    match v:
        Text(s):
            if quoted:
                return quote_text(s)

            return s.clone()
        PairRef(id): return show_pair(m, id, quoted)
        Void: return "#<void>"
        Builtin(name, _, _): return "#<builtin " + name + ">"
        Closure(id):
            let name = m.procs[id].name.clone()
            if name.is_empty():
                return "#<procedure>"

            return "#<procedure " + name + ">"
        _: return atom_text(v)

fn show_pair(m: Machine, id: Int, quoted: Bool) String:
    var parts = List[String]()
    var rest = Value.PairRef(id)

    while true:
        let pid = pair_id_of(rest)
        if pid < 0:
            break

        parts.append(show(m, m.cars[pid], quoted))
        rest = m.cdrs[pid].clone()

    var tail = ""
    if not is_nil(rest):
        tail = " . " + show(m, rest, quoted)
    return "(" + parts.join(" ") + tail + ")"

# ---------- heap, lists, and output ----------

fn cons(var m: Machine, head: Value, rest: Value) Value:
    m.cars.append(head)
    m.cdrs.append(rest)
    return Value.PairRef(m.cars.length() - 1)

fn build_list(var m: Machine, items: List[Value], tail: Value) Value:
    var acc = tail
    var i = items.length() - 1

    while i >= 0:
        acc = cons(var m, items[i].clone(), acc)
        i -= 1

    return acc

fn to_list(m: Machine, v: Value) Optional[List[Value]]:
    var out = List[Value]()
    var rest = v.clone()

    while true:
        let pid = pair_id_of(rest)
        if pid < 0:
            break

        out.append(m.cars[pid].clone())
        rest = m.cdrs[pid].clone()

    if is_nil(rest):
        return some(out)

    return none

fn list_of(m: Machine, name: String, v: Value) Result[List[Value], Fault]:
    if let items = to_list(m, v):
        return ok(items)

    return error(wrong_kind(m, name, "list", v))

fn int_of(m: Machine, name: String, v: Value) Result[Int, Fault]:
    match v:
        Number(n): return ok(n)
        _: return error(wrong_kind(m, name, "integer", v))

fn str_of(m: Machine, name: String, v: Value) Result[String, Fault]:
    match v:
        Text(s): return ok(s.clone())
        _: return error(wrong_kind(m, name, "string", v))

fn pair_of(m: Machine, name: String, v: Value) Result[Int, Fault]:
    let id = pair_id_of(v)
    if id < 0:
        return error(wrong_kind(m, name, "pair", v))

    return ok(id)

fn ints_of(m: Machine, name: String, args: List[Value]) Result[List[Int], Fault]:
    var out = List[Int]()

    for a in args:
        match a:
            Number(n): out.append(n)
            _: return error(wrong_kind(m, name, "integer", a))

    return ok(out)

fn emit(var m: Machine, s: String) Unit:
    if s.length() > 0:
        m.clean = s.ends_with("\n")
    stdout().write(s).get()

fn report(var m: Machine, f: Fault) Unit:
    if not m.clean:
        emit(var m, "\n")
    emit(var m, "error: " + f.text + "\n")

# Drops frames created above `mark` unless a closure may still refer to one.
fn release(var m: Machine, mark: Int) Unit:
    if m.escape >= mark:
        return

    while m.frames.length() > mark:
        let _dropped = m.frames.pop()

fn new_frame(var m: Machine, parent: Int) Int:
    m.frames.append(Frame(vars: Map[String, Value](), parent: parent))
    return m.frames.length() - 1

fn lookup(m: Machine, env: Int, name: String) Optional[Value]:
    var e = env

    while e >= 0:
        if let v = m.frames[e].vars.get(name):
            return some(v.clone())

        e = m.frames[e].parent

    return none

# ---------- reader ----------

fn is_delim(c: String) Bool:
    return (
        c == " "
        or c == "\t"
        or c == "\n"
        or c == "\r"
        or c == "("
        or c == ")"
        or c == "\""
        or c == ";"
    )

fn skip_space(var m: Machine) Unit:
    while m.pos < m.input.length():
        let c = m.input[m.pos]

        if c == ";":
            while m.pos < m.input.length() and m.input[m.pos] != "\n":
                m.pos += 1
        else if c == " " or c == "\t" or c == "\n" or c == "\r":
            m.pos += 1
        else:
            return

fn read_string(var m: Machine) Result[Token, Fault]:
    var text = ""

    while m.pos < m.input.length():
        let c = m.input[m.pos]
        m.pos += 1
        if c == "\"":
            return ok(Token.Str(text))

        if c == "\\":
            if m.pos >= m.input.length():
                break

            let e = m.input[m.pos]
            m.pos += 1

            if e == "n":
                text = text + "\n"
            else if e == "t":
                text = text + "\t"
            else if e == "\\":
                text = text + "\\"
            else if e == "\"":
                text = text + "\""
            else:
                return error(syntax_fault("bad escape"))
        else:
            text = text + c

    return error(syntax_fault("unterminated string"))

fn next_token(var m: Machine) Result[Token, Fault]:
    skip_space(var m)
    if m.pos >= m.input.length():
        return ok(Token.End)

    let c = m.input[m.pos]

    if c == "(":
        m.pos += 1
        return ok(Token.Open)

    if c == ")":
        m.pos += 1
        return ok(Token.Close)

    if c == "'":
        m.pos += 1
        return ok(Token.Quote)

    if c == "\"":
        m.pos += 1
        return read_string(var m)

    var text = ""

    while m.pos < m.input.length() and not is_delim(m.input[m.pos]):
        text = text + m.input[m.pos]
        m.pos += 1

    if text == ".":
        return ok(Token.Dot)

    return ok(Token.Atom(text))

fn is_close(t: Token) Bool:
    match t:
        Close: return true
        _: return false

fn is_dot(t: Token) Bool:
    match t:
        Dot: return true
        _: return false

fn is_end(t: Token) Bool:
    match t:
        End: return true
        _: return false

fn is_integer_text(text: String) Bool:
    var digits = text.clone()
    if text.starts_with("-"):
        digits = text.drop(1)
    if digits.is_empty():
        return false

    for c in digits.chars():
        if not DIGITS.contains(c):
            return false
    return true

fn atom_value(text: String) Result[Value, Fault]:
    if text == "#t":
        return ok(Value.Boolean(true))
    if text == "#f":
        return ok(Value.Boolean(false))
    if text.starts_with("#"):
        return error(syntax_fault("bad token: " + text))

    if is_integer_text(text):
        if let n = text.parse_int():
            return ok(Value.Number(n))

        return error(syntax_fault("integer out of range"))

    return ok(Value.Symbol(text))

fn build_quote(var m: Machine, datum: Value) Value:
    let tail = cons(var m, datum, Value.Nil)
    return cons(var m, Value.Symbol("quote"), tail)

fn datum_from(var m: Machine, tok: Token) Result[Value, Fault]:
    match tok:
        End: return error(syntax_fault("unexpected end of input"))
        Close: return error(syntax_fault("unexpected )"))
        Dot: return error(syntax_fault("unexpected ."))
        Open: return read_list(var m)
        Str(text): return ok(Value.Text(text))
        Atom(text): return atom_value(text)
        Quote:
            let next = try next_token(var m)
            let datum = try datum_from(var m, next)
            return ok(build_quote(var m, datum))

# Reads the datum after a dot, then requires the closing paren.
fn read_tail(var m: Machine) Result[Value, Fault]:
    let tok = try next_token(var m)
    if is_close(tok):
        return error(syntax_fault("bad dotted list"))
    if is_dot(tok):
        return error(syntax_fault("unexpected ."))

    let datum = try datum_from(var m, tok)
    let close = try next_token(var m)
    if is_close(close):
        return ok(datum)
    if is_end(close):
        return error(syntax_fault("unexpected end of input"))

    return error(syntax_fault("bad dotted list"))

fn read_list(var m: Machine) Result[Value, Fault]:
    var items = List[Value]()

    while true:
        let tok = try next_token(var m)
        if is_close(tok):
            return ok(build_list(var m, items, Value.Nil))

        if is_dot(tok):
            if items.is_empty():
                return error(syntax_fault("bad dotted list"))

            let tail = try read_tail(var m)
            return ok(build_list(var m, items, tail))

        let datum = try datum_from(var m, tok)
        items.append(datum)

# ---------- procedures and argument binding ----------

fn parse_params(m: Machine, spec: Value, form: String) Result[Params, Fault]:
    var names = List[String]()
    var rest = spec.clone()

    while true:
        let pid = pair_id_of(rest)
        if pid < 0:
            break

        let p = symbol_name(m.cars[pid])
        if p.is_empty() or names.contains(p):
            return error(bad_form(form))

        names.append(p)
        rest = m.cdrs[pid].clone()

    if is_nil(rest):
        return ok(Params(names: names, rest: false))

    let last = symbol_name(rest)
    if last.is_empty() or names.contains(last):
        return error(bad_form(form))

    names.append(last)
    return ok(Params(names: names, rest: true))

fn parse_bindings(m: Machine, spec: Value, form: String) Result[Bindings, Fault]:
    var names = List[String]()
    var inits = List[Value]()

    if let parts = to_list(m, spec):
        for b in parts:
            if let pair = to_list(m, b.clone()):
                if pair.length() != 2 or symbol_name(pair[0]).is_empty():
                    return error(bad_form(form))

                names.append(symbol_name(pair[0]))
                inits.append(pair[1].clone())
            else:
                return error(bad_form(form))

        return ok(Bindings(names: names, inits: inits))

    return error(bad_form(form))

fn make_closure(
    var m: Machine, name: String, params: Params, body: List[Value], env: Int
) Value:
    if env > m.escape:
        m.escape = env
    m.procs.append(
        Procedure(
            name: name, params: params.names.clone(), rest: params.rest, body: body,
            env: env
        )
    )
    return Value.Closure(m.procs.length() - 1)

# The expressions parts[start..], as a body for a procedure.
fn body_from(parts: List[Value], start: Int) List[Value]:
    var body = List[Value]()
    for i in start..parts.length():
        body.append(parts[i].clone())
    return body

fn make_lambda(var m: Machine, parts: List[Value], env: Int, name: String) Result[
    Value, Fault
]:
    if parts.length() < 3:
        return error(bad_form("lambda"))

    let params = try parse_params(m, parts[1].clone(), "lambda")
    let body = body_from(parts, 2)
    return ok(make_closure(var m, name, params, body, env))

fn bind_args(var m: Machine, id: Int, args: List[Value]) Result[Int, Fault]:
    var name = m.procs[id].name.clone()
    if name.is_empty():
        name = "lambda"

    let rest = m.procs[id].rest
    let count = m.procs[id].params.length()
    var fixed = count
    if rest:
        fixed = count - 1

    let high = if rest: -1 else: fixed

    let _arity = try check_arity(name, fixed, high, args.length())
    var vars = Map[String, Value]()
    for i in 0..fixed:
        vars.add(m.procs[id].params[i].clone(), args[i].clone())

    if rest:
        var extra = List[Value]()
        for i in fixed..args.length():
            extra.append(args[i].clone())

        let packed = build_list(var m, extra, Value.Nil)
        vars.add(m.procs[id].params[fixed].clone(), packed)

    m.frames.append(Frame(vars: vars, parent: m.procs[id].env))
    return ok(m.frames.length() - 1)

# Evaluates all but the last expression of a procedure body in its new frame.
fn run_prefix(var m: Machine, id: Int, frame: Int, depth: Int) Result[Unit, Fault]:
    let last = m.procs[id].body.length() - 1
    for i in 0..last:
        let _ignored = try eval_expr(
            var m, m.procs[id].body[i].clone(), frame, depth, true
        )
    return ok(unit)

# Applies f in a non-tail position of a frame at depth `cur`.
fn apply_proc(var m: Machine, f: Value, args: List[Value], cur: Int) Result[
    Value, Fault
]:
    match f:
        Builtin(name, low, high):
            let _arity = try check_arity(name, low, high, args.length())
            return call_builtin(var m, name, args, cur)
        Closure(id):
            if cur >= MAX_DEPTH:
                return error(rt_fault("recursion limit exceeded"))

            let mark = m.frames.length()
            let frame = try bind_args(var m, id, args)
            let _prefix = try run_prefix(var m, id, frame, cur + 1)
            let last = m.procs[id].body.length() - 1
            let result = eval_expr(
                var m, m.procs[id].body[last].clone(), frame, cur + 1, false
            )
            release(var m, mark)
            return result
        _:
            return error(rt_fault("not a procedure: " + show(m, f, true)))

# Applies f in the position of the current step. `pending` says the step is
# not a tail position of its frame, so entering a body adds one to the depth.
fn apply_tail(
    var m: Machine, f: Value, args: List[Value], var cur: Int, var pending: Bool,
    mark: Int
) Result[Step, Fault]:
    match f:
        Builtin(name, low, high):
            let _arity = try check_arity(name, low, high, args.length())
            let v = try call_builtin(var m, name, args, cur)
            return ok(Step.Done(v))
        Closure(id):
            release(var m, mark)

            let frame = try bind_args(var m, id, args)

            if pending:
                if cur >= MAX_DEPTH:
                    return error(rt_fault("recursion limit exceeded"))

                cur += 1
                pending = false

            let _prefix = try run_prefix(var m, id, frame, cur)
            let last = m.procs[id].body.length() - 1
            return ok(Step.Tail(m.procs[id].body[last].clone(), frame))
        _:
            return error(rt_fault("not a procedure: " + show(m, f, true)))

# ---------- evaluator ----------

# Evaluates expr in env. `depth` is the depth of the frame that contains expr.
# `pending` is true when expr is not a tail position, so that closure calls
# made directly by it enter a body one level deeper.
fn eval_expr(var m: Machine, expr: Value, env: Int, depth: Int, pending: Bool) Result[
    Value, Fault
]:
    let mark = m.frames.length()
    let result = eval_loop(var m, expr, env, depth, pending, mark)
    release(var m, mark)
    return result

fn eval_loop(
    var m: Machine, expr: Value, env: Int, depth: Int, pending: Bool, mark: Int
) Result[Value, Fault]:
    var e = expr.clone()
    var en = env
    var cur = depth
    var pend = pending

    while true:
        let step = try eval_step(var m, e.clone(), en, var cur, var pend, mark)

        match step:
            Done(value):
                return ok(value)
            Tail(next, next_env):
                e = next
                en = next_env

fn eval_step(
    var m: Machine, expr: Value, env: Int, var cur: Int, var pending: Bool, mark: Int
) Result[Step, Fault]:
    match expr:
        Symbol(name):
            if let v = lookup(m, env, name):
                return ok(Step.Done(v))

            return error(rt_fault("unbound variable: " + name))
        PairRef(id):
            return eval_pair(var m, id, env, var cur, var pending, mark)
        Nil:
            return error(syntax_fault("empty application"))
        _:
            return ok(Step.Done(expr.clone()))

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

fn eval_pair(
    var m: Machine, id: Int, env: Int, var cur: Int, var pending: Bool, mark: Int
) Result[Step, Fault]:
    let form = Value.PairRef(id)
    let name = symbol_name(m.cars[id])
    let special = is_special(name)

    if let items = to_list(m, form):
        if special:
            return special_form(var m, name, items, env, var cur, var pending, mark)

        return apply_form(var m, items, env, var cur, var pending, mark)

    if special:
        return error(bad_form(name))

    return error(syntax_fault("bad application"))

fn apply_form(
    var m: Machine, items: List[Value], env: Int, var cur: Int, var pending: Bool,
    mark: Int
) Result[Step, Fault]:
    let op = try eval_expr(var m, items[0].clone(), env, cur, true)
    var args = List[Value]()

    for i in 1..items.length():
        let arg = try eval_expr(var m, items[i].clone(), env, cur, true)
        args.append(arg)

    return apply_tail(var m, op, args, var cur, var pending, mark)

fn eval_all(var m: Machine, exprs: List[Value], env: Int, cur: Int) Result[
    List[Value], Fault
]:
    var out = List[Value]()

    for x in exprs:
        let v = try eval_expr(var m, x.clone(), env, cur, true)
        out.append(v)

    return ok(out)

# Evaluates items[start..] with the last one in tail position.
fn eval_seq(var m: Machine, items: List[Value], start: Int, env: Int, cur: Int) Result[
    Step, Fault
]:
    let last = items.length() - 1
    if start > last:
        return ok(Step.Done(Value.Void))

    var i = start

    while i < last:
        let _ignored = try eval_expr(var m, items[i].clone(), env, cur, true)
        i += 1

    return ok(Step.Tail(items[last].clone(), env))

fn special_form(
    var m: Machine, name: String, items: List[Value], env: Int, var cur: Int,
    var pending: Bool, mark: Int
) Result[Step, Fault]:
    if name == "quote":
        if items.length() != 2:
            return error(bad_form(name))

        return ok(Step.Done(items[1].clone()))

    if name == "if":
        return special_if(var m, items, env, cur)
    if name == "define":
        return special_define(var m, items, env, cur)
    if name == "set!":
        return special_set(var m, items, env, cur)

    if name == "lambda":
        let made = try make_lambda(var m, items, env, "")
        return ok(Step.Done(made))

    if name == "begin":
        return eval_seq(var m, items, 1, env, cur)
    if name == "let":
        return special_let(var m, items, env, var cur, var pending, mark)
    if name == "let*" or name == "letrec":
        return special_letstar(var m, items, env, cur, name)
    if name == "cond":
        return special_cond(var m, items, env, cur)
    if name == "and":
        return special_and(var m, items, env, cur)
    if name == "or":
        return special_or(var m, items, env, cur)
    if name == "when":
        return special_when(var m, items, env, cur, false)
    if name == "unless":
        return special_when(var m, items, env, cur, true)

    return special_try(var m, items, env, cur)

fn special_if(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    let n = items.length()
    if n != 3 and n != 4:
        return error(bad_form("if"))

    let verdict = try eval_expr(var m, items[1].clone(), env, cur, true)
    if truthy(verdict):
        return ok(Step.Tail(items[2].clone(), env))
    if n == 4:
        return ok(Step.Tail(items[3].clone(), env))

    return ok(Step.Done(Value.Void))

fn define_value(var m: Machine, expr: Value, env: Int, cur: Int, name: String) Result[
    Value, Fault
]:
    if let parts = to_list(m, expr.clone()):
        if not parts.is_empty() and symbol_name(parts[0]) == "lambda":
            return make_lambda(var m, parts, env, name)
    return eval_expr(var m, expr, env, cur, true)

fn special_define(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    if items.length() < 2:
        return error(bad_form("define"))

    let target = items[1].clone()
    let tid = pair_id_of(target)

    if tid < 0:
        let name = symbol_name(target)
        if name.is_empty() or items.length() != 3:
            return error(bad_form("define"))

        let value = try define_value(var m, items[2].clone(), env, cur, name.clone())
        m.frames[env].vars.add(name.clone(), value)
        return ok(Step.Done(Value.Void))

    let name = symbol_name(m.cars[tid])
    if name.is_empty() or items.length() < 3:
        return error(bad_form("define"))

    let params = try parse_params(m, m.cdrs[tid].clone(), "define")
    let body = body_from(items, 2)
    let proc = make_closure(var m, name.clone(), params, body, env)
    m.frames[env].vars.add(name, proc)
    return ok(Step.Done(Value.Void))

fn special_set(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    if items.length() != 3 or symbol_name(items[1]).is_empty():
        return error(bad_form("set!"))

    let name = symbol_name(items[1])
    let value = try eval_expr(var m, items[2].clone(), env, cur, true)
    var target = -1
    var e = env

    while e >= 0:
        if m.frames[e].vars.contains(name):
            target = e
            break

        e = m.frames[e].parent

    if target < 0:
        return error(rt_fault("unbound variable: " + name))

    m.frames[target].vars.add(name, value)
    return ok(Step.Done(Value.Void))

fn special_let(
    var m: Machine, items: List[Value], env: Int, var cur: Int, var pending: Bool,
    mark: Int
) Result[Step, Fault]:
    if items.length() < 3:
        return error(bad_form("let"))

    let name = symbol_name(items[1])
    if not name.is_empty():
        return named_let(var m, name, items, env, var cur, var pending, mark)

    let bind = try parse_bindings(m, items[1].clone(), "let")
    let vals = try eval_all(var m, bind.inits, env, cur)
    let frame = new_frame(var m, env)
    for i in 0..bind.names.length():
        m.frames[frame].vars.add(bind.names[i].clone(), vals[i].clone())
    return eval_seq(var m, items, 2, frame, cur)

fn named_let(
    var m: Machine, name: String, items: List[Value], env: Int, var cur: Int,
    var pending: Bool, mark: Int
) Result[Step, Fault]:
    if items.length() < 4:
        return error(bad_form("let"))

    let bind = try parse_bindings(m, items[2].clone(), "let")
    let vals = try eval_all(var m, bind.inits, env, cur)
    let frame = new_frame(var m, env)
    let body = body_from(items, 3)
    let proc = make_closure(
        var m, name.clone(), Params(names: bind.names.clone(), rest: false), body, frame
    )
    m.frames[frame].vars.add(name, proc.clone())
    return apply_tail(var m, proc, vals, var cur, var pending, mark)

fn special_letstar(var m: Machine, items: List[Value], env: Int, cur: Int, form: String) Result[
    Step, Fault
]:
    if items.length() < 3:
        return error(bad_form(form))

    let bind = try parse_bindings(m, items[1].clone(), form)
    let frame = new_frame(var m, env)

    for i in 0..bind.names.length():
        let v = try eval_expr(var m, bind.inits[i].clone(), frame, cur, true)
        m.frames[frame].vars.add(bind.names[i].clone(), v)

    return eval_seq(var m, items, 2, frame, cur)

fn special_cond(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    var i = 1

    while i < items.length():
        if let parts = to_list(m, items[i].clone()):
            if parts.is_empty():
                return error(bad_form("cond"))

            if symbol_name(parts[0]) == "else":
                let is_last = i == items.length() - 1
                if not is_last or parts.length() < 2:
                    return error(bad_form("cond"))

                return eval_seq(var m, parts, 1, env, cur)

            let verdict = try eval_expr(var m, parts[0].clone(), env, cur, true)

            if truthy(verdict):
                if parts.length() == 1:
                    return ok(Step.Done(verdict))

                return eval_seq(var m, parts, 1, env, cur)
        else:
            return error(bad_form("cond"))

        i += 1

    return ok(Step.Done(Value.Void))

fn special_and(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    if items.length() == 1:
        return ok(Step.Done(Value.Boolean(true)))

    var i = 1

    while i < items.length() - 1:
        let v = try eval_expr(var m, items[i].clone(), env, cur, true)
        if not truthy(v):
            return ok(Step.Done(v))

        i += 1

    return ok(Step.Tail(items[items.length() - 1].clone(), env))

fn special_or(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    if items.length() == 1:
        return ok(Step.Done(Value.Boolean(false)))

    var i = 1

    while i < items.length() - 1:
        let v = try eval_expr(var m, items[i].clone(), env, cur, true)
        if truthy(v):
            return ok(Step.Done(v))

        i += 1

    return ok(Step.Tail(items[items.length() - 1].clone(), env))

fn special_when(var m: Machine, items: List[Value], env: Int, cur: Int, negate: Bool) Result[
    Step, Fault
]:
    let name = if negate: "unless" else: "when"

    if items.length() < 3:
        return error(bad_form(name))

    let verdict = try eval_expr(var m, items[1].clone(), env, cur, true)
    if truthy(verdict) != negate:
        return eval_seq(var m, items, 2, env, cur)

    return ok(Step.Done(Value.Void))

fn special_try(var m: Machine, items: List[Value], env: Int, cur: Int) Result[
    Step, Fault
]:
    if items.length() != 3:
        return error(bad_form("try"))

    let attempt = eval_expr(var m, items[1].clone(), env, cur, true)
    if attempt.is_ok():
        return ok(Step.Done(attempt.get().clone()))

    let fault = attempt.err()
    if fault.syntax:
        return error(fault.clone())

    let handler = try eval_expr(var m, items[2].clone(), env, cur, true)
    let message = Value.Text(fault.text.clone())
    let v = try apply_proc(var m, handler, [message], cur)
    return ok(Step.Done(v))

# ---------- equality and arithmetic ----------

fn eq_values(a: Value, b: Value) Bool:
    let ta = tag(a)
    if ta != tag(b):
        return false
    if ta == T_NUMBER or ta == T_BOOLEAN or ta == T_SYMBOL or ta == T_NIL:
        return atom_text(a) == atom_text(b)

    return false

fn atomic_equal(a: Value, b: Value) Bool:
    let ta = tag(a)
    if ta != tag(b):
        return false
    if ta == T_TEXT:
        return text_of(a) == text_of(b)
    if ta == T_CLOSURE:
        return closure_id_of(a) == closure_id_of(b)
    if ta == T_BUILTIN:
        return builtin_name(a) == builtin_name(b)

    return atom_text(a) == atom_text(b)

fn equal_values(m: Machine, a: Value, b: Value) Bool:
    var x = a.clone()
    var y = b.clone()

    while pair_id_of(x) >= 0 and pair_id_of(y) >= 0:
        let px = pair_id_of(x)
        let py = pair_id_of(y)
        if not equal_values(m, m.cars[px].clone(), m.cars[py].clone()):
            return false

        x = m.cdrs[px].clone()
        y = m.cdrs[py].clone()

    if pair_id_of(x) >= 0 or pair_id_of(y) >= 0:
        return false

    return atomic_equal(x, y)

fn add_checked(a: Int, b: Int) Result[Int, Fault]:
    if (b > 0 and a > MAX_INT - b) or (b < 0 and a < MIN_INT - b):
        return error(rt_fault("integer overflow"))

    return ok(a + b)

fn sub_checked(a: Int, b: Int) Result[Int, Fault]:
    if (b < 0 and a > MAX_INT + b) or (b > 0 and a < MIN_INT + b):
        return error(rt_fault("integer overflow"))

    return ok(a - b)

fn mul_checked(a: Int, b: Int) Result[Int, Fault]:
    if a == 0 or b == 0:
        return ok(0)

    var overflow = false

    if a > 0:
        if b > 0:
            overflow = a > MAX_INT / b
        else:
            overflow = b < MIN_INT / a
    else:
        if b > 0:
            overflow = a < MIN_INT / b
        else:
            overflow = a < MAX_INT / b

    if overflow:
        return error(rt_fault("integer overflow"))

    return ok(a * b)

fn quotient_of(a: Int, b: Int) Result[Int, Fault]:
    if b == 0:
        return error(rt_fault("division by zero"))
    if b == -1 and a == MIN_INT:
        return error(rt_fault("integer overflow"))

    return ok(a / b)

fn remainder_of(a: Int, b: Int) Result[Int, Fault]:
    if b == 0:
        return error(rt_fault("division by zero"))
    if b == -1:
        return ok(0)

    return ok(a % b)

fn modulo_of(a: Int, b: Int) Result[Int, Fault]:
    let r = try remainder_of(a, b)
    if r != 0 and ((r < 0) != (b < 0)):
        return ok(r + b)

    return ok(r)

fn compare_ok(name: String, a: Int, b: Int) Bool:
    if name == "=":
        return a == b
    if name == "<":
        return a < b
    if name == ">":
        return a > b
    if name == "<=":
        return a <= b

    return a >= b

fn cxr(m: Machine, name: String, v: Value, ops: String) Result[Value, Fault]:
    var cur = v.clone()

    for op in ops.chars():
        let pid = try pair_of(m, name, cur)

        if op == "a":
            cur = m.cars[pid].clone()
        else:
            cur = m.cdrs[pid].clone()

    return ok(cur)

# ---------- builtins ----------

fn numeric_builtin(m: Machine, name: String, args: List[Value]) Result[Value, Fault]:
    let ns = try ints_of(m, name, args)

    if name == "+":
        var total = 0
        for n in ns:
            total = try add_checked(total, n)
        return ok(Value.Number(total))

    if name == "-":
        if ns.length() == 1:
            return ok(Value.Number(try sub_checked(0, ns[0])))

        let first = ns[0]
        var acc = first
        for i in 1..ns.length():
            acc = try sub_checked(acc, ns[i])
        return ok(Value.Number(acc))

    if name == "*":
        var prod = 1
        for n in ns:
            prod = try mul_checked(prod, n)
        return ok(Value.Number(prod))

    if name == "quotient":
        return ok(Value.Number(try quotient_of(ns[0], ns[1])))
    if name == "remainder":
        return ok(Value.Number(try remainder_of(ns[0], ns[1])))
    if name == "modulo":
        return ok(Value.Number(try modulo_of(ns[0], ns[1])))

    if name == "abs":
        if ns[0] == MIN_INT:
            return error(rt_fault("integer overflow"))
        if ns[0] < 0:
            return ok(Value.Number(-ns[0]))

        return ok(Value.Number(ns[0]))

    if name == "min" or name == "max":
        let first = ns[0]
        var best = first

        for n in ns:
            if name == "min" and n < best:
                best = n
            if name == "max" and n > best:
                best = n

        return ok(Value.Number(best))

    if name == "zero?":
        return ok(Value.Boolean(ns[0] == 0))
    if name == "even?":
        return ok(Value.Boolean(ns[0] % 2 == 0))
    if name == "odd?":
        return ok(Value.Boolean(ns[0] % 2 != 0))

    var holds = true
    for i in 0..ns.length() - 1:
        if not compare_ok(name, ns[i], ns[i + 1]):
            holds = false
    return ok(Value.Boolean(holds))

fn is_numeric_name(name: String) Bool:
    return (
        name == "+"
        or name == "-"
        or name == "*"
        or name == "quotient"
        or name == "remainder"
        or name == "modulo"
        or name == "abs"
        or name == "min"
        or name == "max"
        or name == "zero?"
        or name == "even?"
        or name == "odd?"
        or name == "="
        or name == "<"
        or name == ">"
        or name == "<="
        or name == ">="
    )

fn string_builtin(var m: Machine, name: String, args: List[Value]) Result[Value, Fault]:
    if name == "string-length":
        let s = try str_of(m, name, args[0])
        return ok(Value.Number(s.length()))

    if name == "string-append":
        var acc = ""

        for a in args:
            let s = try str_of(m, name, a)
            acc = acc + s

        return ok(Value.Text(acc))

    if name == "substring":
        let s = try str_of(m, name, args[0])
        let start = try int_of(m, name, args[1])
        let end = try int_of(m, name, args[2])
        if start < 0 or end > s.length() or start > end:
            return error(rt_fault("substring: index out of range"))

        return ok(Value.Text(s.slice(start, end).get()))

    if name == "string-ref":
        let s = try str_of(m, name, args[0])
        let index = try int_of(m, name, args[1])
        if index < 0 or index >= s.length():
            return error(rt_fault("string-ref: index out of range"))

        return ok(Value.Text(s.get(index)))

    if name == "string=?":
        let a = try str_of(m, name, args[0])
        let b = try str_of(m, name, args[1])
        return ok(Value.Boolean(a == b))

    if name == "string<?":
        let a = try str_of(m, name, args[0])
        let b = try str_of(m, name, args[1])
        return ok(Value.Boolean(a.compare(b) < 0))

    if name == "string-upcase":
        let s = try str_of(m, name, args[0])
        return ok(Value.Text(s.upper()))

    if name == "string-downcase":
        let s = try str_of(m, name, args[0])
        return ok(Value.Text(s.lower()))

    if name == "string->number":
        let s = try str_of(m, name, args[0])
        if is_integer_text(s):
            if let n = s.parse_int():
                return ok(Value.Number(n))
        return ok(Value.Boolean(false))

    if name == "number->string":
        let n = try int_of(m, name, args[0])
        return ok(Value.Text("{n}"))

    if name == "string->symbol":
        let s = try str_of(m, name, args[0])
        return ok(Value.Symbol(s))

    if name == "symbol->string":
        if tag(args[0]) != T_SYMBOL:
            return error(wrong_kind(m, name, "symbol", args[0]))

        return ok(Value.Text(symbol_name(args[0])))

    if name == "string->list":
        let s = try str_of(m, name, args[0])
        var out = List[Value]()
        for c in s.chars():
            out.append(Value.Text(c))
        return ok(build_list(var m, out, Value.Nil))

    if name == "list->string":
        let items = try list_of(m, name, args[0])
        var acc = ""

        for item in items:
            let s = try str_of(m, name, item)
            acc = acc + s

        return ok(Value.Text(acc))

    if name == "string-join":
        let items = try list_of(m, name, args[0])
        let sep = try str_of(m, name, args[1])
        var parts = List[String]()

        for item in items:
            let s = try str_of(m, name, item)
            parts.append(s)

        return ok(Value.Text(parts.join(sep)))

    if name == "string-split":
        let s = try str_of(m, name, args[0])
        let sep = try str_of(m, name, args[1])
        if sep.length() != 1:
            return error(rt_fault("string-split: separator must be one character"))

        var out = List[Value]()
        for part in s.split(sep):
            out.append(Value.Text(part))
        return ok(build_list(var m, out, Value.Nil))

    let s = try str_of(m, name, args[0])
    let sub = try str_of(m, name, args[1])
    return ok(Value.Boolean(s.contains(sub)))

fn is_string_name(name: String) Bool:
    return (
        name == "string-length"
        or name == "string-append"
        or name == "substring"
        or name == "string-ref"
        or name == "string=?"
        or name == "string<?"
        or name == "string-upcase"
        or name == "string-downcase"
        or name == "string->number"
        or name == "number->string"
        or name == "string->symbol"
        or name == "symbol->string"
        or name == "string->list"
        or name == "list->string"
        or name == "string-join"
        or name == "string-split"
        or name == "string-contains?"
    )

fn call_builtin(var m: Machine, name: String, args: List[Value], cur: Int) Result[
    Value, Fault
]:
    if is_numeric_name(name):
        return numeric_builtin(m, name, args)
    if is_string_name(name):
        return string_builtin(var m, name, args)
    if name == "not":
        return ok(Value.Boolean(not truthy(args[0])))
    if name == "null?":
        return ok(Value.Boolean(is_nil(args[0])))
    if name == "pair?":
        return ok(Value.Boolean(pair_id_of(args[0]) >= 0))
    if name == "list?":
        return ok(Value.Boolean(to_list(m, args[0]).is_some()))
    if name == "number?":
        return ok(Value.Boolean(tag(args[0]) == T_NUMBER))
    if name == "string?":
        return ok(Value.Boolean(tag(args[0]) == T_TEXT))
    if name == "symbol?":
        return ok(Value.Boolean(tag(args[0]) == T_SYMBOL))
    if name == "boolean?":
        return ok(Value.Boolean(tag(args[0]) == T_BOOLEAN))
    if name == "procedure?":
        return ok(Value.Boolean(is_procedure(args[0])))
    if name == "eq?":
        return ok(Value.Boolean(eq_values(args[0], args[1])))
    if name == "equal?":
        return ok(Value.Boolean(equal_values(m, args[0], args[1])))
    if name == "cons":
        return ok(cons(var m, args[0].clone(), args[1].clone()))

    if name == "car":
        let pid = try pair_of(m, name, args[0])
        return ok(m.cars[pid].clone())

    if name == "cdr":
        let pid = try pair_of(m, name, args[0])
        return ok(m.cdrs[pid].clone())

    if name == "cadr":
        return cxr(m, name, args[0], "da")
    if name == "cddr":
        return cxr(m, name, args[0], "dd")
    if name == "caddr":
        return cxr(m, name, args[0], "dda")

    if name == "set-car!":
        let pid = try pair_of(m, name, args[0])
        m.cars[pid] = args[1].clone()
        return ok(Value.Void)

    if name == "set-cdr!":
        let pid = try pair_of(m, name, args[0])
        m.cdrs[pid] = args[1].clone()
        return ok(Value.Void)

    if name == "list":
        return ok(build_list(var m, args, Value.Nil))

    if name == "length":
        let items = try list_of(m, name, args[0])
        return ok(Value.Number(items.length()))

    if name == "append":
        if args.is_empty():
            return ok(Value.Nil)

        var result = args[args.length() - 1].clone()
        var i = args.length() - 2

        while i >= 0:
            let items = try list_of(m, name, args[i])
            var j = items.length() - 1

            while j >= 0:
                result = cons(var m, items[j].clone(), result)
                j -= 1

            i -= 1

        return ok(result)

    if name == "reverse":
        let items = try list_of(m, name, args[0])
        var acc = Value.Nil
        for x in items:
            acc = cons(var m, x.clone(), acc)
        return ok(acc)

    if name == "list-ref":
        let items = try list_of(m, name, args[0])
        let k = try int_of(m, name, args[1])
        if k < 0 or k >= items.length():
            return error(rt_fault("list-ref: index out of range"))

        return ok(items[k].clone())

    if name == "list-tail":
        let items = try list_of(m, name, args[0])
        let k = try int_of(m, name, args[1])
        if k < 0 or k > items.length():
            return error(rt_fault("list-tail: index out of range"))

        var rest = args[0].clone()

        for i in 0..k:
            let pid = pair_id_of(rest)
            rest = m.cdrs[pid].clone()

        return ok(rest)

    if name == "range":
        let a = try int_of(m, name, args[0])
        let b = try int_of(m, name, args[1])
        var acc = Value.Nil
        var i = b - 1

        while i >= a and b > a:
            acc = cons(var m, Value.Number(i), acc)
            i -= 1

        return ok(acc)

    if name == "assoc":
        let items = try list_of(m, name, args[1])

        for entry in items:
            let pid = try pair_of(m, name, entry)
            if equal_values(m, args[0].clone(), m.cars[pid].clone()):
                return ok(entry.clone())

        return ok(Value.Boolean(false))

    if name == "member":
        let items = try list_of(m, name, args[1])
        var rest = args[1].clone()

        for x in items:
            if equal_values(m, args[0].clone(), x.clone()):
                return ok(rest)

            rest = m.cdrs[pair_id_of(rest)].clone()

        return ok(Value.Boolean(false))

    if name == "map" or name == "for-each":
        if not is_procedure(args[0]):
            return error(wrong_kind(m, name, "procedure", args[0]))

        var lists = List[List[Value]]()
        var shortest = MAX_INT

        for i in 1..args.length():
            let items = try list_of(m, name, args[i])
            if items.length() < shortest:
                shortest = items.length()
            lists.append(items)

        var out = List[Value]()

        for k in 0..shortest:
            var call = List[Value]()
            for j in 0..lists.length():
                call.append(lists[j][k].clone())

            let r = try apply_proc(var m, args[0].clone(), call, cur)
            out.append(r)

        if name == "for-each":
            return ok(Value.Void)

        return ok(build_list(var m, out, Value.Nil))

    if name == "filter":
        if not is_procedure(args[0]):
            return error(wrong_kind(m, name, "procedure", args[0]))

        let items = try list_of(m, name, args[1])
        var out = List[Value]()

        for x in items:
            let keep = try apply_proc(var m, args[0].clone(), [x.clone()], cur)
            if truthy(keep):
                out.append(x.clone())

        return ok(build_list(var m, out, Value.Nil))

    if name == "fold":
        if not is_procedure(args[0]):
            return error(wrong_kind(m, name, "procedure", args[0]))

        let items = try list_of(m, name, args[2])
        var acc = args[1].clone()
        for x in items:
            acc = try apply_proc(var m, args[0].clone(), [acc, x.clone()], cur)
        return ok(acc)

    if name == "foldr":
        if not is_procedure(args[0]):
            return error(wrong_kind(m, name, "procedure", args[0]))

        let items = try list_of(m, name, args[2])
        var acc = args[1].clone()
        var i = items.length() - 1

        while i >= 0:
            acc = try apply_proc(var m, args[0].clone(), [items[i].clone(), acc], cur)
            i -= 1

        return ok(acc)

    if name == "apply":
        if not is_procedure(args[0]):
            return error(wrong_kind(m, name, "procedure", args[0]))

        let last = try list_of(m, name, args[args.length() - 1])
        var call = List[Value]()
        for i in 1..args.length() - 1:
            call.append(args[i].clone())
        for x in last:
            call.append(x.clone())
        return apply_proc(var m, args[0].clone(), call, cur)

    if name == "sort":
        if not is_procedure(args[1]):
            return error(wrong_kind(m, name, "procedure", args[1]))

        let items = try list_of(m, name, args[0])
        let sorted = try merge_sort(var m, items, args[1].clone(), cur)
        return ok(build_list(var m, sorted, Value.Nil))

    if name == "display":
        let text = show(m, args[0], false)
        emit(var m, text)
        return ok(Value.Void)

    if name == "write":
        let text = show(m, args[0], true)
        emit(var m, text)
        return ok(Value.Void)

    if name == "newline":
        emit(var m, "\n")
        return ok(Value.Void)

    if name == "void":
        return ok(Value.Void)

    if name == "error":
        let first = try str_of(m, name, args[0])
        var message = first
        for i in 1..args.length():
            message = message + " " + show(m, args[i], true)
        return error(rt_fault(message))

    return error(rt_fault("unknown builtin: " + name))

# Stable merge sort; less is called as (less later earlier).
fn merge_sort(var m: Machine, items: List[Value], less: Value, cur: Int) Result[
    List[Value], Fault
]:
    if items.length() <= 1:
        return ok(items)

    let mid = items.length() / 2
    var left = List[Value]()
    var right = List[Value]()

    for i in 0..items.length():
        if i < mid:
            left.append(items[i].clone())
        else:
            right.append(items[i].clone())

    let sorted_left = try merge_sort(var m, left, less.clone(), cur)
    let sorted_right = try merge_sort(var m, right, less.clone(), cur)
    var out = List[Value]()
    var i = 0
    var j = 0

    while i < sorted_left.length() and j < sorted_right.length():
        let take_right = try apply_proc(
            var m, less.clone(), [sorted_right[j].clone(), sorted_left[i].clone()], cur
        )

        if truthy(take_right):
            out.append(sorted_right[j].clone())
            j += 1
        else:
            out.append(sorted_left[i].clone())
            i += 1

    while i < sorted_left.length():
        out.append(sorted_left[i].clone())
        i += 1

    while j < sorted_right.length():
        out.append(sorted_right[j].clone())
        j += 1

    return ok(out)

fn install(var m: Machine, name: String, low: Int, high: Int) Unit:
    m.frames[0].vars.add(name.clone(), Value.Builtin(name, low, high))

fn install_builtins(var m: Machine) Unit:
    install(var m, "+", 0, -1)
    install(var m, "-", 1, -1)
    install(var m, "*", 0, -1)
    install(var m, "quotient", 2, 2)
    install(var m, "remainder", 2, 2)
    install(var m, "modulo", 2, 2)
    install(var m, "abs", 1, 1)
    install(var m, "min", 1, -1)
    install(var m, "max", 1, -1)
    install(var m, "=", 2, -1)
    install(var m, "<", 2, -1)
    install(var m, ">", 2, -1)
    install(var m, "<=", 2, -1)
    install(var m, ">=", 2, -1)
    install(var m, "zero?", 1, 1)
    install(var m, "even?", 1, 1)
    install(var m, "odd?", 1, 1)
    install(var m, "not", 1, 1)
    install(var m, "null?", 1, 1)
    install(var m, "pair?", 1, 1)
    install(var m, "list?", 1, 1)
    install(var m, "number?", 1, 1)
    install(var m, "string?", 1, 1)
    install(var m, "symbol?", 1, 1)
    install(var m, "boolean?", 1, 1)
    install(var m, "procedure?", 1, 1)
    install(var m, "eq?", 2, 2)
    install(var m, "equal?", 2, 2)
    install(var m, "cons", 2, 2)
    install(var m, "car", 1, 1)
    install(var m, "cdr", 1, 1)
    install(var m, "cadr", 1, 1)
    install(var m, "cddr", 1, 1)
    install(var m, "caddr", 1, 1)
    install(var m, "set-car!", 2, 2)
    install(var m, "set-cdr!", 2, 2)
    install(var m, "list", 0, -1)
    install(var m, "length", 1, 1)
    install(var m, "append", 0, -1)
    install(var m, "reverse", 1, 1)
    install(var m, "list-ref", 2, 2)
    install(var m, "list-tail", 2, 2)
    install(var m, "range", 2, 2)
    install(var m, "assoc", 2, 2)
    install(var m, "member", 2, 2)
    install(var m, "map", 2, -1)
    install(var m, "for-each", 2, -1)
    install(var m, "filter", 2, 2)
    install(var m, "fold", 3, 3)
    install(var m, "foldr", 3, 3)
    install(var m, "apply", 2, -1)
    install(var m, "sort", 2, 2)
    install(var m, "string-length", 1, 1)
    install(var m, "string-append", 0, -1)
    install(var m, "substring", 3, 3)
    install(var m, "string-ref", 2, 2)
    install(var m, "string=?", 2, 2)
    install(var m, "string<?", 2, 2)
    install(var m, "string-upcase", 1, 1)
    install(var m, "string-downcase", 1, 1)
    install(var m, "string->number", 1, 1)
    install(var m, "number->string", 1, 1)
    install(var m, "string->symbol", 1, 1)
    install(var m, "symbol->string", 1, 1)
    install(var m, "string->list", 1, 1)
    install(var m, "list->string", 1, 1)
    install(var m, "string-join", 2, 2)
    install(var m, "string-split", 2, 2)
    install(var m, "string-contains?", 2, 2)
    install(var m, "display", 1, 1)
    install(var m, "write", 1, 1)
    install(var m, "newline", 0, 0)
    install(var m, "void", 0, 0)
    install(var m, "error", 1, -1)

# ---------- driver ----------

fn run_form(var m: Machine) Result[Unit, Fault]:
    let tok = try next_token(var m)
    let form = try datum_from(var m, tok)
    let _ignored = try eval_expr(var m, form, 0, 0, true)
    return ok(unit)

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var m = Machine(
        input: text.chars(), pos: 0, cars: List[Value](), cdrs: List[Value](),
        frames: List[Frame](), procs: List[Procedure](), clean: true, escape: -1
    )
    let _root = new_frame(var m, -1)
    install_builtins(var m)

    while true:
        skip_space(var m)
        if m.pos >= m.input.length():
            return 0

        let outcome = run_form(var m)

        if outcome.is_error():
            report(var m, outcome.err())
            return 0

    return 0
