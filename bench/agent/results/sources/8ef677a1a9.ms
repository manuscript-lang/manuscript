import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type RLine:
	text: String
	line: Int

type ERule:
	name: String
	pre: List[String] = []
	oo: List[String] = []
	rec: List[RLine] = []

type PRule:
	pat: String
	pre: List[String] = []
	oo: List[String] = []
	rec: List[RLine] = []

type Resolved:
	kind: Int = 0
	pre: List[String] = []
	oo: List[String] = []
	rec: List[RLine] = []
	stem: String = ""

type Cond:
	parent: Bool
	value: Bool
	in_else: Bool
	line: Int
	active: Bool

type Ctx:
	files: Map[String, Int] = Map[String, Int]()
	clock: Int = 0
	out: String = ""
	mf: String = ""
	vals: Map[String, String] = Map[String, String]()
	simples: Set[String] = Set[String]()
	cmd: Set[String] = Set[String]()
	binds: Map[String, String] = Map[String, String]()
	auto: Map[String, String] = Map[String, String]()
	expanding: List[String] = []
	line: Int = 0
	erules: List[ERule] = []
	eidx: Map[String, Int] = Map[String, Int]()
	prules: List[PRule] = []
	phony: Set[String] = Set[String]()
	phony_order: List[String] = []
	default_goal: String = ""
	conds: List[Cond] = []
	pend_open: Bool = false
	pend_targets: List[String] = []
	pend_pidx: List[Int] = []
	pend_rec: List[RLine] = []
	pend_line: Int = 0
	memo: Map[String, Bool] = Map[String, Bool]()
	stack: List[String] = []
	ran: Int = 0
	dry: Bool = false

fn fatal(ctx: Ctx, msg: String) Error:
	if ctx.line == 0:
		return Error("make: *** {msg}.  Stop.")
	return Error("Makefile:{ctx.line}: *** {msg}.  Stop.")

fn sub(cs: List[String], a: Int, b: Int) String:
	var r = ""
	var i = a
	while i < b and i < cs.length():
		r += cs.get(i, "")
		i += 1
	return r

fn sl(s: String, a: Int, b: Int) String:
	if r := s.slice(a, b):
		return r
	else:
		return ""

fn is_ws(c: String) Bool:
	return c == " " or c == "\t"

fn trim_st(s: String) String:
	return s.trim_chars(" \t")

fn join_ws(ws: List[String]) String:
	return ws.join(" ")

fn match_pat(pat: String, w: String) String?:
	if i := pat.index_of("%"):
		prefix := sl(pat, 0, i)
		suffix := sl(pat, i + 1, pat.length())
		if not w.starts_with(prefix):
			return none
		if not w.ends_with(suffix):
			return none
		if w.length() < prefix.length() + suffix.length():
			return none
		return sl(w, prefix.length(), w.length() - suffix.length())
	if w == pat:
		return ""
	return none

fn subst_pat(rep: String, stem: String) String:
	if i := rep.index_of("%"):
		return sl(rep, 0, i) + stem + sl(rep, i + 1, rep.length())
	return rep.clone()

fn patsubst_words(pat: String, rep: String, text: String) String:
	var res = List[String]()
	for w in text.fields():
		if stem := match_pat(pat, w):
			res.append(subst_pat(rep, stem))
		else:
			res.append(w.clone())
	return join_ws(res)

fn split_args(raw: String) List[String]:
	var res = List[String]()
	var cur = ""
	var depth = 0
	for c in raw.chars():
		if c == "(" or c == "\{":
			depth += 1
		else if c == ")" or c == "\}":
			depth -= 1
		if c == "," and depth == 0:
			res.append(cur.clone())
			cur = ""
		else:
			cur += c
	res.append(cur.clone())
	return res

fn is_func(name: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(name)

fn glob(p: List[String], pi: Int, s: List[String], si: Int) Bool:
	if pi == p.length():
		return si == s.length()
	c := p.get(pi, "")
	if c == "*":
		var k = si
		while true:
			if glob(p, pi + 1, s, k):
				return true
			if k < s.length() and s.get(k, "") != "/":
				k += 1
			else:
				return false
		return false
	if si >= s.length():
		return false
	if c == "?":
		if s.get(si, "") == "/":
			return false
		return glob(p, pi + 1, s, si + 1)
	if c != s.get(si, ""):
		return false
	return glob(p, pi + 1, s, si + 1)

fn ext_pos(w: String) Int:
	var last_slash = -1
	var last_dot = -1
	cs := w.chars()
	for i in 0..cs.length():
		c := cs.get(i, "")
		if c == "/":
			last_slash = i
		if c == ".":
			last_dot = i
	if last_dot > last_slash:
		return last_dot
	return -1

fn arg(var ctx: Ctx, args: List[String], i: Int) String!:
	if i >= args.length():
		return ok("")
	r := expand(var ctx, trim_st(args.get(i, "")))?
	return ok(r)

fn call_fn(var ctx: Ctx, name: String, raw: String) String!:
	args := split_args(raw)
	if name == "subst":
		from := arg(var ctx, args, 0)?
		to := arg(var ctx, args, 1)?
		text := arg(var ctx, args, 2)?
		if from == "":
			return ok(text)
		return ok(text.replace(from, to))
	if name == "patsubst":
		pat := arg(var ctx, args, 0)?
		rep := arg(var ctx, args, 1)?
		text := arg(var ctx, args, 2)?
		return ok(patsubst_words(pat, rep, text))
	if name == "strip":
		text := arg(var ctx, args, 0)?
		return ok(join_ws(text.fields()))
	if name == "findstring":
		find := arg(var ctx, args, 0)?
		text := arg(var ctx, args, 1)?
		if text.contains(find):
			return ok(find)
		return ok("")
	if name == "filter" or name == "filter-out":
		pats := (arg(var ctx, args, 0)?).fields()
		ws := (arg(var ctx, args, 1)?).fields()
		var res = List[String]()
		for w in ws:
			var hit = false
			for p in pats:
				if _m := match_pat(p, w):
					hit = true
			if hit == (name == "filter"):
				res.append(w.clone())
		return ok(join_ws(res))
	if name == "sort":
		ws := (arg(var ctx, args, 0)?).fields().sorted()
		var res = List[String]()
		for w in ws:
			if res.length() == 0 or res.get(res.length() - 1, "") != w:
				res.append(w.clone())
		return ok(join_ws(res))
	if name == "word":
		ns := arg(var ctx, args, 0)?
		ws := (arg(var ctx, args, 1)?).fields()
		if n := ns.trim().parse_int():
			if n >= 1 and n <= ws.length():
				return ok(ws.get(n - 1, ""))
		return ok("")
	if name == "wordlist":
		ss := arg(var ctx, args, 0)?
		es := arg(var ctx, args, 1)?
		ws := (arg(var ctx, args, 2)?).fields()
		if s := ss.trim().parse_int():
			if e := es.trim().parse_int():
				if s < 1 or e < s or s > ws.length():
					return ok("")
				var res = List[String]()
				var k = s
				while k <= e and k <= ws.length():
					res.append(ws.get(k - 1, ""))
					k += 1
				return ok(join_ws(res))
		return ok("")
	if name == "words":
		ws := (arg(var ctx, args, 0)?).fields()
		return ok("{ws.length()}")
	if name == "firstword":
		ws := (arg(var ctx, args, 0)?).fields()
		return ok(ws.get(0, ""))
	if name == "lastword":
		ws := (arg(var ctx, args, 0)?).fields()
		return ok(ws.get(ws.length() - 1, ""))
	if name == "dir" or name == "notdir" or name == "suffix" or name == "basename":
		ws := (arg(var ctx, args, 0)?).fields()
		var res = List[String]()
		for w in ws:
			cs := w.chars()
			var ls = -1
			for i in 0..cs.length():
				if cs.get(i, "") == "/":
					ls = i
			if name == "dir":
				if ls < 0:
					res.append("./")
				else:
					res.append(sub(cs, 0, ls + 1))
			else if name == "notdir":
				res.append(sub(cs, ls + 1, cs.length()))
			else:
				e := ext_pos(w)
				if name == "suffix":
					if e >= 0:
						res.append(sub(cs, e, cs.length()))
				else:
					if e >= 0:
						res.append(sub(cs, 0, e))
					else:
						res.append(w.clone())
		return ok(join_ws(res))
	if name == "addprefix" or name == "addsuffix":
		fix := arg(var ctx, args, 0)?
		ws := (arg(var ctx, args, 1)?).fields()
		var res = List[String]()
		for w in ws:
			if name == "addprefix":
				res.append(fix + w)
			else:
				res.append(w + fix)
		return ok(join_ws(res))
	if name == "wildcard":
		pats := (arg(var ctx, args, 0)?).fields()
		var res = List[String]()
		for p in pats:
			if not p.contains_any("*?"):
				if ctx.files.contains(p):
					res.append(p.clone())
			else:
				pc := p.chars()
				var found = List[String]()
				for k in ctx.files.keys():
					if glob(pc, 0, k.chars(), 0):
						found.append(k.clone())
				found.sort()
				for f in found:
					res.append(f.clone())
		return ok(join_ws(res))
	if name == "foreach":
		vn := (arg(var ctx, args, 0)?).trim()
		lst := (arg(var ctx, args, 1)?).fields()
		body := trim_st(args.get(2, ""))
		var res = List[String]()
		for w in lst:
			had := ctx.binds.contains(vn)
			old := ctx.binds.get_or(vn, "").clone()
			ctx.binds[vn.clone()] = w.clone()
			r := expand(var ctx, body)?
			if had:
				ctx.binds[vn.clone()] = old.clone()
			else:
				ctx.binds.remove(vn.clone())
			res.append(r.clone())
		return ok(res.join(" "))
	if name == "if":
		cond := arg(var ctx, args, 0)?
		if cond.trim() != "":
			r := arg(var ctx, args, 1)?
			return ok(r)
		r := arg(var ctx, args, 2)?
		return ok(r)
	if name == "info":
		text := arg(var ctx, args, 0)?
		ctx.out += text + "\n"
		return ok("")
	if name == "error":
		text := arg(var ctx, args, 0)?
		return error(fatal(ctx, text))
	return ok("")

fn lookup(var ctx: Ctx, name: String) String!:
	if ctx.binds.contains(name):
		return ok(ctx.binds.get_or(name, "").clone())
	if ctx.auto.contains(name):
		return ok(ctx.auto.get_or(name, "").clone())
	if ctx.vals.contains(name):
		val := ctx.vals.get_or(name, "").clone()
		if ctx.simples.contains(name):
			return ok(val)
		if ctx.expanding.contains(name):
			return error(fatal(ctx, "Recursive variable '{name}' references itself (eventually)"))
		ctx.expanding.append(name.clone())
		r := expand(var ctx, val)?
		ctx.expanding.remove(ctx.expanding.length() - 1)
		return ok(r)
	return ok("")

fn eval_ref(var ctx: Ctx, inner: String) String!:
	cs := inner.chars()
	var sp = -1
	for i in 0..cs.length():
		if is_ws(cs.get(i, "")):
			sp = i
			break
	if sp > 0:
		fname := sub(cs, 0, sp)
		if is_func(fname):
			r := call_fn(var ctx, fname, sub(cs, sp + 1, cs.length()))?
			return ok(r)
	name := (expand(var ctx, inner)?).trim()
	nc := name.chars()
	var p = -1
	for i in 1..nc.length():
		if nc.get(i, "") == ":":
			p = i
			break
	if p > 0:
		var q = -1
		for i in (p + 1)..nc.length():
			if nc.get(i, "") == "=":
				q = i
				break
		if q > 0:
			vn := sub(nc, 0, p).trim()
			var from = sub(nc, p + 1, q)
			var to = sub(nc, q + 1, nc.length())
			if not from.contains("%"):
				from = "%" + from
				to = "%" + to
			v := lookup(var ctx, vn)?
			return ok(patsubst_words(from, to, v))
	r := lookup(var ctx, name)?
	return ok(r)

fn expand(var ctx: Ctx, text: String) String!:
	if not text.contains("$"):
		return ok(text.clone())
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
		if i + 1 >= n:
			break
		d := cs.get(i + 1, "")
		if d == "$":
			out += "$"
			i += 2
			continue
		if d == "(" or d == "\{":
			close := if d == "(": ")" else: "\}"
			var j = i + 2
			var depth = 1
			while j < n:
				ch := cs.get(j, "")
				if ch == d:
					depth += 1
				else if ch == close:
					depth -= 1
					if depth == 0:
						break
				j += 1
			if depth != 0:
				return error(fatal(ctx, "unterminated variable reference"))
			r := eval_ref(var ctx, sub(cs, i + 2, j))?
			out += r
			i = j + 1
		else:
			r := lookup(var ctx, d)?
			out += r
			i += 2
	return ok(out)

// ---------- parsing ----------

type Scan:
	eq: Int = -1
	col: Int = -1
	semi: Int = -1

fn scan_line(cs: List[String]) Scan:
	var sc = Scan()
	var depth = 0
	var i = 0
	n := cs.length()
	while i < n:
		c := cs.get(i, "")
		if c == "=" and sc.eq < 0:
			sc.eq = i
		if c == "$" and i + 1 < n and (cs.get(i + 1, "") == "(" or cs.get(i + 1, "") == "\{"):
			depth += 1
			i += 2
			continue
		if depth > 0:
			if c == "(" or c == "\{":
				depth += 1
			else if c == ")" or c == "\}":
				depth -= 1
		else:
			if c == ";" and sc.semi < 0:
				sc.semi = i
			if c == ":" and sc.col < 0 and sc.semi < 0:
				sc.col = i
		i += 1
	return sc

fn cur_active(ctx: Ctx) Bool:
	if ctx.conds.length() == 0:
		return true
	return ctx.conds.get(ctx.conds.length() - 1, Cond(false, false, false, 0, false)).active

fn var Ctx.close_rule() Unit:
	if not self.pend_open:
		return
	if self.pend_rec.length() > 0:
		for t in self.pend_targets:
			if idx := self.eidx.get(t):
				if self.erules[idx].rec.length() > 0:
					self.out += "Makefile:{self.pend_line}: warning: overriding recipe for target '{t}'\n"
				var nr = List[RLine]()
				for rl in self.pend_rec:
					nr.append(RLine(rl.text.clone(), rl.line))
				self.erules[idx].rec = nr
		for pi in self.pend_pidx:
			var nr = List[RLine]()
			for rl in self.pend_rec:
				nr.append(RLine(rl.text.clone(), rl.line))
			self.prules[pi].rec = nr
	self.pend_open = false
	self.pend_targets = []
	self.pend_pidx = []
	self.pend_rec = []

fn strip_comment(s: String) String:
	if not s.contains("#"):
		return s.clone()
	cs := s.chars()
	var out = ""
	var i = 0
	while i < cs.length():
		c := cs.get(i, "")
		if c == "\\" and cs.get(i + 1, "") == "#":
			out += "#"
			i += 2
			continue
		if c == "#":
			break
		out += c
		i += 1
	return out

fn parse_cond_args(ctx: Ctx, rest: String) List[String]!:
	t := rest.trim()
	tc := t.chars()
	if tc.length() < 2 or tc.get(0, "") != "(" or tc.get(tc.length() - 1, "") != ")":
		return error(fatal(ctx, "invalid syntax in conditional"))
	inner := sub(tc, 1, tc.length() - 1)
	parts := split_args(inner)
	if parts.length() != 2:
		return error(fatal(ctx, "invalid syntax in conditional"))
	return ok(parts)

fn var Ctx.define(name: String, value: String, op: String) Unit!:
	if self.cmd.contains(name):
		return ok(unit)
	if op == "=":
		self.vals[name.clone()] = value.clone()
		self.simples.remove(name)
	else if op == ":=":
		v := expand(var self, value)?
		self.vals[name.clone()] = v.clone()
		self.simples.add(name.clone())
	else if op == "?=":
		if not self.vals.contains(name):
			self.vals[name.clone()] = value.clone()
			self.simples.remove(name)
	else:
		if not self.vals.contains(name):
			self.vals[name.clone()] = value.clone()
			self.simples.remove(name)
		else if self.simples.contains(name):
			v := expand(var self, value)?
			old := self.vals.get_or(name, "").clone()
			if old == "" or v == "":
				self.vals[name.clone()] = old + v
			else:
				self.vals[name.clone()] = old + " " + v
		else:
			old := self.vals.get_or(name, "").clone()
			if old == "" or value == "":
				self.vals[name.clone()] = old + value
			else:
				self.vals[name.clone()] = old + " " + value
	return ok(unit)

fn var Ctx.add_erule(t: String, pre: List[String], oo: List[String]) Unit:
	var idx = 0
	if self.eidx.contains(t):
		idx = self.eidx.get_or(t, 0)
	else:
		idx = self.erules.length()
		self.eidx[t.clone()] = idx
		self.erules.append(ERule(t.clone()))
		if self.default_goal == "" and not t.starts_with("."):
			self.default_goal = t.clone()
	for p in pre:
		self.erules[idx].pre.append(p.clone())
	for p in oo:
		self.erules[idx].oo.append(p.clone())

fn var Ctx.process_line(raw: String, ln: Int) Unit!:
	self.line = ln
	if raw.starts_with("\t"):
		if not cur_active(self):
			return ok(unit)
		text := raw.trim_start_chars("\t")
		if text.trim() == "":
			return ok(unit)
		if not self.pend_open:
			return error(fatal(self, "recipe commences before first target"))
		self.pend_rec.append(RLine(text.clone(), ln))
		return ok(unit)
	line := strip_comment(raw).trim()
	if line == "":
		return ok(unit)
	ws := line.fields()
	first := ws.get(0, "")
	rest := trim_st(sl(line, first.length(), line.length()))
	if first == "ifdef" or first == "ifndef" or first == "ifeq" or first == "ifneq":
		self.close_rule()
		par := cur_active(self)
		var val = false
		if par:
			if first == "ifdef" or first == "ifndef":
				nm := (expand(var self, rest)?).trim()
				def := self.vals.get_or(nm, "") != ""
				val = if first == "ifdef": def else: not def
			else:
				parts := parse_cond_args(self, rest)?
				a := (expand(var self, trim_st(parts.get(0, "")))?).trim()
				b := (expand(var self, trim_st(parts.get(1, "")))?).trim()
				val = if first == "ifeq": a == b else: a != b
		self.conds.append(Cond(par, val, false, ln, par and val))
		return ok(unit)
	if first == "else":
		self.close_rule()
		if self.conds.length() == 0:
			return error(fatal(self, "extraneous 'else'"))
		k := self.conds.length() - 1
		if self.conds[k].in_else:
			return error(fatal(self, "extraneous 'else'"))
		self.conds[k].in_else = true
		self.conds[k].active = self.conds[k].parent and not self.conds[k].value
		return ok(unit)
	if first == "endif":
		self.close_rule()
		if self.conds.length() == 0:
			return error(fatal(self, "extraneous 'endif'"))
		self.conds.remove(self.conds.length() - 1)
		return ok(unit)
	if not cur_active(self):
		return ok(unit)
	self.close_rule()
	cs := line.chars()
	sc := scan_line(cs)
	n := cs.length()
	is_assign := sc.eq >= 0 and (sc.col < 0 or sc.col > sc.eq or sc.col == sc.eq - 1)
	if is_assign:
		var op = "="
		var name_end = sc.eq
		if sc.eq > 0:
			pc := cs.get(sc.eq - 1, "")
			if pc == ":" or pc == "?" or pc == "+":
				op = pc + "="
				name_end = sc.eq - 1
		name := (expand(var self, sub(cs, 0, name_end))?).trim()
		if name == "":
			return error(fatal(self, "empty variable name"))
		value := sub(cs, sc.eq + 1, n).trim()
		self.define(name, value, op)?
		return ok(unit)
	if sc.col >= 0:
		left := sub(cs, 0, sc.col)
		var ptext = ""
		var cmdtext = ""
		if sc.semi >= 0:
			ptext = sub(cs, sc.col + 1, sc.semi)
			cmdtext = sub(cs, sc.semi + 1, n).trim()
		else:
			ptext = sub(cs, sc.col + 1, n)
		targets := (expand(var self, left)?).fields()
		pexp := expand(var self, ptext)?
		var normal = pexp.clone()
		var ootext = ""
		if bar := pexp.index_of("|"):
			normal = sl(pexp, 0, bar)
			ootext = sl(pexp, bar + 1, pexp.length())
		pre := normal.fields()
		oo := ootext.fields()
		self.pend_open = true
		self.pend_line = ln
		if targets.length() == 1 and targets.get(0, "") == ".PHONY":
			for p in pre:
				if not self.phony.contains(p):
					self.phony.add(p.clone())
					self.phony_order.append(p.clone())
			return ok(unit)
		for t in targets:
			if t.contains("%"):
				self.pend_pidx.append(self.prules.length())
				var pr = PRule(t.clone())
				for p in pre:
					pr.pre.append(p.clone())
				for p in oo:
					pr.oo.append(p.clone())
				self.prules.append(pr)
			else:
				self.add_erule(t, pre, oo)
				self.pend_targets.append(t.clone())
		if cmdtext != "":
			self.pend_rec.append(RLine(cmdtext, ln))
		return ok(unit)
	ex := expand(var self, line)?
	if ex.trim() != "":
		return error(fatal(self, "missing separator"))
	return ok(unit)

fn parse_all(var ctx: Ctx, cmdvars: List[String]) Unit!:
	ctx.vals = Map[String, String]()
	ctx.simples = Set[String]()
	ctx.cmd = Set[String]()
	ctx.binds = Map[String, String]()
	ctx.auto = Map[String, String]()
	ctx.expanding = []
	ctx.erules = []
	ctx.eidx = Map[String, Int]()
	ctx.prules = []
	ctx.phony = Set[String]()
	ctx.phony_order = []
	ctx.default_goal = ""
	ctx.conds = []
	ctx.pend_open = false
	ctx.pend_targets = []
	ctx.pend_pidx = []
	ctx.pend_rec = []
	ctx.line = 0
	for cv in cmdvars:
		if e := cv.index_of("="):
			nm := sl(cv, 0, e)
			ctx.vals[nm.clone()] = sl(cv, e + 1, cv.length())
			ctx.cmd.add(nm.clone())
	phys := ctx.mf.clone().lines()
	n := phys.length()
	var i = 0
	while i < n:
		start := i + 1
		var cur = phys.get(i, "").clone()
		while cur.ends_with("\\") and i + 1 < n:
			cur = trim_st(sl(cur, 0, cur.length() - 1)).clone()
			i += 1
			cur = cur + " " + phys.get(i, "").trim_start()
		ctx.process_line(cur, start)?
		i += 1
	ctx.close_rule()
	if ctx.conds.length() > 0:
		ctx.line = ctx.conds.get(ctx.conds.length() - 1, Cond(false, false, false, 0, false)).line
		return error(fatal(ctx, "missing 'endif'"))
	ctx.line = 0
	return ok(unit)

// ---------- resolution ----------

fn can_make(ctx: Ctx, name: String, depth: Int) Bool:
	if ctx.files.contains(name) or ctx.eidx.contains(name) or ctx.phony.contains(name):
		return true
	if depth >= 8:
		return false
	return find_pattern(ctx, name, depth) >= 0

fn find_pattern(ctx: Ctx, t: String, depth: Int) Int:
	for k in 0..ctx.prules.length():
		pr := ctx.prules[k]
		if pr.rec.length() == 0:
			continue
		if stem := match_pat(pr.pat, t):
			if stem == "":
				continue
			var ok_all = true
			for p in pr.pre:
				if not can_make(ctx, subst_pat(p, stem), depth + 1):
					ok_all = false
			for p in pr.oo:
				if not can_make(ctx, subst_pat(p, stem), depth + 1):
					ok_all = false
			if ok_all:
				return k
	return -1

fn copy_rec(rs: List[RLine]) List[RLine]:
	var nr = List[RLine]()
	for rl in rs:
		nr.append(RLine(rl.text.clone(), rl.line))
	return nr

fn resolve(ctx: Ctx, t: String) Resolved:
	var r = Resolved()
	var ei = -1
	if ctx.eidx.contains(t):
		ei = ctx.eidx.get_or(t, -1)
	if ei >= 0 and ctx.erules[ei].rec.length() > 0:
		r.kind = 1
		for p in ctx.erules[ei].pre:
			r.pre.append(p.clone())
		for p in ctx.erules[ei].oo:
			r.oo.append(p.clone())
		r.rec = copy_rec(ctx.erules[ei].rec)
		return r
	pk := find_pattern(ctx, t, 0)
	if pk >= 0:
		pr := ctx.prules[pk]
		stem := match_pat(pr.pat, t).get("")
		r.kind = 2
		r.stem = stem.clone()
		for p in pr.pre:
			r.pre.append(subst_pat(p, stem))
		for p in pr.oo:
			r.oo.append(subst_pat(p, stem))
		if ei >= 0:
			for p in ctx.erules[ei].pre:
				r.pre.append(p.clone())
			for p in ctx.erules[ei].oo:
				r.oo.append(p.clone())
		r.rec = copy_rec(pr.rec)
		return r
	if ei >= 0:
		r.kind = 3
		for p in ctx.erules[ei].pre:
			r.pre.append(p.clone())
		for p in ctx.erules[ei].oo:
			r.oo.append(p.clone())
	return r

fn dedupe(xs: List[String]) List[String]:
	var res = List[String]()
	for x in xs:
		if not res.contains(x):
			res.append(x.clone())
	return res

fn cycle_error(ctx: Ctx, t: String) Error:
	var s = ""
	var found = false
	for x in ctx.stack:
		if x == t:
			found = true
		if found:
			s += x + " -> "
	return Error("make: *** Circular dependency detected: {s}{t}.  Stop.")

// ---------- building ----------

fn var Ctx.touch_file(name: String) Unit:
	self.clock += 1
	c := self.clock
	self.files[name.clone()] = c

fn var Ctx.run_recipe(t: String, r: Resolved, pre: List[String], oo: List[String], query: List[String]) Unit!:
	self.auto = Map[String, String]()
	self.auto["@"] = t.clone()
	self.auto["<"] = r.pre.get(0, "").clone()
	self.auto["^"] = join_ws(pre)
	self.auto["?"] = join_ws(query)
	self.auto["|"] = join_ws(oo)
	self.auto["*"] = r.stem.clone()
	for rl in r.rec:
		self.line = rl.line
		ex := expand(var self, rl.text)?
		var cmd = ex.trim()
		var silent = false
		var ignore = false
		while cmd.length() > 0:
			c := sl(cmd, 0, 1)
			if c == "@":
				silent = true
			else if c == "-":
				ignore = true
			else if c == "+":
				silent = silent
			else:
				break
			cmd = trim_st(sl(cmd, 1, cmd.length()))
		if self.dry:
			self.out += cmd + "\n"
			continue
		if not silent:
			self.out += cmd + "\n"
		w := cmd.fields()
		prog := w.get(0, "")
		var status = 0
		if prog == "false":
			status = 1
		else if prog == "exit":
			if w.length() > 1:
				if n := w.get(1, "").parse_int():
					status = n
				else:
					status = 2
		else if prog == "touch":
			for k in 1..w.length():
				f := w.get(k, "")
				if not f.starts_with("-"):
					self.touch_file(f.clone())
		else if prog == "rm":
			for k in 1..w.length():
				f := w.get(k, "")
				if not f.starts_with("-"):
					self.files.remove(f)
		else if prog == "cp":
			if w.length() == 3:
				src := w.get(1, "")
				if self.files.contains(src):
					self.touch_file(w.get(2, "").clone())
				else:
					self.out += "cp: cannot stat '{src}': No such file or directory\n"
					status = 1
		else if prog == "echo":
			var parts = List[String]()
			for k in 1..w.length():
				parts.append(w.get(k, "").replace("'", "").replace("\"", ""))
			self.out += join_ws(parts) + "\n"
		if status != 0:
			if ignore:
				self.out += "make: [Makefile:{rl.line}: {t}] Error {status} (ignored)\n"
			else:
				return error(Error("make: *** [Makefile:{rl.line}: {t}] Error {status}"))
	self.auto = Map[String, String]()
	self.line = 0
	return ok(unit)

fn var Ctx.update(t: String, by: String) Bool!:
	if self.memo.contains(t):
		return ok(self.memo.get_or(t, false))
	if self.stack.contains(t):
		return error(cycle_error(self, t))
	r := resolve(self, t)
	isph := self.phony.contains(t)
	if r.kind == 0:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)
		if isph:
			self.memo[t.clone()] = true
			return ok(true)
		if by == "":
			return error(Error("make: *** No rule to make target '{t}'.  Stop."))
		return error(Error("make: *** No rule to make target '{t}', needed by '{by}'.  Stop."))
	existed := self.files.contains(t)
	old := self.files.get_or(t, 0)
	pre := dedupe(r.pre)
	oo := dedupe(r.oo)
	self.stack.append(t.clone())
	var changed = false
	var newer = false
	for p in pre:
		c := self.update(p, t)?
		if c:
			changed = true
		if existed:
			if self.files.contains(p):
				if self.files.get_or(p, 0) > old:
					newer = true
	for p in oo:
		_ := self.update(p, t)?
	self.stack.remove(self.stack.length() - 1)
	var result = false
	if isph or not self.files.contains(t) or changed or newer:
		result = true
		if r.rec.length() > 0:
			var query = List[String]()
			for p in pre:
				if not existed or self.memo.get_or(p, false) or (self.files.contains(p) and self.files.get_or(p, 0) > old):
					query.append(p.clone())
			self.ran += 1
			self.run_recipe(t, r, pre, oo, query)?
			if not self.dry and not isph:
				self.touch_file(t.clone())
	self.memo[t.clone()] = result
	return ok(result)

fn var Ctx.do_build(args: List[String]) Unit!:
	var cv = List[String]()
	var goals = List[String]()
	for a in args:
		if idx := a.index_of("="):
			if idx > 0:
				cv.append(a.clone())
				continue
		goals.append(a.clone())
	parse_all(var self, cv)?
	self.memo = Map[String, Bool]()
	self.stack = []
	self.ran = 0
	if goals.length() == 0:
		if self.default_goal == "":
			self.out += "make: *** No targets.  Stop.\n"
			return ok(unit)
		goals.append(self.default_goal.clone())
	for g in goals:
		ran0 := self.ran
		_ := self.update(g, "")?
		if self.ran == ran0:
			r := resolve(self, g)
			if r.kind == 1 or r.kind == 2 or (not self.phony.contains(g) and self.files.contains(g)):
				self.out += "make: '{g}' is up to date.\n"
			else:
				self.out += "make: Nothing to be done for '{g}'.\n"
	return ok(unit)

fn var Ctx.dfs(t: String, root: Bool, var res: List[String]) Unit!:
	if self.memo.contains(t):
		return ok(unit)
	if self.stack.contains(t):
		return error(cycle_error(self, t))
	r := resolve(self, t)
	self.stack.append(t.clone())
	for p in dedupe(r.pre):
		self.dfs(p, false, var res)?
	for p in dedupe(r.oo):
		self.dfs(p, false, var res)?
	self.stack.remove(self.stack.length() - 1)
	self.memo[t.clone()] = true
	if not root:
		res.append(t.clone())
	return ok(unit)

fn var Ctx.do_deps(args: List[String]) Unit!:
	var cv = List[String]()
	var goals = List[String]()
	for a in args:
		if idx := a.index_of("="):
			if idx > 0:
				cv.append(a.clone())
				continue
		goals.append(a.clone())
	if goals.length() != 1:
		self.out += "usage: deps TARGET\n"
		return ok(unit)
	parse_all(var self, cv)?
	self.memo = Map[String, Bool]()
	self.stack = []
	var res = List[String]()
	self.dfs(goals.get(0, ""), true, var res)?
	if res.length() == 0:
		self.out += "(no prerequisites)\n"
	for x in res:
		self.out += x + "\n"
	return ok(unit)

fn fmt_rule(name: String, pre: List[String], oo: List[String]) String:
	var s = name + ": " + join_ws(pre)
	if name.length() > 0 and pre.length() == 0:
		s = name + ":"
	if oo.length() > 0:
		s = s + " | " + join_ws(oo)
	return s

fn var Ctx.do_targets(args: List[String]) Unit!:
	var cv = List[String]()
	for a in args:
		if idx := a.index_of("="):
			if idx > 0:
				cv.append(a.clone())
	parse_all(var self, cv)?
	if self.default_goal != "":
		self.out += "default: {self.default_goal}\n"
	for er in self.erules:
		self.out += fmt_rule(er.name, er.pre, er.oo) + "\n"
	for pr in self.prules:
		self.out += "pattern " + fmt_rule(pr.pat, pr.pre, pr.oo) + "\n"
	if self.phony_order.length() > 0:
		self.out += "phony: " + join_ws(self.phony_order) + "\n"
	return ok(unit)

fn var Ctx.do_expand(text: String) Unit!:
	parse_all(var self, [])?
	r := expand(var self, text)?
	self.out += "[{r}]\n"
	return ok(unit)

fn var Ctx.report(res: Unit!) Unit:
	if _u := res:
		return
	else:
		self.out += res.err().message + "\n"

fn var Ctx.handle(reqline: String) Unit:
	t := reqline.trim()
	if t == "" or t.starts_with("#"):
		return
	self.out += "> " + reqline.trim_end() + "\n"
	self.line = 0
	self.auto = Map[String, String]()
	self.dry = false
	ws := t.fields()
	word := ws.get(0, "")
	var args = List[String]()
	for k in 1..ws.length():
		args.append(ws.get(k, "").clone())
	if word == "build":
		self.report(self.do_build(args))
	else if word == "dry":
		self.dry = true
		self.report(self.do_build(args))
		self.dry = false
	else if word == "deps":
		self.report(self.do_deps(args))
	else if word == "targets":
		self.report(self.do_targets(args))
	else if word == "expand":
		self.report(self.do_expand(trim_st(sl(t, 6, t.length()))))
	else if word == "files":
		if self.files.length() == 0:
			self.out += "(no files)\n"
		else:
			for k in self.files.keys().sorted():
				self.out += "{k} {self.files.get_or(k, 0)}\n"
	else if word == "touch":
		if args.length() == 1:
			self.touch_file(args.get(0, "").clone())
		else if args.length() == 2:
			if n := args.get(1, "").parse_int():
				self.files[args.get(0, "").clone()] = n
				if n > self.clock:
					self.clock = n
			else:
				self.out += "bad request\n"
		else:
			self.out += "bad request\n"
	else if word == "rm":
		for a in args:
			self.files.remove(a)
	else:
		self.out += "unknown request: {word}\n"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().ok_or(Error("bad input"))?
	all := text.lines()
	var sec = 0
	var mf = ""
	var ctx = Ctx()
	var reqs = List[String]()
	for l in all:
		if sec < 2 and l == "====":
			sec += 1
			continue
		if sec == 0:
			mf += l + "\n"
		else if sec == 1:
			f := l.fields()
			if f.length() == 2:
				if m := f.get(1, "").parse_int():
					if m >= 0:
						ctx.files[f.get(0, "").clone()] = m
						if m > ctx.clock:
							ctx.clock = m
		else:
			reqs.append(l.clone())
	ctx.mf = mf
	for r in reqs:
		ctx.handle(r)
	print(ctx.out, end: "")
