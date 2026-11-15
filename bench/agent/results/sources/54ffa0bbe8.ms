import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

PRINTABLE := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
HEX := "0123456789abcdef"

fn chr(b: Int) String:
	if b >= 32 and b <= 126: return PRINTABLE.chars().get(b - 32, "?")
	return "?"

fn tostr(xs: List[Int]) String:
	var out = ""
	for b in xs:
		out = out + chr(b)
	return out

fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_alpha(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
fn is_word(c: Int) Bool: is_digit(c) or is_alpha(c) or c == 95
fn is_alnum(c: Int) Bool: is_digit(c) or is_alpha(c)
fn lower(c: Int) Int: if c >= 65 and c <= 90: c + 32 else: c

fn hexval(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn shorthand(ch: Int, b: Int) Bool:
	if ch == 100: return is_digit(b)
	if ch == 68: return not is_digit(b)
	if ch == 119: return is_word(b)
	if ch == 87: return not is_word(b)
	space := b == 32 or (b >= 9 and b <= 13)
	if ch == 115: return space
	return not space

type Re:
	p: List[Int] = List[Int]()
	pos: Int = 0
	err: String = ""
	icase: Bool = false
	multi: Bool = false
	dotall: Bool = false
	ngroups: Int = 0
	gnames: List[String] = [""]
	nk: List[Int] = List[Int]()
	na: List[Int] = List[Int]()
	nb: List[Int] = List[Int]()
	nc: List[Int] = List[Int]()
	nd: List[Int] = List[Int]()
	kids: List[Int] = List[Int]()
	cls: List[Int] = List[Int]()
	pend_node: List[Int] = List[Int]()
	pend_name: List[String] = List[String]()
	quantifiable: Bool = true
	bn: Int = 0
	bm: Int = 0
	bend: Int = 0
	root: Int = 0
	// matching state
	s: List[Int] = List[Int]()
	slen: Int = 0
	caps: List[Int] = List[Int]()
	fk: List[Int] = List[Int]()
	fa: List[Int] = List[Int]()
	fb: List[Int] = List[Int]()
	fc: List[Int] = List[Int]()
	fnext: List[Int] = List[Int]()
	full: Bool = false
	endpos: Int = 0

fn var Re.node(kind: Int, a: Int, b: Int, c: Int, d: Int) Int:
	self.nk.append(kind)
	self.na.append(a)
	self.nb.append(b)
	self.nc.append(c)
	self.nd.append(d)
	return self.nk.length() - 1

fn var Re.fail(msg: String) Int:
	if self.err == "": self.err = msg
	return 0

fn Re.peek(off: Int) Int:
	var i = self.pos + off
	if i < self.p.length(): return self.p.get(i, -1)
	return -1

fn var Re.list_node(kind: Int, items: List[Int]) Int:
	start := self.kids.length()
	for x in items:
		self.kids.append(x)
	return self.node(kind, start, items.length(), 0, 0)

fn var Re.add_class(bits: List[Int]) Int:
	idx := self.cls.length() / 256
	for i in 0..256:
		self.cls.append(bits.get(i, 0))
	return self.node(2, idx, 0, 0, 0)

fn Re.is_quant_start(at: Int) Bool:
	c := self.p.get(at, -1)
	if c == 42 or c == 43 or c == 63: return true
	if c == 123: return self.brace_shape(at) >= 0
	return false

// returns end position after the closing brace, or -1 if not a quantifier shape. Does not mutate.
fn Re.brace_shape(at: Int) Int:
	var i = at + 1
	var digits = 0
	while self.p.get(i, -1) >= 48 and self.p.get(i, -1) <= 57:
		i += 1
		digits += 1
	if digits == 0: return -1
	c := self.p.get(i, -1)
	if c == 125: return i + 1
	if c != 44: return -1
	i += 1
	while self.p.get(i, -1) >= 48 and self.p.get(i, -1) <= 57:
		i += 1
	if self.p.get(i, -1) == 125: return i + 1
	return -1

fn var Re.parse_alt() Int:
	var alts = List[Int]()
	while true:
		a := self.parse_seq()
		if self.err != "": return 0
		alts.append(a)
		if self.peek(0) == 124:
			self.pos += 1
		else:
			break
	if alts.length() == 1: return alts.get(0, 0)
	return self.list_node(9, alts)

fn var Re.parse_seq() Int:
	var items = List[Int]()
	var first = true
	while self.pos < self.p.length():
		c := self.peek(0)
		if c == 124 or c == 41: break
		atom := self.parse_atom(first)
		if self.err != "": return 0
		first = false
		q := self.parse_quant(atom, self.quantifiable)
		if self.err != "": return 0
		items.append(q)
	return self.list_node(10, items)

fn var Re.parse_quant(atom: Int, quantifiable: Bool) Int:
	if not self.is_quant_start(self.pos): return atom
	if not quantifiable: return self.fail("nothing to repeat")
	c := self.peek(0)
	var mn = 0
	var mx = -1
	if c == 42:
		self.pos += 1
	else if c == 43:
		mn = 1
		self.pos += 1
	else if c == 63:
		mx = 1
		self.pos += 1
	else:
		e := self.brace_shape(self.pos)
		var i = self.pos + 1
		var n = 0
		while self.p.get(i, -1) >= 48 and self.p.get(i, -1) <= 57:
			if n < 100000: n = n * 10 + (self.p.get(i, 0) - 48)
			i += 1
		mn = n
		if self.p.get(i, -1) == 125:
			mx = n
		else:
			i += 1
			if self.p.get(i, -1) == 125:
				mx = -1
			else:
				var m = 0
				while self.p.get(i, -1) >= 48 and self.p.get(i, -1) <= 57:
					if m < 100000: m = m * 10 + (self.p.get(i, 0) - 48)
					i += 1
				mx = m
		self.pos = e
		if mn > 1000 or mx > 1000 or (mx >= 0 and mn > mx): return self.fail("bad repeat")
	var greedy = 1
	if self.peek(0) == 63:
		greedy = 0
		self.pos += 1
	if self.pos < self.p.length() and self.is_quant_start(self.pos): return self.fail("nothing to repeat")
	return self.node(11, atom, mn, mx, greedy)

fn var Re.parse_name() String:
	// pos at first name char; returns "" if malformed. Consumes through '>'.
	var out = ""
	c := self.peek(0)
	if not (is_alpha(c) or c == 95): return ""
	while is_word(self.peek(0)):
		out = out + chr(self.peek(0))
		self.pos += 1
	if self.peek(0) != 62: return ""
	self.pos += 1
	return out

fn var Re.parse_atom(first: Bool) Int:
	self.quantifiable = true
	c := self.peek(0)
	if c == 42 or c == 43 or c == 63: return self.fail("nothing to repeat")
	if c == 40: return self.parse_group()
	if c == 91:
		return self.parse_class()
	if c == 46:
		self.pos += 1
		return self.node(1, 0, 0, 0, 0)
	if c == 94:
		self.pos += 1
		self.quantifiable = false
		return self.node(3, 0, 0, 0, 0)
	if c == 36:
		self.pos += 1
		self.quantifiable = false
		return self.node(4, 0, 0, 0, 0)
	if c == 92: return self.parse_escape()
	self.pos += 1
	if self.icase: return self.node(0, lower(c), 0, 0, 0)
	return self.node(0, c, 0, 0, 0)

fn var Re.parse_group() Int:
	self.pos += 1
	var kind = 0
	var gidx = 0
	var neg = 0
	if self.peek(0) == 63:
		c := self.peek(1)
		if c == 58:
			self.pos += 2
		else if c == 61 or c == 33:
			kind = 2
			if c == 33: neg = 1
			self.pos += 2
		else if c == 60:
			self.pos += 2
			name := self.parse_name()
			if name == "": return self.fail("bad group")
			for g in self.gnames.clone():
				if g == name: return self.fail("duplicate group name")
			self.ngroups += 1
			gidx = self.ngroups
			self.gnames.append(name)
			kind = 1
		else:
			return self.fail("bad group")
	else:
		self.ngroups += 1
		gidx = self.ngroups
		self.gnames.append("")
		kind = 1
	body := self.parse_alt()
	if self.err != "": return 0
	if self.pos >= self.p.length(): return self.fail("unmatched (")
	self.pos += 1
	if kind == 1: return self.node(7, gidx, body, 0, 0)
	if kind == 2:
		self.quantifiable = false
		return self.node(13, body, neg, 0, 0)
	return body

fn var Re.parse_escape() Int:
	if self.pos + 1 >= self.p.length(): return self.fail("bad escape")
	e := self.peek(1)
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		self.pos += 2
		var bits = List[Int]()
		for b in 0..256:
			bits.append(if shorthand(e, b): 1 else: 0)
		return self.add_class(bits)
	if e == 110:
		self.pos += 2
		return self.node(0, 10, 0, 0, 0)
	if e == 116:
		self.pos += 2
		return self.node(0, 9, 0, 0, 0)
	if e == 114:
		self.pos += 2
		return self.node(0, 13, 0, 0, 0)
	if e == 120:
		h1 := hexval(self.peek(2))
		h2 := hexval(self.peek(3))
		if h1 < 0 or h2 < 0: return self.fail("bad escape")
		self.pos += 4
		v := h1 * 16 + h2
		if self.icase: return self.node(0, lower(v), 0, 0, 0)
		return self.node(0, v, 0, 0, 0)
	if e == 98:
		self.pos += 2
		self.quantifiable = false
		return self.node(5, 0, 0, 0, 0)
	if e == 66:
		self.pos += 2
		self.quantifiable = false
		return self.node(6, 0, 0, 0, 0)
	if e >= 49 and e <= 57:
		self.pos += 2
		var n = self.node(12, e - 48, 0, 0, 0)
		self.pend_node.append(n)
		self.pend_name.append("")
		return n
	if e == 107:
		if self.peek(2) != 60: return self.fail("bad escape")
		self.pos += 3
		name := self.parse_name()
		if name == "": return self.fail("bad escape")
		var n = self.node(12, 0, 0, 0, 0)
		self.pend_node.append(n)
		self.pend_name.append(name)
		return n
	if is_alnum(e) or e >= 128: return self.fail("bad escape")
	self.pos += 2
	if self.icase: return self.node(0, lower(e), 0, 0, 0)
	return self.node(0, e, 0, 0, 0)

// returns 0..255 for a byte, 256+ch for shorthand, -1 on error (err set)
fn var Re.class_member() Int:
	c := self.peek(0)
	if c != 92:
		self.pos += 1
		return c
	if self.pos + 1 >= self.p.length():
		self.fail("bad escape")
		return -1
	e := self.peek(1)
	if e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83:
		self.pos += 2
		return 256 + e
	if e == 110:
		self.pos += 2
		return 10
	if e == 116:
		self.pos += 2
		return 9
	if e == 114:
		self.pos += 2
		return 13
	if e == 120:
		h1 := hexval(self.peek(2))
		h2 := hexval(self.peek(3))
		if h1 < 0 or h2 < 0:
			self.fail("bad escape")
			return -1
		self.pos += 4
		return h1 * 16 + h2
	if is_alnum(e) or e >= 128:
		self.fail("bad escape")
		return -1
	self.pos += 2
	return e

fn var Re.parse_class() Int:
	self.pos += 1
	var bits = List[Int]()
	for i in 0..256:
		bits.append(0)
	var neg = false
	if self.peek(0) == 94:
		neg = true
		self.pos += 1
	var first = true
	var prev_range = false
	while true:
		if self.pos >= self.p.length(): return self.fail("unterminated class")
		c := self.peek(0)
		if c == 93 and not first:
			self.pos += 1
			break
		first = false
		lit_dash := c == 45 and prev_range
		m := self.class_member()
		if self.err != "": return 0
		if lit_dash:
			bits[45] = 1
			prev_range = false
			continue
		if self.peek(0) == 45 and self.pos + 1 < self.p.length() and self.peek(1) != 93:
			self.pos += 1
			m2 := self.class_member()
			if self.err != "": return 0
			if m >= 256 or m2 >= 256: return self.fail("bad range")
			if m2 < m: return self.fail("bad range")
			for b in m..(m2 + 1):
				bits[b] = 1
			prev_range = true
		else:
			if m >= 256:
				for b in 0..256:
					if shorthand(m - 256, b): bits[b] = 1
			else:
				bits[m] = 1
			prev_range = false
	if self.icase:
		for b in 65..91:
			if bits.get(b, 0) == 1 or bits.get(b + 32, 0) == 1:
				bits[b] = 1
				bits[b + 32] = 1
	if neg:
		for b in 0..256:
			bits[b] = 1 - bits.get(b, 0)
	return self.add_class(bits)

fn var Re.compile(pat: List[Int]) Unit:
	self.p = pat.clone()
	var n = self.p.length()
	if self.peek(0) == 40 and self.peek(1) == 63:
		var i = 2
		var im = false
		var mm = false
		var sm = false
		while self.p.get(i, -1) == 105 or self.p.get(i, -1) == 109 or self.p.get(i, -1) == 115:
			c := self.p.get(i, 0)
			if c == 105: im = true
			if c == 109: mm = true
			if c == 115: sm = true
			i += 1
		if i > 2 and self.p.get(i, -1) == 41:
			self.icase = im
			self.multi = mm
			self.dotall = sm
			self.pos = i + 1
	r := self.parse_alt()
	if self.err != "": return
	if self.pos < n:
		self.fail("unmatched )")
		return
	self.root = r
	for j in 0..self.pend_node.length():
		nd := self.pend_node.get(j, 0)
		name := self.pend_name.get(j, "")
		if name == "":
			if self.na.get(nd, 0) > self.ngroups:
				self.fail("bad backreference")
				return
		else:
			var found = -1
			for g in 0..self.gnames.length():
				if g > 0 and self.gnames.get(g, "") == name: found = g
			if found < 0:
				self.fail("bad backreference")
				return
			self.na[nd] = found

// ---------- matching ----------

fn var Re.frame(kind: Int, a: Int, b: Int, c: Int, next: Int) Int:
	self.fk.append(kind)
	self.fa.append(a)
	self.fb.append(b)
	self.fc.append(c)
	self.fnext.append(next)
	return self.fk.length() - 1

fn Re.isw(i: Int) Bool:
	if i < 0 or i >= self.slen: return false
	return is_word(self.s.get(i, 0))

fn var Re.run(k: Int, pos: Int) Bool:
	kind := self.fk.get(k, 0)
	next := self.fnext.get(k, 0)
	if kind == 0:
		if self.full and pos != self.slen: return false
		self.endpos = pos
		return true
	if kind == 1:
		return self.seq(self.fa.get(k, 0), self.fb.get(k, 0), pos, next)
	if kind == 2:
		g := self.fa.get(k, 0)
		old_s := self.caps.get(2 * g, -1)
		old_e := self.caps.get(2 * g + 1, -1)
		self.caps[2 * g] = self.fb.get(k, 0)
		self.caps[2 * g + 1] = pos
		if self.run(next, pos): return true
		self.caps[2 * g] = old_s
		self.caps[2 * g + 1] = old_e
		return false
	if kind == 3:
		node := self.fa.get(k, 0)
		count := self.fb.get(k, 0)
		if pos == self.fc.get(k, 0) and count >= self.nb.get(node, 0): return self.run(next, pos)
		return self.rep(node, count, pos, next)
	return true

fn var Re.seq(node: Int, i: Int, pos: Int, k: Int) Bool:
	var n = self.nb.get(node, 0)
	if n == 0: return self.run(k, pos)
	child := self.kids.get(self.na.get(node, 0) + i, 0)
	if i == n - 1: return self.m(child, pos, k)
	f := self.frame(1, node, i + 1, 0, k)
	return self.m(child, pos, f)

fn var Re.iter(node: Int, count: Int, pos: Int, k: Int) Bool:
	f := self.frame(3, node, count + 1, pos, k)
	return self.m(self.na.get(node, 0), pos, f)

fn var Re.rep(node: Int, count: Int, pos: Int, k: Int) Bool:
	mn := self.nb.get(node, 0)
	mx := self.nc.get(node, 0)
	if count < mn: return self.iter(node, count, pos, k)
	if mx >= 0 and count >= mx: return self.run(k, pos)
	if self.nd.get(node, 0) == 1:
		if self.iter(node, count, pos, k): return true
		return self.run(k, pos)
	if self.run(k, pos): return true
	return self.iter(node, count, pos, k)

fn var Re.m(node: Int, pos: Int, k: Int) Bool:
	kind := self.nk.get(node, 0)
	a := self.na.get(node, 0)
	if kind == 0:
		if pos >= self.slen: return false
		b := self.s.get(pos, 0)
		if self.icase:
			if lower(b) != a: return false
		else:
			if b != a: return false
		return self.run(k, pos + 1)
	if kind == 1:
		if pos >= self.slen: return false
		if not self.dotall and self.s.get(pos, 0) == 10: return false
		return self.run(k, pos + 1)
	if kind == 2:
		if pos >= self.slen: return false
		if self.cls.get(a * 256 + self.s.get(pos, 0), 0) != 1: return false
		return self.run(k, pos + 1)
	if kind == 3:
		if pos == 0 or (self.multi and self.s.get(pos - 1, 0) == 10): return self.run(k, pos)
		return false
	if kind == 4:
		if pos == self.slen or (self.multi and self.s.get(pos, 0) == 10): return self.run(k, pos)
		return false
	if kind == 5:
		if self.isw(pos - 1) != self.isw(pos): return self.run(k, pos)
		return false
	if kind == 6:
		if self.isw(pos - 1) == self.isw(pos): return self.run(k, pos)
		return false
	if kind == 7:
		f := self.frame(2, a, pos, 0, k)
		return self.m(self.nb.get(node, 0), pos, f)
	if kind == 9:
		cnt := self.nb.get(node, 0)
		for i in 0..cnt:
			if self.m(self.kids.get(a + i, 0), pos, k): return true
		return false
	if kind == 10: return self.seq(node, 0, pos, k)
	if kind == 11: return self.rep(node, 0, pos, k)
	if kind == 12:
		st := self.caps.get(2 * a, -1)
		en := self.caps.get(2 * a + 1, -1)
		if st < 0: return false
		ln := en - st
		if pos + ln > self.slen: return false
		for i in 0..ln:
			x := self.s.get(st + i, 0)
			y := self.s.get(pos + i, 0)
			if self.icase:
				if lower(x) != lower(y): return false
			else:
				if x != y: return false
		return self.run(k, pos + ln)
	// lookahead
	saved := self.caps.clone()
	f := self.frame(4, 0, 0, 0, 0)
	r := self.m(a, pos, f)
	if self.nb.get(node, 0) == 1:
		self.caps = saved
		if r: return false
		return self.run(k, pos)
	if not r: return false
	if self.run(k, pos): return true
	self.caps = saved
	return false

// try a match starting exactly at `start`
fn var Re.attempt(start: Int) Bool:
	self.caps = List[Int]()
	for i in 0..(2 * (self.ngroups + 1)):
		self.caps.append(-1)
	self.fk = List[Int]()
	self.fa = List[Int]()
	self.fb = List[Int]()
	self.fc = List[Int]()
	self.fnext = List[Int]()
	done := self.frame(0, 0, 0, 0, 0)
	if self.m(self.root, start, done):
		self.caps[0] = start
		self.caps[1] = self.endpos
		return true
	return false

fn var Re.search(from: Int) Bool:
	var st = from
	while st <= self.slen:
		if self.attempt(st): return true
		st += 1
	return false

// ---------- driver ----------

fn quoted(xs: List[Int]) String:
	var out = "\""
	hx := HEX.chars()
	for b in xs:
		if b == 92: out = out + "\\\\"
		else if b == 34: out = out + "\\\""
		else if b == 10: out = out + "\\n"
		else if b == 9: out = out + "\\t"
		else if b == 13: out = out + "\\r"
		else if b < 32 or b > 126: out = out + "\\x" + hx.get(b / 16, "0") + hx.get(b % 16, "0")
		else: out = out + chr(b)
	return out + "\""

fn sub(xs: List[Int], a: Int, b: Int) List[Int]:
	var out = List[Int]()
	for i in a..b:
		out.append(xs.get(i, 0))
	return out

fn unescape(xs: List[Int]) List[Int]?:
	var out = List[Int]()
	var i = 0
	var n = xs.length()
	while i < n:
		c := xs.get(i, 0)
		if c != 92:
			out.append(c)
			i += 1
			continue
		if i + 1 >= n: return none
		e := xs.get(i + 1, 0)
		if e == 110: out.append(10)
		else if e == 116: out.append(9)
		else if e == 92: out.append(92)
		else if e == 120:
			if i + 3 >= n: return none
			h1 := hexval(xs.get(i + 2, 0))
			h2 := hexval(xs.get(i + 3, 0))
			if h1 < 0 or h2 < 0: return none
			out.append(h1 * 16 + h2)
			i += 2
		else: return none
		i += 2
	return out

type Match:
	caps: List[Int]

fn find_all(var re: Re) List[Match]:
	var res = List[Match]()
	var pos = 0
	while pos <= re.slen:
		if not re.search(pos): break
		s := re.caps.get(0, 0)
		e := re.caps.get(1, 0)
		res.append(Match(re.caps.clone()))
		pos = if e > s: e else: e + 1
	return res

fn label(re: Re, g: Int) String:
	name := re.gnames.get(g, "")
	if name == "": return "{g}"
	return "{g} ({name})"

fn print_groups(re: Re, caps: List[Int], subject: List[Int]) Unit:
	for g in 0..(re.ngroups + 1):
		s := caps.get(2 * g, -1)
		e := caps.get(2 * g + 1, -1)
		if s < 0:
			print("{label(re, g)}: unset")
		else:
			print("{label(re, g)}: {s}..{e} {quoted(sub(subject, s, e))}")

// ms: allow_effect std.console.write
fn handle(fields: List[List[Int]]) Unit:
	cmd := tostr(fields.get(0, List[Int]()))
	need := if cmd == "replace": 4 else: 3
	known := cmd == "test" or cmd == "match" or cmd == "full" or cmd == "find-all" or cmd == "split" or cmd == "replace"
	if not known or fields.length() != need:
		print("error: bad command")
		return
	subject := unescape(fields.get(2, List[Int]()))
	if subject.is_none():
		print("error: bad command")
		return
	var repl = List[Int]()
	if cmd == "replace":
		r := unescape(fields.get(3, List[Int]()))
		if r.is_none():
			print("error: bad command")
			return
		repl = r.get(List[Int]())
	var re = Re()
	re.compile(fields.get(1, List[Int]()))
	if re.err != "":
		print("error: {re.err}")
		return
	subj := subject.get(List[Int]())
	re.s = subj.clone()
	re.slen = subj.length()
	if cmd == "test":
		print(if re.search(0): "true" else: "false")
		return
	if cmd == "match" or cmd == "full":
		re.full = cmd == "full"
		ok := if re.full: re.attempt(0) else: re.search(0)
		if not ok:
			print("no match")
			return
		print_groups(re, re.caps, subj)
		return
	ms := find_all(var re)
	if cmd == "find-all":
		for mt in ms:
			s := mt.caps.get(0, 0)
			e := mt.caps.get(1, 0)
			print("{s}..{e} {quoted(sub(subj, s, e))}")
		print("({ms.length()} matches)")
		return
	if cmd == "split":
		var last = 0
		var pieces = List[String]()
		for mt in ms:
			s := mt.caps.get(0, 0)
			e := mt.caps.get(1, 0)
			if e == s: continue
			pieces.append(quoted(sub(subj, last, s)))
			last = e
		pieces.append(quoted(sub(subj, last, subj.length())))
		for pc in pieces:
			print(pc)
		print("({pieces.length()} pieces)")
		return
	// replace
	var out = List[Int]()
	var last = 0
	for mt in ms:
		s := mt.caps.get(0, 0)
		e := mt.caps.get(1, 0)
		for i in last..s:
			out.append(subj.get(i, 0))
		last = e
		var i = 0
		var n = repl.length()
		while i < n:
			c := repl.get(i, 0)
			if c != 36:
				out.append(c)
				i += 1
				continue
			d := repl.get(i + 1, -1)
			var g = -1
			if d >= 48 and d <= 57:
				g = d - 48
				if g > re.ngroups:
					print("error: bad replacement")
					return
				i += 2
			else if d == 36:
				out.append(36)
				i += 2
				continue
			else if d == 123:
				var j = i + 2
				var name = ""
				while j < n and repl.get(j, 0) != 125:
					name = name + chr(repl.get(j, 0))
					j += 1
				if j >= n:
					print("error: bad replacement")
					return
				for gi in 1..(re.ngroups + 1):
					if re.gnames.get(gi, "") == name: g = gi
				if g < 0 or name == "":
					print("error: bad replacement")
					return
				i = j + 1
			else:
				out.append(36)
				i += 1
				continue
			cs := mt.caps.get(2 * g, -1)
			ce := mt.caps.get(2 * g + 1, -1)
			if cs >= 0:
				for x in cs..ce:
					out.append(subj.get(x, 0))
	for i in last..subj.length():
		out.append(subj.get(i, 0))
	print(quoted(out))

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	var line = List[Int]()
	var lines = List[List[Int]]()
	for i in 0..data.length():
		b := data.get(i).to_int()
		if b == 10:
			lines.append(line.clone())
			line = List[Int]()
		else:
			line.append(b)
	if line.length() > 0: lines.append(line.clone())
	for ln in lines:
		if ln.length() == 0: continue
		var fields = List[List[Int]]()
		var cur = List[Int]()
		for b in ln:
			if b == 9:
				fields.append(cur.clone())
				cur = List[Int]()
			else:
				cur.append(b)
		fields.append(cur.clone())
		handle(fields)
