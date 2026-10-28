from "@std/io.ms" import stdin, stdout, read_all
from "@std/math.ms" import wrapping_add, wrapping_multiply

let MAXI = 9223372036854775807
let MINI = -9223372036854775807 - 1
let DEPTH_LIMIT = 10000
let SPECIAL_COUNT = 15
let K_QUOTE = 0
let K_IF = 1
let K_DEFINE = 2
let K_SET = 3
let K_LAMBDA = 4
let K_BEGIN = 5
let K_LET = 6
let K_LETSTAR = 7
let K_LETREC = 8
let K_COND = 9
let K_AND = 10
let K_OR = 11
let K_WHEN = 12
let K_UNLESS = 13
let K_TRY = 14
let K_ELSE = 15
let SPECIAL_NAMES = [
    "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond",
    "and", "or", "when", "unless", "try", "else"
]
let BUILTIN_NAMES = [
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
    def message() -> String:
        return self.msg.clone()

type Closure:
    name: String
    params: List[Int]
    rest: Int
    body: Value
    env: Int

# One evaluation step: either a finished value, or an expression to continue with in the same loop.
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

def finish(v: Value) -> Step:
    return Step(done: True, value: v, expr: Value.Empty, env: 0, depth: 0, tail: False)

def resume(expr: Value, env: Int, depth: Int, tail: Bool) -> Step:
    return Step(
        done: False, value: Value.Empty, expr: expr, env: env, depth: depth, tail: tail
    )

def runtime_error(msg: String) -> Fail:
    return Fail(msg: msg, syntax: False)

def syntax_error(msg: String) -> Fail:
    return Fail(msg: "syntax error: " + msg, syntax: True)

def bad_form(kw: String) -> Fail:
    return syntax_error("bad form: " + kw)

def truthy(v: Value) -> Bool:
    match v:
        case Flag(flag):
            return flag
        case _:
            return True

def is_delim(c: String) -> Bool:
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

def is_int_text(text: String) -> Bool:
    let cs = text.chars()
    var i = 0
    if cs.length() > 0 and cs[0] == "-":
        i = 1
    if i >= cs.length():
        return False

    while i < cs.length():
        if not (cs[i] >= "0" and cs[i] <= "9"):
            return False

        i += 1

    return True

def add_int(a: Int, b: Int) -> Result[Int, Fail]:
    let r = wrapping_add(a, b)
    if (b > 0 and r < a) or (b < 0 and r > a):
        return error(runtime_error("integer overflow"))

    return ok(r)

def sub_int(a: Int, b: Int) -> Result[Int, Fail]:
    if (b < 0 and a > MAXI + b) or (b > 0 and a < MINI + b):
        return error(runtime_error("integer overflow"))

    return ok(a - b)

def mul_int(a: Int, b: Int) -> Result[Int, Fail]:
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

    let r = wrapping_multiply(a, b)
    if r / a != b:
        return error(runtime_error("integer overflow"))

    return ok(r)

def compare_holds(name: String, a: Int, b: Int) -> Bool:
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
    var def install() -> Result[Unit, Fail]:
        let _root = self.new_frame(-1)
        for name in SPECIAL_NAMES:
            let _s = self.intern(name.clone())

        for name in BUILTIN_NAMES:
            let id = self.intern(name.clone())
            self.define_in(0, id, Value.Prim(name.clone()))

        return ok(())

    var def intern(name: String) -> Int:
        if let known = self.sym_ids.get(name.clone()):
            return known

        let id = self.sym_names.length()
        self.sym_names.append(name.clone())
        self.global_slot.append(-1)
        self.sym_ids[name.clone()] = id
        return id

    var def emit(s: String) -> Unit:
        if s.length() == 0:
            return

        self.fresh = s.ends_with("\n")
        stdout().write(s).get()

    var def report(msg: String) -> Unit:
        if not self.fresh:
            self.emit("\n")
        self.emit("error: " + msg + "\n")

    # ---- heap: pairs, closures, frames -------------------------------------------------

    var def cons(a: Value, d: Value) -> Value:
        self.cars.append(a)
        self.cdrs.append(d)
        return Value.Cons(self.cars.length() - 1)

    var def cons_id(v: Value) -> Int:
        match v:
            case Cons(id):
                return id
            case _:
                return -1

    var def sym_id(v: Value) -> Int:
        match v:
            case Sym(id):
                return id
            case _:
                return -1

    var def proc_id(v: Value) -> Int:
        match v:
            case Proc(id):
                return id
            case _:
                return -1

    var def prim_name(v: Value) -> String:
        match v:
            case Prim(name):
                return name
            case _:
                return ""

    var def is_empty(v: Value) -> Bool:
        match v:
            case Empty:
                return True
            case _:
                return False

    var def car(v: Value) -> Value:
        let id = self.cons_id(v)
        if id < 0:
            return Value.Empty

        return self.cars[id].clone()

    var def cdr(v: Value) -> Value:
        let id = self.cons_id(v)
        if id < 0:
            return Value.Empty

        return self.cdrs[id].clone()

    var def is_form(v: Value, kind: Int) -> Bool:
        return self.sym_id(self.car(v)) == kind

    var def is_proper(v: Value) -> Bool:
        var cur = v.clone()

        while True:
            let id = self.cons_id(cur.clone())
            if id < 0:
                return self.is_empty(cur)

            cur = self.cdrs[id].clone()

    var def list_of(v: Value) -> List[Value]:
        var out = List[Value]()
        var cur = v.clone()

        while True:
            let id = self.cons_id(cur.clone())
            if id < 0:
                return out

            out.append(self.cars[id].clone())
            cur = self.cdrs[id].clone()

    var def build(items: List[Value], tail: Value) -> Value:
        var out = tail
        var i = items.length()

        while i > 0:
            i -= 1
            out = self.cons(items[i].clone(), out)

        return out

    var def from_list(items: List[Value]) -> Value:
        return self.build(items, Value.Empty)

    var def new_frame(parent: Int) -> Int:
        self.frame_parent.append(parent)
        self.frame_first.append(-1)
        return self.frame_parent.length() - 1

    var def find_in_frame(frame: Int, sym: Int) -> Int:
        if frame == 0:
            return self.global_slot[sym]

        let start = self.frame_first[frame]
        var b = start

        while b >= 0:
            if self.bind_sym[b] == sym:
                return b

            b = self.bind_next[b]

        return -1

    var def define_in(frame: Int, sym: Int, val: Value) -> Unit:
        let slot = self.find_in_frame(frame, sym)

        if slot >= 0:
            self.bind_val[slot] = val
            return

        let idx = self.bind_sym.length()
        self.bind_sym.append(sym)
        self.bind_val.append(val)

        if frame == 0:
            self.bind_next.append(-1)
            self.global_slot[sym] = idx
        else:
            self.bind_next.append(self.frame_first[frame])
            self.frame_first[frame] = idx

    var def lookup(env: Int, sym: Int) -> Int:
        var f = env

        while f >= 0:
            let slot = self.find_in_frame(f, sym)
            if slot >= 0:
                return slot

            f = self.frame_parent[f]

        return -1

    var def make_closure(
        params: Value,
        body: Value,
        env: Int,
        name: String,
        kw: String
    ) -> Result[Value, Fail]:
        var ids = List[Int]()
        var rest = -1
        var cur = params.clone()

        while True:
            let id = self.cons_id(cur.clone())
            if id < 0:
                break

            let s = self.sym_id(self.car(cur.clone()))
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

    var def bind_args(id: Int, args: List[Value]) -> Result[Int, Fail]:
        let n = self.closures[id].params.length()
        let count = args.length()

        if count < n or (self.closures[id].rest < 0 and count > n):
            var who = self.closures[id].name.clone()
            if who == "":
                who = "lambda"

            var expected = f"{n}"
            if self.closures[id].rest >= 0:
                expected = f"at least {n}"
            return error(
                runtime_error(
                    f"wrong number of arguments to {who}: expected {expected}, got {count}"
                )
            )

        let frame = self.new_frame(self.closures[id].env)
        for i in 0..n:
            self.define_in(frame, self.closures[id].params[i], args[i].clone())

        if self.closures[id].rest >= 0:
            var extra = List[Value]()
            for i in n..count:
                extra.append(args[i].clone())

            let rest_list = self.from_list(extra)
            self.define_in(frame, self.closures[id].rest, rest_list)

        return ok(frame)

    # ---- printing ----------------------------------------------------------------------

    var def write_string(s: String) -> String:
        var out = "\""

        for c in s.chars():
            if c == "\\":
                out += "\\\\"
            elif c == "\"":
                out += "\\\""
            elif c == "\n":
                out += "\\n"
            elif c == "\t":
                out += "\\t"
            else:
                out += c.clone()

        return out + "\""

    var def render(v: Value, write: Bool) -> String:
        match v:
            case Empty:
                return "()"
            case Unspecified:
                return "#<void>"
            case Flag(flag):
                if flag:
                    return "#t"

                return "#f"
            case Num(n):
                return f"{n}"
            case Text(s):
                if write:
                    return self.write_string(s)

                return s
            case Sym(id):
                return self.sym_names[id].clone()
            case Cons(id):
                return self.render_list(id, write)
            case Prim(name):
                return f"#<builtin {name}>"
            case Proc(id):
                let name = self.closures[id].name.clone()
                if name == "":
                    return "#<procedure>"

                return f"#<procedure {name}>"

    var def render_list(first: Int, write: Bool) -> String:
        var out = "("
        var id = first

        while True:
            out += self.render(self.cars[id].clone(), write)

            let rest = self.cdrs[id].clone()
            let next_id = self.cons_id(rest.clone())

            if next_id >= 0:
                out += " "
                id = next_id
                continue

            if not self.is_empty(rest.clone()):
                out += " . " + self.render(rest, write)
            return out + ")"

    # ---- reader ------------------------------------------------------------------------

    var def peek() -> String:
        if self.pos < self.chars.length():
            return self.chars[self.pos].clone()

        return ""

    var def peek_next() -> String:
        if self.pos + 1 < self.chars.length():
            return self.chars[self.pos + 1].clone()

        return ""

    var def skip_space() -> Unit:
        while self.pos < self.chars.length():
            let c = self.peek()

            if c == ";":
                while self.peek() != "\n" and self.peek() != "":
                    self.pos += 1
            elif c == " " or c == "\t" or c == "\n" or c == "\r":
                self.pos += 1
            else:
                return

    var def read_datum() -> Result[Value, Fail]:
        self.skip_space()

        let c = self.peek()
        if c == "":
            return error(syntax_error("unexpected end of input"))

        if c == "(":
            self.pos += 1
            return self.read_list()

        if c == ")":
            return error(syntax_error("unexpected )"))

        if c == "'":
            self.pos += 1

            let quoted = try self.read_datum()
            let tail = self.cons(quoted, Value.Empty)
            return ok(self.cons(Value.Sym(K_QUOTE), tail))

        if c == "\"":
            return self.read_string()

        return self.read_atom()

    var def read_list() -> Result[Value, Fail]:
        var items = List[Value]()
        var tail = Value.Empty

        while True:
            self.skip_space()

            let c = self.peek()
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

                let e = self.peek()
                if e == "":
                    return error(syntax_error("unexpected end of input"))
                if e != ")":
                    return error(syntax_error("bad dotted list"))

                self.pos += 1
                break

            let item = try self.read_datum()
            items.append(item)

        return ok(self.build(items, tail))

    var def read_string() -> Result[Value, Fail]:
        self.pos += 1

        var out = ""

        while True:
            let c = self.peek()
            if c == "":
                return error(syntax_error("unterminated string"))

            self.pos += 1
            if c == "\"":
                break

            if c == "\\":
                let e = self.peek()
                if e == "":
                    return error(syntax_error("unterminated string"))

                self.pos += 1

                if e == "n":
                    out += "\n"
                elif e == "t":
                    out += "\t"
                elif e == "\\":
                    out += "\\"
                elif e == "\"":
                    out += "\""
                else:
                    return error(syntax_error("bad escape"))
            else:
                out += c

        return ok(Value.Text(out))

    var def read_atom() -> Result[Value, Fail]:
        var text = ""

        while not is_delim(self.peek()):
            text += self.peek()
            self.pos += 1

        if text == "#t":
            return ok(Value.Flag(True))
        if text == "#f":
            return ok(Value.Flag(False))
        if text.starts_with("#"):
            return error(syntax_error("bad token: " + text))
        if text == ".":
            return error(syntax_error("unexpected ."))

        if is_int_text(text):
            if let n = text.parse_int():
                return ok(Value.Num(n))

            return error(syntax_error("integer out of range"))

        return ok(Value.Sym(self.intern(text)))

    var def program() -> Result[Unit, Fail]:
        while True:
            self.skip_space()
            if self.pos >= self.chars.length():
                return ok(())

            let form = try self.read_datum()
            let _v = try self.run(form, 0, 0, False)

    # ---- evaluator ---------------------------------------------------------------------

    # Evaluates `expr`. `tail` says whether this loop is a procedure body (a call here
    # replaces the frame, so depth stays) or a sub-expression (a call here goes one deeper).
    var def run(expr: Value, env: Int, depth: Int, tail: Bool) -> Result[Value, Fail]:
        var form = expr
        var frame = env
        var level = depth
        var in_tail = tail

        while True:
            let step = try self.step(form.clone(), frame, level, in_tail)
            if step.done:
                return ok(step.value.clone())

            form = step.expr.clone()
            frame = step.env
            level = step.depth
            in_tail = step.tail

    var def step(form: Value, env: Int, depth: Int, tail: Bool) -> Result[Step, Fail]:
        let sym = self.sym_id(form.clone())

        if sym >= 0:
            let slot = self.lookup(env, sym)
            if slot < 0:
                return error(
                    runtime_error(
                        "unbound variable: " + self.sym_names[
                            sym
                        ].clone()
                    )
                )

            return ok(finish(self.bind_val[slot].clone()))

        let cid = self.cons_id(form.clone())

        if cid < 0:
            if self.is_empty(form.clone()):
                return error(syntax_error("empty application"))

            return ok(finish(form))

        let head = self.sym_id(self.cars[cid].clone())
        if head >= 0 and head < SPECIAL_COUNT:
            return self.special(head, form, env, depth, tail)

        return self.apply_form(form, env, depth, tail)

    var def apply_form(
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        if not self.is_proper(form.clone()):
            return error(syntax_error("bad application"))

        let items = self.list_of(form)
        let callee = try self.run(items[0].clone(), env, depth, False)
        var args = List[Value]()

        for i in 1..items.length():
            let arg = try self.run(items[i].clone(), env, depth, False)
            args.append(arg)

        return self.apply_value(callee, args, depth, tail)

    var def apply_value(
        callee: Value,
        args: List[Value],
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        let pid = self.proc_id(callee.clone())

        if pid >= 0:
            var level = depth
            if not tail:
                level = depth + 1
            if level > DEPTH_LIMIT:
                return error(runtime_error("recursion limit exceeded"))

            let frame = try self.bind_args(pid, args)
            let body = self.closures[pid].body.clone()
            let last = try self.run_init(body, frame, level)
            return ok(resume(last, frame, level, True))

        let pname = self.prim_name(callee.clone())

        if pname != "":
            let result = try self.call_prim(pname, args, depth + 1)
            return ok(finish(result))

        return error(runtime_error("not a procedure: " + self.render(callee, True)))

    # Calls a procedure from inside a builtin; `d` is the depth of the callee's body.
    var def call_proc(callee: Value, args: List[Value], d: Int) -> Result[Value, Fail]:
        let pid = self.proc_id(callee.clone())

        if pid < 0:
            let pname = self.prim_name(callee.clone())
            if pname != "":
                return self.call_prim(pname, args, d)

            return error(runtime_error("not a procedure: " + self.render(callee, True)))

        if d > DEPTH_LIMIT:
            return error(runtime_error("recursion limit exceeded"))

        let frame = try self.bind_args(pid, args)
        let body = self.closures[pid].body.clone()
        let last = try self.run_init(body, frame, d)
        return self.run(last, frame, d, True)

    # Evaluates all forms of a body but the last, and returns the last one unevaluated.
    var def run_init(forms: Value, env: Int, depth: Int) -> Result[Value, Fail]:
        var cur = forms.clone()

        while True:
            let id = self.cons_id(cur.clone())
            if id < 0:
                return ok(Value.Unspecified)

            let head = self.cars[id].clone()
            let rest = self.cdrs[id].clone()
            if self.is_empty(rest.clone()):
                return ok(head)

            let _v = try self.run(head, env, depth, False)
            cur = rest

    var def parse_binds(bindings: Value, kw: String) -> Result[Binds, Fail]:
        if not self.is_proper(bindings.clone()):
            return error(bad_form(kw))

        var names = List[Int]()
        var inits = List[Value]()

        for b in self.list_of(bindings):
            if not self.is_proper(b.clone()):
                return error(bad_form(kw))

            let parts = self.list_of(b.clone())
            if parts.length() != 2 or self.sym_id(parts[0].clone()) < 0:
                return error(bad_form(kw))

            names.append(self.sym_id(parts[0].clone()))
            inits.append(parts[1].clone())

        return ok(Binds(names: names, inits: inits))

    var def special(
        kind: Int,
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        let name = self.sym_names[kind].clone()
        if not self.is_proper(form.clone()):
            return error(bad_form(name))

        let items = self.list_of(form.clone())
        if kind <= K_BEGIN:
            return self.special_core(kind, items, form, env, depth, tail)
        if kind <= K_LETREC:
            return self.special_bind(kind, items, form, env, depth, tail)

        return self.special_control(kind, items, form, env, depth, tail)

    var def special_core(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        let name = self.sym_names[kind].clone()
        let n = items.length()

        if kind == K_QUOTE:
            if n != 2:
                return error(bad_form(name))

            return ok(finish(items[1].clone()))

        if kind == K_IF:
            if n != 3 and n != 4:
                return error(bad_form(name))

            let verdict = try self.run(items[1].clone(), env, depth, False)
            if truthy(verdict):
                return ok(resume(items[2].clone(), env, depth, tail))
            if n == 4:
                return ok(resume(items[3].clone(), env, depth, tail))

            return ok(finish(Value.Unspecified))

        if kind == K_DEFINE:
            if n < 3:
                return error(bad_form(name))

            let target = self.sym_id(items[1].clone())

            if target >= 0:
                if n != 3:
                    return error(bad_form(name))

                var value = Value.Unspecified

                if self.is_form(items[2].clone(), K_LAMBDA):
                    value = try self.lambda_value(
                        items[2].clone(), env, self.sym_names[target].clone()
                    )
                else:
                    value = try self.run(items[2].clone(), env, depth, False)

                self.define_in(env, target, value)
                return ok(finish(Value.Unspecified))

            let fname = self.sym_id(self.car(items[1].clone()))
            if fname < 0:
                return error(bad_form(name))

            let params = self.cdr(items[1].clone())
            let body = self.cdr(self.cdr(form.clone()))
            let proc = try self.make_closure(
                params, body, env, self.sym_names[fname].clone(), name
            )
            self.define_in(env, fname, proc)
            return ok(finish(Value.Unspecified))

        if kind == K_SET:
            let target = self.sym_id(items[1].clone())
            if n != 3 or target < 0:
                return error(bad_form(name))

            let value = try self.run(items[2].clone(), env, depth, False)
            let slot = self.lookup(env, target)
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

            let proc = try self.make_closure(
                items[1].clone(), self.cdr(self.cdr(form.clone())), env, "", name
            )
            return ok(finish(proc))

        if kind == K_BEGIN:
            if n == 1:
                return ok(finish(Value.Unspecified))

            let last = try self.run_init(self.cdr(form), env, depth)
            return ok(resume(last, env, depth, tail))

        return error(bad_form(name))

    var def special_bind(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        let name = self.sym_names[kind].clone()
        let n = items.length()

        if kind == K_LET:
            if n < 3:
                return error(bad_form(name))
            if self.sym_id(items[1].clone()) >= 0:
                return self.named_let(form, items, env, depth, tail)

            let binds = try self.parse_binds(items[1].clone(), name)
            var vals = List[Value]()

            for init in binds.inits:
                let v = try self.run(init.clone(), env, depth, False)
                vals.append(v)

            let frame = self.new_frame(env)
            for i in 0..vals.length():
                self.define_in(frame, binds.names[i], vals[i].clone())

            let last = try self.run_init(self.cdr(self.cdr(form)), frame, depth)
            return ok(resume(last, frame, depth, tail))

        if kind == K_LETSTAR or kind == K_LETREC:
            if n < 3:
                return error(bad_form(name))

            let binds = try self.parse_binds(items[1].clone(), name)
            let frame = self.new_frame(env)

            for i in 0..binds.names.length():
                let v = try self.run(binds.inits[i].clone(), frame, depth, False)
                self.define_in(frame, binds.names[i], v)

            let last = try self.run_init(self.cdr(self.cdr(form)), frame, depth)
            return ok(resume(last, frame, depth, tail))

        return error(bad_form(name))

    var def special_control(
        kind: Int,
        items: List[Value],
        form: Value,
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        let name = self.sym_names[kind].clone()
        let n = items.length()

        if kind == K_COND:
            var i = 1

            while i < n:
                let clause = items[i].clone()
                if not self.is_proper(clause.clone()) or self.is_empty(clause.clone()):
                    return error(bad_form(name))

                let parts = self.list_of(clause.clone())

                if self.sym_id(parts[0].clone()) == K_ELSE:
                    if i != n - 1 or parts.length() < 2:
                        return error(bad_form(name))

                    let last = try self.run_init(self.cdr(clause), env, depth)
                    return ok(resume(last, env, depth, tail))

                let verdict = try self.run(parts[0].clone(), env, depth, False)

                if truthy(verdict):
                    if parts.length() == 1:
                        return ok(finish(verdict))

                    let last = try self.run_init(self.cdr(clause), env, depth)
                    return ok(resume(last, env, depth, tail))

                i += 1

            return ok(finish(Value.Unspecified))

        if kind == K_AND or kind == K_OR:
            if n == 1:
                return ok(finish(Value.Flag(kind == K_AND)))

            for i in 1..n - 1:
                let v = try self.run(items[i].clone(), env, depth, False)
                if kind == K_AND and not truthy(v.clone()):
                    return ok(finish(v))
                if kind == K_OR and truthy(v.clone()):
                    return ok(finish(v))

            return ok(resume(items[n - 1].clone(), env, depth, tail))

        if kind == K_WHEN or kind == K_UNLESS:
            if n < 3:
                return error(bad_form(name))

            let verdict = try self.run(items[1].clone(), env, depth, False)
            var fire = truthy(verdict)
            if kind == K_UNLESS:
                fire = not fire
            if not fire:
                return ok(finish(Value.Unspecified))

            let last = try self.run_init(self.cdr(self.cdr(form)), env, depth)
            return ok(resume(last, env, depth, tail))

        if kind == K_TRY:
            if n != 3:
                return error(bad_form(name))

            let outcome = self.run(items[1].clone(), env, depth, False)

            if outcome.is_error():
                let failure = outcome.err()
                if failure.syntax:
                    return error(failure.clone())

                let handler = try self.run(items[2].clone(), env, depth, False)
                var msg_args = List[Value]()
                msg_args.append(Value.Text(failure.msg.clone()))

                let handled = try self.call_proc(handler, msg_args, depth + 1)
                return ok(finish(handled))

            let value = try outcome
            return ok(finish(value))

        return error(bad_form(name))

    var def lambda_value(form: Value, env: Int, name: String) -> Result[Value, Fail]:
        let items = self.list_of(form.clone())
        if items.length() < 3:
            return error(bad_form("lambda"))

        return self.make_closure(
            items[1].clone(), self.cdr(self.cdr(form)), env, name, "lambda"
        )

    var def named_let(
        form: Value,
        items: List[Value],
        env: Int,
        depth: Int,
        tail: Bool
    ) -> Result[Step, Fail]:
        if items.length() < 4:
            return error(bad_form("let"))

        let loop_sym = self.sym_id(items[1].clone())
        let binds = try self.parse_binds(items[2].clone(), "let")
        var args = List[Value]()

        for init in binds.inits:
            let v = try self.run(init.clone(), env, depth, False)
            args.append(v)

        let frame = self.new_frame(env)
        let params = self.sym_values(binds.names)
        let proc = try self.make_closure(
            params, self.cdr(self.cdr(self.cdr(form))), frame,
            self.sym_names[loop_sym].clone(), "let"
        )
        self.define_in(frame, loop_sym, proc.clone())
        return self.apply_value(proc, args, depth, tail)

    var def sym_values(ids: List[Int]) -> Value:
        var out = List[Value]()
        for id in ids:
            out.append(Value.Sym(id))
        return self.from_list(out)

    # ---- argument helpers for builtins -------------------------------------------------

    var def type_error(name: String, kind: String, v: Value) -> Fail:
        return runtime_error(f"{name}: expected {kind}, got {self.render(v, True)}")

    var def want(name: String, count: Int, lo: Int, hi: Int) -> Result[Unit, Fail]:
        if count < lo or (hi >= 0 and count > hi):
            var expected = f"{lo}"

            if hi < 0:
                expected = f"at least {lo}"
            elif lo != hi:
                expected = f"{lo} to {hi}"

            return error(
                runtime_error(
                    f"wrong number of arguments to {name}: expected {expected}, got {count}"
                )
            )

        return ok(())

    var def need_int(name: String, v: Value) -> Result[Int, Fail]:
        match v.clone():
            case Num(n):
                return ok(n)
            case _:
                return error(self.type_error(name, "integer", v))

    var def need_str(name: String, v: Value) -> Result[String, Fail]:
        match v.clone():
            case Text(s):
                return ok(s)
            case _:
                return error(self.type_error(name, "string", v))

    var def need_sym(name: String, v: Value) -> Result[Int, Fail]:
        let id = self.sym_id(v.clone())
        if id < 0:
            return error(self.type_error(name, "symbol", v))

        return ok(id)

    var def need_pair(name: String, v: Value) -> Result[Int, Fail]:
        let id = self.cons_id(v.clone())
        if id < 0:
            return error(self.type_error(name, "pair", v))

        return ok(id)

    var def need_proc(name: String, v: Value) -> Result[Value, Fail]:
        if self.proc_id(v.clone()) >= 0 or self.prim_name(v.clone()) != "":
            return ok(v)

        return error(self.type_error(name, "procedure", v))

    var def need_list(name: String, v: Value) -> Result[List[Value], Fail]:
        if not self.is_proper(v.clone()):
            return error(self.type_error(name, "list", v))

        return ok(self.list_of(v))

    var def int_args(name: String, args: List[Value]) -> Result[List[Int], Fail]:
        var out = List[Int]()

        for a in args:
            let x = try self.need_int(name, a.clone())
            out.append(x)

        return ok(out)

    var def atom_key(v: Value) -> String:
        match v:
            case Empty:
                return "e"
            case Flag(flag):
                if flag:
                    return "bt"

                return "bf"
            case Num(n):
                return f"n{n}"
            case Sym(id):
                return f"s{id}"
            case _:
                return ""

    var def leaf_key(v: Value) -> String:
        match v:
            case Text(s):
                return "t" + s
            case Proc(id):
                return f"p{id}"
            case Prim(name):
                return "q" + name
            case Unspecified:
                return "v"
            case _:
                return self.atom_key(v)

    var def equal_values(a0: Value, b0: Value) -> Bool:
        var a = a0
        var b = b0

        while True:
            let ia = self.cons_id(a.clone())
            let ib = self.cons_id(b.clone())

            if ia < 0 and ib < 0:
                let ka = self.leaf_key(a)
                return ka != "" and ka == self.leaf_key(b)

            if ia < 0 or ib < 0:
                return False
            if not self.equal_values(self.car(a.clone()), self.car(b.clone())):
                return False

            a = self.cdr(a)
            b = self.cdr(b)

    var def cxr(name: String, v: Value, ops: String) -> Result[Value, Fail]:
        var cur = v
        let letters = ops.chars()
        var k = letters.length()

        while k > 0:
            k -= 1

            let id = try self.need_pair(name, cur.clone())

            if letters[k] == "a":
                cur = self.cars[id].clone()
            else:
                cur = self.cdrs[id].clone()

        return ok(cur)

    var def sort_list(
        items: List[Value],
        less: Value,
        d: Int
    ) -> Result[List[Value], Fail]:
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

        let ls = try self.sort_list(left, less.clone(), d)
        let rs = try self.sort_list(right, less.clone(), d)
        var out = List[Value]()
        var i = 0
        var j = 0

        while i < ls.length() and j < rs.length():
            let takes_right = try self.call_proc(
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

    # ---- builtins ----------------------------------------------------------------------

    var def call_prim(name: String, args: List[Value], d: Int) -> Result[Value, Fail]:
        let numbers_result = try self.prim_numbers(name, args, d)
        if let found = numbers_result:
            return ok(found)

        let predicates_result = try self.prim_predicates(name, args, d)
        if let found = predicates_result:
            return ok(found)

        let lists_result = try self.prim_lists(name, args, d)
        if let found = lists_result:
            return ok(found)

        let hof_result = try self.prim_hof(name, args, d)
        if let found = hof_result:
            return ok(found)

        let strings_result = try self.prim_strings(name, args, d)
        if let found = strings_result:
            return ok(found)

        let misc_result = try self.prim_misc(name, args, d)
        if let found = misc_result:
            return ok(found)

        return error(runtime_error("unknown builtin: " + name))

    var def prim_numbers(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

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
            let _c = try self.want(name, n, 1, -1)
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
            let _c = try self.want(name, n, 2, 2)
            let a = try self.need_int(name, args[0].clone())
            let b = try self.need_int(name, args[1].clone())
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
            let _c = try self.want(name, n, 1, 1)
            let a = try self.need_int(name, args[0].clone())
            if a < 0:
                return ok(Value.Num(try sub_int(0, a)))

            return ok(Value.Num(a))

        if name == "min" or name == "max":
            let _c = try self.want(name, n, 1, -1)
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
            let _c = try self.want(name, n, 2, -1)
            var xs = try self.int_args(name, args)
            var holds = True
            for i in 0..xs.length() - 1:
                if not compare_holds(name, xs[i], xs[i + 1]):
                    holds = False
            return ok(Value.Flag(holds))

        if name == "zero?" or name == "even?" or name == "odd?":
            let _c = try self.want(name, n, 1, 1)
            let a = try self.need_int(name, args[0].clone())
            if name == "zero?":
                return ok(Value.Flag(a == 0))

            let even = a % 2 == 0
            if name == "even?":
                return ok(Value.Flag(even))

            return ok(Value.Flag(not even))

        return ok(none)

    var def prim_predicates(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

        if name == "not":
            let _c = try self.want(name, n, 1, 1)
            return ok(Value.Flag(not truthy(args[0].clone())))

        if name == "null?":
            let _c = try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.is_empty(args[0].clone())))

        if name == "pair?":
            let _c = try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.cons_id(args[0].clone()) >= 0))

        if name == "list?":
            let _c = try self.want(name, n, 1, 1)
            return ok(Value.Flag(self.is_proper(args[0].clone())))

        if (
            name == "number?"
            or name == "string?"
            or name == "symbol?"
            or name == "boolean?"
            or name == "procedure?"
        ):
            let _c = try self.want(name, n, 1, 1)
            let v = args[0].clone()
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
            let _c = try self.want(name, n, 2, 2)
            let ka = self.atom_key(args[0].clone())
            return ok(Value.Flag(ka != "" and ka == self.atom_key(args[1].clone())))

        if name == "equal?":
            let _c = try self.want(name, n, 2, 2)
            return ok(Value.Flag(self.equal_values(args[0].clone(), args[1].clone())))

        return ok(none)

    var def prim_lists(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

        if name == "cons":
            let _c = try self.want(name, n, 2, 2)
            return ok(self.cons(args[0].clone(), args[1].clone()))

        if name == "car" or name == "cdr":
            let _c = try self.want(name, n, 1, 1)
            let id = try self.need_pair(name, args[0].clone())
            if name == "car":
                return ok(self.cars[id].clone())

            return ok(self.cdrs[id].clone())

        if name == "cadr" or name == "cddr" or name == "caddr":
            let _c = try self.want(name, n, 1, 1)

            if name == "cadr":
                let r = try self.cxr(name, args[0].clone(), "ad")
                return ok(r)

            if name == "cddr":
                let r = try self.cxr(name, args[0].clone(), "dd")
                return ok(r)

            let r = try self.cxr(name, args[0].clone(), "add")
            return ok(r)

        if name == "set-car!" or name == "set-cdr!":
            let _c = try self.want(name, n, 2, 2)
            let id = try self.need_pair(name, args[0].clone())

            if name == "set-car!":
                self.cars[id] = args[1].clone()
            else:
                self.cdrs[id] = args[1].clone()

            return ok(Value.Unspecified)

        if name == "list":
            return ok(self.from_list(args))

        if name == "length":
            let _c = try self.want(name, n, 1, 1)
            let items = try self.need_list(name, args[0].clone())
            return ok(Value.Num(items.length()))

        if name == "append":
            if n == 0:
                return ok(Value.Empty)

            var all = List[Value]()

            for i in 0..n - 1:
                let items = try self.need_list(name, args[i].clone())
                for x in items:
                    all.append(x)

            return ok(self.build(all, args[n - 1].clone()))

        if name == "reverse":
            let _c = try self.want(name, n, 1, 1)
            let items = try self.need_list(name, args[0].clone())
            return ok(self.from_list(items.reversed()))

        if name == "list-ref":
            let _c = try self.want(name, n, 2, 2)
            let items = try self.need_list(name, args[0].clone())
            let k = try self.need_int(name, args[1].clone())
            if k < 0 or k >= items.length():
                return error(runtime_error("list-ref: index out of range"))

            return ok(items[k].clone())

        if name == "list-tail":
            let _c = try self.want(name, n, 2, 2)
            let items = try self.need_list(name, args[0].clone())
            let k = try self.need_int(name, args[1].clone())
            if k < 0 or k > items.length():
                return error(runtime_error("list-tail: index out of range"))

            var cur = args[0].clone()
            for _i in 0..k:
                cur = self.cdr(cur)
            return ok(cur)

        if name == "range":
            let _c = try self.want(name, n, 2, 2)
            let a = try self.need_int(name, args[0].clone())
            let b = try self.need_int(name, args[1].clone())
            var out = List[Value]()
            for i in a..b:
                out.append(Value.Num(i))
            return ok(self.from_list(out))

        if name == "assoc":
            let _c = try self.want(name, n, 2, 2)
            let items = try self.need_list(name, args[1].clone())

            for entry in items:
                if self.cons_id(entry.clone()) < 0:
                    return error(self.type_error(name, "pair", entry))
                if self.equal_values(args[0].clone(), self.car(entry.clone())):
                    return ok(entry)

            return ok(Value.Flag(False))

        if name == "member":
            let _c = try self.want(name, n, 2, 2)
            let _items = try self.need_list(name, args[1].clone())
            var cur = args[1].clone()

            while self.cons_id(cur.clone()) >= 0:
                if self.equal_values(args[0].clone(), self.car(cur.clone())):
                    return ok(cur)

                cur = self.cdr(cur)

            return ok(Value.Flag(False))

        return ok(none)

    var def prim_hof(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

        if name == "map" or name == "for-each":
            let _c = try self.want(name, n, 2, -1)
            let f = try self.need_proc(name, args[0].clone())
            var lists = List[List[Value]]()

            for i in 1..n:
                let items = try self.need_list(name, args[i].clone())
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

                let r = try self.call_proc(f.clone(), call_args, d)
                out.append(r)

            if name == "map":
                return ok(self.from_list(out))

            return ok(Value.Unspecified)

        if name == "filter":
            let _c = try self.want(name, n, 2, 2)
            let f = try self.need_proc(name, args[0].clone())
            let items = try self.need_list(name, args[1].clone())
            var out = List[Value]()

            for x in items:
                var one = List[Value]()
                one.append(x.clone())

                let keep = try self.call_proc(f.clone(), one, d)
                if truthy(keep):
                    out.append(x)

            return ok(self.from_list(out))

        if name == "fold" or name == "foldr":
            let _c = try self.want(name, n, 3, 3)
            let f = try self.need_proc(name, args[0].clone())
            let items = try self.need_list(name, args[2].clone())
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
            let _c = try self.want(name, n, 2, -1)
            let f = try self.need_proc(name, args[0].clone())
            let last = try self.need_list(name, args[n - 1].clone())
            var call_args = List[Value]()
            for i in 1..n - 1:
                call_args.append(args[i].clone())
            for x in last:
                call_args.append(x)

            let r = try self.call_proc(f, call_args, d)
            return ok(r)

        if name == "sort":
            let _c = try self.want(name, n, 2, 2)
            let less = try self.need_proc(name, args[1].clone())
            let items = try self.need_list(name, args[0].clone())
            let sorted = try self.sort_list(items, less, d)
            return ok(self.from_list(sorted))

        return ok(none)

    var def prim_strings(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

        if name == "string-length":
            let _c = try self.want(name, n, 1, 1)
            let s = try self.need_str(name, args[0].clone())
            return ok(Value.Num(s.length()))

        if name == "string-append":
            var out = ""

            for a in args:
                let s = try self.need_str(name, a.clone())
                out += s

            return ok(Value.Text(out))

        if name == "substring":
            let _c = try self.want(name, n, 3, 3)
            let s = try self.need_str(name, args[0].clone())
            let start = try self.need_int(name, args[1].clone())
            let end = try self.need_int(name, args[2].clone())
            let cs = s.chars()
            if start < 0 or start > end or end > cs.length():
                return error(runtime_error("substring: index out of range"))

            var out = ""
            for i in start..end:
                out += cs[i].clone()
            return ok(Value.Text(out))

        if name == "string-ref":
            let _c = try self.want(name, n, 2, 2)
            let s = try self.need_str(name, args[0].clone())
            let k = try self.need_int(name, args[1].clone())
            let cs = s.chars()
            if k < 0 or k >= cs.length():
                return error(runtime_error("string-ref: index out of range"))

            return ok(Value.Text(cs[k].clone()))

        if name == "string=?" or name == "string<?":
            let _c = try self.want(name, n, 2, 2)
            let a = try self.need_str(name, args[0].clone())
            let b = try self.need_str(name, args[1].clone())
            if name == "string=?":
                return ok(Value.Flag(a == b))

            return ok(Value.Flag(a < b))

        if name == "string-upcase" or name == "string-downcase":
            let _c = try self.want(name, n, 1, 1)
            let s = try self.need_str(name, args[0].clone())
            if name == "string-upcase":
                return ok(Value.Text(s.upper()))

            return ok(Value.Text(s.lower()))

        if name == "string->number":
            let _c = try self.want(name, n, 1, 1)
            let s = try self.need_str(name, args[0].clone())
            if is_int_text(s.clone()):
                if let v = s.parse_int():
                    return ok(Value.Num(v))
            return ok(Value.Flag(False))

        if name == "number->string":
            let _c = try self.want(name, n, 1, 1)
            let x = try self.need_int(name, args[0].clone())
            return ok(Value.Text(f"{x}"))

        if name == "string->symbol":
            let _c = try self.want(name, n, 1, 1)
            let s = try self.need_str(name, args[0].clone())
            return ok(Value.Sym(self.intern(s)))

        if name == "symbol->string":
            let _c = try self.want(name, n, 1, 1)
            let id = try self.need_sym(name, args[0].clone())
            return ok(Value.Text(self.sym_names[id].clone()))

        if name == "string->list":
            let _c = try self.want(name, n, 1, 1)
            let s = try self.need_str(name, args[0].clone())
            var out = List[Value]()
            for c in s.chars():
                out.append(Value.Text(c))
            return ok(self.from_list(out))

        if name == "list->string":
            let _c = try self.want(name, n, 1, 1)
            let items = try self.need_list(name, args[0].clone())
            var out = ""

            for x in items:
                let s = try self.need_str(name, x)
                out += s

            return ok(Value.Text(out))

        if name == "string-join":
            let _c = try self.want(name, n, 2, 2)
            let items = try self.need_list(name, args[0].clone())
            let sep = try self.need_str(name, args[1].clone())
            var parts = List[String]()

            for x in items:
                let s = try self.need_str(name, x)
                parts.append(s)

            return ok(Value.Text(parts.join(sep)))

        if name == "string-split":
            let _c = try self.want(name, n, 2, 2)
            let s = try self.need_str(name, args[0].clone())
            let sep = try self.need_str(name, args[1].clone())
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
            let _c = try self.want(name, n, 2, 2)
            let s = try self.need_str(name, args[0].clone())
            let sub = try self.need_str(name, args[1].clone())
            return ok(Value.Flag(s.contains(sub)))

        return ok(none)

    var def prim_misc(
        name: String,
        args: List[Value],
        d: Int
    ) -> Result[Optional[Value], Fail]:
        let n = args.length()

        if name == "display":
            let _c = try self.want(name, n, 1, 1)
            self.emit(self.render(args[0].clone(), False))
            return ok(Value.Unspecified)

        if name == "write":
            let _c = try self.want(name, n, 1, 1)
            self.emit(self.render(args[0].clone(), True))
            return ok(Value.Unspecified)

        if name == "newline":
            let _c = try self.want(name, n, 0, 0)
            self.emit("\n")
            return ok(Value.Unspecified)

        if name == "void":
            let _c = try self.want(name, n, 0, 0)
            return ok(Value.Unspecified)

        if name == "error":
            let _c = try self.want(name, n, 1, -1)
            var msg = try self.need_str(name, args[0].clone())
            for i in 1..n:
                msg += " " + self.render(args[i].clone(), True)
            return error(runtime_error(msg))

        return ok(none)

export def main() -> Int:
    let data = read_all(stdin()).get()
    let text = data.decode_utf8().get("")
    var m = Machine(
        chars: text.chars(), pos: 0, cars: List[Value](), cdrs: List[Value](),
        closures: List[Closure](), frame_parent: List[Int](), frame_first: List[Int](),
        bind_sym: List[Int](), bind_val: List[Value](), bind_next: List[Int](),
        global_slot: List[Int](), sym_names: List[String](),
        sym_ids: Map[String, Int](), fresh: True
    )
    let _i = m.install()
    let outcome = m.program()
    if outcome.is_error():
        m.report(outcome.err().message())
    stdout().flush().get()
    return 0
