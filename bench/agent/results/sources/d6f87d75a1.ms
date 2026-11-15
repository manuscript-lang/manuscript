import floor, pow, sqrt from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

enum Value:
	Empty
	Num(n: Float)
	Text(s: String)
	Bool(b: Bool)
	Err(e: String)

fn cv(v: Value) Value:
	match v:
		Empty: return Value.Empty
		Num(n): return Value.Num(n)
		Text(s): return Value.Text(s.clone())
		Bool(b): return Value.Bool(b)
		Err(e): return Value.Err(e.clone())

fn err(e: String) Value: Value.Err(e)

fn tag(v: Value) Int:
	match v:
		Empty: return 0
		Num(_n): return 1
		Text(_s): return 2
		Bool(_b): return 3
		Err(_e): return 4

fn is_err(v: Value) Bool: tag(v) == 4

fn numf(v: Value) Float:
	match v:
		Num(n): return n
		_: return 0.0

fn strf(v: Value) String:
	match v:
		Text(s): return s.clone()
		Err(e): return e.clone()
		_: return ""

fn boolf(v: Value) Bool:
	match v:
		Bool(b): return b
		_: return false

fn mknum(f: Float) Value:
	if not f.is_finite(): return Value.Err("#NUM!")
	return Value.Num(f)

fn sub(s: String, a: Int, b: Int) String:
	if a >= b: return ""
	if r := s.slice(a, b):
		return r
	return ""

fn f2i(f: Float) Int:
	if f > 1000000000000.0: return 1000000000000
	if f < -1000000000000.0: return -1000000000000
	return f.truncate_to_int().get(0)

fn strip_zeros(s: String) String:
	if not s.contains("."): return s.clone()
	return s.trim_end_chars("0").trim_end_chars(".").clone()

fn fmt_num(x: Float) String:
	if x == 0.0: return "0"
	var s = ""
	if x >= 1e21 or x <= -1e21:
		e := x.to_exponential(100)
		neg := e.starts_with("-")
		body := if neg: sub(e, 1, e.length()) else: e
		parts := body.split("e")
		mant := parts.get(0, "").replace(".", "")
		ex := parts.get(1, "0").replace("+", "").parse_int().get(0)
		var digits = mant.clone()
		for _i in 0..(ex + 1 - digits.length()):
			digits = digits + "0"
		s = if neg: "-" + sub(digits, 0, ex + 1) else: sub(digits, 0, ex + 1)
		return s
	s = strip_zeros(x.to_fixed(10))
	if s == "-0": return "0"
	return s

fn sform(v: Value) String:
	match v:
		Empty: return ""
		Num(n): return fmt_num(n)
		Text(s): return s.clone()
		Bool(b): return if b: "TRUE" else: "FALSE"
		Err(e): return e.clone()

// ---------- character helpers ----------
fn is_digit(c: String) Bool: c >= "0" and c <= "9" and c.length() == 1
fn is_letter(c: String) Bool: c.length() == 1 and ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z"))
fn is_idc(c: String) Bool: is_letter(c) or is_digit(c) or c == "_" or c == "."

type NumScan:
	end: Int = -1
	value: Float = 0.0

fn scan_number(cs: List[String], i: Int) NumScan:
	n := cs.length()
	var p = i
	var ip = ""
	while p < n and is_digit(cs[p]):
		ip = ip + cs[p]
		p += 1
	var fp = ""
	if ip.length() > 0:
		if p < n and cs[p] == ".":
			p += 1
			while p < n and is_digit(cs[p]):
				fp = fp + cs[p]
				p += 1
	else:
		if p < n and cs[p] == "." and p + 1 < n and is_digit(cs[p + 1]):
			p += 1
			while p < n and is_digit(cs[p]):
				fp = fp + cs[p]
				p += 1
		else:
			return NumScan()
	var ep = ""
	if p < n and (cs[p] == "e" or cs[p] == "E"):
		var q = p + 1
		var sg = ""
		if q < n and (cs[q] == "+" or cs[q] == "-"):
			sg = cs[q].clone()
			q += 1
		if q < n and is_digit(cs[q]):
			var ds = ""
			while q < n and is_digit(cs[q]):
				ds = ds + cs[q]
				q += 1
			ep = "e" + sg + ds
			p = q
	txt := (if ip == "": "0" else: ip) + "." + (if fp == "": "0" else: fp) + ep
	v := txt.parse_float().get(big_inf())
	return NumScan(end: p, value: v)

// parse full text (already trimmed) as number grammar; finite only
fn parse_num_text(s: String) Float?:
	if s == "": return none
	cs := s.chars()
	var i = 0
	var neg = false
	if cs[0] == "+" or cs[0] == "-":
		neg = cs[0] == "-"
		i = 1
	r := scan_number(cs, i)
	if r.end != cs.length(): return none
	if not r.value.is_finite(): return none
	return if neg: -r.value else: r.value

// ---------- references ----------
type RefScan:
	ok: Bool = false
	end: Int = 0
	col: Int = 0
	row: Int = 0
	valid: Bool = false
	ac: Bool = false
	ar: Bool = false
	letters: String = ""
	digits: String = ""

fn scan_ref(cs: List[String], i: Int) RefScan:
	n := cs.length()
	var p = i
	var ac = false
	if cs[p] == "$":
		ac = true
		p += 1
	var letters = ""
	while p < n and is_letter(cs[p]):
		letters = letters + cs[p]
		p += 1
	if letters == "": return RefScan()
	var ar = false
	if p < n and cs[p] == "$":
		ar = true
		p += 1
	var digits = ""
	while p < n and is_digit(cs[p]):
		digits = digits + cs[p]
		p += 1
	if digits == "": return RefScan()
	if p < n:
		nx := cs[p]
		if is_idc(nx) or nx == "(" or nx == "$": return RefScan()
	var valid = letters.length() == 1 and digits.length() <= 3 and not digits.starts_with("0")
	var col = 0
	var row = 0
	if valid:
		col = letters.upper().scalar_at(0) - 65
		row = digits.parse_int().get(0)
		if row < 1 or row > 999: valid = false
	return RefScan(ok: true, end: p, col: col, row: row, valid: valid, ac: ac, ar: ar, letters: letters, digits: digits)

fn ref_text(r: RefScan, col: Int, row: Int) String:
	letter := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".slice(col, col + 1).get("A")
	return (if r.ac: "$" else: "") + letter + (if r.ar: "$" else: "") + "{row}"

// ---------- lexer ----------
type Tok:
	kind: Int = 0 // 0 num 1 str 2 ref 3 range 4 errlit 5 id 6 op
	text: String = ""
	num: Float = 0.0
	valid: Bool = true
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0
	start: Int = 0
	end: Int = 0
	a: RefScan = RefScan()
	b: RefScan = RefScan()

type LexResult:
	ok: Bool = true
	toks: List[Tok] = []

fn lex(cs: List[String]) LexResult:
	n := cs.length()
	var res = LexResult()
	var i = 0
	while i < n:
		c := cs[i]
		if c == " " or c == "\t":
			i += 1
			continue
		start := i
		if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
			r := scan_number(cs, i)
			res.toks.append(Tok(kind: 0, num: r.value, start: start, end: r.end))
			i = r.end
		else if c == "\"":
			var p = i + 1
			var s = ""
			var closed = false
			while p < n:
				if cs[p] == "\"":
					if p + 1 < n and cs[p + 1] == "\"":
						s = s + "\""
						p += 2
					else:
						closed = true
						p += 1
						break
				else:
					s = s + cs[p]
					p += 1
			if not closed:
				res.ok = false
				return res
			res.toks.append(Tok(kind: 1, text: s, start: start, end: p))
			i = p
		else if c == "$" or is_letter(c) or c == "_":
			var done = false
			if c == "$" or is_letter(c):
				r := scan_ref(cs, i)
				if r.ok:
					done = true
					if r.end < n and cs[r.end] == ":":
						if r.end + 1 < n:
							r2 := scan_ref(cs, r.end + 1)
							if r2.ok:
								res.toks.append(Tok(kind: 3, valid: r.valid and r2.valid, c1: r.col, r1: r.row, c2: r2.col, r2: r2.row, start: start, end: r2.end, a: r.clone(), b: r2.clone()))
								i = r2.end
							else:
								res.ok = false
								return res
						else:
							res.ok = false
							return res
					else:
						res.toks.append(Tok(kind: 2, valid: r.valid, c1: r.col, r1: r.row, start: start, end: r.end, a: r.clone()))
						i = r.end
			if not done:
				if c == "$":
					res.ok = false
					return res
				var p = i
				var s = ""
				while p < n and is_idc(cs[p]):
					s = s + cs[p]
					p += 1
				res.toks.append(Tok(kind: 5, text: s.upper(), start: start, end: p))
				i = p
		else if c == "#":
			if i + 4 < n and cs[i + 1] == "R" and cs[i + 2] == "E" and cs[i + 3] == "F" and cs[i + 4] == "!":
				res.toks.append(Tok(kind: 4, start: start, end: i + 5))
				i += 5
			else:
				res.ok = false
				return res
		else:
			var op = ""
			if c == "<" or c == ">":
				if i + 1 < n and (cs[i + 1] == "=" or (c == "<" and cs[i + 1] == ">")):
					op = c + cs[i + 1]
				else:
					op = c.clone()
			else if c == "+" or c == "-" or c == "*" or c == "/" or c == "^" or c == "&" or c == "(" or c == ")" or c == "," or c == "=":
				op = c.clone()
			else:
				res.ok = false
				return res
			res.toks.append(Tok(kind: 6, text: op.clone(), start: start, end: start + op.length()))
			i += op.length()
	return res

// ---------- AST ----------
// kinds: 0 NUM 1 STR 2 BOOL 3 REF 4 RANGE 5 ERRLIT 6 NAME 7 CALL 8 BIN 9 UN
type Node:
	kind: Int = 0
	num: Float = 0.0
	s: String = ""
	a: Int = 0
	b: Int = 0
	args: List[Int] = []
	valid: Bool = true
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = []
	fail: Bool = false

fn Parser.kind() Int:
	if self.pos >= self.toks.length(): return 99
	return self.toks[self.pos].kind

fn Parser.is_op(op: String) Bool:
	if self.pos >= self.toks.length(): return false
	t := self.toks[self.pos]
	return t.kind == 6 and t.text == op

fn var Parser.add(nd: Node) Int:
	self.nodes.append(nd)
	return self.nodes.length() - 1

fn var Parser.parse_cmp() Int:
	var l = self.parse_cat()
	while not self.fail:
		var op = ""
		for o in ["=", "<>", "<=", ">=", "<", ">"]:
			if self.is_op(o): op = o
		if op == "": break
		self.pos += 1
		r := self.parse_cat()
		l = self.add(Node(kind: 8, s: op, a: l, b: r))
	return l

fn var Parser.parse_cat() Int:
	var l = self.parse_add()
	while not self.fail and self.is_op("&"):
		self.pos += 1
		r := self.parse_add()
		l = self.add(Node(kind: 8, s: "&", a: l, b: r))
	return l

fn var Parser.parse_add() Int:
	var l = self.parse_mul()
	while not self.fail and (self.is_op("+") or self.is_op("-")):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		r := self.parse_mul()
		l = self.add(Node(kind: 8, s: op, a: l, b: r))
	return l

fn var Parser.parse_mul() Int:
	var l = self.parse_unary()
	while not self.fail and (self.is_op("*") or self.is_op("/")):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		r := self.parse_unary()
		l = self.add(Node(kind: 8, s: op, a: l, b: r))
	return l

fn var Parser.parse_unary() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		e := self.parse_unary()
		return self.add(Node(kind: 9, s: op, a: e))
	return self.parse_pow()

fn var Parser.parse_pow() Int:
	b := self.parse_primary()
	if not self.fail and self.is_op("^"):
		self.pos += 1
		e := self.parse_powexp()
		return self.add(Node(kind: 8, s: "^", a: b, b: e))
	return b

fn var Parser.parse_powexp() Int:
	if self.is_op("+") or self.is_op("-"):
		op := self.toks[self.pos].text.clone()
		self.pos += 1
		e := self.parse_powexp()
		return self.add(Node(kind: 9, s: op, a: e))
	return self.parse_pow()

fn var Parser.parse_primary() Int:
	if self.pos >= self.toks.length():
		self.fail = true
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
		return self.add(Node(kind: 3, valid: t.valid, c1: t.c1, r1: t.r1))
	if k == 3:
		self.pos += 1
		return self.add(Node(kind: 4, valid: t.valid, c1: t.c1, r1: t.r1, c2: t.c2, r2: t.r2))
	if k == 4:
		self.pos += 1
		return self.add(Node(kind: 5))
	if k == 5:
		name := t.text.clone()
		self.pos += 1
		if self.is_op("("):
			self.pos += 1
			var args = List[Int]()
			if self.is_op(")"):
				self.pos += 1
			else:
				while true:
					a := self.parse_cmp()
					if self.fail: return 0
					args.append(a)
					if self.is_op(","):
						self.pos += 1
					else if self.is_op(")"):
						self.pos += 1
						break
					else:
						self.fail = true
						return 0
			return self.add(Node(kind: 7, s: name, args: args))
		if name == "TRUE": return self.add(Node(kind: 2, num: 1.0))
		if name == "FALSE": return self.add(Node(kind: 2, num: 0.0))
		return self.add(Node(kind: 6, s: name))
	if k == 6 and t.text == "(":
		self.pos += 1
		e := self.parse_cmp()
		if self.fail: return 0
		if self.is_op(")"):
			self.pos += 1
			return e
		self.fail = true
		return 0
	self.fail = true
	return 0

type Formula:
	nodes: List[Node] = []
	root: Int = 0
	ok: Bool = false
	prec: List[Int] = []

fn parse_formula(src: String) Formula:
	lr := lex(src.chars())
	if not lr.ok: return Formula()
	if lr.toks.length() == 0: return Formula()
	var p = Parser(toks: lr.toks)
	root := p.parse_cmp()
	if p.fail or p.pos != p.toks.length(): return Formula()
	return Formula(nodes: p.nodes, root: root, ok: true)

fn collect_prec(nodes: List[Node], ni: Int, var out: Set[Int]) Unit:
	nd := nodes[ni]
	if nd.kind == 3:
		if nd.valid: out.add(nd.r1 * 26 + nd.c1)
	else if nd.kind == 4:
		if nd.valid:
			for r in min_i(nd.r1, nd.r2)..max_i(nd.r1, nd.r2) + 1:
				for c in min_i(nd.c1, nd.c2)..max_i(nd.c1, nd.c2) + 1:
					out.add(r * 26 + c)
	else if nd.kind == 7:
		if nd.s == "ROW" or nd.s == "COLUMN": return
		for a in nd.args:
			collect_prec(nodes, a, var out)
	else if nd.kind == 8:
		collect_prec(nodes, nd.a, var out)
		collect_prec(nodes, nd.b, var out)
	else if nd.kind == 9:
		collect_prec(nodes, nd.a, var out)

fn min_i(a: Int, b: Int) Int: if a < b: a else: b
fn max_i(a: Int, b: Int) Int: if a > b: a else: b

// ---------- sheet ----------
type Sheet:
	raws: List[String]
	kinds: List[Int]
	vals: List[Value]
	formulas: Map[Int, Formula] = Map[Int, Formula]()
	deps: Map[Int, List[Int]] = Map[Int, List[Int]]()
	evals: Int = 0

fn new_sheet() Sheet:
	var raws = List[String](reserve: 26 * 1000)
	var kinds = List[Int](reserve: 26 * 1000)
	var vals = List[Value](reserve: 26 * 1000)
	for _i in 0..26 * 1000:
		raws.append("")
		kinds.append(0)
		vals.append(Value.Empty)
	return Sheet(raws: raws, kinds: kinds, vals: vals)

fn idx_name(i: Int) String:
	col := i % 26
	row := i / 26
	letter := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".slice(col, col + 1).get("A")
	return "{letter}{row}"

fn var Sheet.assign(idx: Int, text: String) Unit:
	if self.kinds[idx] == 2:
		if old := self.formulas.get(idx):
			for p in old.prec:
				if lst := self.deps.get(p):
					var nl = List[Int]()
					for d in lst:
						if d != idx: nl.append(d)
					self.deps[p] = nl
		self.formulas.remove(idx)
	self.raws[idx] = text.clone()
	if text == "":
		self.kinds[idx] = 0
		self.vals[idx] = Value.Empty
		return
	if text.starts_with("="):
		self.kinds[idx] = 2
		var f = parse_formula(sub(text, 1, text.length()))
		if f.ok:
			var ps = Set[Int]()
			collect_prec(f.nodes, f.root, var ps)
			var pl = ps.values()
			pl.sort()
			for p in pl:
				var cur = self.deps.get(p).get([])
				cur.append(idx)
				self.deps[p] = cur
			f.prec = pl
		self.formulas[idx] = f
		self.vals[idx] = Value.Err("#PARSE!")
		return
	self.kinds[idx] = 1
	if text.starts_with("'"):
		self.vals[idx] = Value.Text(sub(text, 1, text.length()))
		return
	if n := parse_num_text(text):
		self.vals[idx] = Value.Num(n)
		return
	u := text.upper()
	if u == "TRUE":
		self.vals[idx] = Value.Bool(true)
		return
	if u == "FALSE":
		self.vals[idx] = Value.Bool(false)
		return
	self.vals[idx] = Value.Text(text.clone())

fn var Sheet.recalc(changed: List[Int]) Int:
	var aff = Set[Int]()
	var order = List[Int]()
	var stack = List[Int]()
	for c in changed:
		if self.kinds[c] == 2 and not aff.contains(c):
			aff.add(c)
			order.append(c)
		stack.append(c)
	var seen = Set[Int]()
	while stack.length() > 0:
		x := stack.pop().get(0)
		if seen.contains(x): continue
		seen.add(x)
		if lst := self.deps.get(x):
			for d in lst:
				if not aff.contains(d):
					aff.add(d)
					order.append(d)
				if not seen.contains(d):
					stack.append(d)
	// tarjan over precedent edges
	var index = Map[Int, Int]()
	var low = Map[Int, Int]()
	var onst = Set[Int]()
	var stk = List[Int]()
	var counter = 0
	var sccs = List[List[Int]]()
	for root in order:
		if index.contains(root): continue
		var call = [root]
		var eidx = [0]
		index[root] = counter
		low[root] = counter
		counter += 1
		stk.append(root)
		onst.add(root)
		while call.length() > 0:
			top := call.length() - 1
			v := call[top]
			ei := eidx[top]
			prec := self.formulas.get(v).get(Formula()).prec
			if ei < prec.length():
				eidx[top] = ei + 1
				w := prec[ei]
				if not aff.contains(w): continue
				if not index.contains(w):
					index[w] = counter
					low[w] = counter
					counter += 1
					stk.append(w)
					onst.add(w)
					call.append(w)
					eidx.append(0)
				else if onst.contains(w):
					low[v] = min_i(low[v], index[w])
			else:
				if low[v] == index[v]:
					var comp = List[Int]()
					while true:
						w := stk.pop().get(0)
						onst.remove(w)
						comp.append(w)
						if w == v: break
					sccs.append(comp)
				call.pop()
				eidx.pop()
				if call.length() > 0:
					u := call[call.length() - 1]
					low[u] = min_i(low[u], low[v])
	for comp in sccs:
		var cyc = comp.length() > 1
		if not cyc:
			v := comp[0]
			for p in self.formulas.get(v).get(Formula()).prec:
				if p == v: cyc = true
		if cyc:
			for v in comp:
				self.vals[v] = Value.Err("#CYCLE!")
		else:
			v := comp[0]
			self.vals[v] = self.eval_cell(v)
	self.evals += order.length()
	return order.length()

fn Sheet.eval_cell(idx: Int) Value:
	if f := self.formulas.get(idx):
		if not f.ok: return Value.Err("#PARSE!")
		r := ev(self, f.nodes, f.root)
		if tag(r) == 0: return Value.Num(0.0)
		return r
	return Value.Err("#PARSE!")

// ---------- evaluation ----------
fn coerce_num(v: Value) Value:
	match v:
		Empty: return Value.Num(0.0)
		Num(n): return Value.Num(n)
		Bool(b): return Value.Num(if b: 1.0 else: 0.0)
		Text(s):
			if n := parse_num_text(s.trim()): return Value.Num(n)
			return Value.Err("#VALUE!")
		Err(e): return Value.Err(e.clone())

fn coerce_bool(v: Value) Value:
	match v:
		Empty: return Value.Bool(false)
		Num(n): return Value.Bool(n != 0.0)
		Bool(b): return Value.Bool(b)
		Text(s):
			u := s.upper()
			if u == "TRUE": return Value.Bool(true)
			if u == "FALSE": return Value.Bool(false)
			return Value.Err("#VALUE!")
		Err(e): return Value.Err(e.clone())

fn zero_of(v: Value) Value:
	match v:
		Num(_n): return Value.Num(0.0)
		Text(_s): return Value.Text("")
		Bool(_b): return Value.Bool(false)
		_: return Value.Empty

// returns -1,0,1 for non-error values
fn cmp_vals(l0: Value, r0: Value) Int:
	var l = cv(l0)
	var r = cv(r0)
	if tag(l) == 0 and tag(r) == 0: return 0
	if tag(l) == 0: l = zero_of(r)
	if tag(r) == 0: r = zero_of(l)
	tl := tag(l)
	tr := tag(r)
	if tl != tr: return if tl < tr: -1 else: 1
	if tl == 1:
		a := numf(l)
		b := numf(r)
		return if a < b: -1 else if a > b: 1 else: 0
	if tl == 2:
		a := strf(l)
		b := strf(r)
		return if a < b: -1 else if a > b: 1 else: 0
	a := boolf(l)
	b := boolf(r)
	if a == b: return 0
	return if b: -1 else: 1

fn cell_val(sh: Sheet, c: Int, r: Int) Value:
	return cv(sh.vals[r * 26 + c])

type Item:
	v: Value
	direct: Bool

fn node_items(sh: Sheet, nodes: List[Node], args: List[Int]) List[Item]:
	var items = List[Item]()
	for a in args:
		nd := nodes[a]
		if nd.kind == 4:
			if not nd.valid:
				items.append(Item(v: Value.Err("#REF!"), direct: false))
			else:
				for r in min_i(nd.r1, nd.r2)..max_i(nd.r1, nd.r2) + 1:
					for c in min_i(nd.c1, nd.c2)..max_i(nd.c1, nd.c2) + 1:
						items.append(Item(v: cell_val(sh, c, r), direct: false))
		else:
			items.append(Item(v: ev(sh, nodes, a), direct: true))
	return items

fn round_away(y: Float) Float:
	a := if y < 0.0: -y else: y
	t := floor(a)
	r := if a - t >= 0.5: t + 1.0 else: t
	return if y < 0.0: -r else: r

fn ev(sh: Sheet, nodes: List[Node], ni: Int) Value:
	nd := nodes[ni]
	if nd.kind == 0: return mknum(nd.num)
	if nd.kind == 1: return Value.Text(nd.s.clone())
	if nd.kind == 2: return Value.Bool(nd.num != 0.0)
	if nd.kind == 3:
		if not nd.valid: return Value.Err("#REF!")
		return cell_val(sh, nd.c1, nd.r1)
	if nd.kind == 4:
		if not nd.valid: return Value.Err("#REF!")
		return Value.Err("#VALUE!")
	if nd.kind == 5: return Value.Err("#REF!")
	if nd.kind == 6: return Value.Err("#NAME?")
	if nd.kind == 9:
		x := coerce_num(ev(sh, nodes, nd.a))
		if is_err(x): return x
		if nd.s == "-": return mknum(-numf(x))
		return cv(x)
	if nd.kind == 8: return ev_bin(sh, nodes, nd)
	return ev_call(sh, nodes, nd)

fn ev_bin(sh: Sheet, nodes: List[Node], nd: Node) Value:
	l := ev(sh, nodes, nd.a)
	r := ev(sh, nodes, nd.b)
	op := nd.s
	if op == "&":
		if is_err(l): return l
		if is_err(r): return r
		return Value.Text(sform(l) + sform(r))
	if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
		if is_err(l): return l
		if is_err(r): return r
		c := cmp_vals(l, r)
		var res = false
		if op == "=": res = c == 0
		else if op == "<>": res = c != 0
		else if op == "<": res = c < 0
		else if op == "<=": res = c <= 0
		else if op == ">": res = c > 0
		else: res = c >= 0
		return Value.Bool(res)
	a := coerce_num(l)
	if is_err(a): return a
	b := coerce_num(r)
	if is_err(b): return b
	x := numf(a)
	y := numf(b)
	if op == "+": return mknum(x + y)
	if op == "-": return mknum(x - y)
	if op == "*": return mknum(x * y)
	if op == "/":
		if y == 0.0: return Value.Err("#DIV/0!")
		return mknum(x / y)
	return mknum(pow(x, y))

fn scalar_num(sh: Sheet, nodes: List[Node], ni: Int) Value:
	return coerce_num(ev(sh, nodes, ni))

fn scalar_str(sh: Sheet, nodes: List[Node], ni: Int) Value:
	v := ev(sh, nodes, ni)
	if is_err(v): return v
	return Value.Text(sform(v))

fn chars_slice(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a
	while i < b and i < cs.length():
		out = out + cs[i]
		i += 1
	return out

fn ev_call(sh: Sheet, nodes: List[Node], nd: Node) Value:
	name := nd.s
	args := nd.args
	n := args.length()
	bad := Value.Err("#VALUE!")
	if name == "SUM" or name == "AVERAGE" or name == "MIN" or name == "MAX" or name == "PRODUCT" or name == "MEDIAN":
		if n < 1: return bad
		items := node_items(sh, nodes, args)
		var nums = List[Float]()
		for it in items:
			if is_err(it.v): return cv(it.v)
			if it.direct:
				x := coerce_num(it.v)
				if is_err(x): return x
				nums.append(numf(x))
			else:
				if tag(it.v) == 1: nums.append(numf(it.v))
		if name == "SUM":
			var s = 0.0
			for x in nums: s += x
			return mknum(s)
		if name == "PRODUCT":
			if nums.length() == 0: return Value.Num(0.0)
			var s = 1.0
			for x in nums: s *= x
			return mknum(s)
		if name == "AVERAGE":
			if nums.length() == 0: return Value.Err("#DIV/0!")
			var s = 0.0
			for x in nums: s += x
			return mknum(s / nums.length().to_float())
		if name == "MIN" or name == "MAX":
			if nums.length() == 0: return Value.Num(0.0)
			var m = nums[0]
			for x in nums:
				if name == "MIN":
					if x < m: m = x
				else:
					if x > m: m = x
			return Value.Num(m)
		if nums.length() == 0: return Value.Err("#NUM!")
		sorted := nums.sorted()
		k := sorted.length()
		if k % 2 == 1: return Value.Num(sorted[k / 2])
		return mknum((sorted[k / 2 - 1] + sorted[k / 2]) / 2.0)
	if name == "COUNT" or name == "COUNTA":
		if n < 1: return bad
		items := node_items(sh, nodes, args)
		var cnt = 0
		for it in items:
			t := tag(it.v)
			if name == "COUNT":
				if t == 1: cnt += 1
			else:
				if t != 0: cnt += 1
		return Value.Num(cnt.to_float())
	if name == "IF":
		if n != 2 and n != 3: return bad
		c := coerce_bool(ev(sh, nodes, args[0]))
		if is_err(c): return c
		if boolf(c): return ev(sh, nodes, args[1])
		if n == 3: return ev(sh, nodes, args[2])
		return Value.Bool(false)
	if name == "IFERROR":
		if n != 2: return bad
		a := ev(sh, nodes, args[0])
		if is_err(a): return ev(sh, nodes, args[1])
		return a
	if name == "CHOOSE":
		if n < 2: return bad
		i := scalar_num(sh, nodes, args[0])
		if is_err(i): return i
		k := floor(numf(i))
		if k < 1.0 or k > (n - 1).to_float(): return bad
		return ev(sh, nodes, args[f2i(k)])
	if name == "AND" or name == "OR":
		if n < 1: return bad
		items := node_items(sh, nodes, args)
		var took = false
		var acc = name == "AND"
		for it in items:
			if is_err(it.v): return cv(it.v)
			if not it.direct:
				t := tag(it.v)
				if t == 2 or t == 0: continue
			b := coerce_bool(it.v)
			if is_err(b): return b
			took = true
			if name == "AND": acc = acc and boolf(b)
			else: acc = acc or boolf(b)
		if not took: return bad
		return Value.Bool(acc)
	if name == "NOT":
		if n != 1: return bad
		b := coerce_bool(ev(sh, nodes, args[0]))
		if is_err(b): return b
		return Value.Bool(not boolf(b))
	if name == "ABS" or name == "INT" or name == "SQRT":
		if n != 1: return bad
		x := scalar_num(sh, nodes, args[0])
		if is_err(x): return x
		f := numf(x)
		if name == "ABS": return Value.Num(if f < 0.0: -f else: f)
		if name == "INT": return mknum(floor(f))
		if f < 0.0: return Value.Err("#NUM!")
		return mknum(sqrt(f))
	if name == "POW" or name == "MOD":
		if n != 2: return bad
		a := scalar_num(sh, nodes, args[0])
		b := scalar_num(sh, nodes, args[1])
		if is_err(a): return a
		if is_err(b): return b
		x := numf(a)
		y := numf(b)
		if name == "POW": return mknum(pow(x, y))
		if y == 0.0: return Value.Err("#DIV/0!")
		return mknum(x - y * floor(x / y))
	if name == "ROUND":
		if n != 1 and n != 2: return bad
		a := scalar_num(sh, nodes, args[0])
		if is_err(a): return a
		var d = 0.0
		if n == 2:
			b := scalar_num(sh, nodes, args[1])
			if is_err(b): return b
			d = numf(b)
			d = if d < 0.0: -floor(-d) else: floor(d)
		if d > 15.0 or d < -15.0: return Value.Err("#NUM!")
		p := pow(10.0, d)
		return mknum(round_away(numf(a) * p) / p)
	if name == "LEN" or name == "UPPER" or name == "LOWER" or name == "TRIM":
		if n != 1: return bad
		v := scalar_str(sh, nodes, args[0])
		if is_err(v): return v
		s := strf(v)
		if name == "LEN": return Value.Num(s.scalar_length().to_float())
		if name == "UPPER": return Value.Text(s.map_chars(fn c: if c >= "a" and c <= "z": c.upper() else: c))
		if name == "LOWER": return Value.Text(s.map_chars(fn c: if c >= "A" and c <= "Z": c.lower() else: c))
		return Value.Text(s.fields().join(" "))
	if name == "LEFT" or name == "RIGHT":
		if n != 1 and n != 2: return bad
		v := scalar_str(sh, nodes, args[0])
		if is_err(v): return v
		var k = 1
		if n == 2:
			x := scalar_num(sh, nodes, args[1])
			if is_err(x): return x
			fl := floor(numf(x))
			if fl < 0.0: return bad
			k = f2i(fl)
		cs := strf(v).chars()
		l := cs.length()
		if k > l: k = l
		if name == "LEFT": return Value.Text(chars_slice(cs, 0, k))
		return Value.Text(chars_slice(cs, l - k, l))
	if name == "MID":
		if n != 3: return bad
		v := scalar_str(sh, nodes, args[0])
		if is_err(v): return v
		a := scalar_num(sh, nodes, args[1])
		if is_err(a): return a
		b := scalar_num(sh, nodes, args[2])
		if is_err(b): return b
		st := floor(numf(a))
		ln := floor(numf(b))
		if st < 1.0 or ln < 0.0: return bad
		cs := strf(v).chars()
		s0 := f2i(st) - 1
		return Value.Text(chars_slice(cs, s0, s0 + f2i(ln)))
	if name == "CONCAT":
		if n < 1: return bad
		items := node_items(sh, nodes, args)
		var out = ""
		for it in items:
			if is_err(it.v): return cv(it.v)
			out = out + sform(it.v)
		return Value.Text(out)
	if name == "SUBSTITUTE":
		if n != 3: return bad
		a := scalar_str(sh, nodes, args[0])
		if is_err(a): return a
		b := scalar_str(sh, nodes, args[1])
		if is_err(b): return b
		c := scalar_str(sh, nodes, args[2])
		if is_err(c): return c
		old := strf(b)
		if old == "": return a
		return Value.Text(strf(a).replace(old, strf(c)))
	if name == "VALUE":
		if n != 1: return bad
		return coerce_num(ev(sh, nodes, args[0]))
	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if n != 1: return bad
		t := tag(ev(sh, nodes, args[0]))
		if name == "ISERROR": return Value.Bool(t == 4)
		if name == "ISBLANK": return Value.Bool(t == 0)
		if name == "ISNUMBER": return Value.Bool(t == 1)
		return Value.Bool(t == 2)
	if name == "ROW" or name == "COLUMN":
		if n != 1: return bad
		a := nodes[args[0]]
		if a.kind != 3 and a.kind != 4: return bad
		if not a.valid: return Value.Err("#REF!")
		if name == "ROW": return Value.Num(a.r1.to_float())
		return Value.Num((a.c1 + 1).to_float())
	if name == "INDEX":
		if n < 2 or n > 3: return bad
		a := nodes[args[0]]
		if a.kind != 4: return bad
		if not a.valid: return Value.Err("#REF!")
		x := scalar_num(sh, nodes, args[1])
		if is_err(x): return x
		var y = Value.Num(1.0)
		if n == 3:
			y = scalar_num(sh, nodes, args[2])
			if is_err(y): return y
		r1 := min_i(a.r1, a.r2)
		r2 := max_i(a.r1, a.r2)
		c1 := min_i(a.c1, a.c2)
		c2 := max_i(a.c1, a.c2)
		var ri = f2i(floor(numf(x)))
		var ci = 1
		if n == 3:
			ci = f2i(floor(numf(y)))
		else if r1 == r2:
			ci = ri
			ri = 1
		if ri < 1 or ci < 1 or ri > r2 - r1 + 1 or ci > c2 - c1 + 1: return Value.Err("#REF!")
		return cell_val(sh, c1 + ci - 1, r1 + ri - 1)
	if name == "COUNTIF":
		if n != 2: return bad
		a := nodes[args[0]]
		if a.kind != 4: return bad
		if not a.valid: return Value.Err("#REF!")
		crit := ev(sh, nodes, args[1])
		if is_err(crit): return crit
		var op = "="
		var operand = cv(crit)
		if tag(crit) == 2:
			s := strf(crit)
			for o in [">=", "<=", "<>", ">", "<", "="]:
				if s.starts_with(o):
					op = o
					break
			rest := sub(s, op.length(), s.length())
			if s.starts_with(op):
				if nn := parse_num_text(rest):
					operand = Value.Num(nn)
				else:
					operand = Value.Text(rest)
			else:
				if nn := parse_num_text(s):
					operand = Value.Num(nn)
		var cnt = 0
		for r in min_i(a.r1, a.r2)..max_i(a.r1, a.r2) + 1:
			for c in min_i(a.c1, a.c2)..max_i(a.c1, a.c2) + 1:
				cell := cell_val(sh, c, r)
				if tag(cell) == tag(operand):
					k := cmp_vals(cell, operand)
					var hit = false
					if op == "=": hit = k == 0
					else if op == "<>": hit = k != 0
					else if op == "<": hit = k < 0
					else if op == "<=": hit = k <= 0
					else if op == ">": hit = k > 0
					else: hit = k >= 0
					if hit: cnt += 1
				else:
					if op == "<>" and tag(cell) != 0: cnt += 1
		return Value.Num(cnt.to_float())
	return Value.Err("#NAME?")

// ---------- commands ----------
fn parse_cell(t: String) Int:
	cs := t.chars()
	if cs.length() < 2 or cs.length() > 4: return -1
	if not is_letter(cs[0]): return -1
	var digits = ""
	for i in 1..cs.length():
		if not is_digit(cs[i]): return -1
		digits = digits + cs[i]
	if digits.starts_with("0"): return -1
	row := digits.parse_int().get(0)
	if row < 1 or row > 999: return -1
	col := cs[0].upper().scalar_at(0) - 65
	return row * 26 + col

type Rect:
	ok: Bool = false
	c1: Int = 0
	r1: Int = 0
	c2: Int = 0
	r2: Int = 0

fn parse_range(t: String) Rect:
	parts := t.split(":")
	if parts.length() < 1 or parts.length() > 2: return Rect()
	a := parse_cell(parts[0])
	if a < 0: return Rect()
	var b = a
	if parts.length() == 2:
		b = parse_cell(parts[1])
		if b < 0: return Rect()
	return Rect(ok: true, c1: min_i(a % 26, b % 26), r1: min_i(a / 26, b / 26), c2: max_i(a % 26, b % 26), r2: max_i(a / 26, b / 26))

fn csv_field(s: String) String:
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r") or s.starts_with(" ") or s.ends_with(" "):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s.clone()

fn shift_ref(r: RefScan, dc: Int, dr: Int) String:
	// returns "" if out of grid
	nc := if r.ac: r.col else: r.col + dc
	nr := if r.ar: r.row else: r.row + dr
	if nc < 0 or nc > 25 or nr < 1 or nr > 999: return ""
	return ref_text(r, nc, nr)

fn shift_formula(src: String, dc: Int, dr: Int) String:
	cs := src.chars()
	lr := lex(cs)
	if not lr.ok: return src.clone()
	var out = ""
	var pos = 0
	for t in lr.toks:
		if t.kind != 2 and t.kind != 3: continue
		if not t.valid: continue
		out = out + chars_slice(cs, pos, t.start)
		pos = t.end
		if t.kind == 2:
			s := shift_ref(t.a, dc, dr)
			out = out + (if s == "": "#REF!" else: s)
		else:
			s1 := shift_ref(t.a, dc, dr)
			s2 := shift_ref(t.b, dc, dr)
			if s1 == "" or s2 == "": out = out + "#REF!"
			else: out = out + s1 + ":" + s2
	out = out + chars_slice(cs, pos, cs.length())
	return out

fn parse_csv(text: String) List[List[String]]:
	var records = List[List[String]]()
	var fields = List[String]()
	var cur = ""
	var inq = false
	var content = false
	cs := text.chars()
	var i = 0
	while i < cs.length():
		c := cs[i]
		if inq:
			if c == "\"":
				if i + 1 < cs.length() and cs[i + 1] == "\"":
					cur = cur + "\""
					i += 1
				else:
					inq = false
			else:
				cur = cur + c
		else:
			if c == "\"":
				inq = true
				content = true
			else if c == ",":
				fields.append(cur)
				cur = ""
				content = true
			else if c == "\n":
				if content:
					fields.append(cur)
					records.append(fields)
				fields = List[String]()
				cur = ""
				content = false
			else if c == "\r":
				i += 0
			else:
				cur = cur + c
				content = true
		i += 1
	if content:
		fields.append(cur)
		records.append(fields)
	return records

fn Sheet.cell_display(idx: Int) String:
	return sform(self.vals[idx])

fn var Sheet.run_set(idx: Int, text: String, var out: List[String]) Unit:
	self.assign(idx, text)
	n := self.recalc([idx])
	out.append("recalc {n}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	lines := text.split("\n")
	var sh = new_sheet()
	var out = List[String]()
	var li = 0
	while li < lines.length():
		line := lines[li].clone()
		li += 1
		tr := line.trim()
		if tr == "" or tr.starts_with("#"): continue
		out.append("> " + line.trim_end())
		fl := tr.fields()
		cmd := fl[0].clone()
		args := sub_list(fl, 1)
		na := args.length()
		if cmd == "set":
			if na == 0:
				out.append("error: usage: set CELL VALUE")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			s1 := sub(tr, cmd.length(), tr.length()).trim_start()
			rest := sub(s1, args[0].length(), s1.length()).trim()
			sh.run_set(idx, rest, var out)
		else if cmd == "clear":
			if na != 1:
				out.append("error: usage: clear CELL")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			sh.run_set(idx, "", var out)
		else if cmd == "get" or cmd == "show":
			if na != 1:
				out.append("error: usage: {cmd} CELL")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			k := sh.kinds[idx]
			name := idx_name(idx)
			if cmd == "get":
				out.append(if k == 0: "(empty)" else: sh.cell_display(idx))
			else:
				if k == 0: out.append("{name}: (empty)")
				else if k == 1: out.append("{name}: {sh.raws[idx]}")
				else: out.append("{name}: {sh.raws[idx]} => {sh.cell_display(idx)}")
		else if cmd == "precedents" or cmd == "dependents":
			if na != 1:
				out.append("error: usage: {cmd} CELL")
				continue
			idx := parse_cell(args[0])
			if idx < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			var res = List[Int]()
			if cmd == "precedents":
				if f := sh.formulas.get(idx):
					res = f.prec.clone()
			else:
				var seen = Set[Int]()
				var st = [idx]
				while st.length() > 0:
					x := st.pop().get(0)
					if lst := sh.deps.get(x):
						for d in lst:
							if not seen.contains(d):
								seen.add(d)
								st.append(d)
				res = seen.values()
				res.sort()
			if res.length() == 0:
				out.append("(none)")
			else:
				out.append(res.map(fn i: idx_name(i)).join(" "))
		else if cmd == "copy":
			if na != 2:
				out.append("error: usage: copy SRC DST")
				continue
			src := parse_cell(args[0])
			if src < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			rg := parse_range(args[1])
			if not rg.ok:
				out.append("error: bad range '{args[1]}'")
				continue
			k := sh.kinds[src]
			raw := sh.raws[src].clone()
			var changed = List[Int]()
			for r in rg.r1..rg.r2 + 1:
				for c in rg.c1..rg.c2 + 1:
					d := r * 26 + c
					if k == 2:
						sh.assign(d, "=" + shift_formula(sub(raw, 1, raw.length()), c - src % 26, r - src / 26))
					else:
						sh.assign(d, raw)
					changed.append(d)
			n := sh.recalc(changed)
			out.append("recalc {n}")
		else if cmd == "stats":
			var cells = 0
			var forms = 0
			for k in sh.kinds:
				if k != 0: cells += 1
				if k == 2: forms += 1
			out.append("cells {cells} formulas {forms} evals {sh.evals}")
		else if cmd == "print" or cmd == "export":
			var mode = ""
			var modes = 0
			var rangeArg = ""
			var nr = 0
			for a in args:
				if a == "formulas" or a == "values":
					modes += 1
					mode = a.clone()
				else:
					nr += 1
					rangeArg = a.clone()
			if modes > 1 or nr > 1 or (cmd == "print" and modes > 0):
				out.append(if cmd == "print": "error: usage: print [RANGE]" else: "error: usage: export [formulas] [RANGE]")
				continue
			var rg = Rect()
			if nr == 1:
				rg = parse_range(rangeArg)
				if not rg.ok:
					out.append("error: bad range '{rangeArg}'")
					continue
			else:
				var mc = -1
				var mr = 0
				for i in 0..26 * 1000:
					if sh.kinds[i] != 0:
						mc = max_i(mc, i % 26)
						mr = max_i(mr, i / 26)
				if mc < 0:
					out.append("(empty sheet)")
					continue
				rg = Rect(ok: true, c1: 0, r1: 1, c2: mc, r2: mr)
			for r in rg.r1..rg.r2 + 1:
				var row = List[String]()
				for c in rg.c1..rg.c2 + 1:
					i := r * 26 + c
					if cmd == "print":
						row.append(sh.cell_display(i))
					else:
						if mode == "formulas": row.append(csv_field(sh.raws[i]))
						else: row.append(csv_field(sh.cell_display(i)))
				out.append(row.join(if cmd == "print": " | " else: ","))
		else if cmd == "import":
			var block = List[String]()
			while li < lines.length():
				bl := lines[li].clone()
				li += 1
				if bl == ".": break
				block.append(bl)
			if na != 1:
				out.append("error: usage: import CELL")
				continue
			start := parse_cell(args[0])
			if start < 0:
				out.append("error: bad cell reference '{args[0]}'")
				continue
			recs := parse_csv(block.join("\n"))
			var maxc = 0
			for rec in recs: maxc = max_i(maxc, rec.length())
			if start % 26 + maxc > 26 or start / 26 + recs.length() - 1 > 999:
				out.append("error: import out of range")
				continue
			var changed = List[Int]()
			for ri in 0..recs.length():
				for ci in 0..recs[ri].length():
					d := (start / 26 + ri) * 26 + start % 26 + ci
					sh.assign(d, recs[ri][ci].trim())
					changed.append(d)
			n := sh.recalc(changed)
			out.append("imported {recs.length()} rows, {maxc} columns; recalc {n}")
		else:
			out.append("error: unknown command '{cmd}'")
	print(out.join("\n"))

fn sub_list(xs: List[String], from: Int) List[String]:
	var out = List[String]()
	for i in from..xs.length():
		out.append(xs[i].clone())
	return out

fn big_inf() Float:
	var h = 1e308
	return h * 10.0
