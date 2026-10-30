import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

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
    hist_t: List[Int]
    hist_state: List[String]

type Trans:
    src: String
    dst: String
    guards: List[String]

type Entry:
    t: Int
    actor: String
    id: Int
    detail: String

type St:
    out: List[String]
    lines: List[String]
    pos: Int
    actor: String
    today: String
    clock: Int
    next_id: Int
    issues: List[Issue]
    journal: List[Entry]
    has_wf: Bool
    initial: String
    states: List[String]
    finals: List[String]
    trans: List[Trans]
    views: Map[String, String]

type Res:
    ok: Bool
    msg: String

type Cut:
    word: String
    rest: String

type Toks:
    items: List[String]
    ok: Bool

type Tok:
    kind: String
    field: String
    op: String
    value: String
    quoted: Bool

type QLex:
    toks: List[Tok]
    err: String

type QNode:
    kind: String
    field: String
    op: String
    alts: List[String]
    kids: List[QNode]

type QP:
    toks: List[Tok]
    pos: Int
    err: String
    strict: Bool

type QRes:
    node: QNode
    err: String

type QText:
    filt: String
    sort_text: String
    limit: Int
    err: String

type SKey:
    field: String
    desc: Bool

type SortP:
    keys: List[SKey]
    err: String

type Grp:
    key: String
    name: String
    count: Int
    pts: Int

type Split:
    found: Bool
    before: String
    after: String

type LabelCnt:
    name: String
    n: Int

# ---------- small helpers ----------

fn ok_res(msg: String) Res:
    return Res(ok: true, msg: msg)

fn err_res(msg: String) Res:
    return Res(ok: false, msg: msg)

fn str_i(n: Int) String:
    return n.to_string()

fn out_line(var st: St, s: String) Unit:
    st.out.append(s.clone())

fn out_err(var st: St, msg: String) Unit:
    st.out.append("error: " + msg)

fn res_out(var st: St, r: Res) Unit:
    if r.ok:
        out_line(var st, r.msg)
    else:
        out_err(var st, r.msg)

fn is_ws(c: String) Bool:
    return c == " " or c == "\t"

fn is_lower(c: String) Bool:
    return c >= "a" and c <= "z"

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn is_name_char(c: String) Bool:
    return is_lower(c) or is_digit(c) or c == "_" or c == "-"

fn valid_label(s: String) Bool:
    if s == "":
        return false

    for c in s.chars():
        if not is_name_char(c):
            return false
    return true

fn valid_state_name(s: String) Bool:
    if s == "" or not is_lower(s.chars() [0]):
        return false

    for c in s.chars():
        if not (is_lower(c) or is_digit(c) or c == "_"):
            return false
    return true

fn valid_view_name(s: String) Bool:
    if s == "" or not is_lower(s.chars() [0]):
        return false

    for c in s.chars():
        if not is_name_char(c):
            return false
    return true

# Integer rule: digits only, no leading zeros, at most 1000000. Returns -1 when invalid.
fn int_value(s: String) Int:
    if s == "" or s.length() > 7:
        return -1
    if s.length() > 1 and s.starts_with("0"):
        return -1

    for c in s.chars():
        if not is_digit(c):
            return -1

    let v = s.parse_int().get(-1)
    if v > 1000000:
        return -1

    return v

fn days_in(y: Int, m: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0:
            return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30

    return 31

fn valid_date(s: String) Bool:
    if s.length() != 10:
        return false

    let cs = s.chars()

    for i in 0..10:
        if i == 4 or i == 7:
            if cs[i] != "-":
                return false
        else if not is_digit(cs[i]):
            return false

    let y = s.slice(0, 4).get("").parse_int().get(0)
    let m = s.slice(5, 7).get("").parse_int().get(0)
    let d = s.slice(8, 10).get("").parse_int().get(0)
    if y < 1 or m < 1 or m > 12:
        return false

    return d >= 1 and d <= days_in(y, m)

fn rank(p: String) Int:
    if p == "low":
        return 0
    if p == "medium":
        return 1
    if p == "high":
        return 2
    if p == "critical":
        return 3

    return -1

fn parse_id(s: String) Int:
    var d = s.clone()
    if d.starts_with("#"):
        d = d.drop(1)
    if d == "":
        return 0

    for c in d.chars():
        if not is_digit(c):
            return 0
    while d.length() > 1 and d.starts_with("0"):
        d = d.drop(1)
    if d.length() > 9:
        return 999999999

    return d.parse_int().get(0)

fn has_s(o: Optional[String]) Bool:
    if let _ = o:
        return true

    return false

fn has_i(o: Optional[Int]) Bool:
    if let _ = o:
        return true

    return false

fn dash_s(o: Optional[String]) String:
    if let v = o:
        return v.clone()

    return "-"

fn dash_i(o: Optional[Int]) String:
    if let v = o:
        return v.to_string()

    return "-"

fn same_s(a: Optional[String], b: Optional[String]) Bool:
    if has_s(a) != has_s(b):
        return false

    return dash_s(a) == dash_s(b)

fn same_i(a: Optional[Int], b: Optional[Int]) Bool:
    if has_i(a) != has_i(b):
        return false

    return dash_i(a) == dash_i(b)

fn labels_text(labels: List[String], sep: String) String:
    if labels.length() == 0:
        return "-"

    return labels.join(sep)

fn cmp_int(x: Int, y: Int) Int:
    if x < y:
        return -1
    else if x > y:
        return 1

    return 0

fn cmp_str(x: String, y: String) Int:
    if x < y:
        return -1
    else if x > y:
        return 1

    return 0

fn cmp_opt_int(a: Optional[Int], b: Optional[Int]) Int:
    if not has_i(a) and not has_i(b):
        return 0
    if not has_i(a):
        return 1
    if not has_i(b):
        return -1

    return cmp_int(a.get(0), b.get(0))

fn cmp_opt_str(a: Optional[String], b: Optional[String]) Int:
    if not has_s(a) and not has_s(b):
        return 0
    if not has_s(a):
        return 1
    if not has_s(b):
        return -1

    return cmp_str(a.get("").lower(), b.get("").lower())

fn ord_ok(c: Int, op: String) Bool:
    if op == ":":
        return c == 0
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0
    if op == ">=":
        return c >= 0

    return c != 0

fn is_final(st: St, s: String) Bool:
    return st.finals.contains(s)

fn state_index(states: List[String], s: String) Int:
    for i in 0..states.length():
        if states[i] == s:
            return i
    return -1

fn find_index(st: St, id: Int) Int:
    for i in 0..st.issues.length():
        if st.issues[i].id == id:
            return i
    return -1

fn find_trans(st: St, src: String, dst: String) Int:
    for i in 0..st.trans.length():
        if st.trans[i].src == src and st.trans[i].dst == dst:
            return i
    return -1

fn add_log(var st: St, id: Int, detail: String) Unit:
    st.journal.append(
        Entry(
            t: st.clock, actor: st.actor.clone(), id: id, detail: detail.clone()
        )
    )

fn rest_items(items: List[String]) List[String]:
    var out = List[String]()
    for j in 1..items.length():
        out.append(items[j].clone())
    return out

fn single(s: String) List[String]:
    var out = List[String]()
    out.append(s)
    return out

fn join_from(w: List[String], j: Int) String:
    var parts = List[String]()
    for k in j..w.length():
        parts.append(w[k].clone())
    return parts.join(" ")

fn words(text: String) List[String]:
    return text.replace("\t", " ").split(" ").filter(fn w: w != "")

# Splits off the first whitespace separated word; rest starts after the following blanks.
fn cut(text: String) Cut:
    let cs = text.chars()
    var i = 0
    while i < cs.length() and is_ws(cs[i]):
        i += 1

    var word = ""

    while i < cs.length() and not is_ws(cs[i]):
        word += cs[i]
        i += 1

    while i < cs.length() and is_ws(cs[i]):
        i += 1
    return Cut(word: word, rest: text.drop(i))

# Token style: whitespace separates tokens, double quotes group text inside a token.
fn tokenize(text: String) Toks:
    var items = List[String]()
    var cur = ""
    var started = false
    var quoted = false
    let cs = text.chars()
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if quoted:
            if c == "\"":
                quoted = false
            else if (
                c == "\\"
                and i + 1 < cs.length()
                and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
            ):
                cur += cs[i + 1]
                i += 1
            else:
                cur += c
        else if c == "\"":
            quoted = true
            started = true
        else if is_ws(c):
            if started:
                items.append(cur.clone())
                cur = ""
                started = false
        else:
            cur += c
            started = true

        i += 1

    if quoted:
        return Toks(items: items, ok: false)

    if started:
        items.append(cur.clone())
    return Toks(items: items, ok: true)

# ---------- issue fields ----------

# Parses a comma list of labels into acc (sorted, unique). Returns an error or "".
fn read_labels(value: String, var acc: List[String]) String:
    for raw in value.split(","):
        let l = raw.lower()
        if not valid_label(l):
            return "bad label '" + l + "'"

        if not acc.contains(l):
            acc.append(l.clone())

    acc.sort()
    return ""

fn add_label(var labels: List[String], l: String) Unit:
    if not labels.contains(l):
        labels.append(l.clone())

fn remove_label(var labels: List[String], l: String) Unit:
    let p = labels.index_of(l).get(-1)
    if p >= 0:
        labels.remove(p)

# Applies one field=value token to an issue. Returns an error or "".
fn set_field(var iss: Issue, tok: String) String:
    let ps = tok.split("=", 2)
    if ps.length() < 2 or ps[0] == "":
        return "expected field=value, got '" + tok + "'"

    let field = ps[0].clone()
    let value = ps[1].clone()
    if field == "state":
        return "use move to change state"

    if field == "title":
        if value.trim() == "":
            return "empty title"

        iss.title = value.clone()
        return ""

    if field == "priority":
        if rank(value) < 0:
            return "bad priority '" + value + "'"

        iss.priority = value.clone()
        return ""

    if field == "assignee":
        if value == "none":
            iss.assignee = none
            return ""

        if value.trim() == "":
            return "empty assignee"

        iss.assignee = value.clone()
        return ""

    if field == "reporter":
        if value == "none":
            iss.reporter = none
            return ""

        if value.trim() == "":
            return "empty reporter"

        iss.reporter = value.clone()
        return ""

    if field == "points":
        if value == "none":
            iss.points = none
            return ""

        let n = int_value(value)
        if n < 0:
            return "bad points '" + value + "'"

        iss.points = n
        return ""

    if field == "due":
        if value == "none":
            iss.due = none
            return ""

        if not valid_date(value):
            return "bad date '" + value + "'"

        iss.due = value.clone()
        return ""

    if field == "labels":
        if value == "none":
            iss.labels = List[String]()
            return ""

        var labs = List[String]()
        let e = read_labels(value, var labs)
        if e != "":
            return e

        iss.labels = labs
        return ""

    return "unknown field '" + field + "'"

# Lists the fields that differ, in the fixed log order.
fn diff(a: Issue, b: Issue) List[String]:
    var out = List[String]()
    if a.title != b.title:
        out.append("title: " + a.title + " -> " + b.title)
    if a.priority != b.priority:
        out.append("priority: " + a.priority + " -> " + b.priority)
    if not same_s(a.assignee, b.assignee):
        out.append("assignee: " + dash_s(a.assignee) + " -> " + dash_s(b.assignee))
    if not same_i(a.points, b.points):
        out.append("points: " + dash_i(a.points) + " -> " + dash_i(b.points))
    if not same_s(a.due, b.due):
        out.append("due: " + dash_s(a.due) + " -> " + dash_s(b.due))
    if a.labels.join(",") != b.labels.join(","):
        out.append(
            "labels: " + labels_text(a.labels, ",") + " -> " + labels_text(
                b.labels, ","
            )
        )
    if not same_s(a.reporter, b.reporter):
        out.append("reporter: " + dash_s(a.reporter) + " -> " + dash_s(b.reporter))
    return out

fn issue_line(iss: Issue) String:
    return (
        "#"
        + str_i(iss.id)
        + " | "
        + iss.state
        + " | "
        + iss.priority
        + " | "
        + dash_s(iss.assignee)
        + " | "
        + dash_i(iss.points)
        + " | "
        + dash_s(iss.due)
        + " | "
        + labels_text(iss.labels, ",")
        + " | "
        + iss.title
    )

fn count_line(n: Int) String:
    if n == 1:
        return "(1 issue)"

    return "(" + str_i(n) + " issues)"

# ---------- commands: workflow, actor, today ----------

fn add_state(var states: List[String], name: String) Unit:
    if not states.contains(name):
        states.append(name.clone())

fn guard_name_ok(g: String) Bool:
    return (
        g == "assignee"
        or g == "points"
        or g == "due"
        or g == "labels"
        or g == "reporter"
    )

fn cmd_workflow(var st: St) Unit:
    var err = ""
    if st.next_id > 1:
        err = "workflow: cannot redefine after issues were created"

    var init = ""
    var has_init = false
    var states = List[String]()
    var finals = List[String]()
    var trans = List[Trans]()

    while st.pos < st.lines.length():
        let line = st.lines[st.pos].trim()
        st.pos += 1
        if line == "end":
            break
        if line == "" or line.starts_with("#") or err != "":
            continue

        if line.starts_with("initial:"):
            let name = line.drop(8).trim()

            if not valid_state_name(name):
                err = "workflow: bad state name '" + name + "'"
            else if has_init:
                err = "workflow: initial state defined twice"
            else:
                init = name.clone()
                has_init = true
                add_state(var states, name)
        else if line.starts_with("final:"):
            for raw in line.drop(6).split(","):
                let name = raw.trim()

                if not valid_state_name(name):
                    err = "workflow: bad state name '" + name + "'"
                    break

                add_state(var states, name)
                if not finals.contains(name):
                    finals.append(name.clone())
        else if line.contains("->"):
            let parts = line.split("->", 2)
            let src = parts[0].trim()

            if not valid_state_name(src):
                err = "workflow: bad state name '" + src + "'"
            else:
                add_state(var states, src)

                for ent in parts[1].split(","):
                    if err != "":
                        break

                    let w = words(ent)
                    var dst = ""
                    var gs = List[String]()

                    if w.length() == 1:
                        dst = w[0].clone()
                    else if w.length() == 3 and w[1] == "requires":
                        dst = w[0].clone()
                        for g in w[2].split("+"):
                            gs.append(g.clone())
                    else:
                        err = "workflow: bad line '" + line + "'"
                        break

                    if not valid_state_name(dst):
                        err = "workflow: bad state name '" + dst + "'"
                        break

                    for g in gs:
                        if not guard_name_ok(g):
                            err = "workflow: bad guard field '" + g + "'"
                            break

                    if err != "":
                        break

                    add_state(var states, dst)
                    trans.append(Trans(src: src.clone(), dst: dst.clone(), guards: gs))
        else:
            err = "workflow: bad line '" + line + "'"

    if err == "" and not has_init:
        err = "workflow: initial state missing"

    if err == "":
        for t in trans:
            if finals.contains(t.src):
                err = "workflow: '" + t.src + "' is final and cannot have transitions"
                break

    if err != "":
        out_err(var st, err)
        return

    st.has_wf = true
    st.initial = init
    st.states = states
    st.finals = finals
    st.trans = trans
    out_line(
        var st,
        "workflow ok: " + str_i(st.states.length()) + " states, " + str_i(
            st.trans.length()
        ) + " transitions"
    )

fn cmd_actor(var st: St, args: String) Unit:
    let w = words(args)

    if w.length() != 1:
        out_err(var st, "usage: actor NAME")
        return

    st.actor = w[0].clone()
    out_line(var st, "actor is " + w[0])

fn cmd_today(var st: St, args: String) Unit:
    let w = words(args)

    if w.length() != 1:
        out_err(var st, "usage: today DATE")
        return

    if not valid_date(w[0]):
        out_err(var st, "bad date '" + w[0] + "'")
        return

    st.today = w[0].clone()
    out_line(var st, "today is " + w[0])

# ---------- create / edit / label / assign / move / comment / delete ----------

fn commit(var st: St, idx: Int, base: Issue, var cand: Issue) Res:
    let d = diff(base, cand)
    if d.length() == 0:
        return ok_res("#" + str_i(cand.id) + " unchanged")

    st.clock += 1
    cand.updated = st.clock
    for e in d:
        add_log(var st, cand.id, e)

    let msg = "updated #" + str_i(cand.id)
    st.issues[idx] = cand.clone()
    return ok_res(msg)

fn do_edit(var st: St, id: Int, fields: List[String]) Res:
    let idx = find_index(st, id)
    if idx < 0:
        return err_res("no such issue #" + str_i(id))

    let base = st.issues[idx].clone()
    if is_final(st, base.state):
        return err_res("#" + str_i(id) + " is in final state '" + base.state + "'")
    if fields.length() == 0:
        return err_res("usage: edit ID field=value...")

    var cand = base.clone()

    for f in fields:
        let e = set_field(var cand, f)
        if e != "":
            return err_res(e)

    return commit(var st, idx, base, var cand)

fn do_label(var st: St, id: Int, ops: List[String]) Res:
    let idx = find_index(st, id)
    if idx < 0:
        return err_res("no such issue #" + str_i(id))

    let base = st.issues[idx].clone()
    if is_final(st, base.state):
        return err_res("#" + str_i(id) + " is in final state '" + base.state + "'")

    var labels = base.labels.clone()

    for op in ops:
        var name = op.clone()
        var adding = true

        if op.starts_with("+"):
            name = op.drop(1)
        else if op.starts_with("-"):
            adding = false
            name = op.drop(1)

        let l = name.lower()
        if not valid_label(l):
            return err_res("bad label '" + l + "'")

        if adding:
            add_label(var labels, l)
        else:
            remove_label(var labels, l)

    labels.sort()

    var cand = base.clone()
    cand.labels = labels
    return commit(var st, idx, base, var cand)

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

fn do_move(var st: St, id: Int, target: String, comment: String) Res:
    let idx = find_index(st, id)
    if idx < 0:
        return err_res("no such issue #" + str_i(id))

    let cur = st.issues[idx].state.clone()
    if is_final(st, cur):
        return err_res("#" + str_i(id) + " is in final state '" + cur + "'")
    if not st.states.contains(target):
        return err_res("unknown state '" + target + "'")
    if cur == target:
        return err_res("already in state '" + cur + "'")

    let ti = find_trans(st, cur, target)
    if ti < 0:
        return err_res("transition '" + cur + " -> " + target + "' not allowed")

    var missing = List[String]()
    for g in st.trans[ti].guards:
        if guard_unmet(st.issues[idx], g):
            missing.append(g.clone())
    if missing.length() > 0:
        return err_res(
            "cannot move #" + str_i(
                id
            ) + " to " + target + ": missing " + missing.join(", ")
        )

    var cand = st.issues[idx].clone()
    st.clock += 1
    cand.state = target.clone()
    cand.updated = st.clock
    cand.hist_t.append(st.clock)
    cand.hist_state.append(target.clone())
    add_log(var st, id, "state: " + cur + " -> " + target)

    if comment != "":
        cand.comments.append(
            Comment(
                t: st.clock, actor: st.actor.clone(), text: comment.clone()
            )
        )
        add_log(var st, id, "comment: " + comment)

    st.issues[idx] = cand
    return ok_res("moved #" + str_i(id) + ": " + cur + " -> " + target)

fn cmd_create(var st: St, args: String) Unit:
    if not st.has_wf:
        out_err(var st, "no workflow defined")
        return

    let tk = tokenize(args)

    if not tk.ok:
        out_err(var st, "unterminated quote")
        return

    if tk.items.length() == 0:
        out_err(var st, "usage: create TITLE [field=value...]")
        return

    let title = tk.items[0].clone()

    if title.trim() == "":
        out_err(var st, "empty title")
        return

    let id = st.next_id
    let base = Issue(
        id: id, title: title.clone(), state: st.initial.clone(), priority: "medium",
        assignee: none, reporter: st.actor.clone(), points: none, due: none,
        labels: List[String](), comments: List[Comment](), created: 0, updated: 0,
        hist_t: List[Int](), hist_state: List[String]()
    )
    var cand = base.clone()

    for j in 1..tk.items.length():
        let e = set_field(var cand, tk.items[j])

        if e != "":
            out_err(var st, e)
            return

    st.clock += 1
    cand.created = st.clock
    cand.updated = st.clock
    cand.hist_t.append(st.clock)
    cand.hist_state.append(st.initial.clone())
    st.next_id += 1
    add_log(var st, id, "created \"" + title + "\"")
    for d in diff(base, cand):
        add_log(var st, id, d)
    st.issues.append(cand)
    out_line(var st, "created #" + str_i(id))

fn cmd_edit(var st: St, args: String) Unit:
    let tk = tokenize(args)

    if not tk.ok:
        out_err(var st, "unterminated quote")
        return

    if tk.items.length() == 0:
        out_err(var st, "usage: edit ID field=value...")
        return

    let id = parse_id(tk.items[0])

    if id == 0:
        out_err(var st, "bad issue id '" + tk.items[0] + "'")
        return

    let r = do_edit(var st, id, rest_items(tk.items))
    res_out(var st, r)

fn cmd_assign(var st: St, args: String) Unit:
    let tk = tokenize(args)

    if not tk.ok:
        out_err(var st, "unterminated quote")
        return

    if tk.items.length() != 2:
        out_err(var st, "usage: assign ID NAME")
        return

    let id = parse_id(tk.items[0])

    if id == 0:
        out_err(var st, "bad issue id '" + tk.items[0] + "'")
        return

    let r = do_edit(var st, id, single("assignee=" + tk.items[1]))
    res_out(var st, r)

fn cmd_label(var st: St, args: String) Unit:
    let tk = tokenize(args)

    if not tk.ok:
        out_err(var st, "unterminated quote")
        return

    if tk.items.length() < 2:
        out_err(var st, "usage: label ID +label -label...")
        return

    let id = parse_id(tk.items[0])

    if id == 0:
        out_err(var st, "bad issue id '" + tk.items[0] + "'")
        return

    let r = do_label(var st, id, rest_items(tk.items))
    res_out(var st, r)

fn cmd_move(var st: St, args: String) Unit:
    let c1 = cut(args)
    let c2 = cut(c1.rest)

    if c1.word == "" or c2.word == "":
        out_err(var st, "usage: move ID STATE [comment...]")
        return

    let id = parse_id(c1.word)

    if id == 0:
        out_err(var st, "bad issue id '" + c1.word + "'")
        return

    let r = do_move(var st, id, c2.word, c2.rest)
    res_out(var st, r)

fn cmd_comment(var st: St, args: String) Unit:
    let c1 = cut(args)
    let text = c1.rest.clone()

    if c1.word == "" or text == "":
        out_err(var st, "usage: comment ID TEXT")
        return

    let id = parse_id(c1.word)

    if id == 0:
        out_err(var st, "bad issue id '" + c1.word + "'")
        return

    let idx = find_index(st, id)

    if idx < 0:
        out_err(var st, "no such issue #" + str_i(id))
        return

    st.clock += 1

    var iss = st.issues[idx].clone()
    iss.comments.append(
        Comment(t: st.clock, actor: st.actor.clone(), text: text.clone())
    )
    iss.updated = st.clock
    st.issues[idx] = iss
    add_log(var st, id, "comment: " + text)
    out_line(var st, "commented #" + str_i(id))

fn cmd_delete(var st: St, args: String) Unit:
    let w = words(args)

    if w.length() != 1:
        out_err(var st, "usage: delete ID")
        return

    let id = parse_id(w[0])

    if id == 0:
        out_err(var st, "bad issue id '" + w[0] + "'")
        return

    let idx = find_index(st, id)

    if idx < 0:
        out_err(var st, "no such issue #" + str_i(id))
        return

    st.clock += 1
    st.issues.remove(idx)
    add_log(var st, id, "deleted")
    out_line(var st, "deleted #" + str_i(id))

fn cmd_show(var st: St, args: String) Unit:
    let w = words(args)

    if w.length() != 1:
        out_err(var st, "usage: show ID")
        return

    let id = parse_id(w[0])

    if id == 0:
        out_err(var st, "bad issue id '" + w[0] + "'")
        return

    let idx = find_index(st, id)

    if idx < 0:
        out_err(var st, "no such issue #" + str_i(id))
        return

    let iss = st.issues[idx].clone()
    out_line(var st, "#" + str_i(iss.id) + " " + iss.title)
    out_line(var st, "  state: " + iss.state)
    out_line(var st, "  priority: " + iss.priority)
    out_line(var st, "  assignee: " + dash_s(iss.assignee))
    out_line(var st, "  points: " + dash_i(iss.points))
    out_line(var st, "  due: " + dash_s(iss.due))
    out_line(var st, "  labels: " + labels_text(iss.labels, ", "))
    out_line(var st, "  reporter: " + dash_s(iss.reporter))
    out_line(
        var st,
        "  created: t=" + str_i(iss.created) + ", updated: t=" + str_i(
            iss.updated
        )
    )
    out_line(var st, "  comments: " + str_i(iss.comments.length()))
    for c in iss.comments:
        out_line(var st, "    [t=" + str_i(c.t) + " " + c.actor + "] " + c.text)

# ---------- query language ----------

# Splits "FILTER [sort FIELDS] [limit N]" textually.
fn last_ws_index(s: String) Int:
    let cs = s.chars()
    var i = cs.length() - 1

    while i >= 0:
        if is_ws(cs[i]):
            return i

        i -= 1

    return -1

fn find_sort(s: String) Int:
    let cs = s.chars()
    for i in 0..cs.length():
        if (
            i + 4 < cs.length()
            and s.slice(i, i + 4).get("") == "sort"
            and (i == 0 or is_ws(cs[i - 1]))
            and is_ws(cs[i + 4])
        ):
            return i
    return -1

fn split_query(text: String) QText:
    var body = text.trim().clone()
    var limit = -1
    let wsi = last_ws_index(body)

    if wsi >= 0:
        let arg = body.drop(wsi + 1)
        let head = body.slice(0, wsi).get("").trim_end()

        if head == "limit" or head.ends_with(" limit") or head.ends_with("\tlimit"):
            let n = int_value(arg)
            if n < 0:
                return QText(
                    filt: "", sort_text: "", limit: -1, err: "bad limit '" + arg + "'"
                )

            limit = n
            body = head.slice(0, head.length() - 5).get("").trim_end()

    let si = find_sort(body)
    if si >= 0:
        return QText(
            filt: body.slice(0, si).get("").trim_end(), sort_text: body.drop(si + 4),
            limit: limit, err: ""
        )

    return QText(filt: body, sort_text: "", limit: limit, err: "")

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

fn parse_sort(text: String) SortP:
    var keys = List[SKey]()

    for w in words(text.replace(",", " ")):
        var name = w.clone()
        var desc = false

        if w.starts_with("-"):
            desc = true
            name = w.drop(1)

        if not sort_field_ok(name):
            return SortP(keys: List[SKey](), err: "bad sort field '" + name + "'")

        keys.append(SKey(field: name, desc: desc))

    return SortP(keys: keys, err: "")

fn op_at(cs: List[String], j: Int) String:
    if j >= cs.length():
        return ""

    let c = cs[j].clone()

    let n = if j + 1 < cs.length(): cs[j + 1].clone() else: ""

    if c == "!" and n == "=":
        return "!="
    if (c == "<" or c == ">") and n == "=":
        return c + "="
    if c == ":" or c == "~" or c == "<" or c == ">":
        return c

    return ""

fn lex_filter(text: String) QLex:
    let cs = text.chars()
    var toks = List[Tok]()
    var i = 0

    while i < cs.length():
        let c = cs[i].clone()

        if is_ws(c):
            i += 1
        else if c == "(" or c == ")":
            toks.append(
                Tok(
                    kind: c.clone(), field: "", op: "", value: c.clone(), quoted: false
                )
            )
            i += 1
        else:
            var j = i
            while j < cs.length() and (is_lower(cs[j]) or cs[j] == "_"):
                j += 1

            let field = text.slice(i, j).get("")
            let op = op_at(cs, j)

            if field != "" and op != "":
                j += op.length()

                if j < cs.length() and cs[j] == "\"":
                    j += 1

                    var v = ""
                    var closed = false

                    while j < cs.length() and not closed:
                        if cs[j] == "\"":
                            closed = true
                        else if (
                            cs[j] == "\\"
                            and j + 1 < cs.length()
                            and (
                                cs[j + 1] == "\""
                                or cs[j + 1] == "\\"
                            )
                        ):
                            v += cs[j + 1]
                            j += 1
                        else:
                            v += cs[j]

                        j += 1

                    if not closed:
                        return QLex(toks: toks, err: "query: unterminated quote")

                    toks.append(
                        Tok(
                            kind: "TERM", field: field.clone(), op: op.clone(),
                            value: v, quoted: true
                        )
                    )
                else:
                    var v = ""

                    while (
                        j < cs.length()
                        and not is_ws(cs[j])
                        and cs[j] != "("
                        and cs[j] != ")"
                    ):
                        v += cs[j]
                        j += 1

                    toks.append(
                        Tok(
                            kind: "TERM", field: field.clone(), op: op.clone(),
                            value: v, quoted: false
                        )
                    )

                i = j
            else:
                while (
                    j < cs.length()
                    and not is_ws(cs[j])
                    and cs[j] != "("
                    and cs[j] != ")"
                ):
                    j += 1

                let w = text.slice(i, j).get("")
                var kind = "WORD"
                if w == "AND" or w == "OR" or w == "NOT":
                    kind = w.clone()
                toks.append(
                    Tok(
                        kind: kind, field: "", op: "", value: w.clone(), quoted: false
                    )
                )
                i = j

    return QLex(toks: toks, err: "")

fn all_node() QNode:
    return QNode(
        kind: "all", field: "", op: "", alts: List[String](), kids: List[QNode]()
    )

fn fail_node(var p: QP, msg: String) QNode:
    if p.err == "":
        p.err = msg
    return all_node()

fn bin_node(kind: String, a: QNode, b: QNode) QNode:
    var kids = List[QNode]()
    kids.append(a)
    kids.append(b)
    return QNode(kind: kind, field: "", op: "", alts: List[String](), kids: kids)

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

fn op_allowed(field: String, op: String) Bool:
    if (
        field == "id"
        or field == "created"
        or field == "updated"
        or field == "points"
        or field == "priority"
        or field == "due"
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
        field == "title"
        or field == "assignee"
        or field == "reporter"
        or field == "label"
        or field == "labels"
    ):
        return op == ":" or op == "!=" or op == "~"
    if field == "text":
        return op == "~"
    if field == "state":
        return op == ":" or op == "!="

    return op == ":"

fn check_alt(st: St, field: String, op: String, a: String, strict: Bool) Bool:
    if field == "id" or field == "created" or field == "updated":
        return int_value(a) >= 0

    if field == "points":
        if a == "none":
            return op == ":" or op == "!="

        return int_value(a) >= 0

    if field == "priority":
        return rank(a) >= 0

    if field == "due":
        if a == "none":
            return op == ":" or op == "!="

        return valid_date(a)

    if field == "state":
        return st.states.contains(a)
    if field == "is":
        return a == "open" or a == "final" or a == "overdue" or a == "unassigned"
    if field == "has":
        return (
            a == "assignee"
            or a == "due"
            or a == "points"
            or a == "labels"
            or a == "comments"
            or a == "reporter"
        )
    if field == "view":
        return (not strict) or st.views.contains(a)

    return true

fn term_node(st: St, var p: QP, tk: Tok) QNode:
    if not known_field(tk.field):
        return fail_node(var p, "query: unknown field '" + tk.field + "'")
    if not op_allowed(tk.field, tk.op):
        return fail_node(
            var p, "query: bad operator '" + tk.op + "' for field '" + tk.field + "'"
        )

    var alts = List[String]()
    let ordered = tk.op == "<" or tk.op == "<=" or tk.op == ">" or tk.op == ">="

    if tk.quoted or ordered or tk.field == "view":
        alts.append(tk.value.clone())
    else:
        for a in tk.value.split("|"):
            alts.append(a.clone())

    if tk.field == "label" or tk.field == "labels":
        var low = List[String]()
        for a in alts:
            low.append(a.lower())
        alts = low

    for a in alts:
        if not check_alt(st, tk.field, tk.op, a, p.strict):
            if tk.field == "view":
                return fail_node(var p, "query: unknown view '" + a + "'")

            return fail_node(
                var p, "query: bad value '" + a + "' for field '" + tk.field + "'"
            )

    return QNode(
        kind: "term", field: tk.field.clone(), op: tk.op.clone(), alts: alts,
        kids: List[QNode]()
    )

fn parse_primary(st: St, var p: QP) QNode:
    if p.err != "":
        return all_node()
    if p.pos >= p.toks.length():
        return fail_node(var p, "query: unexpected end of query")

    let tk = p.toks[p.pos].clone()

    if tk.kind == "(":
        p.pos += 1

        let inner = parse_or(st, var p)
        if p.err != "":
            return inner
        if p.pos >= p.toks.length():
            return fail_node(var p, "query: unexpected end of query")
        if p.toks[p.pos].kind != ")":
            return fail_node(
                var p, "query: unexpected token '" + p.toks[p.pos].value + "'"
            )

        p.pos += 1
        return inner

    if tk.kind == "TERM":
        p.pos += 1
        return term_node(st, var p, tk)

    return fail_node(var p, "query: unexpected token '" + tk.value + "'")

fn parse_not(st: St, var p: QP) QNode:
    if p.err == "" and p.pos < p.toks.length() and p.toks[p.pos].kind == "NOT":
        p.pos += 1

        let kid = parse_not(st, var p)
        var kids = List[QNode]()
        kids.append(kid)
        return QNode(kind: "not", field: "", op: "", alts: List[String](), kids: kids)

    return parse_primary(st, var p)

fn parse_and(st: St, var p: QP) QNode:
    var node = parse_not(st, var p)

    while p.err == "" and p.pos < p.toks.length():
        let k = p.toks[p.pos].kind.clone()

        if k == "AND":
            p.pos += 1
        else if k != "TERM" and k != "(" and k != "NOT":
            break

        let rhs = parse_not(st, var p)
        node = bin_node("and", node.clone(), rhs)

    return node

fn parse_or(st: St, var p: QP) QNode:
    var node = parse_and(st, var p)

    while p.err == "" and p.pos < p.toks.length() and p.toks[p.pos].kind == "OR":
        p.pos += 1

        let rhs = parse_and(st, var p)
        node = bin_node("or", node.clone(), rhs)

    return node

fn parse_filter(st: St, text: String, strict: Bool) QRes:
    let lx = lex_filter(text)
    if lx.err != "":
        return QRes(node: all_node(), err: lx.err.clone())
    if lx.toks.length() == 0:
        return QRes(node: all_node(), err: "")

    var p = QP(toks: lx.toks.clone(), pos: 0, err: "", strict: strict)
    let node = parse_or(st, var p)
    if p.err == "" and p.pos < p.toks.length():
        return QRes(
            node: all_node(),
            err: "query: unexpected token '" + p.toks[p.pos].value + "'"
        )

    return QRes(node: node, err: p.err.clone())

fn collect_views(n: QNode, var acc: List[String]) Unit:
    if n.kind == "term" and n.field == "view":
        acc.append(n.alts[0].clone())
    for k in n.kids:
        collect_views(k, var acc)

fn str_match(v: String, op: String, a: String) Bool:
    if op == "~":
        return v.lower().contains(a.lower())

    return v.lower() == a.lower()

fn opt_match(o: Optional[String], op: String, a: String) Bool:
    if not has_s(o):
        return op == ":" and a == "none"

    return str_match(dash_s(o), op, a)

fn eval_view(st: St, name: String, iss: Issue) Bool:
    let qt = split_query(st.views.get(name).get(""))
    let pf = parse_filter(st, qt.filt, false)
    return eval_node(st, pf.node, iss)

fn match_alt(st: St, field: String, op: String, a: String, iss: Issue) Bool:
    if field == "id":
        return ord_ok(cmp_int(iss.id, int_value(a)), op)
    if field == "created":
        return ord_ok(cmp_int(iss.created, int_value(a)), op)
    if field == "updated":
        return ord_ok(cmp_int(iss.updated, int_value(a)), op)

    if field == "points":
        if a == "none":
            return not has_i(iss.points)
        if not has_i(iss.points):
            return false

        return ord_ok(cmp_int(iss.points.get(0), int_value(a)), op)

    if field == "priority":
        return ord_ok(cmp_int(rank(iss.priority), rank(a)), op)

    if field == "due":
        if a == "none":
            return not has_s(iss.due)
        if not has_s(iss.due):
            return false

        return ord_ok(cmp_str(iss.due.get(""), a), op)

    if field == "title":
        return str_match(iss.title, op, a)
    if field == "assignee":
        return opt_match(iss.assignee, op, a)
    if field == "reporter":
        return opt_match(iss.reporter, op, a)

    if field == "text":
        if iss.title.lower().contains(a.lower()):
            return true

        for c in iss.comments:
            if c.text.lower().contains(a.lower()):
                return true
        return false

    if field == "state":
        return iss.state == a

    if field == "label" or field == "labels":
        if op == "~":
            for l in iss.labels:
                if l.contains(a):
                    return true
            return false

        if a == "none":
            return iss.labels.length() == 0

        return iss.labels.contains(a)

    if field == "is":
        if a == "open":
            return not is_final(st, iss.state)
        if a == "final":
            return is_final(st, iss.state)
        if a == "overdue":
            return (
                not is_final(st, iss.state)
                and has_s(iss.due)
                and iss.due.get("") < st.today
            )

        return not has_s(iss.assignee)

    if field == "has":
        if a == "assignee":
            return has_s(iss.assignee)
        if a == "due":
            return has_s(iss.due)
        if a == "points":
            return has_i(iss.points)
        if a == "labels":
            return iss.labels.length() > 0
        if a == "comments":
            return iss.comments.length() > 0

        return has_s(iss.reporter)

    if field == "view":
        return eval_view(st, a, iss)

    return false

fn eval_node(st: St, n: QNode, iss: Issue) Bool:
    if n.kind == "and":
        return eval_node(st, n.kids[0], iss) and eval_node(st, n.kids[1], iss)
    if n.kind == "or":
        return eval_node(st, n.kids[0], iss) or eval_node(st, n.kids[1], iss)
    if n.kind == "not":
        return not eval_node(st, n.kids[0], iss)

    if n.kind == "term":
        if n.op == "!=":
            for a in n.alts:
                if match_alt(st, n.field, ":", a, iss):
                    return false
            return true

        for a in n.alts:
            if match_alt(st, n.field, n.op, a, iss):
                return true
        return false

    return true

fn cmp_field(a: Issue, b: Issue, field: String, states: List[String]) Int:
    if field == "id":
        return cmp_int(a.id, b.id)
    if field == "created":
        return cmp_int(a.created, b.created)
    if field == "updated":
        return cmp_int(a.updated, b.updated)
    if field == "priority":
        return cmp_int(rank(a.priority), rank(b.priority))
    if field == "points":
        return cmp_opt_int(a.points, b.points)
    if field == "state":
        return cmp_int(state_index(states, a.state), state_index(states, b.state))
    if field == "title":
        return cmp_str(a.title.lower(), b.title.lower())
    if field == "assignee":
        return cmp_opt_str(a.assignee, b.assignee)
    if field == "reporter":
        return cmp_opt_str(a.reporter, b.reporter)
    if field == "due":
        return cmp_opt_str(a.due, b.due)

    return 0

fn cmp_issues(a: Issue, b: Issue, keys: List[SKey], states: List[String]) Int:
    for k in keys:
        let r = cmp_field(a, b, k.field, states)

        if r != 0:
            if k.desc:
                return 0 - r

            return r

    return cmp_int(a.id, b.id)

fn run_list(var st: St, node: QNode, keys: List[SKey], limit: Int) Unit:
    var matched = List[Issue]()
    for iss in st.issues:
        if eval_node(st, node, iss):
            matched.append(iss.clone())

    let states = st.states.clone()
    let kk = keys.clone()
    matched.sort(fn a, b: cmp_issues(a, b, kk, states))

    var shown = 0

    for iss in matched:
        if limit >= 0 and shown >= limit:
            break

        out_line(var st, issue_line(iss))
        shown += 1

    out_line(var st, count_line(shown))

fn cmd_list(var st: St, args: String) Unit:
    let qt = split_query(args)

    if qt.err != "":
        out_err(var st, qt.err)
        return

    let pf = parse_filter(st, qt.filt, true)

    if pf.err != "":
        out_err(var st, pf.err)
        return

    let sp = parse_sort(qt.sort_text)

    if sp.err != "":
        out_err(var st, sp.err)
        return

    run_list(var st, pf.node, sp.keys, qt.limit)

# ---------- views ----------

fn sorted_view_names(st: St) List[String]:
    var names = st.views.keys()
    names.sort()
    return names

fn reaches(st: St, name: String, start: List[String]) Bool:
    var stack = List[String]()
    for s in start:
        stack.append(s.clone())

    var seen = List[String]()

    while stack.length() > 0:
        let r = stack[stack.length() - 1].clone()
        stack.remove(stack.length() - 1)
        if r == name:
            return true
        if seen.contains(r):
            continue

        seen.append(r.clone())

        if st.views.contains(r):
            let qt = split_query(st.views.get(r).get(""))
            let pf = parse_filter(st, qt.filt, false)
            var more = List[String]()
            collect_views(pf.node, var more)
            for m in more:
                stack.append(m.clone())

    return false

fn cmd_view_save(var st: St, rest: String) Unit:
    let c = cut(rest)

    if c.word == "":
        out_err(var st, "usage: view save NAME QUERY")
        return

    if not valid_view_name(c.word):
        out_err(var st, "bad view name '" + c.word + "'")
        return

    let qt = split_query(c.rest)

    if qt.err != "":
        out_err(var st, qt.err)
        return

    let pf = parse_filter(st, qt.filt, true)

    if pf.err != "":
        out_err(var st, pf.err)
        return

    let sp = parse_sort(qt.sort_text)

    if sp.err != "":
        out_err(var st, sp.err)
        return

    var direct = List[String]()
    collect_views(pf.node, var direct)

    if reaches(st, c.word, direct):
        out_err(var st, "view '" + c.word + "' would reference itself")
        return

    st.views[c.word.clone()] = c.rest.clone()
    out_line(var st, "saved view " + c.word)

fn cmd_view_run(var st: St, rest: String) Unit:
    let c = cut(rest)

    if c.word == "":
        out_err(var st, "usage: view run NAME [sort FIELDS] [limit N]")
        return

    let name = c.word.clone()

    if not st.views.contains(name):
        out_err(var st, "unknown view '" + name + "'")
        return

    let w = words(c.rest)
    var j = 0
    var ex_sort = List[String]()
    var has_sort = false
    var ex_limit = -1

    while j < w.length():
        if w[j] == "sort" and not has_sort:
            has_sort = true
            j += 1

            while j < w.length() and w[j] != "limit":
                ex_sort.append(w[j].clone())
                j += 1
        else if w[j] == "limit" and ex_limit < 0:
            if j + 1 >= w.length():
                out_err(var st, "usage: view run NAME [sort FIELDS] [limit N]")
                return

            let n = int_value(w[j + 1])

            if n < 0:
                out_err(var st, "bad limit '" + w[j + 1] + "'")
                return

            ex_limit = n
            j += 2
        else:
            out_err(var st, "unexpected '" + join_from(w, j) + "'")
            return

    let qt = split_query(st.views.get(name).get(""))
    var sort_text = qt.sort_text.clone()
    if has_sort:
        sort_text = ex_sort.join(" ")

    var limit = qt.limit + 0
    if ex_limit >= 0:
        limit = ex_limit

    let pf = parse_filter(st, qt.filt, true)

    if pf.err != "":
        out_err(var st, pf.err)
        return

    let sp = parse_sort(sort_text)

    if sp.err != "":
        out_err(var st, sp.err)
        return

    run_list(var st, pf.node, sp.keys, limit)

fn cmd_view_list(var st: St) Unit:
    let names = sorted_view_names(st)

    if names.length() == 0:
        out_line(var st, "(no views)")
        return

    for n in names:
        out_line(var st, n + ": " + st.views.get(n).get(""))

fn cmd_view_show(var st: St, rest: String) Unit:
    let w = words(rest)

    if w.length() != 1:
        out_err(var st, "usage: view show NAME")
        return

    if not st.views.contains(w[0]):
        out_err(var st, "unknown view '" + w[0] + "'")
        return

    out_line(var st, w[0] + ": " + st.views.get(w[0]).get(""))

fn cmd_view_delete(var st: St, rest: String) Unit:
    let w = words(rest)

    if w.length() != 1:
        out_err(var st, "usage: view delete NAME")
        return

    let name = w[0].clone()

    if not st.views.contains(name):
        out_err(var st, "unknown view '" + name + "'")
        return

    for v in sorted_view_names(st):
        if v == name:
            continue

        let pf = parse_filter(st, split_query(st.views.get(v).get("")).filt, false)
        var direct = List[String]()
        collect_views(pf.node, var direct)

        if reaches(st, name, direct):
            out_err(var st, "view '" + name + "' is used by '" + v + "'")
            return

    st.views.remove(name.clone())
    out_line(var st, "deleted view " + name)

fn cmd_view(var st: St, args: String) Unit:
    let c = cut(args)

    if c.word == "save":
        cmd_view_save(var st, c.rest)
    else if c.word == "run":
        cmd_view_run(var st, c.rest)
    else if c.word == "list" and c.rest == "":
        cmd_view_list(var st)
    else if c.word == "show":
        cmd_view_show(var st, c.rest)
    else if c.word == "delete":
        cmd_view_delete(var st, c.rest)
    else:
        out_err(var st, "usage: view save|run|list|show|delete")

# ---------- bulk ----------

# Splits the bulk text at the first word `where`.
fn split_where(args: String) Split:
    let total = args.length()
    var rem = args.clone()
    var c = cut(rem)

    while c.word != "":
        if c.word == "where":
            let start = total - rem.trim_start().length()
            return Split(
                found: true, before: args.slice(0, start).get(""), after: c.rest.clone()
            )

        rem = c.rest.clone()
        c = cut(rem)

    return Split(found: false, before: "", after: "")

fn bulk_shape(items: List[String]) String:
    let act = items[0]

    if act == "move":
        if items.length() != 2:
            return "usage: bulk move STATE where QUERY"

        return ""

    if act == "assign":
        if items.length() != 2:
            return "usage: bulk assign NAME where QUERY"

        return ""

    if act == "label":
        if items.length() < 2:
            return "usage: bulk label +label... where QUERY"

        return ""

    if act == "set":
        if items.length() < 2:
            return "usage: bulk set field=value... where QUERY"

        return ""

    return "unknown bulk action '" + act + "'"

fn bulk_apply(var st: St, items: List[String], id: Int) Res:
    let act = items[0].clone()
    if act == "move":
        return do_move(var st, id, items[1], "")
    if act == "assign":
        return do_edit(var st, id, single("assignee=" + items[1]))
    if act == "label":
        return do_label(var st, id, rest_items(items))

    return do_edit(var st, id, rest_items(items))

fn cmd_bulk(var st: St, args: String) Unit:
    let sp = split_where(args)

    if not sp.found or sp.before.trim() == "":
        out_err(var st, "usage: bulk ACTION... where QUERY")
        return

    let tk = tokenize(sp.before)

    if not tk.ok:
        out_err(var st, "unterminated quote")
        return

    let shape = bulk_shape(tk.items)

    if shape != "":
        out_err(var st, shape)
        return

    let pf = parse_filter(st, sp.after, true)

    if pf.err != "":
        out_err(var st, pf.err)
        return

    var ids = List[Int]()
    for iss in st.issues:
        if eval_node(st, pf.node, iss):
            ids.append(iss.id)

    var good_n = 0
    var bad_n = 0

    for id in ids:
        let r = bulk_apply(var st, tk.items, id)

        if r.ok:
            good_n += 1
            out_line(var st, r.msg)
        else:
            bad_n += 1
            out_line(var st, "#" + str_i(id) + " error: " + r.msg)

    out_line(var st, "bulk: " + str_i(good_n) + " ok, " + str_i(bad_n) + " failed")

# ---------- log and reports ----------

fn cmd_log(var st: St, args: String) Unit:
    let w = words(args)
    var want = -1
    var j = 0

    if w.length() > 0 and w[0] != "tail":
        let id = parse_id(w[0])

        if id == 0:
            out_err(var st, "bad issue id '" + w[0] + "'")
            return

        if id >= st.next_id:
            out_err(var st, "no such issue #" + str_i(id))
            return

        want = id
        j = 1

    var tail = -1

    if j < w.length():
        if w.length() - j != 2 or w[j] != "tail":
            out_err(var st, "usage: log [ID] [tail N]")
            return

        let n = int_value(w[j + 1])

        if n < 0:
            out_err(var st, "bad tail '" + w[j + 1] + "'")
            return

        tail = n

    var sel = List[Entry]()
    for e in st.journal:
        if want < 0 or e.id == want:
            sel.append(e.clone())

    var start = 0
    if tail >= 0 and tail < sel.length():
        start = sel.length() - tail

    var printed = 0

    for k in 0..sel.length():
        if k < start:
            continue

        let e = sel[k]
        out_line(
            var st,
            "t=" + str_i(e.t) + " " + e.actor + " #" + str_i(
                e.id
            ) + " " + e.detail
        )
        printed += 1

    if printed == 0:
        out_line(var st, "(no log entries)")

fn count_state(st: St, s: String) Int:
    var n = 0
    for iss in st.issues:
        if iss.state == s:
            n += 1
    return n

fn count_priority(st: St, p: String) Int:
    var n = 0
    for iss in st.issues:
        if iss.priority == p:
            n += 1
    return n

fn cmd_report_summary(var st: St) Unit:
    let total = st.issues.length()
    var n_open = 0
    var unassigned = 0
    var overdue = 0
    var open_pts = 0

    for iss in st.issues:
        if is_final(st, iss.state):
            continue

        n_open += 1
        if not has_s(iss.assignee):
            unassigned += 1
        if has_s(iss.due) and iss.due.get("") < st.today:
            overdue += 1
        if has_i(iss.points):
            open_pts += iss.points.get(0)

    out_line(
        var st,
        "issues: " + str_i(total) + " (open " + str_i(
            n_open
        ) + ", final " + str_i(total - n_open) + ")"
    )
    out_line(var st, "by state:")
    for s in st.states.clone():
        out_line(var st, "  " + s + ": " + str_i(count_state(st, s)))
    out_line(var st, "by priority:")
    for p in ["critical", "high", "medium", "low"]:
        out_line(var st, "  " + p + ": " + str_i(count_priority(st, p)))
    out_line(var st, "unassigned: " + str_i(unassigned))
    out_line(var st, "overdue: " + str_i(overdue))
    out_line(var st, "open points: " + str_i(open_pts))

fn cmp_grp(a: Grp, b: Grp) Int:
    if a.pts != b.pts:
        return cmp_int(b.pts, a.pts)
    if a.count != b.count:
        return cmp_int(b.count, a.count)

    return cmp_str(a.key, b.key)

fn cmd_report_workload(var st: St) Unit:
    var groups = List[Grp]()
    var any_open = false
    var un_count = 0
    var un_pts = 0

    for iss in st.issues:
        if is_final(st, iss.state):
            continue

        any_open = true

        let p = if has_i(iss.points): iss.points.get(0) else: 0

        if not has_s(iss.assignee):
            un_count += 1
            un_pts += p
            continue

        let key = iss.assignee.get("").lower()
        var found = -1
        for g in 0..groups.length():
            if groups[g].key == key:
                found = g

        if found < 0:
            groups.append(
                Grp(
                    key: key.clone(), name: iss.assignee.get(""), count: 0, pts: 0
                )
            )
            found = groups.length() - 1

        var grp = groups[found].clone()
        grp.count += 1
        grp.pts += p
        groups[found] = grp

    if not any_open:
        out_line(var st, "(no open issues)")
        return

    groups.sort(fn a, b: cmp_grp(a, b))

    for g in groups:
        let noun = if g.count == 1: " issue" else: " issues"

        out_line(
            var st,
            g.name + ": " + str_i(g.count) + noun + ", " + str_i(
                g.pts
            ) + " points"
        )

    if un_count > 0:
        let noun = if un_count == 1: " issue" else: " issues"

        out_line(
            var st,
            "unassigned: " + str_i(un_count) + noun + ", " + str_i(
                un_pts
            ) + " points"
        )

fn cmd_report_labels(var st: St, rest: String) Unit:
    let pf = parse_filter(st, rest, true)

    if pf.err != "":
        out_err(var st, pf.err)
        return

    var counts = List[LabelCnt]()

    for iss in st.issues:
        if not eval_node(st, pf.node, iss):
            continue

        for l in iss.labels:
            var found = -1
            for k in 0..counts.length():
                if counts[k].name == l:
                    found = k

            if found < 0:
                counts.append(LabelCnt(name: l.clone(), n: 1))
            else:
                var lc = counts[found].clone()
                lc.n += 1
                counts[found] = lc

    if counts.length() == 0:
        out_line(var st, "(no labels)")
        return

    counts.sort(fn a, b: cmp_label(a, b))
    for lc in counts:
        out_line(var st, lc.name + ": " + str_i(lc.n))

fn cmp_label(a: LabelCnt, b: LabelCnt) Int:
    if a.n != b.n:
        return cmp_int(b.n, a.n)

    return cmp_str(a.name, b.name)

fn cmd_report_timeline(var st: St, rest: String) Unit:
    let w = words(rest)

    if w.length() != 1:
        out_err(var st, "usage: report timeline ID")
        return

    let id = parse_id(w[0])

    if id == 0:
        out_err(var st, "bad issue id '" + w[0] + "'")
        return

    let idx = find_index(st, id)

    if idx < 0:
        out_err(var st, "no such issue #" + str_i(id))
        return

    let iss = st.issues[idx].clone()

    for k in 0..iss.hist_t.length():
        let start = iss.hist_t[k]
        var stop = st.clock + 0
        if k + 1 < iss.hist_t.length():
            stop = iss.hist_t[k + 1]
        out_line(
            var st,
            iss.hist_state[k] + ": t=" + str_i(start) + ".." + str_i(
                stop
            ) + " (" + str_i(stop - start) + ")"
        )

fn cmd_report(var st: St, args: String) Unit:
    let c = cut(args)

    if c.word == "summary" and c.rest == "":
        cmd_report_summary(var st)
    else if c.word == "workload" and c.rest == "":
        cmd_report_workload(var st)
    else if c.word == "labels":
        cmd_report_labels(var st, c.rest)
    else if c.word == "timeline":
        cmd_report_timeline(var st, c.rest)
    else:
        out_err(var st, "usage: report summary|workload|labels|timeline")

# ---------- dispatch and main ----------

fn run_line(var st: St, line: String) Unit:
    let c = cut(line)
    let cmd = c.word.clone()
    let args = c.rest.clone()

    if cmd == "workflow":
        cmd_workflow(var st)
    else if cmd == "actor":
        cmd_actor(var st, args)
    else if cmd == "today":
        cmd_today(var st, args)
    else if cmd == "create":
        cmd_create(var st, args)
    else if cmd == "edit":
        cmd_edit(var st, args)
    else if cmd == "label":
        cmd_label(var st, args)
    else if cmd == "assign":
        cmd_assign(var st, args)
    else if cmd == "move":
        cmd_move(var st, args)
    else if cmd == "comment":
        cmd_comment(var st, args)
    else if cmd == "delete":
        cmd_delete(var st, args)
    else if cmd == "show":
        cmd_show(var st, args)
    else if cmd == "list":
        cmd_list(var st, args)
    else if cmd == "view":
        cmd_view(var st, args)
    else if cmd == "bulk":
        cmd_bulk(var st, args)
    else if cmd == "log":
        cmd_log(var st, args)
    else if cmd == "report":
        cmd_report(var st, args)
    else:
        out_err(var st, "unknown command '" + cmd + "'")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var st = St(
        out: List[String](), lines: lines, pos: 0, actor: "system", today: "1970-01-01",
        clock: 0, next_id: 1, issues: List[Issue](), journal: List[Entry](),
        has_wf: false, initial: "", states: List[String](), finals: List[String](),
        trans: List[Trans](), views: Map[String, String]()
    )

    while st.pos < st.lines.length():
        let raw = st.lines[st.pos].clone()
        st.pos += 1

        let line = raw.trim_end()
        let t = line.trim_start()
        if t == "" or t.starts_with("#"):
            continue

        out_line(var st, "> " + line)
        run_line(var st, line)

    if st.out.length() > 0:
        stdout().write(st.out.join("\n") + "\n").get()
    return 0
