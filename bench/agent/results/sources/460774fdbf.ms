import (
    stdout from "@std/io/io.ms",
    stdin from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
)

type Var:
    value: String
    simple: Bool

type RLine:
    line: Int
    text: String

type Rule:
    normal: List[String]
    oo: List[String]
    recipe: List[RLine]

type PRule:
    pat: String
    normal: List[String]
    oo: List[String]
    recipe: List[RLine]

type Frame:
    line: Int
    parent: Bool
    cond: Bool
    in_else: Bool
    seen_else: Bool

type Res:
    has: Bool
    normal: List[String]
    oo: List[String]
    recipe: List[RLine]
    stem: String

type LLine:
    num: Int
    text: String

type Fatal:
    text: String

type Env:
    mk: List[String]
    vars: Map[String, Var]
    cli: List[String]
    out: List[String]
    mute: Bool
    line: Int
    rstack: List[String]
    explicit: Map[String, Rule]
    order: List[String]
    prules: List[PRule]
    phony: List[String]
    frames: List[Frame]
    has_pend: Bool
    pend_targets: List[String]
    pend_normal: List[String]
    pend_oo: List[String]
    pend_recipe: List[RLine]
    pend_line: Int
    pend_phony: Bool
    files: Map[String, Int]
    clock: Int
    memo: Map[String, Bool]
    dstack: List[String]
    ran: Int
    dry: Bool
    dseen: List[String]
    dres: List[String]

FUNCS := [
    "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word",
    "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename",
    "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"
]
LETTERS := "abcdefghijklmnopqrstuvwxyz"

// ---------- small helpers ----------

fn cjoin(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var i = a

    while i < b:
        s += cs[i]
        i += 1

    return s

fn sub(s: String, a: Int, b: Int) String:
    return cjoin(s.chars(), a, b)

fn cfind(cs: List[String], ch: String, from: Int) Int:
    var i = from
    if i < 0:
        i = 0

    while i < cs.length():
        if cs[i] == ch: return i

        i += 1

    return -1

fn clast(cs: List[String], ch: String) Int:
    var i = cs.length() - 1

    while i >= 0:
        if cs[i] == ch: return i

        i -= 1

    return -1

fn sub_list(xs: List[String], a: Int, b: Int) List[String]:
    var out = List[String]()
    var i = a

    while i < b:
        out.append(xs[i].clone())
        i += 1

    return out

fn dedupe(xs: List[String]) List[String]:
    var out = List[String]()
    for x in xs:
        if not out.contains(x):
            out.append(x.clone())
    return out

fn has_pct(s: String) Bool:
    return s.contains("%")

fn repl_pct(s: String, st: String) String:
    cs := s.chars()
    k := cfind(cs, "%", 0)
    if k < 0: return s.clone()

    return cjoin(cs, 0, k) + st + cjoin(cs, k + 1, cs.length())

fn joinsp(a: String, b: String) String:
    if a == "" or b == "": return a + b

    return a + " " + b

// Pattern match. Returns the stem, or none. nonempty requires a non-empty stem.
fn pmatch(pat: String, name: String, nonempty: Bool) String?:
    pc := pat.chars()
    k := cfind(pc, "%", 0)

    if k < 0:
        if name == pat: return ""

        return none

    pre := cjoin(pc, 0, k)
    suf := cjoin(pc, k + 1, pc.length())
    nl := name.length()
    var minl = pre.length() + suf.length()
    if nonempty:
        minl += 1
    if nl < minl: return none
    if not name.starts_with(pre) or not name.ends_with(suf): return none

    return sub(name, pre.length(), nl - suf.length())

fn glob_m(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi >= p.length(): return si >= s.length()

    c := p[pi]

    if c == "*":
        var k = si

        while true:
            if glob_m(p, pi + 1, s, k): return true
            if k >= s.length() or s[k] == "/": return false

            k += 1

    if c == "?":
        return si < s.length() and s[si] != "/" and glob_m(p, pi + 1, s, si + 1)

    return si < s.length() and s[si] == c and glob_m(p, pi + 1, s, si + 1)

fn strip_tabs(s: String) String:
    cs := s.chars()
    var k = 0
    while k < cs.length() and cs[k] == "\t":
        k += 1
    return cjoin(cs, k, cs.length())

fn strip_comment(s: String) String:
    cs := s.chars()
    n := cs.length()
    var out = ""
    var i = 0

    while i < n:
        if cs[i] == "\\" and i + 1 < n and cs[i + 1] == "#":
            out += "#"
            i += 2
        else if cs[i] == "#":
            break
        else:
            out += cs[i]
            i += 1

    return out

// Joins physical lines into logical lines (backslash continuation).
fn logical(phys: List[String]) List[LLine]:
    var out = List[LLine]()
    n := phys.length()
    var i = 0

    while i < n:
        start := i + 1
        var cur = phys[i].clone()

        while cur.ends_with("\\") and i + 1 < n:
            base := sub(cur, 0, cur.length() - 1).trim_end()
            i += 1
            cur = base + " " + phys[i].trim_start()

        out.append(LLine(num: start, text: cur))
        i += 1

    return out

// Top-level ':' (outside $(...) / ${...}, before any ';'), or -1.
fn find_colon(cs: List[String]) Int:
    var depth = 0
    var i = 0
    n := cs.length()

    while i < n:
        c := cs[i]

        if c == "$" and i + 1 < n and (cs[i + 1] == "(" or cs[i + 1] == "\{"):
            depth += 1
            i += 2
        else if depth > 0:
            if c == "(" or c == "\{":
                depth += 1
            else if c == ")" or c == "\}":
                depth -= 1

            i += 1
        else:
            if c == ";": return -1
            if c == ":": return i

            i += 1

    return -1

// Returns the keyword of a conditional directive line, or "".
fn directive_kw(t: String) String:
    if t == "else" or t == "endif": return t.clone()

    cs := t.chars()
    n := cs.length()
    var k = 0
    while k < n and LETTERS.contains(cs[k]):
        k += 1

    kw := cjoin(cs, 0, k)
    if kw == "ifdef" or kw == "ifndef" or kw == "ifeq" or kw == "ifneq":
        if k == n or cs[k] == " " or cs[k] == "\t" or cs[k] == "(": return kw.clone()
    return ""

// For "(A,B)": returns [A, B] or [] when the syntax is invalid.
fn parse_ifeq(rest: String) List[String]:
    rc := rest.chars()
    n := rc.length()
    bad := List[String]()
    if n < 2 or rc[0] != "(" or rc[n - 1] != ")": return bad

    var depth = 0
    var commas = List[Int]()
    var j = 1

    while j < n - 1:
        ch := rc[j]

        if ch == "(" or ch == "\{":
            depth += 1
        else if ch == ")" or ch == "\}":
            if depth == 0: return bad

            depth -= 1
        else if ch == "," and depth == 0:
            commas.append(j)

        j += 1

    if commas.length() != 1: return bad

    c := commas[0]
    var res = List[String]()
    res.append(cjoin(rc, 1, c))
    res.append(cjoin(rc, c + 1, n - 1))
    return res

// ---------- expansion ----------

fn close_index(cs: List[String], start: Int, open: String, close: String) Int:
    var depth = 1
    var j = start

    while j < cs.length():
        if cs[j] == open:
            depth += 1
        else if cs[j] == close:
            depth -= 1
            if depth == 0: return j

        j += 1

    return -1

fn split_args(s: String) List[String]:
    cs := s.chars()
    n := cs.length()
    var out = List[String]()
    var depth = 0
    var start = 0

    for i in 0..n:
        c := cs[i]

        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1
        else if c == "," and depth == 0:
            out.append(cjoin(cs, start, i))
            start = i + 1

    out.append(cjoin(cs, start, n))
    return out

fn emit(var e: Env, s: String) Unit:
    if not e.mute:
        e.out.append(s)

fn fatal_at(e: Env, msg: String) Fatal:
    if e.line > 0: return Fatal(text: "Makefile:{e.line}: *** {msg}.  Stop.")

    return Fatal(text: "make: *** {msg}.  Stop.")

fn make_fatal(msg: String) Fatal:
    return Fatal(text: "make: *** {msg}.  Stop.")

fn circ(stack: List[String], p: String) Fatal:
    var parts = List[String]()
    var started = false

    for x in stack:
        if x == p:
            started = true
        if started:
            parts.append(x.clone())

    parts.append(p.clone())
    return make_fatal("Circular dependency detected: " + parts.join(" -> "))

fn expand(var e: Env, text: String) String!Fatal:
    cs := text.chars()
    n := cs.length()
    var res = ""
    var i = 0

    while i < n:
        c := cs[i]

        if c != "$":
            res += c
            i += 1
        else if i + 1 >= n:
            i += 1
        else if cs[i + 1] == "$":
            res += "$"
            i += 2
        else if cs[i + 1] == "(" or cs[i + 1] == "\{":
            var closer = ")"
            if cs[i + 1] == "\{":
                closer = "\}"

            j := close_index(cs, i + 2, cs[i + 1], closer)
            if j < 0: return error(fatal_at(e, "unterminated variable reference"))

            inner := cjoin(cs, i + 2, j)
            v := try ref_value(var e, inner)
            res += v
            i = j + 1
        else:
            v := try lookup_name(var e, cs[i + 1])
            res += v
            i += 2

    return ok(res)

fn lookup_name(var e: Env, name: String) String!Fatal:
    if not e.vars.contains(name): return ok("")

    simple := e.vars[name].simple
    raw := e.vars[name].value.clone()
    if simple: return ok(raw)
    if e.rstack.contains(name):
        return error(
            fatal_at(
                e, "Recursive variable '{name}' references itself (eventually)"
            )
        )

    e.rstack.append(name.clone())

    r := try expand(var e, raw)
    e.rstack.remove(e.rstack.length() - 1)
    return ok(r)

fn patsubst_words(pat: String, rep: String, words: List[String]) String:
    var out = List[String]()

    for w in words:
        if has_pct(pat):
            if st := pmatch(pat, w, false):
                out.append(repl_pct(rep, st))
            else:
                out.append(w.clone())
        else:
            if w == pat:
                out.append(rep.clone())
            else:
                out.append(w.clone())

    return out.join(" ")

fn subst_refs(val: String, from: String, to: String) String:
    var pat = from.clone()
    var rep = to.clone()

    if not has_pct(from):
        pat = "%" + from
        rep = "%" + to

    return patsubst_words(pat, rep, val.fields())

fn ref_value(var e: Env, inner: String) String!Fatal:
    ic := inner.chars()
    n := ic.length()
    var sp = -1

    for k in 0..n:
        if ic[k] == " " or ic[k] == "\t":
            sp = k
            break

    if sp > 0:
        fname := cjoin(ic, 0, sp)

        if FUNCS.contains(fname):
            args := split_args(cjoin(ic, sp + 1, n))
            return call_fn(var e, fname, args)

    ex := try expand(var e, inner)
    nm := ex.trim()
    nc := nm.chars()
    colon := cfind(nc, ":", 1)

    if colon > 0:
        eqi := cfind(nc, "=", colon + 1)

        if eqi > 0:
            vname := cjoin(nc, 0, colon).trim()
            from := cjoin(nc, colon + 1, eqi)
            to := cjoin(nc, eqi + 1, nc.length())
            val := try lookup_name(var e, vname)
            return ok(subst_refs(val, from, to))

    return lookup_name(var e, nm)

fn argv(var e: Env, args: List[String], k: Int) String!Fatal:
    if k >= args.length(): return ok("")

    raw := args[k].trim()
    return expand(var e, raw)

fn words_of(ws: List[String]) List[Int]:
    return List[Int]()

fn path_map(f: String, ws: List[String]) String:
    var out = List[String]()

    for w in ws:
        cs := w.chars()
        n := cs.length()
        sl := clast(cs, "/")
        dot := clast(cs, ".")
        has_suffix := dot > sl
        var r = ""

        if f == "dir":
            if sl < 0:
                r = "./"
            else:
                r = cjoin(cs, 0, sl + 1)
        else if f == "notdir":
            r = cjoin(cs, sl + 1, n)
        else if f == "suffix":
            if has_suffix:
                r = cjoin(cs, dot, n)
        else:
            if has_suffix:
                r = cjoin(cs, 0, dot)
            else:
                r = w.clone()

        if r != "":
            out.append(r)

    return out.join(" ")

fn call_fn(var e: Env, f: String, args: List[String]) String!Fatal:
    if f == "if":
        c := try argv(var e, args, 0)
        if c.trim() != "": return argv(var e, args, 1)

        return argv(var e, args, 2)

    if f == "info":
        t := try argv(var e, args, 0)
        emit(var e, t)
        return ok("")

    if f == "error":
        t := try argv(var e, args, 0)
        return error(fatal_at(e, t))

    if f == "foreach":
        vn := try argv(var e, args, 0)
        lst := try argv(var e, args, 1)
        body := if args.length() > 2: args[2].trim() else: ""

        words := lst.fields()
        had := e.vars.contains(vn)
        var ov = ""
        var os = false

        if had:
            ov = e.vars[vn].value.clone()
            os = e.vars[vn].simple

        var items = List[String]()

        for w in words:
            e.vars[vn.clone()] = Var(value: w.clone(), simple: true)

            r := try expand(var e, body)
            items.append(r)

        if had:
            e.vars[vn.clone()] = Var(value: ov, simple: os)
        else:
            e.vars.remove(vn)

        return ok(items.join(" "))

    if f == "subst":
        a := try argv(var e, args, 0)
        b := try argv(var e, args, 1)
        c := try argv(var e, args, 2)
        if a == "": return ok(c)

        return ok(c.replace(a, b))

    if f == "patsubst":
        p := try argv(var e, args, 0)
        r := try argv(var e, args, 1)
        t := try argv(var e, args, 2)
        return ok(patsubst_words(p, r, t.fields()))

    if f == "strip":
        t := try argv(var e, args, 0)
        return ok(t.fields().join(" "))

    if f == "findstring":
        a := try argv(var e, args, 0)
        t := try argv(var e, args, 1)
        if t.contains(a): return ok(a)

        return ok("")

    if f == "filter" or f == "filter-out":
        pats := (try argv(var e, args, 0)).fields()
        ws := (try argv(var e, args, 1)).fields()
        var out = List[String]()

        for w in ws:
            var m = false
            for p in pats:
                if _st := pmatch(p, w, false):
                    m = true
            if m == (f == "filter"):
                out.append(w.clone())

        return ok(out.join(" "))

    if f == "sort":
        var ws = (try argv(var e, args, 0)).fields()
        ws.sort()

        var out = List[String]()
        for w in ws:
            if out.is_empty() or out[out.length() - 1] != w:
                out.append(w.clone())
        return ok(out.join(" "))

    if f == "word":
        nt := try argv(var e, args, 0)
        ws := (try argv(var e, args, 1)).fields()
        if k := nt.parse_int():
            if k >= 1 and k <= ws.length(): return ok(ws[k - 1].clone())
        return ok("")

    if f == "wordlist":
        st := try argv(var e, args, 0)
        en := try argv(var e, args, 1)
        ws := (try argv(var e, args, 2)).fields()

        if s := st.parse_int():
            if t := en.parse_int():
                if s >= 1 and t >= s and s <= ws.length():
                    var last = t
                    if last > ws.length():
                        last = ws.length()

                    lo := s - 1
                    var out = List[String]()
                    var i = lo

                    while i < last:
                        out.append(ws[i].clone())
                        i += 1

                    return ok(out.join(" "))

        return ok("")

    if f == "words":
        ws := (try argv(var e, args, 0)).fields()
        cnt := ws.length()
        return ok("{cnt}")

    if f == "firstword":
        ws := (try argv(var e, args, 0)).fields()
        if ws.is_empty(): return ok("")

        return ok(ws[0].clone())

    if f == "lastword":
        ws := (try argv(var e, args, 0)).fields()
        if ws.is_empty(): return ok("")

        return ok(ws[ws.length() - 1].clone())

    if f == "dir" or f == "notdir" or f == "suffix" or f == "basename":
        ws := (try argv(var e, args, 0)).fields()
        return ok(path_map(f, ws))

    if f == "addprefix" or f == "addsuffix":
        a := try argv(var e, args, 0)
        ws := (try argv(var e, args, 1)).fields()
        var out = List[String]()

        for w in ws:
            if f == "addprefix":
                out.append(a + w)
            else:
                out.append(w + a)

        return ok(out.join(" "))

    if f == "wildcard":
        pats := (try argv(var e, args, 0)).fields()
        var out = List[String]()
        names := e.files.keys()

        for p in pats:
            var ms = List[String]()
            pc := p.chars()
            for nm in names:
                if glob_m(pc, 0, nm.chars(), 0):
                    ms.append(nm.clone())
            ms.sort()
            for m in ms:
                out.append(m.clone())

        return ok(out.join(" "))

    return ok("")

// ---------- Makefile parsing ----------

fn active(e: Env) Bool:
    n := e.frames.length()
    if n == 0: return true

    f := e.frames[n - 1]
    if not f.parent: return false
    if f.in_else: return not f.cond

    return f.cond

fn close_rule(var e: Env) Unit:
    if not e.has_pend: return

    e.has_pend = false
    if e.pend_phony: return

    tl := e.pend_targets.clone()
    nl := e.pend_normal.clone()
    ol := e.pend_oo.clone()
    rl := e.pend_recipe.clone()
    ln := e.pend_line

    for t in tl:
        if has_pct(t):
            e.prules.append(
                PRule(
                    pat: t.clone(), normal: nl.clone(), oo: ol.clone(),
                    recipe: rl.clone()
                )
            )
        else:
            if not e.explicit.contains(t):
                e.explicit[t.clone()] = Rule(
                    normal: List[String](), oo: List[String](), recipe: List[RLine]()
                )
                e.order.append(t.clone())

            var r = e.explicit[t].clone()
            for p in nl:
                r.normal.append(p.clone())
            for p in ol:
                r.oo.append(p.clone())

            if not rl.is_empty():
                if not r.recipe.is_empty():
                    emit(
                        var e,
                        "Makefile:{ln}: warning: overriding recipe for target '{t}'"
                    )
                r.recipe = rl.clone()

            e.explicit[t.clone()] = r

fn lookup_defined(e: Env, name: String) Bool:
    return e.vars.contains(name) and e.vars[name].value != ""

fn parse(var e: Env, cli: List[String]) Unit!Fatal:
    e.vars = Map[String, Var]()
    e.cli = List[String]()
    e.explicit = Map[String, Rule]()
    e.order = List[String]()
    e.prules = List[PRule]()
    e.phony = List[String]()
    e.frames = List[Frame]()
    e.has_pend = false
    e.pend_targets = List[String]()
    e.pend_normal = List[String]()
    e.pend_oo = List[String]()
    e.pend_recipe = List[RLine]()
    e.pend_line = 0
    e.pend_phony = false
    e.rstack = List[String]()

    for tok in cli:
        cs := tok.chars()
        k := cfind(cs, "=", 0)
        name := cjoin(cs, 0, k)
        value := cjoin(cs, k + 1, cs.length())
        e.vars[name.clone()] = Var(value: value, simple: false)
        e.cli.append(name)

    lls := logical(e.mk)

    for ll in lls:
        e.line = ll.num

        raw := ll.text.clone()

        if raw.starts_with("\t"):
            if not active(e): continue

            body := strip_tabs(raw)
            if body.trim() == "": continue
            if not e.has_pend:
                return error(fatal_at(e, "recipe commences before first target"))

            e.pend_recipe.append(RLine(line: ll.num, text: body))
            continue

        t := strip_comment(raw).trim()
        if t == "": continue

        kw := directive_kw(t)

        if kw != "":
            close_rule(var e)

            tcs := t.chars()
            rest := cjoin(tcs, kw.length(), tcs.length()).trim()
            act := active(e)

            if kw == "endif":
                k := e.frames.length()
                if k == 0: return error(fatal_at(e, "extraneous 'endif'"))

                e.frames.remove(k - 1)
            else if kw == "else":
                k := e.frames.length()
                if k == 0: return error(fatal_at(e, "extraneous 'else'"))
                if e.frames[k - 1].seen_else:
                    return error(fatal_at(e, "extraneous 'else'"))

                fl := e.frames[k - 1].line
                fp := e.frames[k - 1].parent
                fc := e.frames[k - 1].cond
                e.frames.remove(k - 1)
                e.frames.append(
                    Frame(
                        line: fl, parent: fp, cond: fc, in_else: true, seen_else: true
                    )
                )
            else if kw == "ifdef" or kw == "ifndef":
                var cond = false

                if act:
                    nm := (try expand(var e, rest)).trim()
                    d := lookup_defined(e, nm)

                    if kw == "ifdef":
                        cond = d
                    else:
                        cond = not d

                e.frames.append(
                    Frame(
                        line: ll.num, parent: act, cond: cond, in_else: false,
                        seen_else: false
                    )
                )
            else:
                var cond = false

                if act:
                    parts := parse_ifeq(rest)
                    if parts.length() != 2:
                        return error(fatal_at(e, "invalid syntax in conditional"))

                    a := (try expand(var e, parts[0].trim())).trim()
                    b := (try expand(var e, parts[1].trim())).trim()

                    if kw == "ifeq":
                        cond = a == b
                    else:
                        cond = a != b

                e.frames.append(
                    Frame(
                        line: ll.num, parent: act, cond: cond, in_else: false,
                        seen_else: false
                    )
                )

            continue

        if not active(e): continue

        close_rule(var e)

        cs := t.chars()
        n := cs.length()
        eq := cfind(cs, "=", 0)
        col := find_colon(cs)

        if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
            var nend = eq
            var op = "="

            if (
                eq >= 1
                and (
                    cs[eq - 1] == ":"
                    or cs[eq - 1] == "?"
                    or cs[eq - 1] == "+"
                )
            ):
                nend = eq - 1
                op = cs[eq - 1].clone()

            nraw := cjoin(cs, 0, nend)
            name := (try expand(var e, nraw)).trim()
            if name == "": return error(fatal_at(e, "empty variable name"))

            value := cjoin(cs, eq + 1, n).trim()
            if e.cli.contains(name): continue

            if op == "=":
                e.vars[name.clone()] = Var(value: value, simple: false)
            else if op == ":":
                v := try expand(var e, value)
                e.vars[name.clone()] = Var(value: v, simple: true)
            else if op == "?":
                if not e.vars.contains(name):
                    e.vars[name.clone()] = Var(value: value, simple: false)
            else:
                if not e.vars.contains(name):
                    e.vars[name.clone()] = Var(value: value, simple: false)
                else:
                    osimple := e.vars[name].simple
                    oval := e.vars[name].value.clone()

                    if osimple:
                        add := try expand(var e, value)
                        e.vars[name.clone()] = Var(
                            value: joinsp(oval, add), simple: true
                        )
                    else:
                        e.vars[name.clone()] = Var(
                            value: joinsp(oval, value), simple: false
                        )
        else if col >= 0:
            pre := cjoin(cs, 0, col)
            semi := cfind(cs, ";", col + 1)
            var has_cmd = false
            var cmd = ""
            var pq = ""

            if semi >= 0:
                pq = cjoin(cs, col + 1, semi)
                cmd = cjoin(cs, semi + 1, n)
                has_cmd = true
            else:
                pq = cjoin(cs, col + 1, n)

            pre_x := try expand(var e, pre)
            tg := pre_x.fields()
            pe := try expand(var e, pq)
            pcs := pe.chars()
            bar := cfind(pcs, "|", 0)
            var normal = List[String]()
            var oo = List[String]()

            if bar >= 0:
                normal = cjoin(pcs, 0, bar).fields()
                oo = cjoin(pcs, bar + 1, pcs.length()).fields()
            else:
                normal = pe.fields()

            if tg.length() == 1 and tg[0] == ".PHONY":
                for p in normal:
                    if not e.phony.contains(p):
                        e.phony.append(p.clone())
                for p in oo:
                    if not e.phony.contains(p):
                        e.phony.append(p.clone())
                e.has_pend = true
                e.pend_phony = true
                e.pend_targets = List[String]()
                e.pend_recipe = List[RLine]()
            else:
                e.has_pend = true
                e.pend_phony = false
                e.pend_targets = tg
                e.pend_normal = normal
                e.pend_oo = oo
                e.pend_recipe = List[RLine]()
                e.pend_line = ll.num
                if has_cmd:
                    e.pend_recipe.append(RLine(line: ll.num, text: cmd))
        else:
            v := try expand(var e, t)
            if v.trim() != "": return error(fatal_at(e, "missing separator"))

    close_rule(var e)

    if not e.frames.is_empty():
        k := e.frames.length() - 1
        e.line = e.frames[k].line
        return error(fatal_at(e, "missing 'endif'"))


// ---------- rule resolution ----------

fn canmake(e: Env, name: String, levels: Int) Bool:
    if e.files.contains(name) or e.explicit.contains(name) or e.phony.contains(name):
        return true
    if levels <= 0: return false

    for pr in e.prules:
        if not pr.recipe.is_empty():
            if st := pmatch(pr.pat, name, true):
                var good = true
                for p in pr.normal:
                    if good and not canmake(e, repl_pct(p, st), levels - 1):
                        good = false
                for p in pr.oo:
                    if good and not canmake(e, repl_pct(p, st), levels - 1):
                        good = false
                if good: return true

    return false

fn resolve(e: Env, t: String) Res:
    if r := e.explicit.get(t):
        if not r.recipe.is_empty():
            return Res(
                has: true, normal: r.normal.clone(), oo: r.oo.clone(),
                recipe: r.recipe.clone(), stem: ""
            )

    for pr in e.prules:
        if not pr.recipe.is_empty():
            if st := pmatch(pr.pat, t, true):
                var good = true
                for p in pr.normal:
                    if good and not canmake(e, repl_pct(p, st), 7):
                        good = false
                for p in pr.oo:
                    if good and not canmake(e, repl_pct(p, st), 7):
                        good = false

                if good:
                    var nm = List[String]()
                    for p in pr.normal:
                        nm.append(repl_pct(p, st))

                    var oo = List[String]()
                    for p in pr.oo:
                        oo.append(repl_pct(p, st))

                    if r := e.explicit.get(t):
                        for p in r.normal:
                            nm.append(p.clone())
                        for p in r.oo:
                            oo.append(p.clone())

                    return Res(
                        has: true, normal: nm, oo: oo, recipe: pr.recipe.clone(),
                        stem: st
                    )

    if r := e.explicit.get(t):
        return Res(
            has: true, normal: r.normal.clone(), oo: r.oo.clone(),
            recipe: List[RLine](), stem: ""
        )

    return Res(
        has: false, normal: List[String](), oo: List[String](), recipe: List[RLine](),
        stem: ""
    )

fn default_goal(e: Env) String?:
    for t in e.order:
        if not t.starts_with("."): return t.clone()
    return none

// ---------- build ----------

fn simulate(var e: Env, cmd: String) Int:
    ws := cmd.fields()
    if ws.is_empty(): return 0

    w0 := ws[0].clone()
    var args = List[String]()
    var k = 1

    while k < ws.length():
        args.append(ws[k].clone())
        k += 1

    if w0 == "false": return 1

    if w0 == "exit":
        if args.is_empty(): return 0
        if v := args[0].parse_int(): return v

        return 2

    if w0 == "touch":
        for a in args:
            if not a.starts_with("-"):
                e.clock += 1
                e.files[a.clone()] = e.clock

        return 0

    if w0 == "rm":
        for a in args:
            if not a.starts_with("-"):
                e.files.remove(a)
        return 0

    if w0 == "cp":
        if args.length() == 2:
            if not e.files.contains(args[0]):
                emit(var e, "cp: cannot stat '{args[0]}': No such file or directory")
                return 1

            e.clock += 1
            e.files[args[1].clone()] = e.clock

        return 0

    if w0 == "echo":
        var parts = List[String]()
        for a in args:
            parts.append(a.replace("\"", "").replace("'", ""))
        emit(var e, parts.join(" "))
        return 0

    return 0

fn run_recipe(
    var e: Env, t: String, recipe: List[RLine], first: String, dn: List[String],
    qs: List[String], doo: List[String], stem: String
) Unit!Fatal:
    e.ran += 1
    e.vars["@"] = Var(value: t.clone(), simple: true)
    e.vars["<"] = Var(value: first, simple: true)
    e.vars["^"] = Var(value: dn.join(" "), simple: true)
    e.vars["?"] = Var(value: qs.join(" "), simple: true)
    e.vars["|"] = Var(value: doo.join(" "), simple: true)
    e.vars["*"] = Var(value: stem, simple: true)

    for rl in recipe:
        e.line = rl.line

        ex := try expand(var e, rl.text)
        cmd0 := ex.trim()
        cs := cmd0.chars()
        n := cs.length()
        var k = 0
        var silent = false
        var ign = false

        while (
            k < n
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

        cmd := cjoin(cs, k, n)

        if e.dry:
            if cmd != "":
                emit(var e, cmd)
            continue

        if not silent and cmd != "":
            emit(var e, cmd.clone())

        st := simulate(var e, cmd)

        if st != 0:
            if ign:
                emit(var e, "make: [Makefile:{rl.line}: {t}] Error {st} (ignored)")
            else:
                return error(
                    Fatal(
                        text: "make: *** [Makefile:{rl.line}: {t}] Error {st}"
                    )
                )

    if not e.dry and not e.phony.contains(t):
        e.clock += 1
        e.files[t.clone()] = e.clock


fn update_one(var e: Env, t: String, needed: String) Bool!Fatal:
    r := resolve(e, t.clone())

    if not r.has:
        if e.files.contains(t): return ok(false)
        if e.phony.contains(t): return ok(true)
        if needed == "": return error(make_fatal("No rule to make target '{t}'"))

        return error(make_fatal("No rule to make target '{t}', needed by '{needed}'"))

    in0 := e.files.contains(t)
    m0 := if in0: e.files[t] else: 0

    dn := dedupe(r.normal)
    var anyc = false
    var newer = false
    var qs = List[String]()

    for p in dn:
        c := try update(var e, p.clone(), t.clone())
        var nw = false
        if in0 and e.files.contains(p):
            if e.files[p] > m0:
                nw = true
        if c:
            anyc = true
        if nw:
            newer = true
        if not in0 or c or nw:
            qs.append(p.clone())

    doo := dedupe(r.oo)
    for p in doo:
        _o := try update(var e, p.clone(), t.clone())

    need := e.phony.contains(t) or not e.files.contains(t) or anyc or newer
    if not need: return ok(false)

    if not r.recipe.is_empty():
        first := if dn.length() > 0: dn[0].clone() else: ""
        try run_recipe(var e, t.clone(), r.recipe, first, dn, qs, doo, r.stem)

    return ok(true)

fn update(var e: Env, t: String, needed: String) Bool!Fatal:
    if m := e.memo.get(t): return ok(m)
    if e.dstack.contains(t): return error(circ(e.dstack, t))

    e.dstack.append(t.clone())

    c := try update_one(var e, t.clone(), needed)
    e.dstack.remove(e.dstack.length() - 1)
    e.memo[t.clone()] = c
    return ok(c)

fn run_goals(var e: Env, tgs: List[String]) Unit!Fatal:
    var goals = List[String]()
    for g in tgs:
        goals.append(g.clone())

    if goals.is_empty():
        if g := default_goal(e):
            goals.append(g)
        else:
            return error(make_fatal("No targets"))

    for g in goals:
        before := e.ran
        _c := try update(var e, g.clone(), "")

        if e.ran == before:
            r := resolve(e, g.clone())

            if (
                (r.has and not r.recipe.is_empty())
                or (not e.phony.contains(g) and e.files.contains(g))
            ):
                emit(var e, "make: '{g}' is up to date.")
            else:
                emit(var e, "make: Nothing to be done for '{g}'.")


fn deps_visit(var e: Env, name: String) Unit!Fatal:
    r := resolve(e, name.clone())
    var pre = dedupe(r.normal)
    for p in dedupe(r.oo):
        pre.append(p.clone())

    for p in pre:
        if e.dstack.contains(p): return error(circ(e.dstack, p))
        if e.dseen.contains(p): continue

        e.dstack.append(p.clone())
        try deps_visit(var e, p.clone())
        e.dstack.remove(e.dstack.length() - 1)
        e.dseen.append(p.clone())
        e.dres.append(p.clone())


fn fmt_rule(name: String, normal: List[String], oo: List[String]) String:
    var s = name + ":"
    if not normal.is_empty():
        s += " " + normal.join(" ")
    if not oo.is_empty():
        s += " | " + oo.join(" ")
    return s

// ---------- requests ----------

fn handle(var e: Env, raw: String) Unit!Fatal:
    ws := raw.fields()
    cmd := ws[0].clone()

    if cmd == "build" or cmd == "dry" or cmd == "deps" or cmd == "targets":
        var clis = List[String]()
        var tgs = List[String]()
        var k = 1

        while k < ws.length():
            w := ws[k].clone()

            if cfind(w.chars(), "=", 0) > 0:
                clis.append(w)
            else:
                tgs.append(w)

            k += 1

        if cmd == "deps" and tgs.length() != 1:
            emit(var e, "usage: deps TARGET")
            return ok(unit)

        e.dry = cmd == "dry"
        e.memo = Map[String, Bool]()
        e.dstack = List[String]()
        e.dseen = List[String]()
        e.dres = List[String]()
        e.ran = 0
        e.line = 0
        try parse(var e, clis)

        if cmd == "build" or cmd == "dry":
            try run_goals(var e, tgs)
        else if cmd == "deps":
            e.dstack.append(tgs[0].clone())
            try deps_visit(var e, tgs[0].clone())

            if e.dres.is_empty():
                emit(var e, "(no prerequisites)")
            else:
                for x in e.dres.clone():
                    emit(var e, x.clone())
        else:
            if g := default_goal(e):
                emit(var e, "default: {g}")

            for t in e.order.clone():
                r := e.explicit[t].clone()
                emit(var e, fmt_rule(t.clone(), r.normal, r.oo))

            for pr in e.prules.clone():
                emit(var e, "pattern " + fmt_rule(pr.pat.clone(), pr.normal, pr.oo))
            if not e.phony.is_empty():
                emit(var e, "phony: " + e.phony.join(" "))

        return ok(unit)

    if cmd == "expand":
        rest := raw.trim().drop(6).trim()
        e.dry = false
        e.memo = Map[String, Bool]()
        e.dstack = List[String]()
        e.mute = true
        try parse(var e, List[String]())
        e.mute = false
        e.line = 0

        v := try expand(var e, rest)
        emit(var e, "[" + v + "]")
        return ok(unit)

    if cmd == "files":
        var ks = e.files.keys()
        ks.sort()
        if ks.is_empty():
            emit(var e, "(no files)")

        for k in ks:
            mt := e.files[k]
            emit(var e, "{k} {mt}")

        return ok(unit)

    if cmd == "touch":
        if ws.length() == 2:
            e.clock += 1
            e.files[ws[1].clone()] = e.clock
        else if ws.length() == 3:
            if n := ws[2].parse_int():
                e.files[ws[1].clone()] = n
                if n > e.clock:
                    e.clock = n
            else:
                emit(var e, "bad request")
        else:
            emit(var e, "bad request")

        return ok(unit)

    if cmd == "rm":
        var k = 1

        while k < ws.length():
            e.files.remove(ws[k].clone())
            k += 1

        return ok(unit)

    emit(var e, "unknown request: " + cmd)

export fn main() Int:
    b := read_all(stdin()).get()
    text := b.decode_utf8().get("")
    all := text.lines()
    n := all.length()
    var s1 = -1
    var s2 = -1

    for i in 0..n:
        if all[i] == "====":
            if s1 < 0:
                s1 = i
            else:
                s2 = i
                break

    var mk = List[String]()
    var ftab = List[String]()
    var reqs = List[String]()

    if s1 < 0:
        mk = sub_list(all, 0, n)
    else if s2 < 0:
        mk = sub_list(all, 0, s1)
        ftab = sub_list(all, s1 + 1, n)
    else:
        mk = sub_list(all, 0, s1)
        ftab = sub_list(all, s1 + 1, s2)
        reqs = sub_list(all, s2 + 1, n)

    var e = Env(
        mk: mk, vars: Map[String, Var](), cli: List[String](), out: List[String](),
        mute: false, line: 0, rstack: List[String](), explicit: Map[String, Rule](),
        order: List[String](), prules: List[PRule](), phony: List[String](),
        frames: List[Frame](), has_pend: false, pend_targets: List[String](),
        pend_normal: List[String](), pend_oo: List[String](),
        pend_recipe: List[RLine](), pend_line: 0, pend_phony: false,
        files: Map[String, Int](), clock: 0, memo: Map[String, Bool](),
        dstack: List[String](), ran: 0, dry: false, dseen: List[String](),
        dres: List[String]()
    )

    for line in ftab:
        f := line.fields()

        if f.length() == 2:
            if m := f[1].parse_int():
                e.files[f[0].clone()] = m
                if m > e.clock:
                    e.clock = m

    for req in reqs:
        if req.trim() == "" or req.trim_start().starts_with("#"): continue

        e.out.append("> " + req.trim_end())
        e.mute = false

        r := handle(var e, req.clone())
        if r.is_error():
            e.out.append(r.err().text.clone())

    var outs = ""
    for line in e.out:
        outs += line + "\n"
    stdout().write(outs).get()
    return 0
