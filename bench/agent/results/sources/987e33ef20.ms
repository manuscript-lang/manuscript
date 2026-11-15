import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Var:
	value: String
	simple: Bool

type Rec:
	prereqs: List[String]
	oo: List[String]
	recipe: Int = -1

type Pat:
	pat: String
	prereqs: List[String]
	oo: List[String]
	recipe: Int = -1

type Line:
	text: String
	no: Int

type Res:
	found: Bool
	prereqs: List[String]
	oo: List[String]
	recipe: Int
	stem: String

type Cond:
	parent: Bool
	cond: Bool
	in_else: Bool
	line: Int

type Ctx:
	out: String = ""
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	vars: Map[String, Var] = Map[String, Var]()
	cmdvars: Set[String] = Set[String]()
	auto: Map[String, String] = Map[String, String]()
	expanding: Set[String] = Set[String]()
	rules: List[Rec] = List[Rec]()
	order: List[String] = List[String]()
	rule_idx: Map[String, Int] = Map[String, Int]()
	pats: List[Pat] = List[Pat]()
	recipes: List[List[Line]] = List[List[Line]]()
	phony: List[String] = List[String]()
	phony_set: Set[String] = Set[String]()
	default_goal: String = ""
	cur_line: Int = 0
	memo: Map[String, Bool] = Map[String, Bool]()
	stack: List[String] = List[String]()
	ran: Int = 0
	r_open: Bool = false
	r_rid: Int = 0
	r_line: Int = 0
	r_explicit: List[String] = List[String]()
	r_pats: List[Int] = List[Int]()

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\n" or c == "\r"

fn words(s: String) List[String]:
	var res = List[String]()
	var cur = ""
	for c in s.chars():
		if is_ws(c):
			if cur.length() > 0:
				res.append(cur.clone())
				cur = ""
		else:
			cur += c
	if cur.length() > 0:
		res.append(cur.clone())
	return res

fn join_range(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b and i < cs.length():
		out += cs.get(i, "")
		i += 1
	return out

fn sub(s: String, a: Int, b: Int) String:
	if a >= b: return ""
	r := s.slice(a, b)
	if v := r:
		return v
	return ""

fn dedup(xs: List[String]) List[String]:
	var seen = Set[String]()
	var res = List[String]()
	for x in xs:
		if not seen.contains(x):
			seen.add(x.clone())
			res.append(x.clone())
	return res

fn jw(xs: List[String]) String: xs.join(" ")

fn pat_match(pat: String, word: String) String?:
	pi := pat.index_of("%")
	if pi.is_none():
		if pat == word: return ""
		return none
	idx := pi.get(0)
	prefix := sub(pat, 0, idx)
	suffix := sub(pat, idx + 1, pat.length())
	if word.length() < prefix.length() + suffix.length(): return none
	if not word.starts_with(prefix): return none
	if not word.ends_with(suffix): return none
	return sub(word, prefix.length(), word.length() - suffix.length())

fn apply_rep(rep: String, stem: String) String:
	ri := rep.index_of("%")
	if ri.is_none(): return rep.clone()
	idx := ri.get(0)
	return sub(rep, 0, idx) + stem + sub(rep, idx + 1, rep.length())

fn patsubst_words(pat: String, rep: String, text: String) String:
	var res = List[String]()
	for w in words(text):
		m := pat_match(pat, w)
		if stem := m:
			res.append(apply_rep(rep, stem))
		else:
			res.append(w.clone())
	return jw(res)

fn glob_m(p: List[String], pi: Int, s: List[String], si: Int) Bool:
	if pi >= p.length(): return si >= s.length()
	c := p.get(pi, "")
	if c == "*":
		var k = si
		while true:
			if glob_m(p, pi + 1, s, k): return true
			if k >= s.length(): return false
			if s.get(k, "") == "/": return false
			k += 1
		return false
	if si >= s.length(): return false
	d := s.get(si, "")
	if c == "?":
		if d == "/": return false
		return glob_m(p, pi + 1, s, si + 1)
	if c != d: return false
	return glob_m(p, pi + 1, s, si + 1)

fn is_func(n: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(n)

fn split_args(rest: String) List[String]:
	var res = List[String]()
	var cur = ""
	var depth = 0
	for c in rest.chars():
		if c == "(" or c == "\{":
			depth += 1
		else if c == ")" or c == "\}":
			depth -= 1
		if c == "," and depth <= 0:
			res.append(cur.trim())
			cur = ""
		else:
			cur += c
	res.append(cur.trim())
	return res

fn last_slash(w: String) Int:
	var res = -1
	var i = 0
	for c in w.chars():
		if c == "/": res = i
		i += c.length()
	return res

fn dot_in_last(w: String) Int:
	ls := last_slash(w)
	var res = -1
	var i = 0
	for c in w.chars():
		if c == "." and i > ls: res = i
		i += c.length()
	return res

fn strip_comment(s: String) String:
	var out = ""
	cs := s.chars()
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

fn logical_lines(lines: List[String]) List[Line]:
	var res = List[Line]()
	var i = 0
	while i < lines.length():
		no := i + 1
		var cur = lines.get(i, "")
		i += 1
		while cur.ends_with("\\"):
			cur = sub(cur, 0, cur.length() - 1).trim_end()
			if i < lines.length():
				cur = cur + " " + lines.get(i, "").trim_start()
				i += 1
			else:
				break
		res.append(Line(cur, no))
	return res

fn find_col(cs: List[String]) Int:
	var i = 0
	var depth = 0
	var opener = ""
	var closer = ""
	while i < cs.length():
		c := cs.get(i, "")
		if depth > 0:
			if c == opener: depth += 1
			else if c == closer: depth -= 1
			i += 1
			continue
		if c == "$":
			d := cs.get(i + 1, "")
			if d == "(":
				opener = "("
				closer = ")"
				depth = 1
				i += 2
				continue
			if d == "\{":
				opener = "\{"
				closer = "\}"
				depth = 1
				i += 2
				continue
			i += 2
			continue
		if c == ";": return -1
		if c == ":": return i
		i += 1
	return -1

fn find_semi(cs: List[String]) Int:
	var i = 0
	var depth = 0
	var opener = ""
	var closer = ""
	while i < cs.length():
		c := cs.get(i, "")
		if depth > 0:
			if c == opener: depth += 1
			else if c == closer: depth -= 1
			i += 1
			continue
		if c == "$":
			d := cs.get(i + 1, "")
			if d == "(":
				opener = "("
				closer = ")"
				depth = 1
				i += 2
				continue
			if d == "\{":
				opener = "\{"
				closer = "\}"
				depth = 1
				i += 2
				continue
			i += 2
			continue
		if c == ";": return i
		i += 1
	return -1

fn Ctx.fatal(msg: String) Error:
	if self.cur_line > 0:
		return Error("Makefile:{self.cur_line}: *** {msg}.  Stop.")
	return Error("make: *** {msg}.  Stop.")

fn var Ctx.emit(s: String) Unit:
	self.out += s
	self.out += "\n"

fn var Ctx.next_clock() Int:
	self.clock += 1
	return self.clock

fn var Ctx.lookup(name: String) String!:
	if self.auto.contains(name):
		return ok(self.auto.get_or(name, ""))
	if not self.vars.contains(name):
		return ok("")
	v := self.vars.get_or(name, Var("", true))
	if v.simple:
		return ok(v.value.clone())
	if self.expanding.contains(name):
		return error(self.fatal("Recursive variable '{name}' references itself (eventually)"))
	self.expanding.add(name.clone())
	r := self.expand(v.value)
	self.expanding.remove(name)
	return r

fn var Ctx.expand(text: String) String!:
	if not text.contains("$"): return ok(text.clone())
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
			continue
		if d == "(" or d == "\{":
			closer := if d == "(": ")" else: "\}"
			var depth = 1
			var j = i + 2
			while j < n and depth > 0:
				e := cs.get(j, "")
				if e == d: depth += 1
				else if e == closer: depth -= 1
				if depth > 0: j += 1
			if depth > 0:
				return error(self.fatal("unterminated variable reference"))
			inner := join_range(cs, i + 2, j)
			out += self.eval_ref(inner)?
			i = j + 1
			continue
		out += self.lookup(d)?
		i += 2
	return ok(out)

fn var Ctx.eval_ref(inner: String) String!:
	var sp = -1
	var k = 0
	for c in inner.chars():
		if c == " " or c == "\t":
			sp = k
			break
		k += c.length()
	if sp > 0:
		fname := sub(inner, 0, sp)
		if is_func(fname):
			args := split_args(sub(inner, sp + 1, inner.length()))
			return self.call(fname, args)
	name := (self.expand(inner)?).trim()
	ci := name.index_of(":")
	if c := ci:
		if c > 0:
			rest := sub(name, c + 1, name.length())
			ei := rest.index_of("=")
			if e := ei:
				var from = sub(rest, 0, e)
				var to = sub(rest, e + 1, rest.length())
				if not from.contains("%"):
					from = "%" + from
					to = "%" + to
				val := self.lookup(sub(name, 0, c))?
				return ok(patsubst_words(from, to, val))
	return self.lookup(name)

fn var Ctx.arg(args: List[String], i: Int) String!:
	return self.expand(args.get(i, ""))

fn var Ctx.call(name: String, args: List[String]) String!:
	if name == "subst":
		from := self.arg(args, 0)?
		to := self.arg(args, 1)?
		text := self.arg(args, 2)?
		if from.length() == 0: return ok(text)
		return ok(text.replace(from, to))
	if name == "patsubst":
		p := self.arg(args, 0)?
		r := self.arg(args, 1)?
		t := self.arg(args, 2)?
		return ok(patsubst_words(p, r, t))
	if name == "strip":
		return ok(jw(words(self.arg(args, 0)?)))
	if name == "findstring":
		f := self.arg(args, 0)?
		t := self.arg(args, 1)?
		if t.contains(f): return ok(f)
		return ok("")
	if name == "filter" or name == "filter-out":
		pats := words(self.arg(args, 0)?)
		ws := words(self.arg(args, 1)?)
		var res = List[String]()
		for w in ws:
			var hit = false
			for p in pats:
				if pat_match(p, w).is_some(): hit = true
			if hit == (name == "filter"):
				res.append(w.clone())
		return ok(jw(res))
	if name == "sort":
		var ws = words(self.arg(args, 0)?)
		ws.sort()
		return ok(jw(dedup(ws)))
	if name == "word":
		ns := (self.arg(args, 0)?).trim()
		ws := words(self.arg(args, 1)?)
		if n := ns.parse_int():
			if n >= 1 and n <= ws.length(): return ok(ws.get(n - 1, ""))
		return ok("")
	if name == "wordlist":
		ss := (self.arg(args, 0)?).trim()
		es := (self.arg(args, 1)?).trim()
		ws := words(self.arg(args, 2)?)
		sv := ss.parse_int()
		ev := es.parse_int()
		if sv.is_none() or ev.is_none(): return ok("")
		s := sv.get(0)
		var e = ev.get(0)
		if s < 1 or e < s or s > ws.length(): return ok("")
		if e > ws.length(): e = ws.length()
		var res = List[String]()
		var k = s
		while k <= e:
			res.append(ws.get(k - 1, ""))
			k += 1
		return ok(jw(res))
	if name == "words":
		return ok("{words(self.arg(args, 0)?).length()}")
	if name == "firstword":
		ws := words(self.arg(args, 0)?)
		return ok(ws.get(0, ""))
	if name == "lastword":
		ws := words(self.arg(args, 0)?)
		return ok(ws.get(ws.length() - 1, ""))
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		var res = List[String]()
		for w in words(self.arg(args, 0)?):
			ls := last_slash(w)
			if name == "dir":
				if ls < 0: res.append("./")
				else: res.append(sub(w, 0, ls + 1))
			else if name == "notdir":
				res.append(sub(w, ls + 1, w.length()))
			else:
				di := dot_in_last(w)
				if name == "suffix":
					if di >= 0: res.append(sub(w, di, w.length()))
				else:
					if di >= 0: res.append(sub(w, 0, di))
					else: res.append(w.clone())
		return ok(jw(res))
	if name == "addprefix" or name == "addsuffix":
		x := self.arg(args, 0)?
		var res = List[String]()
		for w in words(self.arg(args, 1)?):
			if name == "addprefix": res.append(x + w)
			else: res.append(w + x)
		return ok(jw(res))
	if name == "wildcard":
		var res = List[String]()
		for p in words(self.arg(args, 0)?):
			if p.contains("*") or p.contains("?"):
				var ms = List[String]()
				pc := p.chars()
				for f in self.files.keys():
					if glob_m(pc, 0, f.chars(), 0): ms.append(f.clone())
				ms.sort()
				for m in ms: res.append(m.clone())
			else:
				if self.files.contains(p): res.append(p.clone())
		return ok(jw(res))
	if name == "foreach":
		vname := (self.arg(args, 0)?).trim()
		lst := words(self.arg(args, 1)?)
		had := self.vars.contains(vname)
		old := self.vars.get_or(vname, Var("", true))
		oval := old.value.clone()
		osimple := old.simple
		var res = List[String]()
		for w in lst:
			self.vars[vname.clone()] = Var(w.clone(), true)
			res.append(self.arg(args, 2)?)
		if had: self.vars[vname.clone()] = Var(oval, osimple)
		else: self.vars.remove(vname)
		return ok(res.join(" "))
	if name == "if":
		c := (self.arg(args, 0)?).trim()
		if c.length() > 0: return self.arg(args, 1)
		return self.arg(args, 2)
	if name == "info":
		t := self.arg(args, 0)?
		self.emit(t)
		return ok("")
	if name == "error":
		t := self.arg(args, 0)?
		return error(self.fatal(t))
	return ok("")

// ---------------- parsing ----------------

fn var Ctx.reset() Unit:
	self.vars = Map[String, Var]()
	self.cmdvars = Set[String]()
	self.auto = Map[String, String]()
	self.expanding = Set[String]()
	self.rules = List[Rec]()
	self.order = List[String]()
	self.rule_idx = Map[String, Int]()
	self.pats = List[Pat]()
	self.recipes = List[List[Line]]()
	self.phony = List[String]()
	self.phony_set = Set[String]()
	self.default_goal = ""
	self.cur_line = 0
	self.memo = Map[String, Bool]()
	self.stack = List[String]()
	self.ran = 0
	self.r_open = false

fn var Ctx.close_rule() Unit:
	if not self.r_open: return
	self.r_open = false
	has := self.recipes.get(self.r_rid, List[Line]()).length() > 0
	if not has: return
	for t in self.r_explicit.clone():
		ri := self.rule_idx.get_or(t, 0)
		if self.rules[ri].recipe >= 0:
			self.emit("Makefile:{self.r_line}: warning: overriding recipe for target '{t}'")
		self.rules[ri].recipe = self.r_rid
	for pi in self.r_pats.clone():
		self.pats[pi].recipe = self.r_rid

fn var Ctx.defined_nonempty(name: String) Bool:
	if not self.vars.contains(name): return false
	v := self.vars.get_or(name, Var("", true))
	return v.value.length() > 0

fn var Ctx.eval_cond(fw: String, rest: String) Bool!:
	if fw == "ifdef" or fw == "ifndef":
		name := (self.expand(rest)?).trim()
		d := self.defined_nonempty(name)
		if fw == "ifdef": return ok(d)
		return ok(not d)
	cs := rest.trim().chars()
	n := cs.length()
	if n < 2 or cs.get(0, "") != "(" or cs.get(n - 1, "") != ")":
		return error(self.fatal("invalid syntax in conditional"))
	var depth = 0
	var commas = List[Int]()
	var i = 1
	while i < n - 1:
		c := cs.get(i, "")
		if c == "(" or c == "\{": depth += 1
		else if c == ")" or c == "\}": depth -= 1
		else if c == "," and depth == 0: commas.append(i)
		i += 1
	if commas.length() != 1:
		return error(self.fatal("invalid syntax in conditional"))
	ci := commas.get(0, 0)
	a := (self.expand(join_range(cs, 1, ci).trim())?).trim()
	b := (self.expand(join_range(cs, ci + 1, n - 1).trim())?).trim()
	eq := a == b
	if fw == "ifeq": return ok(eq)
	return ok(not eq)

fn var Ctx.set_var(name: String, op: String, value: String) Unit!:
	if self.cmdvars.contains(name): return ok(unit)
	if op == "=":
		self.vars[name] = Var(value.clone(), false)
	else if op == ":":
		v := self.expand(value)?
		self.vars[name] = Var(v, true)
	else if op == "?":
		if not self.vars.contains(name):
			self.vars[name] = Var(value.clone(), false)
	else:
		if not self.vars.contains(name):
			self.vars[name] = Var(value.clone(), false)
		else:
			old := self.vars.get_or(name, Var("", true))
			if old.simple:
				v := self.expand(value)?
				var nv = old.value.clone()
				if nv.length() > 0 and v.length() > 0: nv += " "
				nv += v
				self.vars[name] = Var(nv, true)
			else:
				var nv = old.value.clone()
				if nv.length() > 0 and value.length() > 0: nv += " "
				nv += value
				self.vars[name] = Var(nv, false)
	return ok(unit)

fn var Ctx.add_rule(ln: Int, line: String, col: Int, cs: List[String]) Unit!:
	tt := join_range(cs, 0, col)
	after := join_range(cs, col + 1, cs.length())
	acs := after.chars()
	semi := find_semi(acs)
	var prereq_text = after.clone()
	var cmd = ""
	if semi >= 0:
		prereq_text = join_range(acs, 0, semi)
		cmd = join_range(acs, semi + 1, acs.length()).trim_start()
	tgts := words(self.expand(tt)?)
	pre := self.expand(prereq_text)?
	var normal = List[String]()
	var oo = List[String]()
	bar := pre.index_of("|")
	if b := bar:
		normal = words(sub(pre, 0, b))
		oo = words(sub(pre, b + 1, pre.length()))
	else:
		normal = words(pre)
	self.r_open = true
	self.r_rid = self.recipes.length()
	self.recipes.append(List[Line]())
	self.r_line = ln
	self.r_explicit = List[String]()
	self.r_pats = List[Int]()
	if tgts.length() == 1 and tgts.get(0, "") == ".PHONY":
		for p in normal:
			if not self.phony_set.contains(p):
				self.phony_set.add(p.clone())
				self.phony.append(p.clone())
	else:
		for t in tgts:
			if t.contains("%"):
				self.r_pats.append(self.pats.length())
				self.pats.append(Pat(t.clone(), normal.clone(), oo.clone(), -1))
			else:
				if not self.rule_idx.contains(t):
					self.rule_idx[t.clone()] = self.rules.length()
					self.rules.append(Rec(List[String](), List[String](), -1))
					self.order.append(t.clone())
					if self.default_goal.length() == 0 and not t.starts_with("."):
						self.default_goal = t.clone()
				ri := self.rule_idx.get_or(t, 0)
				for p in normal: self.rules[ri].prereqs.append(p.clone())
				for p in oo: self.rules[ri].oo.append(p.clone())
				self.r_explicit.append(t.clone())
	if cmd.trim().length() > 0:
		self.recipes[self.r_rid].append(Line(cmd, ln))
	return ok(unit)

fn var Ctx.parse(lines: List[String]) Unit!:
	ll := logical_lines(lines)
	var stack = List[Cond]()
	for ln in ll:
		self.cur_line = ln.no
		raw := ln.text
		var active = true
		if stack.length() > 0:
			top := stack.get(stack.length() - 1, Cond(true, true, false, 0))
			active = top.parent and (if top.in_else: not top.cond else: top.cond)
		if raw.starts_with("\t"):
			if not active: continue
			var k = 0
			cr := raw.chars()
			while k < cr.length() and cr.get(k, "") == "\t": k += 1
			body := join_range(cr, k, cr.length())
			if body.trim().length() == 0: continue
			if not self.r_open:
				return error(self.fatal("recipe commences before first target"))
			self.recipes[self.r_rid].append(Line(body, ln.no))
			continue
		line := strip_comment(raw).trim()
		if line.length() == 0: continue
		var fw = line.clone()
		var rest = ""
		var sp = -1
		var q = 0
		for c in line.chars():
			if c == " " or c == "\t":
				sp = q
				break
			q += c.length()
		if sp >= 0:
			fw = sub(line, 0, sp)
			rest = sub(line, sp + 1, line.length()).trim()
		if fw == "ifdef" or fw == "ifndef" or fw == "ifeq" or fw == "ifneq":
			self.close_rule()
			var cond = false
			if active:
				cond = self.eval_cond(fw, rest)?
			stack.append(Cond(active, cond, false, ln.no))
			continue
		if line == "else":
			self.close_rule()
			if stack.length() == 0:
				return error(self.fatal("extraneous 'else'"))
			ti := stack.length() - 1
			if stack[ti].in_else:
				return error(self.fatal("extraneous 'else'"))
			stack[ti].in_else = true
			continue
		if fw == "endif":
			self.close_rule()
			if stack.length() == 0:
				return error(self.fatal("extraneous 'endif'"))
			stack.pop()
			continue
		if not active: continue
		self.close_rule()
		cs := line.chars()
		n := cs.length()
		var eq = -1
		var z = 0
		while z < n:
			if cs.get(z, "") == "=":
				eq = z
				break
			z += 1
		col := find_col(cs)
		if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
			var op = "="
			var name_end = eq
			if eq > 0:
				pc := cs.get(eq - 1, "")
				if pc == ":" or pc == "?" or pc == "+":
					op = pc
					name_end = eq - 1
			name := (self.expand(join_range(cs, 0, name_end))?).trim()
			if name.length() == 0:
				return error(self.fatal("empty variable name"))
			value := join_range(cs, eq + 1, n).trim()
			self.set_var(name, op, value)?
			continue
		if col >= 0:
			self.add_rule(ln.no, line, col, cs)?
			continue
		e := self.expand(line)?
		if e.trim().length() > 0:
			return error(self.fatal("missing separator"))
	self.close_rule()
	if stack.length() > 0:
		self.cur_line = stack.get(stack.length() - 1, Cond(true, true, false, 0)).line
		return error(self.fatal("missing 'endif'"))
	self.cur_line = 0
	return ok(unit)

// ---------------- resolution and building ----------------

fn var Ctx.pat_find(t: String, depth: Int) Int:
	for i in 0..self.pats.length():
		if self.pats[i].recipe < 0: continue
		stem := pat_match(self.pats[i].pat, t)
		if st := stem:
			if st.length() == 0: continue
			if not self.pat_match_has_pct(i): continue
			var ok_all = true
			for p in self.pats[i].prereqs.clone():
				if not self.can_make(apply_rep(p, st), depth + 1): ok_all = false
			for p in self.pats[i].oo.clone():
				if not self.can_make(apply_rep(p, st), depth + 1): ok_all = false
			if ok_all: return i
	return -1

fn Ctx.pat_match_has_pct(i: Int) Bool:
	return self.pats[i].pat.contains("%")

fn var Ctx.can_make(name: String, depth: Int) Bool:
	if self.files.contains(name): return true
	if self.rule_idx.contains(name): return true
	if self.phony_set.contains(name): return true
	if depth > 8: return false
	return self.pat_find(name, depth) >= 0

fn var Ctx.resolve(t: String) Res:
	var has_exp = false
	var ei = 0
	if self.rule_idx.contains(t):
		has_exp = true
		ei = self.rule_idx.get_or(t, 0)
		if self.rules[ei].recipe >= 0:
			return Res(true, self.rules[ei].prereqs.clone(), self.rules[ei].oo.clone(), self.rules[ei].recipe, "")
	pi := self.pat_find(t, 0)
	if pi >= 0:
		st := pat_match(self.pats[pi].pat, t).get("")
		var pre = List[String]()
		var oo = List[String]()
		for p in self.pats[pi].prereqs: pre.append(apply_rep(p, st))
		for p in self.pats[pi].oo: oo.append(apply_rep(p, st))
		if has_exp:
			for p in self.rules[ei].prereqs: pre.append(p.clone())
			for p in self.rules[ei].oo: oo.append(p.clone())
		return Res(true, pre, oo, self.pats[pi].recipe, st)
	if has_exp:
		return Res(true, self.rules[ei].prereqs.clone(), self.rules[ei].oo.clone(), -1, "")
	return Res(false, List[String](), List[String](), -1, "")

fn var Ctx.cycle_error(t: String) Error:
	var parts = List[String]()
	var on = false
	for s in self.stack:
		if s == t: on = true
		if on: parts.append(s.clone())
	parts.append(t.clone())
	return Error("make: *** Circular dependency detected: {parts.join(" -> ")}.  Stop.")

fn var Ctx.update(t: String, needed_by: String, dry: Bool) Bool!:
	if self.memo.contains(t): return ok(self.memo.get_or(t, false))
	if self.stack.contains(t):
		return error(self.cycle_error(t))
	res := self.resolve(t)
	if not res.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)
		if self.phony_set.contains(t):
			self.memo[t.clone()] = true
			return ok(true)
		if needed_by.length() > 0:
			return error(Error("make: *** No rule to make target '{t}', needed by '{needed_by}'.  Stop."))
		return error(Error("make: *** No rule to make target '{t}'.  Stop."))
	self.stack.append(t.clone())
	in0 := self.files.contains(t)
	mt0 := self.files.get_or(t, 0)
	pre := dedup(res.prereqs)
	var any = false
	var newer = false
	var q = List[String]()
	for p in pre:
		ch := self.update(p.clone(), t.clone(), dry)?
		if ch: any = true
		pnewer := self.files.contains(p) and self.files.get_or(p, 0) > mt0
		if in0 and pnewer: newer = true
		if (not in0) or ch or pnewer: q.append(p.clone())
	for o in dedup(res.oo):
		_oc := self.update(o.clone(), t.clone(), dry)?
	self.stack.pop()
	var changed = false
	if self.phony_set.contains(t) or not self.files.contains(t) or any or newer:
		changed = true
		if res.recipe >= 0:
			self.run_recipe(t.clone(), res, pre, q, dry)?
	self.memo[t.clone()] = changed
	return ok(changed)

fn var Ctx.run_recipe(t: String, res: Res, pre: List[String], q: List[String], dry: Bool) Unit!:
	self.ran += 1
	self.auto = Map[String, String]()
	self.auto["@"] = t.clone()
	self.auto["<"] = res.prereqs.get(0, "")
	self.auto["^"] = jw(pre)
	self.auto["?"] = jw(q)
	self.auto["|"] = jw(dedup(res.oo))
	self.auto["*"] = res.stem.clone()
	lines := self.recipes.get(res.recipe, List[Line]())
	for ln in lines:
		self.cur_line = ln.no
		text := (self.expand(ln.text)?).trim()
		cs := text.chars()
		var k = 0
		var silent = false
		var ign = false
		while k < cs.length():
			c := cs.get(k, "")
			if c == "@": silent = true
			else if c == "-": ign = true
			else if c == "+" or c == " " or c == "\t": k += 0
			else: break
			k += 1
		cmd := join_range(cs, k, cs.length()).trim()
		if dry:
			self.emit(cmd)
			continue
		if not silent: self.emit(cmd)
		status := self.simulate(cmd)
		if status != 0:
			if ign:
				self.emit("make: [Makefile:{ln.no}: {t}] Error {status} (ignored)")
			else:
				return error(Error("make: *** [Makefile:{ln.no}: {t}] Error {status}"))
	self.auto = Map[String, String]()
	self.cur_line = 0
	if not dry and not self.phony_set.contains(t):
		nc := self.next_clock()
		self.files[t.clone()] = nc
	return ok(unit)

fn var Ctx.simulate(cmd: String) Int:
	ws := words(cmd)
	if ws.length() == 0: return 0
	first := ws.get(0, "")
	if first == "false": return 1
	if first == "exit":
		if ws.length() < 2: return 0
		if n := ws.get(1, "").parse_int(): return n
		return 2
	if first == "touch":
		for i in 1..ws.length():
			w := ws.get(i, "")
			if not w.starts_with("-"):
				nc := self.next_clock()
				self.files[w.clone()] = nc
		return 0
	if first == "rm":
		for i in 1..ws.length():
			w := ws.get(i, "")
			if not w.starts_with("-"): self.files.remove(w)
		return 0
	if first == "cp":
		if ws.length() == 3:
			src := ws.get(1, "")
			if not self.files.contains(src):
				self.emit("cp: cannot stat '{src}': No such file or directory")
				return 1
			nc := self.next_clock()
			self.files[ws.get(2, "")] = nc
		return 0
	if first == "echo":
		var parts = List[String]()
		for i in 1..ws.length():
			parts.append(ws.get(i, "").replace("'", "").replace("\"", ""))
		self.emit(parts.join(" "))
		return 0
	return 0

fn var Ctx.begin(args: List[String], with_vars: Bool) List[String]:
	self.reset()
	var targets = List[String]()
	for a in args:
		ei := a.index_of("=")
		if e := ei:
			if e > 0 and with_vars:
				name := sub(a, 0, e)
				self.vars[name.clone()] = Var(sub(a, e + 1, a.length()), false)
				self.cmdvars.add(name.clone())
				continue
		targets.append(a.clone())
	return targets

fn var Ctx.do_build(args: List[String], dry: Bool, mk: List[String]) Unit:
	goals0 := self.begin(args, true)
	r := self.parse(mk)
	if r.is_error():
		self.emit(r.err().message)
		return
	var goals = goals0.clone()
	if goals.length() == 0:
		if self.default_goal.length() == 0:
			self.emit("make: *** No targets.  Stop.")
			return
		goals.append(self.default_goal.clone())
	for g in goals:
		before := self.ran
		u := self.update(g.clone(), "", dry)
		if u.is_error():
			self.emit(u.err().message)
			return
		if self.ran == before:
			res := self.resolve(g)
			if (res.found and res.recipe >= 0) or (self.files.contains(g) and not self.phony_set.contains(g)):
				self.emit("make: '{g}' is up to date.")
			else:
				self.emit("make: Nothing to be done for '{g}'.")

fn var Ctx.visit(t: String, var done: Set[String], var outl: List[String]) Unit!:
	res := self.resolve(t)
	self.stack.append(t.clone())
	var all = dedup(res.prereqs)
	for o in dedup(res.oo): all.append(o)
	for p in all:
		if self.stack.contains(p):
			return error(self.cycle_error(p))
		if done.contains(p): continue
		self.visit(p.clone(), var done, var outl)?
		done.add(p.clone())
		outl.append(p.clone())
	self.stack.pop()
	return ok(unit)

fn var Ctx.do_deps(args: List[String], mk: List[String]) Unit:
	ts := self.begin(args, true)
	r := self.parse(mk)
	if r.is_error():
		self.emit(r.err().message)
		return
	if ts.length() != 1:
		self.emit("usage: deps TARGET")
		return
	var done = Set[String]()
	var outl = List[String]()
	v := self.visit(ts.get(0, ""), var done, var outl)
	if v.is_error():
		self.emit(v.err().message)
		return
	if outl.length() == 0:
		self.emit("(no prerequisites)")
		return
	for x in outl: self.emit(x)

fn fmt_rule(head: String, pre: List[String], oo: List[String]) String:
	var s = head + ":"
	if pre.length() > 0: s += " " + jw(pre)
	if oo.length() > 0: s += " | " + jw(oo)
	return s

fn var Ctx.do_targets(args: List[String], mk: List[String]) Unit:
	self.begin(args, true)
	r := self.parse(mk)
	if r.is_error():
		self.emit(r.err().message)
		return
	if self.default_goal.length() > 0:
		self.emit("default: {self.default_goal}")
	for t in self.order.clone():
		ri := self.rule_idx.get_or(t, 0)
		self.emit(fmt_rule(t, self.rules[ri].prereqs, self.rules[ri].oo))
	for p in self.pats.clone():
		self.emit(fmt_rule("pattern " + p.pat, p.prereqs, p.oo))
	if self.phony.length() > 0:
		self.emit("phony: " + jw(self.phony))

fn var Ctx.do_expand(text: String, mk: List[String]) Unit:
	self.begin(List[String](), false)
	r := self.parse(mk)
	if r.is_error():
		self.emit(r.err().message)
		return
	e := self.expand(text)
	if e.is_error():
		self.emit(e.err().message)
		return
	if v := e:
		self.emit("[{v}]")

fn var Ctx.request(line: String, mk: List[String]) Unit:
	ws := words(line)
	cmd := ws.get(0, "")
	var args = List[String]()
	for i in 1..ws.length(): args.append(ws.get(i, ""))
	if cmd == "build": self.do_build(args, false, mk)
	else if cmd == "dry": self.do_build(args, true, mk)
	else if cmd == "deps": self.do_deps(args, mk)
	else if cmd == "targets": self.do_targets(args, mk)
	else if cmd == "expand":
		t := line.trim()
		self.do_expand(sub(t, 6, t.length()).trim(), mk)
	else if cmd == "files":
		if self.files.length() == 0:
			self.emit("(no files)")
		else:
			var ks = self.files.keys().clone()
			ks.sort()
			for k in ks: self.emit("{k} {self.files.get_or(k, 0)}")
	else if cmd == "touch":
		if args.length() == 1:
			nc := self.next_clock()
			self.files[args.get(0, "")] = nc
		else if args.length() == 2:
			if n := args.get(1, "").parse_int():
				self.files[args.get(0, "")] = n
				if n > self.clock: self.clock = n
			else:
				self.emit("bad request")
		else:
			self.emit("bad request")
	else if cmd == "rm":
		for a in args: self.files.remove(a)
	else:
		self.emit("unknown request: {cmd}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	raw := read_all(stdin(), none)?
	text := raw.decode_utf8().ok_or(Error("bad utf8"))?
	all := text.lines()
	var mk = List[String]()
	var tbl = List[String]()
	var reqs = List[String]()
	var section = 0
	for l0 in all:
		l := l0.trim_end()
		if section < 2 and l == "====":
			section += 1
			continue
		if section == 0: mk.append(l0.clone())
		else if section == 1: tbl.append(l.clone())
		else: reqs.append(l0.clone())
	var ctx = Ctx()
	for l in tbl:
		ws := words(l)
		if ws.length() == 2:
			if n := ws.get(1, "").parse_int():
				if n >= 0:
					ctx.files[ws.get(0, "")] = n
					if n > ctx.clock: ctx.clock = n
	for l in reqs:
		t := l.trim()
		if t.length() == 0 or t.starts_with("#"): continue
		ctx.emit("> " + l.trim_end())
		ctx.request(t, mk)
	print(ctx.out, end: "")
