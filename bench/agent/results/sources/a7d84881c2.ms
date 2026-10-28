import {stdout, stdin} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Fail:
    text: String

impl Error for Fail:
    fn message() String:
        return self.text.clone()

type RecLine:
    no: Int
    text: String

type VarDef:
    value: String
    recursive: Bool

type CondFrame:
    line: Int
    parent_on: Bool
    cond: Bool
    in_else: Bool

type Binding:
    name: String
    value: String

type PatRule:
    pattern: String
    prereqs: List[String]
    oprereqs: List[String]
    recipe: List[RecLine]

type Resolved:
    found: Bool
    prereqs: List[String]
    oprereqs: List[String]
    recipe: List[RecLine]
    stem: String

let FUNCS = [
    "subst", "patsubst", "strip", "findstring", "filter-out", "filter", "sort",
    "wordlist", "word", "words", "firstword", "lastword", "dir", "notdir", "suffix",
    "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"
]
let AUTO = ["@", "<", "^", "?", "|", "*"]
let LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
let DIGITS = "0123456789"

fn emit(s: String) Unit:
    stdout().write(s + "\n").get()

fn join_chars(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var k = a

    while k < b:
        out = out + cs[k].clone()
        k += 1

    return out

fn find_char(cs: List[String], ch: String, from: Int) Int:
    var k = from

    while k < cs.length():
        if cs[k] == ch:
            return k

        k += 1

    return -1

fn last_char(cs: List[String], ch: String) Int:
    var k = cs.length() - 1

    while k >= 0:
        if cs[k] == ch:
            return k

        k -= 1

    return -1

fn count_letters(cs: List[String]) Int:
    var k = 0
    while k < cs.length() and LETTERS.contains(cs[k].clone()):
        k += 1
    return k

fn match_close(cs: List[String], start: Int, opener: String, closer: String) Int:
    var depth = 1
    var k = start

    while k < cs.length():
        if cs[k] == opener:
            depth += 1
        else if cs[k] == closer:
            depth -= 1
            if depth == 0:
                return k

        k += 1

    return -1

fn strip_cr(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    if n > 0 and cs[n - 1] == "\r":
        return join_chars(cs, 0, n - 1)

    return s

fn strip_tabs(s: String) String:
    let cs = s.chars()
    var k = 0
    while k < cs.length() and cs[k] == "\t":
        k += 1
    return join_chars(cs, k, cs.length())

fn words(s: String) List[String]:
    var out = List[String]()
    var cur = ""

    for c in s.chars():
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur = cur + c

    if cur != "":
        out.append(cur)
    return out

fn join_from(ws: List[String], a: Int, b: Int) String:
    var out = List[String]()
    var k = a

    while k < b:
        out.append(ws[k].clone())
        k += 1

    return out.join(" ")

fn dedup(xs: List[String]) List[String]:
    var out = List[String]()
    for x in xs:
        if not out.contains(x):
            out.append(x.clone())
    return out

fn is_digits(s: String) Bool:
    let cs = s.chars()
    if cs.length() == 0:
        return false

    for c in cs:
        if not DIGITS.contains(c):
            return false
    return true

fn strip_comment(s: String) String:
    let cs = s.chars()
    let n = cs.length()
    var out = ""
    var k = 0

    while k < n:
        if cs[k] == "\\" and k + 1 < n and cs[k + 1] == "#":
            out = out + "#"
            k += 2
        else if cs[k] == "#":
            break
        else:
            out = out + cs[k].clone()
            k += 1

    return out

fn find_col(cs: List[String]) Int:
    var depth = 0
    var k = 0
    let n = cs.length()

    while k < n:
        let c = cs[k].clone()
        if depth == 0 and c == ";":
            return -1

        if c == "$" and k + 1 < n and (cs[k + 1] == "(" or cs[k + 1] == "\{"):
            depth += 1
            k += 2
            continue

        if depth > 0:
            if c == "(" or c == "\{":
                depth += 1
            else if c == ")" or c == "\}":
                depth -= 1
        else if c == ":":
            return k

        k += 1

    return -1

fn logical_lines(lines: List[String]) List[RecLine]:
    var out = List[RecLine]()
    var acc = ""
    var start = 0
    var joining = false
    var idx = 0

    for raw in lines:
        idx += 1

        let piece = if joining: raw.trim_start().clone() else: raw.clone()

        if not joining:
            start = idx

        let pc = piece.chars()
        let pn = pc.length()

        if pn > 0 and pc[pn - 1] == "\\":
            acc = acc + join_chars(pc, 0, pn - 1).trim_end() + " "
            joining = true
        else:
            acc = acc + piece
            out.append(RecLine(no: start, text: acc))
            acc = ""
            joining = false

    if joining:
        out.append(RecLine(no: start, text: acc))
    return out

fn pat_match(pat: String, w: String) Optional[String]:
    let pc = pat.chars()
    let wc = w.chars()
    let k = find_char(pc.clone(), "%", 0)

    if k < 0:
        if pat == w:
            return ""

        return none

    let suf_start = k + 1
    let suf_n = pc.length() - suf_start
    let n = wc.length()
    if n < k + suf_n:
        return none
    if join_chars(wc.clone(), 0, k) != join_chars(pc.clone(), 0, k):
        return none
    if (
        join_chars(wc.clone(), n - suf_n, n) != join_chars(
            pc.clone(), suf_start, pc.length()
        )
    ):
        return none

    return join_chars(wc, k, n - suf_n)

fn pat_hit(pat: String, w: String) Bool:
    if let _s = pat_match(pat, w):
        return true

    return false

fn subst_pct(rep: String, stem: String) String:
    let cs = rep.chars()
    let k = find_char(cs.clone(), "%", 0)
    if k < 0:
        return rep

    return (
        join_chars(cs.clone(), 0, k)
        + stem
        + join_chars(cs, k + 1, rep.chars().length())
    )

fn subst_all(xs: List[String], stem: String) List[String]:
    var out = List[String]()
    for w in xs:
        out.append(subst_pct(w.clone(), stem.clone()))
    return out

fn pat_subst(pat: String, rep: String, w: String) String:
    if not pat.contains("%"):
        if pat == w:
            return rep

        return w

    if let s = pat_match(pat, w.clone()):
        return subst_pct(rep, s)

    return w

fn glob_at(p: List[String], pi: Int, s: List[String], si: Int) Bool:
    if pi == p.length():
        return si == s.length()

    let c = p[pi].clone()

    if c == "*":
        var k = si

        while k <= s.length():
            if glob_at(p.clone(), pi + 1, s.clone(), k):
                return true
            if k < s.length() and s[k] == "/":
                return false

            k += 1

        return false

    if si >= s.length():
        return false
    if c == "?":
        return s[si] != "/" and glob_at(p, pi + 1, s, si + 1)
    if c != s[si]:
        return false

    return glob_at(p, pi + 1, s, si + 1)

fn split_args(raw: String) List[String]:
    var out = List[String]()
    var cur = ""
    var depth = 0

    for c in raw.chars():
        if c == "(" or c == "\{":
            depth += 1
        else if c == ")" or c == "\}":
            depth -= 1

        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur = cur + c

    out.append(cur)
    return out

fn raw_arg(args: List[String], k: Int) String:
    if k < args.length():
        return args[k].trim().clone()

    return ""

fn dir_of(w: String) String:
    let cs = w.chars()
    let k = last_char(cs.clone(), "/")
    if k < 0:
        return "./"

    return join_chars(cs, 0, k + 1)

fn notdir_of(w: String) String:
    let cs = w.chars()
    let k = last_char(cs.clone(), "/")
    if k < 0:
        return w

    return join_chars(cs, k + 1, cs.length())

fn suffix_of(w: String) String:
    let cs = w.chars()
    let n = cs.length()
    let start = last_char(cs.clone(), "/") + 1
    let d = last_char(cs.clone(), ".")
    if d >= start:
        return join_chars(cs, d, n)

    return ""

fn basename_of(w: String) String:
    let cs = w.chars()
    let start = last_char(cs.clone(), "/") + 1
    let d = last_char(cs.clone(), ".")
    if d >= start:
        return join_chars(cs, 0, d)

    return w

fn rule_tail(pre: List[String], op: List[String]) String:
    var s = ""
    if pre.length() > 0:
        s = " " + pre.join(" ")
    if op.length() > 0:
        s = s + " | " + op.join(" ")
    return s

fn cond_plain_keyword(kw: String) Bool:
    return kw == "else" or kw == "endif"

fn cond_expr_keyword(kw: String) Bool:
    return kw == "ifdef" or kw == "ifndef" or kw == "ifeq" or kw == "ifneq"

fn strip_quotes(s: String) String:
    var out = ""
    for c in s.chars():
        if c != "'" and c != "\"":
            out = out + c
    return out

type Make:
    mk_lines: List[String]
    vars: Map[String, VarDef]
    cmdvars: Map[String, String]
    table: Map[String, Int]
    clock: Int
    prereqs: Map[String, List[String]]
    oprereqs: Map[String, List[String]]
    recipes: Map[String, List[RecLine]]
    order: List[String]
    prules: List[PatRule]
    phony: List[String]
    frames: List[CondFrame]
    rule_open: Bool
    open_no: Int
    open_explicit: List[String]
    open_pattern: List[String]
    open_normal: List[String]
    open_order: List[String]
    open_recipe: List[RecLine]
    binds: List[Binding]
    auto: Map[String, String]
    stack: List[String]
    line: Int
    memo: Map[String, Bool]
    path: List[String]
    done: List[String]
    outl: List[String]
    recipes_run: Int
    dry: Bool

impl Make:
    fn fail(msg: String) Fail:
        if self.line > 0:
            return Fail(text: "Makefile:{self.line}: *** {msg}.  Stop.")

        return Fail(text: "make: *** {msg}.  Stop.")

    fn is_phony(name: String) Bool:
        return self.phony.contains(name)

    fn is_defined(name: String) Bool:
        if let c = self.cmdvars.get(name.clone()).clone():
            return c != ""
        if let v = self.vars.get(name).clone():
            return v.value != ""

        return false

    fn active() Bool:
        let k = self.frames.length() - 1
        if k < 0:
            return true

        let f = self.frames[k].clone()
        return f.parent_on and f.cond != f.in_else

    fn pre_of(name: String) List[String]:
        if let p = self.prereqs.get(name).clone():
            return p.clone()

        return List[String]()

    fn op_of(name: String) List[String]:
        if let p = self.oprereqs.get(name).clone():
            return p.clone()

        return List[String]()

    fn recipe_of(name: String) List[RecLine]:
        if let p = self.recipes.get(name).clone():
            return p

        return List[RecLine]()

    fn default_goal() String:
        for t in self.order:
            if not t.starts_with("."):
                return t.clone()
        return ""

    fn cycle_error(name: String) Fail:
        var parts = List[String]()
        var started = false

        for p in self.path:
            if p == name:
                started = true
            if started:
                parts.append(p.clone())

        parts.append(name.clone())

        let chain = parts.join(" -> ")
        return Fail(text: "make: *** Circular dependency detected: {chain}.  Stop.")

    var fn reset_parse() Unit:
        self.vars = Map[String, VarDef]()
        self.prereqs = Map[String, List[String]]()
        self.oprereqs = Map[String, List[String]]()
        self.recipes = Map[String, List[RecLine]]()
        self.order = List[String]()
        self.prules = List[PatRule]()
        self.phony = List[String]()
        self.frames = List[CondFrame]()
        self.rule_open = false
        self.binds = List[Binding]()
        self.auto = Map[String, String]()
        self.stack = List[String]()
        self.line = 0
        self.memo = Map[String, Bool]()
        self.path = List[String]()
        self.done = List[String]()
        self.outl = List[String]()

    var fn expand_recursive(name: String, raw: String) Result[String, Fail]:
        if self.stack.contains(name.clone()):
            return error(
                self.fail(
                    "Recursive variable '{name}' references itself (eventually)"
                )
            )

        self.stack.append(name.clone())

        let r = try self.expand(raw)
        let _ = self.stack.pop()
        return ok(r)

    var fn var_value(name: String) Result[String, Fail]:
        var k = self.binds.length() - 1

        while k >= 0:
            if self.binds[k].name == name:
                return ok(self.binds[k].value.clone())

            k -= 1

        if AUTO.contains(name.clone()):
            return ok(self.auto.get(name.clone()).get(""))
        if let c = self.cmdvars.get(name.clone()).clone():
            return self.expand_recursive(name.clone(), c)

        if let v = self.vars.get(name.clone()).clone():
            if v.recursive:
                return self.expand_recursive(name.clone(), v.value.clone())

            return ok(v.value.clone())

        return ok("")

    var fn expand(text: String) Result[String, Fail]:
        let cs = text.chars()
        let n = cs.length()
        var out = ""
        var i = 0

        while i < n:
            if cs[i] != "$":
                out = out + cs[i].clone()
                i += 1
            else if i + 1 >= n:
                i += 1
            else if cs[i + 1] == "$":
                out = out + "$"
                i += 2
            else if cs[i + 1] == "(" or cs[i + 1] == "\{":
                let opener = cs[i + 1].clone()

                let closer = if opener == "(": ")" else: "\}"

                let j = match_close(cs.clone(), i + 2, opener, closer)
                if j < 0:
                    return error(self.fail("unterminated variable reference"))

                let inner = join_chars(cs.clone(), i + 2, j)
                let v = try self.expand_ref(inner)
                out = out + v
                i = j + 1
            else:
                let v = try self.var_value(cs[i + 1].clone())
                out = out + v
                i += 2

        return ok(out)

    var fn expand_ref(inner: String) Result[String, Fail]:
        for f in FUNCS:
            if (
                inner.starts_with(f.clone() + " ")
                or inner.starts_with(f.clone() + "\t")
            ):
                let cs = inner.chars()
                return self.call(
                    f.clone(),
                    join_chars(
                        cs.clone(), f.length() + 1, cs.length()
                    )
                )

        let full = try self.expand(inner)
        let name = full.trim().clone()
        let cs = name.chars()
        let n = cs.length()
        let ci = find_char(cs.clone(), ":", 1)

        if ci >= 1:
            let ei = find_char(cs.clone(), "=", ci + 1)

            if ei >= 0:
                let vname = join_chars(cs.clone(), 0, ci).trim().clone()
                let from = join_chars(cs.clone(), ci + 1, ei)
                let to = join_chars(cs.clone(), ei + 1, n)
                let has_pct = from.contains("%")

                let pf = if has_pct: from.clone() else: "%" + from

                let pt = if has_pct: to.clone() else: "%" + to

                let value = try self.var_value(vname)
                var out = List[String]()
                for w in words(value):
                    out.append(pat_subst(pf.clone(), pt.clone(), w))
                return ok(out.join(" "))

        return self.var_value(name)

    var fn call(fname: String, rest: String) Result[String, Fail]:
        if fname == "info":
            let t = try self.expand(rest.trim())
            emit(t)
            return ok("")

        if fname == "error":
            let t = try self.expand(rest.trim())
            return error(self.fail(t))

        let args = split_args(rest)

        if fname == "if":
            let c = try self.expand(raw_arg(args.clone(), 0))
            if c.trim() != "":
                return self.expand(raw_arg(args.clone(), 1))

            return self.expand(raw_arg(args.clone(), 2))

        if fname == "foreach":
            let v = try self.expand(raw_arg(args.clone(), 0))
            let lst = try self.expand(raw_arg(args.clone(), 1))
            let body = raw_arg(args.clone(), 2)
            var out = List[String]()

            for w in words(lst):
                self.binds.append(Binding(name: v.trim().clone(), value: w))

                let r = try self.expand(body.clone())
                let _ = self.binds.pop()
                out.append(r)

            return ok(out.join(" "))

        if fname == "wildcard":
            let pats = try self.expand(raw_arg(args.clone(), 0))
            var out = List[String]()
            let names = self.table.keys().sorted()

            for p in words(pats):
                let pc = p.chars()
                for f in names:
                    if glob_at(pc.clone(), 0, f.chars(), 0):
                        out.append(f.clone())

            return ok(out.join(" "))

        let a0 = try self.expand(raw_arg(args.clone(), 0))
        let a1 = try self.expand(raw_arg(args.clone(), 1))
        let a2 = try self.expand(raw_arg(args.clone(), 2))

        if fname == "subst":
            if a0 == "":
                return ok(a2)

            return ok(a2.replace(a0, a1))

        if fname == "patsubst":
            var out = List[String]()
            for w in words(a2):
                out.append(pat_subst(a0.clone(), a1.clone(), w))
            return ok(out.join(" "))

        if fname == "strip":
            return ok(words(a0).join(" "))

        if fname == "findstring":
            if a1.contains(a0.clone()):
                return ok(a0)

            return ok("")

        if fname == "filter" or fname == "filter-out":
            let pats = words(a0)
            var out = List[String]()

            for w in words(a1):
                var hit = false
                for p in pats.clone():
                    if pat_hit(p, w.clone()):
                        hit = true

                let keep = if fname == "filter": hit else: not hit

                if keep:
                    out.append(w)

            return ok(out.join(" "))

        if fname == "sort":
            var out = List[String]()
            for w in words(a0).sorted():
                if out.length() == 0 or out[out.length() - 1] != w:
                    out.append(w)
            return ok(out.join(" "))

        if fname == "word":
            if let k = a0.parse_int():
                let ws = words(a1)
                if k >= 1 and k <= ws.length():
                    return ok(ws[k - 1].clone())

            return ok("")

        if fname == "wordlist":
            if let sv = a0.parse_int():
                if let ev = a1.parse_int():
                    let ws = words(a2)

                    let ne = if ev > ws.length(): ws.length() else: ev

                    if sv >= 1 and ev >= sv and sv <= ws.length():
                        return ok(join_from(ws, sv - 1, ne))

            return ok("")

        if fname == "words":
            return ok("{words(a0).length()}")

        if fname == "firstword":
            let ws = words(a0)
            if ws.length() > 0:
                return ok(ws[0].clone())

            return ok("")

        if fname == "lastword":
            let ws = words(a0)
            if ws.length() > 0:
                return ok(ws[ws.length() - 1].clone())

            return ok("")

        if (
            fname == "dir"
            or fname == "notdir"
            or fname == "suffix"
            or fname == "basename"
        ):
            var out = List[String]()

            for w in words(a0):
                if fname == "dir":
                    out.append(dir_of(w))
                else if fname == "notdir":
                    out.append(notdir_of(w))
                else if fname == "suffix":
                    let s = suffix_of(w)
                    if s != "":
                        out.append(s)
                else:
                    out.append(basename_of(w))

            return ok(out.join(" "))

        if fname == "addprefix" or fname == "addsuffix":
            var out = List[String]()

            for w in words(a1):
                if fname == "addprefix":
                    out.append(a0.clone() + w)
                else:
                    out.append(w + a0.clone())

            return ok(out.join(" "))

        return ok("")

    var fn simulate(command: String) Int:
        let ws = words(command)
        if ws.length() == 0:
            return 0

        let cmd = ws[0].clone()
        if cmd == "false":
            return 1

        if cmd == "exit":
            if ws.length() < 2:
                return 0
            if let st = ws[1].parse_int():
                return st

            return 2

        if cmd == "touch":
            for k in 1..ws.length():
                let f = ws[k].clone()

                if not f.starts_with("-"):
                    self.clock += 1
                    self.table.add(f, self.clock)

            return 0

        if cmd == "rm":
            for k in 1..ws.length():
                let f = ws[k].clone()
                if not f.starts_with("-"):
                    self.table.remove(f)

            return 0

        if cmd == "cp":
            if ws.length() == 3:
                let src = ws[1].clone()
                let dst = ws[2].clone()

                if not self.table.contains(src.clone()):
                    emit("cp: cannot stat '{src}': No such file or directory")
                    return 1

                self.clock += 1
                self.table.add(dst, self.clock)

            return 0

        if cmd == "echo":
            var parts = List[String]()
            for k in 1..ws.length():
                parts.append(strip_quotes(ws[k].clone()))
            emit(parts.join(" "))
            return 0

        return 0

    fn resolve(name: String) Resolved:
        let rec = self.recipe_of(name.clone())
        if rec.length() > 0:
            return Resolved(
                found: true, prereqs: self.pre_of(name.clone()),
                oprereqs: self.op_of(name.clone()), recipe: rec, stem: ""
            )

        for p in self.prules:
            if p.recipe.length() > 0:
                if let s = pat_match(p.pattern.clone(), name.clone()):
                    if s != "":
                        let pre = subst_all(p.prereqs.clone(), s.clone())
                        let op = subst_all(p.oprereqs.clone(), s.clone())

                        if self.all_can_make(pre.clone(), op.clone(), 0):
                            var full = pre
                            for w in self.pre_of(name.clone()):
                                full.append(w)

                            var fullo = op
                            for w in self.op_of(name.clone()):
                                fullo.append(w)
                            return Resolved(
                                found: true, prereqs: full, oprereqs: fullo,
                                recipe: p.recipe.clone(), stem: s
                            )

        if self.prereqs.contains(name.clone()):
            return Resolved(
                found: true, prereqs: self.pre_of(name.clone()),
                oprereqs: self.op_of(name.clone()), recipe: List[RecLine](), stem: ""
            )

        return Resolved(
            found: false, prereqs: List[String](), oprereqs: List[String](),
            recipe: List[RecLine](), stem: ""
        )

    fn all_can_make(pre: List[String], op: List[String], depth: Int) Bool:
        for w in pre:
            if not self.can_make(w.clone(), depth):
                return false
        for w in op:
            if not self.can_make(w.clone(), depth):
                return false
        return true

    fn can_make(name: String, depth: Int) Bool:
        if (
            self.table.contains(name.clone())
            or self.prereqs.contains(name.clone())
            or self.is_phony(name.clone())
        ):
            return true
        if depth >= 8:
            return false

        for p in self.prules:
            if p.recipe.length() > 0:
                if let s = pat_match(p.pattern.clone(), name.clone()):
                    if s != "":
                        if self.all_can_make(
                            subst_all(
                                p.prereqs.clone(), s.clone()
                            ),
                            subst_all(
                                p.oprereqs.clone(), s
                            ),
                            depth + 1
                        ):
                            return true
        return false

    var fn run_recipe(
        name: String,
        res: Resolved,
        was_in: Bool,
        old: Int
    ) Result[Unit, Fail]:
        self.recipes_run += 1

        let all = dedup(res.prereqs.clone())
        var newer = List[String]()

        for p in all.clone():
            let changed = self.memo.get(p.clone()).get(false)
            let later = (
                self.table.contains(p.clone())
                and self.table.get(p.clone()).get(0) > old
            )
            if not was_in or changed or later:
                newer.append(p)

        let first = if res.prereqs.length() > 0: res.prereqs[0].clone() else: ""

        self.auto = Map[String, String]()
        self.auto.add("@", name.clone())
        self.auto.add("<", first)
        self.auto.add("^", all.join(" "))
        self.auto.add("?", newer.join(" "))
        self.auto.add("|", dedup(res.oprereqs.clone()).join(" "))
        self.auto.add("*", res.stem.clone())

        for line in res.recipe.clone():
            self.line = line.no

            let raw = try self.expand(line.text.clone())
            let cs = raw.trim().chars()
            let n = cs.length()
            var k = 0
            var silent = false
            var ignore = false

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
                    ignore = true
                k += 1

            let command = join_chars(cs, k, n).trim()

            if self.dry:
                if command != "":
                    emit(command)
                continue

            if not silent and command != "":
                emit(command.clone())

            let status = self.simulate(command)

            if status != 0:
                if ignore:
                    emit("make: [Makefile:{line.no}: {name}] Error {status} (ignored)")
                else:
                    emit("make: *** [Makefile:{line.no}: {name}] Error {status}")
                    return error(Fail(text: ""))

        self.line = 0
        self.auto = Map[String, String]()

        if not self.dry and not self.is_phony(name.clone()):
            self.clock += 1
            self.table.add(name.clone(), self.clock)

        return ok(unit)

    var fn update(name: String, parent: String) Result[Bool, Fail]:
        if self.memo.contains(name.clone()):
            return ok(self.memo.get(name.clone()).get(false))
        if self.path.contains(name.clone()):
            return error(self.cycle_error(name.clone()))

        let res = self.resolve(name.clone())

        if not res.found:
            if self.table.contains(name.clone()):
                self.memo.add(name.clone(), false)
                return ok(false)

            if self.is_phony(name.clone()):
                self.memo.add(name.clone(), true)
                return ok(true)

            if parent == "":
                return error(
                    Fail(
                        text: "make: *** No rule to make target '{name}'.  Stop."
                    )
                )

            return error(
                Fail(
                    text: "make: *** No rule to make target '{name}', needed by '{parent}'.  Stop."
                )
            )

        self.path.append(name.clone())

        let was_in = self.table.contains(name.clone())
        var old = 0
        if was_in:
            old = self.table.get(name.clone()).get(0)

        var changed = false
        var newer = false

        for p in dedup(res.prereqs.clone()):
            let c = try self.update(p.clone(), name.clone())
            if c:
                changed = true
            if (
                was_in
                and self.table.contains(p.clone())
                and self.table.get(p.clone()).get(0) > old
            ):
                newer = true

        for o in dedup(res.oprereqs.clone()):
            let _o = try self.update(o, name.clone())

        let _ = self.path.pop()
        let must = (
            self.is_phony(name.clone())
            or not self.table.contains(name.clone())
            or changed
            or newer
        )
        var result = false

        if must:
            result = true
            if res.recipe.length() > 0:
                try self.run_recipe(name.clone(), res, was_in, old)

        self.memo.add(name.clone(), result)
        return ok(result)

    var fn visit(p: String) Result[Unit, Fail]:
        if self.done.contains(p.clone()):
            return ok(unit)
        if self.path.contains(p.clone()):
            return error(self.cycle_error(p.clone()))

        self.path.append(p.clone())
        try self.collect(p.clone())

        let _ = self.path.pop()
        self.done.append(p.clone())
        self.outl.append(p)
        return ok(unit)

    var fn collect(name: String) Result[Unit, Fail]:
        let res = self.resolve(name.clone())
        for p in dedup(res.prereqs.clone()):
            try self.visit(p)
        for p in dedup(res.oprereqs.clone()):
            try self.visit(p)
        return ok(unit)

    var fn close_rule() Unit:
        if not self.rule_open:
            return

        self.rule_open = false

        for t in self.open_explicit.clone():
            if self.prereqs.contains(t.clone()):
                var p = self.pre_of(t.clone())
                for w in self.open_normal.clone():
                    p.append(w)
                self.prereqs.add(t.clone(), p)

                var q = self.op_of(t.clone())
                for w in self.open_order.clone():
                    q.append(w)
                self.oprereqs.add(t.clone(), q)
            else:
                self.order.append(t.clone())
                self.prereqs.add(t.clone(), self.open_normal.clone())
                self.oprereqs.add(t.clone(), self.open_order.clone())

            if self.open_recipe.length() > 0:
                if self.recipe_of(t.clone()).length() > 0:
                    emit(
                        "Makefile:{self.open_no}: warning: overriding recipe for target '{t}'"
                    )
                self.recipes.add(t.clone(), self.open_recipe.clone())

        for pt in self.open_pattern.clone():
            self.prules.append(
                PatRule(
                    pattern: pt, prereqs: self.open_normal.clone(),
                    oprereqs: self.open_order.clone(), recipe: self.open_recipe.clone()
                )
            )

    var fn cond_line(kw: String, rest: String, no: Int) Result[Unit, Fail]:
        if kw == "else":
            let k = self.frames.length() - 1
            if k < 0:
                return error(self.fail("extraneous 'else'"))

            let f = self.frames[k].clone()
            if f.in_else:
                return error(self.fail("extraneous 'else'"))

            self.frames[k] = CondFrame(
                line: f.line, parent_on: f.parent_on, cond: f.cond, in_else: true
            )
            return ok(unit)

        if kw == "endif":
            if self.frames.length() == 0:
                return error(self.fail("extraneous 'endif'"))

            let _ = self.frames.pop()
            return ok(unit)

        let parent = self.active()
        var on = false

        if parent:
            if kw == "ifdef" or kw == "ifndef":
                let raw = try self.expand(rest.clone())
                let defined = self.is_defined(raw.trim().clone())

                on = if kw == "ifdef": defined else: not defined
            else:
                let cs = rest.trim().chars()
                let n = cs.length()
                if n < 2 or cs[0] != "(" or cs[n - 1] != ")":
                    return error(self.fail("invalid syntax in conditional"))

                let parts = split_args(join_chars(cs, 1, n - 1))
                if parts.length() != 2:
                    return error(self.fail("invalid syntax in conditional"))

                let av = try self.expand(parts[0].trim())
                let bv = try self.expand(parts[1].trim())
                let same = av.trim() == bv.trim()

                on = if kw == "ifeq": same else: not same

        self.frames.append(
            CondFrame(line: no, parent_on: parent, cond: on, in_else: false)
        )
        return ok(unit)

    var fn assign(cs: List[String], eqi: Int) Result[Unit, Fail]:
        let n = cs.length()
        var op = ""
        var name_end = eqi

        if eqi > 0 and (cs[eqi - 1] == ":" or cs[eqi - 1] == "?" or cs[eqi - 1] == "+"):
            op = cs[eqi - 1].clone()
            name_end = eqi - 1

        let nv = try self.expand(join_chars(cs.clone(), 0, name_end))
        let name = nv.trim().clone()
        if name == "":
            return error(self.fail("empty variable name"))

        let value = join_chars(cs, eqi + 1, n).trim().clone()
        if self.cmdvars.contains(name.clone()):
            return ok(unit)

        if op == "":
            self.vars.add(name.clone(), VarDef(value: value, recursive: true))
        else if op == ":":
            let v = try self.expand(value)
            self.vars.add(name.clone(), VarDef(value: v, recursive: false))
        else if op == "?":
            if not self.vars.contains(name.clone()):
                self.vars.add(name.clone(), VarDef(value: value, recursive: true))
        else:
            if let old = self.vars.get(name.clone()).clone():
                let sep = if old.value != "" and value != "": " " else: ""

                if old.recursive:
                    self.vars.add(
                        name.clone(),
                        VarDef(
                            value: old.value + sep + value, recursive: true
                        )
                    )
                else:
                    let v = try self.expand(value)

                    let sep2 = if old.value != "" and v != "": " " else: ""

                    self.vars.add(
                        name.clone(),
                        VarDef(
                            value: old.value + sep2 + v, recursive: false
                        )
                    )
            else:
                self.vars.add(name.clone(), VarDef(value: value, recursive: true))

        return ok(unit)

    var fn rule(cs: List[String], col: Int, no: Int) Result[Unit, Fail]:
        let n = cs.length()
        let semi = find_char(cs.clone(), ";", col + 1)

        let pre_end = if semi >= 0: semi else: n

        let tv = try self.expand(join_chars(cs.clone(), 0, col))
        let targets = words(tv)
        let pv = try self.expand(join_chars(cs.clone(), col + 1, pre_end))
        let pcs = pv.chars()
        let pl = pcs.length()
        let bar = find_char(pcs.clone(), "|", 0)

        let be = if bar >= 0: bar else: pl

        let normal = words(join_chars(pcs.clone(), 0, be))
        var order = List[String]()
        if bar >= 0:
            order = words(join_chars(pcs.clone(), bar + 1, pl))
        self.rule_open = true
        self.open_no = no
        self.open_normal = normal.clone()
        self.open_order = order
        self.open_recipe = List[RecLine]()
        self.open_explicit = List[String]()
        self.open_pattern = List[String]()

        if targets.length() == 1 and targets[0] == ".PHONY":
            for w in normal:
                if not self.phony.contains(w.clone()):
                    self.phony.append(w)
        else:
            for t in targets:
                if t.contains("%"):
                    self.open_pattern.append(t)
                else:
                    self.open_explicit.append(t)

        if semi >= 0:
            self.open_recipe.append(
                RecLine(
                    no: no, text: strip_tabs(join_chars(cs, semi + 1, n))
                )
            )
        return ok(unit)

    var fn parse(lines: List[String]) Result[Unit, Fail]:
        self.reset_parse()

        for lg in logical_lines(lines):
            self.line = lg.no

            if lg.text.starts_with("\t"):
                if self.active():
                    let body = strip_tabs(lg.text.clone())

                    if body.trim() != "":
                        if not self.rule_open:
                            return error(
                                self.fail(
                                    "recipe commences before first target"
                                )
                            )

                        self.open_recipe.append(RecLine(no: lg.no, text: body))

                continue

            let t = strip_comment(lg.text.clone()).trim().clone()
            if t == "":
                continue

            let cs = t.chars()
            let n = cs.length()
            let k = count_letters(cs.clone())
            let kw = join_chars(cs.clone(), 0, k)
            let rest = join_chars(cs.clone(), k, n)

            let nxt = if k < n: cs[k].clone() else: ""

            if cond_plain_keyword(kw.clone()) and rest.trim() == "":
                self.close_rule()
                try self.cond_line(kw, "", lg.no)
                continue

            if (
                cond_expr_keyword(kw.clone())
                and (
                    nxt == ""
                    or nxt == " "
                    or nxt == "\t"
                    or nxt == "("
                )
            ):
                self.close_rule()
                try self.cond_line(kw, rest, lg.no)
                continue

            if not self.active():
                continue

            self.close_rule()

            let eqi = find_char(cs.clone(), "=", 0)
            let col = find_col(cs.clone())

            if eqi >= 0 and (col < 0 or col > eqi or col == eqi - 1):
                try self.assign(cs, eqi)
                continue

            if col >= 0:
                try self.rule(cs, col, lg.no)
                continue

            let v = try self.expand(t)
            if v.trim() != "":
                return error(self.fail("missing separator"))

        self.close_rule()

        let top = self.frames.length() - 1

        if top >= 0:
            let f = self.frames[top].clone()
            return error(Fail(text: "Makefile:{f.line}: *** missing 'endif'.  Stop."))

        self.line = 0
        return ok(unit)

    var fn request(ws: List[String], line: String) Result[Unit, Fail]:
        let cmd = ws[0].clone()
        self.cmdvars = Map[String, String]()

        if (
            cmd == "build"
            or cmd == "dry"
            or cmd == "deps"
            or cmd == "targets"
            or cmd == "expand"
        ):
            var goals = List[String]()

            if cmd == "expand":
                let tc = line.trim().chars()
                let text = join_chars(tc.clone(), 6, tc.length()).trim()
                try self.parse(self.mk_lines.clone())

                let v = try self.expand(text)
                emit("[{v}]")
                return ok(unit)

            for k in 1..ws.length():
                let wc = ws[k].chars()
                let wn = wc.length()
                let eq = find_char(wc.clone(), "=", 1)

                if eq >= 1:
                    self.cmdvars.add(
                        join_chars(wc.clone(), 0, eq), join_chars(wc, eq + 1, wn)
                    )
                else:
                    goals.append(ws[k].clone())

            if cmd == "targets":
                try self.parse(self.mk_lines.clone())

                let d = self.default_goal()
                if d != "":
                    emit("default: " + d)
                for t in self.order.clone():
                    emit(
                        t.clone() + ":" + rule_tail(
                            self.pre_of(t.clone()), self.op_of(t)
                        )
                    )
                for p in self.prules.clone():
                    emit(
                        "pattern " + p.pattern + ":" + rule_tail(
                            p.prereqs, p.oprereqs
                        )
                    )
                if self.phony.length() > 0:
                    emit("phony: " + self.phony.join(" "))
                return ok(unit)

            if cmd == "deps":
                if goals.length() != 1:
                    emit("usage: deps TARGET")
                    return ok(unit)

                try self.parse(self.mk_lines.clone())

                let target = goals[0].clone()
                self.path.append(target.clone())
                try self.collect(target)
                if self.outl.length() == 0:
                    emit("(no prerequisites)")
                for p in self.outl.clone():
                    emit(p)
                return ok(unit)

            self.dry = cmd == "dry"
            try self.parse(self.mk_lines.clone())

            var gl = goals

            if gl.length() == 0:
                let d = self.default_goal()

                if d == "":
                    emit("make: *** No targets.  Stop.")
                    return ok(unit)

                gl.append(d)

            for g in gl:
                let before = self.recipes_run
                let _g = try self.update(g.clone(), "")

                if self.recipes_run == before:
                    let res = self.resolve(g.clone())
                    let is_file = (
                        not self.is_phony(g.clone())
                        and self.table.contains(g.clone())
                    )

                    if res.recipe.length() > 0 or is_file:
                        emit("make: '{g}' is up to date.")
                    else:
                        emit("make: Nothing to be done for '{g}'.")

            return ok(unit)

        if cmd == "files":
            let names = self.table.keys().sorted()
            if names.length() == 0:
                emit("(no files)")
            for n in names:
                emit("{n} {self.table.get(n.clone()).get(0)}")
            return ok(unit)

        if cmd == "touch":
            if ws.length() == 2:
                self.clock += 1
                self.table.add(ws[1].clone(), self.clock)
                return ok(unit)

            if ws.length() == 3 and is_digits(ws[2].clone()):
                if let m = ws[2].parse_int():
                    self.table.add(ws[1].clone(), m)
                    if m > self.clock:
                        self.clock = m

                return ok(unit)

            emit("bad request")
            return ok(unit)

        if cmd == "rm":
            for k in 1..ws.length():
                self.table.remove(ws[k].clone())
            return ok(unit)

        emit("unknown request: " + cmd)
        return ok(unit)

fn new_make(lines: List[String]) Make:
    return Make(
        mk_lines: lines, vars: Map[String, VarDef](), cmdvars: Map[String, String](),
        table: Map[String, Int](), clock: 0, prereqs: Map[String, List[String]](),
        oprereqs: Map[String, List[String]](), recipes: Map[String, List[RecLine]](),
        order: List[String](), prules: List[PatRule](), phony: List[String](),
        frames: List[CondFrame](), rule_open: false, open_no: 0,
        open_explicit: List[String](), open_pattern: List[String](),
        open_normal: List[String](), open_order: List[String](),
        open_recipe: List[RecLine](), binds: List[Binding](),
        auto: Map[String, String](), stack: List[String](), line: 0,
        memo: Map[String, Bool](), path: List[String](), done: List[String](),
        outl: List[String](), recipes_run: 0, dry: false
    )

export fn main() Int:
    let all = read_lines(stdin()).get()
    var seps = 0
    var mk_lines = List[String]()
    var tb = List[String]()
    var rq = List[String]()

    for raw in all:
        let l = strip_cr(raw.clone())

        if l == "====" and seps < 2:
            seps += 1
        else if seps == 0:
            mk_lines.append(l)
        else if seps == 1:
            tb.append(l)
        else:
            rq.append(l)

    var mk = new_make(mk_lines)

    for l in tb:
        let ws = words(l)

        if ws.length() == 2:
            if let m = ws[1].parse_int():
                mk.table.add(ws[0].clone(), m)
                if m > mk.clock:
                    mk.clock = m

    for raw in rq:
        let line = strip_cr(raw.clone()).trim_end()
        let ws = words(line.clone())
        if ws.length() == 0 or ws[0].starts_with("#"):
            continue

        emit("> " + line)

        let r = mk.request(ws, line)

        if r.is_error():
            let e = r.err()
            if e.text != "":
                emit(e.text)

    return 0
