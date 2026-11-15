import floor, pow, sqrt, truncate, min, max from "@std/math/math.ms"
import big_float_of_float from "@std/math/big.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes from "@std/bytes.ms"

type Value:
	t: Int = 0
	n: Float = 0.0
	s: String = ""

fn vnum(x: Float) Value: Value(t: 1, n: x)
fn vtext(s: String) Value: Value(t: 2, s: s)
fn vbool(b: Bool) Value: Value(t: 3, n: if b: 1.0 else: 0.0)
fn verr(code: String) Value: Value(t: 4, s: code)
fn cp(v: Value) Value: Value(t: v.t, n: v.n, s: v.s.clone())

fn is_digit(c: String) Bool: c >= "0" and c <= "9"
fn is_alpha(c: String) Bool: (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

fn letter_col(c: String) Int:
	u := c.upper()
	if u >= "A" and u <= "Z" and u.length() == 1:
		return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars().find_index(fn x: x == u).get(0)
	return -1

fn col_name(c: Int) String:
	return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars().get(c, "?")

fn cell_name(idx: Int) String:
	return "{col_name(idx % 26)}{idx / 26 + 1}"

fn tail1(s: String) String:
	if r := s.slice(1, s.length()):
		return r
	return ""

fn parse_num(s: String) Float?:
	cs := s.chars()
	n := cs.length()
	var i = 0
	var sign = ""
	if i < n and (cs[i] == "+" or cs[i] == "-"):
		if cs[i] == "-":
			sign = "-"
		i += 1
	var ip = ""
	while i < n and is_digit(cs[i]):
		ip += cs[i]
		i += 1
	var fp = ""
	if i < n and cs[i] == ".":
		i += 1
		while i < n and is_digit(cs[i]):
			fp += cs[i]
			i += 1
	if ip.length() == 0 and fp.length() == 0:
		return none
	var ex = ""
	if i < n and (cs[i] == "e" or cs[i] == "E"):
		i += 1
		var es = ""
		if i < n and (cs[i] == "+" or cs[i] == "-"):
			es = cs[i].clone()
			i += 1
		var ed = ""
		while i < n and is_digit(cs[i]):
			ed += cs[i]
			i += 1
		if ed.length() == 0:
			return none
		ex = "e{es}{ed}"
	if i != n:
		return none
	if ip == "":
		ip = "0"
	if fp == "":
		fp = "0"
	text := "{sign}{ip}.{fp}{ex}"
	if x := text.parse_float():
		if x.is_finite():
			return x
	return none

fn fmt_num(x: Float) String:
	var s = ""
	if x >= 1e21 or x <= -1e21:
		if bf := big_float_of_float(x, 64):
			if r := bf.to_fixed(10):
				s = r
	else:
		s = x.to_fixed(10)
	cs0 := s.chars()
	var cs = cs0.clone()
	if s.contains("."):
		while cs.length() > 0 and cs.get(cs.length() - 1, "") == "0":
			cs.pop()
		if cs.length() > 0 and cs.get(cs.length() - 1, "") == ".":
			cs.pop()
	r := cs.join("")
	if r == "-0":
		return "0"
	return r

fn to_str(v: Value) String:
	if v.t == 1:
		return fmt_num(v.n)
	if v.t == 3:
		return if v.n != 0.0: "TRUE" else: "FALSE"
	if v.t == 0:
		return ""
	return v.s.clone()

// ---------- lexer ----------

type RefInfo:
	valid: Bool = false
	col: Int = 0
	row: Int = 0
	ac: Bool = false
	ar: Bool = false

type Tok:
	kind: Int = 0
	text: String = ""
	num: Float = 0.0
	start: Int = 0
	end: Int = 0
	a: RefInfo = RefInfo()
	b: RefInfo = RefInfo()

type Scan:
	info: RefInfo
	end: Int

fn scan_ref(cs: List[String], start: Int) Scan?:
	n := cs.length()
	var i = start
	var ac = false
	if i < n and cs[i] == "$":
		ac = true
		i += 1
	l0 := i
	while i < n and is_alpha(cs[i]):
		i += 1
	if i == l0:
		return none
	nl := i - l0
	letter := cs[l0].clone()
	var ar = false
	if i < n and cs[i] == "$":
		ar = true
		i += 1
	d0 := i
	var ds = ""
	while i < n and is_digit(cs[i]):
		ds += cs[i]
		i += 1
	if i == d0:
		return none
	if i < n:
		c := cs[i]
		if is_alpha(c) or is_digit(c) or c == "_" or c == "." or c == "(" or c == "$":
			return none
	nd := i - d0
	var valid = nl == 1 and nd <= 3 and cs[d0] != "0"
	var row = 0
	if valid:
		row = ds.parse_int().get(0)
		if row < 1 or row > 999:
			valid = false
	return Scan(RefInfo(valid: valid, col: letter_col(letter), row: row, ac: ac, ar: ar), i)

fn tokenize(cs: List[String]) List[Tok]?:
	var toks = List[Tok]()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i].clone()
		if c == " " or c == "\t":
			i += 1
			continue
		if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
			var j = i
			while j < n and is_digit(cs[j]):
				j += 1
			if j < n and cs[j] == ".":
				j += 1
				while j < n and is_digit(cs[j]):
					j += 1
			if j < n and (cs[j] == "e" or cs[j] == "E"):
				var k = j + 1
				if k < n and (cs[k] == "+" or cs[k] == "-"):
					k += 1
				if k < n and is_digit(cs[k]):
					while k < n and is_digit(cs[k]):
						k += 1
					j = k
			var text = ""
			for q in i..j:
				text += cs[q]
			x := parse_num(text)
			if x.is_none():
				return none
			toks.append(Tok(kind: 0, text: text, num: x.get(0.0), start: i, end: j))
			i = j
			continue
		if c == "\"":
			var j = i + 1
			var text = ""
			var closed = false
			while j < n:
				if cs[j] == "\"":
					if j + 1 < n and cs[j + 1] == "\"":
						text += "\""
						j += 2
						continue
					closed = true
					j += 1
					break
				text += cs[j]
				j += 1
			if not closed:
				return none
			toks.append(Tok(kind: 1, text: text, start: i, end: j))
			i = j
			continue
		if c == "#":
			if i + 4 < n and cs[i + 1] == "R" and cs[i + 2] == "E" and cs[i + 3] == "F" and cs[i + 4] == "!":
				toks.append(Tok(kind: 6, text: "#REF!", start: i, end: i + 5))
				i += 5
				continue
			return none
		if is_alpha(c) or c == "_" or c == "$":
			if sc := scan_ref(cs, i):
				if sc.end < n and cs[sc.end] == ":":
					if sc2 := scan_ref(cs, sc.end + 1):
						toks.append(Tok(kind: 3, start: i, end: sc2.end, a: sc.info.clone(), b: sc2.info.clone()))
						i = sc2.end
						continue
				toks.append(Tok(kind: 2, start: i, end: sc.end, a: sc.info.clone()))
				i = sc.end
				continue
			if c == "$":
				return none
			var j = i
			var text = ""
			while j < n and (is_alpha(cs[j]) or is_digit(cs[j]) or cs[j] == "_" or cs[j] == "."):
				text += cs[j]
				j += 1
			toks.append(Tok(kind: 4, text: text, start: i, end: j))
			i = j
			continue
		if i + 1 < n:
			two := "{c}{cs[i + 1]}"
			if two == "<>" or two == "<=" or two == ">=":
				toks.append(Tok(kind: 5, text: two, start: i, end: i + 2))
				i += 2
				continue
		if c == "+" or c == "-" or c == "*" or c == "/" or c == "^" or c == "&" or c == "=" or c == "<" or c == ">" or c == "(" or c == ")" or c == ",":
			toks.append(Tok(kind: 5, text: c, start: i, end: i + 1))
			i += 1
			continue
		return none
	return toks

// ---------- parser ----------

type Node:
	kind: Int = 0
	num: Float = 0.0
	s: String = ""
	a: Int = -1
	b: Int = -1
	args: List[Int] = List[Int]()
	c1: Int = 0
	r1: Int = 0
	lc: Int = 0
	hc: Int = 0
	lr: Int = 0
	hr: Int = 0

// kinds: 0 num, 1 str, 2 bool, 3 ref, 4 range, 5 bad ref, 12 bad range, 6 #REF! literal,
// 7 name, 8 call, 9 binary, 10 neg, 11 pos

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = List[Node]()
	failed: Bool = false

fn var Parser.add(nd: Node) Int:
	self.nodes.append(nd)
	return self.nodes.length() - 1

fn Parser.is_op(text: String) Bool:
	if self.pos >= self.toks.length():
		return false
	t := self.toks[self.pos].clone()
	return t.kind == 5 and t.text == text

fn var Parser.cmp() Int:
	var left = self.concat()
	while not self.failed:
		if self.pos >= self.toks.length():
			break
		t := self.toks[self.pos].clone()
		if t.kind == 5 and (t.text == "=" or t.text == "<>" or t.text == "<" or t.text == "<=" or t.text == ">" or t.text == ">="):
			op := t.text.clone()
			self.pos += 1
			right := self.concat()
			left = self.add(Node(kind: 9, s: op, a: left, b: right))
		else:
			break
	return left

fn var Parser.concat() Int:
	var left = self.addsub()
	while not self.failed and self.is_op("&"):
		self.pos += 1
		right := self.addsub()
		left = self.add(Node(kind: 9, s: "&", a: left, b: right))
	return left

fn var Parser.addsub() Int:
	var left = self.mul()
	while not self.failed and (self.is_op("+") or self.is_op("-")):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		right := self.mul()
		left = self.add(Node(kind: 9, s: op, a: left, b: right))
	return left

fn var Parser.mul() Int:
	var left = self.unary()
	while not self.failed and (self.is_op("*") or self.is_op("/")):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		right := self.unary()
		left = self.add(Node(kind: 9, s: op, a: left, b: right))
	return left

fn var Parser.unary() Int:
	if self.is_op("-"):
		self.pos += 1
		x := self.unary()
		return self.add(Node(kind: 10, a: x))
	if self.is_op("+"):
		self.pos += 1
		x := self.unary()
		return self.add(Node(kind: 11, a: x))
	return self.power()

fn var Parser.power() Int:
	base := self.primary()
	if not self.failed and self.is_op("^"):
		self.pos += 1
		ex := self.powexp()
		return self.add(Node(kind: 9, s: "^", a: base, b: ex))
	return base

fn var Parser.powexp() Int:
	if self.is_op("-"):
		self.pos += 1
		x := self.powexp()
		return self.add(Node(kind: 10, a: x))
	if self.is_op("+"):
		self.pos += 1
		x := self.powexp()
		return self.add(Node(kind: 11, a: x))
	return self.power()

fn ref_node(r: RefInfo) Node:
	if not r.valid:
		return Node(kind: 5)
	return Node(kind: 3, a: (r.row - 1) * 26 + r.col, c1: r.col, r1: r.row)

fn var Parser.primary() Int:
	if self.pos >= self.toks.length():
		self.failed = true
		return 0
	t := self.toks[self.pos].clone()
	k := t.kind
	if k == 0:
		self.pos += 1
		return self.add(Node(kind: 0, num: t.num))
	if k == 1:
		self.pos += 1
		return self.add(Node(kind: 1, s: t.text.clone()))
	if k == 2:
		self.pos += 1
		return self.add(ref_node(t.a))
	if k == 3:
		self.pos += 1
		if t.a.valid and t.b.valid:
			return self.add(Node(kind: 4, c1: t.a.col, r1: t.a.row, lc: min(t.a.col, t.b.col), hc: max(t.a.col, t.b.col), lr: min(t.a.row, t.b.row), hr: max(t.a.row, t.b.row)))
		return self.add(Node(kind: 12))
	if k == 6:
		self.pos += 1
		return self.add(Node(kind: 6))
	if k == 4:
		self.pos += 1
		if self.is_op("("):
			self.pos += 1
			var args = List[Int]()
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.cmp()
					if self.failed:
						return 0
					args.append(a)
					if self.is_op(","):
						self.pos += 1
						continue
					if self.is_op(")"):
						self.pos += 1
						break
					self.failed = true
					return 0
			return self.add(Node(kind: 8, s: t.text.upper(), args: args))
		up := t.text.upper()
		if up == "TRUE":
			return self.add(Node(kind: 2, num: 1.0))
		if up == "FALSE":
			return self.add(Node(kind: 2, num: 0.0))
		return self.add(Node(kind: 7))
	if k == 5 and t.text == "(":
		self.pos += 1
		x := self.cmp()
		if self.failed:
			return 0
		if self.is_op(")"):
			self.pos += 1
			return x
		self.failed = true
		return 0
	self.failed = true
	return 0

// ---------- cells ----------

type Cell:
	raw: String = ""
	kind: Int = 0
	v: Value = Value()
	nodes: List[Node] = List[Node]()
	root: Int = -1
	perr: Bool = false
	precs: List[Int] = List[Int]()

type Sheet:
	cells: List[Cell] = List[Cell]()
	deps: List[Set[Int]] = List[Set[Int]]()
	out: List[String] = List[String]()
	evals: Int = 0

fn new_sheet() Sheet:
	var s = Sheet()
	for _i in 0..25974:
		s.cells.append(Cell())
		s.deps.append(Set[Int]())
	return s

// ---------- evaluation ----------

fn coerce_num(v: Value) Value:
	if v.t == 1 or v.t == 4:
		return cp(v)
	if v.t == 0:
		return vnum(0.0)
	if v.t == 3:
		return vnum(v.n)
	if x := parse_num(v.s.trim()):
		return vnum(x)
	return verr("#VALUE!")

fn coerce_bool(v: Value) Value:
	if v.t == 4 or v.t == 3:
		return cp(v)
	if v.t == 0:
		return vbool(false)
	if v.t == 1:
		return vbool(v.n != 0.0)
	u := v.s.upper()
	if u == "TRUE" and v.s.length() == 4:
		return vbool(true)
	if u == "FALSE" and v.s.length() == 5:
		return vbool(false)
	return verr("#VALUE!")

fn fin(x: Float) Value:
	if x.is_finite():
		return vnum(x)
	return verr("#NUM!")

fn cmp_values(a: Value, b: Value) Int:
	if a.t == 0 and b.t == 0:
		return 0
	var ta = a.t
	var na = a.n
	var sa = a.s.clone()
	var tb = b.t
	var nb = b.n
	var sb = b.s.clone()
	if ta == 0:
		ta = tb
		na = 0.0
		sa = ""
	if tb == 0:
		tb = ta
		nb = 0.0
		sb = ""
	if ta != tb:
		return if ta < tb: -1 else: 1
	if ta == 2:
		return sa.compare(sb)
	if na < nb:
		return -1
	if na > nb:
		return 1
	return 0

type Item:
	v: Value
	fromrange: Bool

fn cell_val(s: Sheet, idx: Int) Value:
	return cp(s.cells[idx].v)

fn collect(s: Sheet, c: Cell, args: List[Int], skip: Int) List[Item]:
	var items = List[Item]()
	for ai in skip..args.length():
		nd := c.nodes[args[ai]]
		if nd.kind == 4:
			for r in nd.lr..nd.hr + 1:
				for col in nd.lc..nd.hc + 1:
					items.append(Item(cell_val(s, (r - 1) * 26 + col), true))
		else:
			items.append(Item(ev(s, c, args[ai]), false))
	return items

fn round_half(y: Float) Float:
	a := if y < 0.0: -y else: y
	f := floor(a)
	r := if a - f >= 0.5: f + 1.0 else: f
	return if y < 0.0: -r else: r

fn is_ws(c: String) Bool: c == " " or c == "\t" or c == "\n" or c == "\r"

fn num_arg(s: Sheet, c: Cell, args: List[Int], i: Int) Value:
	return coerce_num(ev(s, c, args[i]))

fn str_arg(s: Sheet, c: Cell, args: List[Int], i: Int) Value:
	v := ev(s, c, args[i])
	if v.t == 4:
		return v
	return vtext(to_str(v))

fn take(cs: List[String], a: Int, b: Int) String:
	var out = ""
	for i in a..b:
		out += cs[i]
	return out

fn count_if(s: Sheet, c: Cell, nd: Node) Value:
	args := nd.args
	if args.length() != 2:
		return verr("#VALUE!")
	rn := c.nodes[args[0]]
	if rn.kind == 12:
		return verr("#REF!")
	if rn.kind != 4:
		return verr("#VALUE!")
	crit := ev(s, c, args[1])
	if crit.t == 4:
		return crit
	var op = "="
	var operand = cp(crit)
	if crit.t == 2:
		txt := crit.s.clone()
		var rest = txt.clone()
		if txt.starts_with(">="):
			op = ">="
			rest = txt.slice(2, txt.length()).get("")
		else if txt.starts_with("<="):
			op = "<="
			rest = txt.slice(2, txt.length()).get("")
		else if txt.starts_with("<>"):
			op = "<>"
			rest = txt.slice(2, txt.length()).get("")
		else if txt.starts_with(">"):
			op = ">"
			rest = txt.slice(1, txt.length()).get("")
		else if txt.starts_with("<"):
			op = "<"
			rest = txt.slice(1, txt.length()).get("")
		else if txt.starts_with("="):
			op = "="
			rest = txt.slice(1, txt.length()).get("")
		if x := parse_num(rest):
			operand = vnum(x)
		else:
			operand = vtext(rest)
	var count = 0
	for r in rn.lr..rn.hr + 1:
		for col in rn.lc..rn.hc + 1:
			cv := s.cells[(r - 1) * 26 + col].v
			if cv.t == operand.t:
				k := cmp_values(cv, operand)
				ok := if op == "=": k == 0 else if op == "<>": k != 0 else if op == ">": k > 0 else if op == "<": k < 0 else if op == ">=": k >= 0 else: k <= 0
				if ok:
					count += 1
			else:
				if op == "<>" and cv.t != 0:
					count += 1
	return vnum(count.to_float())

fn ev(s: Sheet, c: Cell, ni: Int) Value:
	nd := c.nodes[ni]
	k := nd.kind
	if k == 0:
		return vnum(nd.num)
	if k == 1:
		return vtext(nd.s.clone())
	if k == 2:
		return vbool(nd.num != 0.0)
	if k == 3:
		return cell_val(s, nd.a)
	if k == 4:
		return verr("#VALUE!")
	if k == 5 or k == 12 or k == 6:
		return verr("#REF!")
	if k == 7:
		return verr("#NAME?")
	if k == 8:
		return call(s, c, nd)
	if k == 10 or k == 11:
		x := coerce_num(ev(s, c, nd.a))
		if x.t == 4:
			return cp(x)
		return if k == 10: vnum(-x.n) else: x
	op := nd.s.clone()
	a := ev(s, c, nd.a)
	b := ev(s, c, nd.b)
	if op == "&":
		if a.t == 4:
			return cp(a)
		if b.t == 4:
			return cp(b)
		return vtext("{to_str(a)}{to_str(b)}")
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if a.t == 4:
			return cp(a)
		if b.t == 4:
			return cp(b)
		r := cmp_values(a, b)
		res := if op == "=": r == 0 else if op == "<>": r != 0 else if op == "<": r < 0 else if op == "<=": r <= 0 else if op == ">": r > 0 else: r >= 0
		return vbool(res)
	x := coerce_num(a)
	if x.t == 4:
		return cp(x)
	y := coerce_num(b)
	if y.t == 4:
		return cp(y)
	if op == "+":
		return fin(x.n + y.n)
	if op == "-":
		return fin(x.n - y.n)
	if op == "*":
		return fin(x.n * y.n)
	if op == "/":
		if y.n == 0.0:
			return verr("#DIV/0!")
		return fin(x.n / y.n)
	return fin(pow(x.n, y.n))

fn call(s: Sheet, c: Cell, nd: Node) Value:
	f := nd.s.clone()
	args := nd.args
	na := args.length()
	bad := verr("#VALUE!")
	if f == "SUM" or f == "AVERAGE" or f == "MIN" or f == "MAX" or f == "PRODUCT" or f == "MEDIAN":
		if na < 1:
			return bad
		items := collect(s, c, args, 0)
		var nums = List[Float]()
		for it in items:
			if it.v.t == 4:
				return cp(it.v)
			if it.fromrange:
				if it.v.t == 1:
					nums.append(it.v.n)
			else:
				x := coerce_num(it.v)
				if x.t == 4:
					return x
				nums.append(x.n)
		cnt := nums.length()
		if f == "SUM":
			var t = 0.0
			for x in nums:
				t += x
			return fin(t)
		if f == "PRODUCT":
			if cnt == 0:
				return vnum(0.0)
			var t = 1.0
			for x in nums:
				t *= x
			return fin(t)
		if f == "AVERAGE":
			if cnt == 0:
				return verr("#DIV/0!")
			var t = 0.0
			for x in nums:
				t += x
			return fin(t / cnt.to_float())
		if f == "MIN" or f == "MAX":
			if cnt == 0:
				return vnum(0.0)
			var m = nums[0]
			for x in nums:
				if f == "MIN" and x < m:
					m = x
				if f == "MAX" and x > m:
					m = x
			return vnum(m)
		if cnt == 0:
			return verr("#NUM!")
		nums.sort()
		if cnt % 2 == 1:
			return vnum(nums[cnt / 2])
		return fin((nums[cnt / 2 - 1] + nums[cnt / 2]) / 2.0)
	if f == "COUNT" or f == "COUNTA":
		if na < 1:
			return bad
		items := collect(s, c, args, 0)
		var n = 0
		for it in items:
			if f == "COUNT":
				if it.v.t == 1:
					n += 1
			else:
				if it.v.t != 0:
					n += 1
		return vnum(n.to_float())
	if f == "IF":
		if na < 2 or na > 3:
			return bad
		cv := coerce_bool(ev(s, c, args[0]))
		if cv.t == 4:
			return cv
		if cv.n != 0.0:
			return ev(s, c, args[1])
		if na == 3:
			return ev(s, c, args[2])
		return vbool(false)
	if f == "IFERROR":
		if na != 2:
			return bad
		a := ev(s, c, args[0])
		if a.t == 4:
			return ev(s, c, args[1])
		return a
	if f == "CHOOSE":
		if na < 2:
			return bad
		i := num_arg(s, c, args, 0)
		if i.t == 4:
			return i
		fl := floor(i.n)
		if fl < 1.0 or fl > (na - 1).to_float():
			return bad
		return ev(s, c, args[fl.truncate_to_int().get(1)])
	if f == "AND" or f == "OR":
		if na < 1:
			return bad
		items := collect(s, c, args, 0)
		var took = false
		var acc = f == "AND"
		for it in items:
			if it.v.t == 4:
				return cp(it.v)
			if it.fromrange and (it.v.t == 2 or it.v.t == 0):
				continue
			b := coerce_bool(it.v)
			if b.t == 4:
				return b
			took = true
			if f == "AND":
				acc = acc and b.n != 0.0
			else:
				acc = acc or b.n != 0.0
		if not took:
			return bad
		return vbool(acc)
	if f == "NOT":
		if na != 1:
			return bad
		b := coerce_bool(ev(s, c, args[0]))
		if b.t == 4:
			return b
		return vbool(b.n == 0.0)
	if f == "ABS" or f == "INT" or f == "SQRT":
		if na != 1:
			return bad
		x := num_arg(s, c, args, 0)
		if x.t == 4:
			return x
		if f == "ABS":
			return vnum(if x.n < 0.0: -x.n else: x.n)
		if f == "INT":
			return vnum(floor(x.n))
		if x.n < 0.0:
			return verr("#NUM!")
		return fin(sqrt(x.n))
	if f == "POW" or f == "MOD":
		if na != 2:
			return bad
		a := num_arg(s, c, args, 0)
		if a.t == 4:
			return a
		b := num_arg(s, c, args, 1)
		if b.t == 4:
			return b
		if f == "POW":
			return fin(pow(a.n, b.n))
		if b.n == 0.0:
			return verr("#DIV/0!")
		return fin(a.n - b.n * floor(a.n / b.n))
	if f == "ROUND":
		if na < 1 or na > 2:
			return bad
		x := num_arg(s, c, args, 0)
		if x.t == 4:
			return x
		var d = 0.0
		if na == 2:
			dv := num_arg(s, c, args, 1)
			if dv.t == 4:
				return dv
			d = truncate(dv.n)
		if d > 15.0 or d < -15.0:
			return verr("#NUM!")
		p := pow(10.0, d)
		return fin(round_half(x.n * p) / p)
	if f == "LEN":
		if na != 1:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		return vnum(a.s.scalar_length().to_float())
	if f == "UPPER" or f == "LOWER":
		if na != 1:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		var out = ""
		for ch in a.s.chars():
			if f == "UPPER" and ch >= "a" and ch <= "z":
				out += ch.upper()
			else if f == "LOWER" and ch >= "A" and ch <= "Z":
				out += ch.lower()
			else:
				out += ch
		return vtext(out)
	if f == "TRIM":
		if na != 1:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		var out = ""
		var pending = false
		for ch in a.s.chars():
			if is_ws(ch):
				pending = true
			else:
				if pending and out.length() > 0:
					out += " "
				pending = false
				out += ch
		return vtext(out)
	if f == "LEFT" or f == "RIGHT":
		if na < 1 or na > 2:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		var cnt = 1.0
		if na == 2:
			nv := num_arg(s, c, args, 1)
			if nv.t == 4:
				return nv
			cnt = floor(nv.n)
		if cnt < 0.0:
			return bad
		cs := a.s.chars()
		len := cs.length()
		var k = len
		if cnt < len.to_float():
			k = cnt.truncate_to_int().get(0)
		if f == "LEFT":
			return vtext(take(cs, 0, k))
		return vtext(take(cs, len - k, len))
	if f == "MID":
		if na != 3:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		st := num_arg(s, c, args, 1)
		if st.t == 4:
			return st
		ln := num_arg(s, c, args, 2)
		if ln.t == 4:
			return ln
		fs := floor(st.n)
		fl := floor(ln.n)
		if fs < 1.0 or fl < 0.0:
			return bad
		cs := a.s.chars()
		len := cs.length()
		if fs > len.to_float():
			return vtext("")
		b0 := fs.truncate_to_int().get(1) - 1
		var k = len - b0
		if fl < k.to_float():
			k = fl.truncate_to_int().get(0)
		return vtext(take(cs, b0, b0 + k))
	if f == "CONCAT":
		if na < 1:
			return bad
		items := collect(s, c, args, 0)
		var out = ""
		for it in items:
			if it.v.t == 4:
				return cp(it.v)
			out += to_str(it.v)
		return vtext(out)
	if f == "SUBSTITUTE":
		if na != 3:
			return bad
		a := str_arg(s, c, args, 0)
		if a.t == 4:
			return a
		o := str_arg(s, c, args, 1)
		if o.t == 4:
			return o
		n := str_arg(s, c, args, 2)
		if n.t == 4:
			return n
		if o.s.length() == 0:
			return a
		return vtext(a.s.replace(o.s, n.s))
	if f == "VALUE":
		if na != 1:
			return bad
		v := ev(s, c, args[0])
		if v.t == 4 or v.t == 1:
			return v
		return coerce_num(v)
	if f == "ISERROR" or f == "ISBLANK" or f == "ISNUMBER" or f == "ISTEXT":
		if na != 1:
			return bad
		v := ev(s, c, args[0])
		if f == "ISERROR":
			return vbool(v.t == 4)
		if f == "ISBLANK":
			return vbool(v.t == 0)
		if f == "ISNUMBER":
			return vbool(v.t == 1)
		return vbool(v.t == 2)
	if f == "ROW" or f == "COLUMN":
		if na != 1:
			return bad
		a := c.nodes[args[0]]
		if a.kind == 5 or a.kind == 12:
			return verr("#REF!")
		if a.kind != 3 and a.kind != 4:
			return bad
		if f == "ROW":
			return vnum(a.r1.to_float())
		return vnum((a.c1 + 1).to_float())
	if f == "INDEX":
		if na < 2 or na > 3:
			return bad
		rn := c.nodes[args[0]]
		if rn.kind == 12:
			return verr("#REF!")
		if rn.kind != 4:
			return bad
		rv := num_arg(s, c, args, 1)
		if rv.t == 4:
			return rv
		var cvn = 1.0
		if na == 3:
			cv := num_arg(s, c, args, 2)
			if cv.t == 4:
				return cv
			cvn = floor(cv.n)
		rows := rn.hr - rn.lr + 1
		cols := rn.hc - rn.lc + 1
		var ri = floor(rv.n)
		var ci = cvn
		if na == 2 and rows == 1:
			ci = ri
			ri = 1.0
		if ri < 1.0 or ri > rows.to_float() or ci < 1.0 or ci > cols.to_float():
			return verr("#REF!")
		rr := rn.lr + ri.truncate_to_int().get(1) - 1
		cc := rn.lc + ci.truncate_to_int().get(1) - 1
		return cell_val(s, (rr - 1) * 26 + cc)
	if f == "COUNTIF":
		return count_if(s, c, nd)
	return verr("#NAME?")

// ---------- compile, dependencies ----------

fn gather(nodes: List[Node], root: Int) List[Int]:
	var seen = Set[Int]()
	var stack = List[Int]()
	stack.append(root)
	while stack.length() > 0:
		ni := stack.pop().get(0)
		nd := nodes[ni]
		k := nd.kind
		if k == 3:
			seen.add(nd.a)
		else if k == 4:
			for r in nd.lr..nd.hr + 1:
				for col in nd.lc..nd.hc + 1:
					seen.add((r - 1) * 26 + col)
		else if k == 8:
			if nd.s != "ROW" and nd.s != "COLUMN":
				for a in nd.args:
					stack.append(a)
		else if k == 9:
			stack.append(nd.a)
			stack.append(nd.b)
		else if k == 10 or k == 11:
			stack.append(nd.a)
	var res = List[Int]()
	for x in seen:
		res.append(x)
	res.sort()
	return res

fn compile(src: String) Cell:
	var cell = Cell(kind: 2)
	cs := src.chars()
	tk := tokenize(cs)
	if tk.is_none():
		cell.perr = true
		return cell
	var p = Parser(tk.get([]))
	root := p.cmp()
	if p.failed or p.pos != p.toks.length():
		cell.perr = true
		return cell
	cell.root = root
	cell.precs = gather(p.nodes, root)
	cell.nodes = p.nodes.clone()
	return cell

fn shift_ref(r: RefInfo, dc: Int, dr: Int) String?:
	col := if r.ac: r.col else: r.col + dc
	row := if r.ar: r.row else: r.row + dr
	if col < 0 or col > 25 or row < 1 or row > 999:
		return none
	ca := if r.ac: "$" else: ""
	ra := if r.ar: "$" else: ""
	return "{ca}{col_name(col)}{ra}{row}"

fn shift_formula(src: String, dc: Int, dr: Int) String:
	cs := src.chars()
	tk := tokenize(cs)
	if tk.is_none():
		return src.clone()
	toks := tk.get([])
	var out = ""
	var pos = 0
	for t in toks:
		out += take(cs, pos, t.start)
		if t.kind == 2 and t.a.valid:
			out += shift_ref(t.a, dc, dr).get("#REF!")
		else if t.kind == 3 and t.a.valid and t.b.valid:
			x := shift_ref(t.a, dc, dr)
			y := shift_ref(t.b, dc, dr)
			if x.is_some() and y.is_some():
				out += "{x.get("")}:{y.get("")}"
			else:
				out += "#REF!"
		else:
			out += take(cs, t.start, t.end)
		pos = t.end
	out += take(cs, pos, cs.length())
	return out

// ---------- sheet ----------

fn const_value(text: String) Value:
	if x := parse_num(text):
		return vnum(x)
	u := text.upper()
	if u == "TRUE":
		return vbool(true)
	if u == "FALSE":
		return vbool(false)
	return vtext(text.clone())

fn var Sheet.assign(i: Int, text: String) Unit:
	olds := self.cells[i].precs.clone()
	for p in olds:
		self.deps[p].remove(i)
	if text == "":
		self.cells[i] = Cell()
		return
	if text.starts_with("="):
		var cell = compile(tail1(text))
		cell.raw = text.clone()
		for p in cell.precs:
			self.deps[p].add(i)
		self.cells[i] = cell
		return
	var cell = Cell(kind: 1, raw: text.clone())
	if text.starts_with("'"):
		cell.v = vtext(tail1(text))
	else:
		cell.v = const_value(text)
	self.cells[i] = cell

fn eval_cell(s: Sheet, i: Int) Value:
	c := s.cells[i]
	if c.perr:
		return verr("#PARSE!")
	v := ev(s, c, c.root)
	if v.t == 0:
		return vnum(0.0)
	return v

fn var Sheet.recalc(changed: List[Int]) Int:
	var aff = Set[Int]()
	var queue = List[Int]()
	for ch in changed:
		queue.append(ch)
		if self.cells[ch].kind == 2:
			aff.add(ch)
	var qi = 0
	while qi < queue.length():
		u := queue[qi]
		qi += 1
		for d in self.deps[u]:
			if not aff.contains(d):
				aff.add(d)
				queue.append(d)
	var nodes = List[Int]()
	for x in aff:
		nodes.append(x)
	nodes.sort()
	var succ = Map[Int, List[Int]]()
	for u in nodes:
		var l = List[Int]()
		for d in self.deps[u]:
			if aff.contains(d):
				l.append(d)
		succ[u] = l
	// iterative Tarjan
	var idx = Map[Int, Int]()
	var low = Map[Int, Int]()
	var onst = Set[Int]()
	var stack = List[Int]()
	var comps = List[List[Int]]()
	var counter = 0
	for root in nodes:
		if idx.contains(root):
			continue
		var cs = List[Int]()
		var ci = List[Int]()
		idx[root] = counter
		low[root] = counter
		counter += 1
		stack.append(root)
		onst.add(root)
		cs.append(root)
		ci.append(0)
		while cs.length() > 0:
			top := cs.length() - 1
			u := cs[top]
			pos := ci[top]
			sl := succ.get_or(u, List[Int]())
			if pos < sl.length():
				ci[top] = pos + 1
				w := sl[pos]
				if not idx.contains(w):
					idx[w] = counter
					low[w] = counter
					counter += 1
					stack.append(w)
					onst.add(w)
					cs.append(w)
					ci.append(0)
				else if onst.contains(w):
					lu := low.get_or(u, 0)
					iw := idx.get_or(w, 0)
					if iw < lu:
						low[u] = iw
			else:
				lu := low.get_or(u, 0)
				if lu == idx.get_or(u, 0):
					var comp = List[Int]()
					while true:
						w := stack.pop().get(0)
						onst.remove(w)
						comp.append(w)
						if w == u:
							break
					comps.append(comp)
				cs.pop()
				ci.pop()
				if cs.length() > 0:
					par := cs[cs.length() - 1]
					lp := low.get_or(par, 0)
					if lu < lp:
						low[par] = lu
	var ci2 = comps.length() - 1
	while ci2 >= 0:
		comp := comps[ci2]
		ci2 -= 1
		var cyc = comp.length() > 1
		if comp.length() == 1:
			u := comp[0]
			cyc = succ.get_or(u, List[Int]()).contains(u)
		if cyc:
			for u in comp:
				self.cells[u].v = verr("#CYCLE!")
		else:
			u := comp[0]
			r := eval_cell(self, u)
			self.cells[u].v = r
	n := nodes.length()
	self.evals += n
	return n

// ---------- argument parsing ----------

type Rect:
	lc: Int
	hc: Int
	lr: Int
	hr: Int

fn parse_cell_arg(t: String) Int?:
	cs := t.chars()
	n := cs.length()
	if n < 2 or n > 4:
		return none
	col := letter_col(cs[0])
	if col < 0:
		return none
	if cs[1] == "0":
		return none
	var ds = ""
	for i in 1..n:
		if not is_digit(cs[i]):
			return none
		ds += cs[i]
	row := ds.parse_int().get(0)
	if row < 1 or row > 999:
		return none
	return (row - 1) * 26 + col

fn parse_range_arg(t: String) Rect?:
	parts := t.split(":")
	if parts.length() == 1:
		if a := parse_cell_arg(parts[0]):
			return Rect(a % 26, a % 26, a / 26 + 1, a / 26 + 1)
		return none
	if parts.length() == 2:
		a := parse_cell_arg(parts[0])
		b := parse_cell_arg(parts[1])
		if a.is_some() and b.is_some():
			x := a.get(0)
			y := b.get(0)
			return Rect(min(x % 26, y % 26), max(x % 26, y % 26), min(x / 26, y / 26) + 1, max(x / 26, y / 26) + 1)
	return none

fn words(line: String) List[String]:
	var out = List[String]()
	var cur = ""
	for ch in line.chars():
		if is_ws(ch):
			if cur != "":
				out.append(cur.clone())
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur.clone())
	return out

fn rest_after(line: String, k: Int) String:
	cs := line.chars()
	n := cs.length()
	var i = 0
	for _t in 0..k:
		while i < n and is_ws(cs[i]):
			i += 1
		while i < n and not is_ws(cs[i]):
			i += 1
	return take(cs, i, n).trim()

fn parse_csv(text: String) List[List[String]]:
	var recs = List[List[String]]()
	var rec = List[String]()
	var field = ""
	var inq = false
	var any = false
	cs := text.chars()
	n := cs.length()
	var i = 0
	while i < n:
		ch := cs[i].clone()
		if inq:
			if ch == "\"":
				if i + 1 < n and cs[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				inq = false
			else:
				field += ch
			i += 1
			continue
		if ch == "\"":
			inq = true
			any = true
		else if ch == ",":
			rec.append(field.clone())
			field = ""
			any = true
		else if ch == "\r":
			i += 1
			continue
		else if ch == "\n":
			if any:
				rec.append(field.clone())
				recs.append(rec.clone())
			rec = List[String]()
			field = ""
			any = false
		else:
			field += ch
			any = true
		i += 1
	if any:
		rec.append(field.clone())
		recs.append(rec.clone())
	return recs

fn csv_field(f: String) String:
	var need = f.starts_with(" ") or f.ends_with(" ")
	for ch in f.chars():
		if ch == "," or ch == "\"" or ch == "\n" or ch == "\r":
			need = true
	if not need:
		return f.clone()
	return "\"{f.replace("\"", "\"\"")}\""

fn Sheet.display(i: Int) String:
	c := self.cells[i]
	if c.kind == 0:
		return ""
	return to_str(c.v)

// ---------- commands ----------

fn var Sheet.emit(line: String) Unit:
	self.out.append(line.clone())

fn var Sheet.show_range(args: List[String], csv: Bool, usage: String) Unit:
	var mode = ""
	var rangearg = ""
	var nr = 0
	var nm = 0
	for a in args:
		if a == "formulas" or a == "values":
			mode = a.clone()
			nm += 1
		else:
			rangearg = a.clone()
			nr += 1
	if nr > 1 or nm > 1 or (mode == "formulas" and not csv):
		self.emit(usage)
		return
	var rect = Rect(0, 0, 1, 1)
	if nr == 1:
		if r := parse_range_arg(rangearg):
			rect = r
		else:
			self.emit("error: bad range '{rangearg}'")
			return
	else:
		var maxc = -1
		var maxr = 0
		for i in 0..25974:
			if self.cells[i].kind != 0:
				if i % 26 > maxc:
					maxc = i % 26
				if i / 26 + 1 > maxr:
					maxr = i / 26 + 1
		if maxc < 0:
			self.emit("(empty sheet)")
			return
		rect = Rect(0, maxc, 1, maxr)
	for r in rect.lr..rect.hr + 1:
		var fields = List[String]()
		for col in rect.lc..rect.hc + 1:
			i := (r - 1) * 26 + col
			if mode == "formulas":
				fields.append(self.cells[i].raw.clone())
			else:
				fields.append(self.display(i))
		if csv:
			var parts = List[String]()
			for f in fields:
				parts.append(csv_field(f))
			self.emit(parts.join(","))
		else:
			self.emit(fields.join(" | "))

fn var Sheet.do_import(ws: List[String], block: List[String]) Unit:
	if ws.length() != 2:
		self.emit("error: usage: import CELL")
		return
	start := parse_cell_arg(ws[1])
	if start.is_none():
		self.emit("error: bad cell reference '{ws[1]}'")
		return
	si := start.get(0)
	recs := parse_csv(block.join("\n"))
	var maxc = 0
	for r in recs:
		if r.length() > maxc:
			maxc = r.length()
	if si % 26 + maxc > 26 or si / 26 + recs.length() > 999:
		self.emit("error: import out of range")
		return
	var changed = List[Int]()
	for ri in 0..recs.length():
		rec := recs[ri]
		for fi in 0..rec.length():
			i := si + ri * 26 + fi
			self.assign(i, rec[fi].trim())
			changed.append(i)
	n := self.recalc(changed)
	self.emit("imported {recs.length()} rows, {maxc} columns; recalc {n}")

fn var Sheet.exec(line: String, ws: List[String]) Unit:
	cmd := ws[0].clone()
	na := ws.length() - 1
	if cmd == "set":
		if na < 1:
			self.emit("error: usage: set CELL VALUE")
			return
		ci := parse_cell_arg(ws[1])
		if ci.is_none():
			self.emit("error: bad cell reference '{ws[1]}'")
			return
		i := ci.get(0)
		self.assign(i, rest_after(line, 2))
		n := self.recalc([i])
		self.emit("recalc {n}")
		return
	if cmd == "clear" or cmd == "get" or cmd == "show" or cmd == "precedents" or cmd == "dependents":
		if na != 1:
			self.emit("error: usage: {cmd} CELL")
			return
		ci := parse_cell_arg(ws[1])
		if ci.is_none():
			self.emit("error: bad cell reference '{ws[1]}'")
			return
		i := ci.get(0)
		if cmd == "clear":
			self.assign(i, "")
			n := self.recalc([i])
			self.emit("recalc {n}")
			return
		c := self.cells[i].clone()
		if cmd == "get":
			if c.kind == 0:
				self.emit("(empty)")
			else:
				self.emit(to_str(c.v))
			return
		if cmd == "show":
			name := cell_name(i)
			if c.kind == 0:
				self.emit("{name}: (empty)")
			else if c.kind == 1:
				self.emit("{name}: {c.raw}")
			else:
				self.emit("{name}: {c.raw} => {to_str(c.v)}")
			return
		if cmd == "precedents":
			var names = List[String]()
			if c.kind == 2:
				for p in c.precs:
					names.append(cell_name(p))
			self.emit(if names.length() == 0: "(none)" else: names.join(" "))
			return
		var seen = Set[Int]()
		var queue = List[Int]()
		queue.append(i)
		var qi = 0
		while qi < queue.length():
			u := queue[qi]
			qi += 1
			for d in self.deps[u]:
				if not seen.contains(d):
					seen.add(d)
					queue.append(d)
		var all = List[Int]()
		for x in seen:
			all.append(x)
		all.sort()
		var names = List[String]()
		for x in all:
			names.append(cell_name(x))
		self.emit(if names.length() == 0: "(none)" else: names.join(" "))
		return
	if cmd == "copy":
		if na != 2:
			self.emit("error: usage: copy SRC DST")
			return
		sc := parse_cell_arg(ws[1])
		if sc.is_none():
			self.emit("error: bad cell reference '{ws[1]}'")
			return
		rect := parse_range_arg(ws[2])
		if rect.is_none():
			self.emit("error: bad range '{ws[2]}'")
			return
		rc := rect.get(Rect(0, 0, 1, 1))
		si := sc.get(0)
		src := self.cells[si].clone()
		var changed = List[Int]()
		for r in rc.lr..rc.hr + 1:
			for col in rc.lc..rc.hc + 1:
				i := (r - 1) * 26 + col
				if src.kind == 0:
					self.assign(i, "")
				else if src.kind == 1:
					self.assign(i, src.raw)
				else:
					self.assign(i, "={shift_formula(tail1(src.raw), col - si % 26, r - 1 - si / 26)}")
				changed.append(i)
		n := self.recalc(changed)
		self.emit("recalc {n}")
		return
	if cmd == "print":
		self.show_range(ws.slice(1, ws.length()).get([]), false, "error: usage: print [RANGE]")
		return
	if cmd == "export":
		self.show_range(ws.slice(1, ws.length()).get([]), true, "error: usage: export [formulas] [RANGE]")
		return
	if cmd == "stats":
		var cells = 0
		var forms = 0
		for i in 0..25974:
			k := self.cells[i].kind
			if k != 0:
				cells += 1
			if k == 2:
				forms += 1
		self.emit("cells {cells} formulas {forms} evals {self.evals}")
		return
	self.emit("error: unknown command '{cmd}'")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	lines0 := text.split("\n")
	var lines = lines0.clone()
	if lines.length() > 0 and lines.get(lines.length() - 1, "") == "":
		lines.pop()
	var s = new_sheet()
	var i = 0
	while i < lines.length():
		line := lines[i].clone()
		i += 1
		t := line.trim()
		if t == "" or t.starts_with("#"):
			continue
		s.emit("> {line.trim_end()}")
		ws := words(line)
		if ws[0] == "import":
			var block = List[String]()
			while i < lines.length() and lines[i] != ".":
				block.append(lines[i].clone())
				i += 1
			i += 1
			s.do_import(ws, block)
		else:
			s.exec(line, ws)
	if s.out.length() > 0:
		print(s.out.join("\n"))
	return ok(unit)
