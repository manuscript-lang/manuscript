import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Cmd:
	text: String
	line: Int

type Rule:
	pre: List[String]
	oo: List[String]
	cmds: List[Cmd]

type PatRule:
	pat: String
	pre: List[String]
	oo: List[String]
	cmds: List[Cmd]

type Var:
	val: String
	simple: Bool

type Frame:
	active: Bool
	parent: Bool
	cond: Bool
	seen_else: Bool
	line: Int

type Resolved:
	found: Bool
	pre: List[String]
	oo: List[String]
	cmds: List[Cmd]
	stem: String

type Ctx:
	vars: Map[String, Var] = Map[String, Var]()
	cmdvars: Set[String] = Set[String]()
	rules: Map[String, Rule] = Map[String, Rule]()
	order: List[String] = List[String]()
	pats: List[PatRule] = List[PatRule]()
	phony: Set[String] = Set[String]()
	phony_order: List[String] = List[String]()
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	out: List[String] = List[String]()
	line: Int = 0
	expanding: Set[String] = Set[String]()
	binds: Map[String, String] = Map[String, String]()
	auto: Map[String, String] = Map[String, String]()
	cstack: List[Frame] = List[Frame]()
	rule_open: Bool = false
	r_targets: List[String] = List[String]()
	r_pre: List[String] = List[String]()
	r_oo: List[String] = List[String]()
	r_cmds: List[Cmd] = List[Cmd]()
	r_line: Int = 0
	r_phony: Bool = false
	memo: Map[String, Bool] = Map[String, Bool]()
	bstack: List[String] = List[String]()
	ran: Int = 0
	dry: Bool = false
	dseen: Set[String] = Set[String]()
	dres: List[String] = List[String]()

fn bs(s: String, a: Int, b: Int) String:
	if a >= b: return ""
	if r := s.slice(a, b): return r

	return ""

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\n" or c == "\r"

fn words(s: String) List[String]:
	var out = List[String]()
	var cur = ""

	for c in s.chars():
		if is_ws(c):
			if cur.length() > 0:
				out.append(cur.clone())
				cur = ""
		else:
			cur += c

	if cur.length() > 0:
		out.append(cur.clone())
	return out

fn dedup(xs: List[String]) List[String]:
	var out = List[String]()
	for x in xs:
		if not out.contains(x):
			out.append(x.clone())
	return out

fn split_args(s: String) List[String]:
	var out = List[String]()
	var cur = ""
	var depth = 0

	for c in s.chars():
		if c == "(" or c == "{":
			depth += 1
			cur += c
		else if c == ")" or c == "}":
			depth -= 1
			cur += c
		else if c == "," and depth <= 0:
			out.append(cur.trim())
			cur = ""
		else:
			cur += c

	out.append(cur.trim())
	return out

fn stem_of(pat: String, w: String, nonempty: Bool) String?:
	pi := pat.index_of("%")

	if p := pi:
		pre := bs(pat, 0, p)
		suf := bs(pat, p + 1, pat.length())
		need := pre.length() + suf.length() + (if nonempty: 1 else: 0)
		if w.length() < need: return null
		if not w.starts_with(pre): return null
		if not w.ends_with(suf): return null

		return bs(w, pre.length(), w.length() - suf.length())

	return null

fn subst_pct(s: String, stem: String) String:
	if p := s.index_of("%"): return bs(s, 0, p) + stem + bs(s, p + 1, s.length())
	return s.clone()

fn pat_word(pat: String, rep: String, w: String) String:
	if pat.contains("%"):
		if st := stem_of(pat, w, false): return subst_pct(rep, st)
		return w.clone()

	if pat == w: return rep.clone()

	return w.clone()

fn matches_any(pats: List[String], w: String) Bool:
	for p in pats:
		if p.contains("%"):
			if stem_of(p, w, false) != null: return true
		else if p == w: return true

	return false

fn glob(p: List[String], i: Int, s: List[String], j: Int) Bool:
	if i == p.length(): return j == s.length()

	c := p[i]

	if c == "*":
		var k = j

		while k <= s.length():
			if glob(p, i + 1, s, k): return true
			if k < s.length() and s[k] == "/": break

			k += 1

		return false

	if j >= s.length(): return false
	if c == "?": return s[j] != "/" and glob(p, i + 1, s, j + 1)

	return c == s[j] and glob(p, i + 1, s, j + 1)

fn last_char_idx(w: String, ch: String) Int:
	var idx = -1
	var k = 0

	for c in w.chars():
		if c == ch: idx = k
		k += c.length()

	return idx

fn word_fn(fname: String, w: String) String:
	if fname == "dir":
		i := last_char_idx(w, "/")
		if i < 0: return "./"

		return bs(w, 0, i + 1)

	slash := last_char_idx(w, "/")
	base := bs(w, slash + 1, w.length())
	if fname == "notdir": return base

	d := last_char_idx(base, ".")

	if fname == "suffix":
		if d < 0: return ""
		return bs(base, d, base.length())

	if d < 0: return w.clone()

	return bs(w, 0, w.length() - (base.length() - d))

fn is_func(n: String) Bool:
	names := [
		"subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort",
		"word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix",
		"basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info",
		"error"
	]
	return names.contains(n)

fn find_top(cs: List[String], ch: String, stop_semi: Bool, from: Int) Int:
	n := cs.length()
	var i = from

	while i < n:
		c := cs[i]

		if c == "$":
			if i + 1 >= n: return -1

			nx := cs[i + 1]

			if nx == "(" or nx == "{":
				close := if nx == "(": ")" else: "}"
				var depth = 1
				var j = i + 2

				while j < n and depth > 0:
					if cs[j] == nx:
						depth += 1
					else if cs[j] == close:
						depth -= 1

					j += 1

				i = j
			else:
				i += 2

			continue

		if c == ch: return i
		if stop_semi and c == ";": return -1

		i += 1

	return -1

fn sub(cs: List[String], a: Int, b: Int) String:
	var r = ""
	var i = a

	while i < b and i < cs.length():
		r += cs[i]
		i += 1

	return r

fn join_sp(xs: List[String]) String: xs.join(" ")

fn Ctx.fatal(msg: String) Error:
	if self.line > 0: return Error(f"Makefile:{self.line}: *** {msg}.  Stop.")
	return Error(f"make: *** {msg}.  Stop.")

fn var Ctx.tick() Int:
	self.clock += 1
	return self.clock

fn var Ctx.lookup(name: String) String!:
	if self.binds.contains(name): return ok(self.binds.get_or(name, "").clone())
	if self.auto.contains(name): return ok(self.auto.get_or(name, "").clone())

	var val = ""
	var simple = true

	if v := self.vars.get(name):
		val = v.val.clone()
		simple = v.simple
	else:
		return ok("")

	if simple: return ok(val)
	if self.expanding.contains(name):
		return error(
			self.fatal(
				f"Recursive variable '{name}' references itself (eventually)"
			)
		)

	self.expanding.add(name.clone())

	r := self.expand(val)?
	self.expanding.remove(name)
	return ok(r)

fn var Ctx.expand(text: String) String!:
	if not text.contains("$"): return ok(text.clone())

	cs := text.chars()
	n := cs.length()
	var res = ""
	var i = 0

	while i < n:
		c := cs[i]

		if c != "$":
			res += c
			i += 1
			continue

		if i + 1 >= n:
			i += 1
			continue

		nx := cs[i + 1]

		if nx == "$":
			res += "$"
			i += 2
			continue

		if nx == "(" or nx == "{":
			close := if nx == "(": ")" else: "}"
			var depth = 1
			var j = i + 2
			var found = -1

			while j < n:
				d := cs[j]

				if d == nx:
					depth += 1
				else if d == close:
					depth -= 1

					if depth == 0:
						found = j
						break

				j += 1

			if found < 0: return error(self.fatal("unterminated variable reference"))

			inner := sub(cs, i + 2, found)
			res += self.eval_ref(inner)?
			i = found + 1
			continue

		res += self.lookup(nx.clone())?
		i += 2

	return ok(res)

fn var Ctx.eval_ref(inner: String) String!:
	if k := inner.find_char(fn c: c == " " or c == "\t"):
		fname := bs(inner, 0, k)

		if is_func(fname):
			rest := bs(inner, k + 1, inner.length())
			return self.call_func(fname, rest)

	name := (self.expand(inner)?).trim()

	if ci := name.index_of(":"):
		if ci > 0:
			rest := bs(name, ci + 1, name.length())

			if ei := rest.index_of("="):
				vname := bs(name, 0, ci).trim()
				var from = bs(rest, 0, ei)
				var to = bs(rest, ei + 1, rest.length())

				if not from.contains("%"):
					from = "%" + from
					to = "%" + to

				val := self.lookup(vname)?
				var outw = List[String]()
				for w in words(val):
					outw.append(pat_word(from, to, w))
				return ok(join_sp(outw))

	return self.lookup(name)

fn var Ctx.arg(args: List[String], i: Int) String!:
	a := args.get_or(i, "")
	return self.expand(a)

fn var Ctx.call_func(fname: String, rest: String) String!:
	args := split_args(rest)

	if fname == "subst":
		from := self.arg(args, 0)?
		to := self.arg(args, 1)?
		text := self.arg(args, 2)?
		if from.length() == 0: return ok(text)

		return ok(text.replace(from, to))

	if fname == "patsubst":
		p := self.arg(args, 0)?
		r := self.arg(args, 1)?
		text := self.arg(args, 2)?
		var o = List[String]()
		for w in words(text):
			o.append(pat_word(p, r, w))
		return ok(join_sp(o))

	if fname == "strip":
		t := self.arg(args, 0)?
		return ok(join_sp(words(t)))

	if fname == "findstring":
		f := self.arg(args, 0)?
		t := self.arg(args, 1)?
		if t.contains(f): return ok(f)

		return ok("")

	if fname == "filter" or fname == "filter-out":
		p := words(self.arg(args, 0)?)
		t := words(self.arg(args, 1)?)
		var o = List[String]()
		keep := fname == "filter"
		for w in t:
			if matches_any(p, w) == keep: o.append(w.clone())
		return ok(join_sp(o))

	if fname == "sort":
		t := words(self.arg(args, 0)?)
		s := t.sorted()
		return ok(join_sp(dedup(s)))

	if fname == "word":
		nn := (self.arg(args, 0)?).trim()
		t := words(self.arg(args, 1)?)
		if k := nn.parse_int():
			if k >= 1 and k <= t.length(): return ok(t[k - 1].clone())
		return ok("")

	if fname == "wordlist":
		s := (self.arg(args, 0)?).trim().parse_int()
		e := (self.arg(args, 1)?).trim().parse_int()
		t := words(self.arg(args, 2)?)

		if a := s:
			if b := e:
				if a < 1 or b < a or a > t.length(): return ok("")

				var o = List[String]()
				var k = a

				while k <= b and k <= t.length():
					o.append(t[k - 1].clone())
					k += 1

				return ok(join_sp(o))

		return ok("")

	if fname == "words":
		t := words(self.arg(args, 0)?)
		return ok(f"{t.length()}")

	if fname == "firstword":
		t := words(self.arg(args, 0)?)
		return ok(t.get_or(0, "").clone())

	if fname == "lastword":
		t := words(self.arg(args, 0)?)
		if t.length() == 0: return ok("")

		return ok(t[t.length() - 1].clone())

	if fname == "dir" or fname == "notdir" or fname == "suffix" or fname == "basename":
		t := words(self.arg(args, 0)?)
		var o = List[String]()
		for w in t:
			o.append(word_fn(fname, w))
		return ok(join_sp(o))

	if fname == "addprefix" or fname == "addsuffix":
		p := self.arg(args, 0)?
		t := words(self.arg(args, 1)?)
		var o = List[String]()

		for w in t:
			if fname == "addprefix":
				o.append(p + w)
			else:
				o.append(w + p)

		return ok(join_sp(o))

	if fname == "wildcard":
		pats := words(self.arg(args, 0)?)
		names := self.files.keys().sorted()
		var o = List[String]()

		for p in pats:
			if p.contains("*") or p.contains("?"):
				pc := p.chars()
				for nm in names:
					if glob(pc, 0, nm.chars(), 0): o.append(nm.clone())
			else if self.files.contains(p):
				o.append(p.clone())

		return ok(join_sp(o))

	if fname == "foreach":
		vname := (self.arg(args, 0)?).trim()
		lst := words(self.arg(args, 1)?)
		body := args.get_or(2, "").clone()
		had := self.binds.contains(vname)
		oldv := self.binds.get_or(vname, "").clone()
		var o = List[String]()

		for w in lst:
			self.binds[vname.clone()] = w.clone()
			o.append(self.expand(body)?)

		if had:
			self.binds[vname.clone()] = oldv
		else:
			self.binds.remove(vname)

		return ok(join_sp(o))

	if fname == "if":
		c := (self.arg(args, 0)?).trim()
		if c.length() > 0: return self.arg(args, 1)

		return self.arg(args, 2)

	if fname == "info":
		t := self.arg(args, 0)?
		self.out.append(t)
		return ok("")

	if fname == "error":
		t := self.arg(args, 0)?
		return error(self.fatal(t))

	return ok("")

// ---------- parsing ----------

fn var Ctx.setup(cv: Map[String, String]) Void:
	self.vars = Map[String, Var]()
	self.cmdvars = Set[String]()
	self.rules = Map[String, Rule]()
	self.order = List[String]()
	self.pats = List[PatRule]()
	self.phony = Set[String]()
	self.phony_order = List[String]()
	self.expanding = Set[String]()
	self.binds = Map[String, String]()
	self.auto = Map[String, String]()
	self.cstack = List[Frame]()
	self.rule_open = false
	self.line = 0

	for e in cv.entries():
		self.vars[e.key.clone()] = Var(e.value.clone(), false)
		self.cmdvars.add(e.key.clone())

fn var Ctx.close_rule() Void:
	if not self.rule_open: return

	self.rule_open = false
	if self.r_phony: return

	for t in self.r_targets:
		if t.contains("%"):
			self.pats.append(
				PatRule(
					t.clone(),
					self.r_pre.clone(),
					self.r_oo.clone(),
					self.copy_cmds(self.r_cmds),
				)
			)
			continue

		if not self.rules.contains(t):
			self.rules[t.clone()] = Rule(List[String](), List[String](), List[Cmd]())
			self.order.append(t.clone())

		var warn = false

		if var r = self.rules[t]?:
			for p in self.r_pre: r.pre.append(p.clone())
			for p in self.r_oo: r.oo.append(p.clone())

			if self.r_cmds.length() > 0:
				if r.cmds.length() > 0: warn = true
				r.cmds = List[Cmd]()
				for c in self.r_cmds:
					r.cmds.append(Cmd(c.text.clone(), c.line))

		if warn:
			(
				self
				.out
				.append(
					f"Makefile:{self.r_line}: warning: overriding recipe for target '{t}'"
				)
			)

fn Ctx.copy_cmds(cs: List[Cmd]) List[Cmd]:
	var o = List[Cmd]()
	for c in cs:
		o.append(Cmd(c.text.clone(), c.line))
	return o

fn Ctx.is_active() Bool:
	n := self.cstack.length()
	if n == 0: return true

	return self.cstack[n - 1].active

fn split_cond(s: String) List[String]?:
	// s is "(A,B)" ; returns [A, B] or none
	if not s.starts_with("(") or not s.ends_with(")"): return null

	inner := bs(s, 1, s.length() - 1)
	var parts = List[String]()
	var cur = ""
	var depth = 0

	for c in inner.chars():
		if c == "(" or c == "{":
			depth += 1
			cur += c
		else if c == ")" or c == "}":
			depth -= 1
			cur += c
		else if c == "," and depth == 0:
			parts.append(cur.clone())
			cur = ""
		else:
			cur += c

	parts.append(cur.clone())
	if parts.length() != 2: return null

	return parts

fn var Ctx.parse(src: List[String]) Void!:
	n := src.length()
	var i = 0

	while i < n:
		start := i + 1
		var line = src[i].clone()

		while line.ends_with("\\") and i + 1 < n:
			base := bs(line, 0, line.length() - 1).trim_end()
			line = base + " " + src[i + 1].trim_start()
			i += 1

		i += 1
		self.line = start

		if line.starts_with("\t"):
			var t = line.clone()
			while t.starts_with("\t"):
				t = bs(t, 1, t.length())
			if t.trim().length() == 0: continue
			if not self.is_active(): continue
			if not self.rule_open:
				return error(self.fatal("recipe commences before first target"))

			self.r_cmds.append(Cmd(t, start))
			continue

		// strip comments
		var s = ""
		cs0 := line.chars()
		var k = 0

		while k < cs0.length():
			c := cs0[k]

			if c == "\\" and k + 1 < cs0.length() and cs0[k + 1] == "#":
				s += "#"
				k += 2
				continue

			if c == "#": break

			s += c
			k += 1

		text := s.trim()
		if text.length() == 0: continue

		var fw = text.clone()
		if sp := text.find_char(fn c: c == " " or c == "\t"):
			fw = bs(text, 0, sp)

		rest := bs(text, fw.length(), text.length()).trim()

		if (
			fw == "ifdef"
			or fw == "ifndef"
			or fw == "ifeq"
			or fw == "ifneq"
			or fw == "endif"
			or (fw == "else" and rest.length() == 0)
		):
			self.close_rule()

			if fw == "endif":
				if self.cstack.length() == 0: return error(
					self.fatal("extraneous 'endif'")
				)

				_f := self.cstack.pop()
				continue

			if fw == "else":
				m := self.cstack.length()
				if m == 0: return error(self.fatal("extraneous 'else'"))
				if self.cstack[m - 1].seen_else: return error(
					self.fatal("extraneous 'else'")
				)

				self.cstack[m - 1].seen_else = true
				self.cstack[m - 1].active = (
					self.cstack[m - 1].parent
					and not self.cstack[m - 1].cond
				)
				continue

			parent := self.is_active()
			var cond = false

			if parent:
				if fw == "ifdef" or fw == "ifndef":
					name := (self.expand(rest)?).trim()
					var defined = false
					if v := self.vars.get(name):
						defined = v.val.length() > 0
					cond = if fw == "ifdef": defined else: not defined
				else:
					parts := split_cond(rest)

					if ps := parts:
						a := (self.expand(ps[0].trim())?).trim()
						b := (self.expand(ps[1].trim())?).trim()
						eqv := a == b
						cond = if fw == "ifeq": eqv else: not eqv
					else:
						return error(self.fatal("invalid syntax in conditional"))

			self.cstack.append(Frame(parent and cond, parent, cond, false, start))
			continue

		if not self.is_active(): continue

		self.close_rule()

		cs := text.chars()
		tn := cs.length()
		var eq = -1
		var q = 0

		while q < tn:
			if cs[q] == "=":
				eq = q
				break

			q += 1

		col := find_top(cs, ":", true, 0)

		if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
			var op = "="
			var name_end = eq

			if eq > 0:
				oc := cs[eq - 1]

				if oc == ":" or oc == "?" or oc == "+":
					op = oc.clone()
					name_end = eq - 1

			name := (self.expand(sub(cs, 0, name_end))?).trim()
			if name.length() == 0: return error(self.fatal("empty variable name"))

			val := sub(cs, eq + 1, tn).trim()
			if self.cmdvars.contains(name): continue

			if op == "=":
				self.vars[name.clone()] = Var(val, false)
			else if op == ":":
				ev := self.expand(val)?
				self.vars[name.clone()] = Var(ev, true)
			else if op == "?":
				if not self.vars.contains(name):
					self.vars[name.clone()] = Var(val, false)
			else:
				var old = ""
				var osimple = false
				var had = false

				if v := self.vars.get(name):
					old = v.val.clone()
					osimple = v.simple
					had = true

				if not had:
					self.vars[name.clone()] = Var(val, false)
				else if osimple:
					ev := self.expand(val)?
					joined := if old.length() == 0 or ev.length() == 0: old + ev else: old + " " + ev
					self.vars[name.clone()] = Var(joined, true)
				else:
					joined := if old.length() == 0 or val.length() == 0: old + val else: old + " " + val
					self.vars[name.clone()] = Var(joined, false)

			continue

		if col >= 0:
			tpart := sub(cs, 0, col)
			semi := find_top(cs, ";", false, col + 1)
			var pre_text = ""
			var cmd = ""

			if semi >= 0:
				pre_text = sub(cs, col + 1, semi)
				cmd = sub(cs, semi + 1, tn).trim()
			else:
				pre_text = sub(cs, col + 1, tn)

			targets := words(self.expand(tpart)?)
			pt := self.expand(pre_text)?
			var normal = pt.clone()
			var oo = ""

			if bi := pt.index_of("|"):
				normal = bs(pt, 0, bi)
				oo = bs(pt, bi + 1, pt.length())

			self.rule_open = true
			self.r_targets = targets.clone()
			self.r_pre = words(normal)
			self.r_oo = words(oo)
			self.r_cmds = List[Cmd]()
			self.r_line = start
			self.r_phony = targets.length() == 1 and targets[0] == ".PHONY"

			if self.r_phony:
				for p in self.r_pre:
					if not self.phony.contains(p):
						self.phony.add(p.clone())
						self.phony_order.append(p.clone())

			if cmd.length() > 0:
				self.r_cmds.append(Cmd(cmd, start))
			continue

		ex := self.expand(text)?
		if ex.trim().length() == 0: continue

		return error(self.fatal("missing separator"))

	self.close_rule()

	m := self.cstack.length()

	if m > 0:
		self.line = self.cstack[m - 1].line
		return error(self.fatal("missing 'endif'"))

	self.line = 0
	return ok()

fn Ctx.default_goal() String:
	for t in self.order:
		if not t.starts_with("."): return t.clone()
	return ""

// ---------- resolution ----------

fn Ctx.can_make(name: String, d: Int) Bool:
	if (
		self.files.contains(name)
		or self.rules.contains(name)
		or self.phony.contains(name)
	): return true
	if d >= 8: return false

	return self.find_pat(name, d) >= 0

fn Ctx.find_pat(t: String, d: Int) Int:
	for i in 0..self.pats.length():
		p := self.pats[i]
		if p.cmds.length() == 0: continue

		if st := stem_of(p.pat, t, true):
			var good = true

			for q in p.pre:
				if not self.can_make(subst_pct(q, st), d + 1):
					good = false
					break

			if good:
				for q in p.oo:
					if not self.can_make(subst_pct(q, st), d + 1):
						good = false
						break

			if good: return i

	return -1

fn Ctx.resolve(t: String) Resolved:
	if self.rules.contains(t):
		r := self.rules.get_or(t, Rule(List[String](), List[String](), List[Cmd]()))
		if r.cmds.length() > 0:
			return Resolved(
				true,
				r.pre.clone(),
				r.oo.clone(),
				self.copy_cmds(r.cmds),
				"",
			)

	pi := self.find_pat(t, 0)

	if pi >= 0:
		p := self.pats[pi]
		st := stem_of(p.pat, t, true) or ""
		var pre = List[String]()
		var oo = List[String]()
		for q in p.pre: pre.append(subst_pct(q, st))
		for q in p.oo: oo.append(subst_pct(q, st))

		if r := self.rules.get(t):
			for q in r.pre: pre.append(q.clone())
			for q in r.oo: oo.append(q.clone())

		return Resolved(true, pre, oo, self.copy_cmds(p.cmds), st)

	if r := self.rules.get(t):
		return Resolved(true, r.pre.clone(), r.oo.clone(), List[Cmd](), "")

	return Resolved(false, List[String](), List[String](), List[Cmd](), "")

// ---------- building ----------

fn var Ctx.simulate(cmd: String) Int:
	ws := words(cmd)
	first := ws.get_or(0, "")
	if first == "false": return 1

	if first == "exit":
		if ws.length() > 1: return ws[1].parse_int() or 2
		return 0

	if first == "touch":
		for k in 1..ws.length():
			if not ws[k].starts_with("-"):
				tv := self.tick()
				self.files[ws[k].clone()] = tv

		return 0

	if first == "rm":
		for k in 1..ws.length():
			if not ws[k].starts_with("-"):
				self.files.remove(ws[k].clone())
		return 0

	if first == "cp":
		if ws.length() == 3:
			if not self.files.contains(ws[1]):
				self.out.append(f"cp: cannot stat '{ws[1]}': No such file or directory")
				return 1

			tv := self.tick()
			self.files[ws[2].clone()] = tv

		return 0

	if first == "echo":
		var o = List[String]()
		for k in 1..ws.length():
			o.append(ws[k].replace("'", "").replace("\"", ""))
		self.out.append(join_sp(o))
		return 0

	return 0

fn var Ctx.run_recipe(
	t: String,
	r: Resolved,
	pre: List[String],
	was_in: Bool,
	mt: Int,
) Void!:
	self.ran += 1

	var upd = List[String]()

	for p in pre:
		var inc = not was_in
		if self.memo.get_or(p, false): inc = true
		if was_in:
			if m := self.files.get(p):
				if m > mt: inc = true
		if inc: upd.append(p.clone())

	self.auto = Map[String, String]()
	self.auto["@"] = t.clone()
	self.auto["<"] = r.pre.get_or(0, "").clone()
	self.auto["^"] = join_sp(pre)
	self.auto["?"] = join_sp(upd)
	self.auto["|"] = join_sp(dedup(r.oo))
	self.auto["*"] = r.stem.clone()

	for cmd in r.cmds:
		self.line = cmd.line

		exp := self.expand(cmd.text)?
		var s = exp.trim()
		var silent = false
		var ignore = false

		while s.length() > 0:
			if s.starts_with("@"):
				silent = true
			else if s.starts_with("-"):
				ignore = true
			else if s.starts_with("+"):
				ignore = ignore
			else:
				break

			s = bs(s, 1, s.length()).trim_start()

		if self.dry:
			self.out.append(s)
			continue

		if not silent: self.out.append(s.clone())

		st := self.simulate(s)

		if st != 0:
			if ignore:
				(
					self
					.out
					.append(
						f"make: [Makefile:{cmd.line}: {t}] Error {st} (ignored)"
					)
				)
			else:
				self.auto = Map[String, String]()
				return error(Error(f"make: *** [Makefile:{cmd.line}: {t}] Error {st}"))

	self.auto = Map[String, String]()
	self.line = 0

	if not self.dry and not self.phony.contains(t):
		tv := self.tick()
		self.files[t.clone()] = tv

	return ok()

fn var Ctx.update(t: String, needed: String) Bool!:
	if self.memo.contains(t): return ok(self.memo.get_or(t, false))

	if self.bstack.contains(t):
		var path = List[String]()
		var on = false

		for x in self.bstack:
			if x == t: on = true
			if on: path.append(x.clone())

		path.append(t.clone())
		return error(
			Error(
				f"make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."
			)
		)

	r := self.resolve(t)

	if not r.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)

		if self.phony.contains(t):
			self.memo[t.clone()] = true
			return ok(true)

		if needed.length() > 0:
			return error(
				Error(
					f"make: *** No rule to make target '{t}', needed by '{needed}'.  Stop."
				)
			)

		return error(Error(f"make: *** No rule to make target '{t}'.  Stop."))

	self.bstack.append(t.clone())

	was_in := self.files.contains(t)
	mt := self.files.get_or(t, 0)
	pre := dedup(r.pre)
	var any = false
	var newer = false

	for p in pre:
		ch := self.update(p, t)?
		if ch: any = true
		if was_in:
			if m := self.files.get(p):
				if m > mt: newer = true

	for p in dedup(r.oo):
		_c := self.update(p, t)?

	_x := self.bstack.pop()
	var changed = false

	if self.phony.contains(t) or not self.files.contains(t) or any or newer:
		changed = true
		if r.cmds.length() > 0:
			self.run_recipe(t, r, pre, was_in, mt)?

	self.memo[t.clone()] = changed
	return ok(changed)

fn var Ctx.do_build(goals_in: List[String]) Void!:
	var goals = goals_in.clone()

	if goals.length() == 0:
		d := self.default_goal()
		if d.length() == 0: return error(Error("make: *** No targets.  Stop."))

		goals.append(d)

	self.memo = Map[String, Bool]()
	self.bstack = List[String]()
	self.ran = 0

	for g in goals:
		ran0 := self.ran
		_ch := self.update(g, "")?

		if self.ran == ran0:
			r := self.resolve(g)

			if (
				r.cmds.length() > 0
				or (
					self.files.contains(g)
					and not self.phony.contains(g)
				)
			):
				self.out.append(f"make: '{g}' is up to date.")
			else:
				self.out.append(f"make: Nothing to be done for '{g}'.")

	return ok()

fn var Ctx.deps_visit(t: String, path: List[String]) Void!:
	r := self.resolve(t)
	var all = dedup(r.pre)
	for p in dedup(r.oo): all.append(p.clone())

	var np = path.clone()
	np.append(t.clone())

	for p in all:
		if np.contains(p):
			var cyc = List[String]()
			var on = false

			for x in np:
				if x == p: on = true
				if on: cyc.append(x.clone())

			cyc.append(p.clone())
			return error(
				Error(
					f"make: *** Circular dependency detected: {cyc.join(" -> ")}.  Stop."
				)
			)

		if self.dseen.contains(p): continue

		self.dseen.add(p.clone())
		self.deps_visit(p, np)?
		self.dres.append(p.clone())

	return ok()

// ---------- driver ----------

fn var Ctx.start(cv: Map[String, String], src: List[String]) Bool:
	self.setup(cv)

	res := self.parse(src)

	if _u := res:
		self.line = 0
		return true
	else:
		self.out.append(res.err().message)
		self.line = 0
		return false

fn fmt_rule(name: String, pre: List[String], oo: List[String]) String:
	var s = name + ": " + join_sp(pre)
	if oo.length() > 0:
		s += " | " + join_sp(oo)
	return s

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void!:
	b := read_all(stdin())?
	text := b.decode_utf8() or ""
	all := text.lines()
	var sec = 0
	var mk = List[String]()
	var tbl = List[String]()
	var reqs = List[String]()

	for l in all:
		if sec < 2 and l == "====":
			sec += 1
			continue

		if sec == 0: mk.append(l.clone())
		else if sec == 1: tbl.append(l.clone())
		else: reqs.append(l.clone())

	var ctx = Ctx()

	for l in tbl:
		ws := words(l)

		if ws.length() == 2:
			if m := ws[1].parse_int():
				if m >= 0:
					ctx.files[ws[0].clone()] = m
					if m > ctx.clock: ctx.clock = m

	for rl in reqs:
		tl := rl.trim()
		if tl.length() == 0 or tl.starts_with("#"): continue

		ctx.out.append("> " + rl.trim_end())

		rw := words(tl)
		cmd := rw[0].clone()
		var rest = List[String]()
		for k in 1..rw.length(): rest.append(rw[k].clone())

		if cmd == "build" or cmd == "dry" or cmd == "deps" or cmd == "targets":
			var cv = Map[String, String]()
			var goals = List[String]()

			for a in rest:
				ei := a.index_of("=")
				var isv = false

				if e := ei:
					if e > 0:
						cv[bs(a, 0, e)] = bs(a, e + 1, a.length())
						isv = true

				if not isv: goals.append(a.clone())

			if not ctx.start(cv, mk): continue

			if cmd == "build" or cmd == "dry":
				ctx.dry = cmd == "dry"

				r := ctx.do_build(goals)

				if _u := r:
					void
				else:
					ctx.out.append(r.err().message)

				ctx.dry = false
			else if cmd == "deps":
				if goals.length() != 1:
					ctx.out.append("usage: deps TARGET")
					continue

				ctx.dseen = Set[String]()
				ctx.dres = List[String]()

				r := ctx.deps_visit(goals[0], List[String]())

				if _u := r:
					if ctx.dres.length() == 0:
						ctx.out.append("(no prerequisites)")
					for x in ctx.dres: ctx.out.append(x.clone())
				else:
					ctx.out.append(r.err().message)
			else:
				d := ctx.default_goal()
				if d.length() > 0: ctx.out.append("default: " + d)
				for t in ctx.order:
					if r := ctx.rules.get(t):
						ctx.out.append(fmt_rule(t, r.pre, r.oo))
				for p in ctx.pats:
					ctx.out.append(fmt_rule("pattern " + p.pat, p.pre, p.oo))
				if ctx.phony_order.length() > 0:
					ctx.out.append("phony: " + join_sp(ctx.phony_order))
		else if cmd == "expand":
			if not ctx.start(Map[String, String](), mk): continue

			rr := bs(tl, 6, tl.length()).trim()
			r := ctx.expand(rr)

			if v := r:
				ctx.out.append(f"[{v}]")
			else:
				ctx.out.append(r.err().message)
		else if cmd == "files":
			names := ctx.files.keys().sorted()
			if names.length() == 0:
				ctx.out.append("(no files)")
			for nm in names:
				ctx.out.append(f"{nm} {ctx.files.get_or(nm, 0)}")
		else if cmd == "touch":
			if rest.length() == 1:
				tv := ctx.tick()
				ctx.files[rest[0].clone()] = tv
			else if rest.length() == 2:
				if nn := rest[1].parse_int():
					ctx.files[rest[0].clone()] = nn
					if nn > ctx.clock: ctx.clock = nn
				else:
					ctx.out.append("bad request")
			else:
				ctx.out.append("bad request")
		else if cmd == "rm":
			for f in rest: ctx.files.remove(f)
		else:
			ctx.out.append(f"unknown request: {cmd}")

	for o in ctx.out:
		print(o)
