import stdout, stdin from "@std/io.ms"
import read_lines from "@std/streams.ms"
import parse_int from "@std/math.ms"

# One recipe line: the physical line number of its logical line and its text.
type Rl:
    line: Int
    text: String

# A stored explicit or pattern target with its accumulated prerequisites.
type Tgt:
    name: String
    pre: List[String]
    oo: List[String]
    recipe: List[Rl]

# The rule currently open for recipe lines.
type Rule:
    names: List[String]
    pre: List[String]
    oo: List[String]
    recipe: List[Rl]
    line: Int

# An open conditional block.
type Blk:
    parent: Bool
    branch: Bool
    seen_else: Bool
    line: Int

# A foreach binding.
type Bind:
    name: String
    value: String

# The result of resolving a target to its rule.
type Res:
    found: Bool
    pre: List[String]
    oo: List[String]
    recipe: List[Rl]
    stem: String

# A logical Makefile line, with the index of the next physical line.
type Logical:
    line: Int
    text: String
    next: Int

# Parsed request arguments.
type Args:
    cmd: Map[String, String]
    goals: List[String]

# Two sides of an ifeq comparison.
type Pair:
    a: String
    b: String
    ok: Bool

type Sim:
    files: Map[String, Int]
    clock: Int
    outs: List[String]
    mk: List[String]
    stop: Bool
    dry: Bool
    line: Int
    cmd: Map[String, String]
    vals: Map[String, String]
    simp: Map[String, Bool]
    ts: List[Tgt]
    tidx: Map[String, Int]
    pats: List[Tgt]
    phony: List[String]
    blocks: List[Blk]
    is_open: Bool
    rule: Rule
    binds: List[Bind]
    autos: Map[String, String]
    expanding: List[String]
    memo: Map[String, Bool]
    stk: List[String]
    ran: Int
    dout: List[String]
    dseen: Map[String, Bool]

fn new_sim() Sim:
    return Sim(
        files: Map[String, Int](), clock: 0, outs: List[String](), mk: List[String](),
        stop: false, dry: false, line: 0, cmd: Map[String, String](),
        vals: Map[String, String](), simp: Map[String, Bool](), ts: List[Tgt](),
        tidx: Map[String, Int](), pats: List[Tgt](), phony: List[String](),
        blocks: List[Blk](), is_open: false, rule: empty_rule(), binds: List[Bind](),
        autos: Map[String, String](), expanding: List[String](),
        memo: Map[String, Bool](), stk: List[String](), ran: 0, dout: List[String](),
        dseen: Map[String, Bool]()
    )

fn empty_rule() Rule:
    return Rule(
        names: List[String](), pre: List[String](), oo: List[String](),
        recipe: List[Rl](), line: 0
    )

# ---------- small text helpers ----------

fn isSp(c: String) Bool:
    return c == " " or c == "\t"

fn isWs(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn sub(cs: List[String], a: Int, b: Int) String:
    if b <= a:
        return ""

    return cs.slice(a, b).get(List[String]()).join("")

fn trimsp(s: String) String:
    let cs = s.chars()
    var a = 0
    var b = cs.length()
    while a < b and isSp(cs[a]):
        a += 1
    while b > a and isSp(cs[b - 1]):
        b -= 1
    return sub(cs, a, b)

fn ltrimsp(s: String) String:
    let cs = s.chars()
    var a = 0
    while a < cs.length() and isSp(cs[a]):
        a += 1
    return sub(cs, a, cs.length())

fn rtrimsp(s: String) String:
    let cs = s.chars()
    var b = cs.length()
    while b > 0 and isSp(cs[b - 1]):
        b -= 1
    return sub(cs, 0, b)

fn chomp(s: String) String:
    if s.ends_with("\r"):
        return rtrimsp(s).clone()

    return s.clone()

fn rtrimws(s: String) String:
    let cs = s.chars()
    var b = cs.length()
    while b > 0 and isWs(cs[b - 1]):
        b -= 1
    return sub(cs, 0, b)

fn split_ws(s: String) List[String]:
    var out = List[String]()
    var cur = ""

    for c in s.chars():
        if isWs(c):
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur = cur + c

    if cur != "":
        out.append(cur)
    return out

fn dedupe(xs: List[String]) List[String]:
    var out = List[String]()
    for x in xs:
        if not out.contains(x):
            out.append(x.clone())
    return out

fn find_char(cs: List[String], c: String, from: Int) Int:
    var i = from

    while i < cs.length():
        if cs[i] == c:
            return i

        i += 1

    return -1

fn last_char(cs: List[String], c: String) Int:
    var i = cs.length() - 1

    while i >= 0:
        if cs[i] == c:
            return i

        i -= 1

    return -1

fn index_in(xs: List[String], s: String) Int:
    var i = 0

    while i < xs.length():
        if xs[i] == s:
            return i

        i += 1

    return -1

fn join2(a: String, b: String) String:
    if a == "":
        return b
    if b == "":
        return a

    return a + " " + b

fn to_int(s: String) Optional[Int]:
    let cs = s.chars()
    if cs.length() == 0:
        return none

    var k = 0
    if cs[0] == "-":
        k = 1
    if cs.length() == k:
        return none

    var i = k

    while i < cs.length():
        if not "0123456789".contains(cs[i]):
            return none

        i += 1

    if let v = parse_int(s, 10):
        return some(v)

    return none

# ---------- output and errors ----------

fn say(var st: Sim, s: String) Unit:
    st.outs.append(s + "\n")

fn halt(var st: Sim, line: String) Unit:
    say(var st, line)
    st.stop = true

# A fatal error from the Makefile, or from make itself when no line is current.
fn fail(var st: Sim, msg: String) Unit:
    if st.line > 0:
        halt(var st, "Makefile:{st.line}: *** {msg}.  Stop.")
    else:
        halt(var st, "make: *** {msg}.  Stop.")

# ---------- pattern helpers ----------

# The stem if `word` matches `pat` (one % stands for any text), else none.
fn match_stem(pat: String, word: String) Optional[String]:
    let pcs = pat.chars()
    let wcs = word.chars()
    let p = find_char(pcs, "%", 0)

    if p < 0:
        if pat == word:
            return some("")

        return none

    let pre = sub(pcs, 0, p)
    let suf = sub(pcs, p + 1, pcs.length())
    let pl = pre.length()
    let sl = suf.length()
    if wcs.length() < pl + sl:
        return none
    if not word.starts_with(pre) or not word.ends_with(suf):
        return none

    return some(sub(wcs, pl, wcs.length() - sl))

fn matches(pat: String, word: String) Bool:
    if let _s = match_stem(pat, word):
        return true

    return false

# Replaces the first % of x by stem; x without % is returned unchanged.
fn pct_sub(x: String, stem: String) String:
    let cs = x.chars()
    let p = find_char(cs, "%", 0)
    if p < 0:
        return x

    return sub(cs, 0, p) + stem + sub(cs, p + 1, cs.length())

fn patsubst_words(pat: String, rep: String, text: String) String:
    var out = List[String]()

    for w in split_ws(text):
        if let stem = match_stem(pat, w):
            out.append(pct_sub(rep.clone(), stem))
        else:
            out.append(w)

    return out.join(" ")

# ---------- expansion ----------

fn is_func(name: String) Bool:
    return (
        name == "subst"
        or name == "patsubst"
        or name == "strip"
        or name == "findstring"
        or name == "filter"
        or name == "filter-out"
        or name == "sort"
        or name == "word"
        or name == "wordlist"
        or name == "words"
        or name == "firstword"
        or name == "lastword"
        or name == "dir"
        or name == "notdir"
        or name == "suffix"
        or name == "basename"
        or name == "addprefix"
        or name == "addsuffix"
        or name == "wildcard"
        or name == "foreach"
        or name == "if"
        or name == "info"
        or name == "error"
    )

# Index of the closer matching an opener that has already been read before `start`.
fn match_close(cs: List[String], start: Int, b: Int, open: String, close: String) Int:
    var depth = 1
    var k = start

    while k < b:
        if cs[k] == open:
            depth += 1
        else if cs[k] == close:
            depth -= 1
            if depth == 0:
                return k

        k += 1

    return -1

fn expand(var st: Sim, s: String) String:
    if st.stop:
        return ""

    let cs = s.chars()
    return expand_range(var st, cs, 0, cs.length())

fn expand_range(var st: Sim, cs: List[String], a: Int, b: Int) String:
    var out = ""
    var i = a

    while i < b and not st.stop:
        let c = cs[i]

        if c != "$":
            out = out + c
            i += 1
            continue

        if i + 1 >= b:
            i += 1
            continue

        let nx = cs[i + 1]

        if nx == "$":
            out = out + "$"
            i += 2
            continue

        if nx == "(" or nx == "\{":
            let close = if nx == "(": ")" else: "\}"

            let k = match_close(cs, i + 2, b, nx, close)

            if k < 0:
                fail(var st, "unterminated variable reference")
                return ""

            let inner = sub(cs, i + 2, k)
            out = out + reference(var st, inner)
            i = k + 1
            continue

        out = out + var_value(var st, nx)
        i += 2

    return out

# The value of a $(...) reference whose raw text is `inner`.
fn reference(var st: Sim, inner: String) String:
    let cs = inner.chars()
    let n = cs.length()
    var j = 0
    while j < n and not isSp(cs[j]):
        j += 1
    if j > 0 and j < n and is_func(sub(cs, 0, j)):
        return call_fn(var st, sub(cs, 0, j), split_args(sub(cs, j + 1, n)))

    let t = trimsp(expand(var st, inner))
    let tc = t.chars()
    let c = find_char(tc, ":", 1)

    if c > 0:
        let e = find_char(tc, "=", c + 1)

        if e > 0:
            let vname = trimsp(sub(tc, 0, c))
            let from = sub(tc, c + 1, e)
            let to = sub(tc, e + 1, tc.length())
            let v = var_value(var st, vname)
            if from.contains("%"):
                return patsubst_words(from, to, v)

            return patsubst_words("%" + from, "%" + to, v)

    return var_value(var st, t)

fn var_value(var st: Sim, name: String) String:
    if st.stop:
        return ""

    var k = st.binds.length() - 1

    while k >= 0:
        if st.binds[k].name == name:
            return st.binds[k].value.clone()

        k -= 1

    if st.autos.contains(name):
        return st.autos.get(name).get("")
    if st.cmd.contains(name):
        return recursive_value(var st, name, true)

    if st.vals.contains(name):
        if st.simp.get(name).get(false):
            return st.vals.get(name).get("")

        return recursive_value(var st, name, false)

    return ""

fn recursive_value(var st: Sim, name: String, from_cmd: Bool) String:
    if st.expanding.contains(name):
        fail(var st, "Recursive variable '{name}' references itself (eventually)")
        return ""

    let raw = if from_cmd: st.cmd.get(name).get("") else: st.vals.get(name).get("")

    st.expanding.append(name.clone())

    let r = expand(var st, raw)
    st.expanding.remove(-1)
    return r

# Splits function arguments at commas outside nested brackets; each is still raw.
fn split_args(rest: String) List[String]:
    var out = List[String]()
    var cur = ""
    var depth = 0

    for c in rest.chars():
        if c == "(" or c == "\{":
            depth += 1
            cur = cur + c
        else if c == ")" or c == "\}":
            depth -= 1
            cur = cur + c
        else if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur = cur + c

    out.append(cur)
    return out

# Argument i, trimmed and expanded; missing arguments are empty.
fn arg(var st: Sim, raw: List[String], i: Int) String:
    if i >= raw.length():
        return ""

    return expand(var st, trimsp(raw[i]))

fn call_fn(var st: Sim, name: String, raw: List[String]) String:
    if name == "foreach":
        return fn_foreach(var st, raw)

    if name == "if":
        if trimsp(arg(var st, raw, 0)) != "":
            return arg(var st, raw, 1)

        return arg(var st, raw, 2)

    if name == "info":
        let msg = arg(var st, raw, 0)
        if not st.stop:
            say(var st, msg)
        return ""

    if name == "error":
        let msg = arg(var st, raw, 0)
        fail(var st, msg)
        return ""

    if name == "subst":
        let from = arg(var st, raw, 0)
        let to = arg(var st, raw, 1)
        let text = arg(var st, raw, 2)
        if from == "":
            return text

        return text.replace(from, to)

    if name == "patsubst":
        let pat = arg(var st, raw, 0)
        let rep = arg(var st, raw, 1)
        let text = arg(var st, raw, 2)
        return patsubst_words(pat, rep, text)

    if name == "strip":
        return split_ws(arg(var st, raw, 0)).join(" ")

    if name == "findstring":
        let find = arg(var st, raw, 0)
        let text = arg(var st, raw, 1)
        if text.contains(find):
            return find

        return ""

    if name == "filter" or name == "filter-out":
        let pats = split_ws(arg(var st, raw, 0))
        let words = split_ws(arg(var st, raw, 1))
        var out = List[String]()

        for w in words:
            var hit = false
            for p in pats:
                if matches(p, w):
                    hit = true
            if hit == (name == "filter"):
                out.append(w.clone())

        return out.join(" ")

    if name == "sort":
        var words = split_ws(arg(var st, raw, 0))
        words.sort()
        return dedupe(words).join(" ")

    if name == "word":
        let text = arg(var st, raw, 1)

        if let n = to_int(trimsp(arg(var st, raw, 0))):
            let ws = split_ws(text)
            if n >= 1 and n <= ws.length():
                return ws[n - 1].clone()

        return ""

    if name == "wordlist":
        let s = to_int(trimsp(arg(var st, raw, 0)))
        let e = to_int(trimsp(arg(var st, raw, 1)))
        let ws = split_ws(arg(var st, raw, 2))

        if let a = s:
            if let b = e:
                if a < 1 or b < a or a > ws.length():
                    return ""

                let hi = if b > ws.length(): ws.length() else: b

                return ws.slice(a - 1, hi).get(List[String]()).join(" ")

        return ""

    if name == "words":
        let count = split_ws(arg(var st, raw, 0)).length()
        return "{count}"

    if name == "firstword":
        let ws = split_ws(arg(var st, raw, 0))
        if ws.length() > 0:
            return ws[0].clone()

        return ""

    if name == "lastword":
        let ws = split_ws(arg(var st, raw, 0))
        if ws.length() > 0:
            return ws[ws.length() - 1].clone()

        return ""

    if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
        var out = List[String]()
        for w in split_ws(arg(var st, raw, 0)):
            out.append(file_part(name, w))
        return out.join(" ")

    if name == "addprefix" or name == "addsuffix":
        let x = arg(var st, raw, 0)
        var out = List[String]()

        for w in split_ws(arg(var st, raw, 1)):
            if name == "addprefix":
                out.append(x + w)
            else:
                out.append(w + x)

        return out.join(" ")

    if name == "wildcard":
        var keys = st.files.keys()
        keys.sort()

        var out = List[String]()

        for p in split_ws(arg(var st, raw, 0)):
            let pc = p.chars()
            for k in keys:
                if glob_at(pc, 0, k.chars(), 0):
                    out.append(k.clone())

        return out.join(" ")

    return ""

# dir, notdir, suffix and basename of one word.
fn file_part(name: String, w: String) String:
    let cs = w.chars()
    let slash = last_char(cs, "/")
    let comp = sub(cs, slash + 1, cs.length())
    let dot = last_char(comp.chars(), ".")

    if name == "dir":
        if slash < 0:
            return "./"

        return sub(cs, 0, slash + 1)

    if name == "notdir":
        if slash < 0:
            return w

        return sub(cs, slash + 1, cs.length())

    if name == "suffix":
        if dot < 0:
            return ""

        return sub(comp.chars(), dot, comp.length())

    if dot < 0:
        return w

    return sub(cs, 0, slash + 1 + dot)

# Shell-style glob: * and ? do not match "/".
fn glob_at(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi == p.length():
        return si == s.length()

    let c = p[pi]

    if c == "*":
        var k = si

        while k <= s.length():
            if glob_at(p, pi + 1, s, k):
                return true
            if k < s.length() and s[k] == "/":
                break

            k += 1

        return false

    if si >= s.length():
        return false
    if c == "?":
        return s[si] != "/" and glob_at(p, pi + 1, s, si + 1)
    if c != s[si]:
        return false

    return glob_at(p, pi + 1, s, si + 1)

fn fn_foreach(var st: Sim, raw: List[String]) String:
    let v = trimsp(arg(var st, raw, 0))
    let items = split_ws(arg(var st, raw, 1))

    let body = if raw.length() > 2: trimsp(raw[2]) else: ""

    var parts = List[String]()

    for w in items:
        if st.stop:
            break

        st.binds.append(Bind(name: v.clone(), value: w.clone()))
        parts.append(expand(var st, body))
        st.binds.remove(-1)

    return parts.join(" ")

# ---------- Makefile parsing ----------

# Joins continuation lines starting at physical line i.
fn logical(phys: List[String], i: Int) Logical:
    var text = phys[i].clone()
    var j = i

    while text.ends_with("\\") and j + 1 < phys.length():
        let cs = text.chars()
        let body = rtrimsp(sub(cs, 0, cs.length() - 1))
        j += 1
        text = body + " " + ltrimsp(phys[j])

    return Logical(line: i + 1, text: text, next: j + 1)

# Removes a comment, where \# stands for a literal #.
fn strip_comment(s: String) String:
    let cs = s.chars()
    var out = ""
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if c == "\\" and i + 1 < cs.length() and cs[i + 1] == "#":
            out = out + "#"
            i += 2
            continue

        if c == "#":
            break

        out = out + c
        i += 1

    return out

fn word_of(text: String) String:
    let cs = text.chars()
    var k = 0
    while k < cs.length() and not isSp(cs[k]) and cs[k] != "(":
        k += 1
    return sub(cs, 0, k)

fn active(st: Sim) Bool:
    if st.blocks.length() == 0:
        return true

    let k = st.blocks.length() - 1
    return st.blocks[k].parent and st.blocks[k].branch

fn defined(st: Sim, name: String) Bool:
    if st.cmd.contains(name):
        return st.cmd.get(name).get("") != ""
    if st.vals.contains(name):
        return st.vals.get(name).get("") != ""

    return false

fn ifeq_args(var st: Sim, rest: String) Pair:
    let cs = rest.chars()
    let n = cs.length()

    if n < 2 or cs[0] != "(" or cs[n - 1] != ")":
        fail(var st, "invalid syntax in conditional")
        return Pair(a: "", b: "", ok: false)

    let ic = sub(cs, 1, n - 1).chars()
    var depth = 0
    var commas = 0
    var at = -1
    var k = 0

    while k < ic.length():
        let c = ic[k]

        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1
        else if c == "," and depth == 0:
            commas += 1
            at = k

        k += 1

    if commas != 1:
        fail(var st, "invalid syntax in conditional")
        return Pair(a: "", b: "", ok: false)

    let left = trimsp(expand(var st, trimsp(sub(ic, 0, at))))
    let right = trimsp(expand(var st, trimsp(sub(ic, at + 1, ic.length()))))
    return Pair(a: left, b: right, ok: true)

# Handles a conditional line. Returns false when the line is not a directive.
fn directive(var st: Sim, text: String) Bool:
    let w = word_of(text)

    if w == "ifdef" or w == "ifndef" or w == "ifeq" or w == "ifneq":
        if not active(st):
            st.blocks.append(
                Blk(
                    parent: false, branch: false, seen_else: false, line: st.line
                )
            )
            return true

        close_rule(var st)

        let rest = trimsp(text.drop(w.length()))
        var cond = false

        if w == "ifdef" or w == "ifndef":
            let name = trimsp(expand(var st, rest))
            let d = defined(st, name)

            cond = if w == "ifdef": d else: not d
        else:
            let pr = ifeq_args(var st, rest)
            if st.stop:
                return true

            cond = if w == "ifeq": pr.a == pr.b else: pr.a != pr.b

        st.blocks.append(
            Blk(parent: true, branch: cond, seen_else: false, line: st.line)
        )
        return true

    if w == "else":
        if st.blocks.length() == 0:
            close_rule(var st)
            fail(var st, "extraneous 'else'")
            return true

        let k = st.blocks.length() - 1
        let b = st.blocks[k].clone()

        if b.parent:
            close_rule(var st)

            if b.seen_else:
                fail(var st, "extraneous 'else'")
                return true

            st.blocks[k] = Blk(
                parent: true, branch: not b.branch, seen_else: true, line: b.line
            )
        else:
            st.blocks[k] = Blk(
                parent: false, branch: false, seen_else: true, line: b.line
            )

        return true

    if w == "endif":
        if st.blocks.length() == 0:
            close_rule(var st)
            fail(var st, "extraneous 'endif'")
            return true

        let k = st.blocks.length() - 1
        if st.blocks[k].parent:
            close_rule(var st)
        st.blocks.remove(k)
        return true

    return false

# Index of the first `:` outside $(...) and ${...} references and before any `;`, or -1.
fn top_colon(cs: List[String]) Int:
    let n = cs.length()
    var i = 0

    while i < n:
        let c = cs[i]
        if c == ";":
            return -1

        if c == "$":
            if i + 1 < n and (cs[i + 1] == "(" or cs[i + 1] == "\{"):
                let close = if cs[i + 1] == "(": ")" else: "\}"

                let k = match_close(cs, i + 2, n, cs[i + 1], close)
                if k < 0:
                    return -1

                i = k + 1
                continue

            i += 2
            continue

        if c == ":":
            return i

        i += 1

    return -1

# Closes the open rule, recording its targets.
fn close_rule(var st: Sim) Unit:
    if not st.is_open:
        return

    st.is_open = false

    let r = st.rule.clone()

    for name in r.names:
        if name.contains("%"):
            st.pats.append(
                Tgt(
                    name: name.clone(), pre: r.pre.clone(), oo: r.oo.clone(),
                    recipe: r.recipe.clone()
                )
            )
        else if st.tidx.contains(name.clone()):
            let i = st.tidx.get(name.clone()).get(0)
            let old = st.ts[i].clone()
            var recipe = old.recipe.clone()

            if r.recipe.length() > 0:
                if old.recipe.length() > 0:
                    say(
                        var st,
                        "Makefile:{r.line}: warning: overriding recipe for target '{name}'"
                    )
                recipe = r.recipe.clone()

            var pre = old.pre.clone()
            for p in r.pre:
                pre.append(p.clone())

            var oo = old.oo.clone()
            for p in r.oo:
                oo.append(p.clone())
            st.ts[i] = Tgt(name: name.clone(), pre: pre, oo: oo, recipe: recipe)
        else:
            st.tidx[name.clone()] = st.ts.length()
            st.ts.append(
                Tgt(
                    name: name.clone(), pre: r.pre.clone(), oo: r.oo.clone(),
                    recipe: r.recipe.clone()
                )
            )

# Handles `NAME op value`; eq is the index of the first `=`.
fn assign(var st: Sim, cs: List[String], eq: Int) Unit:
    var op = "="
    var nend = eq

    if eq >= 1 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
        op = cs[eq - 1].clone()
        nend = eq - 1

    let name = trimsp(expand(var st, sub(cs, 0, nend)))
    if st.stop:
        return

    if name == "":
        fail(var st, "empty variable name")
        return

    if st.cmd.contains(name.clone()):
        return

    let value = trimsp(sub(cs, eq + 1, cs.length()))

    if op == "=":
        st.vals[name.clone()] = value.clone()
        st.simp[name.clone()] = false
    else if op == ":":
        let v = expand(var st, value)
        if st.stop:
            return

        st.vals[name.clone()] = v
        st.simp[name.clone()] = true
    else if op == "?":
        if not st.vals.contains(name.clone()):
            st.vals[name.clone()] = value.clone()
            st.simp[name.clone()] = false
    else:
        if not st.vals.contains(name.clone()):
            st.vals[name.clone()] = value.clone()
            st.simp[name.clone()] = false
        else if st.simp.get(name.clone()).get(false):
            let add = expand(var st, value)
            st.vals[name.clone()] = join2(st.vals.get(name.clone()).get(""), add)
        else:
            st.vals[name.clone()] = join2(st.vals.get(name.clone()).get(""), value)

# Handles `TARGETS : PREREQS [; COMMAND]`; col is the index of the top-level colon.
fn rule_line(var st: Sim, cs: List[String], col: Int) Unit:
    let n = cs.length()
    var semi = -1
    var k = col + 1

    while k < n:
        if cs[k] == ";":
            semi = k
            break

        k += 1

    let pre_end = if semi >= 0: semi else: n

    let inline = if semi >= 0: sub(cs, semi + 1, n) else: ""

    let names = split_ws(expand(var st, sub(cs, 0, col)))
    let pe = expand(var st, sub(cs, col + 1, pre_end))
    if st.stop:
        return

    let pcs = pe.chars()
    let bar = find_char(pcs, "|", 0)
    var pre_s = pe.clone()
    var oo_s = ""

    if bar >= 0:
        pre_s = sub(pcs, 0, bar)
        oo_s = sub(pcs, bar + 1, pcs.length())

    let pre = split_ws(pre_s)
    let oo = split_ws(oo_s)
    var rec = List[Rl]()
    if trimsp(inline) != "":
        rec.append(Rl(line: st.line, text: inline))

    if names.length() == 1 and names[0] == ".PHONY":
        for p in pre:
            if not st.phony.contains(p):
                st.phony.append(p.clone())
        for p in oo:
            if not st.phony.contains(p):
                st.phony.append(p.clone())

    # A .PHONY rule has no effect beyond marking its prerequisites, so it is not stored as a target.
    var kept = names.clone()
    if names.length() == 1 and names[0] == ".PHONY":
        kept = List[String]()
    st.is_open = true
    st.rule = Rule(names: kept, pre: pre, oo: oo, recipe: rec, line: st.line)

# A line that is neither a directive nor a recipe line.
fn plain_line(var st: Sim, text: String) Unit:
    let cs = text.chars()
    let eq = find_char(cs, "=", 0)
    let col = top_colon(cs)

    if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
        assign(var st, cs, eq)
        return

    if col >= 0:
        rule_line(var st, cs, col)
        return

    let e = expand(var st, text)
    if not st.stop and trimsp(e) != "":
        fail(var st, "missing separator")

fn parse_all(var st: Sim, phys: List[String]) Unit:
    var i = 0

    while i < phys.length() and not st.stop:
        let lg = logical(phys, i)
        i = lg.next

        if lg.text.starts_with("\t"):
            let body = lg.text.drop(1)
            if trimsp(body) == "":
                continue
            if not active(st):
                continue

            if not st.is_open:
                st.line = lg.line
                fail(var st, "recipe commences before first target")
                break

            st.rule.recipe.append(Rl(line: lg.line, text: body.clone()))
            continue

        let text = trimsp(strip_comment(lg.text))
        if text == "":
            continue

        st.line = lg.line
        if directive(var st, text):
            continue
        if not active(st):
            continue

        close_rule(var st)
        plain_line(var st, text)

    if not st.stop:
        close_rule(var st)

        if st.blocks.length() > 0:
            st.line = st.blocks[st.blocks.length() - 1].line
            fail(var st, "missing 'endif'")

    st.line = 0

# Parses the Makefile afresh with the given command-line variables.
fn load(var st: Sim, cmd: Map[String, String]) Unit:
    st.cmd = cmd
    st.stop = false
    st.line = 0
    st.vals = Map[String, String]()
    st.simp = Map[String, Bool]()
    st.ts = List[Tgt]()
    st.tidx = Map[String, Int]()
    st.pats = List[Tgt]()
    st.phony = List[String]()
    st.blocks = List[Blk]()
    st.is_open = false
    st.rule = empty_rule()
    st.binds = List[Bind]()
    st.autos = Map[String, String]()
    st.expanding = List[String]()
    st.memo = Map[String, Bool]()
    st.stk = List[String]()
    st.ran = 0
    st.dout = List[String]()
    st.dseen = Map[String, Bool]()

    let phys = st.mk.clone()
    parse_all(var st, phys)

# ---------- rule resolution ----------

fn can_make(st: Sim, name: String, depth: Int) Bool:
    if (
        st.files.contains(name.clone())
        or st.tidx.contains(name.clone())
        or st.phony.contains(name.clone())
    ):
        return true
    if depth >= 8:
        return false

    return find_pat(st, name, depth + 1) >= 0

fn pats_ok(st: Sim, k: Int, stem: String, depth: Int) Bool:
    for x in st.pats[k].pre:
        if not can_make(st, pct_sub(x.clone(), stem.clone()), depth + 1):
            return false
    for x in st.pats[k].oo:
        if not can_make(st, pct_sub(x.clone(), stem.clone()), depth + 1):
            return false
    return true

# Index of the first pattern rule with recipe lines that can build `name`, or -1.
fn find_pat(st: Sim, name: String, depth: Int) Int:
    var k = 0

    while k < st.pats.length():
        if st.pats[k].recipe.length() > 0:
            if let stem = match_stem(st.pats[k].name, name.clone()):
                if stem != "" and pats_ok(st, k, stem, depth):
                    return k
        k += 1

    return -1

fn resolve(st: Sim, name: String) Res:
    if st.tidx.contains(name.clone()):
        let i = st.tidx.get(name.clone()).get(0)
        if st.ts[i].recipe.length() > 0:
            return Res(
                found: true, pre: st.ts[i].pre.clone(), oo: st.ts[i].oo.clone(),
                recipe: st.ts[i].recipe.clone(), stem: ""
            )

    let k = find_pat(st, name.clone(), 0)

    if k >= 0:
        let stem = match_stem(st.pats[k].name, name.clone()).get("")
        var pre = List[String]()
        for x in st.pats[k].pre:
            pre.append(pct_sub(x.clone(), stem.clone()))

        var oo = List[String]()
        for x in st.pats[k].oo:
            oo.append(pct_sub(x.clone(), stem.clone()))

        if st.tidx.contains(name.clone()):
            let i = st.tidx.get(name.clone()).get(0)
            for x in st.ts[i].pre:
                pre.append(x.clone())
            for x in st.ts[i].oo:
                oo.append(x.clone())

        return Res(
            found: true, pre: pre, oo: oo, recipe: st.pats[k].recipe.clone(), stem: stem
        )

    if st.tidx.contains(name.clone()):
        let i = st.tidx.get(name.clone()).get(0)
        return Res(
            found: true, pre: st.ts[i].pre.clone(), oo: st.ts[i].oo.clone(),
            recipe: List[Rl](), stem: ""
        )

    return Res(
        found: false, pre: List[String](), oo: List[String](), recipe: List[Rl](),
        stem: ""
    )

fn default_goal(st: Sim) Optional[String]:
    for t in st.ts:
        if not t.name.starts_with("."):
            return some(t.name.clone())
    return none

# ---------- building ----------

fn cycle_error(var st: Sim, name: String) Unit:
    let pos = index_in(st.stk, name)
    var parts = st.stk.slice(pos, st.stk.length()).get(List[String]())
    parts.append(name.clone())

    let path = parts.join(" -> ")
    halt(var st, "make: *** Circular dependency detected: {path}.  Stop.")

# Removes the quote characters from a word.
fn strip_quotes(w: String) String:
    var out = ""
    for c in w.chars():
        if c != "'" and c != "\"":
            out = out + c
    return out

# Simulates one recipe command and returns its exit status.
fn simulate(var st: Sim, command: String) Int:
    let ws = split_ws(command)
    if ws.length() == 0:
        return 0

    let w0 = ws[0].clone()
    if w0 == "false":
        return 1

    if w0 == "exit":
        if ws.length() > 1:
            if let v = to_int(ws[1]):
                return v

            return 2

        return 0

    if w0 == "touch":
        for k in 1..ws.length():
            if not ws[k].starts_with("-"):
                st.clock += 1
                st.files[ws[k].clone()] = st.clock

        return 0

    if w0 == "rm":
        for k in 1..ws.length():
            if not ws[k].starts_with("-"):
                st.files.remove(ws[k].clone())
        return 0

    if w0 == "cp":
        if ws.length() == 3:
            if not st.files.contains(ws[1].clone()):
                say(var st, "cp: cannot stat '{ws[1]}': No such file or directory")
                return 1

            st.clock += 1
            st.files[ws[2].clone()] = st.clock

        return 0

    if w0 == "echo":
        var args = List[String]()
        for k in 1..ws.length():
            args.append(strip_quotes(ws[k]))
        say(var st, args.join(" "))
        return 0

    return 0

# Runs (or, in a dry run, prints) the recipe of `name`.
fn run_recipe(var st: Sim, name: String, r: Res, existed: Bool, old: Int) Unit:
    st.ran += 1

    let d = dedupe(r.pre)
    let oo = dedupe(r.oo)
    var q = List[String]()

    for p in d:
        let newer = (
            st.files.contains(p.clone())
            and st.files.get(p.clone()).get(0) > old
        )
        if not existed or st.memo.get(p.clone()).get(false) or newer:
            q.append(p.clone())

    let first = if r.pre.length() > 0: r.pre[0].clone() else: ""

    st.autos = Map[String, String]()
    st.autos["@"] = name.clone()
    st.autos["<"] = first
    st.autos["^"] = d.join(" ")
    st.autos["?"] = q.join(" ")
    st.autos["|"] = oo.join(" ")
    st.autos["*"] = r.stem.clone()

    for rl in r.recipe:
        if st.stop:
            break

        st.line = rl.line

        let e = trimsp(expand(var st, rl.text))
        if st.stop:
            break

        let cs = e.chars()
        var silent = false
        var ign = false
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
                ign = true
            k += 1

        let command = trimsp(sub(cs, k, cs.length()))
        if command == "":
            continue

        if st.dry or not silent:
            say(var st, command.clone())
        if st.dry:
            continue

        let status = simulate(var st, command)

        if status != 0:
            if ign:
                say(
                    var st,
                    "make: [Makefile:{rl.line}: {name}] Error {status} (ignored)"
                )
            else:
                halt(var st, "make: *** [Makefile:{rl.line}: {name}] Error {status}")
                break

    st.line = 0
    st.autos = Map[String, String]()
    if st.stop:
        return

    if not st.dry and not st.phony.contains(name.clone()):
        st.clock += 1
        st.files[name.clone()] = st.clock

# Brings `name` up to date and returns whether it changed.
fn update(var st: Sim, name: String, needed_by: String) Bool:
    if st.stop:
        return false
    if st.memo.contains(name.clone()):
        return st.memo.get(name.clone()).get(false)

    if st.stk.contains(name.clone()):
        cycle_error(var st, name)
        return false

    let r = resolve(st, name.clone())

    if not r.found:
        if st.files.contains(name.clone()):
            st.memo[name.clone()] = false
            return false

        if st.phony.contains(name.clone()):
            st.memo[name.clone()] = true
            return true

        if needed_by == "":
            halt(var st, "make: *** No rule to make target '{name}'.  Stop.")
        else:
            halt(
                var st,
                "make: *** No rule to make target '{name}', needed by '{needed_by}'.  Stop."
            )

        return false

    st.stk.append(name.clone())

    let existed = st.files.contains(name.clone())
    let old = st.files.get(name.clone()).get(0)
    var changed = false
    var newer = false

    for p in dedupe(r.pre):
        if update(var st, p.clone(), name.clone()):
            changed = true
        if st.stop:
            return false

        if (
            existed
            and st.files.contains(p.clone())
            and st.files.get(p.clone()).get(0) > old
        ):
            newer = true

    for p in dedupe(r.oo):
        update(var st, p.clone(), name.clone())
        if st.stop:
            return false

    let need = (
        st.phony.contains(name.clone())
        or not st.files.contains(name.clone())
        or changed
        or newer
    )

    if need and r.recipe.length() > 0:
        run_recipe(var st, name.clone(), r, existed, old)
        if st.stop:
            return false

    st.stk.remove(-1)
    st.memo[name.clone()] = need
    return need

# Prints the transitive prerequisites of `name` into st.dout, depth first.
fn dfs(var st: Sim, name: String) Unit:
    let r = resolve(st, name.clone())
    var kids = dedupe(r.pre)
    for x in dedupe(r.oo):
        kids.append(x)

    var i = 0

    while i < kids.length() and not st.stop:
        let c = kids[i].clone()
        i += 1
        if st.dseen.contains(c.clone()):
            continue

        if st.stk.contains(c.clone()):
            cycle_error(var st, c)
            return

        st.stk.append(c.clone())
        dfs(var st, c.clone())
        if st.stop:
            return

        st.stk.remove(-1)
        st.dseen[c.clone()] = true
        st.dout.append(c)

# ---------- requests ----------

# Splits the words after the request name into command-line variables and goals.
fn parse_args(ws: List[String]) Args:
    var cmd = Map[String, String]()
    var goals = List[String]()
    var k = 1

    while k < ws.length():
        let cs = ws[k].chars()
        let e = find_char(cs, "=", 0)

        if e > 0:
            cmd[sub(cs, 0, e)] = sub(cs, e + 1, cs.length())
        else:
            goals.append(ws[k].clone())

        k += 1

    return Args(cmd: cmd, goals: goals)

fn do_build(var st: Sim, ws: List[String], dry: Bool) Unit:
    let args = parse_args(ws)
    load(var st, args.cmd.clone())
    if st.stop:
        return

    st.dry = dry

    var gs = args.goals.clone()

    if gs.length() == 0:
        if let dg = default_goal(st):
            gs.append(dg)
        else:
            halt(var st, "make: *** No targets.  Stop.")
            return

    for g in gs:
        let before = st.ran
        update(var st, g.clone(), "")
        if st.stop:
            return

        if st.ran == before:
            let r = resolve(st, g.clone())
            let file = not st.phony.contains(g.clone()) and st.files.contains(g.clone())

            if r.recipe.length() > 0 or file:
                say(var st, "make: '{g}' is up to date.")
            else:
                say(var st, "make: Nothing to be done for '{g}'.")

fn do_deps(var st: Sim, ws: List[String]) Unit:
    let args = parse_args(ws)
    load(var st, args.cmd.clone())
    if st.stop:
        return

    if args.goals.length() != 1:
        say(var st, "usage: deps TARGET")
        return

    let t = args.goals[0].clone()
    st.stk = List[String]()
    st.stk.append(t.clone())
    dfs(var st, t)
    if st.stop:
        return

    if st.dout.length() == 0:
        say(var st, "(no prerequisites)")
        return

    for line in st.dout.clone():
        say(var st, line)

# NAME: PREREQS | ORDER-ONLY, with the parts omitted when empty.
fn fmt_rule(name: String, pre: List[String], oo: List[String]) String:
    var s = name + ":"
    if pre.length() > 0:
        s = s + " " + pre.join(" ")
    if oo.length() > 0:
        s = s + " | " + oo.join(" ")
    return s

fn do_targets(var st: Sim, ws: List[String]) Unit:
    let args = parse_args(ws)
    load(var st, args.cmd.clone())
    if st.stop:
        return

    if let dg = default_goal(st):
        say(var st, "default: {dg}")
    for t in st.ts.clone():
        say(var st, fmt_rule(t.name, t.pre, t.oo))
    for p in st.pats.clone():
        say(var st, "pattern " + fmt_rule(p.name, p.pre, p.oo))
    if st.phony.length() > 0:
        say(var st, "phony: " + st.phony.clone().join(" "))

fn do_expand(var st: Sim, text: String) Unit:
    load(var st, Map[String, String]())
    if st.stop:
        return

    let r = expand(var st, text)
    if st.stop:
        return

    say(var st, "[" + r + "]")

fn do_touch(var st: Sim, ws: List[String]) Unit:
    if ws.length() == 2:
        st.clock += 1
        st.files[ws[1].clone()] = st.clock
    else if ws.length() == 3:
        if let v = to_int(ws[2]):
            st.files[ws[1].clone()] = v
            if v > st.clock:
                st.clock = v
        else:
            say(var st, "bad request")
    else:
        say(var st, "bad request")

fn do_files(var st: Sim) Unit:
    if st.files.length() == 0:
        say(var st, "(no files)")
        return

    var keys = st.files.keys()
    keys.sort()

    for k in keys:
        let m = st.files.get(k.clone()).get(0)
        say(var st, "{k} {m}")

fn handle_request(var st: Sim, line: String) Unit:
    let shown = rtrimws(line)
    let t = ltrimsp(shown)
    if t == "" or t.starts_with("#"):
        return

    say(var st, "> " + shown)
    st.stop = false
    st.line = 0

    let ws = split_ws(t)
    let w = ws[0].clone()

    if w == "build":
        do_build(var st, ws, false)
    else if w == "dry":
        do_build(var st, ws, true)
    else if w == "deps":
        do_deps(var st, ws)
    else if w == "targets":
        do_targets(var st, ws)
    else if w == "expand":
        do_expand(var st, trimsp(t.drop(w.length())))
    else if w == "files":
        do_files(var st)
    else if w == "touch":
        do_touch(var st, ws)
    else if w == "rm":
        for k in 1..ws.length():
            st.files.remove(ws[k].clone())
    else:
        say(var st, "unknown request: {w}")

export fn main() Int:
    let raw = read_lines(stdin()).get(List[String]())
    var st = new_sim()
    var sep = 0
    var tb = List[String]()
    var rq = List[String]()

    for line in raw:
        let l = chomp(line)

        if sep < 2 and l == "====":
            sep += 1
        else if sep == 0:
            st.mk.append(l)
        else if sep == 1:
            tb.append(l)
        else:
            rq.append(l)

    for l in tb:
        let ws = split_ws(l)

        if ws.length() == 2:
            if let m = to_int(ws[1]):
                if m >= 0:
                    st.files[ws[0].clone()] = m
                    if m > st.clock:
                        st.clock = m

    for l in rq:
        handle_request(var st, l)
    stdout().write(st.outs.join("")).get()
    return 0
