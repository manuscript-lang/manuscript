import floor, pow, sqrt from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type V:
	t: Int = 0
	n: Float = 0.0
	s: String = ""

type Node:
	k: Int = 0
	n: Float = 0.0
	s: String = ""
	a: Int = 0
	b: Int = 0
	c: Int = 0
	d: Int = 0
	args: List[Int] = []

type RefT:
	end: Int = 0
	col: Int = -1
	row: Int = -1
	ca: Bool = false
	ra: Bool = false

type Tok:
	k: Int = 0
	s: String = ""
	n: Float = 0.0
	pos: Int = 0
	end: Int = 0
	r1: RefT = RefT()
	r2: RefT = RefT()

type Item:
	v: V
	direct: Bool

type Rect:
	ok: Bool = false
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0

LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn bytes_of(s: String) List[Int]:
	var out = List[Int]()
	b := s.as_bytes()
	for i in 0..b.length():
		out.append(b.get(i).to_int())
	return out

fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_alpha(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
fn is_ws(c: Int) Bool: c == 32 or c == 9 or c == 10 or c == 11 or c == 12 or c == 13

fn idx_of(col: Int, row: Int) Int: (row - 1) * 26 + col
fn cell_name(idx: Int) String:
	col := idx % 26
	row := idx / 26 + 1
	return "{LETTERS.view(col, col + 1)}{row}"

fn mkerr(s: String) V: V(t: 4, s: s)
fn mkbool(b: Bool) V: V(t: 3, n: if b: 1.0 else: 0.0)
fn mkstr(s: String) V: V(t: 2, s: s)
fn mknum(x: Float) V:
	if not x.is_finite(): return V(t: 4, s: "#NUM!")
	return V(t: 1, n: x)

// ---------- number grammar / formatting ----------

fn parse_num(s: String) Float?:
	b := bytes_of(s)
	n := b.length()
	var i = 0
	var neg = false
	if i < n and (b[i] == 43 or b[i] == 45):
		if b[i] == 45: neg = true
		i += 1
	ds := i
	while i < n and is_digit(b[i]): i += 1
	var ip = s.view(ds, i).clone()
	var fp = ""
	var nd = i - ds
	if i < n and b[i] == 46:
		i += 1
		fs := i
		while i < n and is_digit(b[i]): i += 1
		fp = s.view(fs, i).clone()
		nd += i - fs
	if nd == 0: return none
	var ex = ""
	if i < n and (b[i] == 101 or b[i] == 69):
		i += 1
		var sg = ""
		if i < n and (b[i] == 43 or b[i] == 45):
			if b[i] == 45: sg = "-"
			i += 1
		es := i
		while i < n and is_digit(b[i]): i += 1
		if i == es: return none
		ex = "e{sg}{s.view(es, i)}"
	if i != n: return none
	if ip == "": ip = "0"
	if fp == "": fp = "0"
	sign := if neg: "-" else: ""
	r := "{sign}{ip}.{fp}{ex}".parse_float()
	if x := r:
		if x.is_finite(): return x
	return none

fn big_fmt(x: Float) String:
	neg := x < 0.0
	var m = if neg: -x else: x
	var k = 0
	while m >= 9007199254740992.0:
		m = m / 2.0
		k += 1
	var digits = List[Int]()
	var mi = m.truncate_to_int().get(0)
	while mi > 0:
		digits.append(mi % 10)
		mi = mi / 10
	for _j in 0..k:
		var carry = 0
		for q in 0..digits.length():
			v := digits[q] * 2 + carry
			digits[q] = v % 10
			carry = v / 10
		if carry > 0: digits.append(carry)
	var out = if neg: "-" else: ""
	var q = digits.length() - 1
	while q >= 0:
		out += "{digits[q]}"
		q -= 1
	return out

fn fmt_num(x: Float) String:
	if x == 0.0: return "0"
	a := if x < 0.0: -x else: x
	if a >= 1e21: return big_fmt(x)
	s := x.to_fixed(10)
	b := bytes_of(s)
	var e = b.length()
	while e > 0 and b[e - 1] == 48: e -= 1
	if e > 0 and b[e - 1] == 46: e -= 1
	r := s.view(0, e).clone()
	if r == "-0" or r == "": return "0"
	return r

fn sform(v: V) String:
	if v.t == 0: return ""
	if v.t == 1: return fmt_num(v.n)
	if v.t == 3: return if v.n != 0.0: "TRUE" else: "FALSE"
	return v.s.clone()

// ---------- coercion ----------

fn cnum(v: V) V:
	if v.t == 1: return v.clone()
	if v.t == 0: return V(t: 1, n: 0.0)
	if v.t == 3: return V(t: 1, n: v.n)
	if v.t == 4: return v.clone()
	if x := parse_num(v.s.trim()): return V(t: 1, n: x)
	return mkerr("#VALUE!")

fn cbool(v: V) V:
	if v.t == 3: return v.clone()
	if v.t == 0: return mkbool(false)
	if v.t == 1: return mkbool(v.n != 0.0)
	if v.t == 4: return v.clone()
	u := v.s.upper()
	if u == "TRUE": return mkbool(true)
	if u == "FALSE": return mkbool(false)
	return mkerr("#VALUE!")

fn cmp_bytes(a: String, b: String) Int:
	x := bytes_of(a)
	y := bytes_of(b)
	var i = 0
	while i < x.length() and i < y.length():
		if x[i] != y[i]: return if x[i] < y[i]: -1 else: 1
		i += 1
	if x.length() == y.length(): return 0
	return if x.length() < y.length(): -1 else: 1

fn rank(t: Int) Int:
	if t == 1: return 0
	if t == 2: return 1
	return 2

fn zero_of(t: Int) V:
	if t == 1: return V(t: 1, n: 0.0)
	if t == 2: return V(t: 2, s: "")
	return mkbool(false)

// compare two non-error values
fn cmp_vals(a0: V, b0: V) Int:
	if a0.t == 0 and b0.t == 0: return 0
	a := if a0.t == 0: zero_of(b0.t) else: a0.clone()
	b := if b0.t == 0: zero_of(a0.t) else: b0.clone()
	if a.t != b.t:
		return if rank(a.t) < rank(b.t): -1 else: 1
	if a.t == 2: return cmp_bytes(a.s, b.s)
	if a.n < b.n: return -1
	if a.n > b.n: return 1
	return 0

fn to_int(f: Float) Int:
	if f > 1e15: return 1000000000000000
	if f < -1e15: return -1000000000000000
	return f.truncate_to_int().get(0)

// ---------- lexer ----------

fn lex_ref(b: List[Int], i: Int) RefT?:
	n := b.length()
	var j = i
	var ca = false
	if j < n and b[j] == 36:
		ca = true
		j += 1
	ls := j
	while j < n and is_alpha(b[j]): j += 1
	nl := j - ls
	if nl == 0: return none
	var ra = false
	if j < n and b[j] == 36:
		ra = true
		j += 1
	ds := j
	while j < n and is_digit(b[j]): j += 1
	nd := j - ds
	if nd == 0: return none
	if j < n:
		c := b[j]
		if is_alpha(c) or is_digit(c) or c == 95 or c == 46 or c == 40 or c == 36: return none
	var col = -1
	if nl == 1:
		c := b[ls]
		if c >= 65 and c <= 90: col = c - 65
		else if c >= 97 and c <= 122: col = c - 97
	var row = -1
	if nd <= 3 and b[ds] != 48:
		var r = 0
		for q in ds..j:
			r = r * 10 + (b[q] - 48)
		row = r
	return RefT(end: j, col: col, row: row, ca: ca, ra: ra)

// kinds: 0 num 1 str 2 ref 3 range 4 #REF! 5 ident 6 op
fn lex(src: String) List[Tok]?:
	b := bytes_of(src)
	n := b.length()
	var toks = List[Tok]()
	var i = 0
	while i < n:
		c := b[i]
		if c == 32 or c == 9:
			i += 1
			continue
		if is_digit(c) or (c == 46 and i + 1 < n and is_digit(b[i + 1])):
			var j = i
			while j < n and is_digit(b[j]): j += 1
			if j < n and b[j] == 46:
				j += 1
				while j < n and is_digit(b[j]): j += 1
			if j < n and (b[j] == 101 or b[j] == 69):
				var k = j + 1
				if k < n and (b[k] == 43 or b[k] == 45): k += 1
				if k < n and is_digit(b[k]):
					while k < n and is_digit(b[k]): k += 1
					j = k
			x := parse_num(src.view(i, j))
			var val = 0.0
			if f := x: val = f
			else:
				big := 1e308
				val = big * 10.0
			toks.append(Tok(k: 0, n: val, pos: i, end: j))
			i = j
			continue
		if c == 34:
			var j = i + 1
			var closed = false
			while j < n:
				if b[j] == 34:
					if j + 1 < n and b[j + 1] == 34:
						j += 2
						continue
					closed = true
					break
				j += 1
			if not closed: return none
			raw := src.view(i + 1, j).replace("\"\"", "\"")
			toks.append(Tok(k: 1, s: raw, pos: i, end: j + 1))
			i = j + 1
			continue
		if c == 35:
			if i + 5 <= n and src.view(i, i + 5) == "#REF!":
				toks.append(Tok(k: 4, pos: i, end: i + 5))
				i += 5
				continue
			return none
		if is_alpha(c) or c == 36 or c == 95:
			if c != 95:
				if r1 := lex_ref(b, i):
					if r1.end < n and b[r1.end] == 58:
						if r2 := lex_ref(b, r1.end + 1):
							toks.append(Tok(k: 3, pos: i, end: r2.end, r1: r1.clone(), r2: r2.clone()))
							i = r2.end
							continue
					toks.append(Tok(k: 2, pos: i, end: r1.end, r1: r1.clone()))
					i = r1.end
					continue
			if c == 36: return none
			var j = i + 1
			while j < n and (is_alpha(b[j]) or is_digit(b[j]) or b[j] == 95 or b[j] == 46): j += 1
			toks.append(Tok(k: 5, s: src.view(i, j).upper(), pos: i, end: j))
			i = j
			continue
		var op = ""
		if c == 60:
			if i + 1 < n and b[i + 1] == 62: op = "<>"
			else if i + 1 < n and b[i + 1] == 61: op = "<="
			else: op = "<"
		else if c == 62:
			if i + 1 < n and b[i + 1] == 61: op = ">="
			else: op = ">"
		else if c == 43: op = "+"
		else if c == 45: op = "-"
		else if c == 42: op = "*"
		else if c == 47: op = "/"
		else if c == 94: op = "^"
		else if c == 38: op = "&"
		else if c == 61: op = "="
		else if c == 40: op = "("
		else if c == 41: op = ")"
		else if c == 44: op = ","
		else: return none
		oplen := op.length()
		toks.append(Tok(k: 6, s: op, pos: i, end: i + oplen))
		i += oplen
	return toks

// ---------- parser ----------
// node kinds: 0 num 1 str 2 bool 3 ref 4 #REF! 5 range 6 name 7 call 8 binop 9 unary

type Parser:
	toks: List[Tok]
	pos: Int = 0
	bad: Bool = false
	nodes: List[Node]

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn Parser.is_op(s: String) Bool:
	if self.pos >= self.toks.length(): return false
	return self.toks[self.pos].k == 6 and self.toks[self.pos].s == s

fn var Parser.parse_cmp() Int:
	var left = self.parse_cat()
	while not self.bad:
		var op = ""
		for o in ["=", "<>", "<=", ">=", "<", ">"]:
			if self.is_op(o): op = o
		if op == "": break
		self.pos += 1
		right := self.parse_cat()
		left = self.add(Node(k: 8, s: op, a: left, b: right))
	return left

fn var Parser.parse_cat() Int:
	var left = self.parse_add()
	while not self.bad and self.is_op("&"):
		self.pos += 1
		right := self.parse_add()
		left = self.add(Node(k: 8, s: "&", a: left, b: right))
	return left

fn var Parser.parse_add() Int:
	var left = self.parse_mul()
	while not self.bad and (self.is_op("+") or self.is_op("-")):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		right := self.parse_mul()
		left = self.add(Node(k: 8, s: op, a: left, b: right))
	return left

fn var Parser.parse_mul() Int:
	var left = self.parse_unary()
	while not self.bad and (self.is_op("*") or self.is_op("/")):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		right := self.parse_unary()
		left = self.add(Node(k: 8, s: op, a: left, b: right))
	return left

fn var Parser.parse_unary() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		inner := self.parse_unary()
		return self.add(Node(k: 9, s: op, a: inner))
	return self.parse_pow()

fn var Parser.parse_pow() Int:
	base := self.parse_primary()
	if not self.bad and self.is_op("^"):
		self.pos += 1
		ex := self.parse_pow_operand()
		return self.add(Node(k: 8, s: "^", a: base, b: ex))
	return base

fn var Parser.parse_pow_operand() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		inner := self.parse_pow_operand()
		return self.add(Node(k: 9, s: op, a: inner))
	return self.parse_pow()

fn var Parser.parse_primary() Int:
	if self.bad: return 0
	if self.pos >= self.toks.length():
		self.bad = true
		return 0
	t := self.toks[self.pos].clone()
	if t.k == 0:
		self.pos += 1
		return self.add(Node(k: 0, n: t.n))
	if t.k == 1:
		self.pos += 1
		return self.add(Node(k: 1, s: t.s.clone()))
	if t.k == 2:
		self.pos += 1
		valid := t.r1.col >= 0 and t.r1.row >= 1
		if not valid: return self.add(Node(k: 4))
		return self.add(Node(k: 3, a: t.r1.col, b: t.r1.row))
	if t.k == 3:
		self.pos += 1
		valid := t.r1.col >= 0 and t.r1.row >= 1 and t.r2.col >= 0 and t.r2.row >= 1
		return self.add(Node(k: 5, n: if valid: 1.0 else: 0.0, a: t.r1.col, b: t.r1.row, c: t.r2.col, d: t.r2.row))
	if t.k == 4:
		self.pos += 1
		return self.add(Node(k: 4))
	if t.k == 5:
		self.pos += 1
		if self.is_op("("):
			self.pos += 1
			var args = List[Int]()
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.parse_cmp()
					if self.bad: return 0
					args.append(a)
					if self.is_op(","):
						self.pos += 1
						continue
					if self.is_op(")"):
						self.pos += 1
						break
					self.bad = true
					return 0
			return self.add(Node(k: 7, s: t.s.clone(), args: args))
		if t.s == "TRUE": return self.add(Node(k: 2, n: 1.0))
		if t.s == "FALSE": return self.add(Node(k: 2, n: 0.0))
		return self.add(Node(k: 6))
	if t.k == 6 and t.s == "(":
		self.pos += 1
		inner := self.parse_cmp()
		if self.bad: return 0
		if self.is_op(")"):
			self.pos += 1
			return inner
		self.bad = true
		return 0
	self.bad = true
	return 0

// parse; returns nodes and root (-1 on error)
type Parsed:
	nodes: List[Node]
	root: Int

fn parse_formula(src: String) Parsed:
	toks := lex(src)
	if tl := toks:
		var p = Parser(toks: tl, nodes: [])
		root := p.parse_cmp()
		if p.bad or p.pos != p.toks.length(): return Parsed(nodes: [], root: -1)
		return Parsed(nodes: p.nodes.clone(), root: root)
	return Parsed(nodes: [], root: -1)

fn collect_prec(nodes: List[Node], i: Int, var out: List[Int], var seen: Set[Int]) Unit:
	k := nodes[i].k
	if k == 3:
		x := idx_of(nodes[i].a, nodes[i].b)
		if not seen.contains(x):
			seen.add(x)
			out.append(x)
	else if k == 5 and nodes[i].n != 0.0:
		r := norm_rect(nodes[i].a, nodes[i].b, nodes[i].c, nodes[i].d)
		for row in r.r1..r.r2 + 1:
			for col in r.c1..r.c2 + 1:
				x := idx_of(col, row)
				if not seen.contains(x):
					seen.add(x)
					out.append(x)
	else if k == 8:
		collect_prec(nodes, nodes[i].a, var out, var seen)
		collect_prec(nodes, nodes[i].b, var out, var seen)
	else if k == 9:
		collect_prec(nodes, nodes[i].a, var out, var seen)
	else if k == 7:
		nm := nodes[i].s
		if nm == "ROW" or nm == "COLUMN": return
		for a in nodes[i].args:
			collect_prec(nodes, a, var out, var seen)

fn norm_rect(c1: Int, r1: Int, c2: Int, r2: Int) Rect:
	return Rect(ok: true, c1: if c1 < c2: c1 else: c2, r1: if r1 < r2: r1 else: r2, c2: if c1 < c2: c2 else: c1, r2: if r1 < r2: r2 else: r1)

// ---------- evaluation ----------

fn collect_items(vals: List[V], nodes: List[Node], args: List[Int]) List[Item]:
	var items = List[Item]()
	for a in args:
		nd := nodes[a]
		if nd.k == 5:
			if nd.n == 0.0:
				items.append(Item(v: mkerr("#REF!"), direct: true))
			else:
				r := norm_rect(nd.a, nd.b, nd.c, nd.d)
				for row in r.r1..r.r2 + 1:
					for col in r.c1..r.c2 + 1:
						items.append(Item(v: vals[idx_of(col, row)].clone(), direct: false))
		else:
			items.append(Item(v: eval(vals, nodes, a), direct: true))
	return items

fn agg(vals: List[V], nodes: List[Node], name: String, args: List[Int]) V:
	if args.length() == 0: return mkerr("#VALUE!")
	items := collect_items(vals, nodes, args)
	var xs = List[Float]()
	for it in items:
		if it.v.t == 4: return it.v.clone()
		if it.direct:
			c := cnum(it.v)
			if c.t == 4: return c
			xs.append(c.n)
		else if it.v.t == 1:
			xs.append(it.v.n)
	if name == "SUM":
		var acc = 0.0
		for x in xs: acc += x
		return mknum(acc)
	if name == "PRODUCT":
		if xs.length() == 0: return V(t: 1, n: 0.0)
		var acc = 1.0
		for x in xs: acc *= x
		return mknum(acc)
	if name == "AVERAGE":
		if xs.length() == 0: return mkerr("#DIV/0!")
		var acc = 0.0
		for x in xs: acc += x
		return mknum(acc / xs.length().to_float())
	if name == "MIN" or name == "MAX":
		if xs.length() == 0: return V(t: 1, n: 0.0)
		var m = xs[0]
		for x in xs:
			if name == "MIN" and x < m: m = x
			if name == "MAX" and x > m: m = x
		return V(t: 1, n: m)
	// MEDIAN
	if xs.length() == 0: return mkerr("#NUM!")
	xs.sort(fn a, b: a.compare(b))
	h := xs.length() / 2
	if xs.length() % 2 == 1: return mknum(xs[h])
	return mknum((xs[h - 1] + xs[h]) / 2.0)

fn is_rangeish(nodes: List[Node], i: Int) Bool: nodes[i].k == 5

fn cs_sub(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b:
		out += cs[i]
		i += 1
	return out

fn math_round(x: Float) Float:
	a := if x < 0.0: -x else: x
	f := floor(a)
	r := if a - f >= 0.5: f + 1.0 else: f
	return if x < 0.0: -r else: r

fn eval_binary(vals: List[V], nodes: List[Node], i: Int) V:
	op := nodes[i].s.clone()
	l := eval(vals, nodes, nodes[i].a)
	r := eval(vals, nodes, nodes[i].b)
	if op == "&":
		if l.t == 4: return l
		if r.t == 4: return r
		return mkstr(sform(l) + sform(r))
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if l.t == 4: return l
		if r.t == 4: return r
		c := cmp_vals(l, r)
		if op == "=": return mkbool(c == 0)
		if op == "<>": return mkbool(c != 0)
		if op == "<": return mkbool(c < 0)
		if op == "<=": return mkbool(c <= 0)
		if op == ">": return mkbool(c > 0)
		return mkbool(c >= 0)
	a := cnum(l)
	if a.t == 4: return a
	b := cnum(r)
	if b.t == 4: return b
	if op == "+": return mknum(a.n + b.n)
	if op == "-": return mknum(a.n - b.n)
	if op == "*": return mknum(a.n * b.n)
	if op == "/":
		if b.n == 0.0: return mkerr("#DIV/0!")
		return mknum(a.n / b.n)
	return mknum(pow(a.n, b.n))

fn eval(vals: List[V], nodes: List[Node], i: Int) V:
	k := nodes[i].k
	if k == 0: return mknum(nodes[i].n)
	if k == 1: return mkstr(nodes[i].s.clone())
	if k == 2: return mkbool(nodes[i].n != 0.0)
	if k == 3: return vals[idx_of(nodes[i].a, nodes[i].b)].clone()
	if k == 4: return mkerr("#REF!")
	if k == 5:
		if nodes[i].n == 0.0: return mkerr("#REF!")
		return mkerr("#VALUE!")
	if k == 6: return mkerr("#NAME?")
	if k == 8: return eval_binary(vals, nodes, i)
	if k == 9:
		v := eval(vals, nodes, nodes[i].a)
		c := cnum(v)
		if c.t == 4: return c
		if nodes[i].s == "-": return mknum(-c.n)
		return c
	return eval_call(vals, nodes, i)

fn eval_call(vals: List[V], nodes: List[Node], i: Int) V:
	name := nodes[i].s.clone()
	args := nodes[i].args.clone()
	na := args.length()
	if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN":
		return agg(vals, nodes, name, args)
	if name == "COUNT" or name == "COUNTA":
		if na == 0: return mkerr("#VALUE!")
		items := collect_items(vals, nodes, args)
		var cnt = 0
		for it in items:
			if name == "COUNT" and it.v.t == 1: cnt += 1
			if name == "COUNTA" and it.v.t != 0: cnt += 1
		return V(t: 1, n: cnt.to_float())
	if name == "IF":
		if na < 2 or na > 3: return mkerr("#VALUE!")
		c := cbool(eval(vals, nodes, args[0]))
		if c.t == 4: return c
		if c.n != 0.0: return eval(vals, nodes, args[1])
		if na == 3: return eval(vals, nodes, args[2])
		return mkbool(false)
	if name == "IFERROR":
		if na != 2: return mkerr("#VALUE!")
		a := eval(vals, nodes, args[0])
		if a.t == 4: return eval(vals, nodes, args[1])
		return a
	if name == "CHOOSE":
		if na < 2: return mkerr("#VALUE!")
		c := cnum(eval(vals, nodes, args[0]))
		if c.t == 4: return c
		f := to_int(floor(c.n))
		if f < 1 or f > na - 1: return mkerr("#VALUE!")
		return eval(vals, nodes, args[f])
	if name == "AND" or name == "OR":
		if na == 0: return mkerr("#VALUE!")
		items := collect_items(vals, nodes, args)
		var took = false
		var acc = name == "AND"
		for it in items:
			if it.v.t == 4: return it.v.clone()
			if not it.direct and (it.v.t == 2 or it.v.t == 0): continue
			b := cbool(it.v)
			if b.t == 4: return b
			took = true
			if name == "AND": acc = acc and b.n != 0.0
			else: acc = acc or b.n != 0.0
		if not took: return mkerr("#VALUE!")
		return mkbool(acc)
	if name == "NOT":
		if na != 1: return mkerr("#VALUE!")
		b := cbool(eval(vals, nodes, args[0]))
		if b.t == 4: return b
		return mkbool(b.n == 0.0)
	if name == "ABS" or name == "INT" or name == "SQRT":
		if na != 1: return mkerr("#VALUE!")
		c := cnum(eval(vals, nodes, args[0]))
		if c.t == 4: return c
		if name == "ABS": return V(t: 1, n: if c.n < 0.0: -c.n else: c.n)
		if name == "INT": return mknum(floor(c.n))
		if c.n < 0.0: return mkerr("#NUM!")
		return mknum(sqrt(c.n))
	if name == "POW" or name == "MOD":
		if na != 2: return mkerr("#VALUE!")
		l := eval(vals, nodes, args[0])
		r := eval(vals, nodes, args[1])
		a := cnum(l)
		if a.t == 4: return a
		b := cnum(r)
		if b.t == 4: return b
		if name == "POW": return mknum(pow(a.n, b.n))
		if b.n == 0.0: return mkerr("#DIV/0!")
		return mknum(a.n - b.n * floor(a.n / b.n))
	if name == "ROUND":
		if na < 1 or na > 2: return mkerr("#VALUE!")
		l := eval(vals, nodes, args[0])
		var dv = V(t: 1, n: 0.0)
		if na == 2: dv = eval(vals, nodes, args[1])
		a := cnum(l)
		if a.t == 4: return a
		d := cnum(dv)
		if d.t == 4: return d
		dt := d.n.truncate_to_int().get(100)
		if dt > 15 or dt < -15: return mkerr("#NUM!")
		p := pow(10.0, dt.to_float())
		return mknum(math_round(a.n * p) / p)
	if name == "LEN" or name == "UPPER" or name == "LOWER" or name == "TRIM":
		if na != 1: return mkerr("#VALUE!")
		v := eval(vals, nodes, args[0])
		if v.t == 4: return v
		s := sform(v)
		if name == "LEN": return V(t: 1, n: s.scalar_length().to_float())
		if name == "TRIM":
			var out = ""
			var pend = false
			for ch in s.chars():
				bb := bytes_of(ch)
				if bb.length() == 1 and is_ws(bb[0]):
					pend = true
					continue
				if pend and out != "": out += " "
				pend = false
				out += ch
			return mkstr(out)
		var out = ""
		for ch in s.chars():
			bb := bytes_of(ch)
			if bb.length() == 1 and is_alpha(bb[0]):
				out += if name == "UPPER": ch.upper() else: ch.lower()
			else: out += ch
		return mkstr(out)
	if name == "LEFT" or name == "RIGHT":
		if na < 1 or na > 2: return mkerr("#VALUE!")
		v := eval(vals, nodes, args[0])
		if v.t == 4: return v
		var cnt = 1
		if na == 2:
			c := cnum(eval(vals, nodes, args[1]))
			if c.t == 4: return c
			cnt = to_int(floor(c.n))
		if cnt < 0: return mkerr("#VALUE!")
		cs := sform(v).chars()
		len := cs.length()
		if cnt > len: cnt = len
		if name == "LEFT": return mkstr(cs_sub(cs, 0, cnt))
		return mkstr(cs_sub(cs, len - cnt, len))
	if name == "MID":
		if na != 3: return mkerr("#VALUE!")
		v := eval(vals, nodes, args[0])
		s0 := cnum(eval(vals, nodes, args[1]))
		l0 := cnum(eval(vals, nodes, args[2]))
		if v.t == 4: return v
		if s0.t == 4: return s0
		if l0.t == 4: return l0
		st := to_int(floor(s0.n))
		ln := to_int(floor(l0.n))
		if st < 1 or ln < 0: return mkerr("#VALUE!")
		cs := sform(v).chars()
		if st > cs.length(): return mkstr("")
		var e = st - 1 + ln
		if e > cs.length(): e = cs.length()
		return mkstr(cs_sub(cs, st - 1, e))
	if name == "CONCAT":
		if na == 0: return mkerr("#VALUE!")
		items := collect_items(vals, nodes, args)
		var out = ""
		for it in items:
			if it.v.t == 4: return it.v.clone()
			out += sform(it.v)
		return mkstr(out)
	if name == "SUBSTITUTE":
		if na != 3: return mkerr("#VALUE!")
		a := eval(vals, nodes, args[0])
		b := eval(vals, nodes, args[1])
		c := eval(vals, nodes, args[2])
		if a.t == 4: return a
		if b.t == 4: return b
		if c.t == 4: return c
		old := sform(b)
		if old == "": return mkstr(sform(a))
		return mkstr(sform(a).replace(old, sform(c)))
	if name == "VALUE":
		if na != 1: return mkerr("#VALUE!")
		return cnum(eval(vals, nodes, args[0]))
	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if na != 1: return mkerr("#VALUE!")
		v := eval(vals, nodes, args[0])
		if name == "ISERROR": return mkbool(v.t == 4)
		if name == "ISBLANK": return mkbool(v.t == 0)
		if name == "ISNUMBER": return mkbool(v.t == 1)
		return mkbool(v.t == 2)
	if name == "ROW" or name == "COLUMN":
		if na != 1: return mkerr("#VALUE!")
		nd := nodes[args[0]]
		if nd.k == 4: return mkerr("#REF!")
		if nd.k == 3 or nd.k == 5:
			if nd.k == 5 and nd.n == 0.0: return mkerr("#REF!")
			if name == "ROW": return V(t: 1, n: nd.b.to_float())
			return V(t: 1, n: (nd.a + 1).to_float())
		return mkerr("#VALUE!")
	if name == "INDEX":
		if na < 2 or na > 3: return mkerr("#VALUE!")
		nd := nodes[args[0]]
		if nd.k != 5: return mkerr("#VALUE!")
		if nd.n == 0.0: return mkerr("#REF!")
		r := norm_rect(nd.a, nd.b, nd.c, nd.d)
		h := r.r2 - r.r1 + 1
		w := r.c2 - r.c1 + 1
		x := cnum(eval(vals, nodes, args[1]))
		if x.t == 4: return x
		var y = V(t: 1, n: 1.0)
		if na == 3: y = cnum(eval(vals, nodes, args[2]))
		if y.t == 4: return y
		var ri = 1
		var ci = 1
		if na == 3:
			ri = to_int(floor(x.n))
			ci = to_int(floor(y.n))
		else if h == 1:
			ci = to_int(floor(x.n))
		else:
			ri = to_int(floor(x.n))
		if ri < 1 or ri > h or ci < 1 or ci > w: return mkerr("#REF!")
		return vals[idx_of(r.c1 + ci - 1, r.r1 + ri - 1)].clone()
	if name == "COUNTIF":
		if na != 2: return mkerr("#VALUE!")
		nd := nodes[args[0]]
		if nd.k != 5: return mkerr("#VALUE!")
		if nd.n == 0.0: return mkerr("#REF!")
		crit := eval(vals, nodes, args[1])
		if crit.t == 4: return crit
		var op = "="
		var operand = crit.clone()
		if crit.t == 2:
			var rest = crit.s.clone()
			for o in [">=", "<=", "<>", ">", "<", "="]:
				if rest.starts_with(o):
					op = o.clone()
					rest = rest.view(o.length(), rest.length()).clone()
					break
			if x := parse_num(rest): operand = V(t: 1, n: x)
			else: operand = V(t: 2, s: rest)
		r := norm_rect(nd.a, nd.b, nd.c, nd.d)
		var cnt = 0
		for row in r.r1..r.r2 + 1:
			for col in r.c1..r.c2 + 1:
				v := vals[idx_of(col, row)]
				if v.t == operand.t:
					c := cmp_vals(v, operand)
					ok := if op == "=": c == 0 else if op == "<>": c != 0 else if op == "<": c < 0 else if op == "<=": c <= 0 else if op == ">": c > 0 else: c >= 0
					if ok: cnt += 1
				else if op == "<>" and v.t != 0:
					cnt += 1
		return V(t: 1, n: cnt.to_float())
	return mkerr("#NAME?")

// ---------- sheet ----------

type Sheet:
	raw: List[String]
	kind: List[Int]
	vals: List[V]
	nodes: List[List[Node]]
	root: List[Int]
	precs: List[List[Int]]
	deps: List[List[Int]]
	mark: List[Int]
	tin: List[Int]
	low: List[Int]
	onst: List[Int]
	ep: List[Int]
	evals: Int = 0

fn new_sheet() Sheet:
	n := 26 * 999
	var s = Sheet(raw: [], kind: [], vals: [], nodes: [], root: [], precs: [], deps: [], mark: [], tin: [], low: [], onst: [], ep: [])
	for _i in 0..n:
		s.raw.append("")
		s.kind.append(0)
		s.vals.append(V())
		s.nodes.append([])
		s.root.append(-1)
		s.precs.append([])
		s.deps.append([])
		s.mark.append(0)
		s.tin.append(-1)
		s.low.append(0)
		s.onst.append(0)
		s.ep.append(0)
	return s

fn var Sheet.assign(idx: Int, value0: String) Unit:
	value := value0.trim()
	// remove old dependency edges
	for p in self.precs[idx].clone():
		pos := self.deps[p].index_of(idx)
		if q := pos: self.deps[p].remove(q)
	self.precs[idx] = []
	self.nodes[idx] = []
	self.root[idx] = -1
	if value == "":
		self.raw[idx] = ""
		self.kind[idx] = 0
		self.vals[idx] = V()
		return
	self.raw[idx] = value.clone()
	if value.starts_with("="):
		self.kind[idx] = 2
		parsed := parse_formula(value.view(1, value.length()))
		self.root[idx] = parsed.root
		self.vals[idx] = mkerr("#PARSE!")
		if parsed.root >= 0:
			var out = List[Int]()
			var seen = Set[Int]()
			collect_prec(parsed.nodes, parsed.root, var out, var seen)
			for p in out:
				self.deps[p].append(idx)
			self.precs[idx] = out
			self.nodes[idx] = parsed.nodes.clone()
		return
	self.kind[idx] = 1
	if value.starts_with("'"):
		self.vals[idx] = mkstr(value.view(1, value.length()).clone())
		return
	if x := parse_num(value):
		self.vals[idx] = V(t: 1, n: x)
		return
	u := value.upper()
	if u == "TRUE":
		self.vals[idx] = mkbool(true)
		return
	if u == "FALSE":
		self.vals[idx] = mkbool(false)
		return
	self.vals[idx] = mkstr(value.clone())

fn var Sheet.init_node(w: Int, counter: Int) Unit:
	self.tin[w] = counter
	self.low[w] = counter
	self.onst[w] = 1
	self.ep[w] = 0

fn var Sheet.eval_cell(v: Int) Unit:
	if self.root[v] < 0:
		self.vals[v] = mkerr("#PARSE!")
		return
	r := eval(self.vals, self.nodes[v], self.root[v])
	if r.t == 0:
		self.vals[v] = V(t: 1, n: 0.0)
	else:
		self.vals[v] = r

fn var Sheet.recalc(changed: List[Int]) Int:
	var queue = List[Int]()
	var aff = List[Int]()
	for c in changed:
		if self.mark[c] == 0:
			if self.kind[c] == 2:
				self.mark[c] = 2
				aff.append(c)
			else:
				self.mark[c] = 1
			queue.append(c)
	var head = 0
	while head < queue.length():
		x := queue[head]
		head += 1
		for q in 0..self.deps[x].length():
			d := self.deps[x][q]
			if self.mark[d] == 0:
				self.mark[d] = 2
				aff.append(d)
				queue.append(d)
	// Tarjan
	var counter = 0
	var stack = List[Int]()
	for root in aff:
		if self.tin[root] != -1: continue
		self.init_node(root, counter)
		counter += 1
		stack.append(root)
		var call = [root]
		while call.length() > 0:
			v := call[call.length() - 1]
			if self.ep[v] < self.precs[v].length():
				w := self.precs[v][self.ep[v]]
				self.ep[v] += 1
				if self.mark[w] != 2: continue
				if self.tin[w] == -1:
					self.init_node(w, counter)
					counter += 1
					stack.append(w)
					call.append(w)
				else if self.onst[w] == 1:
					if self.tin[w] < self.low[v]: self.low[v] = self.tin[w]
			else:
				if self.low[v] == self.tin[v]:
					var scc = List[Int]()
					while true:
						w := stack.pop().get(-1)
						self.onst[w] = 0
						scc.append(w)
						if w == v: break
					cyc := scc.length() > 1 or self.precs[v].contains(v)
					if cyc:
						for w in scc:
							self.vals[w] = mkerr("#CYCLE!")
					else:
						self.eval_cell(v)
				call.pop()
				if call.length() > 0:
					u := call[call.length() - 1]
					if self.low[v] < self.low[u]: self.low[u] = self.low[v]
	for c in aff:
		self.tin[c] = -1
		self.low[c] = 0
		self.onst[c] = 0
		self.ep[c] = 0
	for x in queue:
		self.mark[x] = 0
	self.evals += aff.length()
	return aff.length()

fn Sheet.disp(idx: Int) String: sform(self.vals[idx])

// ---------- argument parsing ----------

fn parse_cell(s: String) Int:
	b := bytes_of(s)
	n := b.length()
	if n < 2 or n > 4: return -1
	if not is_alpha(b[0]): return -1
	col := if b[0] >= 97: b[0] - 97 else: b[0] - 65
	if col > 25: return -1
	if b[1] == 48: return -1
	var row = 0
	for q in 1..n:
		if not is_digit(b[q]): return -1
		row = row * 10 + b[q] - 48
	if row < 1 or row > 999: return -1
	return idx_of(col, row)

fn parse_range(s: String) Rect:
	var a = parse_cell(s)
	var b = a
	if ci := s.index_of(":"):
		a = parse_cell(s.view(0, ci))
		b = parse_cell(s.view(ci + 1, s.length()))
	if a < 0 or b < 0: return Rect()
	return norm_rect(a % 26, a / 26 + 1, b % 26, b / 26 + 1)

fn words(s: String) List[String]:
	var out = List[String]()
	b := bytes_of(s)
	var i = 0
	while i < b.length():
		if is_ws(b[i]):
			i += 1
			continue
		j0 := i
		while i < b.length() and not is_ws(b[i]): i += 1
		out.append(s.view(j0, i).clone())
	return out

fn csv_field(s: String) String:
	b := bytes_of(s)
	var need = false
	for c in b:
		if c == 44 or c == 34 or c == 10 or c == 13: need = true
	if b.length() > 0 and (b[0] == 32 or b[b.length() - 1] == 32): need = true
	if not need: return s.clone()
	return "\"" + s.replace("\"", "\"\"") + "\""

fn parse_csv(text: String) List[List[String]]:
	var recs = List[List[String]]()
	var rec = List[String]()
	var field = ""
	var inq = false
	var consumed = false
	b := text.chars()
	var i = 0
	while i < b.length():
		c := b[i]
		if inq:
			if c == "\"":
				if i + 1 < b.length() and b[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					inq = false
			else: field += c
			i += 1
			continue
		if c == "\"":
			inq = true
			consumed = true
		else if c == ",":
			rec.append(field.clone())
			field = ""
			consumed = true
		else if c == "\n":
			if consumed:
				rec.append(field.clone())
				recs.append(rec.clone())
			rec = []
			field = ""
			consumed = false
		else if c == "\r": i += 0
		else:
			field += c
			consumed = true
		i += 1
	if consumed:
		rec.append(field.clone())
		recs.append(rec.clone())
	return recs

fn shift_ref(r: RefT, dc: Int, dr: Int) String:
	nc := if r.ca: r.col else: r.col + dc
	nr := if r.ra: r.row else: r.row + dr
	if nc < 0 or nc > 25 or nr < 1 or nr > 999: return ""
	return "{if r.ca: "$" else: ""}{LETTERS.view(nc, nc + 1)}{if r.ra: "$" else: ""}{nr}"

fn shift_formula(src: String, dc: Int, dr: Int) String:
	toks := lex(src)
	if tl := toks:
		var out = ""
		var last = 0
		for t in tl:
			if t.k == 2 and t.r1.col >= 0 and t.r1.row >= 1:
				out += src.view(last, t.pos)
				s := shift_ref(t.r1, dc, dr)
				out += if s == "": "#REF!" else: s
				last = t.end
			else if t.k == 3 and t.r1.col >= 0 and t.r1.row >= 1 and t.r2.col >= 0 and t.r2.row >= 1:
				out += src.view(last, t.pos)
				s1 := shift_ref(t.r1, dc, dr)
				s2 := shift_ref(t.r2, dc, dr)
				out += if s1 == "" or s2 == "": "#REF!" else: "{s1}:{s2}"
				last = t.end
		out += src.view(last, src.length())
		return out
	return src.clone()

// ---------- main ----------

fn rect_cells(r: Rect) List[Int]:
	var out = List[Int]()
	for row in r.r1..r.r2 + 1:
		for col in r.c1..r.c2 + 1:
			out.append(idx_of(col, row))
	return out

// ms: allow_effect std.console.write
fn out_recalc(n: Int) Unit:
	print("recalc {n}")

// ms: allow_effect std.console.write
fn do_set(var sh: Sheet, idx: Int, value: String) Unit:
	sh.assign(idx, value)
	n := sh.recalc([idx])
	out_recalc(n)

// ms: allow_effect std.console.write
fn do_print(sh: Sheet, args: List[String], is_export: Bool) Unit:
	var formulas = false
	var rng = Rect()
	var have = false
	for a in args:
		if is_export and a == "formulas":
			formulas = true
		else if is_export and a == "values":
			formulas = formulas
		else if a == "formulas" and not is_export:
			print("error: usage: print [RANGE]")
			return
		else:
			if have:
				print(if is_export: "error: usage: export [formulas] [RANGE]" else: "error: usage: print [RANGE]")
				return
			rng = parse_range(a)
			if not rng.ok:
				print("error: bad range '{a}'")
				return
			have = true
	if is_export:
		var fcount = 0
		var vcount = 0
		for a in args:
			if a == "formulas": fcount += 1
			if a == "values": vcount += 1
		if fcount + vcount > 1:
			print("error: usage: export [formulas] [RANGE]")
			return
	if not have:
		var mc = -1
		var mr = 0
		for i in 0..sh.kind.length():
			if sh.kind[i] != 0:
				if i % 26 > mc: mc = i % 26
				if i / 26 + 1 > mr: mr = i / 26 + 1
		if mc < 0:
			print("(empty sheet)")
			return
		rng = Rect(ok: true, c1: 0, r1: 1, c2: mc, r2: mr)
	for row in rng.r1..rng.r2 + 1:
		var fields = List[String]()
		for col in rng.c1..rng.c2 + 1:
			idx := idx_of(col, row)
			s := if formulas: sh.raw[idx].clone() else: sh.disp(idx)
			fields.append(if is_export: csv_field(s) else: s)
		print(fields.join(if is_export: "," else: " | "))

// ms: allow_effect std.console.write
fn do_import(var sh: Sheet, args: List[String], block: List[String]) Unit:
	if args.length() != 1:
		print("error: usage: import CELL")
		return
	start := parse_cell(args[0])
	if start < 0:
		print("error: bad cell reference '{args[0]}'")
		return
	recs := parse_csv(block.join("\n"))
	var cmax = 0
	for r in recs:
		if r.length() > cmax: cmax = r.length()
	sc := start % 26
	sr := start / 26 + 1
	if recs.length() > 0 and (sc + cmax > 26 or sr + recs.length() - 1 > 999):
		print("error: import out of range")
		return
	var changed = List[Int]()
	for ri in 0..recs.length():
		for ci in 0..recs[ri].length():
			idx := idx_of(sc + ci, sr + ri)
			sh.assign(idx, recs[ri][ci])
			changed.append(idx)
	n := sh.recalc(changed)
	print("imported {recs.length()} rows, {cmax} columns; recalc {n}")

// ms: allow_effect std.console.write
fn do_copy(var sh: Sheet, args: List[String]) Unit:
	if args.length() != 2:
		print("error: usage: copy SRC DST")
		return
	src := parse_cell(args[0])
	if src < 0:
		print("error: bad cell reference '{args[0]}'")
		return
	rng := parse_range(args[1])
	if not rng.ok:
		print("error: bad range '{args[1]}'")
		return
	kind := sh.kind[src]
	raw := sh.raw[src].clone()
	cells := rect_cells(rng)
	for d in cells:
		if kind == 0:
			sh.assign(d, "")
		else if kind == 1:
			sh.assign(d, raw)
		else:
			dc := d % 26 - src % 26
			dr := d / 26 - src / 26
			sh.assign(d, "=" + shift_formula(raw.view(1, raw.length()), dc, dr))
	n := sh.recalc(cells)
	out_recalc(n)

fn ws_index(s: String) Int:
	b := bytes_of(s)
	for i in 0..b.length():
		if is_ws(b[i]): return i
	return -1

// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().ok_or(Error("bad input"))?
	lines := text.lines()
	var sh = new_sheet()
	var i = 0
	while i < lines.length():
		line := lines[i].clone()
		i += 1
		t := line.trim()
		if t == "" or t.starts_with("#"): continue
		print("> " + line.trim_end())
		wi := ws_index(t)
		cmd := if wi < 0: t.clone() else: t.view(0, wi).clone()
		rest := if wi < 0: "" else: t.view(wi, t.length()).trim()
		args := words(rest)
		if cmd == "import":
			var block = List[String]()
			while i < lines.length():
				l := lines[i].clone()
				i += 1
				if l == ".": break
				block.append(l)
			do_import(var sh, args, block)
		else if cmd == "set":
			if args.length() == 0:
				print("error: usage: set CELL VALUE")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				print("error: bad cell reference '{args[0]}'")
				continue
			ci := ws_index(rest)
			value := if ci < 0: "" else: rest.view(ci, rest.length()).trim()
			do_set(var sh, idx, value)
		else if cmd == "clear":
			if args.length() != 1:
				print("error: usage: clear CELL")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				print("error: bad cell reference '{args[0]}'")
				continue
			do_set(var sh, idx, "")
		else if cmd == "get" or cmd == "show" or cmd == "precedents" or cmd == "dependents":
			if args.length() != 1:
				print("error: usage: {cmd} CELL")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				print("error: bad cell reference '{args[0]}'")
				continue
			if cmd == "get":
				print(if sh.kind[idx] == 0: "(empty)" else: sh.disp(idx))
			else if cmd == "show":
				nm := cell_name(idx)
				if sh.kind[idx] == 0: print("{nm}: (empty)")
				else if sh.kind[idx] == 1: print("{nm}: {sh.raw[idx]}")
				else: print("{nm}: {sh.raw[idx]} => {sh.disp(idx)}")
			else:
				var res = List[Int]()
				if cmd == "precedents":
					res = sh.precs[idx].clone()
				else:
					var seen = Set[Int]()
					var queue = [idx]
					var head = 0
					while head < queue.length():
						x := queue[head]
						head += 1
						for d in sh.deps[x]:
							if not seen.contains(d):
								seen.add(d)
								queue.append(d)
								res.append(d)
				res.sort()
				if res.length() == 0: print("(none)")
				else: print(res.map(fn x: cell_name(x)).join(" "))
		else if cmd == "copy":
			do_copy(var sh, args)
		else if cmd == "print":
			if args.length() > 1:
				print("error: usage: print [RANGE]")
				continue
			do_print(sh, args, false)
		else if cmd == "export":
			do_print(sh, args, true)
		else if cmd == "stats":
			var cells = 0
			var forms = 0
			for k in sh.kind:
				if k != 0: cells += 1
				if k == 2: forms += 1
			print("cells {cells} formulas {forms} evals {sh.evals}")
		else:
			print("error: unknown command '{cmd}'")
