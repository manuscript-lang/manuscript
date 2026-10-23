import stdout from "@std/io.ms"
import read_line from "@std/io.ms"
import stdin from "@std/io.ms"
import range from "@std/collections.ms"

type Fail:
    msg: String

impl Error for Fail:
    fn message() String:
        return self.msg

type Word:
    head: String
    rest: String

type Clause:
    head: String
    found: Bool
    tail: String

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

type Trans:
    src: String
    dst: String
    guards: List[String]

type Entry:
    t: Int
    actor: String
    id: Int
    detail: String

type Update:
    field: String
    norm: String

type Expr:
    case All
    case Term(field: String, op: String, alts: List[String])
    case And(left: Expr, right: Expr)
    case Or(left: Expr, right: Expr)
    case Not(inner: Expr)

type SortKey:
    name: String
    desc: Bool

type Spec:
    filter: Expr
    sort: List[SortKey]
    has_limit: Bool
    limit: Int

type Tok:
    kind: String
    field: String
    op: String
    value: String
    quoted: Bool

type Parser:
    toks: List[Tok]
    pos: Int

type Group:
    key: String
    name: String
    count: Int
    points: Int

type LabelCount:
    name: String
    count: Int

type App:
    t: Int
    today: String
    actor: String
    has_workflow: Bool
    initial: String
    states: List[String]
    finals: List[String]
    trans: List[Trans]
    issues: List[Issue]
    next_id: Int
    journal: List[Entry]
    views: Map[String, String]

fn emit(text: String) Unit:
    stdout().write(text).get()

fn is_space(c: String) Bool:
    return c == " " or c == "\t"

fn join_range(cs: List[String], a: Int, b: Int) String:
    return cs.drop(a).take(b - a).join("")

fn words(text: String) List[String]:
    var out: List[String] = []
    var cur = ""

    for c in text.chars():
        if is_space(c):
            if cur != "":
                out.append(cur)
                cur = ""
        else:
            cur = cur.concat(c)

    if cur != "":
        out.append(cur)
    return out

fn cut_word(text: String) Word:
    let cs = text.chars()
    var i = 0

    while i < cs.length() and not is_space(cs.get(i)):
        i += 1
    return Word(
        head: join_range(cs, 0, i), rest: join_range(cs, i, cs.length()).trim_start()
    )

fn dash(s: String) String:
    if s == "":
        return "-"

    return s

fn opt_text(o: Optional[String]) String:
    if let s = o:
        return s

    return ""

fn opt_show(o: Optional[String]) String:
    return dash(opt_text(o))

fn points_text(o: Optional[Int]) String:
    if let p = o:
        return "{p}"

    return ""

fn sorted_text(xs: List[String]) List[String]:
    return xs.sorted(fn(a: String, b: String) Int: return a.compare(b))

fn unique_sorted(xs: List[String]) List[String]:
    var out: List[String] = []

    for x in xs:
        if not out.contains(x):
            out.append(x)
    return sorted_text(out)

fn digit_value(c: Int) Int:
    return c - 48

fn in_range(c: Int, lo: Int, hi: Int) Bool:
    return c >= lo and c <= hi

fn is_digit_text(c: String) Bool:
    return c.compare("0") >= 0 and c.compare("9") <= 0

fn parse_uint(s: String) Optional[Int]:
    let v = s.scalar_values()
    let n = v.length()
    if n == 0 or n > 7:
        return none
    if n > 1 and v.get(0) == 48:
        return none

    var x = 0

    for i in range(0, n):
        let c = v.get(i)
        if not in_range(c, 48, 57):
            return none

        x = x * 10 + digit_value(c)

    if x > 1000000:
        return none

    return some(x)

fn is_label(s: String) Bool:
    if s == "":
        return false

    for c in s.scalar_values():
        if not (in_range(c, 97, 122) or in_range(c, 48, 57) or c == 95 or c == 45):
            return false
    return true

fn is_state_name(s: String) Bool:
    let v = s.scalar_values()
    if v.length() == 0 or not in_range(v.get(0), 97, 122):
        return false

    for c in v:
        if not (in_range(c, 97, 122) or in_range(c, 48, 57) or c == 95):
            return false
    return true

fn is_view_name(s: String) Bool:
    let v = s.scalar_values()
    if v.length() == 0 or not in_range(v.get(0), 97, 122):
        return false

    for c in v:
        if not (in_range(c, 97, 122) or in_range(c, 48, 57) or c == 95 or c == 45):
            return false
    return true

fn days_in(m: Int, y: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0:
            return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30

    return 31

fn num_at(v: List[Int], a: Int, b: Int) Int:
    var x = 0

    for i in range(a, b):
        x = x * 10 + digit_value(v.get(i))
    return x

fn valid_date(s: String) Bool:
    let v = s.scalar_values()
    if v.length() != 10:
        return false

    for i in range(0, 10):
        let c = v.get(i)

        if i == 4 or i == 7:
            if c != 45:
                return false
        else if not in_range(c, 48, 57):
            return false

    let y = num_at(v, 0, 4)
    let m = num_at(v, 5, 7)
    let d = num_at(v, 8, 10)
    if y < 1 or m < 1 or m > 12:
        return false

    return d >= 1 and d <= days_in(m, y)

fn id_value(digits: String) Int:
    if digits.length() > 9:
        return 1000000000

    return num_at(digits.scalar_values(), 0, digits.length())

fn tokenize(text: String) Result[List[String], Fail]:
    let cs = text.chars()
    var out: List[String] = []
    var cur = ""
    var in_token = false
    var in_quote = false
    var i = 0

    while i < cs.length():
        let c = cs.get(i)

        if in_quote:
            if (
                c == "\\"
                and i + 1 < cs.length()
                and (cs.get(i + 1) == "\"" or cs.get(i + 1) == "\\")
            ):
                cur = cur.concat(cs.get(i + 1))
                i += 1
            else if c == "\"":
                in_quote = false
            else:
                cur = cur.concat(c)
        else if c == "\"":
            in_quote = true
            in_token = true
        else if is_space(c):
            if in_token:
                out.append(cur)
                cur = ""
                in_token = false
        else:
            cur = cur.concat(c)
            in_token = true

        i += 1

    if in_quote:
        return error(Fail(msg: "unterminated quote"))

    if in_token:
        out.append(cur)
    return ok(out)

fn parse_id(arg: String) Result[String, Fail]:
    var cs = arg.chars()

    if cs.length() > 0 and cs.get(0) == "#":
        cs = cs.drop(1)

    var digits_only = cs.length() > 0

    for c in cs:
        if not is_digit_text(c):
            digits_only = false

    var k = 0

    while k < cs.length() and cs.get(k) == "0":
        k += 1

    let digits = cs.drop(k).join("")
    if not digits_only or digits == "":
        return error(Fail(msg: "bad issue id '{arg}'"))

    return ok(digits)

fn find_index(app: App, id: Int) Optional[Int]:
    for i in range(0, app.issues.length()):
        if app.issues.get(i).id == id:
            return some(i)
    return none

fn lookup(app: App, arg: String) Result[Int, Fail]:
    let d = try parse_id(arg)
    let idx = find_index(app, id_value(d))
    if idx.is_none():
        return error(Fail(msg: "no such issue #{d}"))

    return ok(idx.get())

fn state_index(states: List[String], name: String) Int:
    return states.index_of(name).get()

fn is_final(app: App, state: String) Bool:
    return app.finals.contains(state)

fn priority_rank(p: String) Int:
    if p == "low":
        return 0
    if p == "medium":
        return 1
    if p == "high":
        return 2

    return 3

fn is_priority(p: String) Bool:
    return ["low", "medium", "high", "critical"].contains(p)

fn is_field(f: String) Bool:
    return ["title", "priority", "assignee", "points", "due", "labels", "reporter"].contains(
        f
    )

fn field_order() List[String]:
    return ["title", "priority", "assignee", "points", "due", "labels", "reporter"]

fn normalize(field: String, value: String) Result[String, Fail]:
    if field == "title":
        if value.trim() == "":
            return error(Fail(msg: "empty title"))

        return ok(value)

    if field == "priority":
        if not is_priority(value):
            return error(Fail(msg: "bad priority '{value}'"))

        return ok(value)

    if field == "assignee" or field == "reporter":
        if value == "none":
            return ok("")
        if value.trim() == "":
            return error(Fail(msg: "empty {field}"))

        return ok(value)

    if field == "points":
        if value == "none":
            return ok("")

        let p = parse_uint(value)
        if p.is_none():
            return error(Fail(msg: "bad points '{value}'"))

        return ok("{p.get()}")

    if field == "due":
        if value == "none":
            return ok("")
        if not valid_date(value):
            return error(Fail(msg: "bad date '{value}'"))

        return ok(value)

    if value == "none":
        return ok("")

    var labs: List[String] = []

    for item in value.split(","):
        let l = item.lower()
        if not is_label(l):
            return error(Fail(msg: "bad label '{l}'"))

        labs.append(l)

    return ok(unique_sorted(labs).join(","))

fn parse_update(tok: String) Result[Update, Fail]:
    let parts = tok.split("=")
    if parts.length() < 2 or parts.get(0) == "":
        return error(Fail(msg: "expected field=value, got '{tok}'"))

    let field = parts.get(0)
    let value = parts.drop(1).join("=")
    if field == "state":
        return error(Fail(msg: "use move to change state"))
    if not is_field(field):
        return error(Fail(msg: "unknown field '{field}'"))

    let norm = try normalize(field, value)

    return ok(Update(field: field, norm: norm))

fn parse_updates(toks: List[String]) Result[List[Update], Fail]:
    var out: List[Update] = []

    for tok in toks:
        out.append(try parse_update(tok))
    return ok(out)

fn field_norm(it: Issue, field: String) String:
    if field == "title":
        return it.title
    if field == "priority":
        return it.priority
    if field == "assignee":
        return opt_text(it.assignee)
    if field == "points":
        return points_text(it.points)
    if field == "due":
        return opt_text(it.due)
    if field == "labels":
        return it.labels.join(",")

    return opt_text(it.reporter)

fn apply_update(var it: Issue, u: Update) Unit:
    let f = u.field

    if f == "title":
        it.title = u.norm
    else if f == "priority":
        it.priority = u.norm
    else if f == "assignee":
        it.assignee = if_some(u.norm)
    else if f == "points":
        if u.norm == "":
            it.points = none
        else:
            it.points = parse_uint(u.norm)
    else if f == "due":
        it.due = if_some(u.norm)
    else if f == "labels":
        if u.norm == "":
            it.labels = []
        else:
            it.labels = u.norm.split(",")
    else:
        it.reporter = if_some(u.norm)

fn if_some(s: String) Optional[String]:
    if s == "":
        return none

    return some(s)

fn log_add(var app: App, id: Int, detail: String) Unit:
    app.journal.append(Entry(t: app.t, actor: app.actor, id: id, detail: detail))

fn commit(var app: App, idx: Int, updates: List[Update]) Result[List[String], Fail]:
    let old = app.issues.get(idx).clone()
    var nw = old.clone()

    for u in updates:
        apply_update(var nw, u)

    var changes: List[String] = []

    for f in field_order():
        let before = field_norm(old, f)
        let after = field_norm(nw, f)

        if before != after:
            changes.append("{f}: {dash(before)} -> {dash(after)}")

    if changes.length() == 0:
        return ok(["#{old.id} unchanged"])

    app.t += 1
    nw.updated = app.t
    app.issues.set(idx, nw)
    for c in changes:
        log_add(var app, old.id, c)
    return ok(["updated #{old.id}"])

fn edit_core(var app: App, id: Int, fields: List[String]) Result[List[String], Fail]:
    let idx = find_index(app, id).get()
    let it = app.issues.get(idx).clone()
    if is_final(app, it.state):
        return error(Fail(msg: "#{id} is in final state '{it.state}'"))
    if fields.length() == 0:
        return error(Fail(msg: "usage: edit ID field=value..."))

    let updates = try parse_updates(fields)

    return commit(var app, idx, updates)

fn cmd_edit(var app: App, rest: String) Result[List[String], Fail]:
    let toks = try tokenize(rest)
    if toks.length() == 0:
        return error(Fail(msg: "usage: edit ID field=value..."))

    let id = try lookup_id(app, toks.get(0))

    return edit_core(var app, id, toks.drop(1))

fn cmd_assign(var app: App, rest: String) Result[List[String], Fail]:
    let toks = try tokenize(rest)
    if toks.length() != 2:
        return error(Fail(msg: "usage: assign ID NAME"))

    let id = try lookup_id(app, toks.get(0))

    return edit_core(var app, id, ["assignee=".concat(toks.get(1))])

fn lookup_id(app: App, arg: String) Result[Int, Fail]:
    let idx = try lookup(app, arg)

    return ok(app.issues.get(idx).id)

fn label_core(var app: App, id: Int, toks: List[String]) Result[List[String], Fail]:
    let idx = find_index(app, id).get()
    let it = app.issues.get(idx).clone()
    if is_final(app, it.state):
        return error(Fail(msg: "#{id} is in final state '{it.state}'"))

    var labs = it.labels.clone()

    for tok in toks:
        let w = sign_split(tok)
        let l = w.rest.lower()
        if not is_label(l):
            return error(Fail(msg: "bad label '{l}'"))

        if w.head == "-":
            labs = labs.filter(fn(x: String) Bool: return x != l)
        else if not labs.contains(l):
            labs.append(l)

    return commit(
        var app, idx, [Update(field: "labels", norm: unique_sorted(labs).join(","))]
    )

fn sign_split(tok: String) Word:
    let cs = tok.chars()
    if cs.length() > 0 and (cs.get(0) == "+" or cs.get(0) == "-"):
        return Word(head: cs.get(0), rest: join_range(cs, 1, cs.length()))

    return Word(head: "", rest: tok)

fn cmd_label(var app: App, rest: String) Result[List[String], Fail]:
    let toks = try tokenize(rest)
    if toks.length() < 2:
        return error(Fail(msg: "usage: label ID +label -label..."))

    let id = try lookup_id(app, toks.get(0))

    return label_core(var app, id, toks.drop(1))

fn cmd_create(var app: App, rest: String) Result[List[String], Fail]:
    if not app.has_workflow:
        return error(Fail(msg: "no workflow defined"))

    let toks = try tokenize(rest)
    if toks.length() == 0:
        return error(Fail(msg: "usage: create TITLE [field=value...]"))

    let title = toks.get(0)
    if title.trim() == "":
        return error(Fail(msg: "empty title"))

    var it = Issue(
        id: app.next_id, title: title, state: app.initial, priority: "medium",
        assignee: none, reporter: some(app.actor), points: none, due: none, labels: [],
        comments: [], created: 0, updated: 0
    )
    let base = it.clone()
    let updates = try parse_updates(toks.drop(1))

    for u in updates:
        apply_update(var it, u)
    app.t += 1
    it.created = app.t
    it.updated = app.t
    app.next_id += 1
    app.issues.append(it.clone())
    log_add(var app, it.id, "created \"{title}\"")

    for f in field_order():
        let before = field_norm(base, f)
        let after = field_norm(it, f)

        if before != after:
            log_add(var app, it.id, "{f}: {dash(before)} -> {dash(after)}")

    return ok(["created #{it.id}"])

fn guard_met(it: Issue, g: String) Bool:
    if g == "assignee":
        return it.assignee.is_some()
    if g == "points":
        return it.points.is_some()
    if g == "due":
        return it.due.is_some()
    if g == "labels":
        return it.labels.length() > 0

    return it.reporter.is_some()

fn trans_guards(app: App, src: String, dst: String) Optional[List[String]]:
    for tr in app.trans:
        if tr.src == src and tr.dst == dst:
            return some(tr.guards.clone())
    return none

fn move_core(var app: App, id: Int, to: String, comment: String) Result[
    List[String], Fail
]:
    let idx = find_index(app, id).get()
    let it = app.issues.get(idx).clone()
    let from = it.state
    if is_final(app, from):
        return error(Fail(msg: "#{id} is in final state '{from}'"))
    if not app.states.contains(to):
        return error(Fail(msg: "unknown state '{to}'"))
    if from == to:
        return error(Fail(msg: "already in state '{to}'"))

    let guards = trans_guards(app, from, to)
    if guards.is_none():
        return error(Fail(msg: "transition '{from} -> {to}' not allowed"))

    var missing: List[String] = []

    for g in guards.get():
        if not guard_met(it, g):
            missing.append(g)
    if missing.length() > 0:
        return error(
            Fail(
                msg: "cannot move #{id} to {to}: missing {missing.join(", ")}"
            )
        )

    app.t += 1

    var nw = it.clone()

    nw.state = to
    nw.updated = app.t
    if comment != "":
        nw.comments.append(Comment(t: app.t, actor: app.actor, text: comment))
    app.issues.set(idx, nw)
    log_add(var app, id, "state: {from} -> {to}")
    if comment != "":
        log_add(var app, id, "comment: {comment}")
    return ok(["moved #{id}: {from} -> {to}"])

fn cmd_move(var app: App, rest: String) Result[List[String], Fail]:
    let w1 = cut_word(rest)
    let w2 = cut_word(w1.rest)
    if w1.head == "" or w2.head == "":
        return error(Fail(msg: "usage: move ID STATE [comment...]"))

    let id = try lookup_id(app, w1.head)

    return move_core(var app, id, w2.head, w2.rest)

fn cmd_comment(var app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "" or w.rest == "":
        return error(Fail(msg: "usage: comment ID TEXT"))

    let idx = try lookup(app, w.head)

    app.t += 1

    var nw = app.issues.get(idx).clone()

    nw.comments.append(Comment(t: app.t, actor: app.actor, text: w.rest))
    nw.updated = app.t
    app.issues.set(idx, nw.clone())
    log_add(var app, nw.id, "comment: {w.rest}")
    return ok(["commented #{nw.id}"])

fn cmd_delete(var app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: delete ID"))

    let idx = try lookup(app, ws.get(0))

    app.t += 1

    let id = app.issues.get(idx).id

    app.issues.remove(idx)
    log_add(var app, id, "deleted")
    return ok(["deleted #{id}"])

fn cmd_show(app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: show ID"))

    let idx = try lookup(app, ws.get(0))
    let it = app.issues.get(idx)
    var out: List[String] = []

    out.append("#{it.id} {it.title}")
    out.append("  state: {it.state}")
    out.append("  priority: {it.priority}")
    out.append("  assignee: {opt_show(it.assignee)}")
    out.append("  points: {dash(points_text(it.points))}")
    out.append("  due: {dash(opt_text(it.due))}")
    out.append("  labels: {dash(it.labels.join(", "))}")
    out.append("  reporter: {opt_show(it.reporter)}")
    out.append("  created: t={it.created}, updated: t={it.updated}")
    out.append("  comments: {it.comments.length()}")
    for c in it.comments:
        out.append("    [t={c.t} {c.actor}] {c.text}")
    return ok(out)

fn cmd_actor(var app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: actor NAME"))

    app.actor = ws.get(0)
    return ok(["actor is {app.actor}"])

fn cmd_today(var app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: today DATE"))
    if not valid_date(ws.get(0)):
        return error(Fail(msg: "bad date '{ws.get(0)}'"))

    app.today = ws.get(0)
    return ok(["today is {app.today}"])

fn register(var states: List[String], name: String) Unit:
    if not states.contains(name):
        states.append(name)

fn guard_field(g: String) Bool:
    return ["assignee", "points", "due", "labels", "reporter"].contains(g)

fn define_workflow(var app: App, body: List[String]) Result[List[String], Fail]:
    if app.next_id > 1:
        return error(Fail(msg: "workflow: cannot redefine after issues were created"))

    var states: List[String] = []
    var initial = ""
    var has_initial = false
    var finals: List[String] = []
    var trans: List[Trans] = []

    for raw in body:
        let line = raw.trim()
        if line == "" or line.starts_with("#"):
            continue

        let colon = line.split(":")

        if colon.length() == 2 and colon.get(0) == "initial":
            let name = colon.get(1).trim()
            if not is_state_name(name):
                return error(Fail(msg: "workflow: bad state name '{name}'"))
            if has_initial:
                return error(Fail(msg: "workflow: initial state defined twice"))

            has_initial = true
            initial = name
            register(var states, name)
        else if colon.length() == 2 and colon.get(0) == "final":
            for part in colon.get(1).split(","):
                let name = part.trim()
                if not is_state_name(name):
                    return error(Fail(msg: "workflow: bad state name '{name}'"))

                register(var states, name)
                finals.append(name)
        else if line.contains("->"):
            let arrow = line.split("->")
            let src = arrow.get(0).trim()
            if not is_state_name(src):
                return error(Fail(msg: "workflow: bad state name '{src}'"))

            register(var states, src)

            let dst = arrow.drop(1).join("->")

            for entry in dst.split(","):
                let ws = words(entry)
                if ws.length() == 0:
                    return error(Fail(msg: "workflow: bad state name ''"))

                let target = ws.get(0)
                if not is_state_name(target):
                    return error(Fail(msg: "workflow: bad state name '{target}'"))

                var guards: List[String] = []

                if ws.length() == 3 and ws.get(1) == "requires":
                    for g in ws.get(2).split("+"):
                        if not guard_field(g):
                            return error(Fail(msg: "workflow: bad guard field '{g}'"))

                        guards.append(g)
                else if ws.length() != 1:
                    return error(Fail(msg: "workflow: bad line '{line}'"))

                register(var states, target)
                trans.append(Trans(src: src, dst: target, guards: guards))
        else:
            return error(Fail(msg: "workflow: bad line '{line}'"))

    if not has_initial:
        return error(Fail(msg: "workflow: initial state missing"))

    for tr in trans:
        if finals.contains(tr.src):
            return error(
                Fail(
                    msg: "workflow: '{tr.src}' is final and cannot have transitions"
                )
            )
    app.has_workflow = true
    app.initial = initial
    app.states = states.clone()
    app.finals = finals.clone()
    app.trans = trans.clone()
    return ok(["workflow ok: {states.length()} states, {trans.length()} transitions"])

fn is_term_stop(c: String) Bool:
    return (
        is_space(c)
        or c == "("
        or c == ")"
        or c == "\""
        or c == ":"
        or c == "!"
        or c == "<"
        or c == ">"
        or c == "~"
        or c == "="
    )

fn is_field_text(s: String) Bool:
    if s == "":
        return false

    for c in s.scalar_values():
        if not (in_range(c, 97, 122) or c == 95):
            return false
    return true

fn lex_filter(text: String) Result[List[Tok], Fail]:
    let cs = text.chars()
    let n = cs.length()
    var out: List[Tok] = []
    var i = 0

    while i < n:
        let c = cs.get(i)

        if is_space(c):
            i += 1
        else if c == "(" or c == ")":
            out.append(Tok(kind: c, field: "", op: "", value: c, quoted: false))
            i += 1
        else:
            var j = i

            while j < n and not is_term_stop(cs.get(j)):
                j += 1

            let name = join_range(cs, i, j)
            var op = ""
            var k = j

            if j < n:
                let two = join_range(cs, j, j + 2)

                if two == "!=" or two == "<=" or two == ">=":
                    op = two
                    k = j + 2
                else if (
                    cs.get(j) == ":"
                    or cs.get(j) == "<"
                    or cs.get(j) == ">"
                    or cs.get(j) == "~"
                ):
                    op = cs.get(j)
                    k = j + 1

            if op != "" and is_field_text(name):
                var value = ""
                var quoted = false
                var p = k

                if k < n and cs.get(k) == "\"":
                    quoted = true
                    p = k + 1

                    var closed = false

                    while p < n and not closed:
                        let d = cs.get(p)

                        if (
                            d == "\\"
                            and p + 1 < n
                            and (
                                cs.get(p + 1) == "\""
                                or cs.get(p + 1) == "\\"
                            )
                        ):
                            value = value.concat(cs.get(p + 1))
                            p += 2
                        else if d == "\"":
                            closed = true
                            p += 1
                        else:
                            value = value.concat(d)
                            p += 1

                    if not closed:
                        return error(Fail(msg: "query: unterminated quote"))
                else:
                    while (
                        p < n
                        and not is_space(cs.get(p))
                        and cs.get(p) != "("
                        and cs.get(p) != ")"
                    ):
                        value = value.concat(cs.get(p))
                        p += 1

                out.append(
                    Tok(
                        kind: "TERM", field: name, op: op, value: value, quoted: quoted
                    )
                )
                i = p
            else:
                var p = i

                while (
                    p < n
                    and not is_space(cs.get(p))
                    and cs.get(p) != "("
                    and cs.get(p) != ")"
                ):
                    p += 1

                let word = join_range(cs, i, p)

                if word == "AND" or word == "OR" or word == "NOT":
                    out.append(
                        Tok(
                            kind: word, field: "", op: "", value: word, quoted: false
                        )
                    )
                else:
                    out.append(
                        Tok(
                            kind: "BAD", field: "", op: "", value: word, quoted: false
                        )
                    )

                i = p

    return ok(out)

fn known_field(f: String) Bool:
    return [
        "id", "created", "updated", "points", "title", "assignee", "reporter", "text",
        "state", "priority", "due", "labels", "label", "is", "has", "view"
    ].contains(f)

fn ops_for(f: String) List[String]:
    if (
        f == "id"
        or f == "created"
        or f == "updated"
        or f == "points"
        or f == "priority"
        or f == "due"
    ):
        return [":", "!=", "<", "<=", ">", ">="]
    if f == "title" or f == "assignee" or f == "reporter" or f == "labels":
        return [":", "!=", "~"]
    if f == "text":
        return ["~"]
    if f == "state":
        return [":", "!="]

    return [":"]

fn value_ok(app: App, f: String, op: String, a: String) Bool:
    if f == "id" or f == "created" or f == "updated":
        return parse_uint(a).is_some()

    if f == "points":
        if a == "none":
            return op == ":" or op == "!="

        return parse_uint(a).is_some()

    if f == "priority":
        return is_priority(a)

    if f == "due":
        if a == "none":
            return op == ":" or op == "!="

        return valid_date(a)

    if f == "state":
        return app.states.contains(a)
    if f == "is":
        return ["open", "final", "overdue", "unassigned"].contains(a)
    if f == "has":
        return ["assignee", "due", "points", "labels", "comments", "reporter"].contains(
            a
        )

    return true

fn check_term(app: App, t: Tok) Result[Expr, Fail]:
    let field = t.field
    let op = t.op
    var canon = field

    if field == "label":
        canon = "labels"
    if not known_field(field):
        return error(Fail(msg: "query: unknown field '{field}'"))
    if not ops_for(canon).contains(op):
        return error(Fail(msg: "query: bad operator '{op}' for field '{field}'"))

    var alts: List[String] = []

    if (
        t.quoted
        or canon == "view"
        or op == "<"
        or op == "<="
        or op == ">"
        or op == ">="
    ):
        alts = [t.value]
    else:
        alts = t.value.split("|")

    for a in alts:
        if canon == "view":
            if not app.views.contains(a):
                return error(Fail(msg: "query: unknown view '{a}'"))
        else if not value_ok(app, canon, op, a):
            return error(Fail(msg: "query: bad value '{a}' for field '{field}'"))

    return ok(Term(field: canon, op: op, alts: alts))

fn peek_kind(ps: Parser) String:
    if ps.pos >= ps.toks.length():
        return ""

    return ps.toks.get(ps.pos).kind

fn starts_operand(k: String) Bool:
    return k == "TERM" or k == "(" or k == "NOT"

fn parse_or(var ps: Parser, app: App) Result[Expr, Fail]:
    var left = try parse_and(var ps, app)

    while peek_kind(ps) == "OR":
        ps.pos += 1

        let right = try parse_and(var ps, app)

        left = Or(left, right)

    return ok(left)

fn parse_and(var ps: Parser, app: App) Result[Expr, Fail]:
    var left = try parse_not(var ps, app)

    while peek_kind(ps) == "AND" or starts_operand(peek_kind(ps)):
        if peek_kind(ps) == "AND":
            ps.pos += 1

        let right = try parse_not(var ps, app)

        left = And(left, right)

    return ok(left)

fn parse_not(var ps: Parser, app: App) Result[Expr, Fail]:
    if peek_kind(ps) == "NOT":
        ps.pos += 1

        let inner = try parse_not(var ps, app)

        return ok(Not(inner))

    return parse_primary(var ps, app)

fn parse_primary(var ps: Parser, app: App) Result[Expr, Fail]:
    if ps.pos >= ps.toks.length():
        return error(Fail(msg: "query: unexpected end of query"))

    let t = ps.toks.get(ps.pos)

    if t.kind == "(":
        ps.pos += 1

        let inner = try parse_or(var ps, app)
        if ps.pos >= ps.toks.length():
            return error(Fail(msg: "query: unexpected end of query"))
        if ps.toks.get(ps.pos).kind != ")":
            return error(
                Fail(
                    msg: "query: unexpected token '{ps.toks.get(ps.pos).value}'"
                )
            )

        ps.pos += 1
        return ok(inner)

    if t.kind == "TERM":
        ps.pos += 1
        return check_term(app, t)

    return error(Fail(msg: "query: unexpected token '{t.value}'"))

fn parse_filter(app: App, text: String) Result[Expr, Fail]:
    if text.trim() == "":
        return ok(All)

    let toks = try lex_filter(text)
    var ps = Parser(toks: toks, pos: 0)
    let e = try parse_or(var ps, app)
    if ps.pos < ps.toks.length():
        return error(Fail(msg: "query: unexpected token '{ps.toks.get(ps.pos).value}'"))

    return ok(e)

fn split_limit(text: String) Clause:
    let cs = text.chars()
    let n = cs.length()
    var s = n

    while s > 0 and not is_space(cs.get(s - 1)):
        s -= 1

    var e = s

    while e > 0 and is_space(cs.get(e - 1)):
        e -= 1

    var b = e

    while b > 0 and not is_space(cs.get(b - 1)):
        b -= 1
    if n > 0 and e < s and join_range(cs, b, e) == "limit":
        return Clause(
            head: join_range(cs, 0, b).trim_end(), found: true,
            tail: join_range(cs, s, n)
        )

    return Clause(head: text, found: false, tail: "")

fn split_sort(text: String) Clause:
    let cs = text.chars()
    let n = cs.length()
    var i = 0

    while i + 4 < n:
        if i == 0 or is_space(cs.get(i - 1)):
            if join_range(cs, i, i + 4) == "sort" and is_space(cs.get(i + 4)):
                return Clause(
                    head: join_range(cs, 0, i).trim_end(), found: true,
                    tail: join_range(cs, i + 4, n)
                )
        i += 1

    return Clause(head: text, found: false, tail: "")

fn sort_field(f: String) Bool:
    return [
        "id", "created", "updated", "priority", "points", "state", "title", "assignee",
        "reporter", "due"
    ].contains(f)

fn parse_sort_keys(text: String) Result[List[SortKey], Fail]:
    var out: List[SortKey] = []

    for w in words(text.split(",").join(" ")):
        var desc = false
        var name = w
        let s = sign_split(w)

        if s.head == "-":
            desc = true
            name = s.rest

        if not sort_field(name):
            return error(Fail(msg: "bad sort field '{name}'"))

        out.append(SortKey(name: name, desc: desc))

    return ok(out)

fn parse_spec(app: App, text: String) Result[Spec, Fail]:
    let lim = split_limit(text.trim())
    var limit = 0

    if lim.found:
        let v = parse_uint(lim.tail)
        if v.is_none():
            return error(Fail(msg: "bad limit '{lim.tail}'"))

        limit = v.get()

    let srt = split_sort(lim.head)
    let filter = try parse_filter(app, srt.head)
    var keys: List[SortKey] = []

    if srt.found:
        keys = try parse_sort_keys(srt.tail)
    return ok(Spec(filter: filter, sort: keys, has_limit: lim.found, limit: limit))

fn cmp_ok(c: Int, op: String) Bool:
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0
    if op == ">=":
        return c >= 0

    return c == 0

fn text_match(cur: String, op: String, a: String) Bool:
    if op == "~":
        return cur.lower().contains(a.lower())

    return cur.lower() == a.lower()

fn one(app: App, f: String, op: String, a: String, it: Issue) Bool:
    if f == "id":
        return cmp_ok(it.id.compare(parse_uint(a).get()), op)
    if f == "created":
        return cmp_ok(it.created.compare(parse_uint(a).get()), op)
    if f == "updated":
        return cmp_ok(it.updated.compare(parse_uint(a).get()), op)

    if f == "points":
        if it.points.is_none():
            return a == "none" and op == ":"
        if a == "none":
            return false

        return cmp_ok(it.points.get().compare(parse_uint(a).get()), op)

    if f == "title":
        return text_match(it.title, op, a)

    if f == "assignee":
        if it.assignee.is_none():
            return op == ":" and a == "none"

        return text_match(it.assignee.get(), op, a)

    if f == "reporter":
        if it.reporter.is_none():
            return op == ":" and a == "none"

        return text_match(it.reporter.get(), op, a)

    if f == "text":
        let lo = a.lower()
        if it.title.lower().contains(lo):
            return true

        for c in it.comments:
            if c.text.lower().contains(lo):
                return true
        return false

    if f == "state":
        return it.state == a

    if f == "priority":
        if op == ":":
            return it.priority == a

        return cmp_ok(priority_rank(it.priority).compare(priority_rank(a)), op)

    if f == "due":
        if it.due.is_none():
            return op == ":" and a == "none"

        let d = it.due.get()
        if op == ":":
            return d == a

        return cmp_ok(d.compare(a), op)

    if f == "labels":
        let lo = a.lower()

        if op == "~":
            for l in it.labels:
                if l.contains(lo):
                    return true
            return false

        if lo == "none":
            return it.labels.length() == 0

        return it.labels.contains(lo)

    if f == "is":
        if a == "open":
            return not is_final(app, it.state)
        if a == "final":
            return is_final(app, it.state)
        if a == "overdue":
            return (
                not is_final(app, it.state)
                and it.due.is_some()
                and it.due.get().compare(app.today) < 0
            )
        if a == "unassigned":
            return it.assignee.is_none()

        return false

    if f == "has":
        if a == "assignee":
            return it.assignee.is_some()
        if a == "due":
            return it.due.is_some()
        if a == "points":
            return it.points.is_some()
        if a == "labels":
            return it.labels.length() > 0
        if a == "comments":
            return it.comments.length() > 0

        return it.reporter.is_some()

    let spec = try_view(app, a)

    return eval(app, spec, it)

fn try_view(app: App, name: String) Expr:
    return parse_spec(app, app.views.get(name).get()).get().filter

fn any_alt(app: App, f: String, op: String, alts: List[String], it: Issue) Bool:
    for a in alts:
        if one(app, f, op, a, it):
            return true
    return false

fn eval(app: App, e: Expr, it: Issue) Bool:
    match e:
        All:
            return true
        Term(field, op, alts):
            if op == "!=":
                return not any_alt(app, field, ":", alts, it)

            return any_alt(app, field, op, alts, it)
        And(left, right):
            return eval(app, left, it) and eval(app, right, it)
        Or(left, right):
            return eval(app, left, it) or eval(app, right, it)
        Not(inner):
            return not eval(app, inner, it)

fn view_refs(e: Expr) List[String]:
    match e:
        All:
            return []
        Term(field, op, alts):
            if field == "view":
                return alts

            return []
        And(left, right):
            return view_refs(left).concat(view_refs(right))
        Or(left, right):
            return view_refs(left).concat(view_refs(right))
        Not(inner):
            return view_refs(inner)

fn reaches(app: App, text: String, target: String) Bool:
    let spec = parse_spec(app, text)
    if spec.is_error():
        return false

    let sp = spec.get().clone()

    for r in view_refs(sp.filter.clone()):
        if r == target:
            return true
        if app.views.contains(r) and reaches(app, app.views.get(r).get(), target):
            return true

    return false

fn cmp_absent(a_none: Bool, b_none: Bool) Int:
    if a_none and b_none:
        return 0
    if a_none:
        return 1

    return -1

fn cmp_opt_int(a: Optional[Int], b: Optional[Int]) Int:
    if a.is_none() or b.is_none():
        return cmp_absent(a.is_none(), b.is_none())

    return a.get().compare(b.get())

fn cmp_opt_text(a: Optional[String], b: Optional[String]) Int:
    if a.is_none() or b.is_none():
        return cmp_absent(a.is_none(), b.is_none())

    return opt_text(a).lower().compare(opt_text(b).lower())

fn cmp_field(states: List[String], f: String, a: Issue, b: Issue) Int:
    if f == "id":
        return a.id.compare(b.id)
    if f == "created":
        return a.created.compare(b.created)
    if f == "updated":
        return a.updated.compare(b.updated)
    if f == "priority":
        return priority_rank(a.priority).compare(priority_rank(b.priority))
    if f == "state":
        return state_index(states, a.state).compare(state_index(states, b.state))
    if f == "points":
        return cmp_opt_int(a.points, b.points)
    if f == "title":
        return a.title.lower().compare(b.title.lower())
    if f == "assignee":
        return cmp_opt_text(a.assignee, b.assignee)
    if f == "reporter":
        return cmp_opt_text(a.reporter, b.reporter)

    return cmp_opt_text(a.due, b.due)

fn cmp_issues(states: List[String], keys: List[SortKey], a: Issue, b: Issue) Int:
    for k in keys:
        let c = cmp_field(states, k.name, a, b)

        if c != 0:
            if k.desc:
                return -c

            return c

    return a.id.compare(b.id)

fn sort_issues(states: List[String], keys: List[SortKey], xs: List[Issue]) List[Issue]:
    var out: List[Issue] = []

    for x in xs:
        var pos = 0

        while (
            pos < out.length()
            and cmp_issues(states, keys.clone(), out.get(pos), x) < 0
        ):
            pos += 1
        out.insert(pos, x.clone())

    return out

fn issue_line(it: Issue) String:
    return "#{it.id} | {it.state} | {it.priority} | {opt_show(it.assignee)} | {dash(points_text(it.points))} | {dash(opt_text(it.due))} | {dash(it.labels.join(","))} | {it.title}"

fn count_line(n: Int) String:
    if n == 1:
        return "(1 issue)"

    return "({n} issues)"

fn query_lines(app: App, spec: Spec) List[String]:
    var hits: List[Issue] = []
    let matcher = spec.filter.clone()

    for it in app.issues:
        if eval(app, matcher.clone(), it):
            hits.append(it.clone())
    if spec.sort.length() > 0:
        hits = sort_issues(app.states.clone(), spec.sort.clone(), hits)
    if spec.has_limit:
        hits = hits.take(spec.limit)

    var out: List[String] = []

    for it in hits:
        out.append(issue_line(it))
    out.append(count_line(hits.length()))
    return out

fn cmd_list(app: App, rest: String) Result[List[String], Fail]:
    let spec = try parse_spec(app, rest)

    return ok(query_lines(app, spec))

fn view_save(var app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "":
        return error(Fail(msg: "usage: view save NAME QUERY"))
    if not is_view_name(w.head):
        return error(Fail(msg: "bad view name '{w.head}'"))

    let text = w.rest.trim()
    let checked = try parse_spec(app, text)
    if reaches(app, text, w.head):
        return error(Fail(msg: "view '{w.head}' would reference itself"))

    app.views.add(w.head, text)
    return ok(["saved view {w.head}"])

fn view_run(app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "":
        return error(Fail(msg: "usage: view run NAME [sort FIELDS] [limit N]"))
    if not app.views.contains(w.head):
        return error(Fail(msg: "unknown view '{w.head}'"))

    var spec = try parse_spec(app, app.views.get(w.head).get())
    let lim = split_limit(w.rest.trim())

    if lim.found:
        let v = parse_uint(lim.tail)
        if v.is_none():
            return error(Fail(msg: "bad limit '{lim.tail}'"))

        spec.has_limit = true
        spec.limit = v.get()

    let srt = split_sort(lim.head)
    if srt.head.trim() != "":
        return error(Fail(msg: "unexpected '{srt.head.trim()}'"))

    if srt.found:
        spec.sort = try parse_sort_keys(srt.tail)
    return ok(query_lines(app, spec))

fn view_list(app: App) Result[List[String], Fail]:
    let names = sorted_text(app.views.keys())
    if names.length() == 0:
        return ok(["(no views)"])

    var out: List[String] = []

    for n in names:
        out.append("{n}: {app.views.get(n).get()}")
    return ok(out)

fn view_show(app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: view show NAME"))

    let name = ws.get(0)
    if not app.views.contains(name):
        return error(Fail(msg: "unknown view '{name}'"))

    return ok(["{name}: {app.views.get(name).get()}"])

fn view_delete(var app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    if ws.length() != 1:
        return error(Fail(msg: "usage: view delete NAME"))

    let name = ws.get(0)
    if not app.views.contains(name):
        return error(Fail(msg: "unknown view '{name}'"))

    for other in sorted_text(app.views.keys()):
        if other != name and reaches(app, app.views.get(other).get(), name):
            return error(Fail(msg: "view '{name}' is used by '{other}'"))
    app.views.remove(name)
    return ok(["deleted view {name}"])

fn cmd_view(var app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "save":
        return view_save(var app, w.rest)
    if w.head == "run":
        return view_run(app, w.rest)
    if w.head == "list":
        return view_list(app)
    if w.head == "show":
        return view_show(app, w.rest)
    if w.head == "delete":
        return view_delete(var app, w.rest)

    return error(Fail(msg: "usage: view save|run|list|show|delete"))

fn bulk_one(var app: App, verb: String, args: List[String], id: Int) Result[
    List[String], Fail
]:
    if verb == "move":
        return move_core(var app, id, args.get(0), "")
    if verb == "assign":
        return edit_core(var app, id, ["assignee=".concat(args.get(0))])
    if verb == "label":
        return label_core(var app, id, args)

    return edit_core(var app, id, args)

fn cmd_bulk(var app: App, rest: String) Result[List[String], Fail]:
    let cs = rest.chars()
    let n = cs.length()
    var at = -1
    var i = 0

    while i + 5 <= n and at < 0:
        if i == 0 or is_space(cs.get(i - 1)):
            if (
                join_range(cs, i, i + 5) == "where"
                and (i + 5 == n or is_space(cs.get(i + 5)))
            ):
                at = i
        i += 1

    if at < 0:
        return error(Fail(msg: "usage: bulk ACTION... where QUERY"))

    let action = join_range(cs, 0, at).trim()
    let query = join_range(cs, at + 5, n).trim()
    if action == "":
        return error(Fail(msg: "usage: bulk ACTION... where QUERY"))

    let toks = try tokenize(action)
    let verb = toks.get(0)
    let args = toks.drop(1)

    if verb == "move":
        if args.length() != 1:
            return error(Fail(msg: "usage: bulk move STATE where QUERY"))
    else if verb == "assign":
        if args.length() != 1:
            return error(Fail(msg: "usage: bulk assign NAME where QUERY"))
    else if verb == "label":
        if args.length() == 0:
            return error(Fail(msg: "usage: bulk label +label... where QUERY"))
    else if verb == "set":
        if args.length() == 0:
            return error(Fail(msg: "usage: bulk set field=value... where QUERY"))
    else:
        return error(Fail(msg: "unknown bulk action '{verb}'"))

    let filt = try parse_filter(app, query)
    var ids: List[Int] = []

    for it in app.issues:
        if eval(app, filt.clone(), it):
            ids.append(it.id)

    var out: List[String] = []
    var okn = 0
    var failed = 0

    for id in ids:
        let r = bulk_one(var app, verb, args.clone(), id)

        if r.is_error():
            out.append("#{id} error: {r.err().message()}")
            failed += 1
        else:
            for line in r.get():
                out.append(line)
            okn += 1

    out.append("bulk: {okn} ok, {failed} failed")
    return ok(out)

fn cmd_log(app: App, rest: String) Result[List[String], Fail]:
    let ws = words(rest)
    let n = ws.length()
    let usage_text = "usage: log [ID] [tail N]"
    let shape_ok = (
        n == 0
        or (n == 2 and ws.get(0) == "tail")
        or (n == 1 and ws.get(0) != "tail")
        or (n == 3 and ws.get(1) == "tail")
    )
    if not shape_ok:
        return error(Fail(msg: usage_text))

    var wanted = 0

    if n == 1 or n == 3:
        let d = try parse_id(ws.get(0))
        if id_value(d) >= app.next_id:
            return error(Fail(msg: "no such issue #{d}"))

        wanted = id_value(d)

    var limit_n = -1

    if n == 2 or n == 3:
        let t = parse_uint(ws.get(n - 1))
        if t.is_none():
            return error(Fail(msg: "bad tail '{ws.get(n - 1)}'"))

        limit_n = t.get()

    var sel: List[Entry] = []

    for e in app.journal:
        if (n != 1 and n != 3) or e.id == wanted:
            sel.append(e)
    if limit_n >= 0 and sel.length() > limit_n:
        sel = sel.drop(sel.length() - limit_n)
    if sel.length() == 0:
        return ok(["(no log entries)"])

    var out: List[String] = []

    for e in sel:
        out.append("t={e.t} {e.actor} #{e.id} {e.detail}")
    return ok(out)

fn count_state(app: App, s: String) Int:
    var c = 0

    for it in app.issues:
        if it.state == s:
            c += 1
    return c

fn count_priority(app: App, p: String) Int:
    var c = 0

    for it in app.issues:
        if it.priority == p:
            c += 1
    return c

fn report_summary(app: App) List[String]:
    var open_n = 0
    var unassigned = 0
    var overdue = 0
    var open_points = 0

    for it in app.issues:
        if not is_final(app, it.state):
            open_n += 1
            if it.assignee.is_none():
                unassigned += 1
            if it.due.is_some() and it.due.get().compare(app.today) < 0:
                overdue += 1
            if it.points.is_some():
                open_points += it.points.get()

    let total = app.issues.length()
    let final_n = total - open_n
    var out: List[String] = []

    out.append("issues: {total} (open {open_n}, final {final_n})")
    out.append("by state:")
    for s in app.states:
        out.append("  {s}: {count_state(app, s)}")
    out.append("by priority:")
    for p in ["critical", "high", "medium", "low"]:
        out.append("  {p}: {count_priority(app, p)}")
    out.append("unassigned: {unassigned}")
    out.append("overdue: {overdue}")
    out.append("open points: {open_points}")
    return out

fn cmp_group(a: Group, b: Group) Int:
    if a.points != b.points:
        return b.points.compare(a.points)
    if a.count != b.count:
        return b.count.compare(a.count)

    return a.key.compare(b.key)

fn issue_word(n: Int) String:
    if n == 1:
        return "issue"

    return "issues"

fn points_or_zero(o: Optional[Int]) Int:
    if let p = o:
        return p

    return 0

fn report_workload(app: App) List[String]:
    var groups: List[Group] = []
    var any_open = false
    var unassigned_n = 0
    var unassigned_pts = 0

    for it in app.issues:
        if is_final(app, it.state):
            continue

        any_open = true

        let pts = points_or_zero(it.points)

        if it.assignee.is_none():
            unassigned_n += 1
            unassigned_pts += pts
        else:
            let name = it.assignee.get()
            let key = name.lower()
            var found = -1

            for gi in range(0, groups.length()):
                if groups.get(gi).key == key:
                    found = gi

            if found < 0:
                groups.append(Group(key: key, name: name, count: 1, points: pts))
            else:
                var g = groups.get(found)

                g.count += 1
                g.points += pts
                groups.set(found, g)

    if not any_open:
        return ["(no open issues)"]

    var out: List[String] = []

    for g in groups.sorted(fn(a: Group, b: Group) Int: return cmp_group(a, b)):
        out.append("{g.name}: {g.count} {issue_word(g.count)}, {g.points} points")
    if unassigned_n > 0:
        out.append(
            "unassigned: {unassigned_n} {issue_word(unassigned_n)}, {unassigned_pts} points"
        )
    return out

fn cmp_label(a: LabelCount, b: LabelCount) Int:
    if a.count != b.count:
        return b.count.compare(a.count)

    return a.name.compare(b.name)

fn report_labels(app: App, text: String) Result[List[String], Fail]:
    let filt = try parse_filter(app, text)
    var counts = Map[String, Int]()

    for it in app.issues:
        if eval(app, filt.clone(), it):
            for l in it.labels:
                counts.add(l, counts.get_or(l, 0) + 1)
    if counts.length() == 0:
        return ok(["(no labels)"])

    var rows: List[LabelCount] = []

    for l in counts.keys():
        rows.append(LabelCount(name: l, count: counts.get(l).get()))

    let sorted_rows = rows.sorted(
        fn(a: LabelCount, b: LabelCount) Int: return cmp_label(a, b)
    )
    var out: List[String] = []

    for r in sorted_rows:
        out.append("{r.name}: {r.count}")
    return ok(out)

fn period(state: String, from: Int, to: Int) String:
    let dur = to - from

    return "{state}: t={from}..{to} ({dur})"

fn report_timeline(app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "":
        return error(Fail(msg: "usage: report timeline ID"))

    let idx = try lookup(app, w.head)
    let it = app.issues.get(idx)
    var out: List[String] = []
    var state = app.initial
    var from = it.created

    for e in app.journal:
        if e.id == it.id and e.detail.starts_with("state: "):
            let to_state = e.detail.split(" -> ").get(1)

            out.append(period(state, from, e.t))
            state = to_state
            from = e.t

    out.append(period(state, from, app.t))
    return ok(out)

fn cmd_report(app: App, rest: String) Result[List[String], Fail]:
    let w = cut_word(rest)
    if w.head == "summary":
        return ok(report_summary(app))
    if w.head == "workload":
        return ok(report_workload(app))
    if w.head == "labels":
        return report_labels(app, w.rest)
    if w.head == "timeline":
        return report_timeline(app, w.rest)

    return error(Fail(msg: "usage: report summary|workload|labels|timeline"))

fn dispatch(var app: App, cmd: String, rest: String) Result[List[String], Fail]:
    if cmd == "create":
        return cmd_create(var app, rest)
    if cmd == "edit":
        return cmd_edit(var app, rest)
    if cmd == "label":
        return cmd_label(var app, rest)
    if cmd == "assign":
        return cmd_assign(var app, rest)
    if cmd == "move":
        return cmd_move(var app, rest)
    if cmd == "comment":
        return cmd_comment(var app, rest)
    if cmd == "delete":
        return cmd_delete(var app, rest)
    if cmd == "show":
        return cmd_show(app, rest)
    if cmd == "list":
        return cmd_list(app, rest)
    if cmd == "view":
        return cmd_view(var app, rest)
    if cmd == "bulk":
        return cmd_bulk(var app, rest)
    if cmd == "log":
        return cmd_log(app, rest)
    if cmd == "report":
        return cmd_report(app, rest)
    if cmd == "actor":
        return cmd_actor(var app, rest)
    if cmd == "today":
        return cmd_today(var app, rest)

    return error(Fail(msg: "unknown command '{cmd}'"))

fn read_all() List[String]:
    var out: List[String] = []
    let input = stdin()

    while true:
        let line = read_line(input, none).get()
        if line.is_none():
            break

        out.append(line.get(""))

    return out

fn show(r: Result[List[String], Fail]) Unit:
    if r.is_error():
        emit("error: {r.err().message()}\n")
    else:
        for line in r.get():
            emit("{line}\n")

export fn main() Int:
    var app = App(
        t: 0, today: "1970-01-01", actor: "system", has_workflow: false, initial: "",
        states: [], finals: [], trans: [], issues: [], next_id: 1, journal: [],
        views: Map[String, String]()
    )
    let lines = read_all()
    var i = 0

    while i < lines.length():
        let line = lines.get(i).trim_end()

        i += 1

        let body = line.trim_start()
        if body == "" or body.starts_with("#"):
            continue

        emit("> {line}\n")

        let w = cut_word(body)

        if w.head == "workflow":
            var block: List[String] = []

            while i < lines.length() and lines.get(i).trim() != "end":
                block.append(lines.get(i))
                i += 1

            i += 1
            show(define_workflow(var app, block))
        else:
            show(dispatch(var app, w.head, w.rest))

    return 0
