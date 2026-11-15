import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes from "@std/bytes.ms"

type RL:
	text: String
	line: Int

type Rule:
	prereqs: List[String]
	oo: List[String]
	recipe: List[RL]

type PatRule:
	pat: String
	prereqs: List[String]
	oo: List[String]
	recipe: List[RL]

type Var:
	value: String
	simple: Bool

type Block:
	parent: Bool
	taking: Bool
	cond: Bool
	in_else: Bool
	line: Int

type LLine:
	num: Int
	text: String
	recipe: Bool

type Resolved:
	found: Bool
	prereqs: List[String]
	oo: List[String]
	recipe: List[RL]
	stem: String

type Ctx:
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	out: List[String] = List[String]()
	vars: Map[String, Var] = Map[String, Var]()
	cmdvars: Set[String] = Set[String]()
	rules: List[Rule] = List[Rule]()
	ridx: Map[String, Int] = Map[String, Int]()
	order: List[String] = List[String]()
	pats: List[PatRule] = List[PatRule]()
	phony: Set[String] = Set[String]()
	phony_order: List[String] = List[String]()
	line: Int = 0
	fe: Map[String, String] = Map[String, String]()
	auto: Map[String, String] = Map[String, String]()
	expanding: List[String] = List[String]()
	memo: Map[String, Bool] = Map[String, Bool]()
	stack: List[String] = List[String]()
	ran: Int = 0
	dry: Bool = false
	pend_open: Bool = false
	pend_phony: Bool = false
	pend_targets: List[String] = List[String]()
	pend_pats: List[Int] = List[Int]()
	pend_recipe: List[RL] = List[RL]()
	pend_line: Int = 0

fn is_ws(c: String) Bool: c == " " or c == "\t"

fn sl(s: String, a: Int, b: Int) String: s.slice(a, b).get("")

fn sub(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b and i < cs.length():
		out += cs.get(i, "")
		i += 1
	return out

fn clone_rl(xs: List[RL]) List[RL]:
	var out = List[RL]()
	for x in xs:
		out.append(RL(text: x.text.clone(), line: x.line))
	return out

fn dedupe(xs: List[String]) List[String]:
	var out = List[String]()
	var seen = Set[String]()
	for x in xs:
		if seen.contains(x): continue
		seen.add(x.clone())
		out.append(x.clone())
	return out

fn split_args(raw: String) List[String]:
	var parts = List[String]()
	var cur = ""
	var depth = 0
	for c in raw.chars():
		if c == "," and depth == 0:
			parts.append(cur.clone())
			cur = ""
			continue
		if c == "(" or c == "\{": depth += 1
		if c == ")" or c == "\}":
			if depth > 0: depth -= 1
		cur += c
	parts.append(cur.clone())
	return parts

// byte offset of first `target` char outside $( ) / ${ } references; -1 if none
fn scan_top(cs: List[String], target: String, stop_semi: Bool) Int:
	var i = 0
	var bp = 0
	n := cs.length()
	while i < n:
		c := cs.get(i, "")
		if c == "$":
			d := cs.get(i + 1, "")
			if d == "$":
				bp += 2
				i += 2
				continue
			if d == "(" or d == "\{":
				close := if d == "(": ")" else: "\}"
				var depth = 1
				var j = i + 2
				while j < n:
					ch := cs.get(j, "")
					if ch == d: depth += 1
					if ch == close:
						depth -= 1
						if depth == 0: break
					j += 1
				var k = i
				while k <= j and k < n:
					bp += cs.get(k, "").length()
					k += 1
				i = j + 1
				continue
		if stop_semi and c == ";": return -1
		if c == target: return bp
		bp += c.length()
		i += 1
	return -1

fn pat_stem(pat: String, w: String) String?:
	if i := pat.index_of("%"):
		pre := sl(pat, 0, i)
		suf := sl(pat, i + 1, pat.length())
		if w.length() >= pre.length() + suf.length() and w.starts_with(pre) and w.ends_with(suf):
			return sl(w, pre.length(), w.length() - suf.length())
		return none
	if pat == w: return ""
	return none

fn subst_stem(s: String, stem: String) String: s.replace_first("%", stem)

fn patsubst_words(pat: String, rep: String, text: String) String:
	var out = List[String]()
	for w in text.fields():
		if stem := pat_stem(pat, w):
			if pat.contains("%"):
				out.append(subst_stem(rep, stem))
			else:
				out.append(rep.clone())
		else:
			out.append(w.clone())
	return out.join(" ")

fn glob(p: List[String], i: Int, w: List[String], j: Int) Bool:
	if i == p.length(): return j == w.length()
	c := p.get(i, "")
	if c == "*":
		var k = j
		while true:
			if glob(p, i + 1, w, k): return true
			if k >= w.length() or w.get(k, "") == "/": return false
			k += 1
		return false
	if j >= w.length(): return false
	d := w.get(j, "")
	if c == "?":
		if d == "/": return false
		return glob(p, i + 1, w, j + 1)
	if c != d: return false
	return glob(p, i + 1, w, j + 1)

fn is_func(n: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(n)

fn last_slash(w: String) Int:
	var r = -1
	var i = 0
	for c in w.chars():
		if c == "/": r = i
		i += c.length()
	return r

fn last_dot_after(w: String, from: Int) Int:
	var r = -1
	var i = 0
	for c in w.chars():
		if c == "." and i >= from: r = i
		i += c.length()
	return r

fn Ctx.fatal(msg: String) Error:
	if self.line > 0:
		return Error("Makefile:{self.line}: *** {msg}.  Stop.")
	return Error("make: *** {msg}.  Stop.")

fn Ctx.get_var(name: String) Var?:
	if v := self.vars.get(name):
		return Var(value: v.value.clone(), simple: v.simple)
	return none

fn var Ctx.lookup(name: String) String!:
	if v := self.fe.get(name): return ok(v.clone())
	if v := self.auto.get(name): return ok(v.clone())
	if vr := self.get_var(name):
		if vr.simple: return ok(vr.value.clone())
		if self.expanding.contains(name):
			return error(self.fatal("Recursive variable '{name}' references itself (eventually)"))
		self.expanding.append(name.clone())
		r := self.expand(vr.value)?
		_ := self.expanding.pop()
		return ok(r)
	return ok("")

fn var Ctx.arg(args: List[String], i: Int) String!:
	return self.expand(args.get(i, "").trim())

fn var Ctx.eval_ref(inner: String) String!:
	cs := inner.chars()
	var wsi = -1
	var k = 0
	while k < cs.length():
		if is_ws(cs.get(k, "")):
			wsi = k
			break
		k += 1
	if wsi > 0:
		fname := sub(cs, 0, wsi)
		if is_func(fname):
			return self.call_func(fname, sub(cs, wsi + 1, cs.length()))
	name := (self.expand(inner)?).trim()
	nc := name.chars()
	var ci = -1
	var p = 0
	for c in nc:
		if c == ":" and p > 0:
			ci = p
			break
		p += c.length()
	if ci > 0:
		rest := sl(name, ci + 1, name.length())
		if e := rest.index_of("="):
			vname := sl(name, 0, ci).trim()
			from := sl(rest, 0, e).trim()
			to := sl(rest, e + 1, rest.length()).trim()
			value := self.lookup(vname)?
			if from.contains("%"):
				return ok(patsubst_words(from, to, value))
			return ok(patsubst_words("%" + from, "%" + to, value))
	return self.lookup(name)

fn var Ctx.expand(s: String) String!:
	cs := s.chars()
	n := cs.length()
	var out = ""
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if c != "$":
			out += c
			i += 1
			continue
		if i + 1 >= n:
			i += 1
			continue
		d := cs.get(i + 1, "")
		if d == "$":
			out += "$"
			i += 2
			continue
		if d == "(" or d == "\{":
			close := if d == "(": ")" else: "\}"
			var depth = 1
			var j = i + 2
			var found = false
			while j < n:
				ch := cs.get(j, "")
				if ch == d: depth += 1
				if ch == close:
					depth -= 1
					if depth == 0:
						found = true
						break
				j += 1
			if not found:
				return error(self.fatal("unterminated variable reference"))
			out += self.eval_ref(sub(cs, i + 2, j))?
			i = j + 1
			continue
		out += self.lookup(d)?
		i += 2
	return ok(out)

fn var Ctx.call_func(name: String, rest: String) String!:
	args := split_args(rest)
	if name == "subst":
		from := self.arg(args, 0)?
		to := self.arg(args, 1)?
		text := self.arg(args, 2)?
		if from.length() == 0: return ok(text)
		return ok(text.replace(from, to))
	if name == "patsubst":
		pat := self.arg(args, 0)?
		rep := self.arg(args, 1)?
		text := self.arg(args, 2)?
		return ok(patsubst_words(pat, rep, text))
	if name == "strip":
		return ok((self.arg(args, 0)?).fields().join(" "))
	if name == "findstring":
		f := self.arg(args, 0)?
		text := self.arg(args, 1)?
		if text.contains(f): return ok(f)
		return ok("")
	if name == "filter" or name == "filter-out":
		pats := (self.arg(args, 0)?).fields()
		ws := (self.arg(args, 1)?).fields()
		var out = List[String]()
		for w in ws:
			var hit = false
			for p in pats:
				if pat_stem(p, w).is_some(): hit = true
			if hit == (name == "filter"): out.append(w.clone())
		return ok(out.join(" "))
	if name == "sort":
		ws := (self.arg(args, 0)?).fields().sorted()
		var out = List[String]()
		for w in ws:
			if out.length() > 0 and out.get(out.length() - 1, "") == w: continue
			out.append(w.clone())
		return ok(out.join(" "))
	if name == "word":
		ns := self.arg(args, 0)?
		ws := (self.arg(args, 1)?).fields()
		if n := ns.parse_int():
			if n >= 1 and n <= ws.length(): return ok(ws.get(n - 1, "").clone())
		return ok("")
	if name == "wordlist":
		ss := self.arg(args, 0)?
		es := self.arg(args, 1)?
		ws := (self.arg(args, 2)?).fields()
		s := ss.parse_int().get(0)
		e := es.parse_int().get(-1)
		if s < 1 or e < s or s > ws.length(): return ok("")
		var out = List[String]()
		var i = s
		while i <= e and i <= ws.length():
			out.append(ws.get(i - 1, "").clone())
			i += 1
		return ok(out.join(" "))
	if name == "words":
		return ok("{(self.arg(args, 0)?).fields().length()}")
	if name == "firstword":
		ws := (self.arg(args, 0)?).fields()
		return ok(ws.get(0, "").clone())
	if name == "lastword":
		ws := (self.arg(args, 0)?).fields()
		return ok(ws.get(ws.length() - 1, "").clone())
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		ws := (self.arg(args, 0)?).fields()
		var out = List[String]()
		for w in ws:
			ls := last_slash(w)
			if name == "dir":
				if ls < 0: out.append("./")
				else: out.append(sl(w, 0, ls + 1))
			else if name == "notdir":
				out.append(sl(w, ls + 1, w.length()))
			else:
				ld := last_dot_after(w, ls + 1)
				if name == "suffix":
					if ld >= 0: out.append(sl(w, ld, w.length()))
				else:
					if ld >= 0: out.append(sl(w, 0, ld))
					else: out.append(w.clone())
		return ok(out.join(" "))
	if name == "addprefix" or name == "addsuffix":
		pre := self.arg(args, 0)?
		ws := (self.arg(args, 1)?).fields()
		var out = List[String]()
		for w in ws:
			if name == "addprefix": out.append(pre + w)
			else: out.append(w + pre)
		return ok(out.join(" "))
	if name == "wildcard":
		pats := (self.arg(args, 0)?).fields()
		var out = List[String]()
		for p in pats:
			if p.contains("*") or p.contains("?"):
				var names = List[String]()
				for e in self.files.keys():
					if glob(p.chars(), 0, e.chars(), 0): names.append(e.clone())
				for e in names.sorted(): out.append(e.clone())
			else:
				if self.files.contains(p): out.append(p.clone())
		return ok(out.join(" "))
	if name == "foreach":
		v := (self.arg(args, 0)?).trim()
		lst := (self.arg(args, 1)?).fields()
		body := args.get(2, "").trim()
		old := self.fe.get(v)
		var oldv = ""
		var had = false
		if o := old:
			oldv = o.clone()
			had = true
		var out = List[String]()
		for w in lst:
			self.fe[v.clone()] = w.clone()
			out.append(self.expand(body)?)
		if had: self.fe[v.clone()] = oldv
		else: self.fe.remove(v)
		return ok(out.join(" "))
	if name == "if":
		cond := (self.arg(args, 0)?).trim()
		if cond.length() > 0: return self.arg(args, 1)
		return self.arg(args, 2)
	if name == "info":
		t := self.arg(args, 0)?
		self.out.append(t)
		return ok("")
	if name == "error":
		t := self.arg(args, 0)?
		return error(self.fatal(t))
	return ok("")

fn logical_lines(phys: List[String]) List[LLine]:
	var out = List[LLine]()
	var i = 0
	n := phys.length()
	while i < n:
		start := i + 1
		var cur = phys.get(i, "").clone()
		isrec := cur.starts_with("\t")
		i += 1
		while cur.ends_with("\\"):
			body := sl(cur, 0, cur.length() - 1).trim_end()
			if i >= n:
				cur = body
				break
			cur = body + " " + phys.get(i, "").trim_start()
			i += 1
		out.append(LLine(num: start, text: cur.clone(), recipe: isrec))
	return out

fn strip_comment(s: String) String:
	cs := s.chars()
	var out = ""
	var i = 0
	while i < cs.length():
		c := cs.get(i, "")
		if c == "\\" and cs.get(i + 1, "") == "#":
			out += "#"
			i += 2
			continue
		if c == "#": break
		out += c
		i += 1
	return out

fn strip_tabs(s: String) String:
	var i = 0
	while i < s.length() and sl(s, i, i + 1) == "\t": i += 1
	return sl(s, i, s.length())

fn first_word(s: String) String:
	var i = 0
	for c in s.chars():
		if is_ws(c): break
		i += c.length()
	return sl(s, 0, i)

fn join_sp(a: String, b: String) String:
	if a.length() == 0: return b.clone()
	if b.length() == 0: return a.clone()
	return a + " " + b

fn var Ctx.reset(names: List[String], vals: List[String]) Void:
	self.vars = Map[String, Var]()
	self.cmdvars = Set[String]()
	self.rules = List[Rule]()
	self.ridx = Map[String, Int]()
	self.order = List[String]()
	self.pats = List[PatRule]()
	self.phony = Set[String]()
	self.phony_order = List[String]()
	self.line = 0
	self.fe = Map[String, String]()
	self.auto = Map[String, String]()
	self.expanding = List[String]()
	self.memo = Map[String, Bool]()
	self.stack = List[String]()
	self.ran = 0
	self.pend_open = false
	self.pend_phony = false
	self.pend_targets = List[String]()
	self.pend_pats = List[Int]()
	self.pend_recipe = List[RL]()
	for i in 0..names.length():
		self.vars[names.get(i, "").clone()] = Var(value: vals.get(i, "").clone(), simple: false)
		self.cmdvars.add(names.get(i, "").clone())

fn var Ctx.close_rule() Void:
	if not self.pend_open: return
	self.pend_open = false
	targets := self.pend_targets.clone()
	pidx := self.pend_pats.clone()
	rec := clone_rl(self.pend_recipe)
	self.pend_targets = List[String]()
	self.pend_pats = List[Int]()
	self.pend_recipe = List[RL]()
	if self.pend_phony: return
	if rec.length() == 0: return
	for t in targets:
		if i := self.ridx.get(t):
			if self.rules[i].recipe.length() > 0:
				self.out.append("Makefile:{self.pend_line}: warning: overriding recipe for target '{t}'")
			self.rules[i].recipe = clone_rl(rec)
	for pi in pidx:
		self.pats[pi].recipe = clone_rl(rec)

fn var Ctx.apply_assign(name: String, op: String, value: String) Void!:
	if self.cmdvars.contains(name): return
	if op == "=":
		self.vars[name.clone()] = Var(value: value.clone(), simple: false)
	else if op == ":=":
		v := self.expand(value)?
		self.vars[name.clone()] = Var(value: v, simple: true)
	else if op == "?=":
		if not self.vars.contains(name):
			self.vars[name.clone()] = Var(value: value.clone(), simple: false)
	else:
		old := self.get_var(name)
		if o := old:
			if o.simple:
				nv := self.expand(value)?
				self.vars[name.clone()] = Var(value: join_sp(o.value, nv), simple: true)
			else:
				self.vars[name.clone()] = Var(value: join_sp(o.value, value), simple: false)
		else:
			self.vars[name.clone()] = Var(value: value.clone(), simple: false)

fn var Ctx.eval_ifeq(rest: String) Bool!:
	cs := rest.chars()
	n := cs.length()
	if n < 2 or cs.get(0, "") != "(" or cs.get(n - 1, "") != ")":
		return error(self.fatal("invalid syntax in conditional"))
	args := split_args(sub(cs, 1, n - 1))
	if args.length() != 2:
		return error(self.fatal("invalid syntax in conditional"))
	a := (self.expand(args.get(0, "").trim())?).trim()
	b := (self.expand(args.get(1, "").trim())?).trim()
	return ok(a == b)

fn var Ctx.add_rule_line(text: String, col: Int, num: Int) Void!:
	targets_raw := sl(text, 0, col)
	rest := sl(text, col + 1, text.length())
	semi := scan_top(rest.chars(), ";", false)
	var prereq_raw = rest.clone()
	var cmd = ""
	if semi >= 0:
		prereq_raw = sl(rest, 0, semi)
		cmd = sl(rest, semi + 1, rest.length()).trim()
	tt := (self.expand(targets_raw)?).fields()
	pp := self.expand(prereq_raw)?
	var normal = List[String]()
	var oo = List[String]()
	if bar := pp.index_of("|"):
		normal = sl(pp, 0, bar).fields()
		oo = sl(pp, bar + 1, pp.length()).fields()
	else:
		normal = pp.fields()
	self.pend_open = true
	self.pend_line = num
	self.pend_phony = tt.length() == 1 and tt.get(0, "") == ".PHONY"
	if self.pend_phony:
		for p in normal:
			if not self.phony.contains(p):
				self.phony.add(p.clone())
				self.phony_order.append(p.clone())
	else:
		for t in tt:
			if t.contains("%"):
				self.pats.append(PatRule(pat: t.clone(), prereqs: normal.clone(), oo: oo.clone(), recipe: List[RL]()))
				self.pend_pats.append(self.pats.length() - 1)
			else:
				if i := self.ridx.get(t):
					for p in normal: self.rules[i].prereqs.append(p.clone())
					for p in oo: self.rules[i].oo.append(p.clone())
				else:
					self.rules.append(Rule(prereqs: normal.clone(), oo: oo.clone(), recipe: List[RL]()))
					self.ridx[t.clone()] = self.rules.length() - 1
					self.order.append(t.clone())
				self.pend_targets.append(t.clone())
	if cmd.length() > 0:
		self.pend_recipe.append(RL(text: cmd, line: num))

fn var Ctx.parse(mf: List[String]) Void!:
	lls := logical_lines(mf)
	var blocks = List[Block]()
	for ll in lls:
		self.line = ll.num
		active := blocks.length() == 0 or blocks[blocks.length() - 1].taking
		if ll.recipe:
			if not active: continue
			t := strip_tabs(ll.text)
			if t.trim().length() == 0: continue
			if not self.pend_open:
				return error(self.fatal("recipe commences before first target"))
			self.pend_recipe.append(RL(text: t, line: ll.num))
			continue
		text := strip_comment(ll.text).trim()
		if text.length() == 0: continue
		w := first_word(text)
		rest := sl(text, w.length(), text.length()).trim()
		if w == "ifdef" or w == "ifndef" or w == "ifeq" or w == "ifneq":
			self.close_rule()
			var cond = false
			if active:
				if w == "ifdef" or w == "ifndef":
					name := (self.expand(rest)?).trim()
					var defined = false
					if v := self.vars.get(name):
						defined = v.value.length() > 0
					cond = if w == "ifdef": defined else: not defined
				else:
					r := self.eval_ifeq(rest)?
					cond = if w == "ifeq": r else: not r
			blocks.append(Block(parent: active, taking: active and cond, cond: cond, in_else: false, line: ll.num))
			continue
		if text == "else":
			self.close_rule()
			if blocks.length() == 0: return error(self.fatal("extraneous 'else'"))
			li := blocks.length() - 1
			if blocks[li].in_else: return error(self.fatal("extraneous 'else'"))
			blocks[li].in_else = true
			blocks[li].taking = blocks[li].parent and not blocks[li].cond
			continue
		if w == "endif":
			self.close_rule()
			if blocks.length() == 0: return error(self.fatal("extraneous 'endif'"))
			_ := blocks.pop()
			continue
		if not active: continue
		self.close_rule()
		eq := text.index_of("=").get(-1)
		col := scan_top(text.chars(), ":", true)
		if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
			var op = "="
			var namepart = sl(text, 0, eq)
			if eq > 0:
				pc := sl(text, eq - 1, eq)
				if pc == ":" or pc == "?" or pc == "+":
					op = pc + "="
					namepart = sl(text, 0, eq - 1)
			name := (self.expand(namepart)?).trim()
			if name.length() == 0: return error(self.fatal("empty variable name"))
			value := sl(text, eq + 1, text.length()).trim()
			self.apply_assign(name, op, value)?
		else if col >= 0:
			self.add_rule_line(text, col, ll.num)?
		else:
			x := self.expand(text)?
			if x.trim().length() > 0:
				return error(self.fatal("missing separator"))
	self.close_rule()
	if blocks.length() > 0:
		self.line = blocks[blocks.length() - 1].line
		return error(self.fatal("missing 'endif'"))
	self.line = 0

fn Ctx.all_make(prereqs: List[String], oo: List[String], stem: String, depth: Int) Bool:
	for x in prereqs:
		if not self.can_make(subst_stem(x, stem), depth): return false
	for x in oo:
		if not self.can_make(subst_stem(x, stem), depth): return false
	return true

fn Ctx.can_make(name: String, depth: Int) Bool:
	if self.files.contains(name): return true
	if self.ridx.contains(name): return true
	if self.phony.contains(name): return true
	if depth > 8: return false
	for p in self.pats:
		if p.recipe.length() == 0: continue
		if s := pat_stem(p.pat, name):
			if s.length() > 0 and self.all_make(p.prereqs, p.oo, s, depth + 1): return true
	return false

fn Ctx.resolve(t: String) Resolved:
	var ei = -1
	if i := self.ridx.get(t): ei = i
	if ei >= 0 and self.rules[ei].recipe.length() > 0:
		return Resolved(found: true, prereqs: self.rules[ei].prereqs.clone(), oo: self.rules[ei].oo.clone(), recipe: clone_rl(self.rules[ei].recipe), stem: "")
	for p in self.pats:
		if p.recipe.length() == 0: continue
		if s := pat_stem(p.pat, t):
			if s.length() == 0: continue
			if self.all_make(p.prereqs, p.oo, s, 1):
				var pre = List[String]()
				var oo = List[String]()
				for x in p.prereqs: pre.append(subst_stem(x, s))
				for x in p.oo: oo.append(subst_stem(x, s))
				if ei >= 0:
					for x in self.rules[ei].prereqs: pre.append(x.clone())
					for x in self.rules[ei].oo: oo.append(x.clone())
				return Resolved(found: true, prereqs: pre, oo: oo, recipe: clone_rl(p.recipe), stem: s.clone())
	if ei >= 0:
		return Resolved(found: true, prereqs: self.rules[ei].prereqs.clone(), oo: self.rules[ei].oo.clone(), recipe: List[RL](), stem: "")
	return Resolved(found: false, prereqs: List[String](), oo: List[String](), recipe: List[RL](), stem: "")

fn var Ctx.simulate(cmd: String) Int:
	ws := cmd.fields()
	w := ws.get(0, "")
	if w == "false": return 1
	if w == "exit":
		if ws.length() >= 2:
			if n := ws.get(1, "").parse_int(): return n
			return 2
		return 0
	if w == "touch":
		for i in 1..ws.length():
			f := ws.get(i, "")
			if not f.starts_with("-"):
				self.clock += 1
				self.files[f.clone()] = self.clock
		return 0
	if w == "rm":
		for i in 1..ws.length():
			f := ws.get(i, "")
			if not f.starts_with("-"): self.files.remove(f)
		return 0
	if w == "cp":
		if ws.length() == 3:
			src := ws.get(1, "")
			if not self.files.contains(src):
				self.out.append("cp: cannot stat '{src}': No such file or directory")
				return 1
			self.clock += 1
			self.files[ws.get(2, "").clone()] = self.clock
		return 0
	if w == "echo":
		var parts = List[String]()
		for i in 1..ws.length():
			parts.append(ws.get(i, "").replace("'", "").replace("\"", ""))
		self.out.append(parts.join(" "))
		return 0
	return 0

fn var Ctx.run_recipe(t: String, r: Resolved, pre: List[String], existed: Bool, t0: Int) Void!:
	var q = List[String]()
	for p in pre:
		var inc = not existed or self.memo.get_or(p, false)
		if existed:
			if pm := self.files.get(p):
				if pm > t0: inc = true
		if inc: q.append(p.clone())
	self.auto = Map[String, String]()
	self.auto["@"] = t.clone()
	self.auto["<"] = r.prereqs.get(0, "").clone()
	self.auto["^"] = pre.join(" ")
	self.auto["?"] = q.join(" ")
	self.auto["|"] = dedupe(r.oo).join(" ")
	self.auto["*"] = r.stem.clone()
	self.ran += 1
	for rl in r.recipe:
		self.line = rl.line
		ex := (self.expand(rl.text)?).trim()
		var silent = false
		var ign = false
		var cmd = ex.clone()
		while cmd.length() > 0:
			c := sl(cmd, 0, 1)
			if c == "@": silent = true
			else if c == "-": ign = true
			else if c == "+" or c == " " or c == "\t": silent = silent
			else: break
			cmd = sl(cmd, 1, cmd.length())
		cmd = cmd.trim()
		if cmd.length() == 0: continue
		if self.dry or not silent: self.out.append(cmd.clone())
		if not self.dry:
			st := self.simulate(cmd)
			if st != 0:
				if ign:
					self.out.append("make: [Makefile:{rl.line}: {t}] Error {st} (ignored)")
				else:
					return error(Error("make: *** [Makefile:{rl.line}: {t}] Error {st}"))
	self.auto = Map[String, String]()
	self.line = 0
	if not self.dry and not self.phony.contains(t):
		self.clock += 1
		self.files[t.clone()] = self.clock

fn var Ctx.update(t: String, by: String) Bool!:
	if m := self.memo.get(t): return ok(m)
	if self.stack.contains(t):
		var path = List[String]()
		var started = false
		for s in self.stack:
			if s == t: started = true
			if started: path.append(s.clone())
		path.append(t.clone())
		return error(Error("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
	r := self.resolve(t)
	if not r.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)
		if self.phony.contains(t):
			self.memo[t.clone()] = true
			return ok(true)
		if by.length() == 0:
			return error(Error("make: *** No rule to make target '{t}'.  Stop."))
		return error(Error("make: *** No rule to make target '{t}', needed by '{by}'.  Stop."))
	existed := self.files.contains(t)
	t0 := self.files.get_or(t, 0)
	self.stack.append(t.clone())
	var anych = false
	var newer = false
	pre := dedupe(r.prereqs)
	for p in pre:
		ch := self.update(p, t)?
		if ch: anych = true
		if existed:
			if pm := self.files.get(p):
				if pm > t0: newer = true
	for p in dedupe(r.oo):
		_ := self.update(p, t)?
	_ := self.stack.pop()
	need := self.phony.contains(t) or not self.files.contains(t) or anych or newer
	if need and r.recipe.length() > 0:
		self.run_recipe(t, r, pre, existed, t0)?
	self.memo[t.clone()] = need
	return ok(need)

fn var Ctx.build_goals(goals: List[String]) Void!:
	var gl = goals.clone()
	if gl.length() == 0:
		for t in self.order:
			if not t.starts_with("."):
				gl.append(t.clone())
				break
		if gl.length() == 0:
			self.out.append("make: *** No targets.  Stop.")
			return
	for g in gl:
		start := self.ran
		_ := self.update(g, "")?
		if self.ran == start:
			r := self.resolve(g)
			if r.recipe.length() > 0 or (self.files.contains(g) and not self.phony.contains(g)):
				self.out.append("make: '{g}' is up to date.")
			else:
				self.out.append("make: Nothing to be done for '{g}'.")

fn var Ctx.dfs(t: String, var seen: Set[String], var emit: List[String]) Void!:
	if self.stack.contains(t):
		var path = List[String]()
		var started = false
		for s in self.stack:
			if s == t: started = true
			if started: path.append(s.clone())
		path.append(t.clone())
		return error(Error("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
	if seen.contains(t): return
	r := self.resolve(t)
	self.stack.append(t.clone())
	for p in dedupe(r.prereqs):
		self.dfs(p, var seen, var emit)?
	for p in dedupe(r.oo):
		self.dfs(p, var seen, var emit)?
	_ := self.stack.pop()
	seen.add(t.clone())
	emit.append(t.clone())

fn fmt_rule(name: String, pre: List[String], oo: List[String]) String:
	var s = name + ": " + pre.join(" ")
	if oo.length() > 0: s += " | " + oo.join(" ")
	return s

fn var Ctx.run_parse(names: List[String], vals: List[String], mf: List[String]) Bool:
	self.reset(names, vals)
	r := self.parse(mf)
	self.line = 0
	if r.is_error():
		self.out.append(r.err().message.clone())
		return false
	return true

fn var Ctx.targets_out() Void:
	for t in self.order:
		if not t.starts_with("."):
			self.out.append("default: {t}")
			break
	for t in self.order:
		if i := self.ridx.get(t):
			self.out.append(fmt_rule(t + "", self.rules[i].prereqs, self.rules[i].oo))
	for p in self.pats:
		self.out.append(fmt_rule("pattern " + p.pat, p.prereqs, p.oo))
	if self.phony_order.length() > 0:
		self.out.append("phony: " + self.phony_order.join(" "))

fn var Ctx.handle(line: String, mf: List[String]) Void:
	req := line.trim()
	if req.length() == 0 or req.starts_with("#"): return
	self.out.append("> " + line.trim_end())
	fields := req.fields()
	word := fields.get(0, "")
	rest := sl(req, word.length(), req.length()).trim()
	if word == "files":
		var names = self.files.keys().sorted()
		if names.length() == 0:
			self.out.append("(no files)")
		for n in names:
			self.out.append("{n} {self.files.get_or(n, 0)}")
		return
	if word == "touch":
		if fields.length() == 2:
			self.clock += 1
			self.files[fields.get(1, "").clone()] = self.clock
		else if fields.length() == 3:
			if n := fields.get(2, "").parse_int():
				self.files[fields.get(1, "").clone()] = n
				if n > self.clock: self.clock = n
			else:
				self.out.append("bad request")
		else:
			self.out.append("bad request")
		return
	if word == "rm":
		for i in 1..fields.length(): self.files.remove(fields.get(i, ""))
		return
	if word == "expand":
		if not self.run_parse(List[String](), List[String](), mf): return
		r := self.expand(rest)
		self.line = 0
		if r.is_error():
			self.out.append(r.err().message.clone())
		else:
			self.out.append("[{r.get("")}]")
		return
	if word == "build" or word == "dry" or word == "deps" or word == "targets":
		var names = List[String]()
		var vals = List[String]()
		var goals = List[String]()
		for i in 1..fields.length():
			a := fields.get(i, "")
			if e := a.index_of("="):
				if e > 0:
					names.append(sl(a, 0, e))
					vals.append(sl(a, e + 1, a.length()))
					continue
			goals.append(a.clone())
		if word == "deps" and goals.length() != 1:
			self.out.append("usage: deps TARGET")
			return
		if not self.run_parse(names, vals, mf): return
		if word == "targets":
			self.targets_out()
			return
		if word == "deps":
			var seen = Set[String]()
			var emit = List[String]()
			r := self.dfs(goals.get(0, ""), var seen, var emit)
			self.stack = List[String]()
			if r.is_error():
				self.out.append(r.err().message.clone())
				return
			emit.pop()
			if emit.length() == 0:
				self.out.append("(no prerequisites)")
			for e in emit: self.out.append(e.clone())
			return
		self.dry = word == "dry"
		r := self.build_goals(goals)
		self.auto = Map[String, String]()
		self.line = 0
		if r.is_error(): self.out.append(r.err().message.clone())
		return
	self.out.append("unknown request: {word}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void!:
	bytes := read_all(stdin(), none)?
	text := bytes.decode_utf8().get("")
	var mf = List[String]()
	var table = List[String]()
	var reqs = List[String]()
	var sec = 0
	for raw in text.split("\n", none):
		l := if raw.ends_with("\r"): sl(raw, 0, raw.length() - 1) else: raw.clone()
		if sec < 2 and l == "====":
			sec += 1
			continue
		if sec == 0: mf.append(l)
		else if sec == 1: table.append(l)
		else: reqs.append(l)
	var ctx = Ctx()
	for l in table:
		f := l.fields()
		if f.length() != 2: continue
		if m := f.get(1, "").parse_int():
			if m < 0: continue
			ctx.files[f.get(0, "").clone()] = m
			if m > ctx.clock: ctx.clock = m
	for l in reqs:
		ctx.handle(l, mf)
	if ctx.out.length() > 0: print(ctx.out.join("\n"))
