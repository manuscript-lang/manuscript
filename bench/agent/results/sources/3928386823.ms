import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import from_scalars from "@std/string.ms"

// AST kinds
A_CHAR: Int := 0
A_ANY: Int := 1
A_CLASS: Int := 2
A_BOL: Int := 3
A_EOL: Int := 4
A_WB: Int := 5
A_NWB: Int := 6
A_REF: Int := 7
A_GROUP: Int := 8
A_LOOK: Int := 9
A_SEQ: Int := 10
A_ALT: Int := 11
A_REP: Int := 12

// program node kinds
N_CHAR: Int := 0
N_ANY: Int := 1
N_CLASS: Int := 2
N_BOL: Int := 3
N_EOL: Int := 4
N_WB: Int := 5
N_NWB: Int := 6
N_REF: Int := 7
N_GSTART: Int := 8
N_GEND: Int := 9
N_LOOK: Int := 10
N_LKEND: Int := 11
N_ALT: Int := 12
N_ENTER: Int := 13
N_LOOP: Int := 14
N_LEND: Int := 15
N_ACCEPT: Int := 16

type Eng:
	p: List[Int] = []
	i: Int = 0
	icase: Bool = false
	multi: Bool = false
	dotall: Bool = false
	ngroups: Int = 0
	names: List[String] = [""]
	refnames: List[String] = []
	// ast
	ak: List[Int] = []
	aa: List[Int] = []
	ab: List[Int] = []
	ac: List[Int] = []
	akids: List[List[Int]] = []
	// classes pool (256 entries each)
	pool: List[Int] = []
	// program
	nk: List[Int] = []
	na: List[Int] = []
	nb: List[Int] = []
	nc: List[Int] = []
	nd: List[Int] = []
	nn: List[Int] = []
	altl: List[List[Int]] = []
	root: Int = 0
	accept: Int = 0
	// match state
	s: List[Int] = []
	full: Bool = false
	capS: List[Int] = []
	capE: List[Int] = []
	tmp: List[Int] = []
	cnt: List[Int] = []
	ist: List[Int] = []
	endpos: Int = 0

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn is_alpha(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_word(c: Int) Bool: is_digit(c) or is_alpha(c) or c == 95

fn lower(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	return c

fn upper(c: Int) Int:
	if c >= 97 and c <= 122: return c - 32
	return c

fn hexval(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn short_has(ch: Int, c: Int) Bool:
	if ch == 100: return is_digit(c)
	if ch == 68: return not is_digit(c)
	if ch == 119: return is_word(c)
	if ch == 87: return not is_word(c)
	isws := c == 32 or c == 9 or c == 10 or c == 13 or c == 12 or c == 11
	if ch == 115: return isws
	return not isws

fn var Eng.mk(k: Int, a: Int, b: Int, c: Int, kids: List[Int]) Int:
	self.ak.append(k)
	self.aa.append(a)
	self.ab.append(b)
	self.ac.append(c)
	self.akids.append(kids)
	return self.ak.length() - 1

fn var Eng.mkset(mem: List[Int]) Int:
	id := self.pool.length() / 256
	for j in 0..256:
		self.pool.append(mem.get(j, 0))
	return id

fn var Eng.short_set(ch: Int) Int:
	var mem = List[Int]()
	for j in 0..256:
		mem.append(if short_has(ch, j): 1 else: 0)
	return self.mkset(mem)

fn Eng.peek(off: Int) Int:
	return self.p.get(self.i + off, -1)

// class item: returns byte (0..255) or 256+letter for shorthand
fn var Eng.class_item() Int!:
	c := self.peek(0)
	self.i += 1
	if c != 92: return ok(c)
	e := self.peek(0)
	if e < 0: return error(Error("bad escape"))
	self.i += 1
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83: return ok(256 + e)
	if e == 110: return ok(10)
	if e == 116: return ok(9)
	if e == 114: return ok(13)
	if e == 120:
		h1 := hexval(self.peek(0))
		h2 := hexval(self.peek(1))
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.i += 2
		return ok(h1 * 16 + h2)
	if is_alpha(e) or is_digit(e) or e >= 128: return error(Error("bad escape"))
	return ok(e)

fn var Eng.parse_class() Int!:
	// self.i is after '['
	var neg = false
	if self.peek(0) == 94:
		neg = true
		self.i += 1
	var mem = List[Int]()
	for j in 0..256:
		mem.append(0)
	var first = true
	var prev_range = false
	while true:
		c := self.peek(0)
		if c < 0: return error(Error("unterminated class"))
		if c == 93 and not first:
			self.i += 1
			break
		first = false
		if c == 45 and prev_range:
			self.i += 1
			mem[45] = 1
			prev_range = false
			continue
		lo := self.class_item()?
		prev_range = false
		if lo >= 256:
			if self.peek(0) == 45 and self.peek(1) != 93:
				if self.peek(1) < 0: return error(Error("unterminated class"))
				self.i += 1
				_hi := self.class_item()?
				return error(Error("bad range"))
			for j in 0..256:
				if short_has(lo - 256, j): mem[j] = 1
			continue
		if self.peek(0) == 45 and self.peek(1) != 93:
			if self.peek(1) < 0: return error(Error("unterminated class"))
			self.i += 1
			hi := self.class_item()?
			if hi >= 256 or hi < lo: return error(Error("bad range"))
			for j in lo..(hi + 1):
				mem[j] = 1
			prev_range = true
			continue
		mem[lo] = 1
	if self.icase:
		for j in 65..91:
			if mem[j] == 1 or mem[j + 32] == 1:
				mem[j] = 1
				mem[j + 32] = 1
	if neg:
		for j in 0..256:
			mem[j] = 1 - mem[j]
	id := self.mkset(mem)
	return ok(self.mk(A_CLASS, id, 0, 0, []))

fn var Eng.name_at() String?:
	// parses [A-Za-z_][A-Za-z0-9_]* at self.i; leaves self.i after name
	c := self.peek(0)
	if not (is_alpha(c) or c == 95): return none
	var out = List[Int]()
	while true:
		d := self.peek(0)
		if is_alpha(d) or is_digit(d) or d == 95:
			out.append(d)
			self.i += 1
		else: break
	r := from_scalars(out)
	if x := r: return x
	return none

fn var Eng.parse_atom() Int!:
	c := self.p[self.i]
	if c == 42 or c == 43 or c == 63: return error(Error("nothing to repeat"))
	self.i += 1
	if c == 46: return ok(self.mk(A_ANY, 0, 0, 0, []))
	if c == 94: return ok(self.mk(A_BOL, 0, 0, 0, []))
	if c == 36: return ok(self.mk(A_EOL, 0, 0, 0, []))
	if c == 91: return self.parse_class()
	if c == 40: return self.parse_group()
	if c == 92: return self.parse_escape()
	return ok(self.lit(c))

fn var Eng.lit(c: Int) Int:
	v := if self.icase: lower(c) else: c
	return self.mk(A_CHAR, v, 0, 0, [])

fn var Eng.parse_escape() Int!:
	e := self.peek(0)
	if e < 0: return error(Error("bad escape"))
	self.i += 1
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		id := self.short_set(e)
		return ok(self.mk(A_CLASS, id, 0, 0, []))
	if e == 110: return ok(self.lit(10))
	if e == 116: return ok(self.lit(9))
	if e == 114: return ok(self.lit(13))
	if e == 98: return ok(self.mk(A_WB, 0, 0, 0, []))
	if e == 66: return ok(self.mk(A_NWB, 0, 0, 0, []))
	if e == 120:
		h1 := hexval(self.peek(0))
		h2 := hexval(self.peek(1))
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.i += 2
		return ok(self.lit(h1 * 16 + h2))
	if e >= 49 and e <= 57: return ok(self.mk(A_REF, e - 48, -1, 0, []))
	if e == 107:
		if self.peek(0) != 60: return error(Error("bad escape"))
		self.i += 1
		nm := self.name_at()
		if self.peek(0) != 62: return error(Error("bad escape"))
		if name := nm:
			self.i += 1
			self.refnames.append(name)
			return ok(self.mk(A_REF, 0, self.refnames.length() - 1, 0, []))
		return error(Error("bad escape"))
	if is_alpha(e) or is_digit(e) or e >= 128: return error(Error("bad escape"))
	return ok(self.lit(e))

fn var Eng.parse_group() Int!:
	// self.i after '('
	if self.peek(0) == 63:
		k := self.peek(1)
		if k == 58:
			self.i += 2
			inner := self.parse_alt(true)?
			return ok(self.mk(A_SEQ, 0, 0, 0, [inner]))
		if k == 61 or k == 33:
			self.i += 2
			inner := self.parse_alt(true)?
			return ok(self.mk(A_LOOK, if k == 33: 1 else: 0, 0, 0, [inner]))
		if k == 60:
			self.i += 2
			nm := self.name_at()
			if self.peek(0) != 62: return error(Error("bad group"))
			if name := nm:
				self.i += 1
				for q in self.names:
					if q == name: return error(Error("duplicate group name"))
				self.ngroups += 1
				g := self.ngroups
				self.names.append(name)
				inner := self.parse_alt(true)?
				return ok(self.mk(A_GROUP, g, 0, 0, [inner]))
			return error(Error("bad group"))
		return error(Error("bad group"))
	self.ngroups += 1
	g := self.ngroups
	self.names.append("")
	inner := self.parse_alt(true)?
	return ok(self.mk(A_GROUP, g, 0, 0, [inner]))

// is there a valid {..} quantifier at offset? returns [len, min, max] or empty
fn Eng.brace_at(at: Int) List[Int]:
	var j = at + 1
	var n1 = 0
	var d1 = 0
	while is_digit(self.p.get(j, -1)):
		n1 = n1 * 10 + (self.p[j] - 48)
		if n1 > 100000: n1 = 100000
		d1 += 1
		j += 1
	if d1 == 0: return []
	if self.p.get(j, -1) == 125: return [j + 1 - at, n1, n1]
	if self.p.get(j, -1) != 44: return []
	j += 1
	var n2 = 0
	var d2 = 0
	while is_digit(self.p.get(j, -1)):
		n2 = n2 * 10 + (self.p[j] - 48)
		if n2 > 100000: n2 = 100000
		d2 += 1
		j += 1
	if self.p.get(j, -1) != 125: return []
	if d2 == 0: return [j + 1 - at, n1, -1]
	return [j + 1 - at, n1, n2]

fn Eng.is_quant_start() Bool:
	c := self.peek(0)
	if c == 42 or c == 43 or c == 63: return true
	if c == 123: return self.brace_at(self.i).length() > 0
	return false

fn var Eng.parse_seq() Int!:
	var items = List[Int]()
	while self.i < self.p.length():
		c := self.p[self.i]
		if c == 124 or c == 41: break
		atom := self.parse_atom()?
		var node = atom
		if self.is_quant_start():
			k := self.ak[atom]
			if k == A_BOL or k == A_EOL or k == A_WB or k == A_NWB or k == A_LOOK:
				return error(Error("nothing to repeat"))
			q := self.peek(0)
			var mn = 0
			var mx = -1
			if q == 42:
				self.i += 1
			else if q == 43:
				mn = 1
				self.i += 1
			else if q == 63:
				mx = 1
				self.i += 1
			else:
				b := self.brace_at(self.i)
				mn = b[1]
				mx = b[2]
				if mn > 1000 or mx > 1000 or (mx >= 0 and mn > mx): return error(Error("bad repeat"))
				self.i += b[0]
			var greedy = 1
			if self.peek(0) == 63:
				greedy = 0
				self.i += 1
			if self.is_quant_start(): return error(Error("nothing to repeat"))
			node = self.mk(A_REP, mn, mx, greedy, [atom])
		items.append(node)
	return ok(self.mk(A_SEQ, 0, 0, 0, items))

fn var Eng.parse_alt(ingroup: Bool) Int!:
	var branches = List[Int]()
	while true:
		b := self.parse_seq()?
		branches.append(b)
		if self.peek(0) == 124:
			self.i += 1
			continue
		break
	if ingroup:
		if self.peek(0) != 41: return error(Error("unmatched ("))
		self.i += 1
	else:
		if self.i < self.p.length(): return error(Error("unmatched )"))
	if branches.length() == 1: return ok(branches[0])
	return ok(self.mk(A_ALT, 0, 0, 0, branches))

fn var Eng.parse_all() Unit!:
	// leading flags
	if self.peek(0) == 40 and self.peek(1) == 63:
		var j = self.i + 2
		var ci = false
		var cm = false
		var cs = false
		var cnt = 0
		while true:
			f := self.p.get(j, -1)
			if f == 105: ci = true
			else if f == 109: cm = true
			else if f == 115: cs = true
			else: break
			cnt += 1
			j += 1
		if cnt > 0 and self.p.get(j, -1) == 41:
			self.icase = ci
			self.multi = cm
			self.dotall = cs
			self.i = j + 1
	r := self.parse_alt(false)?
	// resolve backrefs
	for n in 0..self.ak.length():
		if self.ak[n] == A_REF:
			if self.ab[n] >= 0:
				nm := self.refnames[self.ab[n]]
				var found = -1
				for g in 1..self.names.length():
					if self.names[g] == nm: found = g
				if found < 0: return error(Error("bad backreference"))
				self.aa[n] = found
			else if self.aa[n] > self.ngroups:
				return error(Error("bad backreference"))
	self.accept = self.node(N_ACCEPT, 0, 0, 0, 0, 0)
	self.root = self.compile(r, self.accept)
	return ok(unit)

fn var Eng.node(k: Int, a: Int, b: Int, c: Int, d: Int, nx: Int) Int:
	self.nk.append(k)
	self.na.append(a)
	self.nb.append(b)
	self.nc.append(c)
	self.nd.append(d)
	self.nn.append(nx)
	return self.nk.length() - 1

fn var Eng.compile(a: Int, next: Int) Int:
	k := self.ak[a]
	if k == A_CHAR: return self.node(N_CHAR, self.aa[a], 0, 0, 0, next)
	if k == A_ANY: return self.node(N_ANY, 0, 0, 0, 0, next)
	if k == A_CLASS: return self.node(N_CLASS, self.aa[a], 0, 0, 0, next)
	if k == A_BOL: return self.node(N_BOL, 0, 0, 0, 0, next)
	if k == A_EOL: return self.node(N_EOL, 0, 0, 0, 0, next)
	if k == A_WB: return self.node(N_WB, 0, 0, 0, 0, next)
	if k == A_NWB: return self.node(N_NWB, 0, 0, 0, 0, next)
	if k == A_REF: return self.node(N_REF, self.aa[a], 0, 0, 0, next)
	if k == A_SEQ:
		var cur = next
		var kids = List[Int]()
		for x in self.akids[a]:
			kids.append(x)
		var j = kids.length() - 1
		while j >= 0:
			cur = self.compile(kids[j], cur)
			j -= 1
		return cur
	if k == A_ALT:
		var kids = List[Int]()
		for x in self.akids[a]:
			kids.append(x)
		var starts = List[Int]()
		for x in kids:
			starts.append(self.compile(x, next))
		self.altl.append(starts)
		return self.node(N_ALT, self.altl.length() - 1, 0, 0, 0, next)
	if k == A_GROUP:
		kid := self.akids[a][0]
		g := self.aa[a]
		e := self.node(N_GEND, g, 0, 0, 0, next)
		body := self.compile(kid, e)
		return self.node(N_GSTART, g, 0, 0, 0, body)
	if k == A_LOOK:
		kid := self.akids[a][0]
		e := self.node(N_LKEND, 0, 0, 0, 0, 0)
		body := self.compile(kid, e)
		return self.node(N_LOOK, self.aa[a], body, 0, 0, next)
	// REP
	kid := self.akids[a][0]
	l := self.node(N_LOOP, self.aa[a], self.ab[a], self.ac[a], 0, next)
	e := self.node(N_LEND, l, 0, 0, 0, 0)
	body := self.compile(kid, e)
	self.nd[l] = body
	return self.node(N_ENTER, l, 0, 0, 0, 0)

// ---------- matching ----------

fn Eng.wordat(pos: Int) Bool:
	if pos < 0 or pos >= self.s.length(): return false
	return is_word(self.s[pos])

fn var Eng.iter(l: Int, pos: Int) Bool:
	oi := self.ist[l]
	self.ist[l] = pos
	if self.m(self.nd[l], pos): return true
	self.ist[l] = oi
	return false

fn var Eng.decide(l: Int, pos: Int) Bool:
	c := self.cnt[l]
	mn := self.na[l]
	mx := self.nb[l]
	if c < mn: return self.iter(l, pos)
	if mx >= 0 and c >= mx: return self.m(self.nn[l], pos)
	if self.nc[l] == 1:
		if self.iter(l, pos): return true
		return self.m(self.nn[l], pos)
	if self.m(self.nn[l], pos): return true
	return self.iter(l, pos)

fn var Eng.m(start: Int, pos0: Int) Bool:
	var n = start
	var pos = pos0
	len := self.s.length()
	while true:
		k := self.nk[n]
		if k == N_CHAR:
			if pos >= len: return false
			ch := self.s[pos]
			v := if self.icase: lower(ch) else: ch
			if v != self.na[n]: return false
			pos += 1
			n = self.nn[n]
		else if k == N_ANY:
			if pos >= len: return false
			if not self.dotall and self.s[pos] == 10: return false
			pos += 1
			n = self.nn[n]
		else if k == N_CLASS:
			if pos >= len: return false
			if self.pool[self.na[n] * 256 + self.s[pos]] == 0: return false
			pos += 1
			n = self.nn[n]
		else if k == N_BOL:
			if not (pos == 0 or (self.multi and self.s[pos - 1] == 10)): return false
			n = self.nn[n]
		else if k == N_EOL:
			if not (pos == len or (self.multi and self.s[pos] == 10)): return false
			n = self.nn[n]
		else if k == N_WB:
			if self.wordat(pos - 1) == self.wordat(pos): return false
			n = self.nn[n]
		else if k == N_NWB:
			if self.wordat(pos - 1) != self.wordat(pos): return false
			n = self.nn[n]
		else if k == N_REF:
			g := self.na[n]
			gs := self.capS[g]
			if gs < 0: return false
			ge := self.capE[g]
			l := ge - gs
			if pos + l > len: return false
			for j in 0..l:
				a := self.s[gs + j]
				b := self.s[pos + j]
				if self.icase:
					if lower(a) != lower(b): return false
				else if a != b: return false
			pos += l
			n = self.nn[n]
		else if k == N_GSTART:
			g := self.na[n]
			old := self.tmp[g]
			self.tmp[g] = pos
			if self.m(self.nn[n], pos): return true
			self.tmp[g] = old
			return false
		else if k == N_GEND:
			g := self.na[n]
			os := self.capS[g]
			oe := self.capE[g]
			self.capS[g] = self.tmp[g]
			self.capE[g] = pos
			if self.m(self.nn[n], pos): return true
			self.capS[g] = os
			self.capE[g] = oe
			return false
		else if k == N_ALT:
			var brs = List[Int]()
			for x in self.altl[self.na[n]]:
				brs.append(x)
			for x in brs:
				if self.m(x, pos): return true
			return false
		else if k == N_ENTER:
			l := self.na[n]
			oc := self.cnt[l]
			oi := self.ist[l]
			self.cnt[l] = 0
			self.ist[l] = -1
			if self.decide(l, pos): return true
			self.cnt[l] = oc
			self.ist[l] = oi
			return false
		else if k == N_LEND:
			l := self.na[n]
			c := self.cnt[l]
			self.cnt[l] = c + 1
			var r = false
			if pos == self.ist[l] and c + 1 >= self.na[l]:
				r = self.m(self.nn[l], pos)
			else:
				r = self.decide(l, pos)
			if r: return true
			self.cnt[l] = c
			return false
		else if k == N_LOOK:
			var sS = List[Int]()
			var sE = List[Int]()
			for x in self.capS:
				sS.append(x)
			for x in self.capE:
				sE.append(x)
			r := self.m(self.nb[n], pos)
			neg := self.na[n] == 1
			if neg:
				for j in 0..sS.length():
					self.capS[j] = sS[j]
					self.capE[j] = sE[j]
				if r: return false
				n = self.nn[n]
			else:
				if not r: return false
				if self.m(self.nn[n], pos): return true
				for j in 0..sS.length():
					self.capS[j] = sS[j]
					self.capE[j] = sE[j]
				return false
		else if k == N_LKEND:
			return true
		else:
			// accept
			if self.full and pos != len: return false
			self.endpos = pos
			return true
	return false

// attempt match starting exactly at `st`
fn var Eng.attempt(st: Int) Bool:
	for g in 0..(self.ngroups + 1):
		self.capS[g] = -1
		self.capE[g] = -1
		self.tmp[g] = -1
	if self.m(self.root, st):
		self.capS[0] = st
		self.capE[0] = self.endpos
		return true
	return false

fn var Eng.search(from: Int) Bool:
	var st = from
	while st <= self.s.length():
		if self.attempt(st): return true
		st += 1
	return false

fn var Eng.prepare(subj: List[Int]) Unit:
	self.s = subj.clone()
	self.capS = []
	self.capE = []
	self.tmp = []
	for g in 0..(self.ngroups + 1):
		self.capS.append(-1)
		self.capE.append(-1)
		self.tmp.append(-1)
	self.cnt = []
	self.ist = []
	for j in 0..self.nk.length():
		self.cnt.append(0)
		self.ist.append(-1)

// ---------- driver ----------

HEXD: String := "0123456789abcdef"

fn quoted(s: List[Int], a: Int, b: Int) String:
	var out = List[Int]()
	out.append(34)
	hx := HEXD.as_bytes()
	for j in a..b:
		c := s[j]
		if c == 92:
			out.append(92)
			out.append(92)
		else if c == 34:
			out.append(92)
			out.append(34)
		else if c == 10:
			out.append(92)
			out.append(110)
		else if c == 9:
			out.append(92)
			out.append(116)
		else if c == 13:
			out.append(92)
			out.append(114)
		else if c < 32 or c > 126:
			out.append(92)
			out.append(120)
			out.append(hx.get(c / 16, 48).to_int())
			out.append(hx.get(c % 16, 48).to_int())
		else: out.append(c)
	out.append(34)
	r := from_scalars(out)
	if x := r: return x
	return "\"\""

// unescape subject/replacement; none on error
fn unescape(f: List[Int]) List[Int]?:
	var out = List[Int]()
	var j = 0
	while j < f.length():
		c := f[j]
		if c != 92:
			out.append(c)
			j += 1
			continue
		e := f.get(j + 1, -1)
		if e < 0: return none
		if e == 110: out.append(10)
		else if e == 116: out.append(9)
		else if e == 92: out.append(92)
		else if e == 120:
			h1 := hexval(f.get(j + 2, -1))
			h2 := hexval(f.get(j + 3, -1))
			if h1 < 0 or h2 < 0: return none
			out.append(h1 * 16 + h2)
			j += 2
		else: return none
		j += 2
	return out

fn bstr(f: List[Int]) String:
	var o = List[Int]()
	for c in f:
		if c < 128: o.append(c)
	r := from_scalars(o)
	if x := r: return x
	return ""

fn group_label(e: Eng, g: Int) String:
	if g == 0 or e.names[g] == "": return "{g}"
	return "{g} ({e.names[g]})"

// returns expansion or none on error
fn expand(e: Eng, rep: List[Int]) List[Int]?:
	var out = List[Int]()
	var j = 0
	while j < rep.length():
		c := rep[j]
		if c != 36:
			out.append(c)
			j += 1
			continue
		d := rep.get(j + 1, -1)
		if d == 36:
			out.append(36)
			j += 2
		else if is_digit(d):
			g := d - 48
			if g > e.ngroups: return none
			if e.capS[g] >= 0:
				for q in e.capS[g]..e.capE[g]:
					out.append(e.s[q])
			j += 2
		else if d == 123:
			var q = j + 2
			var nm = List[Int]()
			var closed = false
			while q < rep.length():
				if rep[q] == 125:
					closed = true
					break
				nm.append(rep[q])
				q += 1
			if not closed: return none
			name := bstr(nm)
			var found = -1
			for g in 1..e.names.length():
				if e.names[g] == name: found = g
			if found < 0: return none
			if e.capS[found] >= 0:
				for z in e.capS[found]..e.capE[found]:
					out.append(e.s[z])
			j = q + 1
		else:
			out.append(36)
			j += 1
	return out

fn is_cmd(name: List[Int], s: String) Bool:
	return bstr(name) == s and name.length() == s.length()

fn run_line(line: List[Int]) Unit:
	var fields = List[List[Int]]()
	var cur = List[Int]()
	for c in line:
		if c == 9:
			fields.append(cur.clone())
			cur = []
		else: cur.append(c)
	fields.append(cur.clone())
	name := fields[0].clone()
	var cmd = ""
	for cn in ["test", "match", "full", "find-all", "split", "replace"]:
		if is_cmd(name, cn): cmd = cn
	need := if cmd == "replace": 4 else: 3
	if cmd == "" or fields.length() != need:
		print("error: bad command")
		return
	subj0 := unescape(fields[2])
	if subj0.is_none():
		print("error: bad command")
		return
	subj := subj0.get([])
	var rep = List[Int]()
	if cmd == "replace":
		r0 := unescape(fields[3])
		if r0.is_none():
			print("error: bad command")
			return
		rep = r0.get([])
	var e = Eng()
	e.p = fields[1].clone()
	pr := e.parse_all()
	if pr.is_error():
		print("error: {pr.err().message}")
		return
	e.prepare(subj)
	if cmd == "test":
		print(if e.search(0): "true" else: "false")
		return
	if cmd == "match" or cmd == "full":
		var ok_ = false
		if cmd == "full":
			e.full = true
			ok_ = e.attempt(0)
		else: ok_ = e.search(0)
		if not ok_:
			print("no match")
			return
		for g in 0..(e.ngroups + 1):
			if e.capS[g] < 0: print("{group_label(e, g)}: unset")
			else: print("{group_label(e, g)}: {e.capS[g]}..{e.capE[g]} {quoted(subj, e.capS[g], e.capE[g])}")
		return
	// find-all family
	var pos = 0
	var res = List[Int]()
	var pieces = List[String]()
	var last = 0
	var count = 0
	var bad = false
	while pos <= subj.length():
		if not e.search(pos): break
		st := e.capS[0]
		en := e.capE[0]
		count += 1
		if cmd == "find-all":
			print("{st}..{en} {quoted(subj, st, en)}")
		else if cmd == "split":
			if en > st:
				pieces.append(quoted(subj, last, st))
				last = en
		else:
			for q in last..st:
				res.append(subj[q])
			x := expand(e, rep)
			if x2 := x:
				for c in x2:
					res.append(c)
			else:
				bad = true
				break
			last = en
		pos = if en == st: en + 1 else: en
	if cmd == "find-all":
		print("({count} matches)")
	else if cmd == "split":
		pieces.append(quoted(subj, last, subj.length()))
		for p in pieces:
			print(p)
		print("({pieces.length()} pieces)")
	else:
		if bad:
			print("error: bad replacement")
			return
		for q in last..subj.length():
			res.append(subj[q])
		print(quoted(res, 0, res.length()))

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	var line = List[Int]()
	for j in 0..data.length():
		c := data.get(j, 0).to_int()
		if c == 10:
			if line.length() > 0: run_line(line)
			line = []
		else: line.append(c)
	if line.length() > 0: run_line(line)
