from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

let K_END = -1
let K_OPEN = 0
let K_CLOSE = 1
let K_WORD = 2
let K_TERM = 3
let K_AND = 4
let K_OR = 5
let K_NOT = 6

type Comment:
    t: Int
    actor: String
    text: String

type Issue:
    id: Int
    title: String
    state: String
    priority: String
    assignee: Optional[String]
    reporter: Optional[String]
    points: Optional[Int]
    due: Optional[String]
    labels: List[String]
    comments: List[Comment]
    created: Int
    updated: Int

type Transition:
    src: String
    dst: String
    guards: List[String]

type Workflow:
    initial: String
    states: List[String]
    finals: List[String]
    transitions: List[Transition]

type WfParse:
    err: String
    wf: Workflow

type LogEntry:
    t: Int
    actor: String
    id: Int
    detail: String

type Expr:
    case Cmp(field: String, op: String, values: List[String])
    case Both(left: Expr, right: Expr)
    case Either(left: Expr, right: Expr)
    case Negate(inner: Expr)
    case Everything

type Env:
    today: String
    finals: List[String]
    states: List[String]

type SortKey:
    name: String
    desc: Bool

type SortParse:
    err: String
    keys: List[SortKey]

type Plan:
    err: String
    expr: Expr
    keys: List[SortKey]
    limit: Int

type Parts:
    filter: String
    has_sort: Bool
    sort: String
    has_limit: Bool
    limit: String

type QTok:
    kind: Int
    text: String
    field: String
    op: String
    quoted: Bool

type QLex:
    toks: List[QTok]
    err: String

type ParseOut:
    expr: Expr
    err: String

type Parser:
    toks: List[QTok]
    pos: Int
    err: String
    states: List[String]
    views: Map[String, String]

type Quoted:
    value: String
    next: Int
    ok: Bool

type Toks:
    items: List[String]
    ok: Bool

type Group:
    name: String
    key: String
    count: Int
    points: Int

type LabelCount:
    name: String
    count: Int

type Tracker:
    wf: Workflow
    has_wf: Bool
    issues: List[Issue]
    next_id: Int
    clock: Int
    actor: String
    today: String
    log: List[LogEntry]
    views: Map[String, String]

# ---------- output and scalar helpers ----------

def emit(line: String) -> Unit:
    stdout().write(line + "\n").get()

def sub(s: String, a: Int, b: Int) -> String:
    return s.slice_scalars(a, b).get()

def is_ws(c: Int) -> Bool:
    return c == 32 or c == 9

def is_lower(c: Int) -> Bool:
    return c >= 97 and c <= 122

def is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57

def all_digits(s: String) -> Bool:
    if s.scalar_length() == 0:
        return False

    for i in 0..s.scalar_length():
        if not is_digit(s.scalar_at(i)):
            return False
    return True

# Saturates well above the 1000000 limit so huge values stay comparable.
def to_num(s: String) -> Int:
    var n = 0

    for i in 0..s.scalar_length():
        n = n * 10 + (s.scalar_at(i) - 48)
        if n > 1000000000000:
            return 1000000000000

    return n

# Integer rule: decimal digits, no sign, no leading zeros, at most 1000000.
def int_rule(s: String) -> Bool:
    if not all_digits(s):
        return False
    if s.scalar_length() > 1 and s.scalar_at(0) == 48:
        return False

    return to_num(s) <= 1000000

def valid_state(s: String) -> Bool:
    let n = s.scalar_length()
    if n == 0 or not is_lower(s.scalar_at(0)):
        return False

    for i in 1..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95):
            return False

    return True

def valid_view_name(s: String) -> Bool:
    let n = s.scalar_length()
    if n == 0 or not is_lower(s.scalar_at(0)):
        return False

    for i in 1..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95 or c == 45):
            return False

    return True

def valid_label(s: String) -> Bool:
    let n = s.scalar_length()
    if n == 0:
        return False

    for i in 0..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95 or c == 45):
            return False

    return True

def days_in(month: Int, year: Int) -> Int:
    if month == 2:
        if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0:
            return 29

        return 28

    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30

    return 31

def valid_date(s: String) -> Bool:
    if s.scalar_length() != 10:
        return False

    for i in 0..10:
        let c = s.scalar_at(i)

        if i == 4 or i == 7:
            if c != 45:
                return False
        elif not is_digit(c):
            return False

    let year = to_num(sub(s, 0, 4))
    let month = to_num(sub(s, 5, 7))
    let day = to_num(sub(s, 8, 10))
    if year < 1 or month < 1 or month > 12:
        return False

    return day >= 1 and day <= days_in(month, year)

def cmp_int(a: Int, b: Int) -> Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

def cmp_str(a: String, b: String) -> Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

def words(s: String) -> List[String]:
    var res = List[String]()
    let n = s.scalar_length()
    var i = 0

    while i < n:
        if is_ws(s.scalar_at(i)):
            i += 1
        else:
            let start = i
            while i < n and not is_ws(s.scalar_at(i)):
                i += 1
            res.append(sub(s, start, i))

    return res

# Skips n whitespace-separated words and returns the rest, leading blanks removed.
def after_words(s: String, n: Int) -> String:
    let len = s.scalar_length()
    var i = 0
    var k = 0

    while k < n:
        while i < len and is_ws(s.scalar_at(i)):
            i += 1
        while i < len and not is_ws(s.scalar_at(i)):
            i += 1
        k += 1

    while i < len and is_ws(s.scalar_at(i)):
        i += 1
    return sub(s, i, len)

def rest_list(items: List[String], k: Int) -> List[String]:
    var res = List[String]()
    for i in k..items.length():
        res.append(items[i].clone())
    return res

def strip_cr(s: String) -> String:
    let n = s.scalar_length()
    if n > 0 and s.scalar_at(n - 1) == 13:
        return sub(s, 0, n - 1)

    return s

def first_eq(s: String) -> Int:
    for i in 0..s.scalar_length():
        if s.scalar_at(i) == 61:
            return i
    return -1

def field_of(tok: String) -> String:
    return sub(tok, 0, first_eq(tok))

def value_of(tok: String) -> String:
    return sub(tok, first_eq(tok) + 1, tok.scalar_length())

# Splits on whitespace where a double quote opens a quoted section inside a token.
def split_tokens(s: String) -> Toks:
    var items = List[String]()
    var cur = ""
    var started = False
    var quoted = False
    let n = s.scalar_length()
    var i = 0

    while i < n:
        let c = s.scalar_at(i)

        if quoted:
            if c == 34:
                quoted = False
            elif (
                c == 92
                and i + 1 < n
                and (
                    s.scalar_at(i + 1) == 34
                    or s.scalar_at(i + 1) == 92
                )
            ):
                i += 1
                cur = cur + sub(s, i, i + 1)
            else:
                cur = cur + sub(s, i, i + 1)
        elif c == 34:
            quoted = True
            started = True
        elif is_ws(c):
            if started:
                items.append(cur)
                cur = ""
                started = False
        else:
            started = True
            cur = cur + sub(s, i, i + 1)

        i += 1

    if quoted:
        return Toks(items: items, ok: False)

    if started:
        items.append(cur)
    return Toks(items: items, ok: True)

# Finds the standalone word `where` outside quotes; returns its start or -1.
def find_where(s: String) -> Int:
    let n = s.scalar_length()
    var i = 0
    var quoted = False
    var start = -1

    while i < n:
        let c = s.scalar_at(i)

        if quoted:
            if (
                c == 92
                and i + 1 < n
                and (
                    s.scalar_at(i + 1) == 34
                    or s.scalar_at(i + 1) == 92
                )
            ):
                i += 1
            elif c == 34:
                quoted = False
        elif is_ws(c):
            if start >= 0 and sub(s, start, i) == "where":
                return start

            start = -1
        else:
            if start < 0:
                start = i
            if c == 34:
                quoted = True

        i += 1

    if start >= 0 and sub(s, start, n) == "where":
        return start

    return -1

# Reads a quoted section starting at the opening quote index `start`.
def read_quoted(s: String, start: Int) -> Quoted:
    let n = s.scalar_length()
    var i = start + 1
    var out = ""

    while i < n:
        let c = s.scalar_at(i)
        if c == 34:
            return Quoted(value: out, next: i + 1, ok: True)

        if (
            c == 92
            and i + 1 < n
            and (s.scalar_at(i + 1) == 34 or s.scalar_at(i + 1) == 92)
        ):
            out = out + sub(s, i + 1, i + 2)
            i += 2
        else:
            out = out + sub(s, i, i + 1)
            i += 1

    return Quoted(value: out, next: n, ok: False)

# ---------- field validation and values ----------

def is_known_field(f: String) -> Bool:
    return (
        f == "title"
        or f == "priority"
        or f == "assignee"
        or f == "points"
        or f == "due"
        or f == "labels"
        or f == "reporter"
    )

def check_field(tok: String) -> String:
    let p = first_eq(tok)
    if p <= 0:
        return "expected field=value, got '" + tok + "'"

    let field = field_of(tok)
    let value = value_of(tok)
    let clear = value == "none"
    if field == "state":
        return "use move to change state"
    if not is_known_field(field):
        return "unknown field '" + field + "'"

    if field == "title":
        if value.trim() == "":
            return "empty title"
    elif field == "priority":
        if not (
            value == "low"
            or value == "medium"
            or value == "high"
            or value == "critical"
        ):
            return "bad priority '" + value + "'"
    elif field == "points":
        if not clear and not int_rule(value):
            return "bad points '" + value + "'"
    elif field == "due":
        if not clear and not valid_date(value):
            return "bad date '" + value + "'"
    elif field == "labels":
        if not clear:
            for part in value.split(","):
                let lab = part.lower()
                if not valid_label(lab):
                    return "bad label '" + lab + "'"
    elif field == "assignee":
        if not clear and value.trim() == "":
            return "empty assignee"
    elif field == "reporter":
        if not clear and value.trim() == "":
            return "empty reporter"

    return ""

def opt_str(o: Optional[String]) -> String:
    return o.get("")

def opt_int(o: Optional[Int]) -> Int:
    return o.get(-1)

def show_text(o: Optional[String]) -> String:
    let v = opt_str(o)
    if v == "":
        return "-"

    return v

def show_points(o: Optional[Int]) -> String:
    let v = opt_int(o)
    if v < 0:
        return "-"

    return v.to_string()

def labels_text(labels: List[String], sep: String) -> String:
    if labels.length() == 0:
        return "-"

    return labels.join(sep)

def normalize_labels(items: List[String]) -> List[String]:
    var seen = Set[String]()
    for l in items:
        seen.add(l.lower())
    return seen.values().sorted()

impl Issue:
    var def set_field(field: String, value: String) -> Unit:
        let clear = value == "none"

        if field == "title":
            self.title = value
        elif field == "priority":
            self.priority = value
        elif field == "assignee":
            if clear:
                self.assignee = none
            else:
                self.assignee = value
        elif field == "points":
            if clear:
                self.points = none
            else:
                self.points = to_num(value)
        elif field == "due":
            if clear:
                self.due = none
            else:
                self.due = value
        elif field == "labels":
            if clear:
                self.labels = List[String]()
            else:
                self.labels = normalize_labels(value.split(","))
        elif field == "reporter":
            if clear:
                self.reporter = none
            else:
                self.reporter = value

def diff_issue(a: Issue, b: Issue) -> List[String]:
    var res = List[String]()
    if a.title != b.title:
        res.append("title: " + a.title + " -> " + b.title)
    if a.priority != b.priority:
        res.append("priority: " + a.priority + " -> " + b.priority)
    if opt_str(a.assignee) != opt_str(b.assignee):
        res.append(
            "assignee: " + show_text(a.assignee) + " -> " + show_text(
                b.assignee
            )
        )
    if opt_int(a.points) != opt_int(b.points):
        res.append("points: " + show_points(a.points) + " -> " + show_points(b.points))
    if opt_str(a.due) != opt_str(b.due):
        res.append("due: " + show_text(a.due) + " -> " + show_text(b.due))
    if a.labels != b.labels:
        res.append(
            "labels: " + labels_text(a.labels, ",") + " -> " + labels_text(
                b.labels, ","
            )
        )
    if opt_str(a.reporter) != opt_str(b.reporter):
        res.append(
            "reporter: " + show_text(a.reporter) + " -> " + show_text(
                b.reporter
            )
        )
    return res

def parse_id(tok: String) -> Int:
    var s = tok
    if s.starts_with("#"):
        s = sub(s, 1, s.scalar_length())
    if not all_digits(s):
        return -1

    let v = to_num(s)
    if v < 1:
        return -1

    return v

def unmet_guards(iss: Issue, guards: List[String]) -> List[String]:
    var res = List[String]()

    for g in guards:
        var ok = True

        if g == "assignee":
            ok = opt_str(iss.assignee) != ""
        elif g == "points":
            ok = opt_int(iss.points) >= 0
        elif g == "due":
            ok = opt_str(iss.due) != ""
        elif g == "labels":
            ok = iss.labels.length() > 0
        elif g == "reporter":
            ok = opt_str(iss.reporter) != ""

        if not ok:
            res.append(g)

    return res

# ---------- workflow definition ----------

def add_state(var states: List[String], name: String) -> Unit:
    if not states.contains(name):
        states.append(name)

def guard_ok(g: String) -> Bool:
    return (
        g == "assignee"
        or g == "points"
        or g == "due"
        or g == "labels"
        or g == "reporter"
    )

def wf_fail(msg: String) -> WfParse:
    return WfParse(err: msg, wf: empty_workflow())

def parse_workflow(block: List[String]) -> WfParse:
    var states = List[String]()
    var finals = List[String]()
    var trans = List[Transition]()
    var initial = ""
    var has_initial = False
    var err = ""

    for raw in block:
        let line = raw.trim()
        if err == "" and line != "" and not line.starts_with("#"):
            err = wf_line(
                line, var states, var finals, var trans, var initial, var has_initial
            )

    if err != "":
        return wf_fail(err)
    if not has_initial:
        return wf_fail("workflow: initial state missing")

    for t in trans:
        if finals.contains(t.src):
            return wf_fail(
                "workflow: '" + t.src + "' is final and cannot have transitions"
            )
    return WfParse(
        err: "",
        wf: Workflow(
            initial: initial, states: states, finals: finals, transitions: trans
        )
    )

# Applies one non-blank, non-comment workflow line; returns an error message or "".
def wf_line(
    line: String,
    var states: List[String],
    var finals: List[String],
    var trans: List[Transition],
    var initial: String,
    var has_initial: Bool
) -> String:
    if line.starts_with("initial:"):
        let name = sub(line, 8, line.scalar_length()).trim()
        if not valid_state(name):
            return "workflow: bad state name '" + name + "'"
        if has_initial:
            return "workflow: initial state defined twice"

        has_initial = True
        initial = name.clone()
        add_state(var states, name)
        return ""

    if line.starts_with("final:"):
        for part in sub(line, 6, line.scalar_length()).split(","):
            let name = part.trim()
            if not valid_state(name):
                return "workflow: bad state name '" + name + "'"

            add_state(var states, name.clone())
            if not finals.contains(name):
                finals.append(name.clone())

        return ""

    if line.contains("->"):
        let parts = line.split("->")
        if parts.length() != 2:
            return "workflow: bad line '" + line + "'"

        let src = parts[0].trim()
        if not valid_state(src):
            return "workflow: bad state name '" + src + "'"

        add_state(var states, src.clone())

        for entry in parts[1].split(","):
            let ws = words(entry)
            var dst = ""
            var guards = List[String]()

            if ws.length() == 1:
                dst = ws[0].clone()
            elif ws.length() == 3 and ws[1] == "requires":
                dst = ws[0].clone()
                guards = ws[2].split("+")
            else:
                return "workflow: bad line '" + line + "'"

            if not valid_state(dst):
                return "workflow: bad state name '" + dst + "'"

            for g in guards:
                if not guard_ok(g):
                    return "workflow: bad guard field '" + g + "'"
            add_state(var states, dst.clone())
            trans.append(Transition(src: src.clone(), dst: dst, guards: guards))

        return ""

    return "workflow: bad line '" + line + "'"

def empty_workflow() -> Workflow:
    return Workflow(
        initial: "", states: List[String](), finals: List[String](),
        transitions: List[Transition]()
    )

# ---------- query language ----------

def ident_end(s: String, i: Int) -> Int:
    var j = i
    let n = s.scalar_length()
    while j < n and (is_lower(s.scalar_at(j)) or s.scalar_at(j) == 95):
        j += 1
    return j

def op_at(s: String, i: Int) -> String:
    let n = s.scalar_length()

    if i + 1 < n:
        let two = sub(s, i, i + 2)
        if two == "!=" or two == "<=" or two == ">=":
            return two

    if i < n:
        let c = s.scalar_at(i)
        if c == 58 or c == 60 or c == 62 or c == 126:
            return sub(s, i, i + 1)

    return ""

def word_kind(raw: String) -> Int:
    if raw == "AND":
        return K_AND
    if raw == "OR":
        return K_OR
    if raw == "NOT":
        return K_NOT

    return K_WORD

def lex_filter(s: String) -> QLex:
    var toks = List[QTok]()
    let n = s.scalar_length()
    var i = 0

    while i < n:
        let c = s.scalar_at(i)

        if is_ws(c):
            i += 1
        elif c == 40 or c == 41:
            var kind = K_OPEN
            if c == 41:
                kind = K_CLOSE
            toks.append(
                QTok(
                    kind: kind, text: sub(s, i, i + 1), field: "", op: "", quoted: False
                )
            )
            i += 1
        else:
            let e = ident_end(s, i)
            let op = op_at(s, e)

            if e > i and op != "":
                let vstart = e + op.scalar_length()
                let field = sub(s, i, e)

                if vstart < n and s.scalar_at(vstart) == 34:
                    let q = read_quoted(s, vstart)
                    if not q.ok:
                        return QLex(toks: toks, err: "query: unterminated quote")

                    toks.append(
                        QTok(
                            kind: K_TERM, text: q.value.clone(), field: field, op: op,
                            quoted: True
                        )
                    )
                    i = q.next
                else:
                    var j = vstart
                    while (
                        j < n
                        and not is_ws(s.scalar_at(j))
                        and s.scalar_at(j) != 40
                        and s.scalar_at(j) != 41
                    ):
                        j += 1
                    toks.append(
                        QTok(
                            kind: K_TERM, text: sub(s, vstart, j), field: field, op: op,
                            quoted: False
                        )
                    )
                    i = j
            else:
                var j = i

                while (
                    j < n
                    and not is_ws(s.scalar_at(j))
                    and s.scalar_at(j) != 40
                    and s.scalar_at(j) != 41
                ):
                    if s.scalar_at(j) == 34:
                        let q = read_quoted(s, j)
                        if not q.ok:
                            return QLex(toks: toks, err: "query: unterminated quote")

                        j = q.next
                    else:
                        j += 1

                let raw = sub(s, i, j)
                toks.append(
                    QTok(
                        kind: word_kind(raw), text: raw, field: "", op: "",
                        quoted: False
                    )
                )
                i = j

    return QLex(toks: toks, err: "")

# Names of the views a stored query references through `view:` terms.
def collect_refs(text: String) -> List[String]:
    var res = List[String]()
    let lx = lex_filter(split_query(text).filter)
    for t in lx.toks:
        if t.kind == K_TERM and t.field == "view":
            res.append(t.text.clone())
    return res

def op_allowed(field: String, op: String) -> Bool:
    if field == "text":
        return op == "~"
    if field == "state":
        return op == ":" or op == "!="
    if field == "is" or field == "has" or field == "view":
        return op == ":"
    if (
        field == "title"
        or field == "assignee"
        or field == "reporter"
        or field == "labels"
    ):
        return op == ":" or op == "!=" or op == "~"

    return op != "~"

def known_field(field: String) -> Bool:
    return (
        field == "id"
        or field == "created"
        or field == "updated"
        or field == "points"
        or field == "title"
        or field == "assignee"
        or field == "reporter"
        or field == "text"
        or field == "state"
        or field == "priority"
        or field == "due"
        or field == "labels"
        or field == "is"
        or field == "has"
        or field == "view"
    )

def priority_rank(p: String) -> Int:
    if p == "low":
        return 0
    if p == "medium":
        return 1
    if p == "high":
        return 2

    return 3

impl Parser:
    def kind() -> Int:
        if self.pos >= self.toks.length():
            return K_END

        return self.toks[self.pos].kind

    def value_error(field: String, op: String, v: String) -> String:
        let bad = "query: bad value '" + v + "' for field '" + field + "'"

        if field == "id" or field == "created" or field == "updated":
            if not int_rule(v):
                return bad
        elif field == "points":
            if not ((v == "none" and (op == ":" or op == "!=")) or int_rule(v)):
                return bad
        elif field == "due":
            if not ((v == "none" and (op == ":" or op == "!=")) or valid_date(v)):
                return bad
        elif field == "priority":
            if not (v == "low" or v == "medium" or v == "high" or v == "critical"):
                return bad
        elif field == "state":
            if not self.states.contains(v):
                return bad
        elif field == "is":
            if not (v == "open" or v == "final" or v == "overdue" or v == "unassigned"):
                return bad
        elif field == "has":
            if not (
                v == "assignee"
                or v == "due"
                or v == "points"
                or v == "labels"
                or v == "comments"
                or v == "reporter"
            ):
                return bad
        elif field == "view":
            if not self.views.contains(v):
                return "query: unknown view '" + v + "'"

        return ""

    var def term(tok: QTok) -> Expr:
        var field = tok.field.clone()
        if field == "label":
            field = "labels"

        if not known_field(field):
            self.err = "query: unknown field '" + field + "'"
            return Everything

        let op = tok.op

        if not op_allowed(field, op):
            self.err = "query: bad operator '" + op + "' for field '" + field + "'"
            return Everything

        let ordered = op == "<" or op == "<=" or op == ">" or op == ">="
        var values = List[String]()

        if (
            not tok.quoted
            and not ordered
            and field != "view"
            and tok.text.contains("|")
        ):
            values = tok.text.split("|")
        else:
            values.append(tok.text.clone())

        for v in values:
            let e = self.value_error(field, op, v)

            if e != "":
                self.err = e
                return Everything

        if field == "view":
            let vtext = self.views.get(values[0]).get("")
            let inner = parse_filter(
                split_query(vtext).filter, self.states.clone(), self.views.clone()
            )

            if inner.err != "":
                self.err = inner.err.clone()
                return Everything

            return inner.expr.clone()

        return Cmp(field: field, op: op.clone(), values: values)

    var def parse_unary() -> Expr:
        let k = self.kind()

        if k == K_END:
            self.err = "query: unexpected end of query"
            return Everything

        if k == K_NOT:
            self.pos += 1

            let inner = self.parse_unary()
            return Negate(inner: inner)

        if k == K_OPEN:
            self.pos += 1

            let e = self.parse_or()
            if self.err != "":
                return e

            if self.kind() == K_END:
                self.err = "query: unexpected end of query"
                return e

            if self.kind() != K_CLOSE:
                self.err = "query: unexpected token '" + self.toks[self.pos].text + "'"
                return e

            self.pos += 1
            return e

        if k == K_TERM:
            let tok = self.toks[self.pos].clone()
            self.pos += 1
            return self.term(tok)

        self.err = "query: unexpected token '" + self.toks[self.pos].text + "'"
        return Everything

    def starts_operand() -> Bool:
        let k = self.kind()
        return k == K_AND or k == K_NOT or k == K_OPEN or k == K_TERM or k == K_WORD

    var def parse_and() -> Expr:
        var left = self.parse_unary()

        while self.err == "" and self.starts_operand():
            if self.kind() == K_AND:
                self.pos += 1

            let right = self.parse_unary()
            left = Both(left: left, right: right)

        return left

    var def parse_or() -> Expr:
        var left = self.parse_and()

        while self.err == "" and self.kind() == K_OR:
            self.pos += 1

            let right = self.parse_and()
            left = Either(left: left, right: right)

        return left

def parse_filter(
    text: String,
    states: List[String],
    views: Map[String, String]
) -> ParseOut:
    let lx = lex_filter(text)
    if lx.err != "":
        return ParseOut(expr: Everything, err: lx.err.clone())
    if lx.toks.length() == 0:
        return ParseOut(expr: Everything, err: "")

    var p = Parser(toks: lx.toks.clone(), pos: 0, err: "", states: states, views: views)
    let e = p.parse_or()
    if p.err == "" and p.pos < lx.toks.length():
        p.err = "query: unexpected token '" + lx.toks[p.pos].text + "'"
    return ParseOut(expr: e, err: p.err.clone())

def last_space(s: String) -> Int:
    var i = s.scalar_length() - 1

    while i >= 0:
        if is_ws(s.scalar_at(i)):
            return i

        i -= 1

    return -1

# Splits a query into filter, sort clause and limit clause (textual, as the spec says).
def split_query(raw: String) -> Parts:
    let text = raw.trim()
    var filter = text.clone()
    var has_limit = False
    var limit = ""
    let n = text.scalar_length()
    let w = last_space(text)

    if w >= 0:
        let arg = sub(text, w + 1, n)
        let prefix = sub(text, 0, w).trim_end()
        let m = prefix.scalar_length()

        if (
            m >= 5
            and sub(prefix, m - 5, m) == "limit"
            and (m == 5 or is_ws(prefix.scalar_at(m - 6)))
        ):
            has_limit = True
            limit = arg
            filter = sub(prefix, 0, m - 5).trim_end()

    var has_sort = False
    var sort = ""
    let fl = filter.scalar_length()
    var i = 0

    while i + 4 < fl:
        if (
            sub(filter, i, i + 4) == "sort"
            and (i == 0 or is_ws(filter.scalar_at(i - 1)))
            and is_ws(filter.scalar_at(i + 4))
        ):
            has_sort = True
            sort = sub(filter, i + 4, fl).trim()
            filter = sub(filter, 0, i).trim_end()
            break

        i += 1

    return Parts(
        filter: filter, has_sort: has_sort, sort: sort, has_limit: has_limit,
        limit: limit
    )

def sort_field_ok(name: String) -> Bool:
    return (
        name == "id"
        or name == "created"
        or name == "updated"
        or name == "priority"
        or name == "points"
        or name == "state"
        or name == "title"
        or name == "assignee"
        or name == "reporter"
        or name == "due"
    )

def parse_sort(text: String) -> SortParse:
    var keys = List[SortKey]()

    for w in words(text.replace(",", " ")):
        var name = w.clone()
        var desc = False

        if w.starts_with("-"):
            desc = True
            name = sub(w, 1, w.scalar_length())

        if not sort_field_ok(name):
            return SortParse(err: "bad sort field '" + name + "'", keys: keys)

        keys.append(SortKey(name: name, desc: desc))

    return SortParse(err: "", keys: keys)

def eval_text(a: String, v: String, op: String) -> Bool:
    if op == "~":
        return a.lower().contains(v.lower())

    return a.lower() == v.lower()

def eval_alt(field: String, op: String, v: String, iss: Issue, env: Env) -> Bool:
    if field == "id":
        return cmp_op(iss.id, to_num(v), op)
    if field == "created":
        return cmp_op(iss.created, to_num(v), op)
    if field == "updated":
        return cmp_op(iss.updated, to_num(v), op)

    if field == "points":
        if v == "none":
            return opt_int(iss.points) < 0 and op == ":"
        if opt_int(iss.points) < 0:
            return False

        return cmp_op(opt_int(iss.points), to_num(v), op)

    if field == "due":
        if v == "none":
            return opt_str(iss.due) == "" and op == ":"
        if opt_str(iss.due) == "":
            return False

        return cmp_op_str(opt_str(iss.due), v, op)

    if field == "priority":
        return cmp_op(priority_rank(iss.priority), priority_rank(v), op)
    if field == "title":
        return eval_text(iss.title, v, op)

    if field == "assignee":
        if opt_str(iss.assignee) == "":
            return v == "none" and op == ":"

        return eval_text(opt_str(iss.assignee), v, op)

    if field == "reporter":
        if opt_str(iss.reporter) == "":
            return v == "none" and op == ":"

        return eval_text(opt_str(iss.reporter), v, op)

    if field == "labels":
        if op == "~":
            for l in iss.labels:
                if l.contains(v.lower()):
                    return True
            return False

        if v == "none":
            return iss.labels.length() == 0

        return iss.labels.contains(v.lower())

    if field == "text":
        if iss.title.lower().contains(v.lower()):
            return True

        for c in iss.comments:
            if c.text.lower().contains(v.lower()):
                return True
        return False

    if field == "state":
        return iss.state == v

    if field == "is":
        if v == "open":
            return not env.finals.contains(iss.state)
        if v == "final":
            return env.finals.contains(iss.state)
        if v == "overdue":
            return (
                not env.finals.contains(iss.state)
                and opt_str(iss.due) != ""
                and opt_str(iss.due) < env.today
            )
        if v == "unassigned":
            return opt_str(iss.assignee) == ""

        return False

    if field == "has":
        if v == "assignee":
            return opt_str(iss.assignee) != ""
        if v == "due":
            return opt_str(iss.due) != ""
        if v == "points":
            return opt_int(iss.points) >= 0
        if v == "labels":
            return iss.labels.length() > 0
        if v == "comments":
            return iss.comments.length() > 0
        if v == "reporter":
            return opt_str(iss.reporter) != ""

    return False

def cmp_op(a: Int, b: Int, op: String) -> Bool:
    if op == ":":
        return a == b
    if op == "<":
        return a < b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == ">=":
        return a >= b

    return a != b

def cmp_op_str(a: String, b: String, op: String) -> Bool:
    if op == ":":
        return a == b
    if op == "<":
        return a < b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == ">=":
        return a >= b

    return a != b

def eval_cmp(
    field: String,
    op: String,
    values: List[String],
    iss: Issue,
    env: Env
) -> Bool:
    if op == "!=":
        for v in values:
            if eval_alt(field, ":", v, iss, env):
                return False
        return True

    if op == "<" or op == "<=" or op == ">" or op == ">=":
        return eval_alt(field, op, values[0], iss, env)

    for v in values:
        if eval_alt(field, op, v, iss, env):
            return True
    return False

def eval_expr(e: Expr, iss: Issue, env: Env) -> Bool:
    match e:
        case Cmp(field, op, values):
            return eval_cmp(field, op, values, iss, env)
        case Both(left, right):
            return eval_expr(left, iss, env) and eval_expr(right, iss, env)
        case Either(left, right):
            return eval_expr(left, iss, env) or eval_expr(right, iss, env)
        case Negate(inner):
            return not eval_expr(inner, iss, env)
        case Everything:
            return True

def index_in(items: List[String], value: String) -> Int:
    for i in 0..items.length():
        if items[i] == value:
            return i
    return -1

def field_cmp(a: Issue, b: Issue, name: String, env: Env) -> Int:
    if name == "id":
        return cmp_int(a.id, b.id)
    if name == "created":
        return cmp_int(a.created, b.created)
    if name == "updated":
        return cmp_int(a.updated, b.updated)
    if name == "priority":
        return cmp_int(priority_rank(a.priority), priority_rank(b.priority))
    if name == "state":
        return cmp_int(index_in(env.states, a.state), index_in(env.states, b.state))
    if name == "title":
        return cmp_str(a.title.lower(), b.title.lower())

    if name == "points":
        let pa = opt_int(a.points)
        let pb = opt_int(b.points)
        if pa < 0 and pb < 0:
            return 0
        if pa < 0:
            return 1
        if pb < 0:
            return -1

        return cmp_int(pa, pb)

    if name == "assignee" or name == "reporter" or name == "due":
        var sa = opt_str(a.assignee)
        var sb = opt_str(b.assignee)

        if name == "reporter":
            sa = opt_str(a.reporter)
            sb = opt_str(b.reporter)

        if name == "due":
            sa = opt_str(a.due)
            sb = opt_str(b.due)

        if sa == "" and sb == "":
            return 0
        if sa == "":
            return 1
        if sb == "":
            return -1
        if name == "due":
            return cmp_str(sa, sb)

        return cmp_str(sa.lower(), sb.lower())

    return 0

def compare_issues(a: Issue, b: Issue, keys: List[SortKey], env: Env) -> Int:
    for k in keys:
        let c = field_cmp(a, b, k.name, env)

        if c != 0:
            if k.desc:
                return 0 - c

            return c

    return cmp_int(a.id, b.id)

def issue_line(iss: Issue) -> String:
    return (
        "#"
        + iss.id.to_string()
        + " | "
        + iss.state
        + " | "
        + iss.priority
        + " | "
        + show_text(iss.assignee)
        + " | "
        + show_points(iss.points)
        + " | "
        + show_text(iss.due)
        + " | "
        + labels_text(iss.labels, ",")
        + " | "
        + iss.title
    )

def count_word(n: Int, one: String, many: String) -> String:
    if n == 1:
        return "1 " + one

    return n.to_string() + " " + many

def compare_group(a: Group, b: Group) -> Int:
    if a.points != b.points:
        return cmp_int(b.points, a.points)
    if a.count != b.count:
        return cmp_int(b.count, a.count)

    return cmp_str(a.key, b.key)

def compare_label(a: LabelCount, b: LabelCount) -> Int:
    if a.count != b.count:
        return cmp_int(b.count, a.count)

    return cmp_str(a.name, b.name)

def period_line(state: String, from: Int, to: Int) -> String:
    return (
        state
        + ": t="
        + from.to_string()
        + ".."
        + to.to_string()
        + " ("
        + (to - from).to_string()
        + ")"
    )

# ---------- the tracker ----------

impl Tracker:
    def index_of(id: Int) -> Int:
        for i in 0..self.issues.length():
            if self.issues[i].id == id:
                return i
        return -1

    def is_final(state: String) -> Bool:
        return self.wf.finals.contains(state)

    def env() -> Env:
        return Env(
            today: self.today.clone(), finals: self.wf.finals.clone(),
            states: self.wf.states.clone()
        )

    var def log_add(id: Int, detail: String) -> Unit:
        self.log.append(
            LogEntry(
                t: self.clock, actor: self.actor.clone(), id: id, detail: detail
            )
        )

    def reaches(from: String, target: String) -> Bool:
        if not self.views.contains(from):
            return False

        for r in collect_refs(self.views.get(from).get("")):
            if r == target or self.reaches(r, target):
                return True
        return False

    def plan(parts: Parts) -> Plan:
        if parts.has_limit and not all_digits(parts.limit):
            return Plan(
                err: "bad limit '" + parts.limit + "'", expr: Everything,
                keys: List[SortKey](), limit: -1
            )

        var limit = -1
        if parts.has_limit:
            limit = to_num(parts.limit)

        let pr = parse_filter(parts.filter, self.wf.states.clone(), self.views.clone())
        if pr.err != "":
            return Plan(
                err: pr.err.clone(), expr: Everything, keys: List[SortKey](), limit: -1
            )

        var keys = List[SortKey]()

        if parts.has_sort:
            let sp = parse_sort(parts.sort)
            if sp.err != "":
                return Plan(
                    err: sp.err.clone(), expr: Everything, keys: List[SortKey](),
                    limit: -1
                )

            keys = sp.keys.clone()

        return Plan(err: "", expr: pr.expr.clone(), keys: keys, limit: limit)

    def run(plan: Plan) -> List[Issue]:
        let env = self.env()
        var res = List[Issue]()
        for iss in self.issues:
            if eval_expr(plan.expr, iss, env):
                res.append(iss.clone())
        if plan.keys.length() > 0:
            res = res.sorted(lambda a, b: compare_issues(a, b, plan.keys, env))

        if plan.limit >= 0 and plan.limit < res.length():
            var cut = List[Issue]()
            for i in 0..plan.limit:
                cut.append(res[i].clone())
            res = cut

        return res

    def print_issues(found: List[Issue]) -> Unit:
        for iss in found:
            self.out(issue_line(iss))
        self.out("(" + count_word(found.length(), "issue", "issues") + ")")

    def out(line: String) -> Unit:
        emit(line)

    var def define_workflow(block: List[String]) -> Unit:
        if self.next_id > 1:
            self.out("error: workflow: cannot redefine after issues were created")
            return

        let parsed = parse_workflow(block)

        if parsed.err != "":
            self.out("error: " + parsed.err)
            return

        let n_states = parsed.wf.states.length()
        let n_trans = parsed.wf.transitions.length()
        self.wf = parsed.wf.clone()
        self.has_wf = True
        self.out(
            "workflow ok: "
            + n_states.to_string()
            + " states, "
            + n_trans.to_string()
            + " transitions"
        )

    var def commit(idx: Int, next: Issue) -> String:
        let diffs = diff_issue(self.issues[idx], next)
        let id = next.id

        if diffs.length() == 0:
            self.out("#" + id.to_string() + " unchanged")
            return ""

        self.clock += 1

        var n = next.clone()
        n.updated = self.clock
        self.issues[idx] = n
        for d in diffs:
            self.log_add(id, d)
        self.out("updated #" + id.to_string())
        return ""

    var def edit_fields(id: Int, fields: List[String]) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()
        if self.is_final(self.issues[idx].state):
            return (
                "#"
                + id.to_string()
                + " is in final state '"
                + self.issues[idx].state
                + "'"
            )
        if fields.length() == 0:
            return "usage: edit ID field=value..."

        for f in fields:
            let e = check_field(f)
            if e != "":
                return e

        var iss = self.issues[idx].clone()
        for f in fields:
            iss.set_field(field_of(f), value_of(f))
        return self.commit(idx, iss)

    var def label_issue(id: Int, ops: List[String]) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()
        if self.is_final(self.issues[idx].state):
            return (
                "#"
                + id.to_string()
                + " is in final state '"
                + self.issues[idx].state
                + "'"
            )

        for op in ops:
            var body = op.clone()
            if op.starts_with("+") or op.starts_with("-"):
                body = sub(op, 1, op.scalar_length())
            if not valid_label(body.lower()):
                return "bad label '" + body.lower() + "'"

        var cur = Set[String]()
        for l in self.issues[idx].labels:
            cur.add(l.clone())

        for op in ops:
            var body = op.clone()
            if op.starts_with("+") or op.starts_with("-"):
                body = sub(op, 1, op.scalar_length())

            if op.starts_with("-"):
                cur.remove(body.lower())
            else:
                cur.add(body.lower())

        var iss = self.issues[idx].clone()
        iss.labels = cur.values().sorted()
        return self.commit(idx, iss)

    var def move_issue(id: Int, target: String, comment: String) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        let cur = self.issues[idx].state.clone()
        if self.is_final(cur):
            return "#" + id.to_string() + " is in final state '" + cur + "'"
        if not self.wf.states.contains(target):
            return "unknown state '" + target + "'"
        if cur == target:
            return "already in state '" + target + "'"

        var allowed = False
        var seen = False
        var best = List[String]()

        for t in self.wf.transitions:
            if t.src == cur and t.dst == target:
                seen = True

                let m = unmet_guards(self.issues[idx], t.guards.clone())

                if m.length() == 0:
                    allowed = True
                    break

                if best.length() == 0:
                    best = m

        if not seen:
            return "transition '" + cur + " -> " + target + "' not allowed"
        if not allowed:
            return (
                "cannot move #"
                + id.to_string()
                + " to "
                + target
                + ": missing "
                + best.join(", ")
            )

        self.clock += 1

        var iss = self.issues[idx].clone()
        iss.state = target.clone()
        iss.updated = self.clock
        if comment != "":
            iss.comments.append(
                Comment(
                    t: self.clock, actor: self.actor.clone(), text: comment.clone()
                )
            )
        self.issues[idx] = iss
        self.log_add(id, "state: " + cur + " -> " + target)
        self.out("moved #" + id.to_string() + ": " + cur + " -> " + target)
        if comment != "":
            self.log_add(id, "comment: " + comment)
        return ""

    var def comment_issue(id: Int, text: String) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        self.clock += 1

        var iss = self.issues[idx].clone()
        iss.comments.append(
            Comment(
                t: self.clock, actor: self.actor.clone(), text: text.clone()
            )
        )
        iss.updated = self.clock
        self.issues[idx] = iss
        self.log_add(id, "comment: " + text)
        self.out("commented #" + id.to_string())
        return ""

    var def delete_issue(id: Int) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        self.clock += 1
        self.log_add(id, "deleted")
        self.issues.splice(idx, 1, List[Issue]())
        self.out("deleted #" + id.to_string())
        return ""

    var def create_issue(rest: String) -> Unit:
        if not self.has_wf:
            self.out("error: no workflow defined")
            return

        let tk = split_tokens(rest)

        if not tk.ok:
            self.out("error: unterminated quote")
            return

        if tk.items.length() == 0:
            self.out("error: usage: create TITLE [field=value...]")
            return

        let title = tk.items[0]

        if title.trim() == "":
            self.out("error: empty title")
            return

        for i in 1..tk.items.length():
            let e = check_field(tk.items[i].clone())

            if e != "":
                self.out("error: " + e)
                return

        let defaults = Issue(
            id: self.next_id, title: title.clone(), state: self.wf.initial.clone(),
            priority: "medium", assignee: none, reporter: self.actor.clone(),
            points: none, due: none, labels: List[String](), comments: List[Comment](),
            created: 0, updated: 0
        )
        var iss = defaults.clone()
        for i in 1..tk.items.length():
            iss.set_field(field_of(tk.items[i].clone()), value_of(tk.items[i].clone()))
        self.clock += 1
        iss.created = self.clock
        iss.updated = self.clock
        self.next_id += 1

        let id = iss.id
        self.issues.append(iss)
        self.log_add(id, "created \"" + title + "\"")
        for d in diff_issue(defaults, self.issues[self.issues.length() - 1]):
            self.log_add(id, d)
        self.out("created #" + id.to_string())

    var def show_issue(id: Int) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        let iss = self.issues[idx].clone()
        self.out("#" + id.to_string() + " " + iss.title)
        self.out("  state: " + iss.state)
        self.out("  priority: " + iss.priority)
        self.out("  assignee: " + show_text(iss.assignee))
        self.out("  points: " + show_points(iss.points))
        self.out("  due: " + show_text(iss.due))
        self.out("  labels: " + labels_text(iss.labels, ", "))
        self.out("  reporter: " + show_text(iss.reporter))
        self.out(
            "  created: t="
            + iss.created.to_string()
            + ", updated: t="
            + iss.updated.to_string()
        )
        self.out("  comments: " + iss.comments.length().to_string())
        for c in iss.comments:
            self.out("    [t=" + c.t.to_string() + " " + c.actor + "] " + c.text)
        return ""

    var def show_log(id: Int, tail: Int) -> Unit:
        var sel = List[LogEntry]()
        for e in self.log:
            if id == 0 or e.id == id:
                sel.append(e.clone())

        var start = 0
        if tail >= 0 and tail < sel.length():
            start = sel.length() - tail

        if sel.length() == 0 or start >= sel.length():
            self.out("(no log entries)")
            return

        for i in start..sel.length():
            let e = sel[i]
            self.out(
                "t="
                + e.t.to_string()
                + " "
                + e.actor
                + " #"
                + e.id.to_string()
                + " "
                + e.detail
            )

    var def report_summary() -> Unit:
        var open_n = 0
        var final_n = 0
        var unassigned = 0
        var overdue = 0
        var open_points = 0

        for iss in self.issues:
            if self.is_final(iss.state):
                final_n += 1
            else:
                open_n += 1
                if opt_str(iss.assignee) == "":
                    unassigned += 1
                if opt_str(iss.due) != "" and opt_str(iss.due) < self.today:
                    overdue += 1
                if opt_int(iss.points) > 0:
                    open_points += opt_int(iss.points)

        self.out(
            "issues: "
            + self.issues.length().to_string()
            + " (open "
            + open_n.to_string()
            + ", final "
            + final_n.to_string()
            + ")"
        )
        self.out("by state:")

        for s in self.wf.states:
            var c = 0
            for iss in self.issues:
                if iss.state == s:
                    c += 1
            self.out("  " + s + ": " + c.to_string())

        self.out("by priority:")

        for p in ["critical", "high", "medium", "low"]:
            var c = 0
            for iss in self.issues:
                if iss.priority == p:
                    c += 1
            self.out("  " + p + ": " + c.to_string())

        self.out("unassigned: " + unassigned.to_string())
        self.out("overdue: " + overdue.to_string())
        self.out("open points: " + open_points.to_string())

    var def report_workload() -> Unit:
        var groups = List[Group]()
        var un_count = 0
        var un_points = 0
        var any_open = False

        for iss in self.issues:
            if self.is_final(iss.state):
                continue

            any_open = True

            var pts = opt_int(iss.points)
            if pts < 0:
                pts = 0

            let a = opt_str(iss.assignee)

            if a == "":
                un_count += 1
                un_points += pts
            else:
                let key = a.lower()
                var gi = -1
                for i in 0..groups.length():
                    if groups[i].key == key:
                        gi = i

                if gi < 0:
                    groups.append(Group(name: a, key: key, count: 0, points: 0))
                    gi = groups.length() - 1

                var g = groups[gi].clone()
                g.count += 1
                g.points += pts
                groups[gi] = g

        if not any_open:
            self.out("(no open issues)")
            return

        groups = groups.sorted(lambda x, y: compare_group(x, y))
        for g in groups:
            self.out(
                g.name + ": " + count_word(
                    g.count, "issue", "issues"
                ) + ", " + g.points.to_string() + " points"
            )
        if un_count > 0:
            self.out(
                "unassigned: " + count_word(
                    un_count, "issue", "issues"
                ) + ", " + un_points.to_string() + " points"
            )

    var def report_labels(filter: String) -> Unit:
        let pr = parse_filter(filter, self.wf.states.clone(), self.views.clone())

        if pr.err != "":
            self.out("error: " + pr.err)
            return

        let env = self.env()
        var counts = List[LabelCount]()

        for iss in self.issues:
            if not eval_expr(pr.expr, iss, env):
                continue

            for l in iss.labels:
                var found = False

                for i in 0..counts.length():
                    if counts[i].name == l:
                        var c = counts[i].clone()
                        c.count += 1
                        counts[i] = c
                        found = True

                if not found:
                    counts.append(LabelCount(name: l.clone(), count: 1))

        if counts.length() == 0:
            self.out("(no labels)")
            return

        for c in counts.sorted(lambda x, y: compare_label(x, y)):
            self.out(c.name + ": " + c.count.to_string())

    var def report_timeline(id: Int) -> String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        var iss = self.issues[idx].clone()
        var cur = self.wf.initial.clone()
        var from = iss.created

        for e in self.log:
            if e.id == id and e.detail.starts_with("state: "):
                let to = e.detail.split(" -> ") [1]
                self.out(period_line(cur, from, e.t))
                cur = to
                from = e.t

        self.out(period_line(cur, from, self.clock))
        return ""

    var def cmd_report(rest: String) -> Unit:
        let ws = words(rest)
        let usage = "error: usage: report summary|workload|labels|timeline"

        if ws.length() == 0:
            self.out(usage)
            return

        let kind = ws[0].clone()

        if kind == "summary":
            self.report_summary()
        elif kind == "workload":
            self.report_workload()
        elif kind == "labels":
            self.report_labels(after_words(rest, 1))
        elif kind == "timeline":
            if ws.length() != 2:
                self.out("error: usage: report timeline ID")
                return

            let id = parse_id(ws[1].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[1].clone() + "'")
                return

            let e = self.report_timeline(id)
            if e != "":
                self.out("error: " + e)
        else:
            self.out(usage)

    var def cmd_log(rest: String) -> Unit:
        let ws = words(rest)
        var k = 0
        var id = 0

        if ws.length() > 0 and ws[0].clone() != "tail":
            id = parse_id(ws[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[0].clone() + "'")
                return

            k = 1

        let rem = ws.length() - k
        var tail = -1

        if rem == 2 and ws[k] == "tail":
            if not all_digits(ws[k + 1].clone()):
                self.out("error: bad tail '" + ws[k + 1].clone() + "'")
                return

            tail = to_num(ws[k + 1].clone())
        elif rem != 0:
            self.out("error: usage: log [ID] [tail N]")
            return

        if id > 0 and id >= self.next_id:
            self.out("error: no such issue #" + id.to_string())
            return

        self.show_log(id, tail)

    var def cmd_bulk(rest: String) -> Unit:
        let at = find_where(rest)

        if at < 0:
            self.out("error: usage: bulk ACTION... where QUERY")
            return

        let action = sub(rest, 0, at).trim()
        let query = sub(rest, at + 5, rest.scalar_length()).trim()

        if action == "":
            self.out("error: usage: bulk ACTION... where QUERY")
            return

        let tk = split_tokens(action)

        if not tk.ok:
            self.out("error: unterminated quote")
            return

        let items = tk.items
        let kind = items[0]

        if kind == "move":
            if items.length() != 2:
                self.out("error: usage: bulk move STATE where QUERY")
                return
        elif kind == "assign":
            if items.length() != 2:
                self.out("error: usage: bulk assign NAME where QUERY")
                return
        elif kind == "label":
            if items.length() < 2:
                self.out("error: usage: bulk label +label... where QUERY")
                return
        elif kind == "set":
            if items.length() < 2:
                self.out("error: usage: bulk set field=value... where QUERY")
                return
        else:
            self.out("error: unknown bulk action '" + kind + "'")
            return

        let pr = parse_filter(query, self.wf.states.clone(), self.views.clone())

        if pr.err != "":
            self.out("error: " + pr.err)
            return

        let env = self.env()
        var ids = List[Int]()
        for iss in self.issues:
            if eval_expr(pr.expr, iss, env):
                ids.append(iss.id)

        var ok = 0
        var failed = 0

        for id in ids:
            var e = ""

            if kind == "move":
                e = self.move_issue(id, items[1], "")
            elif kind == "assign":
                e = self.edit_fields(id, ["assignee=" + items[1]])
            elif kind == "label":
                e = self.label_issue(id, rest_list(items, 1))
            else:
                e = self.edit_fields(id, rest_list(items, 1))

            if e == "":
                ok += 1
            else:
                failed += 1
                self.out("#" + id.to_string() + " error: " + e)

        self.out("bulk: " + ok.to_string() + " ok, " + failed.to_string() + " failed")

    var def cmd_view(rest: String) -> Unit:
        let ws = words(rest)

        if ws.length() == 0:
            self.out("error: usage: view save|run|list|show|delete")
            return

        let verb = ws[0].clone()

        if verb == "save":
            if ws.length() < 2:
                self.out("error: usage: view save NAME QUERY")
                return

            let name = ws[1].clone()

            if not valid_view_name(name):
                self.out("error: bad view name '" + name + "'")
                return

            let query = after_words(rest, 2).trim()
            let plan = self.plan(split_query(query))

            if plan.err != "":
                self.out("error: " + plan.err)
                return

            for r in collect_refs(query):
                if r == name or self.reaches(r, name):
                    self.out("error: view '" + name + "' would reference itself")
                    return

            self.views[name.clone()] = query
            self.out("saved view " + name)
        elif verb == "run":
            if ws.length() < 2:
                self.out("error: usage: view run NAME [sort FIELDS] [limit N]")
                return

            let name = ws[1].clone()

            if not self.views.contains(name):
                self.out("error: unknown view '" + name + "'")
                return

            let given = split_query(after_words(rest, 2))

            if given.has_limit and not all_digits(given.limit):
                self.out("error: bad limit '" + given.limit + "'")
                return

            if given.filter != "":
                self.out("error: unexpected '" + given.filter + "'")
                return

            let stored = split_query(self.views.get(name).get(""))
            var eff = Parts(
                filter: stored.filter.clone(), has_sort: stored.has_sort,
                sort: stored.sort.clone(), has_limit: stored.has_limit,
                limit: stored.limit.clone()
            )

            if given.has_sort:
                eff.has_sort = True
                eff.sort = given.sort.clone()

            if given.has_limit:
                eff.has_limit = True
                eff.limit = given.limit.clone()

            let plan = self.plan(eff)

            if plan.err != "":
                self.out("error: " + plan.err)
                return

            self.print_issues(self.run(plan))
        elif verb == "list":
            let names = self.views.keys().sorted()

            if names.length() == 0:
                self.out("(no views)")
                return

            for n in names:
                self.out(n + ": " + self.views.get(n).get(""))
        elif verb == "show":
            if ws.length() != 2:
                self.out("error: usage: view show NAME")
                return

            if not self.views.contains(ws[1].clone()):
                self.out("error: unknown view '" + ws[1].clone() + "'")
                return

            self.out(ws[1].clone() + ": " + self.views.get(ws[1].clone()).get(""))
        elif verb == "delete":
            if ws.length() != 2:
                self.out("error: usage: view delete NAME")
                return

            let name = ws[1].clone()

            if not self.views.contains(name):
                self.out("error: unknown view '" + name + "'")
                return

            for m in self.views.keys().sorted():
                if m != name and self.reaches(m, name):
                    self.out("error: view '" + name + "' is used by '" + m + "'")
                    return

            self.views.remove(name.clone())
            self.out("deleted view " + name)
        else:
            self.out("error: usage: view save|run|list|show|delete")

    var def dispatch(cmd: String, rest: String) -> Unit:
        if cmd == "actor":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: actor NAME")
                return

            self.actor = ws[0].clone()
            self.out("actor is " + ws[0].clone())
        elif cmd == "today":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: today DATE")
                return

            if not valid_date(ws[0].clone()):
                self.out("error: bad date '" + ws[0].clone() + "'")
                return

            self.today = ws[0].clone()
            self.out("today is " + ws[0].clone())
        elif cmd == "create":
            self.create_issue(rest)
        elif cmd == "edit":
            let tk = split_tokens(rest)

            if not tk.ok:
                self.out("error: unterminated quote")
                return

            if tk.items.length() == 0:
                self.out("error: usage: edit ID field=value...")
                return

            let id = parse_id(tk.items[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + tk.items[0] + "'")
                return

            let e = self.edit_fields(id, rest_list(tk.items, 1))
            if e != "":
                self.out("error: " + e)
        elif cmd == "assign":
            let tk = split_tokens(rest)

            if not tk.ok:
                self.out("error: unterminated quote")
                return

            if tk.items.length() != 2:
                self.out("error: usage: assign ID NAME")
                return

            let id = parse_id(tk.items[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + tk.items[0] + "'")
                return

            let e = self.edit_fields(id, ["assignee=" + tk.items[1]])
            if e != "":
                self.out("error: " + e)
        elif cmd == "label":
            let tk = split_tokens(rest)

            if not tk.ok:
                self.out("error: unterminated quote")
                return

            if tk.items.length() < 2:
                self.out("error: usage: label ID +label -label...")
                return

            let id = parse_id(tk.items[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + tk.items[0] + "'")
                return

            let e = self.label_issue(id, rest_list(tk.items, 1))
            if e != "":
                self.out("error: " + e)
        elif cmd == "move":
            let ws = words(rest)

            if ws.length() < 2:
                self.out("error: usage: move ID STATE [comment...]")
                return

            let id = parse_id(ws[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[0].clone() + "'")
                return

            let e = self.move_issue(id, ws[1].clone(), after_words(rest, 2))
            if e != "":
                self.out("error: " + e)
        elif cmd == "comment":
            let ws = words(rest)

            if ws.length() < 2:
                self.out("error: usage: comment ID TEXT")
                return

            let id = parse_id(ws[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[0].clone() + "'")
                return

            let e = self.comment_issue(id, after_words(rest, 1))
            if e != "":
                self.out("error: " + e)
        elif cmd == "delete":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: delete ID")
                return

            let id = parse_id(ws[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[0].clone() + "'")
                return

            let e = self.delete_issue(id)
            if e != "":
                self.out("error: " + e)
        elif cmd == "show":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: show ID")
                return

            let id = parse_id(ws[0].clone())

            if id < 0:
                self.out("error: bad issue id '" + ws[0].clone() + "'")
                return

            let e = self.show_issue(id)
            if e != "":
                self.out("error: " + e)
        elif cmd == "list":
            let plan = self.plan(split_query(rest))

            if plan.err != "":
                self.out("error: " + plan.err)
                return

            self.print_issues(self.run(plan))
        elif cmd == "log":
            self.cmd_log(rest)
        elif cmd == "view":
            self.cmd_view(rest)
        elif cmd == "bulk":
            self.cmd_bulk(rest)
        elif cmd == "report":
            self.cmd_report(rest)
        else:
            self.out("error: unknown command '" + cmd + "'")

export def main() -> Int:
    let raw = read_lines(stdin()).get()
    let n = raw.length()
    var tr = Tracker(
        wf: empty_workflow(), has_wf: False, issues: List[Issue](), next_id: 1,
        clock: 0, actor: "system", today: "1970-01-01", log: List[LogEntry](),
        views: Map[String, String]()
    )
    var idx = 0

    while idx < n:
        let line = strip_cr(raw[idx].clone()).trim_end()
        idx += 1

        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue

        emit("> " + line)

        let cmd = words(t) [0]
        let rest = after_words(line, 1)

        if cmd == "workflow":
            var block = List[String]()
            var closed = False

            while idx < n and not closed:
                let b = strip_cr(raw[idx].clone())
                idx += 1

                if b.trim() == "end":
                    closed = True
                else:
                    block.append(b)

            tr.define_workflow(block)
        else:
            tr.dispatch(cmd, rest)

    stdout().flush().get()
    return 0
