import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Comment:
	t: Int
	actor: String
	text: String

type Issue:
	id: Int
	title: String
	state: Int
	priority: Int = 1
	assignee: String? = none
	reporter: String? = none
	points: Int? = none
	due: String? = none
	labels: List[String] = []
	comments: List[Comment] = []
	created: Int = 0
	updated: Int = 0

type Trans:
	src: Int
	dst: Int
	guards: List[String]

type Entry:
	t: Int
	actor: String
	id: Int
	detail: String

type St:
	states: List[String] = []
	finals: List[Bool] = []
	initial: Int = -1
	trans: List[Trans] = []
	issues: List[Issue] = []
	next_id: Int = 1
	clock: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	views: Map[String, String] = Map[String, String]()
	log: List[Entry] = []

type Fields:
	title: String
	priority: Int = 1
	assignee: String? = none
	points: Int? = none
	due: String? = none
	labels: List[String] = []
	reporter: String? = none
	rep_touched: Bool = false

type Tok:
	kind: Int
	text: String
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
	vals: List[String] = []

type Query:
	nodes: List[Node]
	root: Int

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = []

type QText:
	filter: String
	has_sort: Bool
	sort: String
	limit: Int

type SortKey:
	field: String
	desc: Bool

type Pair:
	first: String
	rest: String

type Group:
	name: String
	key: String
	count: Int
	points: Int

type LCount:
	name: String
	count: Int

// ---------- helpers ----------

fn is_ws(c: String) Bool:
	return c == " " or c == "\t" or c == "\r" or c == "\n"

fn sub(cs: List[String], a: Int, b: Int) String:
	var out = ""
	for k in a..b:
		out += cs.get(k, "")
	return out

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn valid_int(s: String) Int?:
	if s.length() == 0 or s.length() > 7: return none
	if not is_digits(s): return none
	if s.length() > 1 and s.starts_with("0"): return none
	v := s.parse_int()
	if n := v:
		if n <= 1000000: return n
	return none

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false
	for k in 0..10:
		c := cs.get(k, "")
		if k == 4 or k == 7:
			if c != "-": return false
		else:
			if not "0123456789".contains(c): return false
	y := sub(cs, 0, 4).parse_int().get(0)
	m := sub(cs, 5, 7).parse_int().get(0)
	d := sub(cs, 8, 10).parse_int().get(0)
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
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(c): return false
	return true

fn valid_state_name(s: String) Bool:
	if s.length() == 0: return false
	cs := s.chars()
	if not "abcdefghijklmnopqrstuvwxyz".contains(cs.get(0, "")): return false
	for c in cs:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(c): return false
	return true

fn valid_view_name(s: String) Bool:
	if s.length() == 0: return false
	cs := s.chars()
	if not "abcdefghijklmnopqrstuvwxyz".contains(cs.get(0, "")): return false
	for c in cs:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(c): return false
	return true

fn prank(s: String) Int:
	if s == "low": return 0
	if s == "medium": return 1
	if s == "high": return 2
	if s == "critical": return 3
	return -1

fn pname(r: Int) String:
	if r == 0: return "low"
	if r == 1: return "medium"
	if r == 2: return "high"
	return "critical"

fn split_word(s: String) Pair:
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n and is_ws(cs.get(i, "")):
		i += 1
	start := i
	while i < n and not is_ws(cs.get(i, "")):
		i += 1
	word := sub(cs, start, i)
	while i < n and is_ws(cs.get(i, "")):
		i += 1
	return Pair(first: word, rest: sub(cs, i, n))

fn tokenize(s: String) List[String]!:
	cs := s.chars()
	n := cs.length()
	var out = List[String]()
	var i = 0
	while i < n:
		if is_ws(cs.get(i, "")):
			i += 1
			continue
		var cur = ""
		while i < n and not is_ws(cs.get(i, "")):
			c := cs.get(i, "")
			if c == "\"":
				i += 1
				var closed = false
				while i < n:
					d := cs.get(i, "")
					if d == "\\" and i + 1 < n and (cs.get(i + 1, "") == "\"" or cs.get(i + 1, "") == "\\"):
						cur += cs.get(i + 1, "")
						i += 2
						continue
					if d == "\"":
						closed = true
						i += 1
						break
					cur += d
					i += 1
				if not closed: return error(Error("unterminated quote"))
			else:
				cur += c
				i += 1
		out.append(cur)
	return ok(out)

fn dash(o: String?) String:
	return o.get("-")

fn pts(o: Int?) String:
	if p := o: return "{p}"
	return "-"

fn lab(l: List[String]) String:
	if l.length() == 0: return "-"
	return l.join(",")

fn norm_labels(items: List[String]) List[String]!:
	var out = List[String]()
	for it in items:
		l := it.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		if not out.contains(l): out.append(l.clone())
	out.sort()
	return ok(out)

fn parse_id(arg: String) Int!:
	s := if arg.starts_with("#"): arg.slice(1, arg.length()).get("") else: arg.clone()
	if not is_digits(s): return error(Error("bad issue id '{arg}'"))
	var k = 0
	while k < s.length() - 1 and s.slice(k, k + 1).get("") == "0":
		k += 1
	t := s.slice(k, s.length()).get("")
	if t == "0": return error(Error("bad issue id '{arg}'"))
	if t.length() > 15: return ok(999999999999999)
	return ok(t.parse_int().get(0))

// ---------- field editing ----------

fn apply_field(var f: Fields, tok: String) String?:
	p := tok.index_of("=")
	if p.is_none(): return "expected field=value, got '{tok}'"
	pos := p.get(0)
	if pos == 0: return "expected field=value, got '{tok}'"
	key := tok.slice(0, pos).get("")
	val := tok.slice(pos + 1, tok.length()).get("")
	if key == "state": return "use move to change state"
	if key == "title":
		if val.trim() == "": return "empty title"
		f.title = val.clone()
		return none
	if key == "priority":
		r := prank(val)
		if r < 0: return "bad priority '{val}'"
		f.priority = r
		return none
	if key == "assignee":
		if val == "none":
			f.assignee = none
			return none
		if val.trim() == "": return "empty assignee"
		f.assignee = val.clone()
		return none
	if key == "points":
		if val == "none":
			f.points = none
			return none
		v := valid_int(val)
		if v.is_none(): return "bad points '{val}'"
		f.points = v
		return none
	if key == "due":
		if val == "none":
			f.due = none
			return none
		if not valid_date(val): return "bad date '{val}'"
		f.due = val.clone()
		return none
	if key == "labels":
		if val == "none":
			f.labels = []
			return none
		r := norm_labels(val.split(",", none))
		if x := r:
			f.labels = x.clone()
			return none
		return r.err().message
	if key == "reporter":
		f.rep_touched = true
		if val == "none":
			f.reporter = none
			return none
		if val.trim() == "": return "empty reporter"
		f.reporter = val.clone()
		return none
	return "unknown field '{key}'"

fn fields_of(it: Issue) Fields:
	return Fields(title: it.title.clone(), priority: it.priority, assignee: it.assignee.clone(), points: it.points, due: it.due.clone(), labels: it.labels.clone(), reporter: it.reporter.clone())

// ---------- state methods ----------

fn St.state_name(i: Int) String:
	return self.states.get(i, "")

fn St.is_final(i: Int) Bool:
	return self.finals.get(i, false)

fn var St.add_log(id: Int, detail: String) Void:
	self.log.append(Entry(t: self.clock, actor: self.actor.clone(), id: id, detail: detail))

fn St.find_issue(arg: String) Int!:
	id := parse_id(arg)?
	for k in 0..self.issues.length():
		if self.issues[k].id == id: return ok(k)
	return error(Error("no such issue #{id}"))

fn St.final_err(i: Int) String?:
	if self.is_final(self.issues[i].state):
		return "#{self.issues[i].id} is in final state '{self.state_name(self.issues[i].state)}'"
	return none

fn var St.do_edit(arg: String, toks: List[String]) String!:
	i := self.find_issue(arg)?
	id := self.issues[i].id
	if e := self.final_err(i): return error(Error(e))
	var f = fields_of(self.issues[i])
	for tok in toks:
		if e := apply_field(var f, tok): return error(Error(e))
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))
	var d = List[String]()
	if self.issues[i].title != f.title: d.append("title: {self.issues[i].title} -> {f.title}")
	if self.issues[i].priority != f.priority: d.append("priority: {pname(self.issues[i].priority)} -> {pname(f.priority)}")
	if self.issues[i].assignee != f.assignee: d.append("assignee: {dash(self.issues[i].assignee)} -> {dash(f.assignee)}")
	if self.issues[i].points != f.points: d.append("points: {pts(self.issues[i].points)} -> {pts(f.points)}")
	if self.issues[i].due != f.due: d.append("due: {dash(self.issues[i].due)} -> {dash(f.due)}")
	if self.issues[i].labels != f.labels: d.append("labels: {lab(self.issues[i].labels)} -> {lab(f.labels)}")
	if self.issues[i].reporter != f.reporter: d.append("reporter: {dash(self.issues[i].reporter)} -> {dash(f.reporter)}")
	if d.length() == 0: return ok("#{id} unchanged")
	self.clock += 1
	self.issues[i].title = f.title.clone()
	self.issues[i].priority = f.priority
	self.issues[i].assignee = f.assignee.clone()
	self.issues[i].points = f.points
	self.issues[i].due = f.due.clone()
	self.issues[i].labels = f.labels.clone()
	self.issues[i].reporter = f.reporter.clone()
	self.issues[i].updated = self.clock
	for x in d:
		self.add_log(id, x.clone())
	return ok("updated #{id}")

fn var St.do_label(arg: String, ops: List[String]) String!:
	i := self.find_issue(arg)?
	if e := self.final_err(i): return error(Error(e))
	var cur = self.issues[i].labels.clone()
	for op in ops:
		var name = op.clone()
		var add = true
		if op.starts_with("+"):
			name = op.slice(1, op.length()).get("")
		else if op.starts_with("-"):
			name = op.slice(1, op.length()).get("")
			add = false
		l := name.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		if add:
			if not cur.contains(l): cur.append(l.clone())
		else:
			var nx = List[String]()
			for c in cur:
				if c != l: nx.append(c.clone())
			cur = nx
	cur.sort()
	v := if cur.length() == 0: "none" else: cur.join(",")
	return self.do_edit(arg, ["labels={v}"])

fn var St.do_move(arg: String, target: String, comment: String) String!:
	i := self.find_issue(arg)?
	id := self.issues[i].id
	if e := self.final_err(i): return error(Error(e))
	di := self.states.index_of(target)
	if di.is_none(): return error(Error("unknown state '{target}'"))
	dst := di.get(0)
	src := self.issues[i].state
	if src == dst: return error(Error("already in state '{target}'"))
	var found = -1
	for k in 0..self.trans.length():
		if self.trans[k].src == src and self.trans[k].dst == dst:
			found = k
			break
	sname := self.state_name(src)
	if found < 0: return error(Error("transition '{sname} -> {target}' not allowed"))
	var missing = List[String]()
	for g in self.trans[found].guards:
		var ok_ = true
		if g == "assignee": ok_ = self.issues[i].assignee.is_some()
		if g == "points": ok_ = self.issues[i].points.is_some()
		if g == "due": ok_ = self.issues[i].due.is_some()
		if g == "labels": ok_ = self.issues[i].labels.length() > 0
		if g == "reporter": ok_ = self.issues[i].reporter.is_some()
		if not ok_: missing.append(g.clone())
	if missing.length() > 0: return error(Error("cannot move #{id} to {target}: missing {missing.join(", ")}"))
	self.clock += 1
	self.issues[i].state = dst
	self.issues[i].updated = self.clock
	self.add_log(id, "state: {sname} -> {target}")
	if comment != "":
		self.issues[i].comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: comment.clone()))
		self.add_log(id, "comment: {comment}")
	return ok("moved #{id}: {sname} -> {target}")

fn var St.do_create(rest: String) String!:
	if self.states.length() == 0: return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: create TITLE [field=value...]"))
	first := toks.get(0, "")
	if first.trim() == "": return error(Error("empty title"))
	var f = Fields(title: first.clone())
	for k in 1..toks.length():
		if e := apply_field(var f, toks.get(k, "")): return error(Error(e))
	if not f.rep_touched: f.reporter = self.actor.clone()
	self.clock += 1
	id := self.next_id
	self.next_id += 1
	it := Issue(id: id, title: f.title.clone(), state: self.initial, priority: f.priority, assignee: f.assignee.clone(), reporter: f.reporter.clone(), points: f.points, due: f.due.clone(), labels: f.labels.clone(), created: self.clock, updated: self.clock)
	self.issues.append(it)
	self.add_log(id, "created \"{first}\"")
	if f.title != first: self.add_log(id, "title: {first} -> {f.title}")
	if f.priority != 1: self.add_log(id, "priority: medium -> {pname(f.priority)}")
	if f.assignee.is_some(): self.add_log(id, "assignee: - -> {dash(f.assignee)}")
	if f.points.is_some(): self.add_log(id, "points: - -> {pts(f.points)}")
	if f.due.is_some(): self.add_log(id, "due: - -> {dash(f.due)}")
	if f.labels.length() > 0: self.add_log(id, "labels: - -> {lab(f.labels)}")
	if f.rep_touched and f.reporter.is_some(): self.add_log(id, "reporter: - -> {dash(f.reporter)}")
	return ok("created #{id}")

fn var St.do_comment(rest: String) String!:
	a := split_word(rest)
	b := split_word(a.rest)
	if a.first == "" or b.first == "": return error(Error("usage: comment ID TEXT"))
	text := a.rest.clone()
	i := self.find_issue(a.first)?
	id := self.issues[i].id
	self.clock += 1
	self.issues[i].updated = self.clock
	self.issues[i].comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: text.clone()))
	self.add_log(id, "comment: {text}")
	return ok("commented #{id}")

fn var St.do_delete(rest: String) String!:
	w := rest.fields()
	if w.length() != 1: return error(Error("usage: delete ID"))
	i := self.find_issue(w.get(0, ""))?
	id := self.issues[i].id
	self.clock += 1
	self.issues.remove(i)
	self.add_log(id, "deleted")
	return ok("deleted #{id}")

fn St.do_show(rest: String) String!:
	w := rest.fields()
	if w.length() != 1: return error(Error("usage: show ID"))
	i := self.find_issue(w.get(0, ""))?
	it := self.issues[i]
	var out = "#{it.id} {it.title}\n"
	out += "  state: {self.state_name(it.state)}\n"
	out += "  priority: {pname(it.priority)}\n"
	out += "  assignee: {dash(it.assignee)}\n"
	out += "  points: {pts(it.points)}\n"
	out += "  due: {dash(it.due)}\n"
	ls := if it.labels.length() == 0: "-" else: it.labels.join(", ")
	out += "  labels: {ls}\n"
	out += "  reporter: {dash(it.reporter)}\n"
	out += "  created: t={it.created}, updated: t={it.updated}\n"
	out += "  comments: {it.comments.length()}"
	for c in it.comments:
		out += "\n    [t={c.t} {c.actor}] {c.text}"
	return ok(out)

// ---------- query ----------

fn is_field_char(c: String) Bool:
	return c == "_" or "abcdefghijklmnopqrstuvwxyz".contains(c)

fn lex(text: String) List[Tok]:
	cs := text.chars()
	n := cs.length()
	var toks = List[Tok]()
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if is_ws(c):
			i += 1
			continue
		if c == "(":
			toks.append(Tok(kind: 5, text: "("))
			i += 1
			continue
		if c == ")":
			toks.append(Tok(kind: 6, text: ")"))
			i += 1
			continue
		var j = i
		while j < n and is_field_char(cs.get(j, "")):
			j += 1
		var op = ""
		if j > i and j < n:
			c1 := cs.get(j, "")
			c2 := cs.get(j + 1, "")
			if (c1 == "!" or c1 == "<" or c1 == ">") and c2 == "=":
				op = c1 + c2
			else if c1 == ":" or c1 == "<" or c1 == ">" or c1 == "~":
				op = c1.clone()
		if op != "":
			field := sub(cs, i, j)
			k := j + op.length()
			if k < n and cs.get(k, "") == "\"":
				var m = k + 1
				var val = ""
				var closed = false
				while m < n:
					d := cs.get(m, "")
					if d == "\\" and m + 1 < n and (cs.get(m + 1, "") == "\"" or cs.get(m + 1, "") == "\\"):
						val += cs.get(m + 1, "")
						m += 2
						continue
					if d == "\"":
						closed = true
						m += 1
						break
					val += d
					m += 1
				if not closed:
					toks.append(Tok(kind: 7, text: "query: unterminated quote"))
					return toks
				toks.append(Tok(kind: 1, text: sub(cs, i, m), field: field, op: op, value: val, quoted: true))
				i = m
			else:
				var m = k
				while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
					m += 1
				toks.append(Tok(kind: 1, text: sub(cs, i, m), field: field, op: op, value: sub(cs, k, m)))
				i = m
			continue
		var m = i
		while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
			m += 1
		w := sub(cs, i, m)
		var kind = 0
		if w == "AND": kind = 2
		if w == "OR": kind = 3
		if w == "NOT": kind = 4
		toks.append(Tok(kind: kind, text: w))
		i = m
	return toks

fn allowed_ops(field: String) List[String]:
	if field == "id" or field == "created" or field == "updated" or field == "points" or field == "priority" or field == "due":
		return [":", "!=", "<", "<=", ">", ">="]
	if field == "title" or field == "assignee" or field == "reporter" or field == "label" or field == "labels":
		return [":", "!=", "~"]
	if field == "text": return ["~"]
	if field == "state": return [":", "!="]
	if field == "is" or field == "has" or field == "view": return [":"]
	return []

fn bad_value(v: String, field: String) Error:
	return Error("query: bad value '{v}' for field '{field}'")

fn validate_term(st: St, field: String, op: String, value: String, quoted: Bool) List[String]!:
	ops := allowed_ops(field)
	if ops.length() == 0: return error(Error("query: unknown field '{field}'"))
	if not ops.contains(op): return error(Error("query: bad operator '{op}' for field '{field}'"))
	var alts = List[String]()
	if field == "view":
		if not st.views.contains(value): return error(Error("query: unknown view '{value}'"))
		alts.append(value.clone())
		return ok(alts)
	splittable := (op == ":" or op == "!=" or op == "~") and not quoted
	if splittable:
		for p in value.split("|", none):
			alts.append(p.clone())
	else:
		alts.append(value.clone())
	eqop := op == ":" or op == "!="
	for a in alts:
		var good = true
		if field == "id" or field == "created" or field == "updated":
			good = valid_int(a).is_some()
		else if field == "points":
			good = valid_int(a).is_some() or (a == "none" and eqop)
		else if field == "state":
			good = st.states.contains(a)
		else if field == "priority":
			good = prank(a) >= 0
		else if field == "due":
			good = valid_date(a) or (a == "none" and eqop)
		else if field == "is":
			good = a == "open" or a == "final" or a == "overdue" or a == "unassigned"
		else if field == "has":
			good = a == "assignee" or a == "due" or a == "points" or a == "labels" or a == "comments" or a == "reporter"
		if not good: return error(bad_value(a, field))
	return ok(alts)

fn var Parser.peek_kind() Int:
	if self.pos < self.toks.length(): return self.toks[self.pos].kind
	return -1

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.unexpected() Error:
	if self.pos >= self.toks.length(): return Error("query: unexpected end of query")
	return Error("query: unexpected token '{self.toks[self.pos].text}'")

fn var Parser.parse_not(st: St) Int!:
	k := self.peek_kind()
	if k == -1: return error(Error("query: unexpected end of query"))
	if k == 7: return error(Error(self.toks[self.pos].text.clone()))
	if k == 4:
		self.pos += 1
		inner := self.parse_not(st)?
		return ok(self.add(Node(kind: 3, a: inner)))
	if k == 5:
		self.pos += 1
		e := self.parse_or(st)?
		k2 := self.peek_kind()
		if k2 == 6:
			self.pos += 1
			return ok(e)
		return error(self.unexpected())
	if k == 1:
		tf := self.toks[self.pos].field.clone()
		to := self.toks[self.pos].op.clone()
		tv := self.toks[self.pos].value.clone()
		tq := self.toks[self.pos].quoted
		vals := validate_term(st, tf, to, tv, tq)?
		self.pos += 1
		return ok(self.add(Node(kind: 0, field: tf, op: to, vals: vals.clone())))
	return error(self.unexpected())

fn var Parser.parse_and(st: St) Int!:
	var left = self.parse_not(st)?
	while true:
		k := self.peek_kind()
		if k == 2:
			self.pos += 1
		else if k == 1 or k == 4 or k == 5 or k == 0 or k == 7:
			self.pos += 0
		else:
			break
		right := self.parse_not(st)?
		left = self.add(Node(kind: 1, a: left, b: right))
	return ok(left)

fn var Parser.parse_or(st: St) Int!:
	var left = self.parse_and(st)?
	while self.peek_kind() == 3:
		self.pos += 1
		right := self.parse_and(st)?
		left = self.add(Node(kind: 2, a: left, b: right))
	return ok(left)

fn parse_filter(st: St, text: String) Query!:
	if text.trim() == "": return ok(Query(nodes: [], root: -1))
	var p = Parser(toks: lex(text))
	root := p.parse_or(st)?
	if p.pos < p.toks.length(): return error(p.unexpected())
	return ok(Query(nodes: p.nodes.clone(), root: root))

fn find_word(cs: List[String], w: String, allow_end: Bool) Int:
	n := cs.length()
	wl := w.chars().length()
	var i = 0
	while i + wl <= n:
		if sub(cs, i, i + wl) == w and (i == 0 or is_ws(cs.get(i - 1, ""))):
			if i + wl == n:
				if allow_end: return i
			else if is_ws(cs.get(i + wl, "")):
				return i
		i += 1
	return -1

fn split_query(text: String) QText!:
	cs := text.chars()
	n := cs.length()
	var e = n
	while e > 0 and is_ws(cs.get(e - 1, "")):
		e -= 1
	var a = e
	while a > 0 and not is_ws(cs.get(a - 1, "")):
		a -= 1
	var b = a
	while b > 0 and is_ws(cs.get(b - 1, "")):
		b -= 1
	var c = b
	while c > 0 and not is_ws(cs.get(c - 1, "")):
		c -= 1
	var limit = -1
	var rem = text.clone()
	if a < e and b < a and b > c and sub(cs, c, b) == "limit":
		arg := sub(cs, a, e)
		v := valid_int(arg)
		if x := v:
			limit = x
		else:
			return error(Error("bad limit '{arg}'"))
		rem = sub(cs, 0, c)
	rcs := rem.chars()
	sp := find_word(rcs, "sort", false)
	if sp >= 0:
		return ok(QText(filter: sub(rcs, 0, sp), has_sort: true, sort: sub(rcs, sp + 4, rcs.length()), limit: limit))
	return ok(QText(filter: rem.clone(), has_sort: false, sort: "", limit: limit))

fn parse_sort(text: String) List[SortKey]!:
	var out = List[SortKey]()
	known := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	var norm = text.replace(",", " ")
	for w in norm.fields():
		var name = w.clone()
		var desc = false
		if w.starts_with("-"):
			name = w.slice(1, w.length()).get("")
			desc = true
		if not known.contains(name): return error(Error("bad sort field '{name}'"))
		out.append(SortKey(field: name.clone(), desc: desc))
	return ok(out)

fn refs_in(q: Query) List[String]:
	var out = List[String]()
	for n in q.nodes:
		if n.kind == 0 and n.field == "view":
			out.append(n.vals.get(0, ""))
	return out

fn cmp_ci(a: String, b: String) Int:
	return a.lower().compare(b.lower())

fn cmp_opt_int(a: Int?, b: Int?) Int:
	if x := a:
		if y := b: return x.compare(y)
		return -1
	if b.is_some(): return 1
	return 0

fn cmp_opt_str(a: String?, b: String?, ci: Bool) Int:
	if x := a:
		if y := b:
			if ci: return cmp_ci(x, y)
			return x.compare(y)
		return -1
	if b.is_some(): return 1
	return 0

fn cmp_field(st: St, f: String, x: Int, y: Int) Int:
	if f == "id": return st.issues[x].id.compare(st.issues[y].id)
	if f == "created": return st.issues[x].created.compare(st.issues[y].created)
	if f == "updated": return st.issues[x].updated.compare(st.issues[y].updated)
	if f == "priority": return st.issues[x].priority.compare(st.issues[y].priority)
	if f == "points": return cmp_opt_int(st.issues[x].points, st.issues[y].points)
	if f == "state": return st.issues[x].state.compare(st.issues[y].state)
	if f == "title": return cmp_ci(st.issues[x].title, st.issues[y].title)
	if f == "assignee": return cmp_opt_str(st.issues[x].assignee, st.issues[y].assignee, true)
	if f == "reporter": return cmp_opt_str(st.issues[x].reporter, st.issues[y].reporter, true)
	if f == "due": return cmp_opt_str(st.issues[x].due, st.issues[y].due, false)
	return 0

fn cmp_by(st: St, keys: List[SortKey], x: Int, y: Int) Int:
	for k in keys:
		c := cmp_field(st, k.field, x, y)
		if c != 0:
			if k.desc: return 0 - c
			return c
	return st.issues[x].id.compare(st.issues[y].id)

fn cmp_op(c: Int, op: String) Bool:
	if op == ":": return c == 0
	if op == "!=": return c != 0
	if op == "<": return c < 0
	if op == "<=": return c <= 0
	if op == ">": return c > 0
	return c >= 0

fn is_open(st: St, it: Issue) Bool:
	return not st.is_final(it.state)

fn match_eq(st: St, it: Issue, f: String, alt: String) Bool:
	if f == "id": return it.id == alt.parse_int().get(-1)
	if f == "created": return it.created == alt.parse_int().get(-1)
	if f == "updated": return it.updated == alt.parse_int().get(-1)
	if f == "points":
		if p := it.points: return alt != "none" and p == alt.parse_int().get(-1)
		return alt == "none"
	if f == "title": return cmp_ci(it.title, alt) == 0
	if f == "assignee":
		if a := it.assignee: return cmp_ci(a, alt) == 0
		return alt == "none"
	if f == "reporter":
		if a := it.reporter: return cmp_ci(a, alt) == 0
		return alt == "none"
	if f == "state": return st.state_name(it.state) == alt
	if f == "priority": return it.priority == prank(alt)
	if f == "due":
		if d := it.due: return d == alt
		return alt == "none"
	if f == "label" or f == "labels":
		l := alt.lower()
		if l == "none": return it.labels.length() == 0
		return it.labels.contains(l)
	if f == "is":
		if alt == "open": return is_open(st, it)
		if alt == "final": return not is_open(st, it)
		if alt == "overdue":
			if d := it.due: return is_open(st, it) and d < st.today
			return false
		return it.assignee.is_none()
	if f == "has":
		if alt == "assignee": return it.assignee.is_some()
		if alt == "due": return it.due.is_some()
		if alt == "points": return it.points.is_some()
		if alt == "labels": return it.labels.length() > 0
		if alt == "comments": return it.comments.length() > 0
		return it.reporter.is_some()
	return false

fn match_sub(it: Issue, f: String, alt: String) Bool:
	a := alt.lower()
	if f == "title": return it.title.lower().contains(a)
	if f == "assignee":
		if x := it.assignee: return x.lower().contains(a)
		return false
	if f == "reporter":
		if x := it.reporter: return x.lower().contains(a)
		return false
	if f == "text":
		if it.title.lower().contains(a): return true
		for c in it.comments:
			if c.text.lower().contains(a): return true
		return false
	for l in it.labels:
		if l.contains(a): return true
	return false

fn match_ord(it: Issue, f: String, op: String, alt: String) Bool:
	if f == "id": return cmp_op(it.id.compare(alt.parse_int().get(0)), op)
	if f == "created": return cmp_op(it.created.compare(alt.parse_int().get(0)), op)
	if f == "updated": return cmp_op(it.updated.compare(alt.parse_int().get(0)), op)
	if f == "points":
		if p := it.points: return cmp_op(p.compare(alt.parse_int().get(0)), op)
		return false
	if f == "priority": return cmp_op(it.priority.compare(prank(alt)), op)
	if f == "due":
		if d := it.due: return cmp_op(d.compare(alt), op)
		return false
	return false

fn eval_term(st: St, it: Issue, f: String, op: String, vals: List[String]) Bool:
	if f == "view":
		qt := split_query(st.views.get_or(vals.get(0, ""), ""))
		if t := qt:
			q := parse_filter(st, t.filter)
			if x := q:
				if x.root < 0: return true
				return eval(st, x, x.root, it)
		return false
	if op == ":" or op == "!=":
		var any = false
		for a in vals:
			if match_eq(st, it, f, a):
				any = true
				break
		if op == ":": return any
		return not any
	if op == "~":
		for a in vals:
			if match_sub(it, f, a): return true
		return false
	return match_ord(it, f, op, vals.get(0, ""))

fn eval(st: St, q: Query, n: Int, it: Issue) Bool:
	node := q.nodes[n]
	if node.kind == 0: return eval_term(st, it, node.field, node.op, node.vals)
	if node.kind == 1: return eval(st, q, node.a, it) and eval(st, q, node.b, it)
	if node.kind == 2: return eval(st, q, node.a, it) or eval(st, q, node.b, it)
	return not eval(st, q, node.a, it)

fn issue_line(st: St, it: Issue) String:
	return "#{it.id} | {st.state_name(it.state)} | {pname(it.priority)} | {dash(it.assignee)} | {pts(it.points)} | {dash(it.due)} | {lab(it.labels)} | {it.title}"

fn St.matching(q: Query) List[Int]:
	var idx = List[Int]()
	for k in 0..self.issues.length():
		if q.root < 0 or eval(self, q, q.root, self.issues[k]): idx.append(k)
	return idx

fn St.run_list(filter: String, sort: String, limit: Int) String!:
	q := parse_filter(self, filter)?
	keys := parse_sort(sort)?
	var idx = self.matching(q)
	idx.sort(fn a, b: cmp_by(self, keys, a, b))
	var out = ""
	var count = 0
	for k in idx:
		if limit >= 0 and count >= limit: break
		out += issue_line(self, self.issues[k]) + "\n"
		count += 1
	if count == 1:
		out += "(1 issue)"
	else:
		out += "({count} issues)"
	return ok(out)

fn St.cmd_list(rest: String) String!:
	qt := split_query(rest)?
	return self.run_list(qt.filter, qt.sort, qt.limit)

// ---------- views ----------

fn St.reach(start: List[String]) Set[String]:
	var seen = Set[String]()
	var stack = start.clone()
	while stack.length() > 0:
		v := stack.pop().get("")
		if seen.contains(v): continue
		seen.add(v.clone())
		if not self.views.contains(v): continue
		qt := split_query(self.views.get_or(v, ""))
		if t := qt:
			q := parse_filter(self, t.filter)
			if x := q:
				for r in refs_in(x):
					stack.append(r.clone())
	return seen

fn var St.cmd_view(rest: String) String!:
	a := split_word(rest)
	usage := "usage: view save|run|list|show|delete"
	if a.first == "save":
		b := split_word(a.rest)
		if b.first == "": return error(Error("usage: view save NAME QUERY"))
		name := b.first
		if not valid_view_name(name): return error(Error("bad view name '{name}'"))
		query := b.rest.trim()
		qt := split_query(query)?
		q := parse_filter(self, qt.filter)?
		_k := parse_sort(qt.sort)?
		var start = List[String]()
		for r in refs_in(q):
			start.append(r.clone())
		if self.views.contains(name):
			var seen = Set[String]()
			var stack = start.clone()
			while stack.length() > 0:
				v := stack.pop().get("")
				if v == name: return error(Error("view '{name}' would reference itself"))
				if seen.contains(v): continue
				seen.add(v.clone())
				vq := split_query(self.views.get_or(v, ""))
				if t := vq:
					pq := parse_filter(self, t.filter)
					if x := pq:
						for r in refs_in(x):
							stack.append(r.clone())
		self.views[name.clone()] = query.clone()
		return ok("saved view {name}")
	if a.first == "run":
		b := split_word(a.rest)
		if b.first == "": return error(Error("usage: view run NAME [sort FIELDS] [limit N]"))
		if not self.views.contains(b.first): return error(Error("unknown view '{b.first}'"))
		ex := split_query(b.rest)?
		if ex.filter.trim() != "": return error(Error("unexpected '{ex.filter.trim()}'"))
		_k := parse_sort(ex.sort)?
		st0 := split_query(self.views.get_or(b.first, ""))?
		sortt := if ex.has_sort: ex.sort.clone() else: st0.sort.clone()
		limit := if ex.limit >= 0: ex.limit else: st0.limit
		return self.run_list(st0.filter, sortt, limit)
	if a.first == "list":
		if self.views.length() == 0: return ok("(no views)")
		names := self.views.keys().sorted()
		var out = List[String]()
		for n in names:
			out.append("{n}: {self.views.get_or(n, "")}")
		return ok(out.join("\n"))
	if a.first == "show":
		w := a.rest.fields()
		if w.length() != 1: return error(Error("usage: view show NAME"))
		n := w.get(0, "")
		if not self.views.contains(n): return error(Error("unknown view '{n}'"))
		return ok("{n}: {self.views.get_or(n, "")}")
	if a.first == "delete":
		w := a.rest.fields()
		if w.length() != 1: return error(Error("usage: view delete NAME"))
		n := w.get(0, "")
		if not self.views.contains(n): return error(Error("unknown view '{n}'"))
		names := self.views.keys().sorted()
		for m in names:
			if m == n: continue
			var start = List[String]()
			vq := split_query(self.views.get_or(m, ""))
			if t := vq:
				pq := parse_filter(self, t.filter)
				if x := pq:
					for r in refs_in(x):
						start.append(r.clone())
			if self.reach(start).contains(n): return error(Error("view '{n}' is used by '{m}'"))
		self.views.remove(n.clone())
		return ok("deleted view {n}")
	return error(Error(usage))

// ---------- bulk ----------

fn var St.cmd_bulk(rest: String) String!:
	cs := rest.chars()
	w := find_word(cs, "where", true)
	usage := "usage: bulk ACTION... where QUERY"
	if w < 0: return error(Error(usage))
	action := sub(cs, 0, w)
	query := sub(cs, w + 5, cs.length())
	if action.trim() == "": return error(Error(usage))
	toks := tokenize(action)?
	kind := toks.get(0, "")
	n := toks.length()
	if kind == "move":
		if n != 2: return error(Error("usage: bulk move STATE where QUERY"))
	else if kind == "assign":
		if n != 2: return error(Error("usage: bulk assign NAME where QUERY"))
	else if kind == "label":
		if n < 2: return error(Error("usage: bulk label +label... where QUERY"))
	else if kind == "set":
		if n < 2: return error(Error("usage: bulk set field=value... where QUERY"))
	else:
		return error(Error("unknown bulk action '{kind}'"))
	q := parse_filter(self, query)?
	var ids = List[Int]()
	for k in self.matching(q):
		ids.append(self.issues[k].id)
	var lines = List[String]()
	var good = 0
	var bad = 0
	for id in ids:
		arg := "#{id}"
		var r: String! = ok("")
		if kind == "move":
			r = self.do_move(arg, toks.get(1, ""), "")
		else if kind == "assign":
			r = self.do_edit(arg, ["assignee={toks.get(1, "")}"])
		else if kind == "label":
			r = self.do_label(arg, toks.slice(1, n).get([]))
		else:
			r = self.do_edit(arg, toks.slice(1, n).get([]))
		if v := r:
			good += 1
			lines.append(v.clone())
		else:
			bad += 1
			lines.append("#{id} error: {r.err().message}")
	lines.append("bulk: {good} ok, {bad} failed")
	return ok(lines.join("\n"))

// ---------- log & reports ----------

fn St.cmd_log(rest: String) String!:
	w := rest.fields()
	n := w.length()
	var idf = ""
	var tail = -1
	if n == 0:
		idf = ""
	else if w.get(0, "") == "tail":
		if n != 2: return error(Error("usage: log [ID] [tail N]"))
		tail = 0
	else if n == 1:
		idf = w.get(0, "")
	else if n == 3 and w.get(1, "") == "tail":
		idf = w.get(0, "")
		tail = 2
	else:
		return error(Error("usage: log [ID] [tail N]"))
	var id = -1
	if idf != "":
		id = parse_id(idf)?
		if id >= self.next_id: return error(Error("no such issue #{id}"))
	var limit = -1
	if tail >= 0:
		arg := w.get(n - 1, "")
		v := valid_int(arg)
		if x := v:
			limit = x
		else:
			return error(Error("bad tail '{arg}'"))
	var sel = List[String]()
	for e in self.log:
		if id < 0 or e.id == id:
			sel.append("t={e.t} {e.actor} #{e.id} {e.detail}")
	if sel.length() == 0: return ok("(no log entries)")
	var start = 0
	if limit >= 0 and limit < sel.length(): start = sel.length() - limit
	if start >= sel.length(): return ok("(no log entries)")
	return ok(sel.slice(start, sel.length()).get([]).join("\n"))

fn St.report_summary() String:
	var total = 0
	var open = 0
	var final = 0
	var un = 0
	var od = 0
	var op = 0
	var bystate = List[Int]()
	for _s in self.states:
		bystate.append(0)
	var bypri = [0, 0, 0, 0]
	for it in self.issues:
		total += 1
		bystate.replace(it.state, bystate.get(it.state, 0) + 1)
		bypri.replace(it.priority, bypri.get(it.priority, 0) + 1)
		if is_open(self, it):
			open += 1
			if it.assignee.is_none(): un += 1
			if d := it.due:
				if d < self.today: od += 1
			op += it.points.get(0)
		else:
			final += 1
	var out = "issues: {total} (open {open}, final {final})\nby state:"
	for k in 0..self.states.length():
		out += "\n  {self.states.get(k, "")}: {bystate.get(k, 0)}"
	out += "\nby priority:"
	var r = 3
	while r >= 0:
		out += "\n  {pname(r)}: {bypri.get(r, 0)}"
		r -= 1
	out += "\nunassigned: {un}\noverdue: {od}\nopen points: {op}"
	return out

fn plural(n: Int) String:
	if n == 1: return "issue"
	return "issues"

fn St.report_workload() String:
	var groups = List[Group]()
	var un = 0
	var unp = 0
	var any = false
	for it in self.issues:
		if not is_open(self, it): continue
		any = true
		p := it.points.get(0)
		if a := it.assignee:
			key := a.lower()
			var found = false
			for k in 0..groups.length():
				if groups[k].key == key:
					groups[k].count += 1
					groups[k].points += p
					found = true
					break
			if not found: groups.append(Group(name: a.clone(), key: key.clone(), count: 1, points: p))
		else:
			un += 1
			unp += p
	if not any: return "(no open issues)"
	groups.sort(fn a, b: if a.points != b.points: b.points.compare(a.points) else: if a.count != b.count: b.count.compare(a.count) else: a.key.compare(b.key))
	var lines = List[String]()
	for g in groups:
		lines.append("{g.name}: {g.count} {plural(g.count)}, {g.points} points")
	if un > 0: lines.append("unassigned: {un} {plural(un)}, {unp} points")
	return lines.join("\n")

fn St.report_labels(filter: String) String!:
	q := parse_filter(self, filter)?
	var counts = List[LCount]()
	for k in self.matching(q):
		for l in self.issues[k].labels:
			var found = false
			for j in 0..counts.length():
				if counts[j].name == l:
					counts[j].count += 1
					found = true
					break
			if not found: counts.append(LCount(name: l.clone(), count: 1))
	if counts.length() == 0: return ok("(no labels)")
	counts.sort(fn a, b: if a.count != b.count: b.count.compare(a.count) else: a.name.compare(b.name))
	var lines = List[String]()
	for c in counts:
		lines.append("{c.name}: {c.count}")
	return ok(lines.join("\n"))

fn St.report_timeline(arg: String) String!:
	i := self.find_issue(arg)?
	id := self.issues[i].id
	var cur = self.state_name(self.initial)
	var from = self.issues[i].created
	var lines = List[String]()
	for e in self.log:
		if e.id == id and e.detail.starts_with("state: "):
			p := e.detail.index_of(" -> ").get(0)
			lines.append("{cur}: t={from}..{e.t} ({e.t - from})")
			cur = e.detail.slice(p + 4, e.detail.length()).get("")
			from = e.t
	lines.append("{cur}: t={from}..{self.clock} ({self.clock - from})")
	return ok(lines.join("\n"))

fn St.cmd_report(rest: String) String!:
	a := split_word(rest)
	usage := "usage: report summary|workload|labels|timeline"
	if a.first == "summary": return ok(self.report_summary())
	if a.first == "workload": return ok(self.report_workload())
	if a.first == "labels": return self.report_labels(a.rest)
	if a.first == "timeline":
		w := a.rest.fields()
		if w.length() != 1: return error(Error("usage: report timeline ID"))
		return self.report_timeline(w.get(0, ""))
	return error(Error(usage))

// ---------- workflow ----------

fn state_idx(var states: List[String], name: String) Int:
	k := states.index_of(name)
	if x := k: return x
	states.append(name.clone())
	return states.length() - 1

fn var St.define_workflow(block: List[String]) Void:
	if self.next_id > 1:
		print("error: workflow: cannot redefine after issues were created")
		return
	var states = List[String]()
	var finals = List[String]()
	var trans = List[Trans]()
	var initial = ""
	var has_initial = false
	var err = ""
	var count = 0
	guards_ok := ["assignee", "points", "due", "labels", "reporter"]
	for raw in block:
		line := raw.trim()
		if line == "" or line.starts_with("#"): continue
		if err != "": continue
		if line.starts_with("initial:"):
			name := line.slice(8, line.length()).get("").trim()
			if not valid_state_name(name):
				err = "workflow: bad state name '{name}'"
			else if has_initial:
				err = "workflow: initial state defined twice"
			else:
				has_initial = true
				initial = name.clone()
				_x := state_idx(var states, name)
		else if line.starts_with("final:"):
			for part in line.slice(6, line.length()).get("").split(",", none):
				name := part.trim()
				if err != "": break
				if not valid_state_name(name):
					err = "workflow: bad state name '{name}'"
				else:
					finals.append(name.clone())
					_x := state_idx(var states, name)
		else if line.contains("->"):
			p := line.index_of("->").get(0)
			src := line.slice(0, p).get("").trim()
			if not valid_state_name(src):
				err = "workflow: bad state name '{src}'"
				continue
			si := state_idx(var states, src)
			for part in line.slice(p + 2, line.length()).get("").split(",", none):
				if err != "": break
				ws := part.fields()
				var gs = List[String]()
				if ws.length() == 3 and ws.get(1, "") == "requires":
					for g in ws.get(2, "").split("+", none):
						gs.append(g.clone())
				else if ws.length() != 1:
					err = "workflow: bad line '{line}'"
					break
				target := ws.get(0, "")
				if not valid_state_name(target):
					err = "workflow: bad state name '{target}'"
					break
				if ws.length() == 3:
					for g in gs:
						if not guards_ok.contains(g):
							err = "workflow: bad guard field '{g}'"
							break
					if err != "": break
				di := state_idx(var states, target)
				trans.append(Trans(src: si, dst: di, guards: gs.clone()))
				count += 1
		else:
			err = "workflow: bad line '{line}'"
	if err == "" and not has_initial: err = "workflow: initial state missing"
	if err == "":
		for t in trans:
			nm := states.get(t.src, "")
			if finals.contains(nm):
				err = "workflow: '{nm}' is final and cannot have transitions"
				break
	if err != "":
		print("error: {err}")
		return
	var fl = List[Bool]()
	for s in states:
		fl.append(finals.contains(s))
	self.initial = states.index_of(initial).get(0)
	self.states = states.clone()
	self.finals = fl
	self.trans = trans.clone()
	print("workflow ok: {states.length()} states, {count} transitions")

// ---------- dispatch ----------

fn emit(r: String!) Void:
	if v := r:
		print(v)
	else:
		print("error: {r.err().message}")

fn var St.exec(cmd: String, rest: String) Void:
	if cmd == "actor":
		w := rest.fields()
		if w.length() != 1:
			print("error: usage: actor NAME")
			return
		self.actor = w.get(0, "")
		print("actor is {self.actor}")
	else if cmd == "today":
		w := rest.fields()
		if w.length() != 1:
			print("error: usage: today DATE")
			return
		if not valid_date(w.get(0, "")):
			print("error: bad date '{w.get(0, "")}'")
			return
		self.today = w.get(0, "")
		print("today is {self.today}")
	else if cmd == "create":
		emit(self.do_create(rest))
	else if cmd == "edit":
		emit(self.cmd_edit(rest))
	else if cmd == "label":
		emit(self.cmd_label(rest))
	else if cmd == "assign":
		emit(self.cmd_assign(rest))
	else if cmd == "move":
		a := split_word(rest)
		b := split_word(a.rest)
		if a.first == "" or b.first == "":
			print("error: usage: move ID STATE [comment...]")
			return
		emit(self.do_move(a.first, b.first, b.rest))
	else if cmd == "comment":
		emit(self.do_comment(rest))
	else if cmd == "delete":
		emit(self.do_delete(rest))
	else if cmd == "show":
		emit(self.do_show(rest))
	else if cmd == "list":
		emit(self.cmd_list(rest))
	else if cmd == "view":
		emit(self.cmd_view(rest))
	else if cmd == "bulk":
		emit(self.cmd_bulk(rest))
	else if cmd == "log":
		emit(self.cmd_log(rest))
	else if cmd == "report":
		emit(self.cmd_report(rest))
	else:
		print("error: unknown command '{cmd}'")

fn var St.cmd_edit(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))
	return self.do_edit(toks.get(0, ""), toks.slice(1, toks.length()).get([]))

fn var St.cmd_label(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() < 2: return error(Error("usage: label ID +label -label..."))
	return self.do_label(toks.get(0, ""), toks.slice(1, toks.length()).get([]))

fn var St.cmd_assign(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() != 2: return error(Error("usage: assign ID NAME"))
	return self.do_edit(toks.get(0, ""), ["assignee={toks.get(1, "")}"])

// ms: allow_effect std.console.write
fn main() Void!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	lines := text.split("\n", none)
	var st = St()
	var i = 0
	while i < lines.length():
		raw := lines.get(i, "")
		i += 1
		line := raw.trim_end()
		t := line.trim()
		if t == "" or t.starts_with("#"): continue
		print("> {line}")
		a := split_word(line)
		if a.first == "workflow":
			var block = List[String]()
			while i < lines.length():
				l := lines.get(i, "")
				i += 1
				if l.trim() == "end": break
				block.append(l.clone())
			st.define_workflow(block)
		else:
			st.exec(a.first, a.rest)
