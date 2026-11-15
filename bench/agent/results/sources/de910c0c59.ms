import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder, Bytes from "@std/bytes.ms"

K_LIT := 0
K_COL := 1
K_NEG := 2
K_NOT := 3
K_ARITH := 4
K_CMP := 5
K_AND := 6
K_OR := 7
K_ISNULL := 8
K_LIKE := 9
K_IN := 10
K_BETWEEN := 11
K_CALL := 12

enum Value:
	Null
	I(n: Int)
	T(s: String)
	B(b: Bool)

type Token:
	kind: Int
	text: String
	n: Int = 0

type Node:
	kind: Int = 0
	op: String = ""
	s: String = ""
	q: String = ""
	hasq: Bool = false
	a: Int = -1
	b: Int = -1
	c: Int = -1
	args: List[Int] = []
	flag: Bool = false
	star: Bool = false
	v: Value = Value.Null

type ColDef:
	name: String
	is_int: Bool
	notnull: Bool = false
	pk: Bool = false

type SelItem:
	star: Bool = false
	qual: String = ""
	hasq: Bool = false
	expr: Int = -1
	alias: String = ""
	hasalias: Bool = false

type TRef:
	table: String
	alias: String

type JoinC:
	left: Bool
	tref: TRef
	on: Int

type OrderItem:
	expr: Int
	desc: Bool

type Stmt:
	kind: Int
	table: String = ""
	cols: List[ColDef] = []
	names: List[String] = []
	has_names: Bool = false
	rows: List[List[Int]] = []
	exprs: List[Int] = []
	cond: Int = -1
	distinct: Bool = false
	items: List[SelItem] = []
	froms: List[TRef] = []
	joins: List[JoinC] = []
	group: List[Int] = []
	having: Int = -1
	order: List[OrderItem] = []
	limit: Int = -1
	offset: Int = 0

type Table:
	name: String
	cols: List[ColDef]
	rows: List[List[Value]] = []

type ColInfo:
	alias: String
	name: String

type OutCol:
	name: String
	expr: Int = -1
	col: Int = -1

fn syn() Error: Error("syntax error")

fn terr() Error: Error("type error")

// ---------- values ----------

fn kind_of(v: Value) Int:
	match v:
		Null: return 0
		I(_n): return 1
		T(_s): return 2
		B(_b): return 3

fn vint(v: Value) Int:
	match v:
		I(n): return n
		_: return 0

fn vtext(v: Value) String:
	match v:
		T(s): return s.clone()
		_: return ""

fn vbool(v: Value) Bool:
	match v:
		B(b): return b
		_: return false

fn vshow(v: Value) String:
	match v:
		Null: return "NULL"
		I(n): return "{n}"
		T(s): return s.clone()
		B(b): return if b: "true" else: "false"

fn vkey(v: Value) String:
	match v:
		Null: return "N;"
		I(n): return "I{n};"
		T(s): return "T{s.length()}:{s};"
		B(b): return if b: "B1;" else: "B0;"

fn vorder(a: Value, b: Value) Int:
	ka := kind_of(a)
	kb := kind_of(b)
	if ka != kb:
		if ka < kb: return -1
		return 1
	if ka == 1:
		x := vint(a)
		y := vint(b)
		if x < y: return -1
		if x > y: return 1
		return 0
	if ka == 2:
		return vtext(a).compare(vtext(b))
	if ka == 3:
		x := vbool(a)
		y := vbool(b)
		if x == y: return 0
		if not x: return -1
		return 1
	return 0

fn compare_op(op: String, a: Value, b: Value) Value!:
	ka := kind_of(a)
	kb := kind_of(b)
	if ka == 0 or kb == 0: return ok(Value.Null)
	if ka != kb or ka == 3: return error(terr())
	c := vorder(a, b)
	r := if op == "=": c == 0 else if op == "<>": c != 0 else if op == "<": c < 0 else if op == "<=": c <= 0 else if op == ">": c > 0 else: c >= 0
	return ok(Value.B(r))

fn and3(a: Value, b: Value) Value:
	ka := kind_of(a)
	kb := kind_of(b)
	if ka == 3 and not vbool(a): return Value.B(false)
	if kb == 3 and not vbool(b): return Value.B(false)
	if ka == 0 or kb == 0: return Value.Null
	return Value.B(true)

fn like_match(s: Bytes, p: Bytes) Bool:
	sl := s.length()
	pl := p.length()
	var si = 0
	var pi = 0
	var star = -1
	var mark = 0
	while si < sl:
		if pi < pl and p.get(pi).to_int() == 37:
			star = pi
			mark = si
			pi += 1
		else if pi < pl and (p.get(pi).to_int() == 95 or p.get(pi).to_int() == s.get(si).to_int()):
			si += 1
			pi += 1
		else if star >= 0:
			pi = star + 1
			mark += 1
			si = mark
		else:
			return false
	while pi < pl and p.get(pi).to_int() == 37:
		pi += 1
	return pi == pl

fn ascii_case(s: String, up: Bool) String:
	b := s.to_bytes()
	var bb = BytesBuilder()
	for i in 0..b.length():
		ch := b.get(i)
		c := ch.to_int()
		if up and c >= 97 and c <= 122:
			bb.append((c - 32).to_uint8().get(ch))
		else if not up and c >= 65 and c <= 90:
			bb.append((c + 32).to_uint8().get(ch))
		else:
			bb.append(ch)
	return bb.build().decode_utf8().get("")

// ---------- lexer ----------

fn is_alpha(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn keywords() Set[String]:
	var s = Set[String]()
	words := "SELECT FROM WHERE GROUP BY HAVING ORDER LIMIT OFFSET JOIN LEFT INNER ON AS AND OR NOT NULL IS LIKE IN BETWEEN INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY DISTINCT ASC DESC".split(" ")
	for w in words:
		s.add(w.clone())
	return s

fn split_statements(src: String) List[String]:
	b := src.to_bytes()
	n := b.length()
	var out = List[String]()
	var start = 0
	var i = 0
	while i < n:
		c := b.get(i).to_int()
		if c == 39:
			i += 1
			while i < n and b.get(i).to_int() != 39:
				i += 1
			i += 1
		else if c == 45 and i + 1 < n and b.get(i + 1).to_int() == 45:
			while i < n and b.get(i).to_int() != 10:
				i += 1
		else if c == 59:
			out.append(b.decode_utf8_range(start, i).get(""))
			i += 1
			start = i
		else:
			i += 1
	if start < n:
		out.append(b.decode_utf8_range(start, n).get(""))
	return out

fn lex(src: String) List[Token]!:
	b := src.to_bytes()
	n := b.length()
	kws := keywords()
	var out = List[Token]()
	var i = 0
	while i < n:
		c := b.get(i).to_int()
		if c == 32 or c == 9 or c == 13 or c == 10:
			i += 1
			continue
		if c == 45 and i + 1 < n and b.get(i + 1).to_int() == 45:
			while i < n and b.get(i).to_int() != 10:
				i += 1
			continue
		if is_alpha(c):
			var e = i
			while e < n and (is_alpha(b.get(e).to_int()) or is_digit(b.get(e).to_int())):
				e += 1
			text := b.decode_utf8_range(i, e).get("")
			up := text.upper()
			if kws.contains(up):
				out.append(Token(3, up))
			else:
				out.append(Token(2, text))
			i = e
			continue
		if is_digit(c):
			var e = i
			while e < n and is_digit(b.get(e).to_int()):
				e += 1
			text := b.decode_utf8_range(i, e).get("")
			if v := text.parse_int():
				out.append(Token(0, text, v))
			else:
				return error(syn())
			i = e
			continue
		if c == 39:
			var bb = BytesBuilder()
			var k = i + 1
			var closed = false
			while k < n:
				ch := b.get(k)
				if ch.to_int() == 39:
					if k + 1 < n and b.get(k + 1).to_int() == 39:
						bb.append(ch)
						k += 2
						continue
					closed = true
					k += 1
					break
				bb.append(ch)
				k += 1
			if not closed:
				return error(syn())
			out.append(Token(1, bb.build().decode_utf8().get("")))
			i = k
			continue
		nc := if i + 1 < n: b.get(i + 1).to_int() else: 0
		if (c == 60 and (nc == 61 or nc == 62)) or (c == 62 and nc == 61) or (c == 33 and nc == 61) or (c == 124 and nc == 124):
			text := b.decode_utf8_range(i, i + 2).get("")
			if text == "!=":
				out.append(Token(4, "<>"))
			else:
				out.append(Token(4, text))
			i += 2
			continue
		if c == 61 or c == 60 or c == 62 or c == 43 or c == 45 or c == 42 or c == 47 or c == 37 or c == 40 or c == 41 or c == 44 or c == 46:
			out.append(Token(4, b.decode_utf8_range(i, i + 1).get("")))
			i += 1
			continue
		return error(syn())
	out.append(Token(5, ""))
	return ok(out)

// ---------- parser ----------

type Parser:
	toks: List[Token]
	pos: Int = 0
	nodes: List[Node] = []

fn Parser.kind_at(off: Int) Int:
	p := self.pos + off
	if p >= self.toks.length(): return 5
	return self.toks[p].kind

fn Parser.text_at(off: Int) String:
	p := self.pos + off
	if p >= self.toks.length(): return ""
	return self.toks[p].text.clone()

fn Parser.at_kw(kw: String) Bool:
	return self.kind_at(0) == 3 and self.toks[self.pos].text == kw

fn Parser.at_op(op: String) Bool:
	return self.kind_at(0) == 4 and self.toks[self.pos].text == op

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.accept_kw(kw: String) Bool:
	if self.at_kw(kw):
		self.pos += 1
		return true
	return false

fn var Parser.accept_op(op: String) Bool:
	if self.at_op(op):
		self.pos += 1
		return true
	return false

fn var Parser.expect_kw(kw: String) Unit!:
	if self.at_kw(kw):
		self.pos += 1
		return ok(unit)
	return error(syn())

fn var Parser.expect_op(op: String) Unit!:
	if self.at_op(op):
		self.pos += 1
		return ok(unit)
	return error(syn())

fn var Parser.expect_ident() String!:
	if self.kind_at(0) == 2:
		t := self.toks[self.pos].text.clone()
		self.pos += 1
		return ok(t)
	return error(syn())

fn var Parser.parse_or() Int!:
	var l = self.parse_and()?
	while self.at_kw("OR"):
		self.pos += 1
		r := self.parse_and()?
		l = self.add(Node(kind: K_OR, a: l, b: r))
	return ok(l)

fn var Parser.parse_and() Int!:
	var l = self.parse_not()?
	while self.at_kw("AND"):
		self.pos += 1
		r := self.parse_not()?
		l = self.add(Node(kind: K_AND, a: l, b: r))
	return ok(l)

fn var Parser.parse_not() Int!:
	if self.at_kw("NOT"):
		self.pos += 1
		e := self.parse_not()?
		return ok(self.add(Node(kind: K_NOT, a: e)))
	return self.parse_cmp()

fn var Parser.parse_cmp() Int!:
	l := self.parse_add()?
	if self.kind_at(0) == 4:
		op := self.text_at(0)
		if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
			self.pos += 1
			r := self.parse_add()?
			return ok(self.add(Node(kind: K_CMP, op: op, a: l, b: r)))
		return ok(l)
	if self.at_kw("IS"):
		self.pos += 1
		neg := self.accept_kw("NOT")
		self.expect_kw("NULL")?
		return ok(self.add(Node(kind: K_ISNULL, a: l, flag: neg)))
	var neg = false
	if self.at_kw("NOT"):
		neg = true
		self.pos += 1
		if not (self.at_kw("LIKE") or self.at_kw("IN") or self.at_kw("BETWEEN")):
			return error(syn())
	if self.at_kw("LIKE"):
		self.pos += 1
		r := self.parse_add()?
		return ok(self.add(Node(kind: K_LIKE, a: l, b: r, flag: neg)))
	if self.at_kw("IN"):
		self.pos += 1
		self.expect_op("(")?
		var items = List[Int]()
		items.append(self.parse_or()?)
		while self.accept_op(","):
			items.append(self.parse_or()?)
		self.expect_op(")")?
		return ok(self.add(Node(kind: K_IN, a: l, args: items, flag: neg)))
	if self.at_kw("BETWEEN"):
		self.pos += 1
		lo := self.parse_add()?
		self.expect_kw("AND")?
		hi := self.parse_add()?
		return ok(self.add(Node(kind: K_BETWEEN, a: l, b: lo, c: hi, flag: neg)))
	return ok(l)

fn var Parser.parse_add() Int!:
	var l = self.parse_mul()?
	while self.at_op("+") or self.at_op("-") or self.at_op("||"):
		op := self.text_at(0)
		self.pos += 1
		r := self.parse_mul()?
		l = self.add(Node(kind: K_ARITH, op: op, a: l, b: r))
	return ok(l)

fn var Parser.parse_mul() Int!:
	var l = self.parse_unary()?
	while self.at_op("*") or self.at_op("/") or self.at_op("%"):
		op := self.text_at(0)
		self.pos += 1
		r := self.parse_unary()?
		l = self.add(Node(kind: K_ARITH, op: op, a: l, b: r))
	return ok(l)

fn var Parser.parse_unary() Int!:
	if self.at_op("-"):
		self.pos += 1
		e := self.parse_unary()?
		return ok(self.add(Node(kind: K_NEG, a: e)))
	return self.parse_primary()

fn var Parser.parse_primary() Int!:
	k := self.kind_at(0)
	if k == 0:
		v := self.toks[self.pos].n
		self.pos += 1
		return ok(self.add(Node(kind: K_LIT, v: Value.I(v))))
	if k == 1:
		s := self.toks[self.pos].text.clone()
		self.pos += 1
		return ok(self.add(Node(kind: K_LIT, v: Value.T(s))))
	if self.at_kw("NULL"):
		self.pos += 1
		return ok(self.add(Node(kind: K_LIT)))
	if self.at_op("("):
		self.pos += 1
		e := self.parse_or()?
		self.expect_op(")")?
		return ok(e)
	if k == 2:
		name := self.text_at(0)
		self.pos += 1
		if self.at_op("("):
			self.pos += 1
			up := name.upper()
			var distinct = false
			var star = false
			var args = List[Int]()
			if self.accept_kw("DISTINCT"):
				distinct = true
			if self.at_op("*"):
				if up != "COUNT": return error(syn())
				self.pos += 1
				star = true
			else if not self.at_op(")"):
				args.append(self.parse_or()?)
				while self.accept_op(","):
					args.append(self.parse_or()?)
			self.expect_op(")")?
			return ok(self.add(Node(kind: K_CALL, s: up, args: args, flag: distinct, star: star)))
		if self.at_op("."):
			self.pos += 1
			col := self.expect_ident()?
			return ok(self.add(Node(kind: K_COL, q: name, s: col, hasq: true)))
		return ok(self.add(Node(kind: K_COL, s: name)))
	return error(syn())

fn var Parser.parse_tref() TRef!:
	name := self.expect_ident()?
	if self.accept_kw("AS"):
		al := self.expect_ident()?
		return ok(TRef(name, al))
	if self.kind_at(0) == 2:
		al := self.expect_ident()?
		return ok(TRef(name, al))
	return ok(TRef(name.clone(), name))

fn var Parser.parse_where() Int!:
	if self.accept_kw("WHERE"):
		return self.parse_or()
	return ok(-1)

fn var Parser.parse_select() Stmt!:
	var st = Stmt(kind: 5)
	st.distinct = self.accept_kw("DISTINCT")
	while true:
		var it = SelItem()
		if self.at_op("*"):
			self.pos += 1
			it.star = true
		else if self.kind_at(0) == 2 and self.kind_at(1) == 4 and self.text_at(1) == "." and self.kind_at(2) == 4 and self.text_at(2) == "*":
			it.star = true
			it.hasq = true
			it.qual = self.text_at(0)
			self.pos += 3
		else:
			it.expr = self.parse_or()?
			if self.accept_kw("AS"):
				it.alias = self.expect_ident()?
				it.hasalias = true
		st.items.append(it)
		if not self.accept_op(","): break
	if self.accept_kw("FROM"):
		st.froms.append(self.parse_tref()?)
		while self.at_kw("INNER") or self.at_kw("LEFT") or self.at_kw("JOIN"):
			var left = false
			if self.accept_kw("LEFT"):
				left = true
			else:
				self.accept_kw("INNER")
			self.expect_kw("JOIN")?
			t := self.parse_tref()?
			self.expect_kw("ON")?
			on := self.parse_or()?
			st.joins.append(JoinC(left, t, on))
	st.cond = self.parse_where()?
	if self.accept_kw("GROUP"):
		self.expect_kw("BY")?
		while true:
			st.group.append(self.parse_colref()?)
			if not self.accept_op(","): break
	if self.accept_kw("HAVING"):
		st.having = self.parse_or()?
	if self.accept_kw("ORDER"):
		self.expect_kw("BY")?
		while true:
			e := self.parse_or()?
			var desc = false
			if self.accept_kw("DESC"):
				desc = true
			else:
				self.accept_kw("ASC")
			st.order.append(OrderItem(e, desc))
			if not self.accept_op(","): break
	if self.accept_kw("LIMIT"):
		if self.kind_at(0) != 0: return error(syn())
		st.limit = self.toks[self.pos].n
		self.pos += 1
		if self.accept_kw("OFFSET"):
			if self.kind_at(0) != 0: return error(syn())
			st.offset = self.toks[self.pos].n
			self.pos += 1
	return ok(st)

fn var Parser.parse_colref() Int!:
	name := self.expect_ident()?
	if self.accept_op("."):
		col := self.expect_ident()?
		return ok(self.add(Node(kind: K_COL, q: name, s: col, hasq: true)))
	return ok(self.add(Node(kind: K_COL, s: name)))

fn var Parser.parse_stmt() Stmt!:
	if self.kind_at(0) != 3: return error(syn())
	kw := self.text_at(0)
	self.pos += 1
	var st = Stmt(kind: -1)
	if kw == "SELECT":
		st = self.parse_select()?
	else if kw == "CREATE":
		self.expect_kw("TABLE")?
		st.kind = 0
		st.table = self.expect_ident()?
		self.expect_op("(")?
		while true:
			name := self.expect_ident()?
			ty := (self.expect_ident()?).upper()
			if ty != "INT" and ty != "TEXT": return error(syn())
			var cd = ColDef(name, ty == "INT")
			while true:
				if self.accept_kw("PRIMARY"):
					self.expect_kw("KEY")?
					cd.pk = true
				else if self.accept_kw("NOT"):
					self.expect_kw("NULL")?
					cd.notnull = true
				else:
					break
			st.cols.append(cd)
			if not self.accept_op(","): break
		self.expect_op(")")?
	else if kw == "DROP":
		self.expect_kw("TABLE")?
		st.kind = 1
		st.table = self.expect_ident()?
	else if kw == "INSERT":
		self.expect_kw("INTO")?
		st.kind = 2
		st.table = self.expect_ident()?
		if self.accept_op("("):
			st.has_names = true
			while true:
				st.names.append(self.expect_ident()?)
				if not self.accept_op(","): break
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		while true:
			self.expect_op("(")?
			var row = List[Int]()
			while true:
				row.append(self.parse_or()?)
				if not self.accept_op(","): break
			self.expect_op(")")?
			st.rows.append(row)
			if not self.accept_op(","): break
	else if kw == "UPDATE":
		st.kind = 3
		st.table = self.expect_ident()?
		self.expect_kw("SET")?
		while true:
			st.names.append(self.expect_ident()?)
			self.expect_op("=")?
			st.exprs.append(self.parse_or()?)
			if not self.accept_op(","): break
		st.cond = self.parse_where()?
	else if kw == "DELETE":
		self.expect_kw("FROM")?
		st.kind = 4
		st.table = self.expect_ident()?
		st.cond = self.parse_where()?
	else:
		return error(syn())
	if self.kind_at(0) != 5: return error(syn())
	return ok(st)

// ---------- resolution ----------

fn find_col(scope: List[ColInfo], hasq: Bool, q: String, name: String) Int:
	var found = -1
	var count = 0
	for i in 0..scope.length():
		c := scope[i]
		if c.name == name and (not hasq or c.alias == q):
			if count == 0: found = i
			count += 1
	if count == 0: return -1
	if count > 1: return -2
	return found

fn col_display(n: Node) String:
	if n.hasq: return "{n.q}.{n.s}"
	return n.s.clone()

fn children(n: Node) List[Int]:
	var out = List[Int]()
	if n.a >= 0: out.append(n.a)
	if n.b >= 0: out.append(n.b)
	if n.c >= 0: out.append(n.c)
	for x in n.args:
		out.append(x)
	return out

fn is_agg_name(s: String) Bool:
	return s == "COUNT" or s == "SUM" or s == "MIN" or s == "MAX"

fn has_agg(nodes: List[Node], e: Int) Bool:
	n := nodes[e]
	if n.kind == K_CALL and is_agg_name(n.s): return true
	for c in children(n):
		if has_agg(nodes, c): return true
	return false

fn check(nodes: List[Node], e: Int, scope: List[ColInfo], allow_agg: Bool, in_agg: Bool) Unit!:
	n := nodes[e]
	if n.kind == K_LIT: return ok(unit)
	if n.kind == K_COL:
		ci := find_col(scope, n.hasq, n.q, n.s)
		if ci == -1: return error(Error("no such column: {col_display(n)}"))
		if ci == -2: return error(Error("ambiguous column: {n.s}"))
		return ok(unit)
	if n.kind == K_CALL:
		nm := n.s
		argc := n.args.length()
		isagg := is_agg_name(nm)
		if not isagg and nm != "UPPER" and nm != "LOWER" and nm != "LENGTH" and nm != "ABS" and nm != "SUBSTR" and nm != "COALESCE":
			return error(Error("no such function: {nm}"))
		var okc = false
		if isagg:
			okc = (n.star and argc == 0) or (not n.star and argc == 1)
		else if nm == "SUBSTR":
			okc = argc == 3
		else if nm == "COALESCE":
			okc = argc >= 1
		else:
			okc = argc == 1
		if not okc: return error(Error("wrong number of arguments to {nm}"))
		if isagg and (not allow_agg or in_agg): return error(Error("misuse of aggregate"))
		for a in n.args:
			check(nodes, a, scope, allow_agg, in_agg or isagg)?
		return ok(unit)
	for c in children(n):
		check(nodes, c, scope, allow_agg, in_agg)?
	return ok(unit)

fn check_group(nodes: List[Node], e: Int, scope: List[ColInfo], gcols: List[Int]) Unit!:
	n := nodes[e]
	if n.kind == K_COL:
		ci := find_col(scope, n.hasq, n.q, n.s)
		if not gcols.contains(ci): return error(Error("column {col_display(n)} must appear in GROUP BY"))
		return ok(unit)
	if n.kind == K_CALL and is_agg_name(n.s): return ok(unit)
	for c in children(n):
		check_group(nodes, c, scope, gcols)?
	return ok(unit)

// ---------- evaluation ----------

fn cond_true(v: Value) Bool!:
	k := kind_of(v)
	if k == 0: return ok(false)
	if k == 3: return ok(vbool(v))
	return error(terr())

fn eval_agg(nodes: List[Node], n: Node, scope: List[ColInfo], grows: List[List[Value]], idx: List[Int]) Value!:
	if n.star: return ok(Value.I(idx.length()))
	var vals = List[Value]()
	var seen = Set[String]()
	noidx := List[Int]()
	for i in idx:
		v := eval(nodes, n.args[0], scope, grows[i], grows, noidx, false)?
		if kind_of(v) == 0: continue
		if n.flag:
			k := vkey(v)
			if seen.contains(k): continue
			seen.add(k)
		vals.append(v)
	nm := n.s
	if nm == "COUNT": return ok(Value.I(vals.length()))
	if vals.length() == 0: return ok(Value.Null)
	if nm == "SUM":
		var total = 0
		for v in vals:
			if kind_of(v) != 1: return error(terr())
			total += vint(v)
		return ok(Value.I(total))
	k0 := kind_of(vals[0])
	if k0 == 3: return error(terr())
	var best = vals[0].clone()
	for v in vals:
		if kind_of(v) != k0: return error(terr())
		c := vorder(v, best)
		if (nm == "MIN" and c < 0) or (nm == "MAX" and c > 0):
			best = v.clone()
	return ok(best)

fn eval(nodes: List[Node], e: Int, scope: List[ColInfo], row: List[Value], grows: List[List[Value]], idx: List[Int], agg: Bool) Value!:
	n := nodes[e]
	k := n.kind
	if k == K_LIT: return ok(n.v.clone())
	if k == K_COL:
		ci := find_col(scope, n.hasq, n.q, n.s)
		if agg:
			if idx.length() == 0: return ok(Value.Null)
			return ok(grows[idx[0]][ci].clone())
		return ok(row[ci].clone())
	if k == K_NEG:
		v := eval(nodes, n.a, scope, row, grows, idx, agg)?
		kk := kind_of(v)
		if kk == 0: return ok(Value.Null)
		if kk != 1: return error(terr())
		return ok(Value.I(0 - vint(v)))
	if k == K_NOT:
		v := eval(nodes, n.a, scope, row, grows, idx, agg)?
		kk := kind_of(v)
		if kk == 0: return ok(Value.Null)
		if kk != 3: return error(terr())
		return ok(Value.B(not vbool(v)))
	if k == K_AND:
		l := eval(nodes, n.a, scope, row, grows, idx, agg)?
		lk := kind_of(l)
		if lk == 3 and not vbool(l): return ok(Value.B(false))
		if lk != 0 and lk != 3: return error(terr())
		r := eval(nodes, n.b, scope, row, grows, idx, agg)?
		rk := kind_of(r)
		if rk != 0 and rk != 3: return error(terr())
		if lk == 3: return ok(r)
		if rk == 3 and not vbool(r): return ok(Value.B(false))
		return ok(Value.Null)
	if k == K_OR:
		l := eval(nodes, n.a, scope, row, grows, idx, agg)?
		lk := kind_of(l)
		if lk == 3 and vbool(l): return ok(Value.B(true))
		if lk != 0 and lk != 3: return error(terr())
		r := eval(nodes, n.b, scope, row, grows, idx, agg)?
		rk := kind_of(r)
		if rk != 0 and rk != 3: return error(terr())
		if lk == 3: return ok(r)
		if rk == 3 and vbool(r): return ok(Value.B(true))
		return ok(Value.Null)
	if k == K_ARITH:
		l := eval(nodes, n.a, scope, row, grows, idx, agg)?
		r := eval(nodes, n.b, scope, row, grows, idx, agg)?
		lk := kind_of(l)
		rk := kind_of(r)
		if lk == 0 or rk == 0: return ok(Value.Null)
		if n.op == "||":
			if lk != 2 or rk != 2: return error(terr())
			return ok(Value.T(vtext(l) + vtext(r)))
		if lk != 1 or rk != 1: return error(terr())
		x := vint(l)
		y := vint(r)
		if n.op == "+": return ok(Value.I(x + y))
		if n.op == "-": return ok(Value.I(x - y))
		if n.op == "*": return ok(Value.I(x * y))
		if y == 0: return error(Error("division by zero"))
		if n.op == "/": return ok(Value.I(x / y))
		return ok(Value.I(x % y))
	if k == K_CMP:
		l := eval(nodes, n.a, scope, row, grows, idx, agg)?
		r := eval(nodes, n.b, scope, row, grows, idx, agg)?
		return compare_op(n.op, l, r)
	if k == K_ISNULL:
		v := eval(nodes, n.a, scope, row, grows, idx, agg)?
		isn := kind_of(v) == 0
		return ok(Value.B(if n.flag: not isn else: isn))
	if k == K_LIKE:
		l := eval(nodes, n.a, scope, row, grows, idx, agg)?
		r := eval(nodes, n.b, scope, row, grows, idx, agg)?
		lk := kind_of(l)
		rk := kind_of(r)
		if lk == 0 or rk == 0: return ok(Value.Null)
		if lk != 2 or rk != 2: return error(terr())
		m := like_match(vtext(l).to_bytes(), vtext(r).to_bytes())
		return ok(Value.B(if n.flag: not m else: m))
	if k == K_IN:
		x := eval(nodes, n.a, scope, row, grows, idx, agg)?
		var found = false
		var sawnull = false
		for a in n.args:
			it := eval(nodes, a, scope, row, grows, idx, agg)?
			c := compare_op("=", x, it)?
			ck := kind_of(c)
			if ck == 0: sawnull = true
			else if vbool(c): found = true
		if kind_of(x) == 0: return ok(Value.Null)
		if found: return ok(Value.B(not n.flag))
		if sawnull: return ok(Value.Null)
		return ok(Value.B(n.flag))
	if k == K_BETWEEN:
		x := eval(nodes, n.a, scope, row, grows, idx, agg)?
		lo := eval(nodes, n.b, scope, row, grows, idx, agg)?
		hi := eval(nodes, n.c, scope, row, grows, idx, agg)?
		ge := compare_op(">=", x, lo)?
		var res = Value.B(false)
		if kind_of(ge) == 3 and not vbool(ge):
			res = Value.B(false)
		else:
			le := compare_op("<=", x, hi)?
			res = and3(ge, le)
		if n.flag:
			if kind_of(res) == 3: return ok(Value.B(not vbool(res)))
		return ok(res)
	// call
	nm := n.s
	if is_agg_name(nm): return eval_agg(nodes, n, scope, grows, idx)
	var args = List[Value]()
	for a in n.args:
		args.append(eval(nodes, a, scope, row, grows, idx, agg)?)
	if nm == "COALESCE":
		for v in args:
			if kind_of(v) != 0: return ok(v.clone())
		return ok(Value.Null)
	for v in args:
		if kind_of(v) == 0: return ok(Value.Null)
	if nm == "UPPER" or nm == "LOWER":
		if kind_of(args[0]) != 2: return error(terr())
		return ok(Value.T(ascii_case(vtext(args[0]), nm == "UPPER")))
	if nm == "LENGTH":
		if kind_of(args[0]) != 2: return error(terr())
		return ok(Value.I(vtext(args[0]).length()))
	if nm == "ABS":
		if kind_of(args[0]) != 1: return error(terr())
		x := vint(args[0])
		return ok(Value.I(if x < 0: 0 - x else: x))
	// SUBSTR
	if kind_of(args[0]) != 2 or kind_of(args[1]) != 1 or kind_of(args[2]) != 1: return error(terr())
	bs := vtext(args[0]).to_bytes()
	start := vint(args[1])
	ln := vint(args[2])
	total := bs.length()
	if ln <= 0 or start > total: return ok(Value.T(""))
	lo := if start < 1: 1 else: start
	hi := if start + ln - 1 > total: total else: start + ln - 1
	if lo > hi: return ok(Value.T(""))
	return ok(Value.T(bs.decode_utf8_range(lo - 1, hi).get("")))

// ---------- execution ----------

fn find_table(db: List[Table], name: String) Int:
	for i in 0..db.length():
		if db[i].name == name: return i
	return -1

fn table_scope(t: Table, alias: String) List[ColInfo]:
	var out = List[ColInfo]()
	for c in t.cols:
		out.append(ColInfo(alias.clone(), c.name.clone()))
	return out

fn check_row(cols: List[ColDef], row: List[Value]) Unit!:
	for i in 0..cols.length():
		c := cols[i]
		k := kind_of(row[i])
		if k == 0:
			if c.notnull or c.pk: return error(Error("NOT NULL constraint failed: {c.name}"))
		else if (c.is_int and k != 1) or (not c.is_int and k != 2):
			return error(Error("type mismatch in column {c.name}"))
	return ok(unit)

fn check_pk(cols: List[ColDef], existing: List[List[Value]], added: List[List[Value]]) Unit!:
	var pi = -1
	for i in 0..cols.length():
		if cols[i].pk: pi = i
	if pi < 0: return ok(unit)
	var seen = Set[String]()
	for r in existing:
		seen.add(vkey(r[pi]))
	for r in added:
		k := vkey(r[pi])
		if seen.contains(k): return error(Error("duplicate primary key: {vshow(r[pi])}"))
		seen.add(k)
	return ok(unit)

fn cmp_keys(keys: List[List[Value]], descs: List[Bool], a: Int, b: Int) Int:
	for i in 0..descs.length():
		c := vorder(keys[a][i], keys[b][i])
		if c != 0:
			return if descs[i]: 0 - c else: c
	return 0

fn row_key(row: List[Value]) String:
	var s = ""
	for v in row:
		s = s + vkey(v)
	return s

fn exec_select(db: List[Table], nodes: List[Node], st: Stmt) List[String]!:
	var trefs = List[TRef]()
	for t in st.froms:
		trefs.append(t.clone())
	for j in st.joins:
		trefs.append(j.tref.clone())
	var tix = List[Int]()
	for t in trefs:
		ix := find_table(db, t.table)
		if ix < 0: return error(Error("no such table: {t.table}"))
		tix.append(ix)
	var seen = Set[String]()
	for t in trefs:
		if seen.contains(t.alias): return error(Error("duplicate alias: {t.alias}"))
		seen.add(t.alias.clone())
	var scope = List[ColInfo]()
	var jscopes = List[List[ColInfo]]()
	if trefs.length() > 0:
		for c in table_scope(db[tix[0]], trefs[0].alias):
			scope.append(c.clone())
	for ji in 0..st.joins.length():
		for c in table_scope(db[tix[ji + 1]], trefs[ji + 1].alias):
			scope.append(c.clone())
		check(nodes, st.joins[ji].on, scope, false, false)?
		jscopes.append(scope.clone())
	// stars
	var outs = List[OutCol]()
	for it in st.items:
		if it.star:
			if it.hasq:
				var any = false
				for t in trefs:
					if t.alias == it.qual: any = true
				if not any: return error(Error("no such table: {it.qual}"))
				for i in 0..scope.length():
					if scope[i].alias == it.qual:
						outs.append(OutCol(scope[i].name.clone(), -1, i))
			else:
				for i in 0..scope.length():
					outs.append(OutCol(scope[i].name.clone(), -1, i))
		else:
			outs.append(OutCol("", it.expr, -1))
	var gcols = List[Int]()
	for g in st.group:
		gn := nodes[g]
		ci := find_col(scope, gn.hasq, gn.q, gn.s)
		if ci == -1: return error(Error("no such column: {col_display(gn)}"))
		if ci == -2: return error(Error("ambiguous column: {gn.s}"))
		gcols.append(ci)
	if st.cond >= 0:
		check(nodes, st.cond, scope, false, false)?
	for it in st.items:
		if not it.star:
			check(nodes, it.expr, scope, true, false)?
	// output names for expression items
	var oi = 0
	for it in st.items:
		if it.star:
			// advance over the expanded star columns
			if it.hasq:
				for i in 0..scope.length():
					if scope[i].alias == it.qual: oi += 1
			else:
				oi += scope.length()
		else:
			if it.hasalias:
				outs[oi].name = it.alias.clone()
			else:
				en := nodes[it.expr]
				if en.kind == K_COL:
					outs[oi].name = en.s.clone()
				else:
					outs[oi].name = "?column?"
			oi += 1
	if st.having >= 0:
		check(nodes, st.having, scope, true, false)?
	var ordcol = List[Int]()
	for o in st.order:
		on := nodes[o.expr]
		var oc = -1
		if on.kind == K_LIT and kind_of(on.v) == 1:
			p := vint(on.v)
			if p < 1 or p > outs.length(): return error(Error("bad ORDER BY position"))
			oc = p - 1
		else if on.kind == K_COL and not on.hasq:
			for i in 0..outs.length():
				if oc < 0 and outs[i].name == on.s: oc = i
		if oc < 0:
			check(nodes, o.expr, scope, true, false)?
		ordcol.append(oc)
	var aggregated = gcols.length() > 0 or st.having >= 0
	for it in st.items:
		if not it.star and has_agg(nodes, it.expr): aggregated = true
	for i in 0..st.order.length():
		if ordcol[i] < 0 and has_agg(nodes, st.order[i].expr): aggregated = true
	if aggregated:
		for oc in outs:
			if oc.expr >= 0:
				check_group(nodes, oc.expr, scope, gcols)?
			else if not gcols.contains(oc.col):
				return error(Error("column {oc.name} must appear in GROUP BY"))
		if st.having >= 0:
			check_group(nodes, st.having, scope, gcols)?
		for i in 0..st.order.length():
			if ordcol[i] < 0:
				check_group(nodes, st.order[i].expr, scope, gcols)?
	// rows
	var rows = List[List[Value]]()
	if trefs.length() == 0:
		rows.append(List[Value]())
	else:
		for r in db[tix[0]].rows:
			rows.append(r.clone())
	noidx := List[Int]()
	nogrows := List[List[Value]]()
	for ji in 0..st.joins.length():
		j := st.joins[ji]
		tab := db[tix[ji + 1]]
		var nrows = List[List[Value]]()
		for r in rows:
			var matched = false
			for r2 in tab.rows:
				var comb = r.clone()
				for v in r2:
					comb.append(v.clone())
				c := eval(nodes, j.on, jscopes[ji], comb, nogrows, noidx, false)?
				if cond_true(c)?:
					matched = true
					nrows.append(comb)
			if not matched and j.left:
				var comb = r.clone()
				for _c in tab.cols:
					comb.append(Value.Null)
				nrows.append(comb)
		rows = nrows
	var kept = List[Int]()
	for ri in 0..rows.length():
		if st.cond >= 0:
			c := eval(nodes, st.cond, scope, rows[ri], nogrows, noidx, false)?
			if not cond_true(c)?: continue
		kept.append(ri)
	var outrows = List[List[Value]]()
	var srcs = List[Int]()
	var groups = List[List[Int]]()
	if aggregated:
		if gcols.length() == 0:
			groups.append(kept.clone())
		else:
			var gmap = Map[String, Int]()
			for ri in kept:
				var key = ""
				for ci in gcols:
					key = key + vkey(rows[ri][ci])
				if gi := gmap.get(key):
					groups[gi].append(ri)
				else:
					gmap[key] = groups.length()
					var ng = List[Int]()
					ng.append(ri)
					groups.append(ng)
		var keptg = List[Int]()
		for gi in 0..groups.length():
			if st.having >= 0:
				c := eval(nodes, st.having, scope, List[Value](), rows, groups[gi], true)?
				if not cond_true(c)?: continue
			keptg.append(gi)
		for gi in keptg:
			var orow = List[Value]()
			for oc in outs:
				if oc.expr >= 0:
					orow.append(eval(nodes, oc.expr, scope, List[Value](), rows, groups[gi], true)?)
				else:
					if groups[gi].length() == 0:
						orow.append(Value.Null)
					else:
						orow.append(rows[groups[gi][0]][oc.col].clone())
			outrows.append(orow)
			srcs.append(gi)
	else:
		for ri in kept:
			var orow = List[Value]()
			for oc in outs:
				if oc.expr >= 0:
					orow.append(eval(nodes, oc.expr, scope, rows[ri], nogrows, noidx, false)?)
				else:
					orow.append(rows[ri][oc.col].clone())
			outrows.append(orow)
			srcs.append(ri)
	if st.distinct:
		var dseen = Set[String]()
		var o2 = List[List[Value]]()
		var s2 = List[Int]()
		for i in 0..outrows.length():
			k := row_key(outrows[i])
			if dseen.contains(k): continue
			dseen.add(k)
			o2.append(outrows[i].clone())
			s2.append(srcs[i])
		outrows = o2
		srcs = s2
	var order = List[Int]()
	for i in 0..outrows.length():
		order.append(i)
	if st.order.length() > 0:
		var keys = List[List[Value]]()
		var descs = List[Bool]()
		for o in st.order:
			descs.append(o.desc)
		for i in 0..outrows.length():
			var kr = List[Value]()
			for oi2 in 0..st.order.length():
				if ordcol[oi2] >= 0:
					kr.append(outrows[i][ordcol[oi2]].clone())
				else if aggregated:
					kr.append(eval(nodes, st.order[oi2].expr, scope, List[Value](), rows, groups[srcs[i]], true)?)
				else:
					kr.append(eval(nodes, st.order[oi2].expr, scope, rows[srcs[i]], nogrows, noidx, false)?)
			keys.append(kr)
		order = order.sorted(fn a, b: cmp_keys(keys, descs, a, b))
	var lines = List[String]()
	var names = List[String]()
	for oc in outs:
		names.append(oc.name.clone())
	lines.append(names.join("|"))
	var emitted = 0
	var skipped = 0
	for i in order:
		if skipped < st.offset:
			skipped += 1
			continue
		if st.limit >= 0 and emitted >= st.limit: break
		var parts = List[String]()
		for v in outrows[i]:
			parts.append(vshow(v))
		lines.append(parts.join("|"))
		emitted += 1
	lines.append("({emitted} rows)")
	return ok(lines)

fn run_stmt(text: String, var db: List[Table]) List[String]!:
	toks := lex(text)?
	if toks.length() == 1: return ok(List[String]())
	var p = Parser(toks)
	st := p.parse_stmt()?
	nodes := p.nodes
	var out = List[String]()
	if st.kind == 5:
		return exec_select(db, nodes, st)
	if st.kind == 0:
		if find_table(db, st.table) >= 0: return error(Error("table {st.table} already exists"))
		var names = Set[String]()
		var pks = 0
		for c in st.cols:
			if names.contains(c.name): return error(Error("duplicate column: {c.name}"))
			names.add(c.name.clone())
			if c.pk: pks += 1
		if pks > 1: return error(Error("multiple primary keys"))
		var cols = List[ColDef]()
		for c in st.cols:
			var c2 = c.clone()
			if c2.pk: c2.notnull = true
			cols.append(c2)
		db.append(Table(st.table.clone(), cols))
		out.append("ok")
		return ok(out)
	ti := find_table(db, st.table)
	if ti < 0: return error(Error("no such table: {st.table}"))
	if st.kind == 1:
		db.remove(ti)
		out.append("ok")
		return ok(out)
	cols := db[ti].cols.clone()
	scope := table_scope(db[ti], st.table)
	noidx := List[Int]()
	nogrows := List[List[Value]]()
	if st.kind == 2:
		var map = List[Int]()
		if st.has_names:
			for nm in st.names:
				var ci = -1
				for i in 0..cols.length():
					if cols[i].name == nm: ci = i
				if ci < 0: return error(Error("no such column: {nm}"))
				if map.contains(ci): return error(Error("duplicate column: {nm}"))
				map.append(ci)
		else:
			for i in 0..cols.length():
				map.append(i)
		var added = List[List[Value]]()
		empty := List[ColInfo]()
		for r in st.rows:
			if r.length() != map.length(): return error(Error("wrong number of values"))
			for e in r:
				check(nodes, e, empty, false, false)?
			var row = List[Value]()
			for _c in cols:
				row.append(Value.Null)
			for i in 0..r.length():
				row[map[i]] = eval(nodes, r[i], empty, List[Value](), nogrows, noidx, false)?
			check_row(cols, row)?
			added.append(row)
		check_pk(cols, db[ti].rows, added)?
		n := added.length()
		for r in added:
			db[ti].rows.append(r.clone())
		out.append("inserted {n}")
		return ok(out)
	if st.kind == 3:
		var cis = List[Int]()
		for nm in st.names:
			var ci = -1
			for i in 0..cols.length():
				if cols[i].name == nm: ci = i
			if ci < 0: return error(Error("no such column: {nm}"))
			cis.append(ci)
		for e in st.exprs:
			check(nodes, e, scope, false, false)?
		if st.cond >= 0:
			check(nodes, st.cond, scope, false, false)?
		var newrows = List[List[Value]]()
		var count = 0
		for r in db[ti].rows:
			var hit = true
			if st.cond >= 0:
				c := eval(nodes, st.cond, scope, r, nogrows, noidx, false)?
				hit = cond_true(c)?
			if hit:
				var vals = List[Value]()
				for e in st.exprs:
					vals.append(eval(nodes, e, scope, r, nogrows, noidx, false)?)
				var nr = r.clone()
				for i in 0..cis.length():
					nr[cis[i]] = vals[i].clone()
				check_row(cols, nr)?
				newrows.append(nr)
				count += 1
			else:
				newrows.append(r.clone())
		check_pk(cols, List[List[Value]](), newrows)?
		db[ti].rows = newrows
		out.append("updated {count}")
		return ok(out)
	// delete
	if st.cond >= 0:
		check(nodes, st.cond, scope, false, false)?
	var newrows = List[List[Value]]()
	var count = 0
	for r in db[ti].rows:
		var hit = true
		if st.cond >= 0:
			c := eval(nodes, st.cond, scope, r, nogrows, noidx, false)?
			hit = cond_true(c)?
		if hit:
			count += 1
		else:
			newrows.append(r.clone())
	db[ti].rows = newrows
	out.append("deleted {count}")
	return ok(out)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	src := data.decode_utf8().get("")
	var db = List[Table]()
	for text in split_statements(src):
		r := run_stmt(text, var db)
		if lines := r:
			for l in lines:
				print(l)
		else:
			print("error: {r.err().message}")
	return ok(unit)
