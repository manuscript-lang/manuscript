import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import values from "@std/bytes.ms"
import from_scalars from "@std/string.ms"

// node kinds
// 0 empty 1 char 2 any 3 class 4 seq 5 alt 6 group 7 repeat 8 bol 9 eol 10 wb 11 nwb 12 backref 13 look
type Node:
	kind: Int
	a: Int = 0
	b: Int = 0
	lo: Int = 0
	hi: Int = 0
	greedy: Bool = true
	kids: List[Int] = List[Int]()
	name: String = ""

type Re:
	pat: List[Int]
	pos: Int = 0
	nodes: List[Node] = List[Node]()
	classes: List[List[Bool]] = List[List[Bool]]()
	ngroups: Int = 0
	gnames: List[String] = [""]
	icase: Bool = false
	multi: Bool = false
	dotall: Bool = false
	full: Bool = false
	qlo: Int = 0
	qhi: Int = 0
	root: Int = 0
	ops: List[Int] = List[Int]()
	xs: List[Int] = List[Int]()
	ys: List[Int] = List[Int]()
	nregs: Int = 0

fn bad(msg: String) Error: Error(msg)

fn is_alnum(c: Int) Bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_word(c: Int) Bool:
	return is_alnum(c) or c == 95

fn lower(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	return c

fn hexval(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn shorthand_has(k: Int, b: Int) Bool:
	// k: ascii code of letter
	if k == 100: return b >= 48 and b <= 57
	if k == 68: return not (b >= 48 and b <= 57)
	if k == 119: return is_word(b)
	if k == 87: return not is_word(b)
	sp := b == 32 or (b >= 9 and b <= 13)
	if k == 115: return sp
	return not sp

fn is_shorthand_letter(c: Int) Bool:
	return c == 100 or c == 68 or c == 119 or c == 87 or c == 115 or c == 83

fn var Re.peek() Int:
	if self.pos < self.pat.length(): return self.pat.get(self.pos)
	return -1

fn var Re.peek_at(i: Int) Int:
	if i < self.pat.length(): return self.pat.get(i)
	return -1

fn var Re.newnode(kind: Int, a: Int = 0, b: Int = 0) Int:
	self.nodes.append(Node(kind: kind, a: a, b: b))
	return self.nodes.length() - 1

fn var Re.add_class(set: List[Bool]) Int:
	self.classes.append(set.clone())
	return self.classes.length() - 1

fn var Re.shorthand_node(k: Int) Int:
	var set = List[Bool]()
	for b in 0..256:
		set.append(shorthand_has(k, b))
	idx := self.add_class(set)
	return self.newnode(3, idx)

// parses \xHH starting at pos pointing at 'x'; returns byte
fn var Re.parse_hex() Int!:
	h1 := hexval(self.peek_at(self.pos + 1))
	h2 := hexval(self.peek_at(self.pos + 2))
	if h1 < 0 or h2 < 0: return error(bad("bad escape"))
	self.pos += 3
	return ok(h1 * 16 + h2)

fn var Re.parse_name() String?:
	// pos after '<' ; parses name up to '>' ; none if malformed
	var out = List[Int]()
	var i = self.pos
	while true:
		c := self.peek_at(i)
		if c == -1: return none
		if c == 62: break
		ok_char := is_alnum(c) or c == 95
		if not ok_char: return none
		if out.length() == 0 and c >= 48 and c <= 57: return none
		out.append(c)
		i += 1
	if out.length() == 0: return none
	self.pos = i + 1
	if s := from_scalars(out):
		return s
	return none

fn var Re.parse_escape() Int!:
	// pos at char after backslash
	c := self.peek()
	if c == -1: return error(bad("bad escape"))
	if is_shorthand_letter(c):
		self.pos += 1
		return ok(self.shorthand_node(c))
	if c == 110:
		self.pos += 1
		return ok(self.newnode(1, 10, 0))
	if c == 116:
		self.pos += 1
		return ok(self.newnode(1, 9, 0))
	if c == 114:
		self.pos += 1
		return ok(self.newnode(1, 13, 0))
	if c == 120:
		v := self.parse_hex()?
		return ok(self.newnode(1, v, if self.icase: 1 else: 0))
	if c == 98:
		self.pos += 1
		return ok(self.newnode(10))
	if c == 66:
		self.pos += 1
		return ok(self.newnode(11))
	if c >= 49 and c <= 57:
		self.pos += 1
		return ok(self.newnode(12, c - 48, if self.icase: 1 else: 0))
	if c == 107:
		if self.peek_at(self.pos + 1) != 60: return error(bad("bad escape"))
		self.pos += 2
		if name := self.parse_name():
			n := self.newnode(12, -1, if self.icase: 1 else: 0)
			self.nodes[n].name = name
			return ok(n)
		return error(bad("bad escape"))
	if is_alnum(c) or c >= 128: return error(bad("bad escape"))
	self.pos += 1
	return ok(self.newnode(1, c, if self.icase: 1 else: 0))

// returns byte >= 0, or -(letter) for shorthand
fn var Re.parse_class_item() Int!:
	c := self.peek()
	if c != 92:
		self.pos += 1
		return ok(c)
	self.pos += 1
	e := self.peek()
	if e == -1: return error(bad("bad escape"))
	if is_shorthand_letter(e):
		self.pos += 1
		return ok(-e)
	if e == 110:
		self.pos += 1
		return ok(10)
	if e == 116:
		self.pos += 1
		return ok(9)
	if e == 114:
		self.pos += 1
		return ok(13)
	if e == 120:
		return ok(self.parse_hex()?)
	if is_alnum(e) or e >= 128: return error(bad("bad escape"))
	self.pos += 1
	return ok(e)

fn var Re.parse_class() Int!:
	// pos after '['
	var neg = false
	if self.peek() == 94:
		neg = true
		self.pos += 1
	var set = List[Bool]()
	for _b in 0..256:
		set.append(false)
	var first = true
	var prev_range = false
	while true:
		c := self.peek()
		if c == -1: return error(bad("unterminated class"))
		if c == 93 and not first:
			self.pos += 1
			break
		first = false
		lit_dash := c == 45 and prev_range
		it := self.parse_class_item()?
		prev_range = false
		can_range := self.peek() == 45 and self.peek_at(self.pos + 1) != -1 and self.peek_at(self.pos + 1) != 93
		if it >= 0 and not lit_dash and can_range:
			self.pos += 1
			it2 := self.parse_class_item()?
			if it2 < 0: return error(bad("bad range"))
			if it2 < it: return error(bad("bad range"))
			for b in it..(it2 + 1):
				set[b] = true
			prev_range = true
		else if it < 0:
			if can_range:
				self.pos += 1
				_it2 := self.parse_class_item()?
				return error(bad("bad range"))
			for b in 0..256:
				if shorthand_has(-it, b): set[b] = true
		else:
			set[it] = true
	if self.icase:
		for b in 65..91:
			if set[b] or set[b + 32]:
				set[b] = true
				set[b + 32] = true
	if neg:
		for b in 0..256:
			set[b] = not set[b]
	return ok(self.newnode(3, self.add_class(set)))

// returns 0 none, 1 found (qlo/qhi set, pos advanced)
fn var Re.try_quant() Int!:
	c := self.peek()
	if c == 42:
		self.pos += 1
		self.qlo = 0
		self.qhi = -1
		return ok(1)
	if c == 43:
		self.pos += 1
		self.qlo = 1
		self.qhi = -1
		return ok(1)
	if c == 63:
		self.pos += 1
		self.qlo = 0
		self.qhi = 1
		return ok(1)
	if c != 123: return ok(0)
	var i = self.pos + 1
	var n = 0
	var nd = 0
	while self.peek_at(i) >= 48 and self.peek_at(i) <= 57:
		n = n * 10 + (self.peek_at(i) - 48)
		if n > 100000: n = 100000
		nd += 1
		i += 1
	if nd == 0: return ok(0)
	var m = n
	if self.peek_at(i) == 44:
		i += 1
		var md = 0
		var mm = 0
		while self.peek_at(i) >= 48 and self.peek_at(i) <= 57:
			mm = mm * 10 + (self.peek_at(i) - 48)
			if mm > 100000: mm = 100000
			md += 1
			i += 1
		m = if md == 0: -1 else: mm
	if self.peek_at(i) != 125: return ok(0)
	self.pos = i + 1
	self.qlo = n
	self.qhi = m
	return ok(1)

fn var Re.check_repeat() Unit!:
	if self.qlo > 1000 or self.qhi > 1000: return error(bad("bad repeat"))
	if self.qhi != -1 and self.qlo > self.qhi: return error(bad("bad repeat"))
	return ok(unit)

fn var Re.parse_group() Int!:
	// pos after '('
	if self.peek() != 63:
		self.ngroups += 1
		g := self.ngroups
		self.gnames.append("")
		body := self.parse_alt()?
		if self.peek() != 41: return error(bad("unmatched ("))
		self.pos += 1
		n := self.newnode(6, g)
		self.nodes[n].kids.append(body)
		return ok(n)
	self.pos += 1
	c := self.peek()
	if c == 58:
		self.pos += 1
		body := self.parse_alt()?
		if self.peek() != 41: return error(bad("unmatched ("))
		self.pos += 1
		return ok(body)
	if c == 61 or c == 33:
		self.pos += 1
		body := self.parse_alt()?
		if self.peek() != 41: return error(bad("unmatched ("))
		self.pos += 1
		n := self.newnode(13, if c == 33: 1 else: 0)
		self.nodes[n].kids.append(body)
		return ok(n)
	if c == 60:
		self.pos += 1
		name := self.parse_name()
		if nm := name:
			if self.gnames.contains(nm): return error(bad("duplicate group name"))
			self.ngroups += 1
			g := self.ngroups
			self.gnames.append(nm)
			body := self.parse_alt()?
			if self.peek() != 41: return error(bad("unmatched ("))
			self.pos += 1
			n := self.newnode(6, g)
			self.nodes[n].kids.append(body)
			return ok(n)
		return error(bad("bad group"))
	return error(bad("bad group"))

fn var Re.parse_seq() Int!:
	var items = List[Int]()
	while true:
		c := self.peek()
		if c == -1 or c == 124 or c == 41: break
		var quantifiable = true
		var atom = 0
		self.pos += 1
		if c == 40:
			atom = self.parse_group()?
			if self.nodes[atom].kind == 13: quantifiable = false
		else if c == 91:
			atom = self.parse_class()?
		else if c == 46:
			atom = self.newnode(2, if self.dotall: 1 else: 0)
		else if c == 94:
			atom = self.newnode(8, if self.multi: 1 else: 0)
			quantifiable = false
		else if c == 36:
			atom = self.newnode(9, if self.multi: 1 else: 0)
			quantifiable = false
		else if c == 92:
			atom = self.parse_escape()?
			k := self.nodes[atom].kind
			if k == 10 or k == 11: quantifiable = false
		else if c == 42 or c == 43 or c == 63:
			return error(bad("nothing to repeat"))
		else:
			atom = self.newnode(1, c, if self.icase: 1 else: 0)
		q := self.try_quant()?
		if q == 1:
			if not quantifiable: return error(bad("nothing to repeat"))
			self.check_repeat()?
			lo := self.qlo
			hi := self.qhi
			var greedy = true
			if self.peek() == 63:
				self.pos += 1
				greedy = false
			q2 := self.try_quant()?
			if q2 == 1: return error(bad("nothing to repeat"))
			r := self.newnode(7, atom, 0)
			self.nodes[r].lo = lo
			self.nodes[r].hi = hi
			self.nodes[r].greedy = greedy
			items.append(r)
		else:
			items.append(atom)
	if items.length() == 0: return ok(self.newnode(0))
	if items.length() == 1: return ok(items.get(0))
	n := self.newnode(4)
	self.nodes[n].kids = items
	return ok(n)

fn var Re.parse_alt() Int!:
	var alts = List[Int]()
	while true:
		s := self.parse_seq()?
		alts.append(s)
		if self.peek() == 124:
			self.pos += 1
		else:
			break
	if alts.length() == 1: return ok(alts.get(0))
	n := self.newnode(5)
	self.nodes[n].kids = alts
	return ok(n)

fn var Re.parse_top() Unit!:
	// flags
	if self.peek() == 40 and self.peek_at(1) == 63:
		var i = 2
		var fi = false
		var fm = false
		var fs = false
		while true:
			c := self.peek_at(i)
			if c == 105:
				fi = true
			else if c == 109:
				fm = true
			else if c == 115:
				fs = true
			else:
				break
			i += 1
		if i > 2 and self.peek_at(i) == 41:
			self.icase = fi
			self.multi = fm
			self.dotall = fs
			self.pos = i + 1
	self.root = self.parse_alt()?
	if self.pos < self.pat.length():
		return error(bad("unmatched )"))
	for n in self.nodes:
		if n.kind == 12:
			if n.a == -1:
				if not self.gnames.contains(n.name): return error(bad("bad backreference"))
			else if n.a > self.ngroups:
				return error(bad("bad backreference"))
	return ok(unit)

// ---------- compiler ----------
// ops: 0 char 1 chari 2 any 3 anynl 4 class 5 split 6 jmp 7 save 8 close 9 backref
// 10 bol 11 eol 12 wb 13 nwb 14 look 15 lookend 16 match 17 mark 18 check

fn var Re.emit(op: Int, x: Int = 0, y: Int = 0) Int:
	self.ops.append(op)
	self.xs.append(x)
	self.ys.append(y)
	return self.ops.length() - 1

fn var Re.newreg() Int:
	self.nregs += 1
	return self.nregs - 1

fn var Re.compile_node(ni: Int) Unit:
	kind := self.nodes[ni].kind
	a := self.nodes[ni].a
	b := self.nodes[ni].b
	if kind == 0: return
	if kind == 1:
		if b == 1 and is_alnum(a) and a > 57:
			self.emit(1, lower(a))
		else:
			self.emit(0, a)
		return
	if kind == 2:
		self.emit(if a == 1: 3 else: 2)
		return
	if kind == 3:
		self.emit(4, a)
		return
	if kind == 4:
		kids := self.nodes[ni].kids.clone()
		for k in kids:
			self.compile_node(k)
		return
	if kind == 5:
		kids := self.nodes[ni].kids.clone()
		var jumps = List[Int]()
		for i in 0..kids.length():
			if i < kids.length() - 1:
				sp := self.emit(5, 0, 0)
				self.xs[sp] = sp + 1
				self.compile_node(kids.get(i))
				jumps.append(self.emit(6))
				self.ys[sp] = self.ops.length()
			else:
				self.compile_node(kids.get(i))
		for j in jumps:
			self.xs[j] = self.ops.length()
		return
	if kind == 6:
		kid := self.nodes[ni].kids.get(0)
		self.emit(7, 2 * (self.ngroups + 1) + a)
		self.compile_node(kid)
		self.emit(8, a)
		return
	if kind == 7:
		self.compile_repeat(ni)
		return
	if kind == 8:
		self.emit(10, a)
		return
	if kind == 9:
		self.emit(11, a)
		return
	if kind == 10:
		self.emit(12)
		return
	if kind == 11:
		self.emit(13)
		return
	if kind == 12:
		var g = a
		if a == -1:
			g = self.gnames.index_of(self.nodes[ni].name).get(0)
		self.emit(9, g, b)
		return
	if kind == 13:
		kid := self.nodes[ni].kids.get(0)
		l := self.emit(14, a, 0)
		self.compile_node(kid)
		self.emit(15)
		self.ys[l] = self.ops.length()
		return

fn var Re.compile_repeat(ni: Int) Unit:
	kid := self.nodes[ni].a
	lo := self.nodes[ni].lo
	hi := self.nodes[ni].hi
	greedy := self.nodes[ni].greedy
	var checks = List[Int]()
	var splits = List[Int]()
	for i in 1..(lo + 1):
		if i == lo and hi != lo:
			r := self.newreg()
			self.emit(17, r)
			self.compile_node(kid)
			checks.append(self.emit(18, r, 0))
		else:
			self.compile_node(kid)
	if hi == -1:
		l := self.emit(5, 0, 0)
		r := self.newreg()
		self.emit(17, r)
		self.compile_node(kid)
		checks.append(self.emit(18, r, 0))
		self.emit(6, l)
		endp := self.ops.length()
		if greedy:
			self.xs[l] = l + 1
			self.ys[l] = endp
		else:
			self.xs[l] = endp
			self.ys[l] = l + 1
		for c in checks:
			self.ys[c] = endp
		return
	for _i in 0..(hi - lo):
		l := self.emit(5, 0, 0)
		splits.append(l)
		r := self.newreg()
		self.emit(17, r)
		self.compile_node(kid)
		checks.append(self.emit(18, r, 0))
	endp := self.ops.length()
	for l in splits:
		if greedy:
			self.xs[l] = l + 1
			self.ys[l] = endp
		else:
			self.xs[l] = endp
			self.ys[l] = l + 1
	for c in checks:
		self.ys[c] = endp

fn var Re.compile_all() Unit:
	// register layout: caps 0..2G+1, open-start G+1, then marks
	self.nregs = 3 * (self.ngroups + 1)
	self.compile_node(self.root)
	self.emit(16)

// ---------- matcher ----------
type State:
	s: List[Int]
	regs: List[Int] = List[Int]()
	spc: List[Int] = List[Int]()
	spos: List[Int] = List[Int]()
	stp: List[Int] = List[Int]()
	sp: Int = 0
	tidx: List[Int] = List[Int]()
	tval: List[Int] = List[Int]()
	tp: Int = 0
	endpos: Int = 0

fn var State.setreg(i: Int, v: Int) Unit:
	if self.tp < self.tidx.length():
		self.tidx[self.tp] = i
		self.tval[self.tp] = self.regs[i]
	else:
		self.tidx.append(i)
		self.tval.append(self.regs[i])
	self.tp += 1
	self.regs[i] = v

fn var State.undo(mark: Int) Unit:
	while self.tp > mark:
		self.tp -= 1
		self.regs[self.tidx[self.tp]] = self.tval[self.tp]

fn var State.push(pc: Int, pos: Int) Unit:
	if self.sp < self.spc.length():
		self.spc[self.sp] = pc
		self.spos[self.sp] = pos
		self.stp[self.sp] = self.tp
	else:
		self.spc.append(pc)
		self.spos.append(pos)
		self.stp.append(self.tp)
	self.sp += 1

fn run(re: Re, var st: State, start_pc: Int, start_pos: Int) Bool:
	base := st.sp
	tmark := st.tp
	n := st.s.length()
	var pc = start_pc
	var pos = start_pos
	while true:
		var fail = false
		op := re.ops[pc]
		x := re.xs[pc]
		if op == 0:
			if pos < n and st.s[pos] == x:
				pos += 1
				pc += 1
			else: fail = true
		else if op == 1:
			if pos < n and lower(st.s[pos]) == x:
				pos += 1
				pc += 1
			else: fail = true
		else if op == 2:
			if pos < n and st.s[pos] != 10:
				pos += 1
				pc += 1
			else: fail = true
		else if op == 3:
			if pos < n:
				pos += 1
				pc += 1
			else: fail = true
		else if op == 4:
			if pos < n and re.classes[x][st.s[pos]]:
				pos += 1
				pc += 1
			else: fail = true
		else if op == 5:
			st.push(re.ys[pc], pos)
			pc = x
		else if op == 6:
			pc = x
		else if op == 7:
			st.setreg(x, pos)
			pc += 1
		else if op == 8:
			tmp := 2 * (re.ngroups + 1) + x
			st.setreg(2 * x, st.regs[tmp])
			st.setreg(2 * x + 1, pos)
			st.setreg(tmp, -1)
			pc += 1
		else if op == 9:
			a := st.regs[2 * x]
			b := st.regs[2 * x + 1]
			if a < 0 or b < 0 or st.regs[2 * (re.ngroups + 1) + x] >= 0:
				fail = true
			else:
				ln := b - a
				if pos + ln > n:
					fail = true
				else:
					for i in 0..ln:
						c1 := st.s[a + i]
						c2 := st.s[pos + i]
						if re.ys[pc] == 1:
							if lower(c1) != lower(c2): fail = true
						else if c1 != c2: fail = true
					if not fail:
						pos += ln
						pc += 1
		else if op == 10:
			if pos == 0 or (x == 1 and st.s[pos - 1] == 10): pc += 1
			else: fail = true
		else if op == 11:
			if pos == n or (x == 1 and st.s[pos] == 10): pc += 1
			else: fail = true
		else if op == 12 or op == 13:
			w1 := pos > 0 and is_word(st.s[pos - 1])
			w2 := pos < n and is_word(st.s[pos])
			isb := w1 != w2
			if (op == 12) == isb: pc += 1
			else: fail = true
		else if op == 14:
			tm := st.tp
			r := run(re, var st, pc + 1, pos)
			if x == 1:
				if r:
					st.undo(tm)
					fail = true
				else: pc = re.ys[pc]
			else if r: pc = re.ys[pc]
			else: fail = true
		else if op == 15:
			st.sp = base
			return true
		else if op == 16:
			if re.full and pos != n: fail = true
			else:
				st.endpos = pos
				st.sp = base
				return true
		else if op == 17:
			st.setreg(x, pos)
			pc += 1
		else:
			if pos == st.regs[x]: pc = re.ys[pc]
			else: pc += 1
		if fail:
			if st.sp == base:
				st.undo(tmark)
				return false
			st.sp -= 1
			pc = st.spc[st.sp]
			pos = st.spos[st.sp]
			st.undo(st.stp[st.sp])
	return false

// returns caps list (2*(G+1)) or empty
fn search(re: Re, var st: State, from: Int) List[Int]:
	n := st.s.length()
	for i in 0..re.nregs:
		st.regs[i] = -1
	st.tp = 0
	st.sp = 0
	var start = from
	while start <= n:
		if run(re, var st, 0, start):
			var out = List[Int]()
			out.append(start)
			out.append(st.endpos)
			for i in 2..(2 * (re.ngroups + 1)):
				out.append(st.regs[i])
			return out
		if re.full: break
		start += 1
	return List[Int]()

fn new_state(re: Re, s: List[Int]) State:
	var st = State(s: s.clone())
	for _i in 0..re.nregs:
		st.regs.append(-1)
	return st

// ---------- output ----------
fn quoted(s: List[Int], a: Int, b: Int) String:
	var out = List[Int]()
	out.append(34)
	for i in a..b:
		c := s[i]
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
			hx := c.to_string_radix(16)
			if hx.length() == 1: out.append(48)
			for ch in hx.chars():
				out.append(ch.scalar_at(0))
		else:
			out.append(c)
	out.append(34)
	if r := from_scalars(out): return r
	return ""

fn group_label(re: Re, g: Int) String:
	if g > 0 and re.gnames.get(g) != "": return "{g} ({re.gnames.get(g)})"
	return "{g}"

fn unescape(s: List[Int]) List[Int]?:
	var out = List[Int]()
	var i = 0
	while i < s.length():
		c := s[i]
		if c != 92:
			out.append(c)
			i += 1
		else:
			if i + 1 >= s.length(): return none
			e := s[i + 1]
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
				h1 := hexval(if i + 2 < s.length(): s[i + 2] else: -1)
				h2 := hexval(if i + 3 < s.length(): s[i + 3] else: -1)
				if h1 < 0 or h2 < 0: return none
				out.append(h1 * 16 + h2)
				i += 4
			else: return none
	return out

fn expand(re: Re, rep: List[Int], s: List[Int], caps: List[Int], var out: List[Int]) Bool:
	var i = 0
	while i < rep.length():
		c := rep[i]
		if c != 36:
			out.append(c)
			i += 1
		else:
			nx := if i + 1 < rep.length(): rep[i + 1] else: -1
			if nx == 36:
				out.append(36)
				i += 2
			else if nx >= 48 and nx <= 57:
				g := nx - 48
				if g > re.ngroups: return false
				if caps[2 * g] >= 0:
					for k in caps[2 * g]..caps[2 * g + 1]:
						out.append(s[k])
				i += 2
			else if nx == 123:
				var j = i + 2
				var nm = List[Int]()
				while j < rep.length() and rep[j] != 125:
					nm.append(rep[j])
					j += 1
				if j >= rep.length(): return false
				name := from_scalars(nm)
				if nms := name:
					idx := re.gnames.index_of(nms)
					if g := idx:
						if g == 0: return false
						if caps[2 * g] >= 0:
							for k in caps[2 * g]..caps[2 * g + 1]:
								out.append(s[k])
					else: return false
				else: return false
				i = j + 1
			else:
				out.append(36)
				i += 1
	return true

fn find_all(re: Re, var st: State) List[List[Int]]:
	var res = List[List[Int]]()
	n := st.s.length()
	var pos = 0
	while pos <= n:
		m := search(re, var st, pos)
		if m.length() == 0: break
		s := m.get(0)
		e := m.get(1)
		res.append(m)
		if e > s: pos = e
		else: pos = e + 1
	return res

fn process(fields: List[List[Int]]) String:
	var name = ""
	if c := from_scalars(fields[0]):
		name = c
	var nf = 3
	if name == "replace": nf = 4
	else if name != "test" and name != "match" and name != "full" and name != "find-all" and name != "split":
		return "error: bad command"
	if fields.length() != nf: return "error: bad command"
	subj := unescape(fields[2]).get([])
	if unescape(fields[2]).is_none(): return "error: bad command"
	var rep = List[Int]()
	if nf == 4:
		r := unescape(fields[3])
		if rr := r:
			rep = rr
		else: return "error: bad command"
	var re = Re(pat: fields[1].clone())
	pr := re.parse_top()
	if _ok := pr:
		re.full = name == "full"
	else:
		return "error: {pr.err().message}"
	re.compile_all()
	var st = new_state(re, subj)
	if name == "test":
		m := search(re, var st, 0)
		return if m.length() > 0: "true" else: "false"
	if name == "match" or name == "full":
		m := search(re, var st, 0)
		if m.length() == 0: return "no match"
		var lines = List[String]()
		for g in 0..(re.ngroups + 1):
			if m[2 * g] < 0:
				lines.append("{group_label(re, g)}: unset")
			else:
				lines.append("{group_label(re, g)}: {m[2 * g]}..{m[2 * g + 1]} {quoted(subj, m[2 * g], m[2 * g + 1])}")
		return lines.join("\n")
	all := find_all(re, var st)
	if name == "find-all":
		var lines = List[String]()
		for m in all:
			lines.append("{m[0]}..{m[1]} {quoted(subj, m[0], m[1])}")
		lines.append("({all.length()} matches)")
		return lines.join("\n")
	if name == "split":
		var lines = List[String]()
		var last = 0
		for m in all:
			if m[1] > m[0]:
				lines.append(quoted(subj, last, m[0]))
				last = m[1]
		lines.append(quoted(subj, last, subj.length()))
		lines.append("({lines.length()} pieces)")
		return lines.join("\n")
	var out = List[Int]()
	var last = 0
	for m in all:
		for k in last..m[0]:
			out.append(subj[k])
		if not expand(re, rep, subj, m, var out): return "error: bad replacement"
		last = m[1]
	for k in last..subj.length():
		out.append(subj[k])
	return quoted(out, 0, out.length())

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin(), none)?
	bytes := values(data)
	var line = List[List[Int]]()
	var cur = List[Int]()
	var lines = List[List[List[Int]]]()
	for b in bytes:
		c := b.to_int()
		if c == 10:
			cur_f := cur.clone()
			line.append(cur_f)
			cur = List[Int]()
			lines.append(line.clone())
			line = List[List[Int]]()
		else if c == 9:
			line.append(cur.clone())
			cur = List[Int]()
		else:
			cur.append(c)
	if cur.length() > 0 or line.length() > 0:
		line.append(cur.clone())
		lines.append(line.clone())
	for l in lines:
		if l.length() == 1 and l.get(0).length() == 0: continue
		print(process(l))
