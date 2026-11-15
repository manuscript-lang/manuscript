import floor, pow, sqrt, parse from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

enum NK:
	KNum
	KStr
	KBool
	KRef
	KRange
	KBadRef
	KBadRange
	KErrLit
	KName
	KCall
	KUn
	KBin
	KParen

enum Val:
	Empty
	Num(n: Float)
	Text(s: String)
	Bool(b: Bool)
	Err(e: String)

type Node:
	kind: NK
	s: String = ""
	n: Float = 0.0
	a: Int = 0
	b: Int = 0
	c: Int = 0
	d: Int = 0
	args: List[Int] = List[Int]()

type Tok:
	kind: Int
	s: String = ""
	s2: String = ""
	start: Int = 0
	end: Int = 0

type RefInfo:
	valid: Bool
	col: Int = 0
	row: Int = 0
	cabs: Bool = false
	rabs: Bool = false

type Item:
	v: Val
	direct: Bool

type NumList:
	failed: Bool
	err: Val
	nums: List[Float]

// ---------- char helpers ----------

fn is_digit(c: String) Bool: c.length() == 1 and "0123456789".contains(c)

fn is_letter(c: String) Bool: c.length() == 1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".contains(c)

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\r" or c == "\n"

fn ch(cs: List[String], i: Int) String:
	if i < 0 or i >= cs.length(): return ""
	return cs[i].clone()

fn join_range(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b:
		out += cs[i]
		i += 1
	return out

fn words(s: String) List[String]:
	var out = List[String]()
	var cur = ""
	for c in s.chars():
		if is_ws(c):
			if cur.length() > 0:
				out.append(cur.clone())
				cur = ""
		else:
			cur += c
	if cur.length() > 0: out.append(cur.clone())
	return out

type Pair:
	a: String
	b: String

fn split_first(s: String) Pair:
	cs := s.chars()
	var i = 0
	while i < cs.length() and not is_ws(cs[i]): i += 1
	return Pair(join_range(cs, 0, i), join_range(cs, i, cs.length()).trim())

// ---------- numbers ----------

fn num_grammar(s: String) Bool:
	cs := s.chars()
	n := cs.length()
	var i = 0
	if i < n and (cs[i] == "+" or cs[i] == "-"): i += 1
	var nd = 0
	while i < n and is_digit(cs[i]):
		i += 1
		nd += 1
	if i < n and cs[i] == ".":
		i += 1
		var fd = 0
		while i < n and is_digit(cs[i]):
			i += 1
			fd += 1
		if nd == 0 and fd == 0: return false
	else:
		if nd == 0: return false
	if i < n and (cs[i] == "e" or cs[i] == "E"):
		i += 1
		if i < n and (cs[i] == "+" or cs[i] == "-"): i += 1
		var ed = 0
		while i < n and is_digit(cs[i]):
			i += 1
			ed += 1
		if ed == 0: return false
	return i == n

fn parse_num(s: String) Float?:
	if not num_grammar(s): return none
	cs := s.chars()
	var out = ""
	var i = 0
	if cs[i] == "+" or cs[i] == "-":
		out += cs[i]
		i += 1
	if cs[i] == ".": out += "0"
	var after_dot = false
	while i < cs.length():
		c := cs[i]
		if after_dot and not is_digit(c): out += "0"
		after_dot = false
		out += c
		if c == ".": after_dot = true
		i += 1
	if after_dot: out += "0"
	r := out.parse_float()
	if x := r:
		if x.is_finite(): return x
	return none

fn fmt_num(x: Float) String:
	ax := if x < 0.0: -x else: x
	var s = ""
	if ax >= 1e21:
		var m = ax
		var e = 0
		while m >= 9007199254740992.0:
			m = m / 2.0
			e += 1
		mi := m.truncate_to_int().get(0)
		bi := parse("{mi}", 10)
		if b := bi:
			sh := b.shift_left(e)
			if v := sh:
				s = v.to_string_radix(10)
	else:
		s = ax.to_fixed(10)
		if s.contains("."):
			s = s.trim_end_chars("0")
			s = s.trim_end_chars(".")
	if s == "0" or s == "": return "0"
	if x < 0.0: return "-" + s
	return s

// ---------- values ----------

fn is_err(v: Val) Bool:
	match v:
		Err(_e): return true
		_: return false

fn is_empty(v: Val) Bool:
	match v:
		Empty: return true
		_: return false

fn str_of(v: Val) String:
	match v:
		Empty: return ""
		Num(n): return fmt_num(n)
		Text(s): return s.clone()
		Bool(b): return if b: "TRUE" else: "FALSE"
		Err(e): return e.clone()

fn err(e: String) Val: Val.Err(e)

fn nv(v: Val) Float:
	match v:
		Num(n): return n
		_: return 0.0

fn tag(v: Val) Int:
	match v:
		Empty: return 0
		Num(_n): return 1
		Text(_s): return 2
		Bool(_b): return 3
		Err(_e): return 4

// number coercion: returns Num or Err
fn coerce(v: Val) Val:
	match v:
		Empty: return Val.Num(0.0)
		Num(n): return Val.Num(n)
		Bool(b): return Val.Num(if b: 1.0 else: 0.0)
		Err(e): return Val.Err(e.clone())
		Text(s):
			if x := parse_num(s.trim()): return Val.Num(x)
			return err("#VALUE!")

// boolean coercion: returns Bool or Err
fn bcoerce(v: Val) Val:
	match v:
		Empty: return Val.Bool(false)
		Num(n): return Val.Bool(n != 0.0)
		Bool(b): return Val.Bool(b)
		Err(e): return Val.Err(e.clone())
		Text(s):
			u := s.upper()
			if u == "TRUE": return Val.Bool(true)
			if u == "FALSE": return Val.Bool(false)
			return err("#VALUE!")

fn bv(v: Val) Bool:
	match v:
		Bool(b): return b
		_: return false

fn num_res(x: Float) Val:
	if x.is_finite(): return Val.Num(x)
	return err("#NUM!")

fn zero_like(v: Val) Val:
	match v:
		Num(_n): return Val.Num(0.0)
		Text(_s): return Val.Text("")
		Bool(_b): return Val.Bool(false)
		_: return Val.Empty

fn compare(l: Val, r: Val) Int:
	if is_empty(l) and is_empty(r): return 0
	a := if is_empty(l): zero_like(r) else: l.clone()
	b := if is_empty(r): zero_like(l) else: r.clone()
	ta := tag(a)
	tb := tag(b)
	if ta != tb: return if ta < tb: -1 else: 1
	match a:
		Num(x):
			y := nv(b)
			if x < y: return -1
			if x > y: return 1
			return 0
		Text(x):
			y := str_of(b)
			if x < y: return -1
			if x > y: return 1
			return 0
		Bool(x):
			y := bv(b)
			if x == y: return 0
			return if x: 1 else: -1
		_: return 0

// ---------- references ----------

fn col_letter(c: Int) String: "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars()[c].clone()

fn cell_name(idx: Int) String:
	row := idx / 26 + 1
	col := idx % 26
	return col_letter(col) + "{row}"

fn ref_info(text: String) RefInfo:
	cs := text.chars()
	n := cs.length()
	var i = 0
	var cabs = false
	var rabs = false
	if ch(cs, i) == "$":
		cabs = true
		i += 1
	ls := i
	while is_letter(ch(cs, i)): i += 1
	le := i
	if ch(cs, i) == "$":
		rabs = true
		i += 1
	ds := i
	while is_digit(ch(cs, i)): i += 1
	de := i
	if i != n: return RefInfo(valid: false)
	if le - ls != 1: return RefInfo(valid: false)
	nd := de - ds
	if nd < 1 or nd > 3: return RefInfo(valid: false)
	if cs[ds] == "0": return RefInfo(valid: false)
	letter := cs[ls].upper()
	pos := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars()
	var col = -1
	for k in 0..26:
		if pos[k] == letter: col = k
	if col < 0: return RefInfo(valid: false)
	var row = 0
	for k in ds..de:
		row = row * 10 + (cs[k].parse_int().get(0))
	if row < 1 or row > 999: return RefInfo(valid: false)
	return RefInfo(valid: true, col: col, row: row, cabs: cabs, rabs: rabs)

// plain command cell reference: letter + 1..3 digits, no leading zero
fn parse_cell(text: String) Int:
	cs := text.chars()
	if cs.length() < 2 or cs.length() > 4: return -1
	if not is_letter(cs[0]): return -1
	for k in 1..cs.length():
		if not is_digit(cs[k]): return -1
	info := ref_info(text)
	if not info.valid: return -1
	return (info.row - 1) * 26 + info.col

type Rng:
	ok: Bool
	r1: Int = 0
	c1: Int = 0
	r2: Int = 0
	c2: Int = 0

fn parse_range(text: String) Rng:
	parts := text.split(":")
	if parts.length() < 1 or parts.length() > 2: return Rng(ok: false)
	a := parse_cell(parts[0])
	if a < 0: return Rng(ok: false)
	var b = a
	if parts.length() == 2:
		b = parse_cell(parts[1])
		if b < 0: return Rng(ok: false)
	ar := a / 26
	ac := a % 26
	br := b / 26
	bc := b % 26
	r1 := if ar < br: ar else: br
	r2 := if ar < br: br else: ar
	c1 := if ac < bc: ac else: bc
	c2 := if ac < bc: bc else: ac
	return Rng(ok: true, r1: r1 + 1, c1: c1, r2: r2 + 1, c2: c2)

// ---------- lexer ----------
// token kinds: 0 num, 1 str, 2 ref, 3 range, 4 errlit, 5 ident, 6 op

fn scan_ref(cs: List[String], i: Int) Int:
	var j = i
	if ch(cs, j) == "$": j += 1
	var nl = 0
	while is_letter(ch(cs, j)):
		j += 1
		nl += 1
	if nl == 0: return -1
	if ch(cs, j) == "$": j += 1
	var nd = 0
	while is_digit(ch(cs, j)):
		j += 1
		nd += 1
	if nd == 0: return -1
	f := ch(cs, j)
	if is_letter(f) or is_digit(f) or f == "_" or f == "." or f == "(" or f == "$": return -1
	return j

fn lex(cs: List[String]) List[Tok]!:
	var toks = List[Tok]()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		if c == " " or c == "\t":
			i += 1
			continue
		if is_digit(c) or (c == "." and is_digit(ch(cs, i + 1))):
			start := i
			while is_digit(ch(cs, i)): i += 1
			if ch(cs, i) == ".":
				i += 1
				while is_digit(ch(cs, i)): i += 1
			e := ch(cs, i)
			if e == "e" or e == "E":
				var j = i + 1
				s := ch(cs, j)
				if s == "+" or s == "-": j += 1
				if is_digit(ch(cs, j)):
					while is_digit(ch(cs, j)): j += 1
					i = j
			toks.append(Tok(kind: 0, s: join_range(cs, start, i), start: start, end: i))
			continue
		if c == "\"":
			start := i
			i += 1
			var out = ""
			var closed = false
			while i < n:
				if cs[i] == "\"":
					if ch(cs, i + 1) == "\"":
						out += "\""
						i += 2
						continue
					closed = true
					i += 1
					break
				out += cs[i]
				i += 1
			if not closed: return error(Error("parse"))
			toks.append(Tok(kind: 1, s: out, start: start, end: i))
			continue
		if is_letter(c) or c == "$":
			e1 := scan_ref(cs, i)
			if e1 >= 0:
				if ch(cs, e1) == ":":
					e2 := scan_ref(cs, e1 + 1)
					if e2 >= 0:
						toks.append(Tok(kind: 3, s: join_range(cs, i, e1), s2: join_range(cs, e1 + 1, e2), start: i, end: e2))
						i = e2
						continue
				toks.append(Tok(kind: 2, s: join_range(cs, i, e1), start: i, end: e1))
				i = e1
				continue
		if is_letter(c) or c == "_":
			start := i
			i += 1
			while is_letter(ch(cs, i)) or is_digit(ch(cs, i)) or ch(cs, i) == "_" or ch(cs, i) == ".": i += 1
			toks.append(Tok(kind: 5, s: join_range(cs, start, i), start: start, end: i))
			continue
		if c == "#":
			if join_range(cs, i, if i + 5 <= n: i + 5 else: n) == "#REF!":
				toks.append(Tok(kind: 4, s: "#REF!", start: i, end: i + 5))
				i += 5
				continue
			return error(Error("parse"))
		two := c + ch(cs, i + 1)
		if two == "<>" or two == "<=" or two == ">=":
			toks.append(Tok(kind: 6, s: two, start: i, end: i + 2))
			i += 2
			continue
		if "+-*/^&=<>(),".contains(c):
			toks.append(Tok(kind: 6, s: c.clone(), start: i, end: i + 1))
			i += 1
			continue
		return error(Error("parse"))
	return ok(toks)

// ---------- parser ----------

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = List[Node]()
	precs: List[Int] = List[Int]()

fn Parser.is_op(s: String) Bool:
	if self.pos >= self.toks.length(): return false
	t := self.toks[self.pos].clone()
	return t.kind == 6 and t.s == s

fn var Parser.add(nd: Node) Int:
	self.nodes.append(nd)
	return self.nodes.length() - 1

fn var Parser.parse_cmp() Int!:
	var left = self.parse_cat()?
	while true:
		var op = ""
		for o in ["<>", "<=", ">=", "=", "<", ">"]:
			if self.is_op(o): op = o.clone()
		if op == "": break
		self.pos += 1
		right := self.parse_cat()?
		left = self.add(Node(kind: NK.KBin, s: op, a: left, b: right))
	return ok(left)

fn var Parser.parse_cat() Int!:
	var left = self.parse_add()?
	while self.is_op("&"):
		self.pos += 1
		right := self.parse_add()?
		left = self.add(Node(kind: NK.KBin, s: "&", a: left, b: right))
	return ok(left)

fn var Parser.parse_add() Int!:
	var left = self.parse_mul()?
	while self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		right := self.parse_mul()?
		left = self.add(Node(kind: NK.KBin, s: op, a: left, b: right))
	return ok(left)

fn var Parser.parse_mul() Int!:
	var left = self.parse_unary()?
	while self.is_op("*") or self.is_op("/"):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		right := self.parse_unary()?
		left = self.add(Node(kind: NK.KBin, s: op, a: left, b: right))
	return ok(left)

fn var Parser.parse_unary() Int!:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].s.clone()
		self.pos += 1
		inner := self.parse_unary()?
		return ok(self.add(Node(kind: NK.KUn, s: op, a: inner)))
	return self.parse_pow()

fn var Parser.parse_pow() Int!:
	base := self.parse_primary()?
	if self.is_op("^"):
		self.pos += 1
		ex := self.parse_unary()?
		return ok(self.add(Node(kind: NK.KBin, s: "^", a: base, b: ex)))
	return ok(base)

fn var Parser.add_prec(row: Int, col: Int) Unit:
	self.precs.append((row - 1) * 26 + col)

fn var Parser.parse_primary() Int!:
	if self.pos >= self.toks.length(): return error(Error("parse"))
	t := self.toks[self.pos].clone()
	self.pos += 1
	if t.kind == 0:
		x := parse_num(t.s).get(0.0)
		return ok(self.add(Node(kind: NK.KNum, n: x)))
	if t.kind == 1:
		return ok(self.add(Node(kind: NK.KStr, s: t.s.clone())))
	if t.kind == 2:
		info := ref_info(t.s)
		if not info.valid: return ok(self.add(Node(kind: NK.KBadRef)))
		self.add_prec(info.row, info.col)
		return ok(self.add(Node(kind: NK.KRef, a: info.row, b: info.col)))
	if t.kind == 3:
		i1 := ref_info(t.s)
		i2 := ref_info(t.s2)
		if not i1.valid or not i2.valid: return ok(self.add(Node(kind: NK.KBadRange)))
		r1 := if i1.row < i2.row: i1.row else: i2.row
		r2 := if i1.row < i2.row: i2.row else: i1.row
		c1 := if i1.col < i2.col: i1.col else: i2.col
		c2 := if i1.col < i2.col: i2.col else: i1.col
		for r in r1..r2 + 1:
			for c in c1..c2 + 1:
				self.add_prec(r, c)
		return ok(self.add(Node(kind: NK.KRange, a: r1, b: c1, c: r2, d: c2, args: [i1.row, i1.col])))
	if t.kind == 4:
		return ok(self.add(Node(kind: NK.KErrLit)))
	if t.kind == 5:
		if self.is_op("("):
			self.pos += 1
			name := t.s.upper()
			keep := self.precs.length()
			var args = List[Int]()
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.parse_cmp()?
					args.append(a)
					if self.is_op(","):
						self.pos += 1
						continue
					if self.is_op(")"):
						self.pos += 1
						break
					return error(Error("parse"))
			if name == "ROW" or name == "COLUMN":
				while self.precs.length() > keep:
					_ := self.precs.pop()
			return ok(self.add(Node(kind: NK.KCall, s: name, args: args)))
		u := t.s.upper()
		if u == "TRUE": return ok(self.add(Node(kind: NK.KBool, n: 1.0)))
		if u == "FALSE": return ok(self.add(Node(kind: NK.KBool, n: 0.0)))
		return ok(self.add(Node(kind: NK.KName)))
	if t.s == "(":
		inner := self.parse_cmp()?
		if not self.is_op(")"): return error(Error("parse"))
		self.pos += 1
		return ok(self.add(Node(kind: NK.KParen, a: inner)))
	return error(Error("parse"))

// ---------- evaluation ----------

fn cell_val(vals: List[Val], row: Int, col: Int) Val:
	return vals[(row - 1) * 26 + col].clone()

fn collect(vals: List[Val], nodes: List[Node], args: List[Int], from: Int) List[Item]:
	var out = List[Item]()
	var k = from
	while k < args.length():
		i := args[k]
		if nodes[i].kind == NK.KRange:
			for r in nodes[i].a..nodes[i].c + 1:
				for c in nodes[i].b..nodes[i].d + 1:
					out.append(Item(v: cell_val(vals, r, c), direct: false))
		else:
			out.append(Item(v: eval(vals, nodes, i), direct: true))
		k += 1
	return out

fn gather_nums(items: List[Item]) NumList:
	var nums = List[Float]()
	for it in items:
		if is_err(it.v): return NumList(failed: true, err: it.v.clone(), nums: nums)
		if it.direct:
			c := coerce(it.v)
			if is_err(c): return NumList(failed: true, err: c, nums: nums)
			nums.append(nv(c))
		else:
			match it.v:
				Num(n): nums.append(n)
				_: unit
	return NumList(failed: false, err: Val.Empty, nums: nums)

fn arg_num(vals: List[Val], nodes: List[Node], args: List[Int], k: Int) Val:
	return coerce(eval(vals, nodes, args[k]))

fn arg_text(vals: List[Val], nodes: List[Node], args: List[Int], k: Int) Val:
	v := eval(vals, nodes, args[k])
	if is_err(v): return v
	return Val.Text(str_of(v))

fn flo(x: Float) Int:
	y := if x > 1e12: 1e12 else: (if x < -1e12: -1e12 else: x)
	return floor(y).truncate_to_int().get(0)

fn half_away(y: Float) Float:
	a := if y < 0.0: -y else: y
	t := floor(a)
	r := if a - t >= 0.5: t + 1.0 else: t
	return if y < 0.0: -r else: r

fn take(cs: List[String], a: Int, b: Int) String:
	return join_range(cs, a, b)

fn eval_call(vals: List[Val], nodes: List[Node], i: Int) Val:
	name := nodes[i].s.clone()
	args := nodes[i].args.clone()
	na := args.length()
	if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN":
		if na < 1: return err("#VALUE!")
		g := gather_nums(collect(vals, nodes, args, 0))
		if g.failed: return g.err.clone()
		nums := g.nums
		cnt := nums.length()
		if name == "SUM":
			var s = 0.0
			for x in nums: s += x
			return num_res(s)
		if name == "PRODUCT":
			if cnt == 0: return Val.Num(0.0)
			var p = 1.0
			for x in nums: p = p * x
			return num_res(p)
		if name == "AVERAGE":
			if cnt == 0: return err("#DIV/0!")
			var s = 0.0
			for x in nums: s += x
			return num_res(s / cnt.to_float())
		if name == "MIN":
			if cnt == 0: return Val.Num(0.0)
			var m = nums[0]
			for x in nums:
				if x < m: m = x
			return Val.Num(m)
		if name == "MAX":
			if cnt == 0: return Val.Num(0.0)
			var m = nums[0]
			for x in nums:
				if x > m: m = x
			return Val.Num(m)
		if cnt == 0: return err("#NUM!")
		var sorted = nums.clone()
		sorted.sort()
		if cnt % 2 == 1: return Val.Num(sorted[cnt / 2])
		return num_res((sorted[cnt / 2 - 1] + sorted[cnt / 2]) / 2.0)
	if name == "COUNT" or name == "COUNTA":
		if na < 1: return err("#VALUE!")
		var c = 0
		for it in collect(vals, nodes, args, 0):
			if name == "COUNT":
				match it.v:
					Num(_n): c += 1
					_: unit
			else:
				if not is_empty(it.v): c += 1
		return Val.Num(c.to_float())
	if name == "IF":
		if na < 2 or na > 3: return err("#VALUE!")
		c := bcoerce(eval(vals, nodes, args[0]))
		if is_err(c): return c
		if bv(c): return eval(vals, nodes, args[1])
		if na == 3: return eval(vals, nodes, args[2])
		return Val.Bool(false)
	if name == "IFERROR":
		if na != 2: return err("#VALUE!")
		a := eval(vals, nodes, args[0])
		if is_err(a): return eval(vals, nodes, args[1])
		return a
	if name == "CHOOSE":
		if na < 2: return err("#VALUE!")
		c := arg_num(vals, nodes, args, 0)
		if is_err(c): return c
		k := flo(nv(c))
		if k < 1 or k > na - 1: return err("#VALUE!")
		return eval(vals, nodes, args[k])
	if name == "AND" or name == "OR":
		if na < 1: return err("#VALUE!")
		var took = false
		var acc = name == "AND"
		for it in collect(vals, nodes, args, 0):
			if is_err(it.v): return it.v.clone()
			if not it.direct:
				match it.v:
					Text(_s): continue
					Empty: continue
					_: unit
			b := bcoerce(it.v)
			if is_err(b): return b
			took = true
			if name == "AND": acc = acc and bv(b)
			else: acc = acc or bv(b)
		if not took: return err("#VALUE!")
		return Val.Bool(acc)
	if name == "NOT":
		if na != 1: return err("#VALUE!")
		c := bcoerce(eval(vals, nodes, args[0]))
		if is_err(c): return c
		return Val.Bool(not bv(c))
	if name == "ABS" or name == "INT" or name == "SQRT":
		if na != 1: return err("#VALUE!")
		c := arg_num(vals, nodes, args, 0)
		if is_err(c): return c
		x := nv(c)
		if name == "ABS": return Val.Num(if x < 0.0: -x else: x)
		if name == "INT": return num_res(floor(x))
		if x < 0.0: return err("#NUM!")
		return num_res(sqrt(x))
	if name == "POW" or name == "MOD":
		if na != 2: return err("#VALUE!")
		a := arg_num(vals, nodes, args, 0)
		if is_err(a): return a
		b := arg_num(vals, nodes, args, 1)
		if is_err(b): return b
		x := nv(a)
		y := nv(b)
		if name == "POW": return num_res(pow(x, y))
		if y == 0.0: return err("#DIV/0!")
		return num_res(x - y * floor(x / y))
	if name == "ROUND":
		if na < 1 or na > 2: return err("#VALUE!")
		a := arg_num(vals, nodes, args, 0)
		if is_err(a): return a
		var d = 0
		if na == 2:
			b := arg_num(vals, nodes, args, 1)
			if is_err(b): return b
			bx := nv(b)
			if bx > 100.0 or bx < -100.0: return err("#NUM!")
			d = bx.truncate_to_int().get(0)
		if d > 15 or d < -15: return err("#NUM!")
		p := pow(10.0, d.to_float())
		return num_res(half_away(nv(a) * p) / p)
	if name == "LEN":
		if na != 1: return err("#VALUE!")
		t := arg_text(vals, nodes, args, 0)
		if is_err(t): return t
		return Val.Num(str_of(t).scalar_length().to_float())
	if name == "UPPER" or name == "LOWER":
		if na != 1: return err("#VALUE!")
		t := arg_text(vals, nodes, args, 0)
		if is_err(t): return t
		var out = ""
		for c in str_of(t).chars():
			if is_letter(c): out += if name == "UPPER": c.upper() else: c.lower()
			else: out += c
		return Val.Text(out)
	if name == "TRIM":
		if na != 1: return err("#VALUE!")
		t := arg_text(vals, nodes, args, 0)
		if is_err(t): return t
		var out = ""
		var pending = false
		for c in str_of(t).chars():
			if c.trim() == "":
				pending = true
			else:
				if pending and out.length() > 0: out += " "
				pending = false
				out += c
		return Val.Text(out)
	if name == "LEFT" or name == "RIGHT":
		if na < 1 or na > 2: return err("#VALUE!")
		t := arg_text(vals, nodes, args, 0)
		if is_err(t): return t
		var n = 1
		if na == 2:
			c := arg_num(vals, nodes, args, 1)
			if is_err(c): return c
			n = flo(nv(c))
		if n < 0: return err("#VALUE!")
		cs := str_of(t).chars()
		len := cs.length()
		k := if n > len: len else: n
		if name == "LEFT": return Val.Text(take(cs, 0, k))
		return Val.Text(take(cs, len - k, len))
	if name == "MID":
		if na != 3: return err("#VALUE!")
		t := arg_text(vals, nodes, args, 0)
		if is_err(t): return t
		a := arg_num(vals, nodes, args, 1)
		if is_err(a): return a
		b := arg_num(vals, nodes, args, 2)
		if is_err(b): return b
		st := flo(nv(a))
		ln := flo(nv(b))
		if st < 1 or ln < 0: return err("#VALUE!")
		cs := str_of(t).chars()
		if st > cs.length(): return Val.Text("")
		e := if st - 1 + ln > cs.length(): cs.length() else: st - 1 + ln
		return Val.Text(take(cs, st - 1, e))
	if name == "CONCAT":
		if na < 1: return err("#VALUE!")
		var out = ""
		for it in collect(vals, nodes, args, 0):
			if is_err(it.v): return it.v.clone()
			out += str_of(it.v)
		return Val.Text(out)
	if name == "SUBSTITUTE":
		if na != 3: return err("#VALUE!")
		s := arg_text(vals, nodes, args, 0)
		if is_err(s): return s
		o := arg_text(vals, nodes, args, 1)
		if is_err(o): return o
		w := arg_text(vals, nodes, args, 2)
		if is_err(w): return w
		os := str_of(o)
		if os == "": return s
		return Val.Text(str_of(s).replace(os, str_of(w)))
	if name == "VALUE":
		if na != 1: return err("#VALUE!")
		v := eval(vals, nodes, args[0])
		return coerce(v)
	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if na != 1: return err("#VALUE!")
		v := eval(vals, nodes, args[0])
		t := tag(v)
		if name == "ISERROR": return Val.Bool(t == 4)
		if name == "ISBLANK": return Val.Bool(t == 0)
		if name == "ISNUMBER": return Val.Bool(t == 1)
		return Val.Bool(t == 2)
	if name == "ROW" or name == "COLUMN":
		if na != 1: return err("#VALUE!")
		nd := nodes[args[0]]
		if nd.kind == NK.KRef:
			return Val.Num((if name == "ROW": nd.a else: nd.b + 1).to_float())
		if nd.kind == NK.KRange:
			return Val.Num((if name == "ROW": nd.args[0] else: nd.args[1] + 1).to_float())
		if nd.kind == NK.KBadRef or nd.kind == NK.KBadRange: return err("#REF!")
		return err("#VALUE!")
	if name == "INDEX":
		if na < 2 or na > 3: return err("#VALUE!")
		nd := nodes[args[0]]
		if nd.kind == NK.KBadRange: return err("#REF!")
		if nd.kind != NK.KRange: return err("#VALUE!")
		nrows := nd.c - nd.a + 1
		ncols := nd.d - nd.b + 1
		a := arg_num(vals, nodes, args, 1)
		if is_err(a): return a
		var r = flo(nv(a))
		var c = 1
		if na == 3:
			b := arg_num(vals, nodes, args, 2)
			if is_err(b): return b
			c = flo(nv(b))
		else:
			if nrows == 1:
				c = r
				r = 1
		if r < 1 or r > nrows or c < 1 or c > ncols: return err("#REF!")
		return cell_val(vals, nd.a + r - 1, nd.b + c - 1)
	if name == "COUNTIF":
		if na != 2: return err("#VALUE!")
		nd := nodes[args[0]]
		if nd.kind == NK.KBadRange: return err("#REF!")
		if nd.kind != NK.KRange: return err("#VALUE!")
		crit := eval(vals, nodes, args[1])
		if is_err(crit): return crit
		var op = "="
		var operand = crit.clone()
		match crit:
			Text(s):
				var rest = s.clone()
				for o in [">=", "<=", "<>", ">", "<", "="]:
					if s.starts_with(o):
						op = o.clone()
						rest = s.replace_first(o, "")
						break
				if x := parse_num(rest): operand = Val.Num(x)
				else: operand = Val.Text(rest)
			_: unit
		var cnt = 0
		for r in nd.a..nd.c + 1:
			for c in nd.b..nd.d + 1:
				v := cell_val(vals, r, c)
				if tag(v) == tag(operand):
					k := compare(v, operand)
					ok := if op == "=": k == 0 else: (if op == "<>": k != 0 else: (if op == ">": k > 0 else: (if op == "<": k < 0 else: (if op == ">=": k >= 0 else: k <= 0))))
					if ok: cnt += 1
				else:
					if op == "<>" and not is_empty(v): cnt += 1
		return Val.Num(cnt.to_float())
	return err("#NAME?")

fn eval(vals: List[Val], nodes: List[Node], i: Int) Val:
	match nodes[i].kind:
		KNum: return Val.Num(nodes[i].n)
		KStr: return Val.Text(nodes[i].s.clone())
		KBool: return Val.Bool(nodes[i].n != 0.0)
		KRef: return cell_val(vals, nodes[i].a, nodes[i].b)
		KRange: return err("#VALUE!")
		KBadRef: return err("#REF!")
		KBadRange: return err("#REF!")
		KErrLit: return err("#REF!")
		KName: return err("#NAME?")
		KCall: return eval_call(vals, nodes, i)
		KParen: return eval(vals, nodes, nodes[i].a)
		KUn:
			v := coerce(eval(vals, nodes, nodes[i].a))
			if is_err(v): return v
			x := nv(v)
			return Val.Num(if nodes[i].s == "-": -x else: x)
		KBin:
			l := eval(vals, nodes, nodes[i].a)
			r := eval(vals, nodes, nodes[i].b)
			return eval_bin(nodes[i].s, l, r)

fn eval_bin(op: String, l: Val, r: Val) Val:
	if op == "&":
		if is_err(l): return l.clone()
		if is_err(r): return r.clone()
		return Val.Text(str_of(l) + str_of(r))
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if is_err(l): return l.clone()
		if is_err(r): return r.clone()
		k := compare(l, r)
		res := if op == "=": k == 0 else: (if op == "<>": k != 0 else: (if op == "<": k < 0 else: (if op == "<=": k <= 0 else: (if op == ">": k > 0 else: k >= 0))))
		return Val.Bool(res)
	a := coerce(l)
	if is_err(a): return a.clone()
	b := coerce(r)
	if is_err(b): return b.clone()
	x := nv(a)
	y := nv(b)
	if op == "+": return num_res(x + y)
	if op == "-": return num_res(x - y)
	if op == "*": return num_res(x * y)
	if op == "/":
		if y == 0.0: return err("#DIV/0!")
		return num_res(x / y)
	return num_res(pow(x, y))

// ---------- sheet ----------

type Sheet:
	raw: List[String]
	kind: List[Int]
	vals: List[Val]
	roots: List[Int]
	asts: List[List[Node]]
	precs: List[List[Int]]
	deps: List[List[Int]]
	evals: Int = 0

fn new_sheet() Sheet:
	var raw = List[String]()
	var kind = List[Int]()
	var vals = List[Val]()
	var roots = List[Int]()
	var asts = List[List[Node]]()
	var precs = List[List[Int]]()
	var deps = List[List[Int]]()
	for _i in 0..26 * 999:
		raw.append("")
		kind.append(0)
		vals.append(Val.Empty)
		roots.append(-1)
		asts.append(List[Node]())
		precs.append(List[Int]())
		deps.append(List[Int]())
	return Sheet(raw: raw, kind: kind, vals: vals, roots: roots, asts: asts, precs: precs, deps: deps)

fn var Sheet.assign(idx: Int, value: String) Unit:
	if self.kind[idx] == 4:
		for p in self.precs[idx].clone():
			var k = 0
			var lst = self.deps[p].clone()
			while k < lst.length():
				if lst[k] == idx:
					lst[k] = lst[lst.length() - 1]
					_ := lst.pop()
					break
				k += 1
			self.deps[p] = lst
		self.precs[idx] = List[Int]()
		self.asts[idx] = List[Node]()
		self.roots[idx] = -1
	self.raw[idx] = value.clone()
	if value == "":
		self.kind[idx] = 0
		self.vals[idx] = Val.Empty
		return
	if value.starts_with("="):
		self.kind[idx] = 4
		self.vals[idx] = err("#PARSE!")
		src := value.replace_first("=", "")
		cs := src.chars()
		lr := lex(cs)
		if toks := lr:
			var p = Parser(toks: toks)
			pr := p.parse_cmp()
			if root := pr:
				if p.pos == p.toks.length():
					var ps = p.precs.clone()
					ps.sort()
					var uniq = List[Int]()
					for x in ps:
						if uniq.length() == 0 or uniq[uniq.length() - 1] != x: uniq.append(x)
					for x in uniq: self.deps[x].append(idx)
					self.precs[idx] = uniq
					self.asts[idx] = p.nodes.clone()
					self.roots[idx] = root
		return
	if value.starts_with("'"):
		self.kind[idx] = 2
		self.vals[idx] = Val.Text(value.replace_first("'", ""))
		return
	if x := parse_num(value):
		self.kind[idx] = 1
		self.vals[idx] = Val.Num(x)
		return
	u := value.upper()
	if u == "TRUE" or u == "FALSE":
		self.kind[idx] = 3
		self.vals[idx] = Val.Bool(u == "TRUE")
		return
	self.kind[idx] = 2
	self.vals[idx] = Val.Text(value.clone())

fn var Sheet.recalc(changed: List[Int]) Int:
	var marked = Set[Int]()
	var queue = List[Int]()
	for c in changed:
		if not marked.contains(c):
			marked.add(c)
			queue.append(c)
	var qi = 0
	while qi < queue.length():
		u := queue[qi]
		qi += 1
		for w in self.deps[u]:
			if not marked.contains(w):
				marked.add(w)
				queue.append(w)
	var nodes = List[Int]()
	for u in queue:
		if self.kind[u] == 4: nodes.append(u)
	// iterative Tarjan
	var index = Map[Int, Int]()
	var low = Map[Int, Int]()
	var onstack = Set[Int]()
	var stack = List[Int]()
	var sccs = List[List[Int]]()
	var counter = 0
	for v in nodes:
		if index.contains(v): continue
		var csn = List[Int]()
		var csp = List[Int]()
		index[v] = counter
		low[v] = counter
		counter += 1
		stack.append(v)
		onstack.add(v)
		csn.append(v)
		csp.append(0)
		while csn.length() > 0:
			top := csn.length() - 1
			u := csn[top]
			pos := csp[top]
			if pos < self.deps[u].length():
				csp[top] = pos + 1
				w := self.deps[u][pos]
				if not index.contains(w):
					index[w] = counter
					low[w] = counter
					counter += 1
					stack.append(w)
					onstack.add(w)
					csn.append(w)
					csp.append(0)
				else:
					if onstack.contains(w):
						lu := low.get_or(u, 0)
						iw := index.get_or(w, 0)
						if iw < lu: low[u] = iw
			else:
				_a := csn.pop()
				_b := csp.pop()
				if low.get_or(u, 0) == index.get_or(u, 0):
					var comp = List[Int]()
					while true:
						w := stack.pop().get(-1)
						onstack.remove(w)
						comp.append(w)
						if w == u: break
					sccs.append(comp)
				if csn.length() > 0:
					par := csn[csn.length() - 1]
					lp := low.get_or(par, 0)
					lu := low.get_or(u, 0)
					if lu < lp: low[par] = lu
	var si = sccs.length() - 1
	while si >= 0:
		comp := sccs[si]
		si -= 1
		var cyc = comp.length() > 1
		if comp.length() == 1:
			u := comp[0]
			for w in self.deps[u]:
				if w == u: cyc = true
		if cyc:
			for u in comp: self.vals[u] = err("#CYCLE!")
		else:
			u := comp[0]
			if self.roots[u] < 0:
				self.vals[u] = err("#PARSE!")
			else:
				v := eval(self.vals, self.asts[u], self.roots[u])
				if is_empty(v): self.vals[u] = Val.Num(0.0)
				else: self.vals[u] = v
	self.evals += nodes.length()
	return nodes.length()

// ---------- shifting ----------

fn shift_ref(t: String, dc: Int, dr: Int) String:
	info := ref_info(t)
	if not info.valid: return t.clone()
	col := if info.cabs: info.col else: info.col + dc
	row := if info.rabs: info.row else: info.row + dr
	if col < 0 or col > 25 or row < 1 or row > 999: return "#REF!"
	return (if info.cabs: "$" else: "") + col_letter(col) + (if info.rabs: "$" else: "") + "{row}"

fn shift_formula(src: String, dc: Int, dr: Int) String:
	cs := src.chars()
	lr := lex(cs)
	if toks := lr:
		var out = ""
		var pos = 0
		for t in toks:
			if t.kind == 2:
				out += join_range(cs, pos, t.start)
				out += shift_ref(t.s, dc, dr)
				pos = t.end
			else:
				if t.kind == 3:
					out += join_range(cs, pos, t.start)
					pos = t.end
					i1 := ref_info(t.s)
					i2 := ref_info(t.s2)
					if not i1.valid or not i2.valid:
						out += t.s + ":" + t.s2
					else:
						a := shift_ref(t.s, dc, dr)
						b := shift_ref(t.s2, dc, dr)
						if a == "#REF!" or b == "#REF!": out += "#REF!"
						else: out += a + ":" + b
		out += join_range(cs, pos, cs.length())
		return out
	return src.clone()

// ---------- csv ----------

fn parse_csv(text: String) List[List[String]]:
	var recs = List[List[String]]()
	var cur = List[String]()
	var field = ""
	var inq = false
	var touched = false
	cs := text.chars()
	var i = 0
	while i < cs.length():
		c := cs[i]
		i += 1
		if inq:
			if c == "\"":
				if ch(cs, i) == "\"":
					field += "\""
					i += 1
				else:
					inq = false
			else:
				field += c
			continue
		if c == "\"":
			inq = true
			touched = true
		else if c == ",":
			cur.append(field.clone())
			field = ""
			touched = true
		else if c == "\n":
			if touched:
				cur.append(field.clone())
				recs.append(cur.clone())
			cur = List[String]()
			field = ""
			touched = false
		else if c == "\r":
			unit
		else:
			field += c
			touched = true
	if touched:
		cur.append(field.clone())
		recs.append(cur.clone())
	return recs

fn csv_field(s: String) String:
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r") or s.starts_with(" ") or s.ends_with(" "):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s.clone()

// ---------- commands ----------

fn usage_for(cmd: String) String:
	if cmd == "set": return "usage: set CELL VALUE"
	if cmd == "clear": return "usage: clear CELL"
	if cmd == "get": return "usage: get CELL"
	if cmd == "show": return "usage: show CELL"
	if cmd == "copy": return "usage: copy SRC DST"
	if cmd == "import": return "usage: import CELL"
	if cmd == "precedents": return "usage: precedents CELL"
	if cmd == "dependents": return "usage: dependents CELL"
	if cmd == "print": return "usage: print [RANGE]"
	return "usage: export [formulas] [RANGE]"

fn Sheet.display(idx: Int) String: str_of(self.vals[idx])

fn Sheet.render(r: Rng, mode: Int, csv: Bool) String:
	var lines = List[String]()
	for row in r.r1..r.r2 + 1:
		var fields = List[String]()
		for col in r.c1..r.c2 + 1:
			idx := (row - 1) * 26 + col
			s := if mode == 1: self.raw[idx].clone() else: self.display(idx)
			fields.append(if csv: csv_field(s) else: s)
		lines.append(fields.join(if csv: "," else: " | "))
	return lines.join("\n")

fn var Sheet.exec(line: String, block: List[String]) String:
	t := line.trim()
	p := split_first(t)
	cmd := p.a
	rest := p.b
	args := words(rest)
	if cmd == "set":
		if rest == "": return "error: " + usage_for(cmd)
		q := split_first(rest)
		idx := parse_cell(q.a)
		if idx < 0: return "error: bad cell reference '{q.a}'"
		self.assign(idx, q.b)
		n := self.recalc([idx])
		return "recalc {n}"
	if cmd == "clear":
		if args.length() != 1: return "error: " + usage_for(cmd)
		idx := parse_cell(args[0])
		if idx < 0: return "error: bad cell reference '{args[0]}'"
		self.assign(idx, "")
		n := self.recalc([idx])
		return "recalc {n}"
	if cmd == "get" or cmd == "show" or cmd == "precedents" or cmd == "dependents":
		if args.length() != 1: return "error: " + usage_for(cmd)
		idx := parse_cell(args[0])
		if idx < 0: return "error: bad cell reference '{args[0]}'"
		if cmd == "get":
			if self.kind[idx] == 0: return "(empty)"
			return self.display(idx)
		if cmd == "show":
			name := cell_name(idx)
			if self.kind[idx] == 0: return "{name}: (empty)"
			if self.kind[idx] == 4: return "{name}: {self.raw[idx]} => {self.display(idx)}"
			return "{name}: {self.raw[idx]}"
		if cmd == "precedents":
			if self.precs[idx].length() == 0: return "(none)"
			return self.precs[idx] | .map(fn x: cell_name(x)) | .join(" ")
		var seen = Set[Int]()
		var queue = List[Int]()
		queue.append(idx)
		var qi = 0
		while qi < queue.length():
			u := queue[qi]
			qi += 1
			for w in self.deps[u]:
				if not seen.contains(w):
					seen.add(w)
					queue.append(w)
		var out = List[Int]()
		for w in seen.values(): out.append(w)
		if out.length() == 0: return "(none)"
		out.sort()
		return out | .map(fn x: cell_name(x)) | .join(" ")
	if cmd == "copy":
		if args.length() != 2: return "error: " + usage_for(cmd)
		src := parse_cell(args[0])
		if src < 0: return "error: bad cell reference '{args[0]}'"
		dst := parse_range(args[1])
		if not dst.ok: return "error: bad range '{args[1]}'"
		skind := self.kind[src]
		sraw := self.raw[src].clone()
		sc := src % 26
		sr := src / 26 + 1
		var changed = List[Int]()
		for row in dst.r1..dst.r2 + 1:
			for col in dst.c1..dst.c2 + 1:
				idx := (row - 1) * 26 + col
				var v = ""
				if skind == 4:
					body := sraw.replace_first("=", "")
					v = "=" + shift_formula(body, col - sc, row - sr)
				else:
					v = sraw.clone()
				self.assign(idx, v)
				changed.append(idx)
		n := self.recalc(changed)
		return "recalc {n}"
	if cmd == "import":
		if args.length() != 1: return "error: " + usage_for(cmd)
		idx := parse_cell(args[0])
		if idx < 0: return "error: bad cell reference '{args[0]}'"
		recs := parse_csv(block.join("\n"))
		var cmax = 0
		for r in recs:
			if r.length() > cmax: cmax = r.length()
		r0 := idx / 26 + 1
		c0 := idx % 26
		if recs.length() > 0 and (r0 + recs.length() - 1 > 999 or c0 + cmax > 26): return "error: import out of range"
		var changed = List[Int]()
		var ri = 0
		while ri < recs.length():
			var ci = 0
			while ci < recs[ri].length():
				cidx := (r0 + ri - 1) * 26 + c0 + ci
				self.assign(cidx, recs[ri][ci].trim())
				changed.append(cidx)
				ci += 1
			ri += 1
		n := self.recalc(changed)
		return "imported {recs.length()} rows, {cmax} columns; recalc {n}"
	if cmd == "print" or cmd == "export":
		var mode = 0
		var nword = 0
		var others = List[String]()
		for a in args:
			if a == "formulas" or a == "values":
				nword += 1
				mode = if a == "formulas": 1 else: 2
			else:
				others.append(a.clone())
		if nword > 1 or others.length() > 1 or (cmd == "print" and nword > 0): return "error: " + usage_for(cmd)
		var rng = Rng(ok: true, r1: 1, c1: 0, r2: 1, c2: 0)
		if others.length() == 1:
			rng = parse_range(others[0])
			if not rng.ok: return "error: bad range '{others[0]}'"
		else:
			var maxr = 0
			var maxc = -1
			for k in 0..26 * 999:
				if self.kind[k] != 0:
					if k / 26 + 1 > maxr: maxr = k / 26 + 1
					if k % 26 > maxc: maxc = k % 26
			if maxr == 0: return "(empty sheet)"
			rng = Rng(ok: true, r1: 1, c1: 0, r2: maxr, c2: maxc)
		return self.render(rng, mode, cmd == "export")
	if cmd == "stats":
		var cells = 0
		var forms = 0
		for k in 0..26 * 999:
			if self.kind[k] != 0: cells += 1
			if self.kind[k] == 4: forms += 1
		return "cells {cells} formulas {forms} evals {self.evals}"
	return "error: unknown command '{cmd}'"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var lines = text.split("\n").clone()
	if lines.length() > 0 and lines[lines.length() - 1] == "": _ := lines.pop()
	var sheet = new_sheet()
	var out = List[String]()
	var i = 0
	while i < lines.length():
		line := lines[i]
		i += 1
		tl := line.trim()
		if tl == "" or tl.starts_with("#"): continue
		out.append("> " + line.trim_end())
		var block = List[String]()
		if split_first(tl).a == "import":
			while i < lines.length():
				l := lines[i]
				i += 1
				if l == "." or l == ".\r": break
				block.append(l.clone())
		out.append(sheet.exec(line, block))
	print(out.join("\n"))
	return ok(unit)
