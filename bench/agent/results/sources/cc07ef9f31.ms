import Bytes from "@std/bytes.ms"
import parse_float, pow, floor, truncate, sqrt from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------- values ----------

type Value:
	t: Int
	n: Float
	s: String

fn vempty() Value: Value(0, 0.0, "")
fn verr(s: String) Value: Value(4, 0.0, s)
fn vtext(s: String) Value: Value(2, 0.0, s)
fn vbool(b: Bool) Value: Value(3, if b: 1.0 else: 0.0, "")
fn finite(x: Float) Bool: x - x == 0.0
fn vnum(x: Float) Value:
	if finite(x): return Value(1, x, "")
	return verr("#NUM!")
fn vcopy(v: Value) Value: Value(v.t, v.n, v.s.clone())

fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_letter(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
fn is_ws(c: Int) Bool: c == 32 or (c >= 9 and c <= 13)

fn byte(b: Bytes, i: Int) Int:
	if i < 0 or i >= b.length(): return -1
	return b.get(i).to_int()

fn sub(b: Bytes, a: Int, e: Int) String:
	var e2 = e
	if e2 > b.length(): e2 = b.length()
	if e2 <= a: return ""
	return b.decode_utf8_range(a, e2).get("")

fn fmt_big(x: Float) String:
	// x >= 1e21, an integer
	var m = x
	var e = 0
	while m >= 9007199254740992.0:
		m = m / 2.0
		e += 1
	var digs = List[Int]()
	var mi = m.truncate_to_int().get(0)
	while mi > 0:
		digs.append(mi % 10)
		mi = mi / 10
	for _k in 0..e:
		var carry = 0
		for j in 0..digs.length():
			v := digs[j] * 2 + carry
			digs[j] = v % 10
			carry = v / 10
		if carry > 0: digs.append(carry)
	var out = ""
	var j = digs.length() - 1
	while j >= 0:
		out = out + "{digs[j]}"
		j -= 1
	return out

fn fmt_num(x: Float) String:
	if x >= 1e21: return fmt_big(x)
	if x <= -1e21: return "-" + fmt_big(0.0 - x)
	var s = x.to_fixed(10)
	if s.contains("."):
		s = s.trim_chars("0")
		if s.ends_with("."): s = s.slice(0, s.length() - 1).get("")
	if s == "-0" or s == "" or s == "-": return "0"
	if s.starts_with("."): s = "0" + s
	if s.starts_with("-."): s = "-0" + s.slice(1, s.length()).get("")
	return s

fn disp(v: Value) String:
	if v.t == 1: return fmt_num(v.n)
	if v.t == 3:
		if v.n != 0.0: return "TRUE"
		return "FALSE"
	return v.s.clone()

// number grammar: [+-]? (digits [. digits?] | . digits) ([eE][+-]?digits)?
fn scan_body(b: Bytes, start: Int) Int:
	var i = start
	var nd = 0
	while is_digit(byte(b, i)):
		i += 1
		nd += 1
	if nd > 0:
		if byte(b, i) == 46:
			i += 1
			while is_digit(byte(b, i)): i += 1
	else:
		if byte(b, i) != 46: return -1
		i += 1
		var nf = 0
		while is_digit(byte(b, i)):
			i += 1
			nf += 1
		if nf == 0: return -1
	c := byte(b, i)
	if c == 101 or c == 69:
		var j = i + 1
		d := byte(b, j)
		if d == 43 or d == 45: j += 1
		if is_digit(byte(b, j)):
			while is_digit(byte(b, j)): j += 1
			i = j
	return i

fn canon_float(body: String) Float?:
	var mant = body.clone()
	var ex = ""
	for k in 0..body.length():
		ch := body.view(k, k + 1)
		if ch == "e" or ch == "E":
			mant = body.view(0, k).clone()
			ex = body.view(k + 1, body.length()).clone()
			break
	if mant.starts_with("."): mant = "0" + mant
	if mant.ends_with("."): mant = mant + "0"
	if ex.starts_with("+"): ex = ex.view(1, ex.length()).clone()
	text := if ex == "": mant else: mant + "e" + ex
	r := parse_float(text)
	if f := r:
		if finite(f): return f
	return none

// strict: whole string is a number
fn parse_number(s: String) Float?:
	b := s.as_bytes()
	var i = 0
	var neg = false
	c := byte(b, 0)
	if c == 43 or c == 45:
		i = 1
		neg = c == 45
	e := scan_body(b, i)
	if e < 0 or e != b.length(): return none
	r := canon_float(sub(b, i, e))
	if f := r:
		if neg: return 0.0 - f
		return f
	return none

// ---------- AST ----------

type Node:
	kind: Int
	num: Float
	str: String
	a: Int
	b: Int
	c: Int
	d: Int
	args: List[Int]

type Prog:
	ok: Bool
	nodes: List[Node]
	root: Int

fn nd(kind: Int, num: Float, str: String, a: Int, b: Int, c: Int, d: Int) Node:
	return Node(kind, num, str, a, b, c, d, List[Int]())

fn noprog() Prog: Prog(false, List[Node](), 0)

// node kinds
// 0 num, 1 str, 2 bool(a), 3 ref(a=idx), 4 badref, 5 range(a=c1,b=r1,c=c2,d=r2), 6 badrange, 7 errlit, 8 name, 9 call, 10 bin(str), 11 unary(str)

type RefPart:
	ok: Bool
	col: Int
	row: Int
	ac: Bool
	ar: Bool

type Token:
	kind: Int
	text: String
	num: Float
	start: Int
	end: Int
	p1: RefPart
	p2: RefPart

type Lexed:
	toks: List[Token]
	ok: Bool

fn badpart() RefPart: RefPart(false, 0, 0, false, false)

// try to scan a reference word at i; returns end or -1
fn scan_ref(b: Bytes, i0: Int) Int:
	var i = i0
	if byte(b, i) == 36: i += 1
	var nl = 0
	while is_letter(byte(b, i)):
		i += 1
		nl += 1
	if nl == 0: return -1
	if byte(b, i) == 36: i += 1
	var nd = 0
	while is_digit(byte(b, i)):
		i += 1
		nd += 1
	if nd == 0: return -1
	n := byte(b, i)
	if is_letter(n) or is_digit(n) or n == 95 or n == 46 or n == 40 or n == 36: return -1
	return i

fn ref_part(b: Bytes, s: Int, e: Int) RefPart:
	var i = s
	var ac = false
	var ar = false
	if byte(b, i) == 36:
		ac = true
		i += 1
	ls := i
	while is_letter(byte(b, i)): i += 1
	le := i
	if byte(b, i) == 36:
		ar = true
		i += 1
	ds := i
	nd := e - ds
	if le - ls != 1 or nd > 3 or nd < 1: return badpart()
	if byte(b, ds) == 48: return badpart()
	var row = 0
	for k in ds..e:
		row = row * 10 + (byte(b, k) - 48)
	if row < 1 or row > 999: return badpart()
	l := byte(b, ls)
	var col = 0
	if l >= 97: col = l - 97
	else: col = l - 65
	return RefPart(true, col, row, ac, ar)

fn lex(src: String) Lexed:
	b := src.as_bytes()
	var toks = List[Token]()
	var i = 0
	n := b.length()
	while i < n:
		c := byte(b, i)
		if c == 32 or c == 9:
			i += 1
			continue
		start := i
		if is_digit(c) or (c == 46 and is_digit(byte(b, i + 1))):
			e := scan_body(b, i)
			text := sub(b, i, e)
			var v = 1e308 * 10.0
			if f := canon_float(text.clone()): v = f
			toks.append(Token(0, text, v, start, e, badpart(), badpart()))
			i = e
			continue
		if c == 34:
			var j = i + 1
			var seg = j
			var acc = ""
			var closed = false
			while j < n:
				if byte(b, j) == 34:
					if byte(b, j + 1) == 34:
						acc = acc + sub(b, seg, j) + "\""
						j += 2
						seg = j
						continue
					acc = acc + sub(b, seg, j)
					closed = true
					j += 1
					break
				j += 1
			if not closed: return Lexed(List[Token](), false)
			toks.append(Token(1, acc, 0.0, start, j, badpart(), badpart()))
			i = j
			continue
		if c == 35:
			if sub(b, i, i + 5) == "#REF!":
				toks.append(Token(4, "#REF!", 0.0, start, i + 5, badpart(), badpart()))
				i += 5
				continue
			return Lexed(List[Token](), false)
		if is_letter(c) or c == 36 or c == 95:
			e := scan_ref(b, i)
			if e >= 0:
				p1 := ref_part(b, i, e)
				if byte(b, e) == 58:
					e2 := scan_ref(b, e + 1)
					if e2 >= 0:
						p2 := ref_part(b, e + 1, e2)
						toks.append(Token(3, sub(b, i, e2), 0.0, start, e2, p1, p2))
						i = e2
						continue
				toks.append(Token(2, sub(b, i, e), 0.0, start, e, p1, badpart()))
				i = e
				continue
			if c == 36: return Lexed(List[Token](), false)
			var j = i
			while is_letter(byte(b, j)) or is_digit(byte(b, j)) or byte(b, j) == 95 or byte(b, j) == 46: j += 1
			toks.append(Token(5, sub(b, i, j), 0.0, start, j, badpart(), badpart()))
			i = j
			continue
		// operators
		two := sub(b, i, i + 2)
		if two == "<>" or two == "<=" or two == ">=":
			toks.append(Token(6, two, 0.0, start, i + 2, badpart(), badpart()))
			i += 2
			continue
		if c == 43 or c == 45 or c == 42 or c == 47 or c == 94 or c == 38 or c == 61 or c == 60 or c == 62 or c == 40 or c == 41 or c == 44:
			toks.append(Token(6, sub(b, i, i + 1), 0.0, start, i + 1, badpart(), badpart()))
			i += 1
			continue
		return Lexed(List[Token](), false)
	return Lexed(toks, true)

// ---------- parser ----------

fn cell_idx(col: Int, row: Int) Int: (row - 1) * 26 + col

type Parser:
	toks: List[Token]
	pos: Int
	nodes: List[Node]
	fail: Bool
	precs: List[Int]
	seen: Set[Int]
	sup: Int

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.addprec(i: Int) Unit:
	if self.sup > 0: return
	if self.seen.contains(i): return
	self.seen.add(i)
	self.precs.append(i)

fn Parser.is_op(text: String) Bool:
	if self.pos >= self.toks.length(): return false
	t := self.toks[self.pos]
	return t.kind == 6 and t.text == text

fn var Parser.fail_now() Int:
	self.fail = true
	return -1

fn var Parser.expr() Int:
	var l = self.concat()
	if self.fail: return -1
	while self.pos < self.toks.length():
		t := self.toks[self.pos]
		if t.kind == 6 and (t.text == "=" or t.text == "<>" or t.text == "<" or t.text == "<=" or t.text == ">" or t.text == ">="):
			op := t.text.clone()
			self.pos += 1
			r := self.concat()
			if self.fail: return -1
			l = self.add(nd(10, 0.0, op, l, r, 0, 0))
		else:
			break
	return l

fn var Parser.concat() Int:
	var l = self.additive()
	if self.fail: return -1
	while self.is_op("&"):
		self.pos += 1
		r := self.additive()
		if self.fail: return -1
		l = self.add(nd(10, 0.0, "&", l, r, 0, 0))
	return l

fn var Parser.additive() Int:
	var l = self.term()
	if self.fail: return -1
	while self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		r := self.term()
		if self.fail: return -1
		l = self.add(nd(10, 0.0, op, l, r, 0, 0))
	return l

fn var Parser.term() Int:
	var l = self.unary()
	if self.fail: return -1
	while self.is_op("*") or self.is_op("/"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		r := self.unary()
		if self.fail: return -1
		l = self.add(nd(10, 0.0, op, l, r, 0, 0))
	return l

fn var Parser.unary() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		x := self.unary()
		if self.fail: return -1
		return self.add(nd(11, 0.0, op, x, 0, 0, 0))
	return self.power()

fn var Parser.power() Int:
	l := self.primary()
	if self.fail: return -1
	if self.is_op("^"):
		self.pos += 1
		r := self.power_exp()
		if self.fail: return -1
		return self.add(nd(10, 0.0, "^", l, r, 0, 0))
	return l

fn var Parser.power_exp() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		x := self.power_exp()
		if self.fail: return -1
		return self.add(nd(11, 0.0, op, x, 0, 0, 0))
	return self.power()

fn var Parser.primary() Int:
	if self.pos >= self.toks.length(): return self.fail_now()
	t := self.toks[self.pos].clone()
	self.pos += 1
	if t.kind == 0: return self.add(nd(0, t.num, "", 0, 0, 0, 0))
	if t.kind == 1: return self.add(nd(1, 0.0, t.text.clone(), 0, 0, 0, 0))
	if t.kind == 4: return self.add(nd(7, 0.0, "", 0, 0, 0, 0))
	if t.kind == 2:
		if t.p1.ok:
			idx := cell_idx(t.p1.col, t.p1.row)
			self.addprec(idx)
			return self.add(nd(3, 0.0, "", idx, 0, 0, 0))
		return self.add(nd(4, 0.0, "", 0, 0, 0, 0))
	if t.kind == 3:
		if t.p1.ok and t.p2.ok:
			c1 := if t.p1.col < t.p2.col: t.p1.col else: t.p2.col
			c2 := if t.p1.col < t.p2.col: t.p2.col else: t.p1.col
			r1 := if t.p1.row < t.p2.row: t.p1.row else: t.p2.row
			r2 := if t.p1.row < t.p2.row: t.p2.row else: t.p1.row
			for r in r1..(r2 + 1):
				for c in c1..(c2 + 1):
					self.addprec(cell_idx(c, r))
			return self.add(nd(5, 0.0, "", c1, r1, c2, r2))
		return self.add(nd(6, 0.0, "", 0, 0, 0, 0))
	if t.kind == 5:
		if self.is_op("("):
			self.pos += 1
			name := t.text.upper()
			node := self.add(nd(9, 0.0, name.clone(), 0, 0, 0, 0))
			sup := name == "ROW" or name == "COLUMN"
			if sup: self.sup += 1
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.expr()
					if self.fail: return -1
					self.nodes[node].args.append(a)
					if self.is_op(","):
						self.pos += 1
						continue
					if self.is_op(")"):
						self.pos += 1
						break
					return self.fail_now()
			if sup: self.sup -= 1
			return node
		up := t.text.upper()
		if up == "TRUE": return self.add(nd(2, 0.0, "", 1, 0, 0, 0))
		if up == "FALSE": return self.add(nd(2, 0.0, "", 0, 0, 0, 0))
		return self.add(nd(8, 0.0, "", 0, 0, 0, 0))
	if t.kind == 6 and t.text == "(":
		x := self.expr()
		if self.fail: return -1
		if self.is_op(")"):
			self.pos += 1
			return x
		return self.fail_now()
	return self.fail_now()

fn parse_formula(src: String) Prog:
	lx := lex(src)
	if not lx.ok: return noprog()
	var p = Parser(lx.toks, 0, List[Node](), false, List[Int](), Set[Int](), 0)
	root := p.expr()
	if p.fail or p.pos < p.toks.length(): return noprog()
	return Prog(true, p.nodes, root)

// precedents of a parsed program (recomputed from nodes; ROW/COLUMN args excluded)
fn prog_precs(p: Prog) List[Int]:
	var out = List[Int]()
	var seen = Set[Int]()
	if not p.ok: return out
	var skip = Set[Int]()
	for i in 0..p.nodes.length():
		nn := p.nodes[i]
		if nn.kind == 9 and (nn.str == "ROW" or nn.str == "COLUMN"):
			var stack = List[Int]()
			for a in nn.args: stack.append(a)
			while stack.length() > 0:
				x := stack.pop().get(0)
				skip.add(x)
				for y in p.nodes[x].args: stack.append(y)
				k := p.nodes[x].kind
				if k == 10:
					stack.append(p.nodes[x].a)
					stack.append(p.nodes[x].b)
				if k == 11: stack.append(p.nodes[x].a)
	// nodes are created in evaluation-independent order; sort-free collection
	for i in 0..p.nodes.length():
		if skip.contains(i): continue
		nn := p.nodes[i]
		if nn.kind == 3:
			if not seen.contains(nn.a):
				seen.add(nn.a)
				out.append(nn.a)
		if nn.kind == 5:
			for r in nn.b..(nn.d + 1):
				for c in nn.a..(nn.c + 1):
					k := cell_idx(c, r)
					if not seen.contains(k):
						seen.add(k)
						out.append(k)
	return out

// ---------- sheet ----------

type Sheet:
	raw: List[String]
	kind: List[Int]
	vals: List[Value]
	progs: List[Prog]
	precs: List[List[Int]]
	deps: List[Set[Int]]
	mark: List[Bool]
	tidx: List[Int]
	low: List[Int]
	onst: List[Bool]
	epos: List[Int]
	evals: Int

fn new_sheet() Sheet:
	n := 26 * 999
	var s = Sheet(List[String](), List[Int](), List[Value](), List[Prog](), List[List[Int]](), List[Set[Int]](), List[Bool](), List[Int](), List[Int](), List[Bool](), List[Int](), 0)
	for _i in 0..n:
		s.raw.append("")
		s.kind.append(0)
		s.vals.append(vempty())
		s.progs.append(noprog())
		s.precs.append(List[Int]())
		s.deps.append(Set[Int]())
		s.mark.append(false)
		s.tidx.append(-1)
		s.low.append(0)
		s.onst.append(false)
		s.epos.append(0)
	return s

// ---------- evaluation ----------

fn to_num(v: Value) Value:
	if v.t == 1: return vcopy(v)
	if v.t == 4: return vcopy(v)
	if v.t == 3: return Value(1, v.n, "")
	if v.t == 0: return Value(1, 0.0, "")
	if f := parse_number(v.s.trim()): return Value(1, f, "")
	return verr("#VALUE!")

fn to_bool(v: Value) Value:
	if v.t == 3: return vcopy(v)
	if v.t == 4: return vcopy(v)
	if v.t == 1: return vbool(v.n != 0.0)
	if v.t == 0: return vbool(false)
	u := v.s.upper()
	if u == "TRUE": return vbool(true)
	if u == "FALSE": return vbool(false)
	return verr("#VALUE!")

fn to_str(v: Value) Value:
	if v.t == 4: return vcopy(v)
	return vtext(disp(v))

fn rank(t: Int) Int:
	if t == 1: return 0
	if t == 2: return 1
	return 2

fn cmp_f(a: Float, b: Float) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

// a, b not errors
fn cmp_vals(a: Value, b: Value) Int:
	if a.t == 0 and b.t == 0: return 0
	var at = a.t
	var bt = b.t
	if at == 0: at = bt
	if bt == 0: bt = at
	ra := rank(at)
	rb := rank(bt)
	if ra != rb: return cmp_f(ra.to_float(), rb.to_float())
	if ra == 1:
		x := if a.t == 0: "" else: a.s.clone()
		y := if b.t == 0: "" else: b.s.clone()
		return x.compare(y)
	x := if a.t == 0: 0.0 else: a.n
	y := if b.t == 0: 0.0 else: b.n
	return cmp_f(x, y)

type Item:
	v: Value
	rng: Bool

fn cellv(s: Sheet, c: Int, r: Int) Value: vcopy(s.vals[cell_idx(c, r)])

fn collect_items(s: Sheet, p: Prog, args: List[Int]) List[Item]:
	var out = List[Item]()
	for a in args:
		k := p.nodes[a].kind
		if k == 5:
			nn := p.nodes[a]
			for r in nn.b..(nn.d + 1):
				for c in nn.a..(nn.c + 1):
					out.append(Item(cellv(s, c, r), true))
		else if k == 6:
			out.append(Item(verr("#REF!"), true))
		else:
			out.append(Item(ev(s, p, a), false))
	return out

fn num_args(s: Sheet, p: Prog, args: List[Int], i: Int) Value:
	return to_num(ev(s, p, args[i]))

fn floor_int(f: Float) Float: floor(f)

fn round_half_away(x: Float) Float:
	a := if x < 0.0: 0.0 - x else: x
	t := truncate(a)
	r := if a - t >= 0.5: t + 1.0 else: t
	if x < 0.0: return 0.0 - r
	return r

fn ev(s: Sheet, p: Prog, i: Int) Value:
	nn := p.nodes[i]
	k := nn.kind
	if k == 0: return vnum(nn.num)
	if k == 1: return vtext(nn.str.clone())
	if k == 2: return vbool(nn.a == 1)
	if k == 3: return vcopy(s.vals[nn.a])
	if k == 4: return verr("#REF!")
	if k == 5 or k == 6: return verr("#VALUE!")
	if k == 7: return verr("#REF!")
	if k == 8: return verr("#NAME?")
	if k == 11:
		x := to_num(ev(s, p, nn.a))
		if x.t == 4: return x
		if nn.str == "-": return vnum(0.0 - x.n)
		return x
	if k == 10: return ev_bin(s, p, nn)
	return ev_call(s, p, nn)

fn ev_bin(s: Sheet, p: Prog, nn: Node) Value:
	op := nn.str
	l := ev(s, p, nn.a)
	r := ev(s, p, nn.b)
	if op == "&":
		x := to_str(l)
		if x.t == 4: return x
		y := to_str(r)
		if y.t == 4: return y
		return vtext(x.s + y.s)
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if l.t == 4: return l
		if r.t == 4: return r
		c := cmp_vals(l, r)
		if op == "=": return vbool(c == 0)
		if op == "<>": return vbool(c != 0)
		if op == "<": return vbool(c < 0)
		if op == "<=": return vbool(c <= 0)
		if op == ">": return vbool(c > 0)
		return vbool(c >= 0)
	x := to_num(l)
	if x.t == 4: return x
	y := to_num(r)
	if y.t == 4: return y
	if op == "+": return vnum(x.n + y.n)
	if op == "-": return vnum(x.n - y.n)
	if op == "*": return vnum(x.n * y.n)
	if op == "/":
		if y.n == 0.0: return verr("#DIV/0!")
		return vnum(x.n / y.n)
	return vnum(pow(x.n, y.n))

fn crit_match(op: String, operand: Value, cell: Value) Bool:
	if cell.t == operand.t:
		c := cmp_vals(cell, operand)
		if op == "=": return c == 0
		if op == "<>": return c != 0
		if op == "<": return c < 0
		if op == "<=": return c <= 0
		if op == ">": return c > 0
		return c >= 0
	if op == "<>" and cell.t != 0: return true
	return false

fn ev_call(s: Sheet, p: Prog, nn: Node) Value:
	name := nn.str
	args := nn.args
	na := args.length()
	if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN":
		if na < 1: return verr("#VALUE!")
		items := collect_items(s, p, args)
		var nums = List[Float]()
		for it in items:
			if it.v.t == 4: return vcopy(it.v)
			if it.rng:
				if it.v.t == 1: nums.append(it.v.n)
			else:
				x := to_num(it.v)
				if x.t == 4: return x
				nums.append(x.n)
		if name == "SUM":
			var t = 0.0
			for x in nums: t += x
			return vnum(t)
		if name == "PRODUCT":
			if nums.length() == 0: return vnum(0.0)
			var t = 1.0
			for x in nums: t = t * x
			return vnum(t)
		if name == "AVERAGE":
			if nums.length() == 0: return verr("#DIV/0!")
			var t = 0.0
			for x in nums: t += x
			return vnum(t / nums.length().to_float())
		if name == "MIN" or name == "MAX":
			if nums.length() == 0: return vnum(0.0)
			var m = nums[0]
			for x in nums:
				if name == "MIN" and x < m: m = x
				if name == "MAX" and x > m: m = x
			return vnum(m)
		if nums.length() == 0: return verr("#NUM!")
		nums.sort(fn a, b: a.compare(b))
		h := nums.length() / 2
		if nums.length() % 2 == 1: return vnum(nums[h])
		return vnum((nums[h - 1] + nums[h]) / 2.0)
	if name == "COUNT" or name == "COUNTA":
		if na < 1: return verr("#VALUE!")
		items := collect_items(s, p, args)
		var c = 0
		for it in items:
			if name == "COUNT":
				if it.v.t == 1: c += 1
			else:
				if it.v.t != 0: c += 1
		return vnum(c.to_float())
	if name == "IF":
		if na < 2 or na > 3: return verr("#VALUE!")
		c := to_bool(ev(s, p, args[0]))
		if c.t == 4: return c
		if c.n != 0.0: return ev(s, p, args[1])
		if na == 3: return ev(s, p, args[2])
		return vbool(false)
	if name == "IFERROR":
		if na != 2: return verr("#VALUE!")
		a := ev(s, p, args[0])
		if a.t == 4: return ev(s, p, args[1])
		return a
	if name == "CHOOSE":
		if na < 2: return verr("#VALUE!")
		x := to_num(ev(s, p, args[0]))
		if x.t == 4: return x
		f := floor(x.n)
		if f < 1.0 or f > (na - 1).to_float(): return verr("#VALUE!")
		return ev(s, p, args[f.truncate_to_int().get(1)])
	if name == "AND" or name == "OR":
		if na < 1: return verr("#VALUE!")
		items := collect_items(s, p, args)
		var took = false
		var acc = name == "AND"
		for it in items:
			if it.v.t == 4: return vcopy(it.v)
			if it.rng and (it.v.t == 2 or it.v.t == 0): continue
			b := to_bool(it.v)
			if b.t == 4: return b
			took = true
			if name == "AND": acc = acc and b.n != 0.0
			else: acc = acc or b.n != 0.0
		if not took: return verr("#VALUE!")
		return vbool(acc)
	if name == "NOT":
		if na != 1: return verr("#VALUE!")
		b := to_bool(ev(s, p, args[0]))
		if b.t == 4: return b
		return vbool(b.n == 0.0)
	if name == "ABS" or name == "INT" or name == "SQRT":
		if na != 1: return verr("#VALUE!")
		x := to_num(ev(s, p, args[0]))
		if x.t == 4: return x
		if name == "ABS": return vnum(if x.n < 0.0: 0.0 - x.n else: x.n)
		if name == "INT": return vnum(floor(x.n))
		if x.n < 0.0: return verr("#NUM!")
		return vnum(sqrt(x.n))
	if name == "POW" or name == "MOD":
		if na != 2: return verr("#VALUE!")
		x := to_num(ev(s, p, args[0]))
		if x.t == 4: return x
		y := to_num(ev(s, p, args[1]))
		if y.t == 4: return y
		if name == "POW": return vnum(pow(x.n, y.n))
		if y.n == 0.0: return verr("#DIV/0!")
		return vnum(x.n - y.n * floor(x.n / y.n))
	if name == "ROUND":
		if na < 1 or na > 2: return verr("#VALUE!")
		x := to_num(ev(s, p, args[0]))
		if x.t == 4: return x
		var d = 0.0
		if na == 2:
			dv := to_num(ev(s, p, args[1]))
			if dv.t == 4: return dv
			d = truncate(dv.n)
		if d > 15.0 or d < -15.0: return verr("#NUM!")
		pw := pow(10.0, d)
		return vnum(round_half_away(x.n * pw) / pw)
	if name == "LEN" or name == "UPPER" or name == "LOWER" or name == "TRIM":
		if na != 1: return verr("#VALUE!")
		x := to_str(ev(s, p, args[0]))
		if x.t == 4: return x
		if name == "LEN": return vnum(x.s.scalar_length().to_float())
		if name == "UPPER": return vtext(ascii_case(x.s, true))
		if name == "LOWER": return vtext(ascii_case(x.s, false))
		return vtext(trim_ws(x.s))
	if name == "LEFT" or name == "RIGHT":
		if na < 1 or na > 2: return verr("#VALUE!")
		x := to_str(ev(s, p, args[0]))
		if x.t == 4: return x
		var n = 1.0
		if na == 2:
			nv := to_num(ev(s, p, args[1]))
			if nv.t == 4: return nv
			n = floor(nv.n)
		if n < 0.0: return verr("#VALUE!")
		cs := x.s.chars()
		len := cs.length()
		var cnt = len
		if n < len.to_float(): cnt = n.truncate_to_int().get(0)
		var out = ""
		if name == "LEFT":
			for j in 0..cnt: out = out + cs[j]
		else:
			for j in (len - cnt)..len: out = out + cs[j]
		return vtext(out)
	if name == "MID":
		if na != 3: return verr("#VALUE!")
		x := to_str(ev(s, p, args[0]))
		if x.t == 4: return x
		st := to_num(ev(s, p, args[1]))
		if st.t == 4: return st
		ln := to_num(ev(s, p, args[2]))
		if ln.t == 4: return ln
		sf := floor(st.n)
		lf := floor(ln.n)
		if sf < 1.0 or lf < 0.0: return verr("#VALUE!")
		cs := x.s.chars()
		len := cs.length()
		if sf > len.to_float(): return vtext("")
		s0 := sf.truncate_to_int().get(1) - 1
		var e0 = len
		if lf < (len - s0).to_float(): e0 = s0 + lf.truncate_to_int().get(0)
		var out = ""
		for j in s0..e0: out = out + cs[j]
		return vtext(out)
	if name == "CONCAT":
		if na < 1: return verr("#VALUE!")
		items := collect_items(s, p, args)
		var out = ""
		for it in items:
			x := to_str(it.v)
			if x.t == 4: return x
			out = out + x.s
		return vtext(out)
	if name == "SUBSTITUTE":
		if na != 3: return verr("#VALUE!")
		x := to_str(ev(s, p, args[0]))
		if x.t == 4: return x
		o := to_str(ev(s, p, args[1]))
		if o.t == 4: return o
		w := to_str(ev(s, p, args[2]))
		if w.t == 4: return w
		if o.s == "": return x
		return vtext(x.s.replace(o.s, w.s))
	if name == "VALUE":
		if na != 1: return verr("#VALUE!")
		x := ev(s, p, args[0])
		if x.t == 2:
			if f := parse_number(x.s.trim()): return vnum(f)
			return verr("#VALUE!")
		return to_num(x)
	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if na != 1: return verr("#VALUE!")
		x := ev(s, p, args[0])
		if name == "ISERROR": return vbool(x.t == 4)
		if name == "ISBLANK": return vbool(x.t == 0)
		if name == "ISNUMBER": return vbool(x.t == 1)
		return vbool(x.t == 2)
	if name == "ROW" or name == "COLUMN":
		if na != 1: return verr("#VALUE!")
		a := p.nodes[args[0]]
		if a.kind == 4 or a.kind == 6: return verr("#REF!")
		if a.kind == 3:
			if name == "ROW": return vnum((a.a / 26 + 1).to_float())
			return vnum((a.a % 26 + 1).to_float())
		if a.kind == 5:
			if name == "ROW": return vnum(a.b.to_float())
			return vnum((a.a + 1).to_float())
		return verr("#VALUE!")
	if name == "INDEX":
		if na < 2 or na > 3: return verr("#VALUE!")
		a := p.nodes[args[0]]
		if a.kind == 6: return verr("#REF!")
		if a.kind != 5: return verr("#VALUE!")
		rows := a.d - a.b + 1
		cols := a.c - a.a + 1
		x := to_num(ev(s, p, args[1]))
		if x.t == 4: return x
		var ri = floor(x.n)
		var ci = 1.0
		if na == 3:
			y := to_num(ev(s, p, args[2]))
			if y.t == 4: return y
			ri = floor(x.n)
			ci = floor(y.n)
		else:
			if rows == 1:
				ci = floor(x.n)
				ri = 1.0
		if ri < 1.0 or ci < 1.0 or ri > rows.to_float() or ci > cols.to_float(): return verr("#REF!")
		return cellv(s, a.a + ci.truncate_to_int().get(1) - 1, a.b + ri.truncate_to_int().get(1) - 1)
	if name == "COUNTIF":
		if na != 2: return verr("#VALUE!")
		a := p.nodes[args[0]]
		if a.kind == 6: return verr("#REF!")
		if a.kind != 5: return verr("#VALUE!")
		cr := ev(s, p, args[1])
		if cr.t == 4: return cr
		var op = "="
		var operand = vcopy(cr)
		if cr.t == 2:
			var rest = cr.s.clone()
			var found = false
			for o in ["<=", ">=", "<>", ">", "<", "="]:
				if not found and rest.starts_with(o):
					op = o.clone()
					rest = rest.view(o.length(), rest.length()).clone()
					found = true
			if f := parse_number(rest): operand = Value(1, f, "")
			else: operand = vtext(rest)
		var count = 0
		for r in a.b..(a.d + 1):
			for c in a.a..(a.c + 1):
				if crit_match(op, operand, s.vals[cell_idx(c, r)]): count += 1
		return vnum(count.to_float())
	return verr("#NAME?")

fn ascii_case(x: String, up: Bool) String:
	var out = ""
	for ch in x.chars():
		if ch.length() == 1:
			c := ch.scalar_at(0)
			if up and c >= 97 and c <= 122:
				out = out + ch.upper()
				continue
			if not up and c >= 65 and c <= 90:
				out = out + ch.lower()
				continue
		out = out + ch
	return out

fn trim_ws(x: String) String:
	var out = ""
	var pending = false
	for ch in x.chars():
		if ch.length() == 1 and is_ws(ch.scalar_at(0)):
			pending = out != ""
			continue
		if pending:
			out = out + " "
			pending = false
		out = out + ch
	return out

// ---------- sheet operations ----------

fn var Sheet.assign(idx: Int, text: String) Unit:
	for pc in self.precs[idx]:
		self.deps[pc].remove(idx)
	self.precs[idx] = List[Int]()
	self.progs[idx] = noprog()
	if text == "":
		self.raw[idx] = ""
		self.kind[idx] = 0
		self.vals[idx] = vempty()
		return
	self.raw[idx] = text.clone()
	if text.starts_with("="):
		self.kind[idx] = 2
		pr := parse_formula(text.view(1, text.length()))
		ps := prog_precs(pr)
		self.progs[idx] = pr
		for pc in ps:
			self.deps[pc].add(idx)
		self.precs[idx] = ps
		return
	self.kind[idx] = 1
	if text.starts_with("'"):
		self.vals[idx] = vtext(text.view(1, text.length()).clone())
		return
	if f := parse_number(text):
		self.vals[idx] = Value(1, f, "")
		return
	u := text.upper()
	if u == "TRUE":
		self.vals[idx] = vbool(true)
		return
	if u == "FALSE":
		self.vals[idx] = vbool(false)
		return
	self.vals[idx] = vtext(text.clone())

fn var Sheet.eval_cell(c: Int) Unit:
	pr := self.progs[c]
	if not pr.ok:
		self.vals[c] = verr("#PARSE!")
		return
	v := ev(self, pr, pr.root)
	if v.t == 0:
		self.vals[c] = vnum(0.0)
	else:
		self.vals[c] = v

fn var Sheet.recalc(changed: List[Int]) Int:
	var aff = List[Int]()
	var queue = List[Int]()
	for c in changed:
		if self.kind[c] == 2 and not self.mark[c]:
			self.mark[c] = true
			aff.append(c)
		queue.append(c)
	var qi = 0
	while qi < queue.length():
		c := queue[qi]
		qi += 1
		for d in self.deps[c]:
			if not self.mark[d]:
				self.mark[d] = true
				aff.append(d)
				queue.append(d)
	var counter = 0
	var sccstack = List[Int]()
	var callstack = List[Int]()
	for root in aff:
		if self.tidx[root] != -1: continue
		self.tidx[root] = counter
		self.low[root] = counter
		counter += 1
		sccstack.append(root)
		self.onst[root] = true
		callstack.append(root)
		while callstack.length() > 0:
			v := callstack[callstack.length() - 1]
			if self.epos[v] < self.precs[v].length():
				w := self.precs[v][self.epos[v]]
				self.epos[v] += 1
				if not self.mark[w]: continue
				if self.tidx[w] == -1:
					self.tidx[w] = counter
					self.low[w] = counter
					counter += 1
					sccstack.append(w)
					self.onst[w] = true
					callstack.append(w)
				else if self.onst[w]:
					if self.tidx[w] < self.low[v]: self.low[v] = self.tidx[w]
			else:
				callstack.pop()
				if self.low[v] == self.tidx[v]:
					var comp = List[Int]()
					while true:
						x := sccstack.pop().get(0)
						self.onst[x] = false
						comp.append(x)
						if x == v: break
					var cyc = comp.length() > 1
					if not cyc:
						for pc in self.precs[v]:
							if pc == v: cyc = true
					if cyc:
						for x in comp: self.vals[x] = verr("#CYCLE!")
					else:
						self.eval_cell(v)
				if callstack.length() > 0:
					u := callstack[callstack.length() - 1]
					if self.low[v] < self.low[u]: self.low[u] = self.low[v]
	for c in aff:
		self.mark[c] = false
		self.tidx[c] = -1
		self.low[c] = 0
		self.onst[c] = false
		self.epos[c] = 0
	self.evals += aff.length()
	return aff.length()

// ---------- commands ----------

type CellPos:
	ok: Bool
	col: Int
	row: Int

fn parse_cellref(t: String) CellPos:
	b := t.as_bytes()
	n := b.length()
	bad := CellPos(false, 0, 0)
	if n < 2 or n > 4: return bad
	l := byte(b, 0)
	if not is_letter(l): return bad
	if byte(b, 1) == 48: return bad
	var row = 0
	for k in 1..n:
		c := byte(b, k)
		if not is_digit(c): return bad
		row = row * 10 + (c - 48)
	if row < 1 or row > 999: return bad
	col := if l >= 97: l - 97 else: l - 65
	return CellPos(true, col, row)

type Rect:
	ok: Bool
	c1: Int
	r1: Int
	c2: Int
	r2: Int

fn parse_rect(t: String) Rect:
	bad := Rect(false, 0, 0, 0, 0)
	parts := t.split(":")
	if parts.length() == 1:
		a := parse_cellref(parts[0])
		if not a.ok: return bad
		return Rect(true, a.col, a.row, a.col, a.row)
	if parts.length() == 2:
		a := parse_cellref(parts[0])
		b := parse_cellref(parts[1])
		if not a.ok or not b.ok: return bad
		c1 := if a.col < b.col: a.col else: b.col
		c2 := if a.col < b.col: b.col else: a.col
		r1 := if a.row < b.row: a.row else: b.row
		r2 := if a.row < b.row: b.row else: a.row
		return Rect(true, c1, r1, c2, r2)
	return bad

fn col_name(c: Int) String:
	letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	return letters.view(c, c + 1).clone()

fn cell_name(idx: Int) String:
	return col_name(idx % 26) + "{idx / 26 + 1}"

fn tokens_of(line: String) List[String]:
	return line.fields()

// the rest of the line after n whitespace-separated tokens, trimmed
fn rest_after(line: String, n: Int) String:
	b := line.as_bytes()
	var i = 0
	var cnt = 0
	while cnt < n:
		while i < b.length() and is_ws(byte(b, i)): i += 1
		while i < b.length() and not is_ws(byte(b, i)): i += 1
		cnt += 1
	return sub(b, i, b.length()).trim()

fn shift_ref(p: RefPart, dc: Int, dr: Int) String:
	var col = p.col
	var row = p.row
	if not p.ac: col += dc
	if not p.ar: row += dr
	if col < 0 or col > 25 or row < 1 or row > 999: return ""
	return (if p.ac: "$" else: "") + col_name(col) + (if p.ar: "$" else: "") + "{row}"

fn shift_formula(src: String, dc: Int, dr: Int) String:
	lx := lex(src)
	if not lx.ok: return src.clone()
	b := src.as_bytes()
	var out = ""
	var prev = 0
	for t in lx.toks:
		if t.kind == 2 and t.p1.ok:
			out = out + sub(b, prev, t.start)
			r := shift_ref(t.p1, dc, dr)
			out = out + (if r == "": "#REF!" else: r)
			prev = t.end
		else if t.kind == 3 and t.p1.ok and t.p2.ok:
			out = out + sub(b, prev, t.start)
			r1 := shift_ref(t.p1, dc, dr)
			r2 := shift_ref(t.p2, dc, dr)
			if r1 == "" or r2 == "": out = out + "#REF!"
			else: out = out + r1 + ":" + r2
			prev = t.end
	out = out + sub(b, prev, b.length())
	return out

fn csv_field(f: String) String:
	var need = f.contains(",") or f.contains("\"") or f.contains("\n") or f.contains("\r")
	if f.starts_with(" ") or f.ends_with(" "): need = true
	if not need: return f.clone()
	return "\"" + f.replace("\"", "\"\"") + "\""

type CsvResult:
	rows: List[List[String]]
	cols: Int

fn parse_csv(text: String) CsvResult:
	b := text.as_bytes()
	var rows = List[List[String]]()
	var cur = List[String]()
	var field = ""
	var seg = 0
	var inq = false
	var has = false
	var maxc = 0
	var i = 0
	n := b.length()
	// build field incrementally using byte segments
	while i < n:
		c := byte(b, i)
		if inq:
			if c == 34:
				field = field + sub(b, seg, i)
				if byte(b, i + 1) == 34:
					field = field + "\""
					i += 2
					seg = i
					continue
				inq = false
				i += 1
				seg = i
				continue
			i += 1
			continue
		if c == 34:
			field = field + sub(b, seg, i)
			inq = true
			has = true
			i += 1
			seg = i
			continue
		if c == 44:
			field = field + sub(b, seg, i)
			cur.append(field.clone())
			field = ""
			has = true
			i += 1
			seg = i
			continue
		if c == 10:
			field = field + sub(b, seg, i)
			if has or field != "" or cur.length() > 0:
				cur.append(field.clone())
				if cur.length() > maxc: maxc = cur.length()
				rows.append(cur)
				cur = List[String]()
			field = ""
			has = false
			i += 1
			seg = i
			continue
		if c == 13:
			field = field + sub(b, seg, i)
			i += 1
			seg = i
			continue
		has = true
		i += 1
	field = field + sub(b, seg, n)
	if has or field != "" or cur.length() > 0:
		cur.append(field.clone())
		if cur.length() > maxc: maxc = cur.length()
		rows.append(cur)
	return CsvResult(rows, maxc)

fn var Sheet.render(rc: Rect, mode: Int, csv: Bool) List[String]:
	var lines = List[String]()
	for r in rc.r1..(rc.r2 + 1):
		var fields = List[String]()
		for c in rc.c1..(rc.c2 + 1):
			idx := cell_idx(c, r)
			var f = ""
			if mode == 1:
				f = self.raw[idx].clone()
			else:
				if self.kind[idx] != 0: f = disp(self.vals[idx])
			if csv: fields.append(csv_field(f))
			else: fields.append(f)
		lines.append(fields.join(if csv: "," else: " | "))
	return lines

fn var Sheet.default_rect() Rect:
	var mc = -1
	var mr = 0
	for idx in 0..self.kind.length():
		if self.kind[idx] != 0:
			c := idx % 26
			r := idx / 26 + 1
			if c > mc: mc = c
			if r > mr: mr = r
	return Rect(mc >= 0, 0, 1, mc, mr)

fn var Sheet.set_cmd(line: String, var out: List[String]) Unit:
	toks := tokens_of(line)
	if toks.length() < 2:
		out.append("error: usage: set CELL VALUE")
		return
	cp := parse_cellref(toks[1])
	if not cp.ok:
		out.append("error: bad cell reference '{toks[1]}'")
		return
	val := rest_after(line, 2)
	idx := cell_idx(cp.col, cp.row)
	self.assign(idx, val)
	var ch = List[Int]()
	ch.append(idx)
	n := self.recalc(ch)
	out.append("recalc {n}")

fn var Sheet.run(lines: List[String]) List[String]:
	var out = List[String]()
	var li = 0
	while li < lines.length():
		raw := lines[li]
		li += 1
		line := raw.trim_end()
		lt := line.trim()
		if lt == "" or lt.starts_with("#"): continue
		out.append("> " + line)
		toks := tokens_of(line)
		cmd := toks[0]
		nargs := toks.length() - 1
		if cmd == "set":
			self.set_cmd(line, var out)
		else if cmd == "clear":
			if nargs != 1:
				out.append("error: usage: clear CELL")
				continue
			cp := parse_cellref(toks[1])
			if not cp.ok:
				out.append("error: bad cell reference '{toks[1]}'")
				continue
			idx := cell_idx(cp.col, cp.row)
			self.assign(idx, "")
			var ch = List[Int]()
			ch.append(idx)
			n := self.recalc(ch)
			out.append("recalc {n}")
		else if cmd == "get" or cmd == "show" or cmd == "precedents" or cmd == "dependents":
			if nargs != 1:
				out.append("error: usage: {cmd} CELL")
				continue
			cp := parse_cellref(toks[1])
			if not cp.ok:
				out.append("error: bad cell reference '{toks[1]}'")
				continue
			idx := cell_idx(cp.col, cp.row)
			if cmd == "get":
				if self.kind[idx] == 0: out.append("(empty)")
				else: out.append(disp(self.vals[idx]))
			else if cmd == "show":
				name := cell_name(idx)
				if self.kind[idx] == 0: out.append(name + ": (empty)")
				else if self.kind[idx] == 1: out.append(name + ": " + self.raw[idx])
				else: out.append(name + ": " + self.raw[idx] + " => " + disp(self.vals[idx]))
			else if cmd == "precedents":
				var ps = List[Int]()
				for q in self.precs[idx]: ps.append(q)
				out.append(name_list(ps))
			else:
				var seen = Set[Int]()
				var queue = List[Int]()
				queue.append(idx)
				var qi = 0
				while qi < queue.length():
					c := queue[qi]
					qi += 1
					for d in self.deps[c]:
						if not seen.contains(d):
							seen.add(d)
							queue.append(d)
				var ps = List[Int]()
				for q in seen: ps.append(q)
				out.append(name_list(ps))
		else if cmd == "print" or cmd == "export":
			self.print_cmd(cmd, toks, var out)
		else if cmd == "import":
			// consume block
			var blk = List[String]()
			while li < lines.length():
				l2 := lines[li]
				li += 1
				if l2 == ".": break
				blk.append(l2.clone())
			if nargs != 1:
				out.append("error: usage: import CELL")
				continue
			cp := parse_cellref(toks[1])
			if not cp.ok:
				out.append("error: bad cell reference '{toks[1]}'")
				continue
			csv := parse_csv(blk.join("\n"))
			nr := csv.rows.length()
			if nr > 0 and (cp.row + nr - 1 > 999 or cp.col + csv.cols > 26):
				out.append("error: import out of range")
				continue
			var ch = List[Int]()
			for ri in 0..nr:
				row := csv.rows[ri]
				for ci in 0..row.length():
					idx := cell_idx(cp.col + ci, cp.row + ri)
					self.assign(idx, row[ci].trim())
					ch.append(idx)
			n := self.recalc(ch)
			out.append("imported {nr} rows, {csv.cols} columns; recalc {n}")
		else if cmd == "copy":
			if nargs != 2:
				out.append("error: usage: copy SRC DST")
				continue
			sp := parse_cellref(toks[1])
			if not sp.ok:
				out.append("error: bad cell reference '{toks[1]}'")
				continue
			rc := parse_rect(toks[2])
			if not rc.ok:
				out.append("error: bad range '{toks[2]}'")
				continue
			sidx := cell_idx(sp.col, sp.row)
			skind := self.kind[sidx]
			sraw := self.raw[sidx].clone()
			var ch = List[Int]()
			for r in rc.r1..(rc.r2 + 1):
				for c in rc.c1..(rc.c2 + 1):
					idx := cell_idx(c, r)
					if skind == 2:
						txt := "=" + shift_formula(sraw.view(1, sraw.length()), c - sp.col, r - sp.row)
						self.assign(idx, txt)
					else:
						self.assign(idx, sraw)
					ch.append(idx)
			n := self.recalc(ch)
			out.append("recalc {n}")
		else if cmd == "stats":
			var cells = 0
			var forms = 0
			for k in self.kind:
				if k != 0: cells += 1
				if k == 2: forms += 1
			out.append("cells {cells} formulas {forms} evals {self.evals}")
		else:
			out.append("error: unknown command '{cmd}'")
	return out

fn name_list(ps: List[Int]) String:
	if ps.length() == 0: return "(none)"
	var xs = List[Int]()
	for q in ps: xs.append(q)
	xs.sort(fn a, b: a.compare(b))
	var names = List[String]()
	for q in xs: names.append(cell_name(q))
	return names.join(" ")

fn var Sheet.print_cmd(cmd: String, toks: List[String], var out: List[String]) Unit:
	isexp := cmd == "export"
	var mode = 0
	var modeset = false
	var rangetxt = ""
	var haverange = false
	var usage = false
	for k in 1..toks.length():
		a := toks[k]
		if a == "formulas" or a == "values":
			if modeset: usage = true
			modeset = true
			if a == "formulas":
				mode = 1
				if not isexp: usage = true
		else if not haverange:
			haverange = true
			rangetxt = a.clone()
		else:
			usage = true
	if usage:
		if isexp: out.append("error: usage: export [formulas] [RANGE]")
		else: out.append("error: usage: print [RANGE]")
		return
	var rc = self.default_rect()
	if haverange:
		rc = parse_rect(rangetxt)
		if not rc.ok:
			out.append("error: bad range '{rangetxt}'")
			return
	else:
		if not rc.ok:
			out.append("(empty sheet)")
			return
	for l in self.render(rc, mode, isexp): out.append(l)

fn main() Unit!:
	bs := read_all(stdin())?
	text := bs.decode_utf8().get("")
	parts := text.split("\n")
	var lines = List[String]()
	for k in 0..parts.length():
		if k == parts.length() - 1 and parts[k] == "": break
		lines.append(parts[k].clone())
	var s = new_sheet()
	out := s.run(lines)
	if out.length() > 0:
		print(out.join("\n"))
