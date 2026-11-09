import read_all from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

// ---------------------------------------------------------------- types

type Comment:
    t: Int
    actor: String
    text: String

type Change:
    t: Int
    state: String

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
    history: List[Change]

type Fields:
    title: String
    priority: String
    assignee: String?
    points: Int?
    due: String?
    labels: List[String]
    reporter: String?

type LogEntry:
    t: Int
    actor: String
    id: Int
    detail: String

type View:
    name: String
    query: String

type Transition:
    src: String
    dst: String
    guards: List[String]

type State:
    has_workflow: Bool
    initial: String
    states: List[String]
    finals: List[String]
    transitions: List[Transition]
    issues: List[Issue]
    next_id: Int
    clock: Int
    actor: String
    today: String
    log: List[LogEntry]
    views: List[View]

type Split:
    head: String
    rest: String

type KV:
    key: String
    value: String
    ok: Bool

type Tokens:
    items: List[String]
    ok: Bool

type Res:
    err: String
    out: String

type IdRes:
    idx: Int
    id: Int
    err: String

type SortKey:
    field: String
    desc: Bool

type Clauses:
    err: String
    filter: String
    has_sort: Bool
    sorts: List[SortKey]
    sort_err: String
    has_limit: Bool
    limit: Int

type Tok:
    kind: String
    text: String
    field: String
    op: String
    value: String
    quoted: Bool

type QNode:
    kind: String
    a: Int
    b: Int
    field: String
    op: String
    values: List[String]

type Query:
    nodes: List[QNode]
    root: Int
    err: String

type Parser:
    toks: List[Tok]
    pos: Int
    nodes: List[QNode]
    err: String

type LabRes:
    labels: List[String]
    err: String

// ---------------------------------------------------------------- text helpers

fn is_ws(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn at(cs: List[String], k: Int) String:
    if k < 0:
        return ""
    if k >= cs.length():
        return ""

    return cs[k].clone()

fn join_range(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var k = a

    while k < b:
        out = out + cs[k]
        k += 1

    return out

fn drop_chars(s: String, k: Int) String:
    let cs = s.chars()
    return join_range(cs, k, cs.length())

// Splits off the first whitespace-separated word. rest keeps trailing text
// verbatim, with leading whitespace removed.
fn split_head(s: String) Split:
    let cs = s.trim_start().chars()
    let n = cs.length()
    var k = 0
    while k < n and not is_ws(cs[k]):
        k += 1

    let head = join_range(cs, 0, k)
    while k < n and is_ws(cs[k]):
        k += 1
    return Split(head: head, rest: join_range(cs, k, n))

// Splits off the last whitespace-separated word.
fn last_word(s: String) Split:
    let cs = s.trim_end().chars()
    let n = cs.length()
    var k = n
    while k > 0 and not is_ws(cs[k - 1]):
        k -= 1

    let word = join_range(cs, k, n)
    return Split(head: join_range(cs, 0, k).trim_end(), rest: word)

fn tail_of(xs: List[String]) List[String]:
    var out = List[String]()
    var k = 1

    while k < xs.length():
        out.append(xs[k].clone())
        k += 1

    return out

// Token splitting with double-quoted sections.
fn tokenize(s: String) Tokens:
    let cs = s.chars()
    let n = cs.length()
    var items = List[String]()
    var cur = ""
    var has = false
    var inq = false
    var k = 0

    while k < n:
        let c = cs[k]

        if inq:
            if c == "\\" and (at(cs, k + 1) == "\"" or at(cs, k + 1) == "\\"):
                cur = cur + cs[k + 1]
                k += 2
            else if c == "\"":
                inq = false
                k += 1
            else:
                cur = cur + c
                k += 1
        else if is_ws(c):
            if has:
                items.append(cur)
                cur = ""
                has = false

            k += 1
        else if c == "\"":
            inq = true
            has = true
            k += 1
        else:
            cur = cur + c
            has = true
            k += 1

    if inq:
        return Tokens(items: List[String](), ok: false)

    if has:
        items.append(cur)
    return Tokens(items: items, ok: true)

fn split_kv(tok: String) KV:
    let cs = tok.chars()
    let n = cs.length()
    var key = ""
    var k = 0

    while k < n and cs[k] != "=":
        key = key + cs[k]
        k += 1

    if k == n or k == 0:
        return KV(key: "", value: "", ok: false)

    let value = join_range(cs, k + 1, n)
    return KV(key: key, value: value, ok: true)

// Plain digits, leading zeros allowed. -1 when not all digits or empty.
fn plain_number(s: String) Int:
    let cs = s.chars()
    let n = cs.length()
    if n == 0 or n > 12:
        return -1

    var val = 0

    for c in cs:
        if not "0123456789".contains(c):
            return -1

        val = val * 10 + (c.scalar_at(0, 48) - 48)

    return val

// Integer rule: digits, no leading zeros except 0, at most 1000000. -1 if invalid.
fn int_value(s: String) Int:
    if s.length() > 1 and s.starts_with("0"):
        return -1

    let v = plain_number(s)
    if v > 1000000:
        return -1

    return v

fn parse_id_arg(arg: String) Int:
    var s = arg.clone()
    if s.starts_with("#"):
        s = drop_chars(s, 1)

    let v = plain_number(s)
    if v < 1:
        return 0

    return v

fn days_in_month(y: Int, m: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0:
            return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30

    return 31

fn date_valid(s: String) Bool:
    let cs = s.chars()
    if cs.length() != 10:
        return false

    var k = 0

    while k < 10:
        if k == 4 or k == 7:
            if cs[k] != "-":
                return false
        else:
            if not "0123456789".contains(cs[k]):
                return false

        k += 1

    let y = plain_number(join_range(cs, 0, 4))
    let m = plain_number(join_range(cs, 5, 7))
    let d = plain_number(join_range(cs, 8, 10))
    if y < 1 or m < 1 or m > 12 or d < 1:
        return false

    return d <= days_in_month(y, m)

fn label_ok(s: String) Bool:
    let cs = s.chars()
    if cs.length() == 0:
        return false

    for c in cs:
        if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(c):
            return false
    return true

fn state_name_ok(s: String) Bool:
    let cs = s.chars()
    let n = cs.length()
    if n == 0:
        return false
    if not "abcdefghijklmnopqrstuvwxyz".contains(cs[0]):
        return false

    var k = 1

    while k < n:
        if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(cs[k]):
            return false

        k += 1

    return true

fn view_name_ok(s: String) Bool:
    let cs = s.chars()
    let n = cs.length()
    if n == 0:
        return false
    if not "abcdefghijklmnopqrstuvwxyz".contains(cs[0]):
        return false

    var k = 1

    while k < n:
        if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(cs[k]):
            return false

        k += 1

    return true

fn rank_of(p: String) Int:
    if p == "low":
        return 0
    if p == "medium":
        return 1
    if p == "high":
        return 2
    if p == "critical":
        return 3

    return -1

fn index_of_s(xs: List[String], v: String) Int:
    var k = 0

    while k < xs.length():
        if xs[k] == v:
            return k

        k += 1

    return -1

fn add_state(var xs: List[String], name: String) Unit:
    if not xs.contains(name):
        xs.append(name.clone())

fn list_remove(var xs: List[String], x: String) Unit:
    var k = 0

    while k < xs.length():
        if xs[k] == x:
            xs.remove(k)
            return

        k += 1

fn parse_label_list(value: String) LabRes:
    var out = List[String]()
    let parts = value.split(",")

    for part in parts:
        let l = part.lower()
        if not label_ok(l):
            return LabRes(labels: List[String](), err: "bad label '" + l + "'")

        if not out.contains(l):
            out.append(l)

    out.sort()
    return LabRes(labels: out, err: "")

// ---------------------------------------------------------------- optional helpers

fn has_s(v: String?) Bool:
    if let x = v:
        return x.length() >= 0

    return false

fn has_i(v: Int?) Bool:
    if let x = v:
        return x >= 0

    return false

fn opt_s(v: String?) String:
    if let x = v:
        return x.clone()

    return "-"

fn opt_i(v: Int?) String:
    if let x = v:
        return "{x}"

    return "-"

fn key_s(v: String?) String:
    if let x = v:
        return "s:" + x

    return "n"

fn key_i(v: Int?) String:
    if let x = v:
        return "s:{x}"

    return "n"

fn copy_s(v: String?) String?:
    if let x = v:
        return x.clone()

    return none

fn labels_show(xs: List[String]) String:
    if xs.length() == 0:
        return "-"

    return xs.join(",")

// ---------------------------------------------------------------- fields

fn tok_simple(kind: String, text: String) Tok:
    return Tok(kind: kind, text: text, field: "", op: "", value: "", quoted: false)

fn tok_err(msg: String) Tok:
    return Tok(kind: "err", text: msg, field: "", op: "", value: "", quoted: false)

fn res_ok(s: String) Res:
    return Res(err: "", out: s)

fn res_err(s: String) Res:
    return Res(err: s, out: "")

fn emit_err(msg: String) Unit:
    print("error: " + msg)

fn show_res(r: Res) Unit:
    if r.err != "":
        print("error: " + r.err)
    else:
        print(r.out)

fn fields_of(iss: Issue) Fields:
    return Fields(
        title: iss.title.clone(), priority: iss.priority.clone(),
        assignee: copy_s(iss.assignee), points: iss.points, due: copy_s(iss.due),
        labels: iss.labels.clone(), reporter: copy_s(iss.reporter)
    )

fn store_fields(var st: State, idx: Int, f: Fields) Unit:
    st.issues[idx].title = f.title.clone()
    st.issues[idx].priority = f.priority.clone()
    st.issues[idx].assignee = copy_s(f.assignee)
    st.issues[idx].points = f.points
    st.issues[idx].due = copy_s(f.due)
    st.issues[idx].labels = f.labels.clone()
    st.issues[idx].reporter = copy_s(f.reporter)

// Validates and applies one field=value token. Returns an error message or "".
fn set_field(var f: Fields, field: String, value: String) String:
    if field == "title":
        if value.trim() == "":
            return "empty title"

        f.title = value.clone()
        return ""

    if field == "priority":
        if rank_of(value) < 0:
            return "bad priority '" + value + "'"

        f.priority = value.clone()
        return ""

    if field == "assignee":
        if value == "none":
            f.assignee = none
            return ""

        if value.trim() == "":
            return "empty assignee"

        f.assignee = value.clone()
        return ""

    if field == "reporter":
        if value == "none":
            f.reporter = none
            return ""

        if value.trim() == "":
            return "empty reporter"

        f.reporter = value.clone()
        return ""

    if field == "points":
        if value == "none":
            f.points = none
            return ""

        let v = int_value(value)
        if v < 0:
            return "bad points '" + value + "'"

        f.points = v
        return ""

    if field == "due":
        if value == "none":
            f.due = none
            return ""

        if not date_valid(value):
            return "bad date '" + value + "'"

        f.due = value.clone()
        return ""

    if field == "labels":
        if value == "none":
            f.labels = List[String]()
            return ""

        let r = parse_label_list(value)
        if r.err != "":
            return r.err

        f.labels = r.labels.clone()
        return ""

    if field == "state":
        return "use move to change state"

    return "unknown field '" + field + "'"

fn diff_fields(old: Fields, nw: Fields) List[String]:
    var out = List[String]()
    if old.title != nw.title:
        out.append("title: " + old.title + " -> " + nw.title)
    if old.priority != nw.priority:
        out.append("priority: " + old.priority + " -> " + nw.priority)
    if key_s(old.assignee) != key_s(nw.assignee):
        out.append("assignee: " + opt_s(old.assignee) + " -> " + opt_s(nw.assignee))
    if key_i(old.points) != key_i(nw.points):
        out.append("points: " + opt_i(old.points) + " -> " + opt_i(nw.points))
    if key_s(old.due) != key_s(nw.due):
        out.append("due: " + opt_s(old.due) + " -> " + opt_s(nw.due))

    let ol = labels_show(old.labels)
    let nl = labels_show(nw.labels)
    if ol != nl:
        out.append("labels: " + ol + " -> " + nl)
    if key_s(old.reporter) != key_s(nw.reporter):
        out.append("reporter: " + opt_s(old.reporter) + " -> " + opt_s(nw.reporter))
    return out

fn add_log(var st: State, id: Int, detail: String) Unit:
    st.log.append(
        LogEntry(t: st.clock, actor: st.actor.clone(), id: id, detail: detail)
    )

fn find_issue(st: State, id: Int) Int:
    var k = 0

    while k < st.issues.length():
        if st.issues[k].id == id:
            return k

        k += 1

    return -1

fn resolve_id(st: State, arg: String) IdRes:
    let id = parse_id_arg(arg)
    if id < 1:
        return IdRes(idx: -1, id: 0, err: "bad issue id '" + arg + "'")

    let idx = find_issue(st, id)
    if idx < 0:
        return IdRes(idx: -1, id: id, err: "no such issue #{id}")

    return IdRes(idx: idx, id: id, err: "")

fn is_final(st: State, s: String) Bool:
    return st.finals.contains(s)

fn guard_unmet(iss: Issue, g: String) Bool:
    if g == "assignee":
        return not has_s(iss.assignee)
    if g == "points":
        return not has_i(iss.points)
    if g == "due":
        return not has_s(iss.due)
    if g == "labels":
        return iss.labels.length() == 0
    if g == "reporter":
        return not has_s(iss.reporter)

    return false

// finish: compares old and new fields; logs and stores changes.
fn finish(var st: State, idx: Int, f: Fields) Res:
    let old = fields_of(st.issues[idx])
    let diffs = diff_fields(old, f)
    let id = st.issues[idx].id
    if diffs.length() == 0:
        return res_ok("#{id} unchanged")

    st.clock += 1
    store_fields(var st, idx, f)
    st.issues[idx].updated = st.clock
    for d in diffs:
        add_log(var st, id, d)
    return res_ok("updated #{id}")

// ---------------------------------------------------------------- operations

fn do_edit(var st: State, id: Int, toks: List[String]) Res:
    let idx = find_issue(st, id)
    let cur = st.issues[idx].state.clone()
    if is_final(st, cur):
        return res_err("#{id} is in final state '{cur}'")
    if toks.length() == 0:
        return res_err("usage: edit ID field=value...")

    var f = fields_of(st.issues[idx])

    for t in toks:
        let kv = split_kv(t)
        if not kv.ok:
            return res_err("expected field=value, got '" + t + "'")

        let e = set_field(var f, kv.key, kv.value)
        if e != "":
            return res_err(e)

    return finish(var st, idx, f)

fn do_label(var st: State, id: Int, ops: List[String]) Res:
    let idx = find_issue(st, id)
    let cur = st.issues[idx].state.clone()
    if is_final(st, cur):
        return res_err("#{id} is in final state '{cur}'")

    var labs = st.issues[idx].labels.clone()

    for op in ops:
        var sign = ""
        var name = op.clone()
        let oc = op.chars()

        if oc.length() > 0 and (oc[0] == "+" or oc[0] == "-"):
            sign = oc[0].clone()
            name = drop_chars(op, 1)

        let l = name.lower()
        if not label_ok(l):
            return res_err("bad label '" + l + "'")

        if sign == "-":
            list_remove(var labs, l)
        else:
            if not labs.contains(l):
                labs.append(l)

    labs.sort()

    var f = fields_of(st.issues[idx])
    f.labels = labs.clone()
    return finish(var st, idx, f)

fn do_move(var st: State, id: Int, target: String, comment: String) Res:
    let idx = find_issue(st, id)
    let cur = st.issues[idx].state.clone()
    if is_final(st, cur):
        return res_err("#{id} is in final state '{cur}'")
    if not st.states.contains(target):
        return res_err("unknown state '" + target + "'")
    if cur == target:
        return res_err("already in state '" + target + "'")

    var found = false
    var guards = List[String]()

    for tr in st.transitions:
        if not found and tr.src == cur and tr.dst == target:
            found = true
            guards = tr.guards.clone()

    if not found:
        return res_err("transition '" + cur + " -> " + target + "' not allowed")

    var missing = List[String]()
    for g in guards:
        if guard_unmet(st.issues[idx], g):
            missing.append(g.clone())

    if missing.length() > 0:
        let ms = missing.join(", ")
        return res_err("cannot move #{id} to {target}: missing {ms}")

    st.clock += 1
    st.issues[idx].state = target.clone()
    st.issues[idx].updated = st.clock
    st.issues[idx].history.append(Change(t: st.clock, state: target.clone()))
    add_log(var st, id, "state: " + cur + " -> " + target)

    if comment != "":
        st.issues[idx].comments.append(
            Comment(
                t: st.clock, actor: st.actor.clone(), text: comment.clone()
            )
        )
        add_log(var st, id, "comment: " + comment)

    return res_ok("moved #{id}: {cur} -> {target}")

fn do_comment(var st: State, id: Int, text: String) Res:
    let idx = find_issue(st, id)
    st.clock += 1
    st.issues[idx].updated = st.clock
    st.issues[idx].comments.append(
        Comment(t: st.clock, actor: st.actor.clone(), text: text.clone())
    )
    add_log(var st, id, "comment: " + text)
    return res_ok("commented #{id}")

fn do_delete(var st: State, id: Int) Res:
    let idx = find_issue(st, id)
    st.issues.remove(idx)
    st.clock += 1
    add_log(var st, id, "deleted")
    return res_ok("deleted #{id}")

// ---------------------------------------------------------------- workflow

type WfAcc:
    states: List[String]
    finals: List[String]
    trans: List[Transition]
    ntrans: Int
    initial: String
    has_init: Bool

fn wf_guard_check(gs: List[String]) String:
    for g in gs:
        if not (
            g == "assignee"
            or g == "points"
            or g == "due"
            or g == "labels"
            or g == "reporter"
        ):
            return "workflow: bad guard field '" + g + "'"
    return ""

fn wf_entry(var acc: WfAcc, left: String, ent: String, line: String) String:
    let w = ent.fields()
    var target = ""
    var guards = List[String]()

    if w.length() == 1:
        target = w[0].clone()
    else if w.length() == 3 and w[1] == "requires":
        target = w[0].clone()
        guards = w[2].split("+")

        let gerr = wf_guard_check(guards)
        if gerr != "":
            return gerr
    else:
        return "workflow: bad line '" + line + "'"

    if not state_name_ok(target):
        return "workflow: bad state name '" + target + "'"

    add_state(var acc.states, target)
    acc.trans.append(Transition(src: left.clone(), dst: target.clone(), guards: guards))
    acc.ntrans += 1
    return ""

fn wf_transition_line(var acc: WfAcc, line: String) String:
    let sides = line.split("->", 2)
    let left = sides[0].trim()
    if left.fields().length() != 1:
        return "workflow: bad line '" + line + "'"
    if not state_name_ok(left):
        return "workflow: bad state name '" + left + "'"

    add_state(var acc.states, left)

    let entries = sides[1].split(",")

    for ent in entries:
        let e = wf_entry(var acc, left, ent, line)
        if e != "":
            return e

    return ""

fn wf_final_line(var acc: WfAcc, line: String) String:
    let parts = drop_chars(line, 6).split(",")

    for part in parts:
        let name = part.trim()
        if not state_name_ok(name):
            return "workflow: bad state name '" + name + "'"

        add_state(var acc.states, name)
        acc.finals.append(name.clone())

    return ""

fn wf_initial_line(var acc: WfAcc, line: String) String:
    let name = drop_chars(line, 8).trim()
    if not state_name_ok(name):
        return "workflow: bad state name '" + name + "'"
    if acc.has_init:
        return "workflow: initial state defined twice"

    acc.has_init = true
    acc.initial = name.clone()
    add_state(var acc.states, name)
    return ""

fn wf_line(var acc: WfAcc, raw: String) String:
    let line = raw.trim()
    if line == "" or line.starts_with("#"):
        return ""
    if line.starts_with("initial:"):
        return wf_initial_line(var acc, line)
    if line.starts_with("final:"):
        return wf_final_line(var acc, line)
    if line.contains("->"):
        return wf_transition_line(var acc, line)

    return "workflow: bad line '" + line + "'"

fn wf_check_final_sources(acc: WfAcc) String:
    if not acc.has_init:
        return "workflow: initial state missing"

    for tr in acc.trans:
        if acc.finals.contains(tr.src):
            return "workflow: '" + tr.src + "' is final and cannot have transitions"
    return ""

fn cmd_workflow(var st: State, block: List[String]) Unit:
    if st.next_id > 1:
        emit_err("workflow: cannot redefine after issues were created")
        return

    var acc = WfAcc(
        states: List[String](), finals: List[String](), trans: List[Transition](),
        ntrans: 0, initial: "", has_init: false
    )
    var err = ""
    var k = 0

    while k < block.length() and err == "":
        err = wf_line(var acc, block[k])
        k += 1

    if err == "":
        err = wf_check_final_sources(acc)

    if err != "":
        emit_err(err)
        return

    st.has_workflow = true
    st.initial = acc.initial.clone()
    st.states = acc.states.clone()
    st.finals = acc.finals.clone()
    st.transitions = acc.trans.clone()

    let ns = acc.states.length()
    let nt = acc.ntrans
    print("workflow ok: {ns} states, {nt} transitions")

// ---------------------------------------------------------------- queries

fn is_field_char(c: String) Bool:
    return "abcdefghijklmnopqrstuvwxyz_".contains(c)

fn join_word(cs: List[String], k: Int, n: Int) Int:
    var j = k
    while j < n and not is_ws(cs[j]) and cs[j] != "(" and cs[j] != ")":
        j += 1
    return j

fn lex_query(s: String) List[Tok]:
    let cs = s.chars()
    let n = cs.length()
    var toks = List[Tok]()
    var k = 0

    while k < n:
        let c = cs[k]

        if is_ws(c):
            k += 1
        else if c == "(":
            toks.append(tok_simple("lp", "("))
            k += 1
        else if c == ")":
            toks.append(tok_simple("rp", ")"))
            k += 1
        else:
            let j = join_word(cs, k, n)
            let word = join_range(cs, k, j)

            if word == "AND":
                toks.append(tok_simple("and", "AND"))
                k = j
            else if word == "OR":
                toks.append(tok_simple("or", "OR"))
                k = j
            else if word == "NOT":
                toks.append(tok_simple("not", "NOT"))
                k = j
            else:
                var fe = k
                while fe < n and is_field_char(cs[fe]):
                    fe += 1

                let field = join_range(cs, k, fe)
                var op = ""

                if at(cs, fe) == "!" and at(cs, fe + 1) == "=":
                    op = "!="
                else if at(cs, fe) == "<" and at(cs, fe + 1) == "=":
                    op = "<="
                else if at(cs, fe) == ">" and at(cs, fe + 1) == "=":
                    op = ">="
                else if (
                    at(cs, fe) == ":"
                    or at(cs, fe) == "<"
                    or at(cs, fe) == ">"
                    or at(cs, fe) == "~"
                ):
                    op = at(cs, fe)

                if field == "" or op == "":
                    toks.append(tok_err("query: unexpected token '" + word + "'"))
                    k = j
                else:
                    let vs = fe + op.length()

                    if at(cs, vs) == "\"":
                        var e = vs + 1
                        var val = ""
                        var closed = false

                        while e < n:
                            if (
                                cs[e] == "\\"
                                and (
                                    at(
                                        cs, e + 1
                                    ) == "\""
                                    or at(
                                        cs, e + 1
                                    ) == "\\"
                                )
                            ):
                                val = val + cs[e + 1]
                                e += 2
                            else if cs[e] == "\"":
                                closed = true
                                e += 1
                                break
                            else:
                                val = val + cs[e]
                                e += 1

                        if not closed:
                            toks.append(tok_err("query: unterminated quote"))
                            return toks

                        toks.append(
                            Tok(
                                kind: "term", text: "", field: field, op: op,
                                value: val, quoted: true
                            )
                        )
                        k = e
                    else:
                        let e = join_word(cs, vs, n)
                        let val = join_range(cs, vs, e)
                        toks.append(
                            Tok(
                                kind: "term", text: "", field: field, op: op,
                                value: val, quoted: false
                            )
                        )
                        k = e

    return toks

fn known_field(f: String) Bool:
    return (
        f == "id"
        or f == "created"
        or f == "updated"
        or f == "points"
        or f == "title"
        or f == "assignee"
        or f == "reporter"
        or f == "text"
        or f == "state"
        or f == "priority"
        or f == "due"
        or f == "label"
        or f == "labels"
        or f == "is"
        or f == "has"
        or f == "view"
    )

fn op_allowed(f: String, op: String) Bool:
    if (
        f == "id"
        or f == "created"
        or f == "updated"
        or f == "points"
        or f == "priority"
        or f == "due"
    ):
        return (
            op == ":"
            or op == "!="
            or op == "<"
            or op == "<="
            or op == ">"
            or op == ">="
        )
    if (
        f == "title"
        or f == "assignee"
        or f == "reporter"
        or f == "label"
        or f == "labels"
    ):
        return op == ":" or op == "!=" or op == "~"
    if f == "text":
        return op == "~"
    if f == "state":
        return op == ":" or op == "!="

    return op == ":"

fn is_ordered(op: String) Bool:
    return op == "<" or op == "<=" or op == ">" or op == ">="

fn value_ok(st: State, f: String, op: String, v: String) Bool:
    if f == "id" or f == "created" or f == "updated":
        return int_value(v) >= 0

    if f == "points":
        if v == "none" and (op == ":" or op == "!="):
            return true

        return int_value(v) >= 0

    if f == "priority":
        return rank_of(v) >= 0
    if f == "state":
        return st.states.contains(v)

    if f == "due":
        if v == "none" and (op == ":" or op == "!="):
            return true

        return date_valid(v)

    if f == "is":
        return v == "open" or v == "final" or v == "overdue" or v == "unassigned"
    if f == "has":
        return (
            v == "assignee"
            or v == "due"
            or v == "points"
            or v == "labels"
            or v == "comments"
            or v == "reporter"
        )

    return true

fn node_bin(kind: String, a: Int, b: Int) QNode:
    return QNode(kind: kind, a: a, b: b, field: "", op: "", values: List[String]())

fn node_ref(a: Int) QNode:
    return QNode(kind: "ref", a: a, b: -1, field: "", op: "", values: List[String]())

fn node_term(field: String, op: String, values: List[String]) QNode:
    return QNode(kind: "term", a: -1, b: -1, field: field, op: op, values: values)

fn add_node(var p: Parser, nd: QNode) Int:
    p.nodes.append(nd)
    return p.nodes.length() - 1

fn peek_kind(p: Parser) String:
    if p.pos >= p.toks.length():
        return "end"

    return p.toks[p.pos].kind.clone()

fn unexpected_msg(t: Tok) String:
    return "query: unexpected token '" + t.text + "'"

fn check_view(var p: Parser, st: State, name: String) Int:
    let vi = find_view(st, name)

    if vi < 0:
        p.err = "query: unknown view '" + name + "'"
        return -1

    let stored = split_clauses(st.views[vi].query)
    let ftext = stored.filter.clone()
    if ftext == "":
        return add_node(var p, node_ref(-1))

    let saved = p.toks.clone()
    let saved_pos = p.pos
    p.toks = lex_query(ftext)
    p.pos = 0

    let r = p_or(var p, st)
    p.toks = saved
    p.pos = saved_pos
    if p.err != "":
        return -1

    return add_node(var p, node_ref(r))

fn check_term(var p: Parser, st: State, t: Tok) Int:
    let f = t.field.clone()

    if not known_field(f):
        p.err = "query: unknown field '" + f + "'"
        return -1

    if f == "view":
        if t.op != ":":
            p.err = "query: bad operator '" + t.op + "' for field 'view'"
            return -1

        return check_view(var p, st, t.value)

    if not op_allowed(f, t.op):
        p.err = "query: bad operator '" + t.op + "' for field '" + f + "'"
        return -1

    var vals = List[String]()

    if t.quoted or is_ordered(t.op):
        vals.append(t.value.clone())
    else:
        vals = t.value.split("|")

    for v in vals:
        if not value_ok(st, f, t.op, v):
            p.err = "query: bad value '" + v + "' for field '" + f + "'"
            return -1

    return add_node(var p, node_term(f, t.op, vals))

fn p_primary(var p: Parser, st: State) Int:
    if p.pos >= p.toks.length():
        p.err = "query: unexpected end of query"
        return -1

    let t = p.toks[p.pos].clone()
    p.pos += 1

    if t.kind == "err":
        p.err = t.text.clone()
        return -1

    if t.kind == "term":
        return check_term(var p, st, t)

    if t.kind == "lp":
        let inner = p_or(var p, st)
        if p.err != "":
            return -1

        if p.pos >= p.toks.length():
            p.err = "query: unexpected end of query"
            return -1

        let c = p.toks[p.pos].clone()

        if c.kind != "rp":
            p.err = unexpected_msg(c)
            return -1

        p.pos += 1
        return inner

    p.err = unexpected_msg(t)
    return -1

fn p_not(var p: Parser, st: State) Int:
    if peek_kind(p) == "not":
        p.pos += 1

        let inner = p_not(var p, st)
        if p.err != "":
            return -1

        return add_node(var p, node_bin("not", inner, -1))

    return p_primary(var p, st)

fn p_and(var p: Parser, st: State) Int:
    var left = p_not(var p, st)
    if p.err != "":
        return -1

    while true:
        let k = peek_kind(p)
        var cont = false

        if k == "and":
            p.pos += 1
            cont = true
        else if k == "term" or k == "lp" or k == "not" or k == "err":
            cont = true

        if not cont:
            break

        let right = p_not(var p, st)
        if p.err != "":
            return -1

        left = add_node(var p, node_bin("and", left, right))

    return left

fn p_or(var p: Parser, st: State) Int:
    var left = p_and(var p, st)
    if p.err != "":
        return -1

    while peek_kind(p) == "or":
        p.pos += 1

        let right = p_and(var p, st)
        if p.err != "":
            return -1

        left = add_node(var p, node_bin("or", left, right))

    return left

fn parse_query(st: State, text: String) Query:
    let toks = lex_query(text)
    if toks.length() == 0:
        return Query(nodes: List[QNode](), root: -1, err: "")

    let n = toks.length()
    var p = Parser(toks: toks, pos: 0, nodes: List[QNode](), err: "")
    let root = p_or(var p, st)
    if p.err == "" and p.pos < n:
        p.err = unexpected_msg(p.toks[p.pos].clone())

    let perr = p.err.clone()
    return Query(nodes: p.nodes.clone(), root: root, err: perr)

fn str_cmp_op(a: String, op: String, b: String) Bool:
    if op == "<":
        return a < b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == ">=":
        return a >= b

    return a == b

fn int_cmp(a: Int, op: String, b: Int) Bool:
    if op == "<":
        return a < b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == ">=":
        return a >= b

    return a == b

fn str_match(a: String, op: String, v: String) Bool:
    if op == "~":
        return a.lower().contains(v.lower())

    return a.lower() == v.lower()

fn match_one(st: State, iss: Issue, field: String, op: String, v: String) Bool:
    if field == "id":
        return int_cmp(iss.id, op, int_value(v))
    if field == "created":
        return int_cmp(iss.created, op, int_value(v))
    if field == "updated":
        return int_cmp(iss.updated, op, int_value(v))

    if field == "points":
        if v == "none" and op == ":":
            return not has_i(iss.points)
        if not has_i(iss.points):
            return false

        return int_cmp(opt_int_val(iss.points), op, int_value(v))

    if field == "priority":
        return int_cmp(rank_of(iss.priority), op, rank_of(v))
    if field == "title":
        return str_match(iss.title, op, v)

    if field == "assignee":
        if not has_s(iss.assignee):
            return op == ":" and v == "none"

        return str_match(opt_s(iss.assignee), op, v)

    if field == "reporter":
        if not has_s(iss.reporter):
            return op == ":" and v == "none"

        return str_match(opt_s(iss.reporter), op, v)

    if field == "text":
        if iss.title.lower().contains(v.lower()):
            return true

        for c in iss.comments:
            if c.text.lower().contains(v.lower()):
                return true
        return false

    if field == "state":
        return iss.state == v

    if field == "due":
        if not has_s(iss.due):
            return op == ":" and v == "none"
        if v == "none":
            return false

        return str_cmp_op(opt_s(iss.due), op, v)

    if field == "label" or field == "labels":
        if op == ":" and v == "none":
            return iss.labels.length() == 0

        let lv = v.lower()

        if op == "~":
            for l in iss.labels:
                if l.contains(lv):
                    return true
            return false

        return iss.labels.contains(lv)

    if field == "is":
        if v == "open":
            return not is_final(st, iss.state)
        if v == "final":
            return is_final(st, iss.state)

        if v == "overdue":
            if not has_s(iss.due):
                return false
            if is_final(st, iss.state):
                return false

            return opt_s(iss.due) < st.today

        if v == "unassigned":
            return not has_s(iss.assignee)

        return false

    if field == "has":
        if v == "assignee":
            return has_s(iss.assignee)
        if v == "due":
            return has_s(iss.due)
        if v == "points":
            return has_i(iss.points)
        if v == "labels":
            return iss.labels.length() > 0
        if v == "comments":
            return iss.comments.length() > 0
        if v == "reporter":
            return has_s(iss.reporter)

        return false

    return false

fn opt_int_val(v: Int?) Int:
    if let x = v:
        return x

    return 0

fn term_match(st: State, iss: Issue, nd: QNode) Bool:
    if nd.op == "!=":
        for v in nd.values:
            if match_one(st, iss, nd.field, ":", v):
                return false
        return true

    for v in nd.values:
        if match_one(st, iss, nd.field, nd.op, v):
            return true
    return false

fn eval_node(q: Query, idx: Int, st: State, iss: Issue) Bool:
    let nd = q.nodes[idx].clone()
    if nd.kind == "and":
        return eval_node(q, nd.a, st, iss) and eval_node(q, nd.b, st, iss)
    if nd.kind == "or":
        return eval_node(q, nd.a, st, iss) or eval_node(q, nd.b, st, iss)
    if nd.kind == "not":
        return not eval_node(q, nd.a, st, iss)

    if nd.kind == "ref":
        if nd.a < 0:
            return true

        return eval_node(q, nd.a, st, iss)

    return term_match(st, iss, nd)

fn query_match(q: Query, st: State, iss: Issue) Bool:
    if q.root < 0:
        return true

    return eval_node(q, q.root, st, iss)

// Clause splitting for list / view save / view run.
fn find_sort_pos(s: String) Int:
    let cs = s.chars()
    let n = cs.length()
    var k = 0

    while k < n:
        var pre = k == 0
        if k > 0:
            pre = is_ws(cs[k - 1])
        if (
            pre
            and at(cs, k) == "s"
            and at(cs, k + 1) == "o"
            and at(cs, k + 2) == "r"
            and at(cs, k + 3) == "t"
            and is_ws(at(cs, k + 4))
        ):
            return k

        k += 1

    return -1

fn sort_field_ok(f: String) Bool:
    return (
        f == "id"
        or f == "created"
        or f == "updated"
        or f == "priority"
        or f == "points"
        or f == "state"
        or f == "title"
        or f == "assignee"
        or f == "reporter"
        or f == "due"
    )

fn split_clauses(text: String) Clauses:
    let t0 = text.trim()
    var err = ""
    var has_limit = false
    var limit = 0
    var filt = t0.clone()
    let l1 = last_word(t0)
    let l2 = last_word(l1.head)

    if l2.rest == "limit":
        has_limit = true

        let v = plain_number(l1.rest)

        if v < 0:
            err = "bad limit '" + l1.rest + "'"
        else:
            limit = v

        filt = l2.head.clone()

    var has_sort = false
    var sorts = List[SortKey]()
    var serr = ""
    let sk = find_sort_pos(filt)

    if sk >= 0:
        has_sort = true

        let fcs = filt.chars()
        let sort_text = join_range(fcs, sk + 4, fcs.length())
        filt = join_range(fcs, 0, sk).trim()

        let pieces = sort_text.replace(",", " ").fields()

        for piece in pieces:
            var desc = false
            var name = piece.clone()

            if piece.starts_with("-"):
                desc = true
                name = drop_chars(piece, 1)

            if not sort_field_ok(name):
                if serr == "":
                    serr = "bad sort field '" + name + "'"
            else:
                sorts.append(SortKey(field: name, desc: desc))

    return Clauses(
        err: err, filter: filt, has_sort: has_sort, sorts: sorts, sort_err: serr,
        has_limit: has_limit, limit: limit
    )

fn cmp_int_v(a: Int, b: Int) Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

fn cmp_str_v(a: String, b: String) Int:
    if a < b:
        return -1
    if a > b:
        return 1

    return 0

fn cmp_opt_int(x: Int?, y: Int?) Int:
    if let p = x:
        if let q = y:
            return cmp_int_v(p, q)

        return -1

    if has_i(y):
        return 1

    return 0

fn cmp_opt_str(x: String?, y: String?, ci: Bool) Int:
    if has_s(x):
        if has_s(y):
            let a = opt_s(x)
            let b = opt_s(y)
            if ci:
                return cmp_str_v(a.lower(), b.lower())

            return cmp_str_v(a, b)

        return -1

    if has_s(y):
        return 1

    return 0

fn compare_field(st: State, a: Issue, b: Issue, field: String) Int:
    if field == "id":
        return cmp_int_v(a.id, b.id)
    if field == "created":
        return cmp_int_v(a.created, b.created)
    if field == "updated":
        return cmp_int_v(a.updated, b.updated)
    if field == "priority":
        return cmp_int_v(rank_of(a.priority), rank_of(b.priority))
    if field == "state":
        return cmp_int_v(index_of_s(st.states, a.state), index_of_s(st.states, b.state))
    if field == "points":
        return cmp_opt_int(a.points, b.points)
    if field == "title":
        return cmp_str_v(a.title.lower(), b.title.lower())
    if field == "assignee":
        return cmp_opt_str(a.assignee, b.assignee, true)
    if field == "reporter":
        return cmp_opt_str(a.reporter, b.reporter, true)
    if field == "due":
        return cmp_opt_str(a.due, b.due, false)

    return 0

fn cmp_issue(st: State, keys: List[SortKey], a: Int, b: Int) Int:
    for key in keys:
        var c = compare_field(st, st.issues[a], st.issues[b], key.field)
        if key.desc:
            c = 0 - c
        if c != 0:
            return c

    return cmp_int_v(st.issues[a].id, st.issues[b].id)

fn sort_idxs(st: State, idxs: List[Int], keys: List[SortKey]) List[Int]:
    var out = List[Int]()

    for k in idxs:
        var pos = out.length()
        while pos > 0 and cmp_issue(st, keys, out[pos - 1], k) > 0:
            pos -= 1
        out.insert(pos, k)

    return out

fn select_issues(
    st: State,
    q: Query,
    keys: List[SortKey],
    has_limit: Bool,
    limit: Int
) List[Int]:
    var idxs = List[Int]()
    var k = 0

    while k < st.issues.length():
        if query_match(q, st, st.issues[k]):
            idxs.append(k)
        k += 1

    if keys.length() > 0:
        idxs = sort_idxs(st, idxs, keys)
    if has_limit:
        while idxs.length() > limit:
            idxs.remove(idxs.length() - 1)
    return idxs

fn issue_line(iss: Issue) String:
    let asg = opt_s(iss.assignee)
    let pts = opt_i(iss.points)
    let due = opt_s(iss.due)
    let lab = labels_show(iss.labels)
    return "#{iss.id} | {iss.state} | {iss.priority} | {asg} | {pts} | {due} | {lab} | {iss.title}"

fn print_issues(st: State, idxs: List[Int]) Unit:
    for k in idxs:
        print(issue_line(st.issues[k]))

    let n = idxs.length()

    if n == 1:
        print("(1 issue)")
    else:
        print("({n} issues)")

fn cmd_list(st: State, rest: String) Unit:
    let cl = split_clauses(rest)

    if cl.err != "":
        emit_err(cl.err)
        return

    let q = parse_query(st, cl.filter)

    if q.err != "":
        emit_err(q.err)
        return

    if cl.sort_err != "":
        emit_err(cl.sort_err)
        return

    let idxs = select_issues(st, q, cl.sorts, cl.has_limit, cl.limit)
    print_issues(st, idxs)

// ---------------------------------------------------------------- views

fn find_view(st: State, name: String) Int:
    var k = 0

    while k < st.views.length():
        if st.views[k].name == name:
            return k

        k += 1

    return -1

fn view_refs(text: String) List[String]:
    let cl = split_clauses(text)
    let toks = lex_query(cl.filter)
    var out = List[String]()
    for t in toks:
        if t.kind == "term" and t.field == "view":
            out.append(t.value.clone())
    return out

fn reaches(st: State, target: String, text: String, depth: Int) Bool:
    if depth > 40:
        return false

    let refs = view_refs(text)

    for name in refs:
        if name == target:
            return true

        let vi = find_view(st, name)
        if vi >= 0:
            if reaches(st, target, st.views[vi].query, depth + 1):
                return true

    return false

fn sorted_views(st: State) List[Int]:
    var out = List[Int]()

    for k in 0..st.views.length():
        var pos = out.length()
        while pos > 0 and st.views[out[pos - 1]].name > st.views[k].name:
            pos -= 1
        out.insert(pos, k)

    return out

fn cmd_view_save(var st: State, args: String) Unit:
    let sp = split_head(args)

    if sp.head == "":
        emit_err("usage: view save NAME QUERY")
        return

    let name = sp.head.clone()
    let qtext = sp.rest.trim()

    if not view_name_ok(name):
        emit_err("bad view name '" + name + "'")
        return

    let cl = split_clauses(qtext)

    if cl.err != "":
        emit_err(cl.err)
        return

    let q = parse_query(st, cl.filter)

    if q.err != "":
        emit_err(q.err)
        return

    if cl.sort_err != "":
        emit_err(cl.sort_err)
        return

    if reaches(st, name, qtext, 0):
        emit_err("view '" + name + "' would reference itself")
        return

    let vi = find_view(st, name)

    if vi >= 0:
        st.views[vi].query = qtext.clone()
    else:
        st.views.append(View(name: name.clone(), query: qtext.clone()))

    print("saved view " + name)

fn cmd_view_run(st: State, args: String) Unit:
    let sp = split_head(args)

    if sp.head == "":
        emit_err("usage: view run NAME [sort FIELDS] [limit N]")
        return

    let name = sp.head.clone()
    let vi = find_view(st, name)

    if vi < 0:
        emit_err("unknown view '" + name + "'")
        return

    let ra = split_clauses(sp.rest)

    if ra.err != "":
        emit_err(ra.err)
        return

    if ra.filter != "":
        emit_err("unexpected '" + ra.filter + "'")
        return

    if ra.sort_err != "":
        emit_err(ra.sort_err)
        return

    let stored = split_clauses(st.views[vi].query)
    let q = parse_query(st, stored.filter)

    if q.err != "":
        emit_err(q.err)
        return

    var keys = stored.sorts.clone()
    var has_limit = stored.has_limit
    var limit = stored.limit
    if ra.has_sort:
        keys = ra.sorts.clone()

    if ra.has_limit:
        has_limit = true
        limit = ra.limit

    let idxs = select_issues(st, q, keys, has_limit, limit)
    print_issues(st, idxs)

fn cmd_view_list(st: State) Unit:
    if st.views.length() == 0:
        print("(no views)")
        return

    for k in sorted_views(st):
        print(st.views[k].name + ": " + st.views[k].query)

fn cmd_view_show(st: State, args: String) Unit:
    let name = split_head(args).head.clone()

    if name == "":
        emit_err("usage: view show NAME")
        return

    let vi = find_view(st, name)

    if vi < 0:
        emit_err("unknown view '" + name + "'")
        return

    print(name + ": " + st.views[vi].query)

fn cmd_view_delete(var st: State, args: String) Unit:
    let name = split_head(args).head.clone()

    if name == "":
        emit_err("usage: view delete NAME")
        return

    let vi = find_view(st, name)

    if vi < 0:
        emit_err("unknown view '" + name + "'")
        return

    for k in sorted_views(st):
        let other = st.views[k].name.clone()
        let otext = st.views[k].query.clone()

        if other != name and reaches(st, name, otext, 0):
            emit_err("view '" + name + "' is used by '" + other + "'")
            return

    st.views.remove(vi)
    print("deleted view " + name)

fn cmd_view(var st: State, rest: String) Unit:
    let sp = split_head(rest)
    let sub = sp.head.clone()
    let args = sp.rest.clone()

    if sub == "save":
        cmd_view_save(var st, args)
    else if sub == "run":
        cmd_view_run(st, args)
    else if sub == "list":
        cmd_view_list(st)
    else if sub == "show":
        cmd_view_show(st, args)
    else if sub == "delete":
        cmd_view_delete(var st, args)
    else:
        emit_err("usage: view save|run|list|show|delete")

// ---------------------------------------------------------------- commands

fn cmd_actor(var st: State, rest: String) Unit:
    let w = rest.fields()

    if w.length() != 1:
        emit_err("usage: actor NAME")
        return

    st.actor = w[0].clone()
    print("actor is " + w[0])

fn cmd_today(var st: State, rest: String) Unit:
    let w = rest.fields()

    if w.length() != 1:
        emit_err("usage: today DATE")
        return

    if not date_valid(w[0]):
        emit_err("bad date '" + w[0] + "'")
        return

    st.today = w[0].clone()
    print("today is " + w[0])

fn cmd_create(var st: State, rest: String) Unit:
    if not st.has_workflow:
        emit_err("no workflow defined")
        return

    let tk = tokenize(rest)

    if not tk.ok:
        emit_err("unterminated quote")
        return

    if tk.items.length() == 0:
        emit_err("usage: create TITLE [field=value...]")
        return

    let title0 = tk.items[0].clone()

    if title0.trim() == "":
        emit_err("empty title")
        return

    let defaults = Fields(
        title: title0.clone(), priority: "medium", assignee: none, points: none,
        due: none, labels: List[String](), reporter: st.actor.clone()
    )
    var f = Fields(
        title: title0.clone(), priority: "medium", assignee: none, points: none,
        due: none, labels: List[String](), reporter: st.actor.clone()
    )
    var k = 1

    while k < tk.items.length():
        let kv = split_kv(tk.items[k])

        if not kv.ok:
            emit_err("expected field=value, got '" + tk.items[k] + "'")
            return

        let e = set_field(var f, kv.key, kv.value)

        if e != "":
            emit_err(e)
            return

        k += 1

    let diffs = diff_fields(defaults, f)
    st.clock += 1

    let id = st.next_id
    st.next_id += 1
    st.issues.append(
        Issue(
            id: id, title: f.title.clone(), state: st.initial.clone(),
            priority: f.priority.clone(), assignee: copy_s(f.assignee),
            reporter: copy_s(f.reporter), points: f.points, due: copy_s(f.due),
            labels: f.labels.clone(), comments: List[Comment](), created: st.clock,
            updated: st.clock, history: List[Change]()
        )
    )
    add_log(var st, id, "created \"" + title0 + "\"")
    for d in diffs:
        add_log(var st, id, d)
    print("created #{id}")

fn cmd_edit(var st: State, rest: String) Unit:
    let tk = tokenize(rest)

    if not tk.ok:
        emit_err("unterminated quote")
        return

    if tk.items.length() == 0:
        emit_err("usage: edit ID field=value...")
        return

    let r0 = resolve_id(st, tk.items[0])

    if r0.err != "":
        emit_err(r0.err)
        return

    show_res(do_edit(var st, r0.id, tail_of(tk.items)))

fn cmd_assign(var st: State, rest: String) Unit:
    let tk = tokenize(rest)

    if not tk.ok:
        emit_err("unterminated quote")
        return

    if tk.items.length() != 2:
        emit_err("usage: assign ID NAME")
        return

    let r0 = resolve_id(st, tk.items[0])

    if r0.err != "":
        emit_err(r0.err)
        return

    let kv = "assignee=" + tk.items[1]
    show_res(do_edit(var st, r0.id, [kv]))

fn cmd_label(var st: State, rest: String) Unit:
    let tk = tokenize(rest)

    if not tk.ok:
        emit_err("unterminated quote")
        return

    if tk.items.length() < 2:
        emit_err("usage: label ID +label -label...")
        return

    let r0 = resolve_id(st, tk.items[0])

    if r0.err != "":
        emit_err(r0.err)
        return

    show_res(do_label(var st, r0.id, tail_of(tk.items)))

fn cmd_move(var st: State, rest: String) Unit:
    let s1 = split_head(rest)
    let s2 = split_head(s1.rest)

    if s1.head == "" or s2.head == "":
        emit_err("usage: move ID STATE [comment...]")
        return

    let r0 = resolve_id(st, s1.head)

    if r0.err != "":
        emit_err(r0.err)
        return

    show_res(do_move(var st, r0.id, s2.head, s2.rest.trim()))

fn cmd_comment(var st: State, rest: String) Unit:
    let s1 = split_head(rest)
    let text = s1.rest.trim()

    if s1.head == "" or text == "":
        emit_err("usage: comment ID TEXT")
        return

    let r0 = resolve_id(st, s1.head)

    if r0.err != "":
        emit_err(r0.err)
        return

    show_res(do_comment(var st, r0.id, text))

fn cmd_delete(var st: State, rest: String) Unit:
    let w = rest.fields()

    if w.length() != 1:
        emit_err("usage: delete ID")
        return

    let r0 = resolve_id(st, w[0])

    if r0.err != "":
        emit_err(r0.err)
        return

    show_res(do_delete(var st, r0.id))

fn cmd_show(st: State, rest: String) Unit:
    let w = rest.fields()

    if w.length() != 1:
        emit_err("usage: show ID")
        return

    let r0 = resolve_id(st, w[0])

    if r0.err != "":
        emit_err(r0.err)
        return

    let iss = st.issues[r0.idx].clone()
    let asg = opt_s(iss.assignee)
    let pts = opt_i(iss.points)
    let due = opt_s(iss.due)
    let rep = opt_s(iss.reporter)
    var lab = "-"
    if iss.labels.length() > 0:
        lab = iss.labels.join(", ")
    print("#{iss.id} {iss.title}")
    print("  state: {iss.state}")
    print("  priority: {iss.priority}")
    print("  assignee: {asg}")
    print("  points: {pts}")
    print("  due: {due}")
    print("  labels: {lab}")
    print("  reporter: {rep}")
    print("  created: t={iss.created}, updated: t={iss.updated}")

    let nc = iss.comments.length()
    print("  comments: {nc}")
    for c in iss.comments:
        print("    [t={c.t} {c.actor}] {c.text}")

fn cmd_log(st: State, rest: String) Unit:
    let w = rest.fields()
    var filter_id = 0
    var tail = -1

    if w.length() == 0:
        tail = -1
    else if w[0] == "tail":
        if w.length() != 2:
            emit_err("usage: log [ID] [tail N]")
            return

        tail = plain_number(w[1])

        if tail < 0:
            emit_err("bad tail '" + w[1] + "'")
            return
    else:
        let id = parse_id_arg(w[0])

        if id < 1:
            emit_err("bad issue id '" + w[0] + "'")
            return

        if id >= st.next_id:
            emit_err("no such issue #{id}")
            return

        filter_id = id

        if w.length() == 3 and w[1] == "tail":
            tail = plain_number(w[2])

            if tail < 0:
                emit_err("bad tail '" + w[2] + "'")
                return
        else if w.length() != 1:
            emit_err("usage: log [ID] [tail N]")
            return

    var idxs = List[Int]()
    var k = 0

    while k < st.log.length():
        if filter_id == 0 or st.log[k].id == filter_id:
            idxs.append(k)
        k += 1

    var start = 0
    if tail >= 0 and idxs.length() > tail:
        start = idxs.length() - tail

    if idxs.length() == 0 or start >= idxs.length():
        print("(no log entries)")
        return

    var j = start

    while j < idxs.length():
        let e = st.log[idxs[j]].clone()
        print("t={e.t} {e.actor} #{e.id} {e.detail}")
        j += 1

fn report_summary(st: State) Unit:
    var total = st.issues.length()
    var nopen = 0
    var nfinal = 0
    var unassigned = 0
    var overdue = 0
    var points = 0

    for iss in st.issues:
        if is_final(st, iss.state):
            nfinal += 1
        else:
            nopen += 1
            if not has_s(iss.assignee):
                unassigned += 1
            if has_s(iss.due):
                if opt_s(iss.due) < st.today:
                    overdue += 1
            if has_i(iss.points):
                points += opt_int_val(iss.points)

    print("issues: {total} (open {nopen}, final {nfinal})")
    print("by state:")

    for s in st.states:
        var cnt = 0
        for iss in st.issues:
            if iss.state == s:
                cnt += 1
        print("  {s}: {cnt}")

    print("by priority:")

    let pris = ["critical", "high", "medium", "low"]

    for pr in pris:
        var cnt = 0
        for iss in st.issues:
            if iss.priority == pr:
                cnt += 1
        print("  {pr}: {cnt}")

    print("unassigned: {unassigned}")
    print("overdue: {overdue}")
    print("open points: {points}")

fn group_before(pts: List[Int], cnt: List[Int], keys: List[String], a: Int, b: Int) Bool:
    if pts[a] != pts[b]:
        return pts[a] > pts[b]
    if cnt[a] != cnt[b]:
        return cnt[a] > cnt[b]

    return keys[a] < keys[b]

fn report_workload(st: State) Unit:
    var keys = List[String]()
    var disp = List[String]()
    var cnt = List[Int]()
    var pts = List[Int]()
    var un_cnt = 0
    var un_pts = 0
    var any_open = false

    for iss in st.issues:
        if is_final(st, iss.state):
            continue

        any_open = true

        var p = 0
        if has_i(iss.points):
            p = opt_int_val(iss.points)

        if has_s(iss.assignee):
            let a = opt_s(iss.assignee)
            let key = a.lower()
            let gi = index_of_s(keys, key)

            if gi < 0:
                keys.append(key.clone())
                disp.append(a.clone())
                cnt.append(1)
                pts.append(p)
            else:
                cnt[gi] = cnt[gi] + 1
                pts[gi] = pts[gi] + p
        else:
            un_cnt += 1
            un_pts += p

    if not any_open:
        print("(no open issues)")
        return

    var order = List[Int]()

    for g in 0..keys.length():
        var pos = order.length()
        while pos > 0 and group_before(pts, cnt, keys, g, order[pos - 1]):
            pos -= 1
        order.insert(pos, g)

    for g in order:
        let n = cnt[g]
        let word = if n == 1: "issue" else: "issues"
        let pp = pts[g]
        print("{disp[g]}: {n} {word}, {pp} points")

    if un_cnt > 0:
        let word = if un_cnt == 1: "issue" else: "issues"
        print("unassigned: {un_cnt} {word}, {un_pts} points")

fn report_labels(st: State, args: String) Unit:
    let q = parse_query(st, args)

    if q.err != "":
        emit_err(q.err)
        return

    var names = List[String]()
    var counts = List[Int]()

    for iss in st.issues:
        if query_match(q, st, iss):
            for l in iss.labels:
                let gi = index_of_s(names, l)

                if gi < 0:
                    names.append(l.clone())
                    counts.append(1)
                else:
                    counts[gi] = counts[gi] + 1

    if names.length() == 0:
        print("(no labels)")
        return

    var order = List[Int]()

    for g in 0..names.length():
        var pos = order.length()

        while pos > 0:
            let prev = order[pos - 1]
            var before = false

            if counts[g] != counts[prev]:
                before = counts[g] > counts[prev]
            else:
                before = names[g] < names[prev]

            if not before:
                break

            pos -= 1

        order.insert(pos, g)

    for g in order:
        print("{names[g]}: {counts[g]}")

fn report_timeline(st: State, idx: Int) Unit:
    let iss = st.issues[idx].clone()
    var from_t = iss.created
    var cur = st.initial.clone()

    for ch in iss.history:
        let dur = ch.t - from_t
        print("{cur}: t={from_t}..{ch.t} ({dur})")
        from_t = ch.t
        cur = ch.state.clone()

    let dur = st.clock - from_t
    print("{cur}: t={from_t}..{st.clock} ({dur})")

fn cmd_report(st: State, rest: String) Unit:
    let sp = split_head(rest)
    let sub = sp.head.clone()
    let args = sp.rest.trim()

    if sub == "summary":
        if args != "":
            emit_err("usage: report summary|workload|labels|timeline")
            return

        report_summary(st)
    else if sub == "workload":
        if args != "":
            emit_err("usage: report summary|workload|labels|timeline")
            return

        report_workload(st)
    else if sub == "labels":
        report_labels(st, args)
    else if sub == "timeline":
        if args == "":
            emit_err("usage: report timeline ID")
            return

        let r0 = resolve_id(st, args)

        if r0.err != "":
            emit_err(r0.err)
            return

        report_timeline(st, r0.idx)
    else:
        emit_err("usage: report summary|workload|labels|timeline")

fn find_where(s: String) Int:
    let cs = s.chars()
    let n = cs.length()
    var k = 0

    while k + 5 <= n:
        var pre = k == 0
        if k > 0:
            pre = is_ws(cs[k - 1])

        var post = k + 5 == n
        if k + 5 < n:
            post = is_ws(cs[k + 5])
        if pre and post and join_range(cs, k, k + 5) == "where":
            return k

        k += 1

    return -1

fn bulk_one(var st: State, verb: String, acts: List[String], id: Int) Res:
    if verb == "move":
        return do_move(var st, id, acts[1].clone(), "")

    if verb == "assign":
        let kv = "assignee=" + acts[1]
        return do_edit(var st, id, [kv])

    if verb == "label":
        return do_label(var st, id, tail_of(acts))

    return do_edit(var st, id, tail_of(acts))

fn cmd_bulk(var st: State, rest: String) Unit:
    let usage = "usage: bulk ACTION... where QUERY"
    let wp = find_where(rest)

    if wp < 0:
        emit_err(usage)
        return

    let cs = rest.chars()
    let atext = join_range(cs, 0, wp)
    let qtext = join_range(cs, wp + 5, cs.length()).trim()

    if atext.trim() == "":
        emit_err(usage)
        return

    let tk = tokenize(atext)

    if not tk.ok:
        emit_err("unterminated quote")
        return

    let acts = tk.items.clone()
    let verb = acts[0].clone()
    let na = acts.length()

    if verb == "move":
        if na != 2:
            emit_err("usage: bulk move STATE where QUERY")
            return
    else if verb == "assign":
        if na != 2:
            emit_err("usage: bulk assign NAME where QUERY")
            return
    else if verb == "label":
        if na < 2:
            emit_err("usage: bulk label +label... where QUERY")
            return
    else if verb == "set":
        if na < 2:
            emit_err("usage: bulk set field=value... where QUERY")
            return
    else:
        emit_err("unknown bulk action '" + verb + "'")
        return

    let q = parse_query(st, qtext)

    if q.err != "":
        emit_err(q.err)
        return

    let idxs = select_issues(st, q, List[SortKey](), false, 0)
    var ids = List[Int]()
    for k in idxs:
        ids.append(st.issues[k].id)

    var nok = 0
    var nbad = 0

    for id in ids:
        let r = bulk_one(var st, verb, acts, id)

        if r.err != "":
            print("#{id} error: " + r.err)
            nbad += 1
        else:
            print(r.out)
            nok += 1

    print("bulk: {nok} ok, {nbad} failed")

fn cmd_report_entry(st: State, rest: String) Unit:
    cmd_report(st, rest)

fn dispatch(var st: State, cmd: String, rest: String) Unit:
    if cmd == "actor":
        cmd_actor(var st, rest)
    else if cmd == "today":
        cmd_today(var st, rest)
    else if cmd == "create":
        cmd_create(var st, rest)
    else if cmd == "edit":
        cmd_edit(var st, rest)
    else if cmd == "label":
        cmd_label(var st, rest)
    else if cmd == "assign":
        cmd_assign(var st, rest)
    else if cmd == "move":
        cmd_move(var st, rest)
    else if cmd == "comment":
        cmd_comment(var st, rest)
    else if cmd == "delete":
        cmd_delete(var st, rest)
    else if cmd == "show":
        cmd_show(st, rest)
    else if cmd == "list":
        cmd_list(st, rest)
    else if cmd == "view":
        cmd_view(var st, rest)
    else if cmd == "bulk":
        cmd_bulk(var st, rest)
    else if cmd == "log":
        cmd_log(st, rest)
    else if cmd == "report":
        cmd_report_entry(st, rest)
    else:
        print("error: unknown command '" + cmd + "'")

export fn main() Int:
    let raw = read_all(stdin()).get()
    let text = raw.decode_utf8().get("")
    let all_lines = text.lines()
    let n = all_lines.length()
    var st = State(
        has_workflow: false, initial: "", states: List[String](),
        finals: List[String](), transitions: List[Transition](), issues: List[Issue](),
        next_id: 1, clock: 0, actor: "system", today: "1970-01-01",
        log: List[LogEntry](), views: List[View]()
    )
    var i = 0

    while i < n:
        let line = all_lines[i].clone()
        i += 1

        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue

        print("> " + line.trim_end())

        let sp = split_head(line)

        if sp.head == "workflow":
            var block = List[String]()

            while i < n:
                let bl = all_lines[i].clone()
                i += 1
                if bl.trim() == "end":
                    break

                block.append(bl)

            cmd_workflow(var st, block)
        else:
            dispatch(var st, sp.head.clone(), sp.rest.clone())

    return 0
