import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

// ---------------------------------------------------------------- records

type Comment:
	t: Int
	actor: String
	text: String

// Absent values: assignee/reporter/due are "", points is -1.
type Issue:
	id: Int
	title: String
	state: String
	priority: Int
	assignee: String
	reporter: String
	points: Int
	due: String
	labels: List[String]
	comments: List[Comment]
	created: Int
	updated: Int

type Edge:
	src: String
	dst: String
	guards: List[String]

type WF:
	has_initial: Bool
	initial: String
	states: List[String]
	finals: List[String]
	edges: List[Edge]
	ntrans: Int

type View:
	name: String
	query: String

type LogEntry:
	t: Int
	actor: String
	id: Int
	detail: String

// kind: 0 term, 1 and, 2 or, 3 not
type Node:
	kind: Int
	kids: List[Node]
	field: String
	op: String
	alts: List[String]

type Upd:
	has_title: Bool
	title: String
	has_priority: Bool
	priority: Int
	has_assignee: Bool
	assignee: String
	has_points: Bool
	points: Int
	has_due: Bool
	due: String
	has_labels: Bool
	labels: List[String]
	has_reporter: Bool
	reporter: String

type SortKey:
	field: String
	desc: Bool

type Compiled:
	node: Node
	keys: List[SortKey]
	limit: Int

type QParts:
	filter: String
	has_sort: Bool
	sort: String
	has_limit: Bool
	limit: String

type WS:
	found: Bool
	before: String
	query: String

type FTok:
	kind: Int
	text: String

type FParser:
	toks: List[FTok]
	pos: Int

type LC:
	name: String
	count: Int

type WG:
	key: String
	name: String
	count: Int
	points: Int

type App:
	actor: String
	today: String
	clock: Int
	next_id: Int
	wf: WF
	issues: List[Issue]
	logs: List[LogEntry]
	views: List[View]

// ---------------------------------------------------------------- small helpers

fn is_sp(c: String) Bool:
	return c == " " or c == "\t"

fn prefix(s: String, n: Int) String:
	if n <= 0: return ""
	if n >= s.length(): return s.clone()

	return s.slice_scalars(0, n).get()

fn after(s: String, n: Int) String:
	if n >= s.length(): return ""
	if n <= 0: return s.clone()

	return s.slice_scalars(n, s.length()).get()

// Text after the first `n` whitespace-separated words of `line`, leading blanks
// removed.
fn rest_after(line: String, n: Int) String:
	cs := line.chars()
	len := cs.length()
	var i = 0

	for k in 0..n:
		while i < len and is_sp(cs[i]):
			i += 1
		while i < len and not is_sp(cs[i]):
			i += 1

	while i < len and is_sp(cs[i]):
		i += 1

	var out = ""

	while i < len:
		out += cs[i]
		i += 1

	return out

fn split_ws(s: String) List[String]:
	var out = List[String]()
	var cur = ""
	var has = false

	for c in s.chars():
		if is_sp(c):
			if has:
				out.append(cur.clone())
				cur = ""
				has = false
		else:
			cur += c
			has = true

	if has:
		out.append(cur.clone())
	return out

fn tail(xs: List[String], from: Int) List[String]:
	var out = List[String]()
	var i = from

	while i < xs.length():
		out.append(xs[i].clone())
		i += 1

	return out

fn dash(s: String) String:
	if s.is_empty(): return "-"
	return s.clone()

fn pts_text(p: Int) String:
	if p < 0: return "-"
	return "{p}"

fn labels_text(xs: List[String]) String:
	return xs.join(",")

fn labels_dash(xs: List[String]) String:
	if xs.is_empty(): return "-"
	return xs.join(",")

fn labels_sp(xs: List[String]) String:
	if xs.is_empty(): return "-"
	return xs.join(", ")

fn cmp_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1

	return 0

fn cmp_str(a: String, b: String) Int:
	if a < b: return -1
	if a > b: return 1

	return 0

// Integer rule: digits only, no leading zeros unless "0", at most 1000000. -1 when
// invalid.
fn rule_int(s: String) Int:
	n := s.length()
	if n == 0 or n > 7: return -1
	if n > 1 and s.starts_with("0"): return -1

	for c in s.chars():
		if c < "0" or c > "9": return -1

	v := s.parse_int().get(-1)
	if v > 1000000: return -1

	return v

// Issue id argument: optional '#', digits, value >= 1. 0 when invalid.
fn parse_id(arg: String) Int:
	var body = arg.clone()
	if arg.starts_with("#"):
		body = after(arg, 1)
	if body.is_empty(): return 0

	var v = 0

	for c in body.chars():
		d := "0123456789".index_of(c)
		if d.is_none(): return 0

		if v < 1000000000000:
			v = v * 10 + d.get(0)

	if v == 0: return 0

	return v

fn days_in(y: Int, m: Int) Int:
	if m == 2:
		if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0: return 29
		return 28

	if m == 4 or m == 6 or m == 9 or m == 11: return 30

	return 31

fn valid_date(s: String) Bool:
	if s.length() != 10: return false

	cs := s.chars()

	for i in 0..10:
		if i == 4 or i == 7:
			if cs[i] != "-": return false
		else if cs[i] < "0" or cs[i] > "9":
			return false

	y := s.slice_scalars(0, 4).get().parse_int().get(0)
	mo := s.slice_scalars(5, 7).get().parse_int().get(0)
	d := s.slice_scalars(8, 10).get().parse_int().get(0)
	if y < 1 or mo < 1 or mo > 12: return false

	return d >= 1 and d <= days_in(y, mo)

fn valid_name(s: String, dash_ok: Bool) Bool:
	if s.is_empty(): return false

	var i = 0

	for c in s.chars():
		lower_c := c >= "a" and c <= "z"
		digit_c := c >= "0" and c <= "9"
		under := c == "_"
		dsh := dash_ok and c == "-"

		if i == 0:
			if not lower_c: return false
		else if not (lower_c or digit_c or under or dsh):
			return false

		i += 1

	return true

fn valid_state(s: String) Bool:
	return valid_name(s, false)

fn valid_label(s: String) Bool:
	if s.is_empty(): return false

	for c in s.chars():
		lower_c := c >= "a" and c <= "z"
		digit_c := c >= "0" and c <= "9"
		if not (lower_c or digit_c or c == "_" or c == "-"): return false

	return true

fn prio_rank(s: String) Int:
	if s == "low": return 0
	if s == "medium": return 1
	if s == "high": return 2
	if s == "critical": return 3

	return -1

fn prio_name(r: Int) String:
	if r == 0: return "low"
	if r == 2: return "high"
	if r == 3: return "critical"

	return "medium"

fn is_guard(g: String) Bool:
	return ["assignee", "points", "due", "labels", "reporter"].contains(g)

fn add_label(var xs: List[String], l: String) Unit:
	if not xs.contains(l):
		xs.append(l.clone())
		xs.sort()

fn remove_label(var xs: List[String], l: String) Unit:
	var i = 0

	while i < xs.length():
		if xs[i] == l:
			xs.remove(i)
			return

		i += 1

// Parses a comma list of labels, lowercased, sorted and deduplicated.
fn parse_labels(val: String) Result[List[String], String]:
	var out = List[String]()

	for part in val.split(","):
		l := part.lower()
		if not valid_label(l): return error("bad label '{l}'")

		add_label(var out, l)

	return ok(out)

fn empty_upd() Upd:
	return Upd(
		has_title: false, title: "", has_priority: false, priority: 1,
		has_assignee: false, assignee: "", has_points: false, points: -1,
		has_due: false, due: "", has_labels: false, labels: List[String](),
		has_reporter: false, reporter: ""
	)

fn empty_wf() WF:
	return WF(
		has_initial: false, initial: "", states: List[String](), finals: List[String](),
		edges: List[Edge](), ntrans: 0
	)

fn report(bulk: Bool, id: Int, msg: String) Unit:
	if bulk:
		print("#{id} error: {msg}")
	else:
		print("error: {msg}")

// ---------------------------------------------------------------- token-style arguments

// Quote-aware split on spaces/tabs; a quote starts a section inside a token.
fn tokenize(s: String) Result[List[String], String]:
	cs := s.chars()
	n := cs.length()
	var out = List[String]()
	var cur = ""
	var in_tok = false
	var i = 0

	while i < n:
		c := cs[i]

		if is_sp(c):
			if in_tok:
				out.append(cur.clone())
				cur = ""
				in_tok = false

			i += 1
		else if c == "\"":
			in_tok = true
			i += 1

			var closed = false

			while i < n and not closed:
				d := cs[i]

				if d == "\"":
					closed = true
					i += 1
				else if (
					d == "\\"
					and i + 1 < n
					and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
				):
					cur += cs[i + 1]
					i += 2
				else:
					cur += d
					i += 1

			if not closed: return error("unterminated quote")
		else:
			in_tok = true
			cur += c
			i += 1

	if in_tok:
		out.append(cur.clone())
	return ok(out)

// Applies one field=value token to an update. Returns the error text, or "".
fn token_upd(var up: Upd, tok: String) String:
	eq := tok.index_of("=")
	if eq.is_none(): return "expected field=value, got '{tok}'"

	k := eq.get(0)
	if k == 0: return "expected field=value, got '{tok}'"

	field := prefix(tok, k)
	val := after(tok, k + 1)
	if field == "state": return "use move to change state"

	if field == "title":
		if val.trim().is_empty(): return "empty title"

		up.has_title = true
		up.title = val.clone()
		return ""

	if field == "priority":
		r := prio_rank(val)
		if r < 0: return "bad priority '{val}'"

		up.has_priority = true
		up.priority = r
		return ""

	if field == "assignee":
		if val == "none":
			up.has_assignee = true
			up.assignee = ""
			return ""

		if val.trim().is_empty(): return "empty assignee"

		up.has_assignee = true
		up.assignee = val.clone()
		return ""

	if field == "reporter":
		if val == "none":
			up.has_reporter = true
			up.reporter = ""
			return ""

		if val.trim().is_empty(): return "empty reporter"

		up.has_reporter = true
		up.reporter = val.clone()
		return ""

	if field == "points":
		if val == "none":
			up.has_points = true
			up.points = -1
			return ""

		p := rule_int(val)
		if p < 0: return "bad points '{val}'"

		up.has_points = true
		up.points = p
		return ""

	if field == "due":
		if val == "none":
			up.has_due = true
			up.due = ""
			return ""

		if not valid_date(val): return "bad date '{val}'"

		up.has_due = true
		up.due = val.clone()
		return ""

	if field == "labels":
		if val == "none":
			up.has_labels = true
			up.labels = List[String]()
			return ""

		pr := parse_labels(val)
		if pr.is_error(): return pr.err()

		up.has_labels = true
		up.labels = pr.get()
		return ""

	return "unknown field '{field}'"

// Splits a filter/query value on unquoted '|'; quoted text is kept whole.
fn parse_alts(raw: String) List[String]:
	cs := raw.chars()
	n := cs.length()
	var out = List[String]()
	var cur = ""
	var i = 0

	while i < n:
		c := cs[i]

		if c == "\"":
			i += 1

			var closed = false

			while i < n and not closed:
				if (
					cs[i] == "\\"
					and i + 1 < n
					and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
				):
					cur += cs[i + 1]
					i += 2
				else if cs[i] == "\"":
					closed = true
					i += 1
				else:
					cur += cs[i]
					i += 1
		else if c == "|":
			out.append(cur.clone())
			cur = ""
			i += 1
		else:
			cur += c
			i += 1

	out.append(cur.clone())
	return out

// ---------------------------------------------------------------- query parsing

fn tokenize_filter(s: String) Result[List[FTok], String]:
	cs := s.chars()
	n := cs.length()
	var out = List[FTok]()
	var i = 0

	while i < n:
		c := cs[i]

		if is_sp(c):
			i += 1
		else if c == "(":
			out.append(FTok(kind: 1, text: "("))
			i += 1
		else if c == ")":
			out.append(FTok(kind: 2, text: ")"))
			i += 1
		else:
			var w = ""

			while i < n and not is_sp(cs[i]) and cs[i] != "(" and cs[i] != ")":
				if cs[i] == "\"":
					w += cs[i]
					i += 1

					var closed = false

					while i < n and not closed:
						if (
							cs[i] == "\\"
							and i + 1 < n
							and (
								cs[i + 1] == "\""
								or cs[i + 1] == "\\"
							)
						):
							w += cs[i]
							w += cs[i + 1]
							i += 2
						else if cs[i] == "\"":
							w += cs[i]
							closed = true
							i += 1
						else:
							w += cs[i]
							i += 1

					if not closed: return error("query: unterminated quote")
				else:
					w += cs[i]
					i += 1

			out.append(FTok(kind: 0, text: w.clone()))

	return ok(out)

fn known_field(f: String) Bool:
	return [
		"id", "created", "updated", "points", "title", "assignee", "reporter", "text",
		"state", "priority", "due", "label", "labels", "is", "has", "view"
	].contains(f)

fn op_ok(field: String, op: String) Bool:
	eqop := op == ":" or op == "!="
	ordered := op == "<" or op == "<=" or op == ">" or op == ">="
	if (
		field == "id"
		or field == "created"
		or field == "updated"
		or field == "points"
		or field == "priority"
		or field == "due"
	):
		return eqop or ordered
	if (
		field == "title"
		or field == "assignee"
		or field == "reporter"
		or field == "labels"
		or field == "label"
	):
		return eqop or op == "~"
	if field == "text": return op == "~"
	if field == "state": return eqop

	return op == ":"

fn check_values(app: App, field: String, op: String, alts: List[String]) String:
	eqop := op == ":" or op == "!="
	ordered := op == "<" or op == "<=" or op == ">" or op == ">="

	if ordered and alts.length() > 1:
		joined := alts.join("|")
		return "query: bad value '{joined}' for field '{field}'"

	for v in alts:
		var bad = false

		if field == "id" or field == "created" or field == "updated":
			bad = rule_int(v) < 0
		else if field == "points":
			if v == "none" and eqop:
				bad = false
			else:
				bad = rule_int(v) < 0
		else if field == "priority":
			bad = prio_rank(v) < 0
		else if field == "due":
			if v == "none" and eqop:
				bad = false
			else:
				bad = not valid_date(v)
		else if field == "state":
			bad = not app.wf.states.contains(v)
		else if field == "is":
			bad = not ["open", "final", "overdue", "unassigned"].contains(v)
		else if field == "has":
			bad = not ["assignee", "due", "points", "labels", "comments", "reporter"].contains(
				v
			)

		if bad: return "query: bad value '{v}' for field '{field}'"

	return ""

fn make_term(
	app: App,
	field: String,
	op: String,
	alts: List[String]
) Result[Node, String]:
	if not known_field(field): return error("query: unknown field '{field}'")
	if not op_ok(field, op):
		return error("query: bad operator '{op}' for field '{field}'")

	if field == "view":
		name := alts.join("|")
		if app.find_view(name) < 0: return error("query: unknown view '{name}'")

		var one = List[String]()
		one.append(name.clone())
		return ok(Node(kind: 0, kids: List[Node](), field: field, op: op, alts: one))

	msg := check_values(app, field, op, alts)
	if not msg.is_empty(): return error(msg)

	return ok(Node(kind: 0, kids: List[Node](), field: field, op: op, alts: alts))

fn parse_term(app: App, w: String) Result[Node, String]:
	cs := w.chars()
	n := cs.length()
	var i = 0
	while i < n and ((cs[i] >= "a" and cs[i] <= "z") or cs[i] == "_"):
		i += 1
	if i == 0: return error("query: unexpected token '{w}'")

	field := prefix(w, i)
	r := after(w, i)
	var op = ""

	if r.starts_with("!="):
		op = "!="
	else if r.starts_with("<="):
		op = "<="
	else if r.starts_with(">="):
		op = ">="
	else if r.starts_with(":"):
		op = ":"
	else if r.starts_with("<"):
		op = "<"
	else if r.starts_with(">"):
		op = ">"
	else if r.starts_with("~"):
		op = "~"

	if op.is_empty(): return error("query: unexpected token '{w}'")

	alts := parse_alts(after(r, op.length()))
	return make_term(app, field, op, alts)

fn is_word(ps: FParser, w: String) Bool:
	if ps.pos >= ps.toks.length(): return false
	return ps.toks[ps.pos].kind == 0 and ps.toks[ps.pos].text == w

fn starts_operand(ps: FParser) Bool:
	if ps.pos >= ps.toks.length(): return false

	t := ps.toks[ps.pos]
	if t.kind == 1: return true

	return t.kind == 0 and t.text != "AND" and t.text != "OR"

fn p_primary(app: App, var ps: FParser) Result[Node, String]:
	if ps.pos >= ps.toks.length(): return error("query: unexpected end of query")

	kind := ps.toks[ps.pos].kind
	text := ps.toks[ps.pos].text.clone()
	if kind == 2: return error("query: unexpected token ')'")

	if kind == 1:
		ps.pos += 1

		inner := try p_or(app, var ps)
		if ps.pos >= ps.toks.length(): return error("query: unexpected end of query")

		if ps.toks[ps.pos].kind != 2:
			bad := ps.toks[ps.pos].text.clone()
			return error("query: unexpected token '{bad}'")

		ps.pos += 1
		return ok(inner)

	ps.pos += 1
	if text == "AND" or text == "OR" or text == "NOT":
		return error("query: unexpected token '{text}'")

	return parse_term(app, text)

fn p_unary(app: App, var ps: FParser) Result[Node, String]:
	if ps.pos >= ps.toks.length(): return error("query: unexpected end of query")

	if is_word(ps, "NOT"):
		ps.pos += 1

		inner := try p_unary(app, var ps)
		var kids = List[Node]()
		kids.append(inner)
		return ok(Node(kind: 3, kids: kids, field: "", op: "", alts: List[String]()))

	return p_primary(app, var ps)

fn p_and(app: App, var ps: FParser) Result[Node, String]:
	first := try p_unary(app, var ps)
	var kids = List[Node]()
	kids.append(first)

	while true:
		if is_word(ps, "AND"):
			ps.pos += 1
		else if not starts_operand(ps):
			break

		nxt := try p_unary(app, var ps)
		kids.append(nxt)

	return ok(Node(kind: 1, kids: kids, field: "", op: "", alts: List[String]()))

fn p_or(app: App, var ps: FParser) Result[Node, String]:
	first := try p_and(app, var ps)
	var kids = List[Node]()
	kids.append(first)

	while is_word(ps, "OR"):
		ps.pos += 1

		nxt := try p_and(app, var ps)
		kids.append(nxt)

	return ok(Node(kind: 2, kids: kids, field: "", op: "", alts: List[String]()))

// Parses a plain filter (no sort/limit). Empty text matches everything.
fn parse_filter(app: App, text: String) Result[Node, String]:
	tr := tokenize_filter(text)
	if tr.is_error(): return error(tr.err())

	toks := tr.get()
	if toks.is_empty():
		return ok(
			Node(
				kind: 1, kids: List[Node](), field: "", op: "", alts: List[String]()
			)
		)

	var ps = FParser(toks: toks, pos: 0)
	node := try p_or(app, var ps)

	if ps.pos < ps.toks.length():
		bad := ps.toks[ps.pos].text.clone()
		return error("query: unexpected token '{bad}'")

	return ok(node)

// Splits a query into filter, sort clause and limit, textually (limit first, then
// sort).
fn split_query(raw: String) Result[QParts, String]:
	s := raw.trim()
	cs := s.chars()
	n := cs.length()
	var filt = s.clone()
	var has_limit = false
	var lim = ""
	var k = n - 1
	while k >= 0 and not is_sp(cs[k]):
		k -= 1

	if k >= 0:
		arg := after(s, k + 1)
		rest := prefix(s, k).trim_end()
		rc := rest.chars()
		var m = rc.length() - 1
		while m >= 0 and not is_sp(rc[m]):
			m -= 1

		if after(rest, m + 1) == "limit":
			has_limit = true
			lim = arg.clone()
			filt = prefix(rest, m + 1).trim_end()

	if has_limit and rule_int(lim) < 0: return error("bad limit '{lim}'")

	fc := filt.chars()
	fnn := fc.length()
	var i = 0
	var found = -1

	while i + 4 < fnn and found < 0:
		if (
			(i == 0 or is_sp(fc[i - 1]))
			and fc[i] == "s"
			and fc[i + 1] == "o"
			and fc[i + 2] == "r"
			and fc[i + 3] == "t"
			and is_sp(fc[i + 4])
		):
			found = i
		i += 1

	var fl = filt.clone()
	var has_sort = false
	var sort_text = ""

	if found >= 0:
		fl = prefix(filt, found).trim_end()
		sort_text = after(filt, found + 4).trim()
		has_sort = true

	return ok(
		QParts(
			filter: fl, has_sort: has_sort, sort: sort_text, has_limit: has_limit,
			limit: lim
		)
	)

fn sort_field_ok(f: String) Bool:
	return [
		"id", "created", "updated", "priority", "points", "state", "title", "assignee",
		"reporter", "due"
	].contains(f)

fn parse_sort(text: String) Result[List[SortKey], String]:
	var keys = List[SortKey]()

	for part in text.split(","):
		for piece in split_ws(part):
			var desc = false
			var name = piece.clone()

			if piece.starts_with("-"):
				desc = true
				name = after(piece, 1)

			if not sort_field_ok(name): return error("bad sort field '{name}'")

			keys.append(SortKey(field: name.clone(), desc: desc))

	return ok(keys)

// Full query compile: limit, then filter, then sort.
fn compile_query(app: App, raw: String) Result[Compiled, String]:
	parts := try split_query(raw)
	node := try parse_filter(app, parts.filter)
	keys := try parse_sort(parts.sort)
	var lim = -1
	if parts.has_limit:
		lim = rule_int(parts.limit)
	return ok(Compiled(node: node, keys: keys, limit: lim))

// ---------------------------------------------------------------- query evaluation

fn collect_views(n: Node, var out: List[String]) Unit:
	if n.kind == 0:
		if n.field == "view":
			out.append(n.alts[0].clone())
		return

	for k in n.kids:
		collect_views(k, var out)

fn view_filter(app: App, name: String) Node:
	vi := app.find_view(name)
	parts := split_query(app.views[vi].query.clone()).get()
	return parse_filter(app, parts.filter).get()

fn eq_match(app: App, idx: Int, f: String, v: String) Bool:
	it := app.issues[idx]
	if f == "id": return it.id == rule_int(v)
	if f == "created": return it.created == rule_int(v)
	if f == "updated": return it.updated == rule_int(v)

	if f == "points":
		if v == "none": return it.points < 0
		return it.points == rule_int(v)

	if f == "title": return it.title.lower() == v.lower()

	if f == "assignee":
		if v == "none": return it.assignee.is_empty()
		return not it.assignee.is_empty() and it.assignee.lower() == v.lower()

	if f == "reporter":
		if v == "none": return it.reporter.is_empty()
		return not it.reporter.is_empty() and it.reporter.lower() == v.lower()

	if f == "state": return it.state == v
	if f == "priority": return it.priority == prio_rank(v)

	if f == "due":
		if v == "none": return it.due.is_empty()
		return not it.due.is_empty() and it.due == v

	if f == "labels" or f == "label":
		if v == "none": return it.labels.is_empty()
		return it.labels.contains(v.lower())

	if f == "is":
		fin := app.is_final(it.state)
		if v == "open": return not fin
		if v == "final": return fin
		if v == "overdue": return (
			not fin
			and not it.due.is_empty()
			and it.due < app.today
		)
		if v == "unassigned": return it.assignee.is_empty()

		return false

	if f == "has":
		if v == "assignee": return not it.assignee.is_empty()
		if v == "due": return not it.due.is_empty()
		if v == "points": return it.points >= 0
		if v == "labels": return not it.labels.is_empty()
		if v == "comments": return not it.comments.is_empty()
		if v == "reporter": return not it.reporter.is_empty()

		return false

	return false

fn sub_match(app: App, idx: Int, f: String, v: String) Bool:
	it := app.issues[idx]
	lv := v.lower()
	if f == "title": return it.title.lower().contains(lv)
	if f == "assignee":
		return not it.assignee.is_empty() and it.assignee.lower().contains(lv)
	if f == "reporter":
		return not it.reporter.is_empty() and it.reporter.lower().contains(lv)

	if f == "text":
		if it.title.lower().contains(lv): return true

		for c in it.comments:
			if c.text.lower().contains(lv): return true
		return false

	if f == "labels" or f == "label":
		for l in it.labels:
			if l.contains(lv): return true
		return false

	return false

fn ord_match(app: App, idx: Int, f: String, op: String, v: String) Bool:
	it := app.issues[idx]
	var c = 0

	if f == "id":
		c = cmp_int(it.id, rule_int(v))
	else if f == "created":
		c = cmp_int(it.created, rule_int(v))
	else if f == "updated":
		c = cmp_int(it.updated, rule_int(v))
	else if f == "points":
		if it.points < 0: return false

		c = cmp_int(it.points, rule_int(v))
	else if f == "priority":
		c = cmp_int(it.priority, prio_rank(v))
	else if f == "due":
		if it.due.is_empty(): return false

		c = cmp_str(it.due, v)
	else:
		return false

	if op == "<": return c < 0
	if op == "<=": return c <= 0
	if op == ">": return c > 0

	return c >= 0

fn eval_term(app: App, n: Node, idx: Int) Bool:
	f := n.field.clone()
	if f == "view": return eval(app, view_filter(app, n.alts[0]), idx)

	op := n.op.clone()
	if op == "<" or op == "<=" or op == ">" or op == ">=":
		return ord_match(app, idx, f, op, n.alts[0])

	var pos = false

	for v in n.alts:
		if op == "~":
			if sub_match(app, idx, f, v):
				pos = true
		else:
			if eq_match(app, idx, f, v):
				pos = true

	if op == "!=": return not pos

	return pos

fn eval(app: App, n: Node, idx: Int) Bool:
	if n.kind == 1:
		for k in n.kids:
			if not eval(app, k, idx): return false
		return true

	if n.kind == 2:
		for k in n.kids:
			if eval(app, k, idx): return true
		return false

	if n.kind == 3: return not eval(app, n.kids[0], idx)

	return eval_term(app, n, idx)

fn matching(app: App, node: Node) List[Int]:
	var out = List[Int]()
	var i = 0

	while i < app.issues.length():
		if eval(app, node, i):
			out.append(i)
		i += 1

	return out

fn cmp_absent_int(x: Int, y: Int) Int:
	if x < 0 and y < 0: return 0
	if x < 0: return 1
	if y < 0: return -1

	return cmp_int(x, y)

fn cmp_absent_str(x: String, y: String) Int:
	if x.is_empty() and y.is_empty(): return 0
	if x.is_empty(): return 1
	if y.is_empty(): return -1

	return cmp_str(x.lower(), y.lower())

fn cmp_field(app: App, a: Issue, b: Issue, f: String) Int:
	if f == "id": return cmp_int(a.id, b.id)
	if f == "created": return cmp_int(a.created, b.created)
	if f == "updated": return cmp_int(a.updated, b.updated)
	if f == "priority": return cmp_int(a.priority, b.priority)
	if f == "points": return cmp_absent_int(a.points, b.points)
	if f == "state": return cmp_int(app.state_pos(a.state), app.state_pos(b.state))
	if f == "title": return cmp_str(a.title.lower(), b.title.lower())
	if f == "assignee": return cmp_absent_str(a.assignee, b.assignee)
	if f == "reporter": return cmp_absent_str(a.reporter, b.reporter)
	if f == "due": return cmp_absent_str(a.due, b.due)

	return 0

fn cmp_issue(app: App, a: Issue, b: Issue, keys: List[SortKey]) Int:
	for k in keys:
		c := cmp_field(app, a, b, k.field)

		if c != 0:
			if k.desc: return -c
			return c

	return 0

// Stable insertion sort of issue positions.
fn sort_indices(app: App, xs: List[Int], keys: List[SortKey]) List[Int]:
	var out = List[Int]()

	for idx in xs:
		var pos = out.length()
		while (
			pos > 0
			and cmp_issue(
				app, app.issues[idx], app.issues[out[pos - 1]], keys
			) < 0
		):
			pos -= 1
		out.insert(pos, idx)

	return out

fn issue_line(it: Issue) String:
	return "#{it.id} | {it.state} | {prio_name(it.priority)} | {dash(it.assignee)} | {pts_text(it.points)} | {dash(it.due)} | {labels_dash(it.labels)} | {it.title}"

fn reaches(app: App, from: String, target: String, depth: Int) Bool:
	if depth > 64: return false

	vi := app.find_view(from)
	if vi < 0: return false

	node := view_filter(app, from)
	var refs = List[String]()
	collect_views(node, var refs)

	for r in refs:
		if r == target: return true
		if reaches(app, r, target, depth + 1): return true

	return false

// ---------------------------------------------------------------- workflow parsing

fn add_state(var wf: WF, name: String) Unit:
	if not wf.states.contains(name):
		wf.states.append(name.clone())

fn wf_line(var wf: WF, l: String) String:
	if l.starts_with("initial:"):
		rest := after(l, 8).trim()
		if split_ws(rest).length() > 1: return "workflow: bad line '{l}'"
		if not valid_state(rest): return "workflow: bad state name '{rest}'"
		if wf.has_initial: return "workflow: initial state defined twice"

		wf.has_initial = true
		wf.initial = rest.clone()
		add_state(var wf, rest)
		return ""

	if l.starts_with("final:"):
		rest := after(l, 6)

		for part in rest.split(","):
			nm := part.trim()
			if not valid_state(nm): return "workflow: bad state name '{nm}'"

			add_state(var wf, nm)
			if not wf.finals.contains(nm):
				wf.finals.append(nm.clone())

		return ""

	arrow := l.index_of("->")
	if arrow.is_none(): return "workflow: bad line '{l}'"

	k := arrow.get(0)
	left := prefix(l, k).trim()
	right := after(l, k + 2)
	lw := split_ws(left)
	if lw.length() != 1: return "workflow: bad line '{l}'"
	if not valid_state(lw[0]): return "workflow: bad state name '{lw[0]}'"

	src := lw[0].clone()
	add_state(var wf, src)

	for ent in right.split(","):
		words := split_ws(ent)
		var dst = ""
		var guards = List[String]()

		if words.length() == 1:
			dst = words[0].clone()
		else if words.length() == 3 and words[1] == "requires":
			dst = words[0].clone()
			guards = words[2].split("+")
		else:
			return "workflow: bad line '{l}'"

		if not valid_state(dst): return "workflow: bad state name '{dst}'"

		for g in guards:
			if not is_guard(g): return "workflow: bad guard field '{g}'"
		add_state(var wf, dst)
		wf.edges.append(Edge(src: src.clone(), dst: dst.clone(), guards: guards))
		wf.ntrans += 1

	return ""

fn build_workflow(lines: List[String], start: Int, stop: Int) Result[WF, String]:
	var wf = empty_wf()
	var err = ""
	var j = start

	while j < stop:
		l := lines[j].trim()
		j += 1
		if l.is_empty() or l.starts_with("#"): continue

		e := wf_line(var wf, l)
		if err.is_empty() and not e.is_empty():
			err = e

	if not err.is_empty(): return error(err)
	if not wf.has_initial: return error("workflow: initial state missing")

	for e in wf.edges:
		if wf.finals.contains(e.src):
			return error("workflow: '{e.src}' is final and cannot have transitions")
	return ok(wf)

// ---------------------------------------------------------------- the tracker

impl App:
	fn find(id: Int) Int:
		var i = 0

		while i < self.issues.length():
			if self.issues[i].id == id: return i

			i += 1

		return -1

	fn resolve(arg: String) Int:
		id := parse_id(arg)

		if id == 0:
			print("error: bad issue id '{arg}'")
			return -1

		idx := self.find(id)
		if idx < 0:
			print("error: no such issue #{id}")
		return idx

	fn state_pos(name: String) Int:
		var i = 0

		while i < self.wf.states.length():
			if self.wf.states[i] == name: return i

			i += 1

		return -1

	fn is_final(name: String) Bool:
		return self.wf.finals.contains(name)

	fn find_view(name: String) Int:
		var i = 0

		while i < self.views.length():
			if self.views[i].name == name: return i

			i += 1

		return -1

	fn unmet(idx: Int, g: String) Bool:
		it := self.issues[idx]
		if g == "assignee": return it.assignee.is_empty()
		if g == "points": return it.points < 0
		if g == "due": return it.due.is_empty()
		if g == "labels": return it.labels.is_empty()
		if g == "reporter": return it.reporter.is_empty()

		return false

	var fn log_add(id: Int, detail: String) Unit:
		self.logs.append(
			LogEntry(
				t: self.clock, actor: self.actor.clone(), id: id, detail: detail.clone()
			)
		)

	// Applies an update; logs and bumps the clock only when something changes.
	var fn apply_upd(idx: Int, up: Upd) Bool:
		cur := self.issues[idx].clone()
		var details = List[String]()
		var nt = cur.title.clone()
		var np = cur.priority
		var na = cur.assignee.clone()
		var npts = cur.points
		var nd = cur.due.clone()
		var nl = cur.labels.clone()
		var nr = cur.reporter.clone()

		if up.has_title and up.title != cur.title:
			details.append("title: {cur.title} -> {up.title}")
			nt = up.title.clone()

		if up.has_priority and up.priority != cur.priority:
			details.append(
				"priority: {prio_name(cur.priority)} -> {prio_name(up.priority)}"
			)
			np = up.priority

		if up.has_assignee and up.assignee != cur.assignee:
			details.append("assignee: {dash(cur.assignee)} -> {dash(up.assignee)}")
			na = up.assignee.clone()

		if up.has_points and up.points != cur.points:
			details.append("points: {pts_text(cur.points)} -> {pts_text(up.points)}")
			npts = up.points

		if up.has_due and up.due != cur.due:
			details.append("due: {dash(cur.due)} -> {dash(up.due)}")
			nd = up.due.clone()

		if up.has_labels and labels_text(up.labels) != labels_text(cur.labels):
			details.append(
				"labels: {labels_dash(cur.labels)} -> {labels_dash(up.labels)}"
			)
			nl = up.labels.clone()

		if up.has_reporter and up.reporter != cur.reporter:
			details.append("reporter: {dash(cur.reporter)} -> {dash(up.reporter)}")
			nr = up.reporter.clone()

		if details.is_empty(): return false

		self.clock += 1

		t := self.clock
		id := self.issues[idx].id
		self.issues[idx].title = nt
		self.issues[idx].priority = np
		self.issues[idx].assignee = na
		self.issues[idx].points = npts
		self.issues[idx].due = nd
		self.issues[idx].labels = nl
		self.issues[idx].reporter = nr
		self.issues[idx].updated = t
		for d in details:
			self.log_add(id, d.clone())
		return true

	var fn do_edit(idx: Int, toks: List[String], bulk: Bool) Bool:
		id := self.issues[idx].id

		if self.is_final(self.issues[idx].state):
			report(bulk, id, "#{id} is in final state '{self.issues[idx].state}'")
			return false

		if toks.is_empty():
			report(bulk, id, "usage: edit ID field=value...")
			return false

		var up = empty_upd()

		for tok in toks:
			e := token_upd(var up, tok)

			if not e.is_empty():
				report(bulk, id, e)
				return false

		if self.apply_upd(idx, up):
			print("updated #{id}")
		else:
			print("#{id} unchanged")

		return true

	var fn do_label(idx: Int, ops: List[String], bulk: Bool) Bool:
		id := self.issues[idx].id

		for op in ops:
			neg := op.starts_with("-")
			var name = op.clone()
			if op.starts_with("+") or neg:
				name = after(op, 1)

			l := name.lower()

			if not valid_label(l):
				report(bulk, id, "bad label '{l}'")
				return false

		if self.is_final(self.issues[idx].state):
			report(bulk, id, "#{id} is in final state '{self.issues[idx].state}'")
			return false

		// Operations apply left to right.
		var nl = self.issues[idx].labels.clone()

		for op in ops:
			neg := op.starts_with("-")
			var name = op.clone()
			if op.starts_with("+") or neg:
				name = after(op, 1)

			l := name.lower()

			if neg:
				remove_label(var nl, l)
			else:
				add_label(var nl, l)

		var up = empty_upd()
		up.has_labels = true
		up.labels = nl

		if self.apply_upd(idx, up):
			print("updated #{id}")
		else:
			print("#{id} unchanged")

		return true

	var fn do_move(idx: Int, target: String, comment: String, bulk: Bool) Bool:
		id := self.issues[idx].id
		cur := self.issues[idx].state.clone()

		if self.is_final(cur):
			report(bulk, id, "#{id} is in final state '{cur}'")
			return false

		if self.state_pos(target) < 0:
			report(bulk, id, "unknown state '{target}'")
			return false

		if cur == target:
			report(bulk, id, "already in state '{cur}'")
			return false

		var ei = -1
		var j = 0

		while j < self.wf.edges.length():
			if (
				ei < 0
				and self.wf.edges[j].src == cur
				and self.wf.edges[j].dst == target
			):
				ei = j
			j += 1

		if ei < 0:
			report(bulk, id, "transition '{cur} -> {target}' not allowed")
			return false

		var missing = List[String]()
		for g in self.wf.edges[ei].guards:
			if self.unmet(idx, g):
				missing.append(g.clone())

		if not missing.is_empty():
			mtxt := missing.join(", ")
			report(bulk, id, "cannot move #{id} to {target}: missing {mtxt}")
			return false

		self.clock += 1

		t := self.clock
		self.issues[idx].state = target.clone()
		self.issues[idx].updated = t
		self.log_add(id, "state: {cur} -> {target}")

		if not comment.is_empty():
			self.issues[idx].comments.append(
				Comment(
					t: t, actor: self.actor.clone(), text: comment.clone()
				)
			)
			self.log_add(id, "comment: {comment}")

		print("moved #{id}: {cur} -> {target}")
		return true

	// ------------------------------------------------ commands

	var fn cmd_workflow(lines: List[String], start: Int) Int:
		var j = start
		while j < lines.length() and lines[j].trim() != "end":
			j += 1

		stop := j
		next := if j < lines.length(): j + 1 else: j

		if self.next_id > 1:
			print("error: workflow: cannot redefine after issues were created")
			return next

		res := build_workflow(lines, start, stop)

		if res.is_error():
			print("error: {res.err()}")
			return next

		wf := res.get()
		ns := wf.states.length()
		nt := wf.ntrans
		self.wf = wf
		print("workflow ok: {ns} states, {nt} transitions")
		return next

	var fn cmd_actor(args: List[String]) Unit:
		if args.length() != 2:
			print("error: usage: actor NAME")
			return

		self.actor = args[1].clone()
		print("actor is {self.actor}")

	var fn cmd_today(args: List[String]) Unit:
		if args.length() != 2:
			print("error: usage: today DATE")
			return

		if not valid_date(args[1]):
			print("error: bad date '{args[1]}'")
			return

		self.today = args[1].clone()
		print("today is {self.today}")

	var fn cmd_create(line: String) Unit:
		if not self.wf.has_initial:
			print("error: no workflow defined")
			return

		tr := tokenize(rest_after(line, 1))

		if tr.is_error():
			print("error: {tr.err()}")
			return

		toks := tr.get()

		if toks.is_empty():
			print("error: usage: create TITLE [field=value...]")
			return

		title := toks[0].clone()

		if title.trim().is_empty():
			print("error: empty title")
			return

		var up = empty_upd()
		var k = 1

		while k < toks.length():
			e := token_upd(var up, toks[k])

			if not e.is_empty():
				print("error: {e}")
				return

			k += 1

		self.clock += 1

		t := self.clock
		id := self.next_id
		self.next_id += 1

		var it = Issue(
			id: id, title: title.clone(), state: self.wf.initial.clone(), priority: 1,
			assignee: "", reporter: self.actor.clone(), points: -1, due: "",
			labels: List[String](), comments: List[Comment](), created: t, updated: t
		)
		var details = List[String]()
		details.append("created \"{title}\"")

		if up.has_title:
			if up.title != title:
				details.append("title: {title} -> {up.title}")
			it.title = up.title.clone()

		if up.has_priority:
			if up.priority != 1:
				details.append("priority: medium -> {prio_name(up.priority)}")
			it.priority = up.priority

		if up.has_assignee:
			if not up.assignee.is_empty():
				details.append("assignee: - -> {up.assignee}")
			it.assignee = up.assignee.clone()

		if up.has_points:
			if up.points >= 0:
				details.append("points: - -> {up.points}")
			it.points = up.points

		if up.has_due:
			if not up.due.is_empty():
				details.append("due: - -> {up.due}")
			it.due = up.due.clone()

		if up.has_labels:
			if not up.labels.is_empty():
				details.append("labels: - -> {labels_text(up.labels)}")
			it.labels = up.labels.clone()

		if up.has_reporter:
			if not up.reporter.is_empty():
				details.append("reporter: - -> {up.reporter}")
			it.reporter = up.reporter.clone()

		self.issues.append(it)
		for d in details:
			self.log_add(id, d.clone())
		print("created #{id}")

	var fn cmd_edit(line: String) Unit:
		tr := tokenize(rest_after(line, 1))

		if tr.is_error():
			print("error: {tr.err()}")
			return

		toks := tr.get()

		if toks.is_empty():
			print("error: usage: edit ID field=value...")
			return

		idx := self.resolve(toks[0])
		if idx < 0: return

		_ok := self.do_edit(idx, tail(toks, 1), false)

	var fn cmd_assign(line: String) Unit:
		tr := tokenize(rest_after(line, 1))

		if tr.is_error():
			print("error: {tr.err()}")
			return

		toks := tr.get()

		if toks.length() != 2:
			print("error: usage: assign ID NAME")
			return

		idx := self.resolve(toks[0])
		if idx < 0: return

		tok := "assignee={toks[1]}"
		var one = List[String]()
		one.append(tok)

		_ok := self.do_edit(idx, one, false)

	var fn cmd_label(line: String) Unit:
		tr := tokenize(rest_after(line, 1))

		if tr.is_error():
			print("error: {tr.err()}")
			return

		toks := tr.get()

		if toks.length() < 2:
			print("error: usage: label ID +label -label...")
			return

		idx := self.resolve(toks[0])
		if idx < 0: return

		_ok := self.do_label(idx, tail(toks, 1), false)

	var fn cmd_move(line: String, args: List[String]) Unit:
		if args.length() < 3:
			print("error: usage: move ID STATE [comment...]")
			return

		idx := self.resolve(args[1])
		if idx < 0: return

		comment := rest_after(line, 3)
		_ok := self.do_move(idx, args[2].clone(), comment, false)

	var fn cmd_comment(line: String, args: List[String]) Unit:
		if args.length() < 3:
			print("error: usage: comment ID TEXT")
			return

		idx := self.resolve(args[1])
		if idx < 0: return

		text := rest_after(line, 2)
		self.clock += 1

		t := self.clock
		id := self.issues[idx].id
		self.issues[idx].comments.append(
			Comment(t: t, actor: self.actor.clone(), text: text.clone())
		)
		self.issues[idx].updated = t
		self.log_add(id, "comment: {text}")
		print("commented #{id}")

	var fn cmd_delete(args: List[String]) Unit:
		if args.length() != 2:
			print("error: usage: delete ID")
			return

		idx := self.resolve(args[1])
		if idx < 0: return

		id := self.issues[idx].id
		self.clock += 1
		self.log_add(id, "deleted")
		self.issues.remove(idx)
		print("deleted #{id}")

	fn cmd_show(args: List[String]) Unit:
		if args.length() != 2:
			print("error: usage: show ID")
			return

		idx := self.resolve(args[1])
		if idx < 0: return

		it := self.issues[idx]
		print("#{it.id} {it.title}")
		print("  state: {it.state}")
		print("  priority: {prio_name(it.priority)}")
		print("  assignee: {dash(it.assignee)}")
		print("  points: {pts_text(it.points)}")
		print("  due: {dash(it.due)}")
		print("  labels: {labels_sp(it.labels)}")
		print("  reporter: {dash(it.reporter)}")
		print("  created: t={it.created}, updated: t={it.updated}")
		print("  comments: {it.comments.length()}")
		for c in it.comments:
			print("    [t={c.t} {c.actor}] {c.text}")

	fn run_compiled(c: Compiled) Unit:
		m := matching(self, c.node)
		order := sort_indices(self, m, c.keys)
		var n = order.length()
		if c.limit >= 0 and c.limit < n:
			n = c.limit
		for k in 0..n:
			print(issue_line(self.issues[order[k]]))

		if n == 1:
			print("(1 issue)")
		else:
			print("({n} issues)")

	fn cmd_list(line: String) Unit:
		cr := compile_query(self, rest_after(line, 1))

		if cr.is_error():
			print("error: {cr.err()}")
			return

		self.run_compiled(cr.get())

	fn sorted_view_names() List[String]:
		var names = List[String]()
		for v in self.views:
			names.append(v.name.clone())
		names.sort()
		return names

	var fn cmd_view(line: String, args: List[String]) Unit:
		if args.length() < 2:
			print("error: usage: view save|run|list|show|delete")
			return

		sub := args[1].clone()

		if sub == "save":
			if args.length() < 3:
				print("error: usage: view save NAME QUERY")
				return

			name := args[2].clone()

			if not valid_name(name, true):
				print("error: bad view name '{name}'")
				return

			q := rest_after(line, 3).trim()
			cr := compile_query(self, q)

			if cr.is_error():
				print("error: {cr.err()}")
				return

			node := cr.get().node
			var refs = List[String]()
			collect_views(node, var refs)

			for r in refs:
				if r == name or reaches(self, r, name, 0):
					print("error: view '{name}' would reference itself")
					return

			vi := self.find_view(name)

			if vi >= 0:
				self.views[vi].query = q.clone()
			else:
				self.views.append(View(name: name.clone(), query: q.clone()))

			print("saved view {name}")
			return

		if sub == "run":
			if args.length() < 3:
				print("error: usage: view run NAME [sort FIELDS] [limit N]")
				return

			name := args[2].clone()
			vi := self.find_view(name)

			if vi < 0:
				print("error: unknown view '{name}'")
				return

			pr := split_query(rest_after(line, 3))

			if pr.is_error():
				print("error: {pr.err()}")
				return

			parts := pr.get()

			if not parts.filter.is_empty():
				print("error: unexpected '{parts.filter}'")
				return

			cr := compile_query(self, self.views[vi].query.clone())

			if cr.is_error():
				print("error: {cr.err()}")
				return

			var comp = cr.get()

			if parts.has_sort:
				kr := parse_sort(parts.sort)

				if kr.is_error():
					print("error: {kr.err()}")
					return

				comp.keys = kr.get()

			if parts.has_limit:
				comp.limit = rule_int(parts.limit)
			self.run_compiled(comp)
			return

		if sub == "list":
			names := self.sorted_view_names()
			if names.is_empty():
				print("(no views)")

			for nm in names:
				vi := self.find_view(nm)
				print("{nm}: {self.views[vi].query}")

			return

		if sub == "show":
			if args.length() != 3:
				print("error: usage: view show NAME")
				return

			vi := self.find_view(args[2])

			if vi < 0:
				print("error: unknown view '{args[2]}'")
				return

			print("{args[2]}: {self.views[vi].query}")
			return

		if sub == "delete":
			if args.length() != 3:
				print("error: usage: view delete NAME")
				return

			name := args[2].clone()
			vi := self.find_view(name)

			if vi < 0:
				print("error: unknown view '{name}'")
				return

			for other in self.sorted_view_names():
				if other != name and reaches(self, other, name, 0):
					print("error: view '{name}' is used by '{other}'")
					return

			self.views.remove(vi)
			print("deleted view {name}")
			return

		print("error: usage: view save|run|list|show|delete")

	var fn cmd_bulk(line: String) Unit:
		sp := split_where(rest_after(line, 1))

		if not sp.found or sp.before.is_empty():
			print("error: usage: bulk ACTION... where QUERY")
			return

		tr := tokenize(sp.before)

		if tr.is_error():
			print("error: {tr.err()}")
			return

		toks := tr.get()

		if toks.is_empty():
			print("error: usage: bulk ACTION... where QUERY")
			return

		act := toks[0].clone()
		var kind = 0

		if act == "move":
			if toks.length() != 2:
				print("error: usage: bulk move STATE where QUERY")
				return

			kind = 1
		else if act == "assign":
			if toks.length() != 2:
				print("error: usage: bulk assign NAME where QUERY")
				return

			kind = 2
		else if act == "label":
			if toks.length() < 2:
				print("error: usage: bulk label +label... where QUERY")
				return

			kind = 3
		else if act == "set":
			if toks.length() < 2:
				print("error: usage: bulk set field=value... where QUERY")
				return

			kind = 4
		else:
			print("error: unknown bulk action '{act}'")
			return

		nr := parse_filter(self, sp.query)

		if nr.is_error():
			print("error: {nr.err()}")
			return

		m := matching(self, nr.get())
		var good_n = 0
		var bad_n = 0

		for idx in m:
			var good = false

			if kind == 1:
				good = self.do_move(idx, toks[1].clone(), "", true)
			else if kind == 2:
				tok := "assignee={toks[1]}"
				var one = List[String]()
				one.append(tok)
				good = self.do_edit(idx, one, true)
			else if kind == 3:
				good = self.do_label(idx, tail(toks, 1), true)
			else:
				good = self.do_edit(idx, tail(toks, 1), true)

			if good:
				good_n += 1
			else:
				bad_n += 1

		print("bulk: {good_n} ok, {bad_n} failed")

	var fn cmd_log(args: List[String]) Unit:
		n := args.length()
		var k = 1
		var idf = 0
		var has_tail = false
		var tailn = 0

		if n > 1 and args[1] != "tail":
			id := parse_id(args[1])

			if id == 0:
				print("error: bad issue id '{args[1]}'")
				return

			if id >= self.next_id:
				print("error: no such issue #{id}")
				return

			idf = id
			k = 2

		if k < n:
			if args[k] != "tail" or n != k + 2:
				print("error: usage: log [ID] [tail N]")
				return

			tailn = rule_int(args[k + 1])

			if tailn < 0:
				print("error: bad tail '{args[k + 1]}'")
				return

			has_tail = true

		var sel = List[Int]()
		var i = 0

		while i < self.logs.length():
			if idf == 0 or self.logs[i].id == idf:
				sel.append(i)
			i += 1

		start := if has_tail and tailn < sel.length(): sel.length() - tailn else: 0
		var printed = 0
		var j = start

		while j < sel.length():
			e := self.logs[sel[j]]
			print("t={e.t} {e.actor} #{e.id} {e.detail}")
			printed += 1
			j += 1

		if printed == 0:
			print("(no log entries)")

	var fn cmd_report(line: String, args: List[String]) Unit:
		usage := "error: usage: report summary|workload|labels|timeline"

		if args.length() < 2:
			print(usage)
			return

		sub := args[1].clone()

		if sub == "summary":
			self.report_summary()
		else if sub == "workload":
			self.report_workload()
		else if sub == "labels":
			nr := parse_filter(self, rest_after(line, 2))

			if nr.is_error():
				print("error: {nr.err()}")
				return

			self.report_labels(nr.get())
		else if sub == "timeline":
			if args.length() != 3:
				print("error: usage: report timeline ID")
				return

			idx := self.resolve(args[2])
			if idx < 0: return

			self.report_timeline(idx)
		else:
			print(usage)

	fn report_summary() Unit:
		var total = self.issues.length()
		var nopen = 0
		var nfin = 0
		var unassigned = 0
		var overdue = 0
		var openpts = 0

		for it in self.issues:
			if self.is_final(it.state):
				nfin += 1
			else:
				nopen += 1
				if it.assignee.is_empty():
					unassigned += 1
				if not it.due.is_empty() and it.due < self.today:
					overdue += 1
				if it.points > 0:
					openpts += it.points

		print("issues: {total} (open {nopen}, final {nfin})")
		print("by state:")

		for s in self.wf.states:
			var c = 0
			for it in self.issues:
				if it.state == s:
					c += 1
			print("  {s}: {c}")

		print("by priority:")

		for r in [3, 2, 1, 0]:
			var c = 0
			for it in self.issues:
				if it.priority == r:
					c += 1
			print("  {prio_name(r)}: {c}")

		print("unassigned: {unassigned}")
		print("overdue: {overdue}")
		print("open points: {openpts}")

	fn report_workload() Unit:
		var groups = List[WG]()
		var un_n = 0
		var un_pts = 0
		var any_open = false

		for it in self.issues:
			if self.is_final(it.state): continue

			any_open = true

			p := if it.points > 0: it.points else: 0

			if it.assignee.is_empty():
				un_n += 1
				un_pts += p
			else:
				key := it.assignee.lower()
				var g = -1
				var gi = 0

				while gi < groups.length():
					if groups[gi].key == key:
						g = gi
					gi += 1

				if g < 0:
					groups.append(
						WG(
							key: key.clone(), name: it.assignee.clone(), count: 0,
							points: 0
						)
					)
					g = groups.length() - 1

				groups[g].count += 1
				groups[g].points += p

		if not any_open:
			print("(no open issues)")
			return

		var order = List[Int]()
		var gi = 0

		while gi < groups.length():
			var pos = order.length()
			while pos > 0 and wg_cmp(groups[gi], groups[order[pos - 1]]) < 0:
				pos -= 1
			order.insert(pos, gi)
			gi += 1

		for oi in order:
			g := groups[oi]
			word := if g.count == 1: "issue" else: "issues"
			print("{g.name}: {g.count} {word}, {g.points} points")

		if un_n > 0:
			uw := if un_n == 1: "issue" else: "issues"
			print("unassigned: {un_n} {uw}, {un_pts} points")

	fn report_labels(node: Node) Unit:
		m := matching(self, node)
		var lcs = List[LC]()

		for idx in m:
			for l in self.issues[idx].labels:
				var p = -1
				var li = 0

				while li < lcs.length():
					if lcs[li].name == l:
						p = li
					li += 1

				if p < 0:
					lcs.append(LC(name: l.clone(), count: 1))
				else:
					lcs[p].count += 1

		if lcs.is_empty():
			print("(no labels)")
			return

		var order = List[Int]()
		var gi = 0

		while gi < lcs.length():
			var pos = order.length()
			while pos > 0 and lc_cmp(lcs[gi], lcs[order[pos - 1]]) < 0:
				pos -= 1
			order.insert(pos, gi)
			gi += 1

		for oi in order:
			print("{lcs[oi].name}: {lcs[oi].count}")

	fn report_timeline(idx: Int) Unit:
		it := self.issues[idx]
		var cur = self.wf.initial.clone()
		var from = it.created

		for e in self.logs:
			if e.id == it.id and e.detail.starts_with("state: "):
				ws := split_ws(after(e.detail, 7))
				print("{cur}: t={from}..{e.t} ({e.t - from})")
				cur = ws[2].clone()
				from = e.t

		print("{cur}: t={from}..{self.clock} ({self.clock - from})")

	var fn exec(line: String, lines: List[String], next: Int) Int:
		args := split_ws(line)
		cmd := args[0].clone()
		if cmd == "workflow": return self.cmd_workflow(lines, next)

		if cmd == "actor":
			self.cmd_actor(args)
		else if cmd == "today":
			self.cmd_today(args)
		else if cmd == "create":
			self.cmd_create(line)
		else if cmd == "edit":
			self.cmd_edit(line)
		else if cmd == "label":
			self.cmd_label(line)
		else if cmd == "assign":
			self.cmd_assign(line)
		else if cmd == "move":
			self.cmd_move(line, args)
		else if cmd == "comment":
			self.cmd_comment(line, args)
		else if cmd == "delete":
			self.cmd_delete(args)
		else if cmd == "show":
			self.cmd_show(args)
		else if cmd == "list":
			self.cmd_list(line)
		else if cmd == "view":
			self.cmd_view(line, args)
		else if cmd == "bulk":
			self.cmd_bulk(line)
		else if cmd == "log":
			self.cmd_log(args)
		else if cmd == "report":
			self.cmd_report(line, args)
		else:
			print("error: unknown command '{cmd}'")

		return next

// ---------------------------------------------------------------- report comparators

fn wg_cmp(a: WG, b: WG) Int:
	if a.points != b.points: return cmp_int(b.points, a.points)
	if a.count != b.count: return cmp_int(b.count, a.count)

	return cmp_str(a.key, b.key)

fn lc_cmp(a: LC, b: LC) Int:
	if a.count != b.count: return cmp_int(b.count, a.count)
	return cmp_str(a.name, b.name)

// ---------------------------------------------------------------- bulk helpers

fn split_where(text: String) WS:
	cs := text.chars()
	n := cs.length()
	var i = 0

	while i + 5 <= n:
		atstart := i == 0 or is_sp(cs[i - 1])
		if (
			atstart
			and cs[i] == "w"
			and cs[i + 1] == "h"
			and cs[i + 2] == "e"
			and cs[i + 3] == "r"
			and cs[i + 4] == "e"
			and (i + 5 == n or is_sp(cs[i + 5]))
		):
			return WS(
				found: true, before: prefix(text, i).trim(),
				query: after(text, i + 5).trim()
			)

		i += 1

	return WS(found: false, before: "", query: "")

// ---------------------------------------------------------------- entry point

export fn main() Int:
	data := read_all(stdin()).get()
	text := data.decode_utf8().get("")
	lines := text.split("\n")
	var app = App(
		actor: "system", today: "1970-01-01", clock: 0, next_id: 1, wf: empty_wf(),
		issues: List[Issue](), logs: List[LogEntry](), views: List[View]()
	)
	var i = 0

	while i < lines.length():
		line := lines[i].trim_end()
		i += 1

		st := line.trim_start()
		if st.is_empty() or st.starts_with("#"): continue

		print("> {line}")
		i = app.exec(line, lines, i)

	return 0
