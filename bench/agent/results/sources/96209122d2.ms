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
	deleted: Bool = false
	hist: List[Int] = []

type LogEntry:
	t: Int
	actor: String
	id: Int
	detail: String

type Trans:
	src: Int
	dst: Int
	guards: List[String]

type Workflow:
	states: List[String] = []
	finals: List[Bool] = []
	initial: Int = 0
	trans: List[Trans] = []

type Tok:
	kind: Int
	text: String = ""
	field: String = ""
	op: String = ""
	value: String = ""
	quoted: Bool = false

type QNode:
	kind: Int
	a: Int = 0
	b: Int = 0
	field: String = ""
	op: String = ""
	vals: List[String] = []
	nums: List[Int] = []

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[QNode] = []
	refs: List[String] = []
	root: Int = -1
	depth: Int = 0

type SortKey:
	field: String
	desc: Bool

type Split:
	filter: String
	has_sort: Bool
	sort: String
	has_limit: Bool
	limit: String

type App:
	out: List[String] = []
	wf: Workflow = Workflow()
	has_wf: Bool = false
	issues: List[Issue] = []
	log: List[LogEntry] = []
	views: Map[String, String] = Map[String, String]()
	t: Int = 0
	actor: String = "system"
	today: String = "1970-01-01"

fn is_ws(c: String) Bool:
	return c == " " or c == "\t" or c == "\r" or c == "\n"

fn is_digit(c: String) Bool:
	return c >= "0" and c <= "9"

fn is_lower(c: String) Bool:
	return c >= "a" and c <= "z"

fn all_digits(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if not is_digit(c): return false
	return true

fn parse_uint(s: String) Int?:
	if not all_digits(s): return none
	if s.length() > 1 and s.starts_with("0"): return none
	if s.length() > 7: return none
	v := s.parse_int()
	if x := v:
		if x > 1000000: return none
		return x
	return none

fn state_ok(s: String) Bool:
	if s.is_empty(): return false
	cs := s.chars()
	if not is_lower(cs.get(0, "")): return false
	for c in cs:
		if not (is_lower(c) or is_digit(c) or c == "_"): return false
	return true

fn label_ok(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if not (is_lower(c) or is_digit(c) or c == "_" or c == "-"): return false
	return true

fn view_name_ok(s: String) Bool:
	if s.is_empty(): return false
	cs := s.chars()
	if not is_lower(cs.get(0, "")): return false
	for c in cs:
		if not (is_lower(c) or is_digit(c) or c == "_" or c == "-"): return false
	return true

fn days_in_month(y: Int, m: Int) Int:
	if m == 2:
		leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
		if leap: return 29
		return 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

fn valid_date(s: String) Bool:
	cs := s.chars()
	if cs.length() != 10: return false
	for i in 0..10:
		c := cs.get(i, "")
		if i == 4 or i == 7:
			if c != "-": return false
		else:
			if not is_digit(c): return false
	y := s.view(0, 4).parse_int().get(0)
	m := s.view(5, 7).parse_int().get(0)
	d := s.view(8, 10).parse_int().get(0)
	if y < 1: return false
	if m < 1 or m > 12: return false
	if d < 1 or d > days_in_month(y, m): return false
	return true

fn join_range(cs: List[String], a: Int, b: Int) String:
	var s = ""
	var i = a
	while i < b:
		s += cs.get(i, "")
		i += 1
	return s

fn skip_words(s: String, n: Int) String:
	cs := s.chars()
	total := cs.length()
	var i = 0
	for _k in 0..n:
		while i < total and is_ws(cs.get(i, "")):
			i += 1
		while i < total and not is_ws(cs.get(i, "")):
			i += 1
	while i < total and is_ws(cs.get(i, "")):
		i += 1
	return join_range(cs, i, total)

fn find_word(cs: List[String], w: String, need_after: Bool) Int?:
	wc := w.chars()
	wl := wc.length()
	n := cs.length()
	var i = 0
	while i + wl <= n:
		ok_before := i == 0 or is_ws(cs.get(i - 1, ""))
		if ok_before:
			var m = true
			for k in 0..wl:
				if cs.get(i + k, "") != wc.get(k, ""):
					m = false
					break
			if m:
				if i + wl == n:
					if not need_after: return i
				else:
					if is_ws(cs.get(i + wl, "")): return i
		i += 1
	return none

fn tokenize(s: String) List[String]!:
	cs := s.chars()
	n := cs.length()
	var toks = List[String]()
	var cur = ""
	var has = false
	var inq = false
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if inq:
			if c == "\\" and i + 1 < n and (cs.get(i + 1, "") == "\"" or cs.get(i + 1, "") == "\\"):
				cur += cs.get(i + 1, "")
				i += 2
				continue
			if c == "\"":
				inq = false
			else:
				cur += c
		else:
			if c == "\"":
				inq = true
				has = true
			else if is_ws(c):
				if has:
					toks.append(cur.clone())
					cur = ""
					has = false
			else:
				cur += c
				has = true
		i += 1
	if inq: return error(Error("unterminated quote"))
	if has: toks.append(cur.clone())
	return ok(toks)

fn fail(msg: String) Result[Unit, Error]:
	return error(Error(msg))

fn priority_names() List[String]:
	return ["low", "medium", "high", "critical"]

fn priority_rank(s: String) Int:
	names := priority_names()
	for i in 0..4:
		if names.get(i, "") == s: return i
	return -1

fn join_labels(l: List[String], sep: String) String:
	if l.is_empty(): return "-"
	return l.join(sep)

fn opt_str(o: String?) String:
	if x := o: return x.clone()
	return "-"

fn opt_int(o: Int?) String:
	if x := o: return "{x}"
	return "-"

fn parse_labels(value: String) List[String]!:
	var res = List[String]()
	for part in value.split(","):
		l := part.lower()
		if not label_ok(l): return error(Error("bad label '{l}'"))
		if not res.contains(l): res.append(l)
	res.sort()
	return ok(res)

fn apply_field(var d: Issue, tok: String) Unit!:
	idx := tok.index_of("=")
	if idx.is_none(): return error(Error("expected field=value, got '{tok}'"))
	pos := idx.get(0)
	if pos == 0: return error(Error("expected field=value, got '{tok}'"))
	field := tok.view(0, pos).clone()
	value := tok.view(pos + 1, tok.length()).clone()
	if field == "state": return error(Error("use move to change state"))
	if field == "title":
		if value.trim().is_empty(): return error(Error("empty title"))
		d.title = value
	else if field == "priority":
		r := priority_rank(value)
		if r < 0: return error(Error("bad priority '{value}'"))
		d.priority = r
	else if field == "assignee":
		if value == "none":
			d.assignee = none
		else:
			if value.trim().is_empty(): return error(Error("empty assignee"))
			d.assignee = value
	else if field == "points":
		if value == "none":
			d.points = none
		else:
			p := parse_uint(value)
			if p.is_none(): return error(Error("bad points '{value}'"))
			d.points = p
	else if field == "due":
		if value == "none":
			d.due = none
		else:
			if not valid_date(value): return error(Error("bad date '{value}'"))
			d.due = value
	else if field == "labels":
		if value == "none":
			d.labels = []
		else:
			d.labels = parse_labels(value)?
	else if field == "reporter":
		if value == "none":
			d.reporter = none
		else:
			if value.trim().is_empty(): return error(Error("empty reporter"))
			d.reporter = value
	else:
		return error(Error("unknown field '{field}'"))
	return ok(unit)

fn field_names() List[String]:
	return ["title", "priority", "assignee", "points", "due", "labels", "reporter"]

fn fmt_field(i: Issue, k: Int) String:
	if k == 0: return i.title.clone()
	if k == 1: return priority_names().get(i.priority, "")
	if k == 2: return opt_str(i.assignee)
	if k == 3: return opt_int(i.points)
	if k == 4: return opt_str(i.due)
	if k == 5: return join_labels(i.labels, ",")
	return opt_str(i.reporter)

fn parse_id(arg: String) Int!:
	var digits = arg.clone()
	if arg.starts_with("#"): digits = arg.view(1, arg.length()).clone()
	if not all_digits(digits): return error(Error("bad issue id '{arg}'"))
	stripped := digits.trim_start_chars("0")
	if stripped.is_empty(): return error(Error("bad issue id '{arg}'"))
	if stripped.length() > 15: return ok(999999999999999)
	return ok(stripped.parse_int().get(0))

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_opt_int(a: Int?, b: Int?) Int:
	if x := a:
		if y := b: return cmp_int(x, y)
		return -1
	if b.is_some(): return 1
	return 0

fn cmp_opt_str(a: String?, b: String?, ci: Bool) Int:
	if x := a:
		if y := b:
			if ci: return x.lower().compare(y.lower())
			return x.compare(y)
		return -1
	if b.is_some(): return 1
	return 0

fn sign(n: Int) Int:
	if n < 0: return -1
	if n > 0: return 1
	return 0

fn cmp_key(a: Issue, b: Issue, field: String) Int:
	if field == "id": return cmp_int(a.id, b.id)
	if field == "created": return cmp_int(a.created, b.created)
	if field == "updated": return cmp_int(a.updated, b.updated)
	if field == "priority": return cmp_int(a.priority, b.priority)
	if field == "state": return cmp_int(a.state, b.state)
	if field == "points": return cmp_opt_int(a.points, b.points)
	if field == "title": return sign(a.title.lower().compare(b.title.lower()))
	if field == "assignee": return sign(cmp_opt_str(a.assignee, b.assignee, true))
	if field == "reporter": return sign(cmp_opt_str(a.reporter, b.reporter, true))
	return sign(cmp_opt_str(a.due, b.due, false))

fn parse_sort(text: String) List[SortKey]!:
	var keys = List[SortKey]()
	valid := ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"]
	var cur = ""
	var parts = List[String]()
	for c in text.chars():
		if c == "," or is_ws(c):
			if not cur.is_empty():
				parts.append(cur.clone())
				cur = ""
		else:
			cur += c
	if not cur.is_empty(): parts.append(cur.clone())
	for p in parts:
		var name = p.clone()
		var desc = false
		if p.starts_with("-"):
			desc = true
			name = p.view(1, p.length()).clone()
		if not valid.contains(name): return error(Error("bad sort field '{name}'"))
		keys.append(SortKey(field: name, desc: desc))
	return ok(keys)

fn split_query(text: String) Split!:
	t := text.trim()
	cs := t.chars()
	var cend = t.chars().length()
	var has_limit = false
	var limit = ""
	// limit N at the end
	n := cs.length()
	var e = n
	while e > 0 and not is_ws(cs.get(e - 1, "")):
		e -= 1
	// word N is cs[e..n]
	if e < n and e > 0:
		var b = e
		while b > 0 and is_ws(cs.get(b - 1, "")):
			b -= 1
		var s = b
		while s > 0 and not is_ws(cs.get(s - 1, "")):
			s -= 1
		if join_range(cs, s, b) == "limit":
			has_limit = true
			limit = join_range(cs, e, n)
			cend = s
	if has_limit:
		if parse_uint(limit).is_none(): return error(Error("bad limit '{limit}'"))
	var filter = join_range(cs, 0, cend)
	var has_sort = false
	var sort = ""
	if si := find_word(cs, "sort", true):
		if si < cend:
			has_sort = true
			sort = join_range(cs, si + 4, cend)
			filter = join_range(cs, 0, si)
	return ok(Split(filter: filter.trim(), has_sort: has_sort, sort: sort, has_limit: has_limit, limit: limit))

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
			toks.append(Tok(kind: 0))
			i += 1
			continue
		if c == ")":
			toks.append(Tok(kind: 1))
			i += 1
			continue
		var j = i
		while j < n and (is_lower(cs.get(j, "")) or cs.get(j, "") == "_"):
			j += 1
		var op = ""
		if j > i and j < n:
			c1 := cs.get(j, "")
			c2 := cs.get(j + 1, "")
			if (c1 == "!" or c1 == "<" or c1 == ">") and c2 == "=":
				op = c1 + c2
			else if c1 == ":" or c1 == "<" or c1 == ">" or c1 == "~":
				op = c1
		if not op.is_empty():
			field := join_range(cs, i, j)
			k := j + op.length()
			var value = ""
			var quoted = false
			if k < n and cs.get(k, "") == "\"":
				quoted = true
				var m = k + 1
				var closed = false
				while m < n:
					ch := cs.get(m, "")
					if ch == "\\" and m + 1 < n and (cs.get(m + 1, "") == "\"" or cs.get(m + 1, "") == "\\"):
						value += cs.get(m + 1, "")
						m += 2
						continue
					if ch == "\"":
						closed = true
						m += 1
						break
					value += ch
					m += 1
				if not closed:
					toks.append(Tok(kind: 7))
					return toks
				i = m
			else:
				var m = k
				while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
					m += 1
				value = join_range(cs, k, m)
				i = m
			toks.append(Tok(kind: 5, field: field, op: op, value: value, quoted: quoted))
			continue
		var m = i
		while m < n and not is_ws(cs.get(m, "")) and cs.get(m, "") != "(" and cs.get(m, "") != ")":
			m += 1
		word := join_range(cs, i, m)
		if word == "AND":
			toks.append(Tok(kind: 2, text: word))
		else if word == "OR":
			toks.append(Tok(kind: 3, text: word))
		else if word == "NOT":
			toks.append(Tok(kind: 4, text: word))
		else:
			toks.append(Tok(kind: 6, text: word))
		i = m
	return toks

fn tok_text(t: Tok) String:
	if t.kind == 0: return "("
	if t.kind == 1: return ")"
	return t.text.clone()

fn is_overdue_str(due: String, today: String) Bool:
	return due < today

fn plural(n: Int, one: String, many: String) String:
	if n == 1: return "{n} {one}"
	return "{n} {many}"

fn parse_workflow(lines: List[String]) Workflow!:
	var names = List[String]()
	var finals = List[String]()
	var trans = List[Trans]()
	var initial = -1
	var err = ""
	for raw in lines:
		if not err.is_empty(): continue
		l := raw.trim()
		if l.is_empty() or l.starts_with("#"): continue
		if rest := l.cut_prefix("initial:"):
			name := rest.trim()
			if not state_ok(name):
				err = "workflow: bad state name '{name}'"
				continue
			if initial >= 0:
				err = "workflow: initial state defined twice"
				continue
			initial = intern(var names, name)
			continue
		if rest := l.cut_prefix("final:"):
			for part in rest.split(","):
				name := part.trim()
				if not state_ok(name):
					err = "workflow: bad state name '{name}'"
					break
				intern(var names, name)
				finals.append(name)
			continue
		idx := l.index_of("->")
		if idx.is_none():
			err = "workflow: bad line '{l}'"
			continue
		pos := idx.get(0)
		src := l.view(0, pos).trim()
		rest := l.view(pos + 2, l.length()).trim()
		if not state_ok(src):
			err = "workflow: bad state name '{src}'"
			continue
		si := intern(var names, src)
		for entry in rest.split(","):
			ws := entry.fields()
			if ws.length() == 0:
				err = "workflow: bad line '{l}'"
				break
			target := ws.get(0, "")
			if not state_ok(target):
				err = "workflow: bad state name '{target}'"
				break
			var guards = List[String]()
			if ws.length() > 1:
				if ws.get(1, "") != "requires" or ws.length() != 3:
					err = "workflow: bad line '{l}'"
					break
				var bad = ""
				var found_bad = false
				for g in ws.get(2, "").split("+"):
					if not (g == "assignee" or g == "points" or g == "due" or g == "labels" or g == "reporter"):
						bad = g
						found_bad = true
						break
					guards.append(g)
				if found_bad:
					err = "workflow: bad guard field '{bad}'"
					break
			di := intern(var names, target)
			trans.append(Trans(src: si, dst: di, guards: guards))
	if not err.is_empty(): return error(Error(err))
	if initial < 0: return error(Error("workflow: initial state missing"))
	var fl = List[Bool]()
	for n in names:
		fl.append(finals.contains(n))
	for tr in trans:
		if fl.get(tr.src, false):
			return error(Error("workflow: '{names.get(tr.src, "")}' is final and cannot have transitions"))
	return ok(Workflow(states: names, finals: fl, initial: initial, trans: trans))

fn intern(var names: List[String], s: String) Int:
	for i in 0..names.length():
		if names.get(i, "") == s: return i
	names.append(s.clone())
	return names.length() - 1

fn var App.tick() Int:
	self.t += 1
	return self.t

fn var App.add_log(id: Int, detail: String) Unit:
	self.log.append(LogEntry(t: self.t, actor: self.actor.clone(), id: id, detail: detail))

fn App.state_name(i: Int) String:
	return self.wf.states.get(i, "")

fn App.is_final(i: Int) Bool:
	return self.wf.finals.get(i, false)

fn App.find_issue(arg: String) Int!:
	n := parse_id(arg)?
	if n > self.issues.length(): return error(Error("no such issue #{n}"))
	if self.issues.get(n - 1).deleted: return error(Error("no such issue #{n}"))
	return ok(n - 1)

fn App.issue_line(i: Issue) String:
	return "#{i.id} | {self.state_name(i.state)} | {priority_names().get(i.priority, "")} | {opt_str(i.assignee)} | {opt_int(i.points)} | {opt_str(i.due)} | {join_labels(i.labels, ",")} | {i.title}"

fn App.has_label_op(i: Issue) Bool:
	return true

// ---------- query compile ----------

fn App.make_term(t: Tok, depth: Int, var refs: List[String]) QNode!:
	f := t.field
	op := t.op
	known := ["id", "created", "updated", "points", "title", "assignee", "reporter", "text", "state", "priority", "due", "label", "labels", "is", "has", "view"]
	if not known.contains(f): return error(Error("query: unknown field '{f}'"))
	var allowed = List[String]()
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "priority" or f == "due":
		allowed = [":", "!=", "<", "<=", ">", ">="]
	else if f == "title" or f == "assignee" or f == "reporter" or f == "label" or f == "labels":
		allowed = [":", "!=", "~"]
	else if f == "text":
		allowed = ["~"]
	else if f == "state":
		allowed = [":", "!="]
	else:
		allowed = [":"]
	if not allowed.contains(op): return error(Error("query: bad operator '{op}' for field '{f}'"))
	if f == "view":
		if not t.value.is_empty() or true:
			vq := self.views.get(t.value)
			if vq.is_none(): return error(Error("query: unknown view '{t.value}'"))
			if depth > 40: return error(Error("query: view nesting too deep"))
			sp := split_query(vq.get(""))?
			sub := self.compile(sp.filter, depth + 1)?
			refs.append(t.value.clone())
			for r in sub.refs:
				refs.append(r.clone())
		return ok(QNode(kind: 0, field: f.clone(), op: op.clone(), vals: [t.value.clone()]))
	ordered := op == "<" or op == "<=" or op == ">" or op == ">="
	var vals = List[String]()
	if not ordered and not t.quoted and t.value.contains("|"):
		vals = List[String]()
		for part in t.value.split("|"):
			vals.append(part.clone())
	else:
		vals = [t.value.clone()]
	var nums = List[Int]()
	for v in vals:
		if f == "id" or f == "created" or f == "updated" or f == "points":
			if f == "points" and not ordered and v == "none":
				nums.append(-1)
			else:
				p := parse_uint(v)
				if p.is_none(): return error(Error("query: bad value '{v}' for field '{f}'"))
				nums.append(p.get(0))
		else if f == "state":
			var found = -1
			for i in 0..self.wf.states.length():
				if self.wf.states.get(i, "") == v: found = i
			if found < 0: return error(Error("query: bad value '{v}' for field '{f}'"))
			nums.append(found)
		else if f == "priority":
			r := priority_rank(v)
			if r < 0: return error(Error("query: bad value '{v}' for field '{f}'"))
			nums.append(r)
		else if f == "due":
			if not ordered and v == "none":
				nums.append(-1)
			else:
				if not valid_date(v): return error(Error("query: bad value '{v}' for field '{f}'"))
				nums.append(0)
		else if f == "is":
			if not (v == "open" or v == "final" or v == "overdue" or v == "unassigned"):
				return error(Error("query: bad value '{v}' for field '{f}'"))
		else if f == "has":
			if not (v == "assignee" or v == "due" or v == "points" or v == "labels" or v == "comments" or v == "reporter"):
				return error(Error("query: bad value '{v}' for field '{f}'"))
	if f == "label" or f == "labels":
		var lv = List[String]()
		for v in vals:
			lv.append(v.lower())
		vals = lv
	return ok(QNode(kind: 0, field: f.clone(), op: op.clone(), vals: vals, nums: nums))

fn App.compile(text: String, depth: Int) Parser!:
	var p = Parser(toks: lex(text), depth: depth)
	if p.toks.is_empty():
		return ok(p)
	root := self.p_or(var p)?
	if p.pos < p.toks.length():
		t := p.toks.get(p.pos, Tok(kind: 6))
		if t.kind == 7: return error(Error("query: unterminated quote"))
		return error(Error("query: unexpected token '{tok_text(t)}'"))
	p.root = root
	return ok(p)

fn var App.dummy() Unit:
	return

fn App.p_or(var p: Parser) Int!:
	var left = self.p_and(var p)?
	while p.pos < p.toks.length() and p.toks.get(p.pos, Tok(kind: 6)).kind == 3:
		p.pos += 1
		right := self.p_and(var p)?
		p.nodes.append(QNode(kind: 2, a: left, b: right))
		left = p.nodes.length() - 1
	return ok(left)

fn App.p_and(var p: Parser) Int!:
	var left = self.p_not(var p)?
	while p.pos < p.toks.length():
		k := p.toks.get(p.pos, Tok(kind: 6)).kind
		if k == 2:
			p.pos += 1
		else if k == 0 or k == 4 or k == 5:
			p.pos += 0
		else:
			break
		right := self.p_not(var p)?
		p.nodes.append(QNode(kind: 1, a: left, b: right))
		left = p.nodes.length() - 1
	return ok(left)

fn App.p_not(var p: Parser) Int!:
	if p.pos < p.toks.length() and p.toks.get(p.pos, Tok(kind: 6)).kind == 4:
		p.pos += 1
		inner := self.p_not(var p)?
		p.nodes.append(QNode(kind: 3, a: inner))
		return ok(p.nodes.length() - 1)
	return self.p_primary(var p)

fn App.p_primary(var p: Parser) Int!:
	if p.pos >= p.toks.length(): return error(Error("query: unexpected end of query"))
	t := p.toks.get(p.pos, Tok(kind: 6))
	if t.kind == 7: return error(Error("query: unterminated quote"))
	if t.kind == 0:
		p.pos += 1
		inner := self.p_or(var p)?
		if p.pos >= p.toks.length(): return error(Error("query: unexpected end of query"))
		c := p.toks.get(p.pos, Tok(kind: 6))
		if c.kind == 7: return error(Error("query: unterminated quote"))
		if c.kind != 1: return error(Error("query: unexpected token '{tok_text(c)}'"))
		p.pos += 1
		return ok(inner)
	if t.kind == 5:
		p.pos += 1
		var refs = List[String]()
		node := self.make_term(t, p.depth, var refs)?
		for r in refs:
			p.refs.append(r.clone())
		p.nodes.append(node)
		return ok(p.nodes.length() - 1)
	return error(Error("query: unexpected token '{tok_text(t)}'"))

// ---------- query eval ----------

fn match_str(v: String?, vals: List[String], ci: Bool) Bool:
	for a in vals:
		if x := v:
			if x.lower() == a.lower(): return true
		else:
			if a == "none": return true
	return false

fn cmp_op(c: Int, op: String) Bool:
	if op == "<": return c < 0
	if op == "<=": return c <= 0
	if op == ">": return c > 0
	if op == ">=": return c >= 0
	if op == ":": return c == 0
	return c != 0

fn App.eval_node(p: Parser, i: Int, is_: Issue) Bool:
	n := p.nodes.get(i, QNode(kind: 1))
	if n.kind == 1: return self.eval_node(p, n.a, is_) and self.eval_node(p, n.b, is_)
	if n.kind == 2: return self.eval_node(p, n.a, is_) or self.eval_node(p, n.b, is_)
	if n.kind == 3: return not self.eval_node(p, n.a, is_)
	f := n.field
	op := n.op
	ordered := op == "<" or op == "<=" or op == ">" or op == ">="
	var m = false
	if f == "id" or f == "created" or f == "updated" or f == "points" or f == "priority" or f == "state":
		var cur: Int? = none
		if f == "id": cur = is_.id
		else if f == "created": cur = is_.created
		else if f == "updated": cur = is_.updated
		else if f == "points": cur = is_.points
		else if f == "priority": cur = is_.priority
		else: cur = is_.state
		if ordered:
			if x := cur:
				return cmp_op(cmp_int(x, n.nums.get(0, 0)), op)
			return false
		for a in n.nums:
			if x := cur:
				if a == x: m = true
			else:
				if a == -1: m = true
		if op == ":": return m
		return not m
	if f == "title" or f == "assignee" or f == "reporter":
		var v: String? = none
		if f == "title": v = is_.title.clone()
		else if f == "assignee": v = is_.assignee.clone()
		else: v = is_.reporter.clone()
		if op == "~":
			if x := v:
				for a in n.vals:
					if x.lower().contains(a.lower()): return true
			return false
		m = match_str(v, n.vals, true)
		if op == ":": return m
		return not m
	if f == "text":
		for a in n.vals:
			al := a.lower()
			if is_.title.lower().contains(al): return true
			for c in is_.comments:
				if c.text.lower().contains(al): return true
		return false
	if f == "due":
		if ordered:
			if x := is_.due:
				return cmp_op(sign(x.compare(n.vals.get(0, ""))), op)
			return false
		for a in n.vals:
			if x := is_.due:
				if x == a: m = true
			else:
				if a == "none": m = true
		if op == ":": return m
		return not m
	if f == "label" or f == "labels":
		for a in n.vals:
			if op == "~":
				for l in is_.labels:
					if l.contains(a): m = true
			else:
				if a == "none" and is_.labels.is_empty(): m = true
				if is_.labels.contains(a): m = true
		if op == "!=": return not m
		return m
	if f == "is":
		for a in n.vals:
			if a == "open" and not self.is_final(is_.state): m = true
			if a == "final" and self.is_final(is_.state): m = true
			if a == "unassigned" and is_.assignee.is_none(): m = true
			if a == "overdue" and not self.is_final(is_.state):
				if d := is_.due:
					if d < self.today: m = true
		return m
	if f == "has":
		for a in n.vals:
			if a == "assignee" and is_.assignee.is_some(): m = true
			if a == "due" and is_.due.is_some(): m = true
			if a == "points" and is_.points.is_some(): m = true
			if a == "reporter" and is_.reporter.is_some(): m = true
			if a == "labels" and not is_.labels.is_empty(): m = true
			if a == "comments" and not is_.comments.is_empty(): m = true
		return m
	if f == "view":
		vq := self.views.get(n.vals.get(0, ""))
		if q := vq:
			sp := split_query(q)
			if s := sp:
				pr := self.compile(s.filter, p.depth + 1)
				if c := pr:
					if c.toks.is_empty(): return true
					return self.eval_node(c, c.root, is_)
		return false
	return false

fn App.matching(filter: String) List[Int]!:
	p := self.compile(filter, 0)?
	var res = List[Int]()
	for i in 0..self.issues.length():
		is_ := self.issues.get(i).clone()
		if is_.deleted: continue
		if p.toks.is_empty() or self.eval_node(p, p.root, is_):
			res.append(i)
	return ok(res)

fn App.run_list(filter: String, has_sort: Bool, sort: String, has_limit: Bool, limit: String) String!:
	idxs := self.matching(filter)?
	var keys = List[SortKey]()
	if has_sort: keys = parse_sort(sort)?
	var ids = idxs.clone()
	ids.sort(fn a, b: self.compare_idx(a, b, keys))
	var lim = -1
	if has_limit: lim = parse_uint(limit).get(0)
	var lines = List[String]()
	for i in ids:
		if lim >= 0 and lines.length() >= lim: break
		lines.append(self.issue_line(self.issues.get(i)))
	n := lines.length()
	lines.append("({plural(n, "issue", "issues")})")
	return ok(lines.join("\n"))

fn App.compare_idx(a: Int, b: Int, keys: List[SortKey]) Int:
	ia := self.issues.get(a).clone()
	ib := self.issues.get(b).clone()
	for k in keys:
		c := cmp_key(ia, ib, k.field)
		if c != 0:
			if k.desc: return -c
			return c
	return cmp_int(ia.id, ib.id)

// ---------- commands ----------

fn var App.commit_edit(idx: Int, d: Issue) String:
	old := self.issues.get(idx).clone()
	var changed = List[Int]()
	for k in 0..7:
		if fmt_field(old, k) != fmt_field(d, k): changed.append(k)
	if changed.is_empty(): return "#{old.id} unchanged"
	t := self.tick()
	var nd = d.clone()
	nd.updated = t
	names := field_names()
	for k in changed:
		self.add_log(old.id, "{names.get(k, "")}: {fmt_field(old, k)} -> {fmt_field(nd, k)}")
	self.issues[idx] = nd
	return "updated #{old.id}"

fn var App.do_edit(idarg: String, toks: List[String]) String!:
	idx := self.find_issue(idarg)?
	cur := self.issues.get(idx).clone()
	if self.is_final(cur.state): return error(Error("#{cur.id} is in final state '{self.state_name(cur.state)}'"))
	var d = cur.clone()
	for tok in toks:
		apply_field(var d, tok)?
	if toks.is_empty(): return error(Error("usage: edit ID field=value..."))
	return ok(self.commit_edit(idx, d))

fn var App.do_label(idarg: String, toks: List[String]) String!:
	idx := self.find_issue(idarg)?
	cur := self.issues.get(idx).clone()
	if self.is_final(cur.state): return error(Error("#{cur.id} is in final state '{self.state_name(cur.state)}'"))
	var labels = cur.labels.clone()
	for tok in toks:
		var name = tok.clone()
		var remove = false
		if tok.starts_with("+"):
			name = tok.view(1, tok.length()).clone()
		else if tok.starts_with("-"):
			name = tok.view(1, tok.length()).clone()
			remove = true
		l := name.lower()
		if not label_ok(l): return error(Error("bad label '{l}'"))
		if remove:
			var nl = List[String]()
			for x in labels:
				if x != l: nl.append(x.clone())
			labels = nl
		else:
			if not labels.contains(l): labels.append(l)
	labels.sort()
	var d = cur.clone()
	d.labels = labels
	return ok(self.commit_edit(idx, d))

fn var App.do_move(idarg: String, target: String, comment: String) String!:
	idx := self.find_issue(idarg)?
	cur := self.issues.get(idx).clone()
	if self.is_final(cur.state): return error(Error("#{cur.id} is in final state '{self.state_name(cur.state)}'"))
	var ti = -1
	for i in 0..self.wf.states.length():
		if self.wf.states.get(i, "") == target: ti = i
	if ti < 0: return error(Error("unknown state '{target}'"))
	if ti == cur.state: return error(Error("already in state '{target}'"))
	var found = false
	var guards = List[String]()
	for tr in self.wf.trans:
		if tr.src == cur.state and tr.dst == ti:
			found = true
			guards = tr.guards.clone()
			break
	from := self.state_name(cur.state)
	if not found: return error(Error("transition '{from} -> {target}' not allowed"))
	var missing = List[String]()
	for g in guards:
		var unmet = false
		if g == "assignee": unmet = cur.assignee.is_none()
		else if g == "points": unmet = cur.points.is_none()
		else if g == "due": unmet = cur.due.is_none()
		else if g == "labels": unmet = cur.labels.is_empty()
		else: unmet = cur.reporter.is_none()
		if unmet: missing.append(g.clone())
	if not missing.is_empty():
		return error(Error("cannot move #{cur.id} to {target}: missing {missing.join(", ")}"))
	t := self.tick()
	var nd = cur.clone()
	nd.state = ti
	nd.updated = t
	nd.hist.append(t)
	nd.hist.append(ti)
	self.add_log(cur.id, "state: {from} -> {target}")
	if not comment.is_empty():
		nd.comments.append(Comment(t: t, actor: self.actor.clone(), text: comment.clone()))
		self.add_log(cur.id, "comment: {comment}")
	self.issues[idx] = nd
	return ok("moved #{cur.id}: {from} -> {target}")

fn var App.cmd_create(rest: String) String!:
	if not self.has_wf: return error(Error("no workflow defined"))
	toks := tokenize(rest)?
	if toks.is_empty(): return error(Error("usage: create TITLE [field=value...]"))
	title := toks.get(0, "")
	if title.trim().is_empty(): return error(Error("empty title"))
	id := self.issues.length() + 1
	var d = Issue(id: id, title: title.clone(), state: self.wf.initial, reporter: self.actor.clone())
	var rep_given = false
	for k in 1..toks.length():
		tok := toks.get(k, "")
		apply_field(var d, tok)?
		if tok.starts_with("reporter="): rep_given = true
	t := self.tick()
	d.created = t
	d.updated = t
	d.hist = [t, d.state]
	self.add_log(id, "created \"{title}\"")
	names := field_names()
	for k in 0..7:
		var oldv = "-"
		if k == 0: oldv = title.clone()
		if k == 1: oldv = "medium"
		if k == 6 and not rep_given: oldv = fmt_field(d, 6)
		newv := fmt_field(d, k)
		if oldv != newv:
			self.add_log(id, "{names.get(k, "")}: {oldv} -> {newv}")
	self.issues.append(d)
	return ok("created #{id}")

fn var App.cmd_comment(rest: String) String!:
	ws := rest.fields()
	if ws.length() < 2: return error(Error("usage: comment ID TEXT"))
	idx := self.find_issue(ws.get(0, ""))?
	text := skip_words(rest, 1)
	t := self.tick()
	var nd = self.issues.get(idx).clone()
	nd.updated = t
	nd.comments.append(Comment(t: t, actor: self.actor.clone(), text: text.clone()))
	self.add_log(nd.id, "comment: {text}")
	self.issues[idx] = nd.clone()
	return ok("commented #{nd.id}")

fn var App.cmd_delete(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: delete ID"))
	idx := self.find_issue(ws.get(0, ""))?
	self.tick()
	self.issues[idx].deleted = true
	id := self.issues.get(idx).id
	self.add_log(id, "deleted")
	return ok("deleted #{id}")

fn App.cmd_show(rest: String) String!:
	ws := rest.fields()
	if ws.length() != 1: return error(Error("usage: show ID"))
	idx := self.find_issue(ws.get(0, ""))?
	i := self.issues.get(idx).clone()
	var lines = List[String]()
	lines.append("#{i.id} {i.title}")
	lines.append("  state: {self.state_name(i.state)}")
	lines.append("  priority: {priority_names().get(i.priority, "")}")
	lines.append("  assignee: {opt_str(i.assignee)}")
	lines.append("  points: {opt_int(i.points)}")
	lines.append("  due: {opt_str(i.due)}")
	lines.append("  labels: {join_labels(i.labels, ", ")}")
	lines.append("  reporter: {opt_str(i.reporter)}")
	lines.append("  created: t={i.created}, updated: t={i.updated}")
	lines.append("  comments: {i.comments.length()}")
	for c in i.comments:
		lines.append("    [t={c.t} {c.actor}] {c.text}")
	return ok(lines.join("\n"))

fn App.cmd_log(rest: String) String!:
	ws := rest.fields()
	usage := "usage: log [ID] [tail N]"
	var id = -1
	var tail = -1
	var k = 0
	if ws.length() > 0 and ws.get(0, "") != "tail":
		n := parse_id(ws.get(0, ""))?
		if n > self.issues.length(): return error(Error("no such issue #{n}"))
		id = n
		k = 1
	if k < ws.length():
		if ws.get(k, "") != "tail": return error(Error(usage))
		if k + 2 != ws.length(): return error(Error(usage))
		arg := ws.get(k + 1, "")
		p := parse_uint(arg)
		if p.is_none(): return error(Error("bad tail '{arg}'"))
		tail = p.get(0)
	var lines = List[String]()
	for e in self.log:
		if id < 0 or e.id == id:
			lines.append("t={e.t} {e.actor} #{e.id} {e.detail}")
	if tail >= 0 and lines.length() > tail:
		var cut = List[String]()
		for i in (lines.length() - tail)..lines.length():
			cut.append(lines.get(i, ""))
		lines = cut
	if lines.is_empty(): return ok("(no log entries)")
	return ok(lines.join("\n"))

fn var App.cmd_view(rest: String) String!:
	ws := rest.fields()
	sub := ws.get(0, "")
	generic := "usage: view save|run|list|show|delete"
	if sub == "save":
		if ws.length() < 2: return error(Error("usage: view save NAME QUERY"))
		name := ws.get(1, "")
		if not view_name_ok(name): return error(Error("bad view name '{name}'"))
		q := skip_words(rest, 2).trim()
		sp := split_query(q)?
		p := self.compile(sp.filter, 0)?
		if sp.has_sort:
			_keys := parse_sort(sp.sort)?
		if p.refs.contains(name): return error(Error("view '{name}' would reference itself"))
		self.views[name.clone()] = q.clone()
		return ok("saved view {name}")
	if sub == "run":
		if ws.length() < 2: return error(Error("usage: view run NAME [sort FIELDS] [limit N]"))
		name := ws.get(1, "")
		stored := self.views.get(name)
		if stored.is_none(): return error(Error("unknown view '{name}'"))
		sp := split_query(stored.get(""))?
		ex := split_query(skip_words(rest, 2))?
		if not ex.filter.is_empty(): return error(Error("unexpected '{ex.filter}'"))
		var hs = sp.has_sort
		var sv = sp.sort.clone()
		if ex.has_sort:
			hs = true
			sv = ex.sort.clone()
		var hl = sp.has_limit
		var lv = sp.limit.clone()
		if ex.has_limit:
			hl = true
			lv = ex.limit.clone()
		return self.run_list(sp.filter, hs, sv, hl, lv)
	if sub == "list":
		if ws.length() != 1: return error(Error("usage: view save|run|list|show|delete"))
		if self.views.length() == 0: return ok("(no views)")
		var names = self.views.keys().clone()
		names.sort()
		var lines = List[String]()
		for n in names:
			lines.append("{n}: {self.views.get_or(n, "")}")
		return ok(lines.join("\n"))
	if sub == "show":
		if ws.length() != 2: return error(Error("usage: view show NAME"))
		name := ws.get(1, "")
		stored := self.views.get(name)
		if stored.is_none(): return error(Error("unknown view '{name}'"))
		return ok("{name}: {stored.get("")}")
	if sub == "delete":
		if ws.length() != 2: return error(Error("usage: view delete NAME"))
		name := ws.get(1, "")
		if not self.views.contains(name): return error(Error("unknown view '{name}'"))
		var names = self.views.keys().clone()
		names.sort()
		for m in names:
			if m == name: continue
			sp := split_query(self.views.get_or(m, ""))
			if s := sp:
				pr := self.compile(s.filter, 0)
				if c := pr:
					if c.refs.contains(name): return error(Error("view '{name}' is used by '{m}'"))
		self.views.remove(name.clone())
		return ok("deleted view {name}")
	return error(Error(generic))

fn var App.cmd_bulk(rest: String) String!:
	cs := rest.chars()
	usage := "usage: bulk ACTION... where QUERY"
	wi := find_word(cs, "where", false)
	if wi.is_none(): return error(Error(usage))
	w := wi.get(0)
	before := join_range(cs, 0, w)
	after := join_range(cs, w + 5, cs.length()).trim()
	if before.trim().is_empty(): return error(Error(usage))
	toks := tokenize(before)?
	act := toks.get(0, "")
	var rest_toks = List[String]()
	for i in 1..toks.length():
		rest_toks.append(toks.get(i, "").clone())
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
	idxs := self.matching(after)?
	var lines = List[String]()
	var okc = 0
	var failc = 0
	for i in idxs:
		id := self.issues.get(i).id
		ids := "{id}"
		var r: String! = ok("")
		if act == "move":
			r = self.do_move(ids, rest_toks.get(0, ""), "")
		else if act == "assign":
			r = self.do_edit(ids, ["assignee=" + rest_toks.get(0, "")])
		else if act == "label":
			r = self.do_label(ids, rest_toks)
		else:
			r = self.do_edit(ids, rest_toks)
		if v := r:
			lines.append(v.clone())
			okc += 1
		else:
			lines.append("#{id} error: {r.err().message}")
			failc += 1
	lines.append("bulk: {okc} ok, {failc} failed")
	return ok(lines.join("\n"))

fn App.cmd_report(rest: String) String!:
	ws := rest.fields()
	usage := "usage: report summary|workload|labels|timeline"
	if ws.is_empty(): return error(Error(usage))
	sub := ws.get(0, "")
	if sub == "summary":
		if ws.length() != 1: return error(Error(usage))
		var total = 0
		var open = 0
		var fin = 0
		var unassigned = 0
		var overdue = 0
		var pts = 0
		var by_state = List[Int]()
		for _s in self.wf.states:
			by_state.append(0)
		var by_pri = [0, 0, 0, 0]
		for i in self.issues:
			if i.deleted: continue
			total += 1
			by_state[i.state] = by_state.get(i.state, 0) + 1
			by_pri[i.priority] = by_pri.get(i.priority, 0) + 1
			if self.is_final(i.state):
				fin += 1
			else:
				open += 1
				if i.assignee.is_none(): unassigned += 1
				if d := i.due:
					if d < self.today: overdue += 1
				pts += i.points.get(0)
		var lines = List[String]()
		lines.append("issues: {total} (open {open}, final {fin})")
		lines.append("by state:")
		for k in 0..self.wf.states.length():
			lines.append("  {self.wf.states.get(k, "")}: {by_state.get(k, 0)}")
		lines.append("by priority:")
		lines.append("  critical: {by_pri.get(3, 0)}")
		lines.append("  high: {by_pri.get(2, 0)}")
		lines.append("  medium: {by_pri.get(1, 0)}")
		lines.append("  low: {by_pri.get(0, 0)}")
		lines.append("unassigned: {unassigned}")
		lines.append("overdue: {overdue}")
		lines.append("open points: {pts}")
		return ok(lines.join("\n"))
	if sub == "workload":
		if ws.length() != 1: return error(Error(usage))
		var keys = List[String]()
		var disp = List[String]()
		var cnt = List[Int]()
		var pt = List[Int]()
		var un_c = 0
		var un_p = 0
		var any = false
		for i in self.issues:
			if i.deleted or self.is_final(i.state): continue
			any = true
			if a := i.assignee:
				k := a.lower()
				var pos = -1
				for j in 0..keys.length():
					if keys.get(j, "") == k: pos = j
				if pos < 0:
					keys.append(k)
					disp.append(a.clone())
					cnt.append(0)
					pt.append(0)
					pos = keys.length() - 1
				cnt[pos] = cnt.get(pos, 0) + 1
				pt[pos] = pt.get(pos, 0) + i.points.get(0)
			else:
				un_c += 1
				un_p += i.points.get(0)
		if not any: return ok("(no open issues)")
		var order = List[Int]()
		for j in 0..keys.length():
			order.append(j)
		order.sort(fn a, b: self.wl_cmp(a, b, keys, cnt, pt))
		var lines = List[String]()
		for j in order:
			lines.append("{disp.get(j, "")}: {plural(cnt.get(j, 0), "issue", "issues")}, {pt.get(j, 0)} points")
		if un_c > 0:
			lines.append("unassigned: {plural(un_c, "issue", "issues")}, {un_p} points")
		return ok(lines.join("\n"))
	if sub == "labels":
		filter := skip_words(rest, 1)
		idxs := self.matching(filter)?
		var names = List[String]()
		var counts = List[Int]()
		for i in idxs:
			for l in self.issues.get(i).labels.clone():
				var pos = -1
				for j in 0..names.length():
					if names.get(j, "") == l: pos = j
				if pos < 0:
					names.append(l.clone())
					counts.append(0)
					pos = names.length() - 1
				counts[pos] = counts.get(pos, 0) + 1
		if names.is_empty(): return ok("(no labels)")
		var order = List[Int]()
		for j in 0..names.length():
			order.append(j)
		order.sort(fn a, b: self.lb_cmp(a, b, names, counts))
		var lines = List[String]()
		for j in order:
			lines.append("{names.get(j, "")}: {counts.get(j, 0)}")
		return ok(lines.join("\n"))
	if sub == "timeline":
		if ws.length() != 2: return error(Error("usage: report timeline ID"))
		idx := self.find_issue(ws.get(1, ""))?
		h := self.issues.get(idx).hist.clone()
		var lines = List[String]()
		var k = 0
		while k + 1 < h.length():
			from := h.get(k, 0)
			var to = self.t
			if k + 2 < h.length(): to = h.get(k + 2, 0)
			lines.append("{self.state_name(h.get(k + 1, 0))}: t={from}..{to} ({to - from})")
			k += 2
		return ok(lines.join("\n"))
	return error(Error(usage))

fn wl_cmp_dummy() Int:
	return 0

fn App.wl_cmp(a: Int, b: Int, keys: List[String], cnt: List[Int], pt: List[Int]) Int:
	c := cmp_int(pt.get(b, 0), pt.get(a, 0))
	if c != 0: return c
	c2 := cmp_int(cnt.get(b, 0), cnt.get(a, 0))
	if c2 != 0: return c2
	return sign(keys.get(a, "").compare(keys.get(b, "")))

fn App.lb_cmp(a: Int, b: Int, names: List[String], counts: List[Int]) Int:
	c := cmp_int(counts.get(b, 0), counts.get(a, 0))
	if c != 0: return c
	return sign(names.get(a, "").compare(names.get(b, "")))

fn var App.emit(r: String!) Unit:
	if v := r:
		self.out.append(v.clone())
	else:
		self.out.append("error: {r.err().message}")

fn var App.cmd_workflow(body: List[String]) Unit:
	if not self.issues.is_empty():
		self.out.append("error: workflow: cannot redefine after issues were created")
		return
	r := parse_workflow(body)
	if w := r:
		self.out.append("workflow ok: {w.states.length()} states, {w.trans.length()} transitions")
		self.wf = w.clone()
		self.has_wf = true
	else:
		self.out.append("error: {r.err().message}")

fn var App.run_line(line: String) Unit:
	cs := line.trim_start()
	ws := cs.fields()
	cmd := ws.get(0, "")
	rest := skip_words(cs, 1)
	if cmd == "actor":
		if ws.length() != 2:
			self.out.append("error: usage: actor NAME")
		else:
			self.actor = ws.get(1, "").clone()
			self.out.append("actor is {self.actor}")
	else if cmd == "today":
		if ws.length() != 2:
			self.out.append("error: usage: today DATE")
		else if not valid_date(ws.get(1, "")):
			self.out.append("error: bad date '{ws.get(1, "")}'")
		else:
			self.today = ws.get(1, "").clone()
			self.out.append("today is {self.today}")
	else if cmd == "create":
		self.emit(self.cmd_create(rest))
	else if cmd == "edit":
		toks := tokenize(rest)
		if tk := toks:
			if tk.is_empty():
				self.out.append("error: usage: edit ID field=value...")
			else:
				var others = List[String]()
				for i in 1..tk.length():
					others.append(tk.get(i, "").clone())
				self.emit(self.do_edit(tk.get(0, ""), others))
		else:
			self.out.append("error: {toks.err().message}")
	else if cmd == "label":
		toks := tokenize(rest)
		if tk := toks:
			if tk.length() < 2:
				self.out.append("error: usage: label ID +label -label...")
			else:
				var others = List[String]()
				for i in 1..tk.length():
					others.append(tk.get(i, "").clone())
				self.emit(self.do_label(tk.get(0, ""), others))
		else:
			self.out.append("error: {toks.err().message}")
	else if cmd == "assign":
		toks := tokenize(rest)
		if tk := toks:
			if tk.length() != 2:
				self.out.append("error: usage: assign ID NAME")
			else:
				self.emit(self.do_edit(tk.get(0, ""), ["assignee=" + tk.get(1, "")]))
		else:
			self.out.append("error: {toks.err().message}")
	else if cmd == "move":
		if ws.length() < 3:
			self.out.append("error: usage: move ID STATE [comment...]")
		else:
			self.emit(self.do_move(ws.get(1, ""), ws.get(2, ""), skip_words(rest, 2)))
	else if cmd == "comment":
		self.emit(self.cmd_comment(rest))
	else if cmd == "delete":
		self.emit(self.cmd_delete(rest))
	else if cmd == "show":
		self.emit(self.cmd_show(rest))
	else if cmd == "list":
		self.emit(self.cmd_list(rest))
	else if cmd == "view":
		self.emit(self.cmd_view(rest))
	else if cmd == "bulk":
		self.emit(self.cmd_bulk(rest))
	else if cmd == "log":
		self.emit(self.cmd_log(rest))
	else if cmd == "report":
		self.emit(self.cmd_report(rest))
	else:
		self.out.append("error: unknown command '{cmd}'")

fn App.cmd_list(rest: String) String!:
	sp := split_query(rest)?
	return self.run_list(sp.filter, sp.has_sort, sp.sort, sp.has_limit, sp.limit)

fn var App.run(lines: List[String]) Unit:
	var i = 0
	while i < lines.length():
		raw := lines.get(i, "")
		i += 1
		t := raw.trim()
		if t.is_empty() or t.starts_with("#"): continue
		self.out.append("> {raw.trim_end()}")
		cmd := t.fields().get(0, "")
		if cmd == "workflow":
			var body = List[String]()
			while i < lines.length():
				l := lines.get(i, "")
				i += 1
				if l.trim() == "end": break
				body.append(l.clone())
			self.cmd_workflow(body)
		else:
			self.run_line(raw)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().get("")
	var lines = List[String]()
	for l in text.split("\n"):
		if l.ends_with("\r"):
			lines.append(l.view(0, l.length() - 1).clone())
		else:
			lines.append(l.clone())
	var app = App()
	app.run(lines)
	if not app.out.is_empty():
		print(app.out.join("\n"))
