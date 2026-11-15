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
	priority: Int
	assignee: String
	reporter: String
	points: Int
	due: String
	labels: List[String]
	comments: List[Comment]
	created: Int
	updated: Int
	live: Bool
	hist_t: List[Int]
	hist_s: List[Int]

type LogEntry:
	t: Int
	actor: String
	id: Int
	detail: String

type Trans:
	src: Int
	dst: Int
	guards: List[String]

type Tracker:
	clock: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"
	issues: List[Issue]
	log: List[LogEntry]
	states: List[String]
	finals: List[Bool]
	initial: Int = -1
	trans: List[Trans]
	views: Map[String, String]

type Draft:
	title: String
	priority: Int
	assignee: String
	points: Int
	due: String
	labels: List[String]
	reporter: String
	rep_given: Bool = false

type Tok:
	kind: Int
	field: String = ""
	op: String = ""
	val: String = ""
	quoted: Bool = false
	text: String = ""

type Node:
	kind: Int
	a: Int = 0
	b: Int = 0
	field: String = ""
	op: String = ""
	vals: List[String]

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node]
	used: List[String]
	root: Int = -1

type Clauses:
	filter: String
	has_sort: Bool
	sort: String
	has_limit: Bool
	limit: Int

// ---------- helpers ----------

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\r"

fn sub(s: String, a: Int, b: Int) String:
	r := s.slice(a, b)
	if v := r: return v
	return ""

fn cjoin(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b:
		out += cs.get(i, "")
		i += 1
	return out

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_str(a: String, b: String) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn dash(s: String) String:
	if s == "": return "-"
	return s.clone()

fn pts(n: Int) String:
	if n < 0: return "-"
	return "{n}"

fn err_str(msg: String) String!:
	return error(Error(msg))

fn split_word(s: String) List[String]:
	// returns [word, rest-with-leading-whitespace-removed]
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n and is_ws(cs.get(i, "")):
		i += 1
	var j = i
	while j < n and not is_ws(cs.get(j, "")):
		j += 1
	var k = j
	while k < n and is_ws(cs.get(k, "")):
		k += 1
	return [cjoin(cs, i, j), cjoin(cs, k, n)]

fn parse_uint(s: String) Int?:
	if s == "" or s.length() > 7: return none
	if s.length() > 1 and s.starts_with("0"): return none
	for c in s.chars():
		if c < "0" or c > "9": return none
	v := s.parse_int().get(-1)
	if v < 0 or v > 1000000: return none
	return v

fn days_in(y: Int, m: Int) Int:
	if m == 2:
		if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0: return 29
		return 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false
	var i = 0
	while i < 10:
		c := cs.get(i, "")
		if i == 4 or i == 7:
			if c != "-": return false
		else:
			if c < "0" or c > "9": return false
		i += 1
	y := sub(s, 0, 4).parse_int().get(0)
	m := sub(s, 5, 7).parse_int().get(0)
	d := sub(s, 8, 10).parse_int().get(0)
	if y < 1 or m < 1 or m > 12: return false
	return d >= 1 and d <= days_in(y, m)

fn valid_label(s: String) Bool:
	if s == "": return false
	for c in s.chars():
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

fn valid_state_name(s: String) Bool:
	if s == "": return false
	cs := s.chars()
	first := cs.get(0, "")
	if first < "a" or first > "z": return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"
		if not ok: return false
	return true

fn parse_labels(value: String) List[String]!:
	var out = List[String]()
	for part in value.split(","):
		l := part.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		out.append(l)
	out.sort()
	out.compact()
	return ok(out)

fn tokenize(s: String) List[String]!:
	cs := s.chars()
	n := cs.length()
	var toks = List[String]()
	var cur = ""
	var in_tok = false
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if c == "\"":
			in_tok = true
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
		else if is_ws(c):
			if in_tok:
				toks.append(cur.clone())
				cur = ""
				in_tok = false
			i += 1
		else:
			cur += c
			in_tok = true
			i += 1
	if in_tok: toks.append(cur.clone())
	return ok(toks)

fn prio_rank(s: String) Int:
	if s == "low": return 0
	if s == "medium": return 1
	if s == "high": return 2
	if s == "critical": return 3
	return -1

fn prio_name(n: Int) String:
	if n == 0: return "low"
	if n == 1: return "medium"
	if n == 2: return "high"
	return "critical"

fn parse_id(arg: String) Int!:
	var s = arg.clone()
	if arg.starts_with("#"): s = sub(arg, 1, arg.length())
	if s == "": return error(Error("bad issue id '{arg}'"))
	for c in s.chars():
		if c < "0" or c > "9": return error(Error("bad issue id '{arg}'"))
	var i = 0
	while i < s.length() and sub(s, i, i + 1) == "0":
		i += 1
	stripped := sub(s, i, s.length())
	if stripped == "": return error(Error("bad issue id '{arg}'"))
	if stripped.length() > 15: return ok(1000000000000000)
	return ok(stripped.parse_int().get(0))

// ---------- query ----------

fn is_field_char(c: String) Bool: (c >= "a" and c <= "z") or c == "_"

fn op_len(cs: List[String], j: Int, n: Int) Int:
	if j >= n: return 0
	c0 := cs.get(j, "")
	c1 := if j + 1 < n: cs.get(j + 1, "") else: ""
	if c0 == "!": return if c1 == "=": 2 else: 0
	if c0 == "<" or c0 == ">":
		return if c1 == "=": 2 else: 1
	if c0 == ":" or c0 == "~": return 1
	return 0

fn lex(text: String) List[Tok]:
	cs := text.chars()
	n := cs.length()
	var out = List[Tok]()
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if is_ws(c):
			i += 1
			continue
		if c == "(":
			out.append(Tok(kind: 4, text: "("))
			i += 1
			continue
		if c == ")":
			out.append(Tok(kind: 5, text: ")"))
			i += 1
			continue
		var j = i
		while j < n and is_field_char(cs.get(j, "")):
			j += 1
		ol := if j > i: op_len(cs, j, n) else: 0
		if ol > 0:
			field := cjoin(cs, i, j)
			op := cjoin(cs, j, j + ol)
			k := j + ol
			if k < n and cs.get(k, "") == "\"":
				var val = ""
				var m = k + 1
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
					out.append(Tok(kind: 7))
					i = n
				else:
					out.append(Tok(kind: 0, field: field, op: op, val: val, quoted: true))
					i = m
			else:
				var m = k
				while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
					m += 1
				out.append(Tok(kind: 0, field: field, op: op, val: cjoin(cs, k, m)))
				i = m
		else:
			var m = i
			while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
				m += 1
			w := cjoin(cs, i, m)
			if w == "AND": out.append(Tok(kind: 1, text: w))
			else if w == "OR": out.append(Tok(kind: 2, text: w))
			else if w == "NOT": out.append(Tok(kind: 3, text: w))
			else: out.append(Tok(kind: 6, text: w))
			i = m
	return out

fn state_index(t: Tracker, name: String) Int:
	var i = 0
	for s in t.states:
		if s == name: return i
		i += 1
	return -1

fn bad_value(v: String, f: String) String!:
	return error(Error("query: bad value '{v}' for field '{f}'"))

fn bad_op(op: String, f: String) Int!:
	return error(Error("query: bad operator '{op}' for field '{f}'"))

fn op_in(op: String, ops: List[String]) Bool: ops.contains(op)

fn make_term(t: Tracker, tok: Tok) Node!:
	f := tok.field
	op := tok.op
	var alts = List[String]()
	if tok.quoted or not (op == ":" or op == "!=" or op == "~"):
		alts.append(tok.val.clone())
	else:
		for a in tok.val.split("|"):
			alts.append(a.clone())
	all6 := [":", "!=", "<", "<=", ">", ">="]
	eq := [":", "!="]
	eqs := [":", "!=", "~"]
	var allowed = List[String]()
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "due" or f == "priority":
		allowed = all6
	else if f == "title" or f == "assignee" or f == "reporter" or f == "label" or f == "labels":
		allowed = eqs
	else if f == "text":
		allowed = ["~"]
	else if f == "state":
		allowed = eq
	else if f == "is" or f == "has" or f == "view":
		allowed = [":"]
	else:
		return error(Error("query: unknown field '{f}'"))
	if not op_in(op, allowed): return error(Error("query: bad operator '{op}' for field '{f}'"))
	ordered := not (op == ":" or op == "!=" or op == "~")
	for a in alts:
		if f == "id" or f == "created" or f == "updated":
			if parse_uint(a).is_none(): return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "points":
			if a == "none" and not ordered: continue
			if parse_uint(a).is_none(): return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "due":
			if a == "none" and not ordered: continue
			if not valid_date(a): return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "priority":
			if prio_rank(a) < 0: return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "state":
			if state_index(t, a) < 0: return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "is":
			if not (a == "open" or a == "final" or a == "overdue" or a == "unassigned"): return error(Error("query: bad value '{a}' for field '{f}'"))
		else if f == "has":
			good := a == "assignee" or a == "due" or a == "points" or a == "labels" or a == "comments" or a == "reporter"
			if not good: return error(Error("query: bad value '{a}' for field '{f}'"))
	return ok(Node(kind: 0, field: f.clone(), op: op.clone(), vals: alts))

fn fn_kind(p: Parser) Int:
	if p.pos >= p.toks.length(): return 99
	return p.toks.get(p.pos).kind

fn var Parser.add_node(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.parse_or(t: Tracker) Int!:
	var left = self.parse_and(t)?
	while fn_kind(self) == 2:
		self.pos += 1
		right := self.parse_and(t)?
		left = self.add_node(Node(kind: 2, a: left, b: right, vals: []))
	return ok(left)

fn var Parser.parse_and(t: Tracker) Int!:
	var left = self.parse_not(t)?
	while true:
		k := fn_kind(self)
		if k == 1: self.pos += 1
		if not (k == 0 or k == 1 or k == 3 or k == 4 or k == 6 or k == 7): break
		right := self.parse_not(t)?
		left = self.add_node(Node(kind: 1, a: left, b: right, vals: []))
	return ok(left)

fn var Parser.parse_not(t: Tracker) Int!:
	if fn_kind(self) == 3:
		self.pos += 1
		x := self.parse_not(t)?
		return ok(self.add_node(Node(kind: 3, a: x, vals: [])))
	return self.parse_primary(t)

fn var Parser.parse_primary(t: Tracker) Int!:
	k := fn_kind(self)
	if k == 99: return error(Error("query: unexpected end of query"))
	tok := self.toks.get(self.pos).clone()
	if k == 4:
		self.pos += 1
		x := self.parse_or(t)?
		if fn_kind(self) == 99: return error(Error("query: unexpected end of query"))
		self.pos += 1
		return ok(x)
	if k == 0:
		self.pos += 1
		term := make_term(t, tok)?
		if term.field == "view":
			name := tok.val.clone()
			if not t.views.contains(name): return error(Error("query: unknown view '{name}'"))
			stored := t.views.get_or(name, "")
			cl := split_clauses(stored)?
			sub_p := parse_filter(t, cl.filter)?
			self.used.append(name.clone())
			for u in sub_p.used:
				self.used.append(u.clone())
			return ok(self.add_node(Node(kind: 5, field: name.clone(), vals: [])))
		return ok(self.add_node(term))
	if k == 7: return error(Error("query: unterminated quote"))
	return error(Error("query: unexpected token '{tok.text}'"))

fn parse_filter(t: Tracker, text: String) Parser!:
	var p = Parser(toks: lex(text), nodes: [], used: [])
	if p.toks.is_empty():
		p.root = -1
		return ok(p)
	root := p.parse_or(t)?
	if p.pos < p.toks.length():
		return error(Error("query: unexpected token '{p.toks.get(p.pos).text}'"))
	p.root = root
	return ok(p)

fn split_clauses(text: String) Clauses!:
	cs := text.chars()
	var n = cs.length()
	while n > 0 and is_ws(cs.get(n - 1, "")):
		n -= 1
	var has_limit = false
	var limit = 0
	var end = n
	// last word
	var k = n
	while k > 0 and not is_ws(cs.get(k - 1, "")):
		k -= 1
	if k > 0 and k < n:
		var e = k
		while e > 0 and is_ws(cs.get(e - 1, "")):
			e -= 1
		var m = e
		while m > 0 and not is_ws(cs.get(m - 1, "")):
			m -= 1
		if cjoin(cs, m, e) == "limit":
			arg := cjoin(cs, k, n)
			if arg.length() > 0:
				lv := parse_uint(arg)
				if lv.is_none(): return error(Error("bad limit '{arg}'"))
				limit = lv.get(0)
				has_limit = true
				end = m
	// sort
	var has_sort = false
	var sort_text = ""
	var filter_end = end
	var i = 0
	while i < end:
		if i + 4 < end and cs.get(i, "") == "s" and cjoin(cs, i, i + 4) == "sort" and is_ws(cs.get(i + 4, "")) and (i == 0 or is_ws(cs.get(i - 1, ""))):
			has_sort = true
			sort_text = cjoin(cs, i + 4, end)
			filter_end = i
			break
		i += 1
	return ok(Clauses(filter: cjoin(cs, 0, filter_end), has_sort: has_sort, sort: sort_text, has_limit: has_limit, limit: limit))

fn parse_sort(text: String) List[String]!:
	// returns entries like "-field" / "field"
	var out = List[String]()
	var cur = ""
	for c in text.chars():
		if is_ws(c) or c == ",":
			if cur != "":
				out.append(cur.clone())
				cur = ""
		else:
			cur += c
	if cur != "": out.append(cur.clone())
	valid := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	for e in out:
		name := if e.starts_with("-"): sub(e, 1, e.length()) else: e.clone()
		if not valid.contains(name): return error(Error("bad sort field '{name}'"))
	return ok(out)

fn match_term(t: Tracker, n: Node, is: Issue) Bool:
	f := n.field
	op := n.op
	if f == "id" or f == "created" or f == "updated":
		v := if f == "id": is.id else if f == "created": is.created else: is.updated
		return int_match(v, op, n.vals)
	if f == "points":
		if is.points < 0:
			if op == ":":
				return n.vals.contains("none")
			if op == "!=":
				return not n.vals.contains("none")
			return false
		var vals = List[String]()
		for a in n.vals:
			if a != "none": vals.append(a.clone())
		if op == "!=" and vals.is_empty() and not n.vals.is_empty(): return true
		return int_match(is.points, op, vals)
	if f == "title": return text_match(op, n.vals, true, is.title)
	if f == "assignee": return text_match(op, n.vals, is.assignee != "", is.assignee)
	if f == "reporter": return text_match(op, n.vals, is.reporter != "", is.reporter)
	if f == "text":
		for a in n.vals:
			al := a.lower()
			if is.title.lower().contains(al): return true
			for c in is.comments:
				if c.text.lower().contains(al): return true
		return false
	if f == "state":
		var hit = false
		for a in n.vals:
			if state_index(t, a) == is.state: hit = true
		if op == "!=": return not hit
		return hit
	if f == "priority":
		if op == ":" or op == "!=":
			var hit = false
			for a in n.vals:
				if prio_rank(a) == is.priority: hit = true
			if op == "!=": return not hit
			return hit
		r := prio_rank(n.vals.get(0, ""))
		return int_match(is.priority, op, ["{r}"])
	if f == "due":
		if op == ":" or op == "!=":
			var hit = false
			for a in n.vals:
				if is.due == "":
					if a == "none": hit = true
				else if a == is.due: hit = true
			if op == "!=": return not hit
			return hit
		if is.due == "": return false
		c := cmp_str(is.due, n.vals.get(0, ""))
		if op == "<": return c < 0
		if op == "<=": return c <= 0
		if op == ">": return c > 0
		return c >= 0
	if f == "label" or f == "labels":
		if op == "~":
			for a in n.vals:
				al := a.lower()
				for l in is.labels:
					if l.contains(al): return true
			return false
		var hit = false
		for a in n.vals:
			if a == "none":
				if is.labels.is_empty(): hit = true
			else if is.labels.contains(a.lower()): hit = true
		if op == "!=": return not hit
		return hit
	if f == "is":
		for a in n.vals:
			isfinal := t.finals.get(is.state, false)
			if a == "open" and not isfinal: return true
			if a == "final" and isfinal: return true
			if a == "overdue" and not isfinal and is.due != "" and is.due < t.today: return true
			if a == "unassigned" and is.assignee == "": return true
		return false
	if f == "has":
		for a in n.vals:
			if a == "assignee" and is.assignee != "": return true
			if a == "due" and is.due != "": return true
			if a == "points" and is.points >= 0: return true
			if a == "labels" and not is.labels.is_empty(): return true
			if a == "comments" and not is.comments.is_empty(): return true
			if a == "reporter" and is.reporter != "": return true
		return false
	return false

fn int_match(v: Int, op: String, vals: List[String]) Bool:
	if op == ":" or op == "!=":
		var hit = false
		for a in vals:
			if parse_uint(a).get(-1) == v: hit = true
		if op == "!=": return not hit
		return hit
	x := parse_uint(vals.get(0, "")).get(-1)
	if op == "<": return v < x
	if op == "<=": return v <= x
	if op == ">": return v > x
	return v >= x

fn text_match(op: String, vals: List[String], present: Bool, value: String) Bool:
	var hit = false
	if op == "~":
		if not present: return false
		vl := value.lower()
		for a in vals:
			if vl.contains(a.lower()): return true
		return false
	for a in vals:
		if present:
			if a.lower() == value.lower(): hit = true
		else if a == "none": hit = true
	if op == "!=": return not hit
	return hit

fn match_node(p: Parser, t: Tracker, ni: Int, is: Issue) Bool:
	n := p.nodes.get(ni)
	if n.kind == 0: return match_term(t, n, is)
	if n.kind == 1: return match_node(p, t, n.a, is) and match_node(p, t, n.b, is)
	if n.kind == 2: return match_node(p, t, n.a, is) or match_node(p, t, n.b, is)
	if n.kind == 3: return not match_node(p, t, n.a, is)
	stored := t.views.get_or(n.field, "")
	cl := split_clauses(stored)
	if c := cl:
		q := parse_filter(t, c.filter)
		if qq := q:
			return matches(qq, t, is)
	return false

fn matches(p: Parser, t: Tracker, is: Issue) Bool:
	if p.root < 0: return true
	return match_node(p, t, p.root, is)

fn match_ids(t: Tracker, p: Parser) List[Int]:
	var out = List[Int]()
	for is in t.issues:
		if is.live and matches(p, t, is): out.append(is.id)
	return out

fn cmp_field(t: Tracker, name: String, a: Issue, b: Issue) Int:
	if name == "id": return cmp_int(a.id, b.id)
	if name == "created": return cmp_int(a.created, b.created)
	if name == "updated": return cmp_int(a.updated, b.updated)
	if name == "priority": return cmp_int(a.priority, b.priority)
	if name == "state": return cmp_int(a.state, b.state)
	if name == "title": return cmp_str(a.title.lower(), b.title.lower())
	if name == "points":
		if a.points < 0 and b.points < 0: return 0
		if a.points < 0: return 1
		if b.points < 0: return -1
		return cmp_int(a.points, b.points)
	var x = ""
	var y = ""
	if name == "assignee":
		x = a.assignee.lower()
		y = b.assignee.lower()
		if a.assignee == "" and b.assignee == "": return 0
		if a.assignee == "": return 1
		if b.assignee == "": return -1
	else if name == "reporter":
		x = a.reporter.lower()
		y = b.reporter.lower()
		if a.reporter == "" and b.reporter == "": return 0
		if a.reporter == "": return 1
		if b.reporter == "": return -1
	else:
		x = a.due.clone()
		y = b.due.clone()
		if a.due == "" and b.due == "": return 0
		if a.due == "": return 1
		if b.due == "": return -1
	return cmp_str(x, y)

fn sort_ids(t: Tracker, ids: List[Int], keys: List[String]) List[Int]:
	var out = ids.clone()
	ks := keys.clone()
	out.sort(fn(a: Int, b: Int) Int: cmp_ids(t, ks.clone(), a, b))
	return out

fn cmp_ids(t: Tracker, keys: List[String], a: Int, b: Int) Int:
	ia := t.issues.get(a - 1)
	ib := t.issues.get(b - 1)
	for k in keys:
		desc := k.starts_with("-")
		name := if desc: sub(k, 1, k.length()) else: k
		c := cmp_field(t, name, ia, ib)
		if c != 0: return if desc: 0 - c else: c
	return cmp_int(a, b)

fn issue_line(t: Tracker, is: Issue) String:
	st := t.states.get(is.state, "?")
	return "#{is.id} | {st} | {prio_name(is.priority)} | {dash(is.assignee)} | {pts(is.points)} | {dash(is.due)} | {dash(is.labels.join(","))} | {is.title}"

fn run_list(t: Tracker, filter: String, has_sort: Bool, sort_text: String, has_limit: Bool, limit: Int) String!:
	p := parse_filter(t, filter)?
	keys := if has_sort: parse_sort(sort_text)? else: List[String]()
	ids0 := match_ids(t, p)
	ids1 := if keys.is_empty(): ids0 else: sort_ids(t, ids0, keys)
	var lines = List[String]()
	var cnt = 0
	for id in ids1:
		if has_limit and cnt >= limit: break
		lines.append(issue_line(t, t.issues.get(id - 1)))
		cnt += 1
	lines.append(if cnt == 1: "(1 issue)" else: "({cnt} issues)")
	return ok(lines.join("\n"))

fn uses_view(t: Tracker, query: String, name: String) Bool:
	cl := split_clauses(query)
	if c := cl:
		q := parse_filter(t, c.filter)
		if qq := q:
			return qq.used.contains(name)
	return false

// ---------- tracker ----------

fn Tracker.find_issue(arg: String) Int!:
	id := parse_id(arg)?
	if id < 1 or id > self.issues.length(): return error(Error("no such issue #{id}"))
	if not self.issues.get(id - 1).live: return error(Error("no such issue #{id}"))
	return ok(id - 1)

fn var Tracker.add_log(id: Int, detail: String) Unit:
	self.log.append(LogEntry(t: self.clock, actor: self.actor.clone(), id: id, detail: detail))

fn apply_token(var d: Draft, tok: String) Unit!:
	idx := tok.index_of("=")
	if idx.is_none(): return error(Error("expected field=value, got '{tok}'"))
	k := idx.get(0)
	if k == 0: return error(Error("expected field=value, got '{tok}'"))
	field := sub(tok, 0, k)
	value := sub(tok, k + 1, tok.length())
	if field == "state": return error(Error("use move to change state"))
	if field == "title":
		if value.trim() == "": return error(Error("empty title"))
		d.title = value.clone()
	else if field == "priority":
		r := prio_rank(value)
		if r < 0: return error(Error("bad priority '{value}'"))
		d.priority = r
	else if field == "assignee":
		if value == "none": d.assignee = ""
		else if value == "": return error(Error("empty assignee"))
		else: d.assignee = value.clone()
	else if field == "points":
		if value == "none": d.points = -1
		else:
			v := parse_uint(value)
			if v.is_none(): return error(Error("bad points '{value}'"))
			d.points = v.get(0)
	else if field == "due":
		if value == "none": d.due = ""
		else:
			if not valid_date(value): return error(Error("bad date '{value}'"))
			d.due = value.clone()
	else if field == "labels":
		if value == "none": d.labels = List[String]()
		else: d.labels = parse_labels(value)?
	else if field == "reporter":
		if value == "none":
			d.reporter = ""
		else if value == "": return error(Error("empty reporter"))
		else: d.reporter = value.clone()
		d.rep_given = true
	else:
		return error(Error("unknown field '{field}'"))
	return ok(unit)

fn Tracker.draft_of(i: Int) Draft:
	is := self.issues.get(i)
	return Draft(title: is.title.clone(), priority: is.priority, assignee: is.assignee.clone(), points: is.points, due: is.due.clone(), labels: is.labels.clone(), reporter: is.reporter.clone())

fn changes_between(a: Draft, b: Draft) List[String]:
	var out = List[String]()
	if a.title != b.title: out.append("title: {a.title} -> {b.title}")
	if a.priority != b.priority: out.append("priority: {prio_name(a.priority)} -> {prio_name(b.priority)}")
	if a.assignee != b.assignee: out.append("assignee: {dash(a.assignee)} -> {dash(b.assignee)}")
	if a.points != b.points: out.append("points: {pts(a.points)} -> {pts(b.points)}")
	if a.due != b.due: out.append("due: {dash(a.due)} -> {dash(b.due)}")
	if a.labels.join(",") != b.labels.join(","): out.append("labels: {dash(a.labels.join(","))} -> {dash(b.labels.join(","))}")
	if a.reporter != b.reporter: out.append("reporter: {dash(a.reporter)} -> {dash(b.reporter)}")
	return out

fn var Tracker.commit_draft(i: Int, d: Draft) String:
	old := self.draft_of(i)
	ch := changes_between(old, d)
	id := i + 1
	if ch.is_empty(): return "#{id} unchanged"
	self.clock += 1
	self.issues[i].title = d.title.clone()
	self.issues[i].priority = d.priority
	self.issues[i].assignee = d.assignee.clone()
	self.issues[i].points = d.points
	self.issues[i].due = d.due.clone()
	self.issues[i].labels = d.labels.clone()
	self.issues[i].reporter = d.reporter.clone()
	self.issues[i].updated = self.clock
	for c in ch:
		self.add_log(id, c)
	return "updated #{id}"

fn var Tracker.edit_tokens(idarg: String, toks: List[String]) String!:
	i := self.find_issue(idarg)?
	if self.finals.get(self.issues.get(i).state, false):
		return error(Error("#{i + 1} is in final state '{self.states.get(self.issues.get(i).state, "")}'"))
	if toks.is_empty(): return error(Error("usage: edit ID field=value..."))
	var d = self.draft_of(i)
	for tk in toks:
		apply_token(var d, tk)?
	return ok(self.commit_draft(i, d))

fn var Tracker.label_cmd(idarg: String, ops: List[String]) String!:
	i := self.find_issue(idarg)?
	if self.finals.get(self.issues.get(i).state, false):
		return error(Error("#{i + 1} is in final state '{self.states.get(self.issues.get(i).state, "")}'"))
	var d = self.draft_of(i)
	for op in ops:
		var neg = false
		var body = op.clone()
		if op.starts_with("+"): body = sub(op, 1, op.length())
		else if op.starts_with("-"):
			neg = true
			body = sub(op, 1, op.length())
		l := body.lower()
		if not valid_label(l): return error(Error("bad label '{l}'"))
		if neg:
			d.labels.retain(fn x: x != l)
		else:
			if not d.labels.contains(l): d.labels.append(l)
	d.labels.sort()
	return ok(self.commit_draft(i, d))

fn var Tracker.move_issue(idarg: String, target: String, comment: String) String!:
	i := self.find_issue(idarg)?
	id := i + 1
	cur := self.issues.get(i).state
	if self.finals.get(cur, false):
		return error(Error("#{id} is in final state '{self.states.get(cur, "")}'"))
	ti := state_index(self, target)
	if ti < 0: return error(Error("unknown state '{target}'"))
	cn := self.states.get(cur, "")
	if ti == cur: return error(Error("already in state '{target}'"))
	var found = false
	var guards = List[String]()
	for tr in self.trans:
		if tr.src == cur and tr.dst == ti and not found:
			found = true
			guards = tr.guards.clone()
	if not found: return error(Error("transition '{cn} -> {target}' not allowed"))
	var missing = List[String]()
	is := self.issues.get(i).clone()
	for g in guards:
		var unmet = false
		if g == "assignee": unmet = is.assignee == ""
		else if g == "points": unmet = is.points < 0
		else if g == "due": unmet = is.due == ""
		else if g == "labels": unmet = is.labels.is_empty()
		else if g == "reporter": unmet = is.reporter == ""
		if unmet: missing.append(g.clone())
	if not missing.is_empty():
		return error(Error("cannot move #{id} to {target}: missing {missing.join(", ")}"))
	self.clock += 1
	self.issues[i].state = ti
	self.issues[i].updated = self.clock
	self.issues[i].hist_t.append(self.clock)
	self.issues[i].hist_s.append(ti)
	self.add_log(id, "state: {cn} -> {target}")
	if comment != "":
		self.issues[i].comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: comment.clone()))
		self.add_log(id, "comment: {comment}")
	return ok("moved #{id}: {cn} -> {target}")

fn var Tracker.cmd_create(rest: String) String!:
	if self.states.is_empty(): return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.is_empty(): return error(Error("usage: create TITLE [field=value...]"))
	title0 := toks.get(0)
	if title0.trim() == "": return error(Error("empty title"))
	var d = Draft(title: title0.clone(), priority: 1, assignee: "", points: -1, due: "", labels: [], reporter: self.actor.clone())
	var k = 1
	while k < toks.length():
		apply_token(var d, toks.get(k))?
		k += 1
	id := self.issues.length() + 1
	self.clock += 1
	self.issues.append(Issue(id: id, title: d.title.clone(), state: self.initial, priority: d.priority, assignee: d.assignee.clone(), reporter: d.reporter.clone(), points: d.points, due: d.due.clone(), labels: d.labels.clone(), comments: [], created: self.clock, updated: self.clock, live: true, hist_t: [self.clock], hist_s: [self.initial]))
	self.add_log(id, "created \"{title0}\"")
	if d.title != title0: self.add_log(id, "title: {title0} -> {d.title}")
	if d.priority != 1: self.add_log(id, "priority: medium -> {prio_name(d.priority)}")
	if d.assignee != "": self.add_log(id, "assignee: - -> {d.assignee}")
	if d.points >= 0: self.add_log(id, "points: - -> {d.points}")
	if d.due != "": self.add_log(id, "due: - -> {d.due}")
	if not d.labels.is_empty(): self.add_log(id, "labels: - -> {d.labels.join(",")}")
	if d.rep_given and d.reporter != "": self.add_log(id, "reporter: - -> {d.reporter}")
	return ok("created #{id}")

fn var Tracker.cmd_comment(rest: String) String!:
	a := split_word(rest)
	if a.get(0) == "" or a.get(1) == "": return error(Error("usage: comment ID TEXT"))
	i := self.find_issue(a.get(0))?
	id := i + 1
	self.clock += 1
	self.issues[i].updated = self.clock
	self.issues[i].comments.append(Comment(t: self.clock, actor: self.actor.clone(), text: a.get(1).clone()))
	self.add_log(id, "comment: {a.get(1)}")
	return ok("commented #{id}")

fn var Tracker.cmd_delete(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: delete ID"))
	i := self.find_issue(ws.get(0))?
	self.clock += 1
	self.issues[i].live = false
	self.add_log(i + 1, "deleted")
	return ok("deleted #{i + 1}")

fn Tracker.cmd_show(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: show ID"))
	i := self.find_issue(ws.get(0))?
	is := self.issues.get(i)
	var lines = List[String]()
	lines.append("#{is.id} {is.title}")
	lines.append("  state: {self.states.get(is.state, "")}")
	lines.append("  priority: {prio_name(is.priority)}")
	lines.append("  assignee: {dash(is.assignee)}")
	lines.append("  points: {pts(is.points)}")
	lines.append("  due: {dash(is.due)}")
	lines.append("  labels: {dash(is.labels.join(", "))}")
	lines.append("  reporter: {dash(is.reporter)}")
	lines.append("  created: t={is.created}, updated: t={is.updated}")
	lines.append("  comments: {is.comments.length()}")
	for c in is.comments:
		lines.append("    [t={c.t} {c.actor}] {c.text}")
	return ok(lines.join("\n"))

fn Tracker.cmd_log(rest: String) String!:
	ws := rest.fields()
	var id = 0
	var tail = -1
	var k = 0
	if ws.length() > 0 and ws.get(0) != "tail":
		if ws.length() != 1 and ws.length() != 3: return error(Error("usage: log [ID] [tail N]"))
		if ws.length() == 3 and ws.get(1) != "tail": return error(Error("usage: log [ID] [tail N]"))
		id = parse_id(ws.get(0))?
		if id > self.issues.length(): return error(Error("no such issue #{id}"))
		k = 1
	if ws.length() > k:
		if ws.length() != k + 2 or ws.get(k) != "tail": return error(Error("usage: log [ID] [tail N]"))
		tv := parse_uint(ws.get(k + 1))
		if tv.is_none(): return error(Error("bad tail '{ws.get(k + 1)}'"))
		tail = tv.get(0)
	var sel = List[String]()
	for e in self.log:
		if id == 0 or e.id == id:
			sel.append("t={e.t} {e.actor} #{e.id} {e.detail}")
	if tail >= 0 and sel.length() > tail:
		sel = sel.drop(sel.length() - tail)
	if sel.is_empty(): return ok("(no log entries)")
	return ok(sel.join("\n"))

fn var Tracker.cmd_workflow(block: List[String]) String!:
	if self.issues.length() > 0: return error(Error("workflow: cannot redefine after issues were created"))
	var states = List[String]()
	var finals_names = List[String]()
	var initial = ""
	var has_initial = false
	var trans_src = List[String]()
	var trans_dst = List[String]()
	var trans_guards = List[List[String]]()
	var first_err = ""
	var ntrans = 0
	for raw in block:
		line := raw.trim()
		if line == "" or line.starts_with("#"): continue
		if first_err != "":
			// still register nothing further
			continue
		if line.starts_with("initial:"):
			name := sub(line, 8, line.length()).trim()
			if not valid_state_name(name):
				first_err = "workflow: bad state name '{name}'"
				continue
			if has_initial:
				first_err = "workflow: initial state defined twice"
				continue
			has_initial = true
			initial = name.clone()
			if not states.contains(name): states.append(name.clone())
		else if line.starts_with("final:"):
			body := sub(line, 6, line.length())
			var local = List[String]()
			var bad = ""
			for part in body.split(","):
				nm := part.trim()
				if not valid_state_name(nm):
					bad = nm.clone()
					break
				local.append(nm.clone())
			if bad != "" or local.is_empty():
				first_err = "workflow: bad state name '{bad}'"
				continue
			for nm in local:
				if not states.contains(nm): states.append(nm.clone())
				if not finals_names.contains(nm): finals_names.append(nm.clone())
		else:
			ai := line.index_of("->")
			if ai.is_none():
				first_err = "workflow: bad line '{line}'"
				continue
			src := sub(line, 0, ai.get(0)).trim()
			if not valid_state_name(src):
				first_err = "workflow: bad state name '{src}'"
				continue
			if not states.contains(src): states.append(src.clone())
			rest := sub(line, ai.get(0) + 2, line.length())
			var l_dst = List[String]()
			var l_g = List[List[String]]()
			var err = ""
			for entry in rest.split(","):
				ws := entry.fields()
				if ws.is_empty() or (ws.length() != 1 and ws.length() != 3) or (ws.length() == 3 and ws.get(1) != "requires"):
					err = "workflow: bad line '{line}'"
					break
				if not valid_state_name(ws.get(0)):
					err = "workflow: bad state name '{ws.get(0)}'"
					break
				var gs = List[String]()
				if ws.length() == 3:
					var gbad = ""
					var gb = false
					for g in ws.get(2).split("+"):
						ok2 := g == "assignee" or g == "points" or g == "due" or g == "labels" or g == "reporter"
						if not ok2:
							gbad = g.clone()
							gb = true
							break
						gs.append(g.clone())
					if gb:
						err = "workflow: bad guard field '{gbad}'"
						break
				l_dst.append(ws.get(0).clone())
				l_g.append(gs)
			if err != "":
				first_err = err
				continue
			var q = 0
			while q < l_dst.length():
				if not states.contains(l_dst.get(q)): states.append(l_dst.get(q).clone())
				trans_src.append(src.clone())
				trans_dst.append(l_dst.get(q).clone())
				trans_guards.append(l_g.get(q).clone())
				ntrans += 1
				q += 1
	if first_err != "": return error(Error(first_err))
	if not has_initial: return error(Error("workflow: initial state missing"))
	for s in trans_src:
		if finals_names.contains(s): return error(Error("workflow: '{s}' is final and cannot have transitions"))
	self.states = states.clone()
	var fl = List[Bool]()
	for s in states:
		fl.append(finals_names.contains(s))
	self.finals = fl
	self.initial = states.index_of(initial).get(0)
	var tl = List[Trans]()
	var q = 0
	while q < trans_src.length():
		tl.append(Trans(src: states.index_of(trans_src.get(q)).get(0), dst: states.index_of(trans_dst.get(q)).get(0), guards: trans_guards.get(q).clone()))
		q += 1
	self.trans = tl
	return ok("workflow ok: {states.length()} states, {ntrans} transitions")

// ---------- views ----------

fn validate_query(t: Tracker, text: String) Parser!:
	cl := split_clauses(text)?
	p := parse_filter(t, cl.filter)?
	if cl.has_sort:
		_k := parse_sort(cl.sort)?
	return ok(p)

fn Tracker.sorted_views() List[String]:
	var names = List[String]()
	for e in self.views.keys():
		names.append(e.clone())
	names.sort()
	return names

fn var Tracker.cmd_view(rest: String) String!:
	a := split_word(rest)
	sub_cmd := a.get(0)
	args := a.get(1)
	if sub_cmd == "save":
		b := split_word(args)
		name := b.get(0)
		if name == "": return error(Error("usage: view save NAME QUERY"))
		query := b.get(1).trim()
		var okname = valid_state_name_view(name)
		if not okname: return error(Error("bad view name '{name}'"))
		p := validate_query(self, query)?
		if p.used.contains(name): return error(Error("view '{name}' would reference itself"))
		self.views[name.clone()] = query.clone()
		return ok("saved view {name}")
	if sub_cmd == "run":
		b := split_word(args)
		name := b.get(0)
		if name == "": return error(Error("usage: view run NAME [sort FIELDS] [limit N]"))
		if not self.views.contains(name): return error(Error("unknown view '{name}'"))
		rc := split_clauses(b.get(1))?
		extra := rc.filter.trim()
		if extra != "": return error(Error("unexpected '{extra}'"))
		sc := split_clauses(self.views.get_or(name, ""))?
		hs := if rc.has_sort: true else: sc.has_sort
		st := if rc.has_sort: rc.sort else: sc.sort
		hl := if rc.has_limit: true else: sc.has_limit
		lv := if rc.has_limit: rc.limit else: sc.limit
		return run_list(self, sc.filter, hs, st, hl, lv)
	if sub_cmd == "list":
		names := self.sorted_views()
		if names.is_empty(): return ok("(no views)")
		var lines = List[String]()
		for n in names:
			lines.append("{n}: {self.views.get_or(n, "")}")
		return ok(lines.join("\n"))
	if sub_cmd == "show":
		ws := args.fields()
		if ws.length() != 1: return error(Error("usage: view show NAME"))
		name := ws.get(0)
		if not self.views.contains(name): return error(Error("unknown view '{name}'"))
		return ok("{name}: {self.views.get_or(name, "")}")
	if sub_cmd == "delete":
		ws := args.fields()
		if ws.length() != 1: return error(Error("usage: view delete NAME"))
		name := ws.get(0)
		if not self.views.contains(name): return error(Error("unknown view '{name}'"))
		for m in self.sorted_views():
			if m != name and uses_view(self, self.views.get_or(m, ""), name):
				return error(Error("view '{name}' is used by '{m}'"))
		self.views.remove(name.clone())
		return ok("deleted view {name}")
	return error(Error("usage: view save|run|list|show|delete"))

fn valid_state_name_view(s: String) Bool:
	if s == "": return false
	cs := s.chars()
	first := cs.get(0, "")
	if first < "a" or first > "z": return false
	for c in cs:
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

// ---------- bulk ----------

fn var Tracker.cmd_bulk(rest: String) String!:
	cs := rest.chars()
	n := cs.length()
	var wi = -1
	var i = 0
	while i < n:
		if cs.get(i, "") == "w" and i + 5 <= n and cjoin(cs, i, i + 5) == "where" and (i == 0 or is_ws(cs.get(i - 1, ""))) and (i + 5 == n or is_ws(cs.get(i + 5, ""))):
			wi = i
			break
		i += 1
	if wi < 0: return error(Error("usage: bulk ACTION... where QUERY"))
	before := cjoin(cs, 0, wi)
	after := cjoin(cs, wi + 5, n)
	if before.trim() == "": return error(Error("usage: bulk ACTION... where QUERY"))
	toks := tokenize(before)?
	act := toks.get(0)
	if act == "move":
		if toks.length() != 2: return error(Error("usage: bulk move STATE where QUERY"))
	else if act == "assign":
		if toks.length() != 2: return error(Error("usage: bulk assign NAME where QUERY"))
	else if act == "label":
		if toks.length() < 2: return error(Error("usage: bulk label +label... where QUERY"))
	else if act == "set":
		if toks.length() < 2: return error(Error("usage: bulk set field=value... where QUERY"))
	else:
		return error(Error("unknown bulk action '{act}'"))
	p := parse_filter(self, after)?
	ids := match_ids(self, p)
	var args = List[String]()
	var q = 1
	while q < toks.length():
		args.append(toks.get(q).clone())
		q += 1
	var lines = List[String]()
	var n_ok = 0
	var n_fail = 0
	for id in ids:
		ids_s := "{id}"
		var r: String! = ok("")
		if act == "move": r = self.move_issue(ids_s, toks.get(1), "")
		else if act == "assign": r = self.edit_tokens(ids_s, ["assignee={toks.get(1)}"])
		else if act == "label": r = self.label_cmd(ids_s, args)
		else: r = self.edit_tokens(ids_s, args)
		if s := r:
			lines.append(s.clone())
			n_ok += 1
		else:
			lines.append("#{id} error: {r.err().message}")
			n_fail += 1
	lines.append("bulk: {n_ok} ok, {n_fail} failed")
	return ok(lines.join("\n"))

// ---------- reports ----------

fn Tracker.cmd_report(rest: String) String!:
	a := split_word(rest)
	sc := a.get(0)
	args := a.get(1)
	var lines = List[String]()
	if sc == "summary":
		var total = 0
		var open_n = 0
		var unassigned = 0
		var overdue = 0
		var open_pts = 0
		var by_state = List[Int]()
		for s in self.states:
			by_state.append(0)
		var by_prio = [0, 0, 0, 0]
		for is in self.issues:
			if not is.live: continue
			total += 1
			by_state[is.state] = by_state.get(is.state, 0) + 1
			by_prio[is.priority] = by_prio.get(is.priority, 0) + 1
			if not self.finals.get(is.state, false):
				open_n += 1
				if is.assignee == "": unassigned += 1
				if is.due != "" and is.due < self.today: overdue += 1
				if is.points > 0: open_pts += is.points
		lines.append("issues: {total} (open {open_n}, final {total - open_n})")
		lines.append("by state:")
		var k = 0
		while k < self.states.length():
			lines.append("  {self.states.get(k, "")}: {by_state.get(k, 0)}")
			k += 1
		lines.append("by priority:")
		lines.append("  critical: {by_prio.get(3, 0)}")
		lines.append("  high: {by_prio.get(2, 0)}")
		lines.append("  medium: {by_prio.get(1, 0)}")
		lines.append("  low: {by_prio.get(0, 0)}")
		lines.append("unassigned: {unassigned}")
		lines.append("overdue: {overdue}")
		lines.append("open points: {open_pts}")
		return ok(lines.join("\n"))
	if sc == "workload":
		var keys = List[String]()
		var names = List[String]()
		var counts = List[Int]()
		var points = List[Int]()
		var un_c = 0
		var un_p = 0
		for is in self.issues:
			if not is.live or self.finals.get(is.state, false): continue
			pv := if is.points > 0: is.points else: 0
			if is.assignee == "":
				un_c += 1
				un_p += pv
			else:
				key := is.assignee.lower()
				idx := keys.index_of(key)
				if ix := idx:
					counts[ix] = counts.get(ix, 0) + 1
					points[ix] = points.get(ix, 0) + pv
				else:
					keys.append(key.clone())
					names.append(is.assignee.clone())
					counts.append(1)
					points.append(pv)
		if keys.is_empty() and un_c == 0: return ok("(no open issues)")
		var order = List[Int]()
		var k = 0
		while k < keys.length():
			order.append(k)
			k += 1
		order.sort(fn(x: Int, y: Int) Int: wl_cmp(keys, counts, points, x, y))
		for ix in order:
			c := counts.get(ix, 0)
			lines.append("{names.get(ix, "")}: {c} {if c == 1: "issue" else: "issues"}, {points.get(ix, 0)} points")
		if un_c > 0:
			lines.append("unassigned: {un_c} {if un_c == 1: "issue" else: "issues"}, {un_p} points")
		return ok(lines.join("\n"))
	if sc == "labels":
		p := parse_filter(self, args)?
		var counts = Map[String, Int]()
		for is in self.issues:
			if not is.live or not matches(p, self, is): continue
			for l in is.labels:
				counts[l.clone()] = counts.get_or(l, 0) + 1
		if counts.is_empty(): return ok("(no labels)")
		var names = List[String]()
		for e in counts.keys():
			names.append(e.clone())
		names.sort(fn(x: String, y: String) Int: lb_cmp(counts, x, y))
		for nm in names:
			lines.append("{nm}: {counts.get_or(nm, 0)}")
		return ok(lines.join("\n"))
	if sc == "timeline":
		ws := args.fields()
		if ws.length() != 1: return error(Error("usage: report timeline ID"))
		i := self.find_issue(ws.get(0))?
		is := self.issues.get(i)
		var k = 0
		while k < is.hist_t.length():
			from := is.hist_t.get(k, 0)
			to := if k + 1 < is.hist_t.length(): is.hist_t.get(k + 1, 0) else: self.clock
			lines.append("{self.states.get(is.hist_s.get(k, 0), "")}: t={from}..{to} ({to - from})")
			k += 1
		return ok(lines.join("\n"))
	return error(Error("usage: report summary|workload|labels|timeline"))

fn wl_cmp(keys: List[String], counts: List[Int], points: List[Int], x: Int, y: Int) Int:
	c := cmp_int(points.get(y, 0), points.get(x, 0))
	if c != 0: return c
	c2 := cmp_int(counts.get(y, 0), counts.get(x, 0))
	if c2 != 0: return c2
	return cmp_str(keys.get(x, ""), keys.get(y, ""))

fn lb_cmp(counts: Map[String, Int], x: String, y: String) Int:
	c := cmp_int(counts.get_or(y, 0), counts.get_or(x, 0))
	if c != 0: return c
	return cmp_str(x, y)

// ---------- dispatch ----------

fn var Tracker.dispatch(word: String, rest: String) String!:
	if word == "actor":
		ws := rest.fields()
		if ws.length() != 1: return error(Error("usage: actor NAME"))
		self.actor = ws.get(0).clone()
		return ok("actor is {self.actor}")
	if word == "today":
		ws := rest.fields()
		if ws.length() != 1: return error(Error("usage: today DATE"))
		if not valid_date(ws.get(0)): return error(Error("bad date '{ws.get(0)}'"))
		self.today = ws.get(0).clone()
		return ok("today is {self.today}")
	if word == "create": return self.cmd_create(rest)
	if word == "edit":
		toks := tokenize(rest)?
		if toks.is_empty(): return error(Error("usage: edit ID field=value..."))
		var fields = List[String]()
		var q = 1
		while q < toks.length():
			fields.append(toks.get(q).clone())
			q += 1
		return self.edit_tokens(toks.get(0), fields)
	if word == "label":
		toks := tokenize(rest)?
		if toks.length() < 2: return error(Error("usage: label ID +label -label..."))
		var ops = List[String]()
		var q = 1
		while q < toks.length():
			ops.append(toks.get(q).clone())
			q += 1
		return self.label_cmd(toks.get(0), ops)
	if word == "assign":
		toks := tokenize(rest)?
		if toks.length() != 2: return error(Error("usage: assign ID NAME"))
		return self.edit_tokens(toks.get(0), ["assignee={toks.get(1)}"])
	if word == "move":
		a := split_word(rest)
		b := split_word(a.get(1))
		if a.get(0) == "" or b.get(0) == "": return error(Error("usage: move ID STATE [comment...]"))
		return self.move_issue(a.get(0), b.get(0), b.get(1))
	if word == "comment": return self.cmd_comment(rest)
	if word == "delete": return self.cmd_delete(rest)
	if word == "show": return self.cmd_show(rest)
	if word == "log": return self.cmd_log(rest)
	if word == "view": return self.cmd_view(rest)
	if word == "bulk": return self.cmd_bulk(rest)
	if word == "report": return self.cmd_report(rest)
	if word == "list":
		cl := split_clauses(rest)?
		return run_list(self, cl.filter, cl.has_sort, cl.sort, cl.has_limit, cl.limit)
	return error(Error("unknown command '{word}'"))

// ms: allow_effect std.console.write
fn show_result(r: String!) Unit:
	if s := r:
		print(s)
	else:
		print("error: {r.err().message}")

// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().get("")
	lines := text.lines()
	var t = Tracker(issues: [], log: [], states: [], finals: [], trans: [], views: Map[String, String]())
	var i = 0
	while i < lines.length():
		raw := lines.get(i, "")
		i += 1
		line := raw.trim_end()
		s := line.trim_start()
		if s == "" or s.starts_with("#"): continue
		print("> {line}")
		a := split_word(s)
		word := a.get(0)
		if word == "workflow":
			var block = List[String]()
			while i < lines.length():
				l2 := lines.get(i, "")
				i += 1
				if l2.trim() == "end": break
				block.append(l2.clone())
			show_result(t.cmd_workflow(block))
		else:
			show_result(t.dispatch(word, a.get(1)))
