import (
	stdin from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

// ---------------------------------------------------------------- constants

LABEL_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_-"
PRIORITIES := ["low", "medium", "high", "critical"]
EDIT_FIELDS := ["title", "priority", "assignee", "points", "due", "labels", "reporter"]
GUARD_FIELDS := ["assignee", "points", "due", "labels", "reporter"]
QUERY_FIELDS := [
	"id", "created", "updated", "points", "title", "assignee", "reporter", "text",
	"state", "priority", "due", "label", "labels", "is", "has", "view"
]
SORT_FIELDS := [
	"id", "created", "updated", "priority", "points", "state", "title", "assignee",
	"reporter", "due"
]
IS_VALUES := ["open", "final", "overdue", "unassigned"]
HAS_VALUES := ["assignee", "due", "points", "labels", "comments", "reporter"]

// ---------------------------------------------------------------- types

type Comment:
	t: Int
	actor: String
	text: String

type Issue:
	id: Int
	title: String
	state: String
	priority: String
	assignee: String?
	reporter: String?
	points: Int?
	due: String?
	labels: List[String]
	comments: List[Comment]
	created: Int
	updated: Int

type LogEntry:
	t: Int
	actor: String
	id: Int
	detail: String

type Transition:
	src: String
	dst: String
	guards: List[String]

type Tracker:
	clock: Int
	actor: String
	today: String
	next_id: Int
	ever_created: Bool
	initial: String
	states: List[String]
	finals: List[String]
	transitions: List[Transition]
	issues: List[Issue]
	log: List[LogEntry]
	views: Map[String, String]

type Wf:
	states: List[String]
	initial: String
	finals: List[String]
	transitions: List[Transition]
	err: String

type StrList:
	items: List[String]
	err: String

type Asg:
	field: String
	value: String
	err: String

type SF:
	first: String
	rest: String

type Found:
	idx: Int
	err: String

type QTok:
	kind: String
	text: String
	field: String
	op: String
	value: String
	quoted: Bool

type QTokRes:
	toks: List[QTok]
	err: String

type QP:
	toks: List[QTok]
	pos: Int

type Expr:
	kind: String
	kids: List[Expr]
	field: String
	op: String
	values: List[String]
	name: String

type PE:
	e: Expr
	err: String

type QParts:
	filter: String
	has_sort: Bool
	sort_text: String
	limit: Int
	err: String

type SortKey:
	field: String
	desc: Bool

type SortRes:
	keys: List[SortKey]
	err: String

type EvalCtx:
	today: String
	finals: List[String]
	states: List[String]

type WL:
	name: String
	key: String
	count: Int
	pts: Int

type Where:
	action: String
	query: String
	has: Bool

impl Tracker:
	var fn log_add(id: Int, detail: String) Unit:
		self.log.append(
			LogEntry(
				t: self.clock, actor: self.actor.clone(), id: id, detail: detail
			)
		)

// ---------------------------------------------------------------- basics

fn is_space(c: String) Bool:
	return c == " " or c == "\t" or c == "\r"

fn is_digit(c: String) Bool:
	return c.length() == 1 and "0123456789".contains(c)

fn is_lower(c: String) Bool:
	return c.length() == 1 and "abcdefghijklmnopqrstuvwxyz".contains(c)

fn sub(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a

	while i < b:
		out += cs[i]
		i += 1

	return out

fn digit_val(c: String) Int:
	return c.parse_int().get(0)

// -1 when empty or not all digits; saturates at 10^12
fn digits_value(s: String) Int:
	if s.is_empty(): return -1

	var v = 0

	for c in s.chars():
		if not is_digit(c): return -1

		if v < 1000000000000:
			v = v * 10 + digit_val(c)

	return v

// canonical integer rule: digits, no leading zeros, at most 1000000; -1 when invalid
fn canon_int(s: String) Int:
	if s.is_empty(): return -1
	if s.length() > 1 and s.starts_with("0"): return -1

	v := digits_value(s)
	if v < 0 or v > 1000000: return -1

	return v

// issue id argument: optional '#', digits, leading zeros allowed, at least 1; -1 when
// bad
fn id_value(s: String) Int:
	var body = s.clone()
	if s.starts_with("#"):
		body = sub(s.chars(), 1, s.length())

	v := digits_value(body)
	if v < 1: return -1

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
	if cs[4] != "-" or cs[7] != "-": return false

	y := digits_value(sub(cs, 0, 4))
	m := digits_value(sub(cs, 5, 7))
	d := digits_value(sub(cs, 8, 10))
	if y < 1 or m < 1 or m > 12 or d < 1: return false

	return d <= days_in(y, m)

fn rank(p: String) Int:
	if p == "low": return 0
	if p == "medium": return 1
	if p == "high": return 2

	return 3

fn label_ok(l: String) Bool:
	if l.is_empty(): return false

	for c in l.chars():
		if not LABEL_CHARS.contains(c): return false
	return true

fn valid_state(n: String) Bool:
	cs := n.chars()
	if cs.is_empty(): return false

	var i = 0

	for c in cs:
		if i == 0:
			if not is_lower(c): return false
		else:
			if not (is_lower(c) or is_digit(c) or c == "_"):
				return false

		i += 1

	return true

fn valid_view_name(n: String) Bool:
	cs := n.chars()
	if cs.is_empty(): return false

	var i = 0

	for c in cs:
		if i == 0:
			if not is_lower(c): return false
		else:
			if not (is_lower(c) or is_digit(c) or c == "_" or c == "-"):
				return false

		i += 1

	return true

fn find_str(xs: List[String], s: String) Int:
	var i = 0

	for x in xs:
		if x == s: return i

		i += 1

	return -1

fn join_with(xs: List[String], sep: String) String:
	var out = ""
	var first = true

	for x in xs:
		if first:
			first = false
		else:
			out += sep

		out += x

	return out

fn split_csv(v: String) List[String]:
	if v == "": return List[String]()
	return v.split(",")

fn norm_labels(raw: List[String]) StrList:
	var out = List[String]()

	for r in raw:
		l := r.lower()
		if not label_ok(l):
			return StrList(items: List[String](), err: "bad label '{l}'")

		if find_str(out, l) < 0:
			out.append(l)

	out.sort()
	return StrList(items: out, err: "")

// first word of s (leading whitespace skipped) and the text after it (leading
// whitespace skipped)
fn split_first(s: String) SF:
	cs := s.chars()
	n := cs.length()
	var i = 0
	while i < n and is_space(cs[i]):
		i += 1

	var j = i
	while j < n and not is_space(cs[j]):
		j += 1

	var k = j
	while k < n and is_space(cs[k]):
		k += 1
	return SF(first: sub(cs, i, j), rest: sub(cs, k, n))

// ---------------------------------------------------------------- tokens

// token rules: whitespace separates; a double quote starts a quoted section inside a
// token
fn tokenize(s: String) StrList:
	cs := s.chars()
	n := cs.length()
	var items = List[String]()
	var cur = ""
	var in_tok = false
	var in_q = false
	var i = 0

	while i < n:
		c := cs[i]

		if in_q:
			if c == "\"":
				in_q = false
			else if (
				c == "\\"
				and i + 1 < n
				and (cs[i + 1] == "\"" or cs[i + 1] == "\\")
			):
				cur += cs[i + 1]
				i += 1
			else:
				cur += c
		else if is_space(c):
			if in_tok:
				items.append(cur)
				cur = ""
				in_tok = false
		else if c == "\"":
			in_q = true
			in_tok = true
		else:
			cur += c
			in_tok = true

		i += 1

	if in_q: return StrList(items: List[String](), err: "unterminated quote")

	if in_tok:
		items.append(cur)
	return StrList(items: items, err: "")

fn parse_asg(tok: String) Asg:
	parts := tok.split("=", 2)
	if parts.length() < 2 or parts[0] == "":
		return Asg(field: "", value: "", err: "expected field=value, got '{tok}'")

	return Asg(field: parts[0].clone(), value: parts[1].clone(), err: "")

// "" when valid, else the error message
fn check_assign(field: String, value: String) String:
	if field == "state": return "use move to change state"
	if find_str(EDIT_FIELDS, field) < 0: return "unknown field '{field}'"

	if field == "title":
		if value.trim() == "": return "empty title"
	else if field == "priority":
		if find_str(PRIORITIES, value) < 0: return "bad priority '{value}'"
	else if field == "points":
		if value != "none" and canon_int(value) < 0: return "bad points '{value}'"
	else if field == "due":
		if value != "none" and not valid_date(value): return "bad date '{value}'"
	else if field == "labels":
		if value != "none":
			r := norm_labels(split_csv(value))
			if r.err != "": return r.err.clone()
	else if field == "assignee":
		if value != "none" and value.trim() == "": return "empty assignee"
	else if field == "reporter":
		if value != "none" and value.trim() == "": return "empty reporter"

	return ""

// ---------------------------------------------------------------- issue values

fn present_s(a: String?) Bool:
	if _x := a: return true
	return false

fn present_i(a: Int?) Bool:
	if _x := a: return true
	return false

fn same_s(a: String?, b: String?) Bool:
	if x := a:
		if y := b: return x == y
		return false

	if _y := b: return false

	return true

fn same_i(a: Int?, b: Int?) Bool:
	if x := a:
		if y := b: return x == y
		return false

	if _y := b: return false

	return true

fn show_s(a: String?) String:
	if x := a: return x.clone()
	return "-"

fn show_i(a: Int?) String:
	if x := a: return "{x}"
	return "-"

fn points_or_zero(a: Int?) Int:
	if x := a: return x
	return 0

fn show_labels(l: List[String]) String:
	if l.is_empty(): return "-"
	return join_with(l, ",")

fn show_labels_spaced(l: List[String]) String:
	if l.is_empty(): return "-"
	return join_with(l, ", ")

fn new_issue(id: Int, state: String, title: String, actor: String, clock: Int) Issue:
	return Issue(
		id: id, title: title.clone(), state: state.clone(), priority: "medium",
		assignee: none, reporter: actor.clone(), points: none, due: none,
		labels: List[String](), comments: List[Comment](), created: clock,
		updated: clock
	)

fn with_assign(iss: Issue, field: String, value: String) Issue:
	var n = iss.clone()

	if field == "title":
		n.title = value.clone()
	else if field == "priority":
		n.priority = value.clone()
	else if field == "assignee":
		if value == "none":
			n.assignee = none
		else:
			n.assignee = value.clone()
	else if field == "points":
		if value == "none":
			n.points = none
		else:
			n.points = canon_int(value)
	else if field == "due":
		if value == "none":
			n.due = none
		else:
			n.due = value.clone()
	else if field == "labels":
		if value == "none":
			n.labels = List[String]()
		else:
			r := norm_labels(split_csv(value))
			n.labels = r.items.clone()
	else if field == "reporter":
		if value == "none":
			n.reporter = none
		else:
			n.reporter = value.clone()

	return n

fn diff_entries(old: Issue, nw: Issue) List[String]:
	var out = List[String]()
	if old.title != nw.title:
		out.append("title: {old.title} -> {nw.title}")
	if old.priority != nw.priority:
		out.append("priority: {old.priority} -> {nw.priority}")
	if not same_s(old.assignee, nw.assignee):
		out.append("assignee: {show_s(old.assignee)} -> {show_s(nw.assignee)}")
	if not same_i(old.points, nw.points):
		out.append("points: {show_i(old.points)} -> {show_i(nw.points)}")
	if not same_s(old.due, nw.due):
		out.append("due: {show_s(old.due)} -> {show_s(nw.due)}")

	ol := show_labels(old.labels)
	nl := show_labels(nw.labels)
	if ol != nl:
		out.append("labels: {ol} -> {nl}")
	if not same_s(old.reporter, nw.reporter):
		out.append("reporter: {show_s(old.reporter)} -> {show_s(nw.reporter)}")
	return out

fn field_missing(iss: Issue, g: String) Bool:
	if g == "assignee": return not present_s(iss.assignee)
	if g == "points": return not present_i(iss.points)
	if g == "due": return not present_s(iss.due)
	if g == "reporter": return not present_s(iss.reporter)
	if g == "labels": return iss.labels.is_empty()

	return false

fn is_final(finals: List[String], s: String) Bool:
	return find_str(finals, s) >= 0

fn find_index(t: Tracker, id: Int) Int:
	var i = 0

	for iss in t.issues:
		if iss.id == id: return i

		i += 1

	return -1

fn resolve(t: Tracker, arg: String) Found:
	id := id_value(arg)
	if id < 1: return Found(idx: -1, err: "bad issue id '{arg}'")

	i := find_index(t, id)
	if i < 0: return Found(idx: -1, err: "no such issue #{id}")

	return Found(idx: i, err: "")

// writes the new issue if anything changed; prints the result line
fn commit_update(var t: Tracker, idx: Int, nw: Issue) String:
	old := t.issues[idx].clone()
	diffs := diff_entries(old, nw)
	id := nw.id

	if diffs.is_empty():
		print("#{id} unchanged")
		return ""

	t.clock += 1

	var fin = nw.clone()
	fin.updated = t.clock
	t.issues[idx] = fin
	for d in diffs:
		t.log_add(id, d)
	print("updated #{id}")
	return ""

// ---------------------------------------------------------------- workflow

fn parse_workflow(block: List[String]) Wf:
	var states = List[String]()
	var initial = ""
	var initial_seen = false
	var finals = List[String]()
	var transitions = List[Transition]()
	var err = ""

	for raw in block:
		s := raw.trim()
		if s == "" or s.starts_with("#"): continue

		colon := s.split(":", 2)

		if colon.length() == 2 and colon[0].trim() == "initial":
			if initial_seen:
				err = "workflow: initial state defined twice"
				break

			initial_seen = true

			nm := colon[1].trim()

			if not valid_state(nm):
				err = "workflow: bad state name '{nm}'"
				break

			initial = nm.clone()
			if find_str(states, nm) < 0:
				states.append(nm.clone())
		else if colon.length() == 2 and colon[0].trim() == "final":
			for part in colon[1].split(","):
				nm := part.trim()

				if not valid_state(nm):
					err = "workflow: bad state name '{nm}'"
					break

				if find_str(states, nm) < 0:
					states.append(nm.clone())
				if find_str(finals, nm) < 0:
					finals.append(nm.clone())

			if err != "": break
		else if s.contains("->"):
			arrow := s.split("->", 2)
			src := arrow[0].trim()

			if not valid_state(src):
				err = "workflow: bad state name '{src}'"
				break

			if find_str(states, src) < 0:
				states.append(src.clone())

			for entry in arrow[1].split(","):
				words := entry.fields()
				var target = ""
				var guard_txt = ""

				if words.length() == 1:
					target = words[0].clone()
				else if words.length() == 3 and words[1] == "requires":
					target = words[0].clone()
					guard_txt = words[2].clone()
				else:
					err = "workflow: bad line '{s}'"
					break

				if not valid_state(target):
					err = "workflow: bad state name '{target}'"
					break

				if find_str(states, target) < 0:
					states.append(target.clone())

				var guards = List[String]()

				if guard_txt != "":
					for g in guard_txt.split("+"):
						if find_str(GUARD_FIELDS, g) < 0:
							err = "workflow: bad guard field '{g}'"
							break

						guards.append(g.clone())

					if err != "": break

				transitions.append(
					Transition(
						src: src.clone(), dst: target.clone(), guards: guards
					)
				)

			if err != "": break
		else:
			err = "workflow: bad line '{s}'"
			break

	if err == "":
		if initial == "":
			err = "workflow: initial state missing"
		else:
			for tr in transitions:
				if find_str(finals, tr.src) >= 0:
					err = "workflow: '{tr.src}' is final and cannot have transitions"
					break

	return Wf(
		states: states, initial: initial, finals: finals, transitions: transitions,
		err: err
	)

fn cmd_workflow(var t: Tracker, block: List[String]) String:
	if t.ever_created: return "workflow: cannot redefine after issues were created"

	wf := parse_workflow(block)
	if wf.err != "": return wf.err.clone()

	nstates := wf.states.length()
	ntrans := wf.transitions.length()
	t.states = wf.states.clone()
	t.initial = wf.initial.clone()
	t.finals = wf.finals.clone()
	t.transitions = wf.transitions.clone()
	print("workflow ok: {nstates} states, {ntrans} transitions")
	return ""

// ---------------------------------------------------------------- basic commands

fn cmd_actor(var t: Tracker, rest: String) String:
	w := rest.fields()
	if w.length() != 1: return "usage: actor NAME"

	nm := w[0].clone()
	t.actor = nm.clone()
	print("actor is {nm}")
	return ""

fn cmd_today(var t: Tracker, rest: String) String:
	w := rest.fields()
	if w.length() != 1: return "usage: today DATE"

	d := w[0].clone()
	if not valid_date(d): return "bad date '{d}'"

	t.today = d.clone()
	print("today is {d}")
	return ""

fn cmd_create(var t: Tracker, rest: String) String:
	tk := tokenize(rest)
	if tk.err != "": return tk.err.clone()
	if t.states.is_empty(): return "no workflow defined"

	toks := tk.items
	if toks.is_empty(): return "usage: create TITLE [field=value...]"

	title := toks[0].clone()
	if title.trim() == "": return "empty title"

	id := t.next_id
	base := new_issue(id, t.initial, title, t.actor, t.clock + 1)
	var iss = base.clone()
	var k = 1

	while k < toks.length():
		a := parse_asg(toks[k])
		if a.err != "": return a.err.clone()

		e := check_assign(a.field, a.value)
		if e != "": return e

		iss = with_assign(iss, a.field, a.value)
		k += 1

	diffs := diff_entries(base, iss)
	t.clock += 1
	iss.created = t.clock
	iss.updated = t.clock
	t.issues.append(iss)
	t.next_id += 1
	t.ever_created = true
	t.log_add(id, "created \"{title}\"")
	for d in diffs:
		t.log_add(id, d)
	print("created #{id}")
	return ""

fn edit_common(var t: Tracker, id_arg: String, asgs: List[Asg], usage: String) String:
	f := resolve(t, id_arg)
	if f.err != "": return f.err.clone()

	idx := f.idx
	cur := t.issues[idx].clone()
	if is_final(t.finals, cur.state): return "#{cur.id} is in final state '{cur.state}'"
	if asgs.is_empty(): return usage.clone()

	var nw = cur.clone()

	for a in asgs:
		if a.err != "": return a.err.clone()

		e := check_assign(a.field, a.value)
		if e != "": return e

		nw = with_assign(nw, a.field, a.value)

	return commit_update(var t, idx, nw)

fn cmd_edit(var t: Tracker, rest: String) String:
	tk := tokenize(rest)
	if tk.err != "": return tk.err.clone()

	toks := tk.items
	if toks.is_empty(): return "usage: edit ID field=value..."

	var asgs = List[Asg]()
	var k = 1

	while k < toks.length():
		asgs.append(parse_asg(toks[k]))
		k += 1

	return edit_common(var t, toks[0], asgs, "usage: edit ID field=value...")

fn cmd_assign(var t: Tracker, rest: String) String:
	tk := tokenize(rest)
	if tk.err != "": return tk.err.clone()

	toks := tk.items
	if toks.length() != 2: return "usage: assign ID NAME"

	var asgs = List[Asg]()
	asgs.append(Asg(field: "assignee", value: toks[1].clone(), err: ""))
	return edit_common(var t, toks[0], asgs, "usage: assign ID NAME")

fn label_common(var t: Tracker, id_arg: String, ops: List[String]) String:
	f := resolve(t, id_arg)
	if f.err != "": return f.err.clone()

	idx := f.idx
	var labels = t.issues[idx].labels.clone()

	for op in ops:
		var add = true
		var body = op.clone()

		if op.starts_with("-"):
			add = false
			body = sub(op.chars(), 1, op.length())
		else if op.starts_with("+"):
			body = sub(op.chars(), 1, op.length())

		l := body.lower()
		if not label_ok(l): return "bad label '{l}'"

		if add:
			if find_str(labels, l) < 0:
				labels.append(l)
		else:
			p := find_str(labels, l)
			if p >= 0:
				labels.remove(p)

	labels.sort()

	cur := t.issues[idx].clone()
	if is_final(t.finals, cur.state): return "#{cur.id} is in final state '{cur.state}'"

	var nw = cur.clone()
	nw.labels = labels.clone()
	return commit_update(var t, idx, nw)

fn cmd_label(var t: Tracker, rest: String) String:
	tk := tokenize(rest)
	if tk.err != "": return tk.err.clone()

	toks := tk.items
	if toks.length() < 2: return "usage: label ID +label -label..."

	var ops = List[String]()
	var k = 1

	while k < toks.length():
		ops.append(toks[k].clone())
		k += 1

	return label_common(var t, toks[0], ops)

fn move_common(var t: Tracker, id_arg: String, dst: String, comment: String) String:
	f := resolve(t, id_arg)
	if f.err != "": return f.err.clone()

	idx := f.idx
	cur := t.issues[idx].clone()
	from := cur.state.clone()
	if is_final(t.finals, from): return "#{cur.id} is in final state '{from}'"
	if find_str(t.states, dst) < 0: return "unknown state '{dst}'"
	if from == dst: return "already in state '{from}'"

	var guards = List[String]()
	var found = false

	for tr in t.transitions:
		if not found and tr.src == from and tr.dst == dst:
			found = true
			guards = tr.guards.clone()

	if not found: return "transition '{from} -> {dst}' not allowed"

	var missing = List[String]()
	for g in guards:
		if field_missing(cur, g):
			missing.append(g.clone())

	if not missing.is_empty():
		mtxt := join_with(missing, ", ")
		return "cannot move #{cur.id} to {dst}: missing {mtxt}"

	id := cur.id
	t.clock += 1

	var nw = cur.clone()
	nw.state = dst.clone()
	nw.updated = t.clock

	has_c := comment.trim() != ""
	if has_c:
		nw.comments.append(
			Comment(
				t: t.clock, actor: t.actor.clone(), text: comment.clone()
			)
		)
	t.issues[idx] = nw
	t.log_add(id, "state: {from} -> {dst}")
	if has_c:
		t.log_add(id, "comment: {comment}")
	print("moved #{id}: {from} -> {dst}")
	return ""

fn cmd_move(var t: Tracker, rest: String) String:
	a := split_first(rest)
	b := split_first(a.rest)
	if a.first == "" or b.first == "": return "usage: move ID STATE [comment...]"

	return move_common(var t, a.first, b.first, b.rest)

fn cmd_comment(var t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "" or a.rest == "": return "usage: comment ID TEXT"

	f := resolve(t, a.first)
	if f.err != "": return f.err.clone()

	idx := f.idx
	t.clock += 1

	var nw = t.issues[idx].clone()
	nw.comments.append(
		Comment(t: t.clock, actor: t.actor.clone(), text: a.rest.clone())
	)
	nw.updated = t.clock

	id := nw.id
	t.issues[idx] = nw
	t.log_add(id, "comment: {a.rest}")
	print("commented #{id}")
	return ""

fn cmd_delete(var t: Tracker, rest: String) String:
	w := rest.fields()
	if w.length() != 1: return "usage: delete ID"

	f := resolve(t, w[0])
	if f.err != "": return f.err.clone()

	idx := f.idx
	id := t.issues[idx].id
	t.clock += 1
	t.log_add(id, "deleted")

	var kept = List[Issue]()
	var i = 0

	for iss in t.issues:
		if i != idx:
			kept.append(iss.clone())
		i += 1

	t.issues = kept
	print("deleted #{id}")
	return ""

fn cmd_show(t: Tracker, rest: String) String:
	w := rest.fields()
	if w.length() != 1: return "usage: show ID"

	f := resolve(t, w[0])
	if f.err != "": return f.err.clone()

	iss := t.issues[f.idx].clone()
	print("#{iss.id} {iss.title}")
	print("  state: {iss.state}")
	print("  priority: {iss.priority}")
	print("  assignee: {show_s(iss.assignee)}")
	print("  points: {show_i(iss.points)}")
	print("  due: {show_s(iss.due)}")
	print("  labels: {show_labels_spaced(iss.labels)}")
	print("  reporter: {show_s(iss.reporter)}")
	print("  created: t={iss.created}, updated: t={iss.updated}")
	print("  comments: {iss.comments.length()}")
	for c in iss.comments:
		print("    [t={c.t} {c.actor}] {c.text}")
	return ""

// ---------------------------------------------------------------- query language

fn is_field_char(c: String) Bool:
	return is_lower(c) or c == "_"

fn qtok_simple(kind: String, text: String) QTok:
	return QTok(kind: kind, text: text, field: "", op: "", value: "", quoted: false)

fn read_op(cs: List[String], j: Int) String:
	n := cs.length()
	c := cs[j]
	nx := if j + 1 < n: cs[j + 1].clone() else: ""
	if c == "!" and nx == "=": return "!="
	if c == "<" and nx == "=": return "<="
	if c == ">" and nx == "=": return ">="
	if c == ":" or c == "<" or c == ">" or c == "~": return c.clone()

	return ""

fn tokenize_filter(text: String) QTokRes:
	cs := text.chars()
	n := cs.length()
	var toks = List[QTok]()
	var i = 0

	while i < n:
		c := cs[i]

		if is_space(c):
			i += 1
		else if c == "(" or c == ")":
			toks.append(qtok_simple(c.clone(), c.clone()))
			i += 1
		else:
			var j = i
			while j < n and is_field_char(cs[j]):
				j += 1

			op := if j > i and j < n: read_op(cs, j) else: ""

			if op != "":
				oplen := if op.length() == 2: 2 else: 1
				var p = j + oplen
				var value = ""
				var quoted = false

				if p < n and cs[p] == "\"":
					var q = p + 1
					var closed = false

					while q < n:
						if (
							cs[q] == "\\"
							and q + 1 < n
							and (
								cs[q + 1] == "\""
								or cs[q + 1] == "\\"
							)
						):
							value += cs[q + 1]
							q += 2
						else if cs[q] == "\"":
							closed = true
							q += 1
							break
						else:
							value += cs[q]
							q += 1

					if not closed:
						return QTokRes(
							toks: List[QTok](), err: "query: unterminated quote"
						)

					quoted = true
					p = q
				else:
					while (
						p < n
						and not is_space(cs[p])
						and cs[p] != "("
						and cs[p] != ")"
					):
						value += cs[p]
						p += 1

				toks.append(
					QTok(
						kind: "TERM", text: sub(cs, i, p), field: sub(cs, i, j), op: op,
						value: value, quoted: quoted
					)
				)
				i = p
			else:
				var k = i
				while k < n and not is_space(cs[k]) and cs[k] != "(" and cs[k] != ")":
					k += 1

				w := sub(cs, i, k)
				kind := if w == "AND" or w == "OR" or w == "NOT": w.clone() else: "BARE"
				toks.append(qtok_simple(kind, w))
				i = k

	return QTokRes(toks: toks, err: "")

fn empty_expr() Expr:
	return Expr(
		kind: "all", kids: List[Expr](), field: "", op: "", values: List[String](),
		name: ""
	)

fn mk(kind: String, kids: List[Expr]) Expr:
	return Expr(
		kind: kind, kids: kids, field: "", op: "", values: List[String](), name: ""
	)

fn pe_err(msg: String) PE:
	return PE(e: empty_expr(), err: msg)

fn peek_kind(p: QP) String:
	if p.pos >= p.toks.length(): return ""
	return p.toks[p.pos].kind.clone()

fn op_allowed(f: String, op: String) Bool:
	if (
		f == "id"
		or f == "created"
		or f == "updated"
		or f == "points"
		or f == "priority"
		or f == "due"
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
		f == "title"
		or f == "assignee"
		or f == "reporter"
		or f == "label"
		or f == "labels"
	):
		return op == ":" or op == "!=" or op == "~"
	if f == "text": return op == "~"
	if f == "state": return op == ":" or op == "!="

	return op == ":"

fn bad_value(f: String, op: String, a: String, states: List[String]) Bool:
	if f == "id" or f == "created" or f == "updated": return canon_int(a) < 0

	if f == "points":
		if (op == ":" or op == "!=") and a == "none": return false
		return canon_int(a) < 0

	if f == "due":
		if (op == ":" or op == "!=") and a == "none": return false
		return not valid_date(a)

	if f == "priority": return find_str(PRIORITIES, a) < 0
	if f == "state": return find_str(states, a) < 0
	if f == "is": return find_str(IS_VALUES, a) < 0
	if f == "has": return find_str(HAS_VALUES, a) < 0

	return false

fn parse_stored(stored: String, states: List[String], views: Map[String, String]) PE:
	q := split_query(stored)
	if q.err != "": return pe_err(q.err)

	return parse_filter(q.filter, states, views)

fn make_term(tok: QTok, states: List[String], views: Map[String, String]) PE:
	f := tok.field.clone()
	op := tok.op.clone()
	if find_str(QUERY_FIELDS, f) < 0: return pe_err("query: unknown field '{f}'")
	if not op_allowed(f, op):
		return pe_err("query: bad operator '{op}' for field '{f}'")

	if f == "view":
		name := tok.value.clone()
		if not views.contains(name): return pe_err("query: unknown view '{name}'")

		stored := views.get_or(name, "")
		inner := parse_stored(stored, states, views)
		if inner.err != "": return inner

		var kids = List[Expr]()
		kids.append(inner.e.clone())
		return PE(
			e: Expr(
				kind: "view", kids: kids, field: "", op: "", values: List[String](),
				name: name
			),
			err: ""
		)

	ordered := op != ":" and op != "!=" and op != "~"
	multi := (not tok.quoted) and tok.value.contains("|")
	if multi and ordered:
		return pe_err("query: bad value '{tok.value}' for field '{f}'")

	var alts = List[String]()

	if multi:
		alts = tok.value.split("|")
	else:
		alts.append(tok.value.clone())

	for a in alts:
		if bad_value(f, op, a, states):
			return pe_err("query: bad value '{a}' for field '{f}'")
	return PE(
		e: Expr(
			kind: "term", kids: List[Expr](), field: f, op: op, values: alts, name: ""
		),
		err: ""
	)

fn parse_expr(var p: QP, states: List[String], views: Map[String, String]) PE:
	first := parse_and(var p, states, views)
	if first.err != "": return first

	var left = first.e.clone()

	while peek_kind(p) == "OR":
		p.pos += 1

		r := parse_and(var p, states, views)
		if r.err != "": return r

		var kids = List[Expr]()
		kids.append(left.clone())
		kids.append(r.e.clone())
		left = mk("or", kids)

	return PE(e: left, err: "")

fn parse_and(var p: QP, states: List[String], views: Map[String, String]) PE:
	first := parse_not(var p, states, views)
	if first.err != "": return first

	var left = first.e.clone()

	while true:
		k := peek_kind(p)

		if k == "AND":
			p.pos += 1
		else if not (k == "TERM" or k == "(" or k == "NOT"):
			break

		r := parse_not(var p, states, views)
		if r.err != "": return r

		var kids = List[Expr]()
		kids.append(left.clone())
		kids.append(r.e.clone())
		left = mk("and", kids)

	return PE(e: left, err: "")

fn parse_not(var p: QP, states: List[String], views: Map[String, String]) PE:
	if peek_kind(p) == "NOT":
		p.pos += 1

		c := parse_not(var p, states, views)
		if c.err != "": return c

		var kids = List[Expr]()
		kids.append(c.e.clone())
		return PE(e: mk("not", kids), err: "")

	return parse_primary(var p, states, views)

fn parse_primary(var p: QP, states: List[String], views: Map[String, String]) PE:
	if p.pos >= p.toks.length(): return pe_err("query: unexpected end of query")

	tok := p.toks[p.pos].clone()

	if tok.kind == "(":
		p.pos += 1

		inner := parse_expr(var p, states, views)
		if inner.err != "": return inner
		if p.pos >= p.toks.length(): return pe_err("query: unexpected end of query")

		nxt := p.toks[p.pos].text.clone()
		if p.toks[p.pos].kind != ")": return pe_err("query: unexpected token '{nxt}'")

		p.pos += 1
		return inner

	if tok.kind == "TERM":
		p.pos += 1
		return make_term(tok, states, views)

	return pe_err("query: unexpected token '{tok.text}'")

fn parse_filter(text: String, states: List[String], views: Map[String, String]) PE:
	qt := tokenize_filter(text)
	if qt.err != "": return pe_err(qt.err)
	if qt.toks.is_empty(): return PE(e: empty_expr(), err: "")

	var p = QP(toks: qt.toks.clone(), pos: 0)
	r := parse_expr(var p, states, views)
	if r.err != "": return r

	if p.pos < p.toks.length():
		tx := p.toks[p.pos].text.clone()
		return pe_err("query: unexpected token '{tx}'")

	return r

// limit, then the first ` sort ` clause, then the filter text
fn split_query(text: String) QParts:
	t0 := text.trim()
	cs := t0.chars()
	n := cs.length()
	var filt_end = n
	var limit = -1
	var ws_pos = -1
	var q = n - 1

	while q >= 0:
		if is_space(cs[q]):
			ws_pos = q
			break

		q -= 1

	if ws_pos >= 0:
		arg := sub(cs, ws_pos + 1, n)
		var e = ws_pos
		while e > 0 and is_space(cs[e - 1]):
			e -= 1

		var s = e
		while s > 0 and not is_space(cs[s - 1]):
			s -= 1

		if sub(cs, s, e) == "limit":
			v := canon_int(arg)
			if v < 0:
				return QParts(
					filter: "", has_sort: false, sort_text: "", limit: -1,
					err: "bad limit '{arg}'"
				)

			limit = v
			filt_end = s

	bc := sub(cs, 0, filt_end).chars()
	bn := bc.length()
	var sort_at = -1
	var k = 0

	while k + 4 < bn:
		if (
			(k == 0 or is_space(bc[k - 1]))
			and sub(bc, k, k + 4) == "sort"
			and is_space(bc[k + 4])
		):
			sort_at = k
			break

		k += 1

	if sort_at >= 0:
		return QParts(
			filter: sub(bc, 0, sort_at).trim(), has_sort: true,
			sort_text: sub(bc, sort_at + 4, bn), limit: limit, err: ""
		)

	return QParts(
		filter: sub(bc, 0, bn).trim(), has_sort: false, sort_text: "", limit: limit,
		err: ""
	)

fn parse_sort(text: String) SortRes:
	var keys = List[SortKey]()
	pieces := text.replace(",", " ").fields()

	for p in pieces:
		desc := p.starts_with("-")
		var name = p.clone()
		if desc:
			name = sub(p.chars(), 1, p.length())
		if find_str(SORT_FIELDS, name) < 0:
			return SortRes(keys: List[SortKey](), err: "bad sort field '{name}'")

		keys.append(SortKey(field: name.clone(), desc: desc))

	return SortRes(keys: keys, err: "")

fn uses_view(e: Expr, name: String) Bool:
	if e.kind == "view" and e.name == name: return true

	for k in e.kids:
		if uses_view(k, name): return true
	return false

// ---------------------------------------------------------------- evaluation

fn sgn_int(a: Int, b: Int) Int:
	if a < b: return -1
	if a > b: return 1

	return 0

fn sgn_str(a: String, b: String) Int:
	if a < b: return -1
	if a > b: return 1

	return 0

fn op_match(c: Int, op: String) Bool:
	if op == ":": return c == 0
	if op == "!=": return c != 0
	if op == "<": return c < 0
	if op == "<=": return c <= 0
	if op == ">": return c > 0
	if op == ">=": return c >= 0

	return false

fn text_match(s: String, a: String, op: String) Bool:
	if op == "~": return s.lower().contains(a.lower())
	return s.lower() == a.lower()

fn match_opt_text(v: String?, a: String, op: String) Bool:
	if x := v: return text_match(x, a, op)
	return a == "none" and op == ":"

fn match_one(f: String, op: String, a: String, iss: Issue, ctx: EvalCtx) Bool:
	if f == "id": return op_match(sgn_int(iss.id, canon_int(a)), op)
	if f == "created": return op_match(sgn_int(iss.created, canon_int(a)), op)
	if f == "updated": return op_match(sgn_int(iss.updated, canon_int(a)), op)

	if f == "points":
		if p := iss.points:
			if a == "none": return false
			return op_match(sgn_int(p, canon_int(a)), op)

		return a == "none" and op == ":"

	if f == "title": return text_match(iss.title, a, op)
	if f == "assignee": return match_opt_text(iss.assignee, a, op)
	if f == "reporter": return match_opt_text(iss.reporter, a, op)

	if f == "text":
		if text_match(iss.title, a, op): return true

		for c in iss.comments:
			if text_match(c.text, a, op): return true
		return false

	if f == "state": return iss.state == a

	if f == "priority":
		if op == ":": return iss.priority == a
		return op_match(sgn_int(rank(iss.priority), rank(a)), op)

	if f == "due":
		if d := iss.due:
			if a == "none": return false
			return op_match(sgn_str(d, a), op)

		return a == "none" and op == ":"

	if f == "label" or f == "labels":
		if op == "~":
			needle := a.lower()
			for l in iss.labels:
				if l.contains(needle): return true
			return false

		if a == "none": return iss.labels.is_empty()

		return find_str(iss.labels, a.lower()) >= 0

	if f == "is":
		fin := is_final(ctx.finals, iss.state)
		if a == "open": return not fin
		if a == "final": return fin

		if a == "overdue":
			if d := iss.due: return not fin and sgn_str(d, ctx.today) < 0
			return false

		if a == "unassigned": return not present_s(iss.assignee)

		return false

	if f == "has":
		if a == "assignee": return present_s(iss.assignee)
		if a == "due": return present_s(iss.due)
		if a == "points": return present_i(iss.points)
		if a == "labels": return not iss.labels.is_empty()
		if a == "comments": return not iss.comments.is_empty()
		if a == "reporter": return present_s(iss.reporter)

		return false

	return false

fn eval_term(e: Expr, iss: Issue, ctx: EvalCtx) Bool:
	if e.op == "!=":
		for a in e.values:
			if match_one(e.field, ":", a, iss, ctx): return false
		return true

	for a in e.values:
		if match_one(e.field, e.op, a, iss, ctx): return true
	return false

fn eval_expr(e: Expr, iss: Issue, ctx: EvalCtx) Bool:
	if e.kind == "all": return true
	if e.kind == "term": return eval_term(e, iss, ctx)
	if e.kind == "view": return eval_expr(e.kids[0], iss, ctx)
	if e.kind == "not": return not eval_expr(e.kids[0], iss, ctx)

	if e.kind == "and":
		for k in e.kids:
			if not eval_expr(k, iss, ctx): return false
		return true

	if e.kind == "or":
		for k in e.kids:
			if eval_expr(k, iss, ctx): return true
		return false

	return false

fn cmp_opt_int(a: Int?, b: Int?) Int:
	if x := a:
		if y := b: return sgn_int(x, y)
		return -1

	if _y := b: return 1

	return 0

fn cmp_opt_str(a: String?, b: String?, ci: Bool) Int:
	if x := a:
		if y := b:
			if ci: return sgn_str(x.lower(), y.lower())
			return sgn_str(x, y)

		return -1

	if _y := b: return 1

	return 0

fn cmp_field(a: Issue, b: Issue, f: String, states: List[String]) Int:
	if f == "id": return sgn_int(a.id, b.id)
	if f == "created": return sgn_int(a.created, b.created)
	if f == "updated": return sgn_int(a.updated, b.updated)
	if f == "priority": return sgn_int(rank(a.priority), rank(b.priority))
	if f == "points": return cmp_opt_int(a.points, b.points)
	if f == "state":
		return sgn_int(find_str(states, a.state), find_str(states, b.state))
	if f == "title": return sgn_str(a.title.lower(), b.title.lower())
	if f == "assignee": return cmp_opt_str(a.assignee, b.assignee, true)
	if f == "reporter": return cmp_opt_str(a.reporter, b.reporter, true)

	return cmp_opt_str(a.due, b.due, false)

fn cmp_issues(a: Issue, b: Issue, keys: List[SortKey], states: List[String]) Int:
	for k in keys:
		var c = cmp_field(a, b, k.field, states)
		if k.desc:
			c = -c
		if c != 0: return c

	return sgn_int(a.id, b.id)

fn sort_issues(
	items: List[Issue],
	keys: List[SortKey],
	states: List[String]
) List[Issue]:
	var out = List[Issue]()

	for it in items:
		var pos = out.length()
		var k = 0

		while k < out.length():
			if cmp_issues(it, out[k], keys, states) < 0:
				pos = k
				break

			k += 1

		out.insert(pos, it.clone())

	return out

fn select_issues(t: Tracker, e: Expr, keys: List[SortKey], limit: Int) List[Issue]:
	ctx := EvalCtx(
		today: t.today.clone(), finals: t.finals.clone(), states: t.states.clone()
	)
	var hits = List[Issue]()
	for iss in t.issues:
		if eval_expr(e, iss, ctx):
			hits.append(iss.clone())
	if not keys.is_empty():
		hits = sort_issues(hits, keys, t.states)

	var out = List[Issue]()
	var k = 0

	for h in hits:
		if limit >= 0 and k >= limit: break

		out.append(h.clone())
		k += 1

	return out

fn issue_line(iss: Issue) String:
	a := show_s(iss.assignee)
	p := show_i(iss.points)
	d := show_s(iss.due)
	l := show_labels(iss.labels)
	return "#{iss.id} | {iss.state} | {iss.priority} | {a} | {p} | {d} | {l} | {iss.title}"

fn print_rows(rows: List[Issue]) Unit:
	for r in rows:
		print(issue_line(r))

	n := rows.length()

	if n == 1:
		print("(1 issue)")
	else:
		print("({n} issues)")

fn cmd_list(t: Tracker, rest: String) String:
	q := split_query(rest)
	if q.err != "": return q.err.clone()

	pe := parse_filter(q.filter, t.states, t.views)
	if pe.err != "": return pe.err.clone()

	sr := parse_sort(q.sort_text)
	if sr.err != "": return sr.err.clone()

	rows := select_issues(t, pe.e, sr.keys, q.limit)
	print_rows(rows)
	return ""

// ---------------------------------------------------------------- views

fn view_save(var t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "": return "usage: view save NAME QUERY"

	name := a.first.clone()
	if not valid_view_name(name): return "bad view name '{name}'"

	q := split_query(a.rest)
	if q.err != "": return q.err.clone()

	pe := parse_filter(q.filter, t.states, t.views)
	if pe.err != "": return pe.err.clone()

	sr := parse_sort(q.sort_text)
	if sr.err != "": return sr.err.clone()
	if uses_view(pe.e, name): return "view '{name}' would reference itself"

	t.views[name.clone()] = a.rest.trim()
	print("saved view {name}")
	return ""

fn view_run(t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "": return "usage: view run NAME [sort FIELDS] [limit N]"

	name := a.first.clone()
	if not t.views.contains(name): return "unknown view '{name}'"

	extra := split_query(a.rest)
	if extra.err != "": return extra.err.clone()
	if extra.filter != "": return "unexpected '{extra.filter}'"

	stored := t.views.get_or(name, "")
	st := split_query(stored)
	pe := parse_filter(st.filter, t.states, t.views)
	if pe.err != "": return pe.err.clone()

	var keys_text = st.sort_text.clone()
	if extra.has_sort:
		keys_text = extra.sort_text.clone()

	sr := parse_sort(keys_text)
	if sr.err != "": return sr.err.clone()

	var lim = st.limit
	if extra.limit >= 0:
		lim = extra.limit

	rows := select_issues(t, pe.e, sr.keys, lim)
	print_rows(rows)
	return ""

fn view_list(t: Tracker) String:
	var names = t.views.keys()

	if names.is_empty():
		print("(no views)")
		return ""

	names.sort()

	for n in names:
		q := t.views.get_or(n, "")
		print("{n}: {q}")

	return ""

fn view_show(t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "": return "usage: view show NAME"

	name := a.first.clone()
	if not t.views.contains(name): return "unknown view '{name}'"

	q := t.views.get_or(name, "")
	print("{name}: {q}")
	return ""

fn view_delete(var t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "": return "usage: view delete NAME"

	name := a.first.clone()
	if not t.views.contains(name): return "unknown view '{name}'"

	var names = t.views.keys()
	names.sort()

	for other in names:
		if other != name:
			stored := t.views.get_or(other, "")
			pe := parse_stored(stored, t.states, t.views)
			if pe.err == "" and uses_view(pe.e, name):
				return "view '{name}' is used by '{other}'"

	t.views.remove(name.clone())
	print("deleted view {name}")
	return ""

fn cmd_view(var t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "save": return view_save(var t, a.rest)
	if a.first == "run": return view_run(t, a.rest)
	if a.first == "list": return view_list(t)
	if a.first == "show": return view_show(t, a.rest)
	if a.first == "delete": return view_delete(var t, a.rest)

	return "usage: view save|run|list|show|delete"

// ---------------------------------------------------------------- bulk

fn split_where(text: String) Where:
	cs := text.chars()
	n := cs.length()
	var i = 0

	while i + 5 <= n:
		if (
			(i == 0 or is_space(cs[i - 1]))
			and sub(cs, i, i + 5) == "where"
			and (i + 5 == n or is_space(cs[i + 5]))
		):
			return Where(
				action: sub(cs, 0, i).trim(), query: sub(cs, i + 5, n).trim(), has: true
			)

		i += 1

	return Where(action: "", query: "", has: false)

fn tail_list(toks: List[String], start: Int) List[String]:
	var out = List[String]()
	var k = start

	while k < toks.length():
		out.append(toks[k].clone())
		k += 1

	return out

fn cmd_bulk(var t: Tracker, rest: String) String:
	usage := "usage: bulk ACTION... where QUERY"
	wh := split_where(rest)
	if not wh.has or wh.action == "": return usage.clone()

	tk := tokenize(wh.action)
	if tk.err != "": return tk.err.clone()

	toks := tk.items
	if toks.is_empty(): return usage.clone()

	kind := toks[0].clone()
	n := toks.length()

	if kind == "move":
		if n != 2: return "usage: bulk move STATE where QUERY"
	else if kind == "assign":
		if n != 2: return "usage: bulk assign NAME where QUERY"
	else if kind == "label":
		if n < 2: return "usage: bulk label +label... where QUERY"
	else if kind == "set":
		if n < 2: return "usage: bulk set field=value... where QUERY"
	else:
		return "unknown bulk action '{kind}'"

	pe := parse_filter(wh.query, t.states, t.views)
	if pe.err != "": return pe.err.clone()

	ctx := EvalCtx(
		today: t.today.clone(), finals: t.finals.clone(), states: t.states.clone()
	)
	var ids = List[Int]()
	for iss in t.issues:
		if eval_expr(pe.e, iss, ctx):
			ids.append(iss.id)

	var okc = 0
	var bad = 0

	for id in ids:
		arg := "{id}"
		var err = ""

		if kind == "move":
			err = move_common(var t, arg, toks[1], "")
		else if kind == "assign":
			var asgs = List[Asg]()
			asgs.append(Asg(field: "assignee", value: toks[1].clone(), err: ""))
			err = edit_common(var t, arg, asgs, usage)
		else if kind == "label":
			err = label_common(var t, arg, tail_list(toks, 1))
		else:
			var asgs = List[Asg]()
			for k in 1..n:
				asgs.append(parse_asg(toks[k]))
			err = edit_common(var t, arg, asgs, usage)

		if err == "":
			okc += 1
		else:
			bad += 1
			print("#{id} error: {err}")

	print("bulk: {okc} ok, {bad} failed")
	return ""

// ---------------------------------------------------------------- log and reports

fn log_id_check(t: Tracker, arg: String) String:
	v := id_value(arg)
	if v < 1: return "bad issue id '{arg}'"
	if v >= t.next_id: return "no such issue #{v}"

	return ""

fn cmd_log(t: Tracker, rest: String) String:
	w := rest.fields()
	n := w.length()
	usage := "usage: log [ID] [tail N]"
	var id = -1
	var tail = -1

	if n == 0:
		id = -1
	else if w[0] == "tail":
		if n != 2: return usage.clone()

		tail = canon_int(w[1])
		if tail < 0: return "bad tail '{w[1]}'"
	else if n == 1:
		e := log_id_check(t, w[0])
		if e != "": return e

		id = id_value(w[0])
	else if n == 3 and w[1] == "tail":
		e := log_id_check(t, w[0])
		if e != "": return e

		tail = canon_int(w[2])
		if tail < 0: return "bad tail '{w[2]}'"

		id = id_value(w[0])
	else:
		return usage.clone()

	var entries = List[String]()
	for e in t.log:
		if id < 0 or e.id == id:
			entries.append("t={e.t} {e.actor} #{e.id} {e.detail}")

	var start = 0

	if tail >= 0:
		start = entries.length() - tail
		if start < 0:
			start = 0

	if entries.is_empty() or start >= entries.length():
		print("(no log entries)")
		return ""

	var k = start

	while k < entries.length():
		print(entries[k])
		k += 1

	return ""

fn plural_issue(n: Int) String:
	if n == 1: return "issue"
	return "issues"

fn report_summary(t: Tracker) String:
	total := t.issues.length()
	var open = 0
	var openpts = 0
	var unassigned = 0
	var overdue = 0

	for iss in t.issues:
		if not is_final(t.finals, iss.state):
			open += 1
			openpts += points_or_zero(iss.points)
			if not present_s(iss.assignee):
				unassigned += 1
			if d := iss.due:
				if d < t.today:
					overdue += 1

	fin := total - open
	print("issues: {total} (open {open}, final {fin})")
	print("by state:")

	for s in t.states:
		var c = 0
		for iss in t.issues:
			if iss.state == s:
				c += 1
		print("  {s}: {c}")

	print("by priority:")

	for p in ["critical", "high", "medium", "low"]:
		var c = 0
		for iss in t.issues:
			if iss.priority == p:
				c += 1
		print("  {p}: {c}")

	print("unassigned: {unassigned}")
	print("overdue: {overdue}")
	print("open points: {openpts}")
	return ""

fn wl_before(a: WL, b: WL) Bool:
	if a.pts != b.pts: return a.pts > b.pts
	if a.count != b.count: return a.count > b.count

	return a.key < b.key

fn find_wl(rows: List[WL], key: String) Int:
	var i = 0

	for r in rows:
		if r.key == key: return i

		i += 1

	return -1

fn report_workload(t: Tracker) String:
	var rows = List[WL]()
	var un_count = 0
	var un_pts = 0
	var any_open = false

	for iss in t.issues:
		if is_final(t.finals, iss.state): continue

		any_open = true

		pts := points_or_zero(iss.points)

		if a := iss.assignee:
			key := a.lower()
			k := find_wl(rows, key)

			if k < 0:
				rows.append(WL(name: a.clone(), key: key, count: 1, pts: pts))
			else:
				rows[k].count += 1
				rows[k].pts += pts
		else:
			un_count += 1
			un_pts += pts

	if not any_open: return "(no open issues)"

	m := rows.length()

	for i in 0..m:
		var j = 0

		while j + 1 < m - i:
			if wl_before(rows[j + 1], rows[j]):
				tmp := rows[j].clone()
				rows[j] = rows[j + 1].clone()
				rows[j + 1] = tmp

			j += 1

	for r in rows:
		print("{r.name}: {r.count} {plural_issue(r.count)}, {r.pts} points")
	if un_count > 0:
		print("unassigned: {un_count} {plural_issue(un_count)}, {un_pts} points")
	return ""

fn report_labels(t: Tracker, rest: String) String:
	pe := parse_filter(rest.trim(), t.states, t.views)
	if pe.err != "": return pe.err.clone()

	ctx := EvalCtx(
		today: t.today.clone(), finals: t.finals.clone(), states: t.states.clone()
	)
	var rows = List[WL]()

	for iss in t.issues:
		if eval_expr(pe.e, iss, ctx):
			for l in iss.labels:
				k := find_wl(rows, l)

				if k < 0:
					rows.append(WL(name: l.clone(), key: l.clone(), count: 1, pts: 0))
				else:
					rows[k].count += 1

	if rows.is_empty(): return "(no labels)"

	m := rows.length()

	for i in 0..m:
		var j = 0

		while j + 1 < m - i:
			a := rows[j + 1].clone()
			b := rows[j].clone()

			if a.count > b.count or (a.count == b.count and a.key < b.key):
				rows[j] = a.clone()
				rows[j + 1] = b.clone()

			j += 1

	for r in rows:
		print("{r.name}: {r.count}")
	return ""

fn report_timeline(t: Tracker, rest: String) String:
	w := rest.fields()
	if w.length() != 1: return "usage: report timeline ID"

	f := resolve(t, w[0])
	if f.err != "": return f.err.clone()

	iss := t.issues[f.idx].clone()
	var cur = t.initial.clone()
	var from = iss.created

	for e in t.log:
		if e.id == iss.id and e.detail.starts_with("state: "):
			parts := e.detail.split(" -> ")
			target := parts[1].clone()
			print("{cur}: t={from}..{e.t} ({e.t - from})")
			cur = target
			from = e.t

	print("{cur}: t={from}..{t.clock} ({t.clock - from})")
	return ""

fn cmd_report(t: Tracker, rest: String) String:
	a := split_first(rest)
	if a.first == "summary": return report_summary(t)
	if a.first == "workload": return report_workload(t)
	if a.first == "labels": return report_labels(t, a.rest)
	if a.first == "timeline": return report_timeline(t, a.rest)

	return "usage: report summary|workload|labels|timeline"

// ---------------------------------------------------------------- driver

fn dispatch(var t: Tracker, cmd: String, rest: String) String:
	if cmd == "actor": return cmd_actor(var t, rest)
	if cmd == "today": return cmd_today(var t, rest)
	if cmd == "create": return cmd_create(var t, rest)
	if cmd == "edit": return cmd_edit(var t, rest)
	if cmd == "label": return cmd_label(var t, rest)
	if cmd == "assign": return cmd_assign(var t, rest)
	if cmd == "move": return cmd_move(var t, rest)
	if cmd == "comment": return cmd_comment(var t, rest)
	if cmd == "delete": return cmd_delete(var t, rest)
	if cmd == "show": return cmd_show(t, rest)
	if cmd == "list": return cmd_list(t, rest)
	if cmd == "view": return cmd_view(var t, rest)
	if cmd == "bulk": return cmd_bulk(var t, rest)
	if cmd == "log": return cmd_log(t, rest)
	if cmd == "report": return cmd_report(t, rest)

	return "unknown command '{cmd}'"

fn read_all() List[String]!Error:
	var out = List[String]()
	var s = lines(stdin())

	while true:
		item := try s.next()

		if line := item:
			out.append(line)
		else:
			break

	return ok(out)

export fn main() Int:
	all := read_all().get(List[String]())
	var t = Tracker(
		clock: 0, actor: "system", today: "1970-01-01", next_id: 1, ever_created: false,
		initial: "", states: List[String](), finals: List[String](),
		transitions: List[Transition](), issues: List[Issue](), log: List[LogEntry](),
		views: Map[String, String]()
	)
	n := all.length()
	var i = 0

	while i < n:
		line := all[i].trim_end()
		i += 1

		s := line.trim_start()
		if s == "" or s.starts_with("#"): continue

		print("> {line}")

		sp := split_first(line)

		if sp.first == "workflow":
			var block = List[String]()
			var more = true

			while more and i < n:
				b := all[i].clone()
				i += 1

				if b.trim() == "end":
					more = false
				else:
					block.append(b)

			e := cmd_workflow(var t, block)
			if e != "":
				print("error: {e}")
			continue

		e := dispatch(var t, sp.first, sp.rest)
		if e != "":
			print("error: {e}")

	return 0
