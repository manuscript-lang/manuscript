import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type P:
	pat: List[Int]
	pos: Int = 0
	nk: List[Int]
	na: List[Int]
	nb: List[Int]
	nc: List[Int]
	kids: List[List[Int]]
	sets: List[List[Bool]]
	names: List[String]
	gnames: List[String]
	ngroups: Int = 0
	icase: Bool = false
	multi: Bool = false
	dotall: Bool = false
	quant_ok: Bool = true
	item_set: List[Bool]

fn is_alnum(c: Int) Bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn is_namestart(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_wordb(c: Int) Bool:
	return is_alnum(c) or c == 95

fn hexval(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 65 and c <= 70: return c - 55
	if c >= 97 and c <= 102: return c - 87
	return -1

fn lower(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	return c

fn empty_set() List[Bool]:
	var s = List[Bool](reserve: 256)
	for _i in 0..256:
		s.append(false)
	return s

fn short_set(ch: Int) List[Bool]:
	// ch is one of d D w W s S
	base := lower(ch)
	var s = empty_set()
	for i in 0..256:
		var v = false
		if base == 100: v = is_digit(i)
		else if base == 119: v = is_wordb(i)
		else: v = i == 32 or (i >= 9 and i <= 13)
		if ch < 97: v = not v
		s.replace(i, v)
	return s

fn P.cur() Int:
	if self.pos < self.pat.length(): return self.pat[self.pos]
	return -1

fn P.at(i: Int) Int:
	if i < self.pat.length(): return self.pat[i]
	return -1

fn var P.add(kind: Int, a: Int, b: Int, c: Int, kids: List[Int], set: List[Bool], name: String) Int:
	self.nk.append(kind)
	self.na.append(a)
	self.nb.append(b)
	self.nc.append(c)
	self.kids.append(kids)
	self.sets.append(set)
	self.names.append(name)
	return self.nk.length() - 1

fn var P.simple(kind: Int, a: Int) Int:
	return self.add(kind, a, 0, 0, List[Int](), List[Bool](), "")

fn var P.lit(b: Int) Int:
	if self.icase and is_alnum(b) and not is_digit(b):
		var s = empty_set()
		s.replace(b, true)
		s.replace(lower(b), true)
		s.replace(lower(b) - 32, true)
		return self.add(3, 0, 0, 0, List[Int](), s, "")
	return self.simple(1, b)

fn var P.parse_name() String?:
	// pos after '<'; returns name and leaves pos after '>', or none
	var name = ""
	var p = self.pos
	if not is_namestart(self.at(p)): return none
	while p < self.pat.length() and is_wordb(self.pat[p]):
		name += chr(self.pat[p])
		p += 1
	if self.at(p) != 62: return none
	self.pos = p + 1
	return name

fn var P.parse_alt() Int!:
	var alts = List[Int]()
	while true:
		s := self.parse_seq()?
		alts.append(s)
		if self.cur() == 124:
			self.pos += 1
		else: break
	if alts.length() == 1: return ok(alts[0])
	return ok(self.add(5, 0, 0, 0, alts, List[Bool](), ""))

// try to read a brace quantifier at p; returns [min, max, newpos] or empty list
fn P.brace(p: Int) List[Int]:
	var i = p + 1
	var lo = 0
	var nd = 0
	while is_digit(self.at(i)):
		lo = lo * 10 + (self.at(i) - 48)
		if lo > 1001: lo = 1001
		nd += 1
		i += 1
	if nd == 0: return List[Int]()
	if self.at(i) == 125: return [lo, lo, i + 1]
	if self.at(i) != 44: return List[Int]()
	i += 1
	if self.at(i) == 125: return [lo, -1, i + 1]
	var hi = 0
	var nd2 = 0
	while is_digit(self.at(i)):
		hi = hi * 10 + (self.at(i) - 48)
		if hi > 1001: hi = 1001
		nd2 += 1
		i += 1
	if nd2 == 0 or self.at(i) != 125: return List[Int]()
	return [lo, hi, i + 1]

fn var P.parse_seq() Int!:
	var items = List[Int]()
	while true:
		c := self.cur()
		if c == -1 or c == 124 or c == 41: break
		self.quant_ok = true
		atom := self.parse_atom()?
		ok_q := self.quant_ok
		var node = atom
		// quantifier
		q := self.cur()
		var qmin = -1
		var qmax = -1
		var found = false
		if q == 42:
			qmin = 0
			qmax = -1
			found = true
			self.pos += 1
		else if q == 43:
			qmin = 1
			qmax = -1
			found = true
			self.pos += 1
		else if q == 63:
			qmin = 0
			qmax = 1
			found = true
			self.pos += 1
		else if q == 123:
			b := self.brace(self.pos)
			if b.length() == 3:
				qmin = b[0]
				qmax = b[1]
				if qmin > 1000 or qmax > 1000: return error(Error("bad repeat"))
				if qmax >= 0 and qmin > qmax: return error(Error("bad repeat"))
				found = true
				self.pos = b[2]
		if found:
			if not ok_q: return error(Error("nothing to repeat"))
			var greedy = 1
			if self.cur() == 63:
				greedy = 0
				self.pos += 1
			node = self.add(14, qmin, qmax, greedy, [atom], List[Bool](), "")
			n := self.cur()
			if n == 42 or n == 43 or n == 63: return error(Error("nothing to repeat"))
			if n == 123 and self.brace(self.pos).length() == 3: return error(Error("nothing to repeat"))
		items.append(node)
	if items.length() == 1: return ok(items[0])
	if items.is_empty(): return ok(self.simple(0, 0))
	return ok(self.add(4, 0, 0, 0, items, List[Bool](), ""))

fn var P.parse_atom() Int!:
	c := self.cur()
	if c == 40: return self.parse_group()
	if c == 91: return self.parse_class()
	if c == 46:
		self.pos += 1
		return ok(self.simple(2, 0))
	if c == 94:
		self.pos += 1
		self.quant_ok = false
		return ok(self.simple(9, 0))
	if c == 36:
		self.pos += 1
		self.quant_ok = false
		return ok(self.simple(10, 0))
	if c == 92: return self.parse_escape()
	if c == 42 or c == 43 or c == 63: return error(Error("nothing to repeat"))
	self.pos += 1
	return ok(self.lit(c))

fn var P.parse_escape() Int!:
	e := self.at(self.pos + 1)
	if e == -1: return error(Error("bad escape"))
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		self.pos += 2
		return ok(self.add(3, 0, 0, 0, List[Int](), short_set(e), ""))
	if e == 110:
		self.pos += 2
		return ok(self.lit(10))
	if e == 116:
		self.pos += 2
		return ok(self.lit(9))
	if e == 114:
		self.pos += 2
		return ok(self.lit(13))
	if e == 120:
		h1 := hexval(self.at(self.pos + 2))
		h2 := hexval(self.at(self.pos + 3))
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.pos += 4
		return ok(self.lit(h1 * 16 + h2))
	if e == 98:
		self.pos += 2
		self.quant_ok = false
		return ok(self.simple(11, 0))
	if e == 66:
		self.pos += 2
		self.quant_ok = false
		return ok(self.simple(12, 0))
	if e >= 49 and e <= 57:
		self.pos += 2
		return ok(self.simple(13, e - 48))
	if e == 107:
		self.pos += 2
		if self.cur() != 60: return error(Error("bad escape"))
		self.pos += 1
		nm := self.parse_name()
		if name := nm:
			return ok(self.add(13, -1, 0, 0, List[Int](), List[Bool](), name))
		return error(Error("bad escape"))
	if is_alnum(e) or e >= 128: return error(Error("bad escape"))
	self.pos += 2
	return ok(self.lit(e))

fn var P.parse_group() Int!:
	self.pos += 1
	var kind = 0
	var gidx = 0
	if self.cur() == 63:
		c2 := self.at(self.pos + 1)
		if c2 == 58:
			self.pos += 2
			kind = 0
		else if c2 == 61 or c2 == 33:
			self.pos += 2
			kind = if c2 == 61: 1 else: 2
		else if c2 == 60:
			c3 := self.at(self.pos + 2)
			if c3 == 61 or c3 == 33: return error(Error("bad group"))
			self.pos += 2
			nm := self.parse_name()
			if name := nm:
				if self.gnames.contains(name): return error(Error("duplicate group name"))
				self.ngroups += 1
				gidx = self.ngroups
				self.gnames.append(name)
				kind = 3
			else:
				return error(Error("bad group"))
		else:
			return error(Error("bad group"))
	else:
		self.ngroups += 1
		gidx = self.ngroups
		self.gnames.append("")
		kind = 3
	body := self.parse_alt()?
	if self.cur() != 41: return error(Error("unmatched ("))
	self.pos += 1
	if kind == 0: return ok(body)
	if kind == 3: return ok(self.add(6, gidx, 0, 0, [body], List[Bool](), ""))
	self.quant_ok = false
	return ok(self.add(8, if kind == 1: 1 else: 0, 0, 0, [body], List[Bool](), ""))

// parses one class item; returns byte, or -1 when it is a shorthand (set in item_set)
fn var P.class_item() Int!:
	c := self.cur()
	if c != 92:
		self.pos += 1
		return ok(c)
	e := self.at(self.pos + 1)
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		self.pos += 2
		self.item_set = short_set(e)
		return ok(-1)
	if e == 110:
		self.pos += 2
		return ok(10)
	if e == 116:
		self.pos += 2
		return ok(9)
	if e == 114:
		self.pos += 2
		return ok(13)
	if e == 120:
		h1 := hexval(self.at(self.pos + 2))
		h2 := hexval(self.at(self.pos + 3))
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.pos += 4
		return ok(h1 * 16 + h2)
	if e == -1 or is_alnum(e) or e >= 128: return error(Error("bad escape"))
	self.pos += 2
	return ok(e)

fn var P.parse_class() Int!:
	self.pos += 1
	var neg = false
	if self.cur() == 94:
		neg = true
		self.pos += 1
	var set = empty_set()
	var first = true
	var after_range = false
	while true:
		c := self.cur()
		if c == -1: return error(Error("unterminated class"))
		if c == 93 and not first:
			self.pos += 1
			break
		first = false
		if after_range and c == 45:
			set.replace(45, true)
			self.pos += 1
			after_range = false
			continue
		after_range = false
		lo := self.class_item()?
		dash := self.cur() == 45 and self.at(self.pos + 1) != -1 and self.at(self.pos + 1) != 93
		if lo == -1:
			if dash: return error(Error("bad range"))
			for i in 0..256:
				if self.item_set[i]: set.replace(i, true)
			continue
		if dash:
			self.pos += 1
			hi := self.class_item()?
			if hi == -1 or hi < lo: return error(Error("bad range"))
			for i in lo..(hi + 1):
				set.replace(i, true)
			after_range = true
		else:
			set.replace(lo, true)
	if self.icase:
		for i in 65..91:
			if set[i] or set[i + 32]:
				set.replace(i, true)
				set.replace(i + 32, true)
	if neg:
		for i in 0..256:
			set.replace(i, not set[i])
	return ok(self.add(3, 0, 0, 0, List[Int](), set, ""))

// returns root node or error
fn var P.parse_all() Int!:
	// leading flags
	if self.at(0) == 40 and self.at(1) == 63:
		var i = 2
		var m = false
		var ic = false
		var da = false
		var cnt = 0
		while true:
			c := self.at(i)
			if c == 105: ic = true
			else if c == 109: m = true
			else if c == 115: da = true
			else: break
			cnt += 1
			i += 1
		if cnt > 0 and self.at(i) == 41:
			self.icase = ic
			self.multi = m
			self.dotall = da
			self.pos = i + 1
	root := self.parse_alt()?
	if self.pos < self.pat.length(): return error(Error("unmatched )"))
	for i in 0..self.nk.length():
		if self.nk[i] == 13:
			if self.na[i] == -1:
				if not self.gnames.contains(self.names[i]): return error(Error("bad backreference"))
			else if self.na[i] > self.ngroups: return error(Error("bad backreference"))
	return ok(root)

// ---------------- matcher ----------------

type M:
	nk: List[Int]
	na: List[Int]
	nb: List[Int]
	nc: List[Int]
	kids: List[List[Int]]
	sets: List[List[Bool]]
	subj: List[Int]
	caps: List[Int]
	fk: List[Int]
	fa: List[Int]
	fb: List[Int]
	fc: List[Int]
	fn_: List[Int]
	icase: Bool
	multi: Bool
	dotall: Bool
	need_end: Bool = false
	mend: Int = 0
	ms: Int = 0

fn var M.push(k: Int, a: Int, b: Int, c: Int, nx: Int) Int:
	self.fk.append(k)
	self.fa.append(a)
	self.fb.append(b)
	self.fc.append(c)
	self.fn_.append(nx)
	return self.fk.length() - 1

fn var M.trunc(n: Int) Unit:
	while self.fk.length() > n:
		self.fk.pop()
		self.fa.pop()
		self.fb.pop()
		self.fc.pop()
		self.fn_.pop()

fn M.single(node: Int, pos: Int) Bool:
	if pos >= self.subj.length(): return false
	kind := self.nk[node]
	b := self.subj[pos]
	if kind == 1: return b == self.na[node]
	if kind == 2: return self.dotall or b != 10
	return self.sets[node][b]

fn var M.m(node: Int, pos: Int, k: Int) Bool:
	kind := self.nk[node]
	n := self.subj.length()
	if kind == 0: return self.run(k, pos)
	if kind <= 3:
		if self.single(node, pos): return self.run(k, pos + 1)
		return false
	if kind == 4:
		cnt := self.kids[node].length()
		first := self.kids[node][0]
		if cnt == 1: return self.m(first, pos, k)
		mark := self.fk.length()
		fr := self.push(1, node, 1, 0, k)
		if self.m(first, pos, fr): return true
		self.trunc(mark)
		return false
	if kind == 5:
		cnt := self.kids[node].length()
		for i in 0..cnt:
			if self.m(self.kids[node][i], pos, k): return true
		return false
	if kind == 6:
		mark := self.fk.length()
		fr := self.push(3, self.na[node], pos, 0, k)
		if self.m(self.kids[node][0], pos, fr): return true
		self.trunc(mark)
		return false
	if kind == 8:
		saved := self.caps.clone()
		body := self.kids[node][0]
		r := self.m(body, pos, 1)
		if self.na[node] == 1:
			if not r: return false
			if self.run(k, pos): return true
			self.caps = saved
			return false
		self.caps = saved
		if r: return false
		return self.run(k, pos)
	if kind == 9:
		if pos == 0 or (self.multi and self.subj[pos - 1] == 10): return self.run(k, pos)
		return false
	if kind == 10:
		if pos == n or (self.multi and self.subj[pos] == 10): return self.run(k, pos)
		return false
	if kind == 11 or kind == 12:
		a := pos > 0 and is_wordb(self.subj[pos - 1])
		b := pos < n and is_wordb(self.subj[pos])
		isb := a != b
		if (kind == 11) == isb: return self.run(k, pos)
		return false
	if kind == 13:
		var g = self.na[node]
		if g == -1: g = self.nb[node]
		s := self.caps[2 * g]
		e := self.caps[2 * g + 1]
		if s < 0: return false
		l := e - s
		if pos + l > n: return false
		for i in 0..l:
			x := self.subj[s + i]
			y := self.subj[pos + i]
			if x != y:
				if not self.icase or lower(x) != lower(y): return false
		return self.run(k, pos + l)
	// repeat
	body := self.kids[node][0]
	bk := self.nk[body]
	if bk <= 3:
		mn := self.na[node]
		mx := self.nb[node]
		var cnt = 0
		if self.nc[node] == 1:
			while (mx < 0 or cnt < mx) and self.single(body, pos + cnt):
				cnt += 1
			if cnt < mn: return false
			var j = cnt
			while j >= mn:
				if self.run(k, pos + j): return true
				j -= 1
			return false
		while cnt < mn:
			if not self.single(body, pos + cnt): return false
			cnt += 1
		while true:
			if self.run(k, pos + cnt): return true
			if mx >= 0 and cnt >= mx: return false
			if not self.single(body, pos + cnt): return false
			cnt += 1
		return false
	return self.step(node, 0, pos, k)

fn var M.step(rep: Int, count: Int, pos: Int, nx: Int) Bool:
	mn := self.na[rep]
	mx := self.nb[rep]
	if count < mn: return self.iter(rep, count, pos, nx)
	if mx >= 0 and count >= mx: return self.run(nx, pos)
	if self.nc[rep] == 1:
		if self.iter(rep, count, pos, nx): return true
		return self.run(nx, pos)
	if self.run(nx, pos): return true
	return self.iter(rep, count, pos, nx)

fn var M.iter(rep: Int, count: Int, pos: Int, nx: Int) Bool:
	mark := self.fk.length()
	fr := self.push(2, rep, count + 1, pos, nx)
	if self.m(self.kids[rep][0], pos, fr): return true
	self.trunc(mark)
	return false

fn var M.run(k: Int, pos: Int) Bool:
	kind := self.fk[k]
	if kind == 0:
		if self.need_end and pos != self.subj.length(): return false
		self.mend = pos
		return true
	if kind == 4: return true
	a := self.fa[k]
	b := self.fb[k]
	nx := self.fn_[k]
	if kind == 1:
		kid := self.kids[a][b]
		if b == self.kids[a].length() - 1: return self.m(kid, pos, nx)
		mark := self.fk.length()
		fr := self.push(1, a, b + 1, 0, nx)
		if self.m(kid, pos, fr): return true
		self.trunc(mark)
		return false
	if kind == 2:
		start := self.fc[k]
		if b > self.na[a] and pos == start: return self.run(nx, pos)
		return self.step(a, b, pos, nx)
	// group end
	os := self.caps[2 * a]
	oe := self.caps[2 * a + 1]
	self.caps.replace(2 * a, b)
	self.caps.replace(2 * a + 1, pos)
	if self.run(nx, pos): return true
	self.caps.replace(2 * a, os)
	self.caps.replace(2 * a + 1, oe)
	return false

fn var M.try_at(root: Int, start: Int) Bool:
	for i in 0..self.caps.length():
		self.caps.replace(i, -1)
	self.trunc(0)
	self.push(0, 0, 0, 0, -1)
	self.push(4, 0, 0, 0, -1)
	if self.m(root, start, 0):
		self.ms = start
		self.caps.replace(0, start)
		self.caps.replace(1, self.mend)
		return true
	return false

fn var M.search(root: Int, from: Int) Bool:
	n := self.subj.length()
	var s = from
	while s <= n:
		if self.try_at(root, s): return true
		s += 1
	return false

// ---------------- driver ----------------

fn table() List[String]:
	t := " !" + "\"" + "#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[" + "\\" + "]^_`abcdefghijklmnopqrstuvwxyz" + "\{" + "|" + "\}" + "~"
	return t.chars().clone()

fn chr(c: Int) String:
	if c < 32 or c > 126: return "?"
	return table()[c - 32]

fn bstr(b: List[Int]) String:
	var s = ""
	for c in b:
		s += chr(c)
	return s

fn hex2(c: Int) String:
	h := "0123456789abcdef".chars()
	return h[c / 16] + h[c % 16]

fn quoted(b: List[Int], s: Int, e: Int) String:
	var out = "\""
	for i in s..e:
		c := b[i]
		if c == 92: out += "\\\\"
		else if c == 34: out += "\\\""
		else if c == 10: out += "\\n"
		else if c == 9: out += "\\t"
		else if c == 13: out += "\\r"
		else if c < 32 or c > 126: out += "\\x" + hex2(c)
		else: out += chr(c)
	out += "\""
	return out

fn unescape(b: List[Int]) List[Int]?:
	var out = List[Int]()
	var i = 0
	n := b.length()
	while i < n:
		c := b[i]
		if c != 92:
			out.append(c)
			i += 1
			continue
		if i + 1 >= n: return none
		e := b[i + 1]
		if e == 110: out.append(10)
		else if e == 116: out.append(9)
		else if e == 92: out.append(92)
		else if e == 120:
			if i + 3 >= n: return none
			h1 := hexval(b[i + 2])
			h2 := hexval(b[i + 3])
			if h1 < 0 or h2 < 0: return none
			out.append(h1 * 16 + h2)
			i += 2
		else: return none
		i += 2
	return out

fn label(g: Int, names: List[String]) String:
	if g > 0 and names[g - 1] != "": return "{g} ({names[g - 1]})"
	return "{g}"

fn group_lines(m: M, names: List[String]) String:
	var out = ""
	for g in 0..(m.caps.length() / 2):
		s := m.caps[2 * g]
		if s < 0:
			out += "{label(g, names)}: unset\n"
		else:
			e := m.caps[2 * g + 1]
			out += "{label(g, names)}: {s}..{e} {quoted(m.subj, s, e)}\n"
	return out

fn append_cap(m: M, g: Int, out: List[Int]) List[Int]:
	var r = out.clone()
	s := m.caps[2 * g]
	if s >= 0:
		for i in s..m.caps[2 * g + 1]:
			r.append(m.subj[i])
	return r

// returns none on bad replacement
fn expand2(m: M, repl: List[Int], names: List[String], out: List[Int]) List[Int]?:
	var r = out.clone()
	var i = 0
	n := repl.length()
	ng := names.length()
	while i < n:
		c := repl[i]
		if c != 36:
			r.append(c)
			i += 1
			continue
		d := if i + 1 < n: repl[i + 1] else: -1
		if d == 36:
			r.append(36)
			i += 2
		else if is_digit(d):
			g := d - 48
			if g > ng: return none
			r = append_cap(m, g, r)
			i += 2
		else if d == 123:
			var j = i + 2
			while j < n and repl[j] != 125:
				j += 1
			if j >= n: return none
			var nb = List[Int]()
			for t in (i + 2)..j:
				nb.append(repl[t])
			nm := bstr(nb)
			idx := names.index_of(nm)
			if x := idx:
				if nm == "": return none
				r = append_cap(m, x + 1, r)
			else: return none
			i = j + 1
		else:
			r.append(36)
			i += 1
	return r

fn var M.all_matches(root: Int) List[List[Int]]:
	var res = List[List[Int]]()
	var pos = 0
	n := self.subj.length()
	while pos <= n:
		if not self.search(root, pos): break
		s := self.ms
		e := self.mend
		res.append([s, e])
		if e > s: pos = e
		else: pos = e + 1
	return res

fn process(line: List[Int]) String:
	var fields = List[List[Int]]()
	var cur = List[Int]()
	for c in line:
		if c == 9:
			fields.append(cur)
			cur = List[Int]()
		else: cur.append(c)
	fields.append(cur)
	cmd := bstr(fields[0])
	var want = 3
	if cmd == "replace": want = 4
	else if cmd != "test" and cmd != "match" and cmd != "full" and cmd != "find-all" and cmd != "split": return "error: bad command\n"
	if fields.length() != want: return "error: bad command\n"
	subj_o := unescape(fields[2])
	var subj = List[Int]()
	if x := subj_o: subj = x
	else: return "error: bad command\n"
	var repl = List[Int]()
	if cmd == "replace":
		ro := unescape(fields[3])
		if x := ro: repl = x
		else: return "error: bad command\n"
	var p = P(pat: fields[1].clone(), nk: List[Int](), na: List[Int](), nb: List[Int](), nc: List[Int](), kids: List[List[Int]](), sets: List[List[Bool]](), names: List[String](), gnames: List[String](), item_set: List[Bool]())
	rr := p.parse_all()
	var root = 0
	if r := rr: root = r
	else: return "error: {rr.err().message}\n"
	var caps = List[Int]()
	for _i in 0..(2 * (p.ngroups + 1)):
		caps.append(-1)
	var m = M(nk: p.nk.clone(), na: p.na.clone(), nb: p.nb.clone(), nc: p.nc.clone(), kids: p.kids.clone(), sets: p.sets.clone(), subj: subj.clone(), caps: caps, fk: List[Int](), fa: List[Int](), fb: List[Int](), fc: List[Int](), fn_: List[Int](), icase: p.icase, multi: p.multi, dotall: p.dotall)
	if cmd == "test":
		if m.search(root, 0): return "true\n"
		return "false\n"
	if cmd == "match":
		if not m.search(root, 0): return "no match\n"
		return group_lines(m, p.gnames)
	if cmd == "full":
		m.need_end = true
		if not m.try_at(root, 0): return "no match\n"
		return group_lines(m, p.gnames)
	ms := m.all_matches(root)
	if cmd == "find-all":
		var out = ""
		for x in ms:
			out += "{x[0]}..{x[1]} {quoted(subj, x[0], x[1])}\n"
		out += "({ms.length()} matches)\n"
		return out
	if cmd == "split":
		var out = ""
		var prev = 0
		var cnt = 0
		for x in ms:
			if x[1] > x[0]:
				out += quoted(subj, prev, x[0]) + "\n"
				prev = x[1]
				cnt += 1
		out += quoted(subj, prev, subj.length()) + "\n"
		out += "({cnt + 1} pieces)\n"
		return out
	// replace
	var res = List[Int]()
	var prev = 0
	for x in ms:
		for i in prev..x[0]:
			res.append(subj[i])
		// recompute captures for this match
		m.search(root, x[0])
		er := expand2(m, repl, p.gnames, res)
		if y := er: res = y
		else: return "error: bad replacement\n"
		prev = x[1]
	for i in prev..subj.length():
		res.append(subj[i])
	return quoted(res, 0, res.length()) + "\n"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	bytes := data.values() | .map(fn x: x.to_int())
	var out = ""
	var line = List[Int]()
	for c in bytes:
		if c == 10:
			if not line.is_empty(): out += process(line)
			line = List[Int]()
		else: line.append(c)
	if not line.is_empty(): out += process(line)
	print(out, end: "")
