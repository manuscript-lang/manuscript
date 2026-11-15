import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Var:
	value: String
	simple: Bool

type Rule:
	name: String
	prereqs: List[String] = List[String]()
	oo: List[String] = List[String]()
	recipe: List[String] = List[String]()
	rlines: List[Int] = List[Int]()
	stem: String = ""
	found: Bool = false

type Cond:
	parent_active: Bool
	cond: Bool
	seen_else: Bool
	line: Int

fn Rule.dup() Rule:
	return Rule(name: self.name.clone(), prereqs: self.prereqs.clone(), oo: self.oo.clone(), recipe: self.recipe.clone(), rlines: self.rlines.clone(), stem: self.stem.clone(), found: self.found)

type Ctx:
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	vars: Map[String, Var] = Map[String, Var]()
	cmdnames: Set[String] = Set[String]()
	rules: Map[String, Rule] = Map[String, Rule]()
	order: List[String] = List[String]()
	prules: List[Rule] = List[Rule]()
	phony: List[String] = List[String]()
	phony_set: Set[String] = Set[String]()
	default_goal: String = ""
	cur_line: Int = 0
	autos: Map[String, String] = Map[String, String]()
	binds: Map[String, String] = Map[String, String]()
	expanding: Set[String] = Set[String]()
	done: Map[String, Bool] = Map[String, Bool]()
	stack: List[String] = List[String]()
	runs: Int = 0
	dry: Bool = false
	conds: List[Cond] = List[Cond]()
	open: Bool = false
	o_targets: List[String] = List[String]()
	o_rule: Rule = Rule(name: "")
	o_line: Int = 0
	dout: List[String] = List[String]()
	dvis: Set[String] = Set[String]()

// ---------- pure helpers ----------

fn sub(s: String, a: Int, b: Int) String:
	if b <= a: return ""
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

fn is_ws(c: String) Bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

fn pat_match(pat: String, word: String) String?:
	if idx := pat.index_of("%"):
		pre := sub(pat, 0, idx)
		suf := sub(pat, idx + 1, pat.length())
		if word.length() < pre.length() + suf.length(): return none
		if not word.starts_with(pre): return none
		if not word.ends_with(suf): return none
		return sub(word, pre.length(), word.length() - suf.length())
	if pat == word: return ""
	return none

fn subst_pct(s: String, stem: String) String:
	if idx := s.index_of("%"):
		return sub(s, 0, idx) + stem + sub(s, idx + 1, s.length())
	return s.clone()

fn dedupe(xs: List[String]) List[String]:
	var seen = Set[String]()
	var out = List[String]()
	for x in xs:
		if seen.contains(x): continue
		seen.add(x.clone())
		out.append(x.clone())
	return out

fn split_args(text: String) List[String]:
	var out = List[String]()
	var cur = ""
	var depth = 0
	for c in text.chars():
		if c == "(" or c == "\{":
			depth += 1
		else if c == ")" or c == "\}":
			depth -= 1
		if c == "," and depth <= 0:
			out.append(cur)
			cur = ""
		else:
			cur += c
	out.append(cur)
	return out

fn glob(p: List[String], pi: Int, s: List[String], si: Int) Bool:
	if pi == p.length(): return si == s.length()
	c := p.get(pi, "")
	if c == "*":
		var k = si
		while true:
			if glob(p, pi + 1, s, k): return true
			if k >= s.length(): return false
			if s.get(k, "") == "/": return false
			k += 1
		return false
	if si >= s.length(): return false
	sc := s.get(si, "")
	if c == "?":
		if sc == "/": return false
		return glob(p, pi + 1, s, si + 1)
	if sc != c: return false
	return glob(p, pi + 1, s, si + 1)

fn strip_comment(text: String) String:
	cs := text.chars()
	n := cs.length()
	var out = ""
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if c == "\\" and i + 1 < n and cs.get(i + 1, "") == "#":
			out += "#"
			i += 2
			continue
		if c == "#": break
		out += c
		i += 1
	return out

fn find_col(cs: List[String]) Int:
	n := cs.length()
	var depth = 0
	var i = 0
	while i < n:
		c := cs.get(i, "")
		nx := cs.get(i + 1, "")
		if c == "$" and nx == "$":
			i += 2
			continue
		if c == "$" and (nx == "(" or nx == "\{"):
			depth += 1
			i += 2
			continue
		if depth > 0:
			if c == "(" or c == "\{":
				depth += 1
			else if c == ")" or c == "\}":
				depth -= 1
		else if c == ":":
			return i
		else if c == ";":
			return -1
		i += 1
	return -1

fn join_words(xs: List[String]) String:
	return xs.join(" ")

fn is_func(name: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(name)

fn split_dir(w: String) Int:
	if i := w.last_index_of("/"):
		return i
	return -1

fn ext_index(w: String) Int:
	d := split_dir(w)
	comp := sub(w, d + 1, w.length())
	if i := comp.last_index_of("."):
		return d + 1 + i
	return -1

// ---------- Ctx ----------

fn Ctx.fatal(msg: String) Error:
	if self.cur_line > 0:
		return Error("Makefile:{self.cur_line}: *** {msg}.  Stop.")
	return Error("make: *** {msg}.  Stop.")

fn var Ctx.tick() Int:
	self.clock += 1
	return self.clock

fn var Ctx.reset() Unit:
	self.vars = Map[String, Var]()
	self.cmdnames = Set[String]()
	self.rules = Map[String, Rule]()
	self.order = List[String]()
	self.prules = List[Rule]()
	self.phony = List[String]()
	self.phony_set = Set[String]()
	self.default_goal = ""
	self.cur_line = 0
	self.autos = Map[String, String]()
	self.binds = Map[String, String]()
	self.expanding = Set[String]()
	self.done = Map[String, Bool]()
	self.stack = List[String]()
	self.runs = 0
	self.dry = false
	self.conds = List[Cond]()
	self.open = false
	self.o_targets = List[String]()
	self.o_rule = Rule(name: "")
	self.o_line = 0
	self.dout = List[String]()
	self.dvis = Set[String]()

fn var Ctx.lookup(name: String) String!:
	if b := self.binds.get(name):
		return ok(b.clone())
	if a := self.autos.get(name):
		return ok(a.clone())
	if not self.vars.contains(name): return ok("")
	value := self.vars[name].value.clone()
	simple := self.vars[name].simple
	if simple: return ok(value)
	if self.expanding.contains(name):
		return error(self.fatal("Recursive variable '{name}' references itself (eventually)"))
	self.expanding.add(name.clone())
	r := self.expand(value)
	self.expanding.remove(name)
	return r

fn var Ctx.expand(text: String) String!:
	cs := text.chars()
	n := cs.length()
	var out = ""
	var i = 0
	while i < n:
		c := cs.get(i, "")
		if c != "$":
			out += c
			i += 1
			continue
		if i + 1 >= n: break
		d := cs.get(i + 1, "")
		if d == "$":
			out += "$"
			i += 2
		else if d == "(" or d == "\{":
			closer := if d == "(": ")" else: "\}"
			var j = i + 2
			var depth = 1
			var found = false
			while j < n:
				cj := cs.get(j, "")
				if cj == d:
					depth += 1
				else if cj == closer:
					depth -= 1
					if depth == 0:
						found = true
						break
				j += 1
			if not found:
				return error(self.fatal("unterminated variable reference"))
			inner := cjoin(cs, i + 2, j)
			out += self.expand_ref(inner)?
			i = j + 1
		else:
			out += self.lookup(d)?
			i += 2
	return ok(out)

fn var Ctx.expand_ref(inner: String) String!:
	// function call?
	var k = -1
	var idx = 0
	for c in inner.chars():
		if c == " " or c == "\t":
			k = idx
			break
		idx += 1
	if k > 0:
		fname := sub(inner, 0, k)
		if is_func(fname):
			return self.call_func(fname, sub(inner, k + 1, inner.length()))
	name := (self.expand(inner)?).trim()
	if ci := name.index_of(":"):
		if ci > 0:
			after := sub(name, ci + 1, name.length())
			if ei := after.index_of("="):
				vname := sub(name, 0, ci)
				var from = sub(after, 0, ei)
				var to = sub(after, ei + 1, after.length())
				if not from.contains("%"):
					from = "%" + from
					to = "%" + to
				val := self.lookup(vname)?
				return ok(patsubst(from, to, val))
	return self.lookup(name)

fn patsubst(pattern: String, repl: String, text: String) String:
	var out = List[String]()
	for w in text.fields():
		if stem := pat_match(pattern, w):
			if repl.contains("%"):
				out.append(subst_pct(repl, stem))
			else:
				out.append(repl.clone())
		else:
			out.append(w.clone())
	return out.join(" ")

fn var Ctx.arg(a: List[String], i: Int) String!:
	if i >= a.length(): return ok("")
	return self.expand(a.get(i, "").trim())

fn is_pos_int(s: String) Int:
	if v := s.trim().parse_int():
		return v
	return -1

fn var Ctx.call_func(name: String, rest: String) String!:
	a := split_args(rest)
	if name == "foreach":
		var_name := (self.arg(a, 0)?).trim()
		lst := self.arg(a, 1)?
		body := a.get(2, "").trim()
		var results = List[String]()
		saved := self.binds.get(var_name)
		had := saved.is_some()
		old := saved.get("")
		for w in lst.fields():
			self.binds[var_name.clone()] = w.clone()
			r := self.expand(body)
			if r.is_error():
				return r
			results.append(r.get_or_else(fn e: ""))
		if had:
			self.binds[var_name.clone()] = old
		else:
			self.binds.remove(var_name)
		return ok(results.join(" "))
	if name == "if":
		cond := (self.arg(a, 0)?).trim()
		if cond != "":
			return self.arg(a, 1)
		return self.arg(a, 2)
	if name == "info":
		t := self.arg(a, 0)?
		print(t)
		return ok("")
	if name == "error":
		t := self.arg(a, 0)?
		return error(self.fatal(t))
	if name == "subst":
		from := self.arg(a, 0)?
		to := self.arg(a, 1)?
		text := self.arg(a, 2)?
		if from == "": return ok(text)
		return ok(text.replace(from, to))
	if name == "patsubst":
		p := self.arg(a, 0)?
		r := self.arg(a, 1)?
		text := self.arg(a, 2)?
		return ok(patsubst(p, r, text))
	if name == "strip":
		return ok((self.arg(a, 0)?).fields().join(" "))
	if name == "findstring":
		f := self.arg(a, 0)?
		t := self.arg(a, 1)?
		if t.contains(f): return ok(f)
		return ok("")
	if name == "filter" or name == "filter-out":
		pats := (self.arg(a, 0)?).fields()
		words := (self.arg(a, 1)?).fields()
		var out = List[String]()
		for w in words:
			var m = false
			for p in pats:
				if _pm := pat_match(p, w):
					m = true
			if m == (name == "filter"):
				out.append(w.clone())
		return ok(out.join(" "))
	if name == "sort":
		words := (self.arg(a, 0)?).fields().sorted()
		return ok(dedupe(words).join(" "))
	if name == "word":
		n := is_pos_int(self.arg(a, 0)?)
		words := (self.arg(a, 1)?).fields()
		if n < 1 or n > words.length(): return ok("")
		return ok(words.get(n - 1, ""))
	if name == "wordlist":
		s := is_pos_int(self.arg(a, 0)?)
		e := is_pos_int(self.arg(a, 1)?)
		words := (self.arg(a, 2)?).fields()
		if s < 1 or e < s or s > words.length(): return ok("")
		var en = e
		if en > words.length(): en = words.length()
		var out = List[String]()
		var i = s
		while i <= en:
			out.append(words.get(i - 1, ""))
			i += 1
		return ok(out.join(" "))
	if name == "words":
		return ok("{(self.arg(a, 0)?).fields().length()}")
	if name == "firstword":
		return ok((self.arg(a, 0)?).fields().get(0, ""))
	if name == "lastword":
		ws := (self.arg(a, 0)?).fields()
		return ok(ws.get(ws.length() - 1, ""))
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		var out = List[String]()
		for w in (self.arg(a, 0)?).fields():
			if name == "dir":
				d := split_dir(w)
				if d >= 0:
					out.append(sub(w, 0, d + 1))
				else:
					out.append("./")
			else if name == "notdir":
				d := split_dir(w)
				r := sub(w, d + 1, w.length())
				if r != "": out.append(r)
			else if name == "suffix":
				e := ext_index(w)
				if e >= 0: out.append(sub(w, e, w.length()))
			else:
				e := ext_index(w)
				if e >= 0:
					out.append(sub(w, 0, e))
				else:
					out.append(w.clone())
		return ok(out.join(" "))
	if name == "addprefix" or name == "addsuffix":
		p := self.arg(a, 0)?
		var out = List[String]()
		for w in (self.arg(a, 1)?).fields():
			if name == "addprefix":
				out.append(p + w)
			else:
				out.append(w + p)
		return ok(out.join(" "))
	if name == "wildcard":
		var out = List[String]()
		names := self.files.keys().sorted()
		for p in (self.arg(a, 0)?).fields():
			pc := p.chars()
			for f in names:
				if glob(pc, 0, f.chars(), 0):
					out.append(f.clone())
		return ok(out.join(" "))
	return ok("")

// ---------- parsing ----------

fn Ctx.is_active() Bool:
	if self.conds.length() == 0: return true
	t := self.conds.length() - 1
	return self.conds[t].parent_active and self.conds[t].cond

fn var Ctx.close_rule() Unit:
	if not self.open: return
	self.open = false
	self.finish_rule(self.o_targets.clone(), self.o_rule.dup(), self.o_line)

fn var Ctx.finish_rule(targets: List[String], rule: Rule, line: Int) Unit:
	for t in targets:
		if t.contains("%"):
			var pr = rule.dup()
			pr.name = t.clone()
			self.prules.append(pr)
		else:
			if not self.rules.contains(t):
				self.rules[t.clone()] = Rule(name: t.clone())
			for p in rule.prereqs:
				self.rules[t].prereqs.append(p.clone())
			for p in rule.oo:
				self.rules[t].oo.append(p.clone())
			if rule.recipe.length() > 0:
				if self.rules[t].recipe.length() > 0:
					print("Makefile:{line}: warning: overriding recipe for target '{t}'")
				self.rules[t].recipe = rule.recipe.clone()
				self.rules[t].rlines = rule.rlines.clone()

fn var Ctx.assign(name: String, op: String, value: String) Unit!:
	if self.cmdnames.contains(name): return ok(unit)
	if op == "=":
		self.vars[name] = Var(value.clone(), false)
	else if op == ":=":
		v := self.expand(value)?
		self.vars[name] = Var(v, true)
	else if op == "?=":
		if not self.vars.contains(name):
			self.vars[name] = Var(value.clone(), false)
	else:
		if not self.vars.contains(name):
			self.vars[name] = Var(value.clone(), false)
		else:
			old := self.vars[name].value.clone()
			simple := self.vars[name].simple
			var add = value.clone()
			if simple:
				add = self.expand(value)?
			var nv = ""
			if old == "":
				nv = add
			else if add == "":
				nv = old
			else:
				nv = old + " " + add
			self.vars[name] = Var(nv, simple)
	return ok(unit)

fn var Ctx.eval_cond(word: String, rest: String) Bool!:
	if word == "ifdef" or word == "ifndef":
		name := (self.expand(rest)?).trim()
		var defined = false
		if self.vars.contains(name):
			defined = self.vars[name].value != ""
		return ok(defined == (word == "ifdef"))
	r := rest.trim()
	if not (r.starts_with("(") and r.ends_with(")")) or r.length() < 2:
		return error(self.fatal("invalid syntax in conditional"))
	inner := sub(r, 1, r.length() - 1)
	var depth = 0
	var commas = 0
	var left = ""
	var right = ""
	for c in inner.chars():
		if c == "(" or c == "\{":
			depth += 1
		else if c == ")" or c == "\}":
			depth -= 1
		if c == "," and depth == 0:
			commas += 1
		else if commas == 0:
			left += c
		else:
			right += c
	if commas != 1:
		return error(self.fatal("invalid syntax in conditional"))
	l := (self.expand(left.trim())?).trim()
	rr := (self.expand(right.trim())?).trim()
	return ok((l == rr) == (word == "ifeq"))

fn var Ctx.process(text: String, no: Int) Unit!:
	self.cur_line = no
	if text.starts_with("\t"):
		if not self.is_active(): return ok(unit)
		body := text.trim_start_chars("\t")
		if body.trim() == "": return ok(unit)
		if not self.open:
			return error(self.fatal("recipe commences before first target"))
		self.o_rule.recipe.append(body.clone())
		self.o_rule.rlines.append(no)
		return ok(unit)
	line := strip_comment(text).trim()
	if line == "": return ok(unit)
	fw := line.fields().get(0, "")
	rest := sub(line, fw.length(), line.length()).trim()
	if fw == "ifdef" or fw == "ifndef" or fw == "ifeq" or fw == "ifneq":
		self.close_rule()
		parent := self.is_active()
		var val = false
		if parent:
			val = self.eval_cond(fw, rest)?
		self.conds.append(Cond(parent, val, false, no))
		return ok(unit)
	if line == "else":
		self.close_rule()
		if self.conds.length() == 0:
			return error(self.fatal("extraneous 'else'"))
		t := self.conds.length() - 1
		top := self.conds[t].seen_else
		if top:
			return error(self.fatal("extraneous 'else'"))
		pa := self.conds[t].parent_active
		cv := self.conds[t].cond
		ln := self.conds[t].line
		self.conds.replace(t, Cond(pa, not cv, true, ln))
		return ok(unit)
	if fw == "endif":
		self.close_rule()
		if self.conds.length() == 0:
			return error(self.fatal("extraneous 'endif'"))
		_x := self.conds.pop()
		return ok(unit)
	if not self.is_active(): return ok(unit)
	self.close_rule()
	cs := line.chars()
	n := cs.length()
	var eq = -1
	var ii = 0
	while ii < n:
		if cs.get(ii, "") == "=":
			eq = ii
			break
		ii += 1
	col := find_col(cs)
	if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
		var op = "="
		var name_end = eq
		if eq >= 1:
			pc := cs.get(eq - 1, "")
			if pc == ":" or pc == "?" or pc == "+":
				op = pc + "="
				name_end = eq - 1
		name := (self.expand(cjoin(cs, 0, name_end))?).trim()
		if name == "":
			return error(self.fatal("empty variable name"))
		value := cjoin(cs, eq + 1, n).trim()
		self.assign(name, op, value)?
		return ok(unit)
	if col >= 0:
		tgt_text := cjoin(cs, 0, col)
		var prest = cjoin(cs, col + 1, n)
		var cmd = ""
		if si := prest.index_of(";"):
			cmd = sub(prest, si + 1, prest.length()).trim()
			prest = sub(prest, 0, si)
		targets := (self.expand(tgt_text)?).fields()
		ptext := self.expand(prest)?
		var normal = List[String]()
		var oo = List[String]()
		if bi := ptext.index_of("|"):
			normal = sub(ptext, 0, bi).fields()
			oo = sub(ptext, bi + 1, ptext.length()).fields()
		else:
			normal = ptext.fields()
		var rule = Rule(name: "", prereqs: normal, oo: oo)
		if cmd != "":
			rule.recipe.append(cmd)
			rule.rlines.append(no)
		self.open = true
		self.o_line = no
		if targets.length() == 1 and targets.get(0, "") == ".PHONY":
			for p in rule.prereqs:
				if not self.phony_set.contains(p):
					self.phony_set.add(p.clone())
					self.phony.append(p.clone())
			self.o_targets = List[String]()
			self.o_rule = rule.dup()
			return ok(unit)
		for t in targets:
			if t.contains("%"): continue
			if not self.order.contains(t):
				self.order.append(t.clone())
				if self.default_goal == "" and not t.starts_with("."):
					self.default_goal = t.clone()
		self.o_targets = targets
		self.o_rule = rule.dup()
		return ok(unit)
	e := self.expand(line)?
	if e.trim() != "":
		return error(self.fatal("missing separator"))
	return ok(unit)

fn var Ctx.parse(lines: List[String]) Unit!:
	n := lines.length()
	var i = 0
	while i < n:
		start := i + 1
		var cur = lines.get(i, "")
		while cur.ends_with("\\"):
			body := sub(cur, 0, cur.length() - 1).trim_end()
			if i + 1 < n:
				i += 1
				cur = body + " " + lines.get(i, "").trim_start()
			else:
				cur = body
				break
		self.process(cur, start)?
		i += 1
	self.cur_line = 0
	self.close_rule()
	if self.conds.length() > 0:
		self.cur_line = self.conds[self.conds.length() - 1].line
		return error(self.fatal("missing 'endif'"))
	return ok(unit)

// ---------- building ----------

fn Ctx.find_pattern(t: String, depth: Int) Int:
	var idx = 0
	for pr in self.prules:
		if pr.recipe.length() > 0:
			if stem := pat_match(pr.name, t):
				if stem != "":
					var ok_all = true
					for p in pr.prereqs:
						if not self.can_make(subst_pct(p, stem), depth):
							ok_all = false
					for p in pr.oo:
						if not self.can_make(subst_pct(p, stem), depth):
							ok_all = false
					if ok_all: return idx
		idx += 1
	return -1

fn Ctx.can_make(name: String, depth: Int) Bool:
	if self.files.contains(name): return true
	if self.rules.contains(name): return true
	if self.phony_set.contains(name): return true
	if depth < 8:
		return self.find_pattern(name, depth + 1) >= 0
	return false

fn Ctx.resolve(t: String) Rule:
	has_explicit := self.rules.contains(t)
	if has_explicit and self.rules[t].recipe.length() > 0:
		var r = self.rules[t].dup()
		r.found = true
		return r
	idx := self.find_pattern(t, 0)
	if idx >= 0:
		pr := self.prules[idx]
		stem := pat_match(pr.name, t).get("")
		var r = Rule(name: t.clone())
		for p in pr.prereqs:
			r.prereqs.append(subst_pct(p, stem))
		for p in pr.oo:
			r.oo.append(subst_pct(p, stem))
		if has_explicit:
			for p in self.rules[t].prereqs:
				r.prereqs.append(p.clone())
			for p in self.rules[t].oo:
				r.oo.append(p.clone())
		r.recipe = pr.recipe.clone()
		r.rlines = pr.rlines.clone()
		r.stem = stem
		r.found = true
		return r
	if has_explicit:
		var r = self.rules[t].dup()
		r.found = true
		return r
	return Rule(name: t.clone())

fn Ctx.path_error(t: String) Error:
	var k = 0
	for i in 0..self.stack.length():
		if self.stack[i] == t:
			k = i
			break
	var parts = List[String]()
	for i in k..self.stack.length():
		parts.append(self.stack[i].clone())
	parts.append(t.clone())
	return Error("make: *** Circular dependency detected: {parts.join(" -> ")}.  Stop.")

fn var Ctx.update(t: String, needed: String) Bool!:
	if r := self.done.get(t): return ok(r)
	if self.stack.contains(t):
		return error(self.path_error(t))
	res := self.resolve(t)
	if not res.found:
		if self.files.contains(t):
			self.done[t.clone()] = false
			return ok(false)
		if self.phony_set.contains(t):
			self.done[t.clone()] = true
			return ok(true)
		if needed == "":
			return error(Error("make: *** No rule to make target '{t}'.  Stop."))
		return error(Error("make: *** No rule to make target '{t}', needed by '{needed}'.  Stop."))
	existed := self.files.contains(t)
	mt := self.files.get_or(t, 0)
	self.stack.append(t.clone())
	var changed = false
	var newer = false
	for p in dedupe(res.prereqs):
		c := self.update(p, t)?
		if c: changed = true
		if existed:
			if pm := self.files.get(p):
				if pm > mt: newer = true
	for p in dedupe(res.oo):
		_c := self.update(p, t)?
	_t := self.stack.pop()
	phony := self.phony_set.contains(t)
	rebuild := phony or not self.files.contains(t) or changed or newer
	if rebuild:
		if res.recipe.length() > 0:
			self.run_recipe(t, res, existed, mt)?
	self.done[t.clone()] = rebuild
	return ok(rebuild)

fn var Ctx.run_recipe(t: String, res: Rule, existed: Bool, mt: Int) Unit!:
	self.runs += 1
	uniq := dedupe(res.prereqs)
	var changed_list = List[String]()
	for p in uniq:
		var inc = false
		if not existed:
			inc = true
		else if self.done.get_or(p, false):
			inc = true
		else if self.files.get_or(p, -1) > mt and self.files.contains(p):
			inc = true
		if inc: changed_list.append(p.clone())
	self.autos = Map[String, String]()
	self.autos["@"] = t.clone()
	self.autos["<"] = res.prereqs.get(0, "")
	self.autos["^"] = uniq.join(" ")
	self.autos["?"] = changed_list.join(" ")
	self.autos["|"] = dedupe(res.oo).join(" ")
	self.autos["*"] = res.stem.clone()
	var k = 0
	while k < res.recipe.length():
		lno := res.rlines.get(k, 0)
		self.cur_line = lno
		er := self.expand(res.recipe.get(k, ""))
		if er.is_error():
			self.autos = Map[String, String]()
			return error(er.err())
		self.cur_line = 0
		text := er.get_or_else(fn e: "").trim()
		k += 1
		var silent = false
		var ignore = false
		cs := text.chars()
		var p = 0
		while p < cs.length():
			c := cs.get(p, "")
			if c == "@":
				silent = true
			else if c == "-":
				ignore = true
			else if c == "+" or is_ws(c):
				p += 0
			else:
				break
			p += 1
		cmd := cjoin(cs, p, cs.length())
		if cmd == "": continue
		if self.dry:
			print(cmd)
			continue
		if not silent: print(cmd)
		words := cmd.fields()
		w0 := words.get(0, "")
		var status = 0
		if w0 == "false":
			status = 1
		else if w0 == "exit":
			if words.length() > 1:
				if v := words.get(1, "").parse_int():
					status = v
				else:
					status = 2
		else if w0 == "touch":
			for w in tail(words):
				if not w.starts_with("-"):
					tk := self.tick()
					self.files[w.clone()] = tk
		else if w0 == "rm":
			for w in tail(words):
				if not w.starts_with("-"):
					self.files.remove(w)
		else if w0 == "cp":
			if words.length() == 3:
				src := words.get(1, "")
				if self.files.contains(src):
					tk := self.tick()
					self.files[words.get(2, "")] = tk
				else:
					print("cp: cannot stat '{src}': No such file or directory")
					status = 1
		else if w0 == "echo":
			var parts = List[String]()
			for w in tail(words):
				parts.append(w.replace("'", "").replace("\"", ""))
			print(parts.join(" "))
		if status != 0:
			if ignore:
				print("make: [Makefile:{lno}: {t}] Error {status} (ignored)")
			else:
				self.autos = Map[String, String]()
				return error(Error("make: *** [Makefile:{lno}: {t}] Error {status}"))
	self.autos = Map[String, String]()
	if not self.dry:
		if not self.phony_set.contains(t):
			tk := self.tick()
			self.files[t.clone()] = tk
	return ok(unit)

fn var Ctx.do_build(goals: List[String], dry: Bool) Unit!:
	self.dry = dry
	var gs = goals.clone()
	if gs.length() == 0:
		if self.default_goal == "":
			return error(Error("make: *** No targets.  Stop."))
		gs.append(self.default_goal.clone())
	for g in gs:
		before := self.runs
		_r := self.update(g, "")?
		if self.runs == before:
			res := self.resolve(g)
			if (res.found and res.recipe.length() > 0) or (not self.phony_set.contains(g) and self.files.contains(g)):
				print("make: '{g}' is up to date.")
			else:
				print("make: Nothing to be done for '{g}'.")
	return ok(unit)

fn var Ctx.visit(t: String, root: Bool) Unit!:
	if self.stack.contains(t):
		return error(self.path_error(t))
	if not root and self.dvis.contains(t): return ok(unit)
	res := self.resolve(t)
	self.stack.append(t.clone())
	for p in dedupe(res.prereqs):
		self.visit(p, false)?
	for p in dedupe(res.oo):
		self.visit(p, false)?
	_t := self.stack.pop()
	if not root:
		self.dvis.add(t.clone())
		self.dout.append(t.clone())
	return ok(unit)

fn Ctx.show_targets() Unit:
	if self.default_goal != "":
		print("default: {self.default_goal}")
	for t in self.order:
		r := self.rules.get(t)
		if rr := r:
			print(fmt_rule("{t}:", rr))
		else:
			print("{t}:")
	for pr in self.prules:
		print(fmt_rule("pattern {pr.name}:", pr))
	if self.phony.length() > 0:
		print("phony: {self.phony.join(" ")}")

fn fmt_rule(head: String, r: Rule) String:
	var s = head + " " + r.prereqs.join(" ")
	if r.oo.length() > 0:
		s += " | " + r.oo.join(" ")
	return s

// ---------- requests ----------

fn var Ctx.make_request(word: String, args: List[String], mf: List[String]) Unit:
	self.reset()
	var goals = List[String]()
	for a in args:
		if ei := a.index_of("="):
			if ei > 0:
				name := sub(a, 0, ei)
				self.vars[name.clone()] = Var(sub(a, ei + 1, a.length()), false)
				self.cmdnames.add(name)
				continue
		goals.append(a.clone())
	if word == "deps" and goals.length() != 1:
		print("usage: deps TARGET")
		return
	r := self.make_run(word, goals, mf)
	if r.is_error():
		print(r.err().message)

fn var Ctx.make_run(word: String, goals: List[String], mf: List[String]) Unit!:
	self.parse(mf)?
	if word == "build":
		self.do_build(goals, false)?
	else if word == "dry":
		self.do_build(goals, true)?
	else if word == "deps":
		self.visit(goals.get(0, ""), true)?
		if self.dout.length() == 0:
			print("(no prerequisites)")
		for d in self.dout:
			print(d)
	else:
		self.show_targets()
	return ok(unit)

fn var Ctx.expand_request(text: String, mf: List[String]) Unit:
	self.reset()
	r := self.expand_run(text, mf)
	if r.is_error():
		print(r.err().message)
	else:
		print("[{r.get_or_else(fn e: "")}]")

fn var Ctx.expand_run(text: String, mf: List[String]) String!:
	self.parse(mf)?
	return self.expand(text)

// ms: allow_effect std.console.read
fn read_input() String!:
	data := read_all(stdin(), none)?
	return ok(data.decode_utf8().get(""))

// ms: allow_effect std.console.write
fn main() Unit!:
	text := read_input()?
	all := text.lines()
	var mf = List[String]()
	var table = List[String]()
	var reqs = List[String]()
	var sec = 0
	for l in all:
		if sec < 2 and l == "====":
			sec += 1
			continue
		if sec == 0:
			mf.append(l.clone())
		else if sec == 1:
			table.append(l.clone())
		else:
			reqs.append(l.clone())
	var ctx = Ctx()
	for l in table:
		f := l.fields()
		if f.length() == 2:
			if m := f.get(1, "").parse_int():
				if m >= 0:
					ctx.files[f.get(0, "")] = m
					if m > ctx.clock: ctx.clock = m
	for l in reqs:
		line := l.trim()
		if line == "" or line.starts_with("#"): continue
		print("> {line}")
		f := line.fields()
		word := f.get(0, "")
		args := tail(f)
		if word == "build" or word == "dry" or word == "deps" or word == "targets":
			ctx.make_request(word, args, mf)
		else if word == "expand":
			ctx.expand_request(sub(line, 6, line.length()).trim(), mf)
		else if word == "files":
			names := ctx.files.keys().sorted()
			if names.length() == 0:
				print("(no files)")
			for n in names:
				print("{n} {ctx.files.get_or(n, 0)}")
		else if word == "touch":
			if args.length() == 1:
				tk := ctx.tick()
				ctx.files[args.get(0, "")] = tk
			else if args.length() == 2:
				if v := args.get(1, "").parse_int():
					ctx.files[args.get(0, "")] = v
					if v > ctx.clock: ctx.clock = v
				else:
					print("bad request")
			else:
				print("bad request")
		else if word == "rm":
			for a in args:
				ctx.files.remove(a)
		else:
			print("unknown request: {word}")

fn tail(xs: List[String]) List[String]:
	var out = List[String]()
	var i = 1
	while i < xs.length():
		out.append(xs.get(i, ""))
		i += 1
	return out
