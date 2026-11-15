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
	from_state: String = ""
	to_state: String = ""

type Trans:
	dst: Int
	guards: List[String]

type TLine:
	src: Int
	dst: Int
	guards: List[String]

type Workflow:
	states: List[String] = []
	initial: Int = 0
	finals: List[Bool] = []
	trans: List[List[Trans]] = []

type Patch:
	count: Int = 0
	has_title: Bool = false
	title: String = ""
	has_prio: Bool = false
	prio: Int = 1
	has_assignee: Bool = false
	assignee: String = ""
	has_points: Bool = false
	points: Int = -1
	has_due: Bool = false
	due: String = ""
	has_labels: Bool = false
	labels: List[String] = []
	has_reporter: Bool = false
	reporter: String = ""

type Tracker:
	wf: Workflow = Workflow()
	has_wf: Bool = false
	issues: List[Issue] = []
	log: List[LogEntry] = []
	next_id: Int = 1
	clock: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	views: Map[String, String] = Map[String, String]()
	out: List[String] = []

type Span:
	start: Int
	end: Int
	text: String

type QParts:
	filter: String = ""
	has_sort: Bool = false
	sort: String = ""
	has_limit: Bool = false
	limit: String = ""

type Tok:
	kind: Int
	text: String = ""
	field: String = ""
	op: Int = 0
	val: String = ""
	quoted: Bool = false

type Cond:
	field: Int = 0
	op: Int = 0
	vals: List[String] = []
	nums: List[Int] = []
	root: Int = -1

type Node:
	kind: Int
	a: Int = -1
	b: Int = -1
	cond: Cond = Cond()

type Ctx:
	nodes: List[Node] = []
	pos: Int = 0
	refs: List[String] = []

type SortKey:
	field: Int
	desc: Bool

type LC:
	name: String
	n: Int

type WL:
	name: String
	n: Int
	pts: Int

fn Ctx.dummy() Int: 0

fn var Ctx.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn fail(msg: String) String!:
	return error(Error(msg))

fn is_ws(c: String) Bool:
	return c == " " or c == "\t"

fn sub(s: String, a: Int, b: Int) String:
	if r := s.slice(a, b):
		return r
	else:
		return ""

fn digit(c: String) Int:
	if c.length() != 1: return -1
	return "0123456789".index_of(c).get(-1)

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if digit(c) < 0: return false
	return true

fn to_int(s: String) Int:
	var n = 0
	for c in s.chars():
		n = n * 10 + digit(c)
	return n

fn parse_nat(s: String) Int:
	if not all_digits(s): return -1
	if s.length() > 7: return -1
	if s.length() > 1 and s.starts_with("0"): return -1
	n := to_int(s)
	if n > 1000000: return -1
	return n

fn leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn valid_date(s: String) Bool:
	if s.length() != 10: return false
	c := s.chars()
	if c.length() != 10: return false
	for i in 0..10:
		if i == 4 or i == 7:
			if c[i] != "-": return false
		else:
			if digit(c[i]) < 0: return false
	y := to_int(sub(s, 0, 4))
	m := to_int(sub(s, 5, 7))
	d := to_int(sub(s, 8, 10))
	if y < 1 or m < 1 or m > 12 or d < 1: return false
	var dim = 31
	if m == 4 or m == 6 or m == 9 or m == 11: dim = 30
	if m == 2:
		dim = if leap(y): 29 else: 28
	return d <= dim

fn valid_label(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

fn valid_state_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0: return false
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"
		if not ok: return false
	return true

fn valid_view_name(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0: return false
	if not (cs[0] >= "a" and cs[0] <= "z"): return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

fn prio_rank(s: String) Int:
	if s == "low": return 0
	if s == "medium": return 1
	if s == "high": return 2
	if s == "critical": return 3
	return -1

fn prio_name(r: Int) String:
	if r == 0: return "low"
	if r == 1: return "medium"
	if r == 2: return "high"
	return "critical"

fn dash(s: String) String:
	if s == "": return "-"
	return s.clone()

fn pts_str(p: Int) String:
	if p < 0: return "-"
	return "{p}"

fn tokenize(s: String) List[String]!:
	var toks = List[String]()
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
			else:
				cur += c
		else:
			if is_ws(c):
				if has:
					toks.append(cur.clone())
					cur = ""
					has = false
			else if c == "\"":
				inq = true
				has = true
			else:
				cur += c
				has = true
		i += 1
	if inq: return error(Error("unterminated quote"))
	if has: toks.append(cur.clone())
	return ok(toks)

fn word_spans(s: String) List[Span]:
	var res = List[Span]()
	var off = 0
	var start = -1
	var cur = ""
	for c in s.chars():
		if is_ws(c) or c == "\r" or c == "\n":
			if start >= 0:
				res.append(Span(start, off, cur.clone()))
				start = -1
				cur = ""
		else:
			if start < 0: start = off
			cur += c
		off += c.length()
	if start >= 0:
		res.append(Span(start, off, cur.clone()))
	return res

fn first_word(s: String) String:
	return s.fields().get(0, "")

// text after the first word, with leading whitespace removed
fn after_first(s: String) String:
	t := s.trim_start()
	spans := word_spans(t)
	if spans.length() == 0: return ""
	return sub(t, spans[0].end, t.length()).trim_start()

fn after_words(s: String, k: Int) String:
	var t = s.trim_start()
	for _i in 0..k:
		t = after_first(t)
	return t

fn split_query(q: String) QParts:
	var parts = QParts()
	var text = q.trim_end()
	spans := word_spans(text)
	n := spans.length()
	if n >= 2 and spans[n - 2].text == "limit":
		parts.has_limit = true
		parts.limit = spans[n - 1].text.clone()
		text = sub(text, 0, spans[n - 2].start)
	sp := word_spans(text)
	for k in 0..sp.length():
		if sp[k].text == "sort" and sp[k].end < text.length():
			parts.has_sort = true
			parts.sort = sub(text, sp[k].end, text.length())
			text = sub(text, 0, sp[k].start)
			break
	parts.filter = text
	return parts

fn norm_labels(ls: List[String]) List[String]:
	var res = List[String]()
	for l in ls:
		if not res.contains(l): res.append(l.clone())
	res.sort()
	return res

fn parse_patch(toks: List[String], from: Int) Patch!:
	var p = Patch()
	var i = from
	while i < toks.length():
		tok := toks[i]
		i += 1
		eq := tok.index_of("=").get(-1)
		if eq <= 0: return error(Error("expected field=value, got '{tok}'"))
		field := sub(tok, 0, eq)
		val := sub(tok, eq + 1, tok.length())
		if field == "state": return error(Error("use move to change state"))
		if field == "title":
			if val.trim() == "": return error(Error("empty title"))
			p.has_title = true
			p.title = val
		else if field == "priority":
			r := prio_rank(val)
			if r < 0: return error(Error("bad priority '{val}'"))
			p.has_prio = true
			p.prio = r
		else if field == "assignee":
			if val == "none":
				p.has_assignee = true
				p.assignee = ""
			else:
				if val.trim() == "": return error(Error("empty assignee"))
				p.has_assignee = true
				p.assignee = val
		else if field == "points":
			if val == "none":
				p.has_points = true
				p.points = -1
			else:
				n := parse_nat(val)
				if n < 0: return error(Error("bad points '{val}'"))
				p.has_points = true
				p.points = n
		else if field == "due":
			if val == "none":
				p.has_due = true
				p.due = ""
			else:
				if not valid_date(val): return error(Error("bad date '{val}'"))
				p.has_due = true
				p.due = val
		else if field == "labels":
			if val == "none":
				p.has_labels = true
				p.labels = []
			else:
				var ls = List[String]()
				for part in val.split(","):
					l := part.lower()
					if not valid_label(l): return error(Error("bad label '{l}'"))
					ls.append(l)
				p.has_labels = true
				p.labels = norm_labels(ls)
		else if field == "reporter":
			if val == "none":
				p.has_reporter = true
				p.reporter = ""
			else:
				if val.trim() == "": return error(Error("empty reporter"))
				p.has_reporter = true
				p.reporter = val
		else:
			return error(Error("unknown field '{field}'"))
		p.count += 1
	return ok(p)

fn var Issue.apply(p: Patch) List[String]:
	var d = List[String]()
	if p.has_title and p.title != self.title:
		d.append("title: {self.title} -> {p.title}")
		self.title = p.title.clone()
	if p.has_prio and p.prio != self.priority:
		d.append("priority: {prio_name(self.priority)} -> {prio_name(p.prio)}")
		self.priority = p.prio
	if p.has_assignee and p.assignee != self.assignee:
		d.append("assignee: {dash(self.assignee)} -> {dash(p.assignee)}")
		self.assignee = p.assignee.clone()
	if p.has_points and p.points != self.points:
		d.append("points: {pts_str(self.points)} -> {pts_str(p.points)}")
		self.points = p.points
	if p.has_due and p.due != self.due:
		d.append("due: {dash(self.due)} -> {dash(p.due)}")
		self.due = p.due.clone()
	if p.has_labels and p.labels != self.labels:
		d.append("labels: {dash(self.labels.join(","))} -> {dash(p.labels.join(","))}")
		self.labels = p.labels.clone()
	if p.has_reporter and p.reporter != self.reporter:
		d.append("reporter: {dash(self.reporter)} -> {dash(p.reporter)}")
		self.reporter = p.reporter.clone()
	return d

fn parse_id_num(arg: String) Int!:
	var s = arg.clone()
	if s.starts_with("#"): s = sub(s, 1, s.length())
	if not all_digits(s): return error(Error("bad issue id '{arg}'"))
	var k = 0
	while k < s.length() - 1 and sub(s, k, k + 1) == "0":
		k += 1
	t := sub(s, k, s.length())
	if t == "0": return error(Error("bad issue id '{arg}'"))
	if t.length() > 12: return ok(1000000000000)
	return ok(to_int(t))

// ---------------- tracker basics ----------------

fn var Tracker.emit(s: String) Unit:
	self.out.append(s.clone())

fn var Tracker.emit_result(r: String!) Unit:
	if v := r:
		self.emit(v)
	else:
		self.emit("error: " + r.err().message)

fn Tracker.find(id: Int) Int:
	for i in 0..self.issues.length():
		if self.issues[i].id == id: return i
	return -1

fn Tracker.res_id(arg: String) Int!:
	id := parse_id_num(arg)?
	i := self.find(id)
	if i < 0: return error(Error("no such issue #{id}"))
	return ok(i)

fn Tracker.is_final(state: Int) Bool:
	return self.wf.finals.get(state, false)

fn Tracker.state_name(i: Int) String:
	return self.wf.states.get(i, "?")

fn Tracker.state_index(name: String) Int:
	for i in 0..self.wf.states.length():
		if self.wf.states[i] == name: return i
	return -1

fn var Tracker.log_add(id: Int, detail: String) Unit:
	self.log.append(LogEntry(self.clock, self.actor.clone(), id, detail))

fn Tracker.issue_open(i: Int) Bool:
	return not self.is_final(self.issues[i].state)

// ---------------- query engine ----------------

fn field_code(f: String) Int:
	if f == "id": return 0
	if f == "created": return 1
	if f == "updated": return 2
	if f == "points": return 3
	if f == "title": return 4
	if f == "assignee": return 5
	if f == "reporter": return 6
	if f == "text": return 7
	if f == "state": return 8
	if f == "priority": return 9
	if f == "due": return 10
	if f == "label" or f == "labels": return 11
	if f == "is": return 12
	if f == "has": return 13
	if f == "view": return 14
	return -1

fn op_name(op: Int) String:
	if op == 0: return ":"
	if op == 1: return "!="
	if op == 2: return "<"
	if op == 3: return "<="
	if op == 4: return ">"
	if op == 5: return ">="
	return "~"

fn op_allowed(code: Int, op: Int) Bool:
	if code <= 3 or code == 9 or code == 10: return op <= 5
	if code >= 4 and code <= 6: return op == 0 or op == 1 or op == 6
	if code == 7: return op == 6
	if code == 8: return op == 0 or op == 1
	if code == 11: return op == 0 or op == 1 or op == 6
	return op == 0

fn is_delim(c: String) Bool:
	return is_ws(c) or c == "(" or c == ")" or c == "\r" or c == "\n"

fn is_fchar(c: String) Bool:
	return (c >= "a" and c <= "z") or c == "_"

fn lex(s: String) List[Tok]!:
	var toks = List[Tok]()
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		if is_ws(c) or c == "\r" or c == "\n":
			i += 1
			continue
		if c == "(":
			toks.append(Tok(kind: 4, text: "("))
			i += 1
			continue
		if c == ")":
			toks.append(Tok(kind: 5, text: ")"))
			i += 1
			continue
		var j = i
		while j < n and is_fchar(cs[j]):
			j += 1
		var opn = -1
		var oplen = 0
		if j > i and j < n:
			d := cs[j]
			nx := if j + 1 < n: cs[j + 1].clone() else: ""
			if d == ":":
				opn = 0
				oplen = 1
			else if d == "~":
				opn = 6
				oplen = 1
			else if d == "!" and nx == "=":
				opn = 1
				oplen = 2
			else if d == "<":
				opn = if nx == "=": 3 else: 2
				oplen = if nx == "=": 2 else: 1
			else if d == ">":
				opn = if nx == "=": 5 else: 4
				oplen = if nx == "=": 2 else: 1
		if opn >= 0:
			var field = ""
			for k in i..j:
				field += cs[k]
			var p = j + oplen
			var val = ""
			var quoted = false
			if p < n and cs[p] == "\"":
				quoted = true
				p += 1
				var closed = false
				while p < n:
					e := cs[p]
					if e == "\\" and p + 1 < n and (cs[p + 1] == "\"" or cs[p + 1] == "\\"):
						val += cs[p + 1]
						p += 2
						continue
					if e == "\"":
						closed = true
						p += 1
						break
					val += e
					p += 1
				if not closed: return error(Error("query: unterminated quote"))
			else:
				while p < n and not is_delim(cs[p]):
					val += cs[p]
					p += 1
			toks.append(Tok(kind: 0, text: field.clone(), field: field, op: opn, val: val, quoted: quoted))
			i = p
		else:
			var w = ""
			var p = i
			while p < n and not is_delim(cs[p]):
				w += cs[p]
				p += 1
			if w == "AND":
				toks.append(Tok(kind: 1, text: w))
			else if w == "OR":
				toks.append(Tok(kind: 2, text: w))
			else if w == "NOT":
				toks.append(Tok(kind: 3, text: w))
			else:
				toks.append(Tok(kind: 6, text: w))
			i = p
	return ok(toks)

fn peek(toks: List[Tok], pos: Int) Int:
	if pos < toks.length(): return toks[pos].kind
	return -1

fn bad_value(v: String, f: String) Int!:
	return error(Error("query: bad value '{v}' for field '{f}'"))

fn build_term(tr: Tracker, tk: Tok, var cx: Ctx) Int!:
	code := field_code(tk.field)
	if code < 0: return error(Error("query: unknown field '{tk.field}'"))
	op := tk.op
	if not op_allowed(code, op):
		return error(Error("query: bad operator '{op_name(op)}' for field '{tk.field}'"))
	var alts = List[String]()
	if (op == 0 or op == 1 or op == 6) and not tk.quoted and tk.val.contains("|") and code != 14:
		alts = tk.val.clone().split("|")
	else:
		alts.append(tk.val.clone())
	var c = Cond(field: code, op: op)
	for alt in alts:
		var sv = alt.lower()
		var nv = 0
		if code <= 2:
			nv = parse_nat(alt)
			if nv < 0: return bad_value(alt, tk.field)
		else if code == 3:
			if op <= 1 and alt == "none":
				nv = -1
			else:
				nv = parse_nat(alt)
				if nv < 0: return bad_value(alt, tk.field)
		else if code == 8:
			nv = tr.state_index(alt)
			if nv < 0: return bad_value(alt, tk.field)
		else if code == 9:
			nv = prio_rank(alt)
			if nv < 0: return bad_value(alt, tk.field)
		else if code == 10:
			if op <= 1 and alt == "none":
				sv = ""
			else:
				if not valid_date(alt): return bad_value(alt, tk.field)
				sv = alt.clone()
		else if code == 12:
			if alt == "open":
				nv = 0
			else if alt == "final":
				nv = 1
			else if alt == "overdue":
				nv = 2
			else if alt == "unassigned":
				nv = 3
			else:
				return bad_value(alt, tk.field)
		else if code == 13:
			nv = ["assignee", "due", "points", "labels", "comments", "reporter"].index_of(alt).get(-1)
			if nv < 0: return bad_value(alt, tk.field)
		else if code == 14:
			stored := tr.views.get(alt)
			if stored.is_none(): return error(Error("query: unknown view '{alt}'"))
			cx.refs.append(alt.clone())
			parts := split_query(stored.get(""))
			c.root = parse_text(tr, parts.filter, var cx)?
		c.vals.append(sv)
		c.nums.append(nv)
	return ok(cx.add(Node(kind: 0, cond: c)))

fn parse_not(tr: Tracker, toks: List[Tok], var cx: Ctx) Int!:
	k := peek(toks, cx.pos)
	if k < 0: return error(Error("query: unexpected end of query"))
	if k == 3:
		cx.pos += 1
		child := parse_not(tr, toks, var cx)?
		return ok(cx.add(Node(kind: 3, a: child)))
	if k == 4:
		cx.pos += 1
		e := parse_or(tr, toks, var cx)?
		if peek(toks, cx.pos) != 5: return error(Error("query: unexpected end of query"))
		cx.pos += 1
		return ok(e)
	if k == 0:
		tk := toks[cx.pos]
		cx.pos += 1
		return build_term(tr, tk, var cx)
	return error(Error("query: unexpected token '{toks[cx.pos].text}'"))

fn parse_and(tr: Tracker, toks: List[Tok], var cx: Ctx) Int!:
	var left = parse_not(tr, toks, var cx)?
	while true:
		k := peek(toks, cx.pos)
		if k == 1:
			cx.pos += 1
			right := parse_not(tr, toks, var cx)?
			left = cx.add(Node(kind: 1, a: left, b: right))
		else if k == 0 or k == 3 or k == 4 or k == 6:
			right := parse_not(tr, toks, var cx)?
			left = cx.add(Node(kind: 1, a: left, b: right))
		else:
			break
	return ok(left)

fn parse_or(tr: Tracker, toks: List[Tok], var cx: Ctx) Int!:
	var left = parse_and(tr, toks, var cx)?
	while peek(toks, cx.pos) == 2:
		cx.pos += 1
		right := parse_and(tr, toks, var cx)?
		left = cx.add(Node(kind: 2, a: left, b: right))
	return ok(left)

fn parse_text(tr: Tracker, text: String, var cx: Ctx) Int!:
	toks := lex(text)?
	if toks.length() == 0: return ok(-1)
	saved := cx.pos
	cx.pos = 0
	root := parse_or(tr, toks, var cx)?
	if cx.pos < toks.length():
		return error(Error("query: unexpected token '{toks[cx.pos].text}'"))
	cx.pos = saved
	return ok(root)

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_str(a: String, b: String) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn str_match(val: String, alt: String) Bool:
	if val == "": return alt == "none"
	return val.lower() == alt

fn Tracker.eq_alt(c: Cond, i: Int, is: Issue) Bool:
	f := c.field
	nv := c.nums[i]
	sv := c.vals[i]
	if f == 0: return is.id == nv
	if f == 1: return is.created == nv
	if f == 2: return is.updated == nv
	if f == 3: return is.points == nv
	if f == 4: return str_match(is.title, sv)
	if f == 5: return str_match(is.assignee, sv)
	if f == 6: return str_match(is.reporter, sv)
	if f == 8: return is.state == nv
	if f == 9: return is.priority == nv
	if f == 10: return is.due == sv
	if f == 11:
		if sv == "none": return is.labels.length() == 0
		return is.labels.contains(sv)
	if f == 12:
		isopen := not self.is_final(is.state)
		if nv == 0: return isopen
		if nv == 1: return not isopen
		if nv == 2: return isopen and is.due != "" and is.due < self.today
		return is.assignee == ""
	if f == 13:
		if nv == 0: return is.assignee != ""
		if nv == 1: return is.due != ""
		if nv == 2: return is.points >= 0
		if nv == 3: return is.labels.length() > 0
		if nv == 4: return is.comments.length() > 0
		return is.reporter != ""
	return false

fn Tracker.cond_match(c: Cond, nodes: List[Node], is: Issue) Bool:
	f := c.field
	op := c.op
	if f == 14:
		if c.root < 0: return true
		return self.node_match(nodes, c.root, is)
	if op == 0 or op == 1:
		var any = false
		for i in 0..c.vals.length():
			if self.eq_alt(c, i, is):
				any = true
				break
		return if op == 0: any else: not any
	if op == 6:
		for i in 0..c.vals.length():
			sv := c.vals[i]
			if f == 7:
				if is.title.lower().contains(sv): return true
				for cm in is.comments:
					if cm.text.lower().contains(sv): return true
			else if f == 4:
				if is.title.lower().contains(sv): return true
			else if f == 5:
				if is.assignee != "" and is.assignee.lower().contains(sv): return true
			else if f == 6:
				if is.reporter != "" and is.reporter.lower().contains(sv): return true
			else if f == 11:
				for l in is.labels:
					if l.contains(sv): return true
		return false
	// ordered
	var r = 0
	nv := c.nums[0]
	if f == 0:
		r = cmp_int(is.id, nv)
	else if f == 1:
		r = cmp_int(is.created, nv)
	else if f == 2:
		r = cmp_int(is.updated, nv)
	else if f == 3:
		if is.points < 0: return false
		r = cmp_int(is.points, nv)
	else if f == 9:
		r = cmp_int(is.priority, nv)
	else if f == 10:
		if is.due == "": return false
		r = cmp_str(is.due, c.vals[0])
	if op == 2: return r < 0
	if op == 3: return r <= 0
	if op == 4: return r > 0
	return r >= 0

fn Tracker.node_match(nodes: List[Node], idx: Int, is: Issue) Bool:
	if idx < 0: return true
	n := nodes[idx]
	if n.kind == 0: return self.cond_match(n.cond, nodes, is)
	if n.kind == 1: return self.node_match(nodes, n.a, is) and self.node_match(nodes, n.b, is)
	if n.kind == 2: return self.node_match(nodes, n.a, is) or self.node_match(nodes, n.b, is)
	return not self.node_match(nodes, n.a, is)

fn Tracker.select(filter: String) List[Int]!:
	var cx = Ctx()
	root := parse_text(self, filter, var cx)?
	var res = List[Int]()
	for i in 0..self.issues.length():
		if self.node_match(cx.nodes, root, self.issues[i]): res.append(i)
	return ok(res)

fn sort_field_code(f: String) Int:
	names := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	return names.index_of(f).get(-1)

fn parse_sort(text: String) List[SortKey]!:
	var keys = List[SortKey]()
	for w in text.replace(",", " ").fields():
		var desc = false
		var name = w.clone()
		if w.starts_with("-"):
			desc = true
			name = sub(w, 1, w.length())
		code := sort_field_code(name)
		if code < 0: return error(Error("bad sort field '{name}'"))
		keys.append(SortKey(code, desc))
	return ok(keys)

fn cmp_opt_int(a: Int, b: Int) Int:
	if a < 0 and b < 0: return 0
	if a < 0: return 1
	if b < 0: return -1
	return cmp_int(a, b)

fn cmp_opt_str(a: String, b: String, ci: Bool) Int:
	if a == "" and b == "": return 0
	if a == "": return 1
	if b == "": return -1
	if ci: return cmp_str(a.lower(), b.lower())
	return cmp_str(a, b)

fn cmp_field(f: Int, a: Issue, b: Issue) Int:
	if f == 0: return cmp_int(a.id, b.id)
	if f == 1: return cmp_int(a.created, b.created)
	if f == 2: return cmp_int(a.updated, b.updated)
	if f == 3: return cmp_int(a.priority, b.priority)
	if f == 4: return cmp_opt_int(a.points, b.points)
	if f == 5: return cmp_int(a.state, b.state)
	if f == 6: return cmp_str(a.title.lower(), b.title.lower())
	if f == 7: return cmp_opt_str(a.assignee, b.assignee, true)
	if f == 8: return cmp_opt_str(a.reporter, b.reporter, true)
	return cmp_opt_str(a.due, b.due, false)

fn cmp_issue(keys: List[SortKey], a: Issue, b: Issue) Int:
	for k in keys:
		c := cmp_field(k.field, a, b)
		if c != 0:
			return if k.desc: 0 - c else: c
	return cmp_int(a.id, b.id)

fn Tracker.issue_line(i: Int) String:
	is := self.issues[i]
	return "#{is.id} | {self.state_name(is.state)} | {prio_name(is.priority)} | {dash(is.assignee)} | {pts_str(is.points)} | {dash(is.due)} | {dash(is.labels.join(","))} | {is.title}"

fn var Tracker.run_parts(parts: QParts) Unit!:
	var limit = -1
	if parts.has_limit:
		limit = parse_nat(parts.limit)
		if limit < 0: return error(Error("bad limit '{parts.limit}'"))
	var idx = self.select(parts.filter)?
	keys := parse_sort(if parts.has_sort: parts.sort else: "")?
	idx.sort(fn x, y: cmp_issue(keys, self.issues[x], self.issues[y]))
	var count = 0
	for i in idx:
		if limit >= 0 and count >= limit: break
		self.emit(self.issue_line(i))
		count += 1
	if count == 1:
		self.emit("(1 issue)")
	else:
		self.emit("({count} issues)")
	return ok(unit)

fn var Tracker.cmd_list(rest: String) Unit:
	r := self.run_parts(split_query(rest))
	if r_ok(r): return
	self.emit("error: " + r.err().message)

fn r_ok(r: Unit!) Bool:
	if _v := r: return true
	return false

// ---------------- validate saved query ----------------

fn Tracker.validate_parts(parts: QParts) List[String]!:
	if parts.has_limit:
		if parse_nat(parts.limit) < 0: return error(Error("bad limit '{parts.limit}'"))
	var cx = Ctx()
	_root := parse_text(self, parts.filter, var cx)?
	_keys := parse_sort(if parts.has_sort: parts.sort else: "")?
	return ok(cx.refs)

// ---------------- workflow ----------------

fn reg(var states: List[String], name: String) Int:
	k := states.index_of(name).get(-1)
	if k >= 0: return k
	states.append(name.clone())
	return states.length() - 1

fn var Tracker.do_workflow(lines: List[String]) Unit:
	if self.next_id > 1:
		self.emit("error: workflow: cannot redefine after issues were created")
		return
	var states = List[String]()
	var finals = List[String]()
	var initial = ""
	var tl = List[TLine]()
	var err = ""
	guards_ok := ["assignee", "points", "due", "labels", "reporter"]
	for raw in lines:
		if err != "": break
		line := raw.trim()
		if line == "" or line.starts_with("#"): continue
		if line.starts_with("initial:"):
			name := sub(line, 8, line.length()).trim()
			if not valid_state_name(name):
				err = "workflow: bad state name '{name}'"
			else if initial != "":
				err = "workflow: initial state defined twice"
			else:
				initial = name.clone()
				_k := reg(var states, name)
		else if line.starts_with("final:"):
			for part in sub(line, 6, line.length()).split(","):
				name := part.trim()
				if not valid_state_name(name):
					err = "workflow: bad state name '{name}'"
					break
				_k := reg(var states, name)
				finals.append(name)
		else if line.contains("->"):
			pos := line.index_of("->").get(0)
			src := sub(line, 0, pos).trim()
			right := sub(line, pos + 2, line.length())
			if src.fields().length() != 1:
				err = "workflow: bad line '{line}'"
			else if not valid_state_name(src):
				err = "workflow: bad state name '{src}'"
			else:
				si := reg(var states, src)
				for e in right.split(","):
					ew := e.fields()
					if ew.length() == 1 or (ew.length() == 3 and ew[1] == "requires"):
						if not valid_state_name(ew[0]):
							err = "workflow: bad state name '{ew[0]}'"
							break
						var gs = List[String]()
						if ew.length() == 3:
							for g in ew[2].split("+"):
								if not guards_ok.contains(g):
									err = "workflow: bad guard field '{g}'"
									break
								gs.append(g.clone())
							if err != "": break
						di := reg(var states, ew[0])
						tl.append(TLine(si, di, gs))
					else:
						err = "workflow: bad line '{line}'"
						break
		else:
			err = "workflow: bad line '{line}'"
	if err == "" and initial == "":
		err = "workflow: initial state missing"
	if err == "":
		for t in tl:
			if finals.contains(states[t.src]):
				err = "workflow: '{states[t.src]}' is final and cannot have transitions"
				break
	if err != "":
		self.emit("error: " + err)
		return
	var wf = Workflow()
	wf.initial = states.index_of(initial).get(0)
	for s in states:
		wf.finals.append(finals.contains(s))
		wf.trans.append([])
	for t in tl:
		wf.trans[t.src].append(Trans(t.dst, t.guards.clone()))
	self.emit("workflow ok: {states.length()} states, {tl.length()} transitions")
	wf.states = states
	self.wf = wf
	self.has_wf = true

// ---------------- commands ----------------

fn var Tracker.do_patch(idx: Int, p: Patch) String!:
	d := self.issues[idx].apply(p)
	id := self.issues[idx].id
	if d.length() == 0: return ok("#{id} unchanged")
	self.clock += 1
	self.issues[idx].updated = self.clock
	for x in d:
		self.log_add(id, x)
	return ok("updated #{id}")

fn Tracker.final_check(idx: Int) Unit!:
	if self.is_final(self.issues[idx].state):
		return error(Error("#{self.issues[idx].id} is in final state '{self.state_name(self.issues[idx].state)}'"))
	return ok(unit)

fn var Tracker.do_edit(idx: Int, toks: List[String], from: Int) String!:
	self.final_check(idx)?
	p := parse_patch(toks, from)?
	if p.count == 0: return error(Error("usage: edit ID field=value..."))
	return self.do_patch(idx, p)

fn var Tracker.do_label(idx: Int, toks: List[String], from: Int) String!:
	self.final_check(idx)?
	var ls = self.issues[idx].labels.clone()
	for i in from..toks.length():
		t := toks[i]
		var sign = "+"
		var name = t.clone()
		if t.starts_with("+") or t.starts_with("-"):
			sign = sub(t, 0, 1)
			name = sub(t, 1, t.length())
		l := name.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		if sign == "+":
			if not ls.contains(l): ls.append(l)
		else:
			k := ls.index_of(l).get(-1)
			if k >= 0: ls.remove(k)
	var p = Patch()
	p.has_labels = true
	p.labels = norm_labels(ls)
	return self.do_patch(idx, p)

fn var Tracker.do_move(idx: Int, target: String, comment: String) String!:
	self.final_check(idx)?
	ti := self.state_index(target)
	if ti < 0: return error(Error("unknown state '{target}'"))
	id := self.issues[idx].id
	cur := self.issues[idx].state
	if ti == cur: return error(Error("already in state '{target}'"))
	var found = -1
	for k in 0..self.wf.trans[cur].length():
		if self.wf.trans[cur][k].dst == ti:
			found = k
			break
	if found < 0: return error(Error("transition '{self.state_name(cur)} -> {target}' not allowed"))
	var missing = List[String]()
	for g in self.wf.trans[cur][found].guards:
		is := self.issues[idx]
		var unmet = false
		if g == "assignee": unmet = is.assignee == ""
		if g == "points": unmet = is.points < 0
		if g == "due": unmet = is.due == ""
		if g == "labels": unmet = is.labels.length() == 0
		if g == "reporter": unmet = is.reporter == ""
		if unmet: missing.append(g.clone())
	if missing.length() > 0:
		return error(Error("cannot move #{id} to {target}: missing {missing.join(", ")}"))
	self.clock += 1
	self.issues[idx].state = ti
	self.issues[idx].updated = self.clock
	self.log.append(LogEntry(self.clock, self.actor.clone(), id, "state: {self.state_name(cur)} -> {target}", self.state_name(cur), target.clone()))
	if comment != "":
		self.issues[idx].comments.append(Comment(self.clock, self.actor.clone(), comment.clone()))
		self.log_add(id, "comment: {comment}")
	return ok("moved #{id}: {self.state_name(cur)} -> {target}")

fn var Tracker.cmd_create(rest: String) String!:
	if not self.has_wf: return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: create TITLE [field=value...]"))
	if toks[0].trim() == "": return error(Error("empty title"))
	p := parse_patch(toks, 1)?
	reporter := if p.has_reporter: p.reporter.clone() else: self.actor.clone()
	var is = Issue(id: self.next_id, title: toks[0].clone(), state: self.wf.initial, reporter: "")
	d := is.apply(p)
	is.reporter = reporter
	self.clock += 1
	is.created = self.clock
	is.updated = self.clock
	id := self.next_id
	self.next_id += 1
	self.issues.append(is)
	self.log_add(id, "created \"{toks[0]}\"")
	for x in d:
		self.log_add(id, x)
	return ok("created #{id}")

fn var Tracker.cmd_edit(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() == 0: return error(Error("usage: edit ID field=value..."))
	idx := self.res_id(toks[0])?
	return self.do_edit(idx, toks, 1)

fn var Tracker.cmd_label(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() < 2: return error(Error("usage: label ID +label -label..."))
	idx := self.res_id(toks[0])?
	return self.do_label(idx, toks, 1)

fn var Tracker.cmd_assign(rest: String) String!:
	toks := tokenize(rest)?
	if toks.length() != 2: return error(Error("usage: assign ID NAME"))
	idx := self.res_id(toks[0])?
	return self.do_edit(idx, ["assignee=" + toks[1]], 0)

fn var Tracker.cmd_move(rest: String) String!:
	ws := rest.fields()
	if ws.length() < 2: return error(Error("usage: move ID STATE [comment...]"))
	idx := self.res_id(ws[0])?
	return self.do_move(idx, ws[1], after_words(rest, 2))

fn var Tracker.cmd_comment(rest: String) String!:
	ws := rest.fields()
	if ws.length() < 2: return error(Error("usage: comment ID TEXT"))
	idx := self.res_id(ws[0])?
	text := after_words(rest, 1)
	self.clock += 1
	id := self.issues[idx].id
	self.issues[idx].updated = self.clock
	self.issues[idx].comments.append(Comment(self.clock, self.actor.clone(), text.clone()))
	self.log_add(id, "comment: {text}")
	return ok("commented #{id}")

fn var Tracker.cmd_delete(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: delete ID"))
	idx := self.res_id(ws[0])?
	id := self.issues[idx].id
	self.issues.remove(idx)
	self.clock += 1
	self.log_add(id, "deleted")
	return ok("deleted #{id}")

fn var Tracker.cmd_show(rest: String) Unit!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: show ID"))
	idx := self.res_id(ws[0])?
	is := self.issues[idx].clone()
	self.emit("#{is.id} {is.title}")
	self.emit("  state: {self.state_name(is.state)}")
	self.emit("  priority: {prio_name(is.priority)}")
	self.emit("  assignee: {dash(is.assignee)}")
	self.emit("  points: {pts_str(is.points)}")
	self.emit("  due: {dash(is.due)}")
	self.emit("  labels: {dash(is.labels.join(", "))}")
	self.emit("  reporter: {dash(is.reporter)}")
	self.emit("  created: t={is.created}, updated: t={is.updated}")
	self.emit("  comments: {is.comments.length()}")
	for c in is.comments.clone():
		self.emit("    [t={c.t} {c.actor}] {c.text}")
	return ok(unit)

fn var Tracker.cmd_log(rest: String) Unit!:
	ws := rest.fields()
	var id = -1
	var tail = -1
	var has_tail = false
	var k = 0
	if ws.length() > 0 and ws[0] != "tail":
		n := parse_id_num(ws[0])?
		if n >= self.next_id: return error(Error("no such issue #{n}"))
		id = n
		k = 1
	if ws.length() - k == 2 and ws[k] == "tail":
		has_tail = true
	else if ws.length() - k != 0:
		return error(Error("usage: log [ID] [tail N]"))
	if has_tail:
		tail = parse_nat(ws[k + 1])
		if tail < 0: return error(Error("bad tail '{ws[k + 1]}'"))
	var sel = List[Int]()
	for i in 0..self.log.length():
		if id < 0 or self.log[i].id == id: sel.append(i)
	var from = 0
	if has_tail and tail < sel.length(): from = sel.length() - tail
	if sel.length() - from <= 0:
		self.emit("(no log entries)")
		return ok(unit)
	for j in from..sel.length():
		e := self.log[sel[j]].clone()
		self.emit("t={e.t} {e.actor} #{e.id} {e.detail}")
	return ok(unit)

// ---------------- views ----------------

fn var Tracker.cmd_view(rest: String) Unit!:
	ws := rest.fields()
	usage := "usage: view save|run|list|show|delete"
	if ws.length() == 0: return error(Error(usage))
	sc := ws[0]
	if sc == "list":
		if self.views.length() == 0:
			self.emit("(no views)")
			return ok(unit)
		for name in self.views.keys().sorted():
			self.emit("{name}: {self.views.get(name).get("")}")
		return ok(unit)
	if sc == "show":
		if ws.length() < 2: return error(Error("usage: view show NAME"))
		q := self.views.get(ws[1]).clone()
		if q.is_none(): return error(Error("unknown view '{ws[1]}'"))
		self.emit("{ws[1]}: {q.get("")}")
		return ok(unit)
	if sc == "delete":
		if ws.length() < 2: return error(Error("usage: view delete NAME"))
		name := ws[1]
		if self.views.get(name).is_none(): return error(Error("unknown view '{name}'"))
		for m in self.views.keys().sorted():
			if m == name: continue
			parts := split_query(self.views.get(m).get(""))
			var cx = Ctx()
			if _r := parse_text(self, parts.filter, var cx):
				if cx.refs.contains(name): return error(Error("view '{name}' is used by '{m}'"))
		self.views.remove(name.clone())
		self.emit("deleted view {name}")
		return ok(unit)
	if sc == "save":
		if ws.length() < 2: return error(Error("usage: view save NAME QUERY"))
		name := ws[1]
		if not valid_view_name(name): return error(Error("bad view name '{name}'"))
		q := after_words(rest, 2)
		refs := self.validate_parts(split_query(q))?
		if refs.contains(name): return error(Error("view '{name}' would reference itself"))
		self.views[name.clone()] = q.clone()
		self.emit("saved view {name}")
		return ok(unit)
	if sc == "run":
		if ws.length() < 2: return error(Error("usage: view run NAME [sort FIELDS] [limit N]"))
		name := ws[1]
		stored := self.views.get(name)
		if stored.is_none(): return error(Error("unknown view '{name}'"))
		var parts = split_query(stored.get(""))
		extra := split_query(after_words(rest, 2))
		if extra.has_limit:
			if parse_nat(extra.limit) < 0: return error(Error("bad limit '{extra.limit}'"))
			parts.has_limit = true
			parts.limit = extra.limit.clone()
		if extra.filter.trim() != "": return error(Error("unexpected '{extra.filter.trim()}'"))
		if extra.has_sort:
			_k := parse_sort(extra.sort)?
			parts.has_sort = true
			parts.sort = extra.sort.clone()
		return self.run_parts(parts)
	return error(Error(usage))

// ---------------- bulk ----------------

fn var Tracker.cmd_bulk(rest: String) Unit!:
	usage := "usage: bulk ACTION... where QUERY"
	spans := word_spans(rest)
	var wi = -1
	for k in 0..spans.length():
		if spans[k].text == "where":
			wi = k
			break
	if wi < 0: return error(Error(usage))
	action := sub(rest, 0, spans[wi].start)
	query := sub(rest, spans[wi].end, rest.length())
	if action.trim() == "": return error(Error(usage))
	toks := tokenize(action)?
	kind := toks[0]
	if kind == "move":
		if toks.length() != 2: return error(Error("usage: bulk move STATE where QUERY"))
	else if kind == "assign":
		if toks.length() != 2: return error(Error("usage: bulk assign NAME where QUERY"))
	else if kind == "label":
		if toks.length() < 2: return error(Error("usage: bulk label +label... where QUERY"))
	else if kind == "set":
		if toks.length() < 2: return error(Error("usage: bulk set field=value... where QUERY"))
	else:
		return error(Error("unknown bulk action '{kind}'"))
	sel := self.select(query)?
	var okc = 0
	var failc = 0
	for i in sel:
		id := self.issues[i].id
		var r = fail("")
		if kind == "move":
			r = self.do_move(i, toks[1], "")
		else if kind == "assign":
			r = self.do_edit(i, ["assignee=" + toks[1]], 0)
		else if kind == "label":
			r = self.do_label(i, toks, 1)
		else:
			r = self.do_edit(i, toks, 1)
		if v := r:
			self.emit(v)
			okc += 1
		else:
			self.emit("#{id} error: {r.err().message}")
			failc += 1
	self.emit("bulk: {okc} ok, {failc} failed")
	return ok(unit)

// ---------------- reports ----------------

fn var Tracker.cmd_report(rest: String) Unit!:
	usage := "usage: report summary|workload|labels|timeline"
	ws := rest.fields()
	if ws.length() == 0: return error(Error(usage))
	sc := ws[0]
	if sc == "summary":
		var total = 0
		var nopen = 0
		var unassigned = 0
		var overdue = 0
		var pts = 0
		var by_state = List[Int]()
		for _s in self.wf.states:
			by_state.append(0)
		var by_prio = [0, 0, 0, 0]
		for is in self.issues:
			total += 1
			by_state[is.state] += 1
			by_prio[is.priority] += 1
			if not self.is_final(is.state):
				nopen += 1
				if is.assignee == "": unassigned += 1
				if is.due != "" and is.due < self.today: overdue += 1
				if is.points >= 0: pts += points_of(is)
		self.emit("issues: {total} (open {nopen}, final {total - nopen})")
		self.emit("by state:")
		for i in 0..self.wf.states.length():
			self.emit("  {self.wf.states[i]}: {by_state[i]}")
		self.emit("by priority:")
		for r in 0..4:
			p := 3 - r
			self.emit("  {prio_name(p)}: {by_prio[p]}")
		self.emit("unassigned: {unassigned}")
		self.emit("overdue: {overdue}")
		self.emit("open points: {pts}")
		return ok(unit)
	if sc == "workload":
		var names = List[String]()
		var rows = List[WL]()
		var un = WL("unassigned", 0, 0)
		for is in self.issues:
			if self.is_final(is.state): continue
			p := points_of(is)
			if is.assignee == "":
				un.n += 1
				un.pts += p
			else:
				key := is.assignee.lower()
				k := names.index_of(key).get(-1)
				if k < 0:
					names.append(key)
					rows.append(WL(is.assignee.clone(), 1, p))
				else:
					rows[k].n += 1
					rows[k].pts += p
		if rows.length() == 0 and un.n == 0:
			self.emit("(no open issues)")
			return ok(unit)
		rows.sort(fn a, b: wl_cmp(a, b))
		for r in rows:
			self.emit(wl_line(r.name, r.n, r.pts))
		if un.n > 0: self.emit(wl_line("unassigned", un.n, un.pts))
		return ok(unit)
	if sc == "labels":
		sel := self.select(after_words(rest, 1))?
		var counts = Map[String, Int]()
		for i in sel:
			for l in self.issues[i].labels:
				counts[l.clone()] = counts.get_or(l, 0) + 1
		var rows = List[LC]()
		for e in counts.entries():
			rows.append(LC(e.key.clone(), e.value))
		if rows.length() == 0:
			self.emit("(no labels)")
			return ok(unit)
		rows.sort(fn a, b: if a.n != b.n: b.n - a.n else: cmp_str(a.name, b.name))
		for r in rows:
			self.emit("{r.name}: {r.n}")
		return ok(unit)
	if sc == "timeline":
		if ws.length() != 2: return error(Error("usage: report timeline ID"))
		idx := self.res_id(ws[1])?
		is := self.issues[idx].clone()
		var lines = List[String]()
		var cur = self.state_name(self.wf.initial)
		var found_first = false
		for e in self.log:
			if e.id == is.id and e.to_state != "" and not found_first:
				cur = e.from_state.clone()
				found_first = true
		if not found_first: cur = self.state_name(is.state)
		var from = is.created
		for e in self.log:
			if e.id == is.id and e.to_state != "":
				lines.append("{cur}: t={from}..{e.t} ({e.t - from})")
				cur = e.to_state.clone()
				from = e.t
		lines.append("{cur}: t={from}..{self.clock} ({self.clock - from})")
		for ln in lines:
			self.emit(ln)
		return ok(unit)
	return error(Error(usage))

fn points_of(is: Issue) Int:
	if is.points < 0: return 0
	return is.points

fn wl_cmp(a: WL, b: WL) Int:
	if a.pts != b.pts: return b.pts - a.pts
	if a.n != b.n: return b.n - a.n
	return cmp_str(a.name.lower(), b.name.lower())

fn wl_line(name: String, n: Int, pts: Int) String:
	word := if n == 1: "issue" else: "issues"
	return "{name}: {n} {word}, {pts} points"

// ---------------- dispatch ----------------

fn var Tracker.exec(line: String) Unit:
	t := line.trim_start()
	cmd := first_word(t)
	rest := after_first(t)
	if cmd == "actor":
		ws := rest.fields()
		if ws.length() != 1:
			self.emit("error: usage: actor NAME")
		else:
			self.actor = ws[0].clone()
			self.emit("actor is {ws[0]}")
	else if cmd == "today":
		ws := rest.fields()
		if ws.length() != 1:
			self.emit("error: usage: today DATE")
		else if not valid_date(ws[0]):
			self.emit("error: bad date '{ws[0]}'")
		else:
			self.today = ws[0].clone()
			self.emit("today is {ws[0]}")
	else if cmd == "create":
		self.emit_result(self.cmd_create(rest))
	else if cmd == "edit":
		self.emit_result(self.cmd_edit(rest))
	else if cmd == "label":
		self.emit_result(self.cmd_label(rest))
	else if cmd == "assign":
		self.emit_result(self.cmd_assign(rest))
	else if cmd == "move":
		self.emit_result(self.cmd_move(rest))
	else if cmd == "comment":
		self.emit_result(self.cmd_comment(rest))
	else if cmd == "delete":
		self.emit_result(self.cmd_delete(rest))
	else if cmd == "show":
		self.unit_result(self.cmd_show(rest))
	else if cmd == "list":
		self.cmd_list(rest)
	else if cmd == "view":
		self.unit_result(self.cmd_view(rest))
	else if cmd == "bulk":
		self.unit_result(self.cmd_bulk(rest))
	else if cmd == "log":
		self.unit_result(self.cmd_log(rest))
	else if cmd == "report":
		self.unit_result(self.cmd_report(rest))
	else:
		self.emit("error: unknown command '{cmd}'")

fn var Tracker.unit_result(r: Unit!) Unit:
	if _v := r: return
	self.emit("error: " + r.err().message)

// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var tr = Tracker()
	lines := text.split("\n")
	var i = 0
	while i < lines.length():
		raw := lines[i]
		i += 1
		line := raw.trim_end()
		if i == lines.length() and line == "": break
		t := line.trim_start()
		if t == "" or t.starts_with("#"): continue
		tr.emit("> " + line)
		if first_word(t) == "workflow":
			var block = List[String]()
			while i < lines.length():
				l := lines[i].trim()
				i += 1
				if l == "end": break
				block.append(l)
			tr.do_workflow(block)
			continue
		tr.exec(line)
	if tr.out.length() > 0:
		print(tr.out.join("\n"))
