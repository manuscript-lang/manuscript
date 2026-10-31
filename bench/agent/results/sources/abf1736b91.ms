import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

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

fn emit(line: String) Unit:
    stdout().write(line + "\n").get()

fn sub(s: String, a: Int, b: Int) String:
    return s.slice_scalars(a, b).get()

fn is_ws(c: Int) Bool:
    return c == 32 or c == 9

fn is_lower(c: Int) Bool:
    return c >= 97 and c <= 122

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn all_digits(s: String) Bool:
    if s.scalar_length() == 0:
        return false

    for i in 0..s.scalar_length():
        if not is_digit(s.scalar_at(i)):
            return false
    return true

# Saturates well above the 1000000 limit so huge values stay comparable.
fn to_num(s: String) Int:
    var n = 0

    for i in 0..s.scalar_length():
        n = n * 10 + (s.scalar_at(i) - 48)
        if n > 1000000000000:
            return 1000000000000

    return n

# Integer rule: decimal digits, no sign, no leading zeros, at most 1000000.
fn int_rule(s: String) Bool:
    if not all_digits(s):
        return false
    if s.scalar_length() > 1 and s.scalar_at(0) == 48:
        return false

    return to_num(s) <= 1000000

fn valid_state(s: String) Bool:
    let n = s.scalar_length()
    if n == 0 or not is_lower(s.scalar_at(0)):
        return false

    for i in 1..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95):
            return false

    return true

fn valid_view_name(s: String) Bool:
    let n = s.scalar_length()
    if n == 0 or not is_lower(s.scalar_at(0)):
        return false

    for i in 1..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95 or c == 45):
            return false

    return true

fn valid_label(s: String) Bool:
    let n = s.scalar_length()
    if n == 0:
        return false

    for i in 0..n:
        let c = s.scalar_at(i)
        if not (is_lower(c) or is_digit(c) or c == 95 or c == 45):
            return false

    return true

fn days_in(month: Int, year: Int) Int:
    if month == 2:
        if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0:
            return 29

        return 28

    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30

    return 31

fn valid_date(s: String) Bool:
    if s.scalar_length() != 10:
        return false

    for i in 0..10:
        let c = s.scalar_at(i)

        if i == 4 or i == 7:
            if c != 45:
                return false
        else if not is_digit(c):
            return false

    let year = to_num(sub(s, 0, 4))
    let month = to_num(sub(s, 5, 7))
    let day = to_num(sub(s, 8, 10))
    if year < 1 or month < 1 or month > 12:
        return false

    return day >= 1 and day <= days_in(month, year)

fn cmp_int(a: Int, b: Int) Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

fn cmp_str(a: String, b: String) Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

fn words(s: String) List[String]:
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
fn after_words(s: String, n: Int) String:
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

fn rest_list(items: List[String], k: Int) List[String]:
    var res = List[String]()
    for i in k..items.length():
        res.append(items[i].clone())
    return res

fn strip_cr(s: String) String:
    let n = s.scalar_length()
    if n > 0 and s.scalar_at(n - 1) == 13:
        return sub(s, 0, n - 1)

    return s

fn first_eq(s: String) Int:
    for i in 0..s.scalar_length():
        if s.scalar_at(i) == 61:
            return i
    return -1

fn field_of(tok: String) String:
    return sub(tok, 0, first_eq(tok))

fn value_of(tok: String) String:
    return sub(tok, first_eq(tok) + 1, tok.scalar_length())

# Splits on whitespace where a double quote opens a quoted section inside a token.
fn split_tokens(s: String) Toks:
    var items = List[String]()
    var cur = ""
    var started = false
    var quoted = false
    let n = s.scalar_length()
    var i = 0

    while i < n:
        let c = s.scalar_at(i)

        if quoted:
            if c == 34:
                quoted = false
            else if (
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
        else if c == 34:
            quoted = true
            started = true
        else if is_ws(c):
            if started:
                items.append(cur)
                cur = ""
                started = false
        else:
            started = true
            cur = cur + sub(s, i, i + 1)

        i += 1

    if quoted:
        return Toks(items: items, ok: false)

    if started:
        items.append(cur)
    return Toks(items: items, ok: true)

# Finds the standalone word `where` outside quotes; returns its start or -1.
fn find_where(s: String) Int:
    let n = s.scalar_length()
    var i = 0
    var quoted = false
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
            else if c == 34:
                quoted = false
        else if is_ws(c):
            if start >= 0 and sub(s, start, i) == "where":
                return start

            start = -1
        else:
            if start < 0:
                start = i
            if c == 34:
                quoted = true

        i += 1

    if start >= 0 and sub(s, start, n) == "where":
        return start

    return -1

# Reads a quoted section starting at the opening quote index `start`.
fn read_quoted(s: String, start: Int) Quoted:
    let n = s.scalar_length()
    var i = start + 1
    var out = ""

    while i < n:
        let c = s.scalar_at(i)
        if c == 34:
            return Quoted(value: out, next: i + 1, ok: true)

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

    return Quoted(value: out, next: n, ok: false)

# ---------- field validation and values ----------

fn is_known_field(f: String) Bool:
    return (
        f == "title"
        or f == "priority"
        or f == "assignee"
        or f == "points"
        or f == "due"
        or f == "labels"
        or f == "reporter"
    )

fn check_field(tok: String) String:
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
    else if field == "priority":
        if not (
            value == "low"
            or value == "medium"
            or value == "high"
            or value == "critical"
        ):
            return "bad priority '" + value + "'"
    else if field == "points":
        if not clear and not int_rule(value):
            return "bad points '" + value + "'"
    else if field == "due":
        if not clear and not valid_date(value):
            return "bad date '" + value + "'"
    else if field == "labels":
        if not clear:
            for part in value.split(","):
                let lab = part.lower()
                if not valid_label(lab):
                    return "bad label '" + lab + "'"
    else if field == "assignee":
        if not clear and value.trim() == "":
            return "empty assignee"
    else if field == "reporter":
        if not clear and value.trim() == "":
            return "empty reporter"

    return ""

fn opt_str(o: Optional[String]) String:
    return o.get("")

fn opt_int(o: Optional[Int]) Int:
    return o.get(-1)

fn show_text(o: Optional[String]) String:
    let v = opt_str(o)
    if v == "":
        return "-"

    return v

fn show_points(o: Optional[Int]) String:
    let v = opt_int(o)
    if v < 0:
        return "-"

    return v.to_string()

fn labels_text(labels: List[String], sep: String) String:
    if labels.length() == 0:
        return "-"

    return labels.join(sep)

fn normalize_labels(items: List[String]) List[String]:
    var seen = Set[String]()
    for l in items:
        seen.add(l.lower())
    return seen.values().sorted()

impl Issue:
    var fn set_field(field: String, value: String) Unit:
        let clear = value == "none"

        if field == "title":
            self.title = value
        else if field == "priority":
            self.priority = value
        else if field == "assignee":
            if clear:
                self.assignee = none
            else:
                self.assignee = value
        else if field == "points":
            if clear:
                self.points = none
            else:
                self.points = to_num(value)
        else if field == "due":
            if clear:
                self.due = none
            else:
                self.due = value
        else if field == "labels":
            if clear:
                self.labels = List[String]()
            else:
                self.labels = normalize_labels(value.split(","))
        else if field == "reporter":
            if clear:
                self.reporter = none
            else:
                self.reporter = value

fn diff_issue(a: Issue, b: Issue) List[String]:
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

fn parse_id(tok: String) Int:
    var s = tok
    if s.starts_with("#"):
        s = sub(s, 1, s.scalar_length())
    if not all_digits(s):
        return -1

    let v = to_num(s)
    if v < 1:
        return -1

    return v

fn unmet_guards(iss: Issue, guards: List[String]) List[String]:
    var res = List[String]()

    for g in guards:
        var ok = true

        if g == "assignee":
            ok = opt_str(iss.assignee) != ""
        else if g == "points":
            ok = opt_int(iss.points) >= 0
        else if g == "due":
            ok = opt_str(iss.due) != ""
        else if g == "labels":
            ok = iss.labels.length() > 0
        else if g == "reporter":
            ok = opt_str(iss.reporter) != ""

        if not ok:
            res.append(g)

    return res

# ---------- workflow definition ----------

fn add_state(var states: List[String], name: String) Unit:
    if not states.contains(name):
        states.append(name)

fn guard_ok(g: String) Bool:
    return (
        g == "assignee"
        or g == "points"
        or g == "due"
        or g == "labels"
        or g == "reporter"
    )

fn wf_fail(msg: String) WfParse:
    return WfParse(err: msg, wf: empty_workflow())

fn parse_workflow(block: List[String]) WfParse:
    var states = List[String]()
    var finals = List[String]()
    var trans = List[Transition]()
    var initial = ""
    var has_initial = false
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
fn wf_line(
    line: String,
    var states: List[String],
    var finals: List[String],
    var trans: List[Transition],
    var initial: String,
    var has_initial: Bool
) String:
    if line.starts_with("initial:"):
        let name = sub(line, 8, line.scalar_length()).trim()
        if not valid_state(name):
            return "workflow: bad state name '" + name + "'"
        if has_initial:
            return "workflow: initial state defined twice"

        has_initial = true
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
            else if ws.length() == 3 and ws[1] == "requires":
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

fn empty_workflow() Workflow:
    return Workflow(
        initial: "", states: List[String](), finals: List[String](),
        transitions: List[Transition]()
    )

# ---------- query language ----------

fn ident_end(s: String, i: Int) Int:
    var j = i
    let n = s.scalar_length()
    while j < n and (is_lower(s.scalar_at(j)) or s.scalar_at(j) == 95):
        j += 1
    return j

fn op_at(s: String, i: Int) String:
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

fn word_kind(raw: String) Int:
    if raw == "AND":
        return K_AND
    if raw == "OR":
        return K_OR
    if raw == "NOT":
        return K_NOT

    return K_WORD

fn lex_filter(s: String) QLex:
    var toks = List[QTok]()
    let n = s.scalar_length()
    var i = 0

    while i < n:
        let c = s.scalar_at(i)

        if is_ws(c):
            i += 1
        else if c == 40 or c == 41:
            var kind = K_OPEN
            if c == 41:
                kind = K_CLOSE
            toks.append(
                QTok(
                    kind: kind, text: sub(s, i, i + 1), field: "", op: "", quoted: false
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
                            quoted: true
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
                            quoted: false
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
                        quoted: false
                    )
                )
                i = j

    return QLex(toks: toks, err: "")

# Names of the views a stored query references through `view:` terms.
fn collect_refs(text: String) List[String]:
    var res = List[String]()
    let lx = lex_filter(split_query(text).filter)
    for t in lx.toks:
        if t.kind == K_TERM and t.field == "view":
            res.append(t.text.clone())
    return res

fn op_allowed(field: String, op: String) Bool:
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

fn known_field(field: String) Bool:
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

fn priority_rank(p: String) Int:
    if p == "low":
        return 0
    if p == "medium":
        return 1
    if p == "high":
        return 2

    return 3

impl Parser:
    fn kind() Int:
        if self.pos >= self.toks.length():
            return K_END

        return self.toks[self.pos].kind

    fn value_error(field: String, op: String, v: String) String:
        let bad = "query: bad value '" + v + "' for field '" + field + "'"

        if field == "id" or field == "created" or field == "updated":
            if not int_rule(v):
                return bad
        else if field == "points":
            if not ((v == "none" and (op == ":" or op == "!=")) or int_rule(v)):
                return bad
        else if field == "due":
            if not ((v == "none" and (op == ":" or op == "!=")) or valid_date(v)):
                return bad
        else if field == "priority":
            if not (v == "low" or v == "medium" or v == "high" or v == "critical"):
                return bad
        else if field == "state":
            if not self.states.contains(v):
                return bad
        else if field == "is":
            if not (v == "open" or v == "final" or v == "overdue" or v == "unassigned"):
                return bad
        else if field == "has":
            if not (
                v == "assignee"
                or v == "due"
                or v == "points"
                or v == "labels"
                or v == "comments"
                or v == "reporter"
            ):
                return bad
        else if field == "view":
            if not self.views.contains(v):
                return "query: unknown view '" + v + "'"

        return ""

    var fn term(tok: QTok) Expr:
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

    var fn parse_unary() Expr:
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

    fn starts_operand() Bool:
        let k = self.kind()
        return k == K_AND or k == K_NOT or k == K_OPEN or k == K_TERM or k == K_WORD

    var fn parse_and() Expr:
        var left = self.parse_unary()

        while self.err == "" and self.starts_operand():
            if self.kind() == K_AND:
                self.pos += 1

            let right = self.parse_unary()
            left = Both(left: left, right: right)

        return left

    var fn parse_or() Expr:
        var left = self.parse_and()

        while self.err == "" and self.kind() == K_OR:
            self.pos += 1

            let right = self.parse_and()
            left = Either(left: left, right: right)

        return left

fn parse_filter(text: String, states: List[String], views: Map[String, String]) ParseOut:
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

fn last_space(s: String) Int:
    var i = s.scalar_length() - 1

    while i >= 0:
        if is_ws(s.scalar_at(i)):
            return i

        i -= 1

    return -1

# Splits a query into filter, sort clause and limit clause (textual, as the spec says).
fn split_query(raw: String) Parts:
    let text = raw.trim()
    var filter = text.clone()
    var has_limit = false
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
            has_limit = true
            limit = arg
            filter = sub(prefix, 0, m - 5).trim_end()

    var has_sort = false
    var sort = ""
    let fl = filter.scalar_length()
    var i = 0

    while i + 4 < fl:
        if (
            sub(filter, i, i + 4) == "sort"
            and (i == 0 or is_ws(filter.scalar_at(i - 1)))
            and is_ws(filter.scalar_at(i + 4))
        ):
            has_sort = true
            sort = sub(filter, i + 4, fl).trim()
            filter = sub(filter, 0, i).trim_end()
            break

        i += 1

    return Parts(
        filter: filter, has_sort: has_sort, sort: sort, has_limit: has_limit,
        limit: limit
    )

fn sort_field_ok(name: String) Bool:
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

fn parse_sort(text: String) SortParse:
    var keys = List[SortKey]()

    for w in words(text.replace(",", " ")):
        var name = w.clone()
        var desc = false

        if w.starts_with("-"):
            desc = true
            name = sub(w, 1, w.scalar_length())

        if not sort_field_ok(name):
            return SortParse(err: "bad sort field '" + name + "'", keys: keys)

        keys.append(SortKey(name: name, desc: desc))

    return SortParse(err: "", keys: keys)

fn eval_text(a: String, v: String, op: String) Bool:
    if op == "~":
        return a.lower().contains(v.lower())

    return a.lower() == v.lower()

fn eval_alt(field: String, op: String, v: String, iss: Issue, env: Env) Bool:
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
            return false

        return cmp_op(opt_int(iss.points), to_num(v), op)

    if field == "due":
        if v == "none":
            return opt_str(iss.due) == "" and op == ":"
        if opt_str(iss.due) == "":
            return false

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
                    return true
            return false

        if v == "none":
            return iss.labels.length() == 0

        return iss.labels.contains(v.lower())

    if field == "text":
        if iss.title.lower().contains(v.lower()):
            return true

        for c in iss.comments:
            if c.text.lower().contains(v.lower()):
                return true
        return false

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

        return false

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

    return false

fn cmp_op(a: Int, b: Int, op: String) Bool:
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

fn cmp_op_str(a: String, b: String, op: String) Bool:
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

fn eval_cmp(field: String, op: String, values: List[String], iss: Issue, env: Env) Bool:
    if op == "!=":
        for v in values:
            if eval_alt(field, ":", v, iss, env):
                return false
        return true

    if op == "<" or op == "<=" or op == ">" or op == ">=":
        return eval_alt(field, op, values[0], iss, env)

    for v in values:
        if eval_alt(field, op, v, iss, env):
            return true
    return false

fn eval_expr(e: Expr, iss: Issue, env: Env) Bool:
    match e:
        Cmp(field, op, values):
            return eval_cmp(field, op, values, iss, env)
        Both(left, right):
            return eval_expr(left, iss, env) and eval_expr(right, iss, env)
        Either(left, right):
            return eval_expr(left, iss, env) or eval_expr(right, iss, env)
        Negate(inner):
            return not eval_expr(inner, iss, env)
        Everything:
            return true

fn index_in(items: List[String], value: String) Int:
    for i in 0..items.length():
        if items[i] == value:
            return i
    return -1

fn field_cmp(a: Issue, b: Issue, name: String, env: Env) Int:
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

fn compare_issues(a: Issue, b: Issue, keys: List[SortKey], env: Env) Int:
    for k in keys:
        let c = field_cmp(a, b, k.name, env)

        if c != 0:
            if k.desc:
                return 0 - c

            return c

    return cmp_int(a.id, b.id)

fn issue_line(iss: Issue) String:
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

fn count_word(n: Int, one: String, many: String) String:
    if n == 1:
        return "1 " + one

    return n.to_string() + " " + many

fn compare_group(a: Group, b: Group) Int:
    if a.points != b.points:
        return cmp_int(b.points, a.points)
    if a.count != b.count:
        return cmp_int(b.count, a.count)

    return cmp_str(a.key, b.key)

fn compare_label(a: LabelCount, b: LabelCount) Int:
    if a.count != b.count:
        return cmp_int(b.count, a.count)

    return cmp_str(a.name, b.name)

fn period_line(state: String, from: Int, to: Int) String:
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
    fn index_of(id: Int) Int:
        for i in 0..self.issues.length():
            if self.issues[i].id == id:
                return i
        return -1

    fn is_final(state: String) Bool:
        return self.wf.finals.contains(state)

    fn env() Env:
        return Env(
            today: self.today.clone(), finals: self.wf.finals.clone(),
            states: self.wf.states.clone()
        )

    var fn log_add(id: Int, detail: String) Unit:
        self.log.append(
            LogEntry(
                t: self.clock, actor: self.actor.clone(), id: id, detail: detail
            )
        )

    fn reaches(from: String, target: String) Bool:
        if not self.views.contains(from):
            return false

        for r in collect_refs(self.views.get(from).get("")):
            if r == target or self.reaches(r, target):
                return true
        return false

    fn plan(parts: Parts) Plan:
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

    fn run(plan: Plan) List[Issue]:
        let env = self.env()
        var res = List[Issue]()
        for iss in self.issues:
            if eval_expr(plan.expr, iss, env):
                res.append(iss.clone())
        if plan.keys.length() > 0:
            res = res.sorted(fn a, b: compare_issues(a, b, plan.keys, env))

        if plan.limit >= 0 and plan.limit < res.length():
            var cut = List[Issue]()
            for i in 0..plan.limit:
                cut.append(res[i].clone())
            res = cut

        return res

    fn print_issues(found: List[Issue]) Unit:
        for iss in found:
            self.out(issue_line(iss))
        self.out("(" + count_word(found.length(), "issue", "issues") + ")")

    fn out(line: String) Unit:
        emit(line)

    var fn define_workflow(block: List[String]) Unit:
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
        self.has_wf = true
        self.out(
            "workflow ok: "
            + n_states.to_string()
            + " states, "
            + n_trans.to_string()
            + " transitions"
        )

    var fn commit(idx: Int, next: Issue) String:
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

    var fn edit_fields(id: Int, fields: List[String]) String:
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

    var fn label_issue(id: Int, ops: List[String]) String:
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

    var fn move_issue(id: Int, target: String, comment: String) String:
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

        var allowed = false
        var seen = false
        var best = List[String]()

        for t in self.wf.transitions:
            if t.src == cur and t.dst == target:
                seen = true

                let m = unmet_guards(self.issues[idx], t.guards.clone())

                if m.length() == 0:
                    allowed = true
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

    var fn comment_issue(id: Int, text: String) String:
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

    var fn delete_issue(id: Int) String:
        let idx = self.index_of(id)
        if idx < 0:
            return "no such issue #" + id.to_string()

        self.clock += 1
        self.log_add(id, "deleted")
        self.issues.splice(idx, 1, List[Issue]())
        self.out("deleted #" + id.to_string())
        return ""

    var fn create_issue(rest: String) Unit:
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

    var fn show_issue(id: Int) String:
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

    var fn show_log(id: Int, tail: Int) Unit:
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

    var fn report_summary() Unit:
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

    var fn report_workload() Unit:
        var groups = List[Group]()
        var un_count = 0
        var un_points = 0
        var any_open = false

        for iss in self.issues:
            if self.is_final(iss.state):
                continue

            any_open = true

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

        groups = groups.sorted(fn x, y: compare_group(x, y))
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

    var fn report_labels(filter: String) Unit:
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
                var found = false

                for i in 0..counts.length():
                    if counts[i].name == l:
                        var c = counts[i].clone()
                        c.count += 1
                        counts[i] = c
                        found = true

                if not found:
                    counts.append(LabelCount(name: l.clone(), count: 1))

        if counts.length() == 0:
            self.out("(no labels)")
            return

        for c in counts.sorted(fn x, y: compare_label(x, y)):
            self.out(c.name + ": " + c.count.to_string())

    var fn report_timeline(id: Int) String:
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

    var fn cmd_report(rest: String) Unit:
        let ws = words(rest)
        let usage = "error: usage: report summary|workload|labels|timeline"

        if ws.length() == 0:
            self.out(usage)
            return

        let kind = ws[0].clone()

        if kind == "summary":
            self.report_summary()
        else if kind == "workload":
            self.report_workload()
        else if kind == "labels":
            self.report_labels(after_words(rest, 1))
        else if kind == "timeline":
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

    var fn cmd_log(rest: String) Unit:
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
        else if rem != 0:
            self.out("error: usage: log [ID] [tail N]")
            return

        if id > 0 and id >= self.next_id:
            self.out("error: no such issue #" + id.to_string())
            return

        self.show_log(id, tail)

    var fn cmd_bulk(rest: String) Unit:
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
        else if kind == "assign":
            if items.length() != 2:
                self.out("error: usage: bulk assign NAME where QUERY")
                return
        else if kind == "label":
            if items.length() < 2:
                self.out("error: usage: bulk label +label... where QUERY")
                return
        else if kind == "set":
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
            else if kind == "assign":
                e = self.edit_fields(id, ["assignee=" + items[1]])
            else if kind == "label":
                e = self.label_issue(id, rest_list(items, 1))
            else:
                e = self.edit_fields(id, rest_list(items, 1))

            if e == "":
                ok += 1
            else:
                failed += 1
                self.out("#" + id.to_string() + " error: " + e)

        self.out("bulk: " + ok.to_string() + " ok, " + failed.to_string() + " failed")

    var fn cmd_view(rest: String) Unit:
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
        else if verb == "run":
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
                eff.has_sort = true
                eff.sort = given.sort.clone()

            if given.has_limit:
                eff.has_limit = true
                eff.limit = given.limit.clone()

            let plan = self.plan(eff)

            if plan.err != "":
                self.out("error: " + plan.err)
                return

            self.print_issues(self.run(plan))
        else if verb == "list":
            let names = self.views.keys().sorted()

            if names.length() == 0:
                self.out("(no views)")
                return

            for n in names:
                self.out(n + ": " + self.views.get(n).get(""))
        else if verb == "show":
            if ws.length() != 2:
                self.out("error: usage: view show NAME")
                return

            if not self.views.contains(ws[1].clone()):
                self.out("error: unknown view '" + ws[1].clone() + "'")
                return

            self.out(ws[1].clone() + ": " + self.views.get(ws[1].clone()).get(""))
        else if verb == "delete":
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

    var fn dispatch(cmd: String, rest: String) Unit:
        if cmd == "actor":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: actor NAME")
                return

            self.actor = ws[0].clone()
            self.out("actor is " + ws[0].clone())
        else if cmd == "today":
            let ws = words(rest)

            if ws.length() != 1:
                self.out("error: usage: today DATE")
                return

            if not valid_date(ws[0].clone()):
                self.out("error: bad date '" + ws[0].clone() + "'")
                return

            self.today = ws[0].clone()
            self.out("today is " + ws[0].clone())
        else if cmd == "create":
            self.create_issue(rest)
        else if cmd == "edit":
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
        else if cmd == "assign":
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
        else if cmd == "label":
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
        else if cmd == "move":
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
        else if cmd == "comment":
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
        else if cmd == "delete":
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
        else if cmd == "show":
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
        else if cmd == "list":
            let plan = self.plan(split_query(rest))

            if plan.err != "":
                self.out("error: " + plan.err)
                return

            self.print_issues(self.run(plan))
        else if cmd == "log":
            self.cmd_log(rest)
        else if cmd == "view":
            self.cmd_view(rest)
        else if cmd == "bulk":
            self.cmd_bulk(rest)
        else if cmd == "report":
            self.cmd_report(rest)
        else:
            self.out("error: unknown command '" + cmd + "'")

export fn main() Int:
    let raw = read_lines(stdin()).get()
    let n = raw.length()
    var tr = Tracker(
        wf: empty_workflow(), has_wf: false, issues: List[Issue](), next_id: 1,
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
            var closed = false

            while idx < n and not closed:
                let b = strip_cr(raw[idx].clone())
                idx += 1

                if b.trim() == "end":
                    closed = true
                else:
                    block.append(b)

            tr.define_workflow(block)
        else:
            tr.dispatch(cmd, rest)

    stdout().flush().get()
    return 0
