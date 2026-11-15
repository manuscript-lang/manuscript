import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn dedup(xs: List[String]) List[String]:
	var seen = Set[String]()
	var out = List[String]()
	for x in xs:
		if not seen.contains(x):
			seen.add(x.clone())
			out.append(x.clone())
	return out

fn match_pat(pat: String, w: String) String?:
	if pi := pat.index_of("%"):
		pre := pat.view(0, pi)
		suf := pat.view(pi + 1, pat.length())
		if w.length() < pre.length() + suf.length(): return none
		if not w.starts_with(pre): return none
		if not w.ends_with(suf): return none
		return w.view(pre.length(), w.length() - suf.length()).clone()
	if pat == w: return ""
	return none

fn subst_pct(rep: String, stem: String) String:
	if i := rep.index_of("%"):
		return "{rep.view(0, i)}{stem}{rep.view(i + 1, rep.length())}"
	return rep.clone()

fn patsubst(pat: String, rep: String, text: String) String:
	var out = List[String]()
	for w in text.fields():
		stem := match_pat(pat, w)
		if s := stem:
			out.append(subst_pct(rep, s))
		else:
			out.append(w.clone())
	return out.join(" ")

fn glob_match(p: List[String], pi: Int, s: List[String], si: Int) Bool:
	if pi == p.length(): return si == s.length()
	c := p[pi]
	if c == "*":
		var k = si
		while true:
			if glob_match(p, pi + 1, s, k): return true
			if k >= s.length(): return false
			if s[k] == "/": return false
			k += 1
		return false
	if si >= s.length(): return false
	if c == "?":
		if s[si] == "/": return false
		return glob_match(p, pi + 1, s, si + 1)
	if c != s[si]: return false
	return glob_match(p, pi + 1, s, si + 1)

fn split_args(s: String) List[String]:
	var out = List[String]()
	var depth = 0
	var start = 0
	n := s.length()
	var i = 0
	while i < n:
		c := s.scalar_at(i, -1)
		if c == 40 or c == 123:
			depth += 1
		else if c == 41 or c == 125:
			if depth > 0: depth -= 1
		else if c == 44 and depth == 0:
			out.append(s.view(start, i).trim())
			start = i + 1
		i += 1
	out.append(s.view(start, n).trim())
	return out

fn is_func(name: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(name)

fn strip_comment(s: String) String:
	var out = ""
	var start = 0
	n := s.length()
	var i = 0
	while i < n:
		c := s.scalar_at(i, -1)
		if c == 92 and s.scalar_at(i + 1, -1) == 35:
			out = "{out}{s.view(start, i)}#"
			i += 2
			start = i
		else if c == 35:
			out = "{out}{s.view(start, i)}"
			return out
		else:
			i += 1
	out = "{out}{s.view(start, n)}"
	return out

fn find_top(s: String, target: Int) Int:
	var depth = 0
	n := s.length()
	var i = 0
	while i < n:
		c := s.scalar_at(i, -1)
		if c == 40 or c == 123:
			depth += 1
		else if c == 41 or c == 125:
			if depth > 0: depth -= 1
		else if c == target and depth == 0:
			return i
		i += 1
	return -1

type Res:
	found: Bool = false
	pre: List[String] = []
	oo: List[String] = []
	rt: List[String] = []
	rl: List[Int] = []
	stem: String = ""

type Make:
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	out: List[String] = []
	vars: Map[String, String] = Map[String, String]()
	simple: Set[String] = Set[String]()
	cmd: Set[String] = Set[String]()
	ex_pre: Map[String, List[String]] = Map[String, List[String]]()
	ex_oo: Map[String, List[String]] = Map[String, List[String]]()
	ex_rt: Map[String, List[String]] = Map[String, List[String]]()
	ex_rl: Map[String, List[Int]] = Map[String, List[Int]]()
	ex_order: List[String] = []
	pr_pat: List[String] = []
	pr_pre: List[List[String]] = []
	pr_oo: List[List[String]] = []
	pr_rt: List[List[String]] = []
	pr_rl: List[List[Int]] = []
	phony: List[String] = []
	phony_set: Set[String] = Set[String]()
	default_goal: String = ""
	curline: Int = 0
	bn: List[String] = []
	bv: List[String] = []
	vstack: List[String] = []
	autos: Map[String, String] = Map[String, String]()
	has_open: Bool = false
	o_targets: List[String] = []
	o_pats: List[Int] = []
	o_rt: List[String] = []
	o_rl: List[Int] = []
	o_line: Int = 0
	f_par: List[Bool] = []
	f_cond: List[Bool] = []
	f_cur: List[Bool] = []
	f_else: List[Bool] = []
	f_line: List[Int] = []
	memo: Map[String, Bool] = Map[String, Bool]()
	bstack: List[String] = []
	ran: Int = 0
	dry: Bool = false
	dseen: Set[String] = Set[String]()
	dout: List[String] = []
	mktext: String = ""

fn var Make.reset() Unit:
	self.vars = Map[String, String]()
	self.simple = Set[String]()
	self.cmd = Set[String]()
	self.ex_pre = Map[String, List[String]]()
	self.ex_oo = Map[String, List[String]]()
	self.ex_rt = Map[String, List[String]]()
	self.ex_rl = Map[String, List[Int]]()
	self.ex_order = []
	self.pr_pat = []
	self.pr_pre = []
	self.pr_oo = []
	self.pr_rt = []
	self.pr_rl = []
	self.phony = []
	self.phony_set = Set[String]()
	self.default_goal = ""
	self.curline = 0
	self.bn = []
	self.bv = []
	self.vstack = []
	self.autos = Map[String, String]()
	self.has_open = false
	self.o_targets = []
	self.o_pats = []
	self.o_rt = []
	self.o_rl = []
	self.f_par = []
	self.f_cond = []
	self.f_cur = []
	self.f_else = []
	self.f_line = []
	self.memo = Map[String, Bool]()
	self.bstack = []
	self.ran = 0
	self.dry = false
	self.dseen = Set[String]()
	self.dout = []

fn Make.fatal(msg: String) Error:
	if self.curline == 0:
		return Error("make: *** {msg}.  Stop.")
	return Error("Makefile:{self.curline}: *** {msg}.  Stop.")

fn Make.active() Bool:
	n := self.f_cur.length()
	if n == 0: return true
	return self.f_cur[n - 1]

fn var Make.lookup(name: String) String!:
	var i = self.bn.length() - 1
	while i >= 0:
		if self.bn[i] == name: return ok(self.bv[i].clone())
		i -= 1
	if self.autos.contains(name): return ok(self.autos.get_or(name, "").clone())
	if not self.vars.contains(name): return ok("")
	val := self.vars.get_or(name, "").clone()
	if self.simple.contains(name): return ok(val)
	if self.vstack.contains(name):
		return error(self.fatal("Recursive variable '{name}' references itself (eventually)"))
	self.vstack.append(name.clone())
	r := self.expand(val)?
	_p := self.vstack.pop()
	return ok(r)

fn var Make.expand(text: String) String!:
	var out = ""
	n := text.length()
	var i = 0
	while i < n:
		c := text.scalar_at(i, -1)
		if c != 36:
			var j = i
			while j < n and text.scalar_at(j, -1) != 36:
				j += 1
			out = "{out}{text.view(i, j)}"
			i = j
			continue
		if i + 1 >= n:
			i += 1
			continue
		c2 := text.scalar_at(i + 1, -1)
		if c2 == 36:
			out = "{out}$"
			i += 2
		else if c2 == 40 or c2 == 123:
			close := if c2 == 40: 41 else: 125
			var depth = 1
			var k = i + 2
			while k < n:
				ck := text.scalar_at(k, -1)
				if ck == c2:
					depth += 1
				else if ck == close:
					depth -= 1
					if depth == 0: break
				k += 1
			if depth != 0:
				return error(self.fatal("unterminated variable reference"))
			inner := text.view(i + 2, k)
			piece := self.expand_ref(inner)?
			out = "{out}{piece}"
			i = k + 1
		else:
			var j = i + 2
			while j < n and text.scalar_at(j, -1) == -1:
				j += 1
			piece := self.lookup(text.view(i + 1, j))?
			out = "{out}{piece}"
			i = j
	return ok(out)

fn var Make.expand_ref(inner: String) String!:
	if sp := inner.index_any(" \t"):
		name := inner.view(0, sp)
		if is_func(name):
			return self.call_func(name, inner.view(sp + 1, inner.length()))
	name_text := (self.expand(inner)?).trim()
	if ci := name_text.index_of(":"):
		if ci > 0:
			rest := name_text.view(ci + 1, name_text.length())
			if ei := rest.index_of("="):
				vname := name_text.view(0, ci).trim()
				from := rest.view(0, ei)
				to := rest.view(ei + 1, rest.length())
				val := self.lookup(vname)?
				if from.contains("%"):
					return ok(patsubst(from, to, val))
				return ok(patsubst("%{from}", "%{to}", val))
	return self.lookup(name_text)

fn var Make.call_func(name: String, argtext: String) String!:
	args := split_args(argtext)
	if name == "foreach":
		vn := (self.expand(args.get(0, ""))?).trim()
		lst := self.expand(args.get(1, ""))?
		var res = List[String]()
		for w in lst.fields():
			self.bn.append(vn.clone())
			self.bv.append(w.clone())
			r := self.expand(args.get(2, ""))?
			_a := self.bn.pop()
			_b := self.bv.pop()
			res.append(r)
		return ok(res.join(" "))
	if name == "if":
		cond := (self.expand(args.get(0, ""))?).trim()
		if not cond.is_empty():
			return self.expand(args.get(1, ""))
		return self.expand(args.get(2, ""))
	a0 := self.expand(args.get(0, ""))?
	a1 := self.expand(args.get(1, ""))?
	a2 := self.expand(args.get(2, ""))?
	if name == "info":
		self.out.append(a0)
		return ok("")
	if name == "error":
		return error(self.fatal(a0))
	if name == "subst":
		if a0.is_empty(): return ok(a2)
		return ok(a2.replace(a0, a1))
	if name == "patsubst": return ok(patsubst(a0, a1, a2))
	if name == "strip": return ok(a0.fields().join(" "))
	if name == "findstring":
		if a1.contains(a0): return ok(a0)
		return ok("")
	if name == "filter" or name == "filter-out":
		pats := a0.fields()
		var res = List[String]()
		for w in a1.fields():
			var hit = false
			for p in pats:
				if match_pat(p, w).is_some():
					hit = true
					break
			if hit == (name == "filter"): res.append(w.clone())
		return ok(res.join(" "))
	if name == "sort":
		return ok(dedup(a0.fields()).sorted().join(" "))
	if name == "word":
		ws := a1.fields()
		n := a0.parse_int().get(0)
		if n < 1 or n > ws.length(): return ok("")
		return ok(ws[n - 1].clone())
	if name == "wordlist":
		ws := a2.fields()
		s := a0.parse_int().get(0)
		e0 := a1.parse_int().get(0)
		if s < 1 or e0 < s or s > ws.length(): return ok("")
		e := if e0 > ws.length(): ws.length() else: e0
		var res = List[String]()
		for k in (s - 1)..e:
			res.append(ws[k].clone())
		return ok(res.join(" "))
	if name == "words": return ok("{a0.fields().length()}")
	if name == "firstword":
		ws := a0.fields()
		if ws.length() == 0: return ok("")
		return ok(ws[0].clone())
	if name == "lastword":
		ws := a0.fields()
		if ws.length() == 0: return ok("")
		return ok(ws[ws.length() - 1].clone())
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		var res = List[String]()
		for w in a0.fields():
			var slash = -1
			var dot = -1
			var k = 0
			while k < w.length():
				ck := w.scalar_at(k, -1)
				if ck == 47:
					slash = k
				else if ck == 46:
					dot = k
				k += 1
			if name == "dir":
				if slash < 0:
					res.append("./")
				else:
					res.append(w.view(0, slash + 1).clone())
			else if name == "notdir":
				res.append(w.view(slash + 1, w.length()).clone())
			else if name == "suffix":
				if dot > slash: res.append(w.view(dot, w.length()).clone())
			else:
				if dot > slash:
					res.append(w.view(0, dot).clone())
				else:
					res.append(w.clone())
		return ok(res.join(" "))
	if name == "addprefix":
		var res = List[String]()
		for w in a1.fields():
			res.append("{a0}{w}")
		return ok(res.join(" "))
	if name == "addsuffix":
		var res = List[String]()
		for w in a1.fields():
			res.append("{w}{a0}")
		return ok(res.join(" "))
	if name == "wildcard":
		var res = List[String]()
		names := self.files.keys().sorted()
		for p in a0.fields():
			if p.contains("*") or p.contains("?"):
				pc := p.chars()
				for f in names:
					if glob_match(pc, 0, f.chars(), 0): res.append(f.clone())
			else:
				if self.files.contains(p): res.append(p.clone())
		return ok(res.join(" "))
	return ok("")

fn var Make.end_rule() Unit:
	if not self.has_open: return
	self.has_open = false
	if self.o_rt.length() == 0: return
	for t in self.o_targets:
		if self.ex_rt.get_or(t, []).length() > 0:
			self.out.append("Makefile:{self.o_line}: warning: overriding recipe for target '{t}'")
		self.ex_rt[t.clone()] = self.o_rt.clone()
		self.ex_rl[t.clone()] = self.o_rl.clone()
	for idx in self.o_pats:
		self.pr_rt[idx] = self.o_rt.clone()
		self.pr_rl[idx] = self.o_rl.clone()

fn var Make.parse_rule(line: String, col: Int, lineno: Int) Unit!:
	left := line.view(0, col)
	rest := line.view(col + 1, line.length())
	semi := find_top(rest, 59)
	var prtext = rest.clone()
	var cmdtext = ""
	if semi >= 0:
		prtext = rest.view(0, semi).clone()
		cmdtext = rest.view(semi + 1, rest.length()).trim()
	targets := (self.expand(left)?).fields()
	pretext := self.expand(prtext)?
	var normal = List[String]()
	var oo = List[String]()
	if bar := pretext.index_of("|"):
		normal = pretext.view(0, bar).fields()
		oo = pretext.view(bar + 1, pretext.length()).fields()
	else:
		normal = pretext.fields()
	self.has_open = true
	self.o_targets = []
	self.o_pats = []
	self.o_rt = []
	self.o_rl = []
	self.o_line = lineno
	for t in targets:
		if t == ".PHONY":
			for p in normal:
				if not self.phony_set.contains(p):
					self.phony_set.add(p.clone())
					self.phony.append(p.clone())
		else if t.contains("%"):
			self.pr_pat.append(t.clone())
			self.pr_pre.append(normal.clone())
			self.pr_oo.append(oo.clone())
			self.pr_rt.append([])
			self.pr_rl.append([])
			self.o_pats.append(self.pr_pat.length() - 1)
		else:
			if not self.ex_pre.contains(t):
				self.ex_pre[t.clone()] = []
				self.ex_oo[t.clone()] = []
				self.ex_rt[t.clone()] = []
				self.ex_rl[t.clone()] = []
				self.ex_order.append(t.clone())
				if self.default_goal.is_empty() and not t.starts_with("."):
					self.default_goal = t.clone()
			var pl = self.ex_pre.get_or(t, []).clone()
			for p in normal: pl.append(p.clone())
			self.ex_pre[t.clone()] = pl
			var ol = self.ex_oo.get_or(t, []).clone()
			for p in oo: ol.append(p.clone())
			self.ex_oo[t.clone()] = ol
			self.o_targets.append(t.clone())
	if not cmdtext.is_empty():
		self.o_rt.append(cmdtext.clone())
		self.o_rl.append(lineno)
	return ok(unit)

fn var Make.assign(line: String, eq: Int) Unit!:
	n := line.length()
	var op = "="
	var name_end = eq
	if eq > 0:
		pc := line.scalar_at(eq - 1, -1)
		if pc == 58:
			op = ":="
			name_end = eq - 1
		else if pc == 63:
			op = "?="
			name_end = eq - 1
		else if pc == 43:
			op = "+="
			name_end = eq - 1
	name := (self.expand(line.view(0, name_end))?).trim()
	if name.is_empty():
		return error(self.fatal("empty variable name"))
	value := line.view(eq + 1, n).trim()
	if self.cmd.contains(name): return ok(unit)
	defined := self.vars.contains(name)
	if op == "=" or (op == "?=" and not defined) or (op == "+=" and not defined):
		self.vars[name.clone()] = value.clone()
		self.simple.remove(name)
	else if op == ":=":
		v := self.expand(value)?
		self.vars[name.clone()] = v
		self.simple.add(name.clone())
	else if op == "+=":
		old := self.vars.get_or(name, "").clone()
		if self.simple.contains(name):
			v := self.expand(value)?
			if old.is_empty():
				self.vars[name.clone()] = v
			else if v.is_empty():
				self.vars[name.clone()] = old
			else:
				self.vars[name.clone()] = "{old} {v}"
		else:
			if old.is_empty():
				self.vars[name.clone()] = value.clone()
			else if value.is_empty():
				self.vars[name.clone()] = old
			else:
				self.vars[name.clone()] = "{old} {value}"
	return ok(unit)

fn var Make.directive(word: String, rest: String, lineno: Int) Unit!:
	if word == "endif":
		if self.f_cur.length() == 0:
			return error(self.fatal("extraneous 'endif'"))
		_a := self.f_par.pop()
		_b := self.f_cond.pop()
		_c := self.f_cur.pop()
		_d := self.f_else.pop()
		_e := self.f_line.pop()
		return ok(unit)
	if word == "else":
		k := self.f_cur.length() - 1
		if k < 0 or self.f_else[k]:
			return error(self.fatal("extraneous 'else'"))
		self.f_else[k] = true
		self.f_cur[k] = self.f_par[k] and not self.f_cond[k]
		return ok(unit)
	parent := self.active()
	var cond = false
	if parent:
		if word == "ifdef" or word == "ifndef":
			name := (self.expand(rest)?).trim()
			defined := self.vars.contains(name) and not self.vars.get_or(name, "").is_empty()
			cond = if word == "ifdef": defined else: not defined
		else:
			r := rest.trim()
			if not r.starts_with("(") or not r.ends_with(")") or r.length() < 2:
				return error(self.fatal("invalid syntax in conditional"))
			inner := r.view(1, r.length() - 1)
			parts := split_args(inner)
			if parts.length() != 2:
				return error(self.fatal("invalid syntax in conditional"))
			a := (self.expand(parts[0])?).trim()
			b := (self.expand(parts[1])?).trim()
			cond = if word == "ifeq": a == b else: a != b
	self.f_par.append(parent)
	self.f_cond.append(cond)
	self.f_cur.append(parent and cond)
	self.f_else.append(false)
	self.f_line.append(lineno)
	return ok(unit)

fn var Make.process_line(text: String, lineno: Int) Unit!:
	self.curline = lineno
	if text.starts_with("\t"):
		body := text.trim_start_chars("\t")
		if body.trim().is_empty(): return ok(unit)
		if not self.active(): return ok(unit)
		if not self.has_open:
			return error(self.fatal("recipe commences before first target"))
		self.o_rt.append(body.clone())
		self.o_rl.append(lineno)
		return ok(unit)
	line := strip_comment(text).trim()
	if line.is_empty(): return ok(unit)
	var word = line.clone()
	var rest = ""
	if sp := line.index_any(" \t"):
		word = line.view(0, sp).clone()
		rest = line.view(sp + 1, line.length()).trim()
	if word == "ifdef" or word == "ifndef" or word == "ifeq" or word == "ifneq" or word == "else" or word == "endif":
		self.end_rule()
		return self.directive(word, rest, lineno)
	if not self.active(): return ok(unit)
	self.end_rule()
	n := line.length()
	var eq = -1
	if e := line.index_of("="): eq = e
	var col = -1
	var i = 0
	while i < n:
		c := line.scalar_at(i, -1)
		if c == 36:
			c2 := line.scalar_at(i + 1, -1)
			if c2 == 40 or c2 == 123:
				close := if c2 == 40: 41 else: 125
				var depth = 1
				var k = i + 2
				while k < n:
					ck := line.scalar_at(k, -1)
					if ck == c2:
						depth += 1
					else if ck == close:
						depth -= 1
						if depth == 0: break
					k += 1
				i = k + 1
			else:
				i += 2
		else if c == 59:
			break
		else if c == 58:
			col = i
			break
		else:
			i += 1
	if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
		return self.assign(line, eq)
	if col >= 0:
		return self.parse_rule(line, col, lineno)
	e := self.expand(line)?
	if e.trim().is_empty(): return ok(unit)
	return error(self.fatal("missing separator"))

fn var Make.parse(text: String, cvars: Map[String, String]) Unit!:
	self.reset()
	for e in cvars.entries():
		self.vars[e.key.clone()] = e.value.clone()
		self.cmd.add(e.key.clone())
	phys := List[String]()
	var plines = phys.clone()
	for l in text.split("\n"):
		if l.ends_with("\r"):
			plines.append(l.view(0, l.length() - 1).clone())
		else:
			plines.append(l.clone())
	var i = 0
	while i < plines.length():
		start := i + 1
		var cur = plines[i].clone()
		while cur.ends_with("\\") and i + 1 < plines.length():
			cur = cur.view(0, cur.length() - 1).trim_end()
			nxt := plines[i + 1].trim_start()
			cur = "{cur} {nxt}"
			i += 1
		i += 1
		self.process_line(cur, start)?
	self.end_rule()
	if self.f_cur.length() > 0:
		self.curline = self.f_line[self.f_line.length() - 1]
		return error(self.fatal("missing 'endif'"))
	self.curline = 0
	return ok(unit)

fn var Make.can_make(name: String, level: Int) Bool:
	if self.files.contains(name): return true
	if self.ex_pre.contains(name): return true
	if self.phony_set.contains(name): return true
	if level <= 8: return self.find_pattern(name, level) >= 0
	return false

fn var Make.find_pattern(t: String, level: Int) Int:
	for idx in 0..self.pr_pat.length():
		if self.pr_rt[idx].length() == 0: continue
		stem := match_pat(self.pr_pat[idx], t)
		if stem.is_none(): continue
		st := stem.get("")
		if st.is_empty(): continue
		var good = true
		pre := self.pr_pre[idx].clone()
		for p in pre:
			if not self.can_make(subst_pct(p, st), level + 1):
				good = false
				break
		if not good: continue
		oo := self.pr_oo[idx].clone()
		for p in oo:
			if not self.can_make(subst_pct(p, st), level + 1):
				good = false
				break
		if good: return idx
	return -1

fn var Make.resolve(t: String) Res:
	has_ex := self.ex_pre.contains(t)
	if has_ex and self.ex_rt.get_or(t, []).length() > 0:
		return Res(found: true, pre: self.ex_pre.get_or(t, []).clone(), oo: self.ex_oo.get_or(t, []).clone(), rt: self.ex_rt.get_or(t, []).clone(), rl: self.ex_rl.get_or(t, []).clone(), stem: "")
	idx := self.find_pattern(t, 0)
	if idx >= 0:
		stem := match_pat(self.pr_pat[idx], t).get("")
		var pre = List[String]()
		var oo = List[String]()
		for p in self.pr_pre[idx]: pre.append(subst_pct(p, stem))
		for p in self.pr_oo[idx]: oo.append(subst_pct(p, stem))
		if has_ex:
			for p in self.ex_pre.get_or(t, []): pre.append(p.clone())
			for p in self.ex_oo.get_or(t, []): oo.append(p.clone())
		return Res(found: true, pre: pre, oo: oo, rt: self.pr_rt[idx].clone(), rl: self.pr_rl[idx].clone(), stem: stem)
	if has_ex:
		return Res(found: true, pre: self.ex_pre.get_or(t, []).clone(), oo: self.ex_oo.get_or(t, []).clone())
	return Res()

fn var Make.run_recipe(t: String, r: Res, pre: List[String], was_in: Bool, old: Int) Unit!:
	self.ran += 1
	var changed = List[String]()
	for p in pre:
		if not was_in or self.memo.get_or(p, false) or (self.files.contains(p) and self.files.get_or(p, 0) > old):
			changed.append(p.clone())
	var a = Map[String, String]()
	a["@"] = t.clone()
	a["<"] = r.pre.get(0, "").clone()
	a["^"] = pre.join(" ")
	a["?"] = changed.join(" ")
	a["|"] = dedup(r.oo).join(" ")
	a["*"] = r.stem.clone()
	self.autos = a
	for li in 0..r.rt.length():
		lno := r.rl[li]
		self.curline = lno
		cmd := (self.expand(r.rt[li])?).trim()
		n := cmd.length()
		var i = 0
		var silent = false
		var ignore = false
		while i < n:
			c := cmd.scalar_at(i, -1)
			if c == 64:
				silent = true
			else if c == 45:
				ignore = true
			else if c != 43 and c != 32 and c != 9:
				break
			i += 1
		command := cmd.view(i, n).trim()
		if command.is_empty(): continue
		if self.dry:
			self.out.append(command.clone())
			continue
		if not silent: self.out.append(command.clone())
		ws := command.fields()
		var status = 0
		w0 := ws[0]
		if w0 == "false":
			status = 1
		else if w0 == "exit":
			if ws.length() > 1:
				status = ws[1].parse_int().get(2)
		else if w0 == "touch":
			for k in 1..ws.length():
				if not ws[k].starts_with("-"):
					self.clock += 1
					self.files[ws[k].clone()] = self.clock
		else if w0 == "rm":
			for k in 1..ws.length():
				if not ws[k].starts_with("-"):
					self.files.remove(ws[k].clone())
		else if w0 == "cp":
			if ws.length() == 3:
				if not self.files.contains(ws[1]):
					self.out.append("cp: cannot stat '{ws[1]}': No such file or directory")
					status = 1
				else:
					self.clock += 1
					self.files[ws[2].clone()] = self.clock
		else if w0 == "echo":
			var parts = List[String]()
			for k in 1..ws.length():
				parts.append(ws[k].replace("\"", "").replace("'", ""))
			self.out.append(parts.join(" "))
		if status != 0:
			if ignore:
				self.out.append("make: [Makefile:{lno}: {t}] Error {status} (ignored)")
			else:
				self.curline = 0
				self.autos = Map[String, String]()
				return error(Error("make: *** [Makefile:{lno}: {t}] Error {status}"))
	self.curline = 0
	self.autos = Map[String, String]()
	if not self.dry and not self.phony_set.contains(t):
		self.clock += 1
		self.files[t.clone()] = self.clock
	return ok(unit)

fn var Make.update(t: String, needed: String) Bool!:
	if self.memo.contains(t): return ok(self.memo.get_or(t, false))
	if self.bstack.contains(t):
		var path = List[String]()
		var on = false
		for s in self.bstack:
			if s == t: on = true
			if on: path.append(s.clone())
		path.append(t.clone())
		return error(Error("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
	r := self.resolve(t)
	if not r.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)
		if self.phony_set.contains(t):
			self.memo[t.clone()] = true
			return ok(true)
		if needed.is_empty():
			return error(Error("make: *** No rule to make target '{t}'.  Stop."))
		return error(Error("make: *** No rule to make target '{t}', needed by '{needed}'.  Stop."))
	self.bstack.append(t.clone())
	was_in := self.files.contains(t)
	old := self.files.get_or(t, 0)
	var changed = false
	var newer = false
	pre := dedup(r.pre)
	for p in pre:
		c := self.update(p, t)?
		if c: changed = true
		if was_in and self.files.contains(p) and self.files.get_or(p, 0) > old: newer = true
	for p in dedup(r.oo):
		_c := self.update(p, t)?
	rebuild := self.phony_set.contains(t) or not self.files.contains(t) or changed or newer
	if rebuild and r.rt.length() > 0:
		self.run_recipe(t, r, pre, was_in, old)?
	_x := self.bstack.pop()
	self.memo[t.clone()] = rebuild
	return ok(rebuild)

fn var Make.do_build(goals: List[String]) Unit!:
	var gl = List[String]()
	for g in goals: gl.append(g.clone())
	if gl.length() == 0:
		if self.default_goal.is_empty():
			return error(Error("make: *** No targets.  Stop."))
		gl.append(self.default_goal.clone())
	for g in gl:
		before := self.ran
		_u := self.update(g, "")?
		if self.ran == before:
			r := self.resolve(g)
			if r.rt.length() > 0 or (self.files.contains(g) and not self.phony_set.contains(g)):
				self.out.append("make: '{g}' is up to date.")
			else:
				self.out.append("make: Nothing to be done for '{g}'.")
	return ok(unit)

fn var Make.deps_walk(t: String) Unit!:
	r := self.resolve(t)
	self.bstack.append(t.clone())
	var all = dedup(r.pre)
	for p in dedup(r.oo): all.append(p.clone())
	for p in all:
		if self.bstack.contains(p):
			var path = List[String]()
			var on = false
			for s in self.bstack:
				if s == p: on = true
				if on: path.append(s.clone())
			path.append(p.clone())
			return error(Error("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
		if self.dseen.contains(p): continue
		self.deps_walk(p)?
		self.dseen.add(p.clone())
		self.dout.append(p.clone())
	_x := self.bstack.pop()
	return ok(unit)

fn fmt_rule(head: String, pre: List[String], oo: List[String]) String:
	var s = "{head}:"
	if pre.length() > 0: s = "{s} {pre.join(" ")}"
	if oo.length() > 0: s = "{s} | {oo.join(" ")}"
	return s

fn var Make.request(line: String) Unit:
	t := line.trim()
	ws := t.fields()
	word := ws[0]
	if word == "files":
		if self.files.length() == 0:
			self.out.append("(no files)")
		for k in self.files.keys().sorted():
			self.out.append("{k} {self.files.get_or(k, 0)}")
		return
	if word == "touch":
		if ws.length() == 2:
			self.clock += 1
			self.files[ws[1].clone()] = self.clock
		else if ws.length() == 3:
			if n := ws[2].parse_int():
				self.files[ws[1].clone()] = n
				if n > self.clock: self.clock = n
			else:
				self.out.append("bad request")
		else:
			self.out.append("bad request")
		return
	if word == "rm":
		for k in 1..ws.length():
			self.files.remove(ws[k].clone())
		return
	if word == "expand":
		text := t.view(6, t.length()).trim()
		r := self.parse(self.mktext.clone(), Map[String, String]())
		if _v := r:
			e := self.expand(text)
			if v := e:
				self.out.append("[{v}]")
			else:
				self.out.append(e.err().message.clone())
		else:
			self.out.append(r.err().message.clone())
		return
	if word == "build" or word == "dry" or word == "deps" or word == "targets":
		var cv = Map[String, String]()
		var goals = List[String]()
		for k in 1..ws.length():
			a := ws[k]
			if ei := a.index_of("="):
				if ei > 0:
					cv[a.view(0, ei).clone()] = a.view(ei + 1, a.length()).clone()
					continue
			goals.append(a.clone())
		r := self.parse(self.mktext.clone(), cv)
		if _v := r:
			unit
		else:
			self.out.append(r.err().message.clone())
			return
		if word == "targets":
			if not self.default_goal.is_empty():
				self.out.append("default: {self.default_goal}")
			for k in self.ex_order:
				self.out.append(fmt_rule(k, self.ex_pre.get_or(k, []), self.ex_oo.get_or(k, [])))
			for idx in 0..self.pr_pat.length():
				self.out.append(fmt_rule("pattern {self.pr_pat[idx]}", self.pr_pre[idx], self.pr_oo[idx]))
			if self.phony.length() > 0:
				self.out.append("phony: {self.phony.join(" ")}")
			return
		if word == "deps":
			if goals.length() != 1:
				self.out.append("usage: deps TARGET")
				return
			d := self.deps_walk(goals[0])
			if _w := d:
				if self.dout.length() == 0:
					self.out.append("(no prerequisites)")
				for x in self.dout: self.out.append(x.clone())
			else:
				self.out.append(d.err().message.clone())
			return
		self.dry = word == "dry"
		b := self.do_build(goals)
		if _w := b:
			return
		else:
			self.out.append(b.err().message.clone())
		return
	self.out.append("unknown request: {word}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var m = Make()
	var sec = 0
	var mk = List[String]()
	var tbl = List[String]()
	var reqs = List[String]()
	for l0 in text.split("\n"):
		l := if l0.ends_with("\r"): l0.view(0, l0.length() - 1) else: l0.view(0, l0.length())
		if sec < 2 and l == "====":
			sec += 1
			continue
		if sec == 0:
			mk.append(l.clone())
		else if sec == 1:
			tbl.append(l.clone())
		else:
			reqs.append(l.clone())
	m.mktext = mk.join("\n")
	for l in tbl:
		f := l.fields()
		if f.length() == 2:
			if v := f[1].parse_int():
				if v >= 0:
					m.files[f[0].clone()] = v
					if v > m.clock: m.clock = v
	for r in reqs:
		t := r.trim()
		if t.is_empty() or t.starts_with("#"): continue
		m.out.append("> {r.trim_end()}")
		m.request(r)
	for o in m.out:
		print(o)
