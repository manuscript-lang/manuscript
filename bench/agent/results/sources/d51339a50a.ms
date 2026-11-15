import values from "@std/bytes.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

ASCII := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
HEX := "0123456789abcdef"

fn chr(b: Int) String:
	if b < 32 or b > 126: return "\u{1}"
	return ASCII.slice(b - 32, b - 31).get("")

fn hexv(b: Int) Int:
	if b >= 48 and b <= 57: return b - 48
	if b >= 97 and b <= 102: return b - 87
	if b >= 65 and b <= 70: return b - 55
	return -1

fn bstr(xs: List[Int]) String:
	var s = ""
	for b in xs:
		s = s + chr(b)
	return s

type Node:
	kind: Int
	a: Int = 0
	b: Int = 0
	c: Int = 0
	kids: List[Int] = []

type Q:
	len: Int
	min: Int
	max: Int
	bad: Bool

type P:
	pat: List[Int]
	pos: Int = 0
	nodes: List[Node] = []
	ngroups: Int = 0
	gnames: List[String] = []
	refs: List[String] = []
	sets: List[Int] = []
	icase: Bool = false
	multi: Bool = false
	dotall: Bool = false
	code: List[Int] = []
	nloops: Int = 0

fn is_alnum(c: Int) Bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_letter(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_word(c: Int) Bool:
	return is_alnum(c) or c == 95

fn fold(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	return c

fn other_case(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	if c >= 97 and c <= 122: return c - 32
	return c

fn shorthand(c: Int) List[Int]:
	var s: List[Int] = []
	lower := fold(c)
	for i in 0..256:
		var m = false
		if lower == 100: m = i >= 48 and i <= 57
		else if lower == 119: m = is_word(i)
		else: m = i == 32 or (i >= 9 and i <= 13)
		if c < 97: m = not m
		s.append(if m: 1 else: 0)
	return s

fn var P.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var P.add_set(s: List[Int]) Int:
	idx := self.sets.length() / 256
	for v in s:
		self.sets.append(v)
	return self.add(Node(kind: 3, a: idx))

fn var P.lit(b: Int) Int:
	if self.icase and is_letter(b):
		var s: List[Int] = []
		for i in 0..256:
			s.append(if i == b or i == other_case(b): 1 else: 0)
		return self.add_set(s)
	return self.add(Node(kind: 1, a: b))

fn P.peek(off: Int) Int:
	i := self.pos + off
	if i < self.pat.length(): return self.pat.get(i, 0)
	return -1

// parses the byte after a backslash (self.pos at it) as a single byte escape
fn var P.esc_byte() Int!:
	c := self.peek(0)
	if c < 0: return error(Error("bad escape"))
	if c == 110:
		self.pos += 1
		return ok(10)
	if c == 116:
		self.pos += 1
		return ok(9)
	if c == 114:
		self.pos += 1
		return ok(13)
	if c == 120:
		h1 := hexv(self.peek(1))
		h2 := hexv(self.peek(2))
		if h1 < 0 or h2 < 0: return error(Error("bad escape"))
		self.pos += 3
		return ok(h1 * 16 + h2)
	if c < 128 and not is_alnum(c):
		self.pos += 1
		return ok(c)
	return error(Error("bad escape"))

fn is_short(c: Int) Bool:
	return c == 100 or c == 68 or c == 119 or c == 87 or c == 115 or c == 83

fn var P.parse_class() Int!:
	// self.pos just after '['
	var set: List[Int] = []
	for _i in 0..256:
		set.append(0)
	var neg = false
	if self.peek(0) == 94:
		neg = true
		self.pos += 1
	var first = true
	while true:
		c := self.peek(0)
		if c < 0: return error(Error("unterminated class"))
		if c == 93 and not first: 
			self.pos += 1
			break
		first = false
		// item
		var lo = -1
		var cls: List[Int] = []
		if c == 92:
			self.pos += 1
			e := self.peek(0)
			if e < 0: return error(Error("bad escape"))
			if is_short(e):
				cls = shorthand(e)
				self.pos += 1
			else:
				lo = self.esc_byte()?
		else:
			lo = c
			self.pos += 1
		// range?
		if self.peek(0) == 45 and self.peek(1) >= 0 and self.peek(1) != 93:
			self.pos += 1
			var hi = -1
			var hcls = false
			h := self.peek(0)
			if h == 92:
				self.pos += 1
				e := self.peek(0)
				if e < 0: return error(Error("bad escape"))
				if is_short(e):
					hcls = true
					self.pos += 1
				else:
					hi = self.esc_byte()?
			else:
				hi = h
				self.pos += 1
			if lo < 0 or hcls: return error(Error("bad range"))
			if hi < lo: return error(Error("bad range"))
			for i in lo..hi + 1:
				set[i] = 1
		else:
			if lo >= 0: set[lo] = 1
			else:
				for i in 0..256:
					if cls.get(i, 0) == 1: set[i] = 1
	if self.icase:
		for i in 0..256:
			if is_letter(i) and set.get(i, 0) == 1: set[other_case(i)] = 1
	if neg:
		for i in 0..256:
			set[i] = 1 - set.get(i, 0)
	return ok(self.add_set(set))

fn P.quant_at() Q:
	c := self.peek(0)
	if c == 42: return Q(len: 1, min: 0, max: -1, bad: false)
	if c == 43: return Q(len: 1, min: 1, max: -1, bad: false)
	if c == 63: return Q(len: 1, min: 0, max: 1, bad: false)
	if c != 123: return Q(len: 0, min: 0, max: 0, bad: false)
	var i = 1
	var n1 = 0
	var d1 = 0
	while self.peek(i) >= 48 and self.peek(i) <= 57:
		n1 = n1 * 10 + self.peek(i) - 48
		if n1 > 100000: n1 = 100000
		d1 += 1
		i += 1
	if d1 == 0: return Q(len: 0, min: 0, max: 0, bad: false)
	if self.peek(i) == 125:
		return Q(len: i + 1, min: n1, max: n1, bad: n1 > 1000)
	if self.peek(i) != 44: return Q(len: 0, min: 0, max: 0, bad: false)
	i += 1
	var n2 = 0
	var d2 = 0
	while self.peek(i) >= 48 and self.peek(i) <= 57:
		n2 = n2 * 10 + self.peek(i) - 48
		if n2 > 100000: n2 = 100000
		d2 += 1
		i += 1
	if self.peek(i) != 125: return Q(len: 0, min: 0, max: 0, bad: false)
	if d2 == 0: return Q(len: i + 1, min: n1, max: -1, bad: n1 > 1000)
	return Q(len: i + 1, min: n1, max: n2, bad: n1 > n2 or n1 > 1000 or n2 > 1000)

// reads a name [A-Za-z_][A-Za-z0-9_]* followed by '>' ; returns none if malformed
fn var P.read_name() String?:
	var name = ""
	c := self.peek(0)
	if not (is_letter(c) or c == 95): return none
	while is_word(self.peek(0)):
		name = name + chr(self.peek(0))
		self.pos += 1
	if self.peek(0) != 62: return none
	self.pos += 1
	return name

fn var P.parse_group(depth: Int) Int!:
	// self.pos just after '('
	var kind = 0 // 0 capture, 1 noncap, 2 pos look, 3 neg look
	var name = ""
	if self.peek(0) == 63:
		c := self.peek(1)
		if c == 58:
			kind = 1
			self.pos += 2
		else if c == 61:
			kind = 2
			self.pos += 2
		else if c == 33:
			kind = 3
			self.pos += 2
		else if c == 60:
			self.pos += 2
			n := self.read_name()
			if nm := n:
				name = nm
				if self.gnames.contains(name): return error(Error("duplicate group name"))
			else:
				return error(Error("bad group"))
		else:
			return error(Error("bad group"))
	var g = 0
	if kind == 0:
		self.ngroups += 1
		g = self.ngroups
		self.gnames.append(name)
	body := self.parse_alt(depth + 1)?
	if self.peek(0) < 0: return error(Error("unmatched ("))
	self.pos += 1
	if kind == 0: return ok(self.add(Node(kind: 9, a: g, kids: [body])))
	if kind == 1: return ok(body)
	return ok(self.add(Node(kind: 11, a: if kind == 3: 1 else: 0, kids: [body])))

fn var P.parse_atom(depth: Int) Int!:
	c := self.peek(0)
	if c == 40:
		self.pos += 1
		return self.parse_group(depth)
	if c == 91:
		self.pos += 1
		return self.parse_class()
	if c == 46:
		self.pos += 1
		return ok(self.add(Node(kind: 2, a: if self.dotall: 1 else: 0)))
	if c == 94:
		self.pos += 1
		return ok(self.add(Node(kind: 4, a: if self.multi: 1 else: 0)))
	if c == 36:
		self.pos += 1
		return ok(self.add(Node(kind: 5, a: if self.multi: 1 else: 0)))
	if c == 92:
		self.pos += 1
		e := self.peek(0)
		if e < 0: return error(Error("bad escape"))
		if is_short(e):
			self.pos += 1
			return ok(self.add_set(shorthand(e)))
		if e == 98:
			self.pos += 1
			return ok(self.add(Node(kind: 6)))
		if e == 66:
			self.pos += 1
			return ok(self.add(Node(kind: 7)))
		if e >= 49 and e <= 57:
			self.pos += 1
			return ok(self.add(Node(kind: 8, a: e - 48, b: -1)))
		if e == 107:
			self.pos += 1
			if self.peek(0) != 60: return error(Error("bad escape"))
			self.pos += 1
			n := self.read_name()
			if nm := n:
				self.refs.append(nm)
				return ok(self.add(Node(kind: 8, a: 0, b: self.refs.length() - 1)))
			return error(Error("bad escape"))
		b := self.esc_byte()?
		return ok(self.lit(b))
	self.pos += 1
	return ok(self.lit(c))

fn var P.parse_seq(depth: Int) Int!:
	var items: List[Int] = []
	while true:
		c := self.peek(0)
		if c < 0 or c == 124 or c == 41: break
		if c == 42 or c == 43 or c == 63: return error(Error("nothing to repeat"))
		atom := self.parse_atom(depth)?
		kind := self.nodes[atom].kind
		q := self.quant_at()
		if q.len > 0:
			if kind == 4 or kind == 5 or kind == 6 or kind == 7 or kind == 11:
				return error(Error("nothing to repeat"))
			if q.bad: return error(Error("bad repeat"))
			self.pos += q.len
			var greedy = 1
			if self.peek(0) == 63:
				greedy = 0
				self.pos += 1
			q2 := self.quant_at()
			if q2.len > 0: return error(Error("nothing to repeat"))
			items.append(self.add(Node(kind: 14, a: q.min, b: q.max, c: greedy, kids: [atom])))
		else:
			items.append(atom)
	if items.length() == 1: return ok(items.get(0, 0))
	return ok(self.add(Node(kind: 12, kids: items)))

fn var P.parse_alt(depth: Int) Int!:
	var alts: List[Int] = []
	while true:
		s := self.parse_seq(depth)?
		alts.append(s)
		if self.peek(0) == 124:
			self.pos += 1
			continue
		break
	if alts.length() == 1: return ok(alts.get(0, 0))
	return ok(self.add(Node(kind: 13, kids: alts)))

// ---------------- code generation ----------------
// instruction: op a b c d e

fn var P.ins(op: Int, a: Int, b: Int, c: Int, d: Int, e: Int) Int:
	self.code.append(op)
	self.code.append(a)
	self.code.append(b)
	self.code.append(c)
	self.code.append(d)
	self.code.append(e)
	return self.code.length() / 6 - 1

fn var P.patch(at: Int, field: Int, v: Int) Void:
	self.code[at * 6 + field] = v

fn P.here() Int:
	return self.code.length() / 6

fn var P.emit(i: Int) Void!:
	kind := self.nodes[i].kind
	a := self.nodes[i].a
	b := self.nodes[i].b
	c := self.nodes[i].c
	kids := self.nodes[i].kids.clone()
	ng1 := self.ngroups + 1
	if kind == 1:
		_ := self.ins(1, a, 0, 0, 0, 0)
	else if kind == 2:
		_ := self.ins(2, a, 0, 0, 0, 0)
	else if kind == 3:
		_ := self.ins(3, a, 0, 0, 0, 0)
	else if kind == 4:
		_ := self.ins(4, a, 0, 0, 0, 0)
	else if kind == 5:
		_ := self.ins(5, a, 0, 0, 0, 0)
	else if kind == 6:
		_ := self.ins(6, 0, 0, 0, 0, 0)
	else if kind == 7:
		_ := self.ins(7, 0, 0, 0, 0, 0)
	else if kind == 8:
		var g = a
		if b >= 0:
			name := self.refs.get(b, "")
			idx := self.gnames.index_of(name)
			if x := idx:
				g = x + 1
			else:
				return error(Error("bad backreference"))
		if g < 1 or g > self.ngroups: return error(Error("bad backreference"))
		_ := self.ins(8, g, if self.icase: 1 else: 0, 0, 0, 0)
	else if kind == 9:
		_ := self.ins(9, 2 * ng1 + a, 0, 0, 0, 0)
		self.emit(kids.get(0, 0))?
		_ := self.ins(10, a, 2 * ng1 + a, 0, 0, 0)
	else if kind == 11:
		at := self.ins(11, a, 0, 0, 0, 0)
		self.emit(kids.get(0, 0))?
		_ := self.ins(12, 0, 0, 0, 0, 0)
		self.patch(at, 2, self.here())
	else if kind == 12:
		for k in kids:
			self.emit(k)?
	else if kind == 13:
		var jumps: List[Int] = []
		n := kids.length()
		for j in 0..n:
			if j < n - 1:
				sp := self.ins(18, 0, 0, 0, 0, 0)
				self.patch(sp, 1, self.here())
				self.emit(kids.get(j, 0))?
				jp := self.ins(17, 0, 0, 0, 0, 0)
				jumps.append(jp)
				self.patch(sp, 2, self.here())
			else:
				self.emit(kids.get(j, 0))?
		for jp in jumps:
			self.patch(jp, 1, self.here())
	else if kind == 14:
		reg := 3 * ng1 + 2 * self.nloops
		self.nloops += 1
		_ := self.ins(13, reg, 0, 0, 0, 0)
		h := self.ins(14, reg, a, b, c, 0)
		_ := self.ins(15, reg, 0, 0, 0, 0)
		self.emit(kids.get(0, 0))?
		_ := self.ins(16, reg, h, 0, 0, 0)
		self.patch(h, 5, self.here())

// ---------------- matcher ----------------

fn undo_to(var regs: List[Int], var stack: List[Int], base: Int) Void:
	while stack.length() > base:
		y := stack.pop().get(0)
		x := stack.pop().get(0)
		k := stack.pop().get(0)
		if k == 1: regs[x] = y

fn run(code: List[Int], sets: List[Int], subj: List[Int], var regs: List[Int], var stack: List[Int], pc0: Int, pos0: Int, base: Int) Int:
	var pc = pc0
	var pos = pos0
	n := subj.length()
	var failed = false
	while true:
		if failed:
			var found = false
			while stack.length() > base:
				y := stack.pop().get(0)
				x := stack.pop().get(0)
				k := stack.pop().get(0)
				if k == 1:
					regs[x] = y
				else:
					pc = x
					pos = y
					found = true
					break
			if not found: return -1
			failed = false
		i := pc * 6
		op := code.get(i, 0)
		a := code.get(i + 1, 0)
		b := code.get(i + 2, 0)
		if op == 1:
			if pos < n and subj.get(pos, 0) == a:
				pos += 1
				pc += 1
			else: failed = true
		else if op == 2:
			if pos < n and (a == 1 or subj.get(pos, 0) != 10):
				pos += 1
				pc += 1
			else: failed = true
		else if op == 3:
			if pos < n and sets.get(a * 256 + subj.get(pos, 0), 0) == 1:
				pos += 1
				pc += 1
			else: failed = true
		else if op == 4:
			if pos == 0 or (a == 1 and subj.get(pos - 1, 0) == 10): pc += 1
			else: failed = true
		else if op == 5:
			if pos == n or (a == 1 and subj.get(pos, 0) == 10): pc += 1
			else: failed = true
		else if op == 6 or op == 7:
			w1 := pos > 0 and is_word(subj.get(pos - 1, 0))
			w2 := pos < n and is_word(subj.get(pos, 0))
			isb := w1 != w2
			if isb == (op == 6): pc += 1
			else: failed = true
		else if op == 8:
			s := regs.get(2 * a, -1)
			e := regs.get(2 * a + 1, -1)
			if s < 0: failed = true
			else:
				l := e - s
				if pos + l > n: failed = true
				else:
					var same = true
					for j in 0..l:
						x := subj.get(s + j, 0)
						y := subj.get(pos + j, 0)
						if x != y and not (b == 1 and fold(x) == fold(y)):
							same = false
							break
					if same:
						pos += l
						pc += 1
					else: failed = true
		else if op == 9:
			stack.append(1)
			stack.append(a)
			stack.append(regs.get(a, -1))
			regs[a] = pos
			pc += 1
		else if op == 10:
			stack.append(1)
			stack.append(2 * a)
			stack.append(regs.get(2 * a, -1))
			stack.append(1)
			stack.append(2 * a + 1)
			stack.append(regs.get(2 * a + 1, -1))
			regs[2 * a] = regs.get(b, -1)
			regs[2 * a + 1] = pos
			pc += 1
		else if op == 11:
			nbase := stack.length()
			r := run(code, sets, subj, var regs, var stack, pc + 1, pos, nbase)
			if r >= 0:
				if a == 1:
					undo_to(var regs, var stack, nbase)
					failed = true
				else:
					var tmp: List[Int] = []
					while stack.length() > nbase:
						tmp.append(stack.pop().get(0))
					// tmp holds triples reversed (y, x, k) newest first
					var j = 0
					var keep: List[Int] = []
					while j < tmp.length():
						y := tmp.get(j, 0)
						x := tmp.get(j + 1, 0)
						k := tmp.get(j + 2, 0)
						if k == 1:
							keep.append(k)
							keep.append(x)
							keep.append(y)
						j += 3
					// keep is newest-first triples; push oldest first
					var m = keep.length() - 3
					while m >= 0:
						stack.append(keep.get(m, 0))
						stack.append(keep.get(m + 1, 0))
						stack.append(keep.get(m + 2, 0))
						m -= 3
					pc = code.get(i + 2, 0)
			else:
				if a == 1: pc = code.get(i + 2, 0)
				else: failed = true
		else if op == 12:
			return pos
		else if op == 13:
			stack.append(1)
			stack.append(a)
			stack.append(regs.get(a, 0))
			stack.append(1)
			stack.append(a + 1)
			stack.append(regs.get(a + 1, 0))
			regs[a] = 0
			regs[a + 1] = -1
			pc += 1
		else if op == 14:
			c := code.get(i + 3, 0)
			d := code.get(i + 4, 0)
			ex := code.get(i + 5, 0)
			cnt := regs.get(a, 0)
			st := regs.get(a + 1, -1)
			if cnt < b: pc += 1
			else if cnt > 0 and pos == st: pc = ex
			else if c >= 0 and cnt >= c: pc = ex
			else if d == 1:
				stack.append(0)
				stack.append(ex)
				stack.append(pos)
				pc += 1
			else:
				stack.append(0)
				stack.append(pc + 1)
				stack.append(pos)
				pc = ex
		else if op == 15:
			stack.append(1)
			stack.append(a + 1)
			stack.append(regs.get(a + 1, -1))
			regs[a + 1] = pos
			pc += 1
		else if op == 16:
			stack.append(1)
			stack.append(a)
			stack.append(regs.get(a, 0))
			regs[a] = regs.get(a, 0) + 1
			pc = b
		else if op == 17:
			pc = a
		else if op == 18:
			stack.append(0)
			stack.append(b)
			stack.append(pos)
			pc = a
		else if op == 19:
			if pos == n: pc += 1
			else: failed = true
		else:
			return pos
	return -1

// ---------------- driver ----------------

fn quoted(s: List[Int], from: Int, to: Int) String:
	var r = "\""
	for i in from..to:
		b := s.get(i, 0)
		if b == 92: r = r + "\\\\"
		else if b == 34: r = r + "\\\""
		else if b == 10: r = r + "\\n"
		else if b == 9: r = r + "\\t"
		else if b == 13: r = r + "\\r"
		else if b < 32 or b > 126:
			r = r + "\\x" + HEX.slice(b / 16, b / 16 + 1).get("") + HEX.slice(b % 16, b % 16 + 1).get("")
		else: r = r + chr(b)
	return r + "\""

fn unescape(f: List[Int]) List[Int]?:
	var out: List[Int] = []
	var i = 0
	n := f.length()
	while i < n:
		c := f.get(i, 0)
		if c != 92:
			out.append(c)
			i += 1
			continue
		if i + 1 >= n: return none
		e := f.get(i + 1, 0)
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
			if i + 3 >= n: return none
			h1 := hexv(f.get(i + 2, 0))
			h2 := hexv(f.get(i + 3, 0))
			if h1 < 0 or h2 < 0: return none
			out.append(h1 * 16 + h2)
			i += 4
		else: return none
	return out

fn compile(pat: List[Int]) P!:
	var p = P(pat: pat.clone())
	p.gnames.append("")
	// flags
	if p.peek(0) == 40 and p.peek(1) == 63:
		var j = 2
		var ok_flags = false
		var fi = false
		var fm = false
		var fs = false
		while true:
			c := p.peek(j)
			if c == 105: fi = true
			else if c == 109: fm = true
			else if c == 115: fs = true
			else:
				if c == 41 and j > 2: ok_flags = true
				break
			j += 1
		if ok_flags:
			p.icase = fi
			p.multi = fm
			p.dotall = fs
			p.pos = j + 1
	root := p.parse_alt(0)?
	if p.peek(0) >= 0: return error(Error("unmatched )"))
	p.emit(root)?
	return ok(p)

// result: caps flat (2*(ng+1)) or empty if none
fn search(p: P, subj: List[Int], from: Int, full: Bool) List[Int]:
	var code = p.code.clone()
	if full:
		code.append(19)
		for _i in 0..5:
			code.append(0)
	code.append(20)
	for _i in 0..5:
		code.append(0)
	ng1 := p.ngroups + 1
	nregs := 3 * ng1 + 2 * p.nloops + 2
	n := subj.length()
	var start = from
	while start <= n:
		var regs: List[Int] = []
		for _i in 0..nregs:
			regs.append(-1)
		var stack: List[Int] = []
		r := run(code, p.sets, subj, var regs, var stack, 0, start, 0)
		if r >= 0:
			regs[0] = start
			regs[1] = r
			var out: List[Int] = []
			for i in 0..2 * ng1:
				out.append(regs.get(i, -1))
			return out
		if full: break
		start += 1
	return []

fn all_matches(p: P, subj: List[Int]) List[Int]:
	var res: List[Int] = []
	var pos = 0
	n := subj.length()
	stride := 2 * (p.ngroups + 1)
	while pos <= n:
		m := search(p, subj, pos, false)
		if m.length() == 0: break
		s := m.get(0, 0)
		e := m.get(1, 0)
		for v in m:
			res.append(v)
		if e > s: pos = e
		else: pos = e + 1
	_ := stride
	return res

fn expand(rep: List[Int], p: P, subj: List[Int], m: List[Int], var res: List[Int]) Bool:
	n := rep.length()
	var i = 0
	while i < n:
		c := rep.get(i, 0)
		if c != 36 or i + 1 >= n:
			res.append(c)
			i += 1
			continue
		d := rep.get(i + 1, 0)
		if d == 36:
			res.append(36)
			i += 2
		else if d >= 48 and d <= 57:
			g := d - 48
			if g > p.ngroups: return false
			s := m.get(2 * g, -1)
			e := m.get(2 * g + 1, -1)
			if s >= 0:
				for j in s..e:
					res.append(subj.get(j, 0))
			i += 2
		else if d == 123:
			var j = i + 2
			var name: List[Int] = []
			var closed = false
			while j < n:
				if rep.get(j, 0) == 125:
					closed = true
					break
				name.append(rep.get(j, 0))
				j += 1
			if not closed: return false
			idx := p.gnames.index_of(bstr(name))
			if name.length() == 0: return false
			if g := idx:
				if g == 0: return false
				s := m.get(2 * g, -1)
				e := m.get(2 * g + 1, -1)
				if s >= 0:
					for k in s..e:
						res.append(subj.get(k, 0))
			else: return false
			i = j + 1
		else:
			res.append(36)
			i += 1
	return true

fn split_bytes(xs: List[Int], sep: Int) List[List[Int]]:
	var parts: List[List[Int]] = []
	var cur: List[Int] = []
	for b in xs:
		if b == sep:
			parts.append(cur.clone())
			cur = []
		else: cur.append(b)
	parts.append(cur.clone())
	return parts

fn handle(line: List[Int], var out: List[String]) Void:
	fields := split_bytes(line, 9)
	nf := fields.length()
	cmd := bstr(fields.get(0, []))
	var okc = false
	if cmd == "test" or cmd == "match" or cmd == "full" or cmd == "find-all" or cmd == "split":
		okc = nf == 3
	else if cmd == "replace":
		okc = nf == 4
	if not okc:
		out.append("error: bad command")
		return
	subj_o := unescape(fields.get(2, []))
	if subj_o.is_none():
		out.append("error: bad command")
		return
	subj := subj_o.get([])
	var rep: List[Int] = []
	if cmd == "replace":
		rep_o := unescape(fields.get(3, []))
		if rep_o.is_none():
			out.append("error: bad command")
			return
		rep = rep_o.get([])
	pr := compile(fields.get(1, []))
	if pr.is_error():
		out.append("error: {pr.err().message}")
		return
	p := pr.get(P(pat: []))
	if cmd == "test":
		m := search(p, subj, 0, false)
		out.append(if m.length() > 0: "true" else: "false")
	else if cmd == "match" or cmd == "full":
		m := search(p, subj, 0, cmd == "full")
		if m.length() == 0:
			out.append("no match")
			return
		for g in 0..p.ngroups + 1:
			s := m.get(2 * g, -1)
			e := m.get(2 * g + 1, -1)
			nm := p.gnames.get(g, "")
			label := if nm != "": "{g} ({nm})" else: "{g}"
			if s < 0: out.append("{label}: unset")
			else: out.append("{label}: {s}..{e} {quoted(subj, s, e)}")
	else:
		all := all_matches(p, subj)
		stride := 2 * (p.ngroups + 1)
		cnt := all.length() / stride
		if cmd == "find-all":
			for k in 0..cnt:
				s := all.get(k * stride, 0)
				e := all.get(k * stride + 1, 0)
				out.append("{s}..{e} {quoted(subj, s, e)}")
			out.append("({cnt} matches)")
		else if cmd == "split":
			var pieces = 0
			var last = 0
			for k in 0..cnt:
				s := all.get(k * stride, 0)
				e := all.get(k * stride + 1, 0)
				if e > s:
					out.append(quoted(subj, last, s))
					pieces += 1
					last = e
			out.append(quoted(subj, last, subj.length()))
			pieces += 1
			out.append("({pieces} pieces)")
		else:
			var res: List[Int] = []
			var last = 0
			for k in 0..cnt:
				s := all.get(k * stride, 0)
				e := all.get(k * stride + 1, 0)
				for j in last..s:
					res.append(subj.get(j, 0))
				m := all.slice(k * stride, (k + 1) * stride).get([])
				if not expand(rep, p, subj, m, var res):
					out.append("error: bad replacement")
					return
				last = e
			for j in last..subj.length():
				res.append(subj.get(j, 0))
			out.append(quoted(res, 0, res.length()))

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Void!:
	data := read_all(stdin(), none)?
	var bytes: List[Int] = []
	for b in values(data):
		bytes.append(b.to_int())
	lines := split_bytes(bytes, 10)
	var out: List[String] = []
	for line in lines:
		if line.length() == 0: continue
		handle(line, var out)
	if out.length() > 0:
		print(out.join("\n"))
