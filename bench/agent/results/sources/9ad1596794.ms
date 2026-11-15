import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

NAMECH := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"

fn is_digit(b: Int) Bool: b >= 48 and b <= 57
fn is_alpha(b: Int) Bool: (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
fn is_alnum(b: Int) Bool: is_digit(b) or is_alpha(b)
fn is_word(b: Int) Bool: is_alnum(b) or b == 95

fn hexval(b: Int) Int:
	if b >= 48 and b <= 57: return b - 48
	if b >= 97 and b <= 102: return b - 87
	if b >= 65 and b <= 70: return b - 55
	return -1

fn fold(b: Int) Int:
	if b >= 65 and b <= 90: return b + 32
	return b

fn short_has(ch: Int, b: Int) Bool:
	neg := ch < 97
	lc := if neg: ch + 32 else: ch
	var base = false
	if lc == 100: base = is_digit(b)
	else if lc == 119: base = is_word(b)
	else: base = b == 32 or (b >= 9 and b <= 13)
	return if neg: not base else: base

fn name_of(bs: List[Int], from: Int, to: Int) String:
	if to <= from: return ""
	chars := NAMECH.chars()
	var out = ""
	for i in from..to:
		b := bs[i]
		var idx = -1
		if is_digit(b): idx = b - 48
		else if b >= 65 and b <= 90: idx = 10 + b - 65
		else if b == 95: idx = 36
		else if b >= 97 and b <= 122: idx = 37 + b - 97
		if idx < 0: return ""
		out += chars.get(idx, "")
	return out

type Re:
	p: List[Int] = []
	pos: Int = 0
	ngroups: Int = 0
	names: List[String] = [""]
	fi: Bool = false
	fm: Bool = false
	fs: Bool = false
	ak: List[Int] = []
	a1: List[Int] = []
	a2: List[Int] = []
	a3: List[Int] = []
	a4: List[Int] = []
	sib: List[Int] = []
	refnames: List[String] = []
	refs: List[Int] = []
	cls: List[Bool] = []
	ncls: Int = 0
	nk: List[Int] = []
	na: List[Int] = []
	nb: List[Int] = []
	nc: List[Int] = []
	nd: List[Int] = []
	ne: List[Int] = []
	nn: List[Int] = []
	nloops: Int = 0
	entry: Int = 0
	s: List[Int] = []
	full: Bool = false
	cs: List[Int] = []
	ce: List[Int] = []
	op: List[Int] = []
	tmp: List[Int] = []
	lcnt: List[Int] = []
	lst: List[Int] = []
	endpos: Int = 0

fn Re.peek() Int:
	if self.pos < self.p.length(): return self.p[self.pos]
	return -1

fn var Re.mk(k: Int, x1: Int = 0, x2: Int = 0, x3: Int = 0, x4: Int = 0) Int:
	self.ak.append(k)
	self.a1.append(x1)
	self.a2.append(x2)
	self.a3.append(x3)
	self.a4.append(x4)
	self.sib.append(-1)
	return self.ak.length() - 1

fn var Re.add(k: Int, x: Int = 0, y: Int = 0, z: Int = 0, w: Int = 0, e: Int = 0, nx: Int = -1) Int:
	self.nk.append(k)
	self.na.append(x)
	self.nb.append(y)
	self.nc.append(z)
	self.nd.append(w)
	self.ne.append(e)
	self.nn.append(nx)
	return self.nk.length() - 1

fn var Re.new_class(m: List[Bool], neg: Bool) Int:
	var mm = m.clone()
	if self.fi:
		for b in 65..91:
			if mm[b] or mm[b + 32]:
				mm[b] = true
				mm[b + 32] = true
	for b in 0..256:
		self.cls.append(if neg: not mm[b] else: mm[b])
	self.ncls += 1
	return self.ncls - 1

fn empty_set() List[Bool]:
	var m = List[Bool]()
	for _b in 0..256:
		m.append(false)
	return m

fn var Re.lit(b: Int) Int:
	if self.fi and is_alpha(b):
		var m = empty_set()
		m[fold(b)] = true
		m[fold(b) - 32] = true
		return self.mk(2, self.new_class(m, false))
	return self.mk(1, b)

fn var Re.esc_byte(c: Int) Int!:
	// pos is just after the escape letter c
	if c == 110: return ok(10)
	if c == 116: return ok(9)
	if c == 114: return ok(13)
	if c == 120:
		h1 := if self.pos < self.p.length(): hexval(self.p[self.pos]) else: -1
		h2 := if self.pos + 1 < self.p.length(): hexval(self.p[self.pos + 1]) else: -1
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.pos += 2
		return ok(h1 * 16 + h2)
	if c < 128 and not is_alnum(c): return ok(c)
	return error(Error("bad escape"))

fn var Re.class_item() Int!:
	c := self.p[self.pos]
	self.pos += 1
	if c != 92: return ok(c)
	e := self.peek()
	if e < 0: return error(Error("bad escape"))
	self.pos += 1
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83: return ok(-e)
	return self.esc_byte(e)

fn var Re.parse_class() Int!:
	var neg = false
	if self.peek() == 94:
		neg = true
		self.pos += 1
	var m = empty_set()
	var first = true
	var after_range = false
	while true:
		c := self.peek()
		if c < 0: return error(Error("unterminated class"))
		if c == 93 and not first:
			self.pos += 1
			break
		first = false
		item := self.class_item()?
		dash := self.peek() == 45 and self.pos + 1 < self.p.length() and self.p[self.pos + 1] != 93
		if item < 0:
			if dash and not after_range: return error(Error("bad range"))
			after_range = false
			for b in 0..256:
				if short_has(-item, b): m[b] = true
			continue
		if dash and not after_range:
			self.pos += 1
			hi := self.class_item()?
			if hi < 0 or hi < item: return error(Error("bad range"))
			for b in item..(hi + 1):
				m[b] = true
			after_range = true
		else:
			after_range = false
			m[item] = true
	return ok(self.new_class(m, neg))

fn var Re.parse_name() String:
	start := self.pos
	if self.pos < self.p.length():
		c := self.p[self.pos]
		if is_alpha(c) or c == 95:
			self.pos += 1
			while self.pos < self.p.length() and is_word(self.p[self.pos]):
				self.pos += 1
	return name_of(self.p, start, self.pos)

fn var Re.parse_escape() Int!:
	e := self.peek()
	if e < 0: return error(Error("bad escape"))
	self.pos += 1
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		var m = empty_set()
		for b in 0..256:
			if short_has(e, b): m[b] = true
		return ok(self.mk(2, self.new_class(m, false)))
	if e == 98: return ok(self.mk(5))
	if e == 66: return ok(self.mk(6))
	if e >= 49 and e <= 57:
		id := self.mk(7, e - 48, if self.fi: 1 else: 0, -1)
		self.refs.append(id)
		return ok(id)
	if e == 107:
		if self.peek() != 60: return error(Error("bad escape"))
		self.pos += 1
		name := self.parse_name()
		if name == "" or self.peek() != 62: return error(Error("bad escape"))
		self.pos += 1
		self.refnames.append(name)
		id := self.mk(7, -1, if self.fi: 1 else: 0, self.refnames.length() - 1)
		self.refs.append(id)
		return ok(id)
	b := self.esc_byte(e)?
	return ok(self.lit(b))

fn var Re.parse_group(depth: Int) Int!:
	var kind = 0
	var gname = ""
	if self.peek() == 63:
		self.pos += 1
		d := self.peek()
		if d == 58:
			kind = 1
			self.pos += 1
		else if d == 61:
			kind = 2
			self.pos += 1
		else if d == 33:
			kind = 3
			self.pos += 1
		else if d == 60:
			self.pos += 1
			gname = self.parse_name()
			if gname == "" or self.peek() != 62: return error(Error("bad group"))
			self.pos += 1
			for nm in self.names:
				if nm == gname: return error(Error("duplicate group name"))
		else:
			return error(Error("bad group"))
	var g = 0
	if kind == 0:
		self.ngroups += 1
		g = self.ngroups
		self.names.append(gname)
	inner := self.parse_alt(depth + 1)?
	if self.peek() != 41: return error(Error("unmatched ("))
	self.pos += 1
	if kind == 0: return ok(self.mk(8, g, inner))
	if kind == 1: return ok(inner)
	return ok(self.mk(13, if kind == 3: 1 else: 0, inner))

fn var Re.parse_atom(depth: Int) Int!:
	c := self.p[self.pos]
	self.pos += 1
	if c == 40: return self.parse_group(depth)
	if c == 91:
		ci := self.parse_class()?
		return ok(self.mk(2, ci))
	if c == 46:
		var m = empty_set()
		for b in 0..256:
			if b != 10 or self.fs: m[b] = true
		return ok(self.mk(2, self.new_class(m, false)))
	if c == 94: return ok(self.mk(3, if self.fm: 1 else: 0))
	if c == 36: return ok(self.mk(4, if self.fm: 1 else: 0))
	if c == 92: return self.parse_escape()
	return ok(self.lit(c))

// returns [min, max, end] or [] when not a valid {n}, {n,}, {n,m}
fn Re.shape(at: Int) List[Int]:
	n := self.p.length()
	var i = at + 1
	var mn = 0
	var cnt = 0
	while i < n and is_digit(self.p[i]):
		mn = mn * 10 + self.p[i] - 48
		if mn > 100000: mn = 100000
		cnt += 1
		i += 1
	if cnt == 0 or i >= n: return []
	if self.p[i] == 125: return [mn, mn, i + 1]
	if self.p[i] != 44: return []
	i += 1
	var mx = 0
	var c2 = 0
	while i < n and is_digit(self.p[i]):
		mx = mx * 10 + self.p[i] - 48
		if mx > 100000: mx = 100000
		c2 += 1
		i += 1
	if i >= n or self.p[i] != 125: return []
	if c2 == 0: return [mn, -1, i + 1]
	return [mn, mx, i + 1]

fn var Re.parse_seq(depth: Int) Int!:
	var items = List[Int]()
	while true:
		c := self.peek()
		if c < 0 or c == 124: break
		if c == 41:
			if depth == 0: return error(Error("unmatched )"))
			break
		if c == 42 or c == 43 or c == 63: return error(Error("nothing to repeat"))
		atom := self.parse_atom(depth)?
		var cur = atom
		q := self.peek()
		var mn = 0
		var mx = -1
		var has = false
		var brace = false
		if q == 42:
			has = true
			self.pos += 1
		else if q == 43:
			has = true
			mn = 1
			self.pos += 1
		else if q == 63:
			has = true
			mx = 1
			self.pos += 1
		else if q == 123:
			sh := self.shape(self.pos)
			if sh.length() == 3:
				has = true
				brace = true
				k := self.ak[atom]
				if k == 3 or k == 4 or k == 5 or k == 6 or k == 13: return error(Error("nothing to repeat"))
				mn = sh[0]
				mx = sh[1]
				if mn > 1000 or mx > 1000 or (mx >= 0 and mn > mx): return error(Error("bad repeat"))
				self.pos = sh[2]
		if has:
			k := self.ak[atom]
			if not brace and (k == 3 or k == 4 or k == 5 or k == 6 or k == 13): return error(Error("nothing to repeat"))
			var greedy = 1
			if self.peek() == 63:
				greedy = 0
				self.pos += 1
			cur = self.mk(12, atom, mn, mx, greedy)
			if self.peek() == 123 and self.shape(self.pos).length() == 3: return error(Error("nothing to repeat"))
		items.append(cur)
	seq := self.mk(11, -1)
	if items.length() > 0:
		self.a1[seq] = items[0]
		for i in 0..(items.length() - 1):
			self.sib[items[i]] = items[i + 1]
	return ok(seq)

fn var Re.parse_alt(depth: Int) Int!:
	var alts = List[Int]()
	while true:
		s := self.parse_seq(depth)?
		alts.append(s)
		if self.peek() == 124:
			self.pos += 1
		else:
			break
	if alts.length() == 1: return ok(alts[0])
	node := self.mk(10, -1)
	self.a1[node] = alts[0]
	for i in 0..(alts.length() - 1):
		self.sib[alts[i]] = alts[i + 1]
	return ok(node)

fn var Re.parse_pattern() Int!:
	n := self.p.length()
	if n >= 2 and self.p[0] == 40 and self.p[1] == 63:
		var j = 2
		while j < n and (self.p[j] == 105 or self.p[j] == 109 or self.p[j] == 115):
			j += 1
		if j > 2 and j < n and self.p[j] == 41:
			for t in 2..j:
				if self.p[t] == 105: self.fi = true
				else if self.p[t] == 109: self.fm = true
				else: self.fs = true
			self.pos = j + 1
	root := self.parse_alt(0)?
	for r in self.refs:
		if self.a1[r] > 0:
			if self.a1[r] > self.ngroups: return error(Error("bad backreference"))
		else:
			nm := self.refnames[self.a3[r]]
			var found = -1
			for i in 1..self.names.length():
				if self.names[i] == nm: found = i
			if found < 0: return error(Error("bad backreference"))
			self.a1[r] = found
	return ok(root)

fn var Re.comp(id: Int, nx: Int) Int:
	k := self.ak[id]
	if k == 1: return self.add(1, self.a1[id], nx: nx)
	if k == 2: return self.add(2, self.a1[id], nx: nx)
	if k == 3: return self.add(3, self.a1[id], nx: nx)
	if k == 4: return self.add(4, self.a1[id], nx: nx)
	if k == 5: return self.add(5, nx: nx)
	if k == 6: return self.add(6, nx: nx)
	if k == 7: return self.add(7, self.a1[id], self.a2[id], nx: nx)
	if k == 8:
		g := self.a1[id]
		en := self.add(9, g, nx: nx)
		body := self.comp(self.a2[id], en)
		return self.add(8, g, nx: body)
	if k == 11:
		var kids = List[Int]()
		var c = self.a1[id]
		while c >= 0:
			kids.append(c)
			c = self.sib[c]
		var cur = nx
		var i = kids.length() - 1
		while i >= 0:
			cur = self.comp(kids[i], cur)
			i -= 1
		return cur
	if k == 10:
		var kids = List[Int]()
		var c = self.a1[id]
		while c >= 0:
			kids.append(c)
			c = self.sib[c]
		var entries = List[Int]()
		for kid in kids:
			entries.append(self.comp(kid, nx))
		var cur = entries[entries.length() - 1]
		var i = entries.length() - 2
		while i >= 0:
			cur = self.add(10, entries[i], cur)
			i -= 1
		return cur
	if k == 12:
		kid := self.a1[id]
		mn := self.a2[id]
		mx := self.a3[id]
		gr := self.a4[id]
		kk := self.ak[kid]
		if kk == 1 or kk == 2:
			m := self.comp(kid, 0)
			return self.add(14, mn, mx, gr, m, nx: nx)
		l := self.nloops
		self.nloops += 1
		chk := self.add(12, l, mn, mx, gr, 0, nx: nx)
		en := self.add(13, l, nx: chk)
		body := self.comp(kid, en)
		self.ne[chk] = body
		return self.add(11, l, nx: chk)
	// lookahead
	acc := self.add(16)
	body := self.comp(self.a2[id], acc)
	return self.add(15, self.a1[id], body, nx: nx)

fn Re.char_ok(m: Int, b: Int) Bool:
	if self.nk[m] == 1: return self.na[m] == b
	return self.cls[self.na[m] * 256 + b]

fn var Re.enter(l: Int, body: Int, pos: Int) Bool:
	old := self.lst[l]
	self.lst[l] = pos
	if self.run(body, pos): return true
	self.lst[l] = old
	return false

fn Re.wordat(i: Int) Bool:
	if i < 0 or i >= self.s.length(): return false
	return is_word(self.s[i])

fn var Re.run(start_node: Int, start_pos: Int) Bool:
	var node = start_node
	var pos = start_pos
	n := self.s.length()
	while true:
		k := self.nk[node]
		if k == 1:
			if pos < n and self.s[pos] == self.na[node]:
				pos += 1
				node = self.nn[node]
			else:
				return false
		else if k == 2:
			if pos < n and self.cls[self.na[node] * 256 + self.s[pos]]:
				pos += 1
				node = self.nn[node]
			else:
				return false
		else if k == 0:
			if self.full and pos != n: return false
			self.endpos = pos
			return true
		else if k == 16:
			return true
		else if k == 3:
			if pos == 0 or (self.na[node] == 1 and self.s[pos - 1] == 10):
				node = self.nn[node]
			else:
				return false
		else if k == 4:
			if pos == n or (self.na[node] == 1 and self.s[pos] == 10):
				node = self.nn[node]
			else:
				return false
		else if k == 5 or k == 6:
			b := self.wordat(pos - 1) != self.wordat(pos)
			if b == (k == 5):
				node = self.nn[node]
			else:
				return false
		else if k == 7:
			g := self.na[node]
			if self.op[g] == 1 or self.cs[g] < 0: return false
			ln := self.ce[g] - self.cs[g]
			if pos + ln > n: return false
			st := self.cs[g]
			for i in 0..ln:
				x := self.s[st + i]
				y := self.s[pos + i]
				if self.nb[node] == 1:
					if fold(x) != fold(y): return false
				else:
					if x != y: return false
			pos += ln
			node = self.nn[node]
		else if k == 8:
			g := self.na[node]
			ot := self.tmp[g]
			oo := self.op[g]
			self.tmp[g] = pos
			self.op[g] = 1
			if self.run(self.nn[node], pos): return true
			self.tmp[g] = ot
			self.op[g] = oo
			return false
		else if k == 9:
			g := self.na[node]
			os := self.cs[g]
			oe := self.ce[g]
			self.cs[g] = self.tmp[g]
			self.ce[g] = pos
			self.op[g] = 0
			if self.run(self.nn[node], pos): return true
			self.cs[g] = os
			self.ce[g] = oe
			self.op[g] = 1
			return false
		else if k == 10:
			if self.run(self.na[node], pos): return true
			node = self.nb[node]
		else if k == 11:
			l := self.na[node]
			oc := self.lcnt[l]
			os := self.lst[l]
			self.lcnt[l] = 0
			self.lst[l] = -1
			if self.run(self.nn[node], pos): return true
			self.lcnt[l] = oc
			self.lst[l] = os
			return false
		else if k == 12:
			l := self.na[node]
			c := self.lcnt[l]
			mn := self.nb[node]
			mx := self.nc[node]
			if c < mn: return self.enter(l, self.ne[node], pos)
			if mx >= 0 and c >= mx:
				node = self.nn[node]
			else if self.nd[node] == 1:
				if self.enter(l, self.ne[node], pos): return true
				node = self.nn[node]
			else:
				if self.run(self.nn[node], pos): return true
				return self.enter(l, self.ne[node], pos)
		else if k == 13:
			l := self.na[node]
			chk := self.nn[node]
			oc := self.lcnt[l]
			c := oc + 1
			consumed := pos != self.lst[l]
			self.lcnt[l] = c
			var r = false
			if c >= self.nb[chk] and not consumed:
				r = self.run(self.nn[chk], pos)
			else:
				r = self.run(chk, pos)
			if not r: self.lcnt[l] = oc
			return r
		else if k == 14:
			mn := self.na[node]
			mx := self.nb[node]
			m := self.nd[node]
			ex := self.nn[node]
			if self.nc[node] == 1:
				var cnt = 0
				while pos + cnt < n and (mx < 0 or cnt < mx) and self.char_ok(m, self.s[pos + cnt]):
					cnt += 1
				if cnt < mn: return false
				var j = cnt
				while j > mn:
					if self.run(ex, pos + j): return true
					j -= 1
				pos += mn
				node = ex
			else:
				for i in 0..mn:
					if pos + i >= n or not self.char_ok(m, self.s[pos + i]): return false
				var j = mn
				while true:
					if self.run(ex, pos + j): return true
					if mx >= 0 and j >= mx: return false
					if pos + j >= n or not self.char_ok(m, self.s[pos + j]): return false
					j += 1
		else:
			// lookahead
			neg := self.na[node] == 1
			scs := self.cs.clone()
			sce := self.ce.clone()
			r := self.run(self.nb[node], pos)
			if neg:
				self.cs = scs
				self.ce = sce
				if r: return false
				node = self.nn[node]
			else:
				if not r: return false
				if self.run(self.nn[node], pos): return true
				self.cs = scs
				self.ce = sce
				return false
	return false

fn var Re.try_at(st: Int) Bool:
	for g in 0..(self.ngroups + 1):
		self.cs[g] = -1
		self.ce[g] = -1
		self.op[g] = 0
		self.tmp[g] = -1
	for l in 0..self.nloops:
		self.lcnt[l] = 0
		self.lst[l] = -1
	return self.run(self.entry, st)

// search from `from`; returns start or -1
fn var Re.search(from: Int) Int:
	n := self.s.length()
	var st = from
	while st <= n:
		if self.try_at(st): return st
		st += 1
	return -1

fn compile(pat: List[Int]) Re!:
	var re = Re()
	re.p = pat.clone()
	root := re.parse_pattern()?
	acc := re.add(0)
	re.entry = re.comp(root, acc)
	for _g in 0..(re.ngroups + 1):
		re.cs.append(-1)
		re.ce.append(-1)
		re.op.append(0)
		re.tmp.append(-1)
	for _l in 0..re.nloops:
		re.lcnt.append(0)
		re.lst.append(-1)
	return ok(re)

HEX := "0123456789abcdef"

fn quoted(s: List[Int], a: Int, b: Int) String:
	hx := HEX.chars()
	var out = "\""
	for i in a..b:
		c := s[i]
		if c == 92: out += "\\\\"
		else if c == 34: out += "\\\""
		else if c == 10: out += "\\n"
		else if c == 9: out += "\\t"
		else if c == 13: out += "\\r"
		else if c < 32 or c > 126: out += "\\x" + hx.get(c / 16, "") + hx.get(c % 16, "")
		else: out += ascii_char(c)
	out += "\""
	return out

fn ascii_char(c: Int) String:
	table := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~".chars()
	return table.get(c - 32, "")

fn unescape(f: List[Int]) List[Int]!:
	var out = List[Int]()
	var i = 0
	n := f.length()
	while i < n:
		c := f[i]
		if c != 92:
			out.append(c)
			i += 1
			continue
		if i + 1 >= n: return error(Error("bad"))
		e := f[i + 1]
		if e == 110:
			out.append(10)
			i += 2
		else if e == 116:
			out.append(9)
			i += 2
		else if e == 92:
			out.append(92)
			i += 2
		else if e == 120:
			if i + 3 > n - 1: return error(Error("bad"))
			h1 := hexval(f[i + 2])
			h2 := hexval(f[i + 3])
			if h1 < 0 or h2 < 0: return error(Error("bad"))
			out.append(h1 * 16 + h2)
			i += 4
		else:
			return error(Error("bad"))
	return ok(out)

type Hit:
	st: Int
	en: Int
	cs: List[Int]
	ce: List[Int]

fn var Re.all_matches() List[Hit]:
	var hits = List[Hit]()
	n := self.s.length()
	var pos = 0
	while pos <= n:
		st := self.search(pos)
		if st < 0: break
		e := self.endpos
		hits.append(Hit(st, e, self.cs.clone(), self.ce.clone()))
		pos = if e > st: e else: e + 1
	return hits

fn eq_str(f: List[Int], s: String) Bool:
	b := s.to_bytes()
	if b.length() != f.length(): return false
	for i in 0..f.length():
		if b.get(i).to_int() != f[i]: return false
	return true

fn split_tabs(line: List[Int]) List[List[Int]]:
	var out = List[List[Int]]()
	var cur = List[Int]()
	for b in line:
		if b == 9:
			out.append(cur)
			cur = List[Int]()
		else:
			cur.append(b)
	out.append(cur)
	return out

fn group_label(re: Re, g: Int) String:
	nm := re.names[g]
	if nm == "": return "{g}"
	return "{g} ({nm})"

fn describe(re: Re, h: Hit, subj: List[Int]) String:
	var out = ""
	for g in 0..(re.ngroups + 1):
		if g > 0: out += "\n"
		if h.cs[g] < 0 and g > 0:
			out += "{group_label(re, g)}: unset"
		else:
			a := if g == 0: h.st else: h.cs[g]
			b := if g == 0: h.en else: h.ce[g]
			out += "{group_label(re, g)}: {a}..{b} {quoted(subj, a, b)}"
	return out

fn expand(re: Re, h: Hit, subj: List[Int], rep: List[Int], var out: List[Int]) Bool:
	// appends to out; false on bad replacement
	var i = 0
	n := rep.length()
	while i < n:
		c := rep[i]
		if c != 36 or i + 1 >= n:
			out.append(c)
			i += 1
			continue
		d := rep[i + 1]
		if d == 36:
			out.append(36)
			i += 2
		else if is_digit(d):
			g := d - 48
			if g > re.ngroups: return false
			if g == 0:
				for j in h.st..h.en:
					out.append(subj[j])
			else if h.cs[g] >= 0:
				for j in h.cs[g]..h.ce[g]:
					out.append(subj[j])
			i += 2
		else if d == 123:
			var j = i + 2
			while j < n and rep[j] != 125:
				j += 1
			if j >= n: return false
			nm := name_of(rep, i + 2, j)
			var found = -1
			if nm != "":
				for q in 1..re.names.length():
					if re.names[q] == nm: found = q
			if found < 0: return false
			if h.cs[found] >= 0:
				for t in h.cs[found]..h.ce[found]:
					out.append(subj[t])
			i = j + 1
		else:
			out.append(36)
			i += 1
	return true

fn process(line: List[Int]) String:
	fields := split_tabs(line)
	cmd := fields[0]
	var want = 3
	if eq_str(cmd, "replace"): want = 4
	else if not (eq_str(cmd, "test") or eq_str(cmd, "match") or eq_str(cmd, "full") or eq_str(cmd, "find-all") or eq_str(cmd, "split")): return "error: bad command"
	if fields.length() != want: return "error: bad command"
	subj_r := unescape(fields[2])
	if not subj_r.is_ok(): return "error: bad command"
	subj := subj_r.get(List[Int]())
	var rep = List[Int]()
	if want == 4:
		rr := unescape(fields[3])
		if not rr.is_ok(): return "error: bad command"
		rep = rr.get(List[Int]())
	cr := compile(fields[1])
	if not cr.is_ok(): return "error: {cr.err().message}"
	var re = cr.get(Re())
	re.s = subj.clone()
	n := subj.length()
	if eq_str(cmd, "test"):
		return if re.search(0) >= 0: "true" else: "false"
	if eq_str(cmd, "match") or eq_str(cmd, "full"):
		if eq_str(cmd, "full"):
			re.full = true
			if not re.try_at(0): return "no match"
			h := Hit(0, re.endpos, re.cs.clone(), re.ce.clone())
			return describe(re, h, subj)
		st := re.search(0)
		if st < 0: return "no match"
		h := Hit(st, re.endpos, re.cs.clone(), re.ce.clone())
		return describe(re, h, subj)
	hits := re.all_matches()
	if eq_str(cmd, "find-all"):
		var out = ""
		for h in hits:
			out += "{h.st}..{h.en} {quoted(subj, h.st, h.en)}\n"
		out += "({hits.length()} matches)"
		return out
	if eq_str(cmd, "split"):
		var out = ""
		var prev = 0
		var cnt = 0
		for h in hits:
			if h.en > h.st:
				out += quoted(subj, prev, h.st) + "\n"
				cnt += 1
				prev = h.en
		out += quoted(subj, prev, n) + "\n"
		cnt += 1
		out += "({cnt} pieces)"
		return out
	// replace
	var res = List[Int]()
	var prev = 0
	for h in hits:
		for j in prev..h.st:
			res.append(subj[j])
		if not expand(re, h, subj, rep, var res): return "error: bad replacement"
		prev = h.en
	for j in prev..n:
		res.append(subj[j])
	return quoted(res, 0, res.length())

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	var line = List[Int]()
	for i in 0..data.length():
		b := data.get(i).to_int()
		if b == 10:
			if line.length() > 0: print(process(line))
			line = List[Int]()
		else:
			line.append(b.to_int())
	if line.length() > 0: print(process(line))
