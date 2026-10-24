from "@std/io.ms" import read_all, stdin, stdout

# A fatal error. `text` is the complete line to print; empty means print nothing.
type Fatal:
    text: String

impl Error for Fatal:
    def message() -> String:
        return self.text

type Var:
    value: String
    simple: Bool
    cmd: Bool

# Simulator state shared by all requests: file table, clock, and output lines.
type St:
    files: Map[String, Int]
    clock: Int
    out: List[String]
    vars: Map[String, Var]

type Bind:
    name: String
    value: String

# Expansion context: the current line and, inside recipes, the automatic variables.
type Scope:
    line: Int
    auto_on: Bool
    target: String
    stem: String
    first: String
    deps: String
    newer: String
    order: String
    binds: List[Bind]

type Recipe:
    text: String
    line: Int

type Explicit:
    name: String
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]

type PatRule:
    pattern: String
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]

# The rule currently open for recipe lines.
type Rule:
    targets: List[String]
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]
    line: Int

type Frame:
    parent: Bool
    cond: Bool
    in_else: Bool
    line: Int

# A parsed Makefile, plus the build state for the request that uses it.
type Mk:
    rules: Map[String, Explicit]
    pats: List[PatRule]
    phony: List[String]
    is_open: Bool
    rule: Rule
    frames: List[Frame]
    memo: Map[String, Bool]
    stack: List[String]
    ran: Bool
    dry: Bool

type Resolved:
    found: Bool
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]
    stem: String

type Pair:
    a: String
    b: String

type Logical:
    num: Int
    text: String

def fatal(line: Int, msg: String) -> Fatal:
    if line > 0:
        return Fatal(text: f"Makefile:{line}: *** {msg}.  Stop.")

    return Fatal(text: f"make: *** {msg}.  Stop.")

def silent_abort() -> Fatal:
    return Fatal(text: "")

def is_space(c: String) -> Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

def nat(s: String) -> Optional[Int]:
    if s == "":
        return none

    for c in s.chars():
        if not "0123456789".contains(c):
            return none
    return s.parse_int()

def int_arg(s: String) -> Optional[Int]:
    return s.trim().parse_int()

def split_words(text: String) -> List[String]:
    var out: List[String] = []
    var cur = ""

    for c in text.chars():
        if is_space(c):
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur += c

    if cur != "":
        out.append(cur)
    return out

# Joins words with single spaces, dropping empty items.
def join_words(ws: List[String]) -> String:
    var kept: List[String] = []
    for w in ws:
        if w != "":
            kept.append(w)
    return kept.join(" ")

def index_of(cs: List[String], ch: String) -> Int:
    var k = 0

    while k < cs.length():
        if cs.get(k) == ch:
            return k

        k += 1

    return -1

def last_index(cs: List[String], ch: String) -> Int:
    var k = cs.length() - 1

    while k >= 0:
        if cs.get(k) == ch:
            return k

        k -= 1

    return -1

def strip_tabs(text: String) -> String:
    let cs = text.chars()
    var k = 0
    while k < cs.length() and cs.get(k) == "\t":
        k += 1
    return cs.drop(k).join("")

def strip_quotes(w: String) -> String:
    var out = ""
    for c in w.chars():
        if c != "'" and c != "\"":
            out += c
    return out

# Removes a comment; `\#` stands for a literal `#`.
def strip_comment(text: String) -> String:
    let cs = text.chars()
    let n = cs.length()
    var out = ""
    var k = 0

    while k < n:
        let c = cs.get(k)

        if c == "\\" and k + 1 < n and cs.get(k + 1) == "#":
            out += "#"
            k += 2
            continue

        if c == "#":
            break

        out += c
        k += 1

    return out

# Index of the first ':' outside references and before any ';', or -1.
def top_colon(cs: List[String]) -> Int:
    let n = cs.length()
    var depth = 0
    var k = 0

    while k < n:
        let c = cs.get(k)
        if c == ";":
            return -1

        if c == "$" and k + 1 < n and cs.get(k + 1) == "$":
            k += 2
            continue

        if c == "$" and k + 1 < n and (cs.get(k + 1) == "(" or cs.get(k + 1) == "{"):
            depth += 1
            k += 2
            continue

        if depth > 0 and (c == "(" or c == "{"):
            depth += 1
        elif depth > 0 and (c == ")" or c == "}"):
            depth -= 1
        elif depth == 0 and c == ":":
            return k

        k += 1

    return -1

def join_sep(a: String, b: String) -> String:
    if a == "" or b == "":
        return a + b

    return a + " " + b

def is_directive(w: String) -> Bool:
    return (
        w == "ifdef"
        or w == "ifndef"
        or w == "ifeq"
        or w == "ifneq"
        or w == "else"
        or w == "endif"
    )

def plain(line: Int) -> Scope:
    return Scope(
        line: line, auto_on: False, target: "", stem: "", first: "", deps: "",
        newer: "", order: "", binds: []
    )

def is_auto(name: String) -> Bool:
    return (
        name == "@"
        or name == "<"
        or name == "^"
        or name == "?"
        or name == "|"
        or name == "*"
    )

def auto_value(sc: Scope, name: String) -> String:
    if name == "@":
        return sc.target
    if name == "<":
        return sc.first
    if name == "^":
        return sc.deps
    if name == "?":
        return sc.newer
    if name == "|":
        return sc.order

    return sc.stem

# Index of the first '%' in a pattern, or -1.
def pct_index(cs: List[String]) -> Int:
    return index_of(cs, "%")

# The stem if `word` matches `pattern` (exact match when there is no '%').
def match_stem(pattern: String, word: String) -> Optional[String]:
    let pc = pattern.chars()
    let k = pct_index(pc)

    if k < 0:
        if pattern == word:
            return some("")

        return none

    let wc = word.chars()
    let suf_len = pc.length() - k - 1
    if wc.length() < k + suf_len:
        return none

    let pre = pc.take(k).join("")
    let suf = pc.drop(k + 1).join("")
    if not word.starts_with(pre) or not word.ends_with(suf):
        return none

    return some(wc.drop(k).take(wc.length() - k - suf_len).join(""))

def subst_pct(repl: String, stem: String) -> String:
    let rc = repl.chars()
    let k = pct_index(rc)
    if k < 0:
        return repl

    return rc.take(k).join("") + stem + rc.drop(k + 1).join("")

def subst_all(xs: List[String], stem: String) -> List[String]:
    var out: List[String] = []
    for x in xs:
        out.append(subst_pct(x, stem))
    return out

def matches_any(pats: List[String], w: String) -> Bool:
    for p in pats:
        if match_stem(p, w).is_some():
            return True
    return False

def dir_of(w: String) -> String:
    let cs = w.chars()
    let k = last_index(cs, "/")
    if k < 0:
        return "./"

    return cs.take(k + 1).join("")

def notdir_of(w: String) -> String:
    let cs = w.chars()
    let k = last_index(cs, "/")
    if k < 0:
        return w

    return cs.drop(k + 1).join("")

def suffix_of(w: String) -> String:
    let cs = w.chars()
    let k = last_index(cs, "/")
    let comp = cs.drop(k + 1)
    let d = last_index(comp, ".")
    if d < 0:
        return ""

    return comp.drop(d).join("")

def basename_of(w: String) -> String:
    let s = suffix_of(w)
    if s == "":
        return w

    let cs = w.chars()
    return cs.take(cs.length() - s.length()).join("")

def glob_match(p: List[String], pi: Int, s: List[String], si: Int) -> Bool:
    if pi == p.length():
        return si == s.length()

    let c = p.get(pi)

    if c == "*":
        var k = si

        while k <= s.length():
            if glob_match(p, pi + 1, s, k):
                return True

            if k < s.length() and s.get(k) != "/":
                k += 1
            else:
                return False

        return False

    if si >= s.length():
        return False

    if c == "?":
        if s.get(si) == "/":
            return False

        return glob_match(p, pi + 1, s, si + 1)

    if c != s.get(si):
        return False

    return glob_match(p, pi + 1, s, si + 1)

# Splits function arguments at commas outside brackets; each is trimmed.
def split_args(body: String) -> List[String]:
    var out: List[String] = []
    var cur = ""
    var depth = 0

    for c in body.chars():
        if c == "(" or c == "{":
            depth += 1
        if c == ")" or c == "}":
            depth -= 1

        if c == "," and depth == 0:
            out.append(cur.trim())
            cur = ""
        else:
            cur += c

    out.append(cur.trim())
    return out

def raw_at(raw: List[String], i: Int) -> String:
    if i < raw.length():
        return raw.get(i)

    return ""

# Expands argument `i` (missing arguments are empty).
def arg(var st: St, sc: Scope, stack: List[String], raw: List[String], i: Int) -> Result[
    String, Fatal
]:
    if i >= raw.length():
        return ok("")

    return expand(var st, sc, stack, raw.get(i))

def is_func(name: String) -> Bool:
    return [
        "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort",
        "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix",
        "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info",
        "error"
    ].contains(name)

def lookup(var st: St, sc: Scope, stack: List[String], name: String) -> Result[
    String, Fatal
]:
    for b in sc.binds.reversed():
        if b.name == name:
            return ok(b.value)

    if is_auto(name):
        if not sc.auto_on:
            return ok("")

        return ok(auto_value(sc, name))

    if let v = st.vars.get(name):
        if v.simple:
            return ok(v.value)
        if stack.contains(name):
            return error(
                fatal(
                    sc.line,
                    f"Recursive variable '{name}' references itself (eventually)"
                )
            )

        var s2 = stack
        s2.append(name)
        return expand(var st, sc, s2, v.value)

    return ok("")

# Index of the closing bracket matching an opener at `start - 1`, or -1.
def match_close(cs: List[String], start: Int, open: String, close: String) -> Int:
    var depth = 1
    var k = start

    while k < cs.length():
        let c = cs.get(k)

        if c == open:
            depth += 1
        elif c == close:
            depth -= 1
            if depth == 0:
                return k

        k += 1

    return -1

def call_func(var st: St, sc: Scope, stack: List[String], name: String, body: String) -> Result[
    String, Fatal
]:
    let raw = split_args(body)

    if name == "subst":
        let from = try arg(var st, sc.clone(), stack.clone(), raw, 0)
        let to = try arg(var st, sc.clone(), stack.clone(), raw, 1)
        let text = try arg(var st, sc, stack, raw, 2)
        if from == "":
            return ok(text)

        return ok(text.split(from).join(to))

    if name == "patsubst":
        let pat = try arg(var st, sc.clone(), stack.clone(), raw, 0)
        let repl = try arg(var st, sc.clone(), stack.clone(), raw, 1)
        let text = try arg(var st, sc, stack, raw, 2)
        var outs: List[String] = []

        for w in split_words(text):
            if let s = match_stem(pat, w):
                outs.append(subst_pct(repl, s))
            else:
                outs.append(w)

        return ok(join_words(outs))

    if name == "strip":
        let text = try arg(var st, sc, stack, raw, 0)
        return ok(join_words(split_words(text)))

    if name == "findstring":
        let find = try arg(var st, sc.clone(), stack.clone(), raw, 0)
        let text = try arg(var st, sc, stack, raw, 1)
        if text.contains(find):
            return ok(find)

        return ok("")

    if name == "filter" or name == "filter-out":
        let pats = split_words(try arg(var st, sc.clone(), stack.clone(), raw, 0))
        let text = try arg(var st, sc, stack, raw, 1)
        var outs: List[String] = []

        for w in split_words(text):
            let hit = matches_any(pats.clone(), w)
            if hit == (name == "filter"):
                outs.append(w)

        return ok(join_words(outs))

    if name == "sort":
        let text = try arg(var st, sc, stack, raw, 0)
        let ws = split_words(text).sorted(
            lambda (x: String, y: String) -> Int: return x.compare(y)
        )
        return ok(join_words(ws.distinct()))

    if name == "word":
        let k = int_arg(try arg(var st, sc.clone(), stack.clone(), raw, 0))
        let ws = split_words(try arg(var st, sc, stack, raw, 1))
        if let n = k:
            if n >= 1 and n <= ws.length():
                return ok(ws.get(n - 1))
        return ok("")

    if name == "wordlist":
        let s = int_arg(try arg(var st, sc.clone(), stack.clone(), raw, 0))
        let e = int_arg(try arg(var st, sc.clone(), stack.clone(), raw, 1))
        let ws = split_words(try arg(var st, sc, stack, raw, 2))

        if let first = s:
            if let last = e:
                if first < 1 or last < first or first > ws.length():
                    return ok("")

                let stop = if_min(last, ws.length())
                return ok(join_words(ws.drop(first - 1).take(stop - first + 1)))

        return ok("")

    if name == "words":
        let ws = split_words(try arg(var st, sc, stack, raw, 0))
        return ok(f"{ws.length()}")

    if name == "firstword" or name == "lastword":
        let ws = split_words(try arg(var st, sc, stack, raw, 0))
        if ws.length() == 0:
            return ok("")
        if name == "firstword":
            return ok(ws.get(0))

        return ok(ws.get(ws.length() - 1))

    if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
        let ws = split_words(try arg(var st, sc, stack, raw, 0))
        var outs: List[String] = []

        for w in ws:
            if name == "dir":
                outs.append(dir_of(w))
            elif name == "notdir":
                outs.append(notdir_of(w))
            elif name == "suffix":
                outs.append(suffix_of(w))
            else:
                outs.append(basename_of(w))

        return ok(join_words(outs))

    if name == "addprefix" or name == "addsuffix":
        let affix = try arg(var st, sc.clone(), stack.clone(), raw, 0)
        let ws = split_words(try arg(var st, sc, stack, raw, 1))
        var outs: List[String] = []

        for w in ws:
            if name == "addprefix":
                outs.append(affix + w)
            else:
                outs.append(w + affix)

        return ok(join_words(outs))

    if name == "wildcard":
        let pats = split_words(try arg(var st, sc, stack, raw, 0))
        var outs: List[String] = []

        for p in pats:
            var hits: List[String] = []
            for f in st.files.keys():
                if glob_match(p.chars(), 0, f.chars(), 0):
                    hits.append(f)
            outs = outs.concat(
                hits.sorted(
                    lambda (x: String, y: String) -> Int: return x.compare(
                        y
                    )
                )
            )

        return ok(join_words(outs))

    if name == "foreach":
        let vname = (try arg(var st, sc.clone(), stack.clone(), raw, 0)).trim()
        let items = split_words(try arg(var st, sc.clone(), stack.clone(), raw, 1))
        var outs: List[String] = []

        for w in items:
            var sc2 = sc.clone()
            sc2.binds = sc.binds.concat([Bind(name: vname, value: w)])
            outs.append(try expand(var st, sc2, stack.clone(), raw_at(raw, 2)))

        return ok(outs.join(" "))

    if name == "if":
        let c = (try arg(var st, sc.clone(), stack.clone(), raw, 0)).trim()
        if c != "":
            return arg(var st, sc, stack, raw, 1)

        return arg(var st, sc, stack, raw, 2)

    if name == "info":
        let t = try arg(var st, sc, stack, raw, 0)
        st.out.append(t)
        return ok("")

    # error
    let msg = try arg(var st, sc.clone(), stack, raw, 0)
    return error(fatal(sc.line, msg))

def if_min(a: Int, b: Int) -> Int:
    if a < b:
        return a

    return b

# Resolves `inner` (the text between a reference's brackets).
def reference(var st: St, sc: Scope, stack: List[String], inner: String) -> Result[
    String, Fatal
]:
    let ic = inner.chars()
    let k = index_of_space(ic)

    if k > 0:
        let name = ic.take(k).join("")
        if is_func(name):
            return call_func(var st, sc, stack, name, ic.drop(k + 1).join(""))

    let colon = subst_colon(ic)

    if colon > 0:
        let rest = ic.drop(colon + 1)
        let eq = index_of(rest, "=")
        let vname = (
            try expand(
                var st, sc.clone(), stack.clone(), ic.take(colon).join("")
            )
        ).trim()
        let from = try expand(var st, sc.clone(), stack.clone(), rest.take(eq).join(""))
        let to = try expand(
            var st, sc.clone(), stack.clone(), rest.drop(eq + 1).join("")
        )
        let value = try lookup(var st, sc, stack, vname)
        var pat = from
        var repl = to

        if not from.contains("%"):
            pat = "%" + from
            repl = "%" + to

        var outs: List[String] = []

        for w in split_words(value):
            if let s = match_stem(pat, w):
                outs.append(subst_pct(repl, s))
            else:
                outs.append(w)

        return ok(join_words(outs))

    let nm = (try expand(var st, sc.clone(), stack.clone(), inner)).trim()
    return lookup(var st, sc, stack, nm)

def index_of_space(cs: List[String]) -> Int:
    var k = 0

    while k < cs.length():
        let c = cs.get(k)
        if c == " " or c == "\t":
            return k

        k += 1

    return -1

# Index of a top-level ':' that has a later '=' (a substitution reference), or -1.
def subst_colon(cs: List[String]) -> Int:
    var depth = 0
    var k = 0

    while k < cs.length():
        let c = cs.get(k)

        if depth == 0 and c == ":":
            if index_of(cs.drop(k + 1), "=") >= 0:
                return k

            return -1

        if c == "(" or c == "{":
            depth += 1
        if c == ")" or c == "}":
            depth -= 1
        k += 1

    return -1

# Expands text: `$$`, `$(...)`, `${...}` and `$X` references.
def expand(var st: St, sc: Scope, stack: List[String], text: String) -> Result[
    String, Fatal
]:
    let cs = text.chars()
    let n = cs.length()
    var out = ""
    var k = 0

    while k < n:
        let c = cs.get(k)

        if c != "$":
            out += c
            k += 1
            continue

        if k + 1 >= n:
            k += 1
            continue

        let d = cs.get(k + 1)

        if d == "$":
            out += "$"
            k += 2
            continue

        if d == "(" or d == "{":
            var close = "}"
            if d == "(":
                close = ")"

            let j = match_close(cs, k + 2, d, close)
            if j < 0:
                return error(fatal(sc.line, "unterminated variable reference"))

            let inner = cs.drop(k + 2).take(j - k - 2).join("")
            out += try reference(var st, sc.clone(), stack.clone(), inner)
            k = j + 1
            continue

        out += try reference(var st, sc.clone(), stack.clone(), d)
        k += 2

    return ok(out)

# ---------------------------------------------------------------- parsing
def is_active(frames: List[Frame]) -> Bool:
    if frames.length() == 0:
        return True
    if let f = frames.last():
        return f.parent and f.cond != f.in_else

    return True

def is_defined(st: St, name: String) -> Bool:
    if let v = st.vars.get(name):
        return v.value != ""

    return False

def empty_rule() -> Rule:
    return Rule(targets: [], normal: [], order: [], recipe: [], line: 0)

# Splits "(A,B)" into its two raw sides, or none if the syntax is wrong.
def cond_args(rest: String) -> Optional[Pair]:
    let cs = rest.trim().chars()
    let n = cs.length()
    if n < 2 or cs.get(0) != "(":
        return none

    var depth = 0
    var close = -1
    var k = 0

    while k < n:
        let c = cs.get(k)
        if c == "(" or c == "{":
            depth += 1
        if c == ")" or c == "}":
            depth -= 1

        if depth == 0:
            close = k
            break

        k += 1

    if close != n - 1:
        return none

    let inner = cs.take(n - 1).drop(1)
    var d2 = 0
    var comma = -1
    var count = 0
    var j = 0

    while j < inner.length():
        let c = inner.get(j)
        if c == "(" or c == "{":
            d2 += 1
        if c == ")" or c == "}":
            d2 -= 1

        if c == "," and d2 == 0:
            count += 1
            comma = j

        j += 1

    if count != 1:
        return none

    return some(Pair(a: inner.take(comma).join(""), b: inner.drop(comma + 1).join("")))

def push_frame(var mk: Mk, parent: Bool, cond: Bool, num: Int) -> Result[Unit, Fatal]:
    mk.frames.append(Frame(parent: parent, cond: cond, in_else: False, line: num))
    return ok(())

def directive(var st: St, var mk: Mk, num: Int, text: String, word: String) -> Result[
    Unit, Fatal
]:
    let rest = text.chars().drop(word.length()).join("").trim()

    if word == "ifdef" or word == "ifndef":
        if not is_active(mk.frames):
            return push_frame(var mk, False, False, num)

        let name = (try expand(var st, plain(num), [], rest)).trim()
        let defined = is_defined(st, name)
        var cond = defined
        if word == "ifndef":
            cond = not defined
        return push_frame(var mk, True, cond, num)

    if word == "ifeq" or word == "ifneq":
        if not is_active(mk.frames):
            return push_frame(var mk, False, False, num)

        if let p = cond_args(rest):
            let a = (try expand(var st, plain(num), [], p.a.trim())).trim()
            let b = (try expand(var st, plain(num), [], p.b.trim())).trim()
            var cond = a == b
            if word == "ifneq":
                cond = a != b
            return push_frame(var mk, True, cond, num)

        return error(fatal(num, "invalid syntax in conditional"))

    if word == "else":
        if mk.frames.length() == 0:
            return error(fatal(num, "extraneous 'else'"))

        if let f = mk.frames.last():
            if f.in_else:
                return error(fatal(num, "extraneous 'else'"))

            (
                mk.frames.set(
                    mk.frames.length() - 1,
                    Frame(
                        parent: f.parent, cond: f.cond, in_else: True, line: f.line
                    )
                )
            )

        return ok(())

    # endif
    if mk.frames.length() == 0:
        return error(fatal(num, "extraneous 'endif'"))

    mk.frames.pop()
    return ok(())

def assign(var st: St, num: Int, cs: List[String], eq: Int) -> Result[Unit, Fatal]:
    var op = "="
    var name_end = eq

    if eq >= 1:
        let p = cs.get(eq - 1)

        if p == ":" or p == "?" or p == "+":
            op = p
            name_end = eq - 1

    let name_raw = cs.take(name_end).join("")
    let value_raw = cs.drop(eq + 1).join("").trim()
    let name = (try expand(var st, plain(num), [], name_raw)).trim()
    if name == "":
        return error(fatal(num, "empty variable name"))

    if let old = st.vars.get(name):
        if old.cmd:
            return ok(())

    if op == "=":
        st.vars.add(name, Var(value: value_raw, simple: False, cmd: False))
    elif op == ":":
        let v = try expand(var st, plain(num), [], value_raw)
        st.vars.add(name, Var(value: v, simple: True, cmd: False))
    elif op == "?":
        if not st.vars.contains(name):
            st.vars.add(name, Var(value: value_raw, simple: False, cmd: False))
    else:
        if let old = st.vars.get(name):
            if old.simple:
                let v = try expand(var st, plain(num), [], value_raw)
                (
                    st.vars.add(
                        name,
                        Var(
                            value: join_sep(old.value, v), simple: True, cmd: False
                        )
                    )
                )
            else:
                (
                    st
                    .vars
                    .add(
                        name,
                        Var(
                            value: join_sep(
                                old.value, value_raw
                            ),
                            simple: False,
                            cmd: False
                        )
                    )
                )
        else:
            st.vars.add(name, Var(value: value_raw, simple: False, cmd: False))

    return ok(())

def rule_line(var st: St, var mk: Mk, num: Int, cs: List[String], col: Int) -> Result[
    Unit, Fatal
]:
    let targets_raw = cs.take(col).join("")
    let rest = cs.drop(col + 1)
    let semi = index_of(rest, ";")
    var prereq_raw = rest.join("")
    var recipe: List[Recipe] = []

    if semi >= 0:
        prereq_raw = rest.take(semi).join("")
        recipe.append(Recipe(text: rest.drop(semi + 1).join(""), line: num))

    let targets = split_words(try expand(var st, plain(num), [], targets_raw))
    let pre = try expand(var st, plain(num), [], prereq_raw)
    let pc = pre.chars()
    let bar = index_of(pc, "|")
    var normal = split_words(pre)
    var order: List[String] = []

    if bar >= 0:
        normal = split_words(pc.take(bar).join(""))
        order = split_words(pc.drop(bar + 1).join(""))

    mk.is_open = True

    if targets.length() == 1 and targets.get(0) == ".PHONY":
        for p in normal.concat(order):
            if not mk.phony.contains(p):
                mk.phony.append(p)
        mk.rule = empty_rule()
        mk.rule.line = num
        return ok(())

    mk.rule = Rule(
        targets: targets, normal: normal, order: order, recipe: recipe, line: num
    )
    return ok(())

def statement(var st: St, var mk: Mk, num: Int, text: String) -> Result[Unit, Fatal]:
    let cs = text.chars()
    let eq = index_of(cs, "=")
    let col = top_colon(cs)
    if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
        return assign(var st, num, cs, eq)
    if col >= 0:
        return rule_line(var st, var mk, num, cs, col)

    let v = try expand(var st, plain(num), [], text)
    if v.trim() == "":
        return ok(())

    return error(fatal(num, "missing separator"))

# Closes the open rule: stores its prerequisites and recipe.
def close_rule(var st: St, var mk: Mk) -> Result[Unit, Fatal]:
    if not mk.is_open:
        return ok(())

    mk.is_open = False

    let r = mk.rule

    for t in r.targets:
        if t.contains("%"):
            (
                mk
                .pats
                .append(
                    PatRule(
                        pattern: t, normal: r.normal.clone(), order: r.order.clone(),
                        recipe: r.recipe.clone()
                    )
                )
            )
        elif let old = mk.rules.get(t).clone():
            var e = old.clone()
            e.normal = old.normal.concat(r.normal)
            e.order = old.order.concat(r.order)

            if r.recipe.length() > 0:
                if old.recipe.length() > 0:
                    (
                        st
                        .out
                        .append(
                            f"Makefile:{r.line}: warning: overriding recipe for target '{t}'"
                        )
                    )
                e.recipe = r.recipe.clone()

            mk.rules.add(t, e)
        else:
            (
                mk
                .rules
                .add(
                    t,
                    Explicit(
                        name: t, normal: r.normal.clone(), order: r.order.clone(),
                        recipe: r.recipe.clone()
                    )
                )
            )

    return ok(())

def parse_line(var st: St, var mk: Mk, num: Int, text: String) -> Result[Unit, Fatal]:
    if text.starts_with("\t"):
        let body = strip_tabs(text)
        if body.trim() == "" or not is_active(mk.frames):
            return ok(())
        if not mk.is_open:
            return error(fatal(num, "recipe commences before first target"))

        mk.rule.recipe.append(Recipe(text: body, line: num))
        return ok(())

    let stripped = strip_comment(text).trim()
    if stripped == "":
        return ok(())

    let word = split_words(stripped).get(0)

    if is_directive(word):
        try close_rule(var st, var mk)
        return directive(var st, var mk, num, stripped, word)

    if not is_active(mk.frames):
        return ok(())

    try close_rule(var st, var mk)
    return statement(var st, var mk, num, stripped)

def logical_lines(lines: List[String]) -> List[Logical]:
    var out: List[Logical] = []
    let n = lines.length()
    var i = 0

    while i < n:
        var text = lines.get(i)
        let num = i + 1

        while text.ends_with("\\"):
            let cs = text.chars()
            let body = cs.take(cs.length() - 1).join("")

            if i + 1 < n:
                text = body.trim_end() + " " + lines.get(i + 1).trim_start()
                i += 1
            else:
                text = body.trim_end()
                break

        out.append(Logical(num: num, text: text))
        i += 1

    return out

def parse(var st: St, lines: List[String]) -> Result[Mk, Fatal]:
    var mk = Mk(
        rules: Map[String, Explicit](), pats: [], phony: [], is_open: False,
        rule: empty_rule(), frames: [], memo: Map[String, Bool](), stack: [],
        ran: False, dry: False
    )
    for lg in logical_lines(lines):
        try parse_line(var st, var mk, lg.num, lg.text)
    try close_rule(var st, var mk)
    if let f = mk.frames.last():
        return error(fatal(f.line, "missing 'endif'"))

    return ok(mk)

# ---------------------------------------------------------------- building
def default_goal(mk: Mk) -> String:
    for k in mk.rules.keys():
        if not k.starts_with("."):
            return k
    return ""

# Expanded-rule resolution (explicit recipe, then pattern rule, then explicit without recipe).
def can_make(st: St, mk: Mk, name: String, depth: Int) -> Bool:
    if st.files.contains(name) or mk.rules.contains(name) or mk.phony.contains(name):
        return True
    if depth > 8:
        return False

    return find_pattern(st, mk, name, depth) >= 0

def prereqs_ok(st: St, mk: Mk, p: PatRule, stem: String, depth: Int) -> Bool:
    for x in subst_all(p.normal.clone(), stem):
        if not can_make(st, mk, x, depth + 1):
            return False
    for x in subst_all(p.order.clone(), stem):
        if not can_make(st, mk, x, depth + 1):
            return False
    return True

# Index of the first pattern rule with a recipe that applies to `name`, or -1.
def find_pattern(st: St, mk: Mk, name: String, depth: Int) -> Int:
    var i = 0

    while i < mk.pats.length():
        let p = mk.pats.get(i)
        if p.recipe.length() > 0:
            if let s = match_stem(p.pattern, name):
                if s != "" and prereqs_ok(st, mk, p, s, depth):
                    return i
        i += 1

    return -1

def resolve(st: St, mk: Mk, name: String) -> Resolved:
    if let ex = mk.rules.get(name):
        if ex.recipe.length() > 0:
            return Resolved(
                found: True, normal: ex.normal.clone(), order: ex.order.clone(),
                recipe: ex.recipe.clone(), stem: ""
            )

    let idx = find_pattern(st, mk, name, 0)

    if idx >= 0:
        let p = mk.pats.get(idx)
        let s = match_stem(p.pattern, name).get("")
        var normal = subst_all(p.normal.clone(), s)
        var order = subst_all(p.order.clone(), s)

        if let ex = mk.rules.get(name):
            normal = normal.concat(ex.normal)
            order = order.concat(ex.order)

        return Resolved(
            found: True, normal: normal, order: order, recipe: p.recipe.clone(), stem: s
        )

    if let ex = mk.rules.get(name):
        return Resolved(
            found: True, normal: ex.normal.clone(), order: ex.order.clone(), recipe: [],
            stem: ""
        )

    return Resolved(found: False, normal: [], order: [], recipe: [], stem: "")

def chain(stack: List[String], name: String) -> String:
    let i = stack.index_of(name).get(0)
    return stack.drop(i).concat([name]).join(" -> ")

def simulate(var st: St, cmd: String) -> Int:
    let words = split_words(cmd)
    if words.length() == 0:
        return 0

    let w0 = words.get(0)
    let args = words.drop(1)
    if w0 == "false":
        return 1

    if w0 == "exit":
        if args.length() == 0:
            return 0
        if let v = args.get(0).parse_int():
            return v

        return 2

    if w0 == "touch":
        for a in args:
            if not a.starts_with("-"):
                st.clock += 1
                st.files.add(a, st.clock)

        return 0

    if w0 == "rm":
        for a in args:
            if not a.starts_with("-"):
                st.files.remove(a)
        return 0

    if w0 == "cp" and args.length() == 2:
        if not st.files.contains(args.get(0)):
            st.out.append(f"cp: cannot stat '{args.get(0)}': No such file or directory")
            return 1

        st.clock += 1
        st.files.add(args.get(1), st.clock)
        return 0

    if w0 == "echo":
        var parts: List[String] = []
        for a in args:
            parts.append(strip_quotes(a))
        st.out.append(parts.join(" "))
        return 0

    return 0

def is_phony(mk: Mk, name: String) -> Bool:
    return mk.phony.contains(name)

# Runs (or, in a dry run, prints) the recipe of a rule for `name`.
def run_recipe(var st: St, var mk: Mk, name: String, r: Resolved, newer: List[String]) -> Result[
    Unit, Fatal
]:
    mk.ran = True

    var first = ""
    if r.normal.length() > 0:
        first = r.normal.get(0)

    let all = r.normal.distinct().join(" ")
    let order = r.order.distinct().join(" ")
    let newer_s = newer.join(" ")

    for rl in r.recipe:
        let sc = Scope(
            line: rl.line, auto_on: True, target: name, stem: r.stem, first: first,
            deps: all, newer: newer_s, order: order, binds: []
        )
        let text = try expand(var st, sc, [], rl.text)
        let cs = text.trim().chars()
        var silent = False
        var ign = False
        var k = 0

        while k < cs.length():
            let c = cs.get(k)
            if c == "@":
                silent = True
            if c == "-":
                ign = True
            if c != "@" and c != "-" and c != "+" and not is_space(c):
                break

            k += 1

        let command = cs.drop(k).join("").trim()
        if command == "":
            continue

        if mk.dry:
            st.out.append(command)
            continue

        if not silent:
            st.out.append(command)

        let status = simulate(var st, command)

        if status != 0:
            if ign:
                (
                    st
                    .out
                    .append(
                        f"make: [Makefile:{rl.line}: {name}] Error {status} (ignored)"
                    )
                )
            else:
                st.out.append(f"make: *** [Makefile:{rl.line}: {name}] Error {status}")
                return error(silent_abort())

    if not mk.dry and not is_phony(mk, name):
        st.clock += 1
        st.files.add(name, st.clock)

    return ok(())

# Brings `name` up to date, discarding whether it changed.
def visit(var st: St, var mk: Mk, name: String, needed: String) -> Result[Unit, Fatal]:
    return update(var st, var mk, name, needed).map(
        lambda (changed: Bool) -> Unit: return ()
    )

def parse_only(var st: St, lines: List[String]) -> Result[Unit, Fatal]:
    return parse(var st, lines).map(lambda (mk: Mk) -> Unit: return ())

# Brings `name` up to date; returns whether it changed.
def update(var st: St, var mk: Mk, name: String, needed: String) -> Result[Bool, Fatal]:
    if let m = mk.memo.get(name):
        return ok(m)
    if mk.stack.contains(name):
        return error(fatal(0, f"Circular dependency detected: {chain(mk.stack, name)}"))

    let r = resolve(st, mk, name)

    if not r.found:
        if st.files.contains(name):
            mk.memo.add(name, False)
            return ok(False)

        if mk.phony.contains(name):
            mk.memo.add(name, True)
            return ok(True)

        if needed == "":
            return error(fatal(0, f"No rule to make target '{name}'"))

        return error(fatal(0, f"No rule to make target '{name}', needed by '{needed}'"))

    let existed = st.files.contains(name)
    let old = st.files.get(name).get(0)
    mk.stack.append(name)

    var any = False
    var newer = False
    var changed_list: List[String] = []

    for p in r.normal.distinct():
        let c = try update(var st, var mk, p, name)
        if c:
            any = True

        let mt = st.files.get(p).get(-1)
        let present = mt >= 0
        if existed and present and mt > old:
            newer = True
        if not existed or c or (present and mt > old):
            changed_list.append(p)

    for p in r.order.distinct():
        try visit(var st, var mk, p, name)
    mk.stack.pop()

    let in_table = st.files.contains(name)
    let must = mk.phony.contains(name) or not in_table or any or newer
    var changed = False

    if must:
        changed = True
        if r.recipe.length() > 0:
            try run_recipe(var st, var mk, name, r, changed_list)

    mk.memo.add(name, changed)
    return ok(changed)

def build_req(var st: St, lines: List[String], goals_in: List[String], dry: Bool) -> Result[
    Unit, Fatal
]:
    var mk = try parse(var st, lines)
    mk.dry = dry

    var goals = goals_in

    if goals.length() == 0:
        let d = default_goal(mk)
        if d == "":
            return error(fatal(0, "No targets"))

        goals = [d]

    for g in goals:
        mk.ran = False
        try visit(var st, var mk, g, "")

        if not mk.ran:
            let r = resolve(st, mk, g)

            if (
                r.recipe.length() > 0
                or (not mk.phony.contains(g) and st.files.contains(g))
            ):
                st.out.append(f"make: '{g}' is up to date.")
            else:
                st.out.append(f"make: Nothing to be done for '{g}'.")

    return ok(())

def dep_walk(
    var st: St, mk: Mk, name: String, var stack: List[String], var seen: List[String],
    var out: List[String]
) -> Result[Unit, Fatal]:
    let r = resolve(st, mk, name)
    let kids = r.normal.distinct().concat(r.order.distinct())

    for c in kids:
        if seen.contains(c):
            continue
        if stack.contains(c):
            return error(fatal(0, f"Circular dependency detected: {chain(stack, c)}"))

        stack.append(c)
        try dep_walk(var st, mk, c, var stack, var seen, var out)
        stack.pop()
        seen.append(c)
        out.append(c)

    return ok(())

def deps_req(var st: St, lines: List[String], target: String) -> Result[Unit, Fatal]:
    let mk = try parse(var st, lines)
    var stack = [target]
    var seen: List[String] = []
    var out: List[String] = []
    try dep_walk(var st, mk, target, var stack, var seen, var out)
    if out.length() == 0:
        out.append("(no prerequisites)")
    st.out = st.out.concat(out)
    return ok(())

def rule_text(head: String, normal: List[String], order: List[String]) -> String:
    var s = head + ":"
    if normal.length() > 0:
        s += " " + normal.join(" ")
    if order.length() > 0:
        s += " | " + order.join(" ")
    return s

def targets_req(var st: St, lines: List[String]) -> Result[Unit, Fatal]:
    let mk = try parse(var st, lines)
    let d = default_goal(mk)
    if d != "":
        st.out.append(f"default: {d}")
    for e in mk.rules.values():
        st.out.append(rule_text(e.name, e.normal, e.order))
    for p in mk.pats:
        st.out.append(rule_text("pattern " + p.pattern, p.normal, p.order))
    if mk.phony.length() > 0:
        st.out.append("phony: " + mk.phony.join(" "))
    return ok(())

def expand_req(var st: St, lines: List[String], text: String) -> Result[Unit, Fatal]:
    try parse_only(var st, lines)

    let v = try expand(var st, plain(0), [], text)
    st.out.append(f"[{v}]")
    return ok(())

# Sets the command-line variables and returns the remaining (target) arguments.
def set_vars(var st: St, args: List[String]) -> List[String]:
    st.vars = Map[String, Var]()

    var targets: List[String] = []

    for a in args:
        let cs = a.chars()
        let e = index_of(cs, "=")

        if e > 0:
            (
                st
                .vars
                .add(
                    cs.take(e).join(""),
                    Var(
                        value: cs.drop(e + 1).join(""), simple: False, cmd: True
                    )
                )
            )
        else:
            targets.append(a)

    return targets

def files_req(var st: St) -> Result[Unit, Fatal]:
    let names = (
        st
        .files
        .keys()
        .sorted(lambda (x: String, y: String) -> Int: return x.compare(y))
    )
    if names.length() == 0:
        st.out.append("(no files)")
    for f in names:
        st.out.append(f"{f} {st.files.get(f).get(0)}")
    return ok(())

def touch_req(var st: St, args: List[String]) -> Result[Unit, Fatal]:
    if args.length() == 1:
        st.clock += 1
        st.files.add(args.get(0), st.clock)
        return ok(())

    if args.length() == 2:
        if let n = int_arg(args.get(1)):
            st.files.add(args.get(0), n)
            if n > st.clock:
                st.clock = n
            return ok(())

    st.out.append("bad request")
    return ok(())

def dispatch(var st: St, mk_lines: List[String], line: String, words: List[String]) -> Result[
    Unit, Fatal
]:
    let cmd = words.get(0)
    let args = words.drop(1)

    if cmd == "build" or cmd == "dry":
        let goals = set_vars(var st, args)
        return build_req(var st, mk_lines, goals, cmd == "dry")

    if cmd == "deps":
        let targets = set_vars(var st, args)

        if targets.length() != 1:
            st.out.append("usage: deps TARGET")
            return ok(())

        return deps_req(var st, mk_lines, targets.get(0))

    if cmd == "targets":
        set_vars(var st, args)
        return targets_req(var st, mk_lines)

    if cmd == "expand":
        st.vars = Map[String, Var]()

        let text = line.chars().drop(6).join("").trim()
        return expand_req(var st, mk_lines, text)

    if cmd == "files":
        return files_req(var st)
    if cmd == "touch":
        return touch_req(var st, args)

    if cmd == "rm":
        for a in args:
            st.files.remove(a)
        return ok(())

    st.out.append(f"unknown request: {cmd}")
    return ok(())

export def main() -> Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var mk_lines: List[String] = []
    var tbl: List[String] = []
    var reqs: List[String] = []
    var section = 0

    for ln in text.lines():
        if section < 2 and ln == "====":
            section += 1
            continue

        if section == 0:
            mk_lines.append(ln)
        elif section == 1:
            tbl.append(ln)
        else:
            reqs.append(ln)

    var st = St(files: Map[String, Int](), clock: 0, out: [], vars: Map[String, Var]())

    for ln in tbl:
        let f = split_words(ln)

        if f.length() == 2:
            if let m = nat(f.get(1)):
                st.files.add(f.get(0), m)
                if m > st.clock:
                    st.clock = m

    for ln in reqs:
        let t = ln.trim()
        if t == "" or t.starts_with("#"):
            continue

        st.out.append(f"> {ln.trim_end()}")

        let res = dispatch(var st, mk_lines, t, split_words(t))

        if res.is_error():
            let msg = res.err().text
            if msg != "":
                st.out.append(msg)

    if st.out.length() > 0:
        stdout().write(st.out.join("\n") + "\n").get()
        stdout().flush().get()

    return 0
