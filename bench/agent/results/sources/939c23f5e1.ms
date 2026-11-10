import (
    stdin, stdout from "@std/io/io.ms",
    lines, collect from "@std/io/streams.ms",
)

// ---------- types ----------

type Fail:
    msg: String

type RLine:
    line: Int
    text: String

type MRule:
    name: String
    prereqs: List[String]
    oprereqs: List[String]
    recipe: List[RLine]

type PRule:
    pat: String
    prereqs: List[String]
    oprereqs: List[String]
    recipe: List[RLine]

type VarDef:
    value: String
    simple: Bool

type Frame:
    parent: Bool
    cond: Bool
    elsed: Bool
    line: Int

type Bind:
    name: String
    value: String

type LLine:
    num: Int
    text: String

type Res:
    found: Bool
    prereqs: List[String]
    oprereqs: List[String]
    recipe: List[RLine]
    stem: String
    hasRecipe: Bool

type St:
    mk: List[String]
    vars: Map[String, VarDef]
    cmd: Map[String, String]
    files: Map[String, Int]
    clock: Int
    out: List[String]
    line: Int
    autos: Map[String, String]
    binds: List[Bind]
    stack: List[String]
    rules: List[MRule]
    ridx: Map[String, Int]
    pats: List[PRule]
    phony: List[String]
    frames: List[Frame]
    rOpen: Bool
    rSink: Bool
    rTargets: List[String]
    rPre: List[String]
    rOpre: List[String]
    rRecipe: List[RLine]
    rLine: Int
    memo: Map[String, Bool]
    bstack: List[String]
    dry: Bool
    runs: Int
    dstack: List[String]
    ddone: List[String]
    dres: List[String]

// ---------- small helpers ----------

fn isWsChar(c: String) Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

fn catRange(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var k = a

    while k < b:
        s += cs[k]
        k += 1

    return s

fn trimSp(s: String) String:
    return s.trim_chars(" \t")

fn rtrimSp(s: String) String:
    let cs = s.chars()
    var n = cs.length()
    while n > 0 and (cs[n - 1] == " " or cs[n - 1] == "\t"):
        n -= 1
    return catRange(cs, 0, n)

fn ltrimSp(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var a = 0
    while a < n and (cs[a] == " " or cs[a] == "\t"):
        a += 1
    return catRange(cs, a, n)

fn ltabs(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var a = 0
    while a < n and cs[a] == "\t":
        a += 1
    return catRange(cs, a, n)

fn wordsOf(s: String) List[String]:
    var res = List[String]()
    var cur = ""
    var has = false

    for c in s.chars():
        if isWsChar(c):
            if has:
                res.append(cur.clone())
                cur = ""
                has = false
        else:
            cur += c
            has = true

    if has:
        res.append(cur)
    return res

fn dedup(xs: List[String]) List[String]:
    var res = List[String]()
    for x in xs:
        if not res.contains(x):
            res.append(x.clone())
    return res

fn indexOfStr(xs: List[String], t: String) Int:
    var k = 0

    while k < xs.length():
        if xs[k] == t: return k

        k += 1

    return -1

fn joinSep(a: String, b: String) String:
    if a == "": return b.clone()
    if b == "": return a.clone()

    return a + " " + b

fn mkFail(msg: String) Fail:
    return Fail(msg: "make: *** {msg}.  Stop.")

fn lfail(line: Int, msg: String) Fail:
    if line > 0: return Fail(msg: "Makefile:{line}: *** {msg}.  Stop.")

    return Fail(msg: "make: *** {msg}.  Stop.")

// Index of the matching closer for the opener at `open`, or -1.
fn findClose(cs: List[String], open: Int) Int:
    let o = cs[open].clone()
    var c = ")"
    if o == "\{":
        c = "\}"

    var depth = 0
    var k = open
    let n = cs.length()

    while k < n:
        if cs[k] == o:
            depth += 1
        else if cs[k] == c:
            depth -= 1
            if depth == 0: return k

        k += 1

    return -1

// First index >= from of `target` at bracket depth 0, or -1.
fn findTop(cs: List[String], target: String, from: Int) Int:
    var depth = 0
    var k = from
    let n = cs.length()

    while k < n:
        let c = cs[k]
        if depth == 0 and c == target: return k

        if c == "(" or c == "\{":
            depth += 1
        else if (c == ")" or c == "\}") and depth > 0:
            depth -= 1

        k += 1

    return -1

// First top-level ':' outside $(...) / ${...} and before any ';', or -1.
fn findColon(cs: List[String]) Int:
    let n = cs.length()
    var k = 0

    while k < n:
        let c = cs[k]
        if c == ";": return -1

        if c == "$" and k + 1 < n and (cs[k + 1] == "(" or cs[k + 1] == "\{"):
            let close = findClose(cs, k + 1)
            if close < 0: return -1

            k = close + 1
        else if c == ":":
            return k
        else:
            k += 1

    return -1

// Splits at top-level commas (parentheses and braces count as nesting).
fn splitArgs(s: String) List[String]:
    var res = List[String]()
    var cur = ""
    var depth = 0

    for c in s.chars():
        if c == "(" or c == "\{":
            depth += 1
            cur += c
        else if (c == ")" or c == "\}") and depth > 0:
            depth -= 1
            cur += c
        else if c == "," and depth == 0:
            res.append(cur.clone())
            cur = ""
        else:
            cur += c

    res.append(cur)
    return res

fn argAt(raw: List[String], k: Int) String:
    if k < raw.length(): return trimSp(raw[k])

    return ""

// ---------- pattern helpers ----------

fn patMatch(pat: String, w: String) Bool:
    let pc = pat.chars()
    let p = indexOfStr(pc, "%")
    if p < 0: return pat == w

    let pre = catRange(pc, 0, p)
    let suf = catRange(pc, p + 1, pc.length())
    if w.length() < pre.length() + suf.length(): return false

    return w.starts_with(pre) and w.ends_with(suf)

// Stem of a matching word (only meaningful when patMatch holds).
fn stemOf(pat: String, w: String) String:
    let pc = pat.chars()
    let p = indexOfStr(pc, "%")
    if p < 0: return ""

    let pre = catRange(pc, 0, p)
    let suf = catRange(pc, p + 1, pc.length())
    return w.slice(pre.length(), w.length() - suf.length()).get()

// Replaces the first % of r with stem.
fn subPct(r: String, stem: String) String:
    let rc = r.chars()
    let p = indexOfStr(rc, "%")
    if p < 0: return r.clone()

    return catRange(rc, 0, p) + stem + catRange(rc, p + 1, rc.length())

// Replacement for patsubst: only substitutes when the pattern has a %.
fn patRepl(pat: String, repl: String, stem: String) String:
    if pat.contains("%"): return subPct(repl, stem)

    return repl.clone()

fn gm(pc: List[String], pi: Int, sc: List[String], si: Int) Bool:
    let pn = pc.length()
    let sn = sc.length()
    if pi == pn: return si == sn

    let c = pc[pi].clone()

    if c == "*":
        var k = si

        while k <= sn:
            if gm(pc, pi + 1, sc, k): return true
            if k < sn and sc[k] == "/": return false

            k += 1

        return false

    if si >= sn: return false

    if c == "?":
        if sc[si] == "/": return false

        return gm(pc, pi + 1, sc, si + 1)

    if sc[si] != c: return false

    return gm(pc, pi + 1, sc, si + 1)

fn globMatch(p: String, s: String) Bool:
    return gm(p.chars(), 0, s.chars(), 0)

fn isFunc(n: String) Bool:
    let names = [
        "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort",
        "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix",
        "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info",
        "error"
    ]
    return names.contains(n)

fn substRef(v: String, fromT: String, toT: String) String:
    var f = fromT.clone()
    var t = toT.clone()

    if not f.contains("%"):
        f = "%" + fromT
        t = "%" + toT

    var res = List[String]()

    for w in wordsOf(v):
        if patMatch(f, w):
            res.append(subPct(t, stemOf(f, w)))
        else:
            res.append(w)

    return res.join(" ")

fn unaryWord(name: String, w: String) String:
    let cs = w.chars()
    let n = cs.length()
    var slash = -1
    var k = 0

    while k < n:
        if cs[k] == "/":
            slash = k
        k += 1

    let base = catRange(cs, slash + 1, n)

    if name == "dir":
        if slash < 0: return "./"

        return catRange(cs, 0, slash + 1)

    if name == "notdir": return base.clone()

    let bc = base.chars()
    var dot = -1
    var j = 0

    while j < bc.length():
        if bc[j] == ".":
            dot = j
        j += 1

    if name == "suffix":
        if dot < 0: return ""

        return catRange(bc, dot, bc.length())

    if dot < 0: return w.clone()

    return catRange(cs, 0, n - (bc.length() - dot))

// ---------- expansion ----------

fn isSimpleVar(st: St, name: String) Bool:
    if let d = st.vars.get(name): return d.simple

    return false

fn rawVar(st: St, name: String) String:
    if let d = st.vars.get(name): return d.value.clone()

    return ""

fn isDefined(st: St, name: String) Bool:
    if st.cmd.contains(name): return st.cmd.get(name).get("") != ""
    if st.vars.contains(name): return rawVar(st, name) != ""

    return false

fn recur(var st: St, name: String, value: String) String!Fail:
    if st.stack.contains(name):
        return error(
            lfail(
                st.line, "Recursive variable '{name}' references itself (eventually)"
            )
        )

    st.stack.append(name.clone())

    let r = try expand(var st, value)
    let _p = st.stack.pop()
    return ok(r)

fn lookup(var st: St, name: String) String!Fail:
    var k = st.binds.length() - 1

    while k >= 0:
        if st.binds[k].name == name: return ok(st.binds[k].value.clone())

        k -= 1

    if st.autos.contains(name): return ok(st.autos.get(name).get(""))

    if st.cmd.contains(name):
        let cv = st.cmd.get(name).get("")
        return recur(var st, name, cv)

    if st.vars.contains(name):
        let simple = isSimpleVar(st, name)
        let raw = rawVar(st, name)
        if simple: return ok(raw)

        return recur(var st, name, raw)

    return ok("")

fn refText(var st: St, inner: String) String!Fail:
    let cs = inner.chars()
    let n = cs.length()
    var k = 0
    while k < n and cs[k] != " " and cs[k] != "\t":
        k += 1
    if k > 0 and k < n and isFunc(catRange(cs, 0, k)):
        return callFn(var st, catRange(cs, 0, k), catRange(cs, k + 1, n))

    let p = findTop(cs, ":", 1)

    if p > 0:
        let q = findTop(cs, "=", p + 1)

        if q > 0:
            let nameRaw = try expand(var st, catRange(cs, 0, p))
            let fromRaw = try expand(var st, catRange(cs, p + 1, q))
            let toRaw = try expand(var st, catRange(cs, q + 1, n))
            let vname = trimSp(nameRaw)
            let v = try lookup(var st, vname)
            return ok(substRef(v, fromRaw, toRaw))

    let nm = try expand(var st, inner)
    let v2 = try lookup(var st, trimSp(nm))
    return ok(v2)

fn callFn(var st: St, name: String, argtext: String) String!Fail:
    if name == "info":
        let s = try expand(var st, trimSp(argtext))
        st.out.append(s.clone())
        return ok("")

    if name == "error":
        let s = try expand(var st, trimSp(argtext))
        return error(lfail(st.line, s))

    let raw = splitArgs(argtext)

    if name == "subst":
        let f = try expand(var st, argAt(raw, 0))
        let t = try expand(var st, argAt(raw, 1))
        let x = try expand(var st, argAt(raw, 2))
        if f == "": return ok(x)

        return ok(x.replace(f, t))

    if name == "patsubst":
        let p = try expand(var st, argAt(raw, 0))
        let r = try expand(var st, argAt(raw, 1))
        let x = try expand(var st, argAt(raw, 2))
        var res = List[String]()

        for w in wordsOf(x):
            if patMatch(p, w):
                res.append(patRepl(p, r, stemOf(p, w)))
            else:
                res.append(w)

        return ok(res.join(" "))

    if name == "strip":
        let x = try expand(var st, argAt(raw, 0))
        return ok(wordsOf(x).join(" "))

    if name == "findstring":
        let f = try expand(var st, argAt(raw, 0))
        let x = try expand(var st, argAt(raw, 1))
        if x.contains(f): return ok(f)

        return ok("")

    if name == "filter" or name == "filter-out":
        let px = try expand(var st, argAt(raw, 0))
        let x = try expand(var st, argAt(raw, 1))
        let ps = wordsOf(px)
        var res = List[String]()

        for w in wordsOf(x):
            var hit = false
            for p in ps:
                if patMatch(p, w):
                    hit = true
            if hit == (name == "filter"):
                res.append(w)

        return ok(res.join(" "))

    if name == "sort":
        let x = try expand(var st, argAt(raw, 0))
        var ws = wordsOf(x)
        ws.sort()

        var res = List[String]()
        for w in ws:
            if res.length() == 0 or res[res.length() - 1] != w:
                res.append(w.clone())
        return ok(res.join(" "))

    if name == "word":
        let nt = try expand(var st, argAt(raw, 0))
        let xt = try expand(var st, argAt(raw, 1))
        let ws = wordsOf(xt)
        if let k = trimSp(nt).parse_int():
            if k >= 1 and k <= ws.length(): return ok(ws[k - 1].clone())
        return ok("")

    if name == "wordlist":
        let at = try expand(var st, argAt(raw, 0))
        let bt = try expand(var st, argAt(raw, 1))
        let xt = try expand(var st, argAt(raw, 2))
        let ws = wordsOf(xt)
        let n = ws.length()

        if let s0 = trimSp(at).parse_int():
            if let e0 = trimSp(bt).parse_int():
                if s0 >= 1 and e0 >= s0 and s0 <= n:
                    var e = e0
                    if e > n:
                        e = n

                    var res = List[String]()
                    var k = s0 - 1

                    while k < e:
                        res.append(ws[k].clone())
                        k += 1

                    return ok(res.join(" "))

        return ok("")

    if name == "words":
        let x = try expand(var st, argAt(raw, 0))
        let c = wordsOf(x).length()
        return ok("{c}")

    if name == "firstword" or name == "lastword":
        let x = try expand(var st, argAt(raw, 0))
        let ws = wordsOf(x)
        if ws.length() == 0: return ok("")
        if name == "firstword": return ok(ws[0].clone())

        return ok(ws[ws.length() - 1].clone())

    if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
        let x = try expand(var st, argAt(raw, 0))
        var res = List[String]()

        for w in wordsOf(x):
            let r = unaryWord(name, w)
            if r != "":
                res.append(r)

        return ok(res.join(" "))

    if name == "addprefix" or name == "addsuffix":
        let p = try expand(var st, argAt(raw, 0))
        let x = try expand(var st, argAt(raw, 1))
        var res = List[String]()

        for w in wordsOf(x):
            if name == "addprefix":
                res.append(p.clone() + w)
            else:
                res.append(w + p.clone())

        return ok(res.join(" "))

    if name == "wildcard":
        let px = try expand(var st, argAt(raw, 0))
        var keys = st.files.keys()
        keys.sort()

        var res = List[String]()
        for p in wordsOf(px):
            for k in keys:
                if globMatch(p, k):
                    res.append(k.clone())
        return ok(res.join(" "))

    if name == "foreach":
        let vraw = try expand(var st, argAt(raw, 0))
        let vn = trimSp(vraw)
        let lraw = try expand(var st, argAt(raw, 1))
        let tmpl = argAt(raw, 2)
        var res = List[String]()

        for w in wordsOf(lraw):
            st.binds.append(Bind(name: vn.clone(), value: w.clone()))

            let r = try expand(var st, tmpl)
            let _b = st.binds.pop()
            res.append(r)

        return ok(res.join(" "))

    if name == "if":
        let c = try expand(var st, argAt(raw, 0))
        if trimSp(c) != "": return expand(var st, argAt(raw, 1))

        return expand(var st, argAt(raw, 2))

    return ok("")

fn expand(var st: St, text: String) String!Fail:
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
            let close = findClose(cs, i + 1)
            if close < 0:
                return error(lfail(st.line, "unterminated variable reference"))

            let v = try refText(var st, catRange(cs, i + 2, close))
            out += v
            i = close + 1
        else:
            let v = try lookup(var st, cs[i + 1].clone())
            out += v
            i += 2

    return ok(out)

// ---------- Makefile parsing ----------

fn stripComment(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var out = ""
    var k = 0

    while k < n:
        if cs[k] == "\\" and k + 1 < n and cs[k + 1] == "#":
            out += "#"
            k += 2
        else if cs[k] == "#":
            return out
        else:
            out += cs[k]
            k += 1

    return out

fn logicals(mk: List[String]) List[LLine]:
    var res = List[LLine]()
    let n = mk.length()
    var i = 0

    while i < n:
        let start = i
        var cur = mk[i].clone()

        while cur.ends_with("\\") and i + 1 < n:
            let cc = cur.chars()
            let base = rtrimSp(catRange(cc, 0, cc.length() - 1))
            i += 1
            cur = base + " " + ltrimSp(mk[i])

        res.append(LLine(num: start + 1, text: cur.clone()))
        i += 1

    return res

fn activeNow(st: St) Bool:
    let n = st.frames.length()
    if n == 0: return true

    let f = st.frames[n - 1]
    if f.elsed: return f.parent and not f.cond

    return f.parent and f.cond

fn closeRule(var st: St) Unit:
    if not st.rOpen: return unit

    st.rOpen = false
    if st.rSink: return unit

    let hasRec = st.rRecipe.length() > 0
    let targets = st.rTargets.clone()

    for t in targets:
        if t.contains("%"):
            st.pats.append(
                PRule(
                    pat: t.clone(), prereqs: st.rPre.clone(),
                    oprereqs: st.rOpre.clone(), recipe: st.rRecipe.clone()
                )
            )
        else:
            if not st.ridx.contains(t):
                st.rules.append(
                    MRule(
                        name: t.clone(), prereqs: List[String](),
                        oprereqs: List[String](), recipe: List[RLine]()
                    )
                )
                st.ridx.add(t.clone(), st.rules.length() - 1)

            let k = st.ridx.get(t).get(0)
            let pres = st.rPre.clone()
            for p in pres:
                st.rules[k].prereqs.append(p.clone())

            let opres = st.rOpre.clone()
            for p in opres:
                st.rules[k].oprereqs.append(p.clone())

            if hasRec:
                if st.rules[k].recipe.length() > 0:
                    (
                        st
                        .out
                        .append(
                            "Makefile:{st.rLine}: warning: overriding recipe for target '{t}'"
                        )
                    )
                st.rules[k].recipe = st.rRecipe.clone()

    return unit

fn ruleLine(var st: St, cs: List[String], col: Int, num: Int) Unit!Fail:
    let n = cs.length()
    var semi = -1
    var k = col + 1

    while k < n:
        if cs[k] == ";":
            semi = k
            break

        k += 1

    var preEnd = n
    if semi >= 0:
        preEnd = semi

    let tgtRaw = catRange(cs, 0, col)
    let preRaw = catRange(cs, col + 1, preEnd)
    let tv = try expand(var st, tgtRaw)
    let pv = try expand(var st, preRaw)
    let pc = pv.chars()
    let bar = indexOfStr(pc, "|")
    var normal = pv.clone()
    var order = ""

    if bar >= 0:
        normal = catRange(pc, 0, bar)
        order = catRange(pc, bar + 1, pc.length())

    st.rOpen = true
    st.rTargets = wordsOf(tv)
    st.rPre = wordsOf(normal)
    st.rOpre = wordsOf(order)
    st.rRecipe = List[RLine]()
    st.rLine = num
    st.rSink = st.rTargets.length() == 1 and st.rTargets[0] == ".PHONY"
    if st.rSink:
        for p in st.rPre:
            if not st.phony.contains(p):
                st.phony.append(p.clone())

    if semi >= 0:
        let c = trimSp(catRange(cs, semi + 1, n))
        if c != "":
            st.rRecipe.append(RLine(line: num, text: c))

    return ok(unit)

fn assignLine(var st: St, cs: List[String], eq: Int, num: Int) Unit!Fail:
    var nameEnd = eq
    var op = "="

    if eq >= 1 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
        nameEnd = eq - 1
        op = cs[eq - 1].clone() + "="

    let nv = try expand(var st, catRange(cs, 0, nameEnd))
    let name = trimSp(nv)
    if name == "": return error(lfail(num, "empty variable name"))

    let value = trimSp(catRange(cs, eq + 1, cs.length()))
    if st.cmd.contains(name): return ok(unit)

    if op == "=":
        st.vars.add(name.clone(), VarDef(value: value, simple: false))
    else if op == ":=":
        let ev = try expand(var st, value)
        st.vars.add(name.clone(), VarDef(value: ev, simple: true))
    else if op == "?=":
        if not st.vars.contains(name):
            st.vars.add(name.clone(), VarDef(value: value, simple: false))
    else:
        if not st.vars.contains(name):
            st.vars.add(name.clone(), VarDef(value: value, simple: false))
        else:
            let oldSimple = isSimpleVar(st, name)
            let oldVal = rawVar(st, name)

            if oldSimple:
                let add = try expand(var st, value)
                st.vars.add(
                    name.clone(),
                    VarDef(
                        value: joinSep(oldVal, add), simple: true
                    )
                )
            else:
                st.vars.add(
                    name.clone(),
                    VarDef(
                        value: joinSep(oldVal, value), simple: false
                    )
                )

    return ok(unit)

fn directive(var st: St, word: String, text: String, rest: String, num: Int) Unit!Fail:
    if text == "else":
        let n = st.frames.length()
        if n == 0 or st.frames[n - 1].elsed:
            return error(lfail(num, "extraneous 'else'"))

        st.frames[n - 1].elsed = true
        return ok(unit)

    if word == "endif":
        if st.frames.length() == 0: return error(lfail(num, "extraneous 'endif'"))

        let _f = st.frames.pop()
        return ok(unit)

    let parent = activeNow(st)
    var cond = false

    if word == "ifdef" or word == "ifndef":
        if parent:
            let nt = try expand(var st, rest)
            let d = isDefined(st, trimSp(nt))

            if word == "ifdef":
                cond = d
            else:
                cond = not d
    else:
        if parent:
            let rc = rest.chars()
            let m = rc.length()
            if m < 2 or rc[0] != "(" or rc[m - 1] != ")":
                return error(lfail(num, "invalid syntax in conditional"))

            let parts = splitArgs(catRange(rc, 1, m - 1))
            if parts.length() != 2:
                return error(lfail(num, "invalid syntax in conditional"))

            let a0 = try expand(var st, trimSp(parts[0]))
            let b0 = try expand(var st, trimSp(parts[1]))
            let same = trimSp(a0) == trimSp(b0)

            if word == "ifeq":
                cond = same
            else:
                cond = not same

    st.frames.append(Frame(parent: parent, cond: cond, elsed: false, line: num))
    return ok(unit)

fn processLine(var st: St, num: Int, raw: String) Unit!Fail:
    st.line = num

    if raw.starts_with("\t"):
        let body = ltabs(raw)
        if trimSp(body) == "": return ok(unit)
        if not activeNow(st): return ok(unit)
        if not st.rOpen:
            return error(lfail(num, "recipe commences before first target"))

        st.rRecipe.append(RLine(line: num, text: body))
        return ok(unit)

    let text = trimSp(stripComment(raw))
    if text == "": return ok(unit)

    let cs = text.chars()
    let n = cs.length()
    var fw = 0
    while fw < n and cs[fw] != " " and cs[fw] != "\t" and cs[fw] != "(":
        fw += 1

    let word = catRange(cs, 0, fw)
    let rest = trimSp(catRange(cs, fw, n))
    let isDir = (
        text == "else"
        or word == "endif"
        or word == "ifdef"
        or word == "ifndef"
        or word == "ifeq"
        or word == "ifneq"
    )

    if isDir:
        closeRule(var st)
        return directive(var st, word, text, rest, num)

    if not activeNow(st): return ok(unit)

    closeRule(var st)

    let eq = indexOfStr(cs, "=")
    let col = findColon(cs)
    if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
        return assignLine(var st, cs, eq, num)
    if col >= 0: return ruleLine(var st, cs, col, num)

    let v = try expand(var st, text)
    if trimSp(v) != "": return error(lfail(num, "missing separator"))

    return ok(unit)

fn loadMake(var st: St) Unit!Fail:
    st.vars = Map[String, VarDef]()
    st.rules = List[MRule]()
    st.ridx = Map[String, Int]()
    st.pats = List[PRule]()
    st.phony = List[String]()
    st.frames = List[Frame]()
    st.rOpen = false
    st.rSink = false
    st.rTargets = List[String]()
    st.rPre = List[String]()
    st.rOpre = List[String]()
    st.rRecipe = List[RLine]()
    st.autos = Map[String, String]()
    st.binds = List[Bind]()
    st.stack = List[String]()
    st.line = 0

    let ls = logicals(st.mk)
    for ll in ls:
        try processLine(var st, ll.num, ll.text.clone())
    closeRule(var st)
    st.line = 0

    if st.frames.length() > 0:
        let top = st.frames[st.frames.length() - 1].line
        return error(lfail(top, "missing 'endif'"))

    return ok(unit)

// ---------- resolution ----------

fn canMake(st: St, name: String, level: Int) Bool:
    if st.files.contains(name) or st.ridx.contains(name) or st.phony.contains(name):
        return true
    if level > 8: return false

    for pr in st.pats:
        if pr.recipe.length() > 0 and patMatch(pr.pat, name):
            let stem = stemOf(pr.pat, name)
            if stem != "" and allMake(st, pr.prereqs, pr.oprereqs, stem, level + 1):
                return true

    return false

fn allMake(st: St, prs: List[String], oprs: List[String], stem: String, level: Int) Bool:
    for p in prs:
        if not canMake(st, subPct(p, stem), level): return false
    for p in oprs:
        if not canMake(st, subPct(p, stem), level): return false
    return true

fn resolveRule(st: St, t: String) Res:
    if st.ridx.contains(t):
        let k = st.ridx.get(t).get(0)
        if st.rules[k].recipe.length() > 0:
            return Res(
                found: true, prereqs: st.rules[k].prereqs.clone(),
                oprereqs: st.rules[k].oprereqs.clone(),
                recipe: st.rules[k].recipe.clone(), stem: "", hasRecipe: true
            )

    for pr in st.pats:
        if pr.recipe.length() > 0 and patMatch(pr.pat, t):
            let stem = stemOf(pr.pat, t)

            if stem != "" and allMake(st, pr.prereqs, pr.oprereqs, stem, 1):
                var pre = List[String]()
                var opre = List[String]()
                for p in pr.prereqs:
                    pre.append(subPct(p, stem))
                for p in pr.oprereqs:
                    opre.append(subPct(p, stem))

                if st.ridx.contains(t):
                    let k = st.ridx.get(t).get(0)
                    for p in st.rules[k].prereqs:
                        pre.append(p.clone())
                    for p in st.rules[k].oprereqs:
                        opre.append(p.clone())

                return Res(
                    found: true, prereqs: pre, oprereqs: opre,
                    recipe: pr.recipe.clone(), stem: stem, hasRecipe: true
                )

    if st.ridx.contains(t):
        let k = st.ridx.get(t).get(0)
        return Res(
            found: true, prereqs: st.rules[k].prereqs.clone(),
            oprereqs: st.rules[k].oprereqs.clone(), recipe: List[RLine](), stem: "",
            hasRecipe: false
        )

    return Res(
        found: false, prereqs: List[String](), oprereqs: List[String](),
        recipe: List[RLine](), stem: "", hasRecipe: false
    )

fn defaultGoal(st: St) String:
    for m in st.rules:
        if not m.name.starts_with("."): return m.name.clone()
    return ""

// ---------- building ----------

// Simulates a command; prints any output and returns its status.
fn simulate(var st: St, cmd: String) Int:
    let ws = wordsOf(cmd)
    let n = ws.length()
    if n == 0: return 0

    let name = ws[0].clone()
    if name == "false": return 1

    if name == "exit":
        if n >= 2:
            if let v = ws[1].parse_int(): return v

            return 2

        return 0

    if name == "touch":
        var j = 1

        while j < n:
            if not ws[j].starts_with("-"):
                st.clock += 1
                st.files.add(ws[j].clone(), st.clock)

            j += 1

        return 0

    if name == "rm":
        var j = 1

        while j < n:
            if not ws[j].starts_with("-"):
                st.files.remove(ws[j].clone())
            j += 1

        return 0

    if name == "cp":
        if n == 3:
            if not st.files.contains(ws[1]):
                st.out.append("cp: cannot stat '{ws[1]}': No such file or directory")
                return 1

            st.clock += 1
            st.files.add(ws[2].clone(), st.clock)

        return 0

    if name == "echo":
        var args = List[String]()
        var j = 1

        while j < n:
            args.append(ws[j].replace("'", "").replace("\"", ""))
            j += 1

        st.out.append(args.join(" "))
        return 0

    return 0

fn runRecipe(var st: St, t: String, r: Res, pre: List[String], qlist: List[String]) Unit!Fail:
    var au = Map[String, String]()
    au.add("@", t.clone())

    var firstP = ""
    if r.prereqs.length() > 0:
        firstP = r.prereqs[0].clone()
    au.add("<", firstP)
    au.add("^", pre.join(" "))
    au.add("?", qlist.join(" "))
    au.add("|", dedup(r.oprereqs).join(" "))
    au.add("*", r.stem.clone())
    st.autos = au
    st.runs += 1

    for rl in r.recipe:
        st.line = rl.line

        let raw = try expand(var st, rl.text.clone())
        let cs = trimSp(raw).chars()
        let n = cs.length()
        var silent = false
        var ign = false
        var k = 0

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

        let cmd = trimSp(catRange(cs, k, n))
        if cmd == "": continue

        if st.dry:
            st.out.append(cmd.clone())
        else:
            if not silent:
                st.out.append(cmd.clone())

            let status = simulate(var st, cmd.clone())

            if status != 0:
                if ign:
                    (
                        st
                        .out
                        .append(
                            "make: [Makefile:{rl.line}: {t}] Error {status} (ignored)"
                        )
                    )
                else:
                    return error(
                        Fail(
                            msg: "make: *** [Makefile:{rl.line}: {t}] Error {status}"
                        )
                    )

    st.line = 0
    st.autos = Map[String, String]()

    if not st.dry and not st.phony.contains(t):
        st.clock += 1
        st.files.add(t.clone(), st.clock)

    return ok(unit)

fn bupdate(var st: St, t: String, needed: String) Bool!Fail:
    if st.memo.contains(t): return ok(st.memo.get(t).get(false))

    if st.bstack.contains(t):
        let k = indexOfStr(st.bstack, t)
        var parts = List[String]()
        var j = k

        while j < st.bstack.length():
            parts.append(st.bstack[j].clone())
            j += 1

        parts.append(t.clone())
        return error(mkFail("Circular dependency detected: " + parts.join(" -> ")))

    let r = resolveRule(st, t)

    if not r.found:
        if st.files.contains(t):
            st.memo.add(t.clone(), false)
            return ok(false)

        if st.phony.contains(t):
            st.memo.add(t.clone(), true)
            return ok(true)

        if needed == "": return error(mkFail("No rule to make target '{t}'"))

        return error(mkFail("No rule to make target '{t}', needed by '{needed}'"))

    st.bstack.append(t.clone())

    let existed = st.files.contains(t)
    var oldm = 0
    if existed:
        oldm = st.files.get(t).get(0)

    var changed = false
    var newer = false
    var qlist = List[String]()
    let pre = dedup(r.prereqs)

    for p in pre:
        let c = try bupdate(var st, p.clone(), t.clone())
        let pe = st.files.contains(p)
        var pm = 0
        if pe:
            pm = st.files.get(p).get(0)

        let isNewer = existed and pe and pm > oldm
        if c:
            changed = true
        if (not existed) or c or isNewer:
            qlist.append(p.clone())
        if isNewer:
            newer = true

    let opre = dedup(r.oprereqs)
    for p in opre:
        let _c2 = try bupdate(var st, p.clone(), t.clone())

    let _s = st.bstack.pop()
    let must = st.phony.contains(t) or (not st.files.contains(t)) or changed or newer
    if must and r.hasRecipe:
        try runRecipe(var st, t.clone(), r, pre, qlist)
    st.memo.add(t.clone(), must)
    return ok(must)

fn doBuild(var st: St, goals: List[String], dry: Bool) Unit!Fail:
    try loadMake(var st)

    var gs = List[String]()
    for g in goals:
        gs.append(g.clone())

    if gs.length() == 0:
        let d = defaultGoal(st)
        if d == "": return error(mkFail("No targets"))

        gs.append(d)

    st.memo = Map[String, Bool]()
    st.bstack = List[String]()
    st.dry = dry

    for g in gs:
        let before = st.runs
        let _m = try bupdate(var st, g.clone(), "")

        if st.runs == before:
            let r = resolveRule(st, g)

            if r.hasRecipe or (st.files.contains(g) and not st.phony.contains(g)):
                st.out.append("make: '{g}' is up to date.")
            else:
                st.out.append("make: Nothing to be done for '{g}'.")

    return ok(unit)

// ---------- deps / targets ----------

fn depsWalk(var st: St, t: String) Unit!Fail:
    let r = resolveRule(st, t)
    var all = r.prereqs.clone()
    for p in r.oprereqs:
        all.append(p.clone())

    for p in all:
        if st.ddone.contains(p): continue

        if st.dstack.contains(p):
            let k = indexOfStr(st.dstack, p)
            var parts = List[String]()
            var j = k

            while j < st.dstack.length():
                parts.append(st.dstack[j].clone())
                j += 1

            parts.append(p.clone())
            return error(mkFail("Circular dependency detected: " + parts.join(" -> ")))

        st.dstack.append(p.clone())
        try depsWalk(var st, p.clone())

        let _d = st.dstack.pop()
        st.ddone.append(p.clone())
        st.dres.append(p.clone())

    return ok(unit)

fn depLine(name: String, pre: List[String], opre: List[String]) String:
    var s = name + ":"
    if pre.length() > 0:
        s += " " + pre.join(" ")
    if opre.length() > 0:
        s += " | " + opre.join(" ")
    return s

fn printTargets(var st: St) Unit:
    var outl = List[String]()
    let d = defaultGoal(st)
    if d != "":
        outl.append("default: " + d)
    for m in st.rules:
        outl.append(depLine(m.name, m.prereqs, m.oprereqs))
    for p in st.pats:
        outl.append("pattern " + depLine(p.pat, p.prereqs, p.oprereqs))
    if st.phony.length() > 0:
        outl.append("phony: " + st.phony.join(" "))
    for l in outl:
        st.out.append(l.clone())
    return unit

// ---------- requests ----------

// Sets command-line variables from args; returns the target words.
fn takeArgs(var st: St, args: List[String]) List[String]:
    st.cmd = Map[String, String]()

    var targets = List[String]()

    for a in args:
        let cs = a.chars()
        let eq = indexOfStr(cs, "=")

        if eq > 0:
            st.cmd.add(catRange(cs, 0, eq), catRange(cs, eq + 1, cs.length()))
        else:
            targets.append(a.clone())

    return targets

fn restAfterWord(req: String) String:
    let cs = trimSp(req).chars()
    let n = cs.length()
    var k = 0
    while k < n and cs[k] != " " and cs[k] != "\t":
        k += 1
    return trimSp(catRange(cs, k, n))

fn doRequest(var st: St, req: String) Unit!Fail:
    let parts = wordsOf(req)
    st.cmd = Map[String, String]()
    st.line = 0
    if parts.length() == 0: return ok(unit)

    let w = parts[0].clone()
    var rest = List[String]()
    var k = 1

    while k < parts.length():
        rest.append(parts[k].clone())
        k += 1

    if w == "build":
        let goals = takeArgs(var st, rest)
        return doBuild(var st, goals, false)

    if w == "dry":
        let goals = takeArgs(var st, rest)
        return doBuild(var st, goals, true)

    if w == "deps":
        let tg = takeArgs(var st, rest)

        if tg.length() != 1:
            st.out.append("usage: deps TARGET")
            return ok(unit)

        try loadMake(var st)

        let target = tg[0].clone()
        st.dstack = List[String]()
        st.dstack.append(target.clone())
        st.ddone = List[String]()
        st.dres = List[String]()
        try depsWalk(var st, target.clone())
        if st.dres.length() == 0:
            st.out.append("(no prerequisites)")
        for d in st.dres:
            st.out.append(d.clone())
        return ok(unit)

    if w == "targets":
        let _t = takeArgs(var st, rest)
        try loadMake(var st)
        printTargets(var st)
        return ok(unit)

    if w == "expand":
        let text = restAfterWord(req)
        try loadMake(var st)

        let v = try expand(var st, text)
        st.out.append("[" + v + "]")
        return ok(unit)

    if w == "files":
        var names = st.files.keys()
        names.sort()
        if names.length() == 0:
            st.out.append("(no files)")

        for nm in names:
            let mt = st.files.get(nm).get(0)
            st.out.append("{nm} {mt}")

        return ok(unit)

    if w == "touch":
        if rest.length() == 1:
            st.clock += 1
            st.files.add(rest[0].clone(), st.clock)
            return ok(unit)

        if rest.length() == 2:
            if let v = rest[1].parse_int():
                st.files.add(rest[0].clone(), v)
                if v > st.clock:
                    st.clock = v
                return ok(unit)

        st.out.append("bad request")
        return ok(unit)

    if w == "rm":
        for f in rest:
            st.files.remove(f.clone())
        return ok(unit)

    st.out.append("unknown request: " + w)
    return ok(unit)

fn handle(var st: St, req: String) Unit:
    let r = doRequest(var st, req)
    if r.is_error():
        st.out.append(r.err().msg.clone())
    return unit

export fn main() Int:
    let all = (stdin() | lines | collect(none)).get()
    var mk = List[String]()
    var table = List[String]()
    var reqs = List[String]()
    var section = 0

    for l in all:
        if section == 2:
            reqs.append(l.clone())
        else if l == "====":
            section += 1
        else if section == 0:
            mk.append(l.clone())
        else:
            table.append(l.clone())

    var st = St(
        mk: mk, vars: Map[String, VarDef](), cmd: Map[String, String](),
        files: Map[String, Int](), clock: 0, out: List[String](), line: 0,
        autos: Map[String, String](), binds: List[Bind](), stack: List[String](),
        rules: List[MRule](), ridx: Map[String, Int](), pats: List[PRule](),
        phony: List[String](), frames: List[Frame](), rOpen: false, rSink: false,
        rTargets: List[String](), rPre: List[String](), rOpre: List[String](),
        rRecipe: List[RLine](), rLine: 0, memo: Map[String, Bool](),
        bstack: List[String](), dry: false, runs: 0, dstack: List[String](),
        ddone: List[String](), dres: List[String]()
    )
    var clock = 0

    for l in table:
        let f = wordsOf(l)

        if f.length() == 2:
            if let v = f[1].parse_int():
                if v >= 0:
                    st.files.add(f[0].clone(), v)
                    if v > clock:
                        clock = v

    st.clock = clock

    for r in reqs:
        let t = trimSp(r)
        if t == "" or t.starts_with("#"): continue

        st.out.append("> " + rtrimSp(r))
        handle(var st, r.clone())

    var buf = ""
    for l in st.out:
        buf += l + "\n"
    stdout().write(buf).get()
    return 0
