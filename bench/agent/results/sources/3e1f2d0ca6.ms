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
	assignee: String? = none
	reporter: String? = none
	points: Int? = none
	due: String? = none
	labels: List[String] = []
	comments: List[Comment] = []
	created: Int = 0
	updated: Int = 0
	alive: Bool = true
	hist_state: List[String] = []
	hist_t: List[Int] = []

type Fields:
	title: String
	priority: Int
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

type Trans:
	src: String
	dst: String
	guards: List[String]

type View:
	name: String
	query: String

type St:
	issues: List[Issue] = []
	log: List[LogEntry] = []
	views: List[View] = []
	states: List[String] = []
	finals: List[String] = []
	initial: String = ""
	trans: List[Trans] = []
	clock: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	out: List[String] = []

type Node:
	kind: Int
	a: Int = 0
	b: Int = 0
	field: String = ""
	op: String = ""
	vals: List[String] = []
	nums: List[Int] = []

type Arena:
	nodes: List[Node] = []
	refs: List[String] = []

type Tok:
	kind: Int
	text: String = ""
	field: String = ""
	op: String = ""
	value: String = ""
	quoted: Bool = false

type SortKey:
	field: String
	desc: Bool

type Clauses:
	filter: String
	sort: String?
	limit: Int?

// ---------- basic helpers ----------

fn split_on(s: String, sep: String) List[String]:
	var res = List[String]()
	var cur = ""
	for c in s.chars():
		if c == sep:
			res.append(cur.clone())
			cur = ""
		else:
			cur += c
	res.append(cur.clone())
	return res

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\r"

fn is_digit(c: String) Bool: c >= "0" and c <= "9"

fn join_range(cs: List[String], a: Int, b: Int) String:
	var r = ""
	var i = a
	while i < b:
		r += cs[i]
		i += 1
	return r

fn words(s: String) List[String]:
	var res = List[String]()
	var cur = ""
	for c in s.chars():
		if is_ws(c):
			if cur.length() > 0:
				res.append(cur.clone())
				cur = ""
		else:
			cur += c
	if cur.length() > 0:
		res.append(cur.clone())
	return res

fn rest_after_words(s: String, n: Int) String:
	cs := s.chars()
	var i = 0
	var w = 0
	while w < n:
		while i < cs.length() and is_ws(cs[i]):
			i += 1
		while i < cs.length() and not is_ws(cs[i]):
			i += 1
		w += 1
	while i < cs.length() and is_ws(cs[i]):
		i += 1
	return join_range(cs, i, cs.length()).trim_end()

fn tokenize(s: String) List[String]!:
	var res = List[String]()
	var cur = ""
	var in_tok = false
	var inq = false
	cs := s.chars()
	var i = 0
	while i < cs.length():
		c := cs[i]
		if inq:
			if c == "\\" and i + 1 < cs.length() and (cs[i + 1] == "\"" or cs[i + 1] == "\\"):
				cur += cs[i + 1]
				i += 2
				continue
			if c == "\"":
				inq = false
			else:
				cur += c
		else:
			if c == "\"":
				inq = true
				in_tok = true
			else if is_ws(c):
				if in_tok:
					res.append(cur.clone())
					cur = ""
					in_tok = false
			else:
				cur += c
				in_tok = true
		i += 1
	if inq:
		return error(Error("unterminated quote"))
	if in_tok:
		res.append(cur.clone())
	return ok(res)

fn parse_num(s: String) Int?:
	n := s.length()
	if n == 0 or n > 7:
		return none
	for c in s.chars():
		if not is_digit(c):
			return none
	if n > 1 and s.starts_with("0"):
		return none
	v := s.parse_int().get(-1)
	if v < 0 or v > 1000000:
		return none
	return v

fn is_leap(y: Int) Bool: (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn days_in(y: Int, m: Int) Int:
	if m == 2:
		return if is_leap(y): 29 else: 28
	if m == 4 or m == 6 or m == 9 or m == 11:
		return 30
	return 31

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10:
		return false
	for i in 0..10:
		if i == 4 or i == 7:
			if cs[i] != "-":
				return false
		else if not is_digit(cs[i]):
			return false
	y := join_range(cs, 0, 4).parse_int().get(0)
	m := join_range(cs, 5, 7).parse_int().get(0)
	d := join_range(cs, 8, 10).parse_int().get(0)
	if y < 1 or m < 1 or m > 12 or d < 1:
		return false
	return d <= days_in(y, m)

fn prio_name(p: Int) String:
	if p == 0:
		return "low"
	if p == 1:
		return "medium"
	if p == 2:
		return "high"
	return "critical"

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

fn opt_str(o: String?) String:
	if v := o:
		return v.clone()
	return "-"

fn opt_int(o: Int?) String:
	if v := o:
		return "{v}"
	return "-"

fn labels_str(ls: List[String], sep: String) String:
	if ls.length() == 0:
		return "-"
	return ls.join(sep)

fn is_final(st: St, s: String) Bool:
	for f in st.finals:
		if f == s:
			return true
	return false

fn has_state(st: St, s: String) Bool:
	for f in st.states:
		if f == s:
			return true
	return false

fn state_index(st: St, s: String) Int:
	var i = 0
	for f in st.states:
		if f == s:
			return i
		i += 1
	return -1

fn err(msg: String) Error: Error(msg)

fn emit(var st: St, line: String) Unit:
	st.out.append(line.clone())

fn add_log(var st: St, id: Int, detail: String) Unit:
	st.log.append(LogEntry(st.clock, st.actor.clone(), id, detail.clone()))

fn valid_state_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0:
		return false
	if not (cs[0] >= "a" and cs[0] <= "z"):
		return false
	for c in cs:
		if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_"):
			return false
	return true

fn valid_label(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0:
		return false
	for c in cs:
		if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"):
			return false
	return true

fn norm_labels(ls: List[String]) List[String]:
	var res = List[String]()
	for l in ls:
		var dup = false
		for r in res:
			if r == l:
				dup = true
		if not dup:
			res.append(l.clone())
	res.sort()
	return res

// ---------- ids ----------

fn find_issue(st: St, arg: String) Int!:
	var d = arg.clone()
	if d.starts_with("#"):
		d = d.slice(1, d.length())?
	if d.length() == 0:
		return error(Error("bad issue id '{arg}'"))
	for c in d.chars():
		if not is_digit(c):
			return error(Error("bad issue id '{arg}'"))
	var v = 0
	for c in d.chars():
		if v < 1000000000000:
			v = v * 10 + c.parse_int().get(0)
	if v < 1:
		return error(Error("bad issue id '{arg}'"))
	if v > st.issues.length():
		return error(Error("no such issue #{v}"))
	idx := v - 1
	if not st.issues[idx].alive:
		return error(Error("no such issue #{v}"))
	return ok(idx)

// ---------- field editing ----------

fn fields_of(it: Issue) Fields:
	return Fields(it.title.clone(), it.priority, it.assignee.clone(), it.points, it.due.clone(), it.labels.clone(), it.reporter.clone())

fn parse_labels(v: String) List[String]!:
	var res = List[String]()
	for p in split_on(v, ","):
		l := p.lower()
		if not valid_label(l):
			return error(Error("bad label '{l}'"))
		res.append(l.clone())
	return ok(norm_labels(res))

fn apply_token(var f: Fields, tok: String) Unit!:
	idx := tok.index_of("=").get(-1)
	if idx <= 0:
		return error(Error("expected field=value, got '{tok}'"))
	name := tok.slice(0, idx)?
	value := tok.slice(idx + 1, tok.length())?
	if name == "state":
		return error(Error("use move to change state"))
	if name == "title":
		if value.trim().length() == 0:
			return error(Error("empty title"))
		f.title = value
	else if name == "priority":
		r := prio_rank(value)
		if r < 0:
			return error(Error("bad priority '{value}'"))
		f.priority = r
	else if name == "assignee":
		if value == "none":
			f.assignee = none
		else:
			if value.trim().length() == 0:
				return error(Error("empty assignee"))
			f.assignee = value
	else if name == "points":
		if value == "none":
			f.points = none
		else:
			p := parse_num(value)
			if p.is_none():
				return error(Error("bad points '{value}'"))
			f.points = p
	else if name == "due":
		if value == "none":
			f.due = none
		else:
			if not valid_date(value):
				return error(Error("bad date '{value}'"))
			f.due = value
	else if name == "labels":
		if value == "none":
			f.labels = []
		else:
			f.labels = parse_labels(value)?
	else if name == "reporter":
		if value == "none":
			f.reporter = none
		else:
			if value.trim().length() == 0:
				return error(Error("empty reporter"))
			f.reporter = value
	else:
		return error(Error("unknown field '{name}'"))
	return ok(unit)

fn same_opt_s(a: String?, b: String?) Bool:
	if x := a:
		if y := b:
			return x == y
		return false
	return b.is_none()

fn same_opt_i(a: Int?, b: Int?) Bool:
	if x := a:
		if y := b:
			return x == y
		return false
	return b.is_none()

fn field_names() List[String]:
	return ["title", "priority", "assignee", "points", "due", "labels", "reporter"]

fn changed_flags(a: Fields, b: Fields) List[Bool]:
	return [a.title != b.title, a.priority != b.priority, not same_opt_s(a.assignee, b.assignee), not same_opt_i(a.points, b.points), not same_opt_s(a.due, b.due), a.labels.join(",") != b.labels.join(","), not same_opt_s(a.reporter, b.reporter)]

fn field_strs(a: Fields) List[String]:
	return [a.title.clone(), prio_name(a.priority), opt_str(a.assignee), opt_int(a.points), opt_str(a.due), labels_str(a.labels, ","), opt_str(a.reporter)]

fn log_diffs(var st: St, id: Int, old: Fields, new: Fields) Unit:
	flags := changed_flags(old, new)
	os := field_strs(old)
	ns := field_strs(new)
	names := field_names()
	for i in 0..7:
		if flags[i]:
			add_log(var st, id, "{names[i]}: {os[i]} -> {ns[i]}")

fn any_changed(flags: List[Bool]) Bool:
	for f in flags:
		if f:
			return true
	return false

fn commit_fields(var st: St, idx: Int, nf: Fields) String!:
	id := st.issues[idx].id
	old := fields_of(st.issues[idx])
	if not any_changed(changed_flags(old, nf)):
		return ok("#{id} unchanged")
	st.clock += 1
	log_diffs(var st, id, old, nf)
	st.issues[idx].title = nf.title.clone()
	st.issues[idx].priority = nf.priority
	st.issues[idx].assignee = nf.assignee.clone()
	st.issues[idx].points = nf.points
	st.issues[idx].due = nf.due.clone()
	st.issues[idx].labels = nf.labels.clone()
	st.issues[idx].reporter = nf.reporter.clone()
	st.issues[idx].updated = st.clock
	return ok("updated #{id}")

fn check_open(st: St, idx: Int) Unit!:
	if is_final(st, st.issues[idx].state):
		return error(Error("#{st.issues[idx].id} is in final state '{st.issues[idx].state}'"))
	return ok(unit)

fn edit_issue(var st: St, idx: Int, toks: List[String]) String!:
	check_open(st, idx)?
	var f = fields_of(st.issues[idx])
	for t in toks:
		apply_token(var f, t)?
	if toks.length() == 0:
		return error(Error("usage: edit ID field=value..."))
	return commit_fields(var st, idx, f)

fn label_issue(var st: St, idx: Int, toks: List[String]) String!:
	check_open(st, idx)?
	var f = fields_of(st.issues[idx])
	var ls = f.labels.clone()
	for t in toks:
		var neg = false
		var name = t.clone()
		if t.starts_with("+"):
			name = t.slice(1, t.length())?
		else if t.starts_with("-"):
			neg = true
			name = t.slice(1, t.length())?
		l := name.lower()
		if not valid_label(l):
			return error(Error("bad label '{l}'"))
		var nl = List[String]()
		for x in ls:
			if x != l:
				nl.append(x.clone())
		if not neg:
			nl.append(l.clone())
		ls = nl
	f.labels = norm_labels(ls)
	return commit_fields(var st, idx, f)

fn move_issue(var st: St, idx: Int, target: String, comment: String) String!:
	id := st.issues[idx].id
	cur := st.issues[idx].state.clone()
	check_open(st, idx)?
	if not has_state(st, target):
		return error(Error("unknown state '{target}'"))
	if cur == target:
		return error(Error("already in state '{target}'"))
	var found = false
	var missing = List[String]()
	for tr in st.trans:
		if not found and tr.src == cur and tr.dst == target:
			found = true
			for g in tr.guards:
				it := st.issues[idx]
				var unmet = false
				if g == "assignee":
					unmet = it.assignee.is_none()
				else if g == "points":
					unmet = it.points.is_none()
				else if g == "due":
					unmet = it.due.is_none()
				else if g == "labels":
					unmet = it.labels.length() == 0
				else if g == "reporter":
					unmet = it.reporter.is_none()
				if unmet:
					missing.append(g.clone())
	if not found:
		return error(Error("transition '{cur} -> {target}' not allowed"))
	if missing.length() > 0:
		return error(Error("cannot move #{id} to {target}: missing {missing.join(", ")}"))
	st.clock += 1
	st.issues[idx].state = target.clone()
	st.issues[idx].updated = st.clock
	st.issues[idx].hist_state.append(target.clone())
	st.issues[idx].hist_t.append(st.clock)
	add_log(var st, id, "state: {cur} -> {target}")
	if comment.length() > 0:
		st.issues[idx].comments.append(Comment(st.clock, st.actor.clone(), comment.clone()))
		add_log(var st, id, "comment: {comment}")
	return ok("moved #{id}: {cur} -> {target}")

// ---------- query lexing & parsing ----------

fn match_op(cs: List[String], k: Int) String:
	c := cs[k]
	nx := if k + 1 < cs.length(): cs[k + 1].clone() else: ""
	if c == "!" and nx == "=":
		return "!="
	if c == "<" and nx == "=":
		return "<="
	if c == ">" and nx == "=":
		return ">="
	if c == ":" or c == "<" or c == ">" or c == "~":
		return c.clone()
	return ""

fn lex_filter(s: String) List[Tok]!:
	var toks = List[Tok]()
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		if is_ws(c):
			i += 1
			continue
		if c == "(":
			toks.append(Tok(1, text: "("))
			i += 1
			continue
		if c == ")":
			toks.append(Tok(2, text: ")"))
			i += 1
			continue
		var j = i
		while j < n and not is_ws(cs[j]) and cs[j] != "(" and cs[j] != ")":
			j += 1
		lex := join_range(cs, i, j)
		if lex == "AND":
			toks.append(Tok(3, text: lex))
			i = j
			continue
		if lex == "OR":
			toks.append(Tok(4, text: lex))
			i = j
			continue
		if lex == "NOT":
			toks.append(Tok(5, text: lex))
			i = j
			continue
		var k = i
		while k < n and ((cs[k] >= "a" and cs[k] <= "z") or cs[k] == "_"):
			k += 1
		var op = ""
		if k > i and k < n:
			op = match_op(cs, k)
		if op.length() == 0:
			toks.append(Tok(6, text: lex))
			i = j
			continue
		field := join_range(cs, i, k)
		v := k + op.length()
		if v < n and cs[v] == "\"":
			var x = v + 1
			var val = ""
			var closed = false
			while x < n:
				if cs[x] == "\\" and x + 1 < n and (cs[x + 1] == "\"" or cs[x + 1] == "\\"):
					val += cs[x + 1]
					x += 2
					continue
				if cs[x] == "\"":
					closed = true
					x += 1
					break
				val += cs[x]
				x += 1
			if not closed:
				return error(Error("query: unterminated quote"))
			toks.append(Tok(0, field: field, op: op, value: val, quoted: true, text: join_range(cs, i, x)))
			i = x
		else:
			var e = v
			while e < n and not is_ws(cs[e]) and cs[e] != "(" and cs[e] != ")":
				e += 1
			toks.append(Tok(0, field: field, op: op, value: join_range(cs, v, e), text: join_range(cs, i, e)))
			i = e
	return ok(toks)

fn ordered_op(op: String) Bool: op == "<" or op == "<=" or op == ">" or op == ">="

fn bad_value(v: String, f: String) Error: Error("query: bad value '{v}' for field '{f}'")

fn compile_term(st: St, var arena: Arena, t: Tok) Int!:
	f := t.field
	op := t.op
	var allowed = List[String]()
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "priority" or f == "due":
		allowed = [":", "!=", "<", "<=", ">", ">="]
	else if f == "title" or f == "assignee" or f == "reporter" or f == "label" or f == "labels":
		allowed = [":", "!=", "~"]
	else if f == "text":
		allowed = ["~"]
	else if f == "state":
		allowed = [":", "!="]
	else if f == "is" or f == "has" or f == "view":
		allowed = [":"]
	else:
		return error(Error("query: unknown field '{f}'"))
	var okop = false
	for a in allowed:
		if a == op:
			okop = true
	if not okop:
		return error(Error("query: bad operator '{op}' for field '{f}'"))
	if f == "view":
		var found = false
		var q = ""
		for v in st.views:
			if v.name == t.value:
				found = true
				q = v.query.clone()
		if not found:
			return error(Error("query: unknown view '{t.value}'"))
		arena.refs.append(t.value.clone())
		cl := split_clauses(q)?
		root := parse_filter(st, cl.filter, var arena)?
		arena.nodes.append(Node(4, a: root, field: f.clone(), op: op.clone()))
		return ok(arena.nodes.length() - 1)
	var alts = List[String]()
	if (op == ":" or op == "!=" or op == "~") and not t.quoted and t.value.contains("|"):
		alts = split_on(t.value, "|")
	else:
		alts = [t.value.clone()]
	var vals = List[String]()
	var nums = List[Int]()
	for a in alts:
		if f == "id" or f == "created" or f == "updated" or f == "points":
			if f == "points" and a == "none" and (op == ":" or op == "!="):
				nums.append(-1)
			else:
				p := parse_num(a)
				if p.is_none():
					if ordered_op(op):
						return error(bad_value(alts.join("|"), f))
					return error(bad_value(a, f))
				nums.append(p.get(0))
			vals.append(a.clone())
		else if f == "title" or f == "assignee" or f == "reporter":
			vals.append(a.lower())
			nums.append(if a == "none": 1 else: 0)
		else if f == "text" or f == "label" or f == "labels":
			vals.append(a.lower())
		else if f == "state":
			if not has_state(st, a):
				return error(bad_value(a, f))
			vals.append(a.clone())
		else if f == "priority":
			r := prio_rank(a)
			if r < 0:
				return error(bad_value(a, f))
			vals.append(a.clone())
			nums.append(r)
		else if f == "due":
			if ordered_op(op):
				if not valid_date(a):
					return error(bad_value(a, f))
			else if a != "none" and not valid_date(a):
				return error(bad_value(a, f))
			vals.append(a.clone())
		else if f == "is":
			if a != "open" and a != "final" and a != "overdue" and a != "unassigned":
				return error(bad_value(a, f))
			vals.append(a.clone())
		else if f == "has":
			if a != "assignee" and a != "due" and a != "points" and a != "labels" and a != "comments" and a != "reporter":
				return error(bad_value(a, f))
			vals.append(a.clone())
	arena.nodes.append(Node(0, field: f.clone(), op: op.clone(), vals: vals, nums: nums))
	return ok(arena.nodes.length() - 1)

fn unexpected_end() Error: Error("query: unexpected end of query")

fn parse_not(st: St, toks: List[Tok], var pos: Int, var arena: Arena) Int!:
	if pos >= toks.length():
		return error(unexpected_end())
	t := toks[pos]
	if t.kind == 5:
		pos += 1
		inner := parse_not(st, toks, var pos, var arena)?
		arena.nodes.append(Node(3, a: inner))
		return ok(arena.nodes.length() - 1)
	if t.kind == 1:
		pos += 1
		inner := parse_or(st, toks, var pos, var arena)?
		if pos >= toks.length():
			return error(unexpected_end())
		pos += 1
		return ok(inner)
	if t.kind == 0:
		pos += 1
		return compile_term(st, var arena, t)
	return error(Error("query: unexpected token '{t.text}'"))

fn parse_and(st: St, toks: List[Tok], var pos: Int, var arena: Arena) Int!:
	var left = parse_not(st, toks, var pos, var arena)?
	while pos < toks.length():
		k := toks[pos].kind
		if k == 4 or k == 2:
			break
		if k == 3:
			pos += 1
		right := parse_not(st, toks, var pos, var arena)?
		arena.nodes.append(Node(1, a: left, b: right))
		left = arena.nodes.length() - 1
	return ok(left)

fn parse_or(st: St, toks: List[Tok], var pos: Int, var arena: Arena) Int!:
	var left = parse_and(st, toks, var pos, var arena)?
	while pos < toks.length() and toks[pos].kind == 4:
		pos += 1
		right := parse_and(st, toks, var pos, var arena)?
		arena.nodes.append(Node(2, a: left, b: right))
		left = arena.nodes.length() - 1
	return ok(left)

fn parse_filter(st: St, text: String, var arena: Arena) Int!:
	toks := lex_filter(text)?
	if toks.length() == 0:
		return ok(-1)
	var pos = 0
	root := parse_or(st, toks, var pos, var arena)?
	if pos < toks.length():
		return error(Error("query: unexpected token '{toks[pos].text}'"))
	return ok(root)

fn word_start_at(cs: List[String], i: Int, w: String) Bool:
	n := w.length()
	if i + n > cs.length():
		return false
	if i > 0 and not is_ws(cs[i - 1]):
		return false
	return join_range(cs, i, i + n) == w

fn split_clauses(text: String) Clauses!:
	cs := text.chars()
	var n = cs.length()
	var limit: Int? = none
	// trailing "limit N"
	var e = cs.length()
	while e > 0 and is_ws(cs[e - 1]):
		e -= 1
	var a = e
	while a > 0 and not is_ws(cs[a - 1]):
		a -= 1
	if a > 0 and a < e:
		var p = a
		while p > 0 and is_ws(cs[p - 1]):
			p -= 1
		var q = p
		while q > 0 and not is_ws(cs[q - 1]):
			q -= 1
		if p < a and q < p and join_range(cs, q, p) == "limit":
			arg := join_range(cs, a, e)
			lv := parse_num(arg)
			if lv.is_none():
				return error(Error("bad limit '{arg}'"))
			limit = lv
			n = q
	var filter = join_range(cs, 0, n)
	var sort: String? = none
	var i = 0
	while i + 4 < n:
		if word_start_at(cs, i, "sort") and is_ws(cs[i + 4]):
			filter = join_range(cs, 0, i)
			sort = join_range(cs, i + 4, n)
			break
		i += 1
	return ok(Clauses(filter, sort, limit))

fn parse_sort(text: String) List[SortKey]!:
	var keys = List[SortKey]()
	var cur = ""
	var parts = List[String]()
	for c in text.chars():
		if c == "," or is_ws(c):
			if cur.length() > 0:
				parts.append(cur.clone())
				cur = ""
		else:
			cur += c
	if cur.length() > 0:
		parts.append(cur.clone())
	valid := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	for p in parts:
		var desc = false
		var name = p.clone()
		if p.starts_with("-"):
			desc = true
			name = p.slice(1, p.length())?
		var okf = false
		for v in valid:
			if v == name:
				okf = true
		if not okf:
			return error(Error("bad sort field '{name}'"))
		keys.append(SortKey(name.clone(), desc))
	return ok(keys)

// ---------- evaluation ----------

fn any_eq_s(vals: List[String], x: String) Bool:
	for v in vals:
		if v == x:
			return true
	return false

fn cmp_i(op: String, a: Int, b: Int) Bool:
	if op == "<":
		return a < b
	if op == "<=":
		return a <= b
	if op == ">":
		return a > b
	return a >= b

fn eval_term(st: St, n: Node, it: Issue) Bool:
	f := n.field
	op := n.op
	if f == "id" or f == "created" or f == "updated" or f == "points":
		var v: Int? = none
		if f == "id":
			v = it.id
		else if f == "created":
			v = it.created
		else if f == "updated":
			v = it.updated
		else:
			v = it.points
		if x := v:
			if op == ":":
				return n.nums.any(fn y: y == x)
			if op == "!=":
				return not n.nums.any(fn y: y == x)
			return cmp_i(op, x, n.nums[0])
		if op == ":":
			return n.nums.any(fn y: y == -1)
		if op == "!=":
			return not n.nums.any(fn y: y == -1)
		return false
	if f == "title" or f == "assignee" or f == "reporter":
		var v: String? = none
		if f == "title":
			v = it.title.clone()
		else if f == "assignee":
			v = it.assignee.clone()
		else:
			v = it.reporter.clone()
		if op == "~":
			if x := v:
				xl := x.lower()
				return n.vals.any(fn y: xl.contains(y))
			return false
		var m = false
		if x := v:
			xl := x.lower()
			m = n.vals.any(fn y: y == xl)
		else:
			m = n.nums.any(fn y: y == 1)
		return if op == ":": m else: not m
	if f == "text":
		tl := it.title.lower()
		for y in n.vals:
			if tl.contains(y):
				return true
			for c in it.comments:
				if c.text.lower().contains(y):
					return true
		return false
	if f == "state":
		m := n.vals.any(fn y: y == it.state)
		return if op == ":": m else: not m
	if f == "priority":
		if op == ":":
			return n.nums.any(fn y: y == it.priority)
		if op == "!=":
			return not n.nums.any(fn y: y == it.priority)
		return cmp_i(op, it.priority, n.nums[0])
	if f == "due":
		if d := it.due:
			if op == ":":
				return n.vals.any(fn y: y == d)
			if op == "!=":
				return not n.vals.any(fn y: y == d)
			if op == "<":
				return d < n.vals[0]
			if op == "<=":
				return d <= n.vals[0]
			if op == ">":
				return d > n.vals[0]
			return d >= n.vals[0]
		if op == ":":
			return n.vals.any(fn y: y == "none")
		if op == "!=":
			return not n.vals.any(fn y: y == "none")
		return false
	if f == "label" or f == "labels":
		if op == "~":
			for y in n.vals:
				for l in it.labels:
					if l.contains(y):
						return true
			return false
		var m = false
		for y in n.vals:
			if y == "none" and it.labels.length() == 0:
				m = true
			if any_eq_s(it.labels, y):
				m = true
		return if op == ":": m else: not m
	if f == "is":
		for y in n.vals:
			if y == "open" and not is_final(st, it.state):
				return true
			if y == "final" and is_final(st, it.state):
				return true
			if y == "unassigned" and it.assignee.is_none():
				return true
			if y == "overdue" and not is_final(st, it.state):
				if d := it.due:
					if d < st.today:
						return true
		return false
	if f == "has":
		for y in n.vals:
			if y == "assignee" and it.assignee.is_some():
				return true
			if y == "due" and it.due.is_some():
				return true
			if y == "points" and it.points.is_some():
				return true
			if y == "labels" and it.labels.length() > 0:
				return true
			if y == "comments" and it.comments.length() > 0:
				return true
			if y == "reporter" and it.reporter.is_some():
				return true
		return false
	return false

fn eval_node(st: St, arena: Arena, node: Int, it: Issue) Bool:
	if node < 0:
		return true
	n := arena.nodes[node]
	if n.kind == 0:
		return eval_term(st, n, it)
	if n.kind == 1:
		return eval_node(st, arena, n.a, it) and eval_node(st, arena, n.b, it)
	if n.kind == 2:
		return eval_node(st, arena, n.a, it) or eval_node(st, arena, n.b, it)
	if n.kind == 3:
		return not eval_node(st, arena, n.a, it)
	return eval_node(st, arena, n.a, it)

fn cmp_int(a: Int, b: Int) Int:
	if a < b:
		return -1
	if a > b:
		return 1
	return 0

fn cmp_opt_i(a: Int?, b: Int?) Int:
	if x := a:
		if y := b:
			return cmp_int(x, y)
		return -1
	if b.is_some():
		return 1
	return 0

fn cmp_opt_s(a: String?, b: String?, ci: Bool) Int:
	if x := a:
		if y := b:
			if ci:
				return cmp_int(x.lower().compare(y.lower()), 0)
			return cmp_int(x.compare(y), 0)
		return -1
	if b.is_some():
		return 1
	return 0

fn cmp_field(st: St, a: Issue, b: Issue, f: String) Int:
	if f == "id":
		return cmp_int(a.id, b.id)
	if f == "created":
		return cmp_int(a.created, b.created)
	if f == "updated":
		return cmp_int(a.updated, b.updated)
	if f == "priority":
		return cmp_int(a.priority, b.priority)
	if f == "points":
		return cmp_opt_i(a.points, b.points)
	if f == "state":
		return cmp_int(state_index(st, a.state), state_index(st, b.state))
	if f == "title":
		return cmp_opt_s(a.title, b.title, true)
	if f == "assignee":
		return cmp_opt_s(a.assignee, b.assignee, true)
	if f == "reporter":
		return cmp_opt_s(a.reporter, b.reporter, true)
	if f == "due":
		return cmp_opt_s(a.due, b.due, false)
	return 0

fn exec_query(st: St, filter: String, sort: String?, limit: Int?) List[Int]!:
	var arena = Arena()
	root := parse_filter(st, filter, var arena)?
	var keys = List[SortKey]()
	if s := sort:
		keys = parse_sort(s)?
	var res = List[Int]()
	for i in 0..st.issues.length():
		if st.issues[i].alive and eval_node(st, arena, root, st.issues[i]):
			res.append(i)
	res.sort(fn(x: Int, y: Int) Int: compare_issues(st, keys, x, y))
	if l := limit:
		if res.length() > l:
			var cut = List[Int]()
			for k in 0..l:
				cut.append(res[k])
			res = cut
	return ok(res)

fn compare_issues(st: St, keys: List[SortKey], x: Int, y: Int) Int:
	a := st.issues[x]
	b := st.issues[y]
	for k in keys:
		c := cmp_field(st, a, b, k.field)
		if c != 0:
			return if k.desc: 0 - c else: c
	return cmp_int(a.id, b.id)

fn issue_line(it: Issue) String:
	return "#{it.id} | {it.state} | {prio_name(it.priority)} | {opt_str(it.assignee)} | {opt_int(it.points)} | {opt_str(it.due)} | {labels_str(it.labels, ",")} | {it.title}"

fn print_issues(var st: St, idxs: List[Int]) Unit:
	for i in idxs:
		emit(var st, issue_line(st.issues[i]))
	if idxs.length() == 1:
		emit(var st, "(1 issue)")
	else:
		emit(var st, "({idxs.length()} issues)")

fn cmd_list(var st: St, rest: String) Unit!:
	cl := split_clauses(rest)?
	idxs := exec_query(st, cl.filter, cl.sort, cl.limit)?
	print_issues(var st, idxs)
	return ok(unit)

// ---------- views ----------

fn find_view(st: St, name: String) Int:
	var i = 0
	for v in st.views:
		if v.name == name:
			return i
		i += 1
	return -1

fn view_refs(st: St, query: String) List[String]:
	var arena = Arena()
	cl := split_clauses(query)
	if c := cl:
		r := parse_filter(st, c.filter, var arena)
		if _v := r:
			return arena.refs.clone()
	return List[String]()

fn valid_view_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0:
		return false
	if not (cs[0] >= "a" and cs[0] <= "z"):
		return false
	for c in cs:
		if not ((c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"):
			return false
	return true

fn cmd_view(var st: St, rest: String) Unit!:
	ws := words(rest)
	if ws.length() == 0:
		return error(Error("usage: view save|run|list|show|delete"))
	sub := ws[0]
	if sub == "save":
		if ws.length() < 2:
			return error(Error("usage: view save NAME QUERY"))
		name := ws[1]
		if not valid_view_name(name):
			return error(Error("bad view name '{name}'"))
		query := rest_after_words(rest, 2)
		cl := split_clauses(query)?
		var arena = Arena()
		_r1 := parse_filter(st, cl.filter, var arena)?
		if s := cl.sort:
			_r2 := parse_sort(s)?
		if any_eq_s(arena.refs, name):
			return error(Error("view '{name}' would reference itself"))
		var found = false
		for v in st.views:
			if v.name == name:
				found = true
		if found:
			var nv = List[View]()
			for v in st.views:
				if v.name == name:
					nv.append(View(name.clone(), query.clone()))
				else:
					nv.append(View(v.name.clone(), v.query.clone()))
			st.views = nv
		else:
			st.views.append(View(name.clone(), query.clone()))
		emit(var st, "saved view {name}")
		return ok(unit)
	if sub == "run":
		if ws.length() < 2:
			return error(Error("usage: view run NAME [sort FIELDS] [limit N]"))
		vi := find_view(st, ws[1])
		if vi < 0:
			return error(Error("unknown view '{ws[1]}'"))
		stored := split_clauses(st.views[vi].query)?
		extra := split_clauses(rest_after_words(rest, 2))?
		ft := extra.filter.trim()
		if ft.length() > 0:
			return error(Error("unexpected '{ft}'"))
		var sort: String? = stored.sort.clone()
		if s := extra.sort:
			sort = s.clone()
		var limit: Int? = stored.limit
		if l := extra.limit:
			limit = l
		idxs := exec_query(st, stored.filter, sort, limit)?
		print_issues(var st, idxs)
		return ok(unit)
	if sub == "list":
		if ws.length() != 1:
			return error(Error("usage: view save|run|list|show|delete"))
		if st.views.length() == 0:
			emit(var st, "(no views)")
			return ok(unit)
		var names = List[String]()
		for v in st.views:
			names.append(v.name.clone())
		names.sort()
		for nm in names:
			emit(var st, "{nm}: {st.views[find_view(st, nm)].query}")
		return ok(unit)
	if sub == "show":
		if ws.length() != 2:
			return error(Error("usage: view show NAME"))
		vi := find_view(st, ws[1])
		if vi < 0:
			return error(Error("unknown view '{ws[1]}'"))
		emit(var st, "{ws[1]}: {st.views[vi].query}")
		return ok(unit)
	if sub == "delete":
		if ws.length() != 2:
			return error(Error("usage: view delete NAME"))
		name := ws[1]
		vi := find_view(st, name)
		if vi < 0:
			return error(Error("unknown view '{name}'"))
		var names = List[String]()
		for v in st.views:
			names.append(v.name.clone())
		names.sort()
		for nm in names:
			if nm != name:
				if any_eq_s(view_refs(st, st.views[find_view(st, nm)].query), name):
					return error(Error("view '{name}' is used by '{nm}'"))
		var nv = List[View]()
		for v in st.views:
			if v.name != name:
				nv.append(View(v.name.clone(), v.query.clone()))
		st.views = nv
		emit(var st, "deleted view {name}")
		return ok(unit)
	return error(Error("usage: view save|run|list|show|delete"))

// ---------- commands ----------

fn cmd_create(var st: St, rest: String) Unit!:
	if st.initial.length() == 0:
		return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.length() == 0:
		return error(Error("usage: create TITLE [field=value...]"))
	title := toks[0]
	if title.trim().length() == 0:
		return error(Error("empty title"))
	var f = Fields(title.clone(), 1, none, none, none, List[String](), st.actor.clone())
	var rep_given = false
	for i in 1..toks.length():
		apply_token(var f, toks[i])?
		if toks[i].starts_with("reporter="):
			rep_given = true
	var base = Fields(title.clone(), 1, none, none, none, List[String](), none)
	if not rep_given:
		base.reporter = st.actor.clone()
	st.clock += 1
	id := st.issues.length() + 1
	var it = Issue(id, f.title.clone(), st.initial.clone())
	it.priority = f.priority
	it.assignee = f.assignee.clone()
	it.points = f.points
	it.due = f.due.clone()
	it.labels = f.labels.clone()
	it.reporter = f.reporter.clone()
	it.created = st.clock
	it.updated = st.clock
	it.hist_state.append(st.initial.clone())
	it.hist_t.append(st.clock)
	st.issues.append(it)
	add_log(var st, id, "created \"{title}\"")
	log_diffs(var st, id, base, f)
	emit(var st, "created #{id}")
	return ok(unit)

fn cmd_edit(var st: St, rest: String) Unit!:
	toks := tokenize(rest)?
	if toks.length() == 0:
		return error(Error("usage: edit ID field=value..."))
	idx := find_issue(st, toks[0])?
	var fl = List[String]()
	for i in 1..toks.length():
		fl.append(toks[i].clone())
	r := edit_issue(var st, idx, fl)?
	emit(var st, r)
	return ok(unit)

fn cmd_label(var st: St, rest: String) Unit!:
	toks := tokenize(rest)?
	if toks.length() < 2:
		return error(Error("usage: label ID +label -label..."))
	idx := find_issue(st, toks[0])?
	var fl = List[String]()
	for i in 1..toks.length():
		fl.append(toks[i].clone())
	r := label_issue(var st, idx, fl)?
	emit(var st, r)
	return ok(unit)

fn cmd_assign(var st: St, rest: String) Unit!:
	toks := tokenize(rest)?
	if toks.length() != 2:
		return error(Error("usage: assign ID NAME"))
	idx := find_issue(st, toks[0])?
	r := edit_issue(var st, idx, ["assignee={toks[1]}"])?
	emit(var st, r)
	return ok(unit)

fn cmd_move(var st: St, rest: String) Unit!:
	ws := words(rest)
	if ws.length() < 2:
		return error(Error("usage: move ID STATE [comment...]"))
	idx := find_issue(st, ws[0])?
	r := move_issue(var st, idx, ws[1], rest_after_words(rest, 2))?
	emit(var st, r)
	return ok(unit)

fn cmd_comment(var st: St, rest: String) Unit!:
	ws := words(rest)
	if ws.length() < 2:
		return error(Error("usage: comment ID TEXT"))
	idx := find_issue(st, ws[0])?
	text := rest_after_words(rest, 1)
	st.clock += 1
	id := st.issues[idx].id
	st.issues[idx].updated = st.clock
	st.issues[idx].comments.append(Comment(st.clock, st.actor.clone(), text.clone()))
	add_log(var st, id, "comment: {text}")
	emit(var st, "commented #{id}")
	return ok(unit)

fn cmd_delete(var st: St, rest: String) Unit!:
	ws := words(rest)
	if ws.length() != 1:
		return error(Error("usage: delete ID"))
	idx := find_issue(st, ws[0])?
	st.clock += 1
	id := st.issues[idx].id
	st.issues[idx].alive = false
	add_log(var st, id, "deleted")
	emit(var st, "deleted #{id}")
	return ok(unit)

fn cmd_show(var st: St, rest: String) Unit!:
	ws := words(rest)
	if ws.length() != 1:
		return error(Error("usage: show ID"))
	idx := find_issue(st, ws[0])?
	it := st.issues[idx].clone()
	emit(var st, "#{it.id} {it.title}")
	emit(var st, "  state: {it.state}")
	emit(var st, "  priority: {prio_name(it.priority)}")
	emit(var st, "  assignee: {opt_str(it.assignee)}")
	emit(var st, "  points: {opt_int(it.points)}")
	emit(var st, "  due: {opt_str(it.due)}")
	emit(var st, "  labels: {labels_str(it.labels, ", ")}")
	emit(var st, "  reporter: {opt_str(it.reporter)}")
	emit(var st, "  created: t={it.created}, updated: t={it.updated}")
	emit(var st, "  comments: {it.comments.length()}")
	for c in it.comments:
		emit(var st, "    [t={c.t} {c.actor}] {c.text}")
	return ok(unit)

fn cmd_log(var st: St, rest: String) Unit!:
	ws := words(rest)
	var filter_id = -1
	var tail = -1
	var i = 0
	if ws.length() > 0 and ws[0] != "tail":
		if ws.length() > 3 or (ws.length() == 3 and ws[1] != "tail") or ws.length() == 2:
			return error(Error("usage: log [ID] [tail N]"))
		i = 1
	else:
		if ws.length() != 0 and ws.length() != 2:
			return error(Error("usage: log [ID] [tail N]"))
	if i == 1:
		arg := ws[0]
		var d = arg.clone()
		if d.starts_with("#"):
			d = d.slice(1, d.length())?
		var allnum = d.length() > 0
		for c in d.chars():
			if not is_digit(c):
				allnum = false
		var v = 0
		if allnum:
			for c in d.chars():
				if v < 1000000000000:
					v = v * 10 + c.parse_int().get(0)
		if not allnum or v < 1:
			return error(Error("bad issue id '{arg}'"))
		if v > st.issues.length():
			return error(Error("no such issue #{v}"))
		filter_id = v
	if ws.length() >= 2:
		targ := ws[ws.length() - 1]
		tv := parse_num(targ)
		if tv.is_none():
			return error(Error("bad tail '{targ}'"))
		tail = tv.get(0)
	var sel = List[Int]()
	for j in 0..st.log.length():
		if filter_id < 0 or st.log[j].id == filter_id:
			sel.append(j)
	var start = 0
	if tail >= 0 and sel.length() > tail:
		start = sel.length() - tail
	if sel.length() - start == 0:
		emit(var st, "(no log entries)")
		return ok(unit)
	for k in start..sel.length():
		e := st.log[sel[k]].clone()
		emit(var st, "t={e.t} {e.actor} #{e.id} {e.detail}")
	return ok(unit)

// ---------- reports ----------

fn plural(n: Int, w: String) String:
	if n == 1:
		return "{n} {w}"
	return "{n} {w}s"

type WL:
	name: String
	count: Int
	points: Int

fn cmd_report(var st: St, rest: String) Unit!:
	ws := words(rest)
	usage := Error("usage: report summary|workload|labels|timeline")
	if ws.length() == 0:
		return error(usage)
	sub := ws[0]
	if sub == "summary":
		var total = 0
		var open = 0
		var unassigned = 0
		var overdue = 0
		var points = 0
		var by_state = List[Int]()
		for s in st.states:
			by_state.append(0)
		var by_prio = [0, 0, 0, 0]
		for it in st.issues:
			if not it.alive:
				continue
			total += 1
			si := state_index(st, it.state)
			if si >= 0:
				by_state[si] += 1
			by_prio[it.priority] += 1
			if not is_final(st, it.state):
				open += 1
				if it.assignee.is_none():
					unassigned += 1
				if d := it.due:
					if d < st.today:
						overdue += 1
				points += it.points.get(0)
		emit(var st, "issues: {total} (open {open}, final {total - open})")
		emit(var st, "by state:")
		for i in 0..st.states.length():
			emit(var st, "  {st.states[i]}: {by_state[i]}")
		emit(var st, "by priority:")
		emit(var st, "  critical: {by_prio[3]}")
		emit(var st, "  high: {by_prio[2]}")
		emit(var st, "  medium: {by_prio[1]}")
		emit(var st, "  low: {by_prio[0]}")
		emit(var st, "unassigned: {unassigned}")
		emit(var st, "overdue: {overdue}")
		emit(var st, "open points: {points}")
		return ok(unit)
	if sub == "workload":
		var groups = List[WL]()
		var un = WL("unassigned", 0, 0)
		for it in st.issues:
			if not it.alive or is_final(st, it.state):
				continue
			if a := it.assignee:
				al := a.lower()
				var found = false
				for gi in 0..groups.length():
					if groups[gi].name.lower() == al:
						groups[gi].count += 1
						groups[gi].points += it.points.get(0)
						found = true
				if not found:
					groups.append(WL(a.clone(), 1, it.points.get(0)))
			else:
				un.count += 1
				un.points += it.points.get(0)
		if groups.length() == 0 and un.count == 0:
			emit(var st, "(no open issues)")
			return ok(unit)
		groups.sort(fn(x: WL, y: WL) Int: wl_cmp(x, y))
		for g in groups:
			emit(var st, "{g.name}: {plural(g.count, "issue")}, {g.points} points")
		if un.count > 0:
			emit(var st, "unassigned: {plural(un.count, "issue")}, {un.points} points")
		return ok(unit)
	if sub == "labels":
		filter := rest_after_words(rest, 1)
		var arena = Arena()
		root := parse_filter(st, filter, var arena)?
		var names = List[String]()
		var counts = List[Int]()
		for it in st.issues:
			if it.alive and eval_node(st, arena, root, it):
				for l in it.labels:
					var found = false
					for k in 0..names.length():
						if names[k] == l:
							counts[k] += 1
							found = true
					if not found:
						names.append(l.clone())
						counts.append(1)
		if names.length() == 0:
			emit(var st, "(no labels)")
			return ok(unit)
		var order = List[Int]()
		for k in 0..names.length():
			order.append(k)
		order.sort(fn(x: Int, y: Int) Int: lbl_cmp(names, counts, x, y))
		for k in order:
			emit(var st, "{names[k]}: {counts[k]}")
		return ok(unit)
	if sub == "timeline":
		if ws.length() != 2:
			return error(Error("usage: report timeline ID"))
		idx := find_issue(st, ws[1])?
		it := st.issues[idx].clone()
		for k in 0..it.hist_state.length():
			from := it.hist_t[k]
			to := if k + 1 < it.hist_t.length(): it.hist_t[k + 1] else: st.clock
			emit(var st, "{it.hist_state[k]}: t={from}..{to} ({to - from})")
		return ok(unit)
	return error(usage)

fn wl_cmp(x: WL, y: WL) Int:
	if x.points != y.points:
		return cmp_int(y.points, x.points)
	if x.count != y.count:
		return cmp_int(y.count, x.count)
	return cmp_int(x.name.lower().compare(y.name.lower()), 0)

fn lbl_cmp(names: List[String], counts: List[Int], x: Int, y: Int) Int:
	if counts[x] != counts[y]:
		return cmp_int(counts[y], counts[x])
	return cmp_int(names[x].compare(names[y]), 0)

// ---------- workflow ----------

fn reg_state(var states: List[String], s: String) Unit:
	for x in states:
		if x == s:
			return
	states.append(s.clone())

fn parse_workflow(var st: St, lines: List[String]) String!:
	var states = List[String]()
	var finals = List[String]()
	var trans = List[Trans]()
	var initial = ""
	var have_initial = false
	var count = 0
	for raw in lines:
		line := raw.trim()
		if line.length() == 0 or line.starts_with("#"):
			continue
		bad_line := Error("workflow: bad line '{line}'")
		if line.starts_with("initial:"):
			name := (line.slice(8, line.length())?).trim()
			if name.length() > 0 and words(name).length() > 1:
				return error(bad_line)
			if not valid_state_name(name):
				return error(Error("workflow: bad state name '{name}'"))
			if have_initial:
				return error(Error("workflow: initial state defined twice"))
			have_initial = true
			initial = name.clone()
			reg_state(var states, name)
		else if line.starts_with("final:"):
			rest := line.slice(6, line.length())?
			for p in split_on(rest, ","):
				name := p.trim()
				if not valid_state_name(name):
					return error(Error("workflow: bad state name '{name}'"))
				reg_state(var states, name)
				finals.append(name.clone())
		else if line.contains("->"):
			ai := line.index_of("->").get(0)
			src := (line.slice(0, ai)?).trim()
			rhs := line.slice(ai + 2, line.length())?
			if words(src).length() > 1:
				return error(bad_line)
			if not valid_state_name(src):
				return error(Error("workflow: bad state name '{src}'"))
			reg_state(var states, src)
			for p in split_on(rhs, ","):
				ew := words(p)
				if ew.length() != 1 and ew.length() != 3:
					return error(bad_line)
				if ew.length() == 3 and ew[1] != "requires":
					return error(bad_line)
				if not valid_state_name(ew[0]):
					return error(Error("workflow: bad state name '{ew[0]}'"))
				var guards = List[String]()
				if ew.length() == 3:
					for g in split_on(ew[2], "+"):
						if g != "assignee" and g != "points" and g != "due" and g != "labels" and g != "reporter":
							return error(Error("workflow: bad guard field '{g}'"))
						guards.append(g.clone())
				reg_state(var states, ew[0])
				trans.append(Trans(src.clone(), ew[0].clone(), guards))
				count += 1
		else:
			return error(bad_line)
	if not have_initial:
		return error(Error("workflow: initial state missing"))
	for tr in trans:
		if any_eq_s(finals, tr.src):
			return error(Error("workflow: '{tr.src}' is final and cannot have transitions"))
	st.states = states
	st.finals = finals
	st.trans = trans
	st.initial = initial
	return ok("workflow ok: {st.states.length()} states, {count} transitions")

// ---------- bulk ----------

fn cmd_bulk(var st: St, rest: String) Unit!:
	usage := Error("usage: bulk ACTION... where QUERY")
	cs := rest.chars()
	n := cs.length()
	var wi = -1
	var i = 0
	while i + 5 <= n:
		if word_start_at(cs, i, "where") and (i + 5 == n or is_ws(cs[i + 5])):
			wi = i
			break
		i += 1
	if wi < 0:
		return error(usage)
	action_text := join_range(cs, 0, wi)
	query := join_range(cs, wi + 5, n)
	if words(action_text).length() == 0:
		return error(usage)
	toks := tokenize(action_text)?
	act := toks[0]
	if act == "move":
		if toks.length() != 2:
			return error(Error("usage: bulk move STATE where QUERY"))
	else if act == "assign":
		if toks.length() != 2:
			return error(Error("usage: bulk assign NAME where QUERY"))
	else if act == "label":
		if toks.length() < 2:
			return error(Error("usage: bulk label +label... where QUERY"))
	else if act == "set":
		if toks.length() < 2:
			return error(Error("usage: bulk set field=value... where QUERY"))
	else:
		return error(Error("unknown bulk action '{act}'"))
	idxs := exec_query(st, query, none, none)?
	var okc = 0
	var failc = 0
	var args = List[String]()
	for k in 1..toks.length():
		args.append(toks[k].clone())
	for idx in idxs:
		id := st.issues[idx].id
		var r: String! = ok("")
		if act == "move":
			r = move_issue(var st, idx, args[0], "")
		else if act == "assign":
			r = edit_issue(var st, idx, ["assignee={args[0]}"])
		else if act == "label":
			r = label_issue(var st, idx, args)
		else:
			r = edit_issue(var st, idx, args)
		if line := r:
			emit(var st, line)
			okc += 1
		else:
			emit(var st, "#{id} error: {r.err().message}")
			failc += 1
	emit(var st, "bulk: {okc} ok, {failc} failed")
	return ok(unit)

// ---------- main ----------

fn run_cmd(var st: St, word: String, rest: String) Unit!:
	if word == "actor":
		ws := words(rest)
		if ws.length() != 1:
			return error(Error("usage: actor NAME"))
		st.actor = ws[0].clone()
		emit(var st, "actor is {ws[0]}")
	else if word == "today":
		ws := words(rest)
		if ws.length() != 1:
			return error(Error("usage: today DATE"))
		if not valid_date(ws[0]):
			return error(Error("bad date '{ws[0]}'"))
		st.today = ws[0].clone()
		emit(var st, "today is {ws[0]}")
	else if word == "create":
		cmd_create(var st, rest)?
	else if word == "edit":
		cmd_edit(var st, rest)?
	else if word == "label":
		cmd_label(var st, rest)?
	else if word == "assign":
		cmd_assign(var st, rest)?
	else if word == "move":
		cmd_move(var st, rest)?
	else if word == "comment":
		cmd_comment(var st, rest)?
	else if word == "delete":
		cmd_delete(var st, rest)?
	else if word == "show":
		cmd_show(var st, rest)?
	else if word == "list":
		cmd_list(var st, rest)?
	else if word == "view":
		cmd_view(var st, rest)?
	else if word == "bulk":
		cmd_bulk(var st, rest)?
	else if word == "log":
		cmd_log(var st, rest)?
	else if word == "report":
		cmd_report(var st, rest)?
	else:
		return error(Error("unknown command '{word}'"))
	return ok(unit)

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	lines := text.split("\n")
	var st = St()
	var i = 0
	while i < lines.length():
		line := lines[i].trim_end()
		i += 1
		tl := line.trim()
		if tl.length() == 0 or tl.starts_with("#"):
			continue
		emit(var st, "> {line}")
		ws := words(line)
		word := ws[0]
		rest := rest_after_words(line, 1)
		if word == "workflow":
			var block = List[String]()
			while i < lines.length():
				bl := lines[i]
				i += 1
				if bl.trim() == "end":
					break
				block.append(bl.clone())
			if st.issues.length() > 0:
				emit(var st, "error: workflow: cannot redefine after issues were created")
			else:
				r := parse_workflow(var st, block)
				if m := r:
					emit(var st, m)
				else:
					emit(var st, "error: {r.err().message}")
			continue
		res := run_cmd(var st, word, rest)
		if _u := res:
			i += 0
		else:
			emit(var st, "error: {res.err().message}")
	print(st.out.join("\n"))
