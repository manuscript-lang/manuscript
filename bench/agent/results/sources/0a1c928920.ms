import read_lines from "@std/streams.ms"
import stdout, stdin from "@std/io.ms"

let PRIORITIES = ["low", "medium", "high", "critical"]
let ISSUE_FIELDS = ["title", "priority", "assignee", "points", "due", "labels", "reporter"]
let SORT_FIELDS = ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
let QFIELDS = ["id", "created", "updated", "points", "title", "assignee", "reporter", "text", "state", "priority", "due", "label", "labels", "is", "has", "view"]
let GUARDS = ["assignee", "points", "due", "labels", "reporter"]
let IS_VALUES = ["open", "final", "overdue", "unassigned"]
let HAS_VALUES = ["assignee", "due", "points", "labels", "comments", "reporter"]
let ORD_OPS = [":", "!=", "<", "<=", ">", ">="]
let EQ_OPS = [":", "!=", "~"]
let LOWER = "abcdefghijklmnopqrstuvwxyz"
let DIGITS = "0123456789"
let OPCHARS = ":!<>=~"
let ALL_OPS = [":", "!=", "<", "<=", ">", ">=", "~"]

type Trans:
    target: String
    guards: List[String]

type Arrow:
    src: String
    entries: List[Trans]
    err: String

type Workflow:
    defined: Bool
    states: List[String]
    index: Map[String, Int]
    initial: String
    finals: List[String]
    trans: Map[String, List[Trans]]
    ntrans: Int

type WfParse:
    wf: Workflow
    err: String

type Comment:
    t: Int
    actor: String
    text: String

type Issue:
    id: Int
    title: String
    state: String
    priority: String
    assignee: String?
    reporter: String?
    points: Int?
    due: String?
    labels: List[String]
    comments: List[Comment]
    created: Int
    updated: Int

type LogEntry:
    t: Int
    actor: String
    id: Int
    detail: String

type QNode:
    kind: Int
    left: Int
    right: Int
    field: String
    op: String
    alts: List[String]

type QP:
    cs: List[String]
    pos: Int
    nodes: List[QNode]
    refs: List[String]
    err: String
    root: Int
    views: List[String]
    states: List[String]

type Out:
    ok: Bool
    text: String

type Split:
    text: String
    has: Bool
    limit: Int
    err: String

type SplitSort:
    text: String
    has: Bool
    sort: String

type SortKey:
    field: String
    desc: Bool

type Keys:
    keys: List[SortKey]
    err: String

type Toks:
    items: List[String]
    err: Bool

type Ref:
    id: Int
    err: String

type Pair:
    a: String
    b: String
    found: Bool

type App:
    wf: Workflow
    clock: Int
    actor: String
    today: String
    next_id: Int
    issues: Map[Int, Issue]
    log: List[LogEntry]
    views: Map[String, String]
    out: List[String]

# ---------- character and value helpers ----------

fn is_ws(c: String) Bool:
    return c == " " or c == "\t" or c == "\r"

fn is_digit(c: String) Bool:
    return c.length() == 1 and DIGITS.contains(c)

fn is_lower(c: String) Bool:
    return c.length() == 1 and LOWER.contains(c)

fn valid_int(s: String) Bool:
    let n = s.length()
    if n == 0 or n > 7:
        return false
    for c in s.chars():
        if not is_digit(c):
            return false
    if n > 1 and s.slice(0, 1).get() == "0":
        return false
    return s.parse_int().get(0) <= 1000000

fn valid_label(s: String) Bool:
    if s.length() == 0:
        return false
    for c in s.chars():
        if not (is_lower(c) or is_digit(c) or c == "_" or c == "-"):
            return false
    return true

fn valid_state(s: String) Bool:
    let cs = s.chars()
    if cs.length() == 0 or not is_lower(cs[0]):
        return false
    for k in 1..cs.length():
        let c = cs[k]
        if not (is_lower(c) or is_digit(c) or c == "_"):
            return false
    return true

fn valid_view(s: String) Bool:
    let cs = s.chars()
    if cs.length() == 0 or not is_lower(cs[0]):
        return false
    for k in 1..cs.length():
        let c = cs[k]
        if not (is_lower(c) or is_digit(c) or c == "_" or c == "-"):
            return false
    return true

fn days_in(m: Int, y: Int) Int:
    if m == 2:
        if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0):
            return 29
        return 28
    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30
    return 31

fn valid_date(s: String) Bool:
    if s.length() != 10:
        return false
    let cs = s.chars()
    for k in [0, 1, 2, 3, 5, 6, 8, 9]:
        if not is_digit(cs[k]):
            return false
    if cs[4] != "-" or cs[7] != "-":
        return false
    let y = s.slice(0, 4).get().parse_int().get(0)
    let m = s.slice(5, 7).get().parse_int().get(0)
    let d = s.slice(8, 10).get().parse_int().get(0)
    if y < 1 or m < 1 or m > 12:
        return false
    return d >= 1 and d <= days_in(m, y)

fn parse_id_arg(arg0: String) Int:
    var arg = arg0.clone()
    if arg.starts_with("#"):
        arg = arg.slice(1, arg.scalar_length()).get()
    if arg.length() == 0:
        return -1
    for c in arg.chars():
        if not is_digit(c):
            return -1
    let v = arg.parse_int().get(-1)
    if v < 1:
        return -1
    return v

fn cmp_int(x: Int, y: Int) Int:
    if x < y:
        return -1
    if x > y:
        return 1
    return 0

fn cmp_str(x: String, y: String) Int:
    if x < y:
        return -1
    if x > y:
        return 1
    return 0

# absent is the empty string; absent sorts after present values
fn absent_cmp(x: String, y: String) Int:
    if x == "" and y == "":
        return 0
    if x == "":
        return 1
    if y == "":
        return -1
    return cmp_str(x, y)

fn dash(s: String) String:
    if s == "":
        return "-"
    return s

fn pts_text(x: Int?) String:
    let v = x.get(-1)
    if v < 0:
        return "-"
    return "{v}"

fn labels_text(xs: List[String]) String:
    if xs.length() == 0:
        return "-"
    return xs.join(",")

fn labels_show(xs: List[String]) String:
    if xs.length() == 0:
        return "-"
    return xs.join(", ")

fn norm_labels(xs: List[String]) List[String]:
    let s = xs.sorted()
    var out = List[String]()
    for x in s:
        if out.length() == 0:
            out.append(x.clone())
        else if out[out.length() - 1] != x:
            out.append(x.clone())
    return out

fn plural_issues(n: Int) String:
    if n == 1:
        return "1 issue"
    return "{n} issues"

fn blank_issue() Issue:
    return Issue(id: 0, title: "", state: "", priority: "medium", assignee: none, reporter: none, points: none, due: none, labels: List[String](), comments: List[Comment](), created: 0, updated: 0)

fn unmet(iss: Issue, g: String) Bool:
    if g == "assignee":
        return iss.assignee.get("") == ""
    if g == "reporter":
        return iss.reporter.get("") == ""
    if g == "due":
        return iss.due.get("") == ""
    if g == "points":
        return iss.points.get(-1) < 0
    return iss.labels.length() == 0

# ---------- word and token splitting ----------

fn words(s: String) List[String]:
    var out = List[String]()
    var cur = ""
    for c in s.chars():
        if is_ws(c):
            if cur.length() > 0:
                out.append(cur)
                cur = ""
        else:
            cur = cur + c
    if cur.length() > 0:
        out.append(cur)
    return out

fn join_cs(cs: List[String], a: Int, b: Int) String:
    var s = ""
    for k in a..b:
        s = s + cs[k]
    return s

# text after skipping k whitespace-separated words, leading blanks removed
fn rest_after(s: String, k: Int) String:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var w = 0
    while w < k:
        while i < n and is_ws(cs[i]):
            i += 1
        while i < n and not is_ws(cs[i]):
            i += 1
        w += 1
    while i < n and is_ws(cs[i]):
        i += 1
    return s.slice(i, n).get()

# token style: whitespace separates tokens, quotes group, \" and \\ escape inside quotes
fn tokens(s: String) Toks:
    let cs = s.chars()
    let n = cs.length()
    var items = List[String]()
    var cur = ""
    var started = false
    var inq = false
    var i = 0
    while i < n:
        let c = cs[i]
        if inq:
            if c == "\"":
                inq = false
                i += 1
            else if c == "\\" and i + 1 < n and (cs[i + 1] == "\"" or cs[i + 1] == "\\"):
                cur = cur + cs[i + 1]
                i += 2
            else:
                cur = cur + c
                i += 1
        else if is_ws(c):
            if started:
                items.append(cur)
                cur = ""
                started = false
            i += 1
        else if c == "\"":
            inq = true
            started = true
            i += 1
        else:
            cur = cur + c
            started = true
            i += 1
    if inq:
        return Toks(items: items, err: true)
    if started:
        items.append(cur)
    return Toks(items: items, err: false)

fn rest_items(it: List[String]) List[String]:
    return it.slice(1, it.length()).get()

# ---------- query text splitting ----------

# trailing "limit N" clause
fn split_limit(s: String) Split:
    let t = s.trim()
    let cs = t.chars()
    let n = cs.length()
    var j = n - 1
    while j >= 0:
        if is_ws(cs[j]):
            break
        j -= 1
    if j < 0:
        return Split(text: t, has: false, limit: 0, err: "")
    let arg = t.slice(j + 1, n).get()
    let head = t.slice(0, j).get().trim()
    let hc = head.chars()
    let hn = hc.length()
    var k = hn - 1
    while k >= 0:
        if is_ws(hc[k]):
            break
        k -= 1
    let word = head.slice(k + 1, hn).get()
    if word != "limit":
        return Split(text: t, has: false, limit: 0, err: "")
    var rest = ""
    if k >= 0:
        rest = head.slice(0, k).get().trim()
    if not valid_int(arg):
        return Split(text: t, has: false, limit: 0, err: "bad limit '" + arg + "'")
    return Split(text: rest, has: true, limit: arg.parse_int().get(0), err: "")

# the first " sort " word starts the sort clause running to the end
fn split_sort(s: String) SplitSort:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    while i + 4 < n:
        var hit = false
        if s.slice(i, i + 4).get() == "sort" and is_ws(cs[i + 4]):
            if i == 0:
                hit = true
            else if is_ws(cs[i - 1]):
                hit = true
        if hit:
            return SplitSort(text: s.slice(0, i).get().trim(), has: true, sort: s.slice(i + 4, n).get().trim())
        i += 1
    return SplitSort(text: s.trim(), has: false, sort: "")

fn parse_sort(s: String) Keys:
    var keys = List[SortKey]()
    for w in words(s.replace(",", " ")):
        var name = w.clone()
        var desc = false
        if w.starts_with("-"):
            desc = true
            name = w.slice(1, w.scalar_length()).get()
        if not SORT_FIELDS.contains(name):
            return Keys(keys: keys, err: "bad sort field '" + name + "'")
        keys.append(SortKey(field: name, desc: desc))
    return Keys(keys: keys, err: "")

# filter part of a stored view query (limit and sort removed)
fn filter_part(text: String) String:
    let l = split_limit(text)
    let s = split_sort(l.text)
    return s.text

fn split_where(s: String) Pair:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    while i + 5 <= n:
        var at_start = false
        if i == 0:
            at_start = true
        else if is_ws(cs[i - 1]):
            at_start = true
        if at_start and s.slice(i, i + 5).get() == "where":
            var at_end = false
            if i + 5 == n:
                at_end = true
            else if is_ws(cs[i + 5]):
                at_end = true
            if at_end:
                return Pair(a: s.slice(0, i).get().trim(), b: s.slice(i + 5, n).get().trim(), found: true)
        i += 1
    return Pair(a: "", b: "", found: false)

# ---------- query compiler ----------

fn op_allowed(field: String, op: String) Bool:
    if field == "id" or field == "created" or field == "updated" or field == "points" or field == "priority" or field == "due":
        return ORD_OPS.contains(op)
    if field == "title" or field == "assignee" or field == "reporter" or field == "labels" or field == "label":
        return EQ_OPS.contains(op)
    if field == "text":
        return op == "~"
    if field == "state":
        return op == ":" or op == "!="
    if field == "is" or field == "has" or field == "view":
        return op == ":"
    return false

fn value_error(field: String, op: String, a: String, views: List[String], states: List[String]) String:
    let bad = "query: bad value '" + a + "' for field '" + field + "'"
    if field == "id" or field == "created" or field == "updated":
        if valid_int(a):
            return ""
        return bad
    if field == "points":
        if a == "none" and (op == ":" or op == "!="):
            return ""
        if valid_int(a):
            return ""
        return bad
    if field == "state":
        if states.contains(a):
            return ""
        return bad
    if field == "priority":
        if PRIORITIES.contains(a):
            return ""
        return bad
    if field == "due":
        if a == "none" and (op == ":" or op == "!="):
            return ""
        if valid_date(a):
            return ""
        return bad
    if field == "is":
        if IS_VALUES.contains(a):
            return ""
        return bad
    if field == "has":
        if HAS_VALUES.contains(a):
            return ""
        return bad
    if field == "view":
        if views.contains(a):
            return ""
        return "query: unknown view '" + a + "'"
    return ""

impl QP:
    var fn skip_ws() Unit:
        while self.pos < self.cs.length():
            if not is_ws(self.cs[self.pos]):
                break
            self.pos += 1

    fn word_at(p: Int) String:
        var w = ""
        var k = p
        while k < self.cs.length():
            let c = self.cs[k]
            if is_ws(c) or c == "(" or c == ")":
                break
            w = w + c
            k += 1
        return w

    var fn push(nd: QNode) Int:
        self.nodes.append(nd)
        return self.nodes.length() - 1

    var fn parse_or() Int:
        var left = self.parse_and()
        if self.err != "":
            return -1
        self.skip_ws()
        while self.word_at(self.pos) == "OR":
            self.pos += 2
            let right = self.parse_and()
            if self.err != "":
                return -1
            left = self.push(QNode(kind: 2, left: left, right: right, field: "", op: "", alts: List[String]()))
            self.skip_ws()
        return left

    var fn parse_and() Int:
        var left = self.parse_not()
        if self.err != "":
            return -1
        while true:
            self.skip_ws()
            if self.pos >= self.cs.length():
                break
            if self.cs[self.pos] == ")" or self.word_at(self.pos) == "OR":
                break
            if self.word_at(self.pos) == "AND":
                self.pos += 3
            let right = self.parse_not()
            if self.err != "":
                return -1
            left = self.push(QNode(kind: 1, left: left, right: right, field: "", op: "", alts: List[String]()))
        return left

    var fn parse_not() Int:
        self.skip_ws()
        if self.word_at(self.pos) == "NOT":
            self.pos += 3
            let c = self.parse_not()
            if self.err != "":
                return -1
            return self.push(QNode(kind: 3, left: c, right: -1, field: "", op: "", alts: List[String]()))
        return self.parse_primary()

    var fn parse_primary() Int:
        self.skip_ws()
        let n = self.cs.length()
        if self.pos >= n:
            self.err = "query: unexpected end of query"
            return -1
        let c = self.cs[self.pos].clone()
        if c == "(":
            self.pos += 1
            let e = self.parse_or()
            if self.err != "":
                return -1
            self.skip_ws()
            if self.pos >= n:
                self.err = "query: unexpected end of query"
                return -1
            self.pos += 1
            return e
        if c == ")":
            self.err = "query: unexpected token ')'"
            return -1
        let w = self.word_at(self.pos)
        if w == "OR" or w == "AND":
            self.err = "query: unexpected token '" + w + "'"
            return -1
        var k = self.pos + 0
        while k < n:
            let ch = self.cs[k]
            if not is_lower(ch) and ch != "_":
                break
            k += 1
        var bare = true
        if k > self.pos and k < n:
            if OPCHARS.contains(self.cs[k]):
                bare = false
        if bare:
            self.err = "query: unexpected token '" + w + "'"
            return -1
        let field = join_cs(self.cs, self.pos, k)
        var op = ""
        if k + 1 < n:
            let two = self.cs[k] + self.cs[k + 1]
            if two == "!=" or two == "<=" or two == ">=":
                op = two
        if op == "":
            if ":<>~".contains(self.cs[k]):
                op = self.cs[k].clone()
        if op == "":
            var m = k
            while m < n:
                if not OPCHARS.contains(self.cs[m]):
                    break
                m += 1
            op = join_cs(self.cs, k, m)
        self.pos = k + op.scalar_length()
        if not ALL_OPS.contains(op):
            self.err = "query: unexpected token '" + w + "'"
            return -1
        if not QFIELDS.contains(field):
            self.err = "query: unknown field '" + field + "'"
            return -1
        if not op_allowed(field, op):
            self.err = "query: bad operator '" + op + "' for field '" + field + "'"
            return -1
        var val = ""
        var quoted = false
        if self.pos < n:
            if self.cs[self.pos] == "\"":
                quoted = true
                var q = self.pos + 1
                var closed = false
                while q < n:
                    let ch = self.cs[q]
                    if ch == "\\" and q + 1 < n and (self.cs[q + 1] == "\"" or self.cs[q + 1] == "\\"):
                        val = val + self.cs[q + 1]
                        q += 2
                    else if ch == "\"":
                        closed = true
                        q += 1
                        break
                    else:
                        val = val + ch
                        q += 1
                if not closed:
                    self.err = "query: unterminated quote"
                    return -1
                self.pos = q
        if not quoted:
            var q = self.pos + 0
            while q < n:
                let ch = self.cs[q]
                if is_ws(ch) or ch == "(" or ch == ")":
                    break
                val = val + ch
                q += 1
            self.pos = q
        var alts = List[String]()
        var splittable = false
        if not quoted and field != "view" and EQ_OPS.contains(op) and val.contains("|"):
            splittable = true
        if splittable:
            alts = val.split("|")
        else:
            alts.append(val.clone())
        for a in alts:
            let e = value_error(field, op, a, self.views, self.states)
            if e != "":
                self.err = e
                return -1
            if field == "view":
                self.refs.append(a.clone())
        return self.push(QNode(kind: 0, left: -1, right: -1, field: field, op: op, alts: alts))

fn compile_query(text: String, views: List[String], states: List[String]) QP:
    var p = QP(cs: text.chars(), pos: 0, nodes: List[QNode](), refs: List[String](), err: "", root: -1, views: views.clone(), states: states.clone())
    p.skip_ws()
    if p.pos >= p.cs.length():
        return p
    p.root = p.parse_or()
    if p.err != "":
        return p
    p.skip_ws()
    if p.pos < p.cs.length():
        p.err = "query: unexpected token ')'"
    return p

# ---------- workflow definition parsing ----------

fn parse_arrow(ln: String) Arrow:
    let p = ln.index_of("->").get(0)
    let src = ln.slice(0, p).get().trim()
    let rest = ln.slice(p + 2, ln.scalar_length()).get()
    if not valid_state(src):
        return Arrow(src: src.clone(), entries: List[Trans](), err: "workflow: bad state name '" + src + "'")
    var entries = List[Trans]()
    for ent in rest.split(","):
        let ws = words(ent)
        if ws.length() == 1:
            if not valid_state(ws[0]):
                return Arrow(src: src, entries: entries, err: "workflow: bad state name '" + ws[0] + "'")
            entries.append(Trans(target: ws[0].clone(), guards: List[String]()))
        else if ws.length() == 3 and ws[1] == "requires":
            if not valid_state(ws[0]):
                return Arrow(src: src, entries: entries, err: "workflow: bad state name '" + ws[0] + "'")
            var guards = List[String]()
            for g in ws[2].split("+"):
                if not GUARDS.contains(g):
                    return Arrow(src: src, entries: entries, err: "workflow: bad guard field '" + g + "'")
                guards.append(g.clone())
            entries.append(Trans(target: ws[0].clone(), guards: guards))
        else:
            return Arrow(src: src, entries: entries, err: "workflow: bad line '" + ln + "'")
    return Arrow(src: src, entries: entries, err: "")

fn parse_wf(body: List[String]) WfParse:
    var states = List[String]()
    var finals = List[String]()
    var initial = ""
    var has_init = false
    var trans = Map[String, List[Trans]]()
    var ntrans = 0
    var srcs = List[String]()
    var err = ""
    for ln in body:
        if err != "":
            break
        if ln == "" or ln.starts_with("#"):
            continue
        if ln.starts_with("initial:"):
            let name = ln.slice(8, ln.scalar_length()).get().trim()
            if not valid_state(name):
                err = "workflow: bad state name '" + name + "'"
            else if has_init:
                err = "workflow: initial state defined twice"
            else:
                has_init = true
                initial = name.clone()
                if not states.contains(name):
                    states.append(name.clone())
        else if ln.starts_with("final:"):
            let rest = ln.slice(6, ln.scalar_length()).get()
            for part in rest.split(","):
                let name = part.trim()
                if not valid_state(name):
                    err = "workflow: bad state name '" + name + "'"
                    break
                if not states.contains(name):
                    states.append(name.clone())
                finals.append(name.clone())
        else if ln.contains("->"):
            let a = parse_arrow(ln)
            if a.err != "":
                err = a.err
            else:
                if not states.contains(a.src):
                    states.append(a.src.clone())
                var lst = trans.get(a.src).get(List[Trans]())
                for e in a.entries:
                    if not states.contains(e.target):
                        states.append(e.target.clone())
                    lst.append(Trans(target: e.target.clone(), guards: e.guards.clone()))
                    ntrans += 1
                    srcs.append(a.src.clone())
                trans[a.src] = lst
        else:
            err = "workflow: bad line '" + ln + "'"
    if err == "" and not has_init:
        err = "workflow: initial state missing"
    if err == "":
        for s in srcs:
            if finals.contains(s):
                err = "workflow: '" + s + "' is final and cannot have transitions"
                break
    if err != "":
        return WfParse(wf: Workflow(defined: false, states: List[String](), index: Map[String, Int](), initial: "", finals: List[String](), trans: Map[String, List[Trans]](), ntrans: 0), err: err)
    var index = Map[String, Int]()
    for k in 0..states.length():
        index[states[k].clone()] = k
    return WfParse(wf: Workflow(defined: true, states: states, index: index, initial: initial, finals: finals, trans: trans, ntrans: ntrans), err: "")

# ---------- issue field updates ----------

fn set_field(var iss: Issue, key: String, val: String) String:
    if key == "title":
        if val.trim() == "":
            return "empty title"
        iss.title = val
        return ""
    if key == "priority":
        if not PRIORITIES.contains(val):
            return "bad priority '" + val + "'"
        iss.priority = val
        return ""
    if key == "assignee":
        if val == "none":
            iss.assignee = none
            return ""
        if val == "":
            return "empty assignee"
        iss.assignee = val
        return ""
    if key == "points":
        if val == "none":
            iss.points = none
            return ""
        if not valid_int(val):
            return "bad points '" + val + "'"
        iss.points = val.parse_int().get(0)
        return ""
    if key == "due":
        if val == "none":
            iss.due = none
            return ""
        if not valid_date(val):
            return "bad date '" + val + "'"
        iss.due = val
        return ""
    if key == "labels":
        if val == "none":
            iss.labels = List[String]()
            return ""
        var ls = List[String]()
        for part in val.split(","):
            let l = part.lower()
            if not valid_label(l):
                return "bad label '" + l + "'"
            ls.append(l)
        iss.labels = norm_labels(ls)
        return ""
    if key == "reporter":
        if val == "none":
            iss.reporter = none
            return ""
        if val == "":
            return "empty reporter"
        iss.reporter = val
        return ""
    return "unknown field '" + key + "'"

fn apply_token(var iss: Issue, tok: String) String:
    let k = tok.index_of("=").get(-1)
    if k <= 0:
        return "expected field=value, got '" + tok + "'"
    let key = tok.slice(0, k).get()
    let val = tok.slice(k + 1, tok.scalar_length()).get()
    if key == "state":
        return "use move to change state"
    if not ISSUE_FIELDS.contains(key):
        return "unknown field '" + key + "'"
    return set_field(var iss, key, val)

# log detail lines for every field that differs between a and b
fn diff(a: Issue, b: Issue) List[String]:
    var out = List[String]()
    if a.title != b.title:
        out.append("title: " + a.title + " -> " + b.title)
    if a.priority != b.priority:
        out.append("priority: " + a.priority + " -> " + b.priority)
    let aa = dash(a.assignee.get(""))
    let ba = dash(b.assignee.get(""))
    if aa != ba:
        out.append("assignee: " + aa + " -> " + ba)
    let ap = pts_text(a.points)
    let bp = pts_text(b.points)
    if ap != bp:
        out.append("points: " + ap + " -> " + bp)
    let ad = dash(a.due.get(""))
    let bd = dash(b.due.get(""))
    if ad != bd:
        out.append("due: " + ad + " -> " + bd)
    let al = labels_text(a.labels)
    let bl = labels_text(b.labels)
    if al != bl:
        out.append("labels: " + al + " -> " + bl)
    let ar = dash(a.reporter.get(""))
    let br = dash(b.reporter.get(""))
    if ar != br:
        out.append("reporter: " + ar + " -> " + br)
    return out

fn group_before(a: Int, b: Int, pts: List[Int], counts: List[Int], keys: List[String]) Bool:
    if pts[a] != pts[b]:
        return pts[a] > pts[b]
    if counts[a] != counts[b]:
        return counts[a] > counts[b]
    return keys[a] < keys[b]

fn label_before(a: Int, b: Int, names: List[String], counts: List[Int]) Bool:
    if counts[a] != counts[b]:
        return counts[a] > counts[b]
    return names[a].lower() < names[b].lower()

# ---------- application state ----------

impl App:
    var fn emit(line: String) Unit:
        self.out.append(line)

    var fn log_add(id: Int, detail: String) Unit:
        self.log.append(LogEntry(t: self.clock, actor: self.actor.clone(), id: id, detail: detail))

    fn is_final(s: String) Bool:
        return self.wf.finals.contains(s)

    fn state_rank(s: String) Int:
        return self.wf.index.get(s).get(-1)

    fn view_names() List[String]:
        return self.views.keys()

    fn load(id: Int) Issue:
        return self.issues.get(id).get(blank_issue())

    fn all_issues() List[Issue]:
        var out = List[Issue]()
        for id in 1..self.next_id:
            let iss = self.load(id)
            if iss.id == id:
                out.append(iss)
        return out

    # live issue id from an argument, or an error
    fn resolve(arg: String) Ref:
        let v = parse_id_arg(arg)
        if v < 0:
            return Ref(id: 0, err: "bad issue id '" + arg + "'")
        if self.load(v).id != v:
            return Ref(id: 0, err: "no such issue #{v}")
        return Ref(id: v, err: "")

    fn person(field: String, iss: Issue) String:
        if field == "assignee":
            return iss.assignee.get("")
        return iss.reporter.get("")

    fn eq_match(field: String, a: String, iss: Issue) Bool:
        if field == "id":
            return iss.id == a.parse_int().get(-1)
        if field == "created":
            return iss.created == a.parse_int().get(-1)
        if field == "updated":
            return iss.updated == a.parse_int().get(-1)
        if field == "points":
            if a == "none":
                return iss.points.get(-1) < 0
            return iss.points.get(-1) == a.parse_int().get(-1)
        if field == "title":
            return a != "none" and iss.title.lower() == a.lower()
        if field == "assignee" or field == "reporter":
            let v = self.person(field, iss)
            if a == "none":
                return v == ""
            return v != "" and v.lower() == a.lower()
        if field == "state":
            return iss.state == a
        if field == "priority":
            return iss.priority == a
        if field == "due":
            let d = iss.due.get("")
            if a == "none":
                return d == ""
            return d != "" and d == a
        if field == "label" or field == "labels":
            let al = a.lower()
            if al == "none":
                return iss.labels.length() == 0
            return iss.labels.contains(al)
        if field == "is":
            if a == "open":
                return not self.is_final(iss.state)
            if a == "final":
                return self.is_final(iss.state)
            if a == "overdue":
                let d = iss.due.get("")
                return not self.is_final(iss.state) and d != "" and d < self.today
            if a == "unassigned":
                return self.person("assignee", iss) == ""
            return false
        if field == "has":
            if a == "assignee":
                return iss.assignee.get("") != ""
            if a == "due":
                return iss.due.get("") != ""
            if a == "points":
                return iss.points.get(-1) >= 0
            if a == "labels":
                return iss.labels.length() > 0
            if a == "comments":
                return iss.comments.length() > 0
            if a == "reporter":
                return iss.reporter.get("") != ""
            return false
        return false

    fn contains_match(field: String, a: String, iss: Issue) Bool:
        let al = a.lower()
        if field == "title":
            return iss.title.lower().contains(al)
        if field == "assignee" or field == "reporter":
            let v = self.person(field, iss)
            return v != "" and v.lower().contains(al)
        if field == "text":
            if iss.title.lower().contains(al):
                return true
            for c in iss.comments:
                if c.text.lower().contains(al):
                    return true
            return false
        if field == "label" or field == "labels":
            for l in iss.labels:
                if l.contains(al):
                    return true
            return false
        return false

    fn ord_match(field: String, op: String, a: String, iss: Issue) Bool:
        var c = 0
        if field == "id":
            c = cmp_int(iss.id, a.parse_int().get(0))
        else if field == "created":
            c = cmp_int(iss.created, a.parse_int().get(0))
        else if field == "updated":
            c = cmp_int(iss.updated, a.parse_int().get(0))
        else if field == "points":
            let p = iss.points.get(-1)
            if p < 0:
                return false
            c = cmp_int(p, a.parse_int().get(0))
        else if field == "priority":
            c = cmp_int(prio_rank(iss.priority), prio_rank(a))
        else if field == "due":
            let d = iss.due.get("")
            if d == "":
                return false
            c = cmp_str(d, a)
        if op == "<":
            return c < 0
        if op == "<=":
            return c <= 0
        if op == ">":
            return c > 0
        return c >= 0

    fn qmatch(nodes: List[QNode], idx: Int, iss: Issue) Bool:
        let nd = nodes[idx]
        if nd.kind == 1:
            return self.qmatch(nodes, nd.left, iss) and self.qmatch(nodes, nd.right, iss)
        if nd.kind == 2:
            return self.qmatch(nodes, nd.left, iss) or self.qmatch(nodes, nd.right, iss)
        if nd.kind == 3:
            return not self.qmatch(nodes, nd.left, iss)
        if nd.field == "view":
            return self.view_match(nd.alts[0], iss)
        var hit = false
        if nd.op == "<" or nd.op == "<=" or nd.op == ">" or nd.op == ">=":
            hit = self.ord_match(nd.field, nd.op, nd.alts[0], iss)
        else:
            for a in nd.alts:
                var m = false
                if nd.op == "~":
                    m = self.contains_match(nd.field, a, iss)
                else:
                    m = self.eq_match(nd.field, a, iss)
                if m:
                    hit = true
                    break
            if nd.op == "!=":
                hit = not hit
        return hit

    fn view_match(name: String, iss: Issue) Bool:
        let text = self.views.get(name).get("")
        let q = compile_query(filter_part(text), self.view_names(), self.wf.states)
        if q.err != "":
            return false
        if q.root < 0:
            return true
        return self.qmatch(q.nodes, q.root, iss)

    # does any of refs (transitively through views) reach target
    fn reaches(refs: List[String], target: String) Bool:
        for r in refs:
            if r == target:
                return true
            let sub = compile_query(filter_part(self.views.get(r).get("")), self.view_names(), self.wf.states)
            if self.reaches(sub.refs, target):
                return true
        return false

    fn key_cmp(field: String, a: Issue, b: Issue) Int:
        if field == "id":
            return cmp_int(a.id, b.id)
        if field == "created":
            return cmp_int(a.created, b.created)
        if field == "updated":
            return cmp_int(a.updated, b.updated)
        if field == "priority":
            return cmp_int(prio_rank(a.priority), prio_rank(b.priority))
        if field == "state":
            return cmp_int(self.state_rank(a.state), self.state_rank(b.state))
        if field == "points":
            let pa = a.points.get(-1)
            let pb = b.points.get(-1)
            if pa < 0 and pb < 0:
                return 0
            if pa < 0:
                return 1
            if pb < 0:
                return -1
            return cmp_int(pa, pb)
        if field == "title":
            return cmp_str(a.title.lower(), b.title.lower())
        if field == "assignee":
            return absent_cmp(a.assignee.get("").lower(), b.assignee.get("").lower())
        if field == "reporter":
            return absent_cmp(a.reporter.get("").lower(), b.reporter.get("").lower())
        return absent_cmp(a.due.get(""), b.due.get(""))

    fn sort_cmp(keys: List[SortKey], a: Issue, b: Issue) Int:
        for k in keys:
            var c = self.key_cmp(k.field, a, b)
            if k.desc:
                c = 0 - c
            if c != 0:
                return c
        return cmp_int(a.id, b.id)

    # runs a filtered, sorted, limited listing and emits it; returns an error or ""
    var fn run_list(filter: String, sort_text: String, has_sort: Bool, limit: Int, has_limit: Bool) String:
        let q = compile_query(filter, self.view_names(), self.wf.states)
        if q.err != "":
            return q.err
        var keys = List[SortKey]()
        if has_sort:
            let k = parse_sort(sort_text)
            if k.err != "":
                return k.err
            keys = k.keys
        var sorted = List[Issue]()
        for id in 1..self.next_id:
            let iss = self.load(id)
            if iss.id == id:
                var ok = true
                if q.root >= 0:
                    ok = self.qmatch(q.nodes, q.root, iss)
                if ok:
                    var pos = sorted.length()
                    var j = 0
                    while j < sorted.length():
                        if self.sort_cmp(keys, iss, sorted[j]) < 0:
                            pos = j
                            break
                        j += 1
                    sorted.insert(pos, iss)
        var cnt = sorted.length()
        if has_limit and limit < cnt:
            cnt = limit
        for k in 0..cnt:
            self.emit(issue_row(sorted[k]))
        if cnt == 1:
            self.emit("(1 issue)")
        else:
            self.emit("({cnt} issues)")
        return ""

    var fn core_move(id: Int, to: String, comment: String) Out:
        var iss = self.load(id)
        if self.is_final(iss.state):
            return Out(ok: false, text: "#{id} is in final state '" + iss.state + "'")
        if not self.wf.states.contains(to):
            return Out(ok: false, text: "unknown state '" + to + "'")
        if iss.state == to:
            return Out(ok: false, text: "already in state '" + to + "'")
        let entries = self.wf.trans.get(iss.state).get(List[Trans]())
        var guards = List[String]()
        var found = false
        for tr in entries:
            if not found and tr.target == to:
                found = true
                guards = tr.guards.clone()
        if not found:
            return Out(ok: false, text: "transition '" + iss.state + " -> " + to + "' not allowed")
        var missing = List[String]()
        for g in guards:
            if unmet(iss, g):
                missing.append(g.clone())
        if missing.length() > 0:
            return Out(ok: false, text: "cannot move #{id} to " + to + ": missing " + missing.join(", "))
        let prev = iss.state.clone()
        self.clock += 1
        iss.state = to.clone()
        iss.updated = self.clock
        self.log_add(id, "state: " + prev + " -> " + to)
        if comment != "":
            iss.comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: comment.clone()))
            self.log_add(id, "comment: " + comment)
        self.issues[id] = iss
        return Out(ok: true, text: "moved #{id}: " + prev + " -> " + to)

    var fn core_edit(id: Int, fields: List[String]) Out:
        var iss = self.load(id)
        if self.is_final(iss.state):
            return Out(ok: false, text: "#{id} is in final state '" + iss.state + "'")
        if fields.length() == 0:
            return Out(ok: false, text: "usage: edit ID field=value...")
        let old = iss.clone()
        for tok in fields:
            let e = apply_token(var iss, tok)
            if e != "":
                return Out(ok: false, text: e)
        let changes = diff(old, iss)
        if changes.length() == 0:
            return Out(ok: true, text: "#{id} unchanged")
        self.clock += 1
        iss.updated = self.clock
        for c in changes:
            self.log_add(id, c)
        self.issues[id] = iss
        return Out(ok: true, text: "updated #{id}")

    var fn core_label(id: Int, toks: List[String]) Out:
        var iss = self.load(id)
        if self.is_final(iss.state):
            return Out(ok: false, text: "#{id} is in final state '" + iss.state + "'")
        var labels = iss.labels.clone()
        for tok in toks:
            var name = tok.clone()
            var add = true
            if tok.starts_with("-"):
                add = false
                name = tok.slice(1, tok.scalar_length()).get()
            else if tok.starts_with("+"):
                name = tok.slice(1, tok.scalar_length()).get()
            let l = name.lower()
            if not valid_label(l):
                return Out(ok: false, text: "bad label '" + l + "'")
            if add:
                labels.append(l.clone())
            else:
                var keep = List[String]()
                for x in labels:
                    if x != l:
                        keep.append(x.clone())
                labels = keep
        let nl = norm_labels(labels)
        let before = labels_text(iss.labels)
        let after = labels_text(nl)
        if before == after:
            return Out(ok: true, text: "#{id} unchanged")
        iss.labels = nl
        self.clock += 1
        iss.updated = self.clock
        self.log_add(id, "labels: " + before + " -> " + after)
        self.issues[id] = iss
        return Out(ok: true, text: "updated #{id}")

    var fn core_comment(id: Int, text: String) Out:
        var iss = self.load(id)
        self.clock += 1
        iss.comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: text.clone()))
        iss.updated = self.clock
        self.log_add(id, "comment: " + text)
        self.issues[id] = iss
        return Out(ok: true, text: "commented #{id}")

    var fn core_delete(id: Int) Out:
        self.clock += 1
        self.issues.remove(id)
        self.log_add(id, "deleted")
        return Out(ok: true, text: "deleted #{id}")

    var fn run_action(kind: String, it: List[String], id: Int) Out:
        if kind == "move":
            return self.core_move(id, it[1].clone(), "")
        if kind == "assign":
            return self.core_edit(id, ["assignee=" + it[1]])
        if kind == "label":
            return self.core_label(id, rest_items(it))
        return self.core_edit(id, rest_items(it))

    # ---------- commands ----------

    var fn cmd_workflow(body: List[String]) Unit:
        if self.next_id > 1:
            self.emit("error: workflow: cannot redefine after issues were created")
            return
        let r = parse_wf(body)
        if r.err != "":
            self.emit("error: " + r.err)
            return
        self.wf = r.wf
        self.emit("workflow ok: {self.wf.states.length()} states, {self.wf.ntrans} transitions")

    var fn cmd_actor(ws: List[String]) Unit:
        if ws.length() != 2:
            self.emit("error: usage: actor NAME")
            return
        self.actor = ws[1].clone()
        self.emit("actor is " + self.actor)

    var fn cmd_today(ws: List[String]) Unit:
        if ws.length() != 2:
            self.emit("error: usage: today DATE")
            return
        if not valid_date(ws[1]):
            self.emit("error: bad date '" + ws[1] + "'")
            return
        self.today = ws[1].clone()
        self.emit("today is " + self.today)

    var fn cmd_create(s: String) Unit:
        if not self.wf.defined:
            self.emit("error: no workflow defined")
            return
        let tk = tokens(rest_after(s, 1))
        if tk.err:
            self.emit("error: unterminated quote")
            return
        if tk.items.length() == 0:
            self.emit("error: usage: create TITLE [field=value...]")
            return
        let title = tk.items[0].clone()
        if title.trim() == "":
            self.emit("error: empty title")
            return
        var iss = Issue(id: self.next_id, title: title.clone(), state: self.wf.initial.clone(), priority: "medium", assignee: none, reporter: self.actor.clone(), points: none, due: none, labels: List[String](), comments: List[Comment](), created: 0, updated: 0)
        let def = iss.clone()
        for k in 1..tk.items.length():
            let e = apply_token(var iss, tk.items[k].clone())
            if e != "":
                self.emit("error: " + e)
                return
        self.clock += 1
        iss.created = self.clock
        iss.updated = self.clock
        let id = self.next_id
        self.log_add(id, "created \"" + title + "\"")
        for c in diff(def, iss):
            self.log_add(id, c)
        self.issues[id] = iss
        self.next_id += 1
        self.emit("created #{id}")

    var fn cmd_edit(s: String) Unit:
        let tk = tokens(rest_after(s, 1))
        if tk.err:
            self.emit("error: unterminated quote")
            return
        if tk.items.length() == 0:
            self.emit("error: usage: edit ID field=value...")
            return
        let r = self.resolve(tk.items[0])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_edit(r.id, rest_items(tk.items))
        self.emit(out_line(o))

    var fn cmd_assign(s: String) Unit:
        let tk = tokens(rest_after(s, 1))
        if tk.err:
            self.emit("error: unterminated quote")
            return
        if tk.items.length() != 2:
            self.emit("error: usage: assign ID NAME")
            return
        let r = self.resolve(tk.items[0])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_edit(r.id, ["assignee=" + tk.items[1]])
        self.emit(out_line(o))

    var fn cmd_label(s: String) Unit:
        let tk = tokens(rest_after(s, 1))
        if tk.err:
            self.emit("error: unterminated quote")
            return
        if tk.items.length() < 2:
            self.emit("error: usage: label ID +label -label...")
            return
        let r = self.resolve(tk.items[0])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_label(r.id, rest_items(tk.items))
        self.emit(out_line(o))

    var fn cmd_move(s: String, ws: List[String]) Unit:
        if ws.length() < 3:
            self.emit("error: usage: move ID STATE [comment...]")
            return
        let r = self.resolve(ws[1])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_move(r.id, ws[2].clone(), rest_after(s, 3))
        self.emit(out_line(o))

    var fn cmd_comment(s: String, ws: List[String]) Unit:
        if ws.length() < 3:
            self.emit("error: usage: comment ID TEXT")
            return
        let r = self.resolve(ws[1])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_comment(r.id, rest_after(s, 2))
        self.emit(out_line(o))

    var fn cmd_delete(ws: List[String]) Unit:
        if ws.length() != 2:
            self.emit("error: usage: delete ID")
            return
        let r = self.resolve(ws[1])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let o = self.core_delete(r.id)
        self.emit(out_line(o))

    var fn cmd_show(ws: List[String]) Unit:
        if ws.length() != 2:
            self.emit("error: usage: show ID")
            return
        let r = self.resolve(ws[1])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let iss = self.load(r.id)
        self.emit("#{iss.id} " + iss.title)
        self.emit("  state: " + iss.state)
        self.emit("  priority: " + iss.priority)
        self.emit("  assignee: " + dash(iss.assignee.get("")))
        self.emit("  points: " + pts_text(iss.points))
        self.emit("  due: " + dash(iss.due.get("")))
        self.emit("  labels: " + labels_show(iss.labels))
        self.emit("  reporter: " + dash(iss.reporter.get("")))
        self.emit("  created: t={iss.created}, updated: t={iss.updated}")
        self.emit("  comments: {iss.comments.length()}")
        for c in iss.comments:
            self.emit("    [t={c.t} " + c.actor + "] " + c.text)

    var fn cmd_list(s: String) Unit:
        let lim = split_limit(rest_after(s, 1))
        if lim.err != "":
            self.emit("error: " + lim.err)
            return
        let sp = split_sort(lim.text)
        let e = self.run_list(sp.text, sp.sort, sp.has, lim.limit, lim.has)
        if e != "":
            self.emit("error: " + e)

    var fn cmd_bulk(s: String) Unit:
        let p = split_where(rest_after(s, 1))
        if not p.found or p.a == "":
            self.emit("error: usage: bulk ACTION... where QUERY")
            return
        let tk = tokens(p.a)
        if tk.err:
            self.emit("error: unterminated quote")
            return
        let it = tk.items
        let kind = it[0].clone()
        var shape_ok = true
        var usage = ""
        if kind == "move":
            shape_ok = it.length() == 2
            usage = "usage: bulk move STATE where QUERY"
        else if kind == "assign":
            shape_ok = it.length() == 2
            usage = "usage: bulk assign NAME where QUERY"
        else if kind == "label":
            shape_ok = it.length() >= 2
            usage = "usage: bulk label +label... where QUERY"
        else if kind == "set":
            shape_ok = it.length() >= 2
            usage = "usage: bulk set field=value... where QUERY"
        else:
            self.emit("error: unknown bulk action '" + kind + "'")
            return
        if not shape_ok:
            self.emit("error: " + usage)
            return
        let q = compile_query(p.b, self.view_names(), self.wf.states)
        if q.err != "":
            self.emit("error: " + q.err)
            return
        var ids = List[Int]()
        for id in 1..self.next_id:
            let iss = self.load(id)
            if iss.id == id:
                var ok = true
                if q.root >= 0:
                    ok = self.qmatch(q.nodes, q.root, iss)
                if ok:
                    ids.append(id)
        var good = 0
        var bad = 0
        for id in ids:
            let o = self.run_action(kind, it, id)
            if o.ok:
                good += 1
                self.emit(o.text)
            else:
                bad += 1
                self.emit("#{id} error: " + o.text)
        self.emit("bulk: {good} ok, {bad} failed")

    var fn cmd_log(ws: List[String]) Unit:
        var idx = 1
        var sel = 0
        var tail = -1
        if ws.length() > 1 and ws[1] != "tail":
            let v = parse_id_arg(ws[1])
            if v < 0:
                self.emit("error: bad issue id '" + ws[1] + "'")
                return
            if v >= self.next_id:
                self.emit("error: no such issue #{v}")
                return
            sel = v
            idx = 2
        if idx < ws.length():
            if ws[idx] != "tail" or idx + 1 >= ws.length():
                self.emit("error: usage: log [ID] [tail N]")
                return
            let tv = ws[idx + 1]
            if not valid_int(tv):
                self.emit("error: bad tail '" + tv + "'")
                return
            tail = tv.parse_int().get(0)
            idx += 2
        if idx != ws.length():
            self.emit("error: usage: log [ID] [tail N]")
            return
        var lines = List[String]()
        for e in self.log:
            if sel == 0 or e.id == sel:
                lines.append("t={e.t} " + e.actor + " #{e.id} " + e.detail)
        if tail >= 0:
            let n = lines.length()
            var start = 0
            if n > tail:
                start = n - tail
            lines = lines.slice(start, n).get()
        if lines.length() == 0:
            self.emit("(no log entries)")
            return
        for l in lines:
            self.emit(l)

    var fn cmd_report(s: String, ws: List[String]) Unit:
        if ws.length() < 2:
            self.emit("error: usage: report summary|workload|labels|timeline")
            return
        let sub = ws[1].clone()
        if sub == "summary":
            self.report_summary()
        else if sub == "workload":
            self.report_workload()
        else if sub == "labels":
            self.report_labels(rest_after(s, 2))
        else if sub == "timeline":
            self.report_timeline(ws)
        else:
            self.emit("error: usage: report summary|workload|labels|timeline")

    var fn report_summary() Unit:
        let all = self.all_issues()
        var open = 0
        var fin = 0
        var unassigned = 0
        var overdue = 0
        var openpts = 0
        for iss in all:
            if self.is_final(iss.state):
                fin += 1
            else:
                open += 1
                if iss.assignee.get("") == "":
                    unassigned += 1
                let d = iss.due.get("")
                if d != "" and d < self.today:
                    overdue += 1
                openpts += iss.points.get(0)
        self.emit("issues: {all.length()} (open {open}, final {fin})")
        self.emit("by state:")
        for st in self.wf.states.clone():
            var n = 0
            for iss in all:
                if iss.state == st:
                    n += 1
            self.emit("  " + st + ": {n}")
        self.emit("by priority:")
        for p in ["critical", "high", "medium", "low"]:
            var n = 0
            for iss in all:
                if iss.priority == p:
                    n += 1
            self.emit("  " + p + ": {n}")
        self.emit("unassigned: {unassigned}")
        self.emit("overdue: {overdue}")
        self.emit("open points: {openpts}")

    var fn report_workload() Unit:
        let all = self.all_issues()
        var keys = List[String]()
        var names = List[String]()
        var counts = List[Int]()
        var pts = List[Int]()
        var un_n = 0
        var un_p = 0
        for iss in all:
            if not self.is_final(iss.state):
                let a = iss.assignee.get("")
                let p = iss.points.get(0)
                if a == "":
                    un_n += 1
                    un_p += p
                else:
                    let key = a.lower()
                    var g = -1
                    var j = 0
                    while j < keys.length():
                        if keys[j] == key:
                            g = j
                            break
                        j += 1
                    if g < 0:
                        keys.append(key)
                        names.append(a.clone())
                        counts.append(0)
                        pts.append(0)
                        g = keys.length() - 1
                    counts[g] = counts[g] + 1
                    pts[g] = pts[g] + p
        if keys.length() == 0 and un_n == 0:
            self.emit("(no open issues)")
            return
        var order = List[Int]()
        for g in 0..keys.length():
            var pos = order.length()
            var j = 0
            while j < order.length():
                if group_before(g, order[j], pts, counts, keys):
                    pos = j
                    break
                j += 1
            order.insert(pos, g)
        for g in order:
            let pl = plural_issues(counts[g])
            let pp = pts[g]
            self.emit(names[g] + ": " + pl + ", {pp} points")
        if un_n > 0:
            let pl = plural_issues(un_n)
            self.emit("unassigned: " + pl + ", {un_p} points")

    var fn report_labels(filter: String) Unit:
        let q = compile_query(filter, self.view_names(), self.wf.states)
        if q.err != "":
            self.emit("error: " + q.err)
            return
        var names = List[String]()
        var counts = List[Int]()
        for iss in self.all_issues():
            var ok = true
            if q.root >= 0:
                ok = self.qmatch(q.nodes, q.root, iss)
            if ok:
                for l in iss.labels:
                    var g = -1
                    var j = 0
                    while j < names.length():
                        if names[j] == l:
                            g = j
                            break
                        j += 1
                    if g < 0:
                        names.append(l.clone())
                        counts.append(1)
                    else:
                        counts[g] = counts[g] + 1
        if names.length() == 0:
            self.emit("(no labels)")
            return
        var order = List[Int]()
        for g in 0..names.length():
            var pos = order.length()
            var j = 0
            while j < order.length():
                if label_before(g, order[j], names, counts):
                    pos = j
                    break
                j += 1
            order.insert(pos, g)
        for g in order:
            self.emit(names[g] + ": {counts[g]}")

    var fn report_timeline(ws: List[String]) Unit:
        if ws.length() != 3:
            self.emit("error: usage: report timeline ID")
            return
        let r = self.resolve(ws[2])
        if r.err != "":
            self.emit("error: " + r.err)
            return
        let iss = self.load(r.id)
        var state = self.wf.initial.clone()
        let created0 = iss.created
        var start = created0
        for e in self.log.clone():
            if e.id == r.id and e.detail.starts_with("state: "):
                let parts = e.detail.split(" -> ")
                let stop = e.t
                self.emit("{state}: t={start}..{stop} ({stop - start})")
                state = parts[1].clone()
                start = e.t
        let stop = self.clock
        self.emit("{state}: t={start}..{stop} ({stop - start})")

    var fn view_save(s: String, ws: List[String]) Unit:
        if ws.length() < 3:
            self.emit("error: usage: view save NAME QUERY")
            return
        let name = ws[2].clone()
        if not valid_view(name):
            self.emit("error: bad view name '" + name + "'")
            return
        let query = rest_after(s, 3)
        let lim = split_limit(query)
        if lim.err != "":
            self.emit("error: " + lim.err)
            return
        let sp = split_sort(lim.text)
        let q = compile_query(sp.text, self.view_names(), self.wf.states)
        if q.err != "":
            self.emit("error: " + q.err)
            return
        if sp.has:
            let k = parse_sort(sp.sort)
            if k.err != "":
                self.emit("error: " + k.err)
                return
        if self.reaches(q.refs, name):
            self.emit("error: view '" + name + "' would reference itself")
            return
        self.views[name.clone()] = query.clone()
        self.emit("saved view " + name)

    var fn view_run(s: String, ws: List[String]) Unit:
        if ws.length() < 3:
            self.emit("error: usage: view run NAME [sort FIELDS] [limit N]")
            return
        let name = ws[2].clone()
        if not self.view_names().contains(name):
            self.emit("error: unknown view '" + name + "'")
            return
        let lim = split_limit(rest_after(s, 3))
        if lim.err != "":
            self.emit("error: " + lim.err)
            return
        let sp = split_sort(lim.text)
        if sp.text != "":
            self.emit("error: unexpected '" + sp.text + "'")
            return
        let stored = self.views.get(name).get("")
        var sl = split_limit(stored)
        var ss = split_sort(sl.text)
        var sort_text = ss.sort.clone()
        var has_sort = ss.has
        if sp.has:
            sort_text = sp.sort.clone()
            has_sort = true
        var limit = sl.limit
        var has_limit = sl.has
        if lim.has:
            limit = lim.limit
            has_limit = true
        let e = self.run_list(ss.text.clone(), sort_text, has_sort, limit, has_limit)
        if e != "":
            self.emit("error: " + e)

    var fn view_delete(ws: List[String]) Unit:
        if ws.length() != 3:
            self.emit("error: usage: view delete NAME")
            return
        let name = ws[2].clone()
        if not self.view_names().contains(name):
            self.emit("error: unknown view '" + name + "'")
            return
        let names = self.view_names().sorted()
        for m in names:
            if m != name:
                let refs = compile_query(filter_part(self.views.get(m).get("")), self.view_names(), self.wf.states).refs
                if self.reaches(refs, name):
                    self.emit("error: view '" + name + "' is used by '" + m + "'")
                    return
        self.views.remove(name.clone())
        self.emit("deleted view " + name)

    var fn cmd_view(s: String, ws: List[String]) Unit:
        let usage = "error: usage: view save|run|list|show|delete"
        if ws.length() < 2:
            self.emit(usage)
            return
        let sub = ws[1].clone()
        if sub == "save":
            self.view_save(s, ws)
        else if sub == "run":
            self.view_run(s, ws)
        else if sub == "list":
            if ws.length() != 2:
                self.emit(usage)
                return
            let names = self.view_names().sorted()
            if names.length() == 0:
                self.emit("(no views)")
                return
            for n in names:
                self.emit(n + ": " + self.views.get(n).get(""))
        else if sub == "show":
            if ws.length() != 3:
                self.emit("error: usage: view show NAME")
                return
            let name = ws[2].clone()
            if not self.view_names().contains(name):
                self.emit("error: unknown view '" + name + "'")
                return
            self.emit(name + ": " + self.views.get(name).get(""))
        else if sub == "delete":
            self.view_delete(ws)
        else:
            self.emit(usage)

    var fn dispatch(s: String) Unit:
        let ws = words(s)
        let cmd = ws[0].clone()
        if cmd == "actor":
            self.cmd_actor(ws)
        else if cmd == "today":
            self.cmd_today(ws)
        else if cmd == "create":
            self.cmd_create(s)
        else if cmd == "edit":
            self.cmd_edit(s)
        else if cmd == "assign":
            self.cmd_assign(s)
        else if cmd == "label":
            self.cmd_label(s)
        else if cmd == "move":
            self.cmd_move(s, ws)
        else if cmd == "comment":
            self.cmd_comment(s, ws)
        else if cmd == "delete":
            self.cmd_delete(ws)
        else if cmd == "show":
            self.cmd_show(ws)
        else if cmd == "list":
            self.cmd_list(s)
        else if cmd == "bulk":
            self.cmd_bulk(s)
        else if cmd == "log":
            self.cmd_log(ws)
        else if cmd == "report":
            self.cmd_report(s, ws)
        else if cmd == "view":
            self.cmd_view(s, ws)
        else:
            self.emit("error: unknown command '" + cmd + "'")

fn prio_rank(s: String) Int:
    let ps = PRIORITIES
    for k in 0..ps.length():
        if ps[k] == s:
            return k
    return -1

fn out_line(o: Out) String:
    if o.ok:
        return o.text
    return "error: " + o.text

fn issue_row(iss: Issue) String:
    let a = dash(iss.assignee.get(""))
    let p = pts_text(iss.points)
    let d = dash(iss.due.get(""))
    let l = labels_text(iss.labels)
    return "#{iss.id} | " + iss.state + " | " + iss.priority + " | " + a + " | " + p + " | " + d + " | " + l + " | " + iss.title

export fn main() Int:
    let raw = read_lines(stdin()).get()
    var app = App(wf: Workflow(defined: false, states: List[String](), index: Map[String, Int](), initial: "", finals: List[String](), trans: Map[String, List[Trans]](), ntrans: 0), clock: 0, actor: "system", today: "1970-01-01", next_id: 1, issues: Map[Int, Issue](), log: List[LogEntry](), views: Map[String, String](), out: List[String]())
    var lines = List[String]()
    for r in raw:
        lines.append(r.trim_end())
    let n = lines.length()
    var i = 0
    while i < n:
        let line = lines[i].clone()
        let s = line.trim()
        i += 1
        if s == "" or s.starts_with("#"):
            continue
        app.emit("> " + line)
        let ws = words(s)
        if ws[0] == "workflow":
            var body = List[String]()
            while i < n:
                let b = lines[i].trim()
                i += 1
                if b == "end":
                    break
                body.append(b)
            app.cmd_workflow(body)
        else:
            app.dispatch(s)
    if app.out.length() > 0:
        stdout().write(app.out.join("\n") + "\n").get()
    return 0
