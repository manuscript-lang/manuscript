import stdin, stdout, read_all from "@std/io.ms"
import wrapping_add, wrapping_multiply from "@std/math.ms"

MAXI := 9223372036854775807
MINI := -9223372036854775807 - 1
DEPTH_LIMIT := 10000
SPECIAL_COUNT := 15
K_QUOTE := 0
K_IF := 1
K_DEFINE := 2
K_SET := 3
K_LAMBDA := 4
K_BEGIN := 5
K_LET := 6
K_LETSTAR := 7
K_LETREC := 8
K_COND := 9
K_AND := 10
K_OR := 11
K_WHEN := 12
K_UNLESS := 13
K_TRY := 14
K_ELSE := 15
SPECIAL_NAMES := [
    "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond",
    "and", "or", "when", "unless", "try", "else"
]
BUILTIN_NAMES := [
    "+", "-", "*", "quotient", "remainder", "modulo", "abs", "min", "max", "=", "<",
    ">", "<=", ">=", "zero?", "even?", "odd?", "not", "null?", "pair?", "list?",
    "number?", "string?", "symbol?", "boolean?", "procedure?", "eq?", "equal?", "cons",
    "car", "cdr", "cadr", "cddr", "caddr", "set-car!", "set-cdr!", "list", "length",
    "append", "reverse", "list-ref", "list-tail", "range", "assoc", "member", "map",
    "for-each", "filter", "fold", "foldr", "apply", "sort", "string-length",
    "string-append", "substring", "string-ref", "string=?", "string<?", "string-upcase",
    "string-downcase", "string->number", "number->string", "string->symbol",
    "symbol->string", "string->list", "list->string", "string-join", "string-split",
    "string-contains?", "display", "write", "newline", "void", "error"
]

type Value:
    case Empty
    case Unspecified
    case Flag(flag: Bool)
    case Num(n: Int)
    case Text(s: String)
    case Sym(id: Int)
    case Cons(id: Int)
    case Prim(name: String)
    case Proc(id: Int)

type Fail:
    msg: String
    syntax: Bool

impl Error for Fail:
    fn message() String:
        return self.msg.clone()

type Closure:
    name: String
    params: List[Int]
    rest: Int
    body: Value
    env: Int

// One evaluation step: either a finished value, or an expression to continue with in the same loop.
type Step:
    done: Bool
    value: Value
    expr: Value
    env: Int
    depth: Int
    tail: Bool

type Binds:
    names: List[Int]
    inits: List[Value]

type Machine:
    chars: List[String]
    pos: Int
    cars: List[Value]
    cdrs: List[Value]
    closures: List[Closure]
    frame_parent: List[Int]
    frame_first: List[Int]
    bind_sym: List[Int]
    bind_val: List[Value]
    bind_next: List[Int]
    global_slot: List[Int]
    sym_names: List[String]
    sym_ids: Map[String, Int]
    fresh: Bool

fn finish(v: Value) Step:
    return Step(done: true, value: v, expr: Value.Empty, env: 0, depth: 0, tail: false)

fn resume(expr: Value, env: Int, depth: Int, tail: Bool) Step:
    return Step(
        done: false, value: Value.Empty, expr: expr, env: env, depth: depth, tail: tail
    )

fn runtime_error(msg: String) Fail:
    return Fail(msg: msg, syntax: false)

fn syntax_error(msg: String) Fail:
    return Fail(msg: "syntax error: " + msg, syntax: true)

fn bad_form(kw: String) Fail:
    return syntax_error("bad form: " + kw)

fn truthy(v: Value) Bool:
    match v:
        Flag(flag):
            return flag
        _:
            return true

fn is_delim(c: String) Bool:
    return (
        c == ""
        or c == " "
        or c == "\t"
        or c == "\n"
        or c == "\r"
        or c == "("
        or c == ")"
        or c == "\""
        or c == ";"
    )

fn is_int_text(text: String) Bool:
    cs := text.chars()
    var i = 0
    if cs.length() > 0 and cs[0] == "-":
        i = 1
    if i >= cs.length():
        return false

    while i < cs.length():
        if not (cs[i] >= "0" and cs[i] <= "9"):
            return false

        i += 1

    return true

fn add_int(a: Int, b: Int) Result[Int, Fail]:
    r := wrapping_add(a, b)
    if (b > 0 and r < a) or (b < 0 and r > a):
        return error(runtime_error("integer overflow"))

    return ok(r)

fn sub_int(a: Int, b: Int) Result[Int, Fail]:
    if (b < 0 and a > MAXI + b) or (b > 0 and a < MINI + b):
        return error(runtime_error("integer overflow"))

    return ok(a - b)

fn mul_int(a: Int, b: Int) Result[Int, Fail]:
    if a == 0 or b == 0:
        return ok(0)

    if a == -1:
        if b == MINI:
            return error(runtime_error("integer overflow"))

        return ok(-b)

    if b == -1:
        if a == MINI:
            return error(runtime_error("integer overflow"))

        return ok(-a)

    r := wrapping_multiply(a, b)
    if r / a != b:
        return error(runtime_error("integer overflow"))

    return ok(r)

fn compare_holds(name: String, a: Int, b: Int) Bool:
    if name == "=":
        return a == b
    if name == "<":
        return a < b
    if name == ">":
        return a > b
    if name == "<=":
        return a <= b

    return a >= b

impl Machine:
    var fn install() Result[Unit, Fail]:
        _root := self.new_frame(-1)
        for name in SPECIAL_NAMES:
            _s := self.intern(name.clone())

        for name in BUILTIN_NAMES:
            id := self.intern(name.clone())
            self.define_in(0, id, Value.Prim(name.clone()))

        return ok(unit)

    var fn intern(name: String) Int:
        if known := self.sym_ids.get(name.clone()):
            return known

        id := self.sym_names.length()
        self.sym_names.append(name.clone())
        self.global_slot.append(-1)
        self.sym_ids[name.clone()] = id
        return id

    var fn emit(s: String) Unit:
        if s.length() == 0:
            return

        self.fresh = s.ends_with("\n")
        stdout().write(s).get()

    var fn report(msg: String) Unit:
        if not self.fresh:
            self.emit("\n")
        self.emit("error: " + msg + "\n")

    // ---- heap: pairs, closures, frames -------------------------------------------------

    var fn cons(a: Value, d: Value) Value:
        self.cars.append(a)
        self.cdrs.append(d)
        return Value.Cons(self.cars.length() - 1)

    var fn cons_id(v: Value) Int:
        match v:
            Cons(id):
                return id
            _:
                return -1

    var fn sym_id(v: Value) Int:
        match v:
            Sym(id):
                return id
            _:
                return -1

    var fn proc_id(v: Value) Int:
        match v:
            Proc(id):
                return id
            _:
                return -1

    var fn prim_name(v: Value) String:
        match v:
            Prim(name):
                return name
            _:
                return ""

    var fn is_empty(v: Value) Bool:
        match v:
            Empty:
                return true
            _:
                return false

    var fn car(v: Value) Value:
        id := self.cons_id(v)
        if id < 0:
            return Value.Empty

        return self.cars[id].clone()

    var fn cdr(v: Value) Value:
        id := self.cons_id(v)
        if id < 0:
            return Value.Empty

        return self.cdrs[id].clone()

    var fn is_form(v: Value, kind: Int) Bool:
        return self.sym_id(self.car(v)) == kind

    var fn is_proper(v: Value) Bool:
        var cur = v.clone()

        while true:
            id := self.cons_id(cur.clone())
            if id < 0:
                return self.is_empty(cur)

            cur = self.cdrs[id].clone()

    var fn list_of(v: Value) List[Value]:
        var out = List[Value]()
        var cur = v.clone()

        while true:
            id := self.cons_id(cur.clone())
            if id < 0:
                return out

            out.append(self.cars[id].clone())
            cur = self.cdrs[id].clone()

    var fn build(items: List[Value], tail: Value) Value:
        var out = tail
        var i = items.length()

        while i > 0:
            i -= 1
            out = self.cons(items[i].clone(), out)

        return out

    var fn from_list(items: List[Value]) Value:
        return self.build(items, Value.Empty)

    var fn new_frame(parent: Int) Int:
        self.frame_parent.append(parent)
        self.frame_first.append(-1)
        return self.frame_parent.length() - 1

    var fn find_in_frame(frame: Int, sym: Int) Int:
        if frame == 0:
            return self.global_slot[sym]

        start := self.frame_first[frame]
        var b = start

        while b >= 0:
            if self.bind_sym[b] == sym:
                return b

            b = self.bind_next[b]

        return -1

    var fn define_in(frame: Int, sym: Int, val: Value) Unit:
        slot := self.find_in_frame(frame, sym)

        if slot >= 0:
            self.bind_val[slot] = val
            return

        idx := self.bind_sym.length()
        self.bind_sym.append(sym)
        self.bind_val.append(val)

        if frame == 0:
            self.bind_next.append(-1)
            self.global_slot[sym] = idx
        else:
            self.bind_next.append(self.frame_first[frame])
            self.frame_first[frame] = idx

    var fn lookup(env: Int, sym: Int) Int:
        var f = env

        while f >= 0:
            slot := self.find_in_frame(f, sym)
            if slot >= 0:
                return slot

            f = self.frame_parent[f]

        return -1

    var fn make_closure(
        params: Value,
        body: Value,
        env: Int,
        name: String,
        kw: String
    ) Result[Value, Fail]:
        var ids = List[Int]()
        var rest = -1
        var cur = params.clone()

        while true:
            id := self.cons_id(cur.clone())
            if id < 0:
                break

            s := self.sym_id(self.car(cur.clone()))
            if s < 0 or ids.contains(s):
                return error(bad_form(kw))

            ids.append(s)
            cur = self.cdr(cur.clone())

        if not self.is_empty(cur.clone()):
            rest = self.sym_id(cur.clone())
            if rest < 0 or ids.contains(rest):
                return error(bad_form(kw))

        self.closures.append(
            Closure(
                name: name, params: ids, rest: rest, body: body, env: env
            )
        )
        return ok(Value.Proc(self.closures.length() - 1))

    var fn bind_args(id: Int, args: List[Value]) Result[Int, Fail]:
        n := self.closures[id].params.length()
        count := args.length()

        if count < n or (self.closures[id].rest < 0 and count > n):
            var who = self.closures[id].name.clone()
            if who == "":
                who = "lambda"

            var expected = "{n}"
            if self.closures[id].rest >= 0:
                expected = "at least {n}"
            return error(
                runtime_error(
                    "wrong number of arguments to {who}: expected {expected}, got {count}"
                )
            )

        frame := self.new_frame(self.closures[id].env)
        for i in 0..n:
            self.define_in(frame, self.closures[id].params[i], args[i].clone())

        if self.closures[id].rest >= 0:
            var extra = List[Value]()
            for i in n..count:
                extra.append(args[i].clone())

            rest_list := self.from_list(extra)
            self.define_in(frame, self.closures[id].rest, rest_list)

        return ok(frame)

    // ---- printing ----------------------------------------------------------------------

    var fn write_string(s: String) String:
        var out = "\""

        for c in s.chars():
            if c == "\\":
                out += "\\\\"
            else if c == "\"":
                out += "\\\""
            else if c == "\n":
                out += "\\n"
            else if c == "\t":
                out += "\\t"
            else:
                out += c.clone()

        return out + "\""

    var fn render(v: Value, write: Bool) String:
        match v:
            Empty:
                return "()"
            Unspecified:
                return "#<void>"
            Flag(flag):
                if flag:
                    return "#t"

                return "#f"
            Num(n):
                return "{n}"
            Text(s):
                if write:
                    return self.write_string(s)

                return s
            Sym(id):
                return self.sym_names[id].clone()
            Cons(id):
                return self.render_list(id, write)
            Prim(name):
                return "#<builtin {name}>"
            Proc(id):
                name := self.closures[id].name.clone()
                if name == "":
                    return "#<procedure>"

                return "#<procedure {name}>"

    var fn render_list(first: Int, write: Bool) String:
        var out = "("
        var id = first

        while true:
            out += self.render(self.cars[id].clone(), write)

            rest := self.cdrs[id].clone()
            next_id := self.cons_id(rest.clone())

            if next_id >= 0:
                out += " "
                id = next_id
                continue

            if not self.is_empty(rest.clone()):
                out += " . " + self.render(rest, write)
            return out + ")"

    // ---- reader ------------------------------------------------------------------------

    var fn peek() String:
        if self.pos < self.chars.length():
            return self.chars[self.pos].clone()

        return ""

    var fn peek_next() String:
        if self.pos + 1 < self.chars.length():
            return self.chars[self.pos + 1].clone()

        return ""

    var fn skip_space() Unit:
        while self.pos < self.chars.length():
            c := self.peek()

            if c == ";":
                while self.peek() != "\n" and self.peek() != "":
                    self.pos += 1
            else if c == " " or c == "\t" or c == "\n" or c == "\r":
                self.pos += 1
            else:
                return

    var fn read_datum() Result[Value, Fail]:
        self.skip_space()

        c := self.peek()
        if c == "":
            return error(syntax_error("unexpected end of input"))

        if c == "(":
            self.pos += 1
            return self.read_list()

        if c == ")":
            return error(syntax_error("unexpected )"))

        if c == "'":
            self.pos += 1

            quoted := try self.read_datum()
            tail := self.cons(quoted, Value.Empty)
            return ok(self.cons(Value.Sym(K_QUOTE), tail))

        if c == "\"":
            return self.read_string()

        return self.read_atom()

    var fn read_list() Result[Value, Fail]:
        var items = List[Value]()
        var tail = Value.Empty

        while true:
            self.skip_space()

            c := self.peek()
            if c == "":
                return error(syntax_error("unexpected end of input"))

            if c == ")":
                self.pos += 1
                break

            if c == "." and is_delim(self.peek_next()):
                if items.length() == 0:
                    return error(syntax_error("bad dotted list"))

                self.pos += 1
                self.skip_space()
                if self.peek() == ")":
                    return error(syntax_error("bad dotted list"))

                tail = try self.read_datum()
                self.skip_space()

                e := self.peek()
                if e == "":
                    return error(syntax_error("unexpected end of input"))
                if e != ")":
                    return error(syntax_error("bad dotted list"))

                self.pos += 1
                break

            item := try self.read_datum()
            items.append(item)

        return ok(self.build(items, tail))

    var fn read_string() Result[Value, Fail]:
        self.pos += 1

        var out = ""

        while true:
            c := self.peek()
            if c == "":
                return error(syntax_error("unterminated string"))

            self.pos += 1
            if c == "\"":
                break

            if c == "\\":
                e := self.peek()
                if e == "":
                    return error(syntax_error("unterminated string"))

                self.pos += 1

                if e == "n":
                    out += "\n"
                else if e == "t":
                    out += "\t"
                else if e == "\\":
                    out += "\\"
                else if e == "\"":
                    out += "\""
                else:
                    return error(syntax_error("bad escape"))
            else:
                out += c

        return ok(Value.Text(out))

    var fn read_atom() Result[Value, Fail]:
        var text = ""

        while not is_delim(self.peek()):
            text += self.peek()
            self.pos += 1

        if text == "#t":
            return ok(Value.Flag(true))
        if text == "#f":
            return ok(Value.Flag(false))
        if text.starts_with("#"):
            return error(syntax_error("bad token: " + text))
        if text == ".":
            return error(syntax_error("unexpected ."))

        if is_int_text(text):
            if n := text.parse_int():
                return ok(Value.Num(n))

            return error(syntax_error("integer out of range"))

        return ok(Value.Sym(self.intern(text)))

    var fn program() Result[Unit, Fail]:
        while true:
            self.skip_space()
            if self.pos >= self.chars.length():
                return ok(unit)

            form := try self.read_datum()
            _v := try self.run(form, 0, 0, false)

    // ---- evaluator ---------------------------------------------------------------------

    // Evaluates `expr`. `tail` says whether this loop is a procedure body (a call here
    // replaces the frame, so depth stays) or a sub-expression (a call here goes one deeper).
    var fn run(expr: Value, env: Int, depth: Int, tail: Bool) Result[Value, Fail]:
        var form = expr
        var frame = env
        var level = depth
        var in_tail = tail

        while true:
            step := try self.step(form.clone(), frame, level, in_tail)
            if step.done:
                return ok(step.value.clone())

            form = step.expr.clone()
            frame = step.env
            level = step.depth
            in_tail = step.tail

    var fn step(form: Value, env: Int, depth: Int, tail: Bool) Result[Step, Fail]:
        sym := self.sym_id(form.clone())

        if sym >= 0:
            slot := self.lookup(env, sym)
            if slot < 0:
                return error(
                    runtime_error(
                        "unbound variable: " + self.sym_names[
                            sym
                        ].clone()
                    )
                )

            return ok(finish(self.bind_val[slot].clone()))

        cid := self.cons_id(form.clone())

        if cid < 0:
            if self.is_empty(form.clone()):
                return error(syntax_error("empty application"))

            return ok(finish(form))

        head := self.sym_id(self.cars[cid].clone())
        if head >= 0 and head < SPECIAL_COUNT:
            return self.special(head, form, env, depth, tail)

        return self.apply_form(form, env, depth, tail)

    var fn apply_form(form: Value, env: Int, depth: Int, tail: Bool) Result[Step, Fail]:
        if not self.is_proper(form.clone()):
            return error(syntax_error("bad application"))

        items := self.list_of(form)
        callee := try self.run(items[0].clone(), env, depth, false)
        var args = List[Value]()

        for i in 1..items.length():
            arg := try self.run(items[i].clone(), env, depth, false)
            args.append(arg)

        return self.apply_value(callee, args, depth, tail)

    var fn apply_value(
        callee: Value,
        args: List[Value],
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        pid := self.proc_id(callee.clone())

        if pid >= 0:
            var level = depth
            if not tail:
                level = depth + 1
            if level > DEPTH_LIMIT:
                return error(runtime_error("recursion limit exceeded"))

            frame := try self.bind_args(pid, args)
            body := self.closures[pid].body.clone()
            last := try self.run_init(body, frame, level)
            return ok(resume(last, frame, level, true))

        pname := self.prim_name(callee.clone())

        if pname != "":
            result := try self.call_prim(pname, args, depth + 1)
            return ok(finish(result))

        return error(runtime_error("not a procedure: " + self.render(callee, true)))

    // Calls a procedure from inside a builtin; `d` is the depth of the callee's body.
    var fn call_proc(callee: Value, args: List[Value], d: Int) Result[Value, Fail]:
        pid := self.proc_id(callee.clone())

        if pid < 0:
            pname := self.prim_name(callee.clone())
            if pname != "":
                return self.call_prim(pname, args, d)

            return error(runtime_error("not a procedure: " + self.render(callee, true)))

        if d > DEPTH_LIMIT:
            return error(runtime_error("recursion limit exceeded"))

        frame := try self.bind_args(pid, args)
        body := self.closures[pid].body.clone()
        last := try self.run_init(body, frame, d)
        return self.run(last, frame, d, true)

    // Evaluates all forms of a body but the last, and returns the last one unevaluated.
    var fn run_init(forms: Value, env: Int, depth: Int) Result[Value, Fail]:
        var cur = forms.clone()

        while true:
            id := self.cons_id(cur.clone())
            if id < 0:
                return ok(Value.Unspecified)

            head := self.cars[id].clone()
            rest := self.cdrs[id].clone()
            if self.is_empty(rest.clone()):
                return ok(head)

            _v := try self.run(head, env, depth, false)
            cur = rest

    var fn parse_binds(bindings: Value, kw: String) Result[Binds, Fail]:
        if not self.is_proper(bindings.clone()):
            return error(bad_form(kw))

        var names = List[Int]()
        var inits = List[Value]()

        for b in self.list_of(bindings):
            if not self.is_proper(b.clone()):
                return error(bad_form(kw))

            parts := self.list_of(b.clone())
            if parts.length() != 2 or self.sym_id(parts[0].clone()) < 0:
                return error(bad_form(kw))

            names.append(self.sym_id(parts[0].clone()))
            inits.append(parts[1].clone())

        return ok(Binds(names: names, inits: inits))

    var fn special(
        kind: Int,
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        name := self.sym_names[kind].clone()
        if not self.is_proper(form.clone()):
            return error(bad_form(name))

        items := self.list_of(form.clone())
        if kind <= K_BEGIN:
            return self.special_core(kind, items, form, env, depth, tail)
        if kind <= K_LETREC:
            return self.special_bind(kind, items, form, env, depth, tail)

        return self.special_control(kind, items, form, env, depth, tail)

    var fn special_core(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        name := self.sym_names[kind].clone()
        n := items.length()

        if kind == K_QUOTE:
            if n != 2:
                return error(bad_form(name))

            return ok(finish(items[1].clone()))

        if kind == K_IF:
            if n != 3 and n != 4:
                return error(bad_form(name))

            verdict := try self.run(items[1].clone(), env, depth, false)
            if truthy(verdict):
                return ok(resume(items[2].clone(), env, depth, tail))
            if n == 4:
                return ok(resume(items[3].clone(), env, depth, tail))

            return ok(finish(Value.Unspecified))

        if kind == K_DEFINE:
            if n < 3:
                return error(bad_form(name))

            target := self.sym_id(items[1].clone())

            if target >= 0:
                if n != 3:
                    return error(bad_form(name))

                var value = Value.Unspecified

                if self.is_form(items[2].clone(), K_LAMBDA):
                    value = try self.lambda_value(
                        items[2].clone(), env, self.sym_names[target].clone()
                    )
                else:
                    value = try self.run(items[2].clone(), env, depth, false)

                self.define_in(env, target, value)
                return ok(finish(Value.Unspecified))

            fname := self.sym_id(self.car(items[1].clone()))
            if fname < 0:
                return error(bad_form(name))

            params := self.cdr(items[1].clone())
            body := self.cdr(self.cdr(form.clone()))
            proc := try self.make_closure(
                params, body, env, self.sym_names[fname].clone(), name
            )
            self.define_in(env, fname, proc)
            return ok(finish(Value.Unspecified))

        if kind == K_SET:
            target := self.sym_id(items[1].clone())
            if n != 3 or target < 0:
                return error(bad_form(name))

            value := try self.run(items[2].clone(), env, depth, false)
            slot := self.lookup(env, target)
            if slot < 0:
                return error(
                    runtime_error(
                        "unbound variable: " + self.sym_names[
                            target
                        ].clone()
                    )
                )

            self.bind_val[slot] = value
            return ok(finish(Value.Unspecified))

        if kind == K_LAMBDA:
            if n < 3:
                return error(bad_form(name))

            proc := try self.make_closure(
                items[1].clone(), self.cdr(self.cdr(form.clone())), env, "", name
            )
            return ok(finish(proc))

        if kind == K_BEGIN:
            if n == 1:
                return ok(finish(Value.Unspecified))

            last := try self.run_init(self.cdr(form), env, depth)
            return ok(resume(last, env, depth, tail))

        return error(bad_form(name))

    var fn special_bind(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        name := self.sym_names[kind].clone()
        n := items.length()

        if kind == K_LET:
            if n < 3:
                return error(bad_form(name))
            if self.sym_id(items[1].clone()) >= 0:
                return self.named_let(form, items, env, depth, tail)

            binds := try self.parse_binds(items[1].clone(), name)
            var vals = List[Value]()

            for init in binds.inits:
                v := try self.run(init.clone(), env, depth, false)
                vals.append(v)

            frame := self.new_frame(env)
            for i in 0..vals.length():
                self.define_in(frame, binds.names[i], vals[i].clone())

            last := try self.run_init(self.cdr(self.cdr(form)), frame, depth)
            return ok(resume(last, frame, depth, tail))

        if kind == K_LETSTAR or kind == K_LETREC:
            if n < 3:
                return error(bad_form(name))

            binds := try self.parse_binds(items[1].clone(), name)
            frame := self.new_frame(env)

            for i in 0..binds.names.length():
                v := try self.run(binds.inits[i].clone(), frame, depth, false)
                self.define_in(frame, binds.names[i], v)

            last := try self.run_init(self.cdr(self.cdr(form)), frame, depth)
            return ok(resume(last, frame, depth, tail))

        return error(bad_form(name))

    var fn special_control(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        name := self.sym_names[kind].clone()
        n := items.length()

        if kind == K_COND:
            var i = 1

            while i < n:
                clause := items[i].clone()
                if not self.is_proper(clause.clone()) or self.is_empty(clause.clone()):
                    return error(bad_form(name))

                parts := self.list_of(clause.clone())

                if self.sym_id(parts[0].clone()) == K_ELSE:
                    if i != n - 1 or parts.length() < 2:
                        return error(bad_form(name))

                    last := try self.run_init(self.cdr(clause), env, depth)
                    return ok(resume(last, env, depth, tail))

                verdict := try self.run(parts[0].clone(), env, depth, false)

                if truthy(verdict):
                    if parts.length() == 1:
                        return ok(finish(verdict))

                    last := try self.run_init(self.cdr(clause), env, depth)
                    return ok(resume(last, env, depth, tail))

                i += 1

            return ok(finish(Value.Unspecified))

        if kind == K_AND or kind == K_OR:
            if n == 1:
                return ok(finish(Value.Flag(kind == K_AND)))

            for i in 1..n - 1:
                v := try self.run(items[i].clone(), env, depth, false)
                if kind == K_AND and not truthy(v.clone()):
                    return ok(finish(v))
                if kind == K_OR and truthy(v.clone()):
                    return ok(finish(v))

            return ok(resume(items[n - 1].clone(), env, depth, tail))

        if kind == K_WHEN or kind == K_UNLESS:
            if n < 3:
                return error(bad_form(name))

            verdict := try self.run(items[1].clone(), env, depth, false)
            var fire = truthy(verdict)
            if kind == K_UNLESS:
                fire = not fire
            if not fire:
                return ok(finish(Value.Unspecified))

            last := try self.run_init(self.cdr(self.cdr(form)), env, depth)
            return ok(resume(last, env, depth, tail))

        if kind == K_TRY:
            if n != 3:
                return error(bad_form(name))

            outcome := self.run(items[1].clone(), env, depth, false)

            if outcome.is_error():
                failure := outcome.err()
                if failure.syntax:
                    return error(failure.clone())

                handler := try self.run(items[2].clone(), env, depth, false)
                var msg_args = List[Value]()
                msg_args.append(Value.Text(failure.msg.clone()))

                handled := try self.call_proc(handler, msg_args, depth + 1)
                return ok(finish(handled))

            value := try outcome
            return ok(finish(value))

        return error(bad_form(name))

    var fn lambda_value(form: Value, env: Int, name: String) Result[Value, Fail]:
        items := self.list_of(form.clone())
        if items.length() < 3:
            return error(bad_form("lambda"))

        return self.make_closure(
            items[1].clone(), self.cdr(self.cdr(form)), env, name, "lambda"
        )

    var fn named_let(
        form: Value,
        items: List[Value],
        env: Int,
        depth: Int,
        tail: Bool
    ) Result[Step, Fail]:
        if items.length() < 4:
            return error(bad_form("let"))

        loop_sym := self.sym_id(items[1].clone())
        binds := try self.parse_binds(items[2].clone(), "let")
        var args = List[Value]()

        for init in binds.inits:
            v := try self.run(init.clone(), env, depth, false)
            args.append(v)

        frame := self.new_frame(env)
        params := self.sym_values(binds.names)
        proc := try self.make_closure(
            params, self.cdr(self.cdr(self.cdr(form))), frame,
            self.sym_names[loop_sym].clone(), "let"
        )
        self.define_in(frame, loop_sym, proc.clone())
        return self.apply_value(proc, args, depth, tail)

    var fn sym_values(ids: List[Int]) Value:
        var out = List[Value]()
        for id in ids:
            out.append(Value.Sym(id))
        return self.from_list(out)

    // ---- argument helpers for builtins -------------------------------------------------

    var fn type_error(name: String, kind: String, v: Value) Fail:
        return runtime_error("{name}: expected {kind}, got {self.render(v, true)}")

    var fn want(name: String, count: Int, lo: Int, hi: Int) Result[Unit, Fail]:
        if count < lo or (hi >= 0 and count > hi):
            var expected = "{lo}"

            if hi < 0:
                expected = "at least {lo}"
            else if lo != hi:
                expected = "{lo} to {hi}"

            return error(
                runtime_error(
                    "wrong number of arguments to {name}: expected {expected}, got {count}"
                )
            )

        return ok(unit)

    var fn need_int(name: String, v: Value) Result[Int, Fail]:
        match v.clone():
            Num(n):
                return ok(n)
            _:
                return error(self.type_error(name, "integer", v))

    var fn need_str(name: String, v: Value) Result[String, Fail]:
        match v.clone():
            Text(s):
                return ok(s)
            _:
                return error(self.type_error(name, "string", v))

    var fn need_sym(name: String, v: Value) Result[Int, Fail]:
        id := self.sym_id(v.clone())
        if id < 0:
            return error(self.type_error(name, "symbol", v))

        return ok(id)

    var fn need_pair(name: String, v: Value) Result[Int, Fail]:
        id := self.cons_id(v.clone())
        if id < 0:
            return error(self.type_error(name, "pair", v))

        return ok(id)

    var fn need_proc(name: String, v: Value) Result[Value, Fail]:
        if self.proc_id(v.clone()) >= 0 or self.prim_name(v.clone()) != "":
            return ok(v)

        return error(self.type_error(name, "procedure", v))

    var fn need_list(name: String, v: Value) Result[List[Value], Fail]:
        if not self.is_proper(v.clone()):
            return error(self.type_error(name, "list", v))

        return ok(self.list_of(v))

    var fn int_args(name: String, args: List[Value]) Result[List[Int], Fail]:
        var out = List[Int]()

        for a in args:
            x := try self.need_int(name, a.clone())
            out.append(x)

        return ok(out)

    var fn atom_key(v: Value) String:
        match v:
            Empty:
                return "e"
            Flag(flag):
                if flag:
                    return "bt"

                return "bf"
            Num(n):
                return "n{n}"
            Sym(id):
                return "s{id}"
            _:
                return ""

    var fn leaf_key(v: Value) String:
        match v:
            Text(s):
                return "t" + s
            Proc(id):
                return "p{id}"
            Prim(name):
                return "q" + name
            Unspecified:
                return "v"
            _:
                return self.atom_key(v)

    var fn equal_values(a0: Value, b0: Value) Bool:
        var a = a0
        var b = b0

        while true:
            ia := self.cons_id(a.clone())
            ib := self.cons_id(b.clone())

            if ia < 0 and ib < 0:
                ka := self.leaf_key(a)
                return ka != "" and ka == self.leaf_key(b)

            if ia < 0 or ib < 0:
                return false
            if not self.equal_values(self.car(a.clone()), self.car(b.clone())):
                return false

            a = self.cdr(a)
            b = self.cdr(b)

    var fn cxr(name: String, v: Value, ops: String) Result[Value, Fail]:
        var cur = v
        letters := ops.chars()
        var k = letters.length()

        while k > 0:
            k -= 1

            id := try self.need_pair(name, cur.clone())

            if letters[k] == "a":
                cur = self.cars[id].clone()
            else:
                cur = self.cdrs[id].clone()

        return ok(cur)

    var fn sort_list(items: List[Value], less: Value, d: Int) Result[List[Value], Fail]:
        if items.length() <= 1:
            return ok(items)

        mid := items.length() / 2
        var left = List[Value]()
        var right = List[Value]()

        for i in 0..items.length():
            if i < mid:
                left.append(items[i].clone())
            else:
                right.append(items[i].clone())

        ls := try self.sort_list(left, less.clone(), d)
        rs := try self.sort_list(right, less.clone(), d)
        var out = List[Value]()
        var i = 0
        var j = 0

        while i < ls.length() and j < rs.length():
            takes_right := try self.call_proc(
                less.clone(), [rs[j].clone(), ls[i].clone()], d
            )

            if truthy(takes_right):
                out.append(rs[j].clone())
                j += 1
            else:
                out.append(ls[i].clone())
                i += 1

        while i < ls.length():
            out.append(ls[i].clone())
            i += 1

        while j < rs.length():
            out.append(rs[j].clone())
            j += 1

        return ok(out)

    // ---- builtins ----------------------------------------------------------------------

    var fn call_prim(name: String, args: List[Value], d: Int) Result[Value, Fail]:
        numbers_result := try self.prim_numbers(name, args, d)
        if found := numbers_result:
            return ok(found)

        predicates_result := try self.prim_predicates(name, args, d)
        if found := predicates_result:
            return ok(found)

        lists_result := try self.prim_lists(name, args, d)
        if found := lists_result:
            return ok(found)

        hof_result := try self.prim_hof(name, args, d)
        if found := hof_result:
            return ok(found)

        strings_result := try self.prim_strings(name, args, d)
        if found := strings_result:
            return ok(found)

        misc_result := try self.prim_misc(name, args, d)
        if found := misc_result:
            return ok(found)

        return error(runtime_error("unknown builtin: " + name))

    var fn prim_numbers(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "+":
            var xs = try self.int_args(name, args)
            var total = 0
            for x in xs:
                total = try add_int(total, x)
            return ok(Value.Num(total))

        if name == "*":
            var xs = try self.int_args(name, args)
            var product = 1
            for x in xs:
                product = try mul_int(product, x)
            return ok(Value.Num(product))

        if name == "-":
            _c := try self.want(name, n, 1, -1)
            var xs = try self.int_args(name, args)
            if xs.length() == 1:
                return ok(Value.Num(try sub_int(0, xs[0])))

            var diff = 0

            for i in 0..xs.length():
                if i == 0:
                    diff = xs[0]
                else:
                    diff = try sub_int(diff, xs[i])

            return ok(Value.Num(diff))

        if name == "quotient" or name == "remainder" or name == "modulo":
            _c := try self.want(name, n, 2, 2)
            a := try self.need_int(name, args[0].clone())
            b := try self.need_int(name, args[1].clone())
            if b == 0:
                return error(runtime_error("division by zero"))

            if name == "quotient":
                if b == -1 and a == MINI:
                    return error(runtime_error("integer overflow"))
                if b == -1:
                    return ok(Value.Num(-a))

                return ok(Value.Num(a / b))

            if b == -1:
                return ok(Value.Num(0))

            var r = a % b
            if name == "modulo" and r != 0 and ((r < 0) != (b < 0)):
                r += b
            return ok(Value.Num(r))

        if name == "abs":
            _c := try self.want(name, n, 1, 1)
            a := try self.need_int(name, args[0].clone())
            if a < 0:
                return ok(Value.Num(try sub_int(0, a)))

            return ok(Value.Num(a))

        if name == "min" or name == "max":
            _c := try self.want(name, n, 1, -1)
            var xs = try self.int_args(name, args)
            var best = MAXI
            if name == "max":
                best = MINI

            for x in xs:
                if name == "min" and x < best:
                    best = x
                if name == "max" and x > best:
                    best = x

            return ok(Value.Num(best))

        if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
            _c := try self.want(name, n, 2, -1)
            var xs = try self.int_args(name, args)
            var holds = true
            for i in 0..xs.length() - 1:
                if not compare_holds(name, xs[i], xs[i + 1]):
                    holds = false
            return ok(Value.Flag(holds))

        if name == "zero?" or name == "even?" or name == "odd?":
            _c := try self.want(name, n, 1, 1)
            a := try self.need_int(name, args[0].clone())
            if name == "zero?":
                return ok(Value.Flag(a == 0))

            even := a % 2 == 0
            if name == "even?":
                return ok(Value.Flag(even))

            return ok(Value.Flag(not even))

        return ok(none)

    var fn prim_predicates(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "not":
            _c := try self.want(name, n, 1, 1)
            return ok(Value.Flag(not truthy(args[0].clone())))

        if name == "null?":
            _c := try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.is_empty(args[0].clone())))

        if name == "pair?":
            _c := try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.cons_id(args[0].clone()) >= 0))

        if name == "list?":
            _c := try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.is_proper(args[0].clone())))

        if (
            name == "number?"
            or name == "string?"
            or name == "symbol?"
            or name == "boolean?"
            or name == "procedure?"
        ):
            _c := try self.want(name, n, 1, 1)
            v := args[0].clone()
            if name == "number?":
                return ok(
                    Value.Flag(
                        self.atom_key(
                            v.clone()
                        ) != "" and self.sym_id(v.clone()) < 0 and self.leaf_key(
                            v.clone()
                        ).starts_with("n")
                    )
                )
            if name == "string?":
                return ok(Value.Flag(self.leaf_key(v.clone()).starts_with("t")))
            if name == "symbol?":
                return ok(Value.Flag(self.sym_id(v.clone()) >= 0))
            if name == "boolean?":
                return ok(Value.Flag(self.leaf_key(v.clone()).starts_with("b")))

            return ok(
                Value.Flag(
                    self.proc_id(v.clone()) >= 0 or self.prim_name(
                        v.clone()
                    ) != ""
                )
            )

        if name == "eq?":
            _c := try self.want(name, n, 2, 2)
            ka := self.atom_key(args[0].clone())
            return ok(Value.Flag(ka != "" and ka == self.atom_key(args[1].clone())))

        if name == "equal?":
            _c := try self.want(name, n, 2, 2)
            return ok(Value.Flag(self.equal_values(args[0].clone(), args[1].clone())))

        return ok(none)

    var fn prim_lists(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "cons":
            _c := try self.want(name, n, 2, 2)
            return ok(self.cons(args[0].clone(), args[1].clone()))

        if name == "car" or name == "cdr":
            _c := try self.want(name, n, 1, 1)
            id := try self.need_pair(name, args[0].clone())
            if name == "car":
                return ok(self.cars[id].clone())

            return ok(self.cdrs[id].clone())

        if name == "cadr" or name == "cddr" or name == "caddr":
            _c := try self.want(name, n, 1, 1)

            if name == "cadr":
                r := try self.cxr(name, args[0].clone(), "ad")
                return ok(r)

            if name == "cddr":
                r := try self.cxr(name, args[0].clone(), "dd")
                return ok(r)

            r := try self.cxr(name, args[0].clone(), "add")
            return ok(r)

        if name == "set-car!" or name == "set-cdr!":
            _c := try self.want(name, n, 2, 2)
            id := try self.need_pair(name, args[0].clone())

            if name == "set-car!":
                self.cars[id] = args[1].clone()
            else:
                self.cdrs[id] = args[1].clone()

            return ok(Value.Unspecified)

        if name == "list":
            return ok(self.from_list(args))

        if name == "length":
            _c := try self.want(name, n, 1, 1)
            items := try self.need_list(name, args[0].clone())
            return ok(Value.Num(items.length()))

        if name == "append":
            if n == 0:
                return ok(Value.Empty)

            var all = List[Value]()

            for i in 0..n - 1:
                items := try self.need_list(name, args[i].clone())
                for x in items:
                    all.append(x)

            return ok(self.build(all, args[n - 1].clone()))

        if name == "reverse":
            _c := try self.want(name, n, 1, 1)
            items := try self.need_list(name, args[0].clone())
            return ok(self.from_list(items.reversed()))

        if name == "list-ref":
            _c := try self.want(name, n, 2, 2)
            items := try self.need_list(name, args[0].clone())
            k := try self.need_int(name, args[1].clone())
            if k < 0 or k >= items.length():
                return error(runtime_error("list-ref: index out of range"))

            return ok(items[k].clone())

        if name == "list-tail":
            _c := try self.want(name, n, 2, 2)
            items := try self.need_list(name, args[0].clone())
            k := try self.need_int(name, args[1].clone())
            if k < 0 or k > items.length():
                return error(runtime_error("list-tail: index out of range"))

            var cur = args[0].clone()
            for _i in 0..k:
                cur = self.cdr(cur)
            return ok(cur)

        if name == "range":
            _c := try self.want(name, n, 2, 2)
            a := try self.need_int(name, args[0].clone())
            b := try self.need_int(name, args[1].clone())
            var out = List[Value]()
            for i in a..b:
                out.append(Value.Num(i))
            return ok(self.from_list(out))

        if name == "assoc":
            _c := try self.want(name, n, 2, 2)
            items := try self.need_list(name, args[1].clone())

            for entry in items:
                if self.cons_id(entry.clone()) < 0:
                    return error(self.type_error(name, "pair", entry))
                if self.equal_values(args[0].clone(), self.car(entry.clone())):
                    return ok(entry)

            return ok(Value.Flag(false))

        if name == "member":
            _c := try self.want(name, n, 2, 2)
            _items := try self.need_list(name, args[1].clone())
            var cur = args[1].clone()

            while self.cons_id(cur.clone()) >= 0:
                if self.equal_values(args[0].clone(), self.car(cur.clone())):
                    return ok(cur)

                cur = self.cdr(cur)

            return ok(Value.Flag(false))

        return ok(none)

    var fn prim_hof(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "map" or name == "for-each":
            _c := try self.want(name, n, 2, -1)
            f := try self.need_proc(name, args[0].clone())
            var lists = List[List[Value]]()

            for i in 1..n:
                items := try self.need_list(name, args[i].clone())
                lists.append(items)

            var shortest = lists[0].length()
            for i in 0..lists.length():
                if lists[i].length() < shortest:
                    shortest = lists[i].length()

            var out = List[Value]()

            for i in 0..shortest:
                var call_args = List[Value]()
                for j in 0..lists.length():
                    call_args.append(lists[j][i].clone())

                r := try self.call_proc(f.clone(), call_args, d)
                out.append(r)

            if name == "map":
                return ok(self.from_list(out))

            return ok(Value.Unspecified)

        if name == "filter":
            _c := try self.want(name, n, 2, 2)
            f := try self.need_proc(name, args[0].clone())
            items := try self.need_list(name, args[1].clone())
            var out = List[Value]()

            for x in items:
                var one = List[Value]()
                one.append(x.clone())

                keep := try self.call_proc(f.clone(), one, d)
                if truthy(keep):
                    out.append(x)

            return ok(self.from_list(out))

        if name == "fold" or name == "foldr":
            _c := try self.want(name, n, 3, 3)
            f := try self.need_proc(name, args[0].clone())
            items := try self.need_list(name, args[2].clone())
            var acc = args[1].clone()

            if name == "fold":
                for x in items:
                    acc = try self.call_proc(f.clone(), [acc.clone(), x], d)
            else:
                var i = items.length()

                while i > 0:
                    i -= 1
                    acc = try self.call_proc(
                        f.clone(), [items[i].clone(), acc.clone()], d
                    )

            return ok(acc)

        if name == "apply":
            _c := try self.want(name, n, 2, -1)
            f := try self.need_proc(name, args[0].clone())
            last := try self.need_list(name, args[n - 1].clone())
            var call_args = List[Value]()
            for i in 1..n - 1:
                call_args.append(args[i].clone())
            for x in last:
                call_args.append(x)

            r := try self.call_proc(f, call_args, d)
            return ok(r)

        if name == "sort":
            _c := try self.want(name, n, 2, 2)
            less := try self.need_proc(name, args[1].clone())
            items := try self.need_list(name, args[0].clone())
            sorted := try self.sort_list(items, less, d)
            return ok(self.from_list(sorted))

        return ok(none)

    var fn prim_strings(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "string-length":
            _c := try self.want(name, n, 1, 1)
            s := try self.need_str(name, args[0].clone())
            return ok(Value.Num(s.length()))

        if name == "string-append":
            var out = ""

            for a in args:
                s := try self.need_str(name, a.clone())
                out += s

            return ok(Value.Text(out))

        if name == "substring":
            _c := try self.want(name, n, 3, 3)
            s := try self.need_str(name, args[0].clone())
            start := try self.need_int(name, args[1].clone())
            end := try self.need_int(name, args[2].clone())
            cs := s.chars()
            if start < 0 or start > end or end > cs.length():
                return error(runtime_error("substring: index out of range"))

            var out = ""
            for i in start..end:
                out += cs[i].clone()
            return ok(Value.Text(out))

        if name == "string-ref":
            _c := try self.want(name, n, 2, 2)
            s := try self.need_str(name, args[0].clone())
            k := try self.need_int(name, args[1].clone())
            cs := s.chars()
            if k < 0 or k >= cs.length():
                return error(runtime_error("string-ref: index out of range"))

            return ok(Value.Text(cs[k].clone()))

        if name == "string=?" or name == "string<?":
            _c := try self.want(name, n, 2, 2)
            a := try self.need_str(name, args[0].clone())
            b := try self.need_str(name, args[1].clone())
            if name == "string=?":
                return ok(Value.Flag(a == b))

            return ok(Value.Flag(a < b))

        if name == "string-upcase" or name == "string-downcase":
            _c := try self.want(name, n, 1, 1)
            s := try self.need_str(name, args[0].clone())
            if name == "string-upcase":
                return ok(Value.Text(s.upper()))

            return ok(Value.Text(s.lower()))

        if name == "string->number":
            _c := try self.want(name, n, 1, 1)
            s := try self.need_str(name, args[0].clone())
            if is_int_text(s.clone()):
                if v := s.parse_int():
                    return ok(Value.Num(v))
            return ok(Value.Flag(false))

        if name == "number->string":
            _c := try self.want(name, n, 1, 1)
            x := try self.need_int(name, args[0].clone())
            return ok(Value.Text("{x}"))

        if name == "string->symbol":
            _c := try self.want(name, n, 1, 1)
            s := try self.need_str(name, args[0].clone())
            return ok(Value.Sym(self.intern(s)))

        if name == "symbol->string":
            _c := try self.want(name, n, 1, 1)
            id := try self.need_sym(name, args[0].clone())
            return ok(Value.Text(self.sym_names[id].clone()))

        if name == "string->list":
            _c := try self.want(name, n, 1, 1)
            s := try self.need_str(name, args[0].clone())
            var out = List[Value]()
            for c in s.chars():
                out.append(Value.Text(c))
            return ok(self.from_list(out))

        if name == "list->string":
            _c := try self.want(name, n, 1, 1)
            items := try self.need_list(name, args[0].clone())
            var out = ""

            for x in items:
                s := try self.need_str(name, x)
                out += s

            return ok(Value.Text(out))

        if name == "string-join":
            _c := try self.want(name, n, 2, 2)
            items := try self.need_list(name, args[0].clone())
            sep := try self.need_str(name, args[1].clone())
            var parts = List[String]()

            for x in items:
                s := try self.need_str(name, x)
                parts.append(s)

            return ok(Value.Text(parts.join(sep)))

        if name == "string-split":
            _c := try self.want(name, n, 2, 2)
            s := try self.need_str(name, args[0].clone())
            sep := try self.need_str(name, args[1].clone())
            if sep.length() != 1:
                return error(
                    runtime_error(
                        "string-split: separator must be one character"
                    )
                )

            var out = List[Value]()
            for part in s.split(sep):
                out.append(Value.Text(part))
            return ok(self.from_list(out))

        if name == "string-contains?":
            _c := try self.want(name, n, 2, 2)
            s := try self.need_str(name, args[0].clone())
            sub := try self.need_str(name, args[1].clone())
            return ok(Value.Flag(s.contains(sub)))

        return ok(none)

    var fn prim_misc(
        name: String,
        args: List[Value],
        d: Int
    ) Result[Optional[Value], Fail]:
        n := args.length()

        if name == "display":
            _c := try self.want(name, n, 1, 1)
            self.emit(self.render(args[0].clone(), false))
            return ok(Value.Unspecified)

        if name == "write":
            _c := try self.want(name, n, 1, 1)
            self.emit(self.render(args[0].clone(), true))
            return ok(Value.Unspecified)

        if name == "newline":
            _c := try self.want(name, n, 0, 0)
            self.emit("\n")
            return ok(Value.Unspecified)

        if name == "void":
            _c := try self.want(name, n, 0, 0)
            return ok(Value.Unspecified)

        if name == "error":
            _c := try self.want(name, n, 1, -1)
            var msg = try self.need_str(name, args[0].clone())
            for i in 1..n:
                msg += " " + self.render(args[i].clone(), true)
            return error(runtime_error(msg))

        return ok(none)

export fn main() Int:
    data := read_all(stdin()).get()
    text := data.decode_utf8().get("")
    var m = Machine(
        chars: text.chars(), pos: 0, cars: List[Value](), cdrs: List[Value](),
        closures: List[Closure](), frame_parent: List[Int](), frame_first: List[Int](),
        bind_sym: List[Int](), bind_val: List[Value](), bind_next: List[Int](),
        global_slot: List[Int](), sym_names: List[String](),
        sym_ids: Map[String, Int](), fresh: true
    )
    _i := m.install()
    outcome := m.program()
    if outcome.is_error():
        m.report(outcome.err().message())
    stdout().flush().get()
    return 0
