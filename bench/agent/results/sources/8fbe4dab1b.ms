import stdout, stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder from "@std/bytes.ms"

fn hexv(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn is_word(c: Int) Bool:
	if c >= 48 and c <= 57: return true
	if c >= 65 and c <= 90: return true
	if c >= 97 and c <= 122: return true
	return c == 95

fn is_alnum(c: Int) Bool: is_word(c) and c != 95

fn bytes_str(xs: List[Int], a: Int, b: Int) String:
	var bb = BytesBuilder()
	for i in a..b:
		bb.append(xs[i].to_uint8().get(0))
	return bb.build().decode_utf8().get("")

fn put(var out: BytesBuilder, s: String) Unit:
	out.append_bytes(s.to_bytes())

fn hex2(c: Int) String:
	d := "0123456789abcdef"
	return d.slice(c / 16, c / 16 + 1).get("") + d.slice(c % 16, c % 16 + 1).get("")

fn put_quoted(var out: BytesBuilder, xs: List[Int], a: Int, b: Int) Unit:
	out.append(34)
	for i in a..b:
		c := xs[i]
		if c == 92: put(var out, "\\\\")
		else if c == 34: put(var out, "\\\"")
		else if c == 10: put(var out, "\\n")
		else if c == 9: put(var out, "\\t")
		else if c == 13: put(var out, "\\r")
		else if c < 32 or c > 126: put(var out, "\\x" + hex2(c))
		else: out.append(c.to_uint8().get(0))
	out.append(34)

type Re:
	pat: List[Int] = List[Int]()
	pos: Int = 0
	fi: Bool = false
	fm: Bool = false
	fs: Bool = false
	ngroups: Int = 0
	names: List[String] = List[String]()
	err: String = ""
	qmn: Int = 0
	qmx: Int = 0
	qend: Int = -1
	ak: List[Int] = List[Int]()
	aval: List[Int] = List[Int]()
	amin: List[Int] = List[Int]()
	amax: List[Int] = List[Int]()
	ag: List[Int] = List[Int]()
	akids: List[List[Int]] = List[List[Int]]()
	pend_ast: List[Int] = List[Int]()
	pend_num: List[Int] = List[Int]()
	pend_name: List[String] = List[String]()
	tables: List[Bool] = List[Bool]()
	nk: List[Int] = List[Int]()
	na: List[Int] = List[Int]()
	nb: List[Int] = List[Int]()
	nc: List[Int] = List[Int]()
	nd: List[Int] = List[Int]()
	nbody: List[Int] = List[Int]()
	nnext: List[Int] = List[Int]()
	nalts: List[List[Int]] = List[List[Int]]()
	nreps: Int = 0
	entry: Int = 0
	subj: List[Int] = List[Int]()
	slen: Int = 0
	cs: List[Int] = List[Int]()
	ce: List[Int] = List[Int]()
	ts: List[Int] = List[Int]()
	cnt: List[Int] = List[Int]()
	last: List[Int] = List[Int]()
	mend: Int = 0
	need_end: Bool = false

fn var Re.fail(msg: String) Int:
	if self.err == "": self.err = msg
	return 0

fn Re.peek() Int:
	if self.pos < self.pat.length(): return self.pat[self.pos]
	return -1

fn Re.peek_at(k: Int) Int:
	if self.pos + k < self.pat.length(): return self.pat[self.pos + k]
	return -1

fn var Re.mk(kind: Int, val: Int, kids: List[Int]) Int:
	self.ak.append(kind)
	self.aval.append(val)
	self.amin.append(0)
	self.amax.append(0)
	self.ag.append(1)
	self.akids.append(kids)
	return self.ak.length() - 1

fn var Re.new_table() Int:
	off := self.tables.length()
	for _i in 0..256:
		self.tables.append(false)
	return off

fn var Re.add_range(off: Int, lo: Int, hi: Int) Unit:
	for b in lo..(hi + 1):
		self.tables[off + b] = true

fn var Re.add_short(off: Int, ch: Int) Unit:
	lower := ch >= 97
	base := if lower: ch else: ch + 32
	for b in 0..256:
		m := if base == 100: (b >= 48 and b <= 57) else if base == 119: is_word(b) else: (b == 32 or (b >= 9 and b <= 13))
		if m == lower: self.tables[off + b] = true

fn var Re.fold_table(off: Int) Unit:
	for b in 65..91:
		if self.tables[off + b] or self.tables[off + b + 32]:
			self.tables[off + b] = true
			self.tables[off + b + 32] = true

fn var Re.lit(c: Int) Int:
	off := self.new_table()
	self.tables[off + c] = true
	if self.fi: self.fold_table(off)
	return self.mk(1, off, List[Int]())

fn var Re.read_name(start: Int) String:
	// name starting at pat[start]; returns "" if malformed; sets qend to position after '>'
	self.qend = -1
	c0 := if start < self.pat.length(): self.pat[start] else: -1
	if not (c0 == 95 or (c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122)): return ""
	var e = start
	while e < self.pat.length() and is_word(self.pat[e]):
		e += 1
	if e >= self.pat.length() or self.pat[e] != 62: return ""
	self.qend = e + 1
	return bytes_str(self.pat, start, e)

fn var Re.quant_shape() Unit:
	// at '{'; sets qend (-1 if not a quantifier shape), qmn, qmx
	self.qend = -1
	var p = self.pos + 1
	n := self.pat.length()
	var d1 = 0
	var v1 = 0
	while p < n and self.pat[p] >= 48 and self.pat[p] <= 57:
		v1 = (v1 * 10 + self.pat[p] - 48).min(100000)
		d1 += 1
		p += 1
	if d1 == 0 or p >= n: return
	if self.pat[p] == 125:
		self.qmn = v1
		self.qmx = v1
		self.qend = p + 1
		return
	if self.pat[p] != 44: return
	p += 1
	var d2 = 0
	var v2 = 0
	while p < n and self.pat[p] >= 48 and self.pat[p] <= 57:
		v2 = (v2 * 10 + self.pat[p] - 48).min(100000)
		d2 += 1
		p += 1
	if p >= n or self.pat[p] != 125: return
	self.qmn = v1
	self.qmx = if d2 == 0: -1 else: v2
	self.qend = p + 1

fn var Re.parse_class() Int:
	// pos at '['
	self.pos += 1
	off := self.new_table()
	neg := self.peek() == 94
	if neg: self.pos += 1
	var first = true
	var after_range = false
	while true:
		c := self.peek()
		if c == -1: return self.fail("unterminated class")
		if c == 93 and not first: break
		first = false
		// parse one item: kind 0 = byte, 1 = set
		var is_set = false
		var val = c
		self.pos += 1
		if c == 92:
			e := self.peek()
			if e == -1: return self.fail("bad escape")
			self.pos += 1
			if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
				is_set = true
				self.add_short(off, e)
			else if e == 110: val = 10
			else if e == 116: val = 9
			else if e == 114: val = 13
			else if e == 120:
				h1 := hexv(self.peek())
				h2 := hexv(self.peek_at(1))
				if h1 < 0 or h2 < 0: return self.fail("bad escape")
				self.pos += 2
				val = h1 * 16 + h2
			else if e < 128 and not is_alnum(e): val = e
			else: return self.fail("bad escape")
		// range?
		if self.peek() == 45 and self.peek_at(1) != 93 and self.peek_at(1) != -1 and not (val == 45 and after_range and not is_set):
			if is_set: return self.fail("bad range")
			self.pos += 1
			c2 := self.peek()
			var hi = c2
			self.pos += 1
			if c2 == 92:
				e := self.peek()
				if e == -1: return self.fail("bad escape")
				self.pos += 1
				if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83: return self.fail("bad range")
				else if e == 110: hi = 10
				else if e == 116: hi = 9
				else if e == 114: hi = 13
				else if e == 120:
					h1 := hexv(self.peek())
					h2 := hexv(self.peek_at(1))
					if h1 < 0 or h2 < 0: return self.fail("bad escape")
					self.pos += 2
					hi = h1 * 16 + h2
				else if e < 128 and not is_alnum(e): hi = e
				else: return self.fail("bad escape")
			if hi < val: return self.fail("bad range")
			self.add_range(off, val, hi)
			after_range = true
		else:
			if not is_set: self.tables[off + val] = true
			after_range = false
	self.pos += 1
	if self.fi: self.fold_table(off)
	if neg:
		for b in 0..256:
			self.tables[off + b] = not self.tables[off + b]
	return self.mk(1, off, List[Int]())

fn var Re.parse_escape() Int:
	// pos at backslash; returns (ast, prev kind) -- prev kind stored in qmn
	self.pos += 1
	e := self.peek()
	if e == -1: return self.fail("bad escape")
	self.pos += 1
	self.qmn = 1
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		off := self.new_table()
		self.add_short(off, e)
		return self.mk(1, off, List[Int]())
	if e == 110: return self.lit(10)
	if e == 116: return self.lit(9)
	if e == 114: return self.lit(13)
	if e == 120:
		h1 := hexv(self.peek())
		h2 := hexv(self.peek_at(1))
		if h1 < 0 or h2 < 0: return self.fail("bad escape")
		self.pos += 2
		return self.lit(h1 * 16 + h2)
	if e == 98:
		self.qmn = 2
		return self.mk(9, 0, List[Int]())
	if e == 66:
		self.qmn = 2
		return self.mk(10, 0, List[Int]())
	if e >= 49 and e <= 57:
		a := self.mk(11, 0, List[Int]())
		self.pend_ast.append(a)
		self.pend_num.append(e - 48)
		self.pend_name.append("")
		return a
	if e == 107:
		if self.peek() != 60: return self.fail("bad escape")
		name := self.read_name(self.pos + 1)
		if name == "": return self.fail("bad escape")
		self.pos = self.qend
		a := self.mk(11, 0, List[Int]())
		self.pend_ast.append(a)
		self.pend_num.append(0)
		self.pend_name.append(name)
		return a
	if e < 128 and not is_alnum(e): return self.lit(e)
	return self.fail("bad escape")

fn var Re.parse_group() Int:
	// pos at '('
	self.pos += 1
	var kind = 0
	var neg = 0
	var gidx = 0
	if self.peek() == 63:
		c := self.peek_at(1)
		if c == 58:
			self.pos += 2
		else if c == 61 or c == 33:
			self.pos += 2
			kind = 2
			neg = if c == 33: 1 else: 0
		else if c == 60:
			if self.peek_at(2) == 61 or self.peek_at(2) == 33: return self.fail("bad group")
			name := self.read_name(self.pos + 2)
			if name == "": return self.fail("bad group")
			for nm in self.names.clone():
				if nm == name: return self.fail("duplicate group name")
			self.pos = self.qend
			self.ngroups += 1
			gidx = self.ngroups
			self.names.append(name)
			kind = 1
		else: return self.fail("bad group")
	else:
		self.ngroups += 1
		gidx = self.ngroups
		self.names.append("")
		kind = 1
	body := self.parse_alt()
	if self.err != "": return 0
	if self.peek() != 41: return self.fail("unmatched (")
	self.pos += 1
	if kind == 1: return self.mk(4, gidx, [body])
	if kind == 2: return self.mk(12, neg, [body])
	return body

fn var Re.parse_seq() Int:
	var items = List[Int]()
	var prev = 0
	while true:
		c := self.peek()
		if c == -1 or c == 124 or c == 41: break
		var is_q = c == 42 or c == 43 or c == 63
		if c == 123 and prev != 0:
			self.quant_shape()
			is_q = self.qend >= 0
		if is_q:
			if prev != 1: return self.fail("nothing to repeat")
			var mn = 0
			var mx = -1
			if c == 42: self.pos += 1
			else if c == 43:
				mn = 1
				self.pos += 1
			else if c == 63:
				mx = 1
				self.pos += 1
			else:
				mn = self.qmn
				mx = self.qmx
				self.pos = self.qend
				if mn > 1000 or mx > 1000 or (mx >= 0 and mn > mx): return self.fail("bad repeat")
			var greedy = 1
			if self.peek() == 63:
				greedy = 0
				self.pos += 1
			li := items.length() - 1
			r := self.mk(6, 0, [items[li]])
			self.amin[r] = mn
			self.amax[r] = mx
			self.ag[r] = greedy
			items[li] = r
			prev = 3
			continue
		if c == 40:
			a := self.parse_group()
			if self.err != "": return 0
			items.append(a)
			prev = if self.ak[a] == 12: 2 else: 1
		else if c == 91:
			a := self.parse_class()
			if self.err != "": return 0
			items.append(a)
			prev = 1
		else if c == 46:
			self.pos += 1
			off := self.new_table()
			self.add_range(off, 0, 255)
			if not self.fs: self.tables[off + 10] = false
			items.append(self.mk(1, off, List[Int]()))
			prev = 1
		else if c == 94:
			self.pos += 1
			items.append(self.mk(7, 0, List[Int]()))
			prev = 2
		else if c == 36:
			self.pos += 1
			items.append(self.mk(8, 0, List[Int]()))
			prev = 2
		else if c == 92:
			a := self.parse_escape()
			if self.err != "": return 0
			items.append(a)
			prev = self.qmn
		else:
			self.pos += 1
			items.append(self.lit(c))
			prev = 1
	if items.length() == 1: return items[0]
	return self.mk(2, 0, items)

fn var Re.parse_alt() Int:
	var kids = List[Int]()
	while true:
		s := self.parse_seq()
		if self.err != "": return 0
		kids.append(s)
		if self.peek() == 124:
			self.pos += 1
			continue
		break
	if kids.length() == 1: return kids[0]
	return self.mk(3, 0, kids)

fn var Re.parse_all() Int:
	// flags
	if self.peek() == 40 and self.peek_at(1) == 63:
		var p = self.pos + 2
		var nf = 0
		var fi = false
		var fm = false
		var fs = false
		while p < self.pat.length() and (self.pat[p] == 105 or self.pat[p] == 109 or self.pat[p] == 115):
			if self.pat[p] == 105: fi = true
			else if self.pat[p] == 109: fm = true
			else: fs = true
			nf += 1
			p += 1
		if nf > 0 and p < self.pat.length() and self.pat[p] == 41:
			self.fi = fi
			self.fm = fm
			self.fs = fs
			self.pos = p + 1
	a := self.parse_alt()
	if self.err != "": return 0
	if self.pos < self.pat.length(): return self.fail("unmatched )")
	for j in 0..self.pend_ast.length():
		var g = self.pend_num[j]
		if self.pend_name[j] != "":
			g = 0
			for k in 0..self.names.length():
				if self.names[k] == self.pend_name[j]: g = k + 1
		if g < 1 or g > self.ngroups: return self.fail("bad backreference")
		self.aval[self.pend_ast[j]] = g
	return a

fn var Re.node(kind: Int, a: Int, b: Int, c: Int, d: Int, body: Int, next: Int) Int:
	self.nk.append(kind)
	self.na.append(a)
	self.nb.append(b)
	self.nc.append(c)
	self.nd.append(d)
	self.nbody.append(body)
	self.nnext.append(next)
	self.nalts.append(List[Int]())
	return self.nk.length() - 1

fn var Re.comp(a: Int, next: Int) Int:
	k := self.ak[a]
	if k == 1: return self.node(0, self.aval[a], 0, 0, 0, 0, next)
	if k == 2:
		var n = next
		var j = self.akids[a].length()
		while j > 0:
			j -= 1
			n = self.comp(self.akids[a][j], n)
		return n
	if k == 3:
		var starts = List[Int]()
		for j in 0..self.akids[a].length():
			starts.append(self.comp(self.akids[a][j], next))
		n := self.node(1, 0, 0, 0, 0, 0, next)
		self.nalts[n] = starts
		return n
	if k == 4:
		g := self.aval[a]
		ge := self.node(3, g, 0, 0, 0, 0, next)
		body := self.comp(self.akids[a][0], ge)
		return self.node(2, g, 0, 0, 0, 0, body)
	if k == 6:
		kid := self.akids[a][0]
		if self.ak[kid] == 1:
			return self.node(15, self.aval[kid], self.amin[a], self.amax[a], self.ag[a], 0, next)
		id := self.nreps
		self.nreps += 1
		ent := self.node(4, id, self.amin[a], self.amax[a], self.ag[a], 0, next)
		en := self.node(5, ent, 0, 0, 0, 0, 0)
		body := self.comp(kid, en)
		self.nbody[ent] = body
		return ent
	if k == 7: return self.node(6, 0, 0, 0, 0, 0, next)
	if k == 8: return self.node(7, 0, 0, 0, 0, 0, next)
	if k == 9: return self.node(8, 0, 0, 0, 0, 0, next)
	if k == 10: return self.node(9, 0, 0, 0, 0, 0, next)
	if k == 11: return self.node(10, self.aval[a], 0, 0, 0, 0, next)
	if k == 12:
		le := self.node(12, 0, 0, 0, 0, 0, 0)
		body := self.comp(self.akids[a][0], le)
		return self.node(11, self.aval[a], 0, 0, 0, body, next)
	return next

fn Re.wordat(i: Int) Bool:
	if i < 0 or i >= self.slen: return false
	return is_word(self.subj[i])

fn var Re.iter(n: Int, i: Int) Bool:
	id := self.na[n]
	ol := self.last[id]
	self.last[id] = i
	if self.run(self.nbody[n], i): return true
	self.last[id] = ol
	return false

fn var Re.loop(n: Int, i: Int) Bool:
	id := self.na[n]
	c := self.cnt[id]
	mx := self.nc[n]
	if c < self.nb[n]: return self.iter(n, i)
	if mx >= 0 and c >= mx: return self.run(self.nnext[n], i)
	if self.nd[n] == 1:
		if self.iter(n, i): return true
		return self.run(self.nnext[n], i)
	if self.run(self.nnext[n], i): return true
	return self.iter(n, i)

fn var Re.run(n: Int, i: Int) Bool:
	k := self.nk[n]
	if k == 0:
		if i < self.slen:
			if self.tables[self.na[n] + self.subj[i]]: return self.run(self.nnext[n], i + 1)
		return false
	if k == 13:
		if self.need_end and i != self.slen: return false
		self.mend = i
		return true
	if k == 15:
		off := self.na[n]
		mx := self.nc[n]
		var m = 0
		while i + m < self.slen and (mx < 0 or m < mx) and self.tables[off + self.subj[i + m]]:
			m += 1
		mn := self.nb[n]
		if m < mn: return false
		if self.nd[n] == 1:
			var j = m
			while j >= mn:
				if self.run(self.nnext[n], i + j): return true
				j -= 1
			return false
		var j = mn
		while j <= m:
			if self.run(self.nnext[n], i + j): return true
			j += 1
		return false
	if k == 1:
		for j in 0..self.nalts[n].length():
			if self.run(self.nalts[n][j], i): return true
		return false
	if k == 2:
		g := self.na[n]
		old := self.ts[g]
		self.ts[g] = i
		if self.run(self.nnext[n], i): return true
		self.ts[g] = old
		return false
	if k == 3:
		g := self.na[n]
		os := self.cs[g]
		oe := self.ce[g]
		ot := self.ts[g]
		self.cs[g] = ot
		self.ce[g] = i
		self.ts[g] = -1
		if self.run(self.nnext[n], i): return true
		self.cs[g] = os
		self.ce[g] = oe
		self.ts[g] = ot
		return false
	if k == 4:
		id := self.na[n]
		oc := self.cnt[id]
		ol := self.last[id]
		self.cnt[id] = 0
		self.last[id] = -1
		if self.loop(n, i): return true
		self.cnt[id] = oc
		self.last[id] = ol
		return false
	if k == 5:
		e := self.na[n]
		id := self.na[e]
		oc := self.cnt[id]
		self.cnt[id] = oc + 1
		var r = false
		if i == self.last[id] and oc + 1 >= self.nb[e]: r = self.run(self.nnext[e], i)
		else: r = self.loop(e, i)
		if r: return true
		self.cnt[id] = oc
		return false
	if k == 6:
		if i == 0 or (self.fm and self.subj[i - 1] == 10): return self.run(self.nnext[n], i)
		return false
	if k == 7:
		if i == self.slen or (self.fm and self.subj[i] == 10): return self.run(self.nnext[n], i)
		return false
	if k == 8 or k == 9:
		b := self.wordat(i - 1) != self.wordat(i)
		if b == (k == 8): return self.run(self.nnext[n], i)
		return false
	if k == 10:
		g := self.na[n]
		if self.cs[g] < 0 or self.ts[g] >= 0: return false
		s := self.cs[g]
		len := self.ce[g] - s
		if i + len > self.slen: return false
		for j in 0..len:
			var x = self.subj[s + j]
			var y = self.subj[i + j]
			if self.fi:
				if x >= 65 and x <= 90: x += 32
				if y >= 65 and y <= 90: y += 32
			if x != y: return false
		return self.run(self.nnext[n], i + len)
	if k == 11:
		scs := self.cs.clone()
		sce := self.ce.clone()
		r := self.run(self.nbody[n], i)
		if self.na[n] == 1:
			if r:
				self.cs = scs
				self.ce = sce
				return false
			return self.run(self.nnext[n], i)
		if not r: return false
		if self.run(self.nnext[n], i): return true
		self.cs = scs
		self.ce = sce
		return false
	if k == 12: return true
	return false

fn var Re.compile(p: List[Int]) Bool:
	self.pat = p
	a := self.parse_all()
	if self.err != "": return false
	acc := self.node(13, 0, 0, 0, 0, 0, 0)
	self.entry = self.comp(a, acc)
	for _r in 0..self.nreps:
		self.cnt.append(0)
		self.last.append(-1)
	return true

fn var Re.set_subject(s: List[Int]) Unit:
	self.subj = s
	self.slen = self.subj.length()

fn var Re.try_at(s: Int) Bool:
	self.cs = List[Int]()
	self.ce = List[Int]()
	self.ts = List[Int]()
	for _g in 0..(self.ngroups + 1):
		self.cs.append(-1)
		self.ce.append(-1)
		self.ts.append(-1)
	if self.run(self.entry, s):
		self.cs[0] = s
		self.ce[0] = self.mend
		return true
	return false

fn var Re.search(from: Int) Bool:
	for s in from..(self.slen + 1):
		if self.try_at(s): return true
	return false

fn unescape(xs: List[Int]) List[Int]?:
	var out = List[Int]()
	var i = 0
	while i < xs.length():
		c := xs[i]
		if c != 92:
			out.append(c)
			i += 1
			continue
		if i + 1 >= xs.length(): return none
		e := xs[i + 1]
		if e == 110: out.append(10)
		else if e == 116: out.append(9)
		else if e == 92: out.append(92)
		else if e == 120:
			if i + 3 >= xs.length(): return none
			h1 := hexv(xs[i + 2])
			h2 := hexv(xs[i + 3])
			if h1 < 0 or h2 < 0: return none
			out.append(h1 * 16 + h2)
			i += 2
		else: return none
		i += 2
	return out

fn split_tabs(xs: List[Int]) List[List[Int]]:
	var res = List[List[Int]]()
	var cur = List[Int]()
	for c in xs:
		if c == 9:
			res.append(cur)
			cur = List[Int]()
		else: cur.append(c)
	res.append(cur)
	return res

fn put_group_line(var out: BytesBuilder, re: Re, g: Int) Unit:
	label := if g > 0 and re.names[g - 1] != "": "{g} ({re.names[g - 1]})" else: "{g}"
	if re.cs[g] < 0:
		put(var out, "{label}: unset\n")
		return
	put(var out, "{label}: {re.cs[g]}..{re.ce[g]} ")
	put_quoted(var out, re.subj, re.cs[g], re.ce[g])
	put(var out, "\n")

fn find_all(var re: Re) List[Int]:
	// flat list: per match 2*(ngroups+1) ints
	var res = List[Int]()
	var pos = 0
	while pos <= re.slen:
		if not re.search(pos): break
		for g in 0..(re.ngroups + 1):
			res.append(re.cs[g])
			res.append(re.ce[g])
		if re.ce[0] > re.cs[0]: pos = re.ce[0]
		else: pos = re.ce[0] + 1
	return res

fn process(var out: BytesBuilder, line: List[Int]) Unit:
	fields := split_tabs(line)
	cmd := bytes_str(fields[0], 0, fields[0].length())
	nf := fields.length()
	ok := cmd == "test" or cmd == "match" or cmd == "full" or cmd == "find-all" or cmd == "split" or cmd == "replace"
	if not ok or (cmd == "replace" and nf != 4) or (cmd != "replace" and nf != 3):
		put(var out, "error: bad command\n")
		return
	subj := unescape(fields[2]).get(List[Int]())
	if unescape(fields[2]).is_none():
		put(var out, "error: bad command\n")
		return
	var repl = List[Int]()
	if cmd == "replace":
		r := unescape(fields[3])
		if r.is_none():
			put(var out, "error: bad command\n")
			return
		repl = r.get(List[Int]())
	var re = Re()
	if not re.compile(fields[1].clone()):
		put(var out, "error: {re.err}\n")
		return
	re.set_subject(subj)
	if cmd == "test":
		put(var out, if re.search(0): "true\n" else: "false\n")
		return
	if cmd == "match" or cmd == "full":
		var found = false
		if cmd == "full":
			re.need_end = true
			found = re.try_at(0)
		else: found = re.search(0)
		if not found:
			put(var out, "no match\n")
			return
		for g in 0..(re.ngroups + 1):
			put_group_line(var out, re, g)
		return
	ms := find_all(var re)
	w := 2 * (re.ngroups + 1)
	nm := ms.length() / w
	if cmd == "find-all":
		for m in 0..nm:
			put(var out, "{ms[m * w]}..{ms[m * w + 1]} ")
			put_quoted(var out, re.subj, ms[m * w], ms[m * w + 1])
			put(var out, "\n")
		put(var out, "({nm} matches)\n")
		return
	if cmd == "split":
		var prev = 0
		var np = 0
		for m in 0..nm:
			s := ms[m * w]
			e := ms[m * w + 1]
			if e == s: continue
			put_quoted(var out, re.subj, prev, s)
			put(var out, "\n")
			np += 1
			prev = e
		put_quoted(var out, re.subj, prev, re.slen)
		put(var out, "\n")
		put(var out, "({np + 1} pieces)\n")
		return
	// replace
	var prev = 0
	var rs = List[Int]()
	for m in 0..nm:
		s := ms[m * w]
		e := ms[m * w + 1]
		for j in prev..s:
			rs.append(re.subj[j])
		var i = 0
		while i < repl.length():
			c := repl[i]
			if c != 36 or i + 1 >= repl.length():
				rs.append(c)
				i += 1
				continue
			d := repl[i + 1]
			if d >= 48 and d <= 57:
				g := d - 48
				if g > re.ngroups:
					put(var out, "error: bad replacement\n")
					return
				if ms[m * w + 2 * g] >= 0:
					for j in ms[m * w + 2 * g]..ms[m * w + 2 * g + 1]:
						rs.append(re.subj[j])
				i += 2
			else if d == 36:
				rs.append(36)
				i += 2
			else if d == 123:
				var q = i + 2
				while q < repl.length() and repl[q] != 125:
					q += 1
				if q >= repl.length():
					put(var out, "error: bad replacement\n")
					return
				name := bytes_str(repl, i + 2, q)
				var g = -1
				for k in 0..re.names.length():
					if name != "" and re.names[k] == name: g = k + 1
				if g < 0:
					put(var out, "error: bad replacement\n")
					return
				if ms[m * w + 2 * g] >= 0:
					for j in ms[m * w + 2 * g]..ms[m * w + 2 * g + 1]:
						rs.append(re.subj[j])
				i = q + 1
			else:
				rs.append(36)
				i += 1
		prev = e
	for j in prev..re.slen:
		rs.append(re.subj[j])
	put_quoted(var out, rs, 0, rs.length())
	put(var out, "\n")

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin(), none)?
	xs := data.values()
	var out = BytesBuilder()
	var cur = List[Int]()
	for b in xs:
		c := b.to_int()
		if c == 10:
			if cur.length() > 0: process(var out, cur)
			cur = List[Int]()
		else: cur.append(c)
	if cur.length() > 0: process(var out, cur)
	text := out.build().decode_utf8().get("")
	var so = stdout()
	so.write(text)?
