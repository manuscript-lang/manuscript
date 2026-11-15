import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import pow, floor, ceil, sqrt from "@std/math/math.ms"
import from_scalars from "@std/string.ms"

// ---------- values ----------

type Val:
	kind: Int = 0
	n: Float = 0.0
	s: String = ""

fn vnum(x: Float) Val: Val(kind: 1, n: x)
fn vtext(s: String) Val: Val(kind: 2, s: s)
fn vbool(b: Bool) Val: Val(kind: 3, n: if b: 1.0 else: 0.0)
fn verr(s: String) Val: Val(kind: 4, s: s)
fn vempty() Val: Val()

fn numres(x: Float) Val:
	if x.is_finite(): return vnum(x)
	return verr("#NUM!")

// ---------- character helpers ----------

fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_letter(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
fn is_ident(c: Int) Bool: is_letter(c) or is_digit(c) or c == 95 or c == 46
fn is_wsc(c: Int) Bool: c == 32 or c == 9 or c == 10 or c == 13 or c == 11 or c == 12

fn sub(cs: List[Int], a: Int, b: Int) String:
	var out = List[Int]()
	for i in a..b:
		out.append(cs[i])
	if t := from_scalars(out):
		return t
	return ""

fn trim_ascii(s: String) String:
	cs := s.scalar_values()
	var a = 0
	var b = cs.length()
	while a < b and is_wsc(cs[a]): a += 1
	while b > a and is_wsc(cs[b - 1]): b -= 1
	return sub(cs, a, b)

fn upper_ascii(s: String) String:
	var out = List[Int]()
	for c in s.scalar_values():
		if c >= 97 and c <= 122: out.append(c - 32)
		else: out.append(c)
	if t := from_scalars(out):
		return t
	return ""

fn lower_ascii(s: String) String:
	var out = List[Int]()
	for c in s.scalar_values():
		if c >= 65 and c <= 90: out.append(c + 32)
		else: out.append(c)
	if t := from_scalars(out):
		return t
	return ""

// ---------- numbers ----------

// Parses the spreadsheet number grammar; none when it does not match or is not finite.
fn parse_num(s: String) Float?:
	cs := s.scalar_values()
	n := cs.length()
	var i = 0
	var neg = false
	if i < n and (cs[i] == 43 or cs[i] == 45):
		neg = cs[i] == 45
		i += 1
	var ip = ""
	var fp = ""
	var ex = "0"
	a := i
	while i < n and is_digit(cs[i]): i += 1
	ip = sub(cs, a, i)
	if i < n and cs[i] == 46:
		i += 1
		b := i
		while i < n and is_digit(cs[i]): i += 1
		fp = sub(cs, b, i)
	if ip.length() == 0 and fp.length() == 0: return none
	if i < n and (cs[i] == 101 or cs[i] == 69):
		i += 1
		var sign = ""
		if i < n and (cs[i] == 43 or cs[i] == 45):
			if cs[i] == 45: sign = "-"
			i += 1
		c := i
		while i < n and is_digit(cs[i]): i += 1
		if i == c: return none
		ex = sign + sub(cs, c, i)
	if i != n: return none
	if ip.length() == 0: ip = "0"
	if fp.length() == 0: fp = "0"
	text := "{ip}.{fp}e{ex}"
	if v := text.parse_float():
		if not v.is_finite(): return none
		if neg: return -v
		return v
	return none

fn digits_of(m: Int) List[Int]:
	// little-endian decimal digits
	var out = List[Int]()
	var x = m
	if x == 0: out.append(0)
	while x > 0:
		out.append(x % 10)
		x = x / 10
	return out

fn big_integer_string(x: Float) String:
	var ax = x
	var e = 0
	while ax >= 9007199254740992.0:
		ax = ax / 2.0
		e += 1
	var m = 0
	if t := ax.truncate_to_int():
		m = t
	var d = digits_of(m)
	for _k in 0..e:
		var carry = 0
		for i in 0..d.length():
			v := d[i] * 2 + carry
			d[i] = v % 10
			carry = v / 10
		if carry > 0: d.append(carry)
	var out = ""
	var i = d.length() - 1
	while i >= 0:
		out = out + "{d[i]}"
		i -= 1
	return out

fn strip_zeros(s: String) String:
	if not s.contains("."): return s.clone()
	cs := s.scalar_values()
	var b = cs.length()
	while b > 0 and cs[b - 1] == 48: b -= 1
	if b > 0 and cs[b - 1] == 46: b -= 1
	return sub(cs, 0, b)

fn fmt_num(x: Float) String:
	if x == 0.0: return "0"
	ax := x.abs()
	var s = ""
	if ax >= 1e21:
		s = big_integer_string(ax)
	else:
		s = ax.to_fixed(10)
		t := ax * 2048.0
		if t == floor(t):
			s11 := ax.to_fixed(11)
			cs := s11.scalar_values()
			n := cs.length()
			if cs[n - 1] == 53 and (cs[n - 2] - 48) % 2 == 0:
				s = sub(cs, 0, n - 1)
		s = strip_zeros(s)
	if s == "0": return "0"
	if x < 0.0: return "-" + s
	return s

fn display(v: Val) String:
	if v.kind == 0: return ""
	if v.kind == 1: return fmt_num(v.n)
	if v.kind == 3:
		if v.n != 0.0: return "TRUE"
		return "FALSE"
	return v.s.clone()

// ---------- references ----------

type Ref:
	ca: Bool = false
	ra: Bool = false
	c: Int = 0
	r: Int = 0
	ok: Bool = false
	matched: Bool = false
	end: Int = 0

fn scan_ref(cs: List[Int], i: Int) Ref:
	n := cs.length()
	var j = i
	var ca = false
	var ra = false
	if j < n and cs[j] == 36:
		ca = true
		j += 1
	ls := j
	while j < n and is_letter(cs[j]): j += 1
	lcount := j - ls
	if lcount == 0: return Ref()
	if j < n and cs[j] == 36:
		ra = true
		j += 1
	ds := j
	while j < n and is_digit(cs[j]): j += 1
	dcount := j - ds
	if dcount == 0: return Ref()
	if j < n and (is_ident(cs[j]) or cs[j] == 40 or cs[j] == 36): return Ref()
	var ok = lcount == 1 and dcount <= 3 and cs[ds] != 48
	var col = 0
	var row = 0
	if ok:
		l := cs[ls]
		if l >= 97: col = l - 97
		else: col = l - 65
		if col > 25: ok = false
		for k in ds..j:
			row = row * 10 + (cs[k] - 48)
		if row < 1 or row > 999: ok = false
	return Ref(ca: ca, ra: ra, c: col, r: row, ok: ok, matched: true, end: j)

// ---------- tokens ----------

type Tok:
	kind: Int = 0 // 0 num 1 str 2 ref 3 range 4 #REF! 5 ident 6 op
	s: String = ""
	start: Int = 0
	end: Int = 0
	a: Ref = Ref()
	b: Ref = Ref()

type Lexed:
	ok: Bool = true
	toks: List[Tok] = List[Tok]()

fn tokenize(cs: List[Int]) Lexed:
	n := cs.length()
	var toks = List[Tok]()
	var i = 0
	while i < n:
		c := cs[i]
		if c == 32 or c == 9:
			i += 1
			continue
		start := i
		if c == 34:
			var buf = List[Int]()
			i += 1
			var closed = false
			while i < n:
				if cs[i] == 34:
					if i + 1 < n and cs[i + 1] == 34:
						buf.append(34)
						i += 2
						continue
					closed = true
					i += 1
					break
				buf.append(cs[i])
				i += 1
			if not closed: return Lexed(ok: false)
			var t = ""
			if u := from_scalars(buf):
				t = u
			toks.append(Tok(kind: 1, s: t, start: start, end: i))
			continue
		if is_digit(c) or (c == 46 and i + 1 < n and is_digit(cs[i + 1])):
			while i < n and is_digit(cs[i]): i += 1
			if i < n and cs[i] == 46:
				i += 1
				while i < n and is_digit(cs[i]): i += 1
			if i < n and (cs[i] == 101 or cs[i] == 69):
				var k = i + 1
				if k < n and (cs[k] == 43 or cs[k] == 45): k += 1
				if k < n and is_digit(cs[k]):
					while k < n and is_digit(cs[k]): k += 1
					i = k
			toks.append(Tok(kind: 0, s: sub(cs, start, i), start: start, end: i))
			continue
		if is_letter(c) or c == 36 or c == 95:
			if c != 95:
				r1 := scan_ref(cs, i)
				if r1.matched:
					i = r1.end
					if i < n and cs[i] == 58:
						r2 := scan_ref(cs, i + 1)
						if r2.matched:
							i = r2.end
							toks.append(Tok(kind: 3, s: sub(cs, start, i), start: start, end: i, a: r1, b: r2))
							continue
					toks.append(Tok(kind: 2, s: sub(cs, start, i), start: start, end: i, a: r1))
					continue
			if is_letter(c) or c == 95:
				while i < n and is_ident(cs[i]): i += 1
				toks.append(Tok(kind: 5, s: sub(cs, start, i), start: start, end: i))
				continue
			return Lexed(ok: false)
		if c == 35:
			if i + 4 < n and sub(cs, i, i + 5) == "#REF!":
				i += 5
				toks.append(Tok(kind: 4, s: "#REF!", start: start, end: i))
				continue
			return Lexed(ok: false)
		if c == 60:
			if i + 1 < n and (cs[i + 1] == 61 or cs[i + 1] == 62):
				i += 2
			else: i += 1
			toks.append(Tok(kind: 6, s: sub(cs, start, i), start: start, end: i))
			continue
		if c == 62:
			if i + 1 < n and cs[i + 1] == 61: i += 2
			else: i += 1
			toks.append(Tok(kind: 6, s: sub(cs, start, i), start: start, end: i))
			continue
		if c == 43 or c == 45 or c == 42 or c == 47 or c == 94 or c == 38 or c == 61 or c == 40 or c == 41 or c == 44:
			i += 1
			toks.append(Tok(kind: 6, s: sub(cs, start, i), start: start, end: i))
			continue
		return Lexed(ok: false)
	return Lexed(ok: true, toks: toks)

// ---------- AST ----------

type Node:
	kind: Int = 0 // 0 num 1 str 2 bool 3 ref 4 range 5 #REF! 6 name 7 call 8 binop 9 unary
	num: Float = 0.0
	s: String = ""
	args: List[Int] = List[Int]()
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0
	oc: Int = 0
	orow: Int = 0
	ok: Bool = true

type Ast:
	nodes: List[Node] = List[Node]()
	root: Int = 0
	ok: Bool = false
	prec: List[Int] = List[Int]()

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = List[Node]()
	fail: Bool = false

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn Parser.is_op(s: String) Bool:
	if self.pos >= self.toks.length(): return false
	t := self.toks[self.pos]
	return t.kind == 6 and t.s == s

fn var Parser.binary(level: Int) Int:
	if level == 4: return self.unary()
	var left = self.binary(level + 1)
	if self.fail: return 0
	while true:
		if self.pos >= self.toks.length(): break
		t := self.toks[self.pos]
		if t.kind != 6: break
		var hit = false
		if level == 0:
			hit = t.s == "=" or t.s == "<>" or t.s == "<" or t.s == "<=" or t.s == ">" or t.s == ">="
		else if level == 1:
			hit = t.s == "&"
		else if level == 2:
			hit = t.s == "+" or t.s == "-"
		else:
			hit = t.s == "*" or t.s == "/"
		if not hit: break
		op := t.s.clone()
		self.pos += 1
		right := self.binary(level + 1)
		if self.fail: return 0
		var args = List[Int]()
		args.append(left)
		args.append(right)
		left = self.add(Node(kind: 8, s: op, args: args))
	return left

fn var Parser.unary() Int:
	if self.pos < self.toks.length():
		t := self.toks[self.pos]
		if t.kind == 6 and (t.s == "+" or t.s == "-"):
			op := t.s.clone()
			self.pos += 1
			operand := self.unary()
			if self.fail: return 0
			var args = List[Int]()
			args.append(operand)
			return self.add(Node(kind: 9, s: op, args: args))
	base := self.primary()
	if self.fail: return 0
	if self.is_op("^"):
		self.pos += 1
		ex := self.unary()
		if self.fail: return 0
		var args = List[Int]()
		args.append(base)
		args.append(ex)
		return self.add(Node(kind: 8, s: "^", args: args))
	return base

fn var Parser.primary() Int:
	if self.pos >= self.toks.length():
		self.fail = true
		return 0
	t := self.toks[self.pos].clone()
	self.pos += 1
	if t.kind == 0:
		v := parse_num(t.s)
		if x := v:
			return self.add(Node(kind: 0, num: x))
		return self.add(Node(kind: 0, ok: false))
	if t.kind == 1:
		return self.add(Node(kind: 1, s: t.s.clone()))
	if t.kind == 2:
		return self.add(Node(kind: 3, c1: t.a.c, r1: t.a.r, ok: t.a.ok))
	if t.kind == 3:
		ok := t.a.ok and t.b.ok
		var nd = Node(kind: 4, ok: ok)
		if ok:
			nd.c1 = if t.a.c < t.b.c: t.a.c else: t.b.c
			nd.c2 = if t.a.c < t.b.c: t.b.c else: t.a.c
			nd.r1 = if t.a.r < t.b.r: t.a.r else: t.b.r
			nd.r2 = if t.a.r < t.b.r: t.b.r else: t.a.r
		nd.oc = t.a.c
		nd.orow = t.a.r
		return self.add(nd)
	if t.kind == 4:
		return self.add(Node(kind: 5))
	if t.kind == 5:
		name := upper_ascii(t.s)
		if self.is_op("("):
			self.pos += 1
			var args = List[Int]()
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.binary(0)
					if self.fail: return 0
					args.append(a)
					if self.is_op(","):
						self.pos += 1
						continue
					if self.is_op(")"):
						self.pos += 1
						break
					self.fail = true
					return 0
			return self.add(Node(kind: 7, s: name, args: args))
		if name == "TRUE": return self.add(Node(kind: 2, num: 1.0))
		if name == "FALSE": return self.add(Node(kind: 2, num: 0.0))
		return self.add(Node(kind: 6, s: name))
	if t.kind == 6 and t.s == "(":
		inner := self.binary(0)
		if self.fail: return 0
		if self.is_op(")"):
			self.pos += 1
			return inner
		self.fail = true
		return 0
	self.fail = true
	return 0

fn cell_index(c: Int, r: Int) Int: (r - 1) * 26 + c

fn parse_formula(src: String) Ast:
	lx := tokenize(src.scalar_values())
	if not lx.ok: return Ast()
	var p = Parser(toks: lx.toks)
	root := p.binary(0)
	if p.fail or p.pos != p.toks.length(): return Ast()
	var prec = Set[Int]()
	var stack = List[Int]()
	stack.append(root)
	while stack.length() > 0:
		x := stack.pop().get(0)
		nd := p.nodes[x]
		if nd.kind == 3:
			if nd.ok: prec.add(cell_index(nd.c1, nd.r1))
		else if nd.kind == 4:
			if nd.ok:
				for r in nd.r1..(nd.r2 + 1):
					for c in nd.c1..(nd.c2 + 1):
						prec.add(cell_index(c, r))
		else if nd.kind == 7 and (nd.s == "ROW" or nd.s == "COLUMN"):
			continue
		else:
			for ch in nd.args:
				stack.append(ch)
	var pl = List[Int]()
	for x in prec.values():
		pl.append(x)
	pl.sort()
	return Ast(nodes: p.nodes, root: root, ok: true, prec: pl)

// ---------- evaluation ----------

fn to_i(x: Float) Int:
	if v := x.truncate_to_int(): return v
	return 0

fn coerce_num(v: Val) Val:
	if v.kind == 1: return v.clone()
	if v.kind == 0 or v.kind == 3: return vnum(v.n)
	if v.kind == 2:
		if x := parse_num(trim_ascii(v.s)): return vnum(x)
		return verr("#VALUE!")
	return v.clone()

fn coerce_bool(v: Val) Val:
	if v.kind == 1: return vbool(v.n != 0.0)
	if v.kind == 3: return v.clone()
	if v.kind == 0: return vbool(false)
	if v.kind == 2:
		u := upper_ascii(v.s)
		if u == "TRUE": return vbool(true)
		if u == "FALSE": return vbool(false)
		return verr("#VALUE!")
	return v.clone()

fn zero_of(k: Int) Val:
	if k == 2: return vtext("")
	if k == 3: return vbool(false)
	return vnum(0.0)

fn cmp_f(a: Float, b: Float) Int:
	if a < b: return -1
	if a > b: return 1
	return 0

fn cmp_vals(l: Val, r: Val) Int:
	if l.kind == 0 and r.kind == 0: return 0
	var a = l.clone()
	var b = r.clone()
	if a.kind == 0: a = zero_of(b.kind)
	if b.kind == 0: b = zero_of(a.kind)
	if a.kind != b.kind:
		return if a.kind < b.kind: -1 else: 1
	if a.kind == 2:
		c := a.s.compare(b.s)
		if c < 0: return -1
		if c > 0: return 1
		return 0
	return cmp_f(a.n, b.n)

type Item:
	v: Val
	rng: Bool

fn collect(vals: List[Val], a: Ast, args: List[Int]) List[Item]:
	var out = List[Item]()
	for ai in args:
		nd := a.nodes[ai]
		if nd.kind == 4:
			if not nd.ok:
				out.append(Item(v: verr("#REF!"), rng: true))
			else:
				for r in nd.r1..(nd.r2 + 1):
					for c in nd.c1..(nd.c2 + 1):
						out.append(Item(v: vals[cell_index(c, r)].clone(), rng: true))
		else:
			out.append(Item(v: eval(vals, a, ai), rng: false))
	return out

fn sc(vals: List[Val], a: Ast, node: Node, i: Int) Val:
	return eval(vals, a, node.args[i])

fn num_arg(vals: List[Val], a: Ast, node: Node, i: Int) Val:
	return coerce_num(sc(vals, a, node, i))

fn str_arg(vals: List[Val], a: Ast, node: Node, i: Int) Val:
	v := sc(vals, a, node, i)
	if v.kind == 4: return v
	return vtext(display(v))

fn join_chars(cs: List[String], a: Int, b: Int) String:
	var out = ""
	for i in a..b:
		out = out + cs[i]
	return out

fn round_away(v: Float) Float:
	av := v.abs()
	f := floor(av)
	var r = f
	if av - f >= 0.5: r = f + 1.0
	if v < 0.0: return -r
	return r

fn aggregate(vals: List[Val], a: Ast, node: Node, name: String) Val:
	if node.args.length() == 0: return verr("#VALUE!")
	items := collect(vals, a, node.args)
	if name == "COUNT":
		var k = 0
		for it in items:
			if it.v.kind == 1: k += 1
		return vnum(k.to_float())
	if name == "COUNTA":
		var k = 0
		for it in items:
			if it.v.kind != 0: k += 1
		return vnum(k.to_float())
	var nums = List[Float]()
	for it in items:
		if it.v.kind == 4: return it.v.clone()
		if it.rng:
			if it.v.kind == 1: nums.append(it.v.n)
		else:
			c := coerce_num(it.v)
			if c.kind == 4: return c
			nums.append(c.n)
	if name == "SUM":
		var acc = 0.0
		for x in nums: acc += x
		return numres(acc)
	if name == "AVERAGE":
		if nums.length() == 0: return verr("#DIV/0!")
		var acc = 0.0
		for x in nums: acc += x
		return numres(acc / nums.length().to_float())
	if name == "PRODUCT":
		if nums.length() == 0: return vnum(0.0)
		var acc = 1.0
		for x in nums: acc = acc * x
		return numres(acc)
	if name == "MIN" or name == "MAX":
		if nums.length() == 0: return vnum(0.0)
		var best = nums[0]
		for x in nums:
			if name == "MIN" and x < best: best = x
			if name == "MAX" and x > best: best = x
		return vnum(best)
	// MEDIAN
	if nums.length() == 0: return verr("#NUM!")
	var sorted = nums.sorted(fn x, y: cmp_f(x, y))
	m := sorted.length()
	if m % 2 == 1: return vnum(sorted[m / 2])
	return numres((sorted[m / 2 - 1] + sorted[m / 2]) / 2.0)

fn logic(vals: List[Val], a: Ast, node: Node, is_and: Bool) Val:
	if node.args.length() == 0: return verr("#VALUE!")
	items := collect(vals, a, node.args)
	var took = false
	var acc = is_and
	for it in items:
		if it.v.kind == 4: return it.v.clone()
		if it.rng and (it.v.kind == 2 or it.v.kind == 0): continue
		b := coerce_bool(it.v)
		if b.kind == 4: return b
		took = true
		if is_and: acc = acc and b.n != 0.0
		else: acc = acc or b.n != 0.0
	if not took: return verr("#VALUE!")
	return vbool(acc)

fn countif(vals: List[Val], a: Ast, node: Node) Val:
	if node.args.length() != 2: return verr("#VALUE!")
	rn := a.nodes[node.args[0]]
	if rn.kind != 4: return verr("#VALUE!")
	if not rn.ok: return verr("#REF!")
	crit := sc(vals, a, node, 1)
	if crit.kind == 4: return crit
	var op = "="
	var operand = Val()
	if crit.kind == 2:
		cs := crit.s.scalar_values()
		var rest = crit.s.clone()
		for p in [">=", "<=", "<>", ">", "<", "="]:
			if crit.s.starts_with(p):
				op = p.clone()
				rest = sub(cs, p.length(), cs.length())
				break
		if x := parse_num(rest): operand = vnum(x)
		else: operand = vtext(rest)
	else:
		operand = crit.clone()
	var count = 0
	for r in rn.r1..(rn.r2 + 1):
		for c in rn.c1..(rn.c2 + 1):
			cv := vals[cell_index(c, r)]
			var hit = false
			if cv.kind == operand.kind:
				k := cmp_vals(cv, operand)
				if op == "=": hit = k == 0
				else if op == "<>": hit = k != 0
				else if op == "<": hit = k < 0
				else if op == "<=": hit = k <= 0
				else if op == ">": hit = k > 0
				else: hit = k >= 0
			else if op == "<>" and cv.kind != 0:
				hit = true
			if hit: count += 1
	return vnum(count.to_float())

fn eval_call(vals: List[Val], a: Ast, node: Node) Val:
	name := node.s
	n := node.args.length()
	if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN" or name == "COUNT" or name == "COUNTA":
		return aggregate(vals, a, node, name)
	if name == "AND": return logic(vals, a, node, true)
	if name == "OR": return logic(vals, a, node, false)
	if name == "COUNTIF": return countif(vals, a, node)
	if name == "IF":
		if n < 2 or n > 3: return verr("#VALUE!")
		b := coerce_bool(sc(vals, a, node, 0))
		if b.kind == 4: return b
		if b.n != 0.0: return sc(vals, a, node, 1)
		if n == 3: return sc(vals, a, node, 2)
		return vbool(false)
	if name == "IFERROR":
		if n != 2: return verr("#VALUE!")
		v := sc(vals, a, node, 0)
		if v.kind == 4: return sc(vals, a, node, 1)
		return v
	if name == "CHOOSE":
		if n < 2: return verr("#VALUE!")
		iv := num_arg(vals, a, node, 0)
		if iv.kind == 4: return iv
		f := floor(iv.n)
		if f < 1.0 or f > (n - 1).to_float(): return verr("#VALUE!")
		return sc(vals, a, node, to_i(f))
	if name == "NOT":
		if n != 1: return verr("#VALUE!")
		b := coerce_bool(sc(vals, a, node, 0))
		if b.kind == 4: return b
		return vbool(b.n == 0.0)
	if name == "ABS" or name == "INT" or name == "SQRT":
		if n != 1: return verr("#VALUE!")
		x := num_arg(vals, a, node, 0)
		if x.kind == 4: return x
		if name == "ABS": return vnum(x.n.abs())
		if name == "INT": return vnum(floor(x.n))
		if x.n < 0.0: return verr("#NUM!")
		return numres(sqrt(x.n))
	if name == "POW" or name == "MOD":
		if n != 2: return verr("#VALUE!")
		x := num_arg(vals, a, node, 0)
		y := num_arg(vals, a, node, 1)
		if x.kind == 4: return x
		if y.kind == 4: return y
		if name == "POW": return numres(pow(x.n, y.n))
		if y.n == 0.0: return verr("#DIV/0!")
		return numres(x.n - y.n * floor(x.n / y.n))
	if name == "ROUND":
		if n < 1 or n > 2: return verr("#VALUE!")
		x := num_arg(vals, a, node, 0)
		if x.kind == 4: return x
		var d = 0
		if n == 2:
			dv := num_arg(vals, a, node, 1)
			if dv.kind == 4: return dv
			if dv.n.abs() >= 16.0: return verr("#NUM!")
			d = to_i(dv.n)
		if d > 15 or d < -15: return verr("#NUM!")
		p := pow(10.0, d.to_float())
		m := x.n * p
		if not m.is_finite(): return verr("#NUM!")
		return numres(round_away(m) / p)
	if name == "LEN":
		if n != 1: return verr("#VALUE!")
		s := str_arg(vals, a, node, 0)
		if s.kind == 4: return s
		return vnum(s.s.scalar_length().to_float())
	if name == "UPPER" or name == "LOWER" or name == "TRIM":
		if n != 1: return verr("#VALUE!")
		s := str_arg(vals, a, node, 0)
		if s.kind == 4: return s
		if name == "UPPER": return vtext(upper_ascii(s.s))
		if name == "LOWER": return vtext(lower_ascii(s.s))
		var out = List[Int]()
		var pending = false
		for c in s.s.scalar_values():
			if is_wsc(c):
				if out.length() > 0: pending = true
			else:
				if pending: out.append(32)
				pending = false
				out.append(c)
		if t := from_scalars(out): return vtext(t)
		return vtext("")
	if name == "LEFT" or name == "RIGHT":
		if n < 1 or n > 2: return verr("#VALUE!")
		s := str_arg(vals, a, node, 0)
		var cnt = 1.0
		if n == 2:
			nv := num_arg(vals, a, node, 1)
			if s.kind == 4: return s
			if nv.kind == 4: return nv
			cnt = floor(nv.n)
		if s.kind == 4: return s
		if cnt < 0.0: return verr("#VALUE!")
		cs := s.s.chars()
		l := cs.length()
		k := if cnt > l.to_float(): l else: to_i(cnt)
		if name == "LEFT": return vtext(join_chars(cs, 0, k))
		return vtext(join_chars(cs, l - k, l))
	if name == "MID":
		if n != 3: return verr("#VALUE!")
		s := str_arg(vals, a, node, 0)
		st := num_arg(vals, a, node, 1)
		ln := num_arg(vals, a, node, 2)
		if s.kind == 4: return s
		if st.kind == 4: return st
		if ln.kind == 4: return ln
		sf := floor(st.n)
		lf := floor(ln.n)
		if sf < 1.0 or lf < 0.0: return verr("#VALUE!")
		cs := s.s.chars()
		l := cs.length()
		if sf > l.to_float(): return vtext("")
		from := to_i(sf) - 1
		avail := l - from
		k := if lf > avail.to_float(): avail else: to_i(lf)
		return vtext(join_chars(cs, from, from + k))
	if name == "CONCAT":
		if n == 0: return verr("#VALUE!")
		items := collect(vals, a, node.args)
		var out = ""
		for it in items:
			if it.v.kind == 4: return it.v.clone()
			out = out + display(it.v)
		return vtext(out)
	if name == "SUBSTITUTE":
		if n != 3: return verr("#VALUE!")
		s := str_arg(vals, a, node, 0)
		o := str_arg(vals, a, node, 1)
		w := str_arg(vals, a, node, 2)
		if s.kind == 4: return s
		if o.kind == 4: return o
		if w.kind == 4: return w
		if o.s.length() == 0: return s
		return vtext(s.s.replace(o.s, w.s))
	if name == "VALUE":
		if n != 1: return verr("#VALUE!")
		v := sc(vals, a, node, 0)
		if v.kind == 1 or v.kind == 4: return v
		return coerce_num(v)
	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if n != 1: return verr("#VALUE!")
		v := sc(vals, a, node, 0)
		if name == "ISERROR": return vbool(v.kind == 4)
		if name == "ISBLANK": return vbool(v.kind == 0)
		if name == "ISNUMBER": return vbool(v.kind == 1)
		return vbool(v.kind == 2)
	if name == "ROW" or name == "COLUMN":
		if n != 1: return verr("#VALUE!")
		nd := a.nodes[node.args[0]]
		if nd.kind == 3:
			if not nd.ok: return verr("#REF!")
			if name == "ROW": return vnum(nd.r1.to_float())
			return vnum((nd.c1 + 1).to_float())
		if nd.kind == 4:
			if not nd.ok: return verr("#REF!")
			if name == "ROW": return vnum(nd.orow.to_float())
			return vnum((nd.oc + 1).to_float())
		return verr("#VALUE!")
	if name == "INDEX":
		if n < 2 or n > 3: return verr("#VALUE!")
		rn := a.nodes[node.args[0]]
		if rn.kind != 4: return verr("#VALUE!")
		if not rn.ok: return verr("#REF!")
		h := rn.r2 - rn.r1 + 1
		w := rn.c2 - rn.c1 + 1
		rv := num_arg(vals, a, node, 1)
		if rv.kind == 4: return rv
		var ri = floor(rv.n)
		var ci = 1.0
		if n == 3:
			cv := num_arg(vals, a, node, 2)
			if cv.kind == 4: return cv
			ci = floor(cv.n)
		else if h == 1:
			ci = ri
			ri = 1.0
		if ri < 1.0 or ri > h.to_float() or ci < 1.0 or ci > w.to_float(): return verr("#REF!")
		return vals[cell_index(rn.c1 + to_i(ci) - 1, rn.r1 + to_i(ri) - 1)].clone()
	return verr("#NAME?")

fn eval(vals: List[Val], a: Ast, idx: Int) Val:
	node := a.nodes[idx]
	k := node.kind
	if k == 0:
		if not node.ok: return verr("#NUM!")
		return vnum(node.num)
	if k == 1: return vtext(node.s.clone())
	if k == 2: return vbool(node.num != 0.0)
	if k == 3:
		if not node.ok: return verr("#REF!")
		return vals[cell_index(node.c1, node.r1)].clone()
	if k == 4: return verr("#VALUE!")
	if k == 5: return verr("#REF!")
	if k == 6: return verr("#NAME?")
	if k == 7: return eval_call(vals, a, node)
	if k == 9:
		x := coerce_num(eval(vals, a, node.args[0]))
		if x.kind == 4: return x
		if node.s == "-": return vnum(-x.n)
		return x
	l := eval(vals, a, node.args[0])
	r := eval(vals, a, node.args[1])
	op := node.s
	if op == "&":
		if l.kind == 4: return l
		if r.kind == 4: return r
		return vtext(display(l) + display(r))
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if l.kind == 4: return l
		if r.kind == 4: return r
		c := cmp_vals(l, r)
		if op == "=": return vbool(c == 0)
		if op == "<>": return vbool(c != 0)
		if op == "<": return vbool(c < 0)
		if op == "<=": return vbool(c <= 0)
		if op == ">": return vbool(c > 0)
		return vbool(c >= 0)
	ln := coerce_num(l)
	if ln.kind == 4: return ln
	rn := coerce_num(r)
	if rn.kind == 4: return rn
	if op == "+": return numres(ln.n + rn.n)
	if op == "-": return numres(ln.n - rn.n)
	if op == "*": return numres(ln.n * rn.n)
	if op == "/":
		if rn.n == 0.0: return verr("#DIV/0!")
		return numres(ln.n / rn.n)
	return numres(pow(ln.n, rn.n))

// ---------- sheet ----------

type Sheet:
	raw: List[String]
	kind: List[Int]
	vals: List[Val]
	asts: List[Ast]
	evals: Int = 0

fn new_sheet() Sheet:
	var raw = List[String]()
	var kind = List[Int]()
	var vals = List[Val]()
	var asts = List[Ast]()
	for _i in 0..25974:
		raw.append("")
		kind.append(0)
		vals.append(Val())
		asts.append(Ast())
	return Sheet(raw: raw, kind: kind, vals: vals, asts: asts)

fn var Sheet.assign(idx: Int, text: String) Unit:
	if text.length() == 0:
		self.kind[idx] = 0
		self.raw[idx] = ""
		self.vals[idx] = Val()
		self.asts[idx] = Ast()
		return
	cs := text.scalar_values()
	self.raw[idx] = text.clone()
	if cs[0] == 61:
		self.kind[idx] = 2
		self.asts[idx] = parse_formula(sub(cs, 1, cs.length()))
		self.vals[idx] = Val()
		return
	self.kind[idx] = 1
	self.asts[idx] = Ast()
	if cs[0] == 39:
		self.vals[idx] = vtext(sub(cs, 1, cs.length()))
		return
	if x := parse_num(text):
		self.vals[idx] = vnum(x)
		return
	u := upper_ascii(text)
	if u == "TRUE":
		self.vals[idx] = vbool(true)
		return
	if u == "FALSE":
		self.vals[idx] = vbool(false)
		return
	self.vals[idx] = vtext(text.clone())

fn Sheet.build_rev() List[List[Int]]:
	var rev = List[List[Int]]()
	for _i in 0..25974:
		rev.append(List[Int]())
	for i in 0..25974:
		if self.kind[i] == 2:
			for p in self.asts[i].prec:
				rev[p].append(i)
	return rev

fn var Sheet.recalc(changed: List[Int]) Int:
	total := 25974
	rev := self.build_rev()
	var in_a = List[Bool]()
	for _i in 0..total: in_a.append(false)
	var queue = List[Int]()
	for c in changed:
		if self.kind[c] == 2: in_a[c] = true
		queue.append(c)
	var qi = 0
	while qi < queue.length():
		x := queue[qi]
		qi += 1
		for d in rev[x]:
			if not in_a[d]:
				in_a[d] = true
				queue.append(d)
	// Tarjan over affected cells; edges go from a cell to its affected precedents
	var index = List[Int]()
	var low = List[Int]()
	var on_stack = List[Bool]()
	for _i in 0..total:
		index.append(-1)
		low.append(0)
		on_stack.append(false)
	var order = List[Int]()
	var cyc = List[Bool]()
	for _i in 0..total: cyc.append(false)
	var counter = 0
	var count = 0
	var tstack = List[Int]()
	for root in 0..total:
		if not in_a[root] or index[root] != -1: continue
		var cs_v = List[Int]()
		var cs_i = List[Int]()
		index[root] = counter
		low[root] = counter
		counter += 1
		tstack.append(root)
		on_stack[root] = true
		cs_v.append(root)
		cs_i.append(0)
		while cs_v.length() > 0:
			top := cs_v.length() - 1
			v := cs_v[top]
			i := cs_i[top]
			if i < self.asts[v].prec.length():
				cs_i[top] = i + 1
				w := self.asts[v].prec[i]
				if not in_a[w]: continue
				if index[w] == -1:
					index[w] = counter
					low[w] = counter
					counter += 1
					tstack.append(w)
					on_stack[w] = true
					cs_v.append(w)
					cs_i.append(0)
				else if on_stack[w]:
					if index[w] < low[v]: low[v] = index[w]
			else:
				cs_v.pop()
				cs_i.pop()
				if low[v] == index[v]:
					var members = List[Int]()
					while true:
						w := tstack.pop().get(0)
						on_stack[w] = false
						members.append(w)
						if w == v: break
					var is_cycle = members.length() > 1
					if not is_cycle:
						for p in self.asts[v].prec:
							if p == v: is_cycle = true
					for m in members:
						order.append(m)
						if is_cycle: cyc[m] = true
				if cs_v.length() > 0:
					par := cs_v[cs_v.length() - 1]
					if low[v] < low[par]: low[par] = low[v]
	for v in order:
		count += 1
		if cyc[v]:
			self.vals[v] = verr("#CYCLE!")
		else if not self.asts[v].ok:
			self.vals[v] = verr("#PARSE!")
		else:
			res := eval(self.vals, self.asts[v], self.asts[v].root)
			if res.kind == 0: self.vals[v] = vnum(0.0)
			else: self.vals[v] = res
	self.evals += count
	return count

// ---------- argument parsing ----------

type Rect:
	ok: Bool = false
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0

fn parse_cell(s: String) Int:
	cs := s.scalar_values()
	n := cs.length()
	if n < 2 or n > 4: return -1
	if not is_letter(cs[0]): return -1
	if cs[1] == 48: return -1
	var row = 0
	for i in 1..n:
		if not is_digit(cs[i]): return -1
		row = row * 10 + (cs[i] - 48)
	if row < 1 or row > 999: return -1
	var col = cs[0] - 65
	if cs[0] >= 97: col = cs[0] - 97
	return cell_index(col, row)

fn parse_range(s: String) Rect:
	parts := s.split(":")
	if parts.length() == 1:
		i := parse_cell(parts[0])
		if i < 0: return Rect()
		return Rect(ok: true, c1: i % 26, r1: i / 26 + 1, c2: i % 26, r2: i / 26 + 1)
	if parts.length() != 2: return Rect()
	i := parse_cell(parts[0])
	j := parse_cell(parts[1])
	if i < 0 or j < 0: return Rect()
	ca := i % 26
	ra := i / 26 + 1
	cb := j % 26
	rb := j / 26 + 1
	return Rect(ok: true, c1: if ca < cb: ca else: cb, r1: if ra < rb: ra else: rb, c2: if ca < cb: cb else: ca, r2: if ra < rb: rb else: ra)

fn cell_name(i: Int) String:
	var letter = ""
	if g := from_scalars([65 + i % 26]): letter = g
	return "{letter}{i / 26 + 1}"

fn split_ws(s: String) List[String]:
	var out = List[String]()
	var cur = List[Int]()
	for c in s.scalar_values():
		if is_wsc(c):
			if cur.length() > 0:
				if t := from_scalars(cur): out.append(t)
				cur = List[Int]()
		else: cur.append(c)
	if cur.length() > 0:
		if t := from_scalars(cur): out.append(t)
	return out

fn csv_quote(s: String) String:
	cs := s.scalar_values()
	var need = false
	if cs.length() > 0 and (cs[0] == 32 or cs[cs.length() - 1] == 32): need = true
	for c in cs:
		if c == 44 or c == 34 or c == 10 or c == 13: need = true
	if not need: return s.clone()
	return "\"" + s.replace("\"", "\"\"") + "\""

fn parse_csv(text: String) List[List[String]]:
	var rows = List[List[String]]()
	var row = List[String]()
	var field = List[Int]()
	var in_q = false
	var content = false
	cs := text.scalar_values()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		i += 1
		if in_q:
			if c == 34:
				if i < n and cs[i] == 34:
					field.append(34)
					i += 1
				else: in_q = false
			else: field.append(c)
			continue
		if c == 34:
			in_q = true
			content = true
		else if c == 44:
			content = true
			row.append(from_scalars(field).get(""))
			field = List[Int]()
		else if c == 10:
			if content:
				row.append(from_scalars(field).get(""))
				rows.append(row)
			row = List[String]()
			field = List[Int]()
			content = false
		else if c == 13: continue
		else:
			field.append(c)
			content = true
	if content:
		row.append(from_scalars(field).get(""))
		rows.append(row)
	return rows

fn shift_ref(r: Ref, dc: Int, dr: Int) String:
	c := if r.ca: r.c else: r.c + dc
	w := if r.ra: r.r else: r.r + dr
	if c < 0 or c > 25 or w < 1 or w > 999: return ""
	var letter = ""
	if g := from_scalars([65 + c]): letter = g
	return (if r.ca: "$" else: "") + letter + (if r.ra: "$" else: "") + "{w}"

fn shift_formula(src: String, dc: Int, dr: Int) String:
	cs := src.scalar_values()
	lx := tokenize(cs)
	if not lx.ok: return src.clone()
	var out = ""
	var pos = 0
	for t in lx.toks:
		if t.kind == 2 or t.kind == 3:
			out = out + sub(cs, pos, t.start)
			pos = t.end
			if not t.a.ok or (t.kind == 3 and not t.b.ok):
				out = out + t.s
			else:
				x := shift_ref(t.a, dc, dr)
				if t.kind == 2:
					out = out + (if x == "": "#REF!" else: x)
				else:
					y := shift_ref(t.b, dc, dr)
					if x == "" or y == "": out = out + "#REF!"
					else: out = out + x + ":" + y
	out = out + sub(cs, pos, cs.length())
	return out

// ---------- commands ----------

fn usage(msg: String) String: "error: usage: " + msg

fn Sheet.show_grid(rc: Rect, formulas: Bool, csv: Bool) String:
	var lines = List[String]()
	for r in rc.r1..(rc.r2 + 1):
		var fields = List[String]()
		for c in rc.c1..(rc.c2 + 1):
			i := cell_index(c, r)
			var t = ""
			if formulas: t = self.raw[i].clone()
			else: t = display(self.vals[i])
			if csv: fields.append(csv_quote(t))
			else: fields.append(t)
		lines.append(fields.join(if csv: "," else: " | "))
	return lines.join("\n")

fn Sheet.extent() Rect:
	var mc = -1
	var mr = 0
	for i in 0..25974:
		if self.kind[i] != 0:
			if i % 26 > mc: mc = i % 26
			if i / 26 + 1 > mr: mr = i / 26 + 1
	if mc < 0: return Rect()
	return Rect(ok: true, c1: 0, r1: 1, c2: mc, r2: mr)

fn var Sheet.exec(line: String, block: List[String]) String:
	toks := split_ws(line)
	cmd := toks[0].clone()
	argc := toks.length() - 1
	if cmd == "set":
		if argc == 0: return usage("set CELL VALUE")
		cs := line.scalar_values()
		// skip command word and whitespace, then cell token
		var i = 0
		while i < cs.length() and is_wsc(cs[i]): i += 1
		while i < cs.length() and not is_wsc(cs[i]): i += 1
		while i < cs.length() and is_wsc(cs[i]): i += 1
		j0 := i
		while i < cs.length() and not is_wsc(cs[i]): i += 1
		cellt := sub(cs, j0, i)
		value := trim_ascii(sub(cs, i, cs.length()))
		idx := parse_cell(cellt)
		if idx < 0: return "error: bad cell reference '{cellt}'"
		self.assign(idx, value)
		var ch = List[Int]()
		ch.append(idx)
		return "recalc {self.recalc(ch)}"
	if cmd == "clear":
		if argc != 1: return usage("clear CELL")
		idx := parse_cell(toks[1])
		if idx < 0: return "error: bad cell reference '{toks[1]}'"
		self.assign(idx, "")
		var ch = List[Int]()
		ch.append(idx)
		return "recalc {self.recalc(ch)}"
	if cmd == "get" or cmd == "show" or cmd == "precedents" or cmd == "dependents":
		if argc != 1:
			if cmd == "get": return usage("get CELL")
			if cmd == "show": return usage("show CELL")
			if cmd == "precedents": return usage("precedents CELL")
			return usage("dependents CELL")
		idx := parse_cell(toks[1])
		if idx < 0: return "error: bad cell reference '{toks[1]}'"
		if cmd == "get":
			if self.kind[idx] == 0: return "(empty)"
			return display(self.vals[idx])
		if cmd == "show":
			name := cell_name(idx)
			if self.kind[idx] == 0: return "{name}: (empty)"
			if self.kind[idx] == 1: return "{name}: {self.raw[idx]}"
			return "{name}: {self.raw[idx]} => {display(self.vals[idx])}"
		if cmd == "precedents":
			var names = List[String]()
			if self.kind[idx] == 2:
				for p in self.asts[idx].prec: names.append(cell_name(p))
			if names.length() == 0: return "(none)"
			return names.join(" ")
		rev := self.build_rev()
		var seen = Set[Int]()
		var queue = List[Int]()
		queue.append(idx)
		var qi = 0
		while qi < queue.length():
			x := queue[qi]
			qi += 1
			for d in rev[x]:
				if not seen.contains(d):
					seen.add(d)
					queue.append(d)
		var ids = List[Int]()
		for d in seen.values(): ids.append(d)
		ids.sort()
		if ids.length() == 0: return "(none)"
		var names = List[String]()
		for d in ids: names.append(cell_name(d))
		return names.join(" ")
	if cmd == "copy":
		if argc != 2: return usage("copy SRC DST")
		src := parse_cell(toks[1])
		if src < 0: return "error: bad cell reference '{toks[1]}'"
		rc := parse_range(toks[2])
		if not rc.ok: return "error: bad range '{toks[2]}'"
		skind := self.kind[src]
		sraw := self.raw[src].clone()
		var ch = List[Int]()
		for r in rc.r1..(rc.r2 + 1):
			for c in rc.c1..(rc.c2 + 1):
				idx := cell_index(c, r)
				if skind == 0: self.assign(idx, "")
				else if skind == 1: self.assign(idx, sraw)
				else:
					body := sub(sraw.scalar_values(), 1, sraw.scalar_values().length())
					self.assign(idx, "=" + shift_formula(body, c - src % 26, r - (src / 26 + 1)))
				ch.append(idx)
		return "recalc {self.recalc(ch)}"
	if cmd == "print" or cmd == "export":
		var formulas = false
		var seen_word = false
		var rng = Rect()
		var have_range = false
		for k in 1..toks.length():
			w := toks[k]
			if w == "formulas" or w == "values":
				if seen_word: return usage(if cmd == "print": "print [RANGE]" else: "export [formulas] [RANGE]")
				seen_word = true
				formulas = w == "formulas"
			else:
				if have_range: return usage(if cmd == "print": "print [RANGE]" else: "export [formulas] [RANGE]")
				have_range = true
				rng = parse_range(w)
				if not rng.ok: return "error: bad range '{w}'"
		if cmd == "print" and formulas: return usage("print [RANGE]")
		if not have_range:
			rng = self.extent()
			if not rng.ok: return "(empty sheet)"
		return self.show_grid(rng, formulas, cmd == "export")
	if cmd == "import":
		if argc != 1: return usage("import CELL")
		idx := parse_cell(toks[1])
		if idx < 0: return "error: bad cell reference '{toks[1]}'"
		rows := parse_csv(block.join("\n"))
		var width = 0
		for rw in rows:
			if rw.length() > width: width = rw.length()
		sc0 := idx % 26
		sr0 := idx / 26 + 1
		if sc0 + width > 26 or sr0 + rows.length() - 1 > 999: return "error: import out of range"
		var ch = List[Int]()
		for ri in 0..rows.length():
			for ci in 0..rows[ri].length():
				id2 := cell_index(sc0 + ci, sr0 + ri)
				self.assign(id2, trim_ascii(rows[ri][ci]))
				ch.append(id2)
		cnt := self.recalc(ch)
		return "imported {rows.length()} rows, {width} columns; recalc {cnt}"
	if cmd == "stats":
		var cells = 0
		var forms = 0
		for i in 0..25974:
			if self.kind[i] != 0: cells += 1
			if self.kind[i] == 2: forms += 1
		return "cells {cells} formulas {forms} evals {self.evals}"
	return "error: unknown command '{cmd}'"

fn rtrim_ascii(s: String) String:
	cs := s.scalar_values()
	var b = cs.length()
	while b > 0 and is_wsc(cs[b - 1]): b -= 1
	return sub(cs, 0, b)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var lines = List[String]()
	for l in text.split("\n"): lines.append(l.clone())
	if lines.length() > 0 and lines[lines.length() - 1] == "": lines.pop()
	var sh = new_sheet()
	var out = List[String]()
	var i = 0
	while i < lines.length():
		line := lines[i]
		i += 1
		t := trim_ascii(line)
		var block = List[String]()
		if t.length() == 0 or t.starts_with("#"): continue
		toks := split_ws(t)
		if toks[0] == "import":
			while i < lines.length() and lines[i] != ".":
				block.append(lines[i].clone())
				i += 1
			i += 1
		out.append("> " + rtrim_ascii(line))
		out.append(sh.exec(t, block))
	if out.length() > 0: print(out.join("\n"))
