import stdin from "@std/io.ms"
import stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Var:
    recursive: Bool
    value: String

type Line:
    number: Int
    text: String

type Rule:
    prereqs: List[String]
    order: List[String]
    recipe: List[Line]

type Pattern:
    pat: String
    rule: Rule

type Frame:
    parent: Bool
    cond: Bool
    in_else: Bool
    line: Int

type Resolved:
    found: Bool
    prereqs: List[String]
    order: List[String]
    recipe: List[Line]
    stem: String

type Stop:
    text: String

impl Error for Stop:
    fn message() String:
        return self.text.clone()

type Make:
    files: Map[String, Int]
    clock: Int
    vars: Map[String, Var]
    cli: Set[String]
    locals: Map[String, String]
    expanding: List[String]
    explicit: Map[String, Rule]
    explicit_names: List[String]
    patterns: List[Pattern]
    phony: List[String]
    frames: List[Frame]
    line: Int
    is_open: Bool
    open_dummy: Bool
    open_targets: List[String]
    open_rule: Rule
    open_line: Int
    memo: Map[String, Bool]
    stack: List[String]
    visited: Set[String]
    out: List[String]
    ran: Int
    dry: Bool

fn emit(s: String) Unit:
    stdout().write(s).get()

fn empty_rule() Rule:
    return Rule(prereqs: List[String](), order: List[String](), recipe: List[Line]())

fn new_make() Make:
    return Make(
        files: Map[String, Int](), clock: 0, vars: Map[String, Var](),
        cli: Set[String](), locals: Map[String, String](), expanding: List[String](),
        explicit: Map[String, Rule](), explicit_names: List[String](),
        patterns: List[Pattern](), phony: List[String](), frames: List[Frame](),
        line: 0, is_open: false, open_dummy: false, open_targets: List[String](),
        open_rule: empty_rule(), open_line: 0, memo: Map[String, Bool](),
        stack: List[String](), visited: Set[String](), out: List[String](), ran: 0,
        dry: false
    )

# ---------- small text helpers ----------

fn words(s: String) List[String]:
    var out = List[String]()
    var cur = ""

    for c in s.chars():
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur += c

    if cur != "":
        out.append(cur)
    return out

fn tail(xs: List[String]) List[String]:
    var out = List[String]()
    var k = 1

    while k < xs.length():
        out.append(xs[k].clone())
        k += 1

    return out

fn arg(raw: List[String], i: Int) String:
    if i < raw.length():
        return raw[i].clone()

    return ""

fn cat(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var k = a

    while k < b:
        out += cs[k]
        k += 1

    return out

fn find_from(cs: List[String], sep: String, start: Int) Int:
    var k = start

    while k < cs.length():
        if cs[k] == sep:
            return k

        k += 1

    return -1

fn match_close(cs: List[String], open: Int) Int:
    let o = cs[open]
    var c = ")"
    if o == "\{":
        c = "\}"

    var depth = 0
    var k = open

    while k < cs.length():
        if cs[k] == o:
            depth += 1
        else if cs[k] == c:
            depth -= 1
            if depth == 0:
                return k

        k += 1

    return -1

fn find_colon(cs: List[String]) Int:
    var k = 0

    while k < cs.length():
        if cs[k] == "$" and k + 1 < cs.length() and cs[k + 1] == "$":
            k += 2
        else if (
            cs[k] == "$"
            and k + 1 < cs.length()
            and (cs[k + 1] == "(" or cs[k + 1] == "\{")
        ):
            let j = match_close(cs, k + 1)
            if j < 0:
                return -1

            k = j + 1
        else if cs[k] == ";":
            return -1
        else if cs[k] == ":":
            return k
        else:
            k += 1

    return -1

# Splits at commas that are outside (), {} brackets. Pieces are not trimmed.
fn split_top(s: String) List[String]:
    var out = List[String]()
    var cur = ""
    var depth = 0

    for c in s.chars():
        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1

        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c

    out.append(cur)
    return out

fn split_args(rest: String) List[String]:
    var out = List[String]()
    for p in split_top(rest):
        out.append(p.trim().clone())
    return out

fn dedupe(xs: List[String]) List[String]:
    var seen = Set[String]()
    var out = List[String]()

    for x in xs:
        if not seen.contains(x):
            seen.add(x.clone())
            out.append(x.clone())

    return out

fn position(xs: List[String], t: String) Int:
    var k = 0

    while k < xs.length():
        if xs[k] == t:
            return k

        k += 1

    return -1

fn circular(stack: List[String], pos: Int, t: String) Stop:
    var parts = List[String]()
    var k = pos

    while k < stack.length():
        parts.append(stack[k].clone())
        k += 1

    parts.append(t.clone())
    return Stop("make: *** Circular dependency detected: {parts.join(" -> ")}.  Stop.")

fn join_sep(a: String, b: String) String:
    if a == "" or b == "":
        return a + b

    return a + " " + b

fn strip_cr(l: String) String:
    if l.ends_with("\r"):
        return l.take(l.length() - 1)

    return l

fn strip_tabs(s: String) String:
    var out = s
    while out.starts_with("\t"):
        out = out.drop(1)
    return out

# Removes an unescaped comment; `\#` becomes a literal `#`.
fn strip_comment(s: String) String:
    let cs = s.chars()
    var out = ""
    var k = 0

    while k < cs.length():
        if cs[k] == "\\" and k + 1 < cs.length() and cs[k + 1] == "#":
            out += "#"
            k += 2
        else if cs[k] == "#":
            return out
        else:
            out += cs[k]
            k += 1

    return out

# Joins backslash-continued physical lines into logical lines.
fn logical_lines(phys: List[String]) List[Line]:
    var out = List[Line]()
    var i = 0

    while i < phys.length():
        let number = i + 1
        var text = phys[i].clone()

        while text.ends_with("\\") and i + 1 < phys.length():
            let base = text.take(text.length() - 1).trim_end()
            i += 1
            text = base + " " + phys[i].trim_start()

        if text.ends_with("\\"):
            text = text.take(text.length() - 1).trim_end()
        out.append(Line(number: number, text: text))
        i += 1

    return out

fn slice_lines(all: List[String], a: Int, b: Int) List[String]:
    var out = List[String]()
    var k = a

    while k < b:
        out.append(all[k].clone())
        k += 1

    return out

# ---------- pattern matching ----------

# Returns the stem when `word` matches `pat` (one `%` may stand for any stem).
fn pmatch(pat: String, word: String) Optional[String]:
    let parts = pat.split("%")

    if parts.length() == 1:
        if word == pat:
            return some("")

        return none

    let pre = parts[0].clone()
    let suf = parts[1].clone()
    if word.length() < pre.length() + suf.length():
        return none
    if not word.starts_with(pre) or not word.ends_with(suf):
        return none

    let mid = word.drop(pre.length()).take(word.length() - pre.length() - suf.length())
    return some(mid)

fn fill(rep: String, stem: String) String:
    return rep.replace_first("%", stem)

fn matches_any(pats: List[String], w: String) Bool:
    for p in pats:
        if let _s = pmatch(p, w):
            return true
    return false

fn subst_ref(value: String, from: String, to: String) String:
    var f = from.clone()
    var t = to.clone()

    if not from.contains("%"):
        f = "%" + from
        t = "%" + to

    var out = List[String]()

    for w in words(value):
        if let stem = pmatch(f, w):
            out.append(fill(t, stem))
        else:
            out.append(w)

    return out.join(" ")

# Shell-style glob used by wildcard: `*` any run without `/`, `?` one char without `/`.
fn glob(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi == p.length():
        return si == s.length()

    if p[pi] == "*":
        var k = si

        while not glob(p, pi + 1, s, k):
            if k >= s.length() or s[k] == "/":
                return false

            k += 1

        return true

    if si == s.length():
        return false

    if p[pi] == "?":
        if s[si] == "/":
            return false

        return glob(p, pi + 1, s, si + 1)

    if p[pi] != s[si]:
        return false

    return glob(p, pi + 1, s, si + 1)

fn path_part(kind: String, w: String) String:
    let sl = w.last_index_of("/").get(-1)
    let comp = w.drop(sl + 1)
    let dot = comp.last_index_of(".").get(-1)

    if kind == "dir":
        if sl < 0:
            return "./"

        return w.take(sl + 1)

    if kind == "notdir":
        return comp

    if kind == "suffix":
        if dot < 0:
            return ""

        return comp.drop(dot)

    if dot < 0:
        return w

    return w.take(sl + 1 + dot)

fn is_function(name: String) Bool:
    let names = [
        "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort",
        "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix",
        "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info",
        "error"
    ]
    return names.contains(name)

fn is_auto(name: String) Bool:
    return name.length() == 1 and "@<^?|*".contains(name)

fn rule_text(pre: List[String], ord: List[String]) String:
    var out = ":"
    if pre.length() > 0:
        out += " " + pre.join(" ")
    if ord.length() > 0:
        out += " | " + ord.join(" ")
    return out

fn eq_index(a: String) Int:
    let k = find_from(a.chars(), "=", 0)
    if k > 0:
        return k

    return -1

# ---------- the make state ----------

impl Make:
    var fn begin() Unit:
        self.vars = Map[String, Var]()
        self.cli = Set[String]()
        self.locals = Map[String, String]()
        self.expanding = List[String]()
        self.explicit = Map[String, Rule]()
        self.explicit_names = List[String]()
        self.patterns = List[Pattern]()
        self.phony = List[String]()
        self.frames = List[Frame]()
        self.line = 0
        self.is_open = false
        self.open_dummy = false
        self.open_targets = List[String]()
        self.open_rule = empty_rule()
        self.open_line = 0
        self.memo = Map[String, Bool]()
        self.stack = List[String]()
        self.visited = Set[String]()
        self.out = List[String]()
        self.ran = 0
        self.dry = false

    fn fail(at: Int, msg: String) Stop:
        if at > 0:
            return Stop("Makefile:{at}: *** {msg}.  Stop.")

        return Stop("make: *** {msg}.  Stop.")

    fn fatal(msg: String) Stop:
        return self.fail(self.line, msg)

    fn is_defined(name: String) Bool:
        if let v = self.vars.get(name).clone():
            return v.value != ""

        return false

    fn active() Bool:
        if self.frames.length() == 0:
            return true

        let f = self.frames[self.frames.length() - 1].clone()
        if f.in_else:
            return f.parent and not f.cond

        return f.parent and f.cond

    # ----- expansion -----

    var fn expand(text: String) Result[String, Stop]:
        let cs = text.chars()
        let n = cs.length()
        var out = ""
        var i = 0

        while i < n:
            if cs[i] != "$":
                out += cs[i]
                i += 1
            else if i + 1 >= n:
                i += 1
            else if cs[i + 1] == "$":
                out += "$"
                i += 2
            else if cs[i + 1] == "(" or cs[i + 1] == "\{":
                let j = match_close(cs, i + 1)
                if j < 0:
                    return error(self.fatal("unterminated variable reference"))

                let piece = try self.reference(cat(cs, i + 2, j))
                out += piece
                i = j + 1
            else:
                let piece = try self.value_of(cs[i + 1])
                out += piece
                i += 2

        return ok(out)

    var fn reference(inner: String) Result[String, Stop]:
        let cs = inner.chars()
        let n = cs.length()
        var k = 0
        while k < n and cs[k] != " " and cs[k] != "\t":
            k += 1
        if k > 0 and k < n and is_function(cat(cs, 0, k)):
            return self.call(cat(cs, 0, k), cat(cs, k + 1, n))

        let name_text = try self.expand(inner)
        let nc = name_text.chars()
        let colon = find_from(nc, ":", 1)

        if colon > 0:
            let eqp = find_from(nc, "=", colon + 1)

            if eqp >= 0:
                let value = try self.value_of(cat(nc, 0, colon).trim())
                return ok(
                    subst_ref(
                        value, cat(nc, colon + 1, eqp), cat(nc, eqp + 1, nc.length())
                    )
                )

        return self.value_of(name_text.trim())

    var fn value_of(name: String) Result[String, Stop]:
        if is_auto(name) or self.locals.contains(name):
            return ok(self.locals.get_or(name, ""))

        if let v = self.vars.get(name).clone():
            if not v.recursive:
                return ok(v.value.clone())
            if self.expanding.contains(name):
                return error(
                    self.fatal(
                        "Recursive variable '{name}' references itself (eventually)"
                    )
                )

            self.expanding.append(name.clone())

            let r = try self.expand(v.value.clone())
            let _p = self.expanding.pop()
            return ok(r)

        return ok("")

    var fn call(name: String, rest: String) Result[String, Stop]:
        let raw = split_args(rest)

        if name == "subst":
            let from = try self.expand(arg(raw, 0))
            let to = try self.expand(arg(raw, 1))
            let text = try self.expand(arg(raw, 2))
            if from == "":
                return ok(text)

            return ok(text.replace(from, to))

        if name == "patsubst":
            let pat = try self.expand(arg(raw, 0))
            let rep = try self.expand(arg(raw, 1))
            let text = try self.expand(arg(raw, 2))
            var out = List[String]()

            for w in words(text):
                if let stem = pmatch(pat, w):
                    out.append(fill(rep, stem))
                else:
                    out.append(w)

            return ok(out.join(" "))

        if name == "strip":
            let text = try self.expand(arg(raw, 0))
            return ok(words(text).join(" "))

        if name == "findstring":
            let find = try self.expand(arg(raw, 0))
            let text = try self.expand(arg(raw, 1))
            if text.contains(find):
                return ok(find)

            return ok("")

        if name == "filter" or name == "filter-out":
            let pats = words(try self.expand(arg(raw, 0)))
            let text = try self.expand(arg(raw, 1))
            let keep = name == "filter"
            var out = List[String]()
            for w in words(text):
                if matches_any(pats, w) == keep:
                    out.append(w)
            return ok(out.join(" "))

        if name == "sort":
            let text = try self.expand(arg(raw, 0))
            return ok(dedupe(words(text).sorted()).join(" "))

        if name == "word":
            let k = (try self.expand(arg(raw, 0))).trim().parse_int().get(0)
            let ws = words(try self.expand(arg(raw, 1)))
            if k >= 1 and k <= ws.length():
                return ok(ws[k - 1].clone())

            return ok("")

        if name == "wordlist":
            let a = (try self.expand(arg(raw, 0))).trim().parse_int().get(0)
            let b = (try self.expand(arg(raw, 1))).trim().parse_int().get(0)
            let ws = words(try self.expand(arg(raw, 2)))
            if a < 1 or b < a or a > ws.length():
                return ok("")

            var hi = b
            if hi > ws.length():
                hi = ws.length()

            var out = List[String]()
            var k = a - 1

            while k < hi:
                out.append(ws[k].clone())
                k += 1

            return ok(out.join(" "))

        if name == "words":
            let ws = words(try self.expand(arg(raw, 0)))
            return ok("{ws.length()}")

        if name == "firstword" or name == "lastword":
            let ws = words(try self.expand(arg(raw, 0)))
            if ws.length() == 0:
                return ok("")
            if name == "firstword":
                return ok(ws[0].clone())

            return ok(ws[ws.length() - 1].clone())

        if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
            let ws = words(try self.expand(arg(raw, 0)))
            var out = List[String]()

            for w in ws:
                let piece = path_part(name, w)
                if piece != "":
                    out.append(piece)

            return ok(out.join(" "))

        if name == "addprefix" or name == "addsuffix":
            let x = try self.expand(arg(raw, 0))
            let ws = words(try self.expand(arg(raw, 1)))
            var out = List[String]()

            for w in ws:
                if name == "addprefix":
                    out.append(x + w)
                else:
                    out.append(w + x)

            return ok(out.join(" "))

        if name == "wildcard":
            let pats = words(try self.expand(arg(raw, 0)))
            let names = self.files.keys().sorted()
            var out = List[String]()

            for p in pats:
                let pc = p.chars()
                for f in names:
                    if glob(pc, 0, f.chars(), 0):
                        out.append(f.clone())

            return ok(out.join(" "))

        if name == "foreach":
            let var_name = (try self.expand(arg(raw, 0))).trim()
            let items = words(try self.expand(arg(raw, 1)))
            let text = arg(raw, 2)
            let saved = self.locals.get(var_name).clone()
            var out = List[String]()

            for w in items:
                self.locals.add(var_name.clone(), w.clone())

                let piece = try self.expand(text.clone())
                out.append(piece)

            if let s = saved:
                self.locals.add(var_name.clone(), s)
            else:
                self.locals.remove(var_name.clone())

            return ok(out.join(" "))

        if name == "if":
            let c = try self.expand(arg(raw, 0))
            if c.trim() != "":
                return self.expand(arg(raw, 1))

            return self.expand(arg(raw, 2))

        if name == "info":
            let t = try self.expand(arg(raw, 0))
            emit(t + "\n")
            return ok("")

        if name == "error":
            let t = try self.expand(arg(raw, 0))
            return error(self.fatal(t))

        return ok("")

    # ----- parsing -----

    var fn parse(mk: List[String]) Result[Unit, Stop]:
        for ln in logical_lines(mk):
            try self.process(ln)
        self.line = 0
        self.close_rule()

        if self.frames.length() > 0:
            let f = self.frames[self.frames.length() - 1].clone()
            return error(self.fail(f.line, "missing 'endif'"))

        return ok(unit)

    var fn process(ln: Line) Result[Unit, Stop]:
        self.line = ln.number

        let raw = ln.text.clone()

        if raw.starts_with("\t"):
            let body = strip_tabs(raw)
            if body.trim() == "":
                return ok(unit)
            if not self.active():
                return ok(unit)
            if not self.is_open:
                return error(self.fatal("recipe commences before first target"))

            self.open_rule.recipe.append(Line(number: ln.number, text: body))
            return ok(unit)

        let text = strip_comment(raw).trim()
        if text == "":
            return ok(unit)

        let first = words(text) [0]
        let rest = text.drop(first.length()).trim()
        let is_dir = (
            first == "ifdef"
            or first == "ifndef"
            or first == "ifeq"
            or first == "ifneq"
            or ((first == "else" or first == "endif") and rest == "")
        )

        if is_dir:
            self.close_rule()
            return self.directive(first, rest)

        if not self.active():
            return ok(unit)

        self.close_rule()
        return self.statement(text)

    var fn directive(word: String, rest: String) Result[Unit, Stop]:
        if word == "ifdef" or word == "ifndef":
            let parent = self.active()
            var cond = false

            if parent:
                let name = (try self.expand(rest)).trim()
                let defined = self.is_defined(name)

                if word == "ifdef":
                    cond = defined
                else:
                    cond = not defined

            self.frames.append(
                Frame(
                    parent: parent, cond: cond, in_else: false, line: self.line
                )
            )
            return ok(unit)

        if word == "ifeq" or word == "ifneq":
            let parent = self.active()
            var cond = false

            if parent:
                var inner = ""
                var good = (
                    rest.starts_with("(")
                    and rest.ends_with(")")
                    and rest.length() >= 2
                )
                if good:
                    inner = rest.drop(1).take(rest.length() - 2)

                let parts = split_top(inner)
                if not good or parts.length() != 2:
                    return error(self.fatal("invalid syntax in conditional"))

                let a = (try self.expand(parts[0].trim())).trim()
                let b = (try self.expand(parts[1].trim())).trim()

                if word == "ifeq":
                    cond = a == b
                else:
                    cond = a != b

            self.frames.append(
                Frame(
                    parent: parent, cond: cond, in_else: false, line: self.line
                )
            )
            return ok(unit)

        if word == "else":
            if self.frames.length() == 0:
                return error(self.fatal("extraneous 'else'"))

            let k = self.frames.length() - 1
            let f = self.frames[k].clone()
            if f.in_else:
                return error(self.fatal("extraneous 'else'"))

            self.frames[k] = Frame(
                parent: f.parent, cond: f.cond, in_else: true, line: f.line
            )
            return ok(unit)

        if self.frames.length() == 0:
            return error(self.fatal("extraneous 'endif'"))

        let _f = self.frames.pop()
        return ok(unit)

    var fn statement(text: String) Result[Unit, Stop]:
        let cs = text.chars()
        let eq = find_from(cs, "=", 0)
        let col = find_colon(cs)
        if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
            return self.assignment(cs, eq)
        if col >= 0:
            return self.rule_line(cs, col)

        let t = try self.expand(text)
        if t.trim() != "":
            return error(self.fatal("missing separator"))

        return ok(unit)

    var fn assignment(cs: List[String], eq: Int) Result[Unit, Stop]:
        var name_end = eq
        var op = "="

        if eq >= 1 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
            name_end = eq - 1
            op = cs[eq - 1] + "="

        let raw_name = try self.expand(cat(cs, 0, name_end))
        let name = raw_name.trim()
        if name == "":
            return error(self.fatal("empty variable name"))

        let value = cat(cs, eq + 1, cs.length()).trim()
        if self.cli.contains(name):
            return ok(unit)

        if op == "=":
            self.vars.add(name.clone(), Var(recursive: true, value: value))
        else if op == ":=":
            let v = try self.expand(value)
            self.vars.add(name.clone(), Var(recursive: false, value: v))
        else if op == "?=":
            if not self.vars.contains(name):
                self.vars.add(name.clone(), Var(recursive: true, value: value))
        else:
            if let old = self.vars.get(name).clone():
                if old.recursive:
                    self.vars.add(
                        name.clone(),
                        Var(
                            recursive: true,
                            value: join_sep(
                                old.value.clone(), value
                            )
                        )
                    )
                else:
                    let v = try self.expand(value)
                    self.vars.add(
                        name.clone(),
                        Var(
                            recursive: false,
                            value: join_sep(
                                old.value.clone(), v
                            )
                        )
                    )
            else:
                self.vars.add(name.clone(), Var(recursive: true, value: value))

        return ok(unit)

    var fn rule_line(cs: List[String], col: Int) Result[Unit, Stop]:
        let n = cs.length()
        let before = cat(cs, 0, col)
        let semi = find_from(cs, ";", col + 1)
        var prereq_text = cat(cs, col + 1, n)
        var cmd = ""
        var has_cmd = false

        if semi >= 0:
            prereq_text = cat(cs, col + 1, semi)
            cmd = cat(cs, semi + 1, n).trim()
            has_cmd = true

        let targets = (try self.expand(before)).trim()
        let pre = try self.expand(prereq_text)
        let pc = pre.chars()
        var normal = words(pre)
        var order = List[String]()
        let bar = find_from(pc, "|", 0)

        if bar >= 0:
            normal = words(cat(pc, 0, bar))
            order = words(cat(pc, bar + 1, pc.length()))

        self.is_open = true
        self.open_line = self.line
        self.open_targets = words(targets)

        if targets == ".PHONY":
            self.open_dummy = true
            for w in normal:
                if not self.phony.contains(w):
                    self.phony.append(w.clone())
            for w in order:
                if not self.phony.contains(w):
                    self.phony.append(w.clone())
        else:
            self.open_dummy = false

        self.open_rule = Rule(prereqs: normal, order: order, recipe: List[Line]())
        if has_cmd:
            self.open_rule.recipe.append(Line(number: self.line, text: cmd))
        return ok(unit)

    var fn close_rule() Unit:
        if not self.is_open:
            return

        self.is_open = false
        if self.open_dummy:
            return

        let targets = self.open_targets.clone()
        let rule = self.open_rule.clone()

        for t in targets:
            if t.contains("%"):
                self.patterns.append(Pattern(pat: t.clone(), rule: rule.clone()))
            else:
                self.add_explicit(t.clone(), rule.clone(), self.open_line)

    var fn add_explicit(t: String, rule: Rule, line: Int) Unit:
        var cur = empty_rule()

        if let old = self.explicit.get(t).clone():
            cur = old
        else:
            self.explicit_names.append(t.clone())

        for p in rule.prereqs:
            cur.prereqs.append(p.clone())
        for p in rule.order:
            cur.order.append(p.clone())

        if rule.recipe.length() > 0:
            if cur.recipe.length() > 0:
                emit("Makefile:{line}: warning: overriding recipe for target '{t}'\n")
            cur.recipe = rule.recipe.clone()

        self.explicit.add(t.clone(), cur)

    # ----- rule resolution -----

    fn can_make(name: String, depth: Int) Bool:
        if self.files.contains(name):
            return true
        if self.explicit.contains(name):
            return true
        if self.phony.contains(name):
            return true

        return self.find_pattern(name, depth + 1).get(-1) >= 0

    fn find_pattern(t: String, depth: Int) Optional[Int]:
        if depth > 8:
            return none

        var k = 0

        while k < self.patterns.length():
            let p = self.patterns[k].clone()
            k += 1
            if p.rule.recipe.length() == 0:
                continue

            if let stem = pmatch(p.pat, t):
                if stem == "":
                    continue

                var all_ok = true
                for q in p.rule.prereqs:
                    if not self.can_make(fill(q, stem), depth):
                        all_ok = false
                for q in p.rule.order:
                    if not self.can_make(fill(q, stem), depth):
                        all_ok = false
                if all_ok:
                    return some(k - 1)

        return none

    fn resolve(t: String) Resolved:
        if let r = self.explicit.get(t).clone():
            if r.recipe.length() > 0:
                return Resolved(
                    found: true, prereqs: r.prereqs.clone(), order: r.order.clone(),
                    recipe: r.recipe.clone(), stem: ""
                )

        let idx = self.find_pattern(t, 0).get(-1)

        if idx >= 0:
            let p = self.patterns[idx].clone()
            let stem = pmatch(p.pat, t).get("")
            var pre = List[String]()
            var ord = List[String]()
            for q in p.rule.prereqs:
                pre.append(fill(q, stem))
            for q in p.rule.order:
                ord.append(fill(q, stem))

            if let r = self.explicit.get(t).clone():
                for q in r.prereqs:
                    pre.append(q.clone())
                for q in r.order:
                    ord.append(q.clone())

            return Resolved(
                found: true, prereqs: pre, order: ord, recipe: p.rule.recipe.clone(),
                stem: stem
            )

        if let r = self.explicit.get(t).clone():
            return Resolved(
                found: true, prereqs: r.prereqs.clone(), order: r.order.clone(),
                recipe: List[Line](), stem: ""
            )

        return Resolved(
            found: false, prereqs: List[String](), order: List[String](),
            recipe: List[Line](), stem: ""
        )

    fn default_goal() String:
        for n in self.explicit_names:
            if not n.starts_with("."):
                return n.clone()
        return ""

    fn goal_uptodate(g: String) Bool:
        let r = self.resolve(g)
        if r.recipe.length() > 0:
            return true

        return not self.phony.contains(g) and self.files.contains(g)

    # ----- building -----

    var fn update(t: String, needed_by: String) Result[Bool, Stop]:
        if let m = self.memo.get(t).clone():
            return ok(m)

        let pos = position(self.stack, t)
        if pos >= 0:
            return error(circular(self.stack, pos, t))

        let r = self.resolve(t)

        if not r.found:
            var result = false

            if self.files.contains(t):
                result = false
            else if self.phony.contains(t):
                result = true
            else if needed_by == "":
                return error(Stop("make: *** No rule to make target '{t}'.  Stop."))
            else:
                return error(
                    Stop(
                        "make: *** No rule to make target '{t}', needed by '{needed_by}'.  Stop."
                    )
                )

            self.memo.add(t.clone(), result)
            return ok(result)

        self.stack.append(t.clone())

        let was = self.files.contains(t)
        let old = self.files.get_or(t, 0)
        var changed_any = false
        var newer = false
        var changed = List[String]()

        for p in dedupe(r.prereqs):
            let c = try self.update(p.clone(), t.clone())

            if c:
                changed_any = true
                changed.append(p.clone())

            if was and self.files.get_or(p, -1) > old:
                newer = true

        for o in dedupe(r.order):
            let _c = try self.update(o.clone(), t.clone())

        let rebuild = (
            self.phony.contains(t)
            or not self.files.contains(t)
            or changed_any
            or newer
        )
        var flag = false

        if rebuild:
            flag = true
            if r.recipe.length() > 0:
                try self.run_recipe(t.clone(), r, was, old, changed)

        let _s = self.stack.pop()
        self.memo.add(t.clone(), flag)
        return ok(flag)

    var fn run_recipe(
        t: String,
        r: Resolved,
        was: Bool,
        old: Int,
        changed: List[String]
    ) Result[Unit, Stop]:
        self.ran += 1

        let uniq = dedupe(r.prereqs)
        var newer = List[String]()
        for p in uniq:
            if not was or changed.contains(p) or self.files.get_or(p, -1) > old:
                newer.append(p.clone())

        var first = ""
        if r.prereqs.length() > 0:
            first = r.prereqs[0].clone()
        self.locals = Map[String, String]()
        self.locals.add("@", t.clone())
        self.locals.add("<", first)
        self.locals.add("^", uniq.join(" "))
        self.locals.add("?", newer.join(" "))
        self.locals.add("|", dedupe(r.order).join(" "))
        self.locals.add("*", r.stem.clone())

        for ln in r.recipe:
            self.line = ln.number

            let expanded = (try self.expand(ln.text.clone())).trim()
            let cs = expanded.chars()
            var silent = false
            var ignore = false
            var k = 0

            while (
                k < cs.length()
                and (
                    cs[k] == "@"
                    or cs[k] == "-"
                    or cs[k] == "+"
                    or cs[k] == " "
                    or cs[k] == "\t"
                )
            ):
                if cs[k] == "@":
                    silent = true
                if cs[k] == "-":
                    ignore = true
                k += 1

            let cmd = cat(cs, k, cs.length())

            if self.dry:
                emit(cmd + "\n")
            else:
                if not silent:
                    emit(cmd + "\n")

                let status = self.simulate(cmd)

                if status != 0:
                    if ignore:
                        emit(
                            "make: [Makefile:{ln.number}: {t}] Error {status} (ignored)\n"
                        )
                    else:
                        return error(
                            Stop(
                                "make: *** [Makefile:{ln.number}: {t}] Error {status}"
                            )
                        )

        self.locals = Map[String, String]()

        if not self.dry and not self.phony.contains(t):
            self.clock += 1
            self.files.add(t.clone(), self.clock)

        return ok(unit)

    var fn simulate(cmd: String) Int:
        let w = words(cmd)
        if w.length() == 0:
            return 0

        let first = w[0].clone()
        if first == "false":
            return 1

        if first == "exit":
            if w.length() < 2:
                return 0

            return w[1].parse_int().get(2)

        if first == "touch":
            for a in tail(w):
                if not a.starts_with("-"):
                    self.clock += 1
                    self.files.add(a.clone(), self.clock)

            return 0

        if first == "rm":
            for a in tail(w):
                if not a.starts_with("-"):
                    self.files.remove(a.clone())
            return 0

        if first == "cp" and w.length() == 3:
            let src = w[1].clone()

            if not self.files.contains(src):
                emit("cp: cannot stat '{src}': No such file or directory\n")
                return 1

            self.clock += 1
            self.files.add(w[2].clone(), self.clock)
            return 0

        if first == "echo":
            var items = List[String]()
            for a in tail(w):
                items.append(a.replace("\"", "").replace("'", ""))
            emit(items.join(" ") + "\n")
            return 0

        return 0

    var fn visit(t: String) Result[Unit, Stop]:
        let pos = position(self.stack, t)
        if pos >= 0:
            return error(circular(self.stack, pos, t))
        if self.visited.contains(t):
            return ok(unit)

        let r = self.resolve(t)
        self.stack.append(t.clone())
        for p in dedupe(r.prereqs):
            try self.visit(p.clone())
        for p in dedupe(r.order):
            try self.visit(p.clone())

        let _s = self.stack.pop()
        self.visited.add(t.clone())
        self.out.append(t.clone())
        return ok(unit)

    var fn deps(x: String) Result[Unit, Stop]:
        let r = self.resolve(x)
        self.stack.append(x.clone())
        for p in dedupe(r.prereqs):
            try self.visit(p.clone())
        for p in dedupe(r.order):
            try self.visit(p.clone())

        let _s = self.stack.pop()
        return ok(unit)

# ---------- requests ----------

fn split_request(var m: Make, args: List[String]) List[String]:
    var goals = List[String]()

    for a in args:
        let k = eq_index(a)

        if k > 0:
            let name = a.take(k)
            m.cli.add(name.clone())
            m.vars.add(name.clone(), Var(recursive: true, value: a.drop(k + 1)))
        else:
            goals.append(a.clone())

    return goals

fn load_makefile(var m: Make, mk: List[String]) Bool:
    let r = m.parse(mk)

    if r.is_error():
        emit(r.err().text + "\n")
        return false

    m.line = 0
    return true

fn build_request(var m: Make, mk: List[String], args: List[String], dry: Bool) Unit:
    m.begin()

    var goals = split_request(var m, args)
    m.dry = dry
    if not load_makefile(var m, mk):
        return

    if goals.length() == 0:
        let d = m.default_goal()

        if d == "":
            emit("make: *** No targets.  Stop.\n")
            return

        goals.append(d)

    for g in goals:
        let before = m.ran
        let r = m.update(g.clone(), "")

        if r.is_error():
            emit(r.err().text + "\n")
            return

        if m.ran == before:
            if m.goal_uptodate(g):
                emit("make: '{g}' is up to date.\n")
            else:
                emit("make: Nothing to be done for '{g}'.\n")

fn deps_request(var m: Make, mk: List[String], args: List[String]) Unit:
    m.begin()

    let goals = split_request(var m, args)

    if goals.length() != 1:
        emit("usage: deps TARGET\n")
        return

    if not load_makefile(var m, mk):
        return

    let r = m.deps(goals[0].clone())

    if r.is_error():
        emit(r.err().text + "\n")
        return

    if m.out.length() == 0:
        emit("(no prerequisites)\n")
    for x in m.out:
        emit(x + "\n")

fn targets_request(var m: Make, mk: List[String], args: List[String]) Unit:
    m.begin()

    let _goals = split_request(var m, args)
    if not load_makefile(var m, mk):
        return

    let d = m.default_goal()
    if d != "":
        emit("default: {d}\n")

    for name in m.explicit_names:
        let rule = m.explicit.get_or(name, empty_rule())
        emit(name + rule_text(rule.prereqs, rule.order) + "\n")

    for p in m.patterns:
        emit("pattern {p.pat}" + rule_text(p.rule.prereqs, p.rule.order) + "\n")
    if m.phony.length() > 0:
        emit("phony: " + m.phony.join(" ") + "\n")

fn expand_request(var m: Make, mk: List[String], line: String) Unit:
    m.begin()
    if not load_makefile(var m, mk):
        return

    let text = line.trim().drop(6).trim()
    let r = m.expand(text)

    if r.is_error():
        emit(r.err().text + "\n")
        return

    emit("[" + r.get() + "]\n")

fn files_request(var m: Make) Unit:
    let names = m.files.keys().sorted()

    if names.length() == 0:
        emit("(no files)\n")
        return

    for n in names:
        let t = m.files.get_or(n, 0)
        emit("{n} {t}\n")

fn touch_request(var m: Make, w: List[String]) Unit:
    if w.length() == 2:
        m.clock += 1
        m.files.add(w[1].clone(), m.clock)
        return

    if w.length() == 3:
        if let n = w[2].parse_int():
            m.files.add(w[1].clone(), n)
            if n > m.clock:
                m.clock = n
            return

    emit("bad request\n")

fn rm_request(var m: Make, w: List[String]) Unit:
    for f in tail(w):
        m.files.remove(f.clone())

fn request(var m: Make, mk: List[String], line: String) Unit:
    let w = words(line)
    let cmd = w[0].clone()
    let args = tail(w)

    if cmd == "build":
        build_request(var m, mk, args, false)
    else if cmd == "dry":
        build_request(var m, mk, args, true)
    else if cmd == "deps":
        deps_request(var m, mk, args)
    else if cmd == "targets":
        targets_request(var m, mk, args)
    else if cmd == "expand":
        expand_request(var m, mk, line)
    else if cmd == "files":
        files_request(var m)
    else if cmd == "touch":
        touch_request(var m, w)
    else if cmd == "rm":
        rm_request(var m, w)
    else:
        emit("unknown request: {cmd}\n")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var all = List[String]()
    for l in lines:
        all.append(strip_cr(l.clone()))

    let n = all.length()
    var sep1 = -1
    var sep2 = -1
    var k = 0

    while k < n:
        if all[k] == "====":
            if sep1 < 0:
                sep1 = k
            else if sep2 < 0:
                sep2 = k

        k += 1

    var mk_end = n
    var tab_start = n
    var tab_end = n
    var req_start = n

    if sep1 >= 0:
        mk_end = sep1
        tab_start = sep1 + 1

        if sep2 >= 0:
            tab_end = sep2
            req_start = sep2 + 1

    let mk = slice_lines(all, 0, mk_end)
    var m = new_make()

    for l in slice_lines(all, tab_start, tab_end):
        let f = words(l)

        if f.length() == 2:
            if let v = f[1].parse_int():
                if v >= 0:
                    m.files.add(f[0].clone(), v)
                    if v > m.clock:
                        m.clock = v

    for l in slice_lines(all, req_start, n):
        let t = l.trim()
        if t == "" or t.starts_with("#"):
            continue

        emit("> " + l.trim_end() + "\n")
        request(var m, mk, l)

    return 0
