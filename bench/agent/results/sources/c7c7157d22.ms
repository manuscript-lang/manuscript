import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

// ---------- data ----------

type LLine:
    num: Int
    text: String
    recipe: Bool

type RLine:
    text: String
    line: Int

type PRule:
    pat: String
    pre: List[String]
    oo: List[String]
    rec: List[RLine]

type Var:
    value: String
    simple: Bool

type Mk:
    vars: Map[String, Var]
    cmd: Map[String, String]
    phony: List[String]
    ex_order: List[String]
    ex_pre: Map[String, List[String]]
    ex_oo: Map[String, List[String]]
    ex_rec: Map[String, List[RLine]]
    pats: List[PRule]
    default_goal: String

type Open:
    active: Bool
    is_phony: Bool
    targets: List[String]
    pre: List[String]
    oo: List[String]
    rec: List[RLine]
    line: Int

type Cond:
    parent: Bool
    cv: Bool
    in_else: Bool
    line: Int

type Res:
    found: Bool
    pre: List[String]
    oo: List[String]
    rec: List[RLine]
    stem: String

type St:
    files: Map[String, Int]
    clock: Int
    memo: Map[String, Bool]
    stack: List[String]
    runs: Int
    changed: Map[String, Bool]
    dry: Bool
    mkl: List[String]

type Cx:
    line: Int
    auto_on: Bool
    at: String
    lt: String
    caret: String
    qmark: String
    pipe: String
    star: String
    stack: List[String]
    bnames: List[String]
    bvals: List[String]

// ---------- small helpers ----------

// ms: allow_effect std.console.write
fn cat(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var k = a

    while k < b:
        out += cs[k]
        k += 1

    return out

// ms: allow_effect std.console.write
fn is_sp(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

// ms: allow_effect std.console.write
fn words_of(s: String) List[String]:
    var out = List[String]()
    var cur = ""

    for c in s.chars():
        if is_sp(c):
            if cur != "":
                out.append(cur.clone())
                cur = ""
        else:
            cur += c

    if cur != "":
        out.append(cur.clone())
    return out

// ms: allow_effect std.console.write
fn dedup(xs: List[String]) List[String]:
    var out = List[String]()
    for x in xs:
        if not out.contains(x):
            out.append(x.clone())
    return out

// ms: allow_effect std.console.write
fn index_of(cs: List[String], target: String, start: Int) Int:
    var k = start

    while k < cs.length():
        if cs[k] == target:
            return k

        k += 1

    return -1

// ms: allow_effect std.console.write
fn copy_range(xs: List[String], a: Int, b: Int) List[String]:
    var out = List[String]()
    var k = a

    while k < b:
        out.append(xs[k].clone())
        k += 1

    return out

// ms: allow_effect std.console.write
fn mkmsg(line: Int, msg: String) String:
    if line > 0:
        return "Makefile:{line}: *** {msg}.  Stop."

    return "make: *** {msg}.  Stop."

// ms: allow_effect std.console.write
fn mkerr(msg: String) String:
    return "make: *** {msg}.  Stop."

// ms: allow_effect std.console.write
fn plain_cx(line: Int) Cx:
    return Cx(
        line: line, auto_on: false, at: "", lt: "", caret: "", qmark: "", pipe: "",
        star: "", stack: List[String](), bnames: List[String](), bvals: List[String]()
    )

// ms: allow_effect std.console.write
fn strip_quotes(s: String) String:
    var out = ""
    for c in s.chars():
        if c != "'" and c != "\"":
            out += c
    return out

// pattern helpers: one '%' stands for a stem
// ms: allow_effect std.console.write
fn pmatch(pat: String, w: String) Bool:
    let pc = pat.chars()
    let p = index_of(pc, "%", 0)
    if p < 0:
        return pat == w

    let wc = w.chars()
    let sl = pc.length() - p - 1
    if wc.length() < p + sl:
        return false

    let pre = cat(pc, 0, p)
    let suf = cat(pc, p + 1, pc.length())
    return w.starts_with(pre) and w.ends_with(suf)

// ms: allow_effect std.console.write
fn pstem(pat: String, w: String) String:
    let pc = pat.chars()
    let p = index_of(pc, "%", 0)
    if p < 0:
        return ""

    let wc = w.chars()
    let sl = pc.length() - p - 1
    return cat(wc, p, wc.length() - sl)

// ms: allow_effect std.console.write
fn subst_pct(s: String, stem: String) String:
    let cs = s.chars()
    let p = index_of(cs, "%", 0)
    if p < 0:
        return s.clone()

    return cat(cs, 0, p) + stem + cat(cs, p + 1, cs.length())

// ms: allow_effect std.console.write
fn glob_ok(p: List[String], pi: Int, w: List[String], wi: Int) Bool:
    if pi == p.length():
        return wi == w.length()

    let c = p[pi]

    if c == "*":
        var k = wi

        while true:
            if glob_ok(p, pi + 1, w, k):
                return true
            if k >= w.length():
                return false
            if w[k] == "/":
                return false

            k += 1

    if wi >= w.length():
        return false

    if c == "?":
        if w[wi] == "/":
            return false

        return glob_ok(p, pi + 1, w, wi + 1)

    if w[wi] != c:
        return false

    return glob_ok(p, pi + 1, w, wi + 1)

// ---------- Makefile lines ----------

// ms: allow_effect std.console.write
fn strip_comment(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var out = ""
    var k = 0

    while k < n:
        if cs[k] == "\\" and k + 1 < n and cs[k + 1] == "#":
            out += "#"
            k += 2
        else if cs[k] == "#":
            break
        else:
            out += cs[k]
            k += 1

    return out

// ms: allow_effect std.console.write
fn logical_lines(phys: List[String]) List[LLine]:
    var out = List[LLine]()
    let n = phys.length()
    var i = 0

    while i < n:
        let num = i + 1
        var cur = phys[i].clone()
        i += 1

        while cur.ends_with("\\") and i < n:
            let cs = cur.chars()
            let head = cat(cs, 0, cs.length() - 1).trim_end_chars(" \t")
            cur = head + " " + phys[i].trim_start_chars(" \t")
            i += 1

        if cur.starts_with("\t"):
            let body = cur.trim_start_chars("\t")
            if body.trim_chars(" \t\r") != "":
                out.append(LLine(num: num, text: body, recipe: true))
        else:
            let t = strip_comment(cur).trim_chars(" \t")
            if t != "":
                out.append(LLine(num: num, text: t, recipe: false))

    return out

// first word of a directive line, or "" when it is not a conditional directive
// ms: allow_effect std.console.write
fn directive_kw(t: String) String:
    let cs = t.chars()
    let n = cs.length()
    var k = 0

    while k < n:
        if cs[k] == " " or cs[k] == "\t" or cs[k] == "(":
            break

        k += 1

    let kw = cat(cs, 0, k)
    if kw == "ifdef" or kw == "ifndef" or kw == "ifeq" or kw == "ifneq":
        return kw
    if kw == "else" and t == "else":
        return "else"
    if kw == "endif":
        return "endif"

    return ""

// top-level ':' of a logical line (outside $() / ${} and before any ';'), or -1
// ms: allow_effect std.console.write
fn top_colon(cs: List[String]) Int:
    let n = cs.length()
    var depth = 0
    var k = 0

    while k < n:
        let c = cs[k]
        if c == ";":
            return -1
        if depth == 0 and c == ":":
            return k

        if c == "$" and k + 1 < n:
            let d = cs[k + 1]

            if d == "(" or d == "\{":
                depth += 1
                k += 2
                continue

        if depth > 0:
            if c == "(" or c == "\{":
                depth += 1
            else if c == ")" or c == "\}":
                depth -= 1

        k += 1

    return -1

// ms: allow_effect std.console.write
fn is_active(conds: List[Cond]) Bool:
    if conds.length() == 0:
        return true

    let c = conds[conds.length() - 1]
    return c.parent and (c.cv != c.in_else)

// ms: allow_effect std.console.write
fn is_defined(mk: Mk, nm: String) Bool:
    if let cv = mk.cmd.get(nm):
        return cv != ""
    if let v = mk.vars.get(nm):
        return v.value != ""

    return false

// ---------- expansion ----------

// ms: allow_effect std.console.write
fn is_func(n: String) Bool:
    return (
        n == "subst"
        or n == "patsubst"
        or n == "strip"
        or n == "findstring"
        or n == "filter"
        or n == "filter-out"
        or n == "sort"
        or n == "word"
        or n == "wordlist"
        or n == "words"
        or n == "firstword"
        or n == "lastword"
        or n == "dir"
        or n == "notdir"
        or n == "suffix"
        or n == "basename"
        or n == "addprefix"
        or n == "addsuffix"
        or n == "wildcard"
        or n == "foreach"
        or n == "if"
        or n == "info"
        or n == "error"
    )

// ms: allow_effect std.console.write
fn is_auto(name: String) Bool:
    return (
        name == "@"
        or name == "<"
        or name == "^"
        or name == "?"
        or name == "|"
        or name == "*"
    )

// ms: allow_effect std.console.write
fn auto_val(cx: Cx, name: String) String:
    if name == "@":
        return cx.at.clone()
    if name == "<":
        return cx.lt.clone()
    if name == "^":
        return cx.caret.clone()
    if name == "?":
        return cx.qmark.clone()
    if name == "|":
        return cx.pipe.clone()

    return cx.star.clone()

// ms: allow_effect std.console.write
fn split_args(s: String) List[String]:
    var out = List[String]()
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
            out.append(cur.clone())
            cur = ""
        else:
            cur += c

    out.append(cur)
    return out

// ms: allow_effect std.console.write
fn argk_raw(raw: List[String], k: Int) String:
    if k < raw.length():
        return raw[k].trim_chars(" \t")

    return ""

// ms: allow_effect std.console.write
fn argk(ea: List[String], k: Int) String:
    if k < ea.length():
        return ea[k].clone()

    return ""

// ms: allow_effect std.console.write
fn subst_ref(val: String, frm: String, tov: String) String:
    var pat = "%" + frm
    if frm.contains("%"):
        pat = frm.clone()

    var rep = "%" + tov
    if tov.contains("%"):
        rep = tov.clone()

    var out = List[String]()

    for w in words_of(val):
        if pmatch(pat, w):
            out.append(subst_pct(rep, pstem(pat, w)))
        else:
            out.append(w.clone())

    return out.join(" ")

// ms: allow_effect std.console.write
fn word_fn(fname: String, w: String) String:
    let wc = w.chars()
    let n = wc.length()
    var lslash = -1
    var ldot = -1
    var k = 0

    while k < n:
        if wc[k] == "/":
            lslash = k
        if wc[k] == ".":
            ldot = k
        k += 1

    if fname == "dir":
        if lslash < 0:
            return "./"

        return cat(wc, 0, lslash + 1)

    if fname == "notdir":
        return cat(wc, lslash + 1, n)

    if ldot < lslash:
        ldot = -1

    if fname == "suffix":
        if ldot < 0:
            return ""

        return cat(wc, ldot, n)

    if ldot < 0:
        return w.clone()

    return cat(wc, 0, ldot)

// ms: allow_effect std.console.write
fn expand_rec(
    mk: Mk,
    files: Map[String, Int],
    var cx: Cx,
    name: String,
    raw: String
) String!String:
    for s in cx.stack:
        if s == name:
            return error(
                mkmsg(
                    cx.line,
                    "Recursive variable '{name}' references itself (eventually)"
                )
            )
    cx.stack.append(name.clone())

    let r = try ex(mk, files, var cx, raw)
    let _ = cx.stack.pop()
    return ok(r)

// ms: allow_effect std.console.write
fn var_value(mk: Mk, files: Map[String, Int], var cx: Cx, name: String) String!String:
    var b = cx.bnames.length() - 1

    while b >= 0:
        if cx.bnames[b] == name:
            return ok(cx.bvals[b].clone())

        b -= 1

    if cx.auto_on and is_auto(name):
        return ok(auto_val(cx, name))
    if let cv = mk.cmd.get(name):
        return expand_rec(mk, files, var cx, name, cv)

    if let v = mk.vars.get(name):
        if v.simple:
            return ok(v.value.clone())

        return expand_rec(mk, files, var cx, name, v.value)

    return ok("")

// ms: allow_effect std.console.write
fn call_func(
    mk: Mk,
    files: Map[String, Int],
    var cx: Cx,
    fname: String,
    argtext: String
) String!String:
    let raw = split_args(argtext)

    if fname == "info":
        let t = try ex(mk, files, var cx, argk_raw(raw, 0))
        print(t)
        return ok("")

    if fname == "error":
        let t = try ex(mk, files, var cx, argk_raw(raw, 0))
        return error(mkmsg(cx.line, t))

    if fname == "if":
        let c = try ex(mk, files, var cx, argk_raw(raw, 0))
        if c.trim_chars(" \t") != "":
            return ex(mk, files, var cx, argk_raw(raw, 1))
        if raw.length() > 2:
            return ex(mk, files, var cx, argk_raw(raw, 2))

        return ok("")

    if fname == "foreach":
        let vn0 = try ex(mk, files, var cx, argk_raw(raw, 0))
        let vn = vn0.trim_chars(" \t")
        let lst = try ex(mk, files, var cx, argk_raw(raw, 1))
        let body = argk_raw(raw, 2)
        var parts = List[String]()

        for w in words_of(lst):
            cx.bnames.append(vn.clone())
            cx.bvals.append(w.clone())

            let r = try ex(mk, files, var cx, body)
            let _ = cx.bnames.pop()
            let _ = cx.bvals.pop()
            parts.append(r)

        return ok(parts.join(" "))

    var ea = List[String]()

    for r in raw:
        let v = try ex(mk, files, var cx, r.trim_chars(" \t"))
        ea.append(v)

    if fname == "subst":
        let frm = argk(ea, 0)
        let tov = argk(ea, 1)
        let txt = argk(ea, 2)
        if frm == "":
            return ok(txt)

        return ok(txt.replace(frm, tov))

    if fname == "patsubst":
        let pat = argk(ea, 0)
        let rep = argk(ea, 1)
        var out = List[String]()

        for w in words_of(argk(ea, 2)):
            if pmatch(pat, w):
                out.append(subst_pct(rep, pstem(pat, w)))
            else:
                out.append(w.clone())

        return ok(out.join(" "))

    if fname == "strip":
        return ok(words_of(argk(ea, 0)).join(" "))

    if fname == "findstring":
        let f = argk(ea, 0)
        if argk(ea, 1).contains(f):
            return ok(f)

        return ok("")

    if fname == "filter" or fname == "filter-out":
        let pats = words_of(argk(ea, 0))
        var out = List[String]()

        for w in words_of(argk(ea, 1)):
            var hit = false
            for p in pats:
                if pmatch(p, w):
                    hit = true

            if fname == "filter":
                if hit:
                    out.append(w.clone())
            else:
                if not hit:
                    out.append(w.clone())

        return ok(out.join(" "))

    if fname == "sort":
        var ws = words_of(argk(ea, 0))
        ws.sort()

        var out = List[String]()
        for w in ws:
            if out.length() == 0 or out[out.length() - 1] != w:
                out.append(w.clone())
        return ok(out.join(" "))

    if fname == "word":
        let ws = words_of(argk(ea, 1))
        let idx = argk(ea, 0).trim_chars(" \t").parse_int()
        if let n = idx:
            if n >= 1 and n <= ws.length():
                return ok(ws[n - 1].clone())
        return ok("")

    if fname == "wordlist":
        let ws = words_of(argk(ea, 2))
        let sidx = argk(ea, 0).trim_chars(" \t").parse_int()
        let eidx = argk(ea, 1).trim_chars(" \t").parse_int()

        if let s = sidx:
            if let e0 = eidx:
                var e = e0
                if e > ws.length():
                    e = ws.length()
                if s >= 1 and e >= s and s <= ws.length():
                    return ok(copy_range(ws, s - 1, e).join(" "))

        return ok("")

    if fname == "words":
        let cnt = words_of(argk(ea, 0)).length()
        return ok("{cnt}")

    if fname == "firstword":
        let ws = words_of(argk(ea, 0))
        if ws.length() > 0:
            return ok(ws[0].clone())

        return ok("")

    if fname == "lastword":
        let ws = words_of(argk(ea, 0))
        if ws.length() > 0:
            return ok(ws[ws.length() - 1].clone())

        return ok("")

    if fname == "dir" or fname == "notdir" or fname == "suffix" or fname == "basename":
        var out = List[String]()

        for w in words_of(argk(ea, 0)):
            let r = word_fn(fname, w)
            if r != "":
                out.append(r)

        return ok(out.join(" "))

    if fname == "addprefix" or fname == "addsuffix":
        let affix = argk(ea, 0)
        var out = List[String]()

        for w in words_of(argk(ea, 1)):
            if fname == "addprefix":
                out.append(affix + w)
            else:
                out.append(w + affix)

        return ok(out.join(" "))

    if fname == "wildcard":
        var names = files.keys()
        names.sort()

        var out = List[String]()

        for pat in words_of(argk(ea, 0)):
            let pc = pat.chars()
            for nm in names:
                if glob_ok(pc, 0, nm.chars(), 0):
                    out.append(nm.clone())

        return ok(out.join(" "))

    return ok("")

// ms: allow_effect std.console.write
fn refer(mk: Mk, files: Map[String, Int], var cx: Cx, inner: String) String!String:
    let ics = inner.chars()
    let n = ics.length()
    var sp = -1
    var k = 0

    while k < n:
        if ics[k] == " " or ics[k] == "\t":
            sp = k
            break

        k += 1

    if sp > 0:
        let fname = cat(ics, 0, sp)
        if is_func(fname):
            return call_func(mk, files, var cx, fname, cat(ics, sp + 1, n))

    let nm0 = try ex(mk, files, var cx, inner)
    let nm = nm0.trim_chars(" \t")
    let nc = nm.chars()
    let colon = index_of(nc, ":", 1)

    if colon > 0:
        let eqi = index_of(nc, "=", colon + 1)

        if eqi > colon:
            let vn = cat(nc, 0, colon).trim_chars(" \t")
            let frm = cat(nc, colon + 1, eqi)
            let tov = cat(nc, eqi + 1, nc.length())
            let val = try var_value(mk, files, var cx, vn)
            return ok(subst_ref(val, frm, tov))

    return var_value(mk, files, var cx, nm)

// ms: allow_effect std.console.write
fn ex(mk: Mk, files: Map[String, Int], var cx: Cx, s: String) String!String:
    let cs = s.chars()
    let n = cs.length()
    var out = ""
    var i = 0

    while i < n:
        let c = cs[i]

        if c != "$":
            out += c
            i += 1
        else if i + 1 >= n:
            i += 1
        else if cs[i + 1] == "$":
            out += "$"
            i += 2
        else if cs[i + 1] == "(" or cs[i + 1] == "\{":
            let opn = cs[i + 1]
            var cls = ")"
            if opn == "\{":
                cls = "\}"

            var depth = 1
            var j = i + 2

            while j < n:
                if cs[j] == opn:
                    depth += 1
                else if cs[j] == cls:
                    depth -= 1
                    if depth == 0:
                        break

                j += 1

            if j >= n:
                return error(mkmsg(cx.line, "unterminated variable reference"))

            let inner = cat(cs, i + 2, j)
            let v = try refer(mk, files, var cx, inner)
            out += v
            i = j + 1
        else:
            let v = try var_value(mk, files, var cx, cs[i + 1])
            out += v
            i += 2

    return ok(out)

// ---------- rule resolution ----------

// ms: allow_effect std.console.write
fn can_make(mk: Mk, files: Map[String, Int], name: String, depth: Int) Bool:
    if files.contains(name) or mk.ex_pre.contains(name) or mk.phony.contains(name):
        return true
    if depth <= 0:
        return false

    for p in mk.pats:
        if p.rec.length() == 0:
            continue
        if not pmatch(p.pat, name):
            continue

        let stem = pstem(p.pat, name)
        if stem == "":
            continue

        var good = true
        for q in p.pre:
            if not can_make(mk, files, subst_pct(q, stem), depth - 1):
                good = false
        for q in p.oo:
            if not can_make(mk, files, subst_pct(q, stem), depth - 1):
                good = false
        if good:
            return true

    return false

// ms: allow_effect std.console.write
fn resolve(mk: Mk, files: Map[String, Int], t: String) Res:
    let has_ex = mk.ex_pre.contains(t)
    let ex_rec = mk.ex_rec.get_or(t, List[RLine]())
    let ex_pre = mk.ex_pre.get_or(t, List[String]())
    let ex_oo = mk.ex_oo.get_or(t, List[String]())
    if has_ex and ex_rec.length() > 0:
        return Res(found: true, pre: ex_pre, oo: ex_oo, rec: ex_rec, stem: "")

    for p in mk.pats:
        if p.rec.length() == 0:
            continue
        if not pmatch(p.pat, t):
            continue

        let stem = pstem(p.pat, t)
        if stem == "":
            continue

        var good = true
        for q in p.pre:
            if not can_make(mk, files, subst_pct(q, stem), 8):
                good = false
        for q in p.oo:
            if not can_make(mk, files, subst_pct(q, stem), 8):
                good = false

        if good:
            var pre = List[String]()
            for q in p.pre:
                pre.append(subst_pct(q, stem))

            var oo = List[String]()
            for q in p.oo:
                oo.append(subst_pct(q, stem))

            if has_ex:
                for q in ex_pre:
                    pre.append(q.clone())
                for q in ex_oo:
                    oo.append(q.clone())

            return Res(found: true, pre: pre, oo: oo, rec: p.rec.clone(), stem: stem)

    if has_ex:
        return Res(found: true, pre: ex_pre, oo: ex_oo, rec: List[RLine](), stem: "")

    return Res(
        found: false, pre: List[String](), oo: List[String](), rec: List[RLine](),
        stem: ""
    )

// ---------- parsing ----------

// ms: allow_effect std.console.write
fn close_open(var mk: Mk, var op: Open) Unit:
    if not op.active:
        return

    op.active = false

    if op.is_phony:
        for p in op.pre:
            if not mk.phony.contains(p):
                mk.phony.append(p.clone())
        return

    for t in op.targets:
        if t.contains("%"):
            mk.pats.append(
                PRule(
                    pat: t.clone(), pre: op.pre.clone(), oo: op.oo.clone(),
                    rec: op.rec.clone()
                )
            )
        else:
            if not mk.ex_pre.contains(t):
                mk.ex_order.append(t.clone())
                mk.ex_pre[t.clone()] = List[String]()
                mk.ex_oo[t.clone()] = List[String]()
                mk.ex_rec[t.clone()] = List[RLine]()

            var pl = mk.ex_pre.get_or(t, List[String]())
            for p in op.pre:
                pl.append(p.clone())
            mk.ex_pre[t.clone()] = pl

            var ol = mk.ex_oo.get_or(t, List[String]())
            for o in op.oo:
                ol.append(o.clone())
            mk.ex_oo[t.clone()] = ol

            if op.rec.length() > 0:
                if mk.ex_rec.get_or(t, List[RLine]()).length() > 0:
                    print(
                        "Makefile:{op.line}: warning: overriding recipe for target '{t}'"
                    )
                mk.ex_rec[t.clone()] = op.rec.clone()

// ms: allow_effect std.console.write
fn set_var(
    var mk: Mk, files: Map[String, Int], nm: String, aop: String, value: String,
    line: Int
) Unit!String:
    var cx = plain_cx(line)

    if aop == "=":
        mk.vars[nm.clone()] = Var(value: value.clone(), simple: false)
    else if aop == ":=":
        let v = try ex(mk, files, var cx, value)
        mk.vars[nm.clone()] = Var(value: v, simple: true)
    else if aop == "?=":
        if not mk.vars.contains(nm):
            mk.vars[nm.clone()] = Var(value: value.clone(), simple: false)
    else:
        if not mk.vars.contains(nm):
            mk.vars[nm.clone()] = Var(value: value.clone(), simple: false)
        else:
            let old = mk.vars.get_or(nm, Var(value: "", simple: false))

            if old.simple:
                let add = try ex(mk, files, var cx, value)
                var sep = " "
                if old.value == "" or add == "":
                    sep = ""
                mk.vars[nm.clone()] = Var(value: old.value + sep + add, simple: true)
            else:
                var sep2 = " "
                if old.value == "" or value == "":
                    sep2 = ""
                mk.vars[nm.clone()] = Var(
                    value: old.value + sep2 + value, simple: false
                )

    return ok(unit)

// ms: allow_effect std.console.write
fn eval_ifeq(
    mk: Mk,
    files: Map[String, Int],
    var cx: Cx,
    line: Int,
    rest: String
) Bool!String:
    let cs = rest.chars()
    let n = cs.length()
    if n < 2:
        return error(mkmsg(line, "invalid syntax in conditional"))
    if cs[0] != "(" or cs[n - 1] != ")":
        return error(mkmsg(line, "invalid syntax in conditional"))

    let ics = cat(cs, 1, n - 1).chars()
    var commas = List[Int]()
    var depth = 0
    var k = 0

    while k < ics.length():
        let c = ics[k]

        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1
        else if c == "," and depth == 0:
            commas.append(k)

        k += 1

    if commas.length() != 1:
        return error(mkmsg(line, "invalid syntax in conditional"))

    let cpos = commas[0]
    let a = cat(ics, 0, cpos).trim_chars(" \t")
    let b = cat(ics, cpos + 1, ics.length()).trim_chars(" \t")
    let ea = try ex(mk, files, var cx, a)
    let eb = try ex(mk, files, var cx, b)
    return ok(ea.trim_chars(" \t") == eb.trim_chars(" \t"))

// ms: allow_effect std.console.write
fn parse_mk(
    phys: List[String],
    files: Map[String, Int],
    cmdv: Map[String, String]
) Mk!String:
    var mk = Mk(
        vars: Map[String, Var](), cmd: cmdv, phony: List[String](),
        ex_order: List[String](), ex_pre: Map[String, List[String]](),
        ex_oo: Map[String, List[String]](), ex_rec: Map[String, List[RLine]](),
        pats: List[PRule](), default_goal: ""
    )
    var op = Open(
        active: false, is_phony: false, targets: List[String](), pre: List[String](),
        oo: List[String](), rec: List[RLine](), line: 0
    )
    var conds = List[Cond]()
    var cx = plain_cx(0)

    for ll in logical_lines(phys):
        cx.line = ll.num

        if ll.recipe:
            if not is_active(conds):
                continue
            if not op.active:
                return error(mkmsg(ll.num, "recipe commences before first target"))

            op.rec.append(RLine(text: ll.text.clone(), line: ll.num))
            continue

        let kw = directive_kw(ll.text)

        if kw != "":
            close_open(var mk, var op)

            if kw == "ifdef" or kw == "ifndef" or kw == "ifeq" or kw == "ifneq":
                if not is_active(conds):
                    conds.append(
                        Cond(
                            parent: false, cv: false, in_else: false, line: ll.num
                        )
                    )
                    continue

                var cv = false
                let rest = ll.text.drop(kw.length()).trim_chars(" \t")

                if kw == "ifdef" or kw == "ifndef":
                    let nm0 = try ex(mk, files, var cx, rest)
                    let d = is_defined(mk, nm0.trim_chars(" \t"))
                    cv = d
                    if kw == "ifndef":
                        cv = not d
                else:
                    let eqv = try eval_ifeq(mk, files, var cx, ll.num, rest)
                    cv = eqv
                    if kw == "ifneq":
                        cv = not eqv

                conds.append(Cond(parent: true, cv: cv, in_else: false, line: ll.num))
            else if kw == "else":
                if conds.length() == 0:
                    return error(mkmsg(ll.num, "extraneous 'else'"))

                let k = conds.length() - 1
                if conds[k].in_else:
                    return error(mkmsg(ll.num, "extraneous 'else'"))

                conds[k] = Cond(
                    parent: conds[k].parent, cv: conds[k].cv, in_else: true,
                    line: conds[k].line
                )
            else:
                if conds.length() == 0:
                    return error(mkmsg(ll.num, "extraneous 'endif'"))

                conds.remove(conds.length() - 1)

            continue

        if not is_active(conds):
            continue

        close_open(var mk, var op)

        let cs = ll.text.chars()
        let n = cs.length()
        let eq = index_of(cs, "=", 0)
        let col = top_colon(cs)

        if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
            var aop = "="
            var name_end = eq

            if eq >= 1:
                let pc = cs[eq - 1]

                if pc == ":" or pc == "?" or pc == "+":
                    aop = pc + "="
                    name_end = eq - 1

            let name_raw = cat(cs, 0, name_end)
            let value = cat(cs, eq + 1, n).trim_chars(" \t")
            let nm0 = try ex(mk, files, var cx, name_raw)
            let nm = nm0.trim_chars(" \t")
            if nm == "":
                return error(mkmsg(ll.num, "empty variable name"))
            if mk.cmd.contains(nm):
                continue

            let _ = try set_var(var mk, files, nm, aop, value, ll.num)
            continue

        if col >= 0:
            let head = cat(cs, 0, col)
            let semi = index_of(cs, ";", col + 1)
            var pre_text = cat(cs, col + 1, n)
            var inline_cmd = ""

            if semi >= 0:
                pre_text = cat(cs, col + 1, semi)
                inline_cmd = cat(cs, semi + 1, n)

            let tg = try ex(mk, files, var cx, head)
            let pt = try ex(mk, files, var cx, pre_text)
            let targets0 = words_of(tg)
            let ptc = pt.chars()
            let bar = index_of(ptc, "|", 0)
            var normal = List[String]()
            var oo = List[String]()

            if bar >= 0:
                normal = words_of(cat(ptc, 0, bar))
                oo = words_of(cat(ptc, bar + 1, ptc.length()))
            else:
                normal = words_of(pt)

            var is_ph = false
            var tl = targets0.clone()

            if targets0.length() == 1 and targets0[0] == ".PHONY":
                is_ph = true
                tl = List[String]()

            var rec = List[RLine]()
            let ic = inline_cmd.trim_chars(" \t")
            if ic != "":
                rec.append(RLine(text: ic, line: ll.num))
            op = Open(
                active: true, is_phony: is_ph, targets: tl, pre: normal, oo: oo,
                rec: rec, line: ll.num
            )
            continue

        let rr = try ex(mk, files, var cx, ll.text)
        if rr.trim_chars(" \t") != "":
            return error(mkmsg(ll.num, "missing separator"))

    close_open(var mk, var op)
    if conds.length() > 0:
        return error(mkmsg(conds[conds.length() - 1].line, "missing 'endif'"))

    var dg = ""

    for t in mk.ex_order:
        if not t.starts_with("."):
            dg = t.clone()
            break

    mk.default_goal = dg
    return ok(mk)

// ---------- building ----------

// ms: allow_effect std.console.write
fn simulate(var st: St, cmd: String) Int:
    let w = words_of(cmd)
    if w.length() == 0:
        return 0

    let c0 = w[0]
    if c0 == "false":
        return 1

    if c0 == "exit":
        if w.length() > 1:
            if let n = w[1].parse_int():
                return n

            return 2

        return 0

    if c0 == "touch":
        var k = 1

        while k < w.length():
            if not w[k].starts_with("-"):
                st.clock += 1
                st.files[w[k].clone()] = st.clock

            k += 1

        return 0

    if c0 == "rm":
        var k = 1

        while k < w.length():
            if not w[k].starts_with("-"):
                st.files.remove(w[k].clone())
            k += 1

        return 0

    if c0 == "cp":
        if w.length() == 3:
            if not st.files.contains(w[1]):
                print("cp: cannot stat '{w[1]}': No such file or directory")
                return 1

            st.clock += 1
            st.files[w[2].clone()] = st.clock

        return 0

    if c0 == "echo":
        var outs = List[String]()
        var k = 1

        while k < w.length():
            outs.append(strip_quotes(w[k]))
            k += 1

        print(outs.join(" "))
        return 0

    return 0

// ms: allow_effect std.console.write
fn run_recipe(
    mk: Mk,
    var st: St,
    t: String,
    r: Res,
    was_in: Bool,
    old_m: Int
) Unit!String:
    st.runs += 1

    let norm = dedup(r.pre)
    var ql = List[String]()

    for p in norm:
        var q = false

        if not was_in:
            q = true
        else if st.changed.get_or(p, false):
            q = true
        else if st.files.contains(p) and st.files.get_or(p, 0) > old_m:
            q = true

        if q:
            ql.append(p.clone())

    var first = ""
    if r.pre.length() > 0:
        first = r.pre[0].clone()

    var cx = Cx(
        line: 0, auto_on: true, at: t.clone(), lt: first, caret: norm.join(" "),
        qmark: ql.join(" "), pipe: dedup(r.oo).join(" "), star: r.stem.clone(),
        stack: List[String](), bnames: List[String](), bvals: List[String]()
    )

    for rl in r.rec:
        cx.line = rl.line

        let txt = try ex(mk, st.files, var cx, rl.text)
        var cmd = txt.trim_chars(" \t")
        var silent = false
        var ignore = false
        var go = true

        while go:
            if cmd.starts_with("@"):
                silent = true
                cmd = cmd.drop(1)
            else if cmd.starts_with("-"):
                ignore = true
                cmd = cmd.drop(1)
            else if (
                cmd.starts_with("+")
                or cmd.starts_with(" ")
                or cmd.starts_with("\t")
            ):
                cmd = cmd.drop(1)
            else:
                go = false

        cmd = cmd.trim_chars(" \t")
        if cmd == "":
            continue

        if st.dry or not silent:
            print(cmd)
        if st.dry:
            continue

        let status = simulate(var st, cmd)

        if status != 0:
            if ignore:
                print("make: [Makefile:{rl.line}: {t}] Error {status} (ignored)")
            else:
                return error("make: *** [Makefile:{rl.line}: {t}] Error {status}")

    if not st.dry and not mk.phony.contains(t):
        st.clock += 1
        st.files[t.clone()] = st.clock

    return ok(unit)

// ms: allow_effect std.console.write
fn update(mk: Mk, var st: St, t: String, needed: String) Bool!String:
    if st.memo.contains(t):
        return ok(st.memo.get_or(t, false))

    if st.stack.contains(t):
        var parts = List[String]()
        var k = index_of(st.stack, t, 0)

        while k < st.stack.length():
            parts.append(st.stack[k].clone())
            k += 1

        parts.append(t.clone())
        return error(mkerr("Circular dependency detected: " + parts.join(" -> ")))

    let r = resolve(mk, st.files, t)

    if not r.found:
        var res = false

        if st.files.contains(t):
            res = false
        else if mk.phony.contains(t):
            res = true
        else:
            if needed == "":
                return error(mkerr("No rule to make target '{t}'"))

            return error(mkerr("No rule to make target '{t}', needed by '{needed}'"))

        st.memo[t.clone()] = res
        return ok(res)

    st.stack.append(t.clone())

    let was_in = st.files.contains(t)
    let old_m = st.files.get_or(t, 0)
    var anych = false
    var newer = false

    for p in dedup(r.pre):
        let c = try update(mk, var st, p, t)

        if c:
            anych = true
            st.changed[p.clone()] = true

        if was_in and st.files.contains(p) and st.files.get_or(p, 0) > old_m:
            newer = true

    for o in dedup(r.oo):
        let _ = try update(mk, var st, o, t)

    let must = mk.phony.contains(t) or not st.files.contains(t) or anych or newer
    var changed = false

    if must:
        changed = true
        if r.rec.length() > 0:
            let _ = try run_recipe(mk, var st, t, r, was_in, old_m)

    let _ = st.stack.pop()
    st.memo[t.clone()] = changed
    return ok(changed)

// ms: allow_effect std.console.write
fn do_build(mk: Mk, var st: St, goals: List[String], dry: Bool) Unit!String:
    st.dry = dry
    st.memo = Map[String, Bool]()
    st.stack = List[String]()
    st.changed = Map[String, Bool]()
    st.runs = 0

    var gs = List[String]()
    for g in goals:
        gs.append(g.clone())

    if gs.length() == 0:
        if mk.default_goal == "":
            return error(mkerr("No targets"))

        gs.append(mk.default_goal.clone())

    for g in gs:
        let before = st.runs
        let _ = try update(mk, var st, g, "")

        if st.runs == before:
            let r = resolve(mk, st.files, g)

            if (
                r.rec.length() > 0
                or (not mk.phony.contains(g) and st.files.contains(g))
            ):
                print("make: '{g}' is up to date.")
            else:
                print("make: Nothing to be done for '{g}'.")

    return ok(unit)

// ms: allow_effect std.console.write
fn deps_visit(
    mk: Mk,
    files: Map[String, Int],
    t: String,
    var stack: List[String],
    var done: Map[String, Bool],
    var out: List[String]
) Unit!String:
    let r = resolve(mk, files, t)
    var kids = dedup(r.pre)
    for o in dedup(r.oo):
        kids.append(o.clone())

    for c in kids:
        if done.get_or(c, false):
            continue

        if stack.contains(c):
            var parts = List[String]()
            var k = index_of(stack, c, 0)

            while k < stack.length():
                parts.append(stack[k].clone())
                k += 1

            parts.append(c.clone())
            return error(mkerr("Circular dependency detected: " + parts.join(" -> ")))

        stack.append(c.clone())

        let _ = try deps_visit(mk, files, c, var stack, var done, var out)
        let _ = stack.pop()
        done[c.clone()] = true
        out.append(c.clone())

    return ok(unit)

// ms: allow_effect std.console.write
fn fmt_deps(pre: List[String], oo: List[String]) String:
    var s = ""
    if pre.length() > 0:
        s += " " + pre.join(" ")
    if oo.length() > 0:
        s += " | " + oo.join(" ")
    return s

// ms: allow_effect std.console.write
fn print_targets(mk: Mk) Unit:
    if mk.default_goal != "":
        print("default: {mk.default_goal}")

    for t in mk.ex_order:
        let pre = mk.ex_pre.get_or(t, List[String]())
        let oo = mk.ex_oo.get_or(t, List[String]())
        print("{t}:" + fmt_deps(pre, oo))

    for p in mk.pats:
        print("pattern {p.pat}:" + fmt_deps(p.pre, p.oo))
    if mk.phony.length() > 0:
        print("phony: " + mk.phony.join(" "))

// ---------- requests ----------

// ms: allow_effect std.console.write
fn exec(var st: St, line: String) Unit!String:
    let toks = words_of(line)
    let cmd = toks[0].clone()

    if cmd == "build" or cmd == "dry" or cmd == "deps" or cmd == "targets":
        var vars = Map[String, String]()
        var goals = List[String]()
        var k = 1

        while k < toks.length():
            let tk = toks[k].clone()
            let tc = tk.chars()
            let eqp = index_of(tc, "=", 1)

            if eqp >= 1:
                let nm = cat(tc, 0, eqp)
                vars[nm] = cat(tc, eqp + 1, tc.length())
            else:
                goals.append(tk)

            k += 1

        if cmd == "deps" and goals.length() != 1:
            print("usage: deps TARGET")
            return ok(unit)

        let mk = try parse_mk(st.mkl, st.files, vars)
        if cmd == "build":
            return do_build(mk, var st, goals, false)
        if cmd == "dry":
            return do_build(mk, var st, goals, true)

        if cmd == "targets":
            print_targets(mk)
            return ok(unit)

        var stack = List[String]()
        stack.append(goals[0].clone())

        var done = Map[String, Bool]()
        var out = List[String]()
        let _ = try deps_visit(
            mk, st.files, goals[0].clone(), var stack, var done, var out
        )
        if out.length() == 0:
            print("(no prerequisites)")
        for x in out:
            print(x)
        return ok(unit)

    if cmd == "expand":
        let t = line.trim_chars(" \t\r")
        let tc = t.chars()
        let rest = cat(tc, 6, tc.length()).trim_chars(" \t")
        let mk = try parse_mk(st.mkl, st.files, Map[String, String]())
        var cx = plain_cx(0)
        let r = try ex(mk, st.files, var cx, rest)
        print("[{r}]")
        return ok(unit)

    if cmd == "files":
        var ks = st.files.keys()
        ks.sort()
        if ks.length() == 0:
            print("(no files)")

        for k in ks:
            let mt = st.files.get_or(k, 0)
            print("{k} {mt}")

        return ok(unit)

    if cmd == "touch":
        if toks.length() == 2:
            st.clock += 1
            st.files[toks[1].clone()] = st.clock
        else if toks.length() == 3:
            if let nv = toks[2].parse_int():
                st.files[toks[1].clone()] = nv
                if nv > st.clock:
                    st.clock = nv
            else:
                print("bad request")
        else:
            print("bad request")

        return ok(unit)

    if cmd == "rm":
        var k = 1

        while k < toks.length():
            st.files.remove(toks[k].clone())
            k += 1

        return ok(unit)

    print("unknown request: {cmd}")
    return ok(unit)

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn read_all() List[String]!Error:
    var out = List[String]()
    for line in lines(stdin()):
        out.append(line)
    return ok(out)

// ms: allow_effect std.console.write
fn run_all(all: List[String]) Unit:
    let n = all.length()
    var s1 = -1
    var s2 = -1
    var k = 0

    while k < n:
        if all[k] == "====":
            if s1 < 0:
                s1 = k
            else if s2 < 0:
                s2 = k

        k += 1

    var mkl = List[String]()
    var tbl = List[String]()
    var reqs = List[String]()

    if s1 < 0:
        mkl = copy_range(all, 0, n)
    else:
        mkl = copy_range(all, 0, s1)

        if s2 < 0:
            tbl = copy_range(all, s1 + 1, n)
        else:
            tbl = copy_range(all, s1 + 1, s2)
            reqs = copy_range(all, s2 + 1, n)

    var files = Map[String, Int]()
    var clock = 0

    for line in tbl:
        let f = words_of(line)

        if f.length() == 2:
            if let v = f[1].parse_int():
                if v >= 0:
                    files[f[0].clone()] = v
                    if v > clock:
                        clock = v

    var st = St(
        files: files, clock: clock, memo: Map[String, Bool](), stack: List[String](),
        runs: 0, changed: Map[String, Bool](), dry: false, mkl: mkl
    )

    for line in reqs:
        let t = line.trim_chars(" \t\r")
        if t == "" or t.starts_with("#"):
            continue

        print("> " + line.trim_end())

        let r = exec(var st, line)
        if r.is_error():
            print(r.err())

export fn main() Int:
    if let all = read_all():
        run_all(all)
    return 0
