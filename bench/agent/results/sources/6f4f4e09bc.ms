import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Rule:
	prereqs: List[String] = []
	oo: List[String] = []
	recipe: List[String] = []
	lines: List[Int] = []
	stem: String = ""
	pat: String = ""
	found: Bool = false

type Cond:
	parent: Bool
	taken: Bool
	in_else: Bool
	line: Int

type Sim:
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	out: List[String] = []
	vval: Map[String, String] = Map[String, String]()
	vsimple: Map[String, Bool] = Map[String, Bool]()
	cmd: Map[String, Bool] = Map[String, Bool]()
	binds: Map[String, String] = Map[String, String]()
	expanding: Map[String, Bool] = Map[String, Bool]()
	failed: Bool = false
	curline: Int = 0
	autos_on: Bool = false
	a_target: String = ""
	a_first: String = ""
	a_all: String = ""
	a_q: String = ""
	a_oo: String = ""
	a_stem: String = ""
	exrules: Map[String, Rule] = Map[String, Rule]()
	exorder: List[String] = []
	prules: List[Rule] = []
	phony: Map[String, Bool] = Map[String, Bool]()
	phony_order: List[String] = []
	pend_targets: List[String] = []
	pend_pats: List[Int] = []
	pend_rec: List[String] = []
	pend_nums: List[Int] = []
	pend_line: Int = 0
	pend_open: Bool = false
	memo: Map[String, Bool] = Map[String, Bool]()
	stack: List[String] = []
	ran: Bool = false
	dry: Bool = false

fn at(s: String, i: Int) Int:
	if i < 0 or i >= s.length(): return -1
	return s.scalar_at(i, default: -1)

fn clen(c: Int) Int:
	if c >= 240: return 4
	if c >= 224: return 3
	if c >= 192: return 2
	return 1

fn sub(s: String, a: Int, b: Int) String:
	n := s.length()
	var x = a
	var y = b
	if x < 0: x = 0
	if y > n: y = n
	if y <= x: return ""
	return s.view(x, y).clone()

fn is_ws(c: Int) Bool:
	return c == 32 or c == 9 or c == 10 or c == 13

fn trim_st(s: String) String:
	return s.trim_chars(" \t")

fn words(s: String) List[String]:
	return s.fields()

fn dedup(xs: List[String]) List[String]:
	var seen = Set[String]()
	var res = List[String]()
	for x in xs:
		if seen.contains(x): continue
		seen.add(x.clone())
		res.append(x.clone())
	return res

fn join_sp(xs: List[String]) String:
	return xs.join(" ")

fn join2(a: String, b: String) String:
	if a == "" or b == "": return a + b
	return a + " " + b

// returns stem or none
fn pmatch(pat: String, w: String) String?:
	if idx := pat.index_of("%"):
		pre := sub(pat, 0, idx)
		suf := sub(pat, idx + 1, pat.length())
		if w.length() < pre.length() + suf.length(): return none
		if not w.starts_with(pre): return none
		if not w.ends_with(suf): return none
		return sub(w, pre.length(), w.length() - suf.length())
	if pat == w: return ""
	return none

fn glob(p: String, pi: Int, s: String, si: Int) Bool:
	if pi >= p.length(): return si == s.length()
	c := at(p, pi)
	if c == 42:
		var k = si
		while true:
			if glob(p, pi + 1, s, k): return true
			if k >= s.length(): return false
			if at(s, k) == 47: return false
			k += clen(at(s, k))
		return false
	if si >= s.length(): return false
	d := at(s, si)
	if c == 63:
		if d == 47: return false
		return glob(p, pi + 1, s, si + clen(d))
	if c == d: return glob(p, pi + 1, s, si + 1)
	return false

fn is_func(t: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(t)

fn split_args(s: String) List[String]:
	var res = List[String]()
	var depth = 0
	var start = 0
	n := s.length()
	var i = 0
	while i < n:
		c := at(s, i)
		if c == 40 or c == 123: depth += 1
		else if c == 41 or c == 125: depth -= 1
		else if c == 44 and depth <= 0:
			res.append(trim_st(sub(s, start, i)))
			start = i + 1
		i += 1
	res.append(trim_st(sub(s, start, n)))
	return res

// index of first ':' outside references and before ';', or -1
fn find_top_colon(s: String) Int:
	n := s.length()
	var i = 0
	while i < n:
		c := at(s, i)
		if c == 36:
			d := at(s, i + 1)
			if d == 40 or d == 123:
				closer := if d == 40: 41 else: 125
				var depth = 1
				var k = i + 2
				while k < n:
					ch := at(s, k)
					if ch == d: depth += 1
					else if ch == closer:
						depth -= 1
						if depth == 0: break
					k += 1
				i = k + 1
				continue
			i += 2
			continue
		if c == 59: return -1
		if c == 58: return i
		i += 1
	return -1

fn find_top_semi(s: String) Int:
	n := s.length()
	var i = 0
	while i < n:
		c := at(s, i)
		if c == 36:
			d := at(s, i + 1)
			if d == 40 or d == 123:
				closer := if d == 40: 41 else: 125
				var depth = 1
				var k = i + 2
				while k < n:
					ch := at(s, k)
					if ch == d: depth += 1
					else if ch == closer:
						depth -= 1
						if depth == 0: break
					k += 1
				i = k + 1
				continue
			i += 2
			continue
		if c == 59: return i
		i += 1
	return -1

fn cond_active(c: Cond) Bool:
	if not c.parent: return false
	if c.in_else: return not c.taken
	return c.taken

fn strip_comment(s: String) String:
	var res = ""
	n := s.length()
	var i = 0
	var start = 0
	while i < n:
		c := at(s, i)
		if c == 92 and at(s, i + 1) == 35:
			res += sub(s, start, i)
			res += "#"
			i += 2
			start = i
			continue
		if c == 35:
			res += sub(s, start, i)
			return res
		i += 1
	res += sub(s, start, n)
	return res

fn fn_first(s: String) String:
	idx := s.index_any(" \t")
	if k := idx: return sub(s, 0, k)
	return s.clone()

// ---------------------------------------------------------------- Sim

fn var Sim.emit(line: String) Unit:
	self.out.append(line)

fn var Sim.fatal(msg: String) Unit:
	if self.failed: return
	self.failed = true
	if self.curline > 0:
		self.emit("Makefile:{self.curline}: *** {msg}.  Stop.")
	else:
		self.emit("make: *** {msg}.  Stop.")

fn var Sim.lookup(name: String) String:
	if v := self.binds.get(name): return v.clone()
	if self.autos_on:
		if name == "@": return self.a_target.clone()
		if name == "<": return self.a_first.clone()
		if name == "^": return self.a_all.clone()
		if name == "?": return self.a_q.clone()
		if name == "|": return self.a_oo.clone()
		if name == "*": return self.a_stem.clone()
	if not self.vval.contains(name): return ""
	value := self.vval.get_or(name, "")
	if self.vsimple.get_or(name, false): return value.clone()
	if self.expanding.contains(name):
		self.fatal("Recursive variable '{name}' references itself (eventually)")
		return ""
	self.expanding[name.clone()] = true
	r := self.expand(value)
	self.expanding.remove(name)
	return r

fn var Sim.expand(s: String) String:
	var res = ""
	n := s.length()
	var i = 0
	var start = 0
	while i < n:
		if self.failed: return ""
		c := at(s, i)
		if c != 36:
			i += 1
			continue
		res += sub(s, start, i)
		j := i + 1
		if j >= n:
			i = n
			start = n
			break
		d := at(s, j)
		if d == 36:
			res += "$"
			i = j + 1
			start = i
		else if d == 40 or d == 123:
			closer := if d == 40: 41 else: 125
			var depth = 1
			var k = j + 1
			while k < n:
				ch := at(s, k)
				if ch == d: depth += 1
				else if ch == closer:
					depth -= 1
					if depth == 0: break
				k += 1
			if depth != 0:
				self.fatal("unterminated variable reference")
				return ""
			res += self.eval_ref(sub(s, j + 1, k))
			i = k + 1
			start = i
		else:
			l := clen(d)
			res += self.lookup(sub(s, j, j + l))
			i = j + l
			start = i
	if self.failed: return ""
	res += sub(s, start, n)
	return res

fn var Sim.eval_ref(inner: String) String:
	idx := inner.index_any(" \t")
	if k := idx:
		tok := sub(inner, 0, k)
		if is_func(tok):
			return self.call_func(tok, sub(inner, k + 1, inner.length()))
	name := self.expand(inner).trim()
	if self.failed: return ""
	if ci := name.index_of(":"):
		if ci > 0:
			rest := sub(name, ci + 1, name.length())
			if e := rest.index_of("="):
				var from = sub(rest, 0, e)
				var to = sub(rest, e + 1, rest.length())
				if not from.contains("%"):
					from = "%" + from
					to = "%" + to
				value := self.lookup(sub(name, 0, ci).trim())
				return patsubst(from, to, value)
	return self.lookup(name)

fn patsubst(pat: String, rep: String, text: String) String:
	var res = List[String]()
	for w in words(text):
		if stem := pmatch(pat, w):
			if pat.contains("%"):
				res.append(rep.replace_first("%", stem))
			else:
				res.append(rep.clone())
		else:
			res.append(w.clone())
	return join_sp(res)

fn matches_any(pats: List[String], w: String) Bool:
	for p in pats:
		if pmatch(p, w).is_some(): return true
	return false

fn var Sim.arg(args: List[String], i: Int) String:
	if i >= args.length(): return ""
	return self.expand(args.get(i, ""))

fn var Sim.call_func(name: String, raw: String) String:
	args := split_args(raw)
	if name == "foreach":
		var_name := self.arg(args, 0).trim()
		lst := self.arg(args, 1)
		if self.failed: return ""
		var res = List[String]()
		has_old := self.binds.contains(var_name)
		oldv := self.binds.get_or(var_name, "")
		for w in words(lst):
			self.binds[var_name.clone()] = w.clone()
			r := self.expand(args.get(2, ""))
			res.append(r)
			if self.failed: break
		if has_old:
			self.binds[var_name.clone()] = oldv
		else:
			self.binds.remove(var_name)
		return join_sp(res)
	if name == "if":
		cond := self.arg(args, 0).trim()
		if self.failed: return ""
		if cond != "": return self.arg(args, 1)
		return self.arg(args, 2)
	if name == "info":
		t := self.arg(args, 0)
		if self.failed: return ""
		self.emit(t)
		return ""
	if name == "error":
		t := self.arg(args, 0)
		if self.failed: return ""
		self.fatal(t)
		return ""
	a0 := self.arg(args, 0)
	if name == "subst":
		a1 := self.arg(args, 1)
		a2 := self.arg(args, 2)
		if a0 == "": return a2
		return a2.replace(a0, a1)
	if name == "patsubst":
		a1 := self.arg(args, 1)
		a2 := self.arg(args, 2)
		return patsubst(a0, a1, a2)
	if name == "strip": return join_sp(words(a0))
	if name == "findstring":
		a1 := self.arg(args, 1)
		if a1.contains(a0): return a0
		return ""
	if name == "filter" or name == "filter-out":
		a1 := self.arg(args, 1)
		pats := words(a0)
		var res = List[String]()
		keep := name == "filter"
		for w in words(a1):
			m := matches_any(pats, w)
			if m == keep: res.append(w.clone())
		return join_sp(res)
	if name == "sort":
		var ws = words(a0)
		ws.sort()
		return join_sp(ws.distinct())
	if name == "word":
		a1 := self.arg(args, 1)
		if n := a0.trim().parse_int():
			ws := words(a1)
			if n >= 1 and n <= ws.length(): return ws.get(n - 1, "")
		return ""
	if name == "wordlist":
		a1 := self.arg(args, 1)
		a2 := self.arg(args, 2)
		s := a0.trim().parse_int()
		e := a1.trim().parse_int()
		if s.is_none() or e.is_none(): return ""
		sv := s.get(0)
		var ev = e.get(0)
		ws := words(a2)
		if sv < 1 or ev < sv or sv > ws.length(): return ""
		if ev > ws.length(): ev = ws.length()
		var res = List[String]()
		for k in (sv - 1)..ev:
			res.append(ws.get(k, ""))
		return join_sp(res)
	if name == "words": return "{words(a0).length()}"
	if name == "firstword":
		ws := words(a0)
		if ws.length() == 0: return ""
		return ws.get(0, "")
	if name == "lastword":
		ws := words(a0)
		if ws.length() == 0: return ""
		return ws.get(ws.length() - 1, "")
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		var res = List[String]()
		for w in words(a0):
			sl := w.last_index_of("/")
			var dirpart = "./"
			var base = w.clone()
			if p := sl:
				dirpart = sub(w, 0, p + 1)
				base = sub(w, p + 1, w.length())
			dot := base.last_index_of(".")
			if name == "dir": res.append(dirpart)
			else if name == "notdir": res.append(base)
			else if name == "suffix":
				if d := dot: res.append(sub(base, d, base.length()))
			else:
				if d := dot:
					res.append(sub(w, 0, w.length() - (base.length() - d)))
				else:
					res.append(w.clone())
		return join_sp(res)
	if name == "addprefix" or name == "addsuffix":
		a1 := self.arg(args, 1)
		var res = List[String]()
		for w in words(a1):
			if name == "addprefix": res.append(a0 + w)
			else: res.append(w + a0)
		return join_sp(res)
	if name == "wildcard":
		var res = List[String]()
		names := self.files.keys().sorted()
		for p in words(a0):
			for f in names:
				if glob(p, 0, f, 0): res.append(f.clone())
		return join_sp(res)
	return ""

// ---------------------------------------------------------------- parsing

fn var Sim.set_var(name: String, value: String, simple: Bool) Unit:
	self.vval[name.clone()] = value.clone()
	self.vsimple[name.clone()] = simple

fn var Sim.finish_rule() Unit:
	if not self.pend_open: return
	self.pend_open = false
	if self.pend_rec.length() > 0:
		for t in self.pend_targets.clone():
			var r = self.exrules.get(t).get(Rule())
			if r.recipe.length() > 0:
				self.emit("Makefile:{self.pend_line}: warning: overriding recipe for target '{t}'")
			r.recipe = self.pend_rec.clone()
			r.lines = self.pend_nums.clone()
			self.exrules[t.clone()] = r
		for pi in self.pend_pats.clone():
			var r = self.prules.get(pi).clone()
			r.recipe = self.pend_rec.clone()
			r.lines = self.pend_nums.clone()
			self.prules.replace(pi, r)
	self.pend_targets = []
	self.pend_pats = []
	self.pend_rec = []
	self.pend_nums = []

fn var Sim.parse(lines: List[String]) Unit:
	var conds = List[Cond]()
	var i = 0
	n := lines.length()
	while i < n and not self.failed:
		lineno := i + 1
		var cur = lines.get(i, "")
		i += 1
		while cur.ends_with("\\"):
			base := sub(cur, 0, cur.length() - 1).trim_end()
			if i < n:
				cur = base + " " + lines.get(i, "").trim_start()
				i += 1
			else:
				cur = base
		self.curline = lineno
		var active = true
		if conds.length() > 0:
			active = cond_active(conds.get(conds.length() - 1, Cond(false, false, false, 0)))
		if cur.starts_with("\t"):
			if not active: continue
			text := cur.trim_start_chars("\t")
			if text.trim() == "": continue
			if not self.pend_open:
				self.fatal("recipe commences before first target")
				break
			self.pend_rec.append(text)
			self.pend_nums.append(lineno)
			continue
		text := strip_comment(cur).trim()
		if text == "": continue
		w := fn_first(text)
		rest := sub(text, w.length(), text.length()).trim()
		if w == "ifdef" or w == "ifndef" or w == "ifeq" or w == "ifneq":
			if not active:
				conds.append(Cond(false, false, false, lineno))
				continue
			self.finish_rule()
			var result = false
			if w == "ifdef" or w == "ifndef":
				name := self.expand(rest).trim()
				if self.failed: break
				defined := self.vval.get_or(name, "") != ""
				result = if w == "ifdef": defined else: not defined
			else:
				if not (rest.starts_with("(") and rest.ends_with(")")) or rest.length() < 2:
					self.fatal("invalid syntax in conditional")
					break
				inner := sub(rest, 1, rest.length() - 1)
				var depth = 0
				var commas = List[Int]()
				for k in 0..inner.length():
					c := at(inner, k)
					if c == 40 or c == 123: depth += 1
					else if c == 41 or c == 125: depth -= 1
					else if c == 44 and depth == 0: commas.append(k)
				if commas.length() != 1:
					self.fatal("invalid syntax in conditional")
					break
				cp := commas.get(0, 0)
				l := self.expand(trim_st(sub(inner, 0, cp)).trim()).trim()
				r := self.expand(trim_st(sub(inner, cp + 1, inner.length())).trim()).trim()
				if self.failed: break
				result = if w == "ifeq": l == r else: l != r
			conds.append(Cond(true, result, false, lineno))
			continue
		if w == "else" and rest == "":
			if conds.length() == 0:
				self.fatal("extraneous 'else'")
				break
			top := conds.get(conds.length() - 1, Cond(false, false, false, 0))
			if top.in_else:
				self.fatal("extraneous 'else'")
				break
			if top.parent: self.finish_rule()
			conds.replace(conds.length() - 1, Cond(top.parent, top.taken, true, top.line))
			continue
		if w == "endif":
			if conds.length() == 0:
				self.fatal("extraneous 'endif'")
				break
			top := conds.get(conds.length() - 1, Cond(false, false, false, 0))
			if top.parent: self.finish_rule()
			conds.pop()
			continue
		if not active: continue
		self.finish_rule()
		self.parse_line(text, lineno)
	if not self.failed and conds.length() > 0:
		self.curline = conds.get(conds.length() - 1, Cond(false, false, false, 0)).line
		self.fatal("missing 'endif'")
	if not self.failed: self.finish_rule()
	self.curline = 0

fn var Sim.parse_line(text: String, lineno: Int) Unit:
	eq := text.index_of("=")
	if e := eq:
		col := find_top_colon(text)
		if col < 0 or col > e or col == e - 1:
			self.assign(text, e)
			return
	col := find_top_colon(text)
	if col < 0:
		r := self.expand(text)
		if self.failed: return
		if r.trim() != "":
			self.fatal("missing separator")
		return
	targets_txt := sub(text, 0, col)
	rest := sub(text, col + 1, text.length())
	semi := find_top_semi(rest)
	var pre_txt = rest.clone()
	var cmd = ""
	if semi >= 0:
		pre_txt = sub(rest, 0, semi)
		cmd = sub(rest, semi + 1, rest.length()).trim()
	tx := self.expand(targets_txt)
	px := self.expand(pre_txt)
	if self.failed: return
	targets := words(tx)
	var normal = List[String]()
	var oo = List[String]()
	if bar := px.index_of("|"):
		normal = words(sub(px, 0, bar))
		oo = words(sub(px, bar + 1, px.length()))
	else:
		normal = words(px)
	self.pend_open = true
	self.pend_line = lineno
	self.pend_targets = []
	self.pend_pats = []
	self.pend_rec = []
	self.pend_nums = []
	if targets.length() == 1 and targets.get(0, "") == ".PHONY":
		for p in normal:
			if not self.phony.contains(p):
				self.phony[p.clone()] = true
				self.phony_order.append(p.clone())
	else:
		for t in targets:
			if t.contains("%"):
				self.prules.append(Rule(prereqs: normal.clone(), oo: oo.clone(), pat: t.clone(), found: true))
				self.pend_pats.append(self.prules.length() - 1)
			else:
				var r = Rule(found: true)
				if existing := self.exrules.get(t):
					r = existing.clone()
				else:
					self.exorder.append(t.clone())
				r.prereqs.extend(normal.clone())
				r.oo.extend(oo.clone())
				self.exrules[t.clone()] = r
				self.pend_targets.append(t.clone())
	if cmd != "":
		self.pend_rec.append(cmd)
		self.pend_nums.append(lineno)

fn var Sim.assign(text: String, e: Int) Unit:
	var op = "="
	var name_end = e
	if e > 0:
		pc := at(text, e - 1)
		if pc == 58: 
			op = ":="
			name_end = e - 1
		else if pc == 63:
			op = "?="
			name_end = e - 1
		else if pc == 43:
			op = "+="
			name_end = e - 1
	name := self.expand(sub(text, 0, name_end)).trim()
	if self.failed: return
	if name == "":
		self.fatal("empty variable name")
		return
	value := sub(text, e + 1, text.length()).trim()
	if self.cmd.contains(name): return
	if op == "=":
		self.set_var(name, value, false)
	else if op == ":=":
		v := self.expand(value)
		if self.failed: return
		self.set_var(name, v, true)
	else if op == "?=":
		if not self.vval.contains(name):
			self.set_var(name, value, false)
	else:
		if not self.vval.contains(name):
			self.set_var(name, value, false)
		else:
			old := self.vval.get_or(name, "")
			if self.vsimple.get_or(name, false):
				v := self.expand(value)
				if self.failed: return
				self.set_var(name, join2(old, v), true)
			else:
				self.set_var(name, join2(old, value), false)

fn var Sim.reset(cmdargs: List[String]) Unit:
	self.vval = Map[String, String]()
	self.vsimple = Map[String, Bool]()
	self.cmd = Map[String, Bool]()
	self.binds = Map[String, String]()
	self.expanding = Map[String, Bool]()
	self.failed = false
	self.curline = 0
	self.autos_on = false
	self.exrules = Map[String, Rule]()
	self.exorder = []
	self.prules = []
	self.phony = Map[String, Bool]()
	self.phony_order = []
	self.pend_targets = []
	self.pend_pats = []
	self.pend_rec = []
	self.pend_nums = []
	self.pend_open = false
	self.memo = Map[String, Bool]()
	self.stack = []
	self.ran = false
	for a in cmdargs:
		if eq := a.index_of("="):
			name := sub(a, 0, eq)
			self.set_var(name, sub(a, eq + 1, a.length()), false)
			self.cmd[name.clone()] = true

fn Sim.default_goal() String:
	for t in self.exorder:
		if not t.starts_with("."): return t.clone()
	return ""

// ---------------------------------------------------------------- rules

fn Sim.can_make(name: String, depth: Int) Bool:
	if self.files.contains(name) or self.exrules.contains(name) or self.phony.contains(name): return true
	if depth >= 8: return false
	return self.find_pattern(name, depth).found

fn Sim.find_pattern(t: String, depth: Int) Rule:
	for r in self.prules:
		if r.recipe.length() == 0: continue
		if stem := pmatch(r.pat, t):
			if stem == "": continue
			var ok = true
			for p in r.prereqs:
				if not self.can_make(p.replace_first("%", stem), depth + 1):
					ok = false
					break
			if ok:
				for p in r.oo:
					if not self.can_make(p.replace_first("%", stem), depth + 1):
						ok = false
						break
			if not ok: continue
			var res = Rule(found: true, stem: stem.clone(), pat: r.pat.clone())
			for p in r.prereqs: res.prereqs.append(p.replace_first("%", stem))
			for p in r.oo: res.oo.append(p.replace_first("%", stem))
			res.recipe = r.recipe.clone()
			res.lines = r.lines.clone()
			return res
	return Rule()

fn Sim.resolve(t: String) Rule:
	ex := self.exrules.get(t)
	if e := ex:
		if e.recipe.length() > 0: return e.clone()
	p := self.find_pattern(t, 0)
	if p.found:
		var r = p.clone()
		if e := ex:
			r.prereqs.extend(e.prereqs.clone())
			r.oo.extend(e.oo.clone())
		return r
	if e := ex: return e.clone()
	return Rule()

// ---------------------------------------------------------------- building

fn var Sim.tick() Int:
	self.clock += 1
	return self.clock

fn var Sim.circular(t: String) Unit:
	var path = List[String]()
	var started = false
	for s in self.stack:
		if s == t: started = true
		if started: path.append(s.clone())
	path.append(t.clone())
	self.emit("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop.")
	self.failed = true

fn var Sim.update(t: String, needed_by: String) Bool:
	if self.memo.contains(t): return self.memo.get_or(t, false)
	if self.stack.contains(t):
		self.circular(t)
		return false
	r := self.resolve(t)
	if not r.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return false
		if self.phony.contains(t):
			self.memo[t.clone()] = true
			return true
		if needed_by == "":
			self.emit("make: *** No rule to make target '{t}'.  Stop.")
		else:
			self.emit("make: *** No rule to make target '{t}', needed by '{needed_by}'.  Stop.")
		self.failed = true
		return false
	in_table := self.files.contains(t)
	mt := self.files.get_or(t, 0)
	self.stack.append(t.clone())
	var any_changed = false
	var newer = false
	prereqs := dedup(r.prereqs)
	for p in prereqs:
		c := self.update(p, t)
		if self.failed: return false
		if c: any_changed = true
		if in_table and self.files.contains(p) and self.files.get_or(p, 0) > mt: newer = true
	for p in dedup(r.oo):
		self.update(p, t)
		if self.failed: return false
	self.stack.pop()
	is_phony := self.phony.contains(t)
	var changed = false
	if is_phony or not self.files.contains(t) or any_changed or newer:
		changed = true
		if r.recipe.length() > 0:
			self.run_recipe(t, r, prereqs, in_table, mt)
			if self.failed: return false
	self.memo[t.clone()] = changed
	return changed

fn var Sim.run_recipe(t: String, r: Rule, prereqs: List[String], in_table: Bool, mt: Int) Unit:
	self.ran = true
	self.a_target = t.clone()
	self.a_first = r.prereqs.get(0, "")
	self.a_all = join_sp(prereqs)
	var q = List[String]()
	for p in prereqs:
		if not in_table or self.memo.get_or(p, false) or (self.files.contains(p) and self.files.get_or(p, 0) > mt):
			q.append(p.clone())
	self.a_q = join_sp(q)
	self.a_oo = join_sp(dedup(r.oo))
	self.a_stem = r.stem.clone()
	for li in 0..r.recipe.length():
		line := r.recipe.get(li, "")
		num := r.lines.get(li, 0)
		self.curline = num
		self.autos_on = true
		ex := self.expand(line).trim()
		self.autos_on = false
		if self.failed: return
		var silent = false
		var ignore = false
		var k = 0
		while k < ex.length():
			ch := at(ex, k)
			if ch == 64:
				silent = true
				k += 1
			else if ch == 45:
				ignore = true
				k += 1
			else if ch == 43 or ch == 32 or ch == 9: k += 1
			else: break
		command := sub(ex, k, ex.length()).trim()
		if self.dry:
			self.emit(command)
			continue
		if not silent: self.emit(command.clone())
		ws := command.fields()
		var status = 0
		if ws.length() > 0:
			w0 := ws.get(0, "")
			if w0 == "false": status = 1
			else if w0 == "exit":
				if ws.length() > 1: status = ws.get(1, "").parse_int().get(2)
			else if w0 == "touch":
				for x in 1..ws.length():
					f := ws.get(x, "")
					if not f.starts_with("-"):
						tv := self.tick()
						self.files[f.clone()] = tv
			else if w0 == "rm":
				for x in 1..ws.length():
					f := ws.get(x, "")
					if not f.starts_with("-"): self.files.remove(f)
			else if w0 == "cp" and ws.length() == 3:
				src := ws.get(1, "")
				if not self.files.contains(src):
					self.emit("cp: cannot stat '{src}': No such file or directory")
					status = 1
				else:
					tv := self.tick()
					self.files[ws.get(2, "")] = tv
			else if w0 == "echo":
				var parts = List[String]()
				for x in 1..ws.length():
					parts.append(ws.get(x, "").replace("'", "").replace("\"", ""))
				self.emit(join_sp(parts))
		if status != 0:
			if ignore:
				self.emit("make: [Makefile:{num}: {t}] Error {status} (ignored)")
			else:
				self.emit("make: *** [Makefile:{num}: {t}] Error {status}")
				self.failed = true
				return
	if not self.dry and not self.phony.contains(t):
		tv := self.tick()
		self.files[t.clone()] = tv

fn var Sim.do_build(goals: List[String]) Unit:
	var gs = goals.clone()
	if gs.length() == 0:
		d := self.default_goal()
		if d == "":
			self.emit("make: *** No targets.  Stop.")
			return
		gs.append(d)
	for g in gs:
		self.ran = false
		self.update(g, "")
		if self.failed: return
		if not self.ran:
			r := self.resolve(g)
			if (r.found and r.recipe.length() > 0) or (self.files.contains(g) and not self.phony.contains(g)):
				self.emit("make: '{g}' is up to date.")
			else:
				self.emit("make: Nothing to be done for '{g}'.")

// ---------------------------------------------------------------- deps / targets

fn var Sim.visit(t: String, var visited: Set[String], var order: List[String]) Unit:
	if visited.contains(t): return
	if self.stack.contains(t):
		self.circular(t)
		return
	r := self.resolve(t)
	self.stack.append(t.clone())
	var all = dedup(r.prereqs)
	all.extend(dedup(r.oo))
	for p in all:
		self.visit(p, var visited, var order)
		if self.failed: return
	self.stack.pop()
	visited.add(t.clone())
	order.append(t.clone())

fn var Sim.do_deps(t: String) Unit:
	var visited = Set[String]()
	var order = List[String]()
	self.visit(t, var visited, var order)
	if self.failed: return
	var shown = List[String]()
	for x in order:
		if x != t: shown.append(x.clone())
	if shown.length() == 0:
		self.emit("(no prerequisites)")
		return
	for x in shown: self.emit(x)

fn fmt_rule(head: String, r: Rule) String:
	var s = head + ":"
	if r.prereqs.length() > 0: s += " " + join_sp(r.prereqs)
	if r.oo.length() > 0: s += " | " + join_sp(r.oo)
	return s

fn var Sim.do_targets() Unit:
	d := self.default_goal()
	if d != "": self.emit("default: {d}")
	for t in self.exorder.clone():
		self.emit(fmt_rule(t, self.exrules.get(t).get(Rule())))
	for r in self.prules.clone():
		self.emit(fmt_rule("pattern " + r.pat, r))
	if self.phony_order.length() > 0:
		self.emit("phony: " + join_sp(self.phony_order))

// ---------------------------------------------------------------- main

fn var Sim.request(raw: String, mk: List[String]) Unit:
	line := raw.trim_end()
	t := line.trim()
	if t == "" or t.starts_with("#"): return
	self.emit("> " + line)
	ws := t.fields()
	w := ws.get(0, "")
	if w == "files":
		if self.files.length() == 0:
			self.emit("(no files)")
			return
		for k in self.files.keys().sorted():
			self.emit("{k} {self.files.get_or(k, 0)}")
		return
	if w == "touch":
		if ws.length() == 2:
			tv := self.tick()
			self.files[ws.get(1, "")] = tv
		else if ws.length() == 3:
			if n := ws.get(2, "").parse_int():
				self.files[ws.get(1, "")] = n
				if n > self.clock: self.clock = n
			else:
				self.emit("bad request")
		else:
			self.emit("bad request")
		return
	if w == "rm":
		for x in 1..ws.length(): self.files.remove(ws.get(x, ""))
		return
	if w == "expand":
		self.reset([])
		self.parse(mk)
		if self.failed: return
		r := self.expand(sub(t, 6, t.length()).trim())
		if self.failed: return
		self.emit("[{r}]")
		return
	if w == "build" or w == "dry" or w == "deps" or w == "targets":
		var cmdargs = List[String]()
		var goals = List[String]()
		for x in 1..ws.length():
			a := ws.get(x, "")
			if idx := a.index_of("="):
				if idx > 0:
					cmdargs.append(a.clone())
					continue
			goals.append(a.clone())
		if w == "deps" and goals.length() != 1:
			self.emit("usage: deps TARGET")
			return
		self.reset(cmdargs)
		self.parse(mk)
		if self.failed: return
		self.dry = w == "dry"
		if w == "build" or w == "dry": self.do_build(goals)
		else if w == "deps": self.do_deps(goals.get(0, ""))
		else: self.do_targets()
		return
	self.emit("unknown request: {w}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	all := text.lines()
	var seps = List[Int]()
	for k in 0..all.length():
		if all.get(k, "") == "====" and seps.length() < 2: seps.append(k)
	var mk = List[String]()
	var tbl = List[String]()
	var reqs = List[String]()
	var section = 0
	for k in 0..all.length():
		l := all.get(k, "")
		if section < 2 and seps.contains(k):
			section += 1
			continue
		if section == 0: mk.append(l.clone())
		else if section == 1: tbl.append(l.clone())
		else: reqs.append(l.clone())
	var sim = Sim()
	var maxt = 0
	for l in tbl:
		f := l.fields()
		if f.length() != 2: continue
		if v := f.get(1, "").parse_int():
			if v < 0: continue
			sim.files[f.get(0, "")] = v
			if v > maxt: maxt = v
	sim.clock = maxt
	for l in reqs:
		sim.request(l, mk)
	if sim.out.length() > 0:
		print(sim.out.join("\n"))
