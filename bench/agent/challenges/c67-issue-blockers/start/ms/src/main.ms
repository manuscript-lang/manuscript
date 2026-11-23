import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Comment:
	t: Int
	actor: String
	text: String

type Fields:
	title: String
	priority: Int = 1
	assignee: String? = null
	points: Int? = null
	due: String? = null
	labels: List[String] = []
	reporter: String? = null

type Issue:
	id: Int
	f: Fields
	state: Int
	created: Int
	updated: Int
	comments: List[Comment] = []
	hist_t: List[Int] = []
	hist_s: List[Int] = []

type Trans:
	src: Int
	dst: Int
	guards: List[String]

type Wf:
	states: List[String] = []
	finals: List[Bool] = []
	initial: Int = -1
	trans: List[Trans] = []

type Entry:
	t: Int
	actor: String
	id: Int
	detail: String

type State:
	wf: Wf = Wf()
	issues: List[Issue] = []
	next_id: Int = 1
	clock: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	views: Map[String, String] = Map[String, String]()
	log: List[Entry] = []
	out: List[String] = []

type Node:
	kind: Int
	a: Int = -1
	b: Int = -1
	field: Int = 0
	op: Int = 0
	vals: List[String] = []

type Parser:
	cs: List[String]
	pos: Int = 0
	kind: Int = 7
	field: String = ""
	opt: String = ""
	op: Int = 0
	value: String = ""
	quoted: Bool = false
	text: String = ""

type QSpec:
	filter: String
	sort: String? = null
	limit: Int? = null

type SortKey:
	field: Int
	desc: Bool

// ---------- string helpers ----------

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\r" or c == "\n"

fn digit(c: String) Int:
	if c.length() != 1: return -1
	return "0123456789".index_of(c) or (-1)

fn is_lower(c: String) Bool: c.length() == 1 and c >= "a" and c <= "z"

fn join_range(cs: List[String], a: Int, b: Int) String:
	var r = ""
	var i = a

	while i < b:
		r += cs[i]
		i += 1

	return r

fn rest_after(s: String, k: Int) String:
	cs := s.chars()
	n := cs.length()
	var i = 0
	var w = 0

	while w < k:
		while i < n and is_ws(cs[i]):
			i += 1
		if i >= n: return ""

		while i < n and not is_ws(cs[i]):
			i += 1
		w += 1

	while i < n and is_ws(cs[i]):
		i += 1
	return join_range(cs, i, n)

fn valid_int(s: String) Bool:
	if s.length() == 0 or s.length() > 7: return false

	for c in s.chars():
		if digit(c) < 0: return false
	if s.length() > 1 and s.starts_with("0"): return false

	return (s.parse_int() or 2000000) <= 1000000

fn to_int(s: String) Int: s.parse_int() or 0

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false

	for i in 0..10:
		if i == 4 or i == 7:
			if cs[i] != "-": return false
		else:
			if digit(cs[i]) < 0: return false

	y := to_int(join_range(cs, 0, 4))
	m := to_int(join_range(cs, 5, 7))
	d := to_int(join_range(cs, 8, 10))
	if y < 1 or m < 1 or m > 12 or d < 1: return false

	var dim = 31
	if m == 4 or m == 6 or m == 9 or m == 11: dim = 30

	if m == 2:
		leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
		dim = if leap: 29 else: 28

	return d <= dim

fn valid_label(s: String) Bool:
	if s.length() == 0: return false

	for c in s.chars():
		if not (is_lower(c) or digit(c) >= 0 or c == "_" or c == "-"): return false
	return true

fn valid_state_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0: return false
	if not is_lower(cs[0]): return false

	for c in cs:
		if not (is_lower(c) or digit(c) >= 0 or c == "_"): return false
	return true

fn tokenize(s: String) List[String]!:
	var out = List[String]()
	var cur = ""
	var has = false
	var inq = false
	cs := s.chars()
	n := cs.length()
	var i = 0

	while i < n:
		c := cs[i]

		if inq:
			if c == "\\" and i + 1 < n and (cs[i + 1] == "\"" or cs[i + 1] == "\\"):
				cur += cs[i + 1]
				i += 2
				continue

			if c == "\"":
				inq = false
				i += 1
				continue

			cur += c
			i += 1
			continue

		if c == "\"":
			inq = true
			has = true
			i += 1
			continue

		if is_ws(c):
			if has:
				out.append(cur.clone())
				cur = ""
				has = false

			i += 1
			continue

		cur += c
		has = true
		i += 1

	if inq: return error(Error("unterminated quote"))

	if has: out.append(cur.clone())
	return ok(out)

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

fn opt_s(x: String?) String: x or "-"

fn opt_i(x: Int?) String:
	v := x
	if v != null: return f"{v}"

	return "-"

fn labels_s(l: List[String]) String:
	if l.length() == 0: return "-"
	return l.join(",")

fn parse_id_syntax(arg: String) Int!:
	var a = arg.clone()
	if a.starts_with("#"): a = rest_after_hash(arg)
	if a.length() == 0: return error(Error(f"bad issue id '{arg}'"))

	var v = 0

	for c in a.chars():
		d := digit(c)
		if d < 0: return error(Error(f"bad issue id '{arg}'"))

		if v < 1000000000000: v = v * 10 + d

	if v < 1: return error(Error(f"bad issue id '{arg}'"))

	return ok(v)

fn rest_after_hash(s: String) String:
	cs := s.chars()
	return join_range(cs, 1, cs.length())

// ---------- fields ----------

fn apply_token(var f: Fields, tok: String) Void!:
	cs := tok.chars()
	var eq = -1

	for i in 0..cs.length():
		if cs[i] == "=":
			eq = i
			break

	if eq <= 0: return error(Error(f"expected field=value, got '{tok}'"))

	name := join_range(cs, 0, eq)
	value := join_range(cs, eq + 1, cs.length())
	if name == "state": return error(Error("use move to change state"))

	if name == "title":
		if value.trim() == "": return error(Error("empty title"))

		f.title = value
		return ok()

	if name == "priority":
		r := prio_rank(value)
		if r < 0: return error(Error(f"bad priority '{value}'"))

		f.priority = r
		return ok()

	if name == "assignee":
		if value.trim() == "": return error(Error("empty assignee"))

		f.assignee = if value == "none": null else: value
		return ok()

	if name == "reporter":
		if value.trim() == "": return error(Error("empty reporter"))

		f.reporter = if value == "none": null else: value
		return ok()

	if name == "points":
		if value == "none":
			f.points = null
			return ok()

		if not valid_int(value): return error(Error(f"bad points '{value}'"))

		f.points = to_int(value)
		return ok()

	if name == "due":
		if value == "none":
			f.due = null
			return ok()

		if not valid_date(value): return error(Error(f"bad date '{value}'"))

		f.due = value
		return ok()

	if name == "labels":
		if value == "none":
			f.labels = []
			return ok()

		f.labels = norm_labels(value.split(","))?
		return ok()

	return error(Error(f"unknown field '{name}'"))

fn norm_labels(parts: List[String]) List[String]!:
	var out = List[String]()

	for p in parts:
		l := p.lower()
		if not valid_label(l): return error(Error(f"bad label '{l}'"))

		out.append(l)

	return ok(sort_unique(out))

fn sort_unique(xs: List[String]) List[String]:
	var s = xs.sorted(fn a, b: a.compare(b))
	var out = List[String]()
	for x in s:
		if out.length() == 0 or out[out.length() - 1] != x:
			out.append(x.clone())
	return out

fn copy_fields(f: Fields) Fields:
	return Fields(
		title: f.title.clone(),
		priority: f.priority,
		assignee: f.assignee.clone(),
		points: f.points,
		due: f.due.clone(),
		labels: f.labels.clone(),
		reporter: f.reporter.clone(),
	)

fn diff_fields(a: Fields, b: Fields) List[String]:
	var out = List[String]()
	if a.title != b.title: out.append(f"title: {a.title} -> {b.title}")
	if a.priority != b.priority: out.append(
		f"priority: {prio_name(a.priority)} -> {prio_name(b.priority)}"
	)
	if (
		opt_s(a.assignee) != opt_s(b.assignee)
		or (a.assignee != null) != (b.assignee != null)
	):
		out.append(f"assignee: {opt_s(a.assignee)} -> {opt_s(b.assignee)}")
	if opt_i(a.points) != opt_i(b.points): out.append(
		f"points: {opt_i(a.points)} -> {opt_i(b.points)}"
	)
	if opt_s(a.due) != opt_s(b.due): out.append(
		f"due: {opt_s(a.due)} -> {opt_s(b.due)}"
	)
	if labels_s(a.labels) != labels_s(b.labels): out.append(
		f"labels: {labels_s(a.labels)} -> {labels_s(b.labels)}"
	)
	if (
		opt_s(a.reporter) != opt_s(b.reporter)
		or (a.reporter != null) != (b.reporter != null)
	):
		out.append(f"reporter: {opt_s(a.reporter)} -> {opt_s(b.reporter)}")
	return out

// ---------- query ----------

fn split_query(text: String) QSpec!:
	cs := text.chars()
	n := cs.length()
	var filter_end = n
	var limit: Int? = null
	var sort: String? = null

	// limit
	var e = n
	while e > 0 and is_ws(cs[e - 1]):
		e -= 1

	var j = e
	while j > 0 and not is_ws(cs[j - 1]):
		j -= 1

	if j > 0:
		arg := join_range(cs, j, e)
		var q = j
		while q > 0 and is_ws(cs[q - 1]):
			q -= 1

		var s = q
		while s > 0 and not is_ws(cs[s - 1]):
			s -= 1

		if join_range(cs, s, q) == "limit":
			if not valid_int(arg): return error(Error(f"bad limit '{arg}'"))

			limit = to_int(arg)
			filter_end = s

	// sort
	var i = 0

	while i < filter_end:
		if i == 0 or is_ws(cs[i - 1]):
			if (
				i + 4 < filter_end
				and join_range(cs, i, i + 4) == "sort"
				and is_ws(cs[i + 4])
			):
				sort = join_range(cs, i + 5, filter_end)
				filter_end = i
				break

		i += 1

	return ok(QSpec(filter: join_range(cs, 0, filter_end), sort: sort, limit: limit))

fn parse_sort(text: String) List[SortKey]!:
	var keys = List[SortKey]()
	t := text.replace(",", " ")

	for w in t.fields():
		var name = w.clone()
		var desc = false

		if w.starts_with("-"):
			desc = true
			name = rest_after_hash(w)

		fi := sort_field(name)
		if fi < 0: return error(Error(f"bad sort field '{name}'"))

		keys.append(SortKey(fi, desc))

	return ok(keys)

fn sort_field(s: String) Int:
	names := [
		"id", "created", "updated", "priority", "points", "state", "title", "assignee",
		"reporter", "due"
	]
	return names.find_index(fn x: x == s) or (-1)

fn field_code(s: String) Int:
	names := [
		"id", "created", "updated", "points", "title", "assignee", "reporter", "text",
		"state", "priority", "due", "label", "is", "has", "view"
	]
	if s == "labels": return 11

	return names.find_index(fn x: x == s) or (-1)

fn op_ok(field: Int, op: Int) Bool:
	if field <= 3 or field == 9 or field == 10: return op <= 5
	if field == 4 or field == 5 or field == 6 or field == 11: return (
		op == 0
		or op == 1
		or op == 6
	)
	if field == 7: return op == 6
	if field == 8: return op == 0 or op == 1

	return op == 0

fn var Parser.advance() Void!:
	n := self.cs.length()
	var i = self.pos
	while i < n and is_ws(self.cs[i]):
		i += 1

	if i >= n:
		self.kind = 7
		self.pos = i
		return ok()

	c := self.cs[i]

	if c == "(":
		self.kind = 0
		self.text = "("
		self.pos = i + 1
		return ok()

	if c == ")":
		self.kind = 1
		self.text = ")"
		self.pos = i + 1
		return ok()

	var j = i
	while j < n and is_lower_or_us(self.cs[j]):
		j += 1

	var op = -1
	var oplen = 0

	if j > i and j < n:
		c1 := self.cs[j]
		c2 := if j + 1 < n: self.cs[j + 1].clone() else: ""

		if c1 == "!" and c2 == "=":
			op = 1
			oplen = 2
		else if c1 == "<" and c2 == "=":
			op = 3
			oplen = 2
		else if c1 == ">" and c2 == "=":
			op = 5
			oplen = 2
		else if c1 == ":":
			op = 0
			oplen = 1
		else if c1 == "<":
			op = 2
			oplen = 1
		else if c1 == ">":
			op = 4
			oplen = 1
		else if c1 == "~":
			op = 6
			oplen = 1

	if op >= 0:
		self.kind = 5
		self.field = join_range(self.cs, i, j)
		self.op = op
		self.opt = join_range(self.cs, j, j + oplen)

		var k = j + oplen
		self.quoted = false

		if k < n and self.cs[k] == "\"":
			self.quoted = true
			k += 1

			var v = ""
			var closed = false

			while k < n:
				ch := self.cs[k]

				if (
					ch == "\\"
					and k + 1 < n
					and (
						self.cs[k + 1] == "\""
						or self.cs[k + 1] == "\\"
					)
				):
					v += self.cs[k + 1]
					k += 2
					continue

				if ch == "\"":
					closed = true
					k += 1
					break

				v += ch
				k += 1

			if not closed: return error(Error("query: unterminated quote"))

			self.value = v
		else:
			var s = k
			while (
				k < n
				and not is_ws(self.cs[k])
				and self.cs[k] != "("
				and self.cs[k] != ")"
			):
				k += 1
			self.value = join_range(self.cs, s, k)

		self.pos = k
		return ok()

	var k = i
	while k < n and not is_ws(self.cs[k]) and self.cs[k] != "(" and self.cs[k] != ")":
		k += 1

	w := join_range(self.cs, i, k)
	self.text = w.clone()
	self.pos = k

	if w == "AND": self.kind = 2
	else if w == "OR": self.kind = 3
	else if w == "NOT": self.kind = 4
	else: self.kind = 6

	return ok()

fn is_lower_or_us(c: String) Bool: is_lower(c) or c == "_"

fn parse_filter(
	st: State,
	text: String,
	var nodes: List[Node],
	var refs: List[String],
) Int!:
	if text.trim() == "": return ok(-1)

	var p = Parser(cs: text.chars().clone())
	p.advance()?

	root := p.parse_or(st, nodes, refs)?
	if p.kind != 7: return error(Error(f"query: unexpected token '{p.text}'"))

	return ok(root)

fn add_node(var nodes: List[Node], n: Node) Int:
	nodes.append(n)
	return nodes.length() - 1

fn var Parser.parse_or(st: State, var nodes: List[Node], var refs: List[String]) Int!:
	var left = self.parse_and(st, nodes, refs)?

	while self.kind == 3:
		self.advance()?

		right := self.parse_and(st, nodes, refs)?
		left = add_node(nodes, Node(kind: 2, a: left, b: right))

	return ok(left)

fn var Parser.parse_and(st: State, var nodes: List[Node], var refs: List[String]) Int!:
	var left = self.parse_not(st, nodes, refs)?

	while true:
		if self.kind == 2:
			self.advance()?

			right := self.parse_not(st, nodes, refs)?
			left = add_node(nodes, Node(kind: 1, a: left, b: right))
		else if self.kind == 4 or self.kind == 0 or self.kind == 5:
			right := self.parse_not(st, nodes, refs)?
			left = add_node(nodes, Node(kind: 1, a: left, b: right))
		else:
			break

	return ok(left)

fn var Parser.parse_not(st: State, var nodes: List[Node], var refs: List[String]) Int!:
	if self.kind == 4:
		self.advance()?

		child := self.parse_not(st, nodes, refs)?
		return ok(add_node(nodes, Node(kind: 3, a: child)))

	if self.kind == 0:
		self.advance()?

		e := self.parse_or(st, nodes, refs)?
		if self.kind == 7: return error(Error("query: unexpected end of query"))
		if self.kind != 1: return error(Error(f"query: unexpected token '{self.text}'"))

		self.advance()?
		return ok(e)

	if self.kind == 5:
		idx := build_term(
			st,
			self.field,
			self.opt,
			self.op,
			self.value.clone(),
			self.quoted,
			nodes,
			refs,
		)?
		self.advance()?
		return ok(idx)

	if self.kind == 7: return error(Error("query: unexpected end of query"))

	return error(Error(f"query: unexpected token '{self.text}'"))

fn build_term(
	st: State,
	fname: String,
	opt: String,
	op: Int,
	value: String,
	quoted: Bool,
	var nodes: List[Node],
	var refs: List[String],
) Int!:
	fc := field_code(fname)
	if fc < 0: return error(Error(f"query: unknown field '{fname}'"))
	if not op_ok(fc, op): return error(
		Error(f"query: bad operator '{opt}' for field '{fname}'")
	)

	if fc == 14:
		q := st.views.get(value)
		if q == null: return error(Error(f"query: unknown view '{value}'"))

		qs := split_query(q)?
		root := parse_filter(st, qs.filter, nodes, refs)?
		refs.append(value.clone())
		return ok(add_node(nodes, Node(kind: 4, a: root)))

	var alts = List[String]()

	if (op == 0 or op == 1 or op == 6) and not quoted:
		alts = value.split("|").clone()
	else:
		alts = [value]

	var vals = List[String]()

	for v in alts:
		if fc <= 2:
			if not valid_int(v): return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 3:
			if not (valid_int(v) or (v == "none" and op <= 1)): return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 8:
			if st.wf.states.find_index(fn x: x == v) == null: return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 9:
			if prio_rank(v) < 0: return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 10:
			okv := valid_date(v) or (v == "none" and op <= 1)
			if not okv: return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 12:
			if not (v == "open" or v == "final" or v == "overdue" or v == "unassigned"): return error(
				Error(f"query: bad value '{v}' for field '{fname}'")
			)

			vals.append(v.clone())
		else if fc == 13:
			if not (
				v == "assignee"
				or v == "due"
				or v == "points"
				or v == "labels"
				or v == "comments"
				or v == "reporter"
			): return error(Error(f"query: bad value '{v}' for field '{fname}'"))

			vals.append(v.clone())
		else:
			vals.append(v.lower())

	return ok(add_node(nodes, Node(kind: 0, field: fc, op: op, vals: vals)))

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1

	return 0

fn cmp_op(op: Int, a: Int, b: Int) Bool:
	if op == 0: return a == b
	if op == 2: return a < b
	if op == 3: return a <= b
	if op == 4: return a > b
	if op == 5: return a >= b

	return false

fn is_open(st: State, iss: Issue) Bool: not st.wf.finals[iss.state]

fn opt_match(x: String?, op: Int, v: String) Bool:
	s := x

	if s != null:
		if op == 6: return s.lower().contains(v)
		return s.lower() == v

	return op == 0 and v == "none"

fn match_one(st: State, fc: Int, op: Int, v: String, iss: Issue) Bool:
	if fc <= 2:
		x := if fc == 0: iss.id else: if fc == 1: iss.created else: iss.updated
		return cmp_op(op, x, to_int(v))

	if fc == 3:
		p := iss.f.points

		if p != null:
			if v == "none": return false
			return cmp_op(op, p, to_int(v))

		return op == 0 and v == "none"

	if fc == 4: return if op == 6: iss.f.title.lower().contains(v) else: iss.f.title.lower() == v
	if fc == 5: return opt_match(iss.f.assignee, op, v)
	if fc == 6: return opt_match(iss.f.reporter, op, v)

	if fc == 7:
		if iss.f.title.lower().contains(v): return true

		for c in iss.comments:
			if c.text.lower().contains(v): return true
		return false

	if fc == 8: return st.wf.states[iss.state] == v
	if fc == 9: return cmp_op(op, iss.f.priority, prio_rank(v))

	if fc == 10:
		d := iss.f.due

		if d != null:
			if v == "none": return false
			if op == 0: return d == v
			if op == 2: return d < v
			if op == 3: return d <= v
			if op == 4: return d > v

			return d >= v

		return op == 0 and v == "none"

	if fc == 11:
		if op == 6:
			for l in iss.f.labels:
				if l.contains(v): return true
			return false

		if v == "none": return iss.f.labels.length() == 0

		for l in iss.f.labels:
			if l == v: return true
		return false

	if fc == 12:
		if v == "open": return is_open(st, iss)
		if v == "final": return not is_open(st, iss)
		if v == "unassigned": return iss.f.assignee == null

		d := iss.f.due
		if d != null: return is_open(st, iss) and d < st.today

		return false

	if v == "assignee": return iss.f.assignee != null
	if v == "due": return iss.f.due != null
	if v == "points": return iss.f.points != null
	if v == "labels": return iss.f.labels.length() > 0
	if v == "comments": return iss.comments.length() > 0

	return iss.f.reporter != null

fn eval_node(st: State, nodes: List[Node], i: Int, iss: Issue) Bool:
	if i < 0: return true

	n := nodes[i]
	if n.kind == 4: return eval_node(st, nodes, n.a, iss)
	if n.kind == 1: return (
		eval_node(st, nodes, n.a, iss)
		and eval_node(st, nodes, n.b, iss)
	)
	if n.kind == 2: return (
		eval_node(st, nodes, n.a, iss)
		or eval_node(st, nodes, n.b, iss)
	)
	if n.kind == 3: return not eval_node(st, nodes, n.a, iss)

	base := if n.op == 1: 0 else: n.op
	var r = false

	for v in n.vals:
		if match_one(st, n.field, base, v, iss):
			r = true
			break

	return if n.op == 1: not r else: r

fn cmp_opt_int(a: Int?, b: Int?) Int:
	x := a

	if x != null:
		y := b
		if y != null: return cmp_int(x, y)

		return -1

	if b != null: return 1

	return 0

fn cmp_opt_str(a: String?, b: String?, ci: Bool) Int:
	x := a

	if x != null:
		y := b

		if y != null:
			if ci: return x.lower().compare(y.lower())
			return x.compare(y)

		return -1

	if b != null: return 1

	return 0

fn cmp_issue(keys: List[SortKey], a: Issue, b: Issue) Int:
	for k in keys:
		var c = 0

		if k.field == 0: c = cmp_int(a.id, b.id)
		else if k.field == 1: c = cmp_int(a.created, b.created)
		else if k.field == 2: c = cmp_int(a.updated, b.updated)
		else if k.field == 3: c = cmp_int(a.f.priority, b.f.priority)
		else if k.field == 4: c = cmp_opt_int(a.f.points, b.f.points)
		else if k.field == 5: c = cmp_int(a.state, b.state)
		else if k.field == 6: c = a.f.title.lower().compare(b.f.title.lower())
		else if k.field == 7: c = cmp_opt_str(a.f.assignee, b.f.assignee, true)
		else if k.field == 8: c = cmp_opt_str(a.f.reporter, b.f.reporter, true)
		else: c = cmp_opt_str(a.f.due, b.f.due, false)

		if k.desc: c = -c
		if c != 0: return c

	return cmp_int(a.id, b.id)

fn issue_line(st: State, iss: Issue) String:
	return f"#{iss.id} | {st.wf.states[iss.state]} | {prio_name(iss.f.priority)} | {opt_s(iss.f.assignee)} | {opt_i(iss.f.points)} | {opt_s(iss.f.due)} | {labels_s(iss.f.labels)} | {iss.f.title}"

fn State.select(filter: String) List[Int]!:
	var nodes = List[Node]()
	var refs = List[String]()
	root := parse_filter(self, filter, nodes, refs)?
	var out = List[Int]()
	for i in 0..self.issues.length():
		if eval_node(self, nodes, root, self.issues[i]): out.append(i)
	return ok(out)

fn State.run_list(
	spec: QSpec,
	sort_override: String?,
	limit_override: Int?,
	use_override: Bool,
) String!:
	var idxs = self.select(spec.filter)?
	var sort_text: String? = spec.sort.clone()
	var limit: Int? = spec.limit

	if use_override:
		sort_text = sort_override.clone()
		limit = limit_override

	keys := parse_sort(sort_text or "")?
	idxs.sort(fn a, b: cmp_issue(keys, self.issues[a], self.issues[b]))

	var lines = List[String]()
	var count = 0

	for i in idxs:
		l := limit
		if l != null:
			if count >= l: break
		lines.append(issue_line(self, self.issues[i]))
		count += 1

	lines.append(if count == 1: "(1 issue)" else: f"({count} issues)")
	return ok(lines.join("\n"))

// ---------- state ops ----------

fn var State.emit(s: String) Void:
	self.out.append(s.clone())

fn State.find(id: Int) Int:
	return self.issues.find_index(fn i: i.id == id) or (-1)

fn State.id_arg(arg: String) Int!:
	id := parse_id_syntax(arg)?
	if self.find(id) < 0: return error(Error(f"no such issue #{id}"))

	return ok(id)

fn var State.add_log(id: Int, detail: String) Void:
	self.log.append(Entry(self.clock, self.actor.clone(), id, detail.clone()))

fn State.final_check(idx: Int) Void!:
	iss := self.issues[idx]
	if self.wf.finals[iss.state]:
		return error(
			Error(
				f"#{iss.id} is in final state '{self.wf.states[iss.state]}'"
			)
		)

	return ok()

fn var State.commit_edit(idx: Int, nf: Fields) String:
	changes := diff_fields(self.issues[idx].f, nf)
	id := self.issues[idx].id
	if changes.length() == 0: return f"#{id} unchanged"

	self.clock += 1
	self.issues[idx].f = nf.clone()
	self.issues[idx].updated = self.clock
	for c in changes:
		self.add_log(id, c)
	return f"updated #{id}"

fn var State.do_edit(id: Int, toks: List[String]) String!:
	idx := self.find(id)
	self.final_check(idx)?
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))

	var nf = copy_fields(self.issues[idx].f)
	for t in toks:
		apply_token(nf, t)?
	return ok(self.commit_edit(idx, nf))

fn var State.do_label(id: Int, items: List[String]) String!:
	idx := self.find(id)
	self.final_check(idx)?

	var labels = self.issues[idx].f.labels.clone()

	for it in items:
		var sign = "+"
		var name = it.clone()

		if it.starts_with("+") or it.starts_with("-"):
			sign = join_range(it.chars(), 0, 1)
			name = rest_after_hash(it)

		l := name.lower()
		if not valid_label(l): return error(Error(f"bad label '{l}'"))

		if sign == "-":
			var nl = List[String]()
			for x in labels:
				if x != l: nl.append(x.clone())
			labels = nl
		else:
			labels.append(l)

	var nf = copy_fields(self.issues[idx].f)
	nf.labels = sort_unique(labels)
	return ok(self.commit_edit(idx, nf))

fn var State.do_move(id: Int, target: String, comment: String) String!:
	idx := self.find(id)
	self.final_check(idx)?

	ti := self.wf.states.find_index(fn x: x == target) or (-1)
	if ti < 0: return error(Error(f"unknown state '{target}'"))

	cur := self.issues[idx].state
	if ti == cur: return error(Error(f"already in state '{target}'"))

	var found = -1

	for k in 0..self.wf.trans.length():
		tr := self.wf.trans[k]

		if tr.src == cur and tr.dst == ti:
			found = k
			break

	curname := self.wf.states[cur].clone()
	if found < 0: return error(Error(f"transition '{curname} -> {target}' not allowed"))

	var missing = List[String]()
	f := self.issues[idx].f.clone()

	for g in self.wf.trans[found].guards:
		var unmet = false

		if g == "assignee": unmet = f.assignee == null
		else if g == "points": unmet = f.points == null
		else if g == "due": unmet = f.due == null
		else if g == "labels": unmet = f.labels.length() == 0
		else: unmet = f.reporter == null

		if unmet: missing.append(g.clone())

	if missing.length() > 0:
		return error(
			Error(
				f"cannot move #{id} to {target}: missing {missing.join(", ")}"
			)
		)

	self.clock += 1
	self.issues[idx].state = ti
	self.issues[idx].updated = self.clock
	self.issues[idx].hist_t.append(self.clock)
	self.issues[idx].hist_s.append(ti)
	self.add_log(id, f"state: {curname} -> {target}")

	if comment != "":
		self.issues[idx].comments.append(
			Comment(self.clock, self.actor.clone(), comment.clone())
		)
		self.add_log(id, f"comment: {comment}")

	return ok(f"moved #{id}: {curname} -> {target}")

// ---------- commands ----------

fn var State.cmd_create(rest: String) String!:
	if self.wf.initial < 0: return error(Error("no workflow defined"))

	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: create TITLE [field=value...]"))

	first := toks[0].clone()
	if first.trim() == "": return error(Error("empty title"))

	var nf = Fields(title: first.clone(), reporter: self.actor.clone())
	for i in 1..toks.length():
		apply_token(nf, toks[i])?
	self.clock += 1

	id := self.next_id
	self.next_id += 1

	var iss = Issue(id, copy_fields(nf), self.wf.initial, self.clock, self.clock)
	iss.hist_t.append(self.clock)
	iss.hist_s.append(self.wf.initial)
	self.issues.append(iss)
	self.add_log(id, f"created \"{first}\"")

	var rep_given = false
	for i in 1..toks.length():
		if toks[i].starts_with("reporter="): rep_given = true

	var def = Fields(title: first.clone())
	if not rep_given: def.reporter = nf.reporter.clone()
	for c in diff_fields(def, nf):
		self.add_log(id, c)
	return ok(f"created #{id}")

fn var State.cmd_edit(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))

	id := self.id_arg(toks[0].clone())?
	return self.do_edit(id, toks.slice(1, toks.length())?)

fn var State.cmd_label(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() < 2: return error(Error("usage: label ID +label -label..."))

	id := self.id_arg(toks[0].clone())?
	return self.do_label(id, toks.slice(1, toks.length())?)

fn var State.cmd_assign(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() != 2: return error(Error("usage: assign ID NAME"))

	id := self.id_arg(toks[0].clone())?
	return self.do_edit(id, [f"assignee={toks[1]}"])

fn var State.cmd_move(rest: String) String!:
	ws := rest.fields()
	if ws.length() < 2: return error(Error("usage: move ID STATE [comment...]"))

	id := self.id_arg(ws[0].clone())?
	return self.do_move(id, ws[1], rest_after(rest, 2))

fn var State.cmd_comment(rest: String) String!:
	ws := rest.fields()
	if ws.length() < 2: return error(Error("usage: comment ID TEXT"))

	id := self.id_arg(ws[0].clone())?
	text := rest_after(rest, 1)
	idx := self.find(id)
	self.clock += 1
	self.issues[idx].updated = self.clock
	self.issues[idx].comments.append(
		Comment(self.clock, self.actor.clone(), text.clone())
	)
	self.add_log(id, f"comment: {text}")
	return ok(f"commented #{id}")

fn var State.cmd_delete(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: delete ID"))

	id := self.id_arg(ws[0].clone())?
	idx := self.find(id)
	self.clock += 1
	self.add_log(id, "deleted")
	self.issues.remove(idx)
	return ok(f"deleted #{id}")

fn State.cmd_show(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: show ID"))

	id := self.id_arg(ws[0].clone())?
	iss := self.issues[self.find(id)]
	f := iss.f
	var lines = List[String]()
	lines.append(f"#{iss.id} {f.title}")
	lines.append(f"  state: {self.wf.states[iss.state]}")
	lines.append(f"  priority: {prio_name(f.priority)}")
	lines.append(f"  assignee: {opt_s(f.assignee)}")
	lines.append(f"  points: {opt_i(f.points)}")
	lines.append(f"  due: {opt_s(f.due)}")
	lines.append(
		f"  labels: {if f.labels.length() == 0: "-" else: f.labels.join(", ")}"
	)
	lines.append(f"  reporter: {opt_s(f.reporter)}")
	lines.append(f"  created: t={iss.created}, updated: t={iss.updated}")
	lines.append(f"  comments: {iss.comments.length()}")
	for c in iss.comments:
		lines.append(f"    [t={c.t} {c.actor}] {c.text}")
	return ok(lines.join("\n"))

fn State.cmd_list(rest: String) String!:
	spec := split_query(rest)?
	return self.run_list(spec, null, null, false)

fn var State.cmd_log(rest: String) String!:
	ws := rest.fields()
	var id = -1
	var tail = -1
	usage := "usage: log [ID] [tail N]"
	var p = 0

	if ws.length() > 0 and ws[0] != "tail":
		id = parse_id_syntax(ws[0])?
		if id >= self.next_id: return error(Error(f"no such issue #{id}"))

		p = 1

	if ws.length() == p + 2 and ws[p] == "tail":
		if not valid_int(ws[p + 1]): return error(Error(f"bad tail '{ws[p + 1]}'"))

		tail = to_int(ws[p + 1])
	else if ws.length() != p:
		return error(Error(usage))

	var sel = List[String]()
	for e in self.log:
		if id < 0 or e.id == id:
			sel.append(f"t={e.t} {e.actor} #{e.id} {e.detail}")

	var start = 0
	if tail >= 0 and tail < sel.length(): start = sel.length() - tail

	var lines = List[String]()
	for i in start..sel.length():
		lines.append(sel[i].clone())
	if lines.length() == 0: return ok("(no log entries)")

	return ok(lines.join("\n"))

fn view_refs(st: State, name: String, q: String) List[String]:
	var nodes = List[Node]()
	var refs = List[String]()
	qs := split_query(q)

	if s := qs:
		r := parse_filter(st, s.filter, nodes, refs)
		if r.is_ok(): return refs

	return refs

fn State.sorted_views() List[String]:
	var names = self.views.keys().clone()
	names.sort()
	return names

fn var State.cmd_view(rest: String) String!:
	ws := rest.fields()
	usage := "usage: view save|run|list|show|delete"
	if ws.length() == 0: return error(Error(usage))

	sub := ws[0]

	if sub == "list":
		names := self.sorted_views()
		if names.length() == 0: return ok("(no views)")

		var lines = List[String]()
		for n in names:
			lines.append(f"{n}: {(self.views.get(n) or "")}")
		return ok(lines.join("\n"))

	if sub == "show":
		if ws.length() != 2: return error(Error("usage: view show NAME"))

		q := self.views.get(ws[1])
		if q == null: return error(Error(f"unknown view '{ws[1]}'"))

		return ok(f"{ws[1]}: {(q)}")

	if sub == "delete":
		if ws.length() != 2: return error(Error("usage: view delete NAME"))

		name := ws[1]
		if self.views.get(name) == null: return error(Error(f"unknown view '{name}'"))

		for m in self.sorted_views():
			if m == name: continue

			refs := view_refs(self, m, self.views.get(m) or "")
			if refs.contains(name): return error(
				Error(f"view '{name}' is used by '{m}'")
			)

		self.views.remove(name.clone())
		return ok(f"deleted view {name}")

	if sub == "run":
		if ws.length() < 2: return error(
			Error("usage: view run NAME [sort FIELDS] [limit N]")
		)

		name := ws[1]
		q := self.views.get(name)
		if q == null: return error(Error(f"unknown view '{name}'"))

		spec := split_query(q)?
		extra := split_query(rest_after(rest, 2))?
		if extra.filter.trim() != "": return error(
			Error(f"unexpected '{extra.filter.trim()}'")
		)

		var sort_t: String? = spec.sort.clone()
		var lim: Int? = spec.limit
		if extra.sort != null: sort_t = extra.sort.clone()
		if extra.limit != null: lim = extra.limit
		return self.run_list(QSpec(filter: spec.filter.clone()), sort_t, lim, true)

	if sub == "save":
		if ws.length() < 2: return error(Error("usage: view save NAME QUERY"))

		name := ws[1]
		valid := valid_view_name(name)
		if not valid: return error(Error(f"bad view name '{name}'"))

		query := rest_after(rest, 2).trim()
		spec := split_query(query)?
		var nodes = List[Node]()
		var refs = List[String]()
		_root := parse_filter(self, spec.filter, nodes, refs)?
		s := spec.sort
		if s != null:
			_keys := parse_sort(s)?
		if refs.contains(name) and (self.views.get(name) != null):
			return error(Error(f"view '{name}' would reference itself"))

		self.views[name.clone()] = query.clone()
		return ok(f"saved view {name}")

	return error(Error(usage))

fn valid_view_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0 or not is_lower(cs[0]): return false

	for c in cs:
		if not (is_lower(c) or digit(c) >= 0 or c == "_" or c == "-"): return false
	return true

fn find_word(cs: List[String], w: String) Int:
	n := cs.length()
	var i = 0

	while i < n:
		if (i == 0 or is_ws(cs[i - 1])) and not is_ws(cs[i]):
			var j = i
			while j < n and not is_ws(cs[j]):
				j += 1
			if join_range(cs, i, j) == w: return i

			i = j
		else:
			i += 1

	return -1

fn var State.cmd_bulk(rest: String) String!:
	cs := rest.chars()
	wi := find_word(cs, "where")
	usage := "usage: bulk ACTION... where QUERY"
	if wi < 0: return error(Error(usage))

	action := join_range(cs, 0, wi)
	query := join_range(cs, wi + 5, cs.length())
	if action.trim() == "": return error(Error(usage))

	toks := tokenize(action)?
	act := toks[0]

	if act == "move":
		if toks.length() != 2: return error(Error("usage: bulk move STATE where QUERY"))
	else if act == "assign":
		if toks.length() != 2: return error(
			Error("usage: bulk assign NAME where QUERY")
		)
	else if act == "label":
		if toks.length() < 2: return error(
			Error("usage: bulk label +label... where QUERY")
		)
	else if act == "set":
		if toks.length() < 2: return error(
			Error("usage: bulk set field=value... where QUERY")
		)
	else:
		return error(Error(f"unknown bulk action '{act}'"))

	idxs := self.select(query)?
	var ids = List[Int]()
	for i in idxs:
		ids.append(self.issues[i].id)

	var lines = List[String]()
	var okc = 0
	var failc = 0
	rest_toks := toks.slice(1, toks.length())?

	for id in ids:
		var r: String! = ok("")

		if act == "move": r = self.do_move(id, toks[1], "")
		else if act == "assign": r = self.do_edit(id, [f"assignee={toks[1]}"])
		else if act == "label": r = self.do_label(id, rest_toks)
		else: r = self.do_edit(id, rest_toks)

		if v := r:
			lines.append(v.clone())
			okc += 1
		else:
			lines.append(f"#{id} error: {r.err().message}")
			failc += 1

	lines.append(f"bulk: {okc} ok, {failc} failed")
	return ok(lines.join("\n"))

// ---------- reports ----------

type Grp:
	name: String
	key: String
	n: Int = 0
	pts: Int = 0

type LC:
	name: String
	n: Int

fn issues_word(n: Int) String: if n == 1: "issue" else: "issues"

fn State.cmd_report(rest: String) String!:
	ws := rest.fields()
	usage := "usage: report summary|workload|labels|timeline"
	if ws.length() == 0: return error(Error(usage))

	sub := ws[0]

	if sub == "summary":
		var open_n = 0
		var unass = 0
		var overdue = 0
		var open_pts = 0
		var by_state = List[Int]()
		for s in self.wf.states:
			by_state.append(0)

		var by_prio = [0, 0, 0, 0]

		for iss in self.issues:
			by_state[iss.state] += 1
			by_prio[iss.f.priority] += 1

			if is_open(self, iss):
				open_n += 1
				if iss.f.assignee == null: unass += 1

				d := iss.f.due
				if d != null:
					if d < self.today: overdue += 1
				open_pts += (iss.f.points or 0)

		var lines = List[String]()
		total := self.issues.length()
		lines.append(f"issues: {total} (open {open_n}, final {total - open_n})")
		lines.append("by state:")
		for i in 0..self.wf.states.length():
			lines.append(f"  {self.wf.states[i]}: {by_state[i]}")
		lines.append("by priority:")

		var p = 3

		while p >= 0:
			lines.append(f"  {prio_name(p)}: {by_prio[p]}")
			p -= 1

		lines.append(f"unassigned: {unass}")
		lines.append(f"overdue: {overdue}")
		lines.append(f"open points: {open_pts}")
		return ok(lines.join("\n"))

	if sub == "workload":
		var groups = List[Grp]()
		var un_n = 0
		var un_p = 0
		var any_open = false

		for iss in self.issues:
			if not is_open(self, iss): continue

			any_open = true

			pts := iss.f.points or 0
			a := iss.f.assignee

			if a != null:
				key := a.lower()
				gi := groups.find_index(fn g: g.key == key) or (-1)

				if gi < 0:
					groups.append(Grp(a.clone(), key, 1, pts))
				else:
					groups[gi].n += 1
					groups[gi].pts += pts
			else:
				un_n += 1
				un_p += pts

		if not any_open: return ok("(no open issues)")

		groups.sort(fn a, b: grp_cmp(a, b))

		var lines = List[String]()
		for g in groups:
			lines.append(f"{g.name}: {g.n} {issues_word(g.n)}, {g.pts} points")
		if un_n > 0: lines.append(
			f"unassigned: {un_n} {issues_word(un_n)}, {un_p} points"
		)
		return ok(lines.join("\n"))

	if sub == "labels":
		idxs := self.select(rest_after(rest, 1))?
		var counts = List[LC]()

		for i in idxs:
			for l in self.issues[i].f.labels:
				gi := counts.find_index(fn c: c.name == l) or (-1)

				if gi < 0:
					counts.append(LC(l.clone(), 1))
				else:
					counts[gi].n += 1

		if counts.length() == 0: return ok("(no labels)")

		counts.sort(fn a, b: lc_cmp(a, b))

		var lines = List[String]()
		for c in counts:
			lines.append(f"{c.name}: {c.n}")
		return ok(lines.join("\n"))

	if sub == "timeline":
		if ws.length() != 2: return error(Error("usage: report timeline ID"))

		id := self.id_arg(ws[1].clone())?
		iss := self.issues[self.find(id)]
		var lines = List[String]()
		n := iss.hist_t.length()

		for i in 0..n:
			to := if i + 1 < n: iss.hist_t[i + 1] else: self.clock
			from := iss.hist_t[i]
			lines.append(
				f"{self.wf.states[iss.hist_s[i]]}: t={from}..{to} ({to - from})"
			)

		return ok(lines.join("\n"))

	return error(Error(usage))

fn grp_cmp(a: Grp, b: Grp) Int:
	if a.pts != b.pts: return cmp_int(b.pts, a.pts)
	if a.n != b.n: return cmp_int(b.n, a.n)

	return a.key.compare(b.key)

fn lc_cmp(a: LC, b: LC) Int:
	if a.n != b.n: return cmp_int(b.n, a.n)
	return a.name.compare(b.name)

// ---------- workflow ----------

fn reg(var states: List[String], name: String) Int:
	gi := states.find_index(fn x: x == name) or (-1)
	if gi >= 0: return gi

	states.append(name.clone())
	return states.length() - 1

fn parse_workflow(block: List[String]) Wf!:
	var states = List[String]()
	var finals = List[Int]()
	var initial = -1
	var trans = List[Trans]()

	for line in block:
		if line == "" or line.starts_with("#"): continue

		if line.starts_with("initial:"):
			name := rest_after_hash_n(line, 8).trim()
			if not valid_state_name(name): return error(
				Error(f"workflow: bad state name '{name}'")
			)
			if initial >= 0: return error(
				Error("workflow: initial state defined twice")
			)

			initial = reg(states, name)
		else if line.starts_with("final:"):
			for part in rest_after_hash_n(line, 6).split(","):
				name := part.trim()
				if not valid_state_name(name): return error(
					Error(f"workflow: bad state name '{name}'")
				)

				finals.append(reg(states, name))
		else if line.contains("->"):
			pos := line.index_of("->") or 0
			src := line.slice(0, pos).trim()
			if not valid_state_name(src): return error(
				Error(f"workflow: bad state name '{src}'")
			)

			si := reg(states, src)
			rest := line.slice(pos + 2, line.length())

			for entry in rest.split(","):
				ws := entry.fields()
				if ws.length() == 0: return error(Error("workflow: bad state name ''"))
				if not valid_state_name(ws[0]): return error(
					Error(f"workflow: bad state name '{ws[0]}'")
				)

				var guards = List[String]()
				if ws.length() == 2 or ws.length() > 3: return error(
					Error(f"workflow: bad line '{line}'")
				)

				if ws.length() == 3:
					if ws[1] != "requires": return error(
						Error(f"workflow: bad line '{line}'")
					)

					for g in ws[2].split("+"):
						if not (
							g == "assignee"
							or g == "points"
							or g == "due"
							or g == "labels"
							or g == "reporter"
						):
							return error(Error(f"workflow: bad guard field '{g}'"))

						guards.append(g.clone())

				di := reg(states, ws[0])
				trans.append(Trans(si, di, guards))
		else:
			return error(Error(f"workflow: bad line '{line}'"))

	if initial < 0: return error(Error("workflow: initial state missing"))

	var fl = List[Bool]()
	for s in states:
		fl.append(false)
	for f in finals:
		fl[f] = true
	for t in trans:
		if fl[t.src]: return error(
			Error(
				f"workflow: '{states[t.src]}' is final and cannot have transitions"
			)
		)
	return ok(Wf(states, fl, initial, trans))

fn rest_after_hash_n(s: String, n: Int) String:
	cs := s.chars()
	return join_range(cs, n, cs.length())

// ---------- dispatch ----------

fn var State.finish(r: String!) Void:
	if v := r:
		self.emit(v)
	else:
		self.emit(f"error: {r.err().message}")

fn var State.run_workflow(lines: List[String], start: Int) Int:
	var i = start
	var block = List[String]()

	while i < lines.length():
		t := lines[i].trim()
		i += 1
		if t == "end": break

		block.append(t.clone())

	if self.next_id > 1:
		self.emit("error: workflow: cannot redefine after issues were created")
		return i

	r := parse_workflow(block)

	if w := r:
		var cnt = w.trans.length()
		var sc = w.states.length()
		self.wf = w.clone()
		self.emit(f"workflow ok: {sc} states, {cnt} transitions")
	else:
		self.emit(f"error: {r.err().message}")

	return i

fn var State.exec(line: String) Void:
	t := line.trim()
	ws := t.fields()
	cmd := ws[0]
	rest := rest_after(t, 1)

	if cmd == "actor":
		if ws.length() != 2:
			self.emit("error: usage: actor NAME")
		else:
			self.actor = ws[1].clone()
			self.emit(f"actor is {ws[1]}")
	else if cmd == "today":
		if ws.length() != 2:
			self.emit("error: usage: today DATE")
		else if not valid_date(ws[1]):
			self.emit(f"error: bad date '{ws[1]}'")
		else:
			self.today = ws[1].clone()
			self.emit(f"today is {ws[1]}")
	else if cmd == "create": self.finish(self.cmd_create(rest))
	else if cmd == "edit": self.finish(self.cmd_edit(rest))
	else if cmd == "label": self.finish(self.cmd_label(rest))
	else if cmd == "assign": self.finish(self.cmd_assign(rest))
	else if cmd == "move": self.finish(self.cmd_move(rest))
	else if cmd == "comment": self.finish(self.cmd_comment(rest))
	else if cmd == "delete": self.finish(self.cmd_delete(rest))
	else if cmd == "show": self.finish(self.cmd_show(rest))
	else if cmd == "list": self.finish(self.cmd_list(rest))
	else if cmd == "view": self.finish(self.cmd_view(rest))
	else if cmd == "bulk": self.finish(self.cmd_bulk(rest))
	else if cmd == "log": self.finish(self.cmd_log(rest))
	else if cmd == "report": self.finish(self.cmd_report(rest))
	else: self.emit(f"error: unknown command '{cmd}'")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void!:
	bytes := read_all(stdin(), null)?
	text := bytes.decode_utf8() or ""
	lines := text.lines()
	var st = State()
	var i = 0

	while i < lines.length():
		line := lines[i].trim_end()
		i += 1

		t := line.trim()
		if t == "" or t.starts_with("#"): continue

		print(f"> {line}")

		if t.fields()[0] == "workflow":
			i = st.run_workflow(lines, i)
		else:
			st.exec(line)

		for o in st.out:
			print(o)
		st.out = []
