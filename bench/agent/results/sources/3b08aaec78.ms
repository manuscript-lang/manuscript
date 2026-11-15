import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Comment:
	t: Int
	actor: String
	text: String

type Issue:
	id: Int
	title: String
	state: String
	priority: Int = 1
	assignee: String = ""
	points: Int = -1
	due: String = ""
	labels: List[String] = List[String]()
	reporter: String = ""
	comments: List[Comment] = List[Comment]()
	created: Int = 0
	updated: Int = 0

type LogEntry:
	t: Int
	actor: String
	id: Int
	detail: String
	to_state: String

type Trans:
	src: String
	dst: String
	guards: List[String]

type State:
	t: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	next_id: Int = 1
	issues: List[Issue] = List[Issue]()
	log: List[LogEntry] = List[LogEntry]()
	states: List[String] = List[String]()
	initial: String = ""
	finals: List[String] = List[String]()
	trans: List[Trans] = List[Trans]()
	has_wf: Bool = false
	views: Map[String, String] = Map[String, String]()

type WF:
	states: List[String] = List[String]()
	finals: List[String] = List[String]()
	trans: List[Trans] = List[Trans]()
	initial: String = ""
	has_initial: Bool = false
	ntrans: Int = 0

type Fields:
	has_title: Bool = false
	title: String = ""
	has_priority: Bool = false
	priority: Int = 1
	has_assignee: Bool = false
	assignee: String = ""
	has_points: Bool = false
	points: Int = -1
	has_due: Bool = false
	due: String = ""
	has_labels: Bool = false
	labels: List[String] = List[String]()
	has_reporter: Bool = false
	reporter: String = ""

type QTok:
	kind: Int
	text: String = ""
	field: String = ""
	op: String = ""
	value: String = ""
	quoted: Bool = false

type Node:
	kind: Int
	a: Int = -1
	b: Int = -1
	field: String = ""
	op: String = ""
	vals: List[String] = List[String]()
	nums: List[Int] = List[Int]()

type Ctx:
	nodes: List[Node] = List[Node]()
	refs: List[String] = List[String]()

type Parser:
	toks: List[QTok]
	pos: Int = 0

type QParts:
	filter: String = ""
	has_sort: Bool = false
	sort: String = ""
	has_limit: Bool = false
	limit: Int = 0

type SortKey:
	field: String
	desc: Bool

// ---------- helpers ----------

fn is_ws(c: String) Bool: c == " " or c == "\t"

fn join_range(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b:
		out = "{out}{cs[i]}"
		i += 1
	return out

fn split_rest(text: String, n: Int) List[String]:
	cs := text.chars()
	len := cs.length()
	var out = List[String]()
	var i = 0
	var k = 0
	while k < n:
		while i < len and is_ws(cs[i]):
			i += 1
		var w = ""
		while i < len and not is_ws(cs[i]):
			w = "{w}{cs[i]}"
			i += 1
		out.append(w)
		k += 1
	while i < len and is_ws(cs[i]):
		i += 1
	out.append(join_range(cs, i, len))
	return out

fn find_word(cs: List[String], w: String) Int:
	len := cs.length()
	var i = 0
	while i < len:
		if is_ws(cs[i]):
			i += 1
			continue
		start := i
		var cur = ""
		while i < len and not is_ws(cs[i]):
			cur = "{cur}{cs[i]}"
			i += 1
		if cur == w: return start
	return -1

fn dash(s: String) String:
	if s.is_empty(): return "-"
	return s.clone()

fn pts(p: Int) String:
	if p < 0: return "-"
	return "{p}"

fn pri_names() List[String]: ["low", "medium", "high", "critical"]

fn pri_name(p: Int) String: pri_names().get(p, "medium")

fn pri_rank(s: String) Int:
	names := pri_names()
	for i in 0..4:
		if names[i] == s: return i
	return -1

fn digit(c: String) Int:
	return "0123456789".index_of(c).get(-1)

// integer rule: -1 when invalid
fn parse_num(s: String) Int:
	if s.is_empty(): return -1
	cs := s.chars()
	if cs.length() > 7: return -1
	if cs.length() > 1 and cs[0] == "0": return -1
	var v = 0
	for c in cs:
		d := digit(c)
		if d < 0: return -1
		v = v * 10 + d
	if v > 1000000: return -1
	return v

fn is_leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false
	for i in 0..10:
		if i == 4 or i == 7:
			if cs[i] != "-": return false
		else:
			if digit(cs[i]) < 0: return false
	y := parse_digits(cs, 0, 4)
	m := parse_digits(cs, 5, 7)
	d := parse_digits(cs, 8, 10)
	if y < 1: return false
	if m < 1 or m > 12: return false
	var dim = 31
	if m == 4 or m == 6 or m == 9 or m == 11: dim = 30
	if m == 2:
		dim = 28
		if is_leap(y): dim = 29
	return d >= 1 and d <= dim

fn parse_digits(cs: List[String], a: Int, b: Int) Int:
	var v = 0
	for i in a..b:
		v = v * 10 + digit(cs[i])
	return v

fn valid_label(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

fn valid_state_name(s: String) Bool:
	if s.is_empty(): return false
	cs := s.chars()
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"
		if not ok: return false
	return true

fn valid_view_name(s: String) Bool:
	if s.is_empty(): return false
	cs := s.chars()
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

fn tokenize(text: String) List[String]!:
	cs := text.chars()
	len := cs.length()
	var out = List[String]()
	var cur = ""
	var in_tok = false
	var q = false
	var i = 0
	while i < len:
		c := cs[i]
		if q:
			if c == "\\" and i + 1 < len and (cs[i + 1] == "\"" or cs[i + 1] == "\\"):
				cur = "{cur}{cs[i + 1]}"
				i += 2
				continue
			if c == "\"":
				q = false
			else:
				cur = "{cur}{c}"
		else:
			if is_ws(c):
				if in_tok:
					out.append(cur.clone())
					cur = ""
					in_tok = false
			else if c == "\"":
				q = true
				in_tok = true
			else:
				cur = "{cur}{c}"
				in_tok = true
		i += 1
	if q: return error(Error("unterminated quote"))
	if in_tok: out.append(cur.clone())
	return ok(out)

fn is_final(st: State, s: String) Bool:
	return st.finals.contains(s)

fn find_idx(st: State, id: Int) Int:
	for i in 0..st.issues.length():
		if st.issues[i].id == id: return i
	return -1

fn state_idx(st: State, s: String) Int:
	for i in 0..st.states.length():
		if st.states[i] == s: return i
	return -1

fn parse_id_num(arg: String) Int!:
	var s = arg.clone()
	if s.starts_with("#"):
		s = join_range(s.chars(), 1, s.chars().length())
	if s.is_empty(): return error(Error("bad issue id '{arg}'"))
	var v = 0
	for c in s.chars():
		d := digit(c)
		if d < 0: return error(Error("bad issue id '{arg}'"))
		if v < 1000000000000: v = v * 10 + d
	if v < 1: return error(Error("bad issue id '{arg}'"))
	return ok(v)

fn parse_id(st: State, arg: String) Int!:
	v := parse_id_num(arg)?
	if find_idx(st, v) < 0: return error(Error("no such issue #{v}"))
	return ok(v)

fn add_log(var st: State, id: Int, detail: String, to_state: String) Unit:
	st.log.append(LogEntry(st.t, st.actor.clone(), id, detail, to_state.clone()))

fn show_res(r: String!) Unit:
	if v := r:
		print(v)
	else:
		print("error: {r.err().message}")

// ---------- fields ----------

fn parse_fields(toks: List[String], start: Int) Fields!:
	var f = Fields()
	var i = start
	while i < toks.length():
		tok := toks[i]
		i += 1
		cs := tok.chars()
		var eq = -1
		for k in 0..cs.length():
			if cs[k] == "=":
				eq = k
				break
		if eq <= 0: return error(Error("expected field=value, got '{tok}'"))
		name := join_range(tok.chars(), 0, eq)
		val := join_range(cs, eq + 1, cs.length())
		if name == "state": return error(Error("use move to change state"))
		if name == "title":
			if val.trim().is_empty(): return error(Error("empty title"))
			f.has_title = true
			f.title = val.clone()
		else if name == "priority":
			r := pri_rank(val)
			if r < 0: return error(Error("bad priority '{val}'"))
			f.has_priority = true
			f.priority = r
		else if name == "assignee":
			f.has_assignee = true
			if val == "none":
				f.assignee = ""
			else:
				if val.is_empty(): return error(Error("empty assignee"))
				f.assignee = val.clone()
		else if name == "reporter":
			f.has_reporter = true
			if val == "none":
				f.reporter = ""
			else:
				if val.is_empty(): return error(Error("empty reporter"))
				f.reporter = val.clone()
		else if name == "points":
			f.has_points = true
			if val == "none":
				f.points = -1
			else:
				n := parse_num(val)
				if n < 0: return error(Error("bad points '{val}'"))
				f.points = n
		else if name == "due":
			f.has_due = true
			if val == "none":
				f.due = ""
			else:
				if not valid_date(val): return error(Error("bad date '{val}'"))
				f.due = val.clone()
		else if name == "labels":
			f.has_labels = true
			if val == "none":
				f.labels = List[String]()
			else:
				f.labels = parse_label_list(val)?
		else:
			return error(Error("unknown field '{name}'"))
	return ok(f)

fn norm_labels(xs: List[String]) List[String]:
	var out = List[String]()
	for x in xs:
		if not out.contains(x): out.append(x.clone())
	out.sort()
	return out

fn parse_label_list(val: String) List[String]!:
	var out = List[String]()
	for part in val.split(","):
		l := part.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		out.append(l)
	return ok(norm_labels(out))

fn change_details(iss: Issue, f: Fields) List[String]:
	var out = List[String]()
	if f.has_title and f.title != iss.title:
		out.append("title: {iss.title} -> {f.title}")
	if f.has_priority and f.priority != iss.priority:
		out.append("priority: {pri_name(iss.priority)} -> {pri_name(f.priority)}")
	if f.has_assignee and f.assignee != iss.assignee:
		out.append("assignee: {dash(iss.assignee)} -> {dash(f.assignee)}")
	if f.has_points and f.points != iss.points:
		out.append("points: {pts(iss.points)} -> {pts(f.points)}")
	if f.has_due and f.due != iss.due:
		out.append("due: {dash(iss.due)} -> {dash(f.due)}")
	if f.has_labels and f.labels.join(",") != iss.labels.join(","):
		out.append("labels: {dash(iss.labels.join(","))} -> {dash(f.labels.join(","))}")
	if f.has_reporter and f.reporter != iss.reporter:
		out.append("reporter: {dash(iss.reporter)} -> {dash(f.reporter)}")
	return out

fn apply_fields(var iss: Issue, f: Fields) Unit:
	if f.has_title: iss.title = f.title.clone()
	if f.has_priority: iss.priority = f.priority
	if f.has_assignee: iss.assignee = f.assignee.clone()
	if f.has_points: iss.points = f.points
	if f.has_due: iss.due = f.due.clone()
	if f.has_labels: iss.labels = f.labels.clone()
	if f.has_reporter: iss.reporter = f.reporter.clone()

fn finish_edit(var st: State, id: Int, f: Fields) String!:
	idx := find_idx(st, id)
	details := change_details(st.issues[idx], f)
	if details.length() == 0: return ok("#{id} unchanged")
	st.t += 1
	apply_fields(var st.issues[idx], f)
	st.issues[idx].updated = st.t
	for d in details:
		add_log(var st, id, d, "")
	return ok("updated #{id}")

fn edit_core(var st: State, id: Int, toks: List[String], start: Int) String!:
	idx := find_idx(st, id)
	if idx < 0: return error(Error("no such issue #{id}"))
	cur := st.issues[idx].state.clone()
	if is_final(st, cur): return error(Error("#{id} is in final state '{cur}'"))
	f := parse_fields(toks, start)?
	if toks.length() <= start: return error(Error("usage: edit ID field=value..."))
	return finish_edit(var st, id, f)

fn label_core(var st: State, id: Int, ops: List[String], start: Int) String!:
	idx := find_idx(st, id)
	if idx < 0: return error(Error("no such issue #{id}"))
	cur := st.issues[idx].state.clone()
	if is_final(st, cur): return error(Error("#{id} is in final state '{cur}'"))
	var labels = st.issues[idx].labels.clone()
	var i = start
	while i < ops.length():
		op := ops[i]
		i += 1
		var l = op.lower()
		var remove = false
		if l.starts_with("+"):
			l = join_range(l.chars(), 1, l.chars().length())
		else if l.starts_with("-"):
			remove = true
			l = join_range(l.chars(), 1, l.chars().length())
		if not valid_label(l): return error(Error("bad label '{l}'"))
		if remove:
			var nl = List[String]()
			for x in labels:
				if x != l: nl.append(x.clone())
			labels = nl
		else:
			if not labels.contains(l): labels.append(l)
	var f = Fields()
	f.has_labels = true
	f.labels = norm_labels(labels)
	return finish_edit(var st, id, f)

fn move_core(var st: State, id: Int, to: String, comment: String) String!:
	idx := find_idx(st, id)
	if idx < 0: return error(Error("no such issue #{id}"))
	cur := st.issues[idx].state.clone()
	if is_final(st, cur): return error(Error("#{id} is in final state '{cur}'"))
	if not st.states.contains(to): return error(Error("unknown state '{to}'"))
	if to == cur: return error(Error("already in state '{to}'"))
	var found = -1
	for i in 0..st.trans.length():
		if st.trans[i].src == cur and st.trans[i].dst == to:
			found = i
			break
	if found < 0: return error(Error("transition '{cur} -> {to}' not allowed"))
	var missing = List[String]()
	for g in st.trans[found].guards:
		iss := st.issues[idx]
		var unmet = false
		if g == "assignee": unmet = iss.assignee.is_empty()
		if g == "points": unmet = iss.points < 0
		if g == "due": unmet = iss.due.is_empty()
		if g == "labels": unmet = iss.labels.length() == 0
		if g == "reporter": unmet = iss.reporter.is_empty()
		if unmet: missing.append(g.clone())
	if missing.length() > 0:
		return error(Error("cannot move #{id} to {to}: missing {missing.join(", ")}"))
	st.t += 1
	st.issues[idx].state = to.clone()
	st.issues[idx].updated = st.t
	add_log(var st, id, "state: {cur} -> {to}", to)
	if not comment.is_empty():
		st.issues[idx].comments.append(Comment(st.t, st.actor.clone(), comment.clone()))
		add_log(var st, id, "comment: {comment}", "")
	return ok("moved #{id}: {cur} -> {to}")

// ---------- workflow ----------

fn find_arrow(cs: List[String]) Int:
	for i in 0..cs.length():
		if cs[i] == "-" and i + 1 < cs.length() and cs[i + 1] == ">": return i
	return -1

fn wf_add(var wf: WF, name: String) Unit:
	if not wf.states.contains(name): wf.states.append(name.clone())

fn wf_line(var wf: WF, l: String) String:
	if l.starts_with("initial:"):
		name := join_range(l.chars(), 8, l.chars().length()).trim()
		if not valid_state_name(name): return "workflow: bad state name '{name}'"
		if wf.has_initial: return "workflow: initial state defined twice"
		wf.has_initial = true
		wf.initial = name.clone()
		wf_add(var wf, name)
		return ""
	if l.starts_with("final:"):
		body := join_range(l.chars(), 6, l.chars().length())
		for part in body.split(","):
			name := part.trim()
			if not valid_state_name(name): return "workflow: bad state name '{name}'"
			wf_add(var wf, name)
			if not wf.finals.contains(name): wf.finals.append(name)
		return ""
	cs := l.chars()
	a := find_arrow(cs)
	if a < 0: return "workflow: bad line '{l}'"
	src := join_range(cs, 0, a).trim()
	rest := join_range(cs, a + 2, cs.length())
	if not valid_state_name(src): return "workflow: bad state name '{src}'"
	wf_add(var wf, src)
	for entry in rest.split(","):
		words := entry.fields()
		if words.length() != 1 and not (words.length() == 3 and words[1] == "requires"):
			return "workflow: bad line '{l}'"
		dst := words[0]
		if not valid_state_name(dst): return "workflow: bad state name '{dst}'"
		var guards = List[String]()
		if words.length() == 3:
			for g in words[2].split("+"):
				okg := g == "assignee" or g == "points" or g == "due" or g == "labels" or g == "reporter"
				if not okg: return "workflow: bad guard field '{g}'"
				guards.append(g.clone())
		wf_add(var wf, dst)
		wf.trans.append(Trans(src.clone(), dst.clone(), guards))
		wf.ntrans += 1
	return ""

fn cmd_workflow(var st: State, block: List[String]) Unit:
	if st.next_id > 1:
		print("error: workflow: cannot redefine after issues were created")
		return
	var wf = WF()
	var err = ""
	for raw in block:
		l := raw.trim()
		if l.is_empty() or l.starts_with("#"): continue
		if not err.is_empty(): continue
		err = wf_line(var wf, l)
	if err.is_empty() and not wf.has_initial: err = "workflow: initial state missing"
	if err.is_empty():
		for t in wf.trans:
			if wf.finals.contains(t.src):
				err = "workflow: '{t.src}' is final and cannot have transitions"
				break
	if not err.is_empty():
		print("error: {err}")
		return
	st.states = wf.states.clone()
	st.finals = wf.finals.clone()
	st.trans = wf.trans.clone()
	st.initial = wf.initial.clone()
	st.has_wf = true
	print("workflow ok: {wf.states.length()} states, {wf.ntrans} transitions")

// ---------- query ----------

fn qerr(msg: String) Error: Error("query: {msg}")

fn is_field_char(c: String) Bool: (c >= "a" and c <= "z") or c == "_"

fn lex(text: String) List[QTok]!:
	cs := text.chars()
	n := cs.length()
	var out = List[QTok]()
	var i = 0
	while i < n:
		c := cs[i]
		if is_ws(c):
			i += 1
			continue
		if c == "(":
			out.append(QTok(2, "("))
			i += 1
			continue
		if c == ")":
			out.append(QTok(3, ")"))
			i += 1
			continue
		var j = i
		while j < n and is_field_char(cs[j]):
			j += 1
		var op = ""
		if j > i and j < n:
			c2 := cs[j]
			var nxt = ""
			if j + 1 < n: nxt = cs[j + 1].clone()
			if c2 == ":": op = ":"
			else if c2 == "~": op = "~"
			else if c2 == "!" and nxt == "=": op = "!="
			else if c2 == "<":
				if nxt == "=":
					op = "<="
				else:
					op = "<"
			else if c2 == ">":
				if nxt == "=":
					op = ">="
				else:
					op = ">"
		if not op.is_empty():
			k := j + op.length()
			var v = ""
			var quoted = false
			var m = k
			if k < n and cs[k] == "\"":
				quoted = true
				m = k + 1
				var closed = false
				while m < n:
					ch := cs[m]
					if ch == "\\" and m + 1 < n and (cs[m + 1] == "\"" or cs[m + 1] == "\\"):
						v = "{v}{cs[m + 1]}"
						m += 2
						continue
					if ch == "\"":
						closed = true
						m += 1
						break
					v = "{v}{ch}"
					m += 1
				if not closed: return error(qerr("unterminated quote"))
			else:
				while m < n and not is_ws(cs[m]) and cs[m] != "(" and cs[m] != ")":
					v = "{v}{cs[m]}"
					m += 1
			out.append(QTok(0, join_range(cs, i, m), join_range(cs, i, j), op, v, quoted))
			i = m
			continue
		var m = i
		while m < n and not is_ws(cs[m]) and cs[m] != "(" and cs[m] != ")":
			m += 1
		out.append(QTok(1, join_range(cs, i, m)))
		i = m
	return ok(out)

fn ops_for(f: String) List[String]:
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "priority" or f == "due":
		return [":", "!=", "<", "<=", ">", ">="]
	if f == "title" or f == "assignee" or f == "reporter" or f == "label" or f == "labels":
		return [":", "!=", "~"]
	if f == "text": return ["~"]
	if f == "state": return [":", "!="]
	return [":"]

fn known_field(f: String) Bool:
	known := ["id", "created", "updated", "points", "title", "assignee", "reporter", "text", "state", "priority", "due", "label", "labels", "is", "has", "view"]
	return known.contains(f)

fn bad_value(v: String, f: String) Error:
	return qerr("bad value '{v}' for field '{f}'")

fn add_node(var cx: Ctx, n: Node) Int:
	cx.nodes.append(n)
	return cx.nodes.length() - 1

fn make_term(st: State, var cx: Ctx, t: QTok) Int!:
	f := t.field
	op := t.op
	v := t.value
	if not known_field(f): return error(qerr("unknown field '{f}'"))
	if not ops_for(f).contains(op): return error(qerr("bad operator '{op}' for field '{f}'"))
	if f == "view":
		q := st.views.get(v)
		if q.is_none(): return error(qerr("unknown view '{v}'"))
		cx.refs.append(v.clone())
		parts := analyze(q.get(""))?
		return compile(st, parts.filter, var cx)
	ordering := op == "<" or op == "<=" or op == ">" or op == ">="
	var alts = List[String]()
	if ordering or t.quoted:
		alts.append(v.clone())
	else:
		alts = v.clone().split("|")
	var nums = List[Int]()
	for a in alts:
		if f == "id" or f == "created" or f == "updated" or f == "points":
			if f == "points" and a == "none" and not ordering:
				nums.append(-1)
			else:
				n := parse_num(a)
				if n < 0: return error(bad_value(a, f))
				nums.append(n)
		else if f == "priority":
			r := pri_rank(a)
			if r < 0: return error(bad_value(a, f))
			nums.append(r)
		else if f == "state":
			if not st.states.contains(a): return error(bad_value(a, f))
		else if f == "due":
			if ordering:
				if not valid_date(a): return error(bad_value(a, f))
			else:
				if a != "none" and not valid_date(a): return error(bad_value(a, f))
		else if f == "is":
			if not (a == "open" or a == "final" or a == "overdue" or a == "unassigned"): return error(bad_value(a, f))
		else if f == "has":
			okh := a == "assignee" or a == "due" or a == "points" or a == "labels" or a == "comments" or a == "reporter"
			if not okh: return error(bad_value(a, f))
	return ok(add_node(var cx, Node(0, -1, -1, f.clone(), op.clone(), alts, nums)))

fn peek_word(p: Parser, w: String) Bool:
	if p.pos >= p.toks.length(): return false
	return p.toks[p.pos].kind == 1 and p.toks[p.pos].text == w

fn unexpected(p: Parser) Error:
	if p.pos >= p.toks.length(): return qerr("unexpected end of query")
	return qerr("unexpected token '{p.toks[p.pos].text}'")

fn parse_primary(st: State, var cx: Ctx, var p: Parser) Int!:
	if p.pos >= p.toks.length(): return error(unexpected(p))
	kind := p.toks[p.pos].kind
	if kind == 0:
		t := p.toks[p.pos].clone()
		p.pos += 1
		return make_term(st, var cx, t)
	if kind == 2:
		p.pos += 1
		inner := parse_or(st, var cx, var p)?
		if p.pos >= p.toks.length() or p.toks[p.pos].kind != 3: return error(unexpected(p))
		p.pos += 1
		return ok(inner)
	return error(unexpected(p))

fn parse_not(st: State, var cx: Ctx, var p: Parser) Int!:
	if peek_word(p, "NOT"):
		p.pos += 1
		child := parse_not(st, var cx, var p)?
		return ok(add_node(var cx, Node(3, child, -1)))
	return parse_primary(st, var cx, var p)

fn starts_unary(p: Parser) Bool:
	if p.pos >= p.toks.length(): return false
	k := p.toks[p.pos].kind
	return k == 0 or k == 2 or peek_word(p, "NOT")

fn parse_and(st: State, var cx: Ctx, var p: Parser) Int!:
	var left = parse_not(st, var cx, var p)?
	while true:
		if peek_word(p, "AND"):
			p.pos += 1
			right := parse_not(st, var cx, var p)?
			left = add_node(var cx, Node(1, left, right))
		else if starts_unary(p):
			right := parse_not(st, var cx, var p)?
			left = add_node(var cx, Node(1, left, right))
		else:
			break
	return ok(left)

fn parse_or(st: State, var cx: Ctx, var p: Parser) Int!:
	var left = parse_and(st, var cx, var p)?
	while peek_word(p, "OR"):
		p.pos += 1
		right := parse_and(st, var cx, var p)?
		left = add_node(var cx, Node(2, left, right))
	return ok(left)

fn compile(st: State, text: String, var cx: Ctx) Int!:
	toks := lex(text)?
	if toks.length() == 0: return ok(add_node(var cx, Node(4)))
	var p = Parser(toks)
	root := parse_or(st, var cx, var p)?
	if p.pos < p.toks.length(): return error(unexpected(p))
	return ok(root)

fn cmp_int_op(op: String, x: Int, a: Int) Bool:
	if op == "<": return x < a
	if op == "<=": return x <= a
	if op == ">": return x > a
	return x >= a

fn cmp_str_op(op: String, x: String, a: String) Bool:
	if op == "<": return x < a
	if op == "<=": return x <= a
	if op == ">": return x > a
	return x >= a

fn eval_term(st: State, n: Node, iss: Issue) Bool:
	f := n.field
	op := n.op
	if f == "id" or f == "created" or f == "updated" or f == "points":
		var x = iss.points
		if f == "id": x = iss.id
		if f == "created": x = iss.created
		if f == "updated": x = iss.updated
		if op == ":" or op == "!=":
			var m = false
			for a in n.nums:
				if a == -1:
					if x < 0: m = true
				else if x == a:
					m = true
			if op == ":": return m
			return not m
		if x < 0: return false
		return cmp_int_op(op, x, n.nums[0])
	if f == "title" or f == "assignee" or f == "reporter":
		var val = iss.title.clone()
		if f == "assignee": val = iss.assignee.clone()
		if f == "reporter": val = iss.reporter.clone()
		absent := f != "title" and val.is_empty()
		lv := val.lower()
		var m = false
		if op == "~":
			if absent: return false
			for a in n.vals:
				if lv.contains(a.lower()): m = true
			return m
		for a in n.vals:
			if absent:
				if a == "none": m = true
			else if lv == a.lower():
				m = true
		if op == ":": return m
		return not m
	if f == "text":
		lt := iss.title.lower()
		for a in n.vals:
			la := a.lower()
			if lt.contains(la): return true
			for c in iss.comments:
				if c.text.lower().contains(la): return true
		return false
	if f == "state":
		var m = false
		for a in n.vals:
			if a == iss.state: m = true
		if op == ":": return m
		return not m
	if f == "priority":
		if op == ":" or op == "!=":
			var m = false
			for a in n.nums:
				if a == iss.priority: m = true
			if op == ":": return m
			return not m
		return cmp_int_op(op, iss.priority, n.nums[0])
	if f == "due":
		if op == ":" or op == "!=":
			var m = false
			for a in n.vals:
				if a == "none":
					if iss.due.is_empty(): m = true
				else if a == iss.due:
					m = true
			if op == ":": return m
			return not m
		if iss.due.is_empty(): return false
		return cmp_str_op(op, iss.due, n.vals[0])
	if f == "label" or f == "labels":
		var m = false
		for a in n.vals:
			la := a.lower()
			if op == "~":
				for l in iss.labels:
					if l.contains(la): m = true
			else if la == "none" and iss.labels.length() == 0:
				m = true
			else if iss.labels.contains(la):
				m = true
		if op == "!=": return not m
		return m
	if f == "is":
		var m = false
		for a in n.vals:
			if a == "open" and not is_final(st, iss.state): m = true
			if a == "final" and is_final(st, iss.state): m = true
			if a == "unassigned" and iss.assignee.is_empty(): m = true
			if a == "overdue" and not is_final(st, iss.state) and not iss.due.is_empty() and iss.due < st.today: m = true
		return m
	if f == "has":
		var m = false
		for a in n.vals:
			if a == "assignee" and not iss.assignee.is_empty(): m = true
			if a == "due" and not iss.due.is_empty(): m = true
			if a == "points" and iss.points >= 0: m = true
			if a == "labels" and iss.labels.length() > 0: m = true
			if a == "comments" and iss.comments.length() > 0: m = true
			if a == "reporter" and not iss.reporter.is_empty(): m = true
		return m
	return false

fn eval_node(st: State, nodes: List[Node], i: Int, iss: Issue) Bool:
	k := nodes[i].kind
	if k == 4: return true
	if k == 0: return eval_term(st, nodes[i], iss)
	if k == 3: return not eval_node(st, nodes, nodes[i].a, iss)
	if k == 1:
		return eval_node(st, nodes, nodes[i].a, iss) and eval_node(st, nodes, nodes[i].b, iss)
	return eval_node(st, nodes, nodes[i].a, iss) or eval_node(st, nodes, nodes[i].b, iss)

fn match_idxs(st: State, cx: Ctx, root: Int) List[Int]:
	var out = List[Int]()
	for i in 0..st.issues.length():
		if eval_node(st, cx.nodes, root, st.issues[i]): out.append(i)
	return out

fn filter_only(st: State, text: String) List[Int]!:
	var cx = Ctx()
	root := compile(st, text, var cx)?
	return ok(match_idxs(st, cx, root))

// split limit and sort clauses
fn analyze(text: String) QParts!:
	var q = QParts()
	cs := text.chars()
	var end = cs.length()
	while end > 0 and is_ws(cs[end - 1]):
		end -= 1
	// last word
	var a0 = end
	while a0 > 0 and not is_ws(cs[a0 - 1]):
		a0 -= 1
	var b1 = a0
	while b1 > 0 and is_ws(cs[b1 - 1]):
		b1 -= 1
	var b0 = b1
	while b0 > 0 and not is_ws(cs[b0 - 1]):
		b0 -= 1
	if a0 < end and b1 > b0 and a0 > b1 and join_range(cs, b0, b1) == "limit":
		arg := join_range(cs, a0, end)
		n := parse_num(arg)
		if n < 0: return error(Error("bad limit '{arg}'"))
		q.has_limit = true
		q.limit = n
		end = b0
	var len = end
	var i = 0
	var found = -1
	while i + 4 < len + 0 and found < 0:
		if cs[i] == "s" and cs[i + 1] == "o" and cs[i + 2] == "r" and cs[i + 3] == "t" and is_ws(cs[i + 4]):
			if i == 0 or is_ws(cs[i - 1]): found = i
		i += 1
	if found >= 0:
		q.has_sort = true
		q.sort = join_range(cs, found + 4, len)
		q.filter = join_range(cs, 0, found)
	else:
		q.filter = join_range(cs, 0, len)
	return ok(q)

fn sort_fields() List[String]:
	return ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]

fn parse_sort(text: String) List[SortKey]!:
	var out = List[SortKey]()
	for piece in text.replace(",", " ").fields():
		var desc = false
		var name = piece.clone()
		if piece.starts_with("-"):
			desc = true
			name = join_range(piece.chars(), 1, piece.chars().length())
		if not sort_fields().contains(name): return error(Error("bad sort field '{name}'"))
		out.append(SortKey(name, desc))
	return ok(out)

fn cmp_i(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_s(a: String, b: String) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_opt_s(a: String, b: String) Int:
	if a.is_empty() and b.is_empty(): return 0
	if a.is_empty(): return 1
	if b.is_empty(): return -1
	return cmp_s(a, b)

fn cmp_field(st: State, f: String, a: Issue, b: Issue) Int:
	if f == "id": return cmp_i(a.id, b.id)
	if f == "created": return cmp_i(a.created, b.created)
	if f == "updated": return cmp_i(a.updated, b.updated)
	if f == "priority": return cmp_i(a.priority, b.priority)
	if f == "points":
		if a.points < 0 and b.points < 0: return 0
		if a.points < 0: return 1
		if b.points < 0: return -1
		return cmp_i(a.points, b.points)
	if f == "state": return cmp_i(state_idx(st, a.state), state_idx(st, b.state))
	if f == "title": return cmp_s(a.title.lower(), b.title.lower())
	if f == "assignee": return cmp_opt_s(a.assignee.lower(), b.assignee.lower())
	if f == "reporter": return cmp_opt_s(a.reporter.lower(), b.reporter.lower())
	return cmp_opt_s(a.due, b.due)

fn cmp_all(st: State, keys: List[SortKey], x: Int, y: Int) Int:
	a := st.issues[x]
	b := st.issues[y]
	for k in keys:
		c := cmp_field(st, k.field, a, b)
		if c != 0:
			if k.desc: return 0 - c
			return c
	return cmp_i(a.id, b.id)

fn exec_query(st: State, q: QParts) List[Int]!:
	var cx = Ctx()
	root := compile(st, q.filter, var cx)?
	keys := parse_sort(q.sort)?
	idxs := match_idxs(st, cx, root)
	var res = idxs.clone()
	if keys.length() > 0:
		res = idxs.sorted(fn x, y: cmp_all(st, keys, x, y))
	if q.has_limit and res.length() > q.limit:
		var cut = List[Int]()
		for i in 0..q.limit:
			cut.append(res[i])
		res = cut
	return ok(res)

fn issue_line(i: Issue) String:
	return "#{i.id} | {i.state} | {pri_name(i.priority)} | {dash(i.assignee)} | {pts(i.points)} | {dash(i.due)} | {dash(i.labels.join(","))} | {i.title}"

fn print_issues(st: State, idxs: List[Int]) Unit:
	for i in idxs:
		print(issue_line(st.issues[i]))
	if idxs.length() == 1:
		print("(1 issue)")
	else:
		print("({idxs.length()} issues)")

fn cmd_list(st: State, text: String) Unit:
	q := analyze(text)
	if p := q:
		r := exec_query(st, p)
		if idxs := r:
			print_issues(st, idxs)
		else:
			print("error: {r.err().message}")
	else:
		print("error: {q.err().message}")

// ---------- views ----------

fn view_refs(st: State, text: String) List[String]:
	var cx = Ctx()
	r := analyze(text)
	if p := r:
		c := compile(st, p.filter, var cx)
		if _x := c:
			return cx.refs.clone()
	return cx.refs.clone()

fn view_save(var st: State, rest: String) String!:
	parts := split_rest(rest, 1)
	name := parts[0]
	if name.is_empty(): return error(Error("usage: view save NAME QUERY"))
	if not valid_view_name(name): return error(Error("bad view name '{name}'"))
	query := parts[1].trim()
	q := analyze(query)?
	var cx = Ctx()
	_root := compile(st, q.filter, var cx)?
	_keys := parse_sort(q.sort)?
	if cx.refs.contains(name): return error(Error("view '{name}' would reference itself"))
	st.views[name.clone()] = query.clone()
	return ok("saved view {name}")

fn view_run(st: State, rest: String) Unit:
	parts := split_rest(rest, 1)
	name := parts[0]
	if name.is_empty():
		print("error: usage: view run NAME [sort FIELDS] [limit N]")
		return
	stored := st.views.get(name)
	if stored.is_none():
		print("error: unknown view '{name}'")
		return
	var base = QParts()
	br := analyze(stored.get(""))
	if b := br:
		base = b.clone()
	ex := analyze(parts[1])
	var e = QParts()
	if x := ex:
		e = x.clone()
	else:
		print("error: {ex.err().message}")
		return
	if not e.filter.trim().is_empty():
		print("error: unexpected '{e.filter.trim()}'")
		return
	if e.has_sort:
		base.has_sort = true
		base.sort = e.sort.clone()
	if e.has_limit:
		base.has_limit = true
		base.limit = e.limit
	r := exec_query(st, base)
	if idxs := r:
		print_issues(st, idxs)
	else:
		print("error: {r.err().message}")

fn cmd_view(var st: State, rest: String) Unit:
	parts := split_rest(rest, 1)
	sub := parts[0]
	args := parts[1]
	if sub == "save":
		show_res(view_save(var st, args))
	else if sub == "run":
		view_run(st, args)
	else if sub == "list":
		names := st.views.keys().sorted()
		if names.length() == 0:
			print("(no views)")
		for n in names:
			print("{n}: {st.views.get_or(n, "")}")
	else if sub == "show" or sub == "delete":
		w := args.fields()
		if w.length() != 1:
			print("error: usage: view {sub} NAME")
			return
		name := w[0]
		if not st.views.contains(name):
			print("error: unknown view '{name}'")
			return
		if sub == "show":
			print("{name}: {st.views.get_or(name, "")}")
			return
		for m in st.views.keys().sorted():
			if m == name: continue
			refs := view_refs(st, st.views.get_or(m, ""))
			if refs.contains(name):
				print("error: view '{name}' is used by '{m}'")
				return
		st.views.remove(name.clone())
		print("deleted view {name}")
	else:
		print("error: usage: view save|run|list|show|delete")

// ---------- bulk ----------

fn cmd_bulk(var st: State, rest: String) Unit:
	cs := rest.chars()
	w := find_word(cs, "where")
	if w < 0:
		print("error: usage: bulk ACTION... where QUERY")
		return
	action := join_range(cs, 0, w).trim()
	if action.is_empty():
		print("error: usage: bulk ACTION... where QUERY")
		return
	query := join_range(cs, w + 5, cs.length()).trim()
	tr := tokenize(action)
	var toks = List[String]()
	if tk := tr:
		toks = tk.clone()
	else:
		print("error: {tr.err().message}")
		return
	kind := toks[0]
	if kind == "move":
		if toks.length() != 2:
			print("error: usage: bulk move STATE where QUERY")
			return
	else if kind == "assign":
		if toks.length() != 2:
			print("error: usage: bulk assign NAME where QUERY")
			return
	else if kind == "label":
		if toks.length() < 2:
			print("error: usage: bulk label +label... where QUERY")
			return
	else if kind == "set":
		if toks.length() < 2:
			print("error: usage: bulk set field=value... where QUERY")
			return
	else:
		print("error: unknown bulk action '{kind}'")
		return
	mr := filter_only(st, query)
	var idxs = List[Int]()
	if mm := mr:
		idxs = mm.clone()
	else:
		print("error: {mr.err().message}")
		return
	var ids = List[Int]()
	for i in idxs:
		ids.append(st.issues[i].id)
	var nok = 0
	var nfail = 0
	for id in ids:
		var r: String! = ok("")
		if kind == "move":
			r = move_core(var st, id, toks[1], "")
		else if kind == "assign":
			var one = List[String]()
			one.append("assignee={toks[1]}")
			r = edit_core(var st, id, one, 0)
		else if kind == "label":
			r = label_core(var st, id, toks, 1)
		else:
			r = edit_core(var st, id, toks, 1)
		if v := r:
			print(v)
			nok += 1
		else:
			print("#{id} error: {r.err().message}")
			nfail += 1
	print("bulk: {nok} ok, {nfail} failed")

// ---------- simple commands ----------

fn cmd_create(var st: State, rest: String) String!:
	if not st.has_wf: return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: create TITLE [field=value...]"))
	title := toks[0]
	if title.trim().is_empty(): return error(Error("empty title"))
	f := parse_fields(toks, 1)?
	base := Issue(0, title.clone(), st.initial.clone())
	details := change_details(base, f)
	var iss = Issue(st.next_id, title.clone(), st.initial.clone())
	apply_fields(var iss, f)
	if not f.has_reporter: iss.reporter = st.actor.clone()
	st.t += 1
	iss.created = st.t
	iss.updated = st.t
	id := iss.id
	st.next_id += 1
	st.issues.append(iss)
	add_log(var st, id, "created \"{title}\"", "")
	for d in details:
		add_log(var st, id, d, "")
	return ok("created #{id}")

fn cmd_edit(var st: State, rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))
	id := parse_id(st, toks[0])?
	return edit_core(var st, id, toks, 1)

fn cmd_label(var st: State, rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() < 2: return error(Error("usage: label ID +label -label..."))
	id := parse_id(st, toks[0])?
	return label_core(var st, id, toks, 1)

fn cmd_assign(var st: State, rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() != 2: return error(Error("usage: assign ID NAME"))
	id := parse_id(st, toks[0])?
	var one = List[String]()
	one.append("assignee={toks[1]}")
	return edit_core(var st, id, one, 0)

fn cmd_move(var st: State, rest: String) String!:
	parts := split_rest(rest, 2)
	if parts[0].is_empty() or parts[1].is_empty(): return error(Error("usage: move ID STATE [comment...]"))
	id := parse_id(st, parts[0])?
	return move_core(var st, id, parts[1], parts[2])

fn cmd_comment(var st: State, rest: String) String!:
	parts := split_rest(rest, 1)
	if parts[0].is_empty() or parts[1].is_empty(): return error(Error("usage: comment ID TEXT"))
	id := parse_id(st, parts[0])?
	idx := find_idx(st, id)
	st.t += 1
	st.issues[idx].updated = st.t
	st.issues[idx].comments.append(Comment(st.t, st.actor.clone(), parts[1].clone()))
	add_log(var st, id, "comment: {parts[1]}", "")
	return ok("commented #{id}")

fn cmd_delete(var st: State, rest: String) String!:
	w := rest.fields()
	if w.length() != 1: return error(Error("usage: delete ID"))
	id := parse_id(st, w[0])?
	idx := find_idx(st, id)
	st.issues.remove(idx)
	st.t += 1
	add_log(var st, id, "deleted", "")
	return ok("deleted #{id}")

fn cmd_show(st: State, rest: String) String!:
	w := rest.fields()
	if w.length() != 1: return error(Error("usage: show ID"))
	id := parse_id(st, w[0])?
	i := st.issues[find_idx(st, id)]
	var lines = List[String]()
	lines.append("#{i.id} {i.title}")
	lines.append("  state: {i.state}")
	lines.append("  priority: {pri_name(i.priority)}")
	lines.append("  assignee: {dash(i.assignee)}")
	lines.append("  points: {pts(i.points)}")
	lines.append("  due: {dash(i.due)}")
	lines.append("  labels: {dash(i.labels.join(", "))}")
	lines.append("  reporter: {dash(i.reporter)}")
	lines.append("  created: t={i.created}, updated: t={i.updated}")
	lines.append("  comments: {i.comments.length()}")
	for c in i.comments:
		lines.append("    [t={c.t} {c.actor}] {c.text}")
	return ok(lines.join("\n"))

fn cmd_log(st: State, rest: String) String!:
	w := rest.fields()
	var id = -1
	var tail = -1
	var n = w.length()
	var pos = 0
	if n > 0 and w[0] != "tail":
		id = parse_id_num(w[0])?
		pos = 1
	if n - pos == 2 and w[pos] == "tail":
		pass_tail := w[pos + 1]
		tail = parse_num(pass_tail)
		if tail < 0:
			if id > 0 and id >= st.next_id: return error(Error("no such issue #{id}"))
			return error(Error("bad tail '{pass_tail}'"))
	else if n - pos != 0:
		return error(Error("usage: log [ID] [tail N]"))
	if id > 0 and id >= st.next_id: return error(Error("no such issue #{id}"))
	var sel = List[String]()
	for e in st.log:
		if id < 0 or e.id == id:
			sel.append("t={e.t} {e.actor} #{e.id} {e.detail}")
	if tail >= 0 and sel.length() > tail:
		var cut = List[String]()
		for i in (sel.length() - tail)..sel.length():
			cut.append(sel[i].clone())
		sel = cut
	if sel.length() == 0: return ok("(no log entries)")
	return ok(sel.join("\n"))

// ---------- reports ----------

type Group:
	name: String
	count: Int
	points: Int

fn report_summary(st: State) String!:
	var open = 0
	var fin = 0
	var unassigned = 0
	var overdue = 0
	var open_pts = 0
	var by_state = Map[String, Int]()
	var by_pri = [0, 0, 0, 0]
	for i in st.issues:
		by_state[i.state.clone()] = by_state.get_or(i.state, 0) + 1
		by_pri[i.priority] = by_pri[i.priority] + 1
		if is_final(st, i.state):
			fin += 1
		else:
			open += 1
			if i.assignee.is_empty(): unassigned += 1
			if not i.due.is_empty() and i.due < st.today: overdue += 1
			if i.points >= 0: open_pts += open_pts * 0 + i.points
	var lines = List[String]()
	lines.append("issues: {st.issues.length()} (open {open}, final {fin})")
	lines.append("by state:")
	for s in st.states:
		lines.append("  {s}: {by_state.get_or(s, 0)}")
	lines.append("by priority:")
	lines.append("  critical: {by_pri[3]}")
	lines.append("  high: {by_pri[2]}")
	lines.append("  medium: {by_pri[1]}")
	lines.append("  low: {by_pri[0]}")
	lines.append("unassigned: {unassigned}")
	lines.append("overdue: {overdue}")
	lines.append("open points: {open_pts}")
	return ok(lines.join("\n"))

fn plural(n: Int) String:
	if n == 1: return "issue"
	return "issues"

fn report_workload(st: State) String!:
	var groups = List[Group]()
	var un = Group("unassigned", 0, 0)
	for i in st.issues:
		if is_final(st, i.state): continue
		p := if i.points >= 0: i.points else: 0
		if i.assignee.is_empty():
			un.count += 1
			un.points += p
			continue
		low := i.assignee.lower()
		var found = -1
		for k in 0..groups.length():
			if groups[k].name.lower() == low: found = k
		if found < 0:
			groups.append(Group(i.assignee.clone(), 1, p))
		else:
			groups[found].count += 1
			groups[found].points += p
	if groups.length() == 0 and un.count == 0: return ok("(no open issues)")
	sorted := groups.sorted(fn a, b: group_cmp(a, b))
	var lines = List[String]()
	for g in sorted:
		lines.append("{g.name}: {g.count} {plural(g.count)}, {g.points} points")
	if un.count > 0:
		lines.append("unassigned: {un.count} {plural(un.count)}, {un.points} points")
	return ok(lines.join("\n"))

fn group_cmp(a: Group, b: Group) Int:
	if a.points != b.points: return cmp_i(b.points, a.points)
	if a.count != b.count: return cmp_i(b.count, a.count)
	return cmp_s(a.name.lower(), b.name.lower())

fn report_labels(st: State, text: String) String!:
	idxs := filter_only(st, text)?
	var counts = Map[String, Int]()
	for i in idxs:
		for l in st.issues[i].labels:
			counts[l.clone()] = counts.get_or(l, 0) + 1
	names := counts.keys().sorted(fn a, b: label_cmp(counts, a, b))
	if names.length() == 0: return ok("(no labels)")
	var lines = List[String]()
	for n in names:
		lines.append("{n}: {counts.get_or(n, 0)}")
	return ok(lines.join("\n"))

fn label_cmp(counts: Map[String, Int], a: String, b: String) Int:
	ca := counts.get_or(a, 0)
	cb := counts.get_or(b, 0)
	if ca != cb: return cmp_i(cb, ca)
	return cmp_s(a, b)

fn report_timeline(st: State, args: String) String!:
	w := args.fields()
	if w.length() != 1: return error(Error("usage: report timeline ID"))
	id := parse_id(st, w[0])?
	idx := find_idx(st, id)
	var names = List[String]()
	var starts = List[Int]()
	names.append(st.initial.clone())
	starts.append(st.issues[idx].created)
	for e in st.log:
		if e.id == id and not e.to_state.is_empty():
			names.append(e.to_state.clone())
			starts.append(e.t)
	var lines = List[String]()
	for k in 0..names.length():
		var to = st.t
		if k + 1 < names.length(): to = starts[k + 1]
		lines.append("{names[k]}: t={starts[k]}..{to} ({to - starts[k]})")
	return ok(lines.join("\n"))

fn cmd_report(st: State, rest: String) String!:
	parts := split_rest(rest, 1)
	sub := parts[0]
	if sub == "summary": return report_summary(st)
	if sub == "workload": return report_workload(st)
	if sub == "labels": return report_labels(st, parts[1])
	if sub == "timeline": return report_timeline(st, parts[1])
	return error(Error("usage: report summary|workload|labels|timeline"))

// ---------- main ----------

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().ok_or(Error("invalid utf-8 input"))?
	lines := text.lines()
	var st = State()
	var i = 0
	while i < lines.length():
		raw := lines[i]
		i += 1
		trimmed := raw.trim()
		if trimmed.is_empty() or trimmed.starts_with("#"): continue
		line := raw.trim_end()
		print("> {line}")
		parts := split_rest(line, 1)
		cmd := parts[0]
		rest := parts[1]
		if cmd == "workflow":
			var block = List[String]()
			while i < lines.length():
				l := lines[i]
				i += 1
				if l.trim() == "end": break
				block.append(l.clone())
			cmd_workflow(var st, block)
		else if cmd == "actor":
			w := rest.fields()
			if w.length() != 1:
				print("error: usage: actor NAME")
			else:
				st.actor = w[0].clone()
				print("actor is {w[0]}")
		else if cmd == "today":
			w := rest.fields()
			if w.length() != 1:
				print("error: usage: today DATE")
			else if not valid_date(w[0]):
				print("error: bad date '{w[0]}'")
			else:
				st.today = w[0].clone()
				print("today is {w[0]}")
		else if cmd == "create": show_res(cmd_create(var st, rest))
		else if cmd == "edit": show_res(cmd_edit(var st, rest))
		else if cmd == "label": show_res(cmd_label(var st, rest))
		else if cmd == "assign": show_res(cmd_assign(var st, rest))
		else if cmd == "move": show_res(cmd_move(var st, rest))
		else if cmd == "comment": show_res(cmd_comment(var st, rest))
		else if cmd == "delete": show_res(cmd_delete(var st, rest))
		else if cmd == "show": show_res(cmd_show(st, rest))
		else if cmd == "log": show_res(cmd_log(st, rest))
		else if cmd == "list": cmd_list(st, rest)
		else if cmd == "view": cmd_view(var st, rest)
		else if cmd == "bulk": cmd_bulk(var st, rest)
		else if cmd == "report": show_res(cmd_report(st, rest))
		else:
			print("error: unknown command '{cmd}'")
