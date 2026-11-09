// ms: allow_effect std.console.write
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------- types ----------

type Fail:
    text: String

type RLine:
    num: Int
    text: String

type Rule:
    name: String
    normal: List[String]
    order: List[String]
    recipe: List[RLine]

type PRule:
    pat: String
    normal: List[String]
    order: List[String]
    recipe: List[RLine]

type Bind:
    name: String
    value: String

type Frame:
    parent: Bool
    taking: Bool
    seen_else: Bool
    line: Int

type LLine:
    num: Int
    text: String

type Res:
    found: Bool
    normal: List[String]
    order: List[String]
    recipe: List[RLine]
    has_recipe: Bool
    stem: String

type St:
    clock: Int
    files: Map[String, Int]
    mk: String
    vars: Map[String, String]
    recur: Map[String, Bool]
    cli: Map[String, String]
    stack: List[String]
    binds: List[Bind]
    auto_on: Bool
    auto: Map[String, String]
    line: Int
    rules: List[Rule]
    ridx: Map[String, Int]
    prules: List[PRule]
    phony: List[String]
    has_default: Bool
    default_goal: String
    rule_open: Bool
    cur_ex: List[Int]
    cur_pat: List[Int]
    cur_rec: List[RLine]
    cur_phony: Bool
    cur_num: Int
    memo: Map[String, Bool]
    bstack: List[String]
    changed: Map[String, Bool]
    recipe_ran: Bool
    dry: Bool

fn new_state() St:
    return St(
        clock: 0, files: Map[String, Int](), mk: "", vars: Map[String, String](),
        recur: Map[String, Bool](), cli: Map[String, String](), stack: List[String](),
        binds: List[Bind](), auto_on: false, auto: Map[String, String](), line: 0,
        rules: List[Rule](), ridx: Map[String, Int](), prules: List[PRule](),
        phony: List[String](), has_default: false, default_goal: "", rule_open: false,
        cur_ex: List[Int](), cur_pat: List[Int](), cur_rec: List[RLine](),
        cur_phony: false, cur_num: 0, memo: Map[String, Bool](), bstack: List[String](),
        changed: Map[String, Bool](), recipe_ran: false, dry: false
    )

fn reset_parse(var st: St) Unit:
    st.vars = Map[String, String]()
    st.recur = Map[String, Bool]()
    st.stack = List[String]()
    st.binds = List[Bind]()
    st.auto_on = false
    st.auto = Map[String, String]()
    st.line = 0
    st.rules = List[Rule]()
    st.ridx = Map[String, Int]()
    st.prules = List[PRule]()
    st.phony = List[String]()
    st.has_default = false
    st.default_goal = ""
    st.rule_open = false
    st.cur_ex = List[Int]()
    st.cur_pat = List[Int]()
    st.cur_rec = List[RLine]()
    st.cur_phony = false
    st.cur_num = 0
    st.memo = Map[String, Bool]()
    st.bstack = List[String]()
    st.changed = Map[String, Bool]()
    st.recipe_ran = false

// ---------- small helpers ----------

fn ferr(line: Int, msg: String) Fail:
    if line > 0:
        return Fail(text: "Makefile:{line}: *** {msg}.  Stop.")

    return Fail(text: "make: *** {msg}.  Stop.")

fn join_range(cs: List[String], a: Int, b: Int) String:
    var parts = List[String]()
    var k = a

    while k < b:
        parts.append(cs[k].clone())
        k += 1

    return parts.join("")

fn argn(args: List[String], i: Int) String:
    if i < args.length():
        return args[i].clone()

    return ""

fn list_index(xs: List[String], s: String) Int:
    var k = 0

    while k < xs.length():
        if xs[k] == s:
            return k

        k += 1

    return -1

fn chain_from(xs: List[String], pos: Int, last: String) String:
    var parts = List[String]()
    var k = pos

    while k < xs.length():
        parts.append(xs[k].clone())
        k += 1

    parts.append(last.clone())
    return parts.join(" -> ")

fn dedup(xs: List[String]) List[String]:
    var out = List[String]()
    for x in xs:
        if not out.contains(x):
            out.append(x.clone())
    return out

fn last_char(w: String, ch: String, from: Int) Int:
    let cs = w.chars()
    var k = cs.length() - 1

    while k >= from and k >= 0:
        if cs[k] == ch:
            return k

        k -= 1

    return -1

fn last_slash(w: String) Int:
    return last_char(w, "/", 0)

fn pct_index(s: String) Int:
    let cs = s.chars()
    var k = 0

    while k < cs.length():
        if cs[k] == "%":
            return k

        k += 1

    return -1

// does word w match pattern pat (one % stands for any stem, possibly empty)
fn pmatch(pat: String, w: String) Bool:
    let k = pct_index(pat)
    if k < 0:
        return pat == w

    let pre = pat.slice_scalars(0, k).get()
    let suf = pat.slice_scalars(k + 1, pat.length()).get()
    if w.length() < pre.length() + suf.length():
        return false

    return w.starts_with(pre) and w.ends_with(suf)

// stem of w against pat; only meaningful when pmatch holds
fn pstem(pat: String, w: String) String:
    let k = pct_index(pat)
    if k < 0:
        return ""

    let suf_n = pat.length() - k - 1
    return w.slice_scalars(k, w.length() - suf_n).get()

fn pat_apply(pat: String, rep: String, w: String) String:
    if pct_index(pat) < 0:
        if w == pat:
            return rep.clone()

        return w.clone()

    if pmatch(pat, w):
        let stem = pstem(pat, w)
        if pct_index(rep) >= 0:
            return rep.replace_first("%", stem)

        return rep.clone()

    return w.clone()

fn words_apply(pat: String, rep: String, text: String) String:
    var out = List[String]()
    for w in text.fields():
        out.append(pat_apply(pat, rep, w))
    return out.join(" ")

fn subst_stem(p: String, stem: String) String:
    if pct_index(p) >= 0:
        return p.replace_first("%", stem)

    return p.clone()

fn join_sep(a: String, b: String) String:
    if a == "" or b == "":
        return "{a}{b}"

    return "{a} {b}"

// index of the closing bracket matching the opener at start, or -1
fn match_close(cs: List[String], start: Int) Int:
    let open = cs[start].clone()
    var close = ")"
    if open == "\{":
        close = "\}"

    var depth = 0
    var j = start

    while j < cs.length():
        if cs[j] == open:
            depth += 1
        else if cs[j] == close:
            depth -= 1
            if depth == 0:
                return j

        j += 1

    return -1

// comma positions outside nested brackets
fn top_commas(cs: List[String]) List[Int]:
    var out = List[Int]()
    var depth = 0
    var k = 0

    while k < cs.length():
        let c = cs[k]

        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1
        else if c == "," and depth == 0:
            out.append(k)

        k += 1

    return out

// raw arguments, each trimmed of spaces and tabs
fn split_args(s: String) List[String]:
    let cs = s.chars()
    let commas = top_commas(cs)
    var out = List[String]()
    var start = 0

    for c in commas:
        out.append(join_range(cs, start, c).trim_chars(" \t"))
        start = c + 1

    out.append(join_range(cs, start, cs.length()).trim_chars(" \t"))
    return out

// splits "VAR:FROM=TO" into [VAR, FROM, TO]; empty list when not a substitution reference
fn subst_parts(t: String) List[String]:
    let cs = t.chars()
    var colon = -1
    var k = 1

    while k < cs.length():
        if cs[k] == ":":
            colon = k
            break

        k += 1

    if colon < 0:
        return List[String]()

    var eq = -1
    var m = colon + 1

    while m < cs.length():
        if cs[m] == "=":
            eq = m
            break

        m += 1

    if eq < 0:
        return List[String]()

    return [
        join_range(cs, 0, colon), join_range(cs, colon + 1, eq),
        join_range(cs, eq + 1, cs.length())
    ]

fn is_auto(name: String) Bool:
    return (
        name == "@"
        or name == "<"
        or name == "^"
        or name == "?"
        or name == "|"
        or name == "*"
    )

fn is_func(n: String) Bool:
    return [
        "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort",
        "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix",
        "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info",
        "error"
    ].contains(n)

// glob matching: * any run of non-/, ? one non-/, others literal
fn glob_m(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi == p.length():
        return si == s.length()

    let pc = p[pi].clone()

    if pc == "*":
        var k = si

        while k <= s.length():
            if glob_m(p, pi + 1, s, k):
                return true
            if k == s.length():
                break
            if s[k] == "/":
                break

            k += 1

        return false

    if si >= s.length():
        return false

    if pc == "?":
        if s[si] == "/":
            return false

        return glob_m(p, pi + 1, s, si + 1)

    if s[si] != pc:
        return false

    return glob_m(p, pi + 1, s, si + 1)

fn glob_match(p: String, s: String) Bool:
    return glob_m(p.chars(), 0, s.chars(), 0)

// ---------- variable expansion ----------

fn expand_var(var st: St, name: String, raw: String) String!Fail:
    if st.stack.contains(name):
        return error(
            ferr(
                st.line, "Recursive variable '{name}' references itself (eventually)"
            )
        )

    st.stack.append(name.clone())

    let v = try expand(var st, raw)
    let _p = st.stack.pop()
    return ok(v)

fn lookup_name(var st: St, name: String) String!Fail:
    var k = st.binds.length()

    while k > 0:
        k -= 1
        if st.binds[k].name == name:
            return ok(st.binds[k].value.clone())

    if is_auto(name):
        if st.auto_on:
            return ok(st.auto.get_or(name.clone(), ""))

        return ok("")

    if st.cli.contains(name):
        let raw = st.cli.get_or(name.clone(), "")
        return expand_var(var st, name, raw)

    if st.vars.contains(name):
        let raw = st.vars.get_or(name.clone(), "")
        if st.recur.get_or(name.clone(), false):
            return expand_var(var st, name, raw)

        return ok(raw)

    return ok("")

fn reference(var st: St, inner: String) String!Fail:
    let cs = inner.chars()
    let n = cs.length()
    var k = 0
    while k < n and cs[k] != " " and cs[k] != "\t":
        k += 1

    if k < n:
        let fname = join_range(cs, 0, k)
        if is_func(fname):
            return call_func(var st, fname, join_range(cs, k + 1, n))

    let full = try expand(var st, inner)
    let t = full.trim()
    let sp = subst_parts(t)

    if sp.length() == 3:
        var pat = sp[1].clone()
        var rep = sp[2].clone()

        if pct_index(pat) < 0:
            pat = "%{pat}"
            rep = "%{rep}"

        let v = try lookup_name(var st, sp[0].trim())
        return ok(words_apply(pat, rep, v))

    return lookup_name(var st, t)

fn expand(var st: St, text: String) String!Fail:
    let cs = text.chars()
    let n = cs.length()
    var parts = List[String]()
    var i = 0

    while i < n:
        if cs[i] != "$":
            parts.append(cs[i].clone())
            i += 1
        else if i + 1 >= n:
            i += 1
        else if cs[i + 1] == "$":
            parts.append("$")
            i += 2
        else if cs[i + 1] == "(" or cs[i + 1] == "\{":
            let j = match_close(cs, i + 1)
            if j < 0:
                return error(ferr(st.line, "unterminated variable reference"))

            let inner = join_range(cs, i + 2, j)
            let v = try reference(var st, inner)
            parts.append(v)
            i = j + 1
        else:
            let v = try lookup_name(var st, cs[i + 1].clone())
            parts.append(v)
            i += 2

    return ok(parts.join(""))

// ---------- functions ----------

fn call_func(var st: St, fname: String, rest: String) String!Fail:
    let args = split_args(rest)
    if fname == "subst":
        return f_subst(var st, args)
    if fname == "patsubst":
        return f_patsubst(var st, args)

    if fname == "strip":
        let t = try expand(var st, argn(args, 0))
        return ok(t.fields().join(" "))

    if fname == "findstring":
        let find = try expand(var st, argn(args, 0))
        let t = try expand(var st, argn(args, 1))
        if t.contains(find):
            return ok(find)

        return ok("")

    if fname == "filter":
        return f_filter(var st, args, true)
    if fname == "filter-out":
        return f_filter(var st, args, false)

    if fname == "sort":
        let t = try expand(var st, argn(args, 0))
        let s = t.fields().sorted()
        var out = List[String]()
        for w in s:
            if out.length() == 0 or out[out.length() - 1] != w:
                out.append(w.clone())
        return ok(out.join(" "))

    if fname == "word":
        let nt = try expand(var st, argn(args, 0))
        let t = try expand(var st, argn(args, 1))
        let words = t.fields()
        if let k = nt.trim().parse_int():
            if k >= 1 and k <= words.length():
                return ok(words[k - 1].clone())
        return ok("")

    if fname == "wordlist":
        let st_t = try expand(var st, argn(args, 0))
        let en_t = try expand(var st, argn(args, 1))
        let t = try expand(var st, argn(args, 2))
        let words = t.fields()

        if let s = st_t.trim().parse_int():
            if let e0 = en_t.trim().parse_int():
                if s >= 1 and e0 >= s and s <= words.length():
                    var e = e0
                    if e > words.length():
                        e = words.length()

                    var out = List[String]()
                    var k = s - 1

                    while k < e:
                        out.append(words[k].clone())
                        k += 1

                    return ok(out.join(" "))

        return ok("")

    if fname == "words":
        let t = try expand(var st, argn(args, 0))
        let c = t.fields().length()
        return ok("{c}")

    if fname == "firstword":
        let t = try expand(var st, argn(args, 0))
        let words = t.fields()
        if words.length() > 0:
            return ok(words[0].clone())

        return ok("")

    if fname == "lastword":
        let t = try expand(var st, argn(args, 0))
        let words = t.fields()
        if words.length() > 0:
            return ok(words[words.length() - 1].clone())

        return ok("")

    if fname == "dir" or fname == "notdir" or fname == "suffix" or fname == "basename":
        let t = try expand(var st, argn(args, 0))
        return ok(path_func(fname, t))

    if fname == "addprefix" or fname == "addsuffix":
        let x = try expand(var st, argn(args, 0))
        let t = try expand(var st, argn(args, 1))
        var out = List[String]()

        for w in t.fields():
            if fname == "addprefix":
                out.append("{x}{w}")
            else:
                out.append("{w}{x}")

        return ok(out.join(" "))

    if fname == "wildcard":
        let pats = (try expand(var st, argn(args, 0))).fields()
        let names = st.files.keys().sorted()
        var out = List[String]()
        for p in pats:
            for nm in names:
                if glob_match(p, nm):
                    out.append(nm.clone())
        return ok(out.join(" "))

    if fname == "foreach":
        return f_foreach(var st, args)

    if fname == "if":
        let c = try expand(var st, argn(args, 0))
        if c.trim() != "":
            return expand(var st, argn(args, 1))

        return expand(var st, argn(args, 2))

    if fname == "info":
        let t = try expand(var st, argn(args, 0))
        print(t)
        return ok("")

    // error
    let t = try expand(var st, argn(args, 0))
    return error(ferr(st.line, t))

fn f_subst(var st: St, args: List[String]) String!Fail:
    let from = try expand(var st, argn(args, 0))
    let to = try expand(var st, argn(args, 1))
    let text = try expand(var st, argn(args, 2))
    if from == "":
        return ok(text)

    return ok(text.replace(from, to))

fn f_patsubst(var st: St, args: List[String]) String!Fail:
    let pat = try expand(var st, argn(args, 0))
    let rep = try expand(var st, argn(args, 1))
    let text = try expand(var st, argn(args, 2))
    return ok(words_apply(pat, rep, text))

fn f_filter(var st: St, args: List[String], keep: Bool) String!Fail:
    let ptxt = try expand(var st, argn(args, 0))
    let wtxt = try expand(var st, argn(args, 1))
    let pats = ptxt.fields()
    var out = List[String]()

    for w in wtxt.fields():
        var hit = false
        for p in pats:
            if pmatch(p, w):
                hit = true
        if hit == keep:
            out.append(w.clone())

    return ok(out.join(" "))

fn f_foreach(var st: St, args: List[String]) String!Fail:
    let vname = (try expand(var st, argn(args, 0))).trim()
    let ltxt = try expand(var st, argn(args, 1))
    var results = List[String]()

    for w in ltxt.fields():
        st.binds.append(Bind(name: vname.clone(), value: w.clone()))

        let r = try expand(var st, argn(args, 2))
        let _b = st.binds.pop()
        results.append(r)

    return ok(results.join(" "))

// dir, notdir, suffix, basename applied to each word
fn path_func(fname: String, text: String) String:
    var out = List[String]()

    for w in text.fields():
        let k = last_slash(w)

        if fname == "dir":
            if k < 0:
                out.append("./")
            else:
                out.append(w.slice_scalars(0, k + 1).get())
        else if fname == "notdir":
            if k < 0:
                out.append(w.clone())
            else:
                let rest = w.slice_scalars(k + 1, w.length()).get()
                if rest != "":
                    out.append(rest)
        else:
            let d = last_char(w, ".", k + 1)

            if fname == "suffix":
                if d >= 0:
                    out.append(w.slice_scalars(d, w.length()).get())
            else:
                if d < 0:
                    out.append(w.clone())
                else:
                    let base = w.slice_scalars(0, d).get()
                    if base != "":
                        out.append(base)

    return out.join(" ")

// ---------- Makefile parsing ----------

fn logical_lines(text: String) List[LLine]:
    var out = List[LLine]()
    var started = false
    var acc = ""
    var start = 0
    var k = 0

    for raw in text.split("\n"):
        k += 1

        let l = raw.trim_end_chars("\r")
        var now = l.clone()

        if started:
            now = "{acc} {l.trim_start()}"
        else:
            start = k

        if now.ends_with("\\"):
            acc = now.slice_scalars(0, now.length() - 1).get().trim_end_chars(" \t")
            started = true
        else:
            out.append(LLine(num: start, text: now))
            started = false
            acc = ""

    if started:
        out.append(LLine(num: start, text: acc))
    return out

// removes comments (\# is a literal #), then trims spaces and tabs
fn strip_comment(t: String) String:
    let cs = t.chars()
    let n = cs.length()
    var out = List[String]()
    var k = 0

    while k < n:
        if cs[k] == "\\" and k + 1 < n and cs[k + 1] == "#":
            out.append("#")
            k += 2
        else if cs[k] == "#":
            break
        else:
            out.append(cs[k].clone())
            k += 1

    return out.join("").trim_chars(" \t")

fn keyword(s: String) String:
    let cs = s.chars()
    var k = 0
    while k < cs.length() and cs[k] != " " and cs[k] != "\t" and cs[k] != "(":
        k += 1

    let w = join_range(cs, 0, k)
    if (
        w == "ifdef"
        or w == "ifndef"
        or w == "ifeq"
        or w == "ifneq"
        or w == "else"
        or w == "endif"
    ):
        return w

    return ""

// top-level ':' (outside $(...) and ${...}, before any ';'), or -1
fn find_col(cs: List[String]) Int:
    let n = cs.length()
    var k = 0

    while k < n:
        if cs[k] == "$" and k + 1 < n and cs[k + 1] == "$":
            k += 2
        else if cs[k] == "$" and k + 1 < n and (cs[k + 1] == "(" or cs[k + 1] == "\{"):
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

fn find_char(cs: List[String], ch: String) Int:
    var k = 0

    while k < cs.length():
        if cs[k] == ch:
            return k

        k += 1

    return -1

fn frames_active(frames: List[Frame]) Bool:
    if frames.length() == 0:
        return true

    let t = frames.length() - 1
    return frames[t].parent and frames[t].taking

fn set_var(var st: St, nm: String, v: String, rec: Bool) Unit:
    st.vars[nm.clone()] = v.clone()
    st.recur[nm.clone()] = rec

fn do_assign(var st: St, cs: List[String], eq: Int) Unit!Fail:
    let n = cs.length()
    var op = "="
    var name_end = eq

    if eq >= 1 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
        let pc = cs[eq - 1].clone()
        op = "{pc}="
        name_end = eq - 1

    let name_raw = join_range(cs, 0, name_end)
    let value_raw = join_range(cs, eq + 1, n).trim()
    let nm = (try expand(var st, name_raw)).trim()
    if nm == "":
        return error(ferr(st.line, "empty variable name"))
    if st.cli.contains(nm):
        return ok(unit)

    if op == "=":
        set_var(var st, nm, value_raw, true)
    else if op == ":=":
        let v = try expand(var st, value_raw)
        set_var(var st, nm, v, false)
    else if op == "?=":
        if not st.vars.contains(nm):
            set_var(var st, nm, value_raw, true)
    else:
        if not st.vars.contains(nm):
            set_var(var st, nm, value_raw, true)
        else if st.recur.get_or(nm.clone(), false):
            let old = st.vars.get_or(nm.clone(), "")
            set_var(var st, nm, join_sep(old, value_raw), true)
        else:
            let v = try expand(var st, value_raw)
            let old = st.vars.get_or(nm.clone(), "")
            set_var(var st, nm, join_sep(old, v), false)

    return ok(unit)

fn close_rule(var st: St) Unit:
    if not st.rule_open:
        return

    st.rule_open = false

    if st.cur_rec.length() > 0 and not st.cur_phony:
        let exs = st.cur_ex.clone()

        for i in exs:
            if st.rules[i].recipe.length() > 0:
                print(
                    "Makefile:{st.cur_num}: warning: overriding recipe for target '{st.rules[i].name}'"
                )
            st.rules[i].recipe = st.cur_rec.clone()

        let pats = st.cur_pat.clone()
        for j in pats:
            st.prules[j].recipe = st.cur_rec.clone()

    st.cur_ex = List[Int]()
    st.cur_pat = List[Int]()
    st.cur_rec = List[RLine]()

fn add_phony(var st: St, name: String) Unit:
    if not st.phony.contains(name):
        st.phony.append(name.clone())

fn do_rule(var st: St, cs: List[String], col: Int) Unit!Fail:
    let n = cs.length()
    var semi = -1
    var k = col + 1

    while k < n:
        if cs[k] == ";":
            semi = k
            break

        k += 1

    let tgt_raw = join_range(cs, 0, col)
    var pre_end = n
    if semi >= 0:
        pre_end = semi

    let pre_raw = join_range(cs, col + 1, pre_end)
    var cmd = ""
    if semi >= 0:
        cmd = join_range(cs, semi + 1, n).trim()

    let tnames = (try expand(var st, tgt_raw)).fields()
    let pe = try expand(var st, pre_raw)
    var ntxt = pe.clone()
    var otxt = ""
    let pcs = pe.chars()
    let bar = find_char(pcs, "|")

    if bar >= 0:
        ntxt = join_range(pcs, 0, bar)
        otxt = join_range(pcs, bar + 1, pcs.length())

    let normal = ntxt.fields()
    let ords = otxt.fields()
    st.cur_ex = List[Int]()
    st.cur_pat = List[Int]()
    st.cur_rec = List[RLine]()
    st.cur_phony = false
    st.cur_num = st.line
    st.rule_open = true
    if cmd != "":
        st.cur_rec.append(RLine(num: st.line, text: cmd.clone()))

    for tn in tnames:
        if tn == ".PHONY":
            st.cur_phony = true
            for p in normal:
                add_phony(var st, p)
            for p in ords:
                add_phony(var st, p)
        else if pct_index(tn) >= 0:
            st.prules.append(
                PRule(
                    pat: tn.clone(), normal: normal.clone(), order: ords.clone(),
                    recipe: List[RLine]()
                )
            )
            st.cur_pat.append(st.prules.length() - 1)
        else:
            if not st.ridx.contains(tn):
                st.ridx[tn.clone()] = st.rules.length()
                st.rules.append(
                    Rule(
                        name: tn.clone(), normal: List[String](), order: List[String](),
                        recipe: List[RLine]()
                    )
                )

                if not st.has_default and not tn.starts_with("."):
                    st.has_default = true
                    st.default_goal = tn.clone()

            let i = st.ridx.get_or(tn.clone(), -1)
            for p in normal:
                st.rules[i].normal.append(p.clone())
            for p in ords:
                st.rules[i].order.append(p.clone())
            st.cur_ex.append(i)

    return ok(unit)

fn eval_cond(var st: St, kw: String, s: String) Bool!Fail:
    let cs = s.chars()
    let rest = join_range(cs, kw.length(), cs.length()).trim()

    if kw == "ifdef" or kw == "ifndef":
        let nm = (try expand(var st, rest)).trim()
        var defined = false

        if st.cli.contains(nm):
            defined = st.cli.get_or(nm.clone(), "") != ""
        else if st.vars.contains(nm):
            defined = st.vars.get_or(nm.clone(), "") != ""

        if kw == "ifdef":
            return ok(defined)

        return ok(not defined)

    let rc = rest.chars()
    let m = rc.length()
    if m < 2 or rc[0] != "(" or rc[m - 1] != ")":
        return error(ferr(st.line, "invalid syntax in conditional"))

    let ic = join_range(rc, 1, m - 1).chars()
    let commas = top_commas(ic)
    if commas.length() != 1:
        return error(ferr(st.line, "invalid syntax in conditional"))

    let c = commas[0]
    let a0 = join_range(ic, 0, c).trim()
    let b0 = join_range(ic, c + 1, ic.length()).trim()
    let a = (try expand(var st, a0)).trim()
    let b = (try expand(var st, b0)).trim()
    if kw == "ifeq":
        return ok(a == b)

    return ok(a != b)

fn parse_mk(var st: St, text: String) Unit!Fail:
    reset_parse(var st)

    let lls = logical_lines(text)
    var frames = List[Frame]()

    for ll in lls:
        st.line = ll.num

        let t = ll.text.clone()
        let active = frames_active(frames)

        if t.starts_with("\t"):
            if active:
                let body = t.trim()

                if body != "":
                    if not st.rule_open:
                        return error(
                            ferr(
                                st.line, "recipe commences before first target"
                            )
                        )

                    st.cur_rec.append(RLine(num: st.line, text: body))

            continue

        let s = strip_comment(t)
        if s == "":
            continue

        let kw = keyword(s)

        if kw == "ifdef" or kw == "ifndef" or kw == "ifeq" or kw == "ifneq":
            if active:
                close_rule(var st)

                let c = try eval_cond(var st, kw, s)
                frames.append(
                    Frame(
                        parent: true, taking: c, seen_else: false, line: st.line
                    )
                )
            else:
                frames.append(
                    Frame(
                        parent: false, taking: false, seen_else: false, line: st.line
                    )
                )

            continue

        if kw == "else" or kw == "endif":
            if frames.length() == 0:
                if kw == "else":
                    return error(ferr(st.line, "extraneous 'else'"))

                return error(ferr(st.line, "extraneous 'endif'"))

            let ti = frames.length() - 1
            let fp = frames[ti].parent
            let fse = frames[ti].seen_else
            let ft = frames[ti].taking
            let fl = frames[ti].line
            if fp:
                close_rule(var st)

            if kw == "else":
                if fp and fse:
                    return error(ferr(st.line, "extraneous 'else'"))

                frames[ti] = Frame(
                    parent: fp, taking: not ft, seen_else: true, line: fl
                )
            else:
                let _f = frames.pop()

            continue

        if not active:
            continue

        close_rule(var st)

        let cs = s.chars()
        let col = find_col(cs)
        let eq = find_char(cs, "=")

        if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
            try do_assign(var st, cs, eq)
        else if col >= 0:
            try do_rule(var st, cs, col)
        else:
            let e = try expand(var st, s)
            if e.trim() != "":
                return error(ferr(st.line, "missing separator"))

    close_rule(var st)
    if frames.length() > 0:
        return error(ferr(frames[frames.length() - 1].line, "missing 'endif'"))

    return ok(unit)

// ---------- resolution and building ----------

fn can_make(st: St, name: String, depth: Int) Bool:
    if st.files.contains(name) or st.ridx.contains(name) or st.phony.contains(name):
        return true
    if depth <= 0:
        return false

    var k = 0

    while k < st.prules.length():
        let pat = st.prules[k].pat.clone()

        if (
            st.prules[k].recipe.length() > 0
            and pmatch(pat, name)
            and pstem(pat, name) != ""
        ):
            let stem = pstem(pat, name)
            var good = true
            for p in st.prules[k].normal:
                if not can_make(st, subst_stem(p, stem), depth - 1):
                    good = false
            for p in st.prules[k].order:
                if not can_make(st, subst_stem(p, stem), depth - 1):
                    good = false
            if good:
                return true

        k += 1

    return false

fn resolve(st: St, t: String) Res:
    let ei = st.ridx.get_or(t.clone(), -1)
    if ei >= 0 and st.rules[ei].recipe.length() > 0:
        return Res(
            found: true, normal: st.rules[ei].normal.clone(),
            order: st.rules[ei].order.clone(), recipe: st.rules[ei].recipe.clone(),
            has_recipe: true, stem: ""
        )

    var k = 0

    while k < st.prules.length():
        let pat = st.prules[k].pat.clone()

        if st.prules[k].recipe.length() > 0 and pmatch(pat, t) and pstem(pat, t) != "":
            let stem = pstem(pat, t)
            var good = true
            for p in st.prules[k].normal:
                if not can_make(st, subst_stem(p, stem), 8):
                    good = false
            for p in st.prules[k].order:
                if not can_make(st, subst_stem(p, stem), 8):
                    good = false

            if good:
                var nrm = List[String]()
                for p in st.prules[k].normal:
                    nrm.append(subst_stem(p, stem))

                var ords = List[String]()
                for p in st.prules[k].order:
                    ords.append(subst_stem(p, stem))

                if ei >= 0:
                    for p in st.rules[ei].normal:
                        nrm.append(p.clone())
                    for p in st.rules[ei].order:
                        ords.append(p.clone())

                return Res(
                    found: true, normal: nrm, order: ords,
                    recipe: st.prules[k].recipe.clone(), has_recipe: true, stem: stem
                )

        k += 1

    if ei >= 0:
        return Res(
            found: true, normal: st.rules[ei].normal.clone(),
            order: st.rules[ei].order.clone(), recipe: List[RLine](), has_recipe: false,
            stem: ""
        )

    return Res(
        found: false, normal: List[String](), order: List[String](),
        recipe: List[RLine](), has_recipe: false, stem: ""
    )

// simulated command; returns exit status, prints its own output
fn simulate(var st: St, cmd: String) Int:
    let w = cmd.fields()
    let n = w.length()
    if n == 0:
        return 0

    let first = w[0].clone()
    if first == "false":
        return 1

    if first == "exit":
        if n < 2:
            return 0
        if let v = w[1].parse_int():
            return v

        return 2

    if first == "touch":
        for k in 1..n:
            if not w[k].starts_with("-"):
                st.clock += 1
                st.files[w[k].clone()] = st.clock

        return 0

    if first == "rm":
        for k in 1..n:
            if not w[k].starts_with("-"):
                if st.files.contains(w[k]):
                    st.files.remove(w[k].clone())
        return 0

    if first == "cp":
        if n == 3:
            if not st.files.contains(w[1]):
                print("cp: cannot stat '{w[1]}': No such file or directory")
                return 1

            st.clock += 1
            st.files[w[2].clone()] = st.clock

        return 0

    if first == "echo":
        var parts = List[String]()
        for k in 1..n:
            parts.append(w[k].replace("\"", "").replace("'", ""))
        print(parts.join(" "))
        return 0

    return 0

fn run_recipe(var st: St, t: String, res: Res, old_in: Bool, old_mt: Int) Unit!Fail:
    st.recipe_ran = true

    let nd = dedup(res.normal)
    var first = ""
    if res.normal.length() > 0:
        first = res.normal[0].clone()

    var qs = List[String]()

    for p in nd:
        var q = not old_in
        if st.changed.get_or(p.clone(), false):
            q = true
        if old_in and st.files.contains(p) and st.files.get_or(p.clone(), 0) > old_mt:
            q = true
        if q:
            qs.append(p.clone())

    let ords = dedup(res.order)
    st.auto = Map[String, String]()
    st.auto["@"] = t.clone()
    st.auto["<"] = first
    st.auto["^"] = nd.join(" ")
    st.auto["?"] = qs.join(" ")
    st.auto["|"] = ords.join(" ")
    st.auto["*"] = res.stem.clone()
    st.auto_on = true

    for rl in res.recipe:
        st.line = rl.num

        let ex = try expand(var st, rl.text)
        let cmdline = ex.trim()
        let cs = cmdline.chars()
        let n = cs.length()
        var silent = false
        var ignore = false
        var k = 0
        var go = true

        while go and k < n:
            if cs[k] == "@":
                silent = true
                k += 1
            else if cs[k] == "-":
                ignore = true
                k += 1
            else if cs[k] == "+" or cs[k] == " " or cs[k] == "\t":
                k += 1
            else:
                go = false

        let cmd = join_range(cs, k, n).trim()
        if cmd == "":
            continue

        if st.dry:
            print(cmd)
            continue

        if not silent:
            print(cmd)

        let status = simulate(var st, cmd)

        if status != 0:
            if ignore:
                print("make: [Makefile:{rl.num}: {t}] Error {status} (ignored)")
            else:
                print("make: *** [Makefile:{rl.num}: {t}] Error {status}")
                return error(Fail(text: ""))

    st.auto_on = false

    if not st.dry and not st.phony.contains(t):
        st.clock += 1
        st.files[t.clone()] = st.clock

    return ok(unit)

fn update(var st: St, t: String, needed: String) Bool!Fail:
    if st.memo.contains(t):
        return ok(st.memo.get_or(t.clone(), false))

    let pos = list_index(st.bstack, t)

    if pos >= 0:
        let chain = chain_from(st.bstack, pos, t)
        return error(ferr(0, "Circular dependency detected: {chain}"))

    let res = resolve(st, t.clone())

    if not res.found:
        if st.files.contains(t):
            st.memo[t.clone()] = false
            return ok(false)

        if st.phony.contains(t):
            st.memo[t.clone()] = true
            st.changed[t.clone()] = true
            return ok(true)

        if needed == "":
            return error(ferr(0, "No rule to make target '{t}'"))

        return error(ferr(0, "No rule to make target '{t}', needed by '{needed}'"))

    st.bstack.append(t.clone())

    let old_in = st.files.contains(t)
    var old_mt = 0
    if old_in:
        old_mt = st.files.get_or(t.clone(), 0)

    var any = false
    let nd = dedup(res.normal)

    for p in nd:
        let c = try update(var st, p.clone(), t.clone())
        if c:
            any = true

    var newer = false
    if old_in:
        for p in nd:
            if st.files.contains(p) and st.files.get_or(p.clone(), 0) > old_mt:
                newer = true

    let od = dedup(res.order)
    for p in od:
        let _c2 = try update(var st, p.clone(), t.clone())

    let must = st.phony.contains(t) or not st.files.contains(t) or any or newer
    var result = false

    if must:
        result = true
        if res.has_recipe:
            try run_recipe(var st, t.clone(), res, old_in, old_mt)

    let _b = st.bstack.pop()
    st.memo[t.clone()] = result
    if result:
        st.changed[t.clone()] = true
    return ok(result)

fn deps_visit(
    st: St,
    t: String,
    var stack: List[String],
    var done: List[String],
    var out: List[String]
) Unit!Fail:
    let res = resolve(st, t.clone())
    var all = dedup(res.normal)
    for p in dedup(res.order):
        all.append(p.clone())
    stack.append(t.clone())

    for p in all:
        let pos = list_index(stack, p)

        if pos >= 0:
            let chain = chain_from(stack, pos, p)
            return error(ferr(0, "Circular dependency detected: {chain}"))

        if not done.contains(p):
            try deps_visit(st, p.clone(), var stack, var done, var out)
            done.append(p.clone())
            out.append(p.clone())

    let _q = stack.pop()
    return ok(unit)

fn rule_line(name: String, normal: List[String], ords: List[String]) String:
    var s = "{name}:"

    if normal.length() > 0:
        let a = normal.join(" ")
        s = "{s} {a}"

    if ords.length() > 0:
        let b = ords.join(" ")
        s = "{s} | {b}"

    return s

// ---------- requests ----------

fn report(e: Fail) Unit:
    if e.text != "":
        print(e.text)

fn after_word(line: String) String:
    let cs = line.trim().chars()
    var k = 0
    while k < cs.length() and cs[k] != " " and cs[k] != "\t":
        k += 1
    return join_range(cs, k, cs.length()).trim()

// sets command-line variables; returns the remaining words (targets)
fn parse_cli(var st: St, toks: List[String]) List[String]:
    st.cli = Map[String, String]()

    var targets = List[String]()
    var k = 1

    while k < toks.length():
        let t = toks[k].clone()
        let cs = t.chars()
        let eq = find_char(cs, "=")

        if eq > 0:
            let name = join_range(cs, 0, eq)
            st.cli[name] = join_range(cs, eq + 1, cs.length())
        else:
            targets.append(t)

        k += 1

    return targets

fn build_req(var st: St, toks: List[String], dry: Bool) Unit!Fail:
    let targets = parse_cli(var st, toks)
    let mk = st.mk.clone()
    try parse_mk(var st, mk)
    st.line = 0
    st.dry = dry
    st.stack = List[String]()
    st.binds = List[Bind]()
    st.auto_on = false

    var goals = targets

    if goals.length() == 0:
        if st.has_default:
            goals = [st.default_goal.clone()]
        else:
            print("make: *** No targets.  Stop.")
            return ok(unit)

    for g in goals:
        st.recipe_ran = false

        let _c = try update(var st, g.clone(), "")

        if not st.recipe_ran:
            let res = resolve(st, g.clone())

            if res.has_recipe or (not st.phony.contains(g) and st.files.contains(g)):
                print("make: '{g}' is up to date.")
            else:
                print("make: Nothing to be done for '{g}'.")

    return ok(unit)

fn deps_req(var st: St, toks: List[String]) Unit!Fail:
    let targets = parse_cli(var st, toks)

    if targets.length() != 1:
        print("usage: deps TARGET")
        return ok(unit)

    let mk = st.mk.clone()
    try parse_mk(var st, mk)
    st.line = 0

    var stack = List[String]()
    var done = List[String]()
    var out = List[String]()
    try deps_visit(st, targets[0].clone(), var stack, var done, var out)
    if out.length() == 0:
        print("(no prerequisites)")
    for o in out:
        print(o)
    return ok(unit)

fn targets_req(var st: St, toks: List[String]) Unit!Fail:
    let _t = parse_cli(var st, toks)
    let mk = st.mk.clone()
    try parse_mk(var st, mk)
    if st.has_default:
        print("default: {st.default_goal}")
    for r in st.rules:
        print(rule_line(r.name, r.normal, r.order))

    for p in st.prules:
        let rl = rule_line(p.pat, p.normal, p.order)
        print("pattern {rl}")

    if st.phony.length() > 0:
        let ph = st.phony.join(" ")
        print("phony: {ph}")

    return ok(unit)

fn touch_req(var st: St, toks: List[String]) Unit:
    let nargs = toks.length() - 1

    if nargs == 1:
        st.clock += 1
        st.files[toks[1].clone()] = st.clock
    else if nargs == 2:
        if let v = toks[2].parse_int():
            st.files[toks[1].clone()] = v
            if v > st.clock:
                st.clock = v
        else:
            print("bad request")
    else:
        print("bad request")

fn run_req(var st: St, line: String) Unit!Fail:
    let toks = line.fields()
    let cmd = toks[0].clone()

    if cmd == "files":
        let names = st.files.keys().sorted()
        if names.length() == 0:
            print("(no files)")

        for nm in names:
            let mt = st.files.get_or(nm.clone(), 0)
            print("{nm} {mt}")

        return ok(unit)

    if cmd == "touch":
        touch_req(var st, toks)
        return ok(unit)

    if cmd == "rm":
        for k in 1..toks.length():
            if st.files.contains(toks[k]):
                st.files.remove(toks[k].clone())
        return ok(unit)

    if cmd == "expand":
        let text = after_word(line)
        st.cli = Map[String, String]()

        let mk = st.mk.clone()
        try parse_mk(var st, mk)
        st.line = 0
        st.stack = List[String]()

        let v = try expand(var st, text)
        print("[{v}]")
        return ok(unit)

    if cmd == "build":
        return build_req(var st, toks, false)
    if cmd == "dry":
        return build_req(var st, toks, true)
    if cmd == "deps":
        return deps_req(var st, toks)
    if cmd == "targets":
        return targets_req(var st, toks)

    print("unknown request: {cmd}")
    return ok(unit)

fn handle(var st: St, line: String) Unit:
    let r = run_req(var st, line)
    r.get_or_else(fn(e: Fail) Unit: report(e))

// ---------- main ----------

export fn main() Int:
    let data = read_all(stdin()).get()
    let text = data.decode_utf8().get()
    let lines = text.split("\n")
    let n = lines.length()
    var sep1 = -1
    var sep2 = -1
    var k = 0

    while k < n:
        if lines[k].trim_end_chars("\r") == "====":
            if sep1 < 0:
                sep1 = k
            else if sep2 < 0:
                sep2 = k

        k += 1

    var mk_end = n
    var tb_start = n
    var tb_end = n
    var rq_start = n

    if sep1 >= 0:
        mk_end = sep1
        tb_start = sep1 + 1

        if sep2 >= 0:
            tb_end = sep2
            rq_start = sep2 + 1

    var mk_lines = List[String]()
    for j in 0..mk_end:
        mk_lines.append(lines[j].clone())

    var st = new_state()
    st.mk = mk_lines.join("\n")

    for j in tb_start..tb_end:
        let f = lines[j].fields()
        if f.length() == 2:
            if let mt = f[1].parse_int():
                if mt >= 0:
                    st.files[f[0].clone()] = mt

    for nm in st.files.keys():
        let mt = st.files.get_or(nm.clone(), 0)
        if mt > st.clock:
            st.clock = mt

    for j in rq_start..n:
        let rl = lines[j].trim_end_chars("\r")
        let t = rl.trim()
        if t == "" or t.starts_with("#"):
            continue

        let shown = rl.trim_end()
        print("> {shown}")
        handle(var st, t)

    return 0
