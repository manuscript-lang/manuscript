import stdout from "@std/io.ms"
import stdin from "@std/io.ms"
import read_lines from "@std/streams.ms"

# ---------------------------------------------------------------- types

type Fatal:
    msg: String

impl Error for Fatal:
    fn message() String:
        return self.msg.clone()

type Var:
    value: String
    recursive: Bool

type Recipe:
    line: Int
    text: String

type Rule:
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]

type PRule:
    pat: String
    rule: Rule

type Cond:
    parent: Bool
    cond: Bool
    act: Bool
    inelse: Bool
    line: Int

type Env:
    line: Int
    recipe: Bool
    autos: Map[String, String]
    binds: Map[String, String]
    stack: List[String]

type Res:
    found: Bool
    normal: List[String]
    order: List[String]
    recipe: List[Recipe]
    stem: String

type Line:
    num: Int
    recipe: Bool
    text: String

type St:
    files: Map[String, Int]
    clock: Int
    vars: Map[String, Var]
    locked: Map[String, Bool]
    explicit: Map[String, Rule]
    names: List[String]
    pats: List[PRule]
    phony: List[String]
    conds: List[Cond]
    isopen: Bool
    otargets: List[String]
    onormal: List[String]
    oorder: List[String]
    orecipe: List[Recipe]
    oline: Int
    ophony: Bool
    memo: Map[String, Bool]
    stackp: List[String]
    dry: Bool
    ran: Int

let FUNCS = [
    "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word",
    "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename",
    "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"
]

# ---------------------------------------------------------------- output and string helpers

fn out(s: String) Unit:
    stdout().write("{s}\n").get()

fn sub(cs: List[String], a: Int, b: Int) String:
    var acc = ""
    var i = a

    while i < b:
        acc += cs[i]
        i += 1

    return acc

fn ssub(s: String, a: Int, b: Int) String:
    return sub(s.chars(), a, b)

fn index_of(cs: List[String], c: String, from: Int) Int:
    var i = from

    while i < cs.length():
        if cs[i] == c:
            return i

        i += 1

    return -1

fn is_sp(c: String) Bool:
    return c == " " or c == "\t"

fn is_wsp(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn words(s: String) List[String]:
    var res = List[String]()
    var cur = ""

    for c in s.chars():
        if is_wsp(c):
            if cur != "":
                res.append(cur)
                cur = ""
        else:
            cur += c

    if cur != "":
        res.append(cur)
    return res

fn join_sp(a: String, b: String) String:
    if a == "":
        return b.clone()
    if b == "":
        return a.clone()

    return a + " " + b

fn dedupe(xs: List[String]) List[String]:
    var res = List[String]()
    for x in xs:
        if not res.contains(x):
            res.append(x.clone())
    return res

fn chomp(s: String) String:
    let cs = s.chars()
    if cs.length() > 0 and cs[cs.length() - 1] == "\r":
        return sub(cs, 0, cs.length() - 1)

    return s.clone()

fn ltrim_sp(s: String) String:
    let cs = s.chars()
    var a = 0

    while a < cs.length():
        if is_sp(cs[a]):
            a += 1
        else:
            break

    return sub(cs, a, cs.length())

fn rtrim_sp(s: String) String:
    let cs = s.chars()
    var b = cs.length()

    while b > 0:
        if is_sp(cs[b - 1]):
            b -= 1
        else:
            break

    return sub(cs, 0, b)

fn strip_tabs(s: String) String:
    let cs = s.chars()
    var a = 0

    while a < cs.length():
        if cs[a] == "\t":
            a += 1
        else:
            break

    return sub(cs, a, cs.length())

fn fatal(line: Int, msg: String) Fatal:
    if line > 0:
        return Fatal(msg: "Makefile:{line}: *** {msg}.  Stop.")

    return Fatal(msg: "make: *** {msg}.  Stop.")

fn errtext(r: Result[Unit, Fatal]) String:
    if let _v = r:
        return ""

    return r.err().message()

fn bracket(r: Result[String, Fatal]) String:
    if let v = r:
        return "[{v}]"

    return r.err().message()

fn env(line: Int) Env:
    return Env(
        line: line, recipe: false, autos: Map[String, String](),
        binds: Map[String, String](), stack: List[String]()
    )

# ---------------------------------------------------------------- logical lines

fn strip_comment(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var acc = ""
    var i = 0

    while i < n:
        if cs[i] == "\\" and i + 1 < n and cs[i + 1] == "#":
            acc += "#"
            i += 2
        else if cs[i] == "#":
            return acc
        else:
            acc += cs[i]
            i += 1

    return acc

fn ends_bs(s: String) Bool:
    let cs = s.chars()
    return cs.length() > 0 and cs[cs.length() - 1] == "\\"

fn logical_lines(phys: List[String]) List[Line]:
    var res = List[Line]()
    let n = phys.length()
    var i = 0

    while i < n:
        let start = i + 1
        var cur = phys[i].clone()

        while ends_bs(cur) and i + 1 < n:
            let cs = cur.chars()
            let base = rtrim_sp(sub(cs, 0, cs.length() - 1))
            i += 1
            cur = base + " " + ltrim_sp(phys[i])

        if cur.starts_with("\t"):
            let body = strip_tabs(cur)
            if body.trim() != "":
                res.append(Line(num: start, recipe: true, text: body))
        else:
            let body = strip_comment(cur).trim()
            if body != "":
                res.append(Line(num: start, recipe: false, text: body))

        i += 1

    return res

# ---------------------------------------------------------------- patterns

fn pmatch(pat: String, t: String) Bool:
    let pc = pat.chars()
    let p = index_of(pc, "%", 0)
    if p < 0:
        return pat == t

    let pre = sub(pc, 0, p)
    let suf = sub(pc, p + 1, pc.length())
    return (
        t.starts_with(pre)
        and t.ends_with(suf)
        and t.length() >= pre.length() + suf.length()
    )

fn stem_of(pat: String, t: String) String:
    let pc = pat.chars()
    let p = index_of(pc, "%", 0)
    let suf_len = pc.length() - p - 1
    return ssub(t, p, t.length() - suf_len)

fn rule_stem(pat: String, t: String) String:
    if not pmatch(pat, t):
        return ""

    return stem_of(pat, t)

fn subst_stem(p: String, stem: String) String:
    let pc = p.chars()
    let idx = index_of(pc, "%", 0)
    if idx < 0:
        return p.clone()

    return sub(pc, 0, idx) + stem + sub(pc, idx + 1, pc.length())

fn patsubst_words(pat: String, rep: String, text: String) String:
    var res = List[String]()
    let has_pct = pat.contains("%")

    for w in words(text):
        if pmatch(pat, w):
            var r = rep.clone()
            if has_pct:
                r = subst_stem(rep, stem_of(pat, w))
            if r != "":
                res.append(r)
        else:
            res.append(w.clone())

    return res.join(" ")

fn glob_match(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi == p.length():
        return si == s.length()

    let c = p[pi]

    if c == "*":
        if glob_match(p, pi + 1, s, si):
            return true
        if si < s.length() and s[si] != "/":
            return glob_match(p, pi, s, si + 1)

        return false

    if si >= s.length():
        return false

    if c == "?":
        if s[si] == "/":
            return false

        return glob_match(p, pi + 1, s, si + 1)

    if c != s[si]:
        return false

    return glob_match(p, pi + 1, s, si + 1)

fn last_slash(w: String) Int:
    let cs = w.chars()
    var i = cs.length() - 1

    while i >= 0:
        if cs[i] == "/":
            return i

        i -= 1

    return -1

fn dot_index(w: String) Int:
    let cs = w.chars()
    let s = last_slash(w)
    var i = cs.length() - 1

    while i > s:
        if cs[i] == ".":
            return i

        i -= 1

    return -1

# ---------------------------------------------------------------- expansion

fn is_auto(name: String) Bool:
    return (
        name == "@"
        or name == "<"
        or name == "^"
        or name == "?"
        or name == "|"
        or name == "*"
    )

fn lookup(name: String, e: Env, st: St) Result[String, Fatal]:
    if let b = e.binds.get(name):
        return ok(b)

    if is_auto(name):
        if e.recipe and e.autos.contains(name):
            return ok(e.autos.get(name).get(""))

        return ok("")

    if let v = st.vars.get(name):
        if v.recursive:
            if e.stack.contains(name):
                return error(
                    fatal(
                        e.line,
                        "Recursive variable '{name}' references itself (eventually)"
                    )
                )

            var stk = e.stack.clone()
            stk.append(name.clone())

            let e2 = Env(
                line: e.line, recipe: e.recipe, autos: e.autos.clone(),
                binds: e.binds.clone(), stack: stk
            )
            return expand(v.value, e2, st)

        return ok(v.value.clone())

    return ok("")

fn find_close(cs: List[String], start: Int, open: String, close: String) Int:
    var depth = 1
    var i = start

    while i < cs.length():
        if cs[i] == open:
            depth += 1
        else if cs[i] == close:
            depth -= 1
            if depth == 0:
                return i

        i += 1

    return -1

fn expand(s: String, e: Env, st: St) Result[String, Fatal]:
    let cs = s.chars()
    let n = cs.length()
    var acc = ""
    var i = 0

    while i < n:
        let c = cs[i]

        if c != "$":
            acc += c
            i += 1
        else if i + 1 >= n:
            i += 1
        else if cs[i + 1] == "$":
            acc += "$"
            i += 2
        else if cs[i + 1] == "(" or cs[i + 1] == "\{":
            var closer = ")"
            if cs[i + 1] == "\{":
                closer = "\}"

            let j = find_close(cs, i + 2, cs[i + 1], closer)
            if j < 0:
                return error(fatal(e.line, "unterminated variable reference"))

            let inner = sub(cs, i + 2, j)
            let v = try ref_value(inner, e, st)
            acc += v
            i = j + 1
        else:
            let v = try lookup(cs[i + 1], e, st)
            acc += v
            i += 2

    return ok(acc)

fn fn_name_of(s: String) String:
    let cs = s.chars()
    var i = 0

    while i < cs.length():
        if is_sp(cs[i]):
            break

        i += 1

    if i == 0 or i >= cs.length():
        return ""

    let name = sub(cs, 0, i)
    if FUNCS.contains(name):
        return name

    return ""

fn ref_value(inner: String, e: Env, st: St) Result[String, Fatal]:
    let fname = fn_name_of(inner)

    if fname != "":
        let ics = inner.chars()
        let args = split_args(sub(ics, fname.length() + 1, ics.length()))
        return call_fn(fname, args, e, st)

    let full = try expand(inner, e, st)
    let name = full.trim()
    let cs = name.chars()
    let colon = index_of(cs, ":", 1)

    if colon > 0:
        let eqi = index_of(cs, "=", colon + 1)

        if eqi > colon:
            let vname = sub(cs, 0, colon)
            let from = sub(cs, colon + 1, eqi)
            let to = sub(cs, eqi + 1, cs.length())
            let val = try lookup(vname, e, st)
            var pat = "%" + from
            var rep = "%" + to

            if from.contains("%"):
                pat = from.clone()
                rep = to.clone()

            return ok(patsubst_words(pat, rep, val))

    return lookup(name, e, st)

fn split_args(s: String) List[String]:
    var res = List[String]()
    var cur = ""
    var depth = 0

    for c in s.chars():
        if c == "(" or c == "\{":
            depth += 1
            cur += c
        else if c == ")" or c == "\}":
            depth -= 1
            cur += c
        else if c == "," and depth == 0:
            res.append(cur)
            cur = ""
        else:
            cur += c

    res.append(cur)
    return res

fn arg_raw(args: List[String], i: Int) String:
    if i < args.length():
        return args[i].trim()

    return ""

fn xa(args: List[String], i: Int, e: Env, st: St) Result[String, Fatal]:
    return expand(arg_raw(args, i), e, st)

fn nonempty(xs: List[String]) String:
    var res = List[String]()
    for x in xs:
        if x != "":
            res.append(x.clone())
    return res.join(" ")

fn call_fn(name: String, args: List[String], e: Env, st: St) Result[String, Fatal]:
    if name == "info":
        let t = try xa(args, 0, e, st)
        out(t)
        return ok("")

    if name == "error":
        let t = try xa(args, 0, e, st)
        return error(fatal(e.line, t))

    if name == "if":
        let c = try xa(args, 0, e, st)

        if c.trim() != "":
            if args.length() > 1:
                return xa(args, 1, e, st)

            return ok("")

        if args.length() > 2:
            return xa(args, 2, e, st)

        return ok("")

    if name == "foreach":
        let vn = (try xa(args, 0, e, st)).trim()
        let lst = try xa(args, 1, e, st)
        let text = arg_raw(args, 2)
        var items = List[String]()

        for w in words(lst):
            var b = e.binds.clone()
            b[vn.clone()] = w.clone()

            let e2 = Env(
                line: e.line, recipe: e.recipe, autos: e.autos.clone(), binds: b,
                stack: e.stack.clone()
            )
            let item = try expand(text, e2, st)
            items.append(item)

        return ok(items.join(" "))

    if name == "subst":
        let fr = try xa(args, 0, e, st)
        let to = try xa(args, 1, e, st)
        let tx = try xa(args, 2, e, st)
        if fr == "":
            return ok(tx)

        return ok(tx.replace(fr, to))

    if name == "patsubst":
        let pat = try xa(args, 0, e, st)
        let rep = try xa(args, 1, e, st)
        let tx = try xa(args, 2, e, st)
        return ok(patsubst_words(pat, rep, tx))

    if name == "strip":
        let tx = try xa(args, 0, e, st)
        return ok(words(tx).join(" "))

    if name == "findstring":
        let f = try xa(args, 0, e, st)
        let tx = try xa(args, 1, e, st)
        if tx.contains(f):
            return ok(f)

        return ok("")

    if name == "filter" or name == "filter-out":
        let pats = words(try xa(args, 0, e, st))
        let ws = words(try xa(args, 1, e, st))
        var res = List[String]()

        for w in ws:
            var m = false
            for p in pats:
                if pmatch(p, w):
                    m = true
            if (name == "filter") == m:
                res.append(w.clone())

        return ok(res.join(" "))

    if name == "sort":
        var ws = words(try xa(args, 0, e, st))
        ws.sort()
        return ok(dedupe(ws).join(" "))

    if name == "word":
        let kx = try xa(args, 0, e, st)
        let k = kx.parse_int().get(0)
        let ws = words(try xa(args, 1, e, st))
        if k < 1 or k > ws.length():
            return ok("")

        return ok(ws[k - 1].clone())

    if name == "wordlist":
        let sx = try xa(args, 0, e, st)
        let ex = try xa(args, 1, e, st)
        let s = sx.parse_int().get(0)
        let hi = ex.parse_int().get(0)
        let ws = words(try xa(args, 2, e, st))
        if s < 1 or hi < s or s > ws.length():
            return ok("")

        var stop = hi
        if stop > ws.length():
            stop = ws.length()

        var res = List[String]()
        var i = s - 1

        while i < stop:
            res.append(ws[i].clone())
            i += 1

        return ok(res.join(" "))

    if name == "words":
        let ws = words(try xa(args, 0, e, st))
        return ok("{ws.length()}")

    if name == "firstword":
        let ws = words(try xa(args, 0, e, st))
        if ws.length() == 0:
            return ok("")

        return ok(ws[0].clone())

    if name == "lastword":
        let ws = words(try xa(args, 0, e, st))
        if ws.length() == 0:
            return ok("")

        return ok(ws[ws.length() - 1].clone())

    if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
        let ws = words(try xa(args, 0, e, st))
        var res = List[String]()

        for w in ws:
            let s = last_slash(w)
            let d = dot_index(w)

            if name == "dir":
                if s < 0:
                    res.append("./")
                else:
                    res.append(ssub(w, 0, s + 1))
            else if name == "notdir":
                if s < 0:
                    res.append(w.clone())
                else:
                    res.append(ssub(w, s + 1, w.length()))
            else if name == "suffix":
                if d >= 0:
                    res.append(ssub(w, d, w.length()))
            else:
                if d >= 0:
                    res.append(ssub(w, 0, d))
                else:
                    res.append(w.clone())

        return ok(nonempty(res))

    if name == "addprefix" or name == "addsuffix":
        let x = try xa(args, 0, e, st)
        let ws = words(try xa(args, 1, e, st))
        var res = List[String]()

        for w in ws:
            if name == "addprefix":
                res.append(x + w)
            else:
                res.append(w + x)

        return ok(res.join(" "))

    if name == "wildcard":
        let pats = words(try xa(args, 0, e, st))
        var res = List[String]()

        for p in pats:
            var hits = List[String]()
            for k in st.files.keys():
                if glob_match(p.chars(), 0, k.chars(), 0):
                    hits.append(k.clone())
            hits.sort()
            for h in hits:
                res.append(h.clone())

        return ok(res.join(" "))

    return ok("")

# ---------------------------------------------------------------- Makefile parsing

fn directive_kw(text: String) String:
    let cs = text.chars()
    var i = 0

    while i < cs.length():
        if "abcdefghijklmnopqrstuvwxyz".contains(cs[i]):
            i += 1
        else:
            break

    let kw = sub(cs, 0, i)
    if (
        kw != "ifdef"
        and kw != "ifndef"
        and kw != "ifeq"
        and kw != "ifneq"
        and kw != "else"
        and kw != "endif"
    ):
        return ""
    if i < cs.length() and not (is_wsp(cs[i]) or cs[i] == "("):
        return ""

    return kw

fn is_active(st: St) Bool:
    let n = st.conds.length()
    if n == 0:
        return true

    return st.conds[n - 1].act

fn eval_ifeq(eq: Bool, rest: String, num: Int, st: St) Result[Bool, Fatal]:
    let cs = rest.chars()
    let n = cs.length()
    if n < 2 or cs[0] != "(" or cs[n - 1] != ")":
        return error(fatal(num, "invalid syntax in conditional"))

    let ic = sub(cs, 1, n - 1).chars()
    var depth = 0
    var count = 0
    var comma = -1
    var i = 0

    while i < ic.length():
        let c = ic[i]

        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1
        else if c == "," and depth == 0:
            count += 1
            comma = i

        i += 1

    if count != 1:
        return error(fatal(num, "invalid syntax in conditional"))

    let a = try expand(sub(ic, 0, comma).trim(), env(num), st)
    let b = try expand(sub(ic, comma + 1, ic.length()).trim(), env(num), st)
    let same = a.trim() == b.trim()
    if eq:
        return ok(same)

    return ok(not same)

fn do_directive(var st: St, num: Int, text: String, kw: String) Result[Unit, Fatal]:
    let kwlen = kw.length()
    let rest = ssub(text, kwlen, text.length()).trim()
    let parent = is_active(st)

    if kw == "else":
        let k = st.conds.length() - 1
        if k < 0:
            return error(fatal(num, "extraneous 'else'"))

        let c = st.conds[k]
        if c.inelse:
            return error(fatal(num, "extraneous 'else'"))

        st.conds[k] = Cond(
            parent: c.parent, cond: c.cond, act: c.parent and not c.cond, inelse: true,
            line: c.line
        )
        return ok(unit)

    if kw == "endif":
        if st.conds.length() == 0:
            return error(fatal(num, "extraneous 'endif'"))

        let _p = st.conds.pop()
        return ok(unit)

    var cnd = false

    if parent:
        if kw == "ifdef" or kw == "ifndef":
            let nm = (try expand(rest, env(num), st)).trim()
            var defined = false
            if let v = st.vars.get(nm):
                if v.value != "":
                    defined = true
            cnd = defined
            if kw == "ifndef":
                cnd = not defined
        else:
            cnd = try eval_ifeq(kw == "ifeq", rest, num, st)

    st.conds.append(
        Cond(
            parent: parent, cond: cnd, act: parent and cnd, inelse: false, line: num
        )
    )
    return ok(unit)

fn find_col(cs: List[String]) Int:
    var i = 0
    var depth = 0
    let n = cs.length()

    while i < n:
        let c = cs[i]

        if depth > 0:
            if c == "(" or c == "\{":
                depth += 1
            else if c == ")" or c == "\}":
                depth -= 1

            i += 1
        else if c == "$" and i + 1 < n and (cs[i + 1] == "(" or cs[i + 1] == "\{"):
            depth = 1
            i += 2
        else if c == "$" and i + 1 < n:
            i += 2
        else if c == ";":
            return -1
        else if c == ":":
            return i
        else:
            i += 1

    return -1

fn join_names(var st: St, names: List[String]) Unit:
    for x in names:
        if not st.phony.contains(x):
            st.phony.append(x.clone())

fn do_assign(var st: St, num: Int, cs: List[String], eq: Int) Result[Unit, Fatal]:
    let n = cs.length()
    var name_end = eq
    var op = "="

    if eq > 0:
        let p = cs[eq - 1]

        if p == ":":
            op = ":="
            name_end = eq - 1
        else if p == "?":
            op = "?="
            name_end = eq - 1
        else if p == "+":
            op = "+="
            name_end = eq - 1

    let nm = try expand(sub(cs, 0, name_end), env(num), st)
    let name = nm.trim()
    if name == "":
        return error(fatal(num, "empty variable name"))

    let raw = sub(cs, eq + 1, n).trim()
    if st.locked.contains(name):
        return ok(unit)

    if op == "=":
        st.vars[name.clone()] = Var(value: raw, recursive: true)
    else if op == ":=":
        let v = try expand(raw, env(num), st)
        st.vars[name.clone()] = Var(value: v, recursive: false)
    else if op == "?=":
        if not st.vars.contains(name):
            st.vars[name.clone()] = Var(value: raw, recursive: true)
    else:
        let exists = st.vars.contains(name)
        let old = st.vars.get(name).get(Var(value: "", recursive: true))

        if not exists:
            st.vars[name.clone()] = Var(value: raw, recursive: true)
        else if old.recursive:
            st.vars[name.clone()] = Var(value: join_sp(old.value, raw), recursive: true)
        else:
            let add = try expand(raw, env(num), st)
            st.vars[name.clone()] = Var(
                value: join_sp(old.value, add), recursive: false
            )

    return ok(unit)

fn open_rule(var st: St, num: Int, cs: List[String], col: Int) Result[Unit, Fatal]:
    let n = cs.length()
    var semi = -1
    var i = col + 1

    while i < n:
        if cs[i] == ";":
            semi = i
            break

        i += 1

    var pend = n
    if semi >= 0:
        pend = semi

    let prereq_raw = sub(cs, col + 1, pend)
    let e = env(num)
    let tg = words(try expand(sub(cs, 0, col), e, st))
    let pre = try expand(prereq_raw, e, st)
    let pc = pre.chars()
    let bar = index_of(pc, "|", 0)
    var nrm = List[String]()
    var ord = List[String]()

    if bar >= 0:
        nrm = words(sub(pc, 0, bar))
        ord = words(sub(pc, bar + 1, pc.length()))
    else:
        nrm = words(pre)

    st.isopen = true
    st.otargets = tg.clone()
    st.onormal = nrm.clone()
    st.oorder = ord.clone()
    st.orecipe = List[Recipe]()
    st.oline = num
    st.ophony = false
    if tg.length() == 1:
        if tg[0] == ".PHONY":
            st.ophony = true

    if st.ophony:
        join_names(var st, nrm)
        join_names(var st, ord)

    if semi >= 0:
        let c = sub(cs, semi + 1, n).trim()
        if c != "":
            st.orecipe.append(Recipe(line: num, text: c))

    return ok(unit)

fn rule_or_empty(st: St, t: String) Rule:
    if let r = st.explicit.get(t):
        return Rule(
            normal: r.normal.clone(), order: r.order.clone(), recipe: r.recipe.clone()
        )

    return Rule(normal: List[String](), order: List[String](), recipe: List[Recipe]())

fn close_rule(var st: St) Unit:
    if not st.isopen:
        return

    st.isopen = false
    if st.ophony:
        return

    let tl = st.otargets.clone()

    for t in tl:
        if t.contains("%"):
            st.pats.append(
                PRule(
                    pat: t.clone(),
                    rule: Rule(
                        normal: st.onormal.clone(), order: st.oorder.clone(),
                        recipe: st.orecipe.clone()
                    )
                )
            )
        else:
            let old = rule_or_empty(st, t)
            var rec = old.recipe.clone()

            if st.orecipe.length() > 0:
                if old.recipe.length() > 0:
                    out(
                        "Makefile:{st.oline}: warning: overriding recipe for target '{t}'"
                    )
                rec = st.orecipe.clone()

            var nn = old.normal.clone()
            for p in st.onormal:
                nn.append(p.clone())

            var oo = old.order.clone()
            for p in st.oorder:
                oo.append(p.clone())
            if not st.explicit.contains(t):
                st.names.append(t.clone())
            st.explicit[t.clone()] = Rule(normal: nn, order: oo, recipe: rec)

    return

fn handle_line(var st: St, num: Int, text: String) Result[Unit, Fatal]:
    let cs = text.chars()
    let eq = index_of(cs, "=", 0)
    let col = find_col(cs)
    let is_assign = eq >= 0 and (col < 0 or col > eq or col == eq - 1)
    if is_assign:
        return do_assign(var st, num, cs, eq)
    if col >= 0:
        return open_rule(var st, num, cs, col)

    let t = try expand(text, env(num), st)
    if t.trim() != "":
        return error(fatal(num, "missing separator"))

    return ok(unit)

fn parse_all(var st: St, lines: List[Line]) Result[Unit, Fatal]:
    for ln in lines:
        if ln.recipe:
            if is_active(st):
                if not st.isopen:
                    return error(fatal(ln.num, "recipe commences before first target"))

                st.orecipe.append(Recipe(line: ln.num, text: ln.text.clone()))
        else:
            close_rule(var st)

            let kw = directive_kw(ln.text)

            if kw != "":
                let _d = try do_directive(var st, ln.num, ln.text, kw)
            else if is_active(st):
                let _h = try handle_line(var st, ln.num, ln.text)

    close_rule(var st)

    let nc = st.conds.length()
    if nc > 0:
        return error(fatal(st.conds[nc - 1].line, "missing 'endif'"))

    return ok(unit)

# ---------------------------------------------------------------- rule resolution

fn can_make(st: St, name: String, depth: Int) Bool:
    if st.files.contains(name) or st.explicit.contains(name) or st.phony.contains(name):
        return true
    if depth > 8:
        return false

    for pr in st.pats:
        if pr.rule.recipe.length() > 0:
            let stem = rule_stem(pr.pat, name)

            if stem != "":
                var good = true
                for p in pr.rule.normal:
                    if not can_make(st, subst_stem(p, stem), depth + 1):
                        good = false
                for p in pr.rule.order:
                    if not can_make(st, subst_stem(p, stem), depth + 1):
                        good = false
                if good:
                    return true

    return false

fn resolve(st: St, t: String) Res:
    if let ex = st.explicit.get(t):
        if ex.recipe.length() > 0:
            return Res(
                found: true, normal: ex.normal.clone(), order: ex.order.clone(),
                recipe: ex.recipe.clone(), stem: ""
            )

    for pr in st.pats:
        if pr.rule.recipe.length() > 0:
            let stem = rule_stem(pr.pat, t)

            if stem != "":
                var good = true
                for p in pr.rule.normal:
                    if not can_make(st, subst_stem(p, stem), 1):
                        good = false
                for p in pr.rule.order:
                    if not can_make(st, subst_stem(p, stem), 1):
                        good = false

                if good:
                    var nn = List[String]()
                    for p in pr.rule.normal:
                        nn.append(subst_stem(p, stem))

                    var oo = List[String]()
                    for p in pr.rule.order:
                        oo.append(subst_stem(p, stem))

                    if let ex = st.explicit.get(t):
                        for p in ex.normal:
                            nn.append(p.clone())
                        for p in ex.order:
                            oo.append(p.clone())

                    return Res(
                        found: true, normal: nn, order: oo,
                        recipe: pr.rule.recipe.clone(), stem: stem
                    )

    if let ex = st.explicit.get(t):
        return Res(
            found: true, normal: ex.normal.clone(), order: ex.order.clone(),
            recipe: List[Recipe](), stem: ""
        )

    return Res(
        found: false, normal: List[String](), order: List[String](),
        recipe: List[Recipe](), stem: ""
    )

fn default_goal(st: St) String:
    for n in st.names:
        if not n.starts_with("."):
            return n.clone()
    return ""

# ---------------------------------------------------------------- running recipes

fn remove_quotes(s: String) String:
    var acc = ""
    for c in s.chars():
        if c != "'" and c != "\"":
            acc += c
    return acc

fn run_cmd(var st: St, cmd: String) Int:
    let w = words(cmd)
    if w.length() == 0:
        return 0

    let w0 = w[0].clone()
    var rest = List[String]()
    var i = 1

    while i < w.length():
        rest.append(w[i].clone())
        i += 1

    if w0 == "false":
        return 1

    if w0 == "exit":
        if rest.length() == 0:
            return 0
        if let v = rest[0].parse_int():
            return v

        return 2

    if w0 == "touch":
        for f in rest:
            if not f.starts_with("-"):
                st.clock += 1
                st.files[f.clone()] = st.clock

        return 0

    if w0 == "rm":
        for f in rest:
            if not f.starts_with("-"):
                st.files.remove(f)
        return 0

    if w0 == "cp":
        if rest.length() == 2:
            if not st.files.contains(rest[0]):
                out("cp: cannot stat '{rest[0]}': No such file or directory")
                return 1

            st.clock += 1
            st.files[rest[1].clone()] = st.clock

        return 0

    if w0 == "echo":
        var parts = List[String]()
        for a in rest:
            parts.append(remove_quotes(a))
        out(parts.join(" "))
        return 0

    return 0

fn run_recipe(
    var st: St, t: String, r: Res, dn: List[String], dord: List[String], q: List[String]
) Result[Unit, Fatal]:
    st.ran += 1

    var autos = Map[String, String]()
    var first = ""
    if r.normal.length() > 0:
        first = r.normal[0].clone()
    autos["@"] = t.clone()
    autos["<"] = first
    autos["^"] = dn.join(" ")
    autos["?"] = q.join(" ")
    autos["|"] = dord.join(" ")
    autos["*"] = r.stem.clone()

    for rl in r.recipe:
        let e = Env(
            line: rl.line, recipe: true, autos: autos.clone(),
            binds: Map[String, String](), stack: List[String]()
        )
        let ex = try expand(rl.text, e, st)
        let cs = ex.chars()
        let n = cs.length()
        var i = 0
        var silent = false
        var ign = false

        while i < n:
            let c = cs[i]

            if c == "@" or c == "-" or c == "+" or is_sp(c):
                if c == "@":
                    silent = true
                if c == "-":
                    ign = true
                i += 1
            else:
                break

        let cmd = sub(cs, i, n).trim()

        if st.dry:
            if cmd != "":
                out(cmd)
        else if cmd != "":
            if not silent:
                out(cmd)

            let status = run_cmd(var st, cmd)

            if status != 0:
                if ign:
                    out("make: [Makefile:{rl.line}: {t}] Error {status} (ignored)")
                else:
                    return error(
                        Fatal(
                            msg: "make: *** [Makefile:{rl.line}: {t}] Error {status}"
                        )
                    )

    if not st.dry:
        if not st.phony.contains(t):
            st.clock += 1
            st.files[t.clone()] = st.clock

    return ok(unit)

fn index_in(xs: List[String], t: String) Int:
    var i = 0

    while i < xs.length():
        if xs[i] == t:
            return i

        i += 1

    return -1

fn cycle_error(stk: List[String], t: String, idx: Int) Fatal:
    var parts = List[String]()
    var i = idx

    while i < stk.length():
        parts.append(stk[i].clone())
        i += 1

    parts.append(t.clone())
    return Fatal(
        msg: "make: *** Circular dependency detected: {parts.join(" -> ")}.  Stop."
    )

fn update(var st: St, t: String, needed: String) Result[Bool, Fatal]:
    if let m = st.memo.get(t):
        return ok(m)

    let idx = index_in(st.stackp, t)
    if idx >= 0:
        return error(cycle_error(st.stackp, t, idx))

    let r = resolve(st, t)
    let existed = st.files.contains(t)
    var oldm = 0
    if existed:
        oldm = st.files.get(t).get(0)

    if not r.found:
        if existed:
            st.memo[t.clone()] = false
            return ok(false)

        if st.phony.contains(t):
            st.memo[t.clone()] = true
            return ok(true)

        if needed == "":
            return error(Fatal(msg: "make: *** No rule to make target '{t}'.  Stop."))

        return error(
            Fatal(
                msg: "make: *** No rule to make target '{t}', needed by '{needed}'.  Stop."
            )
        )

    let dn = dedupe(r.normal)
    let dord = dedupe(r.order)
    st.stackp.append(t.clone())

    var anychg = false
    var newer = false
    var chg = List[String]()

    for p in dn:
        let c = try update(var st, p.clone(), t.clone())

        if c:
            anychg = true
            chg.append(p.clone())

        if existed and st.files.contains(p):
            if st.files.get(p).get(0) > oldm:
                newer = true

    for p in dord:
        let _c = try update(var st, p.clone(), t.clone())

    let _s = st.stackp.pop()
    let rebuild = st.phony.contains(t) or not st.files.contains(t) or anychg or newer
    var changed = false

    if rebuild:
        changed = true

        if r.recipe.length() > 0:
            var q = List[String]()

            for p in dn:
                var inq = not existed or chg.contains(p)
                if st.files.contains(p) and existed:
                    if st.files.get(p).get(0) > oldm:
                        inq = true
                if inq:
                    q.append(p.clone())

            let _rr = try run_recipe(var st, t.clone(), r, dn, dord, q)

    st.memo[t.clone()] = changed
    return ok(changed)

fn cmd_build(var st: St, goals: List[String]) Result[Unit, Fatal]:
    var gs = List[String]()
    for g in goals:
        gs.append(g.clone())

    if gs.length() == 0:
        let d = default_goal(st)
        if d == "":
            return error(Fatal(msg: "make: *** No targets.  Stop."))

        gs.append(d)

    for g in gs:
        let before = st.ran
        let _c = try update(var st, g.clone(), "")

        if st.ran == before:
            let r = resolve(st, g.clone())

            if (
                r.recipe.length() > 0
                or (not st.phony.contains(g) and st.files.contains(g))
            ):
                out("make: '{g}' is up to date.")
            else:
                out("make: Nothing to be done for '{g}'.")

    return ok(unit)

fn dfs(
    st: St,
    t: String,
    var stk: List[String],
    var done: Map[String, Bool],
    var outl: List[String]
) Result[Unit, Fatal]:
    if done.contains(t):
        return ok(unit)

    let idx = index_in(stk, t)
    if idx >= 0:
        return error(cycle_error(stk, t, idx))

    let top = stk.length() == 0
    stk.append(t.clone())

    let r = resolve(st, t)
    for p in dedupe(r.normal):
        let _a = try dfs(st, p.clone(), var stk, var done, var outl)
    for p in dedupe(r.order):
        let _b = try dfs(st, p.clone(), var stk, var done, var outl)

    let _s = stk.pop()
    done[t.clone()] = true
    if not top:
        outl.append(t.clone())
    return ok(unit)

fn cmd_deps(st: St, target: String) Result[Unit, Fatal]:
    var stk = List[String]()
    var done = Map[String, Bool]()
    var outl = List[String]()
    let _d = try dfs(st, target.clone(), var stk, var done, var outl)
    if outl.length() == 0:
        out("(no prerequisites)")
    for x in outl:
        out(x)
    return ok(unit)

fn rule_line(head: String, normal: List[String], order: List[String]) String:
    var s = head + ":"
    if normal.length() > 0:
        s += " " + normal.join(" ")
    if order.length() > 0:
        s += " | " + order.join(" ")
    return s

fn cmd_targets(st: St) Unit:
    let d = default_goal(st)
    if d != "":
        out("default: {d}")

    for n in st.names:
        let r = rule_or_empty(st, n)
        out(rule_line(n, r.normal, r.order))

    for pr in st.pats:
        out(rule_line("pattern " + pr.pat, pr.rule.normal, pr.rule.order))
    if st.phony.length() > 0:
        out("phony: " + st.phony.join(" "))
    return

# ---------------------------------------------------------------- requests

fn reset_parse(var st: St, cmdv: Map[String, String], dry: Bool) Unit:
    st.vars = Map[String, Var]()
    st.locked = Map[String, Bool]()

    for k in cmdv.keys():
        let v = cmdv.get(k).get("")
        st.vars[k.clone()] = Var(value: v, recursive: true)
        st.locked[k.clone()] = true

    st.explicit = Map[String, Rule]()
    st.names = List[String]()
    st.pats = List[PRule]()
    st.phony = List[String]()
    st.conds = List[Cond]()
    st.isopen = false
    st.otargets = List[String]()
    st.onormal = List[String]()
    st.oorder = List[String]()
    st.orecipe = List[Recipe]()
    st.oline = 0
    st.ophony = false
    st.memo = Map[String, Bool]()
    st.stackp = List[String]()
    st.dry = dry
    st.ran = 0
    return

fn handle(var st: St, mk: List[String], line: String) Unit:
    let ws = words(line)
    let cmd = ws[0].clone()
    var args = List[String]()
    var i = 1

    while i < ws.length():
        args.append(ws[i].clone())
        i += 1

    if (
        cmd == "build"
        or cmd == "dry"
        or cmd == "deps"
        or cmd == "targets"
        or cmd == "expand"
    ):
        var cmdv = Map[String, String]()
        var tg = List[String]()
        var text = ""

        if cmd == "expand":
            let t = line.trim()
            text = ssub(t, 6, t.length()).trim()
        else:
            for a in args:
                let p = index_of(a.chars(), "=", 1)

                if p >= 1:
                    cmdv[ssub(a, 0, p)] = ssub(a, p + 1, a.length())
                else:
                    tg.append(a.clone())

        reset_parse(var st, cmdv, cmd == "dry")

        let pe = errtext(parse_all(var st, logical_lines(mk)))

        if pe != "":
            out(pe)
            return

        if cmd == "expand":
            out(bracket(expand(text, env(0), st)))
        else if cmd == "build" or cmd == "dry":
            let e1 = errtext(cmd_build(var st, tg))
            if e1 != "":
                out(e1)
        else if cmd == "deps":
            if tg.length() != 1:
                out("usage: deps TARGET")
            else:
                let e2 = errtext(cmd_deps(st, tg[0].clone()))
                if e2 != "":
                    out(e2)
        else:
            cmd_targets(st)
    else if cmd == "files":
        var ks = st.files.keys()
        ks.sort()
        if ks.length() == 0:
            out("(no files)")
        for k in ks:
            out("{k} {st.files.get(k).get(0)}")
    else if cmd == "touch":
        if args.length() == 1:
            st.clock += 1
            st.files[args[0].clone()] = st.clock
        else if args.length() == 2:
            if let n = args[1].parse_int():
                st.files[args[0].clone()] = n
                if n > st.clock:
                    st.clock = n
            else:
                out("bad request")
        else:
            out("bad request")
    else if cmd == "rm":
        for a in args:
            st.files.remove(a)
    else:
        out("unknown request: {cmd}")

    return

fn slice_list(xs: List[String], a: Int, b: Int) List[String]:
    var res = List[String]()
    var i = a

    while i < b and i < xs.length():
        res.append(xs[i].clone())
        i += 1

    return res

export fn main() Int:
    let raw = read_lines(stdin()).get()
    var lines = List[String]()
    for l in raw:
        lines.append(chomp(l))

    var seps = List[Int]()
    var i = 0

    while i < lines.length() and seps.length() < 2:
        if lines[i] == "====":
            seps.append(i)
        i += 1

    let n = lines.length()
    var mk = List[String]()
    var tab = List[String]()
    var reqs = List[String]()

    if seps.length() == 0:
        mk = slice_list(lines, 0, n)
    else if seps.length() == 1:
        mk = slice_list(lines, 0, seps[0])
        tab = slice_list(lines, seps[0] + 1, n)
    else:
        mk = slice_list(lines, 0, seps[0])
        tab = slice_list(lines, seps[0] + 1, seps[1])
        reqs = slice_list(lines, seps[1] + 1, n)

    var st = St(
        files: Map[String, Int](), clock: 0, vars: Map[String, Var](),
        locked: Map[String, Bool](), explicit: Map[String, Rule](),
        names: List[String](), pats: List[PRule](), phony: List[String](),
        conds: List[Cond](), isopen: false, otargets: List[String](),
        onormal: List[String](), oorder: List[String](), orecipe: List[Recipe](),
        oline: 0, ophony: false, memo: Map[String, Bool](), stackp: List[String](),
        dry: false, ran: 0
    )

    for l in tab:
        let w = words(l)

        if w.length() == 2:
            if let m = w[1].parse_int():
                if m >= 0:
                    st.files[w[0].clone()] = m
                    if m > st.clock:
                        st.clock = m

    for rq in reqs:
        if rq.trim() != "" and not rq.trim().starts_with("#"):
            out("> " + rq.trim_end())
            handle(var st, mk, rq.clone())

    return 0
