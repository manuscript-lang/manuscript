from "@std/io.ms" import stdout, stdin
from "@std/streams.ms" import read_lines

# Simulator state for one run of the program. Persistent across requests:
# files and clock. Everything else is rebuilt by each make invocation.
type Variable:
    recursive: Bool
    value: String

type Line:
    text: String
    num: Int

type Rule:
    name: String
    normal: List[String]
    order_only: List[String]
    recipe: List[Line]

# A rule whose logical line has been read but not yet stored; it stays open
# until a non-recipe line closes it.
type Open:
    has: Bool
    phony: Bool
    targets: List[String]
    normal: List[String]
    order_only: List[String]
    recipe: List[Line]
    line: Int

type Plan:
    found: Bool
    normal: List[String]
    order_only: List[String]
    recipe: List[Line]
    stem: String

type Frame:
    parent: Bool
    cond: Bool
    active: Bool
    has_else: Bool
    line: Int

type Directive:
    kind: String
    rest: String

type Bind:
    name: String
    value: String

# A fatal error. `text` is the complete line to print.
type Fail:
    text: String

impl Error for Fail:
    def message() -> String:
        return self.text.clone()

type Sim:
    files: Map[String, Int]
    clock: Int
    out: List[String]
    mk: List[String]
    dry: Bool
    line: Int
    cmd: Map[String, String]
    vars: Map[String, Variable]
    rules: List[Rule]
    rule_index: Map[String, Int]
    pats: List[Rule]
    phony: List[String]
    pending: Open
    frames: List[Frame]
    binds: List[Bind]
    autos: Map[String, String]
    expanding: List[String]
    memo: Map[String, Bool]
    stack: List[String]
    ran: Int
    dout: List[String]
    dset: Set[String]

export def main() -> Int:
    let input = read_lines(stdin()).get()
    var s = Sim(files: Map[String, Int](), clock: 0, out: List[String](), mk: List[String](), dry: False, line: 0, cmd: Map[String, String](), vars: Map[String, Variable](), rules: List[Rule](), rule_index: Map[String, Int](), pats: List[Rule](), phony: List[String](), pending: new_open(), frames: List[Frame](), binds: List[Bind](), autos: Map[String, String](), expanding: List[String](), memo: Map[String, Bool](), stack: List[String](), ran: 0, dout: List[String](), dset: Set[String]())
    var section = 0
    var table = List[String]()
    var requests = List[String]()
    for raw in input:
        let ln = strip_cr(raw)
        if section < 2 and ln == "====":
            section += 1
        elif section == 0:
            s.mk.append(ln)
        elif section == 1:
            table.append(ln)
        else:
            requests.append(ln)
    load_table(var s, table)
    for req in requests:
        handle_request(var s, req)
    var text = ""
    for line in s.out:
        text += line + "\n"
    var o = stdout()
    o.write(text).get()
    return 0

# ---------------------------------------------------------------- text helpers

def strip_cr(line: String) -> String:
    if line.ends_with("\r"):
        return join_range(line.chars(), 0, line.length() - 1)
    return line

def join_range(cs: List[String], a: Int, b: Int) -> String:
    var out = ""
    var i = a
    while i < b:
        out += cs[i]
        i += 1
    return out

def find_char(cs: List[String], ch: String, from: Int) -> Int:
    var i = from
    while i < cs.length():
        if cs[i] == ch:
            return i
        i += 1
    return -1

def last_index(cs: List[String], ch: String) -> Int:
    var i = cs.length() - 1
    while i >= 0:
        if cs[i] == ch:
            return i
        i -= 1
    return -1

def split_ws(text: String) -> List[String]:
    var out = List[String]()
    var cur = ""
    for c in text.chars():
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            if cur.length() > 0:
                out.append(cur)
                cur = ""
        else:
            cur += c
    if cur.length() > 0:
        out.append(cur)
    return out

def tail_of(xs: List[String]) -> List[String]:
    var out = List[String]()
    var i = 1
    while i < xs.length():
        out.append(xs[i].clone())
        i += 1
    return out

def join_slice(xs: List[String], a: Int, b: Int) -> String:
    var out = List[String]()
    var i = a
    while i < b:
        out.append(xs[i].clone())
        i += 1
    return out.join(" ")

def dedup(xs: List[String]) -> List[String]:
    var seen = Set[String]()
    var out = List[String]()
    for x in xs:
        if not seen.contains(x):
            seen.add(x.clone())
            out.append(x)
    return out

def join_sep(a: String, b: String) -> String:
    if a.length() == 0:
        return b
    if b.length() == 0:
        return a
    return a + " " + b

def fmt_rule(name: String, normal: List[String], order_only: List[String]) -> String:
    var out = name + ":"
    if normal.length() > 0:
        out += " " + normal.join(" ")
    if order_only.length() > 0:
        out += " | " + order_only.join(" ")
    return out

# Index of the matching closer for the opener at `at` ("(" or "{"), counting
# only brackets of the same kind. -1 if unterminated.
def find_close(cs: List[String], at: Int) -> Int:
    let opener = cs[at]
    var closer = ")"
    if opener == "{":
        closer = "}"
    var depth = 0
    var j = at
    while j < cs.length():
        if cs[j] == opener:
            depth += 1
        elif cs[j] == closer:
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1

# Index of the first ':' outside any $(...) / ${...} reference and before any
# ';', or -1.
def top_colon(cs: List[String]) -> Int:
    var i = 0
    while i < cs.length():
        let c = cs[i]
        if c == ";":
            return -1
        if c == "$" and i + 1 < cs.length():
            let nx = cs[i + 1]
            if nx == "(" or nx == "{":
                let close = find_close(cs, i + 1)
                if close < 0:
                    return -1
                i = close + 1
            else:
                i += 2
        elif c == ":":
            return i
        else:
            i += 1
    return -1

# Splits at top-level commas (parentheses and braces nest); each part trimmed.
def split_args(t: String) -> List[String]:
    let cs = t.chars()
    var out = List[String]()
    var depth = 0
    var start = 0
    var i = 0
    while i < cs.length():
        let c = cs[i]
        if c == "(" or c == "{":
            depth += 1
        elif c == ")" or c == "}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append(join_range(cs, start, i).trim())
            start = i + 1
        i += 1
    out.append(join_range(cs, start, cs.length()).trim())
    return out

def arg_at(args: List[String], i: Int) -> String:
    if i < args.length():
        return args[i].clone()
    return ""

# Stem of `word` against `pat`; a pattern without % must match exactly.
def pat_stem(pat: String, word: String) -> Optional[String]:
    let pcs = pat.chars()
    let pc = find_char(pcs, "%", 0)
    if pc < 0:
        if pat == word:
            return some("")
        return none
    let pre = join_range(pcs, 0, pc)
    let suf = join_range(pcs, pc + 1, pcs.length())
    let wlen = word.length()
    let plen = pre.length()
    let slen = suf.length()
    if wlen < plen + slen:
        return none
    if not word.starts_with(pre) or not word.ends_with(suf):
        return none
    return some(join_range(word.chars(), plen, wlen - slen))

def subst_stem(rep: String, stem: String) -> String:
    let rcs = rep.chars()
    let pc = find_char(rcs, "%", 0)
    if pc < 0:
        return rep
    return join_range(rcs, 0, pc) + stem + join_range(rcs, pc + 1, rcs.length())

def patsubst_words(pat: String, rep: String, text: String) -> String:
    var out = List[String]()
    for w in split_ws(text):
        if let stem = pat_stem(pat, w):
            out.append(subst_stem(rep.clone(), stem))
        else:
            out.append(w)
    return out.join(" ")

def filter_words(pats: String, words: String, keep: Bool) -> String:
    let pl = split_ws(pats)
    var out = List[String]()
    for w in split_ws(words):
        var hit = False
        for p in pl:
            if let _stem = pat_stem(p, w):
                hit = True
        if hit == keep:
            out.append(w)
    return out.join(" ")

def sort_words(text: String) -> List[String]:
    let srt = split_ws(text).sorted()
    var out = List[String]()
    for w in srt:
        if out.length() == 0 or out[out.length() - 1] != w:
            out.append(w)
    return out

def path_one(name: String, w: String) -> String:
    let cs = w.chars()
    let slash = last_index(cs, "/")
    if name == "dir":
        if slash < 0:
            return "./"
        return join_range(cs, 0, slash + 1)
    let start = slash + 1
    if name == "notdir":
        return join_range(cs, start, cs.length())
    let dot = last_index(cs, ".")
    if name == "suffix":
        if dot < start:
            return ""
        return join_range(cs, dot, cs.length())
    if dot < start:
        return w
    return join_range(cs, 0, dot)

def path_words(name: String, text: String) -> String:
    var out = List[String]()
    for w in split_ws(text):
        let r = path_one(name, w)
        if r.length() > 0:
            out.append(r)
    return out.join(" ")

def glob_at(p: List[String], pi: Int, t: List[String], ti: Int) -> Bool:
    if pi == p.length():
        return ti == t.length()
    let c = p[pi]
    if c == "*":
        if glob_at(p, pi + 1, t, ti):
            return True
        if ti < t.length() and t[ti] != "/":
            return glob_at(p, pi, t, ti + 1)
        return False
    if ti >= t.length():
        return False
    if c == "?":
        return t[ti] != "/" and glob_at(p, pi + 1, t, ti + 1)
    return t[ti] == c and glob_at(p, pi + 1, t, ti + 1)

def wildcard_files(s: Sim, pats: String) -> String:
    var out = List[String]()
    for p in split_ws(pats):
        var hits = List[String]()
        for f in s.files.keys():
            if glob_at(p.chars(), 0, f.chars(), 0):
                hits.append(f)
        hits.sort()
        for h in hits:
            out.append(h)
    return out.join(" ")

def is_func_name(name: String) -> Bool:
    let names = ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
    return names.contains(name)

def is_auto(name: String) -> Bool:
    return name == "@" or name == "<" or name == "^" or name == "?" or name == "*" or name == "|"

# ---------------------------------------------------------------- output

def say(var s: Sim, text: String) -> Unit:
    s.out.append(text)

def make_fail(msg: String) -> Fail:
    return Fail(text: f"make: *** {msg}.  Stop.")

def fail_line(num: Int, msg: String) -> Fail:
    return Fail(text: f"Makefile:{num}: *** {msg}.  Stop.")

def fail_at(s: Sim, msg: String) -> Fail:
    if s.line > 0:
        return fail_line(s.line, msg)
    return make_fail(msg)

def report(var s: Sim, r: Result[Bool, Fail]) -> Unit:
    if r.is_error():
        say(var s, r.err().message())

# ---------------------------------------------------------------- variables and expansion

def is_defined(s: Sim, name: String) -> Bool:
    if s.cmd.contains(name):
        return s.cmd.get(name).get("").length() > 0
    if s.vars.contains(name):
        let v = s.vars.get(name).get(Variable(recursive: False, value: ""))
        return v.value.length() > 0
    return False

def expand_var(var s: Sim, name: String, value: String) -> Result[String, Fail]:
    if s.expanding.contains(name):
        return error(fail_at(s, f"Recursive variable '{name}' references itself (eventually)"))
    s.expanding.append(name)
    let r = try expand(var s, value)
    s.expanding.remove(-1)
    return ok(r)

def lookup(var s: Sim, name: String) -> Result[String, Fail]:
    var k = s.binds.length() - 1
    while k >= 0:
        if s.binds[k].name == name:
            return ok(s.binds[k].value.clone())
        k -= 1
    if is_auto(name):
        return ok(s.autos.get(name).get(""))
    if s.cmd.contains(name):
        let raw = s.cmd.get(name).get("")
        return expand_var(var s, name, raw)
    if s.vars.contains(name):
        let v = s.vars.get(name).get(Variable(recursive: False, value: ""))
        if v.recursive:
            return expand_var(var s, name, v.value)
        return ok(v.value.clone())
    return ok("")

def expand(var s: Sim, text: String) -> Result[String, Fail]:
    let cs = text.chars()
    let n = cs.length()
    var out = ""
    var i = 0
    while i < n:
        let c = cs[i]
        if c != "$":
            out += c
            i += 1
        elif i + 1 >= n:
            i += 1
        elif cs[i + 1] == "$":
            out += "$"
            i += 2
        elif cs[i + 1] == "(" or cs[i + 1] == "{":
            let close = find_close(cs, i + 1)
            if close < 0:
                return error(fail_at(s, "unterminated variable reference"))
            let inner = join_range(cs, i + 2, close)
            let v = try reference(var s, inner)
            out += v
            i = close + 1
        else:
            let v = try lookup(var s, cs[i + 1].clone())
            out += v
            i += 2
    return ok(out)

# The text inside $( ) or ${ }: a function call, a substitution reference or a variable name.
def reference(var s: Sim, inner: String) -> Result[String, Fail]:
    let cs = inner.chars()
    var k = 0
    while k < cs.length() and cs[k] != " " and cs[k] != "\t":
        k += 1
    if k > 0 and k < cs.length() and is_func_name(join_range(cs, 0, k)):
        return call_func(var s, join_range(cs, 0, k), join_range(cs, k + 1, cs.length()))
    let expanded = try expand(var s, inner)
    let name = expanded.trim()
    let ncs = name.chars()
    let colon = find_char(ncs, ":", 1)
    if colon > 0:
        let eq = find_char(ncs, "=", colon + 1)
        if eq > 0:
            let vname = join_range(ncs, 0, colon).trim()
            let from = join_range(ncs, colon + 1, eq)
            let to = join_range(ncs, eq + 1, ncs.length())
            let value = try lookup(var s, vname)
            if from.contains("%"):
                return ok(patsubst_words(from, to, value))
            return ok(patsubst_words("%" + from, "%" + to, value))
    return lookup(var s, name.clone())

def call_func(var s: Sim, name: String, raw: String) -> Result[String, Fail]:
    let args = split_args(raw)
    if name == "subst":
        let needle = try expand(var s, arg_at(args, 0))
        let repl = try expand(var s, arg_at(args, 1))
        let text = try expand(var s, arg_at(args, 2))
        if needle.length() == 0:
            return ok(text)
        return ok(text.replace(needle, repl))
    if name == "patsubst":
        let pat = try expand(var s, arg_at(args, 0))
        let rep = try expand(var s, arg_at(args, 1))
        let text = try expand(var s, arg_at(args, 2))
        return ok(patsubst_words(pat, rep, text))
    if name == "strip":
        let text = try expand(var s, arg_at(args, 0))
        return ok(split_ws(text).join(" "))
    if name == "findstring":
        let find = try expand(var s, arg_at(args, 0))
        let text = try expand(var s, arg_at(args, 1))
        if text.contains(find):
            return ok(find)
        return ok("")
    if name == "filter" or name == "filter-out":
        let pats = try expand(var s, arg_at(args, 0))
        let words = try expand(var s, arg_at(args, 1))
        return ok(filter_words(pats, words, name == "filter"))
    if name == "sort":
        let words = try expand(var s, arg_at(args, 0))
        return ok(sort_words(words).join(" "))
    if name == "word":
        let nth = try expand(var s, arg_at(args, 0))
        let text = try expand(var s, arg_at(args, 1))
        let ws = split_ws(text)
        if let k = nth.trim().parse_int():
            if k >= 1 and k <= ws.length():
                return ok(ws[k - 1].clone())
        return ok("")
    if name == "wordlist":
        let from_s = try expand(var s, arg_at(args, 0))
        let to_s = try expand(var s, arg_at(args, 1))
        let text = try expand(var s, arg_at(args, 2))
        let ws = split_ws(text)
        if let a = from_s.trim().parse_int():
            if let b = to_s.trim().parse_int():
                if a >= 1 and b >= a and a <= ws.length():
                    let e = ws.length() if b > ws.length() else b
                    return ok(join_slice(ws, a - 1, e))
        return ok("")
    if name == "words":
        let text = try expand(var s, arg_at(args, 0))
        return ok(f"{split_ws(text).length()}")
    if name == "firstword" or name == "lastword":
        let text = try expand(var s, arg_at(args, 0))
        let ws = split_ws(text)
        if ws.length() == 0:
            return ok("")
        if name == "firstword":
            return ok(ws[0].clone())
        return ok(ws[ws.length() - 1].clone())
    if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
        let text = try expand(var s, arg_at(args, 0))
        return ok(path_words(name, text))
    if name == "addprefix" or name == "addsuffix":
        let affix = try expand(var s, arg_at(args, 0))
        let words = try expand(var s, arg_at(args, 1))
        var out = List[String]()
        for w in split_ws(words):
            if name == "addprefix":
                out.append(affix + w)
            else:
                out.append(w + affix)
        return ok(out.join(" "))
    if name == "wildcard":
        let pats = try expand(var s, arg_at(args, 0))
        return ok(wildcard_files(s, pats))
    if name == "foreach":
        let var_name = (try expand(var s, arg_at(args, 0))).trim()
        let list = try expand(var s, arg_at(args, 1))
        var results = List[String]()
        for w in split_ws(list):
            s.binds.append(Bind(name: var_name.clone(), value: w))
            let r = try expand(var s, arg_at(args, 2))
            s.binds.remove(-1)
            results.append(r)
        return ok(results.join(" "))
    if name == "if":
        let cond = try expand(var s, arg_at(args, 0))
        if cond.trim().length() > 0:
            return expand(var s, arg_at(args, 1))
        return expand(var s, arg_at(args, 2))
    if name == "info":
        let text = try expand(var s, arg_at(args, 0))
        say(var s, text)
        return ok("")
    let text = try expand(var s, arg_at(args, 0))
    return error(fail_at(s, text))

# ---------------------------------------------------------------- parsing

def new_open() -> Open:
    return Open(has: False, phony: False, targets: List[String](), normal: List[String](), order_only: List[String](), recipe: List[Line](), line: 0)

def is_active(s: Sim) -> Bool:
    if s.frames.length() == 0:
        return True
    return s.frames[s.frames.length() - 1].active

# Joins physical lines ending in a backslash into logical lines.
def logical_lines(raw: List[String]) -> List[Line]:
    var out = List[Line]()
    var k = 0
    while k < raw.length():
        let num = k + 1
        var text = raw[k].clone()
        while text.ends_with("\\") and k + 1 < raw.length():
            let cs = text.chars()
            let body = join_range(cs, 0, cs.length() - 1).trim_end()
            k += 1
            text = body + " " + raw[k].trim_start()
        out.append(Line(text: text, num: num))
        k += 1
    return out

# Removes comments; `\#` stands for a literal '#'.
def strip_comment(text: String) -> String:
    let cs = text.chars()
    var out = ""
    var i = 0
    while i < cs.length():
        let c = cs[i]
        if c == "\\" and i + 1 < cs.length() and cs[i + 1] == "#":
            out += "#"
            i += 2
        elif c == "#":
            return out
        else:
            out += c
            i += 1
    return out

def strip_tabs(text: String) -> String:
    let cs = text.chars()
    var i = 0
    while i < cs.length() and cs[i] == "\t":
        i += 1
    return join_range(cs, i, cs.length())

# Recognises conditional directives. Kind is "" when the line is not one.
def directive_of(text: String) -> Directive:
    let cs = text.chars()
    var k = 0
    while k < cs.length() and cs[k] != " " and cs[k] != "\t" and cs[k] != "(":
        k += 1
    let word = join_range(cs, 0, k)
    let rest = join_range(cs, k, cs.length()).trim()
    let kinds = ["ifdef", "ifndef", "ifeq", "ifneq", "else", "endif"]
    if not kinds.contains(word):
        return Directive(kind: "", rest: "")
    if word == "ifeq" or word == "ifneq":
        return Directive(kind: word, rest: rest)
    if k < cs.length() and cs[k] == "(":
        return Directive(kind: "", rest: "")
    if word == "else" and rest.length() > 0:
        return Directive(kind: "", rest: "")
    return Directive(kind: word, rest: rest)

def equal_args(var s: Sim, rest: String) -> Result[Bool, Fail]:
    if rest.length() < 2 or not rest.starts_with("(") or not rest.ends_with(")"):
        return error(fail_at(s, "invalid syntax in conditional"))
    let parts = split_args(join_range(rest.chars(), 1, rest.length() - 1))
    if parts.length() != 2:
        return error(fail_at(s, "invalid syntax in conditional"))
    let a = try expand(var s, parts[0])
    let b = try expand(var s, parts[1])
    return ok(a.trim() == b.trim())

def handle_directive(var s: Sim, d: Directive) -> Result[Bool, Fail]:
    if d.kind == "ifdef" or d.kind == "ifndef" or d.kind == "ifeq" or d.kind == "ifneq":
        let parent = is_active(s)
        var cond = False
        if parent:
            if d.kind == "ifdef" or d.kind == "ifndef":
                let name = (try expand(var s, d.rest)).trim()
                let defined = is_defined(s, name)
                cond = defined if d.kind == "ifdef" else not defined
            else:
                let same = try equal_args(var s, d.rest)
                cond = same if d.kind == "ifeq" else not same
        s.frames.append(Frame(parent: parent, cond: cond, active: parent and cond, has_else: False, line: s.line))
        return ok(True)
    if d.kind == "else":
        if s.frames.length() == 0:
            return error(fail_at(s, "extraneous 'else'"))
        let k = s.frames.length() - 1
        if s.frames[k].has_else:
            return error(fail_at(s, "extraneous 'else'"))
        s.frames[k].has_else = True
        s.frames[k].active = s.frames[k].parent and not s.frames[k].cond
        return ok(True)
    if d.kind == "endif":
        if s.frames.length() == 0:
            return error(fail_at(s, "extraneous 'endif'"))
        s.frames.remove(-1)
    return ok(True)

def add_phony(var s: Sim, name: String) -> Unit:
    if not s.phony.contains(name):
        s.phony.append(name)

def add_explicit(var s: Sim, t: String, op: Open) -> Unit:
    if s.rule_index.contains(t):
        let idx = s.rule_index.get(t).get(0)
        for q in op.normal:
            s.rules[idx].normal.append(q.clone())
        for q in op.order_only:
            s.rules[idx].order_only.append(q.clone())
        if op.recipe.length() > 0:
            if s.rules[idx].recipe.length() > 0:
                say(var s, f"Makefile:{op.line}: warning: overriding recipe for target '{t}'")
            s.rules[idx].recipe = op.recipe.clone()
        return
    s.rule_index[t.clone()] = s.rules.length()
    s.rules.append(Rule(name: t, normal: op.normal.clone(), order_only: op.order_only.clone(), recipe: op.recipe.clone()))

# Stores the open rule (if any) into the makefile tables.
def close_open(var s: Sim) -> Unit:
    if not s.pending.has:
        return
    let op = s.pending.clone()
    s.pending = new_open()
    if op.phony:
        for q in op.normal:
            add_phony(var s, q.clone())
        for q in op.order_only:
            add_phony(var s, q.clone())
        return
    for t in op.targets:
        if t.contains("%"):
            s.pats.append(Rule(name: t.clone(), normal: op.normal.clone(), order_only: op.order_only.clone(), recipe: op.recipe.clone()))
        else:
            add_explicit(var s, t.clone(), op)

def assignment(var s: Sim, cs: List[String], eq: Int) -> Result[Bool, Fail]:
    var op = "="
    var name_end = eq
    if eq > 0 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
        op = cs[eq - 1].clone()
        name_end = eq - 1
    let name = (try expand(var s, join_range(cs, 0, name_end))).trim()
    if name.length() == 0:
        return error(fail_at(s, "empty variable name"))
    let value = join_range(cs, eq + 1, cs.length()).trim()
    if s.cmd.contains(name):
        return ok(True)
    if op == "=":
        s.vars[name] = Variable(recursive: True, value: value)
    elif op == ":":
        let v = try expand(var s, value)
        s.vars[name] = Variable(recursive: False, value: v)
    elif op == "?":
        if not s.vars.contains(name):
            s.vars[name] = Variable(recursive: True, value: value)
    elif not s.vars.contains(name):
        s.vars[name] = Variable(recursive: True, value: value)
    else:
        let old = s.vars.get(name).get(Variable(recursive: True, value: ""))
        if old.recursive:
            s.vars[name] = Variable(recursive: True, value: join_sep(old.value.clone(), value))
        else:
            let add = try expand(var s, value)
            s.vars[name] = Variable(recursive: False, value: join_sep(old.value.clone(), add))
    return ok(True)

def rule_line(var s: Sim, cs: List[String], col: Int) -> Result[Bool, Fail]:
    let n = cs.length()
    var prereq_end = n
    let semi = find_char(cs, ";", col + 1)
    if semi >= 0:
        prereq_end = semi
    let tx = try expand(var s, join_range(cs, 0, col))
    let targets = split_ws(tx)
    let px = try expand(var s, join_range(cs, col + 1, prereq_end))
    let pcs = px.chars()
    let bar = find_char(pcs, "|", 0)
    var normal = split_ws(px)
    var order_only = List[String]()
    if bar >= 0:
        normal = split_ws(join_range(pcs, 0, bar))
        order_only = split_ws(join_range(pcs, bar + 1, pcs.length()))
    var recipe = List[Line]()
    if semi >= 0:
        recipe.append(Line(text: join_range(cs, semi + 1, n), num: s.line))
    let is_phony = targets.length() == 1 and targets[0] == ".PHONY"
    s.pending = Open(has: True, phony: is_phony, targets: targets, normal: normal, order_only: order_only, recipe: recipe, line: s.line)
    return ok(True)

def parse_line(var s: Sim, text: String) -> Result[Bool, Fail]:
    let cs = text.chars()
    let eq = find_char(cs, "=", 0)
    let col = top_colon(cs)
    if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
        return assignment(var s, cs, eq)
    if col >= 0:
        return rule_line(var s, cs, col)
    let expanded = try expand(var s, text)
    if expanded.trim().length() == 0:
        return ok(True)
    return error(fail_at(s, "missing separator"))

def parse_lines(var s: Sim, lines: List[Line]) -> Result[Bool, Fail]:
    for ln in lines:
        s.line = ln.num
        if ln.text.starts_with("\t"):
            let body = strip_tabs(ln.text)
            if is_active(s) and body.trim().length() > 0:
                if not s.pending.has:
                    return error(fail_at(s, "recipe commences before first target"))
                s.pending.recipe.append(Line(text: body, num: ln.num))
        else:
            let text = strip_comment(ln.text).trim()
            if text.length() > 0:
                let d = directive_of(text)
                if d.kind.length() > 0:
                    close_open(var s)
                    let _d = try handle_directive(var s, d)
                elif is_active(s):
                    close_open(var s)
                    let _p = try parse_line(var s, text)
    close_open(var s)
    if s.frames.length() > 0:
        let top = s.frames[s.frames.length() - 1]
        return error(fail_line(top.line, "missing 'endif'"))
    return ok(True)

def parse_makefile(var s: Sim) -> Result[Bool, Fail]:
    s.vars = Map[String, Variable]()
    s.rules = List[Rule]()
    s.rule_index = Map[String, Int]()
    s.pats = List[Rule]()
    s.phony = List[String]()
    s.pending = new_open()
    s.frames = List[Frame]()
    s.binds = List[Bind]()
    s.autos = Map[String, String]()
    s.expanding = List[String]()
    s.memo = Map[String, Bool]()
    s.stack = List[String]()
    s.line = 0
    let lines = logical_lines(s.mk)
    let _parsed = try parse_lines(var s, lines)
    s.line = 0
    return ok(True)

def default_goal(s: Sim) -> String:
    for r in s.rules:
        if not r.name.starts_with("."):
            return r.name.clone()
    return ""

# ---------------------------------------------------------------- rule resolution

def can_make(s: Sim, name: String, level: Int) -> Bool:
    if s.files.contains(name) or s.rule_index.contains(name) or s.phony.contains(name):
        return True
    if level > 8:
        return False
    var k = 0
    while k < s.pats.length():
        let p = s.pats[k]
        if p.recipe.length() > 0:
            if let stem = pat_stem(p.name, name):
                if stem.length() > 0 and prereqs_ready(s, p, stem, level + 1):
                    return True
        k += 1
    return False

def prereqs_ready(s: Sim, p: Rule, stem: String, level: Int) -> Bool:
    for q in p.normal:
        if not can_make(s, subst_stem(q.clone(), stem), level):
            return False
    for q in p.order_only:
        if not can_make(s, subst_stem(q.clone(), stem), level):
            return False
    return True

def resolve(s: Sim, t: String) -> Plan:
    var ex = -1
    if s.rule_index.contains(t):
        ex = s.rule_index.get(t).get(-1)
    if ex >= 0 and s.rules[ex].recipe.length() > 0:
        return Plan(found: True, normal: s.rules[ex].normal.clone(), order_only: s.rules[ex].order_only.clone(), recipe: s.rules[ex].recipe.clone(), stem: "")
    var k = 0
    while k < s.pats.length():
        let p = s.pats[k]
        if p.recipe.length() > 0:
            if let stem = pat_stem(p.name, t):
                if stem.length() > 0 and prereqs_ready(s, p, stem, 1):
                    var normal = List[String]()
                    for q in p.normal:
                        normal.append(subst_stem(q.clone(), stem))
                    var order_only = List[String]()
                    for q in p.order_only:
                        order_only.append(subst_stem(q.clone(), stem))
                    if ex >= 0:
                        for q in s.rules[ex].normal:
                            normal.append(q.clone())
                        for q in s.rules[ex].order_only:
                            order_only.append(q.clone())
                    return Plan(found: True, normal: normal, order_only: order_only, recipe: p.recipe.clone(), stem: stem)
        k += 1
    if ex >= 0:
        return Plan(found: True, normal: s.rules[ex].normal.clone(), order_only: s.rules[ex].order_only.clone(), recipe: List[Line](), stem: "")
    return Plan(found: False, normal: List[String](), order_only: List[String](), recipe: List[Line](), stem: "")

# ---------------------------------------------------------------- building

def cycle_text(stack: List[String], t: String) -> String:
    var parts = List[String]()
    var on = False
    for x in stack:
        if x == t:
            on = True
        if on:
            parts.append(x)
    parts.append(t)
    return parts.join(" -> ")

def run_command(var s: Sim, cmd: String) -> Int:
    let ws = split_ws(cmd)
    let first = ws[0]
    if first == "false":
        return 1
    if first == "exit":
        if ws.length() > 1:
            if let code = ws[1].parse_int():
                return code
            return 2
        return 0
    if first == "touch":
        for w in tail_of(ws):
            if not w.starts_with("-"):
                s.clock += 1
                s.files[w] = s.clock
        return 0
    if first == "rm":
        for w in tail_of(ws):
            if not w.starts_with("-"):
                s.files.remove(w)
        return 0
    if first == "cp":
        if ws.length() == 3:
            let src = ws[1]
            if not s.files.contains(src):
                say(var s, f"cp: cannot stat '{src}': No such file or directory")
                return 1
            s.clock += 1
            s.files[ws[2].clone()] = s.clock
        return 0
    if first == "echo":
        var parts = List[String]()
        for w in tail_of(ws):
            parts.append(w.replace("\"", "").replace("'", ""))
        say(var s, parts.join(" "))
        return 0
    return 0

def run_recipe(var s: Sim, t: String, plan: Plan, was_in: Bool, old: Int) -> Result[Bool, Fail]:
    s.ran += 1
    let uniq = dedup(plan.normal.clone())
    var newer = List[String]()
    for p in uniq:
        var hit = (not was_in) or s.memo.get(p).get(False)
        if not hit and s.files.contains(p) and s.files.get(p).get(0) > old:
            hit = True
        if hit:
            newer.append(p.clone())
    var first = ""
    if plan.normal.length() > 0:
        first = plan.normal[0].clone()
    s.autos = Map[String, String]()
    s.autos["@"] = t.clone()
    s.autos["<"] = first
    s.autos["^"] = uniq.join(" ")
    s.autos["?"] = newer.join(" ")
    s.autos["|"] = dedup(plan.order_only.clone()).join(" ")
    s.autos["*"] = plan.stem.clone()
    for ln in plan.recipe:
        s.line = ln.num
        let expanded = try expand(var s, ln.text)
        let cs = expanded.trim().chars()
        var silent = False
        var ignore_err = False
        var k = 0
        while k < cs.length() and (cs[k] == "@" or cs[k] == "-" or cs[k] == "+" or cs[k] == " " or cs[k] == "\t"):
            if cs[k] == "@":
                silent = True
            if cs[k] == "-":
                ignore_err = True
            k += 1
        let body = join_range(cs, k, cs.length()).trim()
        if body.length() == 0:
            continue
        if s.dry:
            say(var s, body)
            continue
        if not silent:
            say(var s, body.clone())
        let status = run_command(var s, body)
        if status != 0:
            if ignore_err:
                say(var s, f"make: [Makefile:{ln.num}: {t}] Error {status} (ignored)")
            else:
                return error(Fail(text: f"make: *** [Makefile:{ln.num}: {t}] Error {status}"))
    s.autos = Map[String, String]()
    s.line = 0
    if not s.dry and not s.phony.contains(t):
        s.clock += 1
        s.files[t] = s.clock
    return ok(True)

def build_target(var s: Sim, t: String, parent: String) -> Result[Bool, Fail]:
    if s.memo.contains(t):
        return ok(s.memo.get(t).get(False))
    if s.stack.contains(t):
        return error(make_fail("Circular dependency detected: " + cycle_text(s.stack.clone(), t)))
    let plan = resolve(s, t)
    if not plan.found:
        if not s.files.contains(t) and not s.phony.contains(t):
            if parent.length() == 0:
                return error(make_fail(f"No rule to make target '{t}'"))
            return error(make_fail(f"No rule to make target '{t}', needed by '{parent}'"))
        let changed = not s.files.contains(t)
        s.memo[t] = changed
        return ok(changed)
    s.stack.append(t.clone())
    let was_in = s.files.contains(t)
    let old = s.files.get(t).get(0)
    var any_changed = False
    for p in dedup(plan.normal.clone()):
        let c = try build_target(var s, p, t)
        if c:
            any_changed = True
    var newer = False
    if was_in:
        for p in dedup(plan.normal.clone()):
            if s.files.contains(p) and s.files.get(p).get(0) > old:
                newer = True
    for p in dedup(plan.order_only.clone()):
        let _o = try build_target(var s, p, t)
    let rebuild = s.phony.contains(t) or not s.files.contains(t) or any_changed or newer
    var changed = False
    if rebuild:
        changed = True
        if plan.recipe.length() > 0:
            let _r = try run_recipe(var s, t.clone(), plan, was_in, old)
    s.stack.remove(-1)
    s.memo[t] = changed
    return ok(changed)

def build_goals(var s: Sim, goals: List[String]) -> Result[Bool, Fail]:
    for g in goals:
        let before = s.ran
        let _c = try build_target(var s, g.clone(), "")
        if s.ran == before:
            let plan = resolve(s, g)
            if plan.recipe.length() > 0 or (not s.phony.contains(g) and s.files.contains(g)):
                say(var s, f"make: '{g}' is up to date.")
            else:
                say(var s, f"make: Nothing to be done for '{g}'.")
    return ok(True)

def run_build(var s: Sim, goals: List[String]) -> Result[Bool, Fail]:
    let _parsed = try parse_makefile(var s)
    var todo = List[String]()
    if goals.length() > 0:
        todo = goals
    else:
        let dg = default_goal(s)
        if dg.length() == 0:
            return error(make_fail("No targets"))
        todo.append(dg)
    return build_goals(var s, todo)

def walk_deps(var s: Sim, node: String) -> Result[Bool, Fail]:
    let plan = resolve(s, node)
    var all = dedup(plan.normal.clone())
    for q in dedup(plan.order_only.clone()):
        all.append(q)
    for p in all:
        if not s.dset.contains(p):
            if s.stack.contains(p):
                return error(make_fail("Circular dependency detected: " + cycle_text(s.stack.clone(), p)))
            s.stack.append(p.clone())
            let _w = try walk_deps(var s, p)
            s.stack.remove(-1)
            s.dset.add(p.clone())
            s.dout.append(p)
    return ok(True)

def run_deps(var s: Sim, target: String) -> Result[Bool, Fail]:
    let _parsed = try parse_makefile(var s)
    s.dout = List[String]()
    s.dset = Set[String]()
    s.stack = List[String]()
    s.stack.append(target.clone())
    let _w = try walk_deps(var s, target)
    let found = s.dout.clone()
    if found.length() == 0:
        say(var s, "(no prerequisites)")
    for d in found:
        say(var s, d)
    return ok(True)

def run_targets(var s: Sim) -> Result[Bool, Fail]:
    let _parsed = try parse_makefile(var s)
    let dg = default_goal(s)
    if dg.length() > 0:
        say(var s, "default: " + dg)
    let rules = s.rules.clone()
    for r in rules:
        say(var s, fmt_rule(r.name, r.normal, r.order_only))
    let pats = s.pats.clone()
    for p in pats:
        say(var s, "pattern " + fmt_rule(p.name, p.normal, p.order_only))
    if s.phony.length() > 0:
        say(var s, "phony: " + s.phony.join(" "))
    return ok(True)

def run_expand(var s: Sim, text: String) -> Result[Bool, Fail]:
    let _parsed = try parse_makefile(var s)
    let v = try expand(var s, text)
    say(var s, f"[{v}]")
    return ok(True)

# ---------------------------------------------------------------- requests

def load_table(var s: Sim, lines: List[String]) -> Unit:
    for ln in lines:
        let f = split_ws(ln)
        if f.length() == 2:
            if let m = f[1].parse_int():
                s.files[f[0].clone()] = m
                if m > s.clock:
                    s.clock = m

# Sets command-line variables from the arguments and returns the other arguments.
def set_cmd(var s: Sim, args: List[String]) -> List[String]:
    s.cmd = Map[String, String]()
    var targets = List[String]()
    for a in args:
        let cs = a.chars()
        let eq = find_char(cs, "=", 0)
        if eq > 0:
            s.cmd[join_range(cs, 0, eq)] = join_range(cs, eq + 1, cs.length())
        else:
            targets.append(a)
    return targets

def list_files(var s: Sim) -> Unit:
    let names = s.files.keys().sorted()
    if names.length() == 0:
        say(var s, "(no files)")
    for n in names:
        let m = s.files.get(n).get(0)
        say(var s, f"{n} {m}")

def touch_request(var s: Sim, args: List[String]) -> Unit:
    if args.length() == 1:
        s.clock += 1
        s.files[args[0].clone()] = s.clock
    elif args.length() == 2:
        if let m = args[1].parse_int():
            s.files[args[0].clone()] = m
            if m > s.clock:
                s.clock = m
        else:
            say(var s, "bad request")
    else:
        say(var s, "bad request")

def after_word(req: String) -> String:
    let t = req.trim()
    return join_range(t.chars(), 6, t.length()).trim()

def handle_request(var s: Sim, raw: String) -> Unit:
    let req = raw.trim_end()
    let words = split_ws(req)
    if words.length() == 0:
        return
    if req.trim_start().starts_with("#"):
        return
    say(var s, "> " + req)
    let cmd = words[0]
    let args = tail_of(words)
    if cmd == "build" or cmd == "dry":
        s.dry = cmd == "dry"
        let goals = set_cmd(var s, args)
        report(var s, run_build(var s, goals))
    elif cmd == "deps":
        let targets = set_cmd(var s, args)
        if targets.length() != 1:
            say(var s, "usage: deps TARGET")
        else:
            report(var s, run_deps(var s, targets[0].clone()))
    elif cmd == "targets":
        let _ignored = set_cmd(var s, args)
        report(var s, run_targets(var s))
    elif cmd == "expand":
        s.cmd = Map[String, String]()
        report(var s, run_expand(var s, after_word(req)))
    elif cmd == "files":
        list_files(var s)
    elif cmd == "touch":
        touch_request(var s, args)
    elif cmd == "rm":
        for w in args:
            s.files.remove(w)
    else:
        say(var s, "unknown request: " + cmd)
