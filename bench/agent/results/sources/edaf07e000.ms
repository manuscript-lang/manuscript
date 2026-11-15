import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Var:
	flavor: Int
	value: String

type Bind:
	name: String
	value: String

type RLine:
	text: String
	line: Int

type Rule:
	pat: String
	prereqs: List[String]
	oo: List[String]
	recipe: List[RLine]

type Cond:
	line: Int
	parent: Bool
	cond: Bool
	in_else: Bool

type Open:
	line: Int
	targets: List[String]
	pats: List[Int]
	recipe: List[RLine]

type Res:
	found: Bool
	prereqs: List[String]
	oo: List[String]
	recipe: List[RLine]
	stem: String

type St:
	files: Map[String, Int]
	clock: Int = 0
	mk: List[String]
	vars: Map[String, Var]
	cmd: Set[String]
	rules: List[Rule]
	rindex: Map[String, Int]
	order: List[String]
	patterns: List[Rule]
	phony: Set[String]
	phony_order: List[String]
	default_goal: String = ""
	autos: Map[String, String]
	binds: List[Bind]
	stack: List[String]
	curline: Int = 0
	memo: Map[String, Bool]
	dstack: List[String]
	recipes_run: Int = 0
	dry: Bool = false
	res_list: List[String]

fn fatal(msg: String) Error:
	return Error(msg, kind: "fatal")

fn abort(msg: String) Error:
	return Error(msg, kind: "abort")

fn sl(s: String, a: Int, b: Int) String:
	if a >= b: return ""
	r := s.slice(a, b)
	if v := r: return v
	return ""

fn join_cs(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b:
		out += cs[i]
		i += 1
	return out

fn find_close(cs: List[String], open_idx: Int) Int:
	opener := cs[open_idx]
	closer := if opener == "(": ")" else: "\}"
	var depth = 0
	var j = open_idx
	n := cs.length()
	while j < n:
		if cs[j] == opener: depth += 1
		else if cs[j] == closer:
			depth -= 1
			if depth == 0: return j
		j += 1
	return -1

fn split_args(text: String) List[String]:
	cs := text.chars()
	var out = List[String]()
	var depth = 0
	var cur = ""
	for c in cs:
		if c == "(" or c == "\{":
			depth += 1
			cur += c
		else if c == ")" or c == "\}":
			if depth > 0: depth -= 1
			cur += c
		else if c == "," and depth == 0:
			out.append(cur.trim())
			cur = ""
		else:
			cur += c
	out.append(cur.trim())
	return out

fn pmatch(pat: String, w: String) String?:
	if idx := pat.index_of("%"):
		pre := sl(pat, 0, idx)
		suf := sl(pat, idx + 1, pat.length())
		if w.starts_with(pre) and w.ends_with(suf) and w.length() >= pre.length() + suf.length():
			return sl(w, pre.length(), w.length() - suf.length())
		return none
	if w == pat: return ""
	return none

fn patsubst(pat: String, rep: String, text: String) String:
	var out = List[String]()
	for w in text.fields():
		if stem := pmatch(pat, w):
			if pat.contains("%"):
				out.append(rep.replace_first("%", stem))
			else:
				out.append(rep.clone())
		else:
			out.append(w.clone())
	return out.join(" ")

fn glob(p: List[String], pi: Int, t: List[String], ti: Int) Bool:
	if pi == p.length(): return ti == t.length()
	c := p[pi]
	if c == "*":
		var k = ti
		while true:
			if glob(p, pi + 1, t, k): return true
			if k >= t.length(): return false
			if t[k] == "/": return false
			k += 1
		return false
	if ti >= t.length(): return false
	if c == "?": return t[ti] != "/" and glob(p, pi + 1, t, ti + 1)
	return c == t[ti] and glob(p, pi + 1, t, ti + 1)

fn is_func(name: String) Bool:
	names := ["subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix", "addsuffix", "wildcard", "foreach", "if", "info", "error"]
	return names.contains(name)

fn last_char_idx(s: String, ch: String) Int:
	cs := s.chars()
	var i = cs.length() - 1
	while i >= 0:
		if cs[i] == ch: return i
		i -= 1
	return -1

fn dedupe(xs: List[String]) List[String]:
	var seen = Set[String]()
	var out = List[String]()
	for x in xs:
		if not seen.contains(x):
			seen.add(x.clone())
			out.append(x.clone())
	return out

fn dedupe_str(xs: List[String]) String:
	return dedupe(xs).join(" ")

// ms: allow_effect std.console.write
fn out(s: String) Unit:
	print(s)

fn strip_comment(s: String) String:
	cs := s.chars()
	var res = ""
	var i = 0
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == "\\" and i + 1 < n and cs[i + 1] == "#":
			res += "#"
			i += 2
		else if c == "#":
			break
		else:
			res += c
			i += 1
	return res

fn rl_clone(xs: List[RLine]) List[RLine]:
	var o = List[RLine]()
	for x in xs:
		o.append(RLine(x.text.clone(), x.line))
	return o

fn new_st() St:
	return St(files: Map[String, Int](), mk: List[String](), vars: Map[String, Var](), cmd: Set[String](), rules: List[Rule](), rindex: Map[String, Int](), order: List[String](), patterns: List[Rule](), phony: Set[String](), phony_order: List[String](), autos: Map[String, String](), binds: List[Bind](), stack: List[String](), memo: Map[String, Bool](), dstack: List[String](), res_list: List[String]())

fn var St.reset() Unit:
	self.vars = Map[String, Var]()
	self.cmd = Set[String]()
	self.rules = List[Rule]()
	self.rindex = Map[String, Int]()
	self.order = List[String]()
	self.patterns = List[Rule]()
	self.phony = Set[String]()
	self.phony_order = List[String]()
	self.default_goal = ""
	self.autos = Map[String, String]()
	self.binds = List[Bind]()
	self.stack = List[String]()
	self.curline = 0
	self.memo = Map[String, Bool]()
	self.dstack = List[String]()
	self.recipes_run = 0
	self.res_list = List[String]()

fn var St.tick() Int:
	self.clock += 1
	return self.clock

fn St.getvar(name: String) Var?:
	if v := self.vars.get(name): return Var(v.flavor, v.value.clone())
	return none

fn var St.lookup(name: String) String!:
	var i = self.binds.length() - 1
	while i >= 0:
		if self.binds[i].name == name: return ok(self.binds[i].value.clone())
		i -= 1
	if v := self.autos.get(name): return ok(v)
	if var_ := self.getvar(name):
		if var_.flavor == 1: return ok(var_.value.clone())
		if self.stack.contains(name):
			return error(fatal("Recursive variable '{name}' references itself (eventually)"))
		self.stack.append(name.clone())
		r := self.expand(var_.value)
		self.stack.pop()
		return r
	return ok("")

fn var St.expand(text: String) String!:
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
		if i + 1 >= n: break
		d := cs[i + 1]
		if d == "$":
			res += "$"
			i += 2
		else if d == "(" or d == "\{":
			j := find_close(cs, i + 1)
			if j < 0: return error(fatal("unterminated variable reference"))
			inner := join_cs(cs, i + 2, j)
			res += self.eval_ref(inner)?
			i = j + 1
		else:
			res += self.lookup(d)?
			i += 2
	return ok(res)

fn var St.eval_ref(inner: String) String!:
	cs := inner.chars()
	var k = 0
	while k < cs.length():
		if cs[k] == " " or cs[k] == "\t": break
		k += 1
	if k > 0 and k < cs.length():
		fname := join_cs(cs, 0, k)
		if is_func(fname):
			return self.call_func(fname, join_cs(cs, k + 1, cs.length()))
	name := (self.expand(inner)?).trim()
	ncs := name.chars()
	var ci = -1
	var q = 1
	while q < ncs.length():
		if ncs[q] == ":":
			ci = q
			break
		q += 1
	if ci > 0:
		var ei = -1
		var r = ci + 1
		while r < ncs.length():
			if ncs[r] == "=":
				ei = r
				break
			r += 1
		if ei > 0:
			vname := join_cs(ncs, 0, ci).trim()
			from := join_cs(ncs, ci + 1, ei)
			to := join_cs(ncs, ei + 1, ncs.length())
			val := self.lookup(vname)?
			if from.contains("%"):
				return ok(patsubst(from, to, val))
			return ok(patsubst("%" + from, "%" + to, val))
	return self.lookup(name)

fn var St.arg(args: List[String], i: Int) String!:
	if i >= args.length(): return ok("")
	return self.expand(args[i])

fn var St.call_func(fname: String, argtext: String) String!:
	args := split_args(argtext)
	if fname == "if":
		cond := (self.arg(args, 0)?).trim()
		if cond != "": return self.arg(args, 1)
		return self.arg(args, 2)
	if fname == "foreach":
		vname := (self.arg(args, 0)?).trim()
		lst := self.arg(args, 1)?
		var results = List[String]()
		for w in lst.fields():
			self.binds.append(Bind(vname.clone(), w.clone()))
			r := self.arg(args, 2)
			self.binds.pop()
			results.append(r?)
		return ok(results.join(" "))
	if fname == "info":
		t := self.arg(args, 0)?
		out(t)
		return ok("")
	if fname == "error":
		t := self.arg(args, 0)?
		return error(fatal(t))
	if fname == "subst":
		from := self.arg(args, 0)?
		to := self.arg(args, 1)?
		text := self.arg(args, 2)?
		if from == "": return ok(text)
		return ok(text.replace(from, to))
	if fname == "patsubst":
		p := self.arg(args, 0)?
		rp := self.arg(args, 1)?
		text := self.arg(args, 2)?
		return ok(patsubst(p, rp, text))
	if fname == "strip":
		t := self.arg(args, 0)?
		return ok(t.fields().join(" "))
	if fname == "findstring":
		f := self.arg(args, 0)?
		t := self.arg(args, 1)?
		if t.contains(f): return ok(f)
		return ok("")
	if fname == "filter" or fname == "filter-out":
		pats := (self.arg(args, 0)?).fields()
		ws := (self.arg(args, 1)?).fields()
		var o = List[String]()
		for w in ws:
			var hit = false
			for p in pats:
				if pmatch(p, w).is_some(): hit = true
			if hit == (fname == "filter"): o.append(w.clone())
		return ok(o.join(" "))
	if fname == "sort":
		var ws = dedupe((self.arg(args, 0)?).fields())
		ws.sort()
		return ok(ws.join(" "))
	if fname == "word":
		ns := (self.arg(args, 0)?).trim()
		ws := (self.arg(args, 1)?).fields()
		if k := ns.parse_int():
			if k >= 1 and k <= ws.length(): return ok(ws[k - 1].clone())
		return ok("")
	if fname == "wordlist":
		ss := (self.arg(args, 0)?).trim()
		es := (self.arg(args, 1)?).trim()
		ws := (self.arg(args, 2)?).fields()
		if s := ss.parse_int():
			if e := es.parse_int():
				if s >= 1 and e >= s and s <= ws.length():
					e2 := if e > ws.length(): ws.length() else: e
					var o = List[String]()
					var k = s
					while k <= e2:
						o.append(ws[k - 1].clone())
						k += 1
					return ok(o.join(" "))
		return ok("")
	if fname == "words":
		return ok("{(self.arg(args, 0)?).fields().length()}")
	if fname == "firstword":
		ws := (self.arg(args, 0)?).fields()
		if ws.length() > 0: return ok(ws[0].clone())
		return ok("")
	if fname == "lastword":
		ws := (self.arg(args, 0)?).fields()
		if ws.length() > 0: return ok(ws[ws.length() - 1].clone())
		return ok("")
	if fname == "dir" or fname == "notdir" or fname == "suffix" or fname == "basename":
		ws := (self.arg(args, 0)?).fields()
		var o = List[String]()
		for w in ws:
			si := last_char_idx(w, "/")
			dirpart := if si >= 0: sl(w, 0, si + 1) else: "./"
			base := if si >= 0: sl(w, si + 1, w.length()) else: w.clone()
			di := last_char_idx(base, ".")
			if fname == "dir": o.append(dirpart)
			else if fname == "notdir": o.append(base)
			else if fname == "suffix":
				if di >= 0: o.append(sl(base, di, base.length()))
			else:
				if di >= 0:
					o.append(sl(w, 0, w.length() - (base.length() - di)))
				else:
					o.append(w.clone())
		return ok(o.join(" "))
	if fname == "addprefix" or fname == "addsuffix":
		p := self.arg(args, 0)?
		ws := (self.arg(args, 1)?).fields()
		var o = List[String]()
		for w in ws:
			if fname == "addprefix": o.append(p + w)
			else: o.append(w + p)
		return ok(o.join(" "))
	if fname == "wildcard":
		pats := (self.arg(args, 0)?).fields()
		var o = List[String]()
		for p in pats:
			var ms = List[String]()
			pcs := p.chars()
			for e in self.files.entries():
				if glob(pcs, 0, e.key.chars(), 0): ms.append(e.key.clone())
			ms.sort()
			for m in ms: o.append(m.clone())
		return ok(o.join(" "))
	return ok("")

fn active(conds: List[Cond]) Bool:
	if conds.length() == 0: return true
	top := conds[conds.length() - 1]
	return top.parent and (top.cond != top.in_else)

fn top_colon(cs: List[String]) Int:
	var i = 0
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == "$" and i + 1 < n and (cs[i + 1] == "(" or cs[i + 1] == "\{"):
			j := find_close(cs, i + 1)
			if j < 0: return -1
			i = j + 1
			continue
		if c == ";": return -1
		if c == ":": return i
		i += 1
	return -1

fn top_semi(cs: List[String], from: Int) Int:
	var i = from
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == "$" and i + 1 < n and (cs[i + 1] == "(" or cs[i + 1] == "\{"):
			j := find_close(cs, i + 1)
			if j < 0: return -1
			i = j + 1
			continue
		if c == ";": return i
		i += 1
	return -1

fn first_eq(cs: List[String]) Int:
	var i = 0
	while i < cs.length():
		if cs[i] == "=": return i
		i += 1
	return -1

fn var St.add_prereqs(t: String, pre: List[String], oo: List[String]) Unit:
	if idx := self.rindex.get(t):
		self.rules[idx].prereqs.extend(pre)
		self.rules[idx].oo.extend(oo)

fn var St.flush(op: Open, has_open: Bool) Bool:
	if not has_open: return false
	if op.recipe.length() > 0:
		for t in op.targets:
			if idx := self.rindex.get(t):
				if self.rules[idx].recipe.length() > 0:
					out("Makefile:{op.line}: warning: overriding recipe for target '{t}'")
				self.rules[idx].recipe = rl_clone(op.recipe)
		for pi in op.pats:
			self.patterns[pi].recipe = rl_clone(op.recipe)
	return false

fn var St.assign(name: String, op: String, value: String) Unit!:
	if self.cmd.contains(name): return ok(unit)
	existing := self.getvar(name)
	if op == "=":
		self.vars[name] = Var(0, value.clone())
	else if op == ":":
		ev := self.expand(value)?
		self.vars[name] = Var(1, ev)
	else if op == "?":
		if existing.is_none(): self.vars[name] = Var(0, value.clone())
	else:
		if old := existing:
			if old.flavor == 1:
				nv := self.expand(value)?
				joined := if old.value == "" or nv == "": old.value + nv else: old.value + " " + nv
				self.vars[name] = Var(1, joined)
			else:
				joined := if old.value == "" or value == "": old.value + value else: old.value + " " + value
				self.vars[name] = Var(0, joined)
		else:
			self.vars[name] = Var(0, value.clone())
	return ok(unit)

fn var St.parse() Unit!:
	var logical = List[RLine]()
	n := self.mk.length()
	var i = 0
	while i < n:
		var cur = self.mk[i].clone()
		start := i + 1
		while cur.ends_with("\\"):
			base := sl(cur, 0, cur.length() - 1).trim_end()
			if i + 1 < n:
				cur = base + " " + self.mk[i + 1].trim_start()
				i += 1
			else:
				cur = base
		logical.append(RLine(cur, start))
		i += 1
	var conds = List[Cond]()
	var op = Open(0, List[String](), List[Int](), List[RLine]())
	var has_open = false
	for ll in logical:
		self.curline = ll.line
		raw := ll.text
		if raw.starts_with("\t"):
			if not active(conds): continue
			body := raw.trim_start_chars("\t")
			if body.trim() == "": continue
			if not has_open:
				return error(fatal("recipe commences before first target"))
			op.recipe.append(RLine(body.clone(), ll.line))
			continue
		s := strip_comment(raw).trim()
		if s == "": continue
		words := s.fields()
		w := words[0]
		if w == "ifdef" or w == "ifndef" or w == "ifeq" or w == "ifneq" or w == "else" or w == "endif":
			has_open = self.flush(op, has_open)
			op = Open(0, List[String](), List[Int](), List[RLine]())
			rest := sl(s, w.length(), s.length()).trim()
			if w == "else":
				if conds.length() == 0: return error(fatal("extraneous 'else'"))
				k := conds.length() - 1
				if conds[k].in_else: return error(fatal("extraneous 'else'"))
				conds[k].in_else = true
			else if w == "endif":
				if conds.length() == 0: return error(fatal("extraneous 'endif'"))
				conds.pop()
			else:
				act := active(conds)
				var cond = false
				if act:
					if w == "ifdef" or w == "ifndef":
						name := (self.expand(rest)?).trim()
						var defined = false
						if v := self.vars.get(name): defined = v.value != ""
						cond = if w == "ifdef": defined else: not defined
					else:
						rcs := rest.chars()
						if rcs.length() < 2 or rcs[0] != "(" or rcs[rcs.length() - 1] != ")":
							return error(fatal("invalid syntax in conditional"))
						parts := split_args_raw(join_cs(rcs, 1, rcs.length() - 1))
						if parts.length() != 2: return error(fatal("invalid syntax in conditional"))
						a := (self.expand(parts[0].trim())?).trim()
						b := (self.expand(parts[1].trim())?).trim()
						cond = if w == "ifeq": a == b else: a != b
				conds.append(Cond(ll.line, act, cond, false))
			continue
		if not active(conds): continue
		has_open = self.flush(op, has_open)
		op = Open(0, List[String](), List[Int](), List[RLine]())
		cs := s.chars()
		eq := first_eq(cs)
		col := top_colon(cs)
		if eq >= 0 and (col < 0 or col > eq or col == eq - 1):
			var opch = "="
			var name_end = eq
			if eq >= 1 and (cs[eq - 1] == ":" or cs[eq - 1] == "?" or cs[eq - 1] == "+"):
				opch = cs[eq - 1].clone()
				name_end = eq - 1
			name := (self.expand(join_cs(cs, 0, name_end))?).trim()
			if name == "": return error(fatal("empty variable name"))
			value := join_cs(cs, eq + 1, cs.length()).trim()
			self.assign(name, opch, value)?
			continue
		if col >= 0:
			semi := top_semi(cs, col + 1)
			pre_end := if semi >= 0: semi else: cs.length()
			ttext := self.expand(join_cs(cs, 0, col))?
			ptext := self.expand(join_cs(cs, col + 1, pre_end))?
			targets := ttext.fields()
			var normal = List[String]()
			var oo = List[String]()
			if bar := ptext.index_of("|"):
				normal = sl(ptext, 0, bar).fields()
				oo = sl(ptext, bar + 1, ptext.length()).fields()
			else:
				normal = ptext.fields()
			has_open = true
			op.line = ll.line
			if semi >= 0:
				cmd := join_cs(cs, semi + 1, cs.length()).trim()
				if cmd != "": op.recipe.append(RLine(cmd, ll.line))
			if targets.length() == 1 and targets[0] == ".PHONY":
				for p in normal:
					if not self.phony.contains(p):
						self.phony.add(p.clone())
						self.phony_order.append(p.clone())
				continue
			for t in targets:
				if t.contains("%"):
					self.patterns.append(Rule(t.clone(), normal.clone(), oo.clone(), List[RLine]()))
					op.pats.append(self.patterns.length() - 1)
				else:
					if not self.rindex.contains(t):
						self.rules.append(Rule("", List[String](), List[String](), List[RLine]()))
						self.rindex[t.clone()] = self.rules.length() - 1
						self.order.append(t.clone())
						if self.default_goal == "" and not t.starts_with("."):
							self.default_goal = t.clone()
					self.add_prereqs(t, normal, oo)
					op.targets.append(t.clone())
			continue
		e := self.expand(s)?
		if e.trim() != "": return error(fatal("missing separator"))
	has_open = self.flush(op, has_open)
	if conds.length() > 0:
		self.curline = conds[conds.length() - 1].line
		return error(fatal("missing 'endif'"))
	self.curline = 0
	return ok(unit)

fn split_args_raw(text: String) List[String]:
	return split_args(text)

fn St.can_make(name: String, depth: Int) Bool:
	if self.files.contains(name) or self.rindex.contains(name) or self.phony.contains(name): return true
	if depth >= 8: return false
	for r in self.patterns:
		if r.recipe.length() == 0: continue
		stem := pmatch(r.pat, name).get("")
		if stem == "" or not r.pat.contains("%"): continue
		var all_ok = true
		for p in r.prereqs:
			if not self.can_make(p.replace_first("%", stem), depth + 1): all_ok = false
		for p in r.oo:
			if not self.can_make(p.replace_first("%", stem), depth + 1): all_ok = false
		if all_ok: return true
	return false

fn St.resolve(t: String) Res:
	var ex = -1
	if idx := self.rindex.get(t): ex = idx
	if ex >= 0 and self.rules[ex].recipe.length() > 0:
		r := self.rules[ex]
		return Res(true, r.prereqs.clone(), r.oo.clone(), rl_clone(r.recipe), "")
	for r in self.patterns:
		if r.recipe.length() == 0: continue
		stem := pmatch(r.pat, t).get("")
		if stem == "" or not r.pat.contains("%"): continue
		var all_ok = true
		for p in r.prereqs:
			if not self.can_make(p.replace_first("%", stem), 1): all_ok = false
		for p in r.oo:
			if not self.can_make(p.replace_first("%", stem), 1): all_ok = false
		if all_ok:
			var pre = List[String]()
			var oo = List[String]()
			for p in r.prereqs: pre.append(p.replace_first("%", stem))
			for p in r.oo: oo.append(p.replace_first("%", stem))
			if ex >= 0:
				pre.extend(self.rules[ex].prereqs)
				oo.extend(self.rules[ex].oo)
			return Res(true, pre, oo, rl_clone(r.recipe), stem)
	if ex >= 0:
		r := self.rules[ex]
		return Res(true, r.prereqs.clone(), r.oo.clone(), List[RLine](), "")
	return Res(false, List[String](), List[String](), List[RLine](), "")

type Pfx:
	text: String
	silent: Bool
	ign: Bool

fn parse_prefix(s: String) Pfx:
	cs := s.chars()
	var silent = false
	var ign = false
	var i = 0
	while i < cs.length():
		c := cs[i]
		if c == "@": silent = true
		else if c == "-": ign = true
		else if c == "+": silent = silent
		else if c == " " or c == "\t": silent = silent
		else: break
		i += 1
	return Pfx(join_cs(cs, i, cs.length()).trim(), silent, ign)

fn var St.simulate(cmd: String) Int:
	ws := cmd.fields()
	if ws.length() == 0: return 0
	w0 := ws[0]
	if w0 == "false": return 1
	if w0 == "exit":
		if ws.length() >= 2:
			if n := ws[1].parse_int(): return n
			return 2
		return 0
	if w0 == "touch":
		var k = 1
		while k < ws.length():
			if not ws[k].starts_with("-"):
				tk := self.tick()
				self.files[ws[k].clone()] = tk
			k += 1
		return 0
	if w0 == "rm":
		var k = 1
		while k < ws.length():
			if not ws[k].starts_with("-"): self.files.remove(ws[k].clone())
			k += 1
		return 0
	if w0 == "cp":
		if ws.length() == 3:
			if not self.files.contains(ws[1]):
				out("cp: cannot stat '{ws[1]}': No such file or directory")
				return 1
			tk := self.tick()
			self.files[ws[2].clone()] = tk
		return 0
	if w0 == "echo":
		var o = List[String]()
		var k = 1
		while k < ws.length():
			o.append(ws[k].replace("'", "").replace("\"", ""))
			k += 1
		out(o.join(" "))
		return 0
	return 0

fn var St.run_recipe(t: String, res: Res, pre: List[String], existed0: Bool, mt0: Int) Unit!:
	self.recipes_run += 1
	var q = List[String]()
	for p in pre:
		var inc = not existed0
		if self.memo.get_or(p, false): inc = true
		if mp := self.files.get(p):
			if mp > mt0: inc = true
		if inc: q.append(p.clone())
	var a = Map[String, String]()
	a["@"] = t.clone()
	a["<"] = if res.prereqs.length() > 0: res.prereqs[0].clone() else: ""
	a["^"] = pre.join(" ")
	a["?"] = q.join(" ")
	a["|"] = dedupe_str(res.oo)
	a["*"] = res.stem.clone()
	self.autos = a
	for rl in res.recipe:
		self.curline = rl.line
		expanded := (self.expand(rl.text)?).trim()
		pf := parse_prefix(expanded)
		if self.dry:
			out(pf.text)
			continue
		if not pf.silent: out(pf.text)
		st := self.simulate(pf.text)
		if st != 0:
			if pf.ign:
				out("make: [Makefile:{rl.line}: {t}] Error {st} (ignored)")
			else:
				return error(abort("make: *** [Makefile:{rl.line}: {t}] Error {st}"))
	self.curline = 0
	self.autos = Map[String, String]()
	if not self.dry and not self.phony.contains(t):
		tk := self.tick()
		self.files[t.clone()] = tk
	return ok(unit)

fn var St.update(t: String, needed_by: String) Bool!:
	if v := self.memo.get(t): return ok(v)
	if self.dstack.contains(t):
		var idx = 0
		var k = 0
		while k < self.dstack.length():
			if self.dstack[k] == t:
				idx = k
				break
			k += 1
		var path = List[String]()
		while idx < self.dstack.length():
			path.append(self.dstack[idx].clone())
			idx += 1
		path.append(t.clone())
		return error(abort("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
	res := self.resolve(t)
	if not res.found:
		if self.files.contains(t):
			self.memo[t.clone()] = false
			return ok(false)
		if self.phony.contains(t):
			self.memo[t.clone()] = true
			return ok(true)
		if needed_by == "": return error(abort("make: *** No rule to make target '{t}'.  Stop."))
		return error(abort("make: *** No rule to make target '{t}', needed by '{needed_by}'.  Stop."))
	existed0 := self.files.contains(t)
	mt0 := self.files.get_or(t, 0)
	self.dstack.append(t.clone())
	var anych = false
	pre := dedupe(res.prereqs)
	for p in pre:
		ch := self.update(p, t)?
		if ch: anych = true
	var newer = false
	if existed0:
		for p in pre:
			if mp := self.files.get(p):
				if mp > mt0: newer = true
	for p in dedupe(res.oo):
		_c := self.update(p, t)?
	self.dstack.pop()
	need := self.phony.contains(t) or not self.files.contains(t) or anych or newer
	if need and res.recipe.length() > 0:
		self.run_recipe(t, res, pre, existed0, mt0)?
	self.memo[t.clone()] = need
	return ok(need)

fn var St.build_goal(g: String) Unit!:
	start := self.recipes_run
	_c := self.update(g, "")?
	if self.recipes_run == start:
		res := self.resolve(g)
		if res.recipe.length() > 0 or (not self.phony.contains(g) and self.files.contains(g)):
			out("make: '{g}' is up to date.")
		else:
			out("make: Nothing to be done for '{g}'.")
	return ok(unit)

fn var St.print_err(e: Error) Unit:
	if e.kind == "abort":
		out(e.message)
	else if self.curline > 0:
		out("Makefile:{self.curline}: *** {e.message}.  Stop.")
	else:
		out("make: *** {e.message}.  Stop.")

fn var St.guard(r: Unit!) Bool:
	if _v := r: return true
	self.print_err(r.err())
	return false

fn var St.begin(args: List[String]) List[String]:
	self.reset()
	var targets = List[String]()
	for a in args:
		if i := a.index_of("="):
			if i > 0:
				nm := sl(a, 0, i)
				self.vars[nm.clone()] = Var(0, sl(a, i + 1, a.length()))
				self.cmd.add(nm)
				continue
		targets.append(a.clone())
	return targets

fn var St.deps_visit(t: String) Unit!:
	self.dstack.append(t.clone())
	res := self.resolve(t)
	var kids = dedupe(res.prereqs)
	kids.extend(dedupe(res.oo))
	for p in kids:
		if self.memo.contains(p): continue
		if self.dstack.contains(p):
			var idx = 0
			var k = 0
			while k < self.dstack.length():
				if self.dstack[k] == p:
					idx = k
					break
				k += 1
			var path = List[String]()
			while idx < self.dstack.length():
				path.append(self.dstack[idx].clone())
				idx += 1
			path.append(p.clone())
			return error(abort("make: *** Circular dependency detected: {path.join(" -> ")}.  Stop."))
		self.deps_visit(p)?
	self.dstack.pop()
	self.memo[t.clone()] = true
	self.res_list.append(t.clone())
	return ok(unit)

fn rule_line(head: String, r: Rule) String:
	var s = head + ": " + r.prereqs.join(" ")
	if r.oo.length() > 0: s += " | " + r.oo.join(" ")
	return s.trim_end()

fn var St.request(cmd: String, line: String, args: List[String]) Unit:
	if cmd == "build" or cmd == "dry":
		var targets = self.begin(args)
		self.dry = cmd == "dry"
		if not self.guard(self.parse()): return
		if targets.length() == 0:
			if self.default_goal == "":
				out("make: *** No targets.  Stop.")
				return
			targets.append(self.default_goal.clone())
		for g in targets:
			if not self.guard(self.build_goal(g)): return
		return
	if cmd == "deps":
		targets := self.begin(args)
		self.dry = false
		if not self.guard(self.parse()): return
		if targets.length() != 1:
			out("usage: deps TARGET")
			return
		if not self.guard(self.deps_visit(targets[0])): return
		self.res_list.pop()
		if self.res_list.length() == 0:
			out("(no prerequisites)")
		else:
			for x in self.res_list: out(x)
		return
	if cmd == "targets":
		_t := self.begin(args)
		if not self.guard(self.parse()): return
		if self.default_goal != "": out("default: {self.default_goal}")
		for nm in self.order:
			if idx := self.rindex.get(nm):
				out(rule_line(nm, self.rules[idx]))
		for r in self.patterns:
			out(rule_line("pattern " + r.pat, r))
		if self.phony_order.length() > 0:
			out("phony: " + self.phony_order.join(" "))
		return
	if cmd == "expand":
		_t := self.begin(List[String]())
		if not self.guard(self.parse()): return
		text := sl(line, cmd.length(), line.length()).trim()
		r := self.expand(text)
		if v := r:
			out("[{v}]")
		else:
			self.print_err(r.err())
		return
	if cmd == "files":
		if self.files.length() == 0:
			out("(no files)")
			return
		ks := self.files.keys().sorted()
		for k in ks: out("{k} {self.files.get_or(k, 0)}")
		return
	if cmd == "touch":
		if args.length() == 1:
			tk := self.tick()
			self.files[args[0].clone()] = tk
		else if args.length() == 2:
			if n := args[1].parse_int():
				self.files[args[0].clone()] = n
				if n > self.clock: self.clock = n
			else:
				out("bad request")
		else:
			out("bad request")
		return
	if cmd == "rm":
		for a in args: self.files.remove(a)
		return
	out("unknown request: {cmd}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var st = new_st()
	var section = 0
	var reqs = List[String]()
	for raw in text.split("\n"):
		line := if raw.ends_with("\r"): sl(raw, 0, raw.length() - 1) else: raw.clone()
		if section < 2 and line == "====":
			section += 1
			continue
		if section == 0:
			st.mk.append(line)
		else if section == 1:
			f := line.fields()
			if f.length() == 2:
				if n := f[1].parse_int():
					if n >= 0:
						st.files[f[0].clone()] = n
						if n > st.clock: st.clock = n
		else:
			reqs.append(line)
	for line in reqs:
		t := line.trim()
		if t == "" or t.starts_with("#"): continue
		out("> " + line.trim_end())
		words := t.fields()
		var args = List[String]()
		var k = 1
		while k < words.length():
			args.append(words[k].clone())
			k += 1
		st.request(words[0], t, args)
