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
	reporter: String = ""
	points: Int = -1
	due: String = ""
	labels: List[String] = []
	comments: List[Comment] = []
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

type Patch:
	title: String? = none
	priority: Int? = none
	assignee: String? = none
	points: Int? = none
	due: String? = none
	labels: List[String]? = none
	reporter: String? = none
	err: String = ""

type Node:
	kind: Int
	a: Int = -1
	b: Int = -1
	field: String = ""
	op: String = ""
	alts: List[String] = []

type Query:
	nodes: List[Node] = []
	root: Int = -1
	err: String = ""
	refs: List[String] = []

type QTok:
	kind: Int
	text: String = ""
	field: String = ""
	op: String = ""
	value: String = ""
	quoted: Bool = false

type QSplit:
	filter: String = ""
	has_sort: Bool = false
	sort_text: String = ""
	limit: Int = -1
	err: String = ""

type SortSpec:
	fields: List[String] = []
	desc: List[Bool] = []
	err: String = ""

type Toks:
	items: List[String] = []
	err: String = ""

type IdRes:
	idx: Int = -1
	id: Int = 0
	err: String = ""

type App:
	out: List[String] = []
	t: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	next_id: Int = 1
	issues: List[Issue] = []
	log: List[LogEntry] = []
	states: List[String] = []
	finals: List[String] = []
	initial: String = ""
	has_wf: Bool = false
	trans: List[Trans] = []
	views: Map[String, String] = Map[String, String]()

// ---------- helpers ----------

fn is_ws(c: String) Bool:
	return c == " " or c == "\t" or c == "\r" or c == "\n"

fn is_digit(c: String) Bool:
	return c >= "0" and c <= "9"

fn join_chars(cs: List[String], a: Int, b: Int) String:
	var s = ""
	for i in a..b:
		s += cs[i]
	return s

fn rest_after(s: String, n: Int) String:
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
	return join_chars(cs, i, cs.length())

fn tokenize(s: String) Toks:
	var res = Toks()
	cs := s.chars()
	var cur = ""
	var started = false
	var inq = false
	var i = 0
	while i < cs.length():
		c := cs[i]
		if inq:
			if c == "\\" and i + 1 < cs.length() and (cs[i + 1] == "\"" or cs[i + 1] == "\\"):
				cur += cs[i + 1]
				i += 1
			else if c == "\"":
				inq = false
			else:
				cur += c
		else:
			if c == "\"":
				inq = true
				started = true
			else if is_ws(c):
				if started:
					res.items.append(cur.clone())
					cur = ""
					started = false
			else:
				cur += c
				started = true
		i += 1
	if inq:
		res.err = "unterminated quote"
		return res
	if started:
		res.items.append(cur.clone())
	return res

fn parse_uint(s: String) Int:
	// returns -1 when not a valid integer per the spec
	if s.length() == 0 or s.length() > 7: return -1
	cs := s.chars()
	for c in cs:
		if not is_digit(c): return -1
	if s.length() > 1 and cs[0] == "0": return -1
	v := s.parse_int().get(-1)
	if v > 1000000: return -1
	return v

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false
	for i in 0..10:
		if i == 4 or i == 7:
			if cs[i] != "-": return false
		else:
			if not is_digit(cs[i]): return false
	y := join_chars(cs, 0, 4).parse_int().get(0)
	m := join_chars(cs, 5, 7).parse_int().get(0)
	d := join_chars(cs, 8, 10).parse_int().get(0)
	if y < 1 or m < 1 or m > 12 or d < 1: return false
	var dim = 31
	if m == 4 or m == 6 or m == 9 or m == 11:
		dim = 30
	else if m == 2:
		leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
		dim = if leap: 29 else: 28
	return d <= dim

fn valid_label(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		ok := (c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"
		if not ok: return false
	return true

fn valid_state_name(s: String) Bool:
	if s.length() == 0: return false
	cs := s.chars()
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or is_digit(c) or c == "_"
		if not ok: return false
	return true

fn valid_view_name(s: String) Bool:
	if s.length() == 0: return false
	cs := s.chars()
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or is_digit(c) or c == "_" or c == "-"
		if not ok: return false
	return true

fn prio_name(p: Int) String:
	if p == 0: return "low"
	if p == 1: return "medium"
	if p == 2: return "high"
	return "critical"

fn prio_rank(s: String) Int:
	if s == "low": return 0
	if s == "medium": return 1
	if s == "high": return 2
	if s == "critical": return 3
	return -1

fn dash(s: String) String:
	if s == "": return "-"
	return s.clone()

fn pts(p: Int) String:
	if p < 0: return "-"
	return "{p}"

fn labels_str(ls: List[String]) String:
	if ls.length() == 0: return "-"
	return ls.join(",")

fn sorted_labels(ls: List[String]) List[String]:
	var out = List[String]()
	for l in ls:
		if not out.contains(l): out.append(l.clone())
	return out.sorted()

fn contains_str(hay: String, needle: String) Bool:
	return hay.contains(needle)

fn Issue.line() String:
	return "#{self.id} | {self.state} | {prio_name(self.priority)} | {dash(self.assignee)} | {pts(self.points)} | {dash(self.due)} | {labels_str(self.labels)} | {self.title}"

// ---------- patches ----------

fn parse_patch(toks: List[String], start: Int) Patch:
	var p = Patch()
	for i in start..toks.length():
		tok := toks[i]
		eq := tok.index_of("=").get(-1)
		if eq <= 0:
			p.err = "expected field=value, got '{tok}'"
			return p
		field := tok.slice(0, eq).get("")
		value := tok.slice(eq + 1, tok.length()).get("")
		if field == "state":
			p.err = "use move to change state"
			return p
		if field == "title":
			if value.trim() == "":
				p.err = "empty title"
				return p
			p.title = value.clone()
		else if field == "priority":
			r := prio_rank(value)
			if r < 0:
				p.err = "bad priority '{value}'"
				return p
			p.priority = r
		else if field == "assignee":
			if value == "none":
				p.assignee = ""
			else if value.trim() == "":
				p.err = "empty assignee"
				return p
			else:
				p.assignee = value.clone()
		else if field == "reporter":
			if value == "none":
				p.reporter = ""
			else if value.trim() == "":
				p.err = "empty reporter"
				return p
			else:
				p.reporter = value.clone()
		else if field == "points":
			if value == "none":
				p.points = -1
			else:
				v := parse_uint(value)
				if v < 0:
					p.err = "bad points '{value}'"
					return p
				p.points = v
		else if field == "due":
			if value == "none":
				p.due = ""
			else if valid_date(value):
				p.due = value.clone()
			else:
				p.err = "bad date '{value}'"
				return p
		else if field == "labels":
			var ls = List[String]()
			if value != "none":
				for part in value.split(","):
					l := part.lower()
					if not valid_label(l):
						p.err = "bad label '{l}'"
						return p
					ls.append(l)
			p.labels = sorted_labels(ls)
		else:
			p.err = "unknown field '{field}'"
			return p
	return p

fn patch_diffs(is: Issue, p: Patch) List[String]:
	var d = List[String]()
	if t := p.title:
		if t != is.title: d.append("title: {is.title} -> {t}")
	if v := p.priority:
		if v != is.priority: d.append("priority: {prio_name(is.priority)} -> {prio_name(v)}")
	if v := p.assignee:
		if v != is.assignee: d.append("assignee: {dash(is.assignee)} -> {dash(v)}")
	if v := p.points:
		if v != is.points: d.append("points: {pts(is.points)} -> {pts(v)}")
	if v := p.due:
		if v != is.due: d.append("due: {dash(is.due)} -> {dash(v)}")
	if v := p.labels:
		if v != is.labels: d.append("labels: {labels_str(is.labels)} -> {labels_str(v)}")
	if v := p.reporter:
		if v != is.reporter: d.append("reporter: {dash(is.reporter)} -> {dash(v)}")
	return d

fn var Issue.apply(p: Patch) Unit:
	if t := p.title:
		self.title = t.clone()
	if v := p.priority:
		self.priority = v
	if v := p.assignee:
		self.assignee = v.clone()
	if v := p.points:
		self.points = v
	if v := p.due:
		self.due = v.clone()
	if v := p.labels:
		self.labels = v.clone()
	if v := p.reporter:
		self.reporter = v.clone()

// ---------- query parsing ----------

fn lex_query(s: String) List[QTok]!:
	var toks = List[QTok]()
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		if is_ws(c):
			i += 1
			continue
		if c == "(":
			toks.append(QTok(0))
			i += 1
			continue
		if c == ")":
			toks.append(QTok(1))
			i += 1
			continue
		var j = i
		while j < n and cs[j] >= "a" and cs[j] <= "z" or (j < n and cs[j] == "_"):
			j += 1
		var op = ""
		if j > i and j < n:
			c1 := cs[j]
			c2 := if j + 1 < n: cs[j + 1].clone() else: ""
			if c1 == "!" and c2 == "=": op = "!="
			else if c1 == "<" and c2 == "=": op = "<="
			else if c1 == ">" and c2 == "=": op = ">="
			else if c1 == ":": op = ":"
			else if c1 == "<": op = "<"
			else if c1 == ">": op = ">"
			else if c1 == "~": op = "~"
		if op != "":
			field := join_chars(cs, i, j)
			var k = j + op.length()
			var value = ""
			var quoted = false
			if k < n and cs[k] == "\"":
				quoted = true
				k += 1
				var closed = false
				while k < n:
					d := cs[k]
					if d == "\\" and k + 1 < n and (cs[k + 1] == "\"" or cs[k + 1] == "\\"):
						value += cs[k + 1]
						k += 2
						continue
					if d == "\"":
						closed = true
						k += 1
						break
					value += d
					k += 1
				if not closed:
					return error(Error("query: unterminated quote"))
			else:
				while k < n and not is_ws(cs[k]) and cs[k] != "(" and cs[k] != ")":
					value += cs[k]
					k += 1
			toks.append(QTok(5, field: field, op: op, value: value, quoted: quoted))
			i = k
			continue
		var k = i
		while k < n and not is_ws(cs[k]) and cs[k] != "(" and cs[k] != ")":
			k += 1
		w := join_chars(cs, i, k)
		if w == "AND": toks.append(QTok(2, text: w))
		else if w == "OR": toks.append(QTok(3, text: w))
		else if w == "NOT": toks.append(QTok(4, text: w))
		else: toks.append(QTok(6, text: w))
		i = k
	return ok(toks)

type QP:
	toks: List[QTok]
	pos: Int = 0
	nodes: List[Node] = []
	err: String = ""
	refs: List[String] = []
	views: Map[String, String] = Map[String, String]()
	states: List[String] = []

fn var QP.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var QP.fail(msg: String) Int:
	if self.err == "": self.err = msg
	return -1

fn var QP.end_err() Int:
	return self.fail("query: unexpected end of query")

fn var QP.p_or() Int:
	left := self.p_and()
	if self.err != "": return -1
	var cur = left
	while self.pos < self.toks.length() and self.toks[self.pos].kind == 3:
		self.pos += 1
		right := self.p_and()
		if self.err != "": return -1
		cur = self.add(Node(2, a: cur, b: right))
	return cur

fn var QP.p_and() Int:
	left := self.p_not()
	if self.err != "": return -1
	var cur = left
	while self.pos < self.toks.length():
		k := self.toks[self.pos].kind
		if k == 2:
			self.pos += 1
		else if k == 0 or k == 4 or k == 5 or k == 6:
			var _x = 0
		else:
			break
		right := self.p_not()
		if self.err != "": return -1
		cur = self.add(Node(1, a: cur, b: right))
	return cur

fn var QP.p_not() Int:
	if self.pos >= self.toks.length(): return self.end_err()
	if self.toks[self.pos].kind == 4:
		self.pos += 1
		inner := self.p_not()
		if self.err != "": return -1
		return self.add(Node(3, a: inner))
	return self.p_primary()

fn var QP.p_primary() Int:
	if self.pos >= self.toks.length(): return self.end_err()
	k := self.toks[self.pos].kind
	if k == 0:
		self.pos += 1
		r := self.p_or()
		if self.err != "": return -1
		if self.pos >= self.toks.length(): return self.end_err()
		if self.toks[self.pos].kind != 1:
			return self.fail("query: unexpected token '{self.toks[self.pos].text}'")
		self.pos += 1
		return r
	if k == 5:
		t := self.toks[self.pos].clone()
		self.pos += 1
		return self.make_term(t)
	if k == 1:
		return self.fail("query: unexpected token ')'")
	return self.fail("query: unexpected token '{self.toks[self.pos].text}'")

fn op_in(op: String, ops: List[String]) Bool:
	return ops.contains(op)

fn var QP.bad_value(v: String, field: String) Int:
	return self.fail("query: bad value '{v}' for field '{field}'")

fn var QP.make_term(t: QTok) Int:
	f := t.field
	op := t.op
	cmp_ops := [":", "!=", "<", "<=", ">", ">="]
	str_ops := [":", "!=", "~"]
	var allowed = List[String]()
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "priority" or f == "due":
		allowed = cmp_ops.clone()
	else if f == "title" or f == "assignee" or f == "reporter" or f == "label" or f == "labels":
		allowed = str_ops.clone()
	else if f == "text":
		allowed = ["~"]
	else if f == "state":
		allowed = [":", "!="]
	else if f == "is" or f == "has" or f == "view":
		allowed = [":"]
	else:
		return self.fail("query: unknown field '{f}'")
	if not op_in(op, allowed):
		return self.fail("query: bad operator '{op}' for field '{f}'")
	if f == "view":
		if not self.views.contains(t.value):
			return self.fail("query: unknown view '{t.value}'")
		self.refs.append(t.value.clone())
		stored := self.views.get_or(t.value, "")
		sp := split_query(stored)
		sub := compile_filter(sp.filter, self.views, self.states)
		if sub.err != "": return self.fail(sub.err)
		off := self.nodes.length()
		for n in sub.nodes:
			var m = n.clone()
			if m.kind == 1 or m.kind == 2:
				m.a += off
				m.b += off
			else if m.kind == 3:
				m.a += off
			self.nodes.append(m)
		return sub.root + off
	var alts = List[String]()
	list_ok := (op == ":" or op == "!=" or op == "~") and not t.quoted
	if list_ok and t.value.contains("|"):
		alts = t.value.clone().split("|")
	else:
		alts = [t.value.clone()]
	var out = List[String]()
	for a in alts:
		if f == "id" or f == "created" or f == "updated":
			if parse_uint(a) < 0: return self.bad_value(a, f)
			out.append(a.clone())
		else if f == "points":
			ordered := op != ":" and op != "!="
			if a == "none" and not ordered:
				out.append(a.clone())
			else:
				if parse_uint(a) < 0: return self.bad_value(a, f)
				out.append(a.clone())
		else if f == "priority":
			if prio_rank(a) < 0: return self.bad_value(a, f)
			out.append(a.clone())
		else if f == "due":
			ordered := op != ":" and op != "!="
			if a == "none" and not ordered:
				out.append(a.clone())
			else:
				if not valid_date(a): return self.bad_value(a, f)
				out.append(a.clone())
		else if f == "state":
			if not self.states.contains(a): return self.bad_value(a, f)
			out.append(a.clone())
		else if f == "is":
			if not ["open", "final", "overdue", "unassigned"].contains(a): return self.bad_value(a, f)
			out.append(a.clone())
		else if f == "has":
			if not ["assignee", "due", "points", "labels", "comments", "reporter"].contains(a): return self.bad_value(a, f)
			out.append(a.clone())
		else:
			out.append(a.lower())
	return self.add(Node(0, field: f.clone(), op: op.clone(), alts: out))

fn compile_filter(text: String, views: Map[String, String], states: List[String]) Query:
	var q = Query()
	lexed := lex_query(text)
	if toks := lexed:
		var p = QP(toks.clone(), views: views.clone(), states: states.clone())
		if p.toks.length() == 0:
			q.nodes.append(Node(5))
			q.root = 0
			return q
		r := p.p_or()
		if p.err == "" and p.pos < p.toks.length():
			p.fail("query: unexpected token '{p.toks[p.pos].text}'")
			if p.toks[p.pos].kind == 1:
				p.err = "query: unexpected token ')'"
		if p.err != "":
			q.err = p.err.clone()
			return q
		q.nodes = p.nodes.clone()
		q.root = r
		q.refs = p.refs.clone()
		return q
	else:
		q.err = lexed.err().message
		return q

fn split_query(raw: String) QSplit:
	var r = QSplit()
	cs := raw.chars()
	end := cs.length()
	var rest_end = end
	// limit
	var j = end
	while j > 0 and not is_ws(cs[j - 1]):
		j -= 1
	if j > 0:
		var k = j
		while k > 0 and is_ws(cs[k - 1]):
			k -= 1
		var m = k
		while m > 0 and not is_ws(cs[m - 1]):
			m -= 1
		if join_chars(cs, m, k) == "limit" and k < j:
			arg := join_chars(cs, j, end)
			v := parse_uint(arg)
			if v < 0:
				r.err = "bad limit '{arg}'"
				return r
			r.limit = v
			rest_end = m
	// sort
	var p = 0
	var found = -1
	while p + 4 <= rest_end:
		if join_chars(cs, p, p + 4) == "sort":
			before := p == 0 or is_ws(cs[p - 1])
			after := p + 4 < rest_end and is_ws(cs[p + 4])
			if before and after:
				found = p
				break
		p += 1
	if found >= 0:
		r.has_sort = true
		r.sort_text = join_chars(cs, found + 4, rest_end)
		r.filter = join_chars(cs, 0, found).trim()
	else:
		r.filter = join_chars(cs, 0, rest_end).trim()
	return r

fn parse_sort(text: String) SortSpec:
	var s = SortSpec()
	valid := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	for w in text.replace(",", " ").fields():
		var name = w.clone()
		var d = false
		if w.starts_with("-"):
			d = true
			name = w.slice(1, w.length()).get("")
		if not valid.contains(name):
			s.err = "bad sort field '{name}'"
			return s
		s.fields.append(name)
		s.desc.append(d)
	return s

// ---------- evaluation ----------

fn App.is_final(state: String) Bool:
	return self.finals.contains(state)

fn App.state_index(state: String) Int:
	for i in 0..self.states.length():
		if self.states[i] == state: return i
	return -1

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn App.eval_term(n: Node, is: Issue) Bool:
	f := n.field
	op := n.op
	if f == "id" or f == "created" or f == "updated" or f == "points":
		var x = is.id
		if f == "created": x = is.created
		if f == "updated": x = is.updated
		if f == "points": x = is.points
		var any = false
		for a in n.alts:
			if f == "points" and a == "none":
				if is.points < 0: any = true
				continue
			if f == "points" and is.points < 0:
				continue
			v := parse_uint(a)
			c := cmp_int(x, v)
			if op == ":" or op == "!=":
				if c == 0: any = true
			else if op == "<":
				if c < 0: any = true
			else if op == "<=":
				if c <= 0: any = true
			else if op == ">":
				if c > 0: any = true
			else:
				if c >= 0: any = true
		if op == "!=": return not any
		return any
	if f == "priority":
		var any = false
		for a in n.alts:
			c := cmp_int(is.priority, prio_rank(a))
			if op == ":" or op == "!=":
				if c == 0: any = true
			else if op == "<":
				if c < 0: any = true
			else if op == "<=":
				if c <= 0: any = true
			else if op == ">":
				if c > 0: any = true
			else:
				if c >= 0: any = true
		if op == "!=": return not any
		return any
	if f == "due":
		var any = false
		for a in n.alts:
			if a == "none" and (op == ":" or op == "!="):
				if is.due == "": any = true
				continue
			if is.due == "": continue
			c := is.due.compare(a)
			if op == ":" or op == "!=":
				if c == 0: any = true
			else if op == "<":
				if c < 0: any = true
			else if op == "<=":
				if c <= 0: any = true
			else if op == ">":
				if c > 0: any = true
			else:
				if c >= 0: any = true
		if op == "!=": return not any
		return any
	if f == "title" or f == "assignee" or f == "reporter":
		var val = is.title.clone()
		if f == "assignee": val = is.assignee.clone()
		if f == "reporter": val = is.reporter.clone()
		lv := val.lower()
		var any = false
		for a in n.alts:
			if op == "~":
				if val != "" and lv.contains(a): any = true
			else:
				if val == "":
					if a == "none": any = true
				else if lv == a:
					any = true
		if op == "!=": return not any
		return any
	if f == "text":
		var any = false
		for a in n.alts:
			if is.title.lower().contains(a): any = true
			for c in is.comments:
				if c.text.lower().contains(a): any = true
		return any
	if f == "state":
		var any = false
		for a in n.alts:
			if is.state == a: any = true
		if op == "!=": return not any
		return any
	if f == "label" or f == "labels":
		var any = false
		for a in n.alts:
			if op == "~":
				for l in is.labels:
					if l.contains(a): any = true
			else:
				if a == "none":
					if is.labels.length() == 0: any = true
				else if is.labels.contains(a):
					any = true
		if op == "!=": return not any
		return any
	if f == "is":
		var any = false
		for a in n.alts:
			open := not self.is_final(is.state)
			if a == "open" and open: any = true
			if a == "final" and not open: any = true
			if a == "overdue" and open and is.due != "" and is.due < self.today: any = true
			if a == "unassigned" and is.assignee == "": any = true
		return any
	if f == "has":
		var any = false
		for a in n.alts:
			if a == "assignee" and is.assignee != "": any = true
			if a == "due" and is.due != "": any = true
			if a == "points" and is.points >= 0: any = true
			if a == "labels" and is.labels.length() > 0: any = true
			if a == "comments" and is.comments.length() > 0: any = true
			if a == "reporter" and is.reporter != "": any = true
		return any
	return false

fn App.ev(nodes: List[Node], i: Int, is: Issue) Bool:
	n := nodes[i]
	if n.kind == 5: return true
	if n.kind == 1: return self.ev(nodes, n.a, is) and self.ev(nodes, n.b, is)
	if n.kind == 2: return self.ev(nodes, n.a, is) or self.ev(nodes, n.b, is)
	if n.kind == 3: return not self.ev(nodes, n.a, is)
	return self.eval_term(n, is)

fn App.sort_cmp(spec: SortSpec, a: Issue, b: Issue) Int:
	for i in 0..spec.fields.length():
		f := spec.fields[i]
		var c = 0
		if f == "id": c = cmp_int(a.id, b.id)
		else if f == "created": c = cmp_int(a.created, b.created)
		else if f == "updated": c = cmp_int(a.updated, b.updated)
		else if f == "priority": c = cmp_int(a.priority, b.priority)
		else if f == "state": c = cmp_int(self.state_index(a.state), self.state_index(b.state))
		else if f == "title": c = a.title.lower().compare(b.title.lower())
		else if f == "points":
			if a.points < 0 and b.points < 0: c = 0
			else if a.points < 0: c = 1
			else if b.points < 0: c = -1
			else: c = cmp_int(a.points, b.points)
		else:
			var x = a.assignee.clone()
			var y = b.assignee.clone()
			if f == "reporter":
				x = a.reporter.clone()
				y = b.reporter.clone()
			if f == "due":
				x = a.due.clone()
				y = b.due.clone()
			else:
				x = x.lower()
				y = y.lower()
			if x == "" and y == "": c = 0
			else if x == "": c = 1
			else if y == "": c = -1
			else: c = x.compare(y)
		if spec.desc[i]: c = -c
		if c != 0: return c
	return cmp_int(a.id, b.id)

fn App.matching(q: Query) List[Int]:
	var r = List[Int]()
	for i in 0..self.issues.length():
		if self.ev(q.nodes, q.root, self.issues[i].clone()): r.append(i)
	return r

fn plural_issues(n: Int) String:
	if n == 1: return "(1 issue)"
	return "({n} issues)"

fn var App.emit(s: String) Unit:
	self.out.append(s)

fn var App.run_query(filter: String, sort_text: String, has_sort: Bool, limit: Int) Unit:
	q := compile_filter(filter, self.views, self.states)
	if q.err != "":
		self.emit("error: {q.err}")
		return
	spec := parse_sort(sort_text)
	if spec.err != "":
		self.emit("error: {spec.err}")
		return
	var idxs = self.matching(q)
	idxs.sort(fn x, y: self.sort_cmp(spec, self.issues[x], self.issues[y]))
	var shown = 0
	for i in idxs:
		if limit >= 0 and shown >= limit: break
		self.emit(self.issues[i].line())
		shown += 1
	self.emit(plural_issues(shown))

fn var App.cmd_list(rest: String) Unit:
	sp := split_query(rest)
	if sp.err != "":
		self.emit("error: {sp.err}")
		return
	self.run_query(sp.filter, sp.sort_text, sp.has_sort, sp.limit)

// ---------- issue lookup & ops ----------

fn App.lookup(arg: String) IdRes:
	var r = IdRes()
	var s = arg.clone()
	if s.starts_with("#"):
		s = s.slice(1, s.length()).get("")
	var good = s.length() > 0
	for c in s.chars():
		if not is_digit(c): good = false
	if not good:
		r.err = "bad issue id '{arg}'"
		return r
	var v = 0
	for c in s.chars():
		if v < 100000000: v = v * 10 + c.parse_int().get(0)
	if v < 1:
		r.err = "bad issue id '{arg}'"
		return r
	r.id = v
	for i in 0..self.issues.length():
		if self.issues[i].id == v:
			r.idx = i
			return r
	r.err = "no such issue #{v}"
	return r

fn var App.add_log(id: Int, detail: String, to_state: String = "") Unit:
	self.log.append(LogEntry(self.t, self.actor.clone(), id, detail, to_state))

fn App.final_err(idx: Int) String:
	is := self.issues[idx]
	if self.is_final(is.state):
		return "#{is.id} is in final state '{is.state}'"
	return ""

fn var App.commit(idx: Int, p: Patch) String:
	diffs := patch_diffs(self.issues[idx], p)
	id := self.issues[idx].id
	if diffs.length() == 0:
		self.emit("#{id} unchanged")
		return ""
	self.t += 1
	self.issues[idx].apply(p)
	self.issues[idx].updated = self.t
	for d in diffs:
		self.add_log(id, d)
	self.emit("updated #{id}")
	return ""

fn var App.op_edit(arg: String, toks: List[String], start: Int) String:
	r := self.lookup(arg)
	if r.err != "": return r.err
	fe := self.final_err(r.idx)
	if fe != "": return fe
	p := parse_patch(toks, start)
	if p.err != "": return p.err
	if toks.length() <= start: return "usage: edit ID field=value..."
	return self.commit(r.idx, p)

fn var App.op_label(arg: String, toks: List[String], start: Int) String:
	r := self.lookup(arg)
	if r.err != "": return r.err
	var ls = self.issues[r.idx].labels.clone()
	for i in start..toks.length():
		tok := toks[i]
		var name = tok.clone()
		var remove = false
		if tok.starts_with("+"):
			name = tok.slice(1, tok.length()).get("")
		else if tok.starts_with("-"):
			name = tok.slice(1, tok.length()).get("")
			remove = true
		l := name.lower()
		if not valid_label(l): return "bad label '{l}'"
		if remove:
			var nl = List[String]()
			for x in ls:
				if x != l: nl.append(x.clone())
			ls = nl
		else if not ls.contains(l):
			ls.append(l)
	fe := self.final_err(r.idx)
	if fe != "": return fe
	var p = Patch()
	p.labels = sorted_labels(ls)
	return self.commit(r.idx, p)

fn var App.op_move(arg: String, state: String, comment: String) String:
	r := self.lookup(arg)
	if r.err != "": return r.err
	fe := self.final_err(r.idx)
	if fe != "": return fe
	if not self.states.contains(state): return "unknown state '{state}'"
	cur := self.issues[r.idx].state.clone()
	if cur == state: return "already in state '{state}'"
	var found = -1
	for i in 0..self.trans.length():
		if self.trans[i].src == cur and self.trans[i].dst == state:
			found = i
			break
	if found < 0: return "transition '{cur} -> {state}' not allowed"
	is := self.issues[r.idx].clone()
	var missing = List[String]()
	for g in self.trans[found].guards:
		var unmet = false
		if g == "assignee": unmet = is.assignee == ""
		else if g == "points": unmet = is.points < 0
		else if g == "due": unmet = is.due == ""
		else if g == "labels": unmet = is.labels.length() == 0
		else: unmet = is.reporter == ""
		if unmet: missing.append(g.clone())
	if missing.length() > 0:
		return "cannot move #{is.id} to {state}: missing {missing.join(", ")}"
	self.t += 1
	self.issues[r.idx].state = state.clone()
	self.issues[r.idx].updated = self.t
	self.add_log(r.id, "state: {cur} -> {state}", state.clone())
	if comment != "":
		self.issues[r.idx].comments.append(Comment(self.t, self.actor.clone(), comment.clone()))
		self.add_log(r.id, "comment: {comment}")
	self.emit("moved #{r.id}: {cur} -> {state}")
	return ""

fn var App.op_comment(arg: String, text: String) String:
	r := self.lookup(arg)
	if r.err != "": return r.err
	self.t += 1
	self.issues[r.idx].updated = self.t
	self.issues[r.idx].comments.append(Comment(self.t, self.actor.clone(), text.clone()))
	self.add_log(r.id, "comment: {text}")
	self.emit("commented #{r.id}")
	return ""

// ---------- commands ----------

fn var App.cmd_create(rest: String) Unit:
	if not self.has_wf:
		self.emit("error: no workflow defined")
		return
	tk := tokenize(rest)
	if tk.err != "":
		self.emit("error: {tk.err}")
		return
	toks := tk.items
	if toks.length() == 0:
		self.emit("error: usage: create TITLE [field=value...]")
		return
	title := toks[0].clone()
	if title.trim() == "":
		self.emit("error: empty title")
		return
	p := parse_patch(toks, 1)
	if p.err != "":
		self.emit("error: {p.err}")
		return
	var base = Issue(self.next_id, title.clone(), self.initial.clone())
	diffs := patch_diffs(base, p)
	var is = Issue(self.next_id, title.clone(), self.initial.clone())
	is.apply(p)
	if p.reporter.is_none():
		is.reporter = self.actor.clone()
	self.t += 1
	is.created = self.t
	is.updated = self.t
	id := self.next_id
	self.next_id += 1
	self.issues.append(is)
	self.add_log(id, "created \"{title}\"")
	for d in diffs:
		self.add_log(id, d)
	self.emit("created #{id}")

fn var App.cmd_edit(rest: String) Unit:
	tk := tokenize(rest)
	if tk.err != "":
		self.emit("error: {tk.err}")
		return
	if tk.items.length() == 0:
		self.emit("error: usage: edit ID field=value...")
		return
	e := self.op_edit(tk.items[0], tk.items, 1)
	if e != "": self.emit("error: {e}")

fn var App.cmd_label(rest: String) Unit:
	tk := tokenize(rest)
	if tk.err != "":
		self.emit("error: {tk.err}")
		return
	if tk.items.length() < 2:
		self.emit("error: usage: label ID +label -label...")
		return
	e := self.op_label(tk.items[0], tk.items, 1)
	if e != "": self.emit("error: {e}")

fn var App.cmd_assign(rest: String) Unit:
	tk := tokenize(rest)
	if tk.err != "":
		self.emit("error: {tk.err}")
		return
	if tk.items.length() != 2:
		self.emit("error: usage: assign ID NAME")
		return
	e := self.op_edit(tk.items[0], ["", "assignee={tk.items[1]}"], 1)
	if e != "": self.emit("error: {e}")

fn var App.cmd_move(rest: String) Unit:
	w := rest.fields()
	if w.length() < 2:
		self.emit("error: usage: move ID STATE [comment...]")
		return
	e := self.op_move(w[0], w[1], rest_after(rest, 2))
	if e != "": self.emit("error: {e}")

fn var App.cmd_comment(rest: String) Unit:
	w := rest.fields()
	if w.length() < 2:
		self.emit("error: usage: comment ID TEXT")
		return
	e := self.op_comment(w[0], rest_after(rest, 1))
	if e != "": self.emit("error: {e}")

fn var App.cmd_delete(rest: String) Unit:
	w := rest.fields()
	if w.length() != 1:
		self.emit("error: usage: delete ID")
		return
	r := self.lookup(w[0])
	if r.err != "":
		self.emit("error: {r.err}")
		return
	self.t += 1
	self.add_log(r.id, "deleted")
	self.issues.remove(r.idx)
	self.emit("deleted #{r.id}")

fn var App.cmd_show(rest: String) Unit:
	w := rest.fields()
	if w.length() != 1:
		self.emit("error: usage: show ID")
		return
	r := self.lookup(w[0])
	if r.err != "":
		self.emit("error: {r.err}")
		return
	is := self.issues[r.idx].clone()
	self.emit("#{is.id} {is.title}")
	self.emit("  state: {is.state}")
	self.emit("  priority: {prio_name(is.priority)}")
	self.emit("  assignee: {dash(is.assignee)}")
	self.emit("  points: {pts(is.points)}")
	self.emit("  due: {dash(is.due)}")
	self.emit("  labels: {if is.labels.length() == 0: "-" else: is.labels.join(", ")}")
	self.emit("  reporter: {dash(is.reporter)}")
	self.emit("  created: t={is.created}, updated: t={is.updated}")
	self.emit("  comments: {is.comments.length()}")
	for c in is.comments.clone():
		self.emit("    [t={c.t} {c.actor}] {c.text}")

fn var App.cmd_log(rest: String) Unit:
	w := rest.fields()
	var id = -1
	var tail = -1
	var i = 0
	if w.length() > 0 and w[0] != "tail":
		r := self.lookup_any(w[0])
		if r.err != "":
			self.emit("error: {r.err}")
			return
		id = r.id
		i = 1
	if i < w.length():
		if w[i] != "tail" or i + 2 != w.length():
			self.emit("error: usage: log [ID] [tail N]")
			return
		v := parse_uint(w[i + 1])
		if v < 0:
			self.emit("error: bad tail '{w[i + 1]}'")
			return
		tail = v
	var sel = List[Int]()
	for k in 0..self.log.length():
		if id < 0 or self.log[k].id == id: sel.append(k)
	var from = 0
	if tail >= 0 and tail < sel.length(): from = sel.length() - tail
	if tail == 0: from = sel.length()
	if from >= sel.length():
		self.emit("(no log entries)")
		return
	for q in from..sel.length():
		e := self.log[sel[q]].clone()
		self.emit("t={e.t} {e.actor} #{e.id} {e.detail}")

fn App.lookup_any(arg: String) IdRes:
	var r = self.lookup(arg)
	if r.err.starts_with("no such issue") and r.id < self.next_id:
		r.err = ""
	return r

// ---------- views ----------

fn App.view_refs_of(name: String) List[String]:
	stored := self.views.get_or(name, "")
	sp := split_query(stored)
	q := compile_filter(sp.filter, self.views, self.states)
	return q.refs

fn App.reaches(from: String, target: String, seen: List[String]) Bool:
	for r in self.view_refs_of(from):
		if r == target: return true
		if not seen.contains(r):
			var s2 = seen.clone()
			s2.append(r.clone())
			if self.reaches(r, target, s2): return true
	return false

fn var App.cmd_view(rest: String) Unit:
	w := rest.fields()
	gen := "usage: view save|run|list|show|delete"
	if w.length() == 0:
		self.emit("error: {gen}")
		return
	sub := w[0]
	if sub == "save":
		if w.length() < 2:
			self.emit("error: usage: view save NAME QUERY")
			return
		name := w[1]
		query := rest_after(rest, 2).trim()
		if not valid_view_name(name):
			self.emit("error: bad view name '{name}'")
			return
		sp := split_query(query)
		if sp.err != "":
			self.emit("error: {sp.err}")
			return
		q := compile_filter(sp.filter, self.views, self.states)
		if q.err != "":
			self.emit("error: {q.err}")
			return
		spec := parse_sort(sp.sort_text)
		if spec.err != "":
			self.emit("error: {spec.err}")
			return
		for r in q.refs:
			if r == name or self.reaches(r, name, [r.clone()]):
				self.emit("error: view '{name}' would reference itself")
				return
		self.views[name.clone()] = query.clone()
		self.emit("saved view {name}")
	else if sub == "run":
		if w.length() < 2:
			self.emit("error: usage: view run NAME [sort FIELDS] [limit N]")
			return
		name := w[1]
		if not self.views.contains(name):
			self.emit("error: unknown view '{name}'")
			return
		stored := split_query(self.views.get_or(name, ""))
		extra := split_query(rest_after(rest, 2))
		if extra.err != "":
			self.emit("error: {extra.err}")
			return
		if extra.filter != "":
			self.emit("error: unexpected '{extra.filter}'")
			return
		var st = stored.sort_text.clone()
		var hs = stored.has_sort
		var lim = stored.limit
		if extra.has_sort:
			st = extra.sort_text.clone()
			hs = true
		if extra.limit >= 0: lim = extra.limit
		self.run_query(stored.filter, st, hs, lim)
	else if sub == "list":
		if w.length() != 1:
			self.emit("error: {gen}")
			return
		names := self.views.keys().sorted()
		if names.length() == 0:
			self.emit("(no views)")
			return
		for n in names:
			self.emit("{n}: {self.views.get_or(n, "")}")
	else if sub == "show":
		if w.length() != 2:
			self.emit("error: usage: view show NAME")
			return
		if not self.views.contains(w[1]):
			self.emit("error: unknown view '{w[1]}'")
			return
		self.emit("{w[1]}: {self.views.get_or(w[1], "")}")
	else if sub == "delete":
		if w.length() != 2:
			self.emit("error: usage: view delete NAME")
			return
		name := w[1]
		if not self.views.contains(name):
			self.emit("error: unknown view '{name}'")
			return
		for m in self.views.keys().sorted():
			if m != name and self.reaches(m, name, [m.clone()]):
				self.emit("error: view '{name}' is used by '{m}'")
				return
		self.views.remove(name.clone())
		self.emit("deleted view {name}")
	else:
		self.emit("error: {gen}")

// ---------- bulk ----------

fn var App.cmd_bulk(rest: String) Unit:
	cs := rest.chars()
	var wpos = -1
	var i = 0
	while i + 5 <= cs.length():
		if join_chars(cs, i, i + 5) == "where":
			before := i == 0 or is_ws(cs[i - 1])
			after := i + 5 == cs.length() or is_ws(cs[i + 5])
			if before and after:
				wpos = i
				break
		i += 1
	usage := "usage: bulk ACTION... where QUERY"
	if wpos < 0:
		self.emit("error: {usage}")
		return
	action_text := join_chars(cs, 0, wpos)
	query_text := join_chars(cs, wpos + 5, cs.length())
	if action_text.trim() == "":
		self.emit("error: {usage}")
		return
	tk := tokenize(action_text)
	if tk.err != "":
		self.emit("error: {tk.err}")
		return
	toks := tk.items
	kind := toks[0]
	if kind == "move":
		if toks.length() != 2:
			self.emit("error: usage: bulk move STATE where QUERY")
			return
	else if kind == "assign":
		if toks.length() != 2:
			self.emit("error: usage: bulk assign NAME where QUERY")
			return
	else if kind == "label":
		if toks.length() < 2:
			self.emit("error: usage: bulk label +label... where QUERY")
			return
	else if kind == "set":
		if toks.length() < 2:
			self.emit("error: usage: bulk set field=value... where QUERY")
			return
	else:
		self.emit("error: unknown bulk action '{kind}'")
		return
	q := compile_filter(query_text.trim(), self.views, self.states)
	if q.err != "":
		self.emit("error: {q.err}")
		return
	var ids = List[Int]()
	for ix in self.matching(q):
		ids.append(self.issues[ix].id)
	var ok = 0
	var failed = 0
	for id in ids:
		var e = ""
		arg := "{id}"
		if kind == "move":
			e = self.op_move(arg, toks[1], "")
		else if kind == "assign":
			e = self.op_edit(arg, ["", "assignee={toks[1]}"], 1)
		else if kind == "label":
			e = self.op_label(arg, toks, 1)
		else:
			e = self.op_edit(arg, toks, 1)
		if e == "":
			ok += 1
		else:
			failed += 1
			self.emit("#{id} error: {e}")
	self.emit("bulk: {ok} ok, {failed} failed")

// ---------- reports ----------

type WLine:
	name: String
	count: Int
	points: Int

fn var App.cmd_report(rest: String) Unit:
	w := rest.fields()
	gen := "usage: report summary|workload|labels|timeline"
	if w.length() == 0:
		self.emit("error: {gen}")
		return
	sub := w[0]
	if sub == "summary":
		var open = 0
		var fin = 0
		var unassigned = 0
		var overdue = 0
		var points = 0
		var by_state = Map[String, Int]()
		var by_prio = [0, 0, 0, 0]
		for is in self.issues:
			by_state[is.state.clone()] = by_state.get_or(is.state, 0) + 1
			by_prio[is.priority] += 1
			if self.is_final(is.state):
				fin += 1
			else:
				open += 1
				if is.assignee == "": unassigned += 1
				if is.due != "" and is.due < self.today: overdue += 1
				if is.points >= 0: points += is.points
		self.emit("issues: {self.issues.length()} (open {open}, final {fin})")
		self.emit("by state:")
		for s in self.states.clone():
			self.emit("  {s}: {by_state.get_or(s, 0)}")
		self.emit("by priority:")
		self.emit("  critical: {by_prio[3]}")
		self.emit("  high: {by_prio[2]}")
		self.emit("  medium: {by_prio[1]}")
		self.emit("  low: {by_prio[0]}")
		self.emit("unassigned: {unassigned}")
		self.emit("overdue: {overdue}")
		self.emit("open points: {points}")
	else if sub == "workload":
		var lines = List[WLine]()
		var un = WLine("unassigned", 0, 0)
		for is in self.issues:
			if self.is_final(is.state): continue
			p := if is.points >= 0: is.points else: 0
			if is.assignee == "":
				un.count += 1
				un.points += p
			else:
				key := is.assignee.lower()
				var found = -1
				for k in 0..lines.length():
					if lines[k].name.lower() == key: found = k
				if found < 0:
					lines.append(WLine(is.assignee.clone(), 1, p))
				else:
					lines[found].count += 1
					lines[found].points += p
		lines.sort(fn a, b: wl_cmp(a, b))
		if lines.length() == 0 and un.count == 0:
			self.emit("(no open issues)")
			return
		for l in lines:
			self.emit("{l.name}: {l.count} {if l.count == 1: "issue" else: "issues"}, {l.points} points")
		if un.count > 0:
			self.emit("unassigned: {un.count} {if un.count == 1: "issue" else: "issues"}, {un.points} points")
	else if sub == "labels":
		q := compile_filter(rest_after(rest, 1).trim(), self.views, self.states)
		if q.err != "":
			self.emit("error: {q.err}")
			return
		var counts = Map[String, Int]()
		for ix in self.matching(q):
			for l in self.issues[ix].labels:
				counts[l.clone()] = counts.get_or(l, 0) + 1
		var names = counts.keys().clone()
		names.sort(fn a, b: cmp_label(counts.get_or(a, 0), counts.get_or(b, 0), a, b))
		if names.length() == 0:
			self.emit("(no labels)")
			return
		for n in names:
			self.emit("{n}: {counts.get_or(n, 0)}")
	else if sub == "timeline":
		if w.length() != 2:
			self.emit("error: usage: report timeline ID")
			return
		r := self.lookup(w[1])
		if r.err != "":
			self.emit("error: {r.err}")
			return
		var cur = self.initial.clone()
		var from = self.issues[r.idx].created
		for e in self.log.clone():
			if e.id == r.id and e.to_state != "":
				self.emit("{cur}: t={from}..{e.t} ({e.t - from})")
				cur = e.to_state.clone()
				from = e.t
		self.emit("{cur}: t={from}..{self.t} ({self.t - from})")
	else:
		self.emit("error: {gen}")

fn wl_cmp(a: WLine, b: WLine) Int:
	if a.points != b.points: return cmp_int(b.points, a.points)
	if a.count != b.count: return cmp_int(b.count, a.count)
	return a.name.lower().compare(b.name.lower())

fn cmp_label(ca: Int, cb: Int, a: String, b: String) Int:
	if ca != cb: return cmp_int(cb, ca)
	return a.compare(b)

// ---------- workflow ----------

type WB:
	initial: String = ""
	has_init: Bool = false
	finals: List[String] = []
	trans: List[Trans] = []
	order: List[String] = []
	err: String = ""
	entries: Int = 0

fn var WB.fail(msg: String) Unit:
	if self.err == "": self.err = msg

fn var WB.state(name: String) Bool:
	if not valid_state_name(name):
		self.fail("workflow: bad state name '{name}'")
		return false
	if not self.order.contains(name): self.order.append(name.clone())
	return true

fn var WB.line(l: String) Unit:
	if l.starts_with("initial:"):
		name := rest_after(l, 1).trim()
		if not self.state(name): return
		if self.has_init:
			self.fail("workflow: initial state defined twice")
			return
		self.has_init = true
		self.initial = name.clone()
	else if l.starts_with("final:"):
		body := l.slice(6, l.length()).get("")
		for part in body.split(","):
			name := part.trim()
			if not self.state(name): return
			self.finals.append(name.clone())
	else if l.contains("->"):
		idx := l.index_of("->").get(0)
		src := l.slice(0, idx).get("").trim()
		rest := l.slice(idx + 2, l.length()).get("")
		if not self.state(src): return
		for e in rest.split(","):
			w := e.fields()
			if w.length() == 0:
				self.fail("workflow: bad line '{l}'")
				return
			if not self.state(w[0]): return
			var guards = List[String]()
			if w.length() == 1:
				var _z = 0
			else if w.length() == 3 and w[1] == "requires":
				for g in w[2].split("+"):
					if not ["assignee", "points", "due", "labels", "reporter"].contains(g):
						self.fail("workflow: bad guard field '{g}'")
						return
					guards.append(g.clone())
			else:
				self.fail("workflow: bad line '{l}'")
				return
			self.trans.append(Trans(src.clone(), w[0].clone(), guards))
			self.entries += 1
	else:
		self.fail("workflow: bad line '{l}'")

fn var App.cmd_workflow(block: List[String]) Unit:
	if self.next_id > 1:
		self.emit("error: workflow: cannot redefine after issues were created")
		return
	var wb = WB()
	for raw in block:
		l := raw.trim()
		if l == "" or l.starts_with("#"): continue
		if wb.err != "": continue
		wb.line(l)
	if wb.err == "" and not wb.has_init:
		wb.fail("workflow: initial state missing")
	if wb.err == "":
		for t in wb.trans.clone():
			if wb.finals.contains(t.src):
				wb.fail("workflow: '{t.src}' is final and cannot have transitions")
				break
	if wb.err != "":
		self.emit("error: {wb.err}")
		return
	self.states = wb.order.clone()
	self.finals = wb.finals.clone()
	self.initial = wb.initial.clone()
	self.trans = wb.trans.clone()
	self.has_wf = true
	self.emit("workflow ok: {self.states.length()} states, {wb.entries} transitions")

// ---------- main ----------

fn var App.cmd_actor(rest: String) Unit:
	w := rest.fields()
	if w.length() != 1:
		self.emit("error: usage: actor NAME")
		return
	self.actor = w[0].clone()
	self.emit("actor is {w[0]}")

fn var App.cmd_today(rest: String) Unit:
	w := rest.fields()
	if w.length() != 1:
		self.emit("error: usage: today DATE")
		return
	if not valid_date(w[0]):
		self.emit("error: bad date '{w[0]}'")
		return
	self.today = w[0].clone()
	self.emit("today is {w[0]}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	lines := text.lines()
	var app = App()
	var i = 0
	while i < lines.length():
		line := lines[i].trim_end()
		i += 1
		trimmed := line.trim_start()
		if trimmed == "" or trimmed.starts_with("#"): continue
		app.emit("> {line}")
		cmd := trimmed.fields()[0]
		rest := rest_after(line, 1)
		if cmd == "workflow":
			var block = List[String]()
			while i < lines.length():
				b := lines[i]
				i += 1
				if b.trim() == "end": break
				block.append(b.clone())
			app.cmd_workflow(block)
		else if cmd == "actor": app.cmd_actor(rest)
		else if cmd == "today": app.cmd_today(rest)
		else if cmd == "create": app.cmd_create(rest)
		else if cmd == "edit": app.cmd_edit(rest)
		else if cmd == "label": app.cmd_label(rest)
		else if cmd == "assign": app.cmd_assign(rest)
		else if cmd == "move": app.cmd_move(rest)
		else if cmd == "comment": app.cmd_comment(rest)
		else if cmd == "delete": app.cmd_delete(rest)
		else if cmd == "show": app.cmd_show(rest)
		else if cmd == "list": app.cmd_list(rest)
		else if cmd == "view": app.cmd_view(rest)
		else if cmd == "bulk": app.cmd_bulk(rest)
		else if cmd == "log": app.cmd_log(rest)
		else if cmd == "report": app.cmd_report(rest)
		else: app.emit("error: unknown command '{cmd}'")
	if app.out.length() > 0:
		print(app.out.join("\n"))
