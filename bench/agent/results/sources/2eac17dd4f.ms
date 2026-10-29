import {stdout, stdin} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"

let K_TERM = 0
let K_AND = 1
let K_OR = 2
let K_NOT = 3
let K_OPEN = 4
let K_CLOSE = 5
let K_BAD = 6

type Failure:
    msg: String

impl Error for Failure:
    fn message() String: self.msg.clone()

fn fail[T](msg: String) Result[T, Failure]:
    return error(Failure(msg))

type Trans:
    src: String
    dst: String
    guards: List[String]

type Workflow:
    defined: Bool
    states: List[String]
    initial: String
    finals: List[String]
    trans: List[Trans]

type IssueComment:
    t: Int
    actor: String
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
    comments: List[IssueComment]
    created: Int
    updated: Int

type LogEntry:
    t: Int
    actor: String
    id: Int
    detail: String

type Store:
    clock: Int
    actor: String
    today: String
    next_id: Int
    wf: Workflow
    issues: List[Issue]
    log: List[LogEntry]
    views: Map[String, String]

type Patch:
    title: Optional[String] = none
    priority: Optional[Int] = none
    assignee: Optional[String] = none
    points: Optional[Int] = none
    due: Optional[String] = none
    labels: Optional[List[String]] = none
    reporter: Optional[String] = none

type Tok:
    kind: Int
    field: String
    op: String
    value: String
    quoted: Bool
    text: String

type Parser:
    toks: List[Tok]
    pos: Int

type Node:
    case Term(field: String, op: String, value: String, quoted: Bool)
    case Both(left: Node, right: Node)
    case Either(left: Node, right: Node)
    case Negate(inner: Node)
    case Inline(inner: Node)
    case Everything

type Clauses:
    filter: String
    sort: String
    limit: Int

type SortKey:
    field: String
    desc: Bool

type Group:
    name: String
    count: Int
    points: Int

type LabelCount:
    name: String
    count: Int

fn emit(text: String) Unit:
    stdout().write(text + "\n").get()

fn show_result(r: Result[String, Failure]) Unit:
    if r.is_ok():
        emit(r.get())
    else:
        emit("error: " + r.err().message())

# ---------- text helpers ----------

fn is_ws(c: String) Bool:
    return c == " " or c == "\t"

fn is_blank(s: String) Bool:
    return s.trim().length() == 0

fn chars_to_str(cs: List[String], from: Int, to: Int) String:
    var out = ""
    var k = from

    while k < to and k < cs.length():
        out += cs[k]
        k += 1

    return out

fn sub_from(s: String, k: Int) String:
    let cs = s.chars()
    return chars_to_str(cs, k, cs.length())

fn words(text: String) List[String]:
    return text.replace("\t", " ").split(" ").filter(fn(w: String) Bool: w.length() > 0)

fn drop_words(text: String, n: Int) String:
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
    return chars_to_str(cs, i, cs.length())

# Char index of the first whitespace-delimited word equal to word, or -1.
fn word_pos(text: String, word: String) Int:
    let cs = text.chars()
    let n = word.length()
    var i = 0

    while i < cs.length():
        if (
            (i == 0 or is_ws(cs[i - 1]))
            and chars_to_str(cs, i, i + n) == word
            and (i + n == cs.length() or is_ws(cs[i + n]))
        ):
            return i

        i += 1

    return -1

fn all_in(s: String, allowed: String) Bool:
    for c in s.chars():
        if not allowed.contains(c):
            return false
    return true

fn tail_list(xs: List[String], k: Int) List[String]:
    var out = List[String]()
    var i = k

    while i < xs.length():
        out.append(xs[i].clone())
        i += 1

    return out

fn contains_ci(a: String, b: String) Bool:
    return a.lower().contains(b.lower())

# ---------- values ----------

# Integer rule: digits only, no leading zeros, at most 1000000.
fn int_value(s: String) Optional[Int]:
    if s.length() == 0 or s.length() > 7:
        return none
    if s.length() > 1 and s.starts_with("0"):
        return none
    if not all_in(s, "0123456789"):
        return none

    let v = s.parse_int().get(0)
    if v > 1000000:
        return none

    return some(v)

fn days_in(y: Int, m: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0:
            return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30

    return 31

fn valid_date(s: String) Bool:
    let parts = s.split("-")
    if parts.length() != 3:
        return false
    if parts[0].length() != 4 or parts[1].length() != 2 or parts[2].length() != 2:
        return false
    if (
        not all_in(parts[0], "0123456789")
        or not all_in(parts[1], "0123456789")
        or not all_in(parts[2], "0123456789")
    ):
        return false

    let y = parts[0].parse_int().get(0)
    let m = parts[1].parse_int().get(0)
    let d = parts[2].parse_int().get(0)
    if y < 1 or m < 1 or m > 12:
        return false

    return d >= 1 and d <= days_in(y, m)

fn prio_rank(s: String) Int:
    if s == "low":
        return 0
    if s == "medium":
        return 1
    if s == "high":
        return 2
    if s == "critical":
        return 3

    return -1

fn prio_name(r: Int) String:
    if r == 0:
        return "low"
    if r == 2:
        return "high"
    if r == 3:
        return "critical"

    return "medium"

fn valid_label(l: String) Bool:
    return l.length() > 0 and all_in(l, "abcdefghijklmnopqrstuvwxyz0123456789_-")

fn valid_state(s: String) Bool:
    if s.length() == 0:
        return false

    let cs = s.chars()
    if not "abcdefghijklmnopqrstuvwxyz".contains(cs[0]):
        return false

    return all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789_")

fn valid_view_name(s: String) Bool:
    if s.length() == 0:
        return false

    let cs = s.chars()
    if not "abcdefghijklmnopqrstuvwxyz".contains(cs[0]):
        return false

    return all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789_-")

fn dash(s: String) String:
    if s.length() == 0:
        return "-"

    return s.clone()

fn pts_text(p: Int) String:
    if p < 0:
        return "-"

    return "{p}"

fn labels_text(labels: List[String], sep: String) String:
    if labels.length() == 0:
        return "-"

    return labels.join(sep)

fn issues_text(n: Int) String:
    if n == 1:
        return "1 issue"

    return "{n} issues"

fn count_text(n: Int) String:
    if n == 1:
        return "(1 issue)"

    return "({n} issues)"

fn normalize_labels(items: List[String]) Result[List[String], Failure]:
    var out = List[String]()

    for raw in items:
        let l = raw.lower()
        if not valid_label(l):
            return fail("bad label '{l}'")

        if not out.contains(l):
            out.append(l)

    out.sort()
    return ok(out)

# ---------- ids and lookup ----------

fn parse_id(arg: String) Result[Int, Failure]:
    var digits = arg.clone()
    if arg.starts_with("#"):
        digits = sub_from(arg, 1)
    if digits.length() == 0 or not all_in(digits, "0123456789"):
        return fail("bad issue id '{arg}'")

    while digits.length() > 1 and digits.starts_with("0"):
        digits = sub_from(digits, 1)

    let v = digits.parse_int()
    if v.is_none():
        return fail("no such issue #{digits}")
    if v.get(0) == 0:
        return fail("bad issue id '{arg}'")

    return ok(v.get(0))

fn index_of_id(st: Store, id: Int) Result[Int, Failure]:
    for k in 0..st.issues.length():
        if st.issues[k].id == id:
            return ok(k)
    return fail("no such issue #{id}")

fn is_final_state(st: Store, s: String) Bool:
    return st.wf.finals.contains(s)

fn has_state(st: Store, s: String) Bool:
    return st.wf.states.contains(s)

fn state_rank(states: List[String], s: String) Int:
    return states.index_of(s).get(0)

fn log_add(var st: Store, id: Int, detail: String) Unit:
    st.log.append(
        LogEntry(t: st.clock, actor: st.actor.clone(), id: id, detail: detail)
    )

# ---------- patches, diffs and edits ----------

fn parse_patch(toks: List[String], start: Int) Result[Patch, Failure]:
    var p = Patch()
    var k = start

    while k < toks.length():
        let tok = toks[k].clone()
        k += 1

        let parts = tok.split("=")
        if parts.length() < 2 or parts[0].length() == 0:
            return fail("expected field=value, got '{tok}'")

        let field = parts[0].clone()
        let value = tail_list(parts, 1).join("=")
        if field == "state":
            return fail("use move to change state")

        if field == "title":
            if is_blank(value):
                return fail("empty title")

            p.title = some(value)
        else if field == "priority":
            let r = prio_rank(value)
            if r < 0:
                return fail("bad priority '{value}'")

            p.priority = some(r)
        else if field == "assignee":
            if value == "none":
                p.assignee = some("")
            else if is_blank(value):
                return fail("empty assignee")
            else:
                p.assignee = some(value)
        else if field == "points":
            if value == "none":
                p.points = some(-1)
            else:
                let v = int_value(value)
                if v.is_none():
                    return fail("bad points '{value}'")

                p.points = v
        else if field == "due":
            if value == "none":
                p.due = some("")
            else if not valid_date(value):
                return fail("bad date '{value}'")
            else:
                p.due = some(value)
        else if field == "labels":
            if value.length() == 0 or value == "none":
                p.labels = some(List[String]())
            else:
                let ls = normalize_labels(value.split(","))
                if ls.is_error():
                    return fail(ls.err().message())

                p.labels = some(ls.get().clone())
        else if field == "reporter":
            if value == "none":
                p.reporter = some("")
            else if is_blank(value):
                return fail("empty reporter")
            else:
                p.reporter = some(value)
        else:
            return fail("unknown field '{field}'")

    return ok(p)

fn apply_patch(old: Issue, p: Patch) Issue:
    var it = old.clone()
    if let v = p.title:
        it.title = v.clone()
    if let v = p.priority:
        it.priority = v
    if let v = p.assignee:
        it.assignee = v.clone()
    if let v = p.points:
        it.points = v
    if let v = p.due:
        it.due = v.clone()
    if let v = p.labels:
        it.labels = v.clone()
    if let v = p.reporter:
        it.reporter = v.clone()
    return it

fn diff_lines(a: Issue, b: Issue) List[String]:
    var out = List[String]()
    if a.title != b.title:
        out.append("title: {a.title} -> {b.title}")
    if a.priority != b.priority:
        out.append("priority: {prio_name(a.priority)} -> {prio_name(b.priority)}")
    if a.assignee != b.assignee:
        out.append("assignee: {dash(a.assignee)} -> {dash(b.assignee)}")
    if a.points != b.points:
        out.append("points: {pts_text(a.points)} -> {pts_text(b.points)}")
    if a.due != b.due:
        out.append("due: {dash(a.due)} -> {dash(b.due)}")

    let la = labels_text(a.labels, ",")
    let lb = labels_text(b.labels, ",")
    if la != lb:
        out.append("labels: {la} -> {lb}")
    if a.reporter != b.reporter:
        out.append("reporter: {dash(a.reporter)} -> {dash(b.reporter)}")
    return out

fn apply_edit(var st: Store, idx: Int, p: Patch) Result[String, Failure]:
    let after = apply_patch(st.issues[idx], p)
    let details = diff_lines(st.issues[idx], after)
    let id = st.issues[idx].id
    if details.length() == 0:
        return ok("#{id} unchanged")

    st.clock += 1

    var it = after
    it.updated = st.clock
    st.issues[idx] = it
    for d in details:
        log_add(var st, id, d)
    return ok("updated #{id}")

fn op_edit(var st: Store, id: Int, toks: List[String], start: Int) Result[
    String, Failure
]:
    let idx = try index_of_id(st, id)
    let state = st.issues[idx].state.clone()
    if is_final_state(st, state):
        return fail("#{id} is in final state '{state}'")

    let p = try parse_patch(toks, start)
    if toks.length() <= start:
        return fail("usage: edit ID field=value...")

    return apply_edit(var st, idx, p)

fn op_assign(var st: Store, id: Int, name: String) Result[String, Failure]:
    let toks = ["assignee=" + name]
    return op_edit(var st, id, toks, 0)

fn op_label(var st: Store, id: Int, ops: List[String]) Result[String, Failure]:
    let idx = try index_of_id(st, id)
    let state = st.issues[idx].state.clone()
    if is_final_state(st, state):
        return fail("#{id} is in final state '{state}'")

    var labels = st.issues[idx].labels.clone()

    for tok in ops:
        var name = tok.clone()
        var adding = true

        if tok.starts_with("-"):
            adding = false
            name = sub_from(tok, 1)
        else if tok.starts_with("+"):
            name = sub_from(tok, 1)

        let l = name.lower()
        if not valid_label(l):
            return fail("bad label '{l}'")

        if adding:
            if not labels.contains(l):
                labels.append(l)
        else:
            if let g = labels.index_of(l):
                labels.remove(g)

    labels.sort()
    return apply_edit(var st, idx, Patch(labels: some(labels)))

fn op_move(var st: Store, id: Int, to: String, comment: String) Result[String, Failure]:
    let idx = try index_of_id(st, id)
    let from = st.issues[idx].state.clone()
    if is_final_state(st, from):
        return fail("#{id} is in final state '{from}'")
    if not has_state(st, to):
        return fail("unknown state '{to}'")
    if from == to:
        return fail("already in state '{to}'")

    var guards = List[String]()
    var allowed = false

    for tr in st.wf.trans:
        if tr.src == from and tr.dst == to:
            allowed = true
            guards = tr.guards.clone()
            break

    if not allowed:
        return fail("transition '{from} -> {to}' not allowed")

    var missing = List[String]()

    for g in guards:
        let it = st.issues[idx]
        var unmet = false

        if g == "assignee":
            unmet = it.assignee.length() == 0
        else if g == "points":
            unmet = it.points < 0
        else if g == "due":
            unmet = it.due.length() == 0
        else if g == "labels":
            unmet = it.labels.length() == 0
        else if g == "reporter":
            unmet = it.reporter.length() == 0

        if unmet:
            missing.append(g.clone())

    if missing.length() > 0:
        let names = missing.join(", ")
        return fail("cannot move #{id} to {to}: missing {names}")

    st.clock += 1

    let t = st.clock
    st.issues[idx].state = to.clone()
    st.issues[idx].updated = t
    log_add(var st, id, "state: {from} -> {to}")

    if comment.length() > 0:
        st.issues[idx].comments.append(
            IssueComment(
                t: t, actor: st.actor.clone(), text: comment.clone()
            )
        )
        log_add(var st, id, "comment: {comment}")

    return ok("moved #{id}: {from} -> {to}")

# ---------- workflow ----------

fn add_state(var states: List[String], name: String) Unit:
    if not states.contains(name):
        states.append(name.clone())

fn valid_guard(g: String) Bool:
    return ["assignee", "points", "due", "labels", "reporter"].contains(g)

fn cmd_workflow(var st: Store, block: List[String]) Result[String, Failure]:
    if st.next_id > 1:
        return fail("workflow: cannot redefine after issues were created")

    var states = List[String]()
    var finals = List[String]()
    var trans = List[Trans]()
    var initial = ""
    var have_initial = false

    for raw in block:
        let line = raw.trim()
        if line.length() == 0 or line.starts_with("#"):
            continue

        if line.starts_with("initial:"):
            let name = sub_from(line, 8).trim()
            if not valid_state(name):
                return fail("workflow: bad state name '{name}'")
            if have_initial:
                return fail("workflow: initial state defined twice")

            have_initial = true
            initial = name.clone()
            add_state(var states, name)
        else if line.starts_with("final:"):
            for part in sub_from(line, 6).split(","):
                let name = part.trim()
                if not valid_state(name):
                    return fail("workflow: bad state name '{name}'")

                add_state(var states, name)
                finals.append(name.clone())
        else if line.contains("->"):
            let parts = line.split("->")
            if parts.length() != 2:
                return fail("workflow: bad line '{line}'")

            let src = parts[0].trim()
            if not valid_state(src):
                return fail("workflow: bad state name '{src}'")

            add_state(var states, src)

            for entry in parts[1].split(","):
                let ws = words(entry)
                if ws.length() == 0:
                    return fail("workflow: bad line '{line}'")

                let dst = ws[0].clone()
                if not valid_state(dst):
                    return fail("workflow: bad state name '{dst}'")

                var guards = List[String]()

                if ws.length() == 3 and ws[1] == "requires":
                    for g in ws[2].split("+"):
                        if not valid_guard(g):
                            return fail("workflow: bad guard field '{g}'")

                        guards.append(g.clone())
                else if ws.length() != 1:
                    return fail("workflow: bad line '{line}'")

                add_state(var states, dst)
                trans.append(Trans(src: src.clone(), dst: dst, guards: guards))
        else:
            return fail("workflow: bad line '{line}'")

    if not have_initial:
        return fail("workflow: initial state missing")

    for tr in trans:
        if finals.contains(tr.src):
            return fail("workflow: '{tr.src}' is final and cannot have transitions")

    let n_states = states.length()
    let n_trans = trans.length()
    st.wf = Workflow(
        defined: true, states: states, initial: initial, finals: finals, trans: trans
    )
    return ok("workflow ok: {n_states} states, {n_trans} transitions")

# ---------- filter language ----------

fn tok_punct(kind: Int, text: String) Tok:
    return Tok(kind: kind, field: "", op: "", value: "", quoted: false, text: text)

fn tok_term(field: String, op: String, value: String, quoted: Bool) Tok:
    return Tok(
        kind: K_TERM, field: field, op: op, value: value, quoted: quoted, text: ""
    )

fn tok_bad(msg: String) Tok:
    return Tok(kind: K_BAD, field: "", op: "", value: "", quoted: false, text: msg)

fn op_at(cs: List[String], j: Int) String:
    if j + 1 < cs.length():
        let two = cs[j] + cs[j + 1]
        if two == "!=" or two == "<=" or two == ">=":
            return two

    if j < cs.length():
        let one = cs[j]
        if one == ":" or one == "<" or one == ">" or one == "~":
            return one.clone()

    return ""

fn lex(text: String) List[Tok]:
    let cs = text.chars()
    let n = cs.length()
    var out = List[Tok]()
    var i = 0

    while i < n:
        let c = cs[i]

        if is_ws(c):
            i += 1
            continue

        if c == "(":
            out.append(tok_punct(K_OPEN, "("))
            i += 1
            continue

        if c == ")":
            out.append(tok_punct(K_CLOSE, ")"))
            i += 1
            continue

        var j = i
        while j < n and "abcdefghijklmnopqrstuvwxyz_".contains(cs[j]):
            j += 1

        let field = chars_to_str(cs, i, j)
        let op = op_at(cs, j)

        if field.length() > 0 and op.length() > 0:
            let k = j + op.length()

            if k < n and cs[k] == "\"":
                var val = ""
                var q = k + 1
                var closed = false

                while q < n:
                    if (
                        cs[q] == "\\"
                        and q + 1 < n
                        and (
                            cs[q + 1] == "\""
                            or cs[q + 1] == "\\"
                        )
                    ):
                        val += cs[q + 1]
                        q += 2
                    else if cs[q] == "\"":
                        closed = true
                        break
                    else:
                        val += cs[q]
                        q += 1

                if not closed:
                    out.append(tok_bad("query: unterminated quote"))
                    return out

                out.append(tok_term(field, op, val, true))
                i = q + 1
                continue

            var e = k
            while e < n and not is_ws(cs[e]) and cs[e] != "(" and cs[e] != ")":
                e += 1

            if e > k:
                out.append(tok_term(field, op, chars_to_str(cs, k, e), false))
                i = e
                continue

        var end = i
        while end < n and not is_ws(cs[end]) and cs[end] != "(" and cs[end] != ")":
            end += 1

        let word = chars_to_str(cs, i, end)

        if word == "AND":
            out.append(tok_punct(K_AND, word))
        else if word == "OR":
            out.append(tok_punct(K_OR, word))
        else if word == "NOT":
            out.append(tok_punct(K_NOT, word))
        else:
            out.append(tok_bad("query: unexpected token '{word}'"))

        i = end

    return out

fn field_ops(field: String) List[String]:
    if (
        field == "id"
        or field == "created"
        or field == "updated"
        or field == "points"
        or field == "priority"
        or field == "due"
    ):
        return [":", "!=", "<", "<=", ">", ">="]
    if (
        field == "title"
        or field == "assignee"
        or field == "reporter"
        or field == "label"
        or field == "labels"
    ):
        return [":", "!=", "~"]
    if field == "text":
        return ["~"]
    if field == "state":
        return [":", "!="]
    if field == "is" or field == "has" or field == "view":
        return [":"]

    return List[String]()

fn value_ok(st: Store, field: String, op: String, v: String) Bool:
    if field == "id" or field == "created" or field == "updated":
        return int_value(v).is_some()

    if field == "points":
        if v == "none":
            return op == ":" or op == "!="

        return int_value(v).is_some()

    if field == "priority":
        return prio_rank(v) >= 0

    if field == "due":
        if v == "none":
            return op == ":" or op == "!="

        return valid_date(v)

    if field == "state":
        return has_state(st, v)
    if field == "is":
        return ["open", "final", "overdue", "unassigned"].contains(v)
    if field == "has":
        return ["assignee", "due", "points", "labels", "comments", "reporter"].contains(
            v
        )

    return true

fn check_term(
    st: Store,
    field: String,
    op: String,
    value: String,
    quoted: Bool
) Result[Unit, Failure]:
    let ops = field_ops(field)
    if ops.length() == 0:
        return fail("query: unknown field '{field}'")
    if not ops.contains(op):
        return fail("query: bad operator '{op}' for field '{field}'")

    let ordering = op == "<" or op == "<=" or op == ">" or op == ">="
    var alts = List[String]()

    if not quoted and not ordering and value.contains("|"):
        alts = value.split("|")
    else:
        alts.append(value.clone())

    for alt in alts:
        if not value_ok(st, field, op, alt):
            return fail("query: bad value '{alt}' for field '{field}'")
    return ok(unit)

fn build_term(st: Store, t: Tok) Result[Node, Failure]:
    if t.field == "view":
        if t.op != ":":
            return fail("query: bad operator '{t.op}' for field 'view'")
        if not st.views.contains(t.value):
            return fail("query: unknown view '{t.value}'")

        let cl = try split_query(st.views.get_or(t.value, ""))
        let inner = try parse_filter(st, cl.filter)
        return ok(Inline(inner))

    let _checked = try check_term(st, t.field, t.op, t.value, t.quoted)
    return ok(
        Term(
            field: t.field.clone(), op: t.op.clone(), value: t.value.clone(),
            quoted: t.quoted
        )
    )

fn peek_kind(p: Parser) Int:
    if p.pos >= p.toks.length():
        return -1

    return p.toks[p.pos].kind

fn parse_or(var p: Parser, st: Store) Result[Node, Failure]:
    var left = try parse_and(var p, st)

    while peek_kind(p) == K_OR:
        p.pos += 1

        let right = try parse_and(var p, st)
        left = Either(left, right)

    return ok(left)

fn parse_and(var p: Parser, st: Store) Result[Node, Failure]:
    var left = try parse_not(var p, st)

    while true:
        let k = peek_kind(p)

        if k == K_AND:
            p.pos += 1
        else if k != K_TERM and k != K_NOT and k != K_OPEN and k != K_BAD:
            break

        let right = try parse_not(var p, st)
        left = Both(left, right)

    return ok(left)

fn parse_not(var p: Parser, st: Store) Result[Node, Failure]:
    if peek_kind(p) == K_NOT:
        p.pos += 1

        let inner = try parse_not(var p, st)
        return ok(Negate(inner))

    return parse_primary(var p, st)

fn parse_primary(var p: Parser, st: Store) Result[Node, Failure]:
    if p.pos >= p.toks.length():
        return fail("query: unexpected end of query")

    let t = p.toks[p.pos].clone()
    p.pos += 1
    if t.kind == K_TERM:
        return build_term(st, t)

    if t.kind == K_OPEN:
        let inner = try parse_or(var p, st)
        if p.pos >= p.toks.length():
            return fail("query: unexpected end of query")

        p.pos += 1
        return ok(inner)

    if t.kind == K_BAD:
        return fail(t.text.clone())

    return fail("query: unexpected token '{t.text}'")

fn parse_filter(st: Store, text: String) Result[Node, Failure]:
    if is_blank(text):
        return ok(Everything)

    var p = Parser(toks: lex(text), pos: 0)
    let node = try parse_or(var p, st)
    if p.pos < p.toks.length():
        return fail("query: unexpected token ')'")

    return ok(node)

fn cmp_op(a: Int, op: String, b: Int) Bool:
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

    return false

fn str_op(a: String, op: String, b: String) Bool:
    return cmp_op(a.compare(b), op, 0)

fn text_op(a: String, op: String, v: String) Bool:
    if op == "~":
        return contains_ci(a, v)

    return a.lower() == v.lower()

fn one_match(field: String, op: String, v: String, it: Issue, st: Store) Bool:
    if field == "id":
        return cmp_op(it.id, op, int_value(v).get(0))
    if field == "created":
        return cmp_op(it.created, op, int_value(v).get(0))
    if field == "updated":
        return cmp_op(it.updated, op, int_value(v).get(0))

    if field == "points":
        if v == "none":
            return it.points < 0
        if it.points < 0:
            return false

        return cmp_op(it.points, op, int_value(v).get(0))

    if field == "title":
        return text_op(it.title, op, v)

    if field == "assignee":
        if it.assignee.length() == 0:
            return op == ":" and v.lower() == "none"

        return text_op(it.assignee, op, v)

    if field == "reporter":
        if it.reporter.length() == 0:
            return op == ":" and v.lower() == "none"

        return text_op(it.reporter, op, v)

    if field == "text":
        if contains_ci(it.title, v):
            return true

        for c in it.comments:
            if contains_ci(c.text, v):
                return true
        return false

    if field == "state":
        return it.state == v
    if field == "priority":
        return cmp_op(it.priority, op, prio_rank(v))

    if field == "due":
        if v == "none":
            return it.due.length() == 0
        if it.due.length() == 0:
            return false

        return str_op(it.due, op, v)

    if field == "label" or field == "labels":
        if op == "~":
            for l in it.labels:
                if contains_ci(l, v):
                    return true
            return false

        if v.lower() == "none":
            return it.labels.length() == 0

        return it.labels.contains(v.lower())

    if field == "is":
        let fin = is_final_state(st, it.state)
        if v == "open":
            return not fin
        if v == "final":
            return fin
        if v == "overdue":
            return not fin and it.due.length() > 0 and str_op(it.due, "<", st.today)
        if v == "unassigned":
            return it.assignee.length() == 0

        return false

    if field == "has":
        if v == "assignee":
            return it.assignee.length() > 0
        if v == "due":
            return it.due.length() > 0
        if v == "points":
            return it.points >= 0
        if v == "labels":
            return it.labels.length() > 0
        if v == "comments":
            return it.comments.length() > 0
        if v == "reporter":
            return it.reporter.length() > 0

        return false

    return false

fn term_any(
    field: String,
    op: String,
    value: String,
    quoted: Bool,
    it: Issue,
    st: Store
) Bool:
    let ordering = op == "<" or op == "<=" or op == ">" or op == ">="
    if quoted or ordering or not value.contains("|"):
        return one_match(field, op, value, it, st)

    for alt in value.split("|"):
        if one_match(field, op, alt, it, st):
            return true
    return false

fn matches(n: Node, it: Issue, st: Store) Bool:
    match n:
        Term(field, op, value, quoted):
            if op == "!=":
                return not term_any(field, ":", value, quoted, it, st)

            return term_any(field, op, value, quoted, it, st)
        Both(left, right):
            return matches(left, it, st) and matches(right, it, st)
        Either(left, right):
            return matches(left, it, st) or matches(right, it, st)
        Negate(inner):
            return not matches(inner, it, st)
        Inline(inner):
            return matches(inner, it, st)
        Everything:
            return true

# Splits "FILTER sort FIELDS limit N" textually; limit is recognised first.
fn split_query(text: String) Result[Clauses, Failure]:
    let t = text.trim()
    let cs = t.chars()
    let n = cs.length()
    var body = t.clone()
    var limit = -1
    var j = n
    while j > 0 and not is_ws(cs[j - 1]):
        j -= 1

    if j > 0:
        var k = j
        while k > 0 and is_ws(cs[k - 1]):
            k -= 1

        var m = k
        while m > 0 and not is_ws(cs[m - 1]):
            m -= 1

        if k < j and chars_to_str(cs, m, k) == "limit":
            let lim = chars_to_str(cs, j, n)
            let v = int_value(lim)
            if v.is_none():
                return fail("bad limit '{lim}'")

            limit = v.get(0)
            body = chars_to_str(cs, 0, m).trim()

    var sort = ""
    let bcs = body.chars()
    let pos = word_pos(body, "sort")

    if pos >= 0 and pos + 4 < bcs.length() and is_ws(bcs[pos + 4]):
        sort = chars_to_str(bcs, pos + 4, bcs.length()).trim()
        body = chars_to_str(bcs, 0, pos).trim()

    return ok(Clauses(filter: body, sort: sort, limit: limit))

fn sort_keys(text: String) Result[List[SortKey], Failure]:
    var keys = List[SortKey]()

    for w in words(text.replace(",", " ")):
        var desc = false
        var name = w.clone()

        if w.starts_with("-"):
            desc = true
            name = sub_from(w, 1)

        if not [
            "id", "created", "updated", "priority", "points", "state", "title",
            "assignee", "reporter", "due"
        ].contains(name):
            return fail("bad sort field '{name}'")

        keys.append(SortKey(field: name, desc: desc))

    return ok(keys)

fn cmp_int(a: Int, b: Int) Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

fn cmp_absent_int(a: Int, b: Int) Int:
    if a < 0 and b < 0:
        return 0
    if a < 0:
        return 1
    if b < 0:
        return -1

    return cmp_int(a, b)

fn cmp_absent_str(a: String, b: String) Int:
    if a.length() == 0 and b.length() == 0:
        return 0
    if a.length() == 0:
        return 1
    if b.length() == 0:
        return -1

    return a.compare(b)

fn compare_field(a: Issue, b: Issue, field: String, states: List[String]) Int:
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
        return cmp_int(state_rank(states, a.state), state_rank(states, b.state))
    if field == "title":
        return a.title.lower().compare(b.title.lower())
    if field == "assignee":
        return cmp_absent_str(a.assignee.lower(), b.assignee.lower())
    if field == "reporter":
        return cmp_absent_str(a.reporter.lower(), b.reporter.lower())

    return cmp_absent_str(a.due, b.due)

fn compare_issues(a: Issue, b: Issue, keys: List[SortKey], states: List[String]) Int:
    for k in keys:
        let c = compare_field(a, b, k.field, states)

        if c != 0:
            if k.desc:
                return 0 - c

            return c

    return cmp_int(a.id, b.id)

fn issue_line(it: Issue) String:
    let labels = labels_text(it.labels, ",")
    return "#{it.id} | {it.state} | {prio_name(it.priority)} | {dash(it.assignee)} | {pts_text(it.points)} | {dash(it.due)} | {labels} | {it.title}"

fn run_list(
    st: Store,
    node: Node,
    keys: List[SortKey],
    limit: Int
) Result[String, Failure]:
    var rows = List[Issue]()
    for it in st.issues:
        if matches(node, it, st):
            rows.append(it.clone())

    let states = st.wf.states.clone()
    rows.sort(fn(a: Issue, b: Issue) Int: compare_issues(a, b, keys, states))

    var lines = List[String]()

    for it in rows:
        if limit >= 0 and lines.length() >= limit:
            break

        lines.append(issue_line(it))

    let shown = lines.length()
    lines.append(count_text(shown))
    return ok(lines.join("\n"))

fn cmd_list(st: Store, rest: String) Result[String, Failure]:
    let cl = try split_query(rest)
    let node = try parse_filter(st, cl.filter)
    let keys = try sort_keys(cl.sort)
    return run_list(st, node, keys, cl.limit)

# ---------- views ----------

fn view_refs(text: String) List[String]:
    var out = List[String]()
    for t in lex(text):
        if t.kind == K_TERM and t.field == "view":
            out.append(t.value.clone())
    return out

fn reaches(st: Store, text: String, target: String, depth: Int) Bool:
    if depth > 100:
        return false

    for r in view_refs(text):
        if r == target:
            return true

        if st.views.contains(r):
            if reaches(st, st.views.get_or(r, ""), target, depth + 1):
                return true

    return false

fn view_save(var st: Store, name: String, query: String) Result[String, Failure]:
    if not valid_view_name(name):
        return fail("bad view name '{name}'")

    let cl = try split_query(query)
    let _node = try parse_filter(st, cl.filter)
    let _keys = try sort_keys(cl.sort)
    let text = query.trim()
    if reaches(st, text, name, 0):
        return fail("view '{name}' would reference itself")

    st.views[name.clone()] = text.clone()
    return ok("saved view {name}")

fn view_run(st: Store, name: String, extra: String) Result[String, Failure]:
    if not st.views.contains(name):
        return fail("unknown view '{name}'")

    let stored = st.views.get_or(name, "")
    let base = try split_query(stored)
    let more = try split_query(extra)
    if more.filter.length() > 0:
        return fail("unexpected '{more.filter}'")

    let base_limit = base.limit
    var limit = base_limit
    if more.limit >= 0:
        limit = more.limit

    var sort = base.sort.clone()
    if more.sort.length() > 0:
        sort = more.sort.clone()

    let node = try parse_filter(st, base.filter)
    let keys = try sort_keys(sort)
    return run_list(st, node, keys, limit)

fn view_list(st: Store) String:
    let names = st.views.keys().sorted()
    if names.length() == 0:
        return "(no views)"

    var lines = List[String]()
    for n in names:
        lines.append(n + ": " + st.views.get_or(n, ""))
    return lines.join("\n")

fn view_show(st: Store, name: String) Result[String, Failure]:
    if not st.views.contains(name):
        return fail("unknown view '{name}'")

    return ok(name + ": " + st.views.get_or(name, ""))

fn view_delete(var st: Store, name: String) Result[String, Failure]:
    if not st.views.contains(name):
        return fail("unknown view '{name}'")

    for other in st.views.keys().sorted():
        if other != name and reaches(st, st.views.get_or(other, ""), name, 0):
            return fail("view '{name}' is used by '{other}'")
    st.views.remove(name.clone())
    return ok("deleted view {name}")

fn cmd_view(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    let general = "usage: view save|run|list|show|delete"
    if w.length() == 0:
        return fail(general)

    let sub = w[0].clone()

    if sub == "save":
        if w.length() < 2:
            return fail("usage: view save NAME QUERY")

        return view_save(var st, w[1].clone(), drop_words(rest, 2))

    if sub == "run":
        if w.length() < 2:
            return fail("usage: view run NAME [sort FIELDS] [limit N]")

        return view_run(st, w[1].clone(), drop_words(rest, 2))

    if sub == "list":
        if w.length() != 1:
            return fail(general)

        return ok(view_list(st))

    if sub == "show":
        if w.length() != 2:
            return fail("usage: view show NAME")

        return view_show(st, w[1].clone())

    if sub == "delete":
        if w.length() != 2:
            return fail("usage: view delete NAME")

        return view_delete(var st, w[1].clone())

    return fail(general)

# ---------- issue commands ----------

fn cmd_actor(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() != 1:
        return fail("usage: actor NAME")

    st.actor = w[0].clone()
    return ok("actor is {st.actor}")

fn cmd_today(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() != 1:
        return fail("usage: today DATE")
    if not valid_date(w[0]):
        return fail("bad date '{w[0]}'")

    st.today = w[0].clone()
    return ok("today is {st.today}")

fn cmd_create(var st: Store, rest: String) Result[String, Failure]:
    if not st.wf.defined:
        return fail("no workflow defined")

    let toks = try tokenize(rest)
    if toks.length() == 0:
        return fail("usage: create TITLE [field=value...]")
    if is_blank(toks[0]):
        return fail("empty title")

    let id = st.next_id
    let base = Issue(
        id: id, title: toks[0].clone(), state: st.wf.initial.clone(), priority: 1,
        assignee: "", reporter: st.actor.clone(), points: -1, due: "",
        labels: List[String](), comments: List[IssueComment](), created: st.clock + 1,
        updated: st.clock + 1
    )
    let p = try parse_patch(toks, 1)
    let made = apply_patch(base, p)
    let details = diff_lines(base, made)
    st.clock += 1
    st.next_id += 1
    log_add(var st, id, "created \"" + toks[0] + "\"")
    for d in details:
        log_add(var st, id, d)
    st.issues.append(made)
    return ok("created #{id}")

fn tokenize(text: String) Result[List[String], Failure]:
    let cs = text.chars()
    var out = List[String]()
    var cur = ""
    var has = false
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
                continue

            if c == "\"":
                inq = false
            else:
                cur += c
        else if c == "\"":
            inq = true
            has = true
        else if is_ws(c):
            if has:
                out.append(cur)
                cur = ""
                has = false
        else:
            cur += c
            has = true

        i += 1

    if inq:
        return fail("unterminated quote")

    if has:
        out.append(cur)
    return ok(out)

fn cmd_edit(var st: Store, rest: String) Result[String, Failure]:
    let toks = try tokenize(rest)
    if toks.length() == 0:
        return fail("usage: edit ID field=value...")

    let id = try parse_id(toks[0])
    return op_edit(var st, id, toks, 1)

fn cmd_assign(var st: Store, rest: String) Result[String, Failure]:
    let toks = try tokenize(rest)
    if toks.length() != 2:
        return fail("usage: assign ID NAME")

    let id = try parse_id(toks[0])
    return op_assign(var st, id, toks[1])

fn cmd_label(var st: Store, rest: String) Result[String, Failure]:
    let toks = try tokenize(rest)
    if toks.length() < 2:
        return fail("usage: label ID +label -label...")

    let id = try parse_id(toks[0])
    return op_label(var st, id, tail_list(toks, 1))

fn cmd_move(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() < 2:
        return fail("usage: move ID STATE [comment...]")

    let id = try parse_id(w[0])
    return op_move(var st, id, w[1].clone(), drop_words(rest, 2))

fn cmd_comment(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() < 2:
        return fail("usage: comment ID TEXT")

    let id = try parse_id(w[0])
    let idx = try index_of_id(st, id)
    let text = drop_words(rest, 1)
    st.clock += 1
    st.issues[idx].comments.append(
        IssueComment(t: st.clock, actor: st.actor.clone(), text: text.clone())
    )
    st.issues[idx].updated = st.clock
    log_add(var st, id, "comment: {text}")
    return ok("commented #{id}")

fn cmd_delete(var st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() != 1:
        return fail("usage: delete ID")

    let id = try parse_id(w[0])
    let idx = try index_of_id(st, id)
    st.issues.remove(idx)
    st.clock += 1
    log_add(var st, id, "deleted")
    return ok("deleted #{id}")

fn cmd_show(st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    if w.length() != 1:
        return fail("usage: show ID")

    let id = try parse_id(w[0])
    let idx = try index_of_id(st, id)
    let it = st.issues[idx]
    let lt = labels_text(it.labels, ", ")
    var lines = List[String]()
    lines.append("#{it.id} {it.title}")
    lines.append("  state: {it.state}")
    lines.append("  priority: {prio_name(it.priority)}")
    lines.append("  assignee: {dash(it.assignee)}")
    lines.append("  points: {pts_text(it.points)}")
    lines.append("  due: {dash(it.due)}")
    lines.append("  labels: {lt}")
    lines.append("  reporter: {dash(it.reporter)}")
    lines.append("  created: t={it.created}, updated: t={it.updated}")
    lines.append("  comments: {it.comments.length()}")
    for c in it.comments:
        lines.append("    [t={c.t} {c.actor}] {c.text}")
    return ok(lines.join("\n"))

fn cmd_log(st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    let usage = "usage: log [ID] [tail N]"
    var id = -1
    var tail = -1

    if w.length() == 0:
        id = -1
    else if w[0] == "tail":
        if w.length() != 2:
            return fail(usage)

        let v = int_value(w[1])
        if v.is_none():
            return fail("bad tail '{w[1]}'")

        tail = v.get(0)
    else:
        id = try parse_id(w[0])
        if id >= st.next_id:
            return fail("no such issue #{id}")

        if w.length() == 3 and w[1] == "tail":
            let v = int_value(w[2])
            if v.is_none():
                return fail("bad tail '{w[2]}'")

            tail = v.get(0)
        else if w.length() != 1:
            return fail(usage)

    var lines = List[String]()
    for e in st.log:
        if id < 0 or e.id == id:
            lines.append("t={e.t} {e.actor} #{e.id} {e.detail}")

    var start = 0
    if tail >= 0 and lines.length() > tail:
        start = lines.length() - tail

    var out = List[String]()
    for k in start..lines.length():
        out.append(lines[k].clone())
    if out.length() == 0:
        return ok("(no log entries)")

    return ok(out.join("\n"))

# ---------- bulk ----------

fn bulk_one(var st: Store, verb: String, args: List[String], id: Int) Result[
    String, Failure
]:
    if verb == "move":
        return op_move(var st, id, args[0].clone(), "")
    if verb == "assign":
        return op_assign(var st, id, args[0].clone())
    if verb == "label":
        return op_label(var st, id, args)

    return op_edit(var st, id, args, 0)

fn cmd_bulk(var st: Store, rest: String) Result[String, Failure]:
    let usage = "usage: bulk ACTION... where QUERY"
    let pos = word_pos(rest, "where")
    if pos < 0:
        return fail(usage)

    let cs = rest.chars()
    let head = chars_to_str(cs, 0, pos)
    let query = chars_to_str(cs, pos + 5, cs.length())
    if is_blank(head):
        return fail(usage)

    let toks = try tokenize(head)
    let verb = toks[0].clone()
    let args = tail_list(toks, 1)

    if verb == "move":
        if args.length() != 1:
            return fail("usage: bulk move STATE where QUERY")
    else if verb == "assign":
        if args.length() != 1:
            return fail("usage: bulk assign NAME where QUERY")
    else if verb == "label":
        if args.length() == 0:
            return fail("usage: bulk label +label... where QUERY")
    else if verb == "set":
        if args.length() == 0:
            return fail("usage: bulk set field=value... where QUERY")
    else:
        return fail("unknown bulk action '{verb}'")

    let node = try parse_filter(st, query)
    var ids = List[Int]()
    for it in st.issues:
        if matches(node, it, st):
            ids.append(it.id)

    var out = List[String]()
    var ok_n = 0
    var bad_n = 0

    for id in ids:
        let r = bulk_one(var st, verb, args, id)

        if r.is_ok():
            out.append(r.get().clone())
            ok_n += 1
        else:
            out.append("#{id} error: {r.err().message()}")
            bad_n += 1

    out.append("bulk: {ok_n} ok, {bad_n} failed")
    return ok(out.join("\n"))

# ---------- reports ----------

fn count_state(st: Store, s: String) Int:
    var n = 0
    for it in st.issues:
        if it.state == s:
            n += 1
    return n

fn count_priority(st: Store, r: Int) Int:
    var n = 0
    for it in st.issues:
        if it.priority == r:
            n += 1
    return n

fn report_summary(st: Store) String:
    var fin = 0
    var unassigned = 0
    var overdue = 0
    var open_pts = 0

    for it in st.issues:
        if is_final_state(st, it.state):
            fin += 1
        else:
            if it.assignee.length() == 0:
                unassigned += 1
            if it.due.length() > 0 and str_op(it.due, "<", st.today):
                overdue += 1
            if it.points >= 0:
                open_pts += it.points

    let total = st.issues.length()
    let open_n = total - fin
    var lines = List[String]()
    lines.append("issues: {total} (open {open_n}, final {fin})")
    lines.append("by state:")

    for s in st.wf.states:
        let n = count_state(st, s)
        lines.append("  {s}: {n}")

    lines.append("by priority:")

    for r in [3, 2, 1, 0]:
        let n = count_priority(st, r)
        let name = prio_name(r)
        lines.append("  {name}: {n}")

    lines.append("unassigned: {unassigned}")
    lines.append("overdue: {overdue}")
    lines.append("open points: {open_pts}")
    return lines.join("\n")

fn cmp_group(a: Group, b: Group) Int:
    if a.points != b.points:
        return b.points - a.points
    if a.count != b.count:
        return b.count - a.count

    return a.name.lower().compare(b.name.lower())

fn report_workload(st: Store) String:
    var keys = List[String]()
    var groups = List[Group]()
    var un_n = 0
    var un_p = 0

    for it in st.issues:
        if is_final_state(st, it.state):
            continue

        var pts = 0
        if it.points >= 0:
            pts = it.points

        if it.assignee.length() == 0:
            un_n += 1
            un_p += pts
            continue

        let key = it.assignee.lower()

        if let g = keys.index_of(key):
            groups[g].count += 1
            groups[g].points += pts
        else:
            keys.append(key)
            groups.append(Group(name: it.assignee.clone(), count: 1, points: pts))

    if groups.length() == 0 and un_n == 0:
        return "(no open issues)"

    groups.sort(fn(a: Group, b: Group) Int: cmp_group(a, b))

    var lines = List[String]()
    for g in groups:
        lines.append("{g.name}: {issues_text(g.count)}, {g.points} points")
    if un_n > 0:
        lines.append("unassigned: {issues_text(un_n)}, {un_p} points")
    return lines.join("\n")

fn cmp_label(a: LabelCount, b: LabelCount) Int:
    if a.count != b.count:
        return b.count - a.count

    return a.name.compare(b.name)

fn report_labels(st: Store, filter: String) Result[String, Failure]:
    let node = try parse_filter(st, filter)
    var names = List[String]()
    var counts = List[Int]()

    for it in st.issues:
        if matches(node, it, st):
            for l in it.labels:
                if let g = names.index_of(l):
                    counts[g] += 1
                else:
                    names.append(l.clone())
                    counts.append(1)

    var groups = List[LabelCount]()
    for k in 0..names.length():
        groups.append(LabelCount(name: names[k].clone(), count: counts[k]))
    if groups.length() == 0:
        return ok("(no labels)")

    groups.sort(fn(a: LabelCount, b: LabelCount) Int: cmp_label(a, b))

    var lines = List[String]()
    for g in groups:
        lines.append("{g.name}: {g.count}")
    return ok(lines.join("\n"))

fn report_timeline(st: Store, idx: Int) String:
    let it = st.issues[idx].clone()
    var lines = List[String]()
    var cur = st.wf.initial.clone()
    let created = it.created
    var since = created

    for e in st.log:
        if e.id == it.id and e.detail.starts_with("state: "):
            let parts = e.detail.split(" -> ")
            let dur = e.t - since
            lines.append("{cur}: t={since}..{e.t} ({dur})")
            cur = parts[1].clone()
            since = e.t

    let dur = st.clock - since
    lines.append("{cur}: t={since}..{st.clock} ({dur})")
    return lines.join("\n")

fn cmd_report(st: Store, rest: String) Result[String, Failure]:
    let w = words(rest)
    let general = "usage: report summary|workload|labels|timeline"
    if w.length() == 0:
        return fail(general)

    let sub = w[0].clone()

    if sub == "summary":
        if w.length() != 1:
            return fail(general)

        return ok(report_summary(st))

    if sub == "workload":
        if w.length() != 1:
            return fail(general)

        return ok(report_workload(st))

    if sub == "labels":
        return report_labels(st, drop_words(rest, 1))

    if sub == "timeline":
        if w.length() != 2:
            return fail("usage: report timeline ID")

        let id = try parse_id(w[1])
        let idx = try index_of_id(st, id)
        return ok(report_timeline(st, idx))

    return fail(general)

# ---------- dispatch ----------

fn dispatch(var st: Store, word: String, rest: String) Result[String, Failure]:
    if word == "actor":
        return cmd_actor(var st, rest)
    if word == "today":
        return cmd_today(var st, rest)
    if word == "create":
        return cmd_create(var st, rest)
    if word == "edit":
        return cmd_edit(var st, rest)
    if word == "label":
        return cmd_label(var st, rest)
    if word == "assign":
        return cmd_assign(var st, rest)
    if word == "move":
        return cmd_move(var st, rest)
    if word == "comment":
        return cmd_comment(var st, rest)
    if word == "delete":
        return cmd_delete(var st, rest)
    if word == "show":
        return cmd_show(st, rest)
    if word == "list":
        return cmd_list(st, rest)
    if word == "view":
        return cmd_view(var st, rest)
    if word == "bulk":
        return cmd_bulk(var st, rest)
    if word == "log":
        return cmd_log(st, rest)
    if word == "report":
        return cmd_report(st, rest)

    return fail("unknown command '{word}'")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var st = Store(
        clock: 0,
        actor: "system",
        today: "1970-01-01",
        next_id: 1,
        wf: Workflow(
            defined: false, states: List[String](), initial: "", finals: List[String](),
            trans: List[Trans]()
        ),
        issues: List[Issue](),
        log: List[LogEntry](),
        views: Map[String, String]()
    )
    var i = 0

    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1

        let body = line.trim_start()
        if body.length() == 0 or body.starts_with("#"):
            continue

        emit("> " + line)

        let ws = words(body)
        let word = ws[0].clone()
        let rest = drop_words(body, 1)

        if word == "workflow":
            var block = List[String]()

            while i < lines.length():
                i += 1
                if lines[i - 1].trim() == "end":
                    break

                block.append(lines[i - 1].clone())

            show_result(cmd_workflow(var st, block))
        else:
            show_result(dispatch(var st, word, rest))

    return 0
