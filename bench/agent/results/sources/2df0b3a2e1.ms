import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

let PRIORITIES = ["low", "medium", "high", "critical"]
let SORT_FIELDS = [
    "id", "created", "updated", "priority", "points", "state", "title", "assignee",
    "reporter", "due"
]
let FILTER_FIELDS = [
    "id", "created", "updated", "points", "title", "assignee", "reporter", "text",
    "state", "priority", "due", "label", "labels", "is", "has", "view"
]
let GUARD_FIELDS = ["assignee", "points", "due", "labels", "reporter"]
let IS_VALUES = ["open", "final", "overdue", "unassigned"]
let HAS_VALUES = ["assignee", "due", "points", "labels", "comments", "reporter"]
let CL_TERM = 0
let CL_AND = 1
let CL_OR = 2
let CL_NOT = 3
let TK_WORD = 0
let TK_LPAREN = 1
let TK_RPAREN = 2
let TK_AND = 3
let TK_OR = 4
let TK_NOT = 5

type Fail:
    msg: String

impl Error for Fail:
    fn message() String:
        return self.msg.clone()

type Transition:
    src: String
    dst: String
    guards: List[String]

type Workflow:
    states: List[String]
    initial: String
    finals: List[String]
    transitions: List[Transition]

type Comment:
    t: Int
    who: String
    text: String

type Issue:
    id: Int
    title: String
    state: String
    priority: Int
    assignee: String
    reporter: String
    points: Int
    due: String
    labels: List[String]
    comments: List[Comment]
    created: Int
    updated: Int

type Entry:
    t: Int
    who: String
    id: Int
    detail: String

type Tracker:
    clock: Int
    actor: String
    today: String
    wf: Workflow
    next_id: Int
    issues: List[Issue]
    views: Map[String, String]
    journal: List[Entry]

type Token:
    kind: Int
    text: String

type Term:
    field: String
    op: String
    text: String
    alts: List[String]

type Clause:
    kind: Int
    term: Term

type Filter:
    clauses: List[Clause]
    refs: List[String]

type Parser:
    toks: List[Token]
    pos: Int
    clauses: List[Clause]
    refs: List[String]

type Parts:
    filter: String
    sort_words: List[String]
    limit: Int

type SortKey:
    field: String
    desc: Bool

type Group:
    name: String
    key: String
    count: Int
    points: Int

# ---------- small text helpers ----------

fn say(line: String) Unit:
    stdout().write(line + "\n").get()

fn sub(s: String, a: Int, b: Int) String:
    return s.slice(a, b).get("")

fn is_ws(c: String) Bool:
    return c == " " or c == "\t"

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn is_digits(s: String) Bool:
    if s == "":
        return false

    for c in s.chars():
        if not is_digit(c):
            return false
    return true

fn int_of(s: String) Int:
    return s.parse_int().get(0)

fn int_text(s: String) Bool:
    if not is_digits(s) or s.scalar_length() > 7:
        return false
    if s.scalar_length() > 1 and s.starts_with("0"):
        return false

    return int_of(s) <= 1000000

fn cmp_int(a: Int, b: Int) Int:
    if a < b:
        return -1
    if a == b:
        return 0

    return 1

fn cmp_str(a: String, b: String) Int:
    if a < b:
        return -1
    if a == b:
        return 0

    return 1

fn order_ok(c: Int, op: String) Bool:
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0

    return c >= 0

fn is_ordered(op: String) Bool:
    return op == "<" or op == "<=" or op == ">" or op == ">="

fn words(text: String) List[String]:
    return text.split("\t").join(" ").split(" ").filter(fn(w: String) Bool: w != "")

fn first_word(text: String) String:
    let ws = words(text)
    if ws.length() == 0:
        return ""

    return ws[0].clone()

# Text after the first n whitespace-separated words, leading blanks removed.
fn rest_after(text: String, n: Int) String:
    let cs = text.chars()
    var i = 0
    var k = 0

    while k < n:
        while i < cs.length() and is_ws(cs[i]):
            i += 1
        while i < cs.length() and not is_ws(cs[i]):
            i += 1
        k += 1

    while i < cs.length() and is_ws(cs[i]):
        i += 1
    return sub(text, i, cs.length())

fn last_word(text: String) String:
    let n = text.scalar_length()
    var i = n
    while i > 0 and not is_ws(sub(text, i - 1, i)):
        i -= 1
    return sub(text, i, n)

fn drop_last_word(text: String) String:
    let n = text.scalar_length()
    var i = n
    while i > 0 and not is_ws(sub(text, i - 1, i)):
        i -= 1
    return sub(text, 0, i).trim_end()

# Index of the first occurrence of `w` as a whole word, or -1.
fn find_word(text: String, w: String, end_ok: Bool) Int:
    let n = text.scalar_length()
    let m = w.scalar_length()
    var i = 0

    while i + m <= n:
        if sub(text, i, i + m) == w and (i == 0 or is_ws(sub(text, i - 1, i))):
            let after_ok = (
                (i + m == n and end_ok)
                or (i + m < n and is_ws(sub(text, i + m, i + m + 1)))
            )
            if after_ok:
                return i

        i += 1

    return -1

# Splits on whitespace; quoted sections join the token. Used by token-style commands.
fn tokenize(text: String) Result[List[String], Fail]:
    let cs = text.chars()
    var out = List[String]()
    var cur = ""
    var has = false
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if is_ws(c):
            if has:
                out.append(cur.clone())
                cur = ""
                has = false

            i += 1
        else if c == "\"":
            has = true
            i += 1

            var closed = false

            while not closed:
                if i >= cs.length():
                    return error(Fail(msg: "unterminated quote"))

                let d = cs[i]

                if d == "\"":
                    closed = true
                    i += 1
                else if (
                    d == "\\"
                    and i + 1 < cs.length()
                    and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
                ):
                    cur += cs[i + 1]
                    i += 2
                else:
                    cur += d
                    i += 1
        else:
            has = true
            cur += c
            i += 1

    if has:
        out.append(cur.clone())
    return ok(out)

# ---------- validation helpers ----------

fn valid_label(l: String) Bool:
    if l == "":
        return false

    for c in l.chars():
        if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"):
            return false
    return true

fn parse_labels(value: String) Result[List[String], Fail]:
    var out = List[String]()

    for raw in value.split(","):
        let l = raw.lower()
        if not valid_label(l):
            return error(Fail(msg: "bad label '{l}'"))

        if not out.contains(l):
            out.append(l)

    out.sort()
    return ok(out)

fn days_in(y: Int, m: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0:
            return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30

    return 31

fn valid_date(s: String) Bool:
    if s.scalar_length() != 10:
        return false

    for i in 0..10:
        let c = sub(s, i, i + 1)

        if i == 4 or i == 7:
            if c != "-":
                return false
        else if not is_digit(c):
            return false

    let y = int_of(sub(s, 0, 4))
    let m = int_of(sub(s, 5, 7))
    let d = int_of(sub(s, 8, 10))
    if y < 1 or m < 1 or m > 12:
        return false

    return d >= 1 and d <= days_in(y, m)

fn valid_state_name(s: String) Bool:
    if s == "":
        return false

    var first = true

    for c in s.chars():
        if first:
            if not (c >= "a" and c <= "z"):
                return false

            first = false
        else if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_"):
            return false

    return true

fn valid_view_name(s: String) Bool:
    if s == "" or not (sub(s, 0, 1) >= "a" and sub(s, 0, 1) <= "z"):
        return false

    for c in s.chars():
        if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"):
            return false
    return true

fn prio_name(r: Int) String:
    if r == 0:
        return "low"
    if r == 1:
        return "medium"
    if r == 2:
        return "high"

    return "critical"

fn show_text(s: String) String:
    if s == "":
        return "-"

    return s.clone()

fn show_points(p: Int) String:
    if p < 0:
        return "-"

    return "{p}"

fn labels_csv(l: List[String]) String:
    if l.length() == 0:
        return "-"

    return l.join(",")

fn labels_list(l: List[String]) String:
    if l.length() == 0:
        return "-"

    return l.join(", ")

# ---------- ids and lookup ----------

fn parse_id(arg: String) Result[Int, Fail]:
    var digits = arg.clone()
    if arg.starts_with("#"):
        digits = arg.drop(1)

    if is_digits(digits):
        let v = int_of(digits)
        if v >= 1:
            return ok(v)

    return error(Fail(msg: "bad issue id '{arg}'"))

fn find_id(st: Tracker, id: Int) Optional[Int]:
    for i in 0..st.issues.length():
        if st.issues[i].id == id:
            return some(i)
    return none

fn live_index(st: Tracker, arg: String) Result[Int, Fail]:
    let id = try parse_id(arg)
    if let i = find_id(st, id):
        return ok(i)

    return error(Fail(msg: "no such issue #{id}"))

fn is_final(st: Tracker, state: String) Bool:
    return st.wf.finals.contains(state)

fn is_open(st: Tracker, iss: Issue) Bool:
    return not st.wf.finals.contains(iss.state)

fn state_index(st: Tracker, state: String) Int:
    return st.wf.states.index_of(state).get(0)

# ---------- field assignment ----------

fn set_field(var iss: Issue, field: String, value: String) Result[Unit, Fail]:
    if field == "state":
        return error(Fail(msg: "use move to change state"))

    if field == "title":
        if value.trim() == "":
            return error(Fail(msg: "empty title"))

        iss.title = value.clone()
    else if field == "priority":
        let rank = PRIORITIES.index_of(value).get(-1)
        if rank < 0:
            return error(Fail(msg: "bad priority '{value}'"))

        iss.priority = rank
    else if field == "assignee":
        if value == "none":
            iss.assignee = ""
        else if value == "":
            return error(Fail(msg: "empty assignee"))
        else:
            iss.assignee = value.clone()
    else if field == "points":
        if value == "none":
            iss.points = -1
        else if int_text(value):
            iss.points = int_of(value)
        else:
            return error(Fail(msg: "bad points '{value}'"))
    else if field == "due":
        if value == "none":
            iss.due = ""
        else if valid_date(value):
            iss.due = value.clone()
        else:
            return error(Fail(msg: "bad date '{value}'"))
    else if field == "labels":
        if value == "none":
            iss.labels = List[String]()
        else:
            let ls = try parse_labels(value)
            iss.labels = ls
    else if field == "reporter":
        if value == "none":
            iss.reporter = ""
        else if value == "":
            return error(Fail(msg: "empty reporter"))
        else:
            iss.reporter = value.clone()
    else:
        return error(Fail(msg: "unknown field '{field}'"))

    return ok(unit)

fn apply_fields(var iss: Issue, toks: List[String], from: Int) Result[Unit, Fail]:
    var k = from

    while k < toks.length():
        let tok = toks[k].clone()
        let at = tok.index_of("=").get(-1)
        if at <= 0:
            return error(Fail(msg: "expected field=value, got '{tok}'"))

        let field = sub(tok, 0, at)
        let value = sub(tok, at + 1, tok.scalar_length())
        try set_field(var iss, field, value)
        k += 1

    return ok(unit)

# Describes what differs between two versions of an issue, in the fixed field order.
fn changes(old: Issue, next: Issue) List[String]:
    var out = List[String]()
    if old.title != next.title:
        out.append("title: {old.title} -> {next.title}")
    if old.priority != next.priority:
        out.append("priority: {prio_name(old.priority)} -> {prio_name(next.priority)}")
    if old.assignee != next.assignee:
        out.append("assignee: {show_text(old.assignee)} -> {show_text(next.assignee)}")
    if old.points != next.points:
        out.append("points: {show_points(old.points)} -> {show_points(next.points)}")
    if old.due != next.due:
        out.append("due: {show_text(old.due)} -> {show_text(next.due)}")
    if old.labels.join(",") != next.labels.join(","):
        out.append("labels: {labels_csv(old.labels)} -> {labels_csv(next.labels)}")
    if old.reporter != next.reporter:
        out.append("reporter: {show_text(old.reporter)} -> {show_text(next.reporter)}")
    return out

fn record(var st: Tracker, id: Int, detail: String) Unit:
    st.journal.append(
        Entry(
            t: st.clock, who: st.actor.clone(), id: id, detail: detail.clone()
        )
    )

# Applies the changes of an edit: reports "unchanged" or bumps the clock and logs them.
fn commit(var st: Tracker, idx: Int, old: Issue, next: Issue) Unit:
    let ch = changes(old, next)

    if ch.length() == 0:
        say("#{old.id} unchanged")
        return

    var fresh = next.clone()
    st.clock += 1
    fresh.updated = st.clock

    let id = fresh.id
    st.issues[idx] = fresh
    for c in ch:
        record(var st, id, c)
    say("updated #{id}")

fn edit_issue(var st: Tracker, idx: Int, toks: List[String], from: Int) Result[
    Unit, Fail
]:
    let old = st.issues[idx].clone()
    if is_final(st, old.state):
        return error(Fail(msg: "#{old.id} is in final state '{old.state}'"))
    if from >= toks.length():
        return error(Fail(msg: "usage: edit ID field=value..."))

    var next = old.clone()
    try apply_fields(var next, toks, from)
    commit(var st, idx, old, next)
    return ok(unit)

fn label_issue(var st: Tracker, idx: Int, ops: List[String], from: Int) Result[
    Unit, Fail
]:
    let old = st.issues[idx].clone()
    if is_final(st, old.state):
        return error(Fail(msg: "#{old.id} is in final state '{old.state}'"))

    var labels = old.labels.clone()
    var k = from

    while k < ops.length():
        let op = ops[k].clone()
        var name = op.clone()
        var remove = false

        if op.starts_with("-"):
            remove = true
            name = op.drop(1)
        else if op.starts_with("+"):
            name = op.drop(1)

        let l = name.lower()
        if not valid_label(l):
            return error(Fail(msg: "bad label '{l}'"))

        if remove:
            var kept = List[String]()
            for x in labels:
                if x != l:
                    kept.append(x.clone())
            labels = kept
        else if not labels.contains(l):
            labels.append(l)

        k += 1

    labels.sort()

    var next = old.clone()
    next.labels = labels
    commit(var st, idx, old, next)
    return ok(unit)

fn guard_unmet(iss: Issue, g: String) Bool:
    if g == "assignee":
        return iss.assignee == ""
    if g == "points":
        return iss.points < 0
    if g == "due":
        return iss.due == ""
    if g == "labels":
        return iss.labels.length() == 0

    return iss.reporter == ""

fn find_transition(wf: Workflow, src: String, dst: String) Int:
    for i in 0..wf.transitions.length():
        if wf.transitions[i].src == src and wf.transitions[i].dst == dst:
            return i
    return -1

fn move_issue(var st: Tracker, idx: Int, target: String, comment: String) Result[
    Unit, Fail
]:
    let id = st.issues[idx].id
    let cur = st.issues[idx].state.clone()
    if is_final(st, cur):
        return error(Fail(msg: "#{id} is in final state '{cur}'"))
    if not st.wf.states.contains(target):
        return error(Fail(msg: "unknown state '{target}'"))
    if cur == target:
        return error(Fail(msg: "already in state '{target}'"))

    let ti = find_transition(st.wf, cur, target)
    if ti < 0:
        return error(Fail(msg: "transition '{cur} -> {target}' not allowed"))

    var missing = List[String]()
    for g in st.wf.transitions[ti].guards:
        if guard_unmet(st.issues[idx], g):
            missing.append(g.clone())

    if missing.length() > 0:
        let miss = missing.join(", ")
        return error(Fail(msg: "cannot move #{id} to {target}: missing {miss}"))

    var next = st.issues[idx].clone()
    st.clock += 1
    next.state = target.clone()
    next.updated = st.clock
    if comment != "":
        next.comments.append(
            Comment(
                t: st.clock, who: st.actor.clone(), text: comment.clone()
            )
        )
    st.issues[idx] = next
    record(var st, id, "state: {cur} -> {target}")
    if comment != "":
        record(var st, id, "comment: {comment}")
    say("moved #{id}: {cur} -> {target}")
    return ok(unit)

fn add_comment(var st: Tracker, idx: Int, text: String) Unit:
    st.clock += 1

    var next = st.issues[idx].clone()
    next.updated = st.clock
    next.comments.append(
        Comment(t: st.clock, who: st.actor.clone(), text: text.clone())
    )

    let id = next.id
    st.issues[idx] = next
    record(var st, id, "comment: {text}")
    say("commented #{id}")

# ---------- workflow definition ----------

fn add_state(var states: List[String], name: String) Unit:
    if not states.contains(name):
        states.append(name.clone())

fn is_guard_field(g: String) Bool:
    return GUARD_FIELDS.contains(g)

fn parse_workflow(lines: List[String], start: Int, stop: Int) Result[Workflow, Fail]:
    var states = List[String]()
    var finals = List[String]()
    var trans = List[Transition]()
    var initial = ""
    var has_initial = false
    var k = start

    while k < stop:
        let line = lines[k].trim()
        k += 1
        if line == "" or line.starts_with("#"):
            continue

        if line.starts_with("initial:"):
            let name = line.drop(8).trim()
            if not valid_state_name(name):
                return error(Fail(msg: "workflow: bad state name '{name}'"))
            if has_initial:
                return error(Fail(msg: "workflow: initial state defined twice"))

            has_initial = true
            initial = name.clone()
            add_state(var states, name)
        else if line.starts_with("final:"):
            for part in line.drop(6).split(","):
                let name = part.trim()
                if not valid_state_name(name):
                    return error(Fail(msg: "workflow: bad state name '{name}'"))

                add_state(var states, name)
                if not finals.contains(name):
                    finals.append(name.clone())
        else if line.contains("->"):
            let arrow = line.index_of("->").get(0)
            let src = sub(line, 0, arrow).trim()
            if not valid_state_name(src):
                return error(Fail(msg: "workflow: bad state name '{src}'"))

            add_state(var states, src)

            for entry in sub(line, arrow + 2, line.scalar_length()).split(","):
                let ws = words(entry)
                if ws.length() != 1 and not (ws.length() == 3 and ws[1] == "requires"):
                    return error(Fail(msg: "workflow: bad line '{line}'"))

                let dst = ws[0].clone()
                if not valid_state_name(dst):
                    return error(Fail(msg: "workflow: bad state name '{dst}'"))

                var guards = List[String]()

                if ws.length() == 3:
                    for g in ws[2].split("+"):
                        if not is_guard_field(g):
                            return error(Fail(msg: "workflow: bad guard field '{g}'"))

                        guards.append(g.clone())

                add_state(var states, dst)
                trans.append(
                    Transition(
                        src: src.clone(), dst: dst.clone(), guards: guards
                    )
                )
        else:
            return error(Fail(msg: "workflow: bad line '{line}'"))

    if not has_initial:
        return error(Fail(msg: "workflow: initial state missing"))

    for t in trans:
        if finals.contains(t.src):
            return error(
                Fail(
                    msg: "workflow: '{t.src}' is final and cannot have transitions"
                )
            )
    return ok(
        Workflow(
            states: states, initial: initial, finals: finals, transitions: trans
        )
    )

# Consumes the block that starts at `start` and returns the index after its `end` line.
fn define_workflow(var st: Tracker, lines: List[String], start: Int) Int:
    var stop = start
    while stop < lines.length() and lines[stop].trim() != "end":
        stop += 1

    if st.next_id > 1:
        say("error: workflow: cannot redefine after issues were created")
        return stop + 1

    let r = parse_workflow(lines, start, stop)

    if r.is_error():
        say("error: " + r.err().message())
        return stop + 1

    if let w = r:
        say(
            "workflow ok: {w.states.length()} states, {w.transitions.length()} transitions"
        )
        st.wf = w

    return stop + 1

# ---------- query language ----------

fn word_kind(w: String) Int:
    if w == "AND":
        return TK_AND
    if w == "OR":
        return TK_OR
    if w == "NOT":
        return TK_NOT

    return TK_WORD

fn lex_query(text: String) Result[List[Token], Fail]:
    let cs = text.chars()
    var toks = List[Token]()
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if is_ws(c):
            i += 1
        else if c == "(":
            toks.append(Token(kind: TK_LPAREN, text: "("))
            i += 1
        else if c == ")":
            toks.append(Token(kind: TK_RPAREN, text: ")"))
            i += 1
        else:
            var w = ""

            while (
                i < cs.length()
                and not is_ws(cs[i])
                and cs[i] != "("
                and cs[i] != ")"
            ):
                if cs[i] == "\"":
                    w += cs[i]
                    i += 1

                    var closed = false

                    while not closed:
                        if i >= cs.length():
                            return error(Fail(msg: "query: unterminated quote"))

                        let d = cs[i]

                        if d == "\"":
                            closed = true
                            w += d
                            i += 1
                        else if (
                            d == "\\"
                            and i + 1 < cs.length()
                            and (
                                cs[i + 1] == "\""
                                or cs[i + 1] == "\\"
                            )
                        ):
                            w += d
                            w += cs[i + 1]
                            i += 2
                        else:
                            w += d
                            i += 1
                else:
                    w += cs[i]
                    i += 1

            toks.append(Token(kind: word_kind(w), text: w.clone()))

    return ok(toks)

# Splits a raw value into alternatives on unquoted `|`; quotes are removed.
fn split_alts(raw: String) List[String]:
    let cs = raw.chars()
    var alts = List[String]()
    var cur = ""
    var inq = false
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if inq:
            if (
                c == "\\"
                and i + 1 < cs.length()
                and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
            ):
                cur += cs[i + 1]
                i += 2
            else if c == "\"":
                inq = false
                i += 1
            else:
                cur += c
                i += 1
        else if c == "\"":
            inq = true
            i += 1
        else if c == "|":
            alts.append(cur.clone())
            cur = ""
            i += 1
        else:
            cur += c
            i += 1

    alts.append(cur.clone())
    return alts

fn is_field_char(c: String) Bool:
    return (c >= "a" and c <= "z") or c == "_"

fn op_allowed(field: String, op: String) Bool:
    if op == "~":
        return (
            field == "title"
            or field == "assignee"
            or field == "reporter"
            or field == "text"
            or field == "label"
            or field == "labels"
        )
    if op == ":":
        return field != "text"
    if op == "!=":
        return not (
            field == "text"
            or field == "is"
            or field == "has"
            or field == "view"
        )

    return (
        field == "id"
        or field == "created"
        or field == "updated"
        or field == "points"
        or field == "priority"
        or field == "due"
    )

fn alt_ok(st: Tracker, field: String, alt: String) Bool:
    if field == "id" or field == "created" or field == "updated":
        return int_text(alt)
    if field == "points":
        return alt == "none" or int_text(alt)
    if field == "priority":
        return PRIORITIES.contains(alt)
    if field == "due":
        return alt == "none" or valid_date(alt)
    if field == "state":
        return st.wf.states.contains(alt)
    if field == "is":
        return IS_VALUES.contains(alt)
    if field == "has":
        return HAS_VALUES.contains(alt)

    return alt != ""

fn ordered_ok(field: String, text: String) Bool:
    if field == "priority":
        return PRIORITIES.contains(text)
    if field == "due":
        return valid_date(text)

    return int_text(text)

fn blank_term() Term:
    return Term(field: "", op: "", text: "", alts: List[String]())

fn make_term(st: Tracker, raw: String) Result[Term, Fail]:
    let n = raw.scalar_length()
    var j = 0
    var field = ""

    while j < n and is_field_char(sub(raw, j, j + 1)):
        field += sub(raw, j, j + 1)
        j += 1

    var op = ""

    if (
        j + 1 < n
        and (
            sub(raw, j, j + 2) == "!="
            or sub(raw, j, j + 2) == "<="
            or sub(raw, j, j + 2) == ">="
        )
    ):
        op = sub(raw, j, j + 2)
        j += 2
    else if (
        j < n
        and (
            sub(raw, j, j + 1) == ":"
            or sub(raw, j, j + 1) == "<"
            or sub(raw, j, j + 1) == ">"
            or sub(raw, j, j + 1) == "~"
        )
    ):
        op = sub(raw, j, j + 1)
        j += 1

    if field == "" or op == "":
        return error(Fail(msg: "query: unexpected token '{raw}'"))
    if not FILTER_FIELDS.contains(field):
        return error(Fail(msg: "query: unknown field '{field}'"))
    if not op_allowed(field, op):
        return error(Fail(msg: "query: bad operator '{op}' for field '{field}'"))

    let alts = split_alts(sub(raw, j, n))
    let text = alts.join("|")

    if field == "view":
        if not st.views.contains(text):
            return error(Fail(msg: "query: unknown view '{text}'"))

        return ok(Term(field: field, op: op, text: text, alts: alts))

    if is_ordered(op):
        if alts.length() > 1 or not ordered_ok(field, text):
            return error(Fail(msg: "query: bad value '{text}' for field '{field}'"))
    else:
        for alt in alts:
            if not alt_ok(st, field, alt):
                return error(Fail(msg: "query: bad value '{alt}' for field '{field}'"))

    return ok(Term(field: field, op: op, text: text, alts: alts))

fn peek_kind(p: Parser) Int:
    if p.pos >= p.toks.length():
        return -1

    return p.toks[p.pos].kind

fn parse_or(var p: Parser, st: Tracker) Result[Unit, Fail]:
    try parse_and(var p, st)

    while peek_kind(p) == TK_OR:
        p.pos += 1
        try parse_and(var p, st)
        p.clauses.append(Clause(kind: CL_OR, term: blank_term()))

    return ok(unit)

fn parse_and(var p: Parser, st: Tracker) Result[Unit, Fail]:
    try parse_not(var p, st)

    while true:
        let k = peek_kind(p)

        if k == TK_AND:
            p.pos += 1
            try parse_not(var p, st)
            p.clauses.append(Clause(kind: CL_AND, term: blank_term()))
        else if k == TK_WORD or k == TK_NOT or k == TK_LPAREN:
            try parse_not(var p, st)
            p.clauses.append(Clause(kind: CL_AND, term: blank_term()))
        else:
            break

    return ok(unit)

fn parse_not(var p: Parser, st: Tracker) Result[Unit, Fail]:
    if peek_kind(p) == TK_NOT:
        p.pos += 1
        try parse_not(var p, st)
        p.clauses.append(Clause(kind: CL_NOT, term: blank_term()))
        return ok(unit)

    try parse_primary(var p, st)
    return ok(unit)

fn parse_primary(var p: Parser, st: Tracker) Result[Unit, Fail]:
    let k = peek_kind(p)
    if k == -1:
        return error(Fail(msg: "query: unexpected end of query"))

    let text = p.toks[p.pos].text.clone()

    if k == TK_LPAREN:
        p.pos += 1
        try parse_or(var p, st)

        let after = peek_kind(p)
        if after == -1:
            return error(Fail(msg: "query: unexpected end of query"))
        if after != TK_RPAREN:
            return error(Fail(msg: "query: unexpected token '{p.toks[p.pos].text}'"))

        p.pos += 1
        return ok(unit)

    if k == TK_WORD:
        p.pos += 1

        let term = try make_term(st, text)
        if term.field == "view":
            p.refs.append(term.text.clone())
        p.clauses.append(Clause(kind: CL_TERM, term: term))
        return ok(unit)

    return error(Fail(msg: "query: unexpected token '{text}'"))

fn compile_filter(st: Tracker, text: String) Result[Filter, Fail]:
    let toks = try lex_query(text)
    if toks.length() == 0:
        return ok(Filter(clauses: List[Clause](), refs: List[String]()))

    var p = Parser(toks: toks, pos: 0, clauses: List[Clause](), refs: List[String]())
    try parse_or(var p, st)
    if p.pos < p.toks.length():
        return error(Fail(msg: "query: unexpected token '{p.toks[p.pos].text}'"))

    return ok(Filter(clauses: p.clauses.clone(), refs: p.refs.clone()))

# Splits "FILTER sort FIELDS limit N" into its parts; checks the limit only.
fn split_query(raw: String) Result[Parts, Fail]:
    var text = raw.trim().clone()
    var limit = -1
    let before = drop_last_word(text)

    if last_word(before) == "limit":
        let v = last_word(text)
        if not int_text(v):
            return error(Fail(msg: "bad limit '{v}'"))

        limit = int_of(v)
        text = drop_last_word(before)

    var sort_words = List[String]()
    let sp = find_word(text, "sort", false)
    var filter = text.clone()

    if sp >= 0:
        filter = sub(text, 0, sp).trim_end()

        let tail = sub(text, sp + 4, text.scalar_length())
        sort_words = words(tail.split(",").join(" "))

    return ok(Parts(filter: filter, sort_words: sort_words, limit: limit))

fn sort_keys(names: List[String]) Result[List[SortKey], Fail]:
    var keys = List[SortKey]()

    for w in names:
        var desc = false
        var name = w.clone()

        if w.starts_with("-"):
            desc = true
            name = w.drop(1)

        if not SORT_FIELDS.contains(name):
            return error(Fail(msg: "bad sort field '{name}'"))

        keys.append(SortKey(field: name, desc: desc))

    return ok(keys)

fn opt_eq(value: String, a: String) Bool:
    if a == "none":
        return value == ""

    return value != "" and value.lower() == a.lower()

fn is_flag(st: Tracker, iss: Issue, a: String) Bool:
    if a == "open":
        return is_open(st, iss)
    if a == "final":
        return is_final(st, iss.state)
    if a == "overdue":
        return is_open(st, iss) and iss.due != "" and iss.due < st.today

    return iss.assignee == ""

fn has_flag(iss: Issue, a: String) Bool:
    if a == "assignee":
        return iss.assignee != ""
    if a == "due":
        return iss.due != ""
    if a == "points":
        return iss.points >= 0
    if a == "labels":
        return iss.labels.length() > 0
    if a == "comments":
        return iss.comments.length() > 0

    return iss.reporter != ""

fn eq_match(st: Tracker, iss: Issue, field: String, a: String) Bool:
    if field == "id":
        return iss.id == int_of(a)
    if field == "created":
        return iss.created == int_of(a)
    if field == "updated":
        return iss.updated == int_of(a)

    if field == "points":
        if a == "none":
            return iss.points < 0

        return iss.points >= 0 and iss.points == int_of(a)

    if field == "title":
        return iss.title.lower() == a.lower()
    if field == "assignee":
        return opt_eq(iss.assignee, a)
    if field == "reporter":
        return opt_eq(iss.reporter, a)
    if field == "state":
        return iss.state == a
    if field == "priority":
        return iss.priority == PRIORITIES.index_of(a).get(-1)

    if field == "due":
        if a == "none":
            return iss.due == ""

        return iss.due != "" and iss.due == a

    if field == "label" or field == "labels":
        let l = a.lower()
        if l == "none":
            return iss.labels.length() == 0

        return iss.labels.contains(l)

    if field == "is":
        return is_flag(st, iss, a)
    if field == "has":
        return has_flag(iss, a)

    return false

fn contains_ci(s: String, needle: String) Bool:
    return s.lower().contains(needle)

fn sub_match(iss: Issue, field: String, a: String) Bool:
    let needle = a.lower()
    if field == "title":
        return contains_ci(iss.title, needle)
    if field == "assignee":
        return iss.assignee != "" and contains_ci(iss.assignee, needle)
    if field == "reporter":
        return iss.reporter != "" and contains_ci(iss.reporter, needle)

    if field == "text":
        if contains_ci(iss.title, needle):
            return true

        for c in iss.comments:
            if contains_ci(c.text, needle):
                return true
        return false

    for l in iss.labels:
        if l.contains(needle):
            return true
    return false

fn ordered_matches(iss: Issue, t: Term) Bool:
    if t.field == "due":
        if iss.due == "":
            return false

        return order_ok(cmp_str(iss.due, t.text), t.op)

    if t.field == "points" and iss.points < 0:
        return false

    var v = 0

    if t.field == "id":
        v = iss.id
    else if t.field == "created":
        v = iss.created
    else if t.field == "updated":
        v = iss.updated
    else if t.field == "points":
        v = iss.points
    else if t.field == "priority":
        v = iss.priority

    var w = int_of(t.text)
    if t.field == "priority":
        w = PRIORITIES.index_of(t.text).get(0)
    return order_ok(cmp_int(v, w), t.op)

fn view_matches(st: Tracker, iss: Issue, name: String) Bool:
    if not st.views.contains(name):
        return false

    let q = st.views.get(name).get("")
    if let parts = split_query(q):
        if let f = compile_filter(st, parts.filter.clone()):
            return eval_filter(st, f, iss)
    return false

fn term_matches(st: Tracker, iss: Issue, t: Term) Bool:
    if t.field == "view":
        return view_matches(st, iss, t.text)
    if is_ordered(t.op):
        return ordered_matches(iss, t)

    var hit = false

    for a in t.alts:
        if t.op == "~":
            if sub_match(iss, t.field, a):
                hit = true
        else if eq_match(st, iss, t.field, a):
            hit = true

    if t.op == "!=":
        return not hit

    return hit

fn eval_filter(st: Tracker, f: Filter, iss: Issue) Bool:
    var stack = List[Bool]()

    for c in f.clauses:
        if c.kind == CL_TERM:
            stack.append(term_matches(st, iss, c.term))
        else if c.kind == CL_NOT:
            let a = stack.pop().get(false)
            stack.append(not a)
        else:
            let b = stack.pop().get(false)
            let a = stack.pop().get(false)

            if c.kind == CL_AND:
                stack.append(a and b)
            else:
                stack.append(a or b)

    if stack.length() == 0:
        return true

    return stack[stack.length() - 1]

fn refs_reach(st: Tracker, refs: List[String], target: String) Bool:
    for r in refs:
        if r == target:
            return true
        if st.views.contains(r) and view_uses(st, r, target):
            return true

    return false

fn view_uses(st: Tracker, view_name: String, target: String) Bool:
    let q = st.views.get(view_name).get("")
    if let p = split_query(q):
        if let g = compile_filter(st, p.filter.clone()):
            return refs_reach(st, g.refs, target)
    return false

# ---------- sorting and listing ----------

fn cmp_absent_int(a: Int, b: Int) Int:
    if a < 0 and b < 0:
        return 0
    if a < 0:
        return 1
    if b < 0:
        return -1

    return cmp_int(a, b)

fn cmp_absent_str(a: String, b: String) Int:
    if a == "" and b == "":
        return 0
    if a == "":
        return 1
    if b == "":
        return -1

    return cmp_str(a, b)

fn cmp_field(st: Tracker, field: String, a: Issue, b: Issue) Int:
    if field == "id":
        return cmp_int(a.id, b.id)
    if field == "created":
        return cmp_int(a.created, b.created)
    if field == "updated":
        return cmp_int(a.updated, b.updated)
    if field == "priority":
        return cmp_int(a.priority, b.priority)
    if field == "points":
        return cmp_absent_int(a.points, b.points)
    if field == "state":
        return cmp_int(state_index(st, a.state), state_index(st, b.state))
    if field == "title":
        return cmp_str(a.title.lower(), b.title.lower())
    if field == "assignee":
        return cmp_absent_str(a.assignee.lower(), b.assignee.lower())
    if field == "reporter":
        return cmp_absent_str(a.reporter.lower(), b.reporter.lower())

    return cmp_absent_str(a.due, b.due)

fn cmp_issue(st: Tracker, keys: List[SortKey], a: Issue, b: Issue) Int:
    for k in keys:
        var c = cmp_field(st, k.field, a, b)
        if k.desc:
            c = 0 - c
        if c != 0:
            return c

    return cmp_int(a.id, b.id)

fn sort_indices(st: Tracker, keys: List[SortKey], idxs: List[Int]) List[Int]:
    var out = List[Int]()

    for i in idxs:
        var pos = out.length()
        while (
            pos > 0
            and cmp_issue(
                st, keys, st.issues[out[pos - 1]], st.issues[i]
            ) > 0
        ):
            pos -= 1
        out.insert(pos, i)

    return out

fn issue_line(iss: Issue) String:
    let pr = prio_name(iss.priority)
    return "#{iss.id} | {iss.state} | {pr} | {show_text(iss.assignee)} | {show_points(iss.points)} | {show_text(iss.due)} | {labels_csv(iss.labels)} | {iss.title}"

fn print_matches(st: Tracker, f: Filter, keys: List[SortKey], limit: Int) Unit:
    var matched = List[Int]()
    for i in 0..st.issues.length():
        if eval_filter(st, f, st.issues[i]):
            matched.append(i)

    let ordered = sort_indices(st, keys, matched)
    var shown = 0

    for i in ordered:
        if limit >= 0 and shown >= limit:
            break

        say(issue_line(st.issues[i]))
        shown += 1

    if shown == 1:
        say("(1 issue)")
    else:
        say("({shown} issues)")

# ---------- commands ----------

fn cmd_actor(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: actor NAME"))

    st.actor = ws[0].clone()
    say("actor is {ws[0]}")
    return ok(unit)

fn cmd_today(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: today DATE"))
    if not valid_date(ws[0]):
        return error(Fail(msg: "bad date '{ws[0]}'"))

    st.today = ws[0].clone()
    say("today is {ws[0]}")
    return ok(unit)

fn cmd_create(var st: Tracker, rest: String) Result[Unit, Fail]:
    if st.wf.states.length() == 0:
        return error(Fail(msg: "no workflow defined"))

    let toks = try tokenize(rest)
    if toks.length() == 0:
        return error(Fail(msg: "usage: create TITLE [field=value...]"))
    if toks[0].trim() == "":
        return error(Fail(msg: "empty title"))

    let base = Issue(
        id: st.next_id, title: toks[0].clone(), state: st.wf.initial.clone(),
        priority: 1, assignee: "", reporter: st.actor.clone(), points: -1, due: "",
        labels: List[String](), comments: List[Comment](), created: 0, updated: 0
    )
    var iss = base.clone()
    try apply_fields(var iss, toks, 1)

    let ch = changes(base, iss)
    st.clock += 1
    st.next_id += 1
    iss.created = st.clock
    iss.updated = st.clock

    let id = iss.id
    st.issues.append(iss)
    record(var st, id, "created \"" + toks[0] + "\"")
    for c in ch:
        record(var st, id, c)
    say("created #{id}")
    return ok(unit)

fn cmd_edit(var st: Tracker, rest: String) Result[Unit, Fail]:
    let toks = try tokenize(rest)
    if toks.length() == 0:
        return error(Fail(msg: "usage: edit ID field=value..."))

    let idx = try live_index(st, toks[0])
    return edit_issue(var st, idx, toks, 1)

fn cmd_assign(var st: Tracker, rest: String) Result[Unit, Fail]:
    let toks = try tokenize(rest)
    if toks.length() != 2:
        return error(Fail(msg: "usage: assign ID NAME"))

    let idx = try live_index(st, toks[0])
    return edit_issue(var st, idx, ["assignee=" + toks[1]], 0)

fn cmd_label(var st: Tracker, rest: String) Result[Unit, Fail]:
    let toks = try tokenize(rest)
    if toks.length() < 2:
        return error(Fail(msg: "usage: label ID +label -label..."))

    let idx = try live_index(st, toks[0])
    return label_issue(var st, idx, toks, 1)

fn cmd_move(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() < 2:
        return error(Fail(msg: "usage: move ID STATE [comment...]"))

    let idx = try live_index(st, ws[0])
    let comment = rest_after(rest, 2)
    return move_issue(var st, idx, ws[1].clone(), comment)

fn cmd_comment(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() < 2:
        return error(Fail(msg: "usage: comment ID TEXT"))

    let idx = try live_index(st, ws[0])
    add_comment(var st, idx, rest_after(rest, 1))
    return ok(unit)

fn cmd_delete(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: delete ID"))

    let idx = try live_index(st, ws[0])
    st.clock += 1

    let id = st.issues[idx].id
    st.issues.remove(idx)
    record(var st, id, "deleted")
    say("deleted #{id}")
    return ok(unit)

fn cmd_show(st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: show ID"))

    let idx = try live_index(st, ws[0])
    let iss = st.issues[idx].clone()
    let pr = prio_name(iss.priority)
    say("#{iss.id} {iss.title}")
    say("  state: {iss.state}")
    say("  priority: {pr}")
    say("  assignee: {show_text(iss.assignee)}")
    say("  points: {show_points(iss.points)}")
    say("  due: {show_text(iss.due)}")
    say("  labels: {labels_list(iss.labels)}")
    say("  reporter: {show_text(iss.reporter)}")
    say("  created: t={iss.created}, updated: t={iss.updated}")
    say("  comments: {iss.comments.length()}")
    for c in iss.comments:
        say("    [t={c.t} {c.who}] {c.text}")
    return ok(unit)

fn cmd_list(st: Tracker, rest: String) Result[Unit, Fail]:
    let parts = try split_query(rest)
    let f = try compile_filter(st, parts.filter.clone())
    let keys = try sort_keys(parts.sort_words)
    print_matches(st, f, keys, parts.limit)
    return ok(unit)

fn view_save(var st: Tracker, r2: String) Result[Unit, Fail]:
    let ws = words(r2)
    if ws.length() == 0:
        return error(Fail(msg: "usage: view save NAME QUERY"))

    let name = ws[0].clone()
    if not valid_view_name(name):
        return error(Fail(msg: "bad view name '{name}'"))

    let query = rest_after(r2, 1)
    let parts = try split_query(query)
    let f = try compile_filter(st, parts.filter.clone())
    let _keys = try sort_keys(parts.sort_words)
    if refs_reach(st, f.refs, name):
        return error(Fail(msg: "view '{name}' would reference itself"))

    st.views[name.clone()] = query.clone()
    say("saved view {name}")
    return ok(unit)

fn view_run(st: Tracker, r2: String) Result[Unit, Fail]:
    let ws = words(r2)
    if ws.length() == 0:
        return error(Fail(msg: "usage: view run NAME [sort FIELDS] [limit N]"))

    let name = ws[0].clone()
    if not st.views.contains(name):
        return error(Fail(msg: "unknown view '{name}'"))

    var parts = try split_query(st.views.get(name).get(""))
    var sort_names = parts.sort_words.clone()
    var limit = 0
    limit = parts.limit

    var i = 1

    while i < ws.length():
        if ws[i] == "sort":
            sort_names = List[String]()
            i += 1

            while i < ws.length() and ws[i] != "limit":
                sort_names.append(ws[i].clone())
                i += 1

            if sort_names.length() == 0:
                return error(Fail(msg: "usage: view run NAME [sort FIELDS] [limit N]"))
        else if ws[i] == "limit":
            if i + 1 >= ws.length():
                return error(Fail(msg: "usage: view run NAME [sort FIELDS] [limit N]"))
            if not int_text(ws[i + 1]):
                return error(Fail(msg: "bad limit '{ws[i + 1]}'"))

            limit = int_of(ws[i + 1])
            i += 2
        else:
            return error(Fail(msg: "unexpected '{ws[i]}'"))

    let f = try compile_filter(st, parts.filter.clone())
    let keys = try sort_keys(sort_names)
    print_matches(st, f, keys, limit)
    return ok(unit)

fn view_list(st: Tracker) Unit:
    var names = st.views.keys()

    if names.length() == 0:
        say("(no views)")
        return

    names.sort()
    for n in names:
        say("{n}: {st.views.get(n).get("")}")

fn view_show(st: Tracker, r2: String) Result[Unit, Fail]:
    let ws = words(r2)
    if ws.length() != 1:
        return error(Fail(msg: "usage: view show NAME"))

    let name = ws[0].clone()
    if not st.views.contains(name):
        return error(Fail(msg: "unknown view '{name}'"))

    say("{name}: {st.views.get(name).get("")}")
    return ok(unit)

fn view_delete(var st: Tracker, r2: String) Result[Unit, Fail]:
    let ws = words(r2)
    if ws.length() != 1:
        return error(Fail(msg: "usage: view delete NAME"))

    let name = ws[0].clone()
    if not st.views.contains(name):
        return error(Fail(msg: "unknown view '{name}'"))

    var names = st.views.keys()
    names.sort()
    for u in names:
        if u != name and view_uses(st, u, name):
            return error(Fail(msg: "view '{name}' is used by '{u}'"))
    st.views.remove(name.clone())
    say("deleted view {name}")
    return ok(unit)

fn cmd_view(var st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    let usage = "usage: view save|run|list|show|delete"
    if ws.length() == 0:
        return error(Fail(msg: usage))

    let sub_cmd = ws[0].clone()
    let r2 = rest_after(rest, 1)
    if sub_cmd == "save":
        return view_save(var st, r2)
    if sub_cmd == "run":
        return view_run(st, r2)

    if sub_cmd == "list":
        view_list(st)
        return ok(unit)

    if sub_cmd == "show":
        return view_show(st, r2)
    if sub_cmd == "delete":
        return view_delete(var st, r2)

    return error(Fail(msg: usage))

fn cmd_bulk_check(toks: List[String]) Result[Unit, Fail]:
    let act = toks[0].clone()
    let n = toks.length()

    if act == "move":
        if n != 2:
            return error(Fail(msg: "usage: bulk move STATE where QUERY"))
    else if act == "assign":
        if n != 2:
            return error(Fail(msg: "usage: bulk assign NAME where QUERY"))
    else if act == "label":
        if n < 2:
            return error(Fail(msg: "usage: bulk label +label... where QUERY"))
    else if act == "set":
        if n < 2:
            return error(Fail(msg: "usage: bulk set field=value... where QUERY"))
    else:
        return error(Fail(msg: "unknown bulk action '{act}'"))

    return ok(unit)

fn bulk_apply(var st: Tracker, idx: Int, toks: List[String]) Result[Unit, Fail]:
    let act = toks[0].clone()
    if act == "move":
        return move_issue(var st, idx, toks[1].clone(), "")
    if act == "assign":
        return edit_issue(var st, idx, ["assignee=" + toks[1]], 0)
    if act == "label":
        return label_issue(var st, idx, toks, 1)

    return edit_issue(var st, idx, toks, 1)

fn cmd_bulk(var st: Tracker, rest: String) Result[Unit, Fail]:
    let w = find_word(rest, "where", true)
    if w < 0:
        return error(Fail(msg: "usage: bulk ACTION... where QUERY"))

    let action_text = sub(rest, 0, w).trim()
    let query_text = sub(rest, w + 5, rest.scalar_length()).trim()
    let toks = try tokenize(action_text)
    if toks.length() == 0:
        return error(Fail(msg: "usage: bulk ACTION... where QUERY"))

    try cmd_bulk_check(toks)

    let f = try compile_filter(st, query_text)
    var matched = List[Int]()
    for i in 0..st.issues.length():
        if eval_filter(st, f, st.issues[i]):
            matched.append(i)

    var ok_count = 0
    var bad_count = 0

    for idx in matched:
        let id = st.issues[idx].id
        let r = bulk_apply(var st, idx, toks)

        if r.is_error():
            say("#{id} error: {r.err().message()}")
            bad_count += 1
        else:
            ok_count += 1

    say("bulk: {ok_count} ok, {bad_count} failed")
    return ok(unit)

fn cmd_log(st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    var i = 0
    var fid = 0

    if ws.length() >= 1 and ws[0] != "tail":
        fid = try parse_id(ws[0])
        if fid >= st.next_id:
            return error(Fail(msg: "no such issue #{fid}"))

        i = 1

    var tail = -1

    if ws.length() - i == 2 and ws[i] == "tail":
        if not int_text(ws[i + 1]):
            return error(Fail(msg: "bad tail '{ws[i + 1]}'"))

        tail = int_of(ws[i + 1])
    else if ws.length() - i != 0:
        return error(Fail(msg: "usage: log [ID] [tail N]"))

    var sel = List[Int]()
    for j in 0..st.journal.length():
        if fid == 0 or st.journal[j].id == fid:
            sel.append(j)

    var start = 0
    if tail >= 0 and tail < sel.length():
        start = sel.length() - tail

    if start >= sel.length():
        say("(no log entries)")
        return ok(unit)

    for k in start..sel.length():
        let e = st.journal[sel[k]]
        say("t={e.t} {e.who} #{e.id} {e.detail}")

    return ok(unit)

fn group_index(groups: List[Group], key: String) Int:
    for i in 0..groups.length():
        if groups[i].key == key:
            return i
    return -1

fn group_before(a: Group, b: Group) Bool:
    if a.points != b.points:
        return a.points > b.points
    if a.count != b.count:
        return a.count > b.count

    return a.key < b.key

fn sort_groups(groups: List[Group]) List[Group]:
    var out = List[Group]()

    for g in groups:
        var pos = out.length()
        while pos > 0 and group_before(g, out[pos - 1]):
            pos -= 1
        out.insert(pos, g.clone())

    return out

fn report_summary(st: Tracker) Unit:
    let total = st.issues.length()
    var open_count = 0
    var unassigned = 0
    var overdue = 0
    var open_points = 0

    for iss in st.issues:
        if is_open(st, iss):
            open_count += 1
            if iss.assignee == "":
                unassigned += 1
            if iss.due != "" and iss.due < st.today:
                overdue += 1
            if iss.points > 0:
                open_points += iss.points

    let final_count = total - open_count
    say("issues: {total} (open {open_count}, final {final_count})")
    say("by state:")

    for s in st.wf.states:
        var n = 0
        for iss in st.issues:
            if iss.state == s:
                n += 1
        say("  {s}: {n}")

    say("by priority:")

    var rk = 3

    while rk >= 0:
        var n = 0
        for iss in st.issues:
            if iss.priority == rk:
                n += 1
        say("  {prio_name(rk)}: {n}")
        rk -= 1

    say("unassigned: {unassigned}")
    say("overdue: {overdue}")
    say("open points: {open_points}")

fn report_workload(st: Tracker) Unit:
    var groups = List[Group]()
    var open_count = 0
    var unassigned = 0
    var unassigned_points = 0

    for iss in st.issues:
        if not is_open(st, iss):
            continue

        open_count += 1

        var pts = 0
        if iss.points > 0:
            pts = iss.points

        if iss.assignee == "":
            unassigned += 1
            unassigned_points += pts
        else:
            let key = iss.assignee.lower()
            let gi = group_index(groups, key)

            if gi < 0:
                groups.append(
                    Group(
                        name: iss.assignee.clone(), key: key, count: 1, points: pts
                    )
                )
            else:
                var g = groups[gi].clone()
                g.count += 1
                g.points += pts
                groups[gi] = g

    if open_count == 0:
        say("(no open issues)")
        return

    for g in sort_groups(groups):
        let noun = if g.count == 1: "issue" else: "issues"

        say("{g.name}: {g.count} {noun}, {g.points} points")

    if unassigned > 0:
        let noun = if unassigned == 1: "issue" else: "issues"

        say("unassigned: {unassigned} {noun}, {unassigned_points} points")

fn report_labels(st: Tracker, f: Filter) Unit:
    var groups = List[Group]()

    for iss in st.issues:
        if not eval_filter(st, f, iss):
            continue

        for l in iss.labels:
            let gi = group_index(groups, l)

            if gi < 0:
                groups.append(
                    Group(
                        name: l.clone(), key: l.clone(), count: 1, points: 0
                    )
                )
            else:
                var g = groups[gi].clone()
                g.count += 1
                groups[gi] = g

    if groups.length() == 0:
        say("(no labels)")
        return

    for g in sort_groups(groups):
        say("{g.name}: {g.count}")

fn report_timeline(st: Tracker, idx: Int) Unit:
    var iss = st.issues[idx].clone()
    var cur = st.wf.initial.clone()
    var since = 0
    since = iss.created

    for e in st.journal:
        if e.id == iss.id and e.detail.starts_with("state: "):
            let parts = e.detail.split(" -> ")
            let dur = e.t - since
            say("{cur}: t={since}..{e.t} ({dur})")
            cur = parts[parts.length() - 1].clone()
            since = e.t

    let last = st.clock - since
    say("{cur}: t={since}..{st.clock} ({last})")

fn cmd_report(st: Tracker, rest: String) Result[Unit, Fail]:
    let ws = words(rest)
    let usage = "usage: report summary|workload|labels|timeline"
    if ws.length() == 0:
        return error(Fail(msg: usage))

    let kind = ws[0].clone()

    if kind == "summary":
        if ws.length() != 1:
            return error(Fail(msg: usage))

        report_summary(st)
        return ok(unit)

    if kind == "workload":
        if ws.length() != 1:
            return error(Fail(msg: usage))

        report_workload(st)
        return ok(unit)

    if kind == "labels":
        let f = try compile_filter(st, rest_after(rest, 1))
        report_labels(st, f)
        return ok(unit)

    if kind == "timeline":
        if ws.length() != 2:
            return error(Fail(msg: "usage: report timeline ID"))

        let idx = try live_index(st, ws[1])
        report_timeline(st, idx)
        return ok(unit)

    return error(Fail(msg: usage))

fn run_command(var st: Tracker, cmd: String, rest: String) Result[Unit, Fail]:
    if cmd == "actor":
        return cmd_actor(var st, rest)
    if cmd == "today":
        return cmd_today(var st, rest)
    if cmd == "create":
        return cmd_create(var st, rest)
    if cmd == "edit":
        return cmd_edit(var st, rest)
    if cmd == "assign":
        return cmd_assign(var st, rest)
    if cmd == "label":
        return cmd_label(var st, rest)
    if cmd == "move":
        return cmd_move(var st, rest)
    if cmd == "comment":
        return cmd_comment(var st, rest)
    if cmd == "delete":
        return cmd_delete(var st, rest)
    if cmd == "show":
        return cmd_show(st, rest)
    if cmd == "list":
        return cmd_list(st, rest)
    if cmd == "view":
        return cmd_view(var st, rest)
    if cmd == "bulk":
        return cmd_bulk(var st, rest)
    if cmd == "log":
        return cmd_log(st, rest)
    if cmd == "report":
        return cmd_report(st, rest)

    return error(Fail(msg: "unknown command '{cmd}'"))

export fn main() Int:
    var lines = List[String]()
    if let got = read_lines(stdin()):
        lines = got

    var st = Tracker(
        clock: 0,
        actor: "system",
        today: "1970-01-01",
        wf: Workflow(
            states: List[String](), initial: "", finals: List[String](),
            transitions: List[Transition]()
        ),
        next_id: 1,
        issues: List[Issue](),
        views: Map[String, String](),
        journal: List[Entry]()
    )
    var i = 0

    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1

        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue

        say("> " + line)

        let cmd = first_word(t)

        if cmd == "workflow":
            i = define_workflow(var st, lines, i)
        else:
            let r = run_command(var st, cmd, rest_after(t, 1))
            if r.is_error():
                say("error: " + r.err().message())

    return 0
